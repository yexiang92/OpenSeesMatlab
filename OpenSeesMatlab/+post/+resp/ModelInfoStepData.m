classdef ModelInfoStepData < post.resp.ResponseBase

    properties (Constant)
        RESP_NAME = 'ModelInfo'
    end

    properties
        modelCollector post.FEMDataCollector

        currentModelInfo
        currentNodeTags
        currentEleTags
        currentEleClassTags

        currentTrussTags
        currentFrameTags
        currentLinkTags
        currentShellTags
        currentPlaneTags
        currentBrickTags
        currentContactTags

        currentPatternTags
        currentNodeLoadData struct
        currentFrameLoadData struct
        currentSurfaceLoadData struct
    end

    methods
        function obj = ModelInfoStepData(ops, varargin)
            obj@post.resp.ResponseBase(ops, varargin{:});
            obj.respName = 'ModelInfo';

            obj.modelCollector = post.FEMDataCollector(obj.ops, post.utils.OpenSeesTagMaps());

            modelInfo = obj.getModelInfo();
            obj.setCurrentTags(modelInfo);

            obj.addStepData(obj.currentModelInfo);
        end

        function addRespDataOneStep(obj)
            if obj.modelUpdate
                modelInfo = obj.getModelInfo();
                obj.setCurrentTags(modelInfo);
                obj.addStepData(obj.currentModelInfo);
            end
        end

        function modelInfo = getCurrentModelInfo(obj)
            modelInfo = obj.currentModelInfo;
        end

        function tags = getCurrentNodeTags(obj)
            tags = obj.currentNodeTags;
        end

        function tags = getCurrentElementTags(obj)
            tags = obj.currentEleTags;
        end

        function tags = getCurrentElementClassTags(obj)
            tags = obj.currentEleClassTags;
        end

        function tags = getCurrentTrussTags(obj)
            tags = obj.currentTrussTags;
        end

        function tags = getCurrentFrameTags(obj)
            tags = obj.currentFrameTags;
        end

        function tags = getCurrentLinkTags(obj)
            tags = obj.currentLinkTags;
        end

        function tags = getCurrentShellTags(obj)
            tags = obj.currentShellTags;
        end

        function tags = getCurrentPlaneTags(obj)
            tags = obj.currentPlaneTags;
        end

        function tags = getCurrentSolidTags(obj)
            tags = obj.currentBrickTags;
        end

        function tags = getCurrentContactTags(obj)
            tags = obj.currentContactTags;
        end

        function tags = getCurrentPatternTags(obj)
            tags = obj.currentPatternTags;
        end

        function data = getCurrentNodeLoadData(obj)
            data = obj.currentNodeLoadData;
        end

        function data = getCurrentFrameLoadData(obj)
            data = obj.currentFrameLoadData;
        end

        function data = getCurrentSurfaceLoadData(obj)
            data = obj.currentSurfaceLoadData;
        end
    end

    methods (Static)
        function out = readResponse(respData, dataType)
            if nargin < 2
                dataType = '';
            end

            if isempty(dataType)
                out = respData;
            elseif isfield(respData, dataType)
                out = respData.(dataType);
            else
                out = [];
            end
        end
    end

    methods (Access = protected)
        function modelInfo = getModelInfo(obj)
            modelInfo = obj.modelCollector.getModelInfo();
        end

        function setCurrentTags(obj, modelInfo)

            obj.currentNodeTags = modelInfo.Nodes.Tags;
            if ~isempty(modelInfo.Nodes.UnusedTags)
                unusedTags = double(modelInfo.Nodes.UnusedTags(:));
                unusedTags = unique(unusedTags(isfinite(unusedTags)));
                obj.currentNodeTags = obj.currentNodeTags(~ismember(obj.currentNodeTags, unusedTags));
                modelInfo.Nodes.Tags = obj.currentNodeTags;
            end
            
            obj.currentEleTags = modelInfo.Elements.Summary.Tags;
            obj.currentEleClassTags = modelInfo.Elements.Summary.ClassTags;

            obj.currentTrussTags = modelInfo.Elements.Families.Truss.Tags;
            obj.currentFrameTags = modelInfo.Elements.Families.Beam.Tags;
            obj.currentLinkTags = modelInfo.Elements.Families.Link.Tags;
            obj.currentShellTags = modelInfo.Elements.Families.Shell.Tags;
            obj.currentPlaneTags = modelInfo.Elements.Families.Plane.Tags;
            obj.currentBrickTags = modelInfo.Elements.Families.Solid.Tags;
            obj.currentContactTags = modelInfo.Elements.Families.Contact.Tags;

            obj.currentPatternTags = modelInfo.Loads.PatternTags;
            obj.currentNodeLoadData = modelInfo.Loads.Node;
            obj.currentFrameLoadData = modelInfo.Loads.Element.Beam;
            obj.currentSurfaceLoadData = modelInfo.Loads.Element.Surface;

            obj.currentModelInfo = modelInfo;
        end
    end
end