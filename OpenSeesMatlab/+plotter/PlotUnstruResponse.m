classdef PlotUnstruResponse < handle
    % PlotUnstruResponse
    % Visualise shell / plane / solid element responses on the full model.
    %
    % Key behaviours
    % --------------
    % 1) response type + component are auto-corrected
    % 2) shell fiber selection supports top / bottom / middle / index
    % 3) AtNodes responses are mapped to ALL model nodes
    % 4) nodes outside the AtNodes set are filled with NaN
    % 5) top-level EleResp.nodeTags / eleTags may be global union vectors
    %    or per-step 2D arrays
    % 6) when tags are 2D, current-step tags are used and NaNs are removed;
    %    when tags are vectors, they are treated as global unions
    % 7) Gauss-point responses are reduced to element scalars
    % 8) node-based colouring and element-based colouring are both supported
    % 9) plotting limits are computed from the actually displayed geometry
    % 10) if interpolated line data exist, line elements are drawn by
    %     interpolated geometry first

    properties
        ModelInfo   struct
        NodalResp   struct
        EleResp     struct
        Plotter     plotter.PatchPlotter
        Ax          matlab.graphics.axis.Axes
        Opts        struct
        Handles     struct = struct()
        cbarTitle   char = ''

        EleType     char = 'Plane'
        RespType    char = ''
        Component   char = ''
        FiberPoint       = 'top'
    end

    properties (Access = private)
        CachedModelDim    double  = 3
        CachedModelSize   double  = 1
        ModelUpdateFlag   logical = false

        GlobalClimCache   double = []
        GlobalClimKey     char   = ''

        GlobalDeformScale double = NaN
        GlobalDeformField char   = ''
        GlobalDeformStep  double = NaN

        ModelTagToIdx     double = []
        ModelTagToIdxMap         = []

        % Per-step scalar fields
        % Node fields are aligned with ALL model nodes.
        RespNodeScalar    cell = {}   % each: [nModelNode x 1] or []
        RespEleScalar     cell = {}   % each: [nActiveEle x 1] or []

        RespNodeTags      double = []   % global node-tag union used by response cache
        ActiveEleTags     double = []   % global element-tag union used by response cache
    end

    methods (Static)
        function opts = defaultOptions()
            opts = struct();

            opts.general = struct( ...
                'clearAxes',true, 'holdOn',true, 'axisEqual',true, ...
                'grid',true, 'box',false, 'view','auto', ...
                'title','auto', 'padRatio',0.05, 'figureSize',[1000,618]);

            opts.deform = struct( ...
                'show',true, 'type','disp', 'scale',1, ...
                'autoScale',true, 'showUndeformed',false);

            opts.interp = struct( ...
                'useInterpolation',true, 'lineWidth',1.5, 'lineStyle','-', ...
                'undeformedLineWidth',0.8, 'colorBy','solid');  % disp | solid

            opts.color = struct( ...
                'useColormap',true, 'colormap',turbo(256), 'clim',[], ...
                'climMode','range', 'solidColor','#3A86FF', ...
                'undeformedColor',[0.6 0.6 0.6], 'undeformedAlpha',0.20, ...
                'deformedAlpha',1.0);

            opts.line = struct( ...
                'show',true, 'lineWidth',1.5, 'lineStyle','-', ...
                'undeformedLineWidth',0.8);

            opts.surf = struct( ...
                'show',true, 'showEdges',true, 'edgeColor','black', 'edgeWidth',0.8, ...
                'colorMode','auto', ...  % auto | node | element
                'gpReduce','mean', ...   % mean | max | min | absmax | index
                'gpIndex',1);            % used when gpReduce = index

            opts.fixed = struct( ...
                'show',true, 'size',40, 'marker','s', 'filled',true, ...
                'edgeColor','#000000', 'color','#8c000f');

            opts.cbar = struct('show',true, 'label','');
        end
    end

    methods
        function obj = PlotUnstruResponse(modelInfo, nodalResp, eleResp, ax, opts)
            if nargin < 1 || isempty(modelInfo)
                error('PlotUnstruResponse:InvalidInput', 'modelInfo must be provided.');
            end
            if nargin < 2 || isempty(nodalResp)
                error('PlotUnstruResponse:InvalidInput', 'nodalResp must be provided.');
            end
            if nargin < 3 || isempty(eleResp)
                error('PlotUnstruResponse:InvalidInput', 'eleResp must be provided.');
            end
            if nargin < 4, ax = []; end
            if nargin < 5, opts = []; end

            obj.ModelInfo = modelInfo;
            obj.NodalResp = nodalResp;
            obj.EleResp   = eleResp;
            obj.Opts      = obj.mergeStruct(plotter.PlotUnstruResponse.defaultOptions(), opts);
            obj.Plotter   = plotter.PatchPlotter(ax);
            obj.Ax        = obj.Plotter.Ax;

            if isfield(nodalResp, 'ModelUpdate')
                obj.ModelUpdateFlag = logical(nodalResp.ModelUpdate);
            elseif isfield(modelInfo, 'Nodes') && isfield(modelInfo.Nodes, 'Coords')
                obj.ModelUpdateFlag = (ndims(modelInfo.Nodes.Coords) == 3);
            end

            P = obj.getNodeCoords(1);
            obj.CachedModelDim  = obj.computeModelDim(P);
            obj.CachedModelSize = obj.computeModelLength(P);

            obj.buildModelTagLookup();
        end

        function ax = getAxes(obj)
            ax = obj.Ax;
        end

        function setOptions(obj, opts)
            prevRespKey  = obj.makeRespKey();
            prevDefField = obj.Opts.deform.type;
            prevDefAuto  = obj.Opts.deform.autoScale;
            prevDefScale = obj.Opts.deform.scale;
            prevGpReduce = obj.Opts.surf.gpReduce;
            prevGpIndex  = obj.Opts.surf.gpIndex;

            obj.Opts = obj.mergeStruct(obj.Opts, opts);

            if ~strcmp(prevRespKey, obj.makeRespKey()) || ...
               ~strcmpi(prevGpReduce, obj.Opts.surf.gpReduce) || ...
               prevGpIndex ~= obj.Opts.surf.gpIndex
                if ~isempty(obj.RespNodeScalar) || ~isempty(obj.RespEleScalar)
                    [obj.RespNodeScalar, obj.RespEleScalar, obj.RespNodeTags, obj.ActiveEleTags] = ...
                        obj.buildRespFields();
                end
                obj.GlobalClimCache = [];
                obj.GlobalClimKey   = '';
            end

            if ~strcmp(prevDefField, obj.Opts.deform.type) || ...
               prevDefAuto ~= obj.Opts.deform.autoScale || ...
               prevDefScale ~= obj.Opts.deform.scale
                obj.GlobalDeformScale = NaN;
                obj.GlobalDeformField = '';
                obj.GlobalDeformStep  = NaN;
            end
        end

        function setResponse(obj, eleType, respType, component, fiberPoint)
            if nargin < 5, fiberPoint = []; end

            obj.EleType    = char(eleType);
            obj.FiberPoint = fiberPoint;

            switch lower(obj.EleType)
                case 'shell'
                    obj.EleType = 'Shell';
                    [obj.RespType, obj.Component, obj.FiberPoint] = ...
                        unstru_check_shell(respType, component, obj.FiberPoint);
                    obj.cbarTitle = sprintf('%s (fiber-%s)', obj.Component, obj.FiberPoint);

                case 'plane'
                    obj.EleType = 'Plane';
                    [obj.RespType, obj.Component] = ...
                        unstru_check_plane(respType, component);
                    obj.cbarTitle = obj.Component;

                case {'solid','brick'}
                    obj.EleType = 'Solid';
                    [obj.RespType, obj.Component] = ...
                        unstru_check_solid(respType, component);
                    obj.cbarTitle = obj.Component;

                otherwise
                    error('PlotUnstruResponse:BadEleType', ...
                        'Unknown ele type "%s". Use Shell, Plane, or Solid.', obj.EleType);
            end

            [obj.RespNodeScalar, obj.RespEleScalar, obj.RespNodeTags, obj.ActiveEleTags] = ...
                obj.buildRespFields();

            obj.GlobalClimCache = [];
            obj.GlobalClimKey   = '';
        end

        function h = plotStep(obj, stepIdx, opts)
            if nargin >= 3 && ~isempty(opts)
                obj.setOptions(opts);
            end
            stepIdx = obj.resolveStepIdx(stepIdx);
            obj.prepareAxes();
            obj.Handles = struct();
            obj.renderStep(stepIdx);
            h = obj.Handles;
        end

        function [cmin, cmax] = globalClim(obj)
            cacheKey = obj.makeRespKey();

            if ~isempty(obj.GlobalClimCache) && strcmp(obj.GlobalClimKey, cacheKey)
                cmin = obj.GlobalClimCache(1);
                cmax = obj.GlobalClimCache(2);
                return;
            end

            allMin = inf;
            allMax = -inf;

            for k = 1:numel(obj.RespNodeScalar)
                v1 = obj.RespNodeScalar{k};
                if ~isempty(v1)
                    v1 = v1(isfinite(v1));
                    if ~isempty(v1)
                        allMin = min(allMin, min(v1));
                        allMax = max(allMax, max(v1));
                    end
                end

                v2 = obj.RespEleScalar{k};
                if ~isempty(v2)
                    v2 = v2(isfinite(v2));
                    if ~isempty(v2)
                        allMin = min(allMin, min(v2));
                        allMax = max(allMax, max(v2));
                    end
                end
            end

            if ~isfinite(allMin), allMin = 0; end
            if ~isfinite(allMax), allMax = 1; end
            if allMin == allMax, allMax = allMin + 1; end

            obj.GlobalClimCache = [allMin allMax];
            obj.GlobalClimKey   = cacheKey;

            cmin = allMin;
            cmax = allMax;
        end
    end

    methods (Access = private)
        function renderStep(obj, stepIdx)
            P        = obj.getNodeCoords(stepIdx);
            lineConn = obj.getLineConn(stepIdx);
            [Pdef, ~, ~] = obj.getDeformedCoords(P, stepIdx);
            [Snode, Sele, clim_] = obj.getScalarField(stepIdx);

            shownPts = [];

            if obj.Opts.deform.show && obj.Opts.deform.showUndeformed
                if obj.hasInterpData(stepIdx) && obj.Opts.interp.useInterpolation
                    [obj.Handles.UndeformedLine, ptsLineU] = obj.drawInterpolatedLine(stepIdx, true, []);
                else
                    [obj.Handles.UndeformedLine, ptsLineU] = obj.drawLine( ...
                        P, lineConn, obj.Opts.color.undeformedColor, ...
                        obj.Opts.line.undeformedLineWidth, 'UndeformedLine');
                end

                [obj.Handles.UndeformedSurf, ptsSurfU] = obj.drawUnstructured( ...
                    P, stepIdx, [], [], [], true);
                shownPts = [shownPts; ptsLineU; ptsSurfU];
            end

            if obj.Opts.line.show
                if obj.hasInterpData(stepIdx) && obj.Opts.interp.useInterpolation
                    [obj.Handles.Line, ptsLine] = obj.drawInterpolatedLine(stepIdx, false, clim_);
                else
                    [obj.Handles.Line, ptsLine] = obj.drawLine( ...
                        Pdef, lineConn, obj.Opts.color.solidColor, ...
                        obj.Opts.line.lineWidth, 'Line');
                end
                shownPts = [shownPts; ptsLine];
            end

            if obj.Opts.surf.show
                [obj.Handles.Surf, ptsSurf] = obj.drawUnstructured(Pdef, stepIdx, Snode, Sele, clim_, false);
                shownPts = [shownPts; ptsSurf];
            end

            [obj.Handles.Fixed, ptsFix] = obj.drawFixed(Pdef, stepIdx);
            shownPts = [shownPts; ptsFix];
            obj.applyColorbar(clim_);
            obj.applyTitle(stepIdx);
            obj.applyView();
            obj.applyDisplayLimits(shownPts);
        end

        function tf = hasInterpData(obj, stepIdx)
            tf = isfield(obj.NodalResp,'interpolatePoints') && ...
                 isfield(obj.NodalResp,'interpolateDisp')   && ...
                 isfield(obj.NodalResp,'interpolateCells')  && ...
                 ~isempty(obj.NodalResp.interpolatePoints);
            if ~tf
                return;
            end

            pts = obj.NodalResp.interpolatePoints;
            if ndims(pts) == 3
                si  = min(stepIdx, size(pts,1));
                row = squeeze(pts(si,:,:));
                tf  = ~isempty(row) && any(isfinite(row(:)));
            end
        end

        function [pts, disp_, cells] = getInterpSlice(obj, stepIdx)
            pts    = double(obj.NodalResp.interpolatePoints);
            disp_  = double(obj.NodalResp.interpolateDisp);
            cells_ = double(obj.NodalResp.interpolateCells);

            if ndims(pts) == 3
                si    = min(stepIdx, size(pts,1));
                pts   = squeeze(pts(si,:,:));
                disp_ = squeeze(disp_(si,:,:));
            end

            if size(pts,2) < 3
                pts(:,3) = 0;
            end
            if size(disp_,2) < 3
                disp_(:,3) = 0;
            end

            if ndims(cells_) == 3
                si     = min(stepIdx, size(cells_,1));
                cells_ = squeeze(cells_(si,:,:));
            end

            if size(cells_,2) >= 3
                cells = cells_(:,end-1:end);
            else
                cells = cells_;
            end
        end

        function [h, ptsOut] = drawInterpolatedLine(obj, stepIdx, asUndeformed, clim_)
            h = gobjects(0);
            ptsOut = zeros(0,3);

            [pts, disp_, cells] = obj.getInterpSlice(stepIdx);
            if isempty(pts) || isempty(cells)
                return;
            end

            if asUndeformed
                Pline = pts;
            else
                scale = obj.globalDeformScale(stepIdx);
                U3 = disp_(:,1:min(3,size(disp_,2)));
                if size(U3,2) < 3
                    U3(:,end+1:3) = 0;
                end
                Pline = pts + scale * U3;
            end

            s.nodes     = Pline;
            s.lines     = cells;
            s.lineWidth = obj.Opts.interp.lineWidth;
            s.lineStyle = obj.Opts.interp.lineStyle;
            s.tag       = 'InterpLine';

            if asUndeformed
                s.color = obj.Opts.color.undeformedColor;
                h = obj.Plotter.addLine(s);
            else
                if strcmpi(obj.Opts.interp.colorBy, 'disp') && obj.Opts.color.useColormap
                    val = sqrt(sum(disp_(:,1:min(3,size(disp_,2))).^2, 2));
                    s.values = val(:);
                    s.cmap   = obj.Opts.color.colormap;
                    if ~isempty(clim_)
                        s.clim = clim_;
                    end
                    h = obj.Plotter.addColoredLine(s);
                else
                    s.color = obj.Opts.color.solidColor;
                    h = obj.Plotter.addLine(s);
                end
            end

            ptsOut = Pline;
        end

        function [Pdef, U3, scale] = getDeformedCoords(obj, P, stepIdx)
            if obj.Opts.deform.show
                U     = obj.getRespSlice(obj.Opts.deform.type, stepIdx);
                U3    = obj.extractXYZ(U);
                scale = obj.globalDeformScale(stepIdx);
                Pdef  = P + scale * U3;
            else
                U3    = zeros(size(P));
                scale = 0;
                Pdef  = P;
            end
        end

        function scale = globalDeformScale(obj, stepIdx)
            if nargin < 2 || isempty(stepIdx)
                stepIdx = 1;
            end

            fieldType = obj.Opts.deform.type;
            if isfinite(obj.GlobalDeformScale) && strcmp(obj.GlobalDeformField, fieldType) && ...
                    isequal(obj.GlobalDeformStep, stepIdx)
                scale = obj.GlobalDeformScale;
                return;
            end

            baseScale = obj.Opts.deform.scale;
            if ~obj.Opts.deform.autoScale
                obj.GlobalDeformScale = baseScale;
                obj.GlobalDeformField = fieldType;
                obj.GlobalDeformStep  = stepIdx;
                scale = baseScale;
                return;
            end

            U = obj.getRespSlice(fieldType, stepIdx);
            umax = max(sqrt(sum(obj.extractXYZ(U).^2, 2)), [], 'omitnan');
            if ~isfinite(umax)
                umax = 0;
            end

            modelSize = obj.computeModelLength(obj.getNodeCoords(stepIdx));

            if obj.hasInterpData(stepIdx)
                [~, disp_, ~] = obj.getInterpSlice(stepIdx);
                uk = max(sqrt(sum(disp_(:,1:min(3,size(disp_,2))).^2, 2)), [], 'omitnan');
                if isfinite(uk)
                    umax = max(umax, uk);
                end
            end

            if umax <= 0, umax = 1; end
            if modelSize <= 0, modelSize = obj.CachedModelSize; end

            scale = baseScale * modelSize / umax / 10;
            obj.GlobalDeformScale = scale;
            obj.GlobalDeformField = fieldType;
            obj.GlobalDeformStep  = stepIdx;
        end

        function [Snode, Sele, clim_] = getScalarField(obj, stepIdx)
            Snode = [];
            Sele  = [];
            clim_ = [];

            if stepIdx <= numel(obj.RespNodeScalar)
                Snode = obj.RespNodeScalar{stepIdx};
            end
            if stepIdx <= numel(obj.RespEleScalar)
                Sele = obj.RespEleScalar{stepIdx};
            end

            vals = [];
            if ~isempty(Snode)
                vals = Snode;
            elseif ~isempty(Sele)
                vals = Sele;
            end

            if ~isempty(vals)
                clim_ = obj.resolveClim(vals);
            end
        end

        function stepIdx = resolveStepIdx(obj, stepIdx)
            if isnumeric(stepIdx)
                stepIdx = round(stepIdx);
                stepIdx = stepIdx + 1; % Convert from 0-based to 1-based index
                n = obj.nSteps();
                if stepIdx < 1 || stepIdx > n
                    error('PlotUnstruResponse:InvalidStep', ...
                        'stepIdx %d out of range [0, %d].', stepIdx-1, n-1);
                end
                return;
            end

            key = obj.normalizeStepSelector(stepIdx);
            n   = max(numel(obj.RespNodeScalar), numel(obj.RespEleScalar));
            vals = obj.initStepSelectorValues(key, n);

            for k = 1:n
                v = [];
                if k <= numel(obj.RespNodeScalar) && ~isempty(obj.RespNodeScalar{k})
                    v = obj.RespNodeScalar{k};
                elseif k <= numel(obj.RespEleScalar) && ~isempty(obj.RespEleScalar{k})
                    v = obj.RespEleScalar{k};
                end

                v = v(isfinite(v));
                if isempty(v), continue; end

                switch key
                    case {'absmax','absmin'}
                        vals(k) = max(abs(v), [], 'omitnan');
                    case 'max'
                        vals(k) = max(v, [], 'omitnan');
                    case 'min'
                        vals(k) = min(v, [], 'omitnan');
                    otherwise
                        error('PlotUnstruResponse:InvalidStepIdx', ...
                            'Unknown stepIdx "%s". Use absmax|absmin|max|min or stepMax-style aliases.', key);
                end
            end

            switch key
                case {'absmax','max'}
                    [~, stepIdx] = max(vals, [], 'omitnan');
                case {'absmin','min'}
                    [~, stepIdx] = min(vals, [], 'omitnan');
            end
        end

        function key = normalizeStepSelector(~, stepIdx)
            key = lower(strtrim(char(string(stepIdx))));
            switch key
                case 'stepmax'
                    key = 'max';
                case 'stepmin'
                    key = 'min';
                case 'stepabsmax'
                    key = 'absmax';
                case 'stepabsmin'
                    key = 'absmin';
            end
        end

        function vals = initStepSelectorValues(~, key, n)
            switch key
                case {'absmax','max'}
                    vals = -inf(n, 1);
                case {'absmin','min'}
                    vals = inf(n, 1);
                otherwise
                    vals = NaN(n, 1);
            end
        end

        function P = getNodeCoords(obj, stepIdx)
            [P, ~] = obj.getNodeStepData(stepIdx);
        end

        function P = getNodeCoordsRaw(obj, stepIdx)
            P = zeros(0,3);
            if ~isfield(obj.ModelInfo, 'Nodes') || ~isfield(obj.ModelInfo.Nodes, 'Coords')
                return;
            end

            C = double(obj.ModelInfo.Nodes.Coords);
            if isempty(C), return; end

            if obj.ModelUpdateFlag && ndims(C) == 3
                P = squeeze(C(min(stepIdx, size(C,1)), :, :));
            else
                P = C;
            end

            if size(P,2) < 3
                P(:,3) = 0;
            elseif size(P,2) > 3
                P = P(:,1:3);
            end
        end

        function [P, tags] = getNodeStepData(obj, stepIdx)
            P = obj.getNodeCoordsRaw(stepIdx);
            tags = obj.getModelNodeTagsRaw(stepIdx, size(P,1));
            if isempty(P)
                tags = zeros(0,1);
                return;
            end

            keepMask = obj.getExistingNodeStepMask(P, tags);
            P = P(keepMask, :);
            tags = obj.trimVectorLength(tags, numel(keepMask));
            tags = tags(keepMask);
        end

        function [keepMask, rawToClean] = getNodeStepSelection(obj, stepIdx, P, ~)
            if nargin < 3 || isempty(P)
                P = obj.getNodeCoordsRaw(stepIdx);
            end

            tags = obj.getModelNodeTagsRaw(stepIdx, size(P,1));
            keepMask = obj.getExistingNodeStepMask(P, tags);
            rawToClean = zeros(size(keepMask));
            rawToClean(keepMask) = 1:nnz(keepMask);
        end

        function keepMask = getExistingNodeStepMask(obj, P, tags)
            if isempty(P)
                keepMask = false(0,1);
                return;
            end

            keepMask = ~all(isnan(P), 2);
            if nargin < 3 || isempty(tags)
                return;
            end

            tags = obj.trimVectorLength(tags, numel(keepMask));
            keepMask = keepMask & isfinite(tags);

            unusedTags = obj.getUnusedNodeTags();
            if ~isempty(unusedTags)
                keepMask = keepMask & ~ismember(tags, unusedTags);
            end
        end

        function keepMask = getNodeStepMask(obj, P, tags)
            keepMask = obj.getExistingNodeStepMask(P, tags);
        end

        function tags = getModelNodeTagsRaw(obj, stepIdx, nRow)
            if nargin < 3, nRow = []; end
            if isfield(obj.ModelInfo,'Nodes') && isfield(obj.ModelInfo.Nodes,'Tags') && ...
               ~isempty(obj.ModelInfo.Nodes.Tags)
                tags = obj.readStepVectorData(obj.ModelInfo.Nodes.Tags, stepIdx);
            else
                tags = (1:size(obj.getNodeCoordsRaw(stepIdx),1)).';
            end

            if ~isempty(nRow)
                tags = obj.trimVectorLength(tags, nRow);
            end
        end

        function tags = getUnusedNodeTags(obj)
            tags = [];
            if ~isfield(obj.ModelInfo,'Nodes') || ~isfield(obj.ModelInfo.Nodes,'UnusedTags') || ...
               isempty(obj.ModelInfo.Nodes.UnusedTags)
                return;
            end
            tags = double(obj.ModelInfo.Nodes.UnusedTags);
            tags = tags(:);
            tags = tags(isfinite(tags));
            tags = unique(tags, 'stable');
        end

        function lines = getLineConn(obj, stepIdx)
            lines = zeros(0,2);

            fam = obj.getFamilies(stepIdx);
            if ~isfield(fam, 'Line') || ~isfield(fam.Line, 'Cells') || isempty(fam.Line.Cells)
                return;
            end

            C = double(fam.Line.Cells);
            if obj.ModelUpdateFlag && ndims(C) == 3
                C = squeeze(C(min(stepIdx, size(C,1)), :, :));
            end

            if size(C,2) >= 3
                lines = C(:, end-1:end);
            elseif size(C,2) == 2
                lines = C;
            end

            [~, rawToClean] = obj.getNodeStepSelection(stepIdx);
            if isempty(lines) || isempty(rawToClean)
                lines = zeros(0,2);
                return;
            end

            lines = round(double(lines));
            valid = all(isfinite(lines), 2) & all(lines >= 1, 2) & all(lines <= numel(rawToClean), 2);
            lines = lines(valid, :);
            if isempty(lines)
                return;
            end

            lines = rawToClean(lines);
            lines = reshape(lines, [], 2);
            lines = lines(all(lines >= 1, 2), :);
        end

        function fam = getFamilies(obj, ~)
            fam = struct();
            if ~isfield(obj.ModelInfo, 'Elements'), return; end
            E = obj.ModelInfo.Elements;
            if isfield(E, 'Families')
                fam = E.Families;
            else
                fam = E;
            end
        end

        function fam = getRespFamily(obj, stepIdx)
            fam = [];
            F = obj.getFamilies(stepIdx);

            switch lower(obj.EleType)
                case 'plane'
                    if isfield(F, 'Plane')
                        fam = F.Plane;
                    end
                case 'shell'
                    if isfield(F, 'Shell')
                        fam = F.Shell;
                    end
                case 'solid'
                    if isfield(F, 'Solid')
                        fam = F.Solid;
                    end
            end
        end

        function U = getRespSlice(obj, fieldType, stepIdx)
            [Pmodel, modelTags] = obj.getNodeStepData(stepIdx);
            nModel = size(Pmodel, 1);
            U = NaN(nModel, 6);

            if ~isfield(obj.NodalResp, fieldType)
                return;
            end

            entry = obj.NodalResp.(fieldType);
            if isstruct(entry) && isfield(entry, 'data')
                % Layout B
                arr  = entry.data;
                if isempty(arr) || ndims(arr) < 3, return; end
                si   = min(stepIdx, size(arr,1));
                Uraw = double(reshape(arr(si,:,:), size(arr,2), size(arr,3)));
            elseif isstruct(entry)
                % Layout C: per-DOF struct
                dofFields = fieldnames(entry);
                if isempty(dofFields), return; end
                firstArr = entry.(dofFields{1});
                if ~isnumeric(firstArr) || isempty(firstArr), return; end
                si   = min(stepIdx, size(firstArr,1));
                nRow = size(firstArr,2);
                nDof = numel(dofFields);
                Uraw = zeros(nRow, nDof, 'double');
                for di = 1:nDof
                    dArr = entry.(dofFields{di});
                    if isnumeric(dArr) && size(dArr,1) >= si
                        Uraw(:,di) = double(dArr(si,:)).';
                    end
                end
            else
                % Layout A: raw array
                arr = entry;
                if isempty(arr) || ndims(arr) < 3, return; end
                si   = min(stepIdx, size(arr,1));
                Uraw = double(reshape(arr(si,:,:), size(arr,2), size(arr,3)));
            end
            if isvector(Uraw)
                Uraw = Uraw(:).';
            end
            ncol = min(size(Uraw,2), 6);
            respTags = obj.getNodalRespNodeTags(fieldType, stepIdx);

            if ~isempty(respTags)
                U(:, 1:ncol) = obj.mapNodeDataToCurrentModel(modelTags, Uraw(:,1:ncol), respTags, ncol);
                return;
            end

            Praw = obj.getNodeCoordsRaw(stepIdx);
            keepMask = obj.getNodeStepMask(Praw, obj.getModelNodeTagsRaw(stepIdx, size(Praw,1)));
            if size(Uraw,1) == size(Praw,1)
                Uraw = Uraw(keepMask, :);
            end

            nCopy = min(nModel, size(Uraw,1));
            U(1:nCopy, 1:ncol) = Uraw(1:nCopy, 1:ncol);
        end

        function buildModelTagLookup(obj)
            obj.ModelTagToIdx    = [];
            obj.ModelTagToIdxMap = [];

            tags = obj.getModelNodeTagsRaw(1);
            if isempty(tags), return; end

            tags = double(tags(:));
            valid = isfinite(tags) & tags >= 1 & mod(tags,1) == 0;
            if ~any(valid)
                return;
            end
            if ~all(valid)
                tags = tags(valid);
            end

            tags = unique(tags, 'stable');
            if isempty(tags)
                return;
            end

            n    = numel(tags);
            maxT = max(tags, [], 'omitnan');

            if isfinite(maxT) && maxT >= 1 && maxT <= max(20*n, 1e6)
                arr = zeros(maxT,1);
                arr(tags) = 1:n;
                obj.ModelTagToIdx = arr;
            else
                obj.ModelTagToIdxMap = containers.Map(num2cell(tags), num2cell(1:n));
            end
        end

        function rows = modelTagsToRows(obj, tags, stepIdx)
            if nargin < 3, stepIdx = 1; end
            rows = zeros(numel(tags), 1);

            if obj.ModelUpdateFlag
                modelTags = obj.getModelNodeTagsRaw(stepIdx);
                [tf, loc] = ismember(double(tags(:)), double(modelTags(:)));
                rows(tf) = loc(tf);
                return;
            end

            if ~isempty(obj.ModelTagToIdx)
                valid = tags >= 1 & tags <= numel(obj.ModelTagToIdx) & isfinite(tags);
                rows(valid) = obj.ModelTagToIdx(tags(valid));
                return;
            end

            if ~isempty(obj.ModelTagToIdxMap)
                keys = num2cell(tags);
                exists = isKey(obj.ModelTagToIdxMap, keys);
                if any(exists)
                    rows(exists) = cell2mat(values(obj.ModelTagToIdxMap, keys(exists)));
                end
            end
        end

        function tags = getModelNodeTags(obj, stepIdx)
            if nargin < 2, stepIdx = 1; end
            [~, tags] = obj.getNodeStepData(stepIdx);
        end

        function n = nSteps(obj)
            if isfield(obj.NodalResp,'time') && ~isempty(obj.NodalResp.time)
                n = numel(obj.NodalResp.time);
                return;
            end
            n = max(numel(obj.RespNodeScalar), numel(obj.RespEleScalar));
            if n <= 0
                rt = obj.normalizeRespType(obj.RespType);
                if isfield(obj.EleResp, rt)
                    fld = obj.EleResp.(rt);
                    if isstruct(fld) && isfield(fld,'data')
                        n = size(fld.data, 1);
                    elseif isstruct(fld)
                        fn2 = fieldnames(fld);
                        if ~isempty(fn2)
                            n = size(double(fld.(fn2{1})), 1);
                        else
                            n = 1;
                        end
                    elseif isnumeric(fld)
                        n = size(fld, 1);
                    else
                        n = 1;
                    end
                else
                    n = 1;
                end
            end
        end

        function n = nNodes(obj, stepIdx)
            if nargin < 2, stepIdx = 1; end
            n = size(obj.getNodeCoords(stepIdx), 1);
        end

        function tags = getNodalRespNodeTags(obj, fieldType, stepIdx)
            tags = [];
            if ~isfield(obj.NodalResp, fieldType)
                return;
            end
            entry = obj.NodalResp.(fieldType);
            if isfield(obj.NodalResp, 'nodeTags') && ~isempty(obj.NodalResp.nodeTags)
                raw = obj.NodalResp.nodeTags;
            elseif isstruct(entry) && isfield(entry, 'nodeTags') && ~isempty(entry.nodeTags)
                raw = entry.nodeTags;
            else
                return;
            end
            tags = obj.readStepVectorData(raw, stepIdx);
        end

        function [cellsModel, modelRowsUsed, keepRows] = remapCellsToModelRows(obj, cells, stepIdx)
            cellsModel = zeros(size(cells));
            modelRowsUsed = zeros(0,1);
            keepRows = false(size(cells,1),1);

            if isempty(cells)
                return;
            end

            [~, rawToClean] = obj.getNodeStepSelection(stepIdx);
            if isempty(rawToClean)
                cellsModel = zeros(0, size(cells,2));
                keepRows = false(0,1);
                return;
            end

            for i = 1:size(cells,1)
                row = double(cells(i,:));
                row = row(isfinite(row) & row > 0);
                if isempty(row)
                    continue;
                end

                n1 = row(1);
                if isfinite(n1) && n1 >= 3 && abs(round(n1) - n1) < 1e-12 && numel(row) >= n1 + 1
                    ids = round(row(2:1+n1));
                    if any(ids < 1 | ids > numel(rawToClean))
                        continue;
                    end
                    rr = rawToClean(ids(:));
                    if any(rr <= 0)
                        continue;
                    end
                    cellsModel(i,1:1+n1) = [n1, rr(:).'];
                    modelRowsUsed = [modelRowsUsed; rr(:)]; %#ok<AGROW>
                    keepRows(i) = true;
                else
                    ids = round(row(:));
                    if any(ids < 1 | ids > numel(rawToClean))
                        continue;
                    end
                    rr = rawToClean(ids);
                    if any(rr <= 0)
                        continue;
                    end
                    cellsModel(i,1:numel(rr)) = rr(:).';
                    modelRowsUsed = [modelRowsUsed; rr(:)]; %#ok<AGROW>
                    keepRows(i) = true;
                end
            end

            cellsModel = cellsModel(keepRows,:);

            if ~isempty(modelRowsUsed)
                modelRowsUsed = unique(modelRowsUsed, 'stable');
            end
        end

        function [cells, types, tags] = getRespFamilyStepData(obj, stepIdx)
            cells = zeros(0,0);
            types = zeros(0,1);
            tags  = zeros(0,1);

            fam = obj.getRespFamily(stepIdx);
            if isempty(fam)
                return;
            end

            if isfield(fam, 'Cells') && ~isempty(fam.Cells)
                cells = double(fam.Cells);
                if obj.ModelUpdateFlag && ndims(cells) == 3
                    cells = squeeze(cells(min(stepIdx, size(cells,1)), :, :));
                end
                if isvector(cells)
                    cells = reshape(cells, 1, []);
                end
            end

            if isfield(fam, 'CellTypes') && ~isempty(fam.CellTypes)
                types = double(fam.CellTypes);
                if obj.ModelUpdateFlag && ndims(types) == 3
                    types = squeeze(types(min(stepIdx, size(types,1)), :, :));
                elseif obj.ModelUpdateFlag && ismatrix(types) && size(types,1) == obj.nSteps()
                    types = squeeze(types(min(stepIdx, size(types,1)), :));
                end
                types = types(:);
            end

            if isfield(fam, 'Tags') && ~isempty(fam.Tags)
                tags = obj.readStepVectorData(fam.Tags, stepIdx);
            end

            if ~isempty(cells)
                keep = ~all(isnan(cells), 2);
                cells = cells(keep, :);
                if ~isempty(types)
                    types = obj.trimVectorLength(types, numel(keep));
                    types = types(keep);
                end
                if ~isempty(tags)
                    tags = obj.trimVectorLength(tags, numel(keep));
                    tags = tags(keep);
                end
            end
        end

        function tags = getRespEleTagsAtStep(obj, stepIdx)
            tags = [];
            if ~isfield(obj.EleResp,'eleTags') || isempty(obj.EleResp.eleTags)
                return;
            end
            tags = obj.readStepVectorData(obj.EleResp.eleTags, stepIdx);
            tags = double(tags(:));
            tags = tags(isfinite(tags));
        end

        function rows = getRespEleRowsAtStep(obj, familyTags, stepIdx)
            rows = [];
            if isempty(familyTags) || ~isfield(obj.EleResp,'eleTags') || isempty(obj.EleResp.eleTags)
                return;
            end

            if nargin < 3 || isempty(stepIdx)
                stepIdx = 1;
            end

            respTags = obj.getRespEleTagsAtStep(stepIdx);
            if isempty(respTags)
                return;
            end

            [tf, loc] = ismember(double(familyTags(:)), respTags);
            rows = zeros(numel(familyTags), 1);
            rows(tf) = loc(tf);
        end

        function [respData, respTags] = normalizeRespElementData(~, respData, respTags)
            respData = double(respData);
            if isempty(respData)
                respTags = zeros(0,1);
                return;
            end

            if isvector(respData)
                respData = respData(:);
            end

            if isempty(respTags)
                return;
            end

            respTags = double(respTags(:));
            valid = isfinite(respTags);
            nValid = nnz(valid);
            nRowData = size(respData, 1);

            if nRowData == numel(respTags)
                respData = respData(valid, :);
                respTags = respTags(valid);
            elseif nRowData == nValid
                respTags = respTags(valid);
            else
                respTags = respTags(valid);
                nUse = min(numel(respTags), nRowData);
                respTags = respTags(1:nUse);
                respData = respData(1:nUse, :);
            end

            if isempty(respTags)
                respData = zeros(0, size(respData, 2));
            end
        end

        function values = readStepVectorData(~, raw, stepIdx)
            raw = double(raw);
            if isvector(raw)
                values = raw(:);
            elseif ismatrix(raw)
                values = raw(min(stepIdx, size(raw,1)), :).';
            else
                values = squeeze(raw(min(stepIdx, size(raw,1)), :, :));
                values = values(:);
            end
        end

        function values = trimVectorLength(~, values, nRow)
            values = values(:);
            if numel(values) < nRow
                values(end+1:nRow,1) = NaN;
            elseif numel(values) > nRow
                values = values(1:nRow);
            end
        end

        function rTags = getRespNodeTagsAtStep(obj, fld, stepIdx)
            if isfield(fld, 'nodeTags') && ~isempty(fld.nodeTags)
                tags = double(fld.nodeTags);
            elseif isfield(obj.EleResp, 'nodeTags') && ~isempty(obj.EleResp.nodeTags)
                tags = double(obj.EleResp.nodeTags);
            else
                rTags = [];
                return;
            end

            if isvector(tags)
                rTags = tags(:);
            elseif ismatrix(tags)
                si = min(stepIdx, size(tags, 1));
                rTags = tags(si, :).';
            else
                error('PlotUnstruResponse:InvalidNodeTagsShape', ...
                    'nodeTags must be a vector or a 2D array.');
            end
        end

        function tags = getRespEleTagUnion(obj)
            tags = [];
            if ~isfield(obj.EleResp, 'eleTags') || isempty(obj.EleResp.eleTags)
                return;
            end
            tags = obj.readTagUnion(obj.EleResp.eleTags);
        end

        function tags = getRespNodeTagUnion(obj, fld)
            tags = [];
            if nargin >= 2 && isstruct(fld) && isfield(fld, 'nodeTags') && ~isempty(fld.nodeTags)
                tags = obj.readTagUnion(fld.nodeTags);
                return;
            end
            if isfield(obj.EleResp, 'nodeTags') && ~isempty(obj.EleResp.nodeTags)
                tags = obj.readTagUnion(obj.EleResp.nodeTags);
            end
        end

        function tags = getModelNodeTagUnion(obj)
            if isfield(obj.ModelInfo,'Nodes') && isfield(obj.ModelInfo.Nodes,'Tags') && ...
               ~isempty(obj.ModelInfo.Nodes.Tags)
                tags = obj.readTagUnion(obj.ModelInfo.Nodes.Tags);
            else
                tags = obj.getModelNodeTags(1);
            end
            tags = double(tags(:));
            tags = tags(isfinite(tags));
        end

        function tags = readTagUnion(~, raw)
            raw = double(raw);
            if isempty(raw)
                tags = zeros(0,1);
                return;
            end

            if isvector(raw)
                tags = raw(:);
            elseif ismatrix(raw)
                tags = raw.';
                tags = tags(:);
            else
                error('PlotUnstruResponse:InvalidTagShape', ...
                    'Tag arrays must be vectors or 2D arrays.');
            end

            tags = tags(isfinite(tags));
            tags = unique(tags, 'stable');
        end

        function [respData, respTags] = normalizeRespNodeData(~, respData, respTags)
            respData = double(respData);
            if isempty(respData)
                respTags = zeros(0,1);
                return;
            end

            if isvector(respData)
                respData = respData(:);
            end

            if isempty(respTags)
                return;
            end

            respTags = double(respTags(:));
            valid = isfinite(respTags);
            nValid = nnz(valid);
            nRowData = size(respData, 1);

            if nRowData == numel(respTags)
                respData = respData(valid, :);
                respTags = respTags(valid);
            elseif nRowData == nValid
                respTags = respTags(valid);
            else
                respTags = respTags(valid);
                nUse = min(numel(respTags), nRowData);
                respTags = respTags(1:nUse);
                respData = respData(1:nUse, :);
            end

            if isempty(respTags)
                respData = zeros(0, size(respData, 2));
                return;
            end
        end

        function out = mapNodeDataToCurrentModel(obj, modelTags, respData, respTags, nCol)
            if nargin < 5 || isempty(nCol)
                if isempty(respData)
                    nCol = 1;
                else
                    nCol = size(respData, 2);
                end
            end

            out = NaN(numel(modelTags), nCol);
            if isempty(respData)
                return;
            end

            respData = double(respData);
            if isvector(respData)
                respData = respData(:);
            end

            nDataCol = min(size(respData, 2), nCol);
            respData = respData(:, 1:nDataCol);

            if isempty(respTags)
                nCopy = min(numel(modelTags), size(respData, 1));
                out(1:nCopy, 1:nDataCol) = respData(1:nCopy, :);
                return;
            end

            [respData, respTags] = obj.normalizeRespNodeData(respData, respTags);
            if isempty(respTags) || isempty(respData)
                return;
            end

            [tf, loc] = ismember(double(modelTags(:)), respTags(:));
            valid = tf & loc > 0 & loc <= size(respData, 1);
            out(valid, 1:size(respData, 2)) = respData(loc(valid), :);
        end

        function out = mapNodeScalarToCurrentModel(obj, modelTags, scalarNode, respTags)
            out = obj.mapNodeDataToCurrentModel(modelTags, scalarNode, respTags, 1);
            out = out(:,1);
        end

        function [nodeFields, eleFields, nodeTags, eleTags] = buildRespFields(obj)
            rt = obj.normalizeRespType(obj.RespType);
            if ~isfield(obj.EleResp, rt)
                error('PlotUnstruResponse:MissingRespField', ...
                    'EleResp does not contain field "%s".', obj.RespType);
            end

            fld = obj.EleResp.(rt);

            % Detect data layout
            if isstruct(fld) && isfield(fld, 'data')
                % Layout B: .data + optional .dofs
                data      = double(fld.data);
                dofs_     = {};
                if isfield(fld, 'dofs'), dofs_ = fld.dofs; end
                nStep     = size(data, 1);
                isLayoutC = false;
                isPlain   = false;
            elseif isstruct(fld)
                % Layout C: per-DOF struct (fld.sxx, fld.syy, ...)
                fn2 = fieldnames(fld);
                if isempty(fn2)
                    error('PlotUnstruResponse:InvalidEleResp', 'EleResp.%s has no sub-fields.', rt);
                end
                f1        = double(fld.(fn2{1}));
                nStep     = size(f1, 1);
                data      = fld;
                dofs_     = fn2;
                isLayoutC = true;
                isPlain   = false;
            elseif isnumeric(fld)
                % Plain matrix: [nStep x nNode] (e.g. PorePressureAtNode)
                data      = double(fld);
                nStep     = size(data, 1);
                dofs_     = {};
                isLayoutC = false;
                isPlain   = true;
            else
                error('PlotUnstruResponse:InvalidEleResp', ...
                    'EleResp.%s must be a struct or numeric array.', rt);
            end

            nodeFields = cell(nStep, 1);
            eleFields  = cell(nStep, 1);
            eleTags    = [];
            nodeTags   = obj.getRespNodeTagUnion(fld);
            if isempty(nodeTags)
                nodeTags = obj.getModelNodeTagUnion();
            end

            isNodeBased = unstru_is_node_based(rt) || isPlain;

            if isNodeBased
                for k = 1:nStep
                    [~, modelTags] = obj.getNodeStepData(k);
                    if isPlain
                        si = min(k, size(data,1));
                        scalarNode = double(data(si,:).');
                    elseif isLayoutC
                        scalarNode = obj.extractNodeScalarLayoutC(fld, k);
                    else
                        scalarNode = obj.extractNodeScalarAtStep(data, k, dofs_);
                    end
                    rTags = obj.getRespNodeTagsAtStep(fld, k);

                    if isempty(rTags)
                        nModelNode = numel(modelTags);
                        scalarNode = double(scalarNode(:));
                        if numel(scalarNode) == nModelNode
                            nodeFields{k} = scalarNode;
                            eleFields{k}  = [];
                        else
                            error('PlotUnstruResponse:MissingNodeTags', ...
                                ['AtNodes response requires nodeTags in EleResp.%s or EleResp.nodeTags, ' ...
                                 'unless the response length exactly matches the model node count.'], rt);
                        end
                        continue;
                    end

                    nodeFields{k} = obj.mapNodeScalarToCurrentModel(modelTags, scalarNode, rTags);
                    eleFields{k}  = [];
                end
                return;
            end

            if ~isfield(obj.EleResp, 'eleTags')
                error('PlotUnstruResponse:MissingEleTags', ...
                    'Element-based response requires EleResp.eleTags.');
            end

            eleTags = obj.getRespEleTagUnion();

            for k = 1:nStep
                [Pstep, ~] = obj.getNodeStepData(k);
                nModelNode = size(Pstep,1);
                [cells, ~, familyTags] = obj.getRespFamilyStepData(k);
                if isempty(cells)
                    nodeFields{k} = NaN(nModelNode,1);
                    eleFields{k} = zeros(0,1);
                    continue;
                end

                if isLayoutC
                    scalarEleRaw = obj.extractElementScalarLayoutC(fld, k);
                else
                    scalarEleRaw = obj.extractElementScalarAtStep(data, k, dofs_);
                end

                respTags = obj.getRespEleTagsAtStep(k);
                [scalarEleRaw, respTags] = obj.normalizeRespElementData(scalarEleRaw, respTags);

                scalarEle = NaN(size(cells,1),1);
                if ~isempty(respTags)
                    [tf, loc] = ismember(double(familyTags(:)), respTags(:));
                    respRows = zeros(numel(familyTags), 1);
                    respRows(tf) = loc(tf);
                    validRows = respRows > 0 & respRows <= numel(scalarEleRaw);
                    scalarEle(validRows) = scalarEleRaw(respRows(validRows));
                else
                    nCopy = min(numel(scalarEleRaw), numel(scalarEle));
                    scalarEle(1:nCopy) = scalarEleRaw(1:nCopy);
                end
                eleFields{k} = scalarEle;

                [cellsModel, ~, keepRows] = obj.remapCellsToModelRows(cells, k);
                scalarDisp = scalarEle(keepRows);

                nodeAcc = zeros(nModelNode,1);
                nodeCnt = zeros(nModelNode,1,'uint32');

                for e = 1:size(cellsModel,1)
                    if e > numel(scalarDisp) || ~isfinite(scalarDisp(e))
                        continue;
                    end

                    conn = double(cellsModel(e,:));
                    conn = conn(isfinite(conn) & conn > 0);
                    if isempty(conn)
                        continue;
                    end

                    n1 = conn(1);
                    if isfinite(n1) && n1 >= 3 && abs(round(n1) - n1) < 1e-12 && numel(conn) >= n1 + 1
                        ni = conn(2:1+n1);
                    else
                        ni = conn;
                    end
                    ni = ni(ni > 0 & ni <= nModelNode);
                    if isempty(ni), continue; end

                    nodeAcc(ni) = nodeAcc(ni) + scalarDisp(e);
                    nodeCnt(ni) = nodeCnt(ni) + 1;
                end

                mask = nodeCnt > 0;
                out = NaN(nModelNode,1);
                out(mask) = nodeAcc(mask) ./ double(nodeCnt(mask));
                nodeFields{k} = out;
            end
        end

        function scalarNode = extractNodeScalarAtStep(obj, data, stepIdx, dofs)
            nd = ndims(data);

            switch nd
                case 3
                    slice = reshape(data(stepIdx,:,:), size(data,2), size(data,3));
                    if isvector(slice), slice = slice(:); end
                    scalarNode = unstru_dof_scalar(slice, dofs, obj.Component);

                case 4
                    blk = reshape(data(stepIdx,:,:,:), size(data,2), size(data,3), size(data,4));
                    fibIdx = unstru_fiber_idx(obj.FiberPoint, size(blk,2));
                    slice = squeeze(blk(:, fibIdx, :));
                    if isvector(slice), slice = slice(:); end
                    scalarNode = unstru_dof_scalar(slice, dofs, obj.Component);

                otherwise
                    error('PlotUnstruResponse:UnsupportedNodeDataShape', ...
                        'Unsupported node response data dimension: %d', nd);
            end

            scalarNode = double(scalarNode(:));
        end

        function scalarEle = extractElementScalarAtStep(obj, data, stepIdx, dofs)
            nd = ndims(data);

            switch nd
                case 3
                    slice = reshape(data(stepIdx,:,:), size(data,2), size(data,3));
                    if isvector(slice), slice = slice(:); end
                    scalarEle = unstru_dof_scalar(slice, dofs, obj.Component);

                case 4
                    blk = reshape(data(stepIdx,:,:,:), size(data,2), size(data,3), size(data,4));
                    blk = obj.reduceGaussBlock(blk);
                    blk = squeeze(blk);
                    if isvector(blk), blk = blk(:); end
                    scalarEle = unstru_dof_scalar(blk, dofs, obj.Component);

                case 5
                    blk = reshape(data(stepIdx,:,:,:,:), size(data,2), size(data,3), size(data,4), size(data,5));
                    fibIdx = unstru_fiber_idx(obj.FiberPoint, size(blk,3));
                    blk = squeeze(blk(:,:,fibIdx,:));
                    blk = obj.reduceGaussBlock(blk);
                    blk = squeeze(blk);
                    if isvector(blk), blk = blk(:); end
                    scalarEle = unstru_dof_scalar(blk, dofs, obj.Component);

                otherwise
                    error('PlotUnstruResponse:UnsupportedElementDataShape', ...
                        'Unsupported response data dimension: %d', nd);
            end

            scalarEle = double(scalarEle(:));
        end

        function scalar = extractNodeScalarLayoutC(obj, entry, stepIdx)
            % Layout C node extraction: entry.(dofName) = [nStep x nNode]
            fn  = fieldnames(entry);
            idx = find(strcmpi(fn, obj.Component), 1);
            if isempty(idx)
                error('PlotUnstruResponse:ComponentNotFound', ...
                    'Component "%s" not found in %s. Available: %s', ...
                    obj.Component, obj.RespType, strjoin(fn.', ', '));
            end
            raw    = double(entry.(fn{idx}));
            si     = min(stepIdx, size(raw,1));
            scalar = double(raw(si,:).');
        end

        function scalar = extractElementScalarLayoutC(obj, entry, stepIdx)
            % Layout C element extraction:
            %   entry.(dofName) = [nStep x nEle x nGP]           (plane/solid)
            %   entry.(dofName) = [nStep x nEle x nGP x nFib]   (shell stress)
            fn  = fieldnames(entry);
            idx = find(strcmpi(fn, obj.Component), 1);
            if isempty(idx)
                error('PlotUnstruResponse:ComponentNotFound', ...
                    'Component "%s" not found in %s. Available: %s', ...
                    obj.Component, obj.RespType, strjoin(fn.', ', '));
            end
            raw = double(entry.(fn{idx}));  % [nStep x ...]
            si  = min(stepIdx, size(raw,1));
            nd  = ndims(raw);

            if nd == 2
                % [nStep x nEle] — already scalar per element
                scalar = double(raw(si,:).');
                return;
            end

            if nd == 3
                % [nStep x nEle x nGP]
                slice = reshape(raw(si,:,:), size(raw,2), size(raw,3));
                blk   = reshape(slice, size(slice,1), size(slice,2), 1);
                scalar = double(squeeze(obj.reduceGaussBlock(blk)));
            elseif nd == 4
                % [nStep x nEle x nGP x nFib] — shell stress, select fiber first
                slice = reshape(raw(si,:,:,:), size(raw,2), size(raw,3), size(raw,4));
                fibIdx = unstru_fiber_idx(obj.FiberPoint, size(slice,3));
                slice2 = slice(:,:,fibIdx);   % [nEle x nGP]
                blk    = reshape(slice2, size(slice2,1), size(slice2,2), 1);
                scalar = double(squeeze(obj.reduceGaussBlock(blk)));
            else
                scalar = double(raw(si,:,1).');
            end
            scalar = scalar(:);
        end

        function out = reduceGaussBlock(obj, blk)
            if isempty(blk)
                out = blk;
                return;
            end

            mode = lower(strtrim(char(string(obj.Opts.surf.gpReduce))));
            if isempty(mode)
                mode = 'mean';
            end

            switch mode
                case 'mean'
                    out = mean(blk, 2, 'omitnan');

                case 'max'
                    out = max(blk, [], 2);

                case 'min'
                    out = min(blk, [], 2);

                case 'absmax'
                    nEle = size(blk, 1);
                    nGp  = size(blk, 2);
                    nDof = size(blk, 3);
                    out  = NaN(nEle, 1, nDof);

                    absBlk = abs(blk);
                    absBlk(~isfinite(absBlk)) = -inf;
                    [~, idx] = max(absBlk, [], 2);

                    for d = 1:nDof
                        id = idx(:,1,d);
                        col = NaN(nEle,1);
                        for e = 1:nEle
                            if isfinite(id(e)) && id(e) >= 1 && id(e) <= nGp
                                col(e) = blk(e, id(e), d);
                            end
                        end
                        out(:,1,d) = col;
                    end

                case 'index'
                    gpIdx = round(double(obj.Opts.surf.gpIndex));
                    nGp = size(blk, 2);
                    gpIdx = max(1, min(nGp, gpIdx));
                    out = blk(:, gpIdx, :);

                otherwise
                    error('PlotUnstruResponse:InvalidGpReduce', ...
                        'Unknown gpReduce "%s". Use mean|max|min|absmax|index.', mode);
            end
        end

        function clim_ = resolveClim(obj, S)
            if ~isempty(obj.Opts.color.clim)
                clim_ = obj.Opts.color.clim;
                return;
            end

            mode = lower(char(string(obj.Opts.color.climMode)));
            switch mode
                case 'absmax'
                    [a,b] = obj.globalClim();
                    clim_ = [0, max(abs(a), abs(b))];
                case 'absmin'
                    [a,b] = obj.globalClim();
                    clim_ = [0, min(abs(a), abs(b))];
                case 'range'
                    [a,b] = obj.globalClim();
                    clim_ = [a,b];
                otherwise
                    Sf = S(isfinite(S));
                    if isempty(Sf)
                        clim_ = [0 1];
                        return;
                    end
                    a = min(Sf);
                    b = max(Sf);
                    if a == b, b = a + 1; end
                    clim_ = [a,b];
            end
        end

        function [h, pts] = drawLine(obj, P, lines, solidColor, lw, tag)
            h = gobjects(0);
            pts = zeros(0,3);
            if isempty(P) || isempty(lines), return; end

            s.nodes     = P;
            s.lines     = lines;
            s.lineWidth = lw;
            s.lineStyle = obj.Opts.line.lineStyle;
            s.color     = solidColor;
            s.tag       = tag;
            h = obj.Plotter.addLine(s);
            pts = P;
        end

        function [h, pts] = drawUnstructured(obj, Pdef, stepIdx, Snode, Sele, clim_, asUndeformed)
            h = gobjects(0);
            pts = zeros(0,3);

            if ~obj.Opts.surf.show, return; end
            if isempty(Pdef), return; end

            R0 = obj.getRespFamily(stepIdx);
            if isempty(R0), return; end
            if ~isfield(R0, 'Cells') || isempty(R0.Cells), return; end
            if ~isfield(R0, 'CellTypes') || isempty(R0.CellTypes), return; end

            [cells, types] = obj.getRespFamilyStepData(stepIdx);
            if isempty(cells)
                return;
            end

            [cellsModel, usedRows, keepRows] = obj.remapCellsToModelRows(cells, stepIdx);
            if isempty(cellsModel) || isempty(usedRows)
                return;
            end
            if ~isempty(types)
                types = obj.trimVectorLength(types, numel(keepRows));
                types = types(keepRows);
            end

            useNode = false;
            useEle  = false;
            mode = lower(char(string(obj.Opts.surf.colorMode)));

            switch mode
                case 'node'
                    useNode = ~isempty(Snode);

                case 'element'
                    useEle = ~isempty(Sele);

                otherwise
                    if unstru_is_node_based(obj.RespType)
                        useNode = ~isempty(Snode);
                    else
                        useEle = ~isempty(Sele);
                    end
            end

            if asUndeformed
                surfOut = plotter.utils.VTKElementTriangulator.triangulate(Pdef, types, cellsModel);

            elseif useEle
                if ~isempty(Sele)
                    Sele = obj.trimVectorLength(Sele, numel(keepRows));
                    Sele = Sele(keepRows);
                end
                surfOut = plotter.utils.VTKElementTriangulator.triangulate( ...
                    Pdef, types, cellsModel, 'Scalars', Sele, 'ScalarsByElement', true);

            elseif useNode
                if numel(Snode) ~= size(Pdef,1)
                    error('PlotUnstruResponse:ModelNodeSizeMismatch', ...
                        'Node scalar size (%d) does not match model node count (%d).', ...
                        numel(Snode), size(Pdef,1));
                end
                surfOut = plotter.utils.VTKElementTriangulator.triangulate( ...
                    Pdef, types, cellsModel, 'Scalars', Snode, 'ScalarsByElement', false);

            else
                surfOut = plotter.utils.VTKElementTriangulator.triangulate(Pdef, types, cellsModel);
            end

            if isempty(surfOut) || ~isfield(surfOut, 'Points') || isempty(surfOut.Points)
                return;
            end

            s.nodes = double(surfOut.Points);
            s.tris  = double(surfOut.Triangles);
            s.tag   = 'Surf';

            pts = double(surfOut.Points);
            if isfield(surfOut, 'EdgePoints') && ~isempty(surfOut.EdgePoints)
                pts = [pts; double(surfOut.EdgePoints)];
            end

            if asUndeformed
                s.faceColor = obj.Opts.color.undeformedColor;
                s.faceAlpha = obj.Opts.color.undeformedAlpha;
                h = obj.Plotter.addMesh(s);

            elseif useEle && isfield(surfOut,'CellScalars') && isfield(surfOut,'TriCellIds')
                triVals = double(surfOut.CellScalars(double(surfOut.TriCellIds(:))));
                s.values        = triVals;
                s.faceColorMode = 'flat';
                s.cmap          = obj.Opts.color.colormap;
                s.faceAlpha     = obj.Opts.color.deformedAlpha;
                if ~isempty(clim_), s.clim = clim_; end
                h = obj.Plotter.addColoredMesh(s);

            elseif useNode && isfield(surfOut,'PointScalars')
                s.values        = double(surfOut.PointScalars(:));
                s.faceColorMode = 'interp';
                s.cmap          = obj.Opts.color.colormap;
                s.faceAlpha     = obj.Opts.color.deformedAlpha;
                if ~isempty(clim_), s.clim = clim_; end
                h = obj.Plotter.addColoredMesh(s);

            else
                s.faceColor = obj.Opts.color.solidColor;
                s.faceAlpha = obj.Opts.color.deformedAlpha;
                h = obj.Plotter.addMesh(s);
            end

            if obj.Opts.surf.showEdges && ...
               isfield(surfOut, 'EdgePoints') && ~isempty(surfOut.EdgePoints)
                w.points    = surfOut.EdgePoints;
                w.color     = obj.Opts.surf.edgeColor;
                w.lineWidth = obj.Opts.surf.edgeWidth;
                obj.Plotter.addLine(w);
            end
        end

        function [h, pts] = drawFixed(obj, Pdef, stepIdx)
            h = gobjects(0);
            pts = zeros(0,3);
            if ~obj.Opts.fixed.show, return; end

            if ~isfield(obj.ModelInfo,'Fixed') || ...
               ~isfield(obj.ModelInfo.Fixed,'NodeIndex') || ...
               isempty(obj.ModelInfo.Fixed.NodeIndex)
                return;
            end

            ni = obj.ModelInfo.Fixed.NodeIndex;
            if obj.ModelUpdateFlag && ~isvector(ni)
                ni = ni(min(stepIdx, size(ni,1)), :);
            end
            idx = double(ni(:));

            idx = idx(isfinite(idx));
            [~, rawToClean] = obj.getNodeStepSelection(stepIdx);
            valid = idx >= 1 & idx <= numel(rawToClean);
            idx = idx(valid);
            if isempty(idx), return; end

            idx = rawToClean(round(idx));
            idx = idx(idx >= 1 & idx <= size(Pdef,1));
            if isempty(idx), return; end

            s.points    = Pdef(idx,:);
            s.size      = obj.Opts.fixed.size;
            s.marker    = obj.Opts.fixed.marker;
            s.filled    = obj.Opts.fixed.filled;
            s.edgeColor = obj.Opts.fixed.edgeColor;
            s.color     = obj.Opts.fixed.color;
            s.tag       = 'FixedNodes';
            h = obj.Plotter.addPoints(s);
            pts = s.points;
        end

        function prepareAxes(obj)
            if obj.Opts.general.clearAxes
                cla(obj.Ax, 'reset');
                hold(obj.Ax, 'on');
            elseif obj.Opts.general.holdOn
                hold(obj.Ax, 'on');
            end

            if obj.Opts.general.axisEqual, axis(obj.Ax, 'equal'); end
            if obj.Opts.general.grid
                grid(obj.Ax, 'on');
            else
                grid(obj.Ax, 'off');
            end
            if obj.Opts.general.box
                box(obj.Ax, 'on');
            else
                box(obj.Ax, 'off');
            end

            colormap(obj.Ax, obj.Opts.color.colormap);
            obj.applyFigureSize();
        end

        function applyFigureSize(obj)
            figSize = obj.Opts.general.figureSize;
            if isempty(figSize)
                return;
            end

            fig = ancestor(obj.Ax, 'figure');
            if isempty(fig) || ~isgraphics(fig, 'figure')
                return;
            end

            fig.Units = 'pixels';
            pos = fig.Position;
            figSize = double(figSize(:).');

            if numel(figSize) == 2
                pos(3:4) = figSize;
            elseif numel(figSize) == 4
                pos = figSize;
            else
                error('PlotUnstruResponse:InvalidFigureSize', ...
                    'general.figureSize must be [width height] or [left bottom width height].');
            end

            fig.Position = pos;
        end

        function applyView(obj)
            v = lower(char(string(obj.Opts.general.view)));
            if strcmp(v, 'auto')
                if obj.CachedModelDim == 2
                    view(obj.Ax, 2);
                else
                    view(obj.Ax, 3);
                end
                return;
            end

            switch v
                case 'iso'
                    view(obj.Ax, 3);
                case 'xy'
                    view(obj.Ax, 2);
                case 'yx'
                    view(obj.Ax, 90, 90);
                case 'xz'
                    view(obj.Ax, 0, 0);
                case 'zx'
                    view(obj.Ax, 180, 0);
                case 'yz'
                    view(obj.Ax, 90, 0);
                case 'zy'
                    view(obj.Ax, -90, 0);
                otherwise
                    if obj.CachedModelDim == 2
                        view(obj.Ax, 2);
                    else
                        view(obj.Ax, 3);
                    end
            end
        end

        function applyDisplayLimits(obj, P)
            if isempty(P) || ~ismatrix(P)
                return;
            end

            P = double(P);
            if size(P,2) < 3
                P(:,3) = 0;
            end

            valid = all(isfinite(P), 2);
            P = P(valid, :);
            if isempty(P)
                return;
            end

            xmin = min(P(:,1)); xmax = max(P(:,1));
            ymin = min(P(:,2)); ymax = max(P(:,2));
            zmin = min(P(:,3)); zmax = max(P(:,3));

            dx = xmax - xmin;
            dy = ymax - ymin;
            dz = zmax - zmin;
            L  = max([dx, dy, dz, obj.CachedModelSize, 1]);

            pad = max(obj.Opts.general.padRatio * L, 1e-6);

            xlim(obj.Ax, [xmin - pad, xmax + pad]);
            ylim(obj.Ax, [ymin - pad, ymax + pad]);

            if obj.CachedModelDim == 3
                zlim(obj.Ax, [zmin - pad, zmax + pad]);
            end
        end

        function applyTitle(obj, stepIdx)
            t = string(obj.Opts.general.title);
            if strcmpi(t, 'auto')
                if isfield(obj.NodalResp,'time') && numel(obj.NodalResp.time) >= stepIdx
                    time_ = obj.NodalResp.time(stepIdx);
                else
                    time_ = NaN;
                end

                fpTxt = '';
                if ~isempty(obj.FiberPoint)
                    if ischar(obj.FiberPoint) || isstring(obj.FiberPoint) || ...
                            (isnumeric(obj.FiberPoint) && isscalar(obj.FiberPoint))
                        fpTxt = sprintf('  |  fiber=%s', char(string(obj.FiberPoint)));
                    end
                end

                gpTxt = '';
                if ~unstru_is_node_based(obj.RespType)
                    gpMode = lower(strtrim(char(string(obj.Opts.surf.gpReduce))));
                    if strcmp(gpMode, 'index')
                        gpTxt = sprintf('  |  gp=%d', round(double(obj.Opts.surf.gpIndex)));
                    else
                        gpTxt = sprintf('  |  gp=%s', gpMode);
                    end
                end

                title(obj.Ax, sprintf('%s  %s  %s%s%s\nstep %d  |  t = %.4g s', ...
                    obj.EleType, obj.RespType, obj.Component, fpTxt, gpTxt, stepIdx-1, time_));
            elseif strlength(t) > 0
                title(obj.Ax, char(t));
            end
        end

        function applyColorbar(obj, clim_)
            if ~obj.Opts.color.useColormap || ~obj.Opts.cbar.show
                colorbar(obj.Ax, 'off');
                return;
            end
            if ~isempty(clim_) && diff(clim_) > 0
                clim(obj.Ax, clim_);
            end
            cb = colorbar(obj.Ax);
            cb.FontSize = 11;
            cb.TickDirection = 'in';
            cb.Title.String = '';
            cb.Label.String = obj.getColorbarSideTitle();
            cb.Label.FontSize = 13;
            cb.Label.FontWeight = 'normal';
        end

        function titleText = getColorbarSideTitle(obj)
            baseTitle = char(string(obj.cbarTitle));
            extraLabel = string(obj.Opts.cbar.label);

            if strlength(strtrim(extraLabel)) > 0
                if isempty(strtrim(baseTitle))
                    titleText = char(extraLabel);
                else
                    titleText = sprintf('%s | %s', baseTitle, char(extraLabel));
                end
            else
                titleText = baseTitle;
            end
        end

        function dim = computeModelDim(~, P)
            if isempty(P) || size(P,2) < 3
                dim = 2;
                return;
            end
            z = P(:,3);
            if all(isnan(z) | abs(z) < 1e-12)
                dim = 2;
            else
                dim = 3;
            end
        end

        function L = computeModelLength(~, P)
            if isempty(P), L = 1; return; end
            ext = max(P,[],1,'omitnan') - min(P,[],1,'omitnan');
            ext = ext(isfinite(ext));
            if isempty(ext), L = 1; return; end
            L = max(ext);
            if ~isfinite(L) || L <= 0, L = 1; end
        end

        function U3 = extractXYZ(~, U)
            U3 = zeros(size(U,1), 3);
            U3(:,1:min(3,size(U,2))) = U(:,1:min(3,size(U,2)));
        end

        function rt = normalizeRespType(obj, rt)
            % Case-insensitive lookup against actual EleResp field names.
            rt = char(rt);
            if isfield(obj.EleResp, rt), return; end
            fn = fieldnames(obj.EleResp);
            match = fn(strcmpi(fn, rt));
            if ~isempty(match), rt = match{1}; end
        end

        function key = makeRespKey(obj)
            if isempty(obj.FiberPoint)
                fp = '';
            elseif isnumeric(obj.FiberPoint) && isscalar(obj.FiberPoint)
                fp = sprintf('%g', obj.FiberPoint);
            elseif ischar(obj.FiberPoint)
                fp = obj.FiberPoint;
            elseif isstring(obj.FiberPoint) && isscalar(obj.FiberPoint)
                fp = char(obj.FiberPoint);
            else
                fp = char(strjoin(string(obj.FiberPoint), "_"));
            end

            gpMode = lower(strtrim(char(string(obj.Opts.surf.gpReduce))));
            gpIdx  = round(double(obj.Opts.surf.gpIndex));

            key = sprintf('%s|%s|%s|%s|%s|%d', ...
                char(string(obj.EleType)), ...
                char(string(obj.RespType)), ...
                char(string(obj.Component)), ...
                fp, gpMode, gpIdx);
        end

        function out = mergeStruct(obj, base, add)
            out = base;
            if isempty(add) || ~isstruct(add), return; end
            for fn = fieldnames(add).'
                n = fn{1};
                if isfield(out,n) && isstruct(out.(n)) && isstruct(add.(n))
                    out.(n) = obj.mergeStruct(out.(n), add.(n));
                else
                    out.(n) = add.(n);
                end
            end
        end
    end
end

function [rt, comp, fp] = unstru_check_shell(rt, comp, fp)
    if isempty(rt), rt = ''; end
    rt0   = lower(strrep(char(rt), ' ', ''));
    isN   = contains(rt0, 'node');
    isDefo = contains(rt0, 'defo');

    if isempty(comp), comp = 'mxx'; end
    cl = lower(strtrim(char(comp)));

    % Alias: legacy sigma/eps notation → canonical Layout C DOF field names
    aliases = { ...
        'sigma11','sxx'; 'sigma22','syy'; 'sigma12','sxy'; ...
        'sigma23','syz'; 'sigma13','sxz'; ...
        'eps11','exx';   'eps22','eyy';   'eps12','exy'; ...
        'eps23','eyz';   'eps13','exz'};
    for k = 1:size(aliases,1)
        if strcmp(cl, aliases{k,1}), cl = aliases{k,2}; break; end
    end
    comp = cl;

    secComp    = {'fxx','fyy','fxy','mxx','myy','mxy','vxz','vyz'};
    stressComp = {'sxx','syy','sxy','syz','sxz'};
    strainComp = {'exx','eyy','exy','eyz','exz'};

    if ismember(cl, secComp)
        if isDefo
            rt = 'SecDefoAtGP';   if isN, rt = 'SecDefoAtNode';  end
        else
            rt = 'SecForceAtGP';  if isN, rt = 'SecForceAtNode'; end
        end
        fp = [];
    elseif ismember(cl, stressComp)
        rt = 'StressAtGP';  if isN, rt = 'StressAtNode'; end
        if isempty(fp), fp = 'top'; end
        if ischar(fp) || isstring(fp)
            fp = lower(char(fp));
            if ~ismember(fp, {'top','bottom','middle'})
                error('PlotUnstruResponse:BadFiberPoint', ...
                    'fiberPoint must be top|bottom|middle or integer.');
            end
        end
    elseif ismember(cl, strainComp)
        rt = 'StrainAtGP';  if isN, rt = 'StrainAtNode'; end
        if isempty(fp), fp = 'top'; end
        if ischar(fp) || isstring(fp)
            fp = lower(char(fp));
            if ~ismember(fp, {'top','bottom','middle'})
                error('PlotUnstruResponse:BadFiberPoint', ...
                    'fiberPoint must be top|bottom|middle or integer.');
            end
        end
    else
        error('PlotUnstruResponse:BadComponent', ...
            'Shell component "%s" not recognised. Use: %s | %s | %s.', ...
            comp, strjoin(secComp,','), strjoin(stressComp,','), strjoin(strainComp,','));
    end
end

function [rt, comp] = unstru_check_plane(rt, comp)
    if isempty(rt), rt = ''; end
    rt0 = lower(strrep(char(rt), ' ', ''));
    isN = contains(rt0, 'node');

    if isempty(comp), comp = 'sxx'; end
    cl = lower(strtrim(char(comp)));

    % Alias: legacy sigma/eps notation → canonical DOF field names
    aliases = { ...
        'sigma11','sxx'; 'sigma22','syy'; 'sigma12','sxy'; 'sigma33','szz'; ...
        'eps11','exx';   'eps22','eyy';   'eps12','exy'};
    for k = 1:size(aliases,1)
        if strcmp(cl, aliases{k,1}), cl = aliases{k,2}; break; end
    end
    comp = cl;

    stressComp = {'sxx','syy','szz','sxy'};
    strainComp = {'exx','eyy','exy'};
    measures   = {'p1','p2','p3','sigmavm','taumax','sigmaoct','tauoct','theta'};

    if ismember(cl, stressComp)
        rt = 'StressAtGP';        if isN, rt = 'StressAtNode'; end
    elseif ismember(cl, strainComp)
        rt = 'StrainAtGP';        if isN, rt = 'StrainAtNode'; end
    elseif ismember(cl, measures)
        rt = 'StressMeasureAtGP'; if isN, rt = 'StressMeasureAtNode'; end
    else
        error('PlotUnstruResponse:BadComponent', ...
            'Plane component "%s" not recognised. Use: %s | %s | %s.', ...
            comp, strjoin(stressComp,','), strjoin(strainComp,','), strjoin(measures,','));
    end
end

function [rt, comp] = unstru_check_solid(rt, comp)
    if isempty(rt), rt = ''; end
    rt0 = lower(strrep(char(rt), ' ', ''));
    isN = contains(rt0, 'node');

    if isempty(comp), comp = 'sxx'; end
    cl = lower(strtrim(char(comp)));

    % Alias: legacy sigma/eps notation → canonical DOF field names
    aliases = { ...
        'sigma11','sxx'; 'sigma22','syy'; 'sigma33','szz'; ...
        'sigma12','sxy'; 'sigma23','syz'; 'sigma13','sxz'; ...
        'eps11','exx';   'eps22','eyy';   'eps33','ezz'; ...
        'eps12','exy';   'eps23','eyz';   'eps13','exz'};
    for k = 1:size(aliases,1)
        if strcmp(cl, aliases{k,1}), cl = aliases{k,2}; break; end
    end
    comp = cl;

    stressComp = {'sxx','syy','szz','sxy','syz','sxz'};
    strainComp = {'exx','eyy','ezz','exy','eyz','exz'};
    measures   = {'p1','p2','p3','sigmavm','taumax','sigmaoct','tauoct'};

    if ismember(cl, stressComp)
        rt = 'StressAtGP';        if isN, rt = 'StressAtNode'; end
    elseif ismember(cl, strainComp)
        rt = 'StrainAtGP';        if isN, rt = 'StrainAtNode'; end
    elseif ismember(cl, measures)
        rt = 'StressMeasureAtGP'; if isN, rt = 'StressMeasureAtNode'; end
    else
        error('PlotUnstruResponse:BadComponent', ...
            'Solid component "%s" not recognised. Use: %s | %s | %s.', ...
            comp, strjoin(stressComp,','), strjoin(strainComp,','), strjoin(measures,','));
    end
end

function scalar = unstru_dof_scalar(mat, dofs, component)
    if isempty(mat)
        scalar = zeros(0,1);
        return;
    end

    if isvector(mat)
        mat = mat(:);
    end

    comp = strtrim(char(string(component)));

    if iscell(dofs) && isscalar(dofs) && iscell(dofs{1})
        dofs = dofs{1};
    end

    for d = 1:numel(dofs)
        name = strtrim(char(string(dofs{d})));
        if strcmpi(name, comp)
            if size(mat,2) >= d
                scalar = mat(:,d);
            else
                scalar = zeros(size(mat,1),1);
            end
            return;
        end
    end

    error('PlotUnstruResponse:DofNotFound', ...
        'Component "%s" not found in dofs.', component);
end

function idx = unstru_fiber_idx(fp, nFib)
    if isempty(fp)
        idx = nFib;
        return;
    end

    if ischar(fp) || isstring(fp)
        switch lower(char(fp))
            case 'top'
                idx = nFib;
            case 'bottom'
                idx = 1;
            case 'middle'
                idx = max(1, round(nFib/2));
            otherwise
                idx = nFib;
        end
    else
        idx = max(1, min(nFib, round(double(fp))));
    end
end

function tf = unstru_is_node_based(rt)
    tf = ~isempty(regexpi(rt, 'atnode', 'once'));
end