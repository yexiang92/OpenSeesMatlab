classdef SmartAnalyze
    % SmartAnalyze manages robust OpenSees analysis retries for OpenSeesMatlab.
    %
    %   SmartAnalyze stores analysis configuration, progress information, and
    %   retry strategies for transient and displacement-control static analyses.
    %   It is intended to be accessed through OpenSeesMatlabAnalysis:
    %
    %       opsmat = OpenSeesMatlab();
    %       smartAnalyze = opsmat.anlys.smartAnalyze;
    %
    %   OpenSeesMatlabAnalysis automatically calls setOPS with the OpenSees
    %   command interface. If SmartAnalyze is used directly, call setOPS or
    %   setOps before configure, transientAnalyze, or staticAnalyze.
    %
    % Retry order
    % -----------
    %   Each failed analysis step is retried in this order:
    %
    %   1. Add convergence-test iteration limits, if tryAddTestTimes is true.
    %   2. Try alternate algorithm types, if tryAlterAlgoTypes is true.
    %   3. Try alternate convergence-test types, if tryAlterTestTypes is true.
    %   4. Loosen the test tolerance, if tryLooseTestTol is true.
    %   5. Split the current step using relaxation until minStep is reached,
    %      if tryRelaxStep is true.
    %
    %   Step relaxation is intentionally tried last because successful substeps
    %   can partially advance the OpenSees model state. Keeping it last avoids
    %   applying other whole-step retry strategies after the model has already
    %   moved through part of the requested step.
    %
    % Example
    % --------
    %       % Transient analysis with full retry strategies
    %       opsmat = OpenSeesMatlab();
    %       ops = opsmat.ops;
    %       smartAnalyze = opsmat.anlys.smartAnalyze;
    %
    %       % You need to configure constraints, numberer, and system before analysis
    %       ops.wipeAnalysis();
    %       ops.constraints('Plain');
    %       ops.numberer('RCM');
    %       ops.system('UmfPack');
    %
    %       smartAnalyze.configure(...
    %           analysis="Transient", ...
    %           testType="EnergyIncr", ...
    %           testTol=1e-10, ...
    %           testIterTimes=100, ...
    %           testPrintFlag=0, ...
    %           tryAddTestTimes=true, ...
    %           normTol=1e3, ...
    %           testIterTimesMore=[50 100], ...
    %           tryLooseTestTol=true, ...
    %           looseTestTolTo=[1e-8, 1e-6], ...
    %           tryAlterTestTypes=true, ...
    %           testTypesMore=["NormDispIncr","NormUnbalance"], ...
    %           tryAlterAlgoTypes=true, ...
    %           algoTypes=[40 10 20 30], ...
    %           tryRelaxStep=true, ...
    %           relaxation=0.5, ...
    %           minStep=1e-6, ...
    %           recordNormHistory=true, ...
    %           recordDiagnostics=false, ...
    %           debugMode=true, ...
    %           printPer=100);
    %
    %       Nsteps = 1000;
    %       dt = 0.01;
    %       smartAnalyze.setTotalSteps(Nsteps);  % set total steps for transient analysis
    %       for i = 1:Nsteps
    %           ok = smartAnalyze.transientAnalyze(dt);
    %           if ok < 0
    %               error("Transient analysis failed at step %d.", i);
    %           end
    %       end
    %
    %       % Inspect convergence history
    %       history = smartAnalyze.getNormHistory();
    %       smartAnalyze.reset();
    %
    %       %----------------------------------------
    %       % Static pushover analysis (minimal settings)
    %       nodeTag = 1;
    %       dof = 1;
    %       targets = [0; 0.5; 1.0];
    %
    %       smartAnalyze.configure(...
    %           analysis="Static", ...
    %           testType="EnergyIncr", ...
    %           testTol=1e-8, ...
    %           tryAlterAlgoTypes=true, ...
    %           algoTypes=[40 10 20], ...
    %           tryRelaxStep=true, ...
    %           minStep=1e-6, ...
    %           recordNormHistory=true, ...
    %           debugMode=false);
    %
    %       % smartAnalyze.setSensitivityAlgorithm("-computeAtEachStep");  % if sensitivity analysis is needed
    %       segs = smartAnalyze.staticStepSplit(targets, 0.1);
    %       for i = 1:numel(segs)
    %           ok = smartAnalyze.staticAnalyze(nodeTag, dof, segs(i));
    %           if ok < 0
    %               error("Static analysis failed at segment %d.", i);
    %           end
    %       end
    %       smartAnalyze.reset();

    properties (Constant)
        % Logo for printing messages
        logo = "SmartAnalyze::"
    end

    methods (Static)
        function setOPS(ops)
            % Set the OpenSees command interface used by SmartAnalyze.
            %
            %   setOPS is kept for backward compatibility. New code can use the
            %   equivalent setOps method.
            %
            % Parameters
            % ----------
            % ops : OpenSeesMatlabCmds or compatible object
            %     Object that provides the OpenSees command methods used by this
            %     class, including test, algorithm, integrator, analysis,
            %     analyze, testNorm, and sensitivityAlgorithm when sensitivity
            %     analysis is enabled.
            arguments
                ops
            end
            s = analysis.SmartAnalyze.state();
            s.ops = ops;
            analysis.SmartAnalyze.state(s);
        end

        function configure(opts)
            % Configure analysis settings and apply the initial OpenSees test and algorithm.
            %
            % Syntax
            % ------
            %     smartAnalyze.configure(Name=Value)
            %
            % Notes
            % -----
            %     setOPS or setOps must be called before configure when this class
            %     is used directly. OpenSeesMatlabAnalysis does this automatically
            %     when SmartAnalyze is accessed as opsmat.anlys.smartAnalyze.
            %
            %     configure immediately applies the selected convergence test and
            %     the first algorithm in algoTypes to the OpenSees command
            %     interface. Therefore, a valid OpenSees command interface is
            %     required even if the actual analysis step is executed later.
            %
            % Parameters
            % ----------
            %   Basic analysis settings
            %   ~~~~~~~~~~~~~~~~~~~~~~~
            %   analysis : string, optional
            %       Analysis type. Must be "Transient" or "Static". Default is "Transient".
            %   testType : string, optional
            %       OpenSees convergence test type. Default is "EnergyIncr".
            %   testTol : double, optional
            %       Convergence-test tolerance. Default is 1e-10.
            %   testIterTimes : double, optional
            %       Default maximum number of convergence-test iterations. Default is 10.
            %   testPrintFlag : double, optional
            %       OpenSees convergence-test print flag. Default is 0.
            %
            %   Convergence-test retry strategies
            %   ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
            %   tryAddTestTimes : logical, optional
            %       If true, retry failed steps with larger iteration limits from
            %       testIterTimesMore when the latest norm is less than normTol.
            %       Default is false.
            %   normTol : double, optional
            %       Maximum latest test norm that allows tryAddTestTimes retries.
            %       Default is 1e3.
            %   testIterTimesMore : double array, optional
            %       Additional convergence-test iteration limits to try. Nonfinite
            %       or nonpositive values are ignored during normalization.
            %       Default is 50.
            %   tryLooseTestTol : logical, optional
            %       If true, retry failed steps with looseTestTolTo after the other
            %       retry strategies fail. Default is false.
            %   looseTestTolTo : double or double array, optional
            %       Looser convergence-test tolerance(s) used by tryLooseTestTol.
            %       Multiple values are tried in order. Default is 100*testTol.
            %   tryAlterTestTypes : logical, optional
            %       If true, retry failed steps with alternate convergence-test
            %       types from testTypesMore. Default is false.
            %   testTypesMore : string array or cell array of char, optional
            %       Alternate convergence-test types to try when
            %       tryAlterTestTypes is true. Default is
            %       {'NormDispIncr','NormUnbalance','RelativeEnergyIncr'}.
            %
            %   Algorithm retry strategies
            %   ~~~~~~~~~~~~~~~~~~~~~~~~~~
            %   tryAlterAlgoTypes : logical, optional
            %       If true, retry failed steps with the remaining entries in
            %       algoTypes. Default is false.
            %   algoTypes : double array, optional
            %       Algorithm type codes. The first entry is applied during
            %       configure; subsequent entries are used as fallback algorithms
            %       when tryAlterAlgoTypes is true. Default is
            %       [40 10 20 30 50 60 70 90].
            %
            %       Supported values:
            %
            %       - 0: {'Linear'}
            %       - 1: {'Linear','-Initial'}
            %       - 2: {'Linear','-Secant'}
            %       - 3: {'Linear','-FactorOnce'}
            %       - 4: {'Linear','-Initial','-FactorOnce'}
            %       - 5: {'Linear','-Secant','-FactorOnce'}
            %       - 10: {'Newton'}
            %       - 11: {'Newton','-Initial'}
            %       - 12: {'Newton','-intialThenCurrent'}
            %       - 13: {'Newton','-Secant'}
            %       - 20: {'NewtonLineSearch'}
            %       - 21: {'NewtonLineSearch','-type','Bisection'}
            %       - 22: {'NewtonLineSearch','-type','Secant'}
            %       - 23: {'NewtonLineSearch','-type','RegulaFalsi'}
            %       - 24: {'NewtonLineSearch','-type','LinearInterpolated'}
            %       - 25: {'NewtonLineSearch','-type','InitialInterpolated'}
            %       - 30: {'ModifiedNewton'}
            %       - 31: {'ModifiedNewton','-initial'}
            %       - 32: {'ModifiedNewton','-secant'}
            %       - 40: {'KrylovNewton'}
            %       - 41: {'KrylovNewton','-iterate','initial'}
            %       - 42: {'KrylovNewton','-increment','initial'}
            %       - 43: {'KrylovNewton','-iterate','initial','-increment','initial'}
            %       - 44: {'KrylovNewton','-maxDim',10}
            %       - 45: {'KrylovNewton','-iterate','initial','-increment','initial','-maxDim',10}
            %       - 50: {'SecantNewton'}
            %       - 51: {'SecantNewton','-iterate','initial'}
            %       - 52: {'SecantNewton','-increment','initial'}
            %       - 53: {'SecantNewton','-iterate','initial','-increment','initial'}
            %       - 60: {'BFGS'}
            %       - 61: {'BFGS','-initial'}
            %       - 62: {'BFGS','-secant'}
            %       - 70: {'Broyden'}
            %       - 71: {'Broyden','-initial'}
            %       - 72: {'Broyden','-secant'}
            %       - 80: {'PeriodicNewton'}
            %       - 81: {'PeriodicNewton','-maxDim',10}
            %       - 90: {'ExpressNewton'}
            %       - 91: {'ExpressNewton','-InitialTangent'}
            %       - 100: user-defined algorithm; UserAlgoArgs must be provided.
            %   UserAlgoArgs : cell array, optional
            %       User-defined arguments passed to the OpenSees algorithm command
            %       when algoTypes includes 100. Default is {}.
            %
            %   Step control
            %   ~~~~~~~~~~~~
            %   initialStep : double, optional
            %       Initial analysis step stored in the configuration. transientAnalyze
            %       and staticAnalyze overwrite this value for each actual step.
            %       Default is unset.
            %   relaxation : double, optional
            %       Factor used to split a failed step during step relaxation.
            %       Default is 0.5.
            %   minStep : double, optional
            %       Minimum absolute substep allowed during step relaxation.
            %       Default is 1e-6.
            %   tryRelaxStep : logical, optional
            %       If true, enable step relaxation (substep splitting) as the
            %       final fallback strategy. Default is true.
            %
            %   Diagnostics and history
            %   ~~~~~~~~~~~~~~~~~~~~~~~
            %   recordDiagnostics : logical, optional
            %       If true, record detailed failure diagnostics (records and
            %       lastFailure). When false, only lightweight norm history is kept.
            %       Default is false.
            %   recordNormHistory : logical, optional
            %       If true, record a summary of convergence norms for each
            %       analysis attempt. Default is true.
            %
            %   Debug output
            %   ~~~~~~~~~~~~
            %   debugMode : logical, optional
            %       Whether to print retry and progress messages. Default is false.
            %   printPer : double, optional
            %       Print progress every printPer successful steps when debugMode is
            %       true. Default is 20.
            %
            % Example
            % -------
            %     % Transient analysis with full retry strategies
            %     smartAnalyze.configure(...
            %         analysis="Transient", ...
            %         testType="EnergyIncr", ...
            %         testTol=1e-10, ...
            %         testIterTimes=10, ...
            %         testPrintFlag=0, ...
            %         tryAddTestTimes=true, ...
            %         normTol=1e3, ...
            %         testIterTimesMore=[50 100], ...
            %         tryLooseTestTol=true, ...
            %         looseTestTolTo=[1e-8, 1e-6], ...
            %         tryAlterTestTypes=true, ...
            %         testTypesMore=["NormDispIncr","NormUnbalance"], ...
            %         tryAlterAlgoTypes=true, ...
            %         algoTypes=[40 10 20 30], ...
            %         tryRelaxStep=true, ...
            %         relaxation=0.5, ...
            %         minStep=1e-6, ...
            %         recordNormHistory=true, ...
            %         recordDiagnostics=false, ...
            %         debugMode=true, ...
            %         printPer=20);
            %
            %     % Static pushover analysis (minimal settings)
            %     smartAnalyze.configure(...
            %         analysis="Static", ...
            %         testType="EnergyIncr", ...
            %         testTol=1e-8, ...
            %         tryAlterAlgoTypes=true, ...
            %         algoTypes=[40 10 20], ...
            %         tryRelaxStep=true, ...
            %         minStep=1e-6, ...
            %         recordNormHistory=true, ...
            %         debugMode=false);

            arguments
                opts.analysis string {mustBeMember(opts.analysis, ["Transient","Static"])} = string(missing)
                opts.testType string = string(missing)
                opts.testTol double = NaN
                opts.testIterTimes double = NaN
                opts.testPrintFlag double = NaN
                opts.tryAddTestTimes = []
                opts.normTol double = NaN
                opts.testIterTimesMore double = NaN
                opts.tryLooseTestTol = []
                opts.looseTestTolTo double = NaN
                opts.tryAlterTestTypes = []
                opts.testTypesMore = []
                opts.recordNormHistory = []
                opts.recordDiagnostics = []
                opts.tryAlterAlgoTypes = []
                opts.algoTypes double = NaN
                opts.UserAlgoArgs cell = {}
                opts.tryRelaxStep = []
                opts.initialStep double = NaN
                opts.relaxation double = NaN
                opts.minStep double = NaN
                opts.debugMode = []
                opts.printPer double = NaN
            end

            s = analysis.SmartAnalyze.state();

            if ~ismissing(opts.analysis)
                s.cfg.analysis = char(opts.analysis);
            end
            if ~ismissing(opts.testType)
                s.cfg.testType = char(opts.testType);
            end
            if ~isnan(opts.testTol)
                s.cfg.testTol = opts.testTol;
            end
            if ~isnan(opts.testIterTimes)
                s.cfg.testIterTimes = opts.testIterTimes;
            end
            if ~isnan(opts.testPrintFlag)
                s.cfg.testPrintFlag = opts.testPrintFlag;
            end
            if ~isempty(opts.tryAddTestTimes)
                s.cfg.tryAddTestTimes = logical(opts.tryAddTestTimes);
            end
            if ~isnan(opts.normTol)
                s.cfg.normTol = opts.normTol;
            end
            if ~all(isnan(opts.testIterTimesMore))
                s.cfg.testIterTimesMore = opts.testIterTimesMore;
            end
            if ~isempty(opts.tryLooseTestTol)
                s.cfg.tryLooseTestTol = logical(opts.tryLooseTestTol);
            end
            if ~isnan(opts.looseTestTolTo)
                s.cfg.looseTestTolTo = opts.looseTestTolTo;
            end
            if ~isempty(opts.tryAlterTestTypes)
                s.cfg.tryAlterTestTypes = logical(opts.tryAlterTestTypes);
            end
            if ~isempty(opts.testTypesMore)
                if isstring(opts.testTypesMore)
                    s.cfg.testTypesMore = cellstr(opts.testTypesMore);
                elseif iscell(opts.testTypesMore)
                    s.cfg.testTypesMore = opts.testTypesMore;
                else
                    s.cfg.testTypesMore = {char(opts.testTypesMore)};
                end
            end
            if ~isempty(opts.tryRelaxStep)
                s.cfg.tryRelaxStep = logical(opts.tryRelaxStep);
            end
            if ~isempty(opts.recordNormHistory)
                s.cfg.recordNormHistory = logical(opts.recordNormHistory);
            end
            if ~isempty(opts.recordDiagnostics)
                s.cfg.recordDiagnostics = logical(opts.recordDiagnostics);
            end
            if ~isempty(opts.tryAlterAlgoTypes)
                s.cfg.tryAlterAlgoTypes = logical(opts.tryAlterAlgoTypes);
            end
            if ~all(isnan(opts.algoTypes))
                s.cfg.algoTypes = opts.algoTypes;
            end
            if ~isempty(opts.UserAlgoArgs)
                s.cfg.UserAlgoArgs = opts.UserAlgoArgs;
            end
            if ~isnan(opts.initialStep)
                s.cfg.initialStep = opts.initialStep;
            end
            if ~isnan(opts.relaxation)
                s.cfg.relaxation = opts.relaxation;
            end
            if ~isnan(opts.minStep)
                s.cfg.minStep = opts.minStep;
            end
            if ~isempty(opts.debugMode)
                s.cfg.debugMode = logical(opts.debugMode);
            end
            if ~isnan(opts.printPer)
                s.cfg.printPer = opts.printPer;
            end

            s = analysis.SmartAnalyze.normalizeState(s);
            analysis.SmartAnalyze.state(s);

            analysis.SmartAnalyze.requireOps();
            analysis.SmartAnalyze.setTest();
            analysis.SmartAnalyze.setAlgorithm(s.cfg.algoTypes(1));
        end

        function reset()
            old = analysis.SmartAnalyze.state();
            s = analysis.SmartAnalyze.defaultState();

            % keep existing ops handle/object
            s.ops = old.ops;

            % optionally keep sensitivity setting too
            s.sensitivityAlgorithm = old.sensitivityAlgorithm;

            analysis.SmartAnalyze.state(s);
        end

        function close()
            analysis.SmartAnalyze.reset();
        end

        function setSensitivityAlgorithm(algorithm)
            % Set the OpenSees sensitivity algorithm used before static analysis steps.
            %
            % Parameters
            % ----------
            % algorithm : string
            %     Sensitivity algorithm option. Must be "-computeAtEachStep" or
            %     "-computeByCommand".
            %
            % Example
            % -------
            %     smartAnalyze.setSensitivityAlgorithm("-computeAtEachStep");
            arguments
                algorithm (1,1) string {mustBeMember(algorithm, ["-computeAtEachStep","-computeByCommand"])}
            end
            s = analysis.SmartAnalyze.state();
            s.sensitivityAlgorithm = char(algorithm);
            analysis.SmartAnalyze.state(s);
        end

        function setTotalSteps(npts)
            % Set the total number of analysis steps for progress tracking.
            %
            %   This method is useful when the caller already knows the total
            %   number of expected transientAnalyze or staticAnalyze calls and
            %   does not need transientStepSplit or staticStepSplit to generate
            %   segments.
            %
            % Parameters
            % ----------
            % npts : double
            %     Total number of expected analysis steps. The value must be
            %     finite and nonnegative; it is rounded to the nearest integer.
            %
            % Example
            % -------
            %     smartAnalyze.setTotalSteps(1000);
            %     for i = 1:1000
            %         ok = smartAnalyze.transientAnalyze(0.01);
            %         if ok < 0
            %             error("Transient analysis failed at step %d.", i);
            %         end
            %     end
            arguments
                npts (1,1) double {mustBeNonnegative, mustBeFinite}
            end
            npts = round(npts);
            s = analysis.SmartAnalyze.state();
            s.progress.npts = npts;
            s.progress.done = 0;
            s.progress.counter = 0;
            s.progress.tic = tic;
            analysis.SmartAnalyze.state(s);
        end

        function segs = transientStepSplit(npts)
            % Split a transient analysis into step indices for progress tracking.
            %
            %   This method does not change the OpenSees time step. It records the
            %   expected number of transientAnalyze calls and returns 1:npts so it
            %   can be used directly in a loop.
            %
            % Parameters
            % ----------
            % npts : double
            %     Number of transient analysis steps. The value must be finite and
            %     nonnegative; it is rounded to the nearest integer.
            %
            % Returns
            % -------
            % segs : double array
            %     Row vector 1:npts. Each entry represents one call to
            %     transientAnalyze.
            %
            % Example
            % -------
            %     dt = 0.01;
            %     segs = smartAnalyze.transientStepSplit(1000);
            %     for i = 1:numel(segs)
            %         ok = smartAnalyze.transientAnalyze(dt);
            %         if ok < 0
            %             error("Transient analysis failed at step %d.", i);
            %         end
            %     end
            arguments
                npts (1,1) double {mustBeNonnegative, mustBeFinite}
            end
            npts = round(npts);
            analysis.SmartAnalyze.setTotalSteps(npts);
            segs = 1:npts;
        end

        function segs = staticStepSplit(targets, maxStep)
            % Split displacement-control target values into bounded static steps.
            %
            %   targets defines one or more target displacement values. When a
            %   scalar target is provided, it is treated as [0; target]. Consecutive
            %   duplicate targets are ignored within the class tolerance.
            %
            % Parameters
            % ----------
            % targets : double array
            %     Column vector of target displacement values. If scalar, it is
            %     expanded to [0; targets].
            % maxStep : double, optional
            %     Maximum absolute displacement increment for a generated segment.
            %     If omitted or NaN, the absolute difference between the first two
            %     targets is used. The value is converted to abs(maxStep).
            %
            % Returns
            % -------
            % segs : double array
            %     Column vector of displacement increments. The sum of all segments
            %     equals targets(end) - targets(1), excluding zero-length intervals,
            %     and each generated segment has abs(seg) <= maxStep.
            %
            % Example
            % -------
            %     targets = [0; 0.5; 1.0];
            %     maxStep = 0.1;
            %     segs = smartAnalyze.staticStepSplit(targets, maxStep);
            %     for i = 1:numel(segs)
            %         ok = smartAnalyze.staticAnalyze(nodeTag, dof, segs(i));
            %         if ok < 0
            %             error("Static analysis failed at segment %d.", i);
            %         end
            %     end
            arguments
                targets (:,1) double
                maxStep (1,1) double {mustBeFinite} = NaN
            end

            s = analysis.SmartAnalyze.state();

            if isempty(targets)
                error('SmartAnalyze:InvalidInput', 'targets must not be empty.');
            end
            if isscalar(targets)
                targets = [0.0; targets];
            end

            if isnan(maxStep)
                maxStep = abs(targets(2) - targets(1));
            else
                maxStep = abs(maxStep);
            end
            if maxStep <= s.eps
                error('SmartAnalyze:InvalidInput', 'maxStep must be positive.');
            end

            d = diff(targets);
            d = d(abs(d) > s.eps);

            if isempty(d)
                segs = zeros(0,1);
                analysis.SmartAnalyze.setTotalSteps(0);
                return;
            end

            nFull = floor(abs(d) ./ maxStep);
            rems  = abs(d) - nFull .* maxStep;
            signs = sign(d);

            n = sum(nFull) + sum(rems > s.eps);
            segs = zeros(n,1);

            k = 1;
            for i = 1:numel(d)
                if nFull(i) > 0
                    segs(k:k+nFull(i)-1) = signs(i) * maxStep;
                    k = k + nFull(i);
                end
                if rems(i) > s.eps
                    segs(k) = signs(i) * rems(i);
                    k = k + 1;
                end
            end

            analysis.SmartAnalyze.setTotalSteps(numel(segs));
        end

        function ok = transientAnalyze(dt)
            % Run one transient analysis step with automatic retry strategies.
            %
            % Requirements
            % ------------
            %     configure must have been called with analysis="Transient", and
            %     setOPS or setOps must have supplied a valid OpenSees command
            %     interface.
            %
            % Parameters
            % ----------
            % dt : double
            %     Time-step size passed to ops.analyze(1, dt). Must be finite and
            %     real.
            %
            % Returns
            % -------
            % ok : double
            %     0 if the step succeeds. A negative value means the original step
            %     and all enabled retry strategies failed.
            %
            % Example
            % -------
            %     smartAnalyze.configure(analysis="Transient", initialStep=0.01);
            %     ok = smartAnalyze.transientAnalyze(0.01);
            arguments
                dt (1,1) double {mustBeFinite, mustBeReal}
            end

            s = analysis.SmartAnalyze.requireOps();
            if s.analysis ~= "Transient"
                error('SmartAnalyze:InvalidState', ...
                    'Current analysis type is not Transient.');
            end

            s.cfg.initialStep = dt;
            analysis.SmartAnalyze.state(s);

            s.ops.analysis(char(s.analysis));
            ok = analysis.SmartAnalyze.runAnalysis();
        end

        function ok = staticAnalyze(nodeTag, dof, seg)
            % Run one displacement-control static analysis step with retries.
            %
            % Requirements
            % ------------
            %     configure must have been called with analysis="Static", and
            %     setOPS or setOps must have supplied a valid OpenSees command
            %     interface.
            %
            % Parameters
            % ----------
            % nodeTag : double
            %     Node tag used by the OpenSees DisplacementControl integrator.
            %     Must be a positive integer.
            % dof : double
            %     Degree of freedom used by the OpenSees DisplacementControl
            %     integrator. Must be a positive integer.
            % seg : double
            %     Displacement increment for this segment. Must be finite and real.
            %
            % Returns
            % -------
            % ok : double
            %     0 if the segment succeeds. A negative value means the original
            %     segment and all enabled retry strategies failed.
            %
            % Example
            % -------
            %     nodeTag = 1;
            %     dof = 1;
            %     seg = 0.1;
            %     smartAnalyze.configure(analysis="Static", initialStep=seg);
            %     ok = smartAnalyze.staticAnalyze(nodeTag, dof, seg);
            arguments
                nodeTag (1,1) double {mustBeInteger, mustBePositive}
                dof     (1,1) double {mustBeInteger, mustBePositive}
                seg     (1,1) double {mustBeFinite, mustBeReal}
            end

            s = analysis.SmartAnalyze.requireOps();
            if s.analysis ~= "Static"
                error('SmartAnalyze:InvalidState', ...
                    'Current analysis type is not Static.');
            end

            s.cfg.initialStep = seg;
            s.progress.node = nodeTag;
            s.progress.dof  = dof;
            s.progress.step = seg;
            analysis.SmartAnalyze.state(s);

            s.ops.integrator("DisplacementControl", nodeTag, dof, seg);
            s.ops.analysis(char(s.analysis));
            analysis.SmartAnalyze.runSensitivity();

            ok = analysis.SmartAnalyze.runAnalysis();
        end

        function s = getState()
            % Get the current internal state of SmartAnalyze.
            %
            %   This is mainly intended for debugging and advanced workflows. The
            %   returned structure includes the OpenSees command interface, current
            %   analysis type, configuration, and progress counters.
            %
            % Returns
            % -------
            % s : struct
            %     Current internal SmartAnalyze state.
            %
            % Example
            % -------
            %     s = smartAnalyze.getState();
            %     disp(s.cfg);

            s = analysis.SmartAnalyze.state();
        end

        function diagnostics = getDiagnostics()
            % Get SmartAnalyze retry and convergence diagnostics. You
            % can use this to inspect the diagnostic records collected
            % during analyze attempts. You need to enable diagnostic
            % recording in the configuration before using this function.
            %
            % Returns
            % -------
            % diagnostics : struct
            %     Diagnostic records collected during analyze attempts. The struct
            %     contains:
            %
            %     - records     : cell array of attempt records
            %     - lastFailure : most recent failed attempt record
            %     - maxRecords  : maximum number of records retained
            %
            % Example
            % -------
            %     diagnostics = smartAnalyze.getDiagnostics();
            %     smartAnalyze.printLastFailure();

            s = analysis.SmartAnalyze.state();

            if s.cfg.recordDiagnostics
                diagnostics = s.diagnostics;
            else
                warning('Diagnostics are not recorded.');
                diagnostics = [];
            end
        end

        function printLastFailure()
            % Print a concise diagnostic report for the most recent failed attempt.
            %
            % Example
            % -------
            %     smartAnalyze.printLastFailure();

            d = analysis.SmartAnalyze.getDiagnostics();
            if ~isfield(d, 'lastFailure') || isempty(d.lastFailure)
                fprintf('>>> %s No failed SmartAnalyze attempt has been recorded.\n', analysis.SmartAnalyze.logo);
                return;
            end

            r = d.lastFailure;
            fprintf('>>>❌ %s Last failure diagnostic\n', analysis.SmartAnalyze.logo);
            fprintf('    Time         : %s\n', r.timestamp);
            fprintf('    Step index   : %d\n', r.stepIndex);
            fprintf('    Analysis     : %s\n', r.analysis);
            fprintf('    Strategy     : %s\n', r.strategy);
            fprintf('    Step size    : %.6e\n', r.step);
            fprintf('    Algorithm    : %s\n', r.algorithmText);
            fprintf('    Test         : %s, tol=%.3e, iter=%d, printFlag=%d\n', ...
                r.testType, r.testTol, r.testIterTimes, r.testPrintFlag);
            fprintf('    Return code  : %g\n', r.ok);
            fprintf('    Reason       : %s\n', r.reason);
            if isfield(r, 'partialAdvance') && r.partialAdvance
                fprintf('    Partial step : model state may have advanced by %.6e before relaxation failed\n', ...
                    r.partialAdvanceInfo.completedStep);
                fprintf('                   remaining=%.6e, failedSubstep=%.6e, reason=%s\n', ...
                    r.partialAdvanceInfo.remainingStep, ...
                    r.partialAdvanceInfo.failedSubstep, ...
                    r.partialAdvanceInfo.reason);
            end
            if isfield(r, 'suggestion') && ~isempty(r.suggestion)
                fprintf('    Suggestion   : %s\n', r.suggestion);
            end

            if ~isempty(r.norms)
                fprintf('    Norm history : first=%.3e, last=%.3e, min=%.3e, max=%.3e\n', ...
                    r.trend.first, r.trend.last, r.trend.min, r.trend.max);
                fprintf('    Norm trend   : improving=%d, stagnating=%d, diverging=%d, nonfinite=%d\n', ...
                    r.trend.isImproving, r.trend.isStagnating, ...
                    r.trend.isDiverging, r.trend.hasNonfinite);
            else
                fprintf('    Norm history : unavailable\n');
            end
        end

        function history = getNormHistory()
            % Get the convergence norm history collected during analysis.
            % You can use this to inspect the norm history collected
            % during analyze attempts. You need to enable norm history
            % recording in the configuration before using this function.
            %
            % Returns
            % -------
            % history : struct array
            %     Each element contains stepIndex, strategy, ok, firstNorm,
            %     lastNorm, minNorm, maxNorm, numIter, improvementRatio,
            %     isDiverging, and isStagnating.
            %
            % Example
            % -------
            %     history = smartAnalyze.getNormHistory();
            %     semilogy([history.lastNorm]);

            s = analysis.SmartAnalyze.state();
            if s.cfg.recordNormHistory
                if isempty(s.normHistory)
                    warning('Norm history is empty.');
                    history = struct([]);
                else
                    history = s.normHistory;
                end
            else
                warning('Norm history is not recorded.');
                history = struct([]);
            end
        end
    end

    methods (Static, Access = private)
        function s = defaultState()
            s = struct();
            s.ops = [];
            s.analysis = "Transient";
            s.debug = false;
            s.eps = 1e-12;
            % s.logFile = ".SmartAnalyze-OpenSees.log";
            s.logo = "SmartAnalyze::";
            s.sensitivityAlgorithm = '';
            s.currentAlgorithmType = NaN;
            s.currentAlgorithmArgs = {};
            s.currentTestType = 'EnergyIncr';
            s.currentTestTol = 1e-10;
            s.currentTestIterTimes = 10;
            s.currentTestPrintFlag = 0;

            s.cfg = struct( ...
                'analysis',          'Transient', ...
                'testType',          'EnergyIncr', ...
                'testTol',           1e-10, ...
                'testIterTimes',     10, ...
                'testPrintFlag',     0, ...
                'tryAddTestTimes',   false, ...
                'normTol',           1e3, ...
                'testIterTimesMore', 50, ...
                'tryLooseTestTol',   false, ...
                'looseTestTolTo',    1e-8, ...
                'tryAlterTestTypes', false, ...
                'testTypesMore',     {{'NormDispIncr','NormUnbalance','RelativeEnergyIncr'}}, ...
                'recordNormHistory', true, ...
                'recordDiagnostics', false, ...
                'tryAlterAlgoTypes', false, ...
                'algoTypes',         [40 10 20 30 50 60 70 90], ...
                'UserAlgoArgs',      {{}}, ...
                'tryRelaxStep',      true, ...
                'initialStep',       [], ...
                'relaxation',        0.5, ...
                'minStep',           1e-6, ...
                'debugMode',         true, ...
                'printPer',          20);

            s.cfg.looseTestTolTo = 100 * s.cfg.testTol;

            s.lastNorms = [];
            s.normHistory = [];

            s.progress = struct( ...
                'tic',      tic, ...
                'counter',  0, ...
                'done',     0, ...
                'npts',     0, ...
                'step',     0.0, ...
                'node',     0, ...
                'dof',      0);

            s.diagnostics = struct( ...
                'records',   {{}}, ...
                'lastFailure', [], ...
                'maxRecords', 200);
        end

        function clearDiagnostics()
            % Clear SmartAnalyze diagnostic records.
            %
            % Example
            % -------
            %     smartAnalyze.clearDiagnostics();

            s = analysis.SmartAnalyze.state();
            s.diagnostics.records = {};
            s.diagnostics.lastFailure = [];
            analysis.SmartAnalyze.state(s);
        end

        function clearNormHistory()
            % Clear the convergence norm history.
            %
            % Example
            % -------
            %     smartAnalyze.clearNormHistory();

            s = analysis.SmartAnalyze.state();
            s.normHistory = [];
            analysis.SmartAnalyze.state(s);
        end

        function out = state(varargin)
            persistent STATE
            if isempty(STATE)
                STATE = analysis.SmartAnalyze.defaultState();
            end
            if nargin == 1
                STATE = varargin{1};
            end
            out = STATE;
        end

        function s = normalizeState(s)
            s.analysis = string(s.cfg.analysis);
            if ~ismember(s.analysis, ["Transient","Static"])
                error('SmartAnalyze:InvalidInput', ...
                    'analysis must be "Transient" or "Static".');
            end

            s.cfg.algoTypes = double(s.cfg.algoTypes(:)).';
            if isempty(s.cfg.algoTypes) || any(~isfinite(s.cfg.algoTypes))
                error('SmartAnalyze:InvalidInput', ...
                    'algoTypes must be a nonempty finite numeric vector.');
            end

            t = double(s.cfg.testIterTimesMore(:)).';
            t = t(isfinite(t) & t > 0);
            if isempty(t)
                t = 50;
            end
            s.cfg.testIterTimesMore = round(t);

            if isempty(s.cfg.UserAlgoArgs)
                s.cfg.UserAlgoArgs = {};
            end

            if isempty(s.cfg.initialStep) || ...
               (isscalar(s.cfg.initialStep) && isnumeric(s.cfg.initialStep) && isnan(s.cfg.initialStep))
                s.cfg.initialStep = [];
            end

            % normalize looseTestTolTo
            t = double(s.cfg.looseTestTolTo(:)).';
            t = t(isfinite(t) & t > 0);
            if isempty(t)
                t = 100 * s.cfg.testTol;
            end
            s.cfg.looseTestTolTo = t;

            % normalize testTypesMore
            if ~iscell(s.cfg.testTypesMore)
                if ischar(s.cfg.testTypesMore) || isstring(s.cfg.testTypesMore)
                    s.cfg.testTypesMore = {char(s.cfg.testTypesMore)};
                else
                    s.cfg.testTypesMore = {};
                end
            end
            s.cfg.testTypesMore = s.cfg.testTypesMore(~cellfun('isempty', s.cfg.testTypesMore));

            s.cfg.recordNormHistory = logical(s.cfg.recordNormHistory);
            s.cfg.recordDiagnostics = logical(s.cfg.recordDiagnostics);
            s.debug = logical(s.cfg.debugMode);
        end

        function s = requireOps()
            s = analysis.SmartAnalyze.state();
            if isempty(s.ops)
                error('SmartAnalyze:OpsNotSet', ...
                    'Call SmartAnalyze.setOps(ops) or SmartAnalyze.setOPS(ops) first. This is done automatically when using opsmat.anlys.smartAnalyze.');
            end
        end

        function t = elapsed()
            s = analysis.SmartAnalyze.state();
            t = toc(s.progress.tic);
        end

        function runSensitivity()
            s = analysis.SmartAnalyze.state();
            if ~isempty(s.sensitivityAlgorithm)
                s.ops.sensitivityAlgorithm(s.sensitivityAlgorithm);
            end
        end

        function ok = runAnalysis()
            s = analysis.SmartAnalyze.state();
            step = s.cfg.initialStep;
            verbose = s.debug;

            ok = analysis.SmartAnalyze.analyzeOne(step, verbose, "initial");
            if ok < 0, ok = analysis.SmartAnalyze.tryAddTestTimes(step, verbose); end
            if ok < 0, ok = analysis.SmartAnalyze.tryAlterAlgo(step, verbose); end
            if ok < 0, ok = analysis.SmartAnalyze.tryAlterTestTypes(step, verbose); end
            if ok < 0, ok = analysis.SmartAnalyze.tryLooseTol(step, verbose); end
            if ok < 0 && s.cfg.tryRelaxStep, ok = analysis.SmartAnalyze.tryRelaxStep(step, verbose); end

            if ok < 0
                analysis.SmartAnalyze.printStatus(false);
                if verbose
                    analysis.SmartAnalyze.printLastFailure();
                end
                return;
            end

            s = analysis.SmartAnalyze.state();
            s.progress.done = s.progress.done + 1;
            s.progress.counter = s.progress.counter + 1;
            analysis.SmartAnalyze.state(s);

            if verbose && s.progress.counter >= s.cfg.printPer
                analysis.SmartAnalyze.printProgress();
                s = analysis.SmartAnalyze.state();
                s.progress.counter = 0;
                analysis.SmartAnalyze.state(s);
            end

            if s.progress.npts > 0 && s.progress.done >= s.progress.npts
                analysis.SmartAnalyze.printStatus(true);
            end

            ok = 0;
        end

        function printStatus(success)
            s = analysis.SmartAnalyze.state();
            t = analysis.SmartAnalyze.elapsed();
            if s.progress.npts > 0
                pct = min(100, 100 * s.progress.done / s.progress.npts);
                progressText = sprintf(' Progress: %.3f %% (%d/%d).', ...
                    pct, s.progress.done, s.progress.npts);
            else
                progressText = sprintf(' Progress: %d steps.', s.progress.done);
            end

            if success
                fprintf('>>>🎃 %s Successfully finished!%s Time consumption: %.3f s.\n', ...
                    s.logo, progressText, t);
            else
                fprintf('>>>❌ %s Analyze failed.%s Time consumption: %.3f s.\n', ...
                    s.logo, progressText, t);
            end
        end

        function printProgress()
            s = analysis.SmartAnalyze.state();
            t = analysis.SmartAnalyze.elapsed();
            if s.progress.npts > 0
                pct = min(100, 100 * s.progress.done / s.progress.npts);
                fprintf('>>>✅ %s progress %.3f %% (%d/%d). Time consumption: %.3f s.\n', ...
                    s.logo, pct, s.progress.done, s.progress.npts, t);
            else
                fprintf('>>>✅ %s progress %d steps. Time consumption: %.3f s.\n', ...
                    s.logo, s.progress.done, t);
            end
        end

        function ok = analyzeOne(step, verbose, strategy)
            if nargin < 3 || strlength(string(strategy)) == 0
                strategy = "analyzeOne";
            end

            s = analysis.SmartAnalyze.state();

            if s.analysis == "Static"
                s.ops.integrator("DisplacementControl", ...
                    s.progress.node, s.progress.dof, step);
                analysis.SmartAnalyze.runSensitivity();
            end

            if ~verbose
                try
                    % s.ops.logFile(s.logFile, '-noEcho');
                catch
                end
            end

            if s.analysis == "Static"
                ok = s.ops.analyze(1);
            else
                ok = s.ops.analyze(1, step);
            end

            norms = analysis.SmartAnalyze.testNorms();
            trend = analysis.SmartAnalyze.normTrend(norms);
            analysis.SmartAnalyze.recordAttempt(strategy, step, ok, norms, trend);
        end

        function ok = tryAddTestTimes(step, verbose)
            s = analysis.SmartAnalyze.state();
            ok = -1;
            if ~s.cfg.tryAddTestTimes
                return;
            end

            nrm = analysis.SmartAnalyze.lastNorm();
            if ~(isfinite(nrm) && nrm < s.cfg.normTol)
                if verbose
                    fprintf('>>> %s Not adding test times for norm %.3e.\n', s.logo, nrm);
                end
                return;
            end

            for n = s.cfg.testIterTimesMore
                if verbose
                    fprintf('>>>✳️ %s Adding test times to %d.\n', s.logo, n);
                end
                s.ops.test(s.cfg.testType, s.cfg.testTol, n, s.cfg.testPrintFlag);
                analysis.SmartAnalyze.setCurrentTest(s.cfg.testType, s.cfg.testTol, n, s.cfg.testPrintFlag);
                ok = analysis.SmartAnalyze.analyzeOne(step, verbose, sprintf('tryAddTestTimes:%d', n));
                if ok == 0
                    analysis.SmartAnalyze.setTest();
                    return;
                end
            end

            analysis.SmartAnalyze.setTest();
        end

        function ok = tryAlterAlgo(step, verbose)
            s = analysis.SmartAnalyze.state();
            ok = -1;
            if ~s.cfg.tryAlterAlgoTypes || numel(s.cfg.algoTypes) <= 1
                return;
            end

            for a = s.cfg.algoTypes(2:end)
                if verbose
                    fprintf('>>>✳️ %s Setting algorithm to %d.\n', s.logo, a);
                end
                analysis.SmartAnalyze.setAlgorithm(a);
                ok = analysis.SmartAnalyze.analyzeOne(step, verbose, sprintf('tryAlterAlgo:%g', a));
                if ok == 0
                    return;
                end
            end

            analysis.SmartAnalyze.setAlgorithm(s.cfg.algoTypes(1));
        end

        function ok = tryRelaxStep(step, verbose)
            s = analysis.SmartAnalyze.state();
            ok = -1;

            if ~s.cfg.tryRelaxStep
                return;
            end

            alpha   = abs(s.cfg.relaxation);
            minStep = abs(s.cfg.minStep);

            remain = step;
            stepTry = step * alpha;
            completed = 0.0;

            if verbose
                fprintf('>>>✳️ %s Dividing current step %.3e into %.3e and %.3e.\n', ...
                    s.logo, step, stepTry, step - stepTry);
            end

            while abs(remain) > s.eps
                if abs(stepTry) < minStep
                    if abs(completed) > s.eps
                        analysis.SmartAnalyze.flagPartialAdvance( ...
                            step, completed, remain, stepTry, "minStepReached");
                    end
                    if verbose
                        fprintf('>>>❌ %s Current step %.3e is below minStep %.3e.\n', ...
                            s.logo, stepTry, minStep);
                        if abs(completed) > s.eps
                            fprintf('>>>⚠️ %s Relaxed substeps partially advanced the model by %.3e before failure. Remaining step: %.3e.\n', ...
                                s.logo, completed, remain);
                        end
                    end
                    return;
                end

                if abs(stepTry) > abs(remain)
                    stepTry = remain;
                end

                ok = analysis.SmartAnalyze.analyzeOne(stepTry, verbose, "tryRelaxStep");

                if ok == 0
                    remain = remain - stepTry;
                    completed = step - remain;
                    stepTry = remain;
                    if verbose
                        fprintf('>>>✳️ %s Total step %.3e, completed %.3e, remaining %.3e.\n', ...
                            s.logo, step, completed, remain);
                    end
                else
                    stepTry = stepTry * alpha;
                    if verbose
                        fprintf('>>>✳️ %s Dividing failed substep into smaller step %.3e.\n', ...
                            s.logo, stepTry);
                    end
                end
            end
        end

        function ok = tryAlterTestTypes(step, verbose)
            s = analysis.SmartAnalyze.state();
            ok = -1;
            if ~s.cfg.tryAlterTestTypes || isempty(s.cfg.testTypesMore)
                return;
            end

            for tt = s.cfg.testTypesMore
                ttChar = char(tt);
                if verbose
                    fprintf('>>>✳️ %s Switching test type to %s.\n', s.logo, ttChar);
                end
                s.ops.test(ttChar, s.cfg.testTol, ...
                           s.cfg.testIterTimes, s.cfg.testPrintFlag);
                analysis.SmartAnalyze.setCurrentTest(ttChar, s.cfg.testTol, ...
                           s.cfg.testIterTimes, s.cfg.testPrintFlag);
                ok = analysis.SmartAnalyze.analyzeOne(step, verbose, sprintf('tryAlterTestTypes:%s', ttChar));
                if ok == 0
                    analysis.SmartAnalyze.setTest();
                    return;
                end
            end

            analysis.SmartAnalyze.setTest();
        end

        function ok = tryLooseTol(step, verbose)
            s = analysis.SmartAnalyze.state();
            ok = -1;
            if ~s.cfg.tryLooseTestTol || isempty(s.cfg.looseTestTolTo)
                return;
            end

            for tol = s.cfg.looseTestTolTo
                if verbose
                    fprintf('>>>✳️ %s Loosing test tolerance to %.3e.\n', ...
                        s.logo, tol);
                end

                s.ops.test(s.cfg.testType, tol, ...
                           s.cfg.testIterTimes, s.cfg.testPrintFlag);
                analysis.SmartAnalyze.setCurrentTest(s.cfg.testType, tol, ...
                           s.cfg.testIterTimes, s.cfg.testPrintFlag);

                ok = analysis.SmartAnalyze.analyzeOne(step, verbose, sprintf('tryLooseTol:%.3e', tol));
                if ok == 0
                    analysis.SmartAnalyze.setTest();
                    return;
                end
            end

            analysis.SmartAnalyze.setTest();
        end

        function setTest()
            s = analysis.SmartAnalyze.state();
            s.ops.test(s.cfg.testType, s.cfg.testTol, ...
                       s.cfg.testIterTimes, s.cfg.testPrintFlag);
            analysis.SmartAnalyze.setCurrentTest(s.cfg.testType, s.cfg.testTol, ...
                       s.cfg.testIterTimes, s.cfg.testPrintFlag);
        end

        function setCurrentTest(testType, testTol, testIterTimes, testPrintFlag)
            s = analysis.SmartAnalyze.state();
            s.currentTestType = testType;
            s.currentTestTol = testTol;
            s.currentTestIterTimes = testIterTimes;
            s.currentTestPrintFlag = testPrintFlag;
            analysis.SmartAnalyze.state(s);
        end

        function setAlgorithm(algotype)
            s = analysis.SmartAnalyze.state();
            args = analysis.SmartAnalyze.algorithmArgs(algotype, s.cfg.UserAlgoArgs);

            if s.debug
                fprintf('>>>✳️ %s Setting algorithm to %s\n', ...
                    s.logo, strjoin(cellfun(@analysis.SmartAnalyze.toText, args, 'UniformOutput', false), ' '));
            end

            s.ops.algorithm(args{:});

            s = analysis.SmartAnalyze.state();
            s.currentAlgorithmType = algotype;
            s.currentAlgorithmArgs = args;
            analysis.SmartAnalyze.state(s);
        end

        function n = lastNorm()
            s = analysis.SmartAnalyze.state();
            a = s.lastNorms;
            if isempty(a)
                a = analysis.SmartAnalyze.testNorms();
            end
            a = a(isfinite(a));
            if isempty(a)
                n = inf;
            else
                n = a(end);
            end
        end

        function norms = testNorms()
            s = analysis.SmartAnalyze.state();
            norms = zeros(0,1);
            try
                a = s.ops.testNorm();
                if isempty(a)
                    return;
                end
                norms = double(a(:));
            catch
                norms = zeros(0,1);
            end
        end

        function trend = normTrend(norms)
            norms = double(norms(:));

            trend = struct( ...
                'isEmpty',       isempty(norms), ...
                'hasNaN',        any(isnan(norms)), ...
                'hasInf',        any(isinf(norms)), ...
                'hasNonfinite',  any(~isfinite(norms)), ...
                'first',         NaN, ...
                'last',          NaN, ...
                'min',           NaN, ...
                'max',           NaN, ...
                'improvementRatio', NaN, ...
                'isImproving',   false, ...
                'isStagnating',  false, ...
                'isDiverging',   false);

            finiteNorms = norms(isfinite(norms));
            if isempty(finiteNorms)
                return;
            end

            trend.isEmpty = false;
            trend.first = finiteNorms(1);
            trend.last  = finiteNorms(end);
            trend.min   = min(finiteNorms);
            trend.max   = max(finiteNorms);

            denom = max(abs(trend.first), eps);
            trend.improvementRatio = abs(trend.last) / denom;
            trend.isImproving = trend.improvementRatio < 0.5;
            trend.isDiverging = numel(finiteNorms) >= 2 && abs(trend.last) > abs(trend.first);

            if numel(finiteNorms) >= 3
                recent = finiteNorms(max(1,end-2):end);
                relChange = abs(diff(recent)) ./ max(abs(recent(1:end-1)), eps);
                trend.isStagnating = all(relChange < 1e-3);
            end
        end

        function recordAttempt(strategy, step, ok, norms, trend)
            s = analysis.SmartAnalyze.state();

            % 缓存 norms 并更新当前步长
            s.progress.step = step;
            s.lastNorms = norms;

            % 记录 norm history（轻量级摘要）
            if s.cfg.recordNormHistory
                nh = struct( ...
                    'stepIndex', s.progress.done + 1, ...
                    'strategy', char(string(strategy)), ...
                    'ok', ok, ...
                    'firstNorm', trend.first, ...
                    'lastNorm', trend.last, ...
                    'minNorm', trend.min, ...
                    'maxNorm', trend.max, ...
                    'numIter', numel(norms), ...
                    'improvementRatio', trend.improvementRatio, ...
                    'isDiverging', trend.isDiverging, ...
                    'isStagnating', trend.isStagnating);
                if isempty(s.normHistory)
                    s.normHistory = nh;
                else
                    s.normHistory(end+1) = nh;
                end
            end

            % 成功时快速返回，避免诊断记录和复杂计算的开销
            if ok == 0
                analysis.SmartAnalyze.state(s);
                return;
            end

            % 失败时，仅在 recordDiagnostics 开启时记录详细诊断
            if s.cfg.recordDiagnostics
                rec = struct();
                rec.timestamp = datestr(now, 'yyyy-mm-dd HH:MM:SS.FFF');
                rec.stepIndex = s.progress.done + 1;
                rec.analysis = char(string(s.analysis));
                rec.strategy = char(string(strategy));
                rec.step = step;
                rec.ok = ok;
                rec.success = false;
                rec.testType = s.currentTestType;
                rec.testTol = s.currentTestTol;
                rec.testIterTimes = s.currentTestIterTimes;
                rec.testPrintFlag = s.currentTestPrintFlag;
                rec.algorithmType = s.currentAlgorithmType;
                rec.algorithmArgs = s.currentAlgorithmArgs;
                rec.algorithmText = analysis.SmartAnalyze.algorithmText(s.currentAlgorithmArgs);
                rec.norms = norms;
                rec.trend = trend;
                rec.reason = analysis.SmartAnalyze.failureReason(ok, trend);
                rec.partialAdvance = false;
                rec.partialAdvanceInfo = [];
                rec.suggestion = analysis.SmartAnalyze.convergenceSuggestion(ok, trend, rec);

                if ~isfield(s, 'diagnostics') || isempty(s.diagnostics)
                    s.diagnostics = struct('records', {{}}, 'lastFailure', [], 'maxRecords', 200);
                end

                s.diagnostics.records{end+1} = rec;
                if isfield(s.diagnostics, 'maxRecords') && numel(s.diagnostics.records) > s.diagnostics.maxRecords
                    s.diagnostics.records = s.diagnostics.records(end-s.diagnostics.maxRecords+1:end);
                end
                s.diagnostics.lastFailure = rec;
            end

            analysis.SmartAnalyze.state(s);
        end

        function reason = failureReason(ok, trend)
            if ok == 0
                reason = 'converged';
                return;
            end

            if trend.hasNonfinite
                reason = 'nonfinite convergence norm detected';
            elseif trend.isEmpty
                reason = 'convergence norm unavailable';
            elseif trend.isDiverging
                reason = 'convergence norm is diverging';
            elseif trend.isStagnating
                reason = 'convergence norm is stagnating';
            elseif trend.isImproving
                reason = 'convergence norm is improving but did not reach tolerance';
            else
                reason = 'analysis command returned a failure code';
            end
        end

        function suggestion = convergenceSuggestion(ok, trend, rec)
            if ok == 0
                suggestion = 'No action needed.';
                return;
            end

            if trend.hasNonfinite
                suggestion = 'Detected NaN/Inf convergence norms. Try reducing the step size, checking material state limits, and switching to a robust line-search algorithm.';
            elseif trend.isEmpty
                suggestion = 'OpenSees did not provide convergence norms. Enable test print output, inspect the OpenSees warning log, and check whether the system/integrator failed before the convergence test ran.';
            elseif trend.isDiverging
                suggestion = 'The convergence norm is growing. Try a smaller step, NewtonLineSearch, KrylovNewton, or a more stable constraint/system configuration.';
            elseif trend.isStagnating
                suggestion = 'The convergence norm is stagnating. Try changing the convergence test type, switching algorithms, or using a smaller step size.';
            elseif trend.isImproving
                suggestion = 'The convergence norm is decreasing but not enough. Try increasing testIterTimes, using tryAddTestTimes, or loosening testTol within an acceptable engineering tolerance.';
            elseif contains(rec.strategy, 'tryRelaxStep')
                suggestion = 'Step relaxation failed. Consider reducing the target step size, increasing relaxation, decreasing minStep, or checking for severe local nonlinearities.';
            elseif contains(rec.strategy, 'tryAlterAlgo')
                suggestion = 'Algorithm switching failed. Add more algorithm candidates, especially NewtonLineSearch variants, ModifiedNewton, BFGS, or Broyden.';
            elseif contains(rec.strategy, 'tryLooseTol')
                suggestion = 'Loose tolerance retry failed. The issue is likely not only tolerance-related; try smaller steps or a different algorithm/test type.';
            else
                suggestion = 'Try enabling tryAddTestTimes, tryAlterAlgoTypes, and tryLooseTestTol, then inspect the recorded norm trend and OpenSees warning messages.';
            end
        end

        function flagPartialAdvance(totalStep, completedStep, remainingStep, failedSubstep, reason)
            s = analysis.SmartAnalyze.state();

            info = struct( ...
                'totalStep',     totalStep, ...
                'completedStep', completedStep, ...
                'remainingStep', remainingStep, ...
                'failedSubstep', failedSubstep, ...
                'reason',        char(string(reason)));

            if ~isfield(s, 'diagnostics') || isempty(s.diagnostics)
                s.diagnostics = struct('records', {{}}, 'lastFailure', [], 'maxRecords', 200);
            end

            if ~isempty(s.diagnostics.records)
                rec = s.diagnostics.records{end};
                rec.partialAdvance = true;
                rec.partialAdvanceInfo = info;
                rec.reason = sprintf('%s; partial model advancement detected', rec.reason);
                rec.suggestion = [rec.suggestion, ...
                    ' The OpenSees model state may already be partially advanced; avoid applying another whole-step retry unless the model can be restored.'];
                s.diagnostics.records{end} = rec;

                if ~isempty(s.diagnostics.lastFailure)
                    s.diagnostics.lastFailure = rec;
                end
            end

            analysis.SmartAnalyze.state(s);
        end

        function txt = algorithmText(args)
            if isempty(args)
                txt = '<unset>';
                return;
            end
            txt = strjoin(cellfun(@analysis.SmartAnalyze.toText, args, 'UniformOutput', false), ' ');
        end

        function args = algorithmArgs(algotype, userArgs)
            switch algotype
                case 0,  args = {'Linear'};
                case 1,  args = {'Linear','-Initial'};
                case 2,  args = {'Linear','-Secant'};
                case 3,  args = {'Linear','-FactorOnce'};
                case 4,  args = {'Linear','-Initial','-FactorOnce'};
                case 5,  args = {'Linear','-Secant','-FactorOnce'};

                case 10, args = {'Newton'};
                case 11, args = {'Newton','-Initial'};
                case 12, args = {'Newton','-initialThenCurrent'};
                case 13, args = {'Newton','-Secant'};

                case 20, args = {'NewtonLineSearch'};
                case 21, args = {'NewtonLineSearch','-type','Bisection'};
                case 22, args = {'NewtonLineSearch','-type','Secant'};
                case 23, args = {'NewtonLineSearch','-type','RegulaFalsi'};
                case 24, args = {'NewtonLineSearch','-type','LinearInterpolated'};
                case 25, args = {'NewtonLineSearch','-type','InitialInterpolated'};

                case 30, args = {'ModifiedNewton'};
                case 31, args = {'ModifiedNewton','-initial'};
                case 32, args = {'ModifiedNewton','-secant'};

                case 40, args = {'KrylovNewton'};
                case 41, args = {'KrylovNewton','-iterate','initial'};
                case 42, args = {'KrylovNewton','-increment','initial'};
                case 43, args = {'KrylovNewton','-iterate','initial','-increment','initial'};
                case 44, args = {'KrylovNewton','-maxDim',10};
                case 45, args = {'KrylovNewton','-iterate','initial','-increment','initial','-maxDim',10};

                case 50, args = {'SecantNewton'};
                case 51, args = {'SecantNewton','-iterate','initial'};
                case 52, args = {'SecantNewton','-increment','initial'};
                case 53, args = {'SecantNewton','-iterate','initial','-increment','initial'};

                case 60, args = {'BFGS'};
                case 61, args = {'BFGS','-initial'};
                case 62, args = {'BFGS','-secant'};

                case 70, args = {'Broyden'};
                case 71, args = {'Broyden','-initial'};
                case 72, args = {'Broyden','-secant'};

                case 80, args = {'PeriodicNewton'};
                case 81, args = {'PeriodicNewton','-maxDim',10};

                case 90, args = {'ExpressNewton'};
                case 91, args = {'ExpressNewton','-InitialTangent'};

                case 100
                    if isempty(userArgs)
                        error('SmartAnalyze:InvalidInput', ...
                            'UserAlgoArgs must be provided for algorithm type 100.');
                    end
                    args = userArgs;

                otherwise
                    error('SmartAnalyze:InvalidInput', ...
                        'Wrong algorithm type: %g', algotype);
            end
        end

        function s = toText(x)
            if ischar(x) || isstring(x)
                s = char(string(x));
            elseif isnumeric(x) && isscalar(x)
                s = num2str(x);
            else
                s = '<arg>';
            end
        end
    end
end
