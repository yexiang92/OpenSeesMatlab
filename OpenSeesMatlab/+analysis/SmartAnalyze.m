classdef SmartAnalyze
    % SmartAnalyze provides utilities for managing and running smart analysis strategies in OpenSeesMatlab. It is designed to be used in conjunction with the OpenSeesMatlabAnalysis class, which holds an instance of SmartAnalyze for analysis management.
    %
    % Example
    % --------
    %     % for transient analysis with automatic retries and adjustments
    %     SmartAnalyze.configure(...
    %         analysis="Transient", ...
    %         tryAlterAlgoTypes=true, ...
    %         algoTypes=[40 10], ...
    %         tryAddTestTimes=true, ...
    %         testIterTimesMore=50, ...
    %         debugMode=true);
    %
    %     segs = SmartAnalyze.transientStepSplit(1000);
    %     for i = 1:numel(segs)
    %         SmartAnalyze.TransientAnalyze(0.01);
    %     end
    %     SmartAnalyze.reset();  % reset to default state if needed for another analysis
    %
    %     %     % for static analysis with automatic retries and adjustments
    %     SmartAnalyze.configure(...
    %         analysis="Static", ...
    %         tryAlterAlgoTypes=true, ...
    %         algoTypes=[40 10], ...
    %         tryAddTestTimes=true, ...
    %         testIterTimesMore=50, ...
    %         debugMode=true);
    %     targets = [0; 1.0];  % target displacement values for the static analysis
    %     segs = SmartAnalyze.staticStepSplit(targets, maxStep=0.1);
    %     for i = 1:numel(segs)
    %         SmartAnalyze.staticAnalyze(nodeTag, dof, segs(i));
    %     end
    %     SmartAnalyze.reset();  % reset to default state if needed for another analysis

    properties (Constant)
        % Logo for printing messages
        logo = "OPSTOOL::SmartAnalyze::"
    end

    methods (Static)
        function setOPS(ops)
            arguments
                ops
            end
            s = analysis.SmartAnalyze.state();
            s.ops = ops;
            analysis.SmartAnalyze.state(s);
        end

        function configure(opts)
            % Configure the analysis settings.
            %
            % Parameters
            % ----------
            % analysis : string, optional
            %     Type of analysis, either "Transient" or "Static". Default is "Transient".
            % testType : string, optional
            %     Type of test for convergence, e.g., "EnergyIncr". Default is "EnergyIncr".
            % testTol : double, optional
            %     Tolerance for the test. Default is 1e-10.
            % testIterTimes : double, optional
            %     Number of iterations for the test. Default is 10.
            % testPrintFlag : double, optional
            %     Print flag for the test. Default is 0.
            % tryAddTestTimes : logical, optional
            %     Whether to try adding test times when convergence fails. Default is false.
            % normTol : double, optional
            %     Norm tolerance for deciding when to try adding test times. Default is 1e3.
            % testIterTimesMore : double, optional
            %     Additional iteration times to try when adding test times. Default is 50.
            % tryLooseTestTol : logical, optional
            %     Whether to try loosening the test tolerance when convergence fails. Default is false.
            % looseTestTolTo : double, optional
            %     The looser test tolerance to try. Default is 100 times the original testTol.
            % tryAlterAlgoTypes : logical, optional
            %     Whether to try altering algorithm types when convergence fails. Default is false.
            % algoTypes : double array, optional
            %     Algorithm types to try in order when altering algorithms. Default is [40 10].
            %     Optional:
            %     
            %     - 0: Linear
            %     - 1: {'Linear','-Initial'}
            %     - 2: {'Linear','-Secant'}
            %     - 3: {'Linear','-FactorOnce'}
            %     - 4: {'Linear','-Initial','-FactorOnce'}
            %     - 5: {'Linear','-Secant','-FactorOnce'}
            %     - 10: {'Newton'}
            %     - 11: {'Newton','-Initial'}
            %     - 12: {'Newton','-intialThenCurrent'}
            %     - 13: {'Newton','-Secant'}
            %     - 20: {'NewtonLineSearch'}
            %     - 21: {'NewtonLineSearch','-type','Bisection'}
            %     - 22: {'NewtonLineSearch','-type','Secant'}
            %     - 23: {'NewtonLineSearch','-type','RegulaFalsi'}
            %     - 24: {'NewtonLineSearch','-type','LinearInterpolated'}
            %     - 25: {'NewtonLineSearch','-type','InitialInterpolated'}
            %     - 30: {'ModifiedNewton'}
            %     - 31: {'ModifiedNewton','-initial'}
            %     - 32: {'ModifiedNewton','-secant'}  
            %     - 40: {'KrylovNewton'}
            %     - 41: {'KrylovNewton','-iterate','initial'}
            %     - 42: {'KrylovNewton','-increment','initial'}
            %     - 43: {'KrylovNewton','-iterate','initial','-increment','initial'}
            %     - 44: {'KrylovNewton','-maxDim',10}
            %     - 45: {'KrylovNewton','-iterate','initial','-increment','initial','-maxDim',10}
            %     - 50: {'SecantNewton'}
            %     - 51: {'SecantNewton','-iterate','initial'}
            %     - 52: {'SecantNewton','-increment','initial'}
            %     - 53: {'SecantNewton','-iterate','initial','-increment','initial'}
            %     - 60: {'BFGS'}
            %     - 61: {'BFGS','-initial'}
            %     - 62: {'BFGS','-secant'}
            %     - 70: {'Broyden'}
            %     - 71: {'Broyden','-initial'}
            %     - 72: {'Broyden','-secant'}
            %     - 80: {'PeriodicNewton'}
            %     - 81: {'PeriodicNewton','-maxDim',10}
            %     - 90: {'Secant'}
            %     - 100: User-defined, in which case UserAlgoArgs must be provided to specify the arguments for the algorithm command.
            % UserAlgoArgs : cell array, optional
            %     User-defined algorithm arguments when algoTypes includes 100. Default is {}.
            % initialStep : double, optional
            %     Initial step size for the analysis. Default is NaN (not set).
            % relaxation : double, optional
            %     Relaxation factor for step size when trying to relax steps. Default is 0.5.
            % minStep : double, optional
            %     Minimum step size when trying to relax steps. Default is 1e-6.
            % debugMode : logical, optional
            %     Whether to enable debug mode for verbose output. Default is false.
            % printPer : double, optional
            %     Print progress every this many steps. Default is 20.

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
                opts.tryAlterAlgoTypes = []
                opts.algoTypes double = NaN
                opts.UserAlgoArgs cell = {}
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
            % Set the sensitivity algorithm for the analysis. This will be used when running sensitivity analysis in StaticAnalyze.
            arguments
                algorithm (1,1) string {mustBeMember(algorithm, ["-computeAtEachStep","-computeByCommand"])}
            end
            s = analysis.SmartAnalyze.state();
            s.sensitivityAlgorithm = char(algorithm);
            analysis.SmartAnalyze.state(s);
        end

        function segs = transientStepSplit(npts)
            % Split the transient analysis into npts segments. This is a simple utility to set the number of steps for progress tracking.
            %
            % Parameters
            % ----------
            % npts : double
            %     Number of points (steps) to split the transient analysis into. Must be a nonnegative integer.
            %
            % Returns
            % -------
            % segs : double array
            %     Array of step sizes for each segment. For transient analysis, this will be an array of 1's with length npts, indicating that each segment corresponds to one step in the transient analysis.
            arguments
                npts (1,1) double {mustBeNonnegative, mustBeFinite}
            end
            npts = round(npts);
            s = analysis.SmartAnalyze.state();
            s.progress.npts = npts;
            analysis.SmartAnalyze.state(s);
            segs = 1:npts;
        end

        function segs = staticStepSplit(targets, maxStep)
            % Split the static analysis into segments based on target values and maximum step size. This utility generates a sequence of steps that will be taken in the StaticAnalyze method, ensuring that the steps do not exceed maxStep and that the targets are reached.
            %
            % Parameters
            % ----------
            % targets : double array
            %     Target values for the static analysis. Can be a scalar or a vector. If scalar, it will be treated as [0; target].
            % maxStep : double, optional
            %     Maximum step size for the analysis. Default is NaN, which means it will
            %     be set to the absolute difference between the first two targets or the target itself if only one target is provided.
            % 
            % Returns
            % -------
            % segs : double array
            %     Array of step sizes for each segment in the static analysis. The sum of segs will equal the difference between the last and first target, and no individual step will exceed maxStep in absolute value.
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
                s.progress.npts = 0;
                analysis.SmartAnalyze.state(s);
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

            s.progress.npts = numel(segs);
            analysis.SmartAnalyze.state(s);
        end

        function ok = transientAnalyze(dt)
            % Perform a transient analysis step with the given time step size. This method will automatically handle retries and adjustments if the analysis fails to converge, based on the configuration set in the configure method.
            %
            % Parameters
            % ----------
            % dt : double
            %     Time step size for the transient analysis. Must be a positive finite number.
            %
            % Returns
            % -------
            % ok : double
            %     0 if the analysis step was successful, <0 if it failed. The method will attempt retries and adjustments according to the configuration, and will return -1 only if all attempts fail.
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
            % Perform a static analysis step with displacement control on the specified node and degree of freedom, using the given step size. This method will automatically handle retries and adjustments if the analysis fails to converge, based on the configuration set in the configure method.
            %
            % Parameters
            % ----------
            % nodeTag : double
            %     Node tag for displacement control. Must be a positive integer.
            % dof : double
            %     Degree of freedom for displacement control. Must be a positive integer.
            % seg : double
            %     Step size for the displacement control. Must be a finite real number.
            %
            % Returns
            % -------
            % ok : double
            %     0 if the analysis step was successful, <0 if it failed. The method will attempt retries and adjustments according to the configuration, and will return -1 only if all attempts fail.
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
            % Get the current internal state of SmartAnalyze. This can be useful for debugging or for advanced users who want to inspect the state directly.
            %
            % Returns
            % -------
            % s : struct
            %     The current internal state of SmartAnalyze.

            s = analysis.SmartAnalyze.state();
        end
    end

    methods (Static, Access = private)
        function s = defaultState()
            s = struct();
            s.ops = [];
            s.analysis = "Transient";
            s.debug = false;
            s.eps = 1e-12;
            s.logFile = ".SmartAnalyze-OpenSees.log";
            s.logo = "OPSTOOL::SmartAnalyze::";
            s.sensitivityAlgorithm = '';

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
                'tryAlterAlgoTypes', false, ...
                'algoTypes',         [40 10 20 30 50 60 70 90], ...
                'UserAlgoArgs',      {{}}, ...
                'initialStep',       [], ...
                'relaxation',        0.5, ...
                'minStep',           1e-6, ...
                'debugMode',         false, ...
                'printPer',          20);

            s.cfg.looseTestTolTo = 100 * s.cfg.testTol;

            s.progress = struct( ...
                'tic',      tic, ...
                'counter',  0, ...
                'done',     0, ...
                'npts',     0, ...
                'step',     0.0, ...
                'node',     0, ...
                'dof',      0);
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

            s.debug = logical(s.cfg.debugMode);
        end

        function s = requireOps()
            s = analysis.SmartAnalyze.state();
            if isempty(s.ops)
                error('SmartAnalyze:OpsNotSet', ...
                    'Call SmartAnalyze.setOps(ops) first.');
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

            ok = analysis.SmartAnalyze.analyzeOne(step, verbose);
            if ok < 0, ok = analysis.SmartAnalyze.tryAddTestTimes(step, verbose); end
            if ok < 0, ok = analysis.SmartAnalyze.tryAlterAlgo(step, verbose); end
            if ok < 0, ok = analysis.SmartAnalyze.tryRelaxStep(step, verbose); end
            if ok < 0, ok = analysis.SmartAnalyze.tryLooseTol(step, verbose); end

            if ok < 0
                analysis.SmartAnalyze.printStatus(false);
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
            if success
                fprintf('>>>🎃 %s Successfully finished! Time consumption: %.3f s.\n', s.logo, t);
            else
                fprintf('>>>❌ %s Analyze failed. Time consumption: %.3f s.\n', s.logo, t);
            end
        end

        function printProgress()
            s = analysis.SmartAnalyze.state();
            t = analysis.SmartAnalyze.elapsed();
            if s.progress.npts > 0
                fprintf('>>>✅ %s progress %.3f %% . Time consumption: %.3f s.\n', ...
                    s.logo, 100 * s.progress.done / s.progress.npts, t);
            else
                fprintf('>>>✅ %s progress %d steps. Time consumption: %.3f s.\n', ...
                    s.logo, s.progress.done, t);
            end
        end

        function ok = analyzeOne(step, verbose)
            s = analysis.SmartAnalyze.state();

            if s.analysis == "Static"
                s.ops.integrator("DisplacementControl", ...
                    s.progress.node, s.progress.dof, step);
                analysis.SmartAnalyze.runSensitivity();
            end

            if ~verbose
                try
                    s.ops.logFile(s.logFile, '-noEcho');
                catch
                end
            end

            if s.analysis == "Static"
                ok = s.ops.analyze(1);
            else
                ok = s.ops.analyze(1, step);
            end

            s = analysis.SmartAnalyze.state();
            s.progress.step = step;
            analysis.SmartAnalyze.state(s);
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
                ok = analysis.SmartAnalyze.analyzeOne(step, verbose);
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
                ok = analysis.SmartAnalyze.analyzeOne(step, verbose);
                if ok == 0
                    return;
                end
            end

            analysis.SmartAnalyze.setAlgorithm(s.cfg.algoTypes(1));
        end

        function ok = tryRelaxStep(step, verbose)
            s = analysis.SmartAnalyze.state();
            alpha   = abs(s.cfg.relaxation);
            minStep = abs(s.cfg.minStep);

            remain = step;
            stepTry = step * alpha;
            ok = -1;

            if verbose
                fprintf('>>>✳️ %s Dividing current step %.3e into %.3e and %.3e.\n', ...
                    s.logo, step, stepTry, step - stepTry);
            end

            while abs(remain) > s.eps
                if abs(stepTry) < minStep
                    if verbose
                        fprintf('>>>❌ %s Current step %.3e is below minStep %.3e.\n', ...
                            s.logo, stepTry, minStep);
                    end
                    return;
                end

                if abs(stepTry) > abs(remain)
                    stepTry = remain;
                end

                ok = analysis.SmartAnalyze.analyzeOne(stepTry, verbose);

                if ok == 0
                    remain = remain - stepTry;
                    stepTry = remain;
                    if verbose
                        fprintf('>>>✳️ %s Total step %.3e, completed %.3e, remaining %.3e.\n', ...
                            s.logo, step, step - remain, remain);
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

        function ok = tryLooseTol(step, verbose)
            s = analysis.SmartAnalyze.state();
            ok = -1;
            if ~s.cfg.tryLooseTestTol
                return;
            end

            if verbose
                fprintf('>>>✳️ %s Loosing test tolerance to %.3e.\n', ...
                    s.logo, s.cfg.looseTestTolTo);
            end

            s.ops.test(s.cfg.testType, s.cfg.looseTestTolTo, ...
                       s.cfg.testIterTimes, s.cfg.testPrintFlag);

            ok = analysis.SmartAnalyze.analyzeOne(step, verbose);
            analysis.SmartAnalyze.setTest();
        end

        function setTest()
            s = analysis.SmartAnalyze.state();
            s.ops.test(s.cfg.testType, s.cfg.testTol, ...
                       s.cfg.testIterTimes, s.cfg.testPrintFlag);
        end

        function setAlgorithm(algotype)
            s = analysis.SmartAnalyze.state();
            args = analysis.SmartAnalyze.algorithmArgs(algotype, s.cfg.UserAlgoArgs);

            if s.debug
                fprintf('>>>✳️ %s Setting algorithm to %s\n', ...
                    s.logo, strjoin(cellfun(@analysis.SmartAnalyze.toText, args, 'UniformOutput', false), ' '));
            end

            s.ops.algorithm(args{:});
        end

        function n = lastNorm()
            s = analysis.SmartAnalyze.state();
            n = inf;
            try
                a = s.ops.testNorm();
                if isempty(a)
                    return;
                end
                a = double(a(:));
                a = a(isfinite(a));
                if ~isempty(a)
                    n = a(end);
                end
            catch
                n = inf;
            end
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
                case 12, args = {'Newton','-intialThenCurrent'};
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