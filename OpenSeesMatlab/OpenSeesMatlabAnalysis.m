classdef OpenSeesMatlabAnalysis < handle
    % Analysis management interface for OpenSeesMatlab.
    %
    %   OpenSeesMatlabAnalysis groups analysis-related helpers used by the main
    %   OpenSeesMatlab object.
    %

    properties (SetAccess = private, GetAccess = private)
        parent  % Reference to the parent OpenSeesMatlab object
    end

    properties (SetAccess = private, GetAccess = public)
        smartAnalyze = analysis.SmartAnalyze()  % Robust analysis helper for convergence recovery and progress tracking
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
