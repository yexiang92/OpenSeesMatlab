classdef OpenSeesMatlabAnalysis < handle
    % Analysis management for OpenSeesMatlab.
    %
    %   This class manages the analysis process for OpenSeesMatlab, including
    %   running analyses, managing analysis state, and providing utilities for
    %   smart analysis strategies. It is designed to work closely with the main
    %   OpenSeesMatlab interface and the post-processing tools.

    properties (SetAccess = private, GetAccess = private)
        parent  % Reference to the parent OpenSeesMatlab object
    end

    properties (SetAccess = private, GetAccess = public)
        smartAnalyze = analysis.SmartAnalyze  % Smart analysis manager
    end

    methods
        function obj = OpenSeesMatlabAnalysis(parentObj)
            % Construct an OpenSeesMatlabAnalysis object.
            %
            % Parameters
            % ----------
            % parentObj : OpenSeesMatlab
            %     The parent OpenSeesMatlab object that this analysis manager will use to execute commands.

            arguments
                parentObj (1,1) OpenSeesMatlab
            end

            obj.parent = parentObj;
            obj.smartAnalyze.setOPS(obj.parent.opensees);
        end
    end

end