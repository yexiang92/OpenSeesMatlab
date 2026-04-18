classdef PlotNodalResp < handle
    % PlotNodalResp
    % Nodal response visualisation based on PatchPlotter.
    %
    % Features
    % --------
    % 1) Step-aware deformation scaling.
    % 2) Global colour limits (range / absMax / absMin / step modes).
    % 3) Cached nearest-neighbour scalar mapping for fixed topology.
    % 4) Interpolated beam-displacement line rendering when nodalResp
    %    contains interpolatePoints / interpolateDisp / interpolateCells
    %    AND opts.interp.useInterpolation = true.
    %
    % Quick start
    % -----------
    %   pr = plotter.PlotNodalResp(modelInfo, nodalResp);
    %   pr.plotStep('absmax');

    properties
        ModelInfo   struct
        NodalResp   struct
        Plotter     plotter.PatchPlotter
        Ax          matlab.graphics.axis.Axes
        Opts        struct
        Handles     struct = struct()
    end

    properties (Access = private)
        CachedModelDim   double  = 3
        CachedModelSize  double  = 1
        ModelUpdateFlag  logical = false

        GlobalClimCache  double = []
        GlobalClimField  char   = ''
        GlobalClimComp   char   = ''

        KnnIdxCache      double = []
        KnnRefPtCount    double = 0
        KnnQueryPtCount  double = 0

        RespTagToIdx     double = []
        RespTagToIdxMap         = []
    end

    % =====================================================================
    methods (Static)

        function opts = defaultOptions()
            opts = struct();

            opts.general = struct( ...
                'clearAxes', true,  'holdOn',    true, 'axisEqual', true, ...
                'grid',      true,  'box',       false,'view',      'auto', ...
                'title',     'auto','padRatio',  0.15, 'figureSize',[1000, 618]);

            opts.field  = struct('type','disp', 'component','magnitude', 'show',true);

            opts.deform = struct( ...
                'show',true, 'type','disp', 'scale',1, ...
                'autoScale',true, 'showUndeformed',false);

            opts.interp = struct( ...
                'useInterpolation',true, 'lineWidth',1.5, ...
                'lineStyle','-', 'undeformedLineWidth',0.8);

            opts.vector = struct( ...
                'show',false, 'type','reaction', 'components',[1 2 3], ...
                'scale',0.05, 'autoScale',true, ...
                'color',[0.85 0.33 0.10], 'lineWidth',1.2);

            opts.color  = struct( ...
                'useColormap',true, 'colormap',turbo(256), 'clim',[], ...
                'climMode','step', 'solidColor','#3A86FF', ...
                'undeformedColor','#d8dcd6', 'undeformedAlpha',1.0, 'deformedAlpha',1.0);

            opts.line   = struct( ...
                'show',true, 'lineWidth',1.5, 'lineStyle','-', ...
                'undeformedLineWidth',0.8);

            opts.surf   = struct('show',true, 'showEdges',true, 'edgeColor','black', 'edgeWidth',0.8);

            opts.nodes  = struct('show',false, 'size',20, 'marker','o', 'filled',true, 'edgeColor','none');

            opts.fixed  = struct( ...
                'show',true, 'size',40, 'marker','s', 'filled',true, ...
                'edgeColor','#000000', 'color','#8c000f');

            opts.cbar   = struct('show',true, 'label','');
        end

    end

    % =====================================================================
    methods

        function obj = PlotNodalResp(modelInfo, nodalResp, ax, opts)
            if nargin < 1 || isempty(modelInfo)
                error('PlotNodalResp:InvalidInput','modelInfo must be provided.');
            end
            if nargin < 2 || isempty(nodalResp)
                error('PlotNodalResp:InvalidInput','nodalResp must be provided.');
            end
            if nargin < 3, ax   = []; end
            if nargin < 4, opts = []; end

            obj.ModelInfo = modelInfo;
            obj.NodalResp = nodalResp;
            obj.Opts      = obj.mergeStruct(plotter.PlotNodalResp.defaultOptions(), opts);
            obj.Plotter   = plotter.PatchPlotter(ax);
            obj.Ax        = obj.Plotter.Ax;

            if isfield(nodalResp,'ModelUpdate')
                obj.ModelUpdateFlag = logical(nodalResp.ModelUpdate);
            elseif isfield(modelInfo,'Nodes') && isfield(modelInfo.Nodes,'Coords')
                obj.ModelUpdateFlag = (ndims(modelInfo.Nodes.Coords) == 3);
            end

            P = obj.getNodeCoords(1);
            obj.CachedModelDim  = obj.computeModelDim(P);
            obj.CachedModelSize = obj.computeModelLength(P);
            obj.buildRespTagLookup();
        end

        function ax = getAxes(obj), ax = obj.Ax; end

        function setOptions(obj, opts)
            prevField    = obj.Opts.field.type;
            prevComp     = obj.Opts.field.component;

            obj.Opts = obj.mergeStruct(obj.Opts, opts);

            if ~strcmp(prevField, obj.Opts.field.type) || ...
               ~strcmp(prevComp,  obj.Opts.field.component)
                obj.GlobalClimCache = [];
                obj.GlobalClimField = '';
                obj.GlobalClimComp  = '';
            end
        end

        function h = plotStep(obj, stepIdx, opts)
            if nargin >= 3 && ~isempty(opts), obj.setOptions(opts); end
            stepIdx = obj.resolveStepIdx(stepIdx);
            obj.prepareAxes();
            obj.Handles = struct();
            obj.renderStep(stepIdx);
            h = obj.Handles;
        end

        function [cmin, cmax] = globalClim(obj, fieldType, component)
            if nargin < 2, fieldType = obj.Opts.field.type;      end
            if nargin < 3, component = obj.Opts.field.component; end

            if ~isempty(obj.GlobalClimCache) && ...
               strcmp(obj.GlobalClimField, fieldType) && ...
               strcmp(obj.GlobalClimComp,  component)
                cmin = obj.GlobalClimCache(1);
                cmax = obj.GlobalClimCache(2);
                return;
            end

            allMin = inf;  allMax = -inf;
            for k = 1:obj.nSteps()
                S = obj.getStepScalarValues(k, fieldType, component);
                if ~isempty(S)
                    allMin = min(allMin, min(S, [], 'omitnan'));
                    allMax = max(allMax, max(S, [], 'omitnan'));
                end
            end

            if ~isfinite(allMin), allMin = 0; end
            if ~isfinite(allMax), allMax = 1; end
            if allMin == allMax,  allMax = allMin + 1; end

            obj.GlobalClimCache = [allMin allMax];
            obj.GlobalClimField = fieldType;
            obj.GlobalClimComp  = component;
            cmin = allMin;  cmax = allMax;
        end

    end

    % =====================================================================
    methods (Access = private)

        % =================================================================
        % Core render
        % =================================================================

        function renderStep(obj, stepIdx)
            P        = obj.getNodeCoords(stepIdx);
            lineConn = obj.getLineConn(stepIdx);
            [Pdef, ~, ~] = obj.getDeformedCoords(P, stepIdx);
            [Snode, clim_] = obj.getScalarField(stepIdx);
            shownPts = Pdef;

            if obj.Opts.deform.show && obj.Opts.deform.showUndeformed
                obj.Handles.UndeformedLine = obj.drawLine( ...
                    P, lineConn, obj.Opts.color.undeformedColor, ...
                    obj.Opts.line.undeformedLineWidth, 'UndeformedLine');
                obj.Handles.UndeformedSurf = obj.drawUnstructured( ...
                    P, stepIdx, [], [], true);
            end

            if obj.Opts.line.show
                if obj.hasInterpData(stepIdx) && obj.Opts.interp.useInterpolation
                    [obj.Handles.Line, Pline] = obj.drawInterpolatedLine(stepIdx, Snode, clim_);
                    shownPts = [shownPts; Pline];
                else
                    obj.Handles.Line = obj.drawLine( ...
                        Pdef, lineConn, obj.Opts.color.solidColor, ...
                        obj.Opts.line.lineWidth, 'Line', Snode, clim_);
                end
            end

            if obj.Opts.surf.show
                obj.Handles.Surf = obj.drawUnstructured(Pdef, stepIdx, Snode, clim_, false);
            end
            if obj.Opts.nodes.show
                obj.Handles.Nodes = obj.drawNodes(Pdef, Snode, clim_);
            end

            obj.Handles.Fixed = obj.drawFixed(Pdef, stepIdx);

            if obj.Opts.vector.show
                obj.Handles.Vector = obj.drawVectorField(Pdef, stepIdx);
            end

            obj.applyColorbar(clim_);
            obj.applyTitle(stepIdx);
            obj.applyView();
            obj.Plotter.applyDataLimits(shownPts, obj.Opts.general.padRatio);
        end

        % =================================================================
        % Interpolated beam line
        % =================================================================

        function tf = hasInterpData(obj, stepIdx)
            tf = isfield(obj.NodalResp,'interpolatePoints') && ...
                 isfield(obj.NodalResp,'interpolateDisp')   && ...
                 isfield(obj.NodalResp,'interpolateCells')  && ...
                 ~isempty(obj.NodalResp.interpolatePoints);
            if ~tf, return; end
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
            if size(pts,2)  < 3, pts(:,3)   = 0; end
            if size(disp_,2)< 3, disp_(:,3) = 0; end

            if ndims(cells_) == 3
                si     = min(stepIdx, size(cells_,1));
                cells_ = squeeze(cells_(si,:,:));
            end
            if ~isempty(cells_)
                cells_ = cells_(~all(isnan(cells_), 2), :);
            end

            valid = ~all(isnan(pts), 2);
            if size(disp_,1) == size(pts,1)
                valid = valid & ~all(isnan(disp_), 2);
            end
            rawToClean = zeros(size(pts,1), 1);
            rawToClean(valid) = 1:nnz(valid);

            pts = pts(valid,:);
            disp_ = disp_(valid,:);

            if isempty(cells_)
                cells = zeros(0, 2);
                return;
            end

            if size(cells_,2) >= 3
                cells = cells_(:,end-1:end);
            else
                cells = cells_;
            end

            cells = round(cells);
            validCells = all(isfinite(cells), 2) & all(cells >= 1, 2) & ...
                all(cells <= numel(rawToClean), 2);
            cells = cells(validCells, :);
            if isempty(cells)
                return;
            end

            cells = rawToClean(cells);
            cells = cells(all(cells >= 1, 2), :);
        end

        function [h, Pline] = drawInterpolatedLine(obj, stepIdx, Snode, clim_)
            h = gobjects(0);
            Pline = zeros(0,3);
            [pts, disp_, cells] = obj.getInterpSlice(stepIdx);
            if isempty(pts) || isempty(cells), return; end

            scale = obj.resolveDeformScale(stepIdx);
            U3    = disp_(:,1:min(3,size(disp_,2)));
            if size(U3,2) < 3, U3(:,end+1:3) = 0; end
            Pline = pts + scale * U3;

            s.nodes     = Pline;
            s.lines     = cells;
            s.lineWidth = obj.Opts.interp.lineWidth;
            s.lineStyle = obj.Opts.interp.lineStyle;
            s.tag       = 'InterpLine';

            if obj.Opts.color.useColormap
                if ~isempty(Snode)
                    if strcmpi(obj.Opts.field.type, 'disp')
                        sval = obj.computeScalarFieldWithComp( ...
                            disp_, obj.Opts.field.component, ...
                            obj.getRespDofs(obj.Opts.field.type));
                        mode = lower(char(string(obj.Opts.color.climMode)));
                        if ismember(mode, {'step','local','current'})
                            clim_ = obj.localClim(sval);
                        end
                    else
                        Pnode = obj.getNodeCoords(stepIdx);
                        if numel(Snode) == size(Pnode,1)
                            sval = obj.mapScalarsByNN(pts, Pnode, Snode);
                        else
                            sval = [];
                        end
                    end
                else
                    sval = [];
                end

                if ~isempty(sval)
                    s.values = sval;
                    s.cmap   = obj.Opts.color.colormap;
                    if ~isempty(clim_), s.clim = clim_; end
                    h = obj.Plotter.addColoredLine(s);
                else
                    s.color = obj.Opts.color.solidColor;
                    h = obj.Plotter.addLine(s);
                end
            else
                s.color = obj.Opts.color.solidColor;
                h = obj.Plotter.addLine(s);
            end
        end

        % =================================================================
        % Deformation helpers
        % =================================================================

        function [Pdef, U3, scale] = getDeformedCoords(obj, P, stepIdx)
            if obj.Opts.deform.show
                U     = obj.getRespSlice(obj.Opts.deform.type, stepIdx);
                U3    = obj.extractXYZ(U);
                scale = obj.resolveDeformScale(stepIdx);
                Pdef  = P + scale * U3;
            else
                U3    = zeros(size(P));
                scale = 0;
                Pdef  = P;
            end
        end

        function scale = resolveDeformScale(obj, stepIdx)
            if nargin < 2 || isempty(stepIdx)
                stepIdx = 1;
            end
            if obj.Opts.deform.autoScale
                scale = obj.currentDeformScale(stepIdx);
            else
                scale = obj.Opts.deform.scale;
            end
        end

        function scale = currentDeformScale(obj, stepIdx)
            fieldType = obj.Opts.deform.type;
            baseScale = obj.Opts.deform.scale;
            if ~obj.Opts.deform.autoScale
                scale = baseScale;  return;
            end

            P = obj.getNodeCoords(stepIdx);
            modelSize = obj.computeModelLength(P);
            umax = obj.getStepPeakMagnitude(fieldType, stepIdx);

            if ~isfinite(modelSize) || modelSize <= 0
                modelSize = 1;
            end

            if ~isfinite(umax) || umax <= 0
                scale = baseScale;
            else
                scale = baseScale * modelSize / (10 * umax);
            end
        end

        function [S, clim_] = getScalarField(obj, stepIdx)
            if obj.Opts.field.show && obj.Opts.color.useColormap
                Uf    = obj.getRespSlice(obj.Opts.field.type, stepIdx);
                S     = obj.computeScalarField(Uf);
                clim_ = obj.resolveClim(S);
            else
                S = [];  clim_ = [];
            end
        end

        % =================================================================
        % Step resolution
        % =================================================================

        function stepIdx = resolveStepIdx(obj, stepIdx)
            if isnumeric(stepIdx)
                stepIdx = round(stepIdx);
                stepIdx = stepIdx + 1;
                n = obj.nSteps();
                if stepIdx < 1 || stepIdx > n
                    error('PlotNodalResp:InvalidStep', ...
                        'stepIdx %d out of range [0, %d].', stepIdx-1, n-1);
                end
                return;
            end
            key  = obj.normalizeStepSelector(stepIdx);
            n    = obj.nSteps();
            [searchFieldType, searchComponent] = obj.getStepSearchSpec();
            vals = obj.initStepSelectorValues(key, n);
            for k = 1:n
                S = obj.getStepScalarValues(k, searchFieldType, searchComponent, false);
                if isempty(S), continue; end
                switch key
                    case {'absmax','absmin'}, vals(k) = max(abs(S), [], 'omitnan');
                    case 'max',               vals(k) = max(S, [], 'omitnan');
                    case 'min',               vals(k) = min(S, [], 'omitnan');
                    otherwise
                        error('PlotNodalResp:InvalidStepIdx', ...
                            'Unknown stepIdx "%s". Use absmax|absmin|max|min or stepMax-style aliases.', key);
                end
            end
            switch key
                case {'absmax','max'}, [~, stepIdx] = max(vals, [], 'omitnan');
                case {'absmin','min'}, [~, stepIdx] = min(vals, [], 'omitnan');
            end
        end

        % =================================================================
        % Topology access
        % =================================================================

        function P = getNodeCoords(obj, stepIdx)
            [P, ~] = obj.getNodeStepData(stepIdx);
        end

        function lines = getLineConn(obj, stepIdx)
            lines = zeros(0, 2);
            fam   = obj.getFamilies(stepIdx);
            if ~isfield(fam,'Line') || ~isfield(fam.Line,'Cells') || ...
               isempty(fam.Line.Cells), return; end
            C = double(fam.Line.Cells);
            if obj.ModelUpdateFlag && ndims(C) == 3
                C = squeeze(C(min(stepIdx, size(C,1)), :, :));
            end
            if ~isempty(C)
                C = C(~all(isnan(C), 2), :);
            end
            if size(C,2) >= 3,     lines = C(:,end-1:end);
            elseif size(C,2) == 2, lines = C;
            end
            [~, rawToClean] = obj.getNodeStepSelection(stepIdx);
            lines = round(lines);
            valid = all(isfinite(lines), 2) & all(lines >= 1, 2) & all(lines <= numel(rawToClean), 2);
            lines = lines(valid, :);
            if isempty(lines), return; end
            lines = rawToClean(lines);
            lines = lines(all(lines >= 1, 2), :);
        end

        function fam = getFamilies(obj, ~)
            fam = struct();
            if ~isfield(obj.ModelInfo,'Elements'), return; end
            E = obj.ModelInfo.Elements;
            if isfield(E,'Families'), fam = E.Families;
            else,                     fam = E;           end
        end

        % =================================================================
        % Response data access
        % =================================================================

        function U = getRespSlice(obj, fieldType, stepIdx)
            % Supports three nodalResp layouts:
            %   (A) nodalResp.<field>        = [nStep x nNode x nDof]  (legacy)
            %   (B) nodalResp.<field>.data   = [nStep x nNode x nDof]  (old struct)
            %       nodalResp.<field>.dofs   = {1 x nDof} cell
            %   (C) nodalResp.<field>.<dof>  = [nStep x nNode]  (current per-DOF)
            %
            fieldType = obj.normalizeFieldType(fieldType);
            [Pmodel, modelTags] = obj.getNodeStepData(stepIdx);
            nModel = size(Pmodel, 1);
            U = NaN(nModel, 6);
            if ~isfield(obj.NodalResp, fieldType), return; end

            entry = obj.NodalResp.(fieldType);

            if isstruct(entry) && isfield(entry, 'data')
                % Layout B
                arr = entry.data;
                if isempty(arr) || ndims(arr) < 3, return; end
                si   = min(stepIdx, size(arr, 1));
                Uraw = double(reshape(arr(si,:,:), size(arr,2), size(arr,3)));
            elseif isstruct(entry)
                % Layout C: per-DOF struct  (entry.ux, entry.uy, ...)
                dofFields = fieldnames(entry);
                if isempty(dofFields), return; end
                firstArr = entry.(dofFields{1});
                if ~isnumeric(firstArr) || isempty(firstArr), return; end
                si   = min(stepIdx, size(firstArr, 1));
                nRow = size(firstArr, 2);
                nDof = numel(dofFields);
                Uraw = zeros(nRow, nDof, 'double');
                for di = 1:nDof
                    dArr = entry.(dofFields{di});
                    if isnumeric(dArr) && size(dArr,1) >= si
                        Uraw(:, di) = double(dArr(si, :)).';
                    end
                end
            else
                % Layout A: raw 3-D array
                arr = entry;
                if isempty(arr) || ndims(arr) < 3, return; end
                si   = min(stepIdx, size(arr, 1));
                Uraw = double(reshape(arr(si,:,:), size(arr,2), size(arr,3)));
            end

            respTags = obj.getRespNodeTags(fieldType, stepIdx);
            ncol = min(size(Uraw, 2), 6);

            % post.readResponse model-update semantics:
            %   - ModelInfo node rows are current-step local rows after
            %     removing all-NaN padded rows.
            %   - NodalResp rows are aligned to the global union of
            %     nodeTags.
            %
            % Therefore the correct mapping is:
            %   current-step valid modelTags -> global response nodeTags.
            % Response-side NaN values indicate missing data for that step,
            % but they must not change the row lookup itself.
            if ~isempty(respTags)
                if numel(respTags) ~= size(Uraw,1)
                    validTags = isfinite(respTags(:));
                    if nnz(validTags) == size(Uraw,1)
                        respTags = respTags(validTags);
                    else
                        nUse = min(numel(respTags), size(Uraw,1));
                        respTags = respTags(1:nUse);
                        Uraw = Uraw(1:nUse, :);
                    end
                end

                respRows = obj.respTagsToRows(double(modelTags(:)), respTags, fieldType);
                valid = respRows > 0 & respRows <= size(Uraw,1);
                U(valid, 1:ncol) = Uraw(respRows(valid), 1:ncol);
                return;
            end

            % Legacy/raw path: only use row-wise compaction directly when
            % the response does not expose node tags for semantic mapping.
            Praw = obj.getNodeCoordsRaw(stepIdx);
            keepMask = obj.getNodeStepMask(stepIdx, Praw);
            if size(Uraw,1) == size(Praw,1)
                Uraw = Uraw(keepMask, :);
                nCopy = min(nModel, size(Uraw,1));
                U(1:nCopy, 1:ncol) = Uraw(1:nCopy, 1:ncol);
                return;
            end

            if size(Uraw,1) == nModel
                U(:, 1:ncol) = Uraw(:, 1:ncol);
                return;
            end
            if size(Uraw,1) == nnz(keepMask)
                U(:, 1:ncol) = Uraw(:, 1:ncol);
                return;
            end

            nCopy = min(nModel, size(Uraw,1));
            U(1:nCopy, 1:ncol) = Uraw(1:nCopy, 1:ncol);

        end

        function buildRespTagLookup(obj)
            obj.RespTagToIdx    = [];
            obj.RespTagToIdxMap = [];
            if ~isfield(obj.NodalResp,'nodeTags') || isempty(obj.NodalResp.nodeTags)
                return;
            end
            tags = double(obj.NodalResp.nodeTags);
            if ~isvector(tags)
                return;
            end
            tags = tags(:);
            tags = tags(isfinite(tags));
            if isempty(tags)
                return;
            end
            n    = numel(tags);
            maxT = max(tags, [], 'omitnan');
            if isfinite(maxT) && maxT >= 1 && maxT <= max(20*n, 1e6)
                arr       = zeros(maxT, 1);
                arr(tags) = 1:n;
                obj.RespTagToIdx = arr;
            else
                obj.RespTagToIdxMap = containers.Map( ...
                    num2cell(tags), num2cell(1:n));
            end
        end

        function rows = respTagsToRows(obj, modelTags, respTags, fieldType)
            if nargin < 4, fieldType = ''; end
            rows = zeros(numel(modelTags), 1);
            useCachedLookup = obj.shouldUseCachedRespLookup(fieldType, respTags);
            arr  = obj.RespTagToIdx;
            if useCachedLookup && ~isempty(arr)
                valid       = modelTags >= 1 & modelTags <= numel(arr) & isfinite(modelTags);
                rows(valid) = arr(modelTags(valid));
                return;
            end
            mp = obj.RespTagToIdxMap;
            if useCachedLookup && ~isempty(mp)
                keys   = num2cell(modelTags);
                exists = isKey(mp, keys);
                if any(exists)
                    rows(exists) = cell2mat(values(mp, keys(exists)));
                end
                return;
            end

            if isempty(respTags)
                return;
            end

            [tf, loc] = ismember(modelTags(:), respTags(:));
            rows(tf) = loc(tf);
        end

        function tf = shouldUseCachedRespLookup(obj, fieldType, respTags)
            tf = false;
            if nargin < 3 || isempty(respTags) || isempty(fieldType)
                return;
            end
            if ~isfield(obj.NodalResp, fieldType)
                return;
            end
            if ~isfield(obj.NodalResp,'nodeTags') || ~isvector(obj.NodalResp.nodeTags)
                return;
            end

            baseTags = double(obj.NodalResp.nodeTags(:));
            tf = numel(respTags) == numel(baseTags) && all(respTags(:) == baseTags);
        end

        function n = nSteps(obj)
            if isfield(obj.NodalResp,'time') && ~isempty(obj.NodalResp.time)
                n = numel(obj.NodalResp.time);  return;
            end
            % Fallback: scan fields for a numeric time-axis.
            n = 0;
            for fn = fieldnames(obj.NodalResp).'
                A = obj.NodalResp.(fn{1});
                if isstruct(A)
                    if isfield(A, 'data')
                        % Layout B
                        A = A.data;
                    else
                        % Layout C: first per-DOF field
                        fn2 = fieldnames(A);
                        if isempty(fn2), continue; end
                        A = A.(fn2{1});
                    end
                end
                if isnumeric(A) && ~isempty(A) && ndims(A) >= 2
                    n = size(A, 1);  return;
                end
            end
        end

        function P = getNodeCoordsRaw(obj, stepIdx)
            P = zeros(0, 3);
            if ~isfield(obj.ModelInfo,'Nodes') || ~isfield(obj.ModelInfo.Nodes,'Coords')
                return;
            end

            C = double(obj.ModelInfo.Nodes.Coords);
            if isempty(C)
                return;
            end

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

            [keepMask, ~] = obj.getNodeStepSelection(stepIdx, P, tags);
            P = P(keepMask,:);
            if ~isempty(tags)
                tags = obj.trimVectorLength(tags, numel(keepMask));
                tags = tags(keepMask(1:numel(tags)));
            end
        end

        function [keepMask, rawToClean] = getNodeStepSelection(obj, stepIdx, P, tags)
            if nargin < 3 || isempty(P)
                P = obj.getNodeCoordsRaw(stepIdx);
            end
            if nargin < 4 || isempty(tags)
                tags = obj.getModelNodeTagsRaw(stepIdx, size(P,1));
            end

            keepMask = obj.getNodeStepMask(stepIdx, P, tags);
            rawToClean = zeros(size(keepMask));
            rawToClean(keepMask) = 1:nnz(keepMask);
        end

        function valid = getNodeStepMask(obj, stepIdx, P, tags)
            if nargin < 3 || isempty(P)
                P = obj.getNodeCoordsRaw(stepIdx);
            end
            if nargin < 4 || isempty(tags)
                tags = obj.getModelNodeTagsRaw(stepIdx, size(P,1));
            end

            if isempty(P)
                valid = false(0,1);
                return;
            end

            % Model-update padding is represented by all-NaN node rows.
            % Drop those rows directly and also exclude nodes explicitly
            % marked as unused by post.ModelInfo.Nodes.UnusedTags.
            valid = ~all(isnan(P), 2);
            unusedTags = obj.getUnusedNodeTags(stepIdx);
            if ~isempty(unusedTags) && ~isempty(tags)
                tags = tags(:);
                nUse = min(numel(tags), numel(valid));
                valid(1:nUse) = valid(1:nUse) & ~ismember(tags(1:nUse), unusedTags(:));
            end
        end

        function tags = getModelNodeTagsRaw(obj, stepIdx, nRow)
            if nargin < 3, nRow = []; end
            tags = [];
            if ~isfield(obj.ModelInfo,'Nodes') || ~isfield(obj.ModelInfo.Nodes,'Tags') || ...
               isempty(obj.ModelInfo.Nodes.Tags)
                return;
            end

            tags = obj.readStepVectorData(obj.ModelInfo.Nodes.Tags, stepIdx);

            if ~isempty(nRow)
                tags = obj.trimVectorLength(tags, nRow);
            end
        end

        function tags = getUnusedNodeTags(obj, ~)
            tags = [];
            if ~isfield(obj.ModelInfo,'Nodes') || ~isfield(obj.ModelInfo.Nodes,'UnusedTags') || ...
               isempty(obj.ModelInfo.Nodes.UnusedTags)
                return;
            end

            tags = double(obj.ModelInfo.Nodes.UnusedTags(:));
            tags = unique(tags(isfinite(tags)));
        end

        function tags = getRespNodeTags(obj, fieldType, stepIdx)
            tags = [];
            if nargin < 3, stepIdx = 1; end
            fieldType = obj.normalizeFieldType(fieldType);
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

        % =================================================================
        % Scalar field
        % =================================================================

        function S = computeScalarField(obj, U)
            S = obj.computeScalarFieldWithComp(U, obj.Opts.field.component, ...
                obj.getRespDofs(obj.Opts.field.type));
        end

        function dofs = getRespDofs(obj, fieldType)
            % Return dof labels for the given response type.
            %   Layout B: stored in entry.dofs
            %   Layout C: the fieldnames are the DOF names
            dofs = {};
            fieldType = obj.normalizeFieldType(fieldType);
            if ~isfield(obj.NodalResp, fieldType), return; end
            entry = obj.NodalResp.(fieldType);
            if ~isstruct(entry), return; end
            if isfield(entry, 'dofs')
                dofs = entry.dofs;          % Layout B
            elseif ~isfield(entry, 'data')
                dofs = fieldnames(entry).'; % Layout C
            end
        end

        function S = computeScalarFieldWithComp(~, U, component, dofs)
            if nargin < 4, dofs = {}; end
            comp   = lower(string(component));
            dofMap = struct('x',1,'ux',1,'y',2,'uy',2,'z',3,'uz',3,'rx',4,'ry',5,'rz',6);
            switch comp
                case {'magnitude','mag'}
                    Uuse = U(:,1:min(3,size(U,2)));
                    S = sqrt(sum(Uuse.^2, 2, 'omitnan'));
                    S(all(~isfinite(Uuse), 2)) = NaN;
                case {'magnitude6','mag6'}
                    S = sqrt(sum(U.^2, 2, 'omitnan'));
                    S(all(~isfinite(U), 2)) = NaN;
                otherwise
                    % First try .dofs label match
                    col = 0;
                    for d = 1:numel(dofs)
                        if strcmpi(dofs{d}, comp)
                            col = d;  break;
                        end
                    end
                    % Fall back to built-in DOF map
                    if col == 0 && isfield(dofMap, char(comp))
                        col = dofMap.(char(comp));
                    end
                    if col > 0 && size(U,2) >= col
                        S = U(:, col);
                    elseif col > 0
                        S = zeros(size(U,1), 1);
                    else
                        Uuse = U(:,1:min(3,size(U,2)));
                        S = sqrt(sum(Uuse.^2, 2, 'omitnan'));
                        S(all(~isfinite(Uuse), 2)) = NaN;
                    end
            end
            S = double(S(:));
        end

        function U3 = extractXYZ(~, U)
            U3 = zeros(size(U,1), 3);
            U3(:,1:min(3,size(U,2))) = U(:,1:min(3,size(U,2)));
        end

        function valid = getValidRespRows(~, U)
            if isempty(U)
                valid = false(0,1);
                return;
            end
            valid = any(isfinite(U), 2) & ~all(isnan(U), 2);
        end

        function umax = getStepPeakMagnitude(obj, fieldType, stepIdx)
            umax = obj.peakVectorMagnitude(obj.getRespSlice(fieldType, stepIdx));
            if obj.shouldUseInterpDisp(fieldType, stepIdx)
                [~, disp_, ~] = obj.getInterpSlice(stepIdx);
                umax = max(umax, obj.peakVectorMagnitude(disp_));
            end
        end

        function mag = peakVectorMagnitude(obj, U)
            U3 = obj.extractXYZ(U);
            valid = obj.getValidRespRows(U3);
            if ~any(valid)
                mag = 0;
                return;
            end
            mag = max(sqrt(sum(U3(valid,:).^2, 2, 'omitnan')), [], 'omitnan');
            if ~isfinite(mag)
                mag = 0;
            end
        end

        function S = getStepScalarValues(obj, stepIdx, fieldType, component, useInterp)
            if nargin < 5
                useInterp = true;
            end

            if useInterp && obj.shouldUseInterpDisp(fieldType, stepIdx)
                [~, disp_, ~] = obj.getInterpSlice(stepIdx);
                S = obj.computeScalarFieldWithComp(disp_, component, obj.getRespDofs(fieldType));
                S = S(isfinite(S));
                return;
            end

            U = obj.getRespSlice(fieldType, stepIdx);
            S = obj.computeScalarFieldWithComp(U, component, obj.getRespDofs(fieldType));
            valid = obj.getValidRespRows(U);
            S = S(valid & isfinite(S));
        end

        function [fieldType, component] = getStepSearchSpec(obj)
            if obj.Opts.field.show && obj.Opts.color.useColormap
                fieldType = obj.Opts.field.type;
                component = obj.Opts.field.component;
                return;
            end

            if obj.Opts.deform.show
                fieldType = obj.Opts.deform.type;
                component = "magnitude";
                return;
            end

            fieldType = obj.Opts.field.type;
            component = obj.Opts.field.component;
        end

        function tf = shouldUseInterpDisp(obj, fieldType, stepIdx)
            tf = strcmpi(fieldType, 'disp') && ...
                 obj.Opts.line.show && ...
                 obj.Opts.interp.useInterpolation && ...
                 obj.hasInterpData(stepIdx);
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

        function clim_ = resolveClim(obj, S)
            if ~isempty(obj.Opts.color.clim), clim_ = obj.Opts.color.clim; return; end
            mode = lower(char(string(obj.Opts.color.climMode)));
            switch mode
                case 'absmax', [a,b] = obj.globalClim(); clim_ = [0, max(abs(a),abs(b))];
                case 'absmin', [a,b] = obj.globalClim(); clim_ = [0, min(abs(a),abs(b))];
                case 'range',  [a,b] = obj.globalClim(); clim_ = [a, b];
                case {'step','local','current'}
                    clim_ = obj.localClim(S);
                otherwise
                    clim_ = obj.localClim(S);
            end
        end

        function clim_ = localClim(~, S)
            Sf = S(isfinite(S));
            if isempty(Sf)
                clim_ = [0 1];
                return;
            end
            clim_ = [min(Sf, [], 'omitnan'), max(Sf, [], 'omitnan')];
            if clim_(1) == clim_(2)
                clim_(2) = clim_(1) + 1;
            end
        end

        function fieldType = normalizeFieldType(obj, fieldType)
            % Case-insensitive match of fieldType against actual NodalResp field names.
            fieldType = char(fieldType);
            if isfield(obj.NodalResp, fieldType), return; end
            fn = fieldnames(obj.NodalResp);
            match = fn(strcmpi(fn, fieldType));
            if ~isempty(match)
                fieldType = match{1};
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

        % =================================================================
        % Drawing primitives
        % =================================================================

        function h = drawLine(obj, P, lines, solidColor, lw, tag, S, clim_)
            h = gobjects(0);
            if isempty(P) || isempty(lines), return; end
            s.nodes     = P;
            s.lines     = lines;
            s.lineWidth = lw;
            s.lineStyle = obj.Opts.line.lineStyle;
            s.tag       = tag;
            if nargin >= 7 && ~isempty(S) && obj.Opts.color.useColormap
                s.values = S;
                s.cmap   = obj.Opts.color.colormap;
                if nargin >= 8 && ~isempty(clim_), s.clim = clim_; end
                h = obj.Plotter.addColoredLine(s);
            else
                s.color = solidColor;
                h = obj.Plotter.addLine(s);
            end
        end

        function h = drawUnstructured(obj, Pdef, stepIdx, S, clim_, asUndeformed)
            h = gobjects(0);
            if ~obj.Opts.surf.show, return; end
            if isempty(Pdef), return; end

            fam = obj.getFamilies(stepIdx);
            if ~isfield(fam,'Unstructured'), return; end
            U0 = fam.Unstructured;
            if ~isfield(U0,'Cells')     || isempty(U0.Cells),     return; end
            if ~isfield(U0,'CellTypes') || isempty(U0.CellTypes), return; end

            cells = double(U0.Cells);
            types = double(U0.CellTypes);

            if obj.ModelUpdateFlag && ndims(cells) == 3
                si    = min(stepIdx, size(cells,1));
                cells = squeeze(cells(si,:,:));
                if ndims(types) == 2 && size(types,1) > 1
                    types = squeeze(types(min(stepIdx,size(types,1)), :));
                end
            elseif ndims(cells) == 3
                cells = squeeze(cells(1,:,:));
                if ndims(types) == 2 && size(types,1) > 1
                    types = squeeze(types(1,:));
                end
            end

            keepRows = ~all(isnan(cells), 2);
            cells = cells(keepRows,:);
            types = types(:);
            if numel(keepRows) == numel(types)
                types = types(keepRows);
            end
            if size(types,1) > size(cells,1)
                types = types(1:size(cells,1));
            elseif size(types,1) < size(cells,1)
                cells = cells(1:size(types,1),:);
            end
            validCells = any(isfinite(cells), 2) & isfinite(types);
            cells = cells(validCells, :);
            types = types(validCells);
            if isempty(cells), return; end

            [~, rawToClean] = obj.getNodeStepSelection(stepIdx);
            cells = round(cells);
            nodeMask = isfinite(cells) & cells >= 1 & cells <= numel(rawToClean);
            cells(nodeMask) = rawToClean(cells(nodeMask));
            cells(~nodeMask) = NaN;
            rowKeep = ~all(isnan(cells), 2);
            cells = cells(rowKeep, :);
            types = types(rowKeep);
            if isempty(cells), return; end

            if ~isempty(S) && obj.Opts.color.useColormap && numel(S) == size(Pdef,1)
                surfOut = plotter.utils.VTKElementTriangulator.triangulate( ...
                    Pdef, types, cells, 'Scalars', S, 'ScalarsByElement', false);
            else
                surfOut = plotter.utils.VTKElementTriangulator.triangulate(Pdef, types, cells);
            end
            if isempty(surfOut) || ~isfield(surfOut,'Points') || isempty(surfOut.Points)
                return;
            end

            s.nodes = double(surfOut.Points);
            s.tris  = double(surfOut.Triangles);
            s.tag   = 'Surf';

            if asUndeformed
                if isfield(surfOut,'EdgePoints') && ~isempty(surfOut.EdgePoints)
                    w.points    = double(surfOut.EdgePoints);
                    w.color     = obj.Opts.color.undeformedColor;
                    w.lineWidth = obj.Opts.surf.edgeWidth;
                    w.tag       = 'UndeformedSurf';
                    h = obj.Plotter.addLine(w);
                end
                return;
            elseif ~isempty(S) && obj.Opts.color.useColormap
                if isfield(surfOut,'PointScalars') && ~isempty(surfOut.PointScalars)
                    s.values = double(surfOut.PointScalars(:));
                else
                    s.values = obj.mapScalarsByNN(s.nodes, Pdef, S);
                end
                s.cmap      = obj.Opts.color.colormap;
                s.faceAlpha = obj.Opts.color.deformedAlpha;
                if ~isempty(clim_), s.clim = clim_; end
                h = obj.Plotter.addColoredMesh(s);
            else
                s.faceColor = obj.Opts.color.solidColor;
                s.faceAlpha = obj.Opts.color.deformedAlpha;
                h = obj.Plotter.addMesh(s);
            end

            if obj.Opts.surf.showEdges && ...
               isfield(surfOut,'EdgePoints') && ~isempty(surfOut.EdgePoints)
                w.points    = surfOut.EdgePoints;
                w.color     = obj.Opts.surf.edgeColor;
                w.lineWidth = obj.Opts.surf.edgeWidth;
                obj.Plotter.addLine(w);
            end
        end

        function h = drawNodes(obj, Pdef, S, clim_)
            h = gobjects(0);
            if isempty(Pdef), return; end
            valid = all(isfinite(Pdef), 2);
            if ~any(valid), return; end
            s.points    = Pdef(valid,:);
            s.size      = obj.Opts.nodes.size;
            s.marker    = obj.Opts.nodes.marker;
            s.filled    = obj.Opts.nodes.filled;
            s.edgeColor = obj.Opts.nodes.edgeColor;
            s.tag       = 'Nodes';
            if ~isempty(S) && obj.Opts.color.useColormap
                s.scalars = S(valid);  s.cmap = obj.Opts.color.colormap;
                if ~isempty(clim_), s.clim = clim_; end
            else
                s.color = obj.Opts.color.solidColor;
            end
            h = obj.Plotter.addPoints(s);
        end

        function h = drawFixed(obj, Pdef, stepIdx)
            h = gobjects(0);
            if ~obj.Opts.fixed.show
                return;
            end
            if ~isfield(obj.ModelInfo,'Fixed') || ...
               ~isfield(obj.ModelInfo.Fixed,'NodeIndex') || ...
               isempty(obj.ModelInfo.Fixed.NodeIndex)
                return;
            end
            ni = obj.ModelInfo.Fixed.NodeIndex;
            if obj.ModelUpdateFlag && ~isvector(ni)
                ni = ni(min(stepIdx,size(ni,1)),:);
            end
            idx = double(ni(:));

            idx = idx(isfinite(idx));
            idx = idx(~isnan(idx));
            [~, rawToClean] = obj.getNodeStepSelection(stepIdx);
            valid = idx >= 1 & idx <= numel(rawToClean);
            idx = idx(valid);
            if isempty(idx)
                return;
            end
            idx = rawToClean(round(idx));
            idx = idx(idx >= 1 & idx <= size(Pdef,1));
            if isempty(idx)
                return;
            end
            s.points    = Pdef(idx,:);
            s.size      = obj.Opts.fixed.size;
            s.marker    = obj.Opts.fixed.marker;
            s.filled    = obj.Opts.fixed.filled;
            s.edgeColor = obj.Opts.fixed.edgeColor;
            s.color     = obj.Opts.fixed.color;
            s.tag       = 'FixedNodes';
            h = obj.Plotter.addPoints(s);
        end

        function h = drawVectorField(obj, Pdef, stepIdx)
            h = gobjects(0);
            U = obj.getRespSlice(obj.Opts.vector.type, stepIdx);
            if isempty(U), return; end
            cols = obj.Opts.vector.components;
            cols = cols(cols >= 1 & cols <= size(U,2));
            if isempty(cols), return; end
            V = zeros(size(U,1), 3);
            for k = 1:min(numel(cols),3), V(:,k) = U(:,cols(k)); end
            vmag = max(sqrt(sum(V.^2, 2, 'omitnan')), [], 'omitnan');
            if ~isfinite(vmag) || vmag <= 0, return; end
            if obj.Opts.vector.autoScale
                scale = obj.CachedModelSize * obj.Opts.vector.scale / vmag;
            else
                scale = obj.Opts.vector.scale;
            end
            valid = all(isfinite(Pdef), 2) & all(isfinite(V), 2);
            if ~any(valid), return; end
            s.points    = Pdef(valid,:);
            s.vectors   = V(valid,:);
            s.scale     = scale;
            s.color     = obj.Opts.vector.color;
            s.lineWidth = obj.Opts.vector.lineWidth;
            s.headSize  = 0.6;
            s.tag       = 'VectorField';
            h = obj.Plotter.addArrows(s);
        end

        % =================================================================
        % Axes decoration
        % =================================================================

        function prepareAxes(obj)
            obj.applyFigureSize();
            if obj.Opts.general.clearAxes
                cla(obj.Ax,'reset');  hold(obj.Ax,'on');
            elseif obj.Opts.general.holdOn
                hold(obj.Ax,'on');
            end
            if obj.Opts.general.axisEqual, axis(obj.Ax,'equal'); end
            if obj.Opts.general.grid, grid(obj.Ax,'on');
            else,                     grid(obj.Ax,'off'); end
            if obj.Opts.general.box,  box(obj.Ax,'on');
            else,                     box(obj.Ax,'off');  end
            colormap(obj.Ax, obj.Opts.color.colormap);
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
                error('PlotNodalResp:InvalidFigureSize', ...
                    'general.figureSize must be [width height] or [left bottom width height].');
            end

            fig.Position = pos;
        end

        function applyView(obj)
            v = lower(char(string(obj.Opts.general.view)));
            if strcmp(v,'auto')
                if obj.CachedModelDim == 2, view(obj.Ax,2);
                else,                       view(obj.Ax,3); end
                return;
            end
            switch v
                case 'iso', view(obj.Ax,3);
                case 'xy',  view(obj.Ax,2);
                case 'yx',  view(obj.Ax,90,90);
                case 'xz',  view(obj.Ax,0,0);
                case 'zx',  view(obj.Ax,180,0);
                case 'yz',  view(obj.Ax,90,0);
                case 'zy',  view(obj.Ax,-90,0);
                otherwise
                    if obj.CachedModelDim == 2, view(obj.Ax,2);
                    else,                       view(obj.Ax,3); end
            end
        end

        function applyTitle(obj, stepIdx)
            t = string(obj.Opts.general.title);
            if strcmpi(t,'auto')
                if isfield(obj.NodalResp,'time') && numel(obj.NodalResp.time) >= stepIdx
                    time_ = obj.NodalResp.time(stepIdx);
                else
                    time_ = NaN;
                end
                title(obj.Ax, sprintf('%s  %s  |  step %d  |  t = %.4g s', ...
                    obj.Opts.field.type, obj.Opts.field.component, stepIdx-1, time_));
            elseif strlength(t) > 0
                title(obj.Ax, char(t));
            end
        end

        function applyColorbar(obj, clim_)
            if ~obj.Opts.color.useColormap || ~obj.Opts.cbar.show
                colorbar(obj.Ax,'off');  return;
            end
            if ~isempty(clim_) && diff(clim_) > 0, clim(obj.Ax, clim_); end
            cb               = colorbar(obj.Ax);
            cb.FontSize      = 11;
            cb.TickDirection = 'in';
            cb.Title.String  = '';
            cb.Label.String  = obj.getColorbarSideTitle();
            cb.Label.FontSize = 13;
        end

        function titleText = getScalarTitle(obj)
            component = char(string(obj.Opts.field.component));
            fieldType = char(string(obj.Opts.field.type));

            if isempty(strtrim(component))
                titleText = fieldType;
            else
                titleText = sprintf('%s | %s', fieldType, component);
            end
        end

        function labelText = getColorbarSideTitle(obj)
            titleText = string(obj.getScalarTitle());
            extraLabel = string(obj.Opts.cbar.label);

            if strlength(strtrim(extraLabel)) > 0
                labelText = sprintf('%s | %s', char(titleText), char(extraLabel));
            else
                labelText = char(titleText);
            end
        end

        % =================================================================
        % Scalar NN mapping
        % =================================================================

        function Squery = mapScalarsByNN(obj, queryPts, refPts, refScalars)
            % Nearest-neighbour scalar mapping (no Statistics Toolbox required).
            Squery = zeros(size(queryPts,1), 1);
            if isempty(queryPts)||isempty(refPts)||isempty(refScalars), return; end
            validRef = all(isfinite(refPts), 2) & isfinite(refScalars(:));
            refPts = refPts(validRef,:);
            refScalars = refScalars(validRef);
            if isempty(refPts) || isempty(refScalars), return; end
            nq = size(queryPts,1);  nr = size(refPts,1);
            if ~obj.ModelUpdateFlag && ~isempty(obj.KnnIdxCache) && ...
               obj.KnnRefPtCount == nr && obj.KnnQueryPtCount == nq
                idx = obj.KnnIdxCache;
            else
                idx = plotter.PlotNodalResp.nearestNeighbourKnn( ...
                    double(queryPts), double(refPts));
                if ~obj.ModelUpdateFlag
                    obj.KnnIdxCache     = idx;
                    obj.KnnRefPtCount   = nr;
                    obj.KnnQueryPtCount = nq;
                end
            end
            Squery = double(refScalars(idx));
        end


        % =================================================================
        % Geometry utilities
        % =================================================================

        function dim = computeModelDim(~, P)
            if isempty(P) || size(P,2) < 3, dim = 2; return; end
            z = P(:,3);
            if all(isnan(z) | abs(z) < 1e-12), dim = 2; else, dim = 3; end
        end

        function L = computeModelLength(~, P)
            if isempty(P), L = 1; return; end
            ext = max(P,[],1,'omitnan') - min(P,[],1,'omitnan');
            ext = ext(isfinite(ext));
            if isempty(ext), L = 1; return; end
            L = max(ext, [], 'omitnan');
            if ~isfinite(L) || L <= 0, L = 1; end
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

        function out = mergeStruct(obj, base, add) %#ok<INUSL>
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

    end % private methods

    % =====================================================================
    methods (Static, Access = private)

        function idx = nearestNeighbourKnn(queryPts, refPts)
            nQ = size(queryPts,1);  nR = size(refPts,1);
            idx = ones(nQ,1);
            chunkSize = max(1, floor(50e6 / (nR * 3)));
            for i = 1:chunkSize:nQ
                iEnd = min(i + chunkSize - 1, nQ);
                d2 = sum(bsxfun(@minus, ...
                    permute(queryPts(i:iEnd,:),[1 3 2]), ...
                    permute(refPts,[3 1 2])).^2, 3);
                [~, idx(i:iEnd)] = min(d2, [], 2);
            end
        end

    end % static private methods

end % classdef