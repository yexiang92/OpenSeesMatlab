classdef OpenSeesMatlabTool < handle
    % OpenSeesMatlabTool class for OpenSees MATLAB tools.
    %   This class provides utility functions for the OpenSees MATLAB interface


    properties (Access = private)
        parent % Reference to the parent OpenSeesMatlab object
    end

    methods
        function obj = OpenSeesMatlabTool(parentObj)
            if nargin < 1 || isempty(parentObj)
                error('OpenSeesMatlabTool:InvalidInput', ...
                    'A parent OpenSeesMatlab object is required.');
            end
            obj.parent = parentObj;
        end

        function loadExamples(obj, modelName)
            % Load example models into the OpenSees MATLAB interface.
            %
            % Example
            % --------
            %     ops.loadExamples(modelName)
            %
            % Parameters
            % ----------
            % modelName : string or char
            %     Name of the example model to load. Supported values are:
            %     'Frame3D', 'ArchBridge', 'ArchBridge2', 'CableStayedBridge', ...
            %     'SuspensionBridge', 'TrussBridge', 'Dam'.

            arguments
                obj (1,1) OpenSeesMatlabTool
                modelName (1,1) string {mustBeMember(modelName, ...
                    ["Frame3D", "ArchBridge", "ArchBridge2", "CableStayedBridge", ...
                     "SuspensionBridge", "TrussBridge", "Dam"])}
            end

            demos.loadExamples(obj.parent.opensees, modelName);
        end
    end
end