classdef OpenSeesMatlabTool < handle
    % OpenSeesMatlabTool Utility interface for OpenSeesMatlab.
    %
    %   OpenSeesMatlabTool groups general-purpose helpers that do not belong
    %   directly to the command, pre-processing, analysis, post-processing, or
    %   visualization interfaces. Users normally access this class through the
    %   utils property of an OpenSeesMatlab object:
    %
    %       opsmat = OpenSeesMatlab();
    %       opsmat.utils.loadExamples("Frame3D");
    %
    %   The current utility interface provides example-model loading. Loaded
    %   examples are executed against the same OpenSees command interface stored
    %   in opsmat.opensees, so subsequent calls to opsmat.post, opsmat.vis, and
    %   opsmat.anlys operate on the loaded model.
    %
    % Example
    % -------
    %       opsmat = OpenSeesMatlab();
    %       opsmat.utils.loadExamples("Frame3D");
    %
    %       modelInfo = opsmat.post.getModelData();
    %       h = opsmat.vis.plotModel();
    %



    properties (Access = private)
        parent % Parent OpenSeesMatlab object that owns this utility interface.
    end

    methods
        function obj = OpenSeesMatlabTool(parentObj)
            % Construct an OpenSeesMatlabTool object.
            %
            %   This constructor is called by OpenSeesMatlab and usually does not
            %   need to be called directly. The parent object is stored so utility
            %   methods can access shared interfaces such as parentObj.opensees.
            %
            % Parameters
            % ----------
            % parentObj : OpenSeesMatlab
            %     Parent OpenSeesMatlab object that owns this utility interface.
            %
            % Example
            % -------
            %     opsmat = OpenSeesMatlab();
            %     utils = opsmat.utils;
            if nargin < 1 || isempty(parentObj)
                error('OpenSeesMatlabTool:InvalidInput', ...
                    'A parent OpenSeesMatlab object is required.');
            end
            obj.parent = parentObj;
        end

        function loadExamples(obj, modelName)
            % Load a bundled example model into the active OpenSees interface.
            %
            %   loadExamples dispatches to demos.loadExamples and builds the
            %   selected demonstration model using obj.parent.opensees. After an
            %   example is loaded, the model can be inspected, analyzed,
            %   post-processed, or visualized through the same OpenSeesMatlab
            %   object.
            %
            % Syntax
            % ------
            %     obj.loadExamples(modelName)
            %
            % Parameters
            % ----------
            % modelName : string
            %     Name of the example model to load. Supported values are:
            %
            %     - "Frame3D"
            %     - "ArchBridge"
            %     - "ArchBridge2"
            %     - "CableStayedBridge"
            %     - "SuspensionBridge"
            %     - "TrussBridge"
            %     - "Dam"
            %
            % Example
            % -------
            %     opsmat = OpenSeesMatlab();
            %     opsmat.utils.loadExamples("Frame3D");
            %
            %     opsmat.post.getModelData();
            %     opsmat.vis.plotModel();

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
