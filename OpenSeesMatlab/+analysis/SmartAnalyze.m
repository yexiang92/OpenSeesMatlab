classdef SmartAnalyze < handle
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
    % Performance
    % -----------
    %   SmartAnalyze is a handle class. All property access and method calls
    %   operate directly on the object without copying state, giving O(1)
    %   overhead per step regardless of analysis length. normHistory uses a
    %   struct-of-columns layout so that appending is O(1) amortised.
    %   diagnostics.records is a fixed-capacity ring buffer so memory is
    %   bounded at maxRecords entries.
    %
    % Example
    % --------
    %       % Transient analysis with full retry strategies
    %       opsmat = OpenSeesMatlab();
    %       ops = opsmat.ops;
    %       sa = opsmat.anlys.smartAnalyze;
    %
    %       ops.wipeAnalysis();
    %       ops.constraints('Plain');
    %       ops.numberer('RCM');
    %       ops.system('UmfPack');
    %
    %       sa.configure(...
    %           analysis="Transient", testType="EnergyIncr", testTol=1e-10, ...
    %           testIterTimes=100, tryAddTestTimes=true, normTol=1e3, ...
    %           testIterTimesMore=[50 100], tryLooseTestTol=true, ...
    %           looseTestTolTo=[1e-8, 1e-6], tryAlterTestTypes=true, ...
    %           testTypesMore=["NormDispIncr","NormUnbalance"], ...
    %           tryAlterAlgoTypes=true, algoTypes=[40 10 20 30], ...
    %           tryRelaxStep=true, relaxation=0.5, minStep=1e-6, ...
    %           recordNormHistory=true, debugMode=true, printPer=100);
    %
    %       sa.setTotalSteps(1000);
    %       for i = 1:1000
    %           ok = sa.transientAnalyze(0.01);
    %           if ok < 0, error("Transient analysis failed at step %d.", i); end
    %       end
    %       history = sa.getNormHistory();
    %       sa.reset();
    %
    %       %--- Static pushover (minimal settings) ---
    %       sa.configure(analysis="Static", testType="EnergyIncr", testTol=1e-8, ...
    %           tryAlterAlgoTypes=true, algoTypes=[40 10 20], tryRelaxStep=true, ...
    %           minStep=1e-6, recordNormHistory=true, debugMode=false);
    %
    %       segs = sa.staticStepSplit([0; 0.5; 1.0], 0.1);
    %       for i = 1:numel(segs)
    %           ok = sa.staticAnalyze(1, 1, segs(i));
    %           if ok < 0, error("Static analysis failed at segment %d.", i); end
    %       end
    %       sa.reset();

    % -----------------------------------------------------------------------
    % Public properties — readable by callers, written only by this class
    % -----------------------------------------------------------------------
    properties (SetAccess = private)
        % ops : OpenSees command interface set by setOPS()
        ops = []

        % cfg : current analysis configuration struct set by configure()
        cfg = struct()

        % normHistory : struct-of-columns convergence norm history
        normHistory = struct()

        % diagnostics : ring-buffer failure diagnostic records
        diagnostics = struct()

        % progress : runtime counters (done, npts, tic, ...)
        progress = struct()
    end

    % -----------------------------------------------------------------------
    % Private properties — internal runtime state
    % -----------------------------------------------------------------------
    properties (Access = private)
        analysisType    string  = "Transient"
        debugMode       logical = false
        eps_            double  = 1e-12
        sensitivityAlgorithm char = ''
        lastNorms       double  = zeros(0,1)

        % Mirror of the active OpenSees test/algorithm for diagnostics
        currentTestType      char   = 'EnergyIncr'
        currentTestTol       double = 1e-10
        currentTestIterTimes double = 10
        currentTestPrintFlag double = 0
        currentAlgorithmType double = NaN
        currentAlgorithmArgs cell   = {}
    end

    properties (Constant, Access = private)
        logo = "[OpenSeesMatlab::SmartAnalyze]"
    end

    % -----------------------------------------------------------------------
    % Constructor
    % -----------------------------------------------------------------------
    methods
        function obj = SmartAnalyze()
            obj.cfg        = analysis.SmartAnalyze.defaultCfg();
            obj.normHistory = analysis.SmartAnalyze.emptyNormHistory();
            obj.diagnostics = analysis.SmartAnalyze.emptyDiagnostics(200);
            obj.progress    = analysis.SmartAnalyze.emptyProgress();
        end
    end

    % -----------------------------------------------------------------------
    % Public API
    % -----------------------------------------------------------------------
    methods
        function setOPS(obj, ops)
            % Set the OpenSees command interface.
            %
            % Parameters
            % ----------
            % ops : OpenSeesMatlabCmds or compatible object
            %     Must expose: test, algorithm, integrator, analysis,
            %     analyze, testNorm, and optionally sensitivityAlgorithm.
            arguments
                obj
                ops
            end
            obj.ops = ops;
        end

        function configure(obj, opts)
            % Configure analysis settings and apply the initial test and algorithm.
            %
            % Syntax
            % ------
            %     sa.configure(Name=Value)
            %
            % Notes
            % -----
            %     setOPS must be called before configure. configure immediately
            %     applies the convergence test and first algorithm to OpenSees.
            %
            % Parameters
            % ----------
            % analysis : string, optional
            %     Analysis type: "Transient" (default) or "Static".
            % testType : string, optional
            %     OpenSees convergence test type. Default is "EnergyIncr".
            %     Supported values:
            %
            %     - "EnergyIncr"                 : half inner product of disp incr and unbalance
            %     - "NormUnbalance"               : norm of unbalanced load vector
            %     - "NormDispIncr"                : norm of displacement increment vector
            %     - "RelativeNormUnbalance"       : NormUnbalance relative to first iteration
            %     - "RelativeNormDispIncr"        : NormDispIncr relative to first iteration
            %     - "RelativeTotalNormDispIncr"   : NormDispIncr relative to total displacement norm
            %     - "RelativeEnergyIncr"          : EnergyIncr relative to first iteration
            %     - "FixedNumIter"                : always runs exactly testIterTimes iterations
            %     - "NormDispAndUnbalance"        : both NormDispIncr and NormUnbalance must pass
            %     - "NormDispOrUnbalance"         : either NormDispIncr or NormUnbalance must pass
            %
            % testTol : double, optional
            %     Convergence tolerance. Default 1e-10.
            % testIterTimes : double, optional
            %     Maximum convergence-test iterations. Default 10.
            % testPrintFlag : double, optional
            %     OpenSees test print flag. Default 0.
            % tryAddTestTimes : logical, optional
            %     Retry with more iterations when norm < normTol. Default false.
            % normTol : double, optional
            %     Norm threshold for tryAddTestTimes. Default 1e3.
            % testIterTimesMore : double array, optional
            %     Extra iteration limits to try. Default 50.
            % tryLooseTestTol : logical, optional
            %     Retry with looser tolerance. Default false.
            % looseTestTolTo : double or array, optional
            %     Looser tolerance(s). Default 100*testTol.
            % tryAlterTestTypes : logical, optional
            %     Retry with alternate test types. Default false.
            % testTypesMore : string array or cell, optional
            %     Alternate test types. Default {'NormDispIncr','NormUnbalance','RelativeEnergyIncr'}.
            %     Supported values are the same as for testType (see above).
            % tryAlterAlgoTypes : logical, optional
            %     Retry with fallback algorithms. Default false.
            % algoTypes : double array, optional
            %     Algorithm codes. First entry applied at configure time.
            %     Default [40 10 20 30 50 60 70 90]. Supported codes:
            %
            %     - 0..5  : Linear variants
            %     - 10..13: Newton variants
            %     - 20..25: NewtonLineSearch variants
            %     - 30..32: ModifiedNewton variants
            %     - 40..45: KrylovNewton variants
            %     - 50..53: SecantNewton variants
            %     - 60..62: BFGS variants
            %     - 70..72: Broyden variants
            %     - 80..81: PeriodicNewton variants
            %     - 90..91: ExpressNewton variants
            %     - 100   : user-defined (requires UserAlgoArgs)
            %
            % UserAlgoArgs : cell array, optional
            %     Arguments for algorithm type 100.
            % tryRelaxStep : logical, optional
            %     Split failed steps into sub-steps. Default true.
            % relaxation : double, optional
            %     Sub-step shrink factor. Default 0.5.
            % minStep : double, optional
            %     Minimum sub-step size. Default 1e-6.
            % initialStep : double, optional
            %     Stored initial step (overwritten by transientAnalyze/staticAnalyze).
            % recordNormHistory : logical, optional
            %     Record per-step norm summaries. Default true.
            % recordDiagnostics : logical, optional
            %     Record detailed failure diagnostics. Default false.
            % debugMode : logical, optional
            %     Print retry and progress messages. Default false.
            % printPer : double, optional
            %     Print progress every N successful steps. Default 20.
            %
            % Example
            % -------
            %     sa.configure(analysis="Transient", testTol=1e-10, ...
            %         tryAlterAlgoTypes=true, algoTypes=[40 10 20], ...
            %         tryRelaxStep=true, minStep=1e-6, debugMode=true);
            arguments
                obj
                opts.analysis         string  {mustBeMember(opts.analysis, ["Transient","Static"])} = string(missing)
                opts.testType         string  = string(missing)
                opts.testTol          double  = NaN
                opts.testIterTimes    double  = NaN
                opts.testPrintFlag    double  = NaN
                opts.tryAddTestTimes          = []
                opts.normTol          double  = NaN
                opts.testIterTimesMore double = NaN
                opts.tryLooseTestTol          = []
                opts.looseTestTolTo   double  = NaN
                opts.tryAlterTestTypes        = []
                opts.testTypesMore            = []
                opts.recordNormHistory        = []
                opts.recordDiagnostics        = []
                opts.tryAlterAlgoTypes        = []
                opts.algoTypes        double  = NaN
                opts.UserAlgoArgs     cell    = {}
                opts.tryRelaxStep             = []
                opts.initialStep      double  = NaN
                opts.relaxation       double  = NaN
                opts.minStep          double  = NaN
                opts.debugMode                = []
                opts.printPer         double  = NaN
            end

            c = obj.cfg;

            if ~ismissing(opts.analysis),        c.analysis        = char(opts.analysis);        end
            if ~ismissing(opts.testType),         c.testType        = char(opts.testType);         end
            if ~isnan(opts.testTol),              c.testTol         = opts.testTol;                end
            if ~isnan(opts.testIterTimes),        c.testIterTimes   = opts.testIterTimes;          end
            if ~isnan(opts.testPrintFlag),        c.testPrintFlag   = opts.testPrintFlag;          end
            if ~isempty(opts.tryAddTestTimes),    c.tryAddTestTimes = logical(opts.tryAddTestTimes); end
            if ~isnan(opts.normTol),              c.normTol         = opts.normTol;                end
            if ~all(isnan(opts.testIterTimesMore)), c.testIterTimesMore = opts.testIterTimesMore;  end
            if ~isempty(opts.tryLooseTestTol),    c.tryLooseTestTol = logical(opts.tryLooseTestTol); end
            if ~isnan(opts.looseTestTolTo),       c.looseTestTolTo  = opts.looseTestTolTo;         end
            if ~isempty(opts.tryAlterTestTypes),  c.tryAlterTestTypes = logical(opts.tryAlterTestTypes); end
            if ~isempty(opts.testTypesMore)
                if isstring(opts.testTypesMore),  c.testTypesMore = cellstr(opts.testTypesMore);
                elseif iscell(opts.testTypesMore),c.testTypesMore = opts.testTypesMore;
                else,                             c.testTypesMore = {char(opts.testTypesMore)};
                end
            end
            if ~isempty(opts.tryRelaxStep),       c.tryRelaxStep    = logical(opts.tryRelaxStep);  end
            if ~isempty(opts.recordNormHistory),  c.recordNormHistory = logical(opts.recordNormHistory); end
            if ~isempty(opts.recordDiagnostics),  c.recordDiagnostics = logical(opts.recordDiagnostics); end
            if ~isempty(opts.tryAlterAlgoTypes),  c.tryAlterAlgoTypes = logical(opts.tryAlterAlgoTypes); end
            if ~all(isnan(opts.algoTypes)),       c.algoTypes       = opts.algoTypes;              end
            if ~isempty(opts.UserAlgoArgs),       c.UserAlgoArgs    = opts.UserAlgoArgs;            end
            if ~isnan(opts.initialStep),          c.initialStep     = opts.initialStep;             end
            if ~isnan(opts.relaxation),           c.relaxation      = opts.relaxation;              end
            if ~isnan(opts.minStep),              c.minStep         = opts.minStep;                 end
            if ~isempty(opts.debugMode),          c.debugMode       = logical(opts.debugMode);      end
            if ~isnan(opts.printPer),             c.printPer        = opts.printPer;                end

            obj.cfg = obj.normalizeCfg(c);
            obj.analysisType = string(obj.cfg.analysis);
            obj.debugMode    = logical(obj.cfg.debugMode);

            obj.requireOps();
            obj.applyTest();
            obj.applyAlgorithm(obj.cfg.algoTypes(1));
        end

        function initialize(obj, npts)
            % Reset cfg to defaults; keep only ops. configure() must be called after.
            %
            %   Preserved : ops
            %   Cleared   : cfg, sensitivityAlgorithm, history, progress, diagnostics
            %
            % Parameters
            % ----------
            % npts : double, optional
            %     Expected total steps (default 0 = no progress tracking).
            arguments
                obj
                npts (1,1) double {mustBeNonnegative, mustBeFinite} = 0
            end
            obj.cfg                  = analysis.SmartAnalyze.defaultCfg();
            obj.normHistory          = analysis.SmartAnalyze.emptyNormHistory();
            obj.diagnostics          = analysis.SmartAnalyze.emptyDiagnostics(200);
            obj.progress             = analysis.SmartAnalyze.emptyProgress();
            obj.progress.npts        = round(npts);
            obj.sensitivityAlgorithm = '';
            obj.lastNorms            = zeros(0,1);
            obj.analysisType         = "Transient";
            obj.debugMode            = false;
        end

        function reset(obj)
            % Clear history and progress; preserve ops and cfg.
            %
            %   After reset(), analysis can resume immediately without
            %   calling configure() again.
            %
            %   Preserved : ops, cfg, sensitivityAlgorithm
            %   Cleared   : normHistory, diagnostics, progress, lastNorms
            obj.normHistory = analysis.SmartAnalyze.emptyNormHistory();
            obj.diagnostics = analysis.SmartAnalyze.emptyDiagnostics(obj.diagnostics.maxRecords);
            obj.progress    = analysis.SmartAnalyze.emptyProgress();
            obj.lastNorms   = zeros(0,1);
        end

        function close(obj)
            % Alias for initialize() — reset cfg to defaults, keep ops.
            obj.initialize();
        end

        function setSensitivityAlgorithm(obj, algorithm)
            % Set the OpenSees sensitivity algorithm for static analysis.
            %
            % Parameters
            % ----------
            % algorithm : string
            %     "-computeAtEachStep" or "-computeByCommand".
            arguments
                obj
                algorithm (1,1) string {mustBeMember(algorithm, ["-computeAtEachStep","-computeByCommand"])}
            end
            obj.sensitivityAlgorithm = char(algorithm);
        end

        function setTotalSteps(obj, npts)
            % Reset and set total expected steps for progress tracking.
            %
            %   Calls reset() then sets npts. configure() is not required again.
            %
            % Parameters
            % ----------
            % npts : double
            %     Total expected steps; rounded to nearest integer.
            arguments
                obj
                npts (1,1) double {mustBeNonnegative, mustBeFinite}
            end
            obj.reset();
            obj.progress.npts = round(npts);
        end

        function segs = transientStepSplit(obj, npts)
            % Split transient analysis into step indices for progress tracking.
            %
            % Parameters
            % ----------
            % npts : double
            %     Number of transient steps.
            %
            % Returns
            % -------
            % segs : 1:npts row vector
            arguments
                obj
                npts (1,1) double {mustBeNonnegative, mustBeFinite}
            end
            npts = round(npts);
            obj.setTotalSteps(npts);
            segs = 1:npts;
        end

        function segs = staticStepSplit(obj, targets, maxStep)
            % Split displacement-control targets into bounded static steps.
            %
            % Parameters
            % ----------
            % targets : (:,1) double
            %     Target displacements. Scalar treated as [0; target].
            % maxStep : double, optional
            %     Maximum segment size. Default: |targets(2)-targets(1)|.
            %
            % Returns
            % -------
            % segs : column vector of displacement increments
            arguments
                obj
                targets (:,1) double
                maxStep (1,1) double {mustBeFinite} = NaN
            end

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
            if maxStep <= obj.eps_
                error('SmartAnalyze:InvalidInput', 'maxStep must be positive.');
            end

            d = diff(targets);
            d = d(abs(d) > obj.eps_);

            if isempty(d)
                segs = zeros(0,1);
                obj.setTotalSteps(0);
                return;
            end

            nFull = floor(abs(d) ./ maxStep);
            rems  = abs(d) - nFull .* maxStep;
            signs = sign(d);
            n     = sum(nFull) + sum(rems > obj.eps_);
            segs  = zeros(n,1);
            k = 1;
            for i = 1:numel(d)
                if nFull(i) > 0
                    segs(k:k+nFull(i)-1) = signs(i) * maxStep;
                    k = k + nFull(i);
                end
                if rems(i) > obj.eps_
                    segs(k) = signs(i) * rems(i);
                    k = k + 1;
                end
            end

            obj.setTotalSteps(numel(segs));
        end

        function ok = transientAnalyze(obj, dt)
            % Run one transient analysis step with automatic retry strategies.
            %
            % Parameters
            % ----------
            % dt : double
            %     Time-step size for ops.analyze(1, dt).
            %
            % Returns
            % -------
            % ok : 0 on success; negative on failure.
            arguments
                obj
                dt (1,1) double {mustBeFinite, mustBeReal}
            end
            obj.requireOps();
            if obj.analysisType ~= "Transient"
                error('SmartAnalyze:InvalidState', 'Analysis type is not Transient.');
            end
            obj.cfg.initialStep = dt;
            obj.ops.analysis('Transient');
            ok = obj.runAnalysis();
        end

        function ok = staticAnalyze(obj, nodeTag, dof, seg)
            % Run one displacement-control static analysis step with retries.
            %
            % Parameters
            % ----------
            % nodeTag : positive integer
            %     Node tag for DisplacementControl integrator.
            % dof : positive integer
            %     Degree of freedom for DisplacementControl integrator.
            % seg : double
            %     Displacement increment.
            %
            % Returns
            % -------
            % ok : 0 on success; negative on failure.
            arguments
                obj
                nodeTag (1,1) double {mustBeInteger, mustBePositive}
                dof     (1,1) double {mustBeInteger, mustBePositive}
                seg     (1,1) double {mustBeFinite, mustBeReal}
            end
            obj.requireOps();
            if obj.analysisType ~= "Static"
                error('SmartAnalyze:InvalidState', 'Analysis type is not Static.');
            end
            obj.cfg.initialStep  = seg;
            obj.progress.node    = nodeTag;
            obj.progress.dof     = dof;
            obj.progress.step    = seg;
            obj.ops.integrator("DisplacementControl", nodeTag, dof, seg);
            obj.ops.analysis('Static');
            obj.runSensitivity();
            ok = obj.runAnalysis();
        end

        function history = getNormHistory(obj)
            % Get convergence norm history as a struct array.
            %
            % Returns
            % -------
            % history : struct array with fields stepIndex, strategy, ok,
            %     firstNorm, lastNorm, minNorm, maxNorm, numIter,
            %     improvementRatio, isDiverging, isStagnating.
            %
            % Example
            % -------
            %     history = sa.getNormHistory();
            %     figure; semilogy([history.lastNorm], '.'); grid on;
            if ~obj.cfg.recordNormHistory
                warning('SmartAnalyze:HistoryDisabled', 'Norm history is not recorded.');
                history = struct([]);
                return;
            end
            n = numel(obj.normHistory.stepIndex);
            if n == 0
                warning('SmartAnalyze:HistoryEmpty', 'Norm history is empty.');
                history = struct([]);
                return;
            end
            % Convert struct-of-columns (SoC) → struct array (AoS) on demand.
            % SoC avoids O(n^2) copy cost during recording.
            history = struct( ...
                'stepIndex',        num2cell(obj.normHistory.stepIndex(:)), ...
                'strategy',         obj.normHistory.strategy(:), ...
                'ok',               num2cell(obj.normHistory.ok(:)), ...
                'firstNorm',        num2cell(obj.normHistory.firstNorm(:)), ...
                'lastNorm',         num2cell(obj.normHistory.lastNorm(:)), ...
                'minNorm',          num2cell(obj.normHistory.minNorm(:)), ...
                'maxNorm',          num2cell(obj.normHistory.maxNorm(:)), ...
                'numIter',          num2cell(obj.normHistory.numIter(:)), ...
                'improvementRatio', num2cell(obj.normHistory.improvementRatio(:)), ...
                'isDiverging',      num2cell(obj.normHistory.isDiverging(:)), ...
                'isStagnating',     num2cell(obj.normHistory.isStagnating(:)));
        end

        function diagnostics = getDiagnostics(obj)
            % Get failure diagnostics collected during analysis.
            %
            % Returns
            % -------
            % diagnostics : struct with fields records, lastFailure, maxRecords.
            %
            % Example
            % -------
            %     d = sa.getDiagnostics();
            %     sa.printLastFailure();
            if ~obj.cfg.recordDiagnostics
                warning('SmartAnalyze:DiagnosticsDisabled', 'Diagnostics are not recorded.');
                diagnostics = [];
                return;
            end
            head   = obj.diagnostics.head;
            maxRec = obj.diagnostics.maxRecords;
            all_   = obj.diagnostics.records;

            if head == 0
                filled = {};
            elseif head <= maxRec && isempty(all_{maxRec})
                filled = all_(1:head);
            else
                idx    = mod((head : head + maxRec - 1), maxRec) + 1;
                filled = all_(idx);
                filled = filled(~cellfun('isempty', filled));
            end

            diagnostics = struct( ...
                'records',     {filled}, ...
                'lastFailure', obj.diagnostics.lastFailure, ...
                'maxRecords',  maxRec);
        end

        function printLastFailure(obj)
            % Print a concise diagnostic report for the most recent failure.
            %
            % Example
            % -------
            %     sa.printLastFailure();
            d = obj.getDiagnostics();
            if isempty(d) || ~isfield(d, 'lastFailure') || isempty(d.lastFailure)
                fprintf('%s No failed attempt has been recorded.\n', obj.logo);
                return;
            end
            r = d.lastFailure;
            fprintf('%s Last failure diagnostic ❌\n', obj.logo);
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
                fprintf('    Partial step : advanced %.6e before failure\n', ...
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
    end

    % -----------------------------------------------------------------------
    % Private implementation methods
    % -----------------------------------------------------------------------
    methods (Access = private)

        function requireOps(obj)
            if isempty(obj.ops)
                error('SmartAnalyze:OpsNotSet', ...
                    'Call setOPS(ops) first. Done automatically via opsmat.anlys.smartAnalyze.');
            end
        end

        function t = elapsed(obj)
            t = toc(obj.progress.tic);
        end

        function runSensitivity(obj)
            if ~isempty(obj.sensitivityAlgorithm)
                obj.ops.sensitivityAlgorithm(obj.sensitivityAlgorithm);
            end
        end

        % --- Main retry orchestrator ----------------------------------------
        function ok = runAnalysis(obj)
            step    = obj.cfg.initialStep;
            verbose = obj.debugMode;

            ok = obj.analyzeOne(step, verbose, "initial");
            if ok < 0, ok = obj.tryAddTestTimes(step, verbose);  end
            if ok < 0, ok = obj.tryAlterAlgo(step, verbose);     end
            if ok < 0, ok = obj.tryAlterTestTypes(step, verbose); end
            if ok < 0, ok = obj.tryLooseTol(step, verbose);      end
            if ok < 0 && obj.cfg.tryRelaxStep
                ok = obj.tryRelaxStep(step, verbose);
            end

            if ok < 0
                obj.printStatus(false);
                if verbose, obj.printLastFailure(); end
                return;
            end

            obj.progress.done    = obj.progress.done + 1;
            obj.progress.counter = obj.progress.counter + 1;

            if verbose && obj.progress.counter >= obj.cfg.printPer
                obj.printProgress();
                obj.progress.counter = 0;
            end

            % Fire completion message exactly once.
            if obj.progress.npts > 0 && obj.progress.done == obj.progress.npts
                obj.printStatus(true);
                obj.progress.npts = 0;
            end

            ok = 0;
        end

        % --- Single increment -----------------------------------------------
        function ok = analyzeOne(obj, step, verbose, strategy)
            % Execute one analysis increment and record convergence norm data.
            %
            % ops.testNorm() returns a vector of length testIterTimes. The first
            % testIter entries hold per-iteration convergence norms; the remainder
            % are zero-padded. The buffer is NOT cleared on return from analyze(),
            % so a single post-solve sample captures the full iteration history.
            if nargin < 4 || strlength(string(strategy)) == 0
                strategy = "analyzeOne";
            end

            if obj.analysisType == "Static"
                obj.ops.integrator("DisplacementControl", ...
                    obj.progress.node, obj.progress.dof, step);
                obj.runSensitivity();
                ok = obj.ops.analyze(1);
            else
                ok = obj.ops.analyze(1, step);
            end

            norms = obj.sampleNorms();
            trend = obj.computeTrend(norms);
            obj.recordAttempt(strategy, step, ok, norms, trend);
        end

        % --- Retry strategies -----------------------------------------------
        function ok = tryAddTestTimes(obj, step, verbose)
            ok = -1;
            if ~obj.cfg.tryAddTestTimes, return; end
            nrm = obj.lastNorm_();
            if ~(isfinite(nrm) && nrm < obj.cfg.normTol)
                if verbose
                    fprintf('%s Not adding test times for norm %.3e.\n', obj.logo, nrm);
                end
                return;
            end
            for n = obj.cfg.testIterTimesMore
                if verbose, fprintf('%s Adding test times to %d. ✳️\n', obj.logo, n); end
                obj.ops.test(obj.cfg.testType, obj.cfg.testTol, n, obj.cfg.testPrintFlag);
                obj.setCurrentTest(obj.cfg.testType, obj.cfg.testTol, n, obj.cfg.testPrintFlag);
                ok = obj.analyzeOne(step, verbose, sprintf('tryAddTestTimes:%d', n));
                if ok == 0, obj.applyTest(); return; end
            end
            obj.applyTest();
        end

        function ok = tryAlterAlgo(obj, step, verbose)
            ok = -1;
            if ~obj.cfg.tryAlterAlgoTypes || numel(obj.cfg.algoTypes) <= 1, return; end
            for a = obj.cfg.algoTypes(2:end)
                if verbose, fprintf('%s Setting algorithm to %d. ✳️\n', obj.logo, a); end
                obj.applyAlgorithm(a);
                ok = obj.analyzeOne(step, verbose, sprintf('tryAlterAlgo:%g', a));
                if ok == 0, return; end
            end
            obj.applyAlgorithm(obj.cfg.algoTypes(1));
        end

        function ok = tryAlterTestTypes(obj, step, verbose)
            ok = -1;
            if ~obj.cfg.tryAlterTestTypes || isempty(obj.cfg.testTypesMore), return; end
            for tt = obj.cfg.testTypesMore
                ttChar = char(tt);
                if verbose, fprintf('%s Switching test type to %s. ✳️\n', obj.logo, ttChar); end
                obj.ops.test(ttChar, obj.cfg.testTol, obj.cfg.testIterTimes, obj.cfg.testPrintFlag);
                obj.setCurrentTest(ttChar, obj.cfg.testTol, obj.cfg.testIterTimes, obj.cfg.testPrintFlag);
                ok = obj.analyzeOne(step, verbose, sprintf('tryAlterTestTypes:%s', ttChar));
                if ok == 0, obj.applyTest(); return; end
            end
            obj.applyTest();
        end

        function ok = tryLooseTol(obj, step, verbose)
            ok = -1;
            if ~obj.cfg.tryLooseTestTol || isempty(obj.cfg.looseTestTolTo), return; end
            for tol = obj.cfg.looseTestTolTo
                if verbose, fprintf('%s Loosing test tolerance to %.3e. ✳️\n', obj.logo, tol); end
                obj.ops.test(obj.cfg.testType, tol, obj.cfg.testIterTimes, obj.cfg.testPrintFlag);
                obj.setCurrentTest(obj.cfg.testType, tol, obj.cfg.testIterTimes, obj.cfg.testPrintFlag);
                ok = obj.analyzeOne(step, verbose, sprintf('tryLooseTol:%.3e', tol));
                if ok == 0, obj.applyTest(); return; end
            end
            obj.applyTest();
        end

        function ok = tryRelaxStep(obj, step, verbose)
            ok = -1;
            if ~obj.cfg.tryRelaxStep, return; end

            alpha    = abs(obj.cfg.relaxation);
            minStep  = abs(obj.cfg.minStep);
            remain   = step;
            stepTry  = step * alpha;
            completed = 0.0;

            if verbose
                fprintf('%s Dividing current step %.3e into %.3e and %.3e. ✳️\n', ...
                    obj.logo, step, stepTry, step - stepTry);
            end

            while abs(remain) > obj.eps_
                if abs(stepTry) < minStep
                    if abs(completed) > obj.eps_
                        obj.flagPartialAdvance(step, completed, remain, stepTry, "minStepReached");
                    end
                    if verbose
                        fprintf('%s Current step %.3e is below minStep %.3e. ❌\n', ...
                            obj.logo, stepTry, minStep);
                        if abs(completed) > obj.eps_
                            fprintf('%s Partially advanced %.3e before failure. Remaining: %.3e. ⚠️\n', ...
                                obj.logo, completed, remain);
                        end
                    end
                    return;
                end

                if abs(stepTry) > abs(remain), stepTry = remain; end

                ok = obj.analyzeOne(stepTry, verbose, "tryRelaxStep");

                if ok == 0
                    remain    = remain - stepTry;
                    completed = step - remain;
                    stepTry   = remain;
                    if verbose
                        fprintf('%s Total %.3e, completed %.3e, remaining %.3e. ✳️\n', ...
                            obj.logo, step, completed, remain);
                    end
                else
                    stepTry = stepTry * alpha;
                    if verbose
                        fprintf('%s Dividing failed substep to %.3e. ✳️\n', obj.logo, stepTry);
                    end
                end
            end
        end

        % --- Test / algorithm helpers ---------------------------------------
        function applyTest(obj)
            obj.ops.test(obj.cfg.testType, obj.cfg.testTol, ...
                         obj.cfg.testIterTimes, obj.cfg.testPrintFlag);
            obj.setCurrentTest(obj.cfg.testType, obj.cfg.testTol, ...
                               obj.cfg.testIterTimes, obj.cfg.testPrintFlag);
        end

        function setCurrentTest(obj, testType, testTol, testIterTimes, testPrintFlag)
            obj.currentTestType      = testType;
            obj.currentTestTol       = testTol;
            obj.currentTestIterTimes = testIterTimes;
            obj.currentTestPrintFlag = testPrintFlag;
        end

        function applyAlgorithm(obj, algotype)
            args = analysis.SmartAnalyze.resolveAlgoArgs(algotype, obj.cfg.UserAlgoArgs);
            if obj.debugMode
                fprintf('%s Setting algorithm to %s ✳️\n', obj.logo, ...
                    strjoin(cellfun(@analysis.SmartAnalyze.toText, args, 'UniformOutput', false), ' '));
            end
            obj.ops.algorithm(args{:});
            obj.currentAlgorithmType = algotype;
            obj.currentAlgorithmArgs = args;
        end

        % --- Norm helpers ---------------------------------------------------
        function norms = sampleNorms(obj)
            % Strip trailing zeros from the testNorm() buffer.
            norms = zeros(0,1);
            try
                a = obj.ops.testNorm();
                if isempty(a), return; end
                a = double(a(:));
                idx = find(a ~= 0, 1, 'last');
                if isempty(idx), return; end
                norms = a(1:idx);
            catch
            end
        end

        function n = lastNorm_(obj)
            % Last finite norm from the most recent step.
            a = obj.lastNorms(isfinite(obj.lastNorms));
            if isempty(a), n = inf; else, n = a(end); end
        end

        % --- Recording ------------------------------------------------------
        function recordAttempt(obj, strategy, step, ok, norms, trend)
            obj.progress.step = step;
            obj.lastNorms     = norms;

            % Append to struct-of-columns norm history — O(1) amortised.
            if obj.cfg.recordNormHistory
                obj.normHistory.stepIndex(end+1,1)        = obj.progress.done + 1;
                obj.normHistory.strategy{end+1,1}         = char(string(strategy));
                obj.normHistory.ok(end+1,1)               = ok;
                obj.normHistory.firstNorm(end+1,1)        = trend.first;
                obj.normHistory.lastNorm(end+1,1)         = trend.last;
                obj.normHistory.minNorm(end+1,1)          = trend.min;
                obj.normHistory.maxNorm(end+1,1)          = trend.max;
                obj.normHistory.numIter(end+1,1)          = numel(norms);
                obj.normHistory.improvementRatio(end+1,1) = trend.improvementRatio;
                obj.normHistory.isDiverging(end+1,1)      = trend.isDiverging;
                obj.normHistory.isStagnating(end+1,1)     = trend.isStagnating;
            end

            if ok == 0, return; end  % success — skip expensive diagnostic path

            if obj.cfg.recordDiagnostics
                rec.timestamp     = char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss.SSS'));
                rec.stepIndex     = obj.progress.done + 1;
                rec.analysis      = char(obj.analysisType);
                rec.strategy      = char(string(strategy));
                rec.step          = step;
                rec.ok            = ok;
                rec.success       = false;
                rec.testType      = obj.currentTestType;
                rec.testTol       = obj.currentTestTol;
                rec.testIterTimes = obj.currentTestIterTimes;
                rec.testPrintFlag = obj.currentTestPrintFlag;
                rec.algorithmType = obj.currentAlgorithmType;
                rec.algorithmArgs = obj.currentAlgorithmArgs;
                rec.algorithmText = analysis.SmartAnalyze.algoText(obj.currentAlgorithmArgs);
                rec.norms         = norms;
                rec.trend         = trend;
                rec.reason        = analysis.SmartAnalyze.failureReason(ok, trend);
                rec.partialAdvance     = false;
                rec.partialAdvanceInfo = [];
                rec.suggestion    = analysis.SmartAnalyze.convergenceSuggestion(ok, trend, rec);

                maxRec = obj.diagnostics.maxRecords;
                obj.diagnostics.head = mod(obj.diagnostics.head, maxRec) + 1;
                obj.diagnostics.records{obj.diagnostics.head} = rec;
                obj.diagnostics.lastFailure = rec;
            end
        end

        function flagPartialAdvance(obj, totalStep, completedStep, remainingStep, failedSubstep, reason)
            if ~obj.cfg.recordDiagnostics || obj.diagnostics.head == 0, return; end
            info = struct('totalStep', totalStep, 'completedStep', completedStep, ...
                'remainingStep', remainingStep, 'failedSubstep', failedSubstep, ...
                'reason', char(string(reason)));
            rec = obj.diagnostics.records{obj.diagnostics.head};
            if isempty(rec), return; end
            rec.partialAdvance     = true;
            rec.partialAdvanceInfo = info;
            rec.reason    = sprintf('%s; partial model advancement detected', rec.reason);
            rec.suggestion = [rec.suggestion, ...
                ' Model state may be partially advanced; avoid whole-step retry.'];
            obj.diagnostics.records{obj.diagnostics.head} = rec;
            obj.diagnostics.lastFailure = rec;
        end

        % --- Print helpers --------------------------------------------------
        function printStatus(obj, success)
            t = obj.elapsed();
            if obj.progress.npts > 0
                pct  = min(100, 100 * obj.progress.done / obj.progress.npts);
                prog = sprintf(' Progress: %.3f %% (%d/%d).', pct, obj.progress.done, obj.progress.npts);
            else
                prog = sprintf(' Progress: %d steps.', obj.progress.done);
            end
            if success
                fprintf('%s Successfully finished!%s Time: %.3f s. 🎃\n', obj.logo, prog, t);
            else
                fprintf('%s Analyze failed.%s Time: %.3f s. ❌\n', obj.logo, prog, t);
            end
        end

        function printProgress(obj)
            t = obj.elapsed();
            if obj.progress.npts > 0
                pct = min(100, 100 * obj.progress.done / obj.progress.npts);
                fprintf('%s progress %.3f %% (%d/%d). Time: %.3f s. ✅\n', ...
                    obj.logo, pct, obj.progress.done, obj.progress.npts, t);
            else
                fprintf('%s progress %d steps. Time: %.3f s. ✅\n', ...
                    obj.logo, obj.progress.done, t);
            end
        end
    end

    % -----------------------------------------------------------------------
    % Static helpers — pure functions, no state
    % -----------------------------------------------------------------------
    methods (Static, Access = private)

        function c = defaultCfg()
            c = struct( ...
                'analysis',           'Transient', ...
                'testType',           'EnergyIncr', ...
                'testTol',            1e-10, ...
                'testIterTimes',      10, ...
                'testPrintFlag',      0, ...
                'tryAddTestTimes',    false, ...
                'normTol',            1e3, ...
                'testIterTimesMore',  50, ...
                'tryLooseTestTol',    false, ...
                'looseTestTolTo',     1e-8, ...
                'tryAlterTestTypes',  false, ...
                'testTypesMore',      {{'NormDispIncr','NormUnbalance','RelativeEnergyIncr'}}, ...
                'recordNormHistory',  true, ...
                'recordDiagnostics',  false, ...
                'tryAlterAlgoTypes',  false, ...
                'algoTypes',          [40 10 20 30 50 60 70 90], ...
                'UserAlgoArgs',       {{}}, ...
                'tryRelaxStep',       true, ...
                'initialStep',        [], ...
                'relaxation',         0.5, ...
                'minStep',            1e-6, ...
                'debugMode',          false, ...
                'printPer',           20);
            c.looseTestTolTo = 100 * c.testTol;
        end

        function nh = emptyNormHistory()
            nh = struct( ...
                'stepIndex',[], 'strategy',{{}}, 'ok',[], ...
                'firstNorm',[], 'lastNorm',[], 'minNorm',[], 'maxNorm',[], ...
                'numIter',[], 'improvementRatio',[], 'isDiverging',[], 'isStagnating',[]);
        end

        function d = emptyDiagnostics(maxRec)
            d = struct('records',{cell(maxRec,1)}, 'head',0, ...
                       'lastFailure',[], 'maxRecords',maxRec);
        end

        function p = emptyProgress()
            p = struct('tic',tic, 'counter',0, 'done',0, 'npts',0, ...
                       'step',0.0, 'node',0, 'dof',0);
        end

        function c = normalizeCfg(c)
            if ~ismember(string(c.analysis), ["Transient","Static"])
                error('SmartAnalyze:InvalidInput', 'analysis must be "Transient" or "Static".');
            end
            c.algoTypes = double(c.algoTypes(:)).';
            if isempty(c.algoTypes) || any(~isfinite(c.algoTypes))
                error('SmartAnalyze:InvalidInput', 'algoTypes must be a nonempty finite vector.');
            end
            t = double(c.testIterTimesMore(:)).';
            t = round(t(isfinite(t) & t > 0));
            if isempty(t), c.testIterTimesMore = 50; else, c.testIterTimesMore = t; end

            if isempty(c.UserAlgoArgs), c.UserAlgoArgs = {}; end
            if isempty(c.initialStep) || (isscalar(c.initialStep) && isnan(c.initialStep))
                c.initialStep = [];
            end

            t = double(c.looseTestTolTo(:)).';
            t = t(isfinite(t) & t > 0);
            if isempty(t), c.looseTestTolTo = 100*c.testTol; else, c.looseTestTolTo = t; end

            if ~iscell(c.testTypesMore)
                if ischar(c.testTypesMore) || isstring(c.testTypesMore)
                    c.testTypesMore = {char(c.testTypesMore)};
                else
                    c.testTypesMore = {};
                end
            end
            c.testTypesMore = c.testTypesMore(~cellfun('isempty', c.testTypesMore));
            c.recordNormHistory = logical(c.recordNormHistory);
            c.recordDiagnostics = logical(c.recordDiagnostics);
        end

        function trend = computeTrend(norms)
            norms = double(norms(:));
            trend = struct( ...
                'isEmpty',true, 'hasNaN',any(isnan(norms)), 'hasInf',any(isinf(norms)), ...
                'hasNonfinite',any(~isfinite(norms)), ...
                'first',NaN, 'last',NaN, 'min',NaN, 'max',NaN, ...
                'improvementRatio',NaN, 'isImproving',false, ...
                'isStagnating',false, 'isDiverging',false);
            fn = norms(isfinite(norms));
            if isempty(fn), return; end
            trend.isEmpty = false;
            trend.first   = fn(1);
            trend.last    = fn(end);
            trend.min     = min(fn);
            trend.max     = max(fn);
            denom = max(abs(trend.first), eps);
            trend.improvementRatio = abs(trend.last) / denom;
            trend.isImproving  = trend.improvementRatio < 0.5;
            trend.isDiverging  = numel(fn) >= 2 && abs(trend.last) > abs(trend.first);
            if numel(fn) >= 3
                r = fn(max(1,end-2):end);
                rc = abs(diff(r)) ./ max(abs(r(1:end-1)), eps);
                trend.isStagnating = all(rc < 1e-3);
            end
        end

        function reason = failureReason(ok, trend)
            if ok == 0,              reason = 'converged';                                        return; end
            if trend.hasNonfinite,   reason = 'nonfinite convergence norm detected';              return; end
            if trend.isEmpty,        reason = 'convergence norm unavailable';                     return; end
            if trend.isDiverging,    reason = 'convergence norm is diverging';                    return; end
            if trend.isStagnating,   reason = 'convergence norm is stagnating';                   return; end
            if trend.isImproving,    reason = 'convergence norm improving but did not converge';  return; end
            reason = 'analysis command returned a failure code';
        end

        function s = convergenceSuggestion(ok, trend, rec)
            if ok == 0, s = 'No action needed.'; return; end
            if trend.hasNonfinite
                s = 'NaN/Inf norms detected. Reduce step size, check material limits, use line-search.';
            elseif trend.isEmpty
                s = 'No norms available. Enable test print, check system/integrator setup.';
            elseif trend.isDiverging
                s = 'Norm growing. Try smaller step, NewtonLineSearch, or KrylovNewton.';
            elseif trend.isStagnating
                s = 'Norm stagnating. Change test type, algorithm, or reduce step size.';
            elseif trend.isImproving
                s = 'Norm decreasing but insufficient. Increase testIterTimes or loosen testTol.';
            elseif contains(rec.strategy, 'tryRelaxStep')
                s = 'Step relaxation failed. Reduce step size or decrease minStep.';
            elseif contains(rec.strategy, 'tryAlterAlgo')
                s = 'Algorithm switching failed. Add more candidates (NewtonLineSearch, BFGS).';
            elseif contains(rec.strategy, 'tryLooseTol')
                s = 'Loose tolerance failed. Try smaller steps or different algorithm/test type.';
            else
                s = 'Enable tryAddTestTimes, tryAlterAlgoTypes, tryLooseTestTol and inspect norm trend.';
            end
        end

        function args = resolveAlgoArgs(algotype, userArgs)
            % Resolve an algorithm type code to its OpenSees argument cell array.
            % The map is built once and cached in a persistent variable.
            persistent m
            if isempty(m)
                m = analysis.SmartAnalyze.buildAlgoMap();
            end
            if algotype == 100
                if isempty(userArgs)
                    error('SmartAnalyze:InvalidInput', 'UserAlgoArgs required for algorithm type 100.');
                end
                args = userArgs;
            elseif m.isKey(algotype)
                args = m(algotype);
            else
                error('SmartAnalyze:InvalidInput', 'Unknown algorithm type: %g', algotype);
            end
        end

        function txt = algoText(args)
            if isempty(args), txt = '<unset>'; return; end
            txt = strjoin(cellfun(@analysis.SmartAnalyze.toText, args, 'UniformOutput', false), ' ');
        end

        function s = toText(x)
            if ischar(x) || isstring(x), s = char(string(x));
            elseif isnumeric(x) && isscalar(x), s = num2str(x);
            else, s = '<arg>';
            end
        end

        function m = buildAlgoMap()
            % Build the algorithm lookup table once at class-load time.
            m = containers.Map('KeyType','double','ValueType','any');
            m(0)  = {'Linear'};
            m(1)  = {'Linear','-Initial'};
            m(2)  = {'Linear','-Secant'};
            m(3)  = {'Linear','-FactorOnce'};
            m(4)  = {'Linear','-Initial','-FactorOnce'};
            m(5)  = {'Linear','-Secant','-FactorOnce'};
            m(10) = {'Newton'};
            m(11) = {'Newton','-Initial'};
            m(12) = {'Newton','-initialThenCurrent'};
            m(13) = {'Newton','-Secant'};
            m(20) = {'NewtonLineSearch'};
            m(21) = {'NewtonLineSearch','-type','Bisection'};
            m(22) = {'NewtonLineSearch','-type','Secant'};
            m(23) = {'NewtonLineSearch','-type','RegulaFalsi'};
            m(24) = {'NewtonLineSearch','-type','LinearInterpolated'};
            m(25) = {'NewtonLineSearch','-type','InitialInterpolated'};
            m(30) = {'ModifiedNewton'};
            m(31) = {'ModifiedNewton','-initial'};
            m(32) = {'ModifiedNewton','-secant'};
            m(40) = {'KrylovNewton'};
            m(41) = {'KrylovNewton','-iterate','initial'};
            m(42) = {'KrylovNewton','-increment','initial'};
            m(43) = {'KrylovNewton','-iterate','initial','-increment','initial'};
            m(44) = {'KrylovNewton','-maxDim',10};
            m(45) = {'KrylovNewton','-iterate','initial','-increment','initial','-maxDim',10};
            m(50) = {'SecantNewton'};
            m(51) = {'SecantNewton','-iterate','initial'};
            m(52) = {'SecantNewton','-increment','initial'};
            m(53) = {'SecantNewton','-iterate','initial','-increment','initial'};
            m(60) = {'BFGS'};
            m(61) = {'BFGS','-initial'};
            m(62) = {'BFGS','-secant'};
            m(70) = {'Broyden'};
            m(71) = {'Broyden','-initial'};
            m(72) = {'Broyden','-secant'};
            m(80) = {'PeriodicNewton'};
            m(81) = {'PeriodicNewton','-maxDim',10};
            m(90) = {'ExpressNewton'};
            m(91) = {'ExpressNewton','-InitialTangent'};
        end
    end
end
