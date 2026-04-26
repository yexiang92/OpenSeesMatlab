classdef OpenSeesMatlabAnalysis < handle
    % Analysis management interface for OpenSeesMatlab.
    %
    %   OpenSeesMatlabAnalysis groups analysis-related helpers used by the main
    %   OpenSeesMatlab object. It currently exposes SmartAnalyze, a robust
    %   analysis utility that can run transient and displacement-control static
    %   analyses with automatic convergence-recovery strategies.
    %
    %   Users normally do not construct this class directly. It is created by
    %   OpenSeesMatlab and accessed through the anlys property:
    %
    %       opsmat = OpenSeesMatlab();
    %       smartAnalyze = opsmat.anlys.smartAnalyze;
    %
    %   The constructor automatically connects SmartAnalyze to the OpenSees
    %   command interface stored in opsmat.opensees, so users can call
    %   smartAnalyze.configure, smartAnalyze.transientAnalyze, and
    %   smartAnalyze.staticAnalyze without manually calling setOPS.
    %
    % Example
    % -------
    %       opsmat = OpenSeesMatlab();
    %       ops = opsmat.opensees;
    %       smartAnalyze = opsmat.anlys.smartAnalyze;
    %
    %       % Build model with ops...
    %       % ops.wipe();
    %       % ops.model(...);
    %
    %       smartAnalyze.configure(...
    %           analysis="Transient", ...
    %           testType="EnergyIncr", ...
    %           testTol=1e-10, ...
    %           testIterTimes=10, ...
    %           testPrintFlag=0, ...
    %           tryAddTestTimes=true, ...
    %           normTol=1e3, ...
    %           testIterTimesMore=[50 100], ...
    %           tryLooseTestTol=true, ...
    %           looseTestTolTo=1e-8, ...
    %           tryAlterAlgoTypes=true, ...
    %           algoTypes=[40 10 20 30], ...
    %           UserAlgoArgs={}, ...
    %           initialStep=0.01, ...
    %           relaxation=0.5, ...
    %           minStep=1e-6, ...
    %           debugMode=true, ...
    %           printPer=20);
    %
    %       smartAnalyze.setTotalSteps(1000);
    %       for i = 1:1000
    %           ok = smartAnalyze.transientAnalyze(0.01);
    %           if ok < 0
    %               error("Transient analysis failed at step %d.", i);
    %           end
    %       end

    properties (SetAccess = private, GetAccess = private)
        parent  % Reference to the parent OpenSeesMatlab object
    end

    properties (SetAccess = private, GetAccess = public)
        smartAnalyze = analysis.SmartAnalyze  % Robust analysis helper for convergence recovery and progress tracking
    end

    methods
        function obj = OpenSeesMatlabAnalysis(parentObj)
            % Construct an OpenSeesMatlabAnalysis object.
            %
            %   The constructor stores the parent OpenSeesMatlab object and binds
            %   SmartAnalyze to parentObj.opensees. This binding is required
            %   because SmartAnalyze applies OpenSees commands such as test,
            %   algorithm, analysis, integrator, and analyze.
            %
            % Parameters
            % ----------
            % parentObj : OpenSeesMatlab
            %     Parent OpenSeesMatlab object. The analysis manager uses
            %     parentObj.opensees as the OpenSees command interface for
            %     SmartAnalyze.
            %
            % Example
            % -------
            %     opsmat = OpenSeesMatlab();
            %     anlys = opsmat.anlys;
            %     smartAnalyze = anlys.smartAnalyze;

            arguments
                parentObj (1,1) OpenSeesMatlab
            end

            obj.parent = parentObj;
            obj.smartAnalyze.setOPS(obj.parent.opensees);
        end
    end

end
