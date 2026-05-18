classdef PlotUnstruResponse < handle
    % PlotUnstruResponse
    % Visualise shell / plane / solid element responses on the full model.
    %
    % Data layouts
    % ------------
    % modelInfo / nodalResp / eleResp can each be:
    %   - Scalar struct  : single segment, no model topology change.
    %   - Struct array   : multiple segments, each element is a scalar
    %                      struct covering a contiguous block of global
    %                      time steps.  Topology is fixed *within* a
    %                      segment; it may change across segments.
    %
    % Global step indexing
    % --------------------
    % Global step g (0-based) maps to:
    %   segment   s = first segment whose cumulative step count exceeds g
    %   localStep   = g - sum(steps in segments 1..s-1)   (1-based internally)

    properties
        ModelInfo   % scalar struct OR struct array (one per segment)
        NodalResp   % scalar struct OR struct array (one per segment)
        EleResp     % scalar struct OR struct array (one per segment)
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
        % Segment bookkeeping
        SegCount        double = 1
        SegStepCounts   double = []
        SegOffsets      double = []

        CachedModelDim    double  = 3
        CachedModelSize   double  = 1

        GlobalClimCache   double = []
        GlobalClimKey     char   = ''

        GlobalDeformScale double = NaN
        GlobalDeformField char   = ''
        GlobalDeformStep  double = NaN

        ModelTagToIdx     cell = {}   % {1 x SegCount}
        ModelTagToIdxMap  cell = {}   % {1 x SegCount}

        % Pre-built scalar fields: one cell per global step
        RespNodeScalar    cell = {}
        RespEleScalar     cell = {}
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
                'undeformedLineWidth',0.8, 'colorBy','solid');

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
                'colorMode','auto', ...
                'gpReduce','mean', ...
                'gpIndex',1);

            opts.fixed = struct( ...
                'show',true, 'size',40, 'marker','s', 'filled',true, ...
                'edgeColor','#000000', 'color','#8c000f');

            opts.cbar = struct('show',true, 'label','');

            opts.help = strjoin({
                '====== PlotUnstruResponse Options =================================='
                ''
                '-- Response ----------------------------------------------------'
                '  (set via setResponse, not opts)'
                '  eleType    ''solid'' | ''shell'' | ''planestress'' | ...'
                '  respType   field name in EleResp (e.g. ''stress'', ''strain'')'
                '  component  ''vonMises'' | ''hydrostatic'' | ''tauMax'''
                '             | ''p1'' | ''p2'' | ''p3'' (principal stresses)'
                ''
                '-- Deformation -------------------------------------------------'
                '  deform.show            logical  Draw deformed shape (default true).'
                '  deform.type            ''disp''   Field used to deform geometry.'
                '  deform.scale           double   Manual deformation scale factor.'
                '  deform.autoScale       logical  Auto-fit deformation to model size.'
                '  deform.showUndeformed  logical  Also draw undeformed ghost.'
                ''
                '-- Surface -----------------------------------------------------'
                '  surf.show       logical  Draw filled surface (default true).'
                '  surf.showEdges  logical  Draw mesh edges.'
                '  surf.edgeColor  color   Edge colour.'
                '  surf.edgeWidth  double  Edge line width.'
                '  surf.colorMode  ''auto'' | ''node'' | ''element''  Colouring strategy.'
                '  surf.gpReduce   ''mean'' | ''max'' | ''min''  GP aggregation method.'
                '  surf.gpIndex    int     GP index to use when gpReduce is irrelevant.'
                ''
                '-- Color -------------------------------------------------------'
                '  color.useColormap     logical  Colour by value (default true).'
                '  color.colormap        N×3     Colormap matrix (default turbo(256)).'
                '  color.clim            [lo hi] Fixed colour limits; [] = auto.'
                '  color.climMode        ''range'' | ''step'' | ''global'''
                '  color.solidColor      color   Solid fill when useColormap=false.'
                '  color.undeformedColor color   Colour of undeformed ghost.'
                '  color.undeformedAlpha double  Opacity of undeformed ghost (0-1).'
                '  color.deformedAlpha   double  Opacity of deformed mesh (0-1).'
                ''
                '-- Interpolation (frame/line elements) -------------------------'
                '  interp.useInterpolation  logical  Interpolate along members.'
                '  interp.lineWidth         double   Deformed line width.'
                '  interp.lineStyle         string   Line style.'
                '  interp.undeformedLineWidth double  Undeformed line width.'
                '  interp.colorBy           ''solid'' | ''field''  Line colouring.'
                ''
                '-- Fixed nodes -------------------------------------------------'
                '  fixed.show       logical  Highlight fixed nodes (default true).'
                '  fixed.size       double   Marker size.'
                '  fixed.marker     string   Marker shape.'
                '  fixed.color      color   Fill colour.'
                '  fixed.edgeColor  color   Edge colour.'
                ''
                '-- Layout ------------------------------------------------------'
                '  general.view       ''auto''|''xy''|''xz''|''iso''  Camera view.'
                '  general.padRatio   double   Axis padding fraction (default 0.05).'
                '  general.figureSize [w h]    Figure size in pixels.'
                '  general.title      ''auto'' | string   Plot title.'
                '  general.clearAxes  logical  Clear axes before each plot.'
                '  general.axisEqual  logical  Equal axis scaling.'
                '  general.grid       logical  Show grid.'
                ''
                '-- Colorbar ----------------------------------------------------'
                '  cbar.show   logical  Show colorbar (default true).'
                '  cbar.label  string   Extra suffix for colorbar label.'
                ''
                '== Example ====================================================='
                '  opts = plotter.PlotUnstruResponse.defaultOptions();'
                '  disp(opts.help)              % print this help'
                '  opts.surf.gpReduce  = ''max'';'
                '  opts.color.climMode = ''global'';'
                '  opts.deform.scale   = 50;'
                '  pur.plotStep(''absmax'', opts);'
                '================================================================='
                }, newline);
        end
    end

    methods
        function obj = PlotUnstruResponse(modelInfo, nodalResp, eleResp, ax, opts)
            if nargin < 1 || isempty(modelInfo), error('PlotUnstruResponse:InvalidInput','modelInfo must be provided.'); end
            if nargin < 2 || isempty(nodalResp), error('PlotUnstruResponse:InvalidInput','nodalResp must be provided.'); end
            if nargin < 3 || isempty(eleResp),   error('PlotUnstruResponse:InvalidInput','eleResp must be provided.');   end
            if nargin < 4, ax   = []; end
            if nargin < 5, opts = []; end

            obj.ModelInfo = modelInfo;
            obj.NodalResp = nodalResp;
            obj.EleResp   = eleResp;
            obj.Opts      = obj.mergeStruct(plotter.PlotUnstruResponse.defaultOptions(), opts);
            obj.Plotter   = plotter.PatchPlotter(ax);
            obj.Ax        = obj.Plotter.Ax;

            obj.buildSegmentIndex();

            P = obj.getNodeCoords(1, 1);
            obj.CachedModelDim  = obj.computeModelDim(1, P);
            obj.CachedModelSize = obj.computeModelLength(P);
        end

        function ax = getAxes(obj), ax = obj.Ax; end

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
                    [obj.RespNodeScalar, obj.RespEleScalar] = obj.buildRespFields();
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
                    [obj.RespType, obj.Component] = unstru_check_plane(respType, component);
                    obj.cbarTitle = obj.Component;
                case {'solid','brick'}
                    obj.EleType = 'Solid';
                    [obj.RespType, obj.Component] = unstru_check_solid(respType, component);
                    obj.cbarTitle = obj.Component;
                otherwise
                    error('PlotUnstruResponse:BadEleType', 'Unknown ele type "%s".', obj.EleType);
            end

            [obj.RespNodeScalar, obj.RespEleScalar] = obj.buildRespFields();
            obj.GlobalClimCache = [];
            obj.GlobalClimKey   = '';
        end

        function h = plotStep(obj, globalStepArg, opts)
            if nargin >= 3 && ~isempty(opts), obj.setOptions(opts); end
            globalStep = obj.resolveGlobalStepArg(globalStepArg);
            [segIdx, localStep] = obj.resolveGlobalStep(globalStep);
            obj.prepareAxes(segIdx);
            obj.Handles = struct();
            obj.renderStep(segIdx, localStep, globalStep);
            h = obj.Handles;
        end

        function n = nSteps(obj)
            n = sum(obj.SegStepCounts);
        end

        function [cmin, cmax] = globalClim(obj)
            cacheKey = obj.makeRespKey();
            if ~isempty(obj.GlobalClimCache) && strcmp(obj.GlobalClimKey, cacheKey)
                cmin = obj.GlobalClimCache(1);  cmax = obj.GlobalClimCache(2);  return;
            end
            allMin = inf;  allMax = -inf;
            for k = 1:numel(obj.RespNodeScalar)
                for vv = {obj.RespNodeScalar{k}, obj.RespEleScalar{k}}
                    v = vv{1};
                    if ~isempty(v)
                        v = v(isfinite(v));
                        if ~isempty(v)
                            allMin = min(allMin, min(v));
                            allMax = max(allMax, max(v));
                        end
                    end
                end
            end
            if ~isfinite(allMin), allMin = 0; end
            if ~isfinite(allMax), allMax = 1; end
            if allMin == allMax,  allMax = allMin + 1; end
            obj.GlobalClimCache = [allMin allMax];
            obj.GlobalClimKey   = cacheKey;
            cmin = allMin;  cmax = allMax;
        end
    end

    methods (Access = private)

        % =================================================================
        % Segment index
        % =================================================================

        function buildSegmentIndex(obj)
            % SegCount: maximum across all three data arrays.
            % Scalar structs have numel==1 and work for all segIdx via safeGetSeg.
            obj.SegCount = max([numel(obj.ModelInfo), numel(obj.NodalResp), numel(obj.EleResp)]);
            obj.SegStepCounts = zeros(1, obj.SegCount);
            for s = 1:obj.SegCount
                obj.SegStepCounts(s) = obj.countSegSteps(s);
            end
            obj.SegOffsets = [0, cumsum(obj.SegStepCounts(1:end-1))];

            obj.ModelTagToIdx    = cell(1, obj.SegCount);
            obj.ModelTagToIdxMap = cell(1, obj.SegCount);
            for s = 1:obj.SegCount
                [obj.ModelTagToIdx{s}, obj.ModelTagToIdxMap{s}] = ...
                    obj.buildSegModelTagLookup(s);
            end
        end
        function n = countSegSteps(obj, segIdx)
            % Safe index into scalar or struct-array resp fields.
            % Try NodalResp first, then EleResp as fallback.
            n = obj.countStepsInRespStruct(obj.safeGetSeg(obj.NodalResp, segIdx));
            if n > 0, return; end
            n = obj.countStepsInRespStruct(obj.safeGetSeg(obj.EleResp,   segIdx));
        end

        function n = countStepsInRespStruct(obj, resp)
            % Extract step count from a response struct of any layout/depth.
            % Works for:
            %   Layout A/B  : resp.field.data = [nStep x nEle x ...]
            %   Layout C    : resp.field.subfield = [nStep x nEle x ...]
            %   Wrapped     : resp.RESP_NAME.field.subfield = [...]
            %   With time   : resp.time = [nStep]
            n = 0;
            if isempty(resp) || ~isstruct(resp), return; end
            fn0 = fieldnames(resp);
            if isempty(fn0), return; end

            % Fastest path: explicit time vector
            if isfield(resp,'time') && ~isempty(resp.time)
                n = numel(resp.time);  return;
            end

            skipMeta = {'time','odbtag','eletype','nodetags','eletags', ...
                        'interpolatepoints','interpolatedisp','interpolatecells', ...
                        'interpolatecoords'};

            % Search recursively up to depth 3
            n = obj.findNStepsRecursive(resp, skipMeta, 3);
        end

        function n = findNStepsRecursive(obj, s, skipMeta, depth)
            % Recursively search struct s for a numeric array with shape
            % [nStep x ...] where nStep > 0. Returns 0 if not found.
            n = 0;
            if depth <= 0 || ~isstruct(s), return; end
            fn = fieldnames(s);
            for i = 1:numel(fn)
                name = fn{i};
                if ismember(lower(name), skipMeta), continue; end
                A = s.(name);
                if isnumeric(A) && ~isempty(A) && ismatrix(A) || ...
                   isnumeric(A) && ~isempty(A) && ndims(A) >= 2
                    % Candidate: first dim is nStep
                    % Reject if it's clearly a tags/index vector (1-D or [nNode x 1])
                    sz = size(A);
                    if numel(sz) >= 2 && sz(1) > 0
                        % Heuristic: if ndims>=3 or nCols>1 it's time-indexed data
                        % If ndims==2 and nCols==1 it might be a tags column — skip
                        % but only in first pass; accept in second pass below
                        if ndims(A) >= 3 || (ndims(A)==2 && sz(2) > 1)
                            n = sz(1);  return;
                        end
                    end
                elseif isstruct(A)
                    n = obj.findNStepsRecursive(A, skipMeta, depth-1);
                    if n > 0, return; end
                end
            end
            % Second pass: accept [nStep x 1] arrays too (single-column)
            for i = 1:numel(fn)
                name = fn{i};
                if ismember(lower(name), skipMeta), continue; end
                A = s.(name);
                if isnumeric(A) && ~isempty(A) && ndims(A) >= 2 && size(A,1) > 1
                    n = size(A,1);  return;
                elseif isnumeric(A) && ~isempty(A) && ndims(A) >= 2
                    n = size(A,1);  return;  % nStep==1 static case
                end
            end
        end
        function s = safeGetSeg(~, arr, segIdx)
            % Safely index a scalar struct or struct array.
            if isempty(arr) || ~isstruct(arr)
                s = struct();  return;
            end
            if numel(arr) >= segIdx
                s = arr(segIdx);
            else
                s = arr(1);   % scalar struct: always use it
            end
        end

        % =================================================================
        % Global step resolution
        % =================================================================

        function [segIdx, localStep] = resolveGlobalStep(obj, globalStep)
            if globalStep < 0 || globalStep >= obj.nSteps()
                error('PlotUnstruResponse:InvalidStep', ...
                    'globalStep %d out of range [0, %d].', globalStep, obj.nSteps()-1);
            end
            segIdx    = find(obj.SegOffsets + obj.SegStepCounts > globalStep, 1, 'first');
            localStep = globalStep - obj.SegOffsets(segIdx) + 1;  % 1-based
        end

        function globalStep = resolveGlobalStepArg(obj, arg)
            if isnumeric(arg)
                globalStep = round(arg);  return;
            end
            key  = obj.normalizeStepSelector(arg);
            n    = obj.nSteps();
            vals = obj.initStepSelectorValues(key, n);

            % Use pre-built cache when available (set by setResponse).
            src = obj.RespNodeScalar;
            if isempty(src), src = obj.RespEleScalar; end
            if ~isempty(src) && numel(src) >= n
                for k = 1:n
                    v = double(src{k});  v = v(isfinite(v));
                    if isempty(v), continue; end
                    switch key
                        case {'absmax','absmin'}, vals(k) = max(abs(v),[],'omitnan');
                        case 'max',              vals(k) = max(v,[],'omitnan');
                        case 'min',              vals(k) = min(v,[],'omitnan');
                    end
                end
            else
                % Cache not ready: build scalar field per step on the fly.
                for g = 0:n-1
                    [si, ls] = obj.resolveGlobalStep(g);
                    [ns, es] = obj.buildStepRespField(si, ls);
                    v = [ns(:); es(:)];  v = v(isfinite(v));
                    if isempty(v), continue; end
                    switch key
                        case {'absmax','absmin'}, vals(g+1) = max(abs(v),[],'omitnan');
                        case 'max',              vals(g+1) = max(v,[],'omitnan');
                        case 'min',              vals(g+1) = min(v,[],'omitnan');
                    end
                end
            end

            switch key
                case {'absmax','max'}
                    % When multiple steps tie, pick the LAST one so the
                    % analysis step wins over the initial state (step 0).
                    bestVal = max(vals,[],'omitnan');
                    idx = find(vals == bestVal, 1, 'last');
                case {'absmin','min'}
                    bestVal = min(vals,[],'omitnan');
                    idx = find(vals == bestVal, 1, 'last');
                otherwise
                    error('PlotUnstruResponse:InvalidStepIdx','Unknown selector "%s".',key);
            end
            if isempty(idx)||~isfinite(idx), idx=1; end
            globalStep = idx - 1;
        end

                function renderStep(obj, segIdx, localStep, globalStep)
            P        = obj.getNodeCoords(segIdx, localStep);
            lineConn = obj.getLineConn(segIdx);
            [Pdef, ~, ~] = obj.getDeformedCoords(P, segIdx, localStep);
            [Snode, Sele, clim_] = obj.getScalarField(globalStep);

            shownPts = [];

            if obj.Opts.deform.show && obj.Opts.deform.showUndeformed
                if obj.hasInterpData(segIdx, localStep) && obj.Opts.interp.useInterpolation
                    [obj.Handles.UndeformedLine, ptsLineU] = obj.drawInterpolatedLine(segIdx, localStep, true, []);
                else
                    [obj.Handles.UndeformedLine, ptsLineU] = obj.drawLine( ...
                        P, lineConn, obj.Opts.color.undeformedColor, ...
                        obj.Opts.line.undeformedLineWidth, 'UndeformedLine');
                end
                [obj.Handles.UndeformedSurf, ptsSurfU] = obj.drawUnstructured(P, segIdx, [], [], [], true);
                shownPts = [shownPts; ptsLineU; ptsSurfU];
            end

            if obj.Opts.line.show
                if obj.hasInterpData(segIdx, localStep) && obj.Opts.interp.useInterpolation
                    [obj.Handles.Line, ptsLine] = obj.drawInterpolatedLine(segIdx, localStep, false, clim_);
                else
                    [obj.Handles.Line, ptsLine] = obj.drawLine( ...
                        Pdef, lineConn, obj.Opts.color.solidColor, ...
                        obj.Opts.line.lineWidth, 'Line');
                end
                shownPts = [shownPts; ptsLine];
            end

            if obj.Opts.surf.show
                [obj.Handles.Surf, ptsSurf] = obj.drawUnstructured(Pdef, segIdx, Snode, Sele, clim_, false);
                shownPts = [shownPts; ptsSurf];
            end

            [obj.Handles.Fixed, ptsFix] = obj.drawFixed(Pdef, segIdx);
            shownPts = [shownPts; ptsFix];

            obj.applyColorbar(clim_);
            obj.applyTitle(segIdx, localStep, globalStep);
            obj.applyView(segIdx);
            obj.applyDisplayLimits(shownPts);
        end

        % =================================================================
        % Interpolation
        % =================================================================

        function tf = hasInterpData(obj, segIdx, localStep)
            nr = obj.NodalResp(segIdx);
            tf = isfield(nr,'interpolatePoints') && isfield(nr,'interpolateDisp') && ...
                 isfield(nr,'interpolateCells')  && ~isempty(nr.interpolatePoints);
            if ~tf, return; end
            pts = nr.interpolatePoints;
            if ndims(pts) == 3
                si  = min(localStep, size(pts,1));
                row = squeeze(pts(si,:,:));
                tf  = ~isempty(row) && any(isfinite(row(:)));
            end
        end

        function [pts, disp_, cells] = getInterpSlice(obj, segIdx, localStep)
            nr     = obj.NodalResp(segIdx);
            pts    = double(nr.interpolatePoints);
            disp_  = double(nr.interpolateDisp);
            cells_ = double(nr.interpolateCells);

            if ndims(pts) == 3
                si  = min(localStep, size(pts,1));
                pts = squeeze(pts(si,:,:));
            end
            if ndims(disp_) == 3
                si    = min(localStep, size(disp_,1));
                disp_ = squeeze(disp_(si,:,:));
            end
            if size(pts,2) < 3,   pts(:,3)   = 0; end
            if size(disp_,2) < 3, disp_(:,3) = 0; end

            if ndims(cells_) == 3
                si     = min(localStep, size(cells_,1));
                cells_ = squeeze(cells_(si,:,:));
            end
            if size(cells_,2) >= 3
                cells = cells_(:,end-1:end);
            else
                cells = cells_;
            end
        end

        function [h, ptsOut] = drawInterpolatedLine(obj, segIdx, localStep, asUndeformed, clim_)
            h = gobjects(0);  ptsOut = zeros(0,3);
            [pts, disp_, cells] = obj.getInterpSlice(segIdx, localStep);
            if isempty(pts) || isempty(cells), return; end

            if asUndeformed
                Pline = pts;
            else
                scale = obj.globalDeformScale(segIdx, localStep);
                U3    = disp_(:,1:min(3,size(disp_,2)));
                if size(U3,2) < 3, U3(:,end+1:3) = 0; end
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
                if strcmpi(obj.Opts.interp.colorBy,'disp') && obj.Opts.color.useColormap
                    val = sqrt(sum(disp_(:,1:min(3,size(disp_,2))).^2, 2));
                    s.values = val(:);
                    s.cmap   = obj.Opts.color.colormap;
                    if ~isempty(clim_), s.clim = clim_; end
                    h = obj.Plotter.addColoredLine(s);
                else
                    s.color = obj.Opts.color.solidColor;
                    h = obj.Plotter.addLine(s);
                end
            end
            ptsOut = Pline;
        end

        % =================================================================
        % Deformation
        % =================================================================

        function [Pdef, U3, scale] = getDeformedCoords(obj, P, segIdx, localStep)
            if obj.Opts.deform.show
                U     = obj.getRespSlice(segIdx, obj.Opts.deform.type, localStep);
                U3    = obj.extractXYZ(U);
                U3(~isfinite(U3)) = 0;
                scale = obj.globalDeformScale(segIdx, localStep);
                Pdef  = P + scale * U3;
            else
                U3    = zeros(size(P));
                scale = 0;
                Pdef  = P;
            end
        end

        function scale = globalDeformScale(obj, segIdx, localStep)
            fieldType = obj.Opts.deform.type;
            cacheKey  = obj.SegOffsets(segIdx) + localStep;
            if isfinite(obj.GlobalDeformScale) && strcmp(obj.GlobalDeformField, fieldType) && ...
               isequal(obj.GlobalDeformStep, cacheKey)
                scale = obj.GlobalDeformScale;  return;
            end
            baseScale = obj.Opts.deform.scale;
            if ~obj.Opts.deform.autoScale
                obj.GlobalDeformScale = baseScale;
                obj.GlobalDeformField = fieldType;
                obj.GlobalDeformStep  = cacheKey;
                scale = baseScale;  return;
            end
            U = obj.getRespSlice(segIdx, fieldType, localStep);
            umax = max(sqrt(sum(obj.extractXYZ(U).^2, 2)), [], 'omitnan');
            if ~isfinite(umax), umax = 0; end
            modelSize = obj.computeModelLength(obj.getNodeCoords(segIdx, localStep));
            if obj.hasInterpData(segIdx, localStep)
                [~, disp_, ~] = obj.getInterpSlice(segIdx, localStep);
                uk = max(sqrt(sum(disp_(:,1:min(3,size(disp_,2))).^2, 2)), [], 'omitnan');
                if isfinite(uk), umax = max(umax, uk); end
            end
            if umax <= 0, umax = 1; end
            if modelSize <= 0, modelSize = obj.CachedModelSize; end
            scale = baseScale * modelSize / umax / 10;
            obj.GlobalDeformScale = scale;
            obj.GlobalDeformField = fieldType;
            obj.GlobalDeformStep  = cacheKey;
        end

        % =================================================================
        % Scalar field retrieval (from pre-built cache)
        % =================================================================

        function [Snode, Sele, clim_] = getScalarField(obj, globalStep)
            Snode = [];  Sele = [];  clim_ = [];
            k = globalStep + 1;  % 0-based global → 1-based cache index
            if k <= numel(obj.RespNodeScalar), Snode = obj.RespNodeScalar{k}; end
            if k <= numel(obj.RespEleScalar),  Sele  = obj.RespEleScalar{k};  end
            vals = [];
            if ~isempty(Snode), vals = Snode;
            elseif ~isempty(Sele), vals = Sele; end
            if ~isempty(vals), clim_ = obj.resolveClim(vals); end
        end

        % =================================================================
        % Topology helpers (per-segment, no time dim)
        % =================================================================

        function P = getNodeCoords(obj, segIdx, ~)
            [P, ~] = obj.getNodeStepData(segIdx);
        end

        function P = getNodeCoordsRaw(obj, segIdx)
            P = zeros(0,3);
            mi = obj.ModelInfo(segIdx);
            if ~isfield(mi,'Nodes') || ~isfield(mi.Nodes,'Coords'), return; end
            C = double(mi.Nodes.Coords);
            if isempty(C), return; end
            P = C;
            if size(P,2) < 3,     P(:,3) = 0;
            elseif size(P,2) > 3, P = P(:,1:3); end
        end

        function [P, tags] = getNodeStepData(obj, segIdx)
            P    = obj.getNodeCoordsRaw(segIdx);
            tags = obj.getModelNodeTagsRaw(segIdx, size(P,1));
            if isempty(P), tags = zeros(0,1); return; end
            keepMask = obj.getExistingNodeStepMask(segIdx, P, tags);
            P    = P(keepMask,:);
            tags = obj.trimVectorLength(tags, numel(keepMask));
            tags = tags(keepMask);
        end

        function [keepMask, rawToClean, tagToClean] = getNodeStepSelection(obj, segIdx, P, tags)
            if nargin < 3 || isempty(P),    P    = obj.getNodeCoordsRaw(segIdx); end
            if nargin < 4 || isempty(tags), tags = obj.getModelNodeTagsRaw(segIdx, size(P,1)); end
            keepMask   = obj.getExistingNodeStepMask(segIdx, P, tags);
            rawToClean = zeros(size(keepMask));
            rawToClean(keepMask) = 1:nnz(keepMask);

            % tagToClean: node tag -> clean row index
            tagToClean = [];
            if ~isempty(tags)
                t      = double(obj.trimVectorLength(tags, numel(keepMask)));
                validT = isfinite(t) & t >= 1;
                if any(validT)
                    maxT = max(t(validT));
                    n    = numel(t);
                    if isfinite(maxT) && maxT <= max(20*n, 1e6)
                        tagToClean = zeros(maxT, 1);
                        for k = 1:n
                            if validT(k) && k <= numel(rawToClean) && rawToClean(k) > 0
                                tagToClean(t(k)) = rawToClean(k);
                            end
                        end
                    end
                end
            end
        end

        function keepMask = getExistingNodeStepMask(obj, segIdx, P, tags)
            if isempty(P), keepMask = false(0,1); return; end
            keepMask = ~all(isnan(P), 2);
            if nargin < 4 || isempty(tags), return; end
            tags = obj.trimVectorLength(tags, numel(keepMask));
            keepMask = keepMask & isfinite(tags);
            unusedTags = obj.getUnusedNodeTags(segIdx);
            if ~isempty(unusedTags)
                keepMask = keepMask & ~ismember(tags, unusedTags);
            end
        end

        function tags = getModelNodeTagsRaw(obj, segIdx, nRow)
            if nargin < 3, nRow = []; end
            mi = obj.ModelInfo(segIdx);
            if isfield(mi,'Nodes') && isfield(mi.Nodes,'Tags') && ~isempty(mi.Nodes.Tags)
                tags = double(mi.Nodes.Tags(:));
            else
                tags = (1:size(obj.getNodeCoordsRaw(segIdx),1)).';
            end
            if ~isempty(nRow), tags = obj.trimVectorLength(tags, nRow); end
        end

        function tags = getUnusedNodeTags(obj, segIdx)
            tags = [];
            mi   = obj.ModelInfo(segIdx);
            if ~isfield(mi,'Nodes') || ~isfield(mi.Nodes,'UnusedTags') || isempty(mi.Nodes.UnusedTags)
                return;
            end
            tags = double(mi.Nodes.UnusedTags(:));
            tags = unique(tags(isfinite(tags)), 'stable');
        end

        function lines = getLineConn(obj, segIdx)
            % Cell format: [nPts, idx1, idx2] — 1-based row indices.
            % No remapping (same as PlotEigen).
            lines = zeros(0,2);
            fam   = obj.getFamilies(segIdx);
            if ~isfield(fam,'Line') || ~isfield(fam.Line,'Cells') || isempty(fam.Line.Cells)
                return;
            end
            C = double(fam.Line.Cells);
            if ~isempty(C), C = C(~all(isnan(C),2),:); end
            if size(C,2) >= 3
                lines = C(:, 2:3);
            elseif size(C,2) == 2
                lines = C;
            else, return; end
            lines = round(lines);
            nPdef = size(obj.getNodeCoordsRaw(segIdx), 1);
            valid = all(isfinite(lines),2) & all(lines>=1,2) & all(lines<=nPdef,2);
            lines = lines(valid,:);
        end

        function fam = getFamilies(obj, segIdx)
            fam = struct();
            mi  = obj.ModelInfo(segIdx);
            if ~isfield(mi,'Elements'), return; end
            E = mi.Elements;
            if isfield(E,'Families'), fam = E.Families; else, fam = E; end
        end

        function fam = getRespFamily(obj, segIdx)
            fam = [];
            F = obj.getFamilies(segIdx);
            switch lower(obj.EleType)
                case 'plane',  if isfield(F,'Plane'),  fam = F.Plane;  end
                case 'shell',  if isfield(F,'Shell'),  fam = F.Shell;  end
                case 'solid',  if isfield(F,'Solid'),  fam = F.Solid;  end
            end
        end

        % =================================================================
        % Response data access
        % =================================================================

        function U = getRespSlice(obj, segIdx, fieldType, localStep)
            % Read nodal response for deformation (Layout A/B/C).
            % DOF order: ux,uy,uz,rx,ry,rz (canonical, same as PlotNodalResp).
            [Pmodel, modelTags] = obj.getNodeStepData(segIdx);
            nModel = size(Pmodel,1);
            U = NaN(nModel, 6);

            nr = obj.NodalResp(segIdx);
            % Normalise fieldType case
            if ~isfield(nr, fieldType)
                fn = fieldnames(nr);
                m  = fn(strcmpi(fn, fieldType));
                if ~isempty(m), fieldType = m{1}; else, return; end
            end
            entry = nr.(fieldType);

            canonical = {'ux','uy','uz','rx','ry','rz'};
            if isstruct(entry) && isfield(entry,'data')
                arr  = entry.data;
                if isempty(arr) || ndims(arr) < 3, return; end
                si   = min(localStep, size(arr,1));
                Uraw = double(reshape(arr(si,:,:), size(arr,2), size(arr,3)));
            elseif isstruct(entry)
                % Layout C — canonical DOF order
                present  = fieldnames(entry).';
                presentU = upper(present);
                canonU   = upper(canonical);
                ordered  = [canonical(ismember(canonU, presentU)), ...
                             present(~ismember(presentU, canonU))];
                dofFields = ordered;
                if isempty(dofFields), return; end
                firstArr = [];
                for dfi = 1:numel(dofFields)
                    if isfield(entry, dofFields{dfi})
                        firstArr = entry.(dofFields{dfi});  break;
                    end
                end
                if isempty(firstArr) || ~isnumeric(firstArr), return; end
                si   = min(localStep, size(firstArr,1));
                nRow = size(firstArr,2);
                nDof = numel(dofFields);
                Uraw = zeros(nRow, nDof, 'double');
                for di = 1:nDof
                    fn_ = dofFields{di};
                    if isfield(entry, fn_)
                        dArr = entry.(fn_);
                        if isnumeric(dArr) && size(dArr,1) >= si
                            Uraw(:,di) = double(dArr(si,:)).';
                        end
                    end
                end
            else
                arr = entry;
                if isempty(arr) || ndims(arr) < 3, return; end
                si   = min(localStep, size(arr,1));
                Uraw = double(reshape(arr(si,:,:), size(arr,2), size(arr,3)));
            end

            if isvector(Uraw), Uraw = Uraw(:).'; end
            ncol = min(size(Uraw,2), 6);

            % Tag mapping
            respTags = obj.getNodalRespNodeTags(segIdx, fieldType);
            if ~isempty(respTags)
                U(:,1:ncol) = obj.mapNodeDataToCurrentModel(segIdx, modelTags, Uraw(:,1:ncol), respTags, ncol);
                return;
            end
            nCopy = min(nModel, size(Uraw,1));
            U(1:nCopy,1:ncol) = Uraw(1:nCopy,1:ncol);
        end

        function tags = getNodalRespNodeTags(obj, segIdx, fieldType)
            tags = [];
            nr   = obj.NodalResp(segIdx);
            if ~isfield(nr, fieldType), return; end
            entry = nr.(fieldType);
            if isfield(nr,'nodeTags') && ~isempty(nr.nodeTags)
                tags = double(nr.nodeTags(:));
            elseif isstruct(entry) && isfield(entry,'nodeTags') && ~isempty(entry.nodeTags)
                tags = double(entry.nodeTags(:));
            end
            if ~isempty(tags), tags = tags(isfinite(tags)); end
        end

        function [arr, mp] = buildSegModelTagLookup(obj, segIdx)
            arr = [];  mp = [];
            tags = obj.getModelNodeTagsRaw(segIdx);
            if isempty(tags), return; end
            tags = double(tags(:));
            valid = isfinite(tags) & tags >= 1 & mod(tags,1) == 0;
            tags  = unique(tags(valid), 'stable');
            if isempty(tags), return; end
            n = numel(tags);  maxT = max(tags);
            if isfinite(maxT) && maxT >= 1 && maxT <= max(20*n, 1e6)
                arr = zeros(maxT,1);
                arr(tags) = 1:n;
            else
                mp = containers.Map(num2cell(tags), num2cell(1:n));
            end
        end

        function out = mapNodeDataToCurrentModel(obj, segIdx, modelTags, respData, respTags, nCol)
            if nargin < 6 || isempty(nCol), nCol = size(respData,2); end
            out = NaN(numel(modelTags), nCol);
            if isempty(respData), return; end
            respData = double(respData);
            if isvector(respData), respData = respData(:); end
            nDataCol = min(size(respData,2), nCol);
            if isempty(respTags)
                % No tag info: positional copy
                nCopy = min(numel(modelTags), size(respData,1));
                out(1:nCopy,1:nDataCol) = respData(1:nCopy,:);
                return;
            end
            respTags = double(respTags(:));
            valid = isfinite(respTags);
            if ~all(valid)
                respData = respData(valid,:);
                respTags = respTags(valid);
            end
            [tf, loc] = ismember(double(modelTags(:)), respTags);
            v = tf & loc > 0 & loc <= size(respData,1);
            out(v, 1:nDataCol) = respData(loc(v), 1:nDataCol);

            % Fallback: if tag mapping yielded nothing (e.g. ModelInfo has no Tags
            % field so modelTags defaulted to 1:N but actual tags differ), and
            % the response has the same node count as the model, use positional copy.
            if ~any(v) && size(respData,1) == numel(modelTags)
                out(1:numel(modelTags), 1:nDataCol) = respData(1:numel(modelTags), :);
            end
        end
        function out = mapNodeScalarToCurrentModel(obj, segIdx, modelTags, scalarNode, respTags)
            out = obj.mapNodeDataToCurrentModel(segIdx, modelTags, scalarNode, respTags, 1);
            out = out(:,1);
        end

        % =================================================================
        % Element response data access
        % =================================================================

        function arr = getRespData(obj, segIdx, fieldName)
            er = obj.EleResp(segIdx);
            fieldName = obj.normalizeRespType(segIdx, fieldName);
            if ~isfield(er, fieldName), arr = []; return; end
            entry = er.(fieldName);
            if isstruct(entry)
                if isfield(entry,'data')
                    arr = entry.data;
                else
                    fn = fieldnames(entry);
                    if isempty(fn), arr = []; return; end
                    parts = cellfun(@(f) entry.(f), fn, 'UniformOutput', false);
                    if ~all(cellfun(@isnumeric,parts)), arr = []; return; end
                    nd  = ndims(parts{1});
                    arr = cat(nd+1, parts{:});
                end
            else
                arr = entry;
            end
        end

        function dofs = getRespDofs(obj, segIdx, fieldName)
            dofs = {};
            er = obj.EleResp(segIdx);
            fieldName = obj.normalizeRespType(segIdx, fieldName);
            if ~isfield(er, fieldName), return; end
            entry = er.(fieldName);
            if ~isstruct(entry), return; end
            if isfield(entry,'dofs')
                dofs = entry.dofs;
            elseif ~isfield(entry,'data')
                dofs = fieldnames(entry).';
            end
        end

        function tags = getRespEleTagsAtStep(obj, segIdx, localStep)
            tags = [];
            er   = obj.EleResp(segIdx);
            if ~isfield(er,'eleTags') || isempty(er.eleTags), return; end
            tags = double(er.eleTags(:));
            tags = tags(isfinite(tags));
        end

        function tags = getRespNodeTagsAtStep(obj, segIdx, fld, localStep)
            if isfield(fld,'nodeTags') && ~isempty(fld.nodeTags)
                tags = double(fld.nodeTags(:));
            elseif isfield(obj.EleResp(segIdx),'nodeTags') && ~isempty(obj.EleResp(segIdx).nodeTags)
                tags = double(obj.EleResp(segIdx).nodeTags(:));
            else
                tags = [];
            end
            if ~isempty(tags), tags = tags(isfinite(tags)); end
        end

        function [cells, types, tags] = getRespFamilyStepData(obj, segIdx)
            cells = zeros(0,0);  types = zeros(0,1);  tags = zeros(0,1);
            fam = obj.getRespFamily(segIdx);
            if isempty(fam), return; end
            if isfield(fam,'Cells') && ~isempty(fam.Cells)
                cells = double(fam.Cells);
                if isvector(cells), cells = reshape(cells,1,[]); end
            end
            if isfield(fam,'CellTypes') && ~isempty(fam.CellTypes)
                types = double(fam.CellTypes(:));
            end
            if isfield(fam,'Tags') && ~isempty(fam.Tags)
                tags = double(fam.Tags(:));
            end
            if ~isempty(cells)
                keep  = ~all(isnan(cells),2);
                cells = cells(keep,:);
                if ~isempty(types), types = obj.trimVectorLength(types, numel(keep)); types = types(keep); end
                if ~isempty(tags),  tags  = obj.trimVectorLength(tags,  numel(keep)); tags  = tags(keep); end
            end
        end

        % =================================================================
        % buildRespFields — pre-compute scalar per global step
        % =================================================================

        function [nodeFields, eleFields] = buildRespFields(obj)
            % Pre-compute scalar fields for every global step.
            % Single unified per-step loop — works for both scalar structs
            % and struct arrays without any fast-path branching.
            n = obj.nSteps();
            nodeFields = cell(n, 1);
            eleFields  = cell(n, 1);
            for g = 0:n-1
                [segIdx, localStep] = obj.resolveGlobalStep(g);
                k = g + 1;
                [nodeFields{k}, eleFields{k}] = obj.buildStepRespField(segIdx, localStep);
            end
        end

                function [nodeScalar, eleScalar] = buildStepRespField(obj, segIdx, localStep)
            nodeScalar = [];
            eleScalar  = [];

            rt = obj.normalizeRespType(segIdx, obj.RespType);
            er = obj.EleResp(segIdx);
            if ~isfield(er, rt), return; end
            fld = er.(rt);

            isLayoutC = isstruct(fld) && ~isfield(fld,'data');
            isPlain   = isnumeric(fld);
            isNodeBased = unstru_is_node_based(rt) || isPlain;

            [~, modelTags] = obj.getNodeStepData(segIdx);
            nModelNode = numel(modelTags);

            if isNodeBased
                if isPlain
                    raw = double(fld);
                    si  = min(localStep, size(raw,1));
                    scalarNode = double(raw(si,:).');
                elseif isLayoutC
                    scalarNode = obj.extractNodeScalarLayoutC(segIdx, fld, localStep);
                else
                    data  = double(fld.data);
                    dofs_ = {};
                    if isfield(fld,'dofs'), dofs_ = fld.dofs; end
                    scalarNode = obj.extractNodeScalarAtStep(data, localStep, dofs_);
                end

                rTags = obj.getRespNodeTagsAtStep(segIdx, fld, localStep);
                if isempty(rTags)
                    scalarNode = double(scalarNode(:));
                    if numel(scalarNode) == nModelNode
                        nodeScalar = scalarNode;
                    end
                else
                    nodeScalar = obj.mapNodeScalarToCurrentModel(segIdx, modelTags, scalarNode, rTags);
                end
                return;
            end

            % Element-based response
            if ~isfield(er,'eleTags'), return; end
            [cells, ~, familyTags] = obj.getRespFamilyStepData(segIdx);
            if isempty(cells), nodeScalar = NaN(nModelNode,1); return; end

            if isLayoutC
                scalarEleRaw = obj.extractElementScalarLayoutC(segIdx, fld, localStep);
            else
                data  = double(fld.data);
                dofs_ = {};
                if isfield(fld,'dofs'), dofs_ = fld.dofs; end
                scalarEleRaw = obj.extractElementScalarAtStep(data, localStep, dofs_);
            end

            respTags = obj.getRespEleTagsAtStep(segIdx, localStep);
            [scalarEleRaw, respTags] = obj.normalizeRespElementData(scalarEleRaw, respTags);

            scalarEle = NaN(size(cells,1),1);
            if ~isempty(respTags)
                [tf, loc] = ismember(double(familyTags(:)), respTags(:));
                respRows  = zeros(numel(familyTags),1);
                respRows(tf) = loc(tf);
                validRows = respRows > 0 & respRows <= numel(scalarEleRaw);
                scalarEle(validRows) = scalarEleRaw(respRows(validRows));
            else
                nCopy = min(numel(scalarEleRaw), numel(scalarEle));
                scalarEle(1:nCopy) = scalarEleRaw(1:nCopy);
            end
            eleScalar = scalarEle;

            [cellsModel, ~, keepRows] = obj.remapCellsToModelRows(cells, segIdx);
            scalarDisp = scalarEle(keepRows);

            nodeAcc = zeros(nModelNode,1);
            nodeCnt = zeros(nModelNode,1,'uint32');
            for e = 1:size(cellsModel,1)
                if e > numel(scalarDisp) || ~isfinite(scalarDisp(e)), continue; end
                conn = double(cellsModel(e,:));
                conn = conn(isfinite(conn) & conn > 0);
                if isempty(conn), continue; end
                % Format: [nPts, idx1, idx2, ...]
                nPts_ = round(conn(1));
                if isfinite(nPts_) && nPts_ >= 1 && numel(conn) >= nPts_+1
                    ni = conn(2:1+nPts_);
                else
                    ni = conn;
                end
                ni = round(ni);
                ni = ni(ni > 0 & ni <= nModelNode);
                if isempty(ni), continue; end
                nodeAcc(ni) = nodeAcc(ni) + scalarDisp(e);
                nodeCnt(ni) = nodeCnt(ni) + 1;
            end
            mask = nodeCnt > 0;
            out  = NaN(nModelNode,1);
            out(mask) = nodeAcc(mask) ./ double(nodeCnt(mask));
            nodeScalar = out;
        end

        % =================================================================
        % Element scalar extraction helpers
        % =================================================================

        function scalarNode = extractNodeScalarAtStep(obj, data, localStep, dofs)
            nd = ndims(data);
            si = min(localStep, size(data,1));
            switch nd
                case 3
                    slice = reshape(data(si,:,:), size(data,2), size(data,3));
                    if isvector(slice), slice = slice(:); end
                    scalarNode = unstru_dof_scalar(slice, dofs, obj.Component);
                case 4
                    blk = reshape(data(si,:,:,:), size(data,2), size(data,3), size(data,4));
                    fibIdx = unstru_fiber_idx(obj.FiberPoint, size(blk,2));
                    slice  = squeeze(blk(:,fibIdx,:));
                    if isvector(slice), slice = slice(:); end
                    scalarNode = unstru_dof_scalar(slice, dofs, obj.Component);
                otherwise
                    error('PlotUnstruResponse:UnsupportedNodeDataShape','Unsupported dim: %d',nd);
            end
            scalarNode = double(scalarNode(:));
        end

        function scalarEle = extractElementScalarAtStep(obj, data, localStep, dofs)
            nd = ndims(data);
            si = min(localStep, size(data,1));
            switch nd
                case 3
                    slice = reshape(data(si,:,:), size(data,2), size(data,3));
                    if isvector(slice), slice = slice(:); end
                    scalarEle = unstru_dof_scalar(slice, dofs, obj.Component);
                case 4
                    blk = reshape(data(si,:,:,:), size(data,2), size(data,3), size(data,4));
                    blk = obj.reduceGaussBlock(blk);
                    blk = squeeze(blk);
                    if isvector(blk), blk = blk(:); end
                    scalarEle = unstru_dof_scalar(blk, dofs, obj.Component);
                case 5
                    blk = reshape(data(si,:,:,:,:), size(data,2), size(data,3), size(data,4), size(data,5));
                    fibIdx = unstru_fiber_idx(obj.FiberPoint, size(blk,3));
                    blk = squeeze(blk(:,:,fibIdx,:));
                    blk = obj.reduceGaussBlock(blk);
                    blk = squeeze(blk);
                    if isvector(blk), blk = blk(:); end
                    scalarEle = unstru_dof_scalar(blk, dofs, obj.Component);
                otherwise
                    error('PlotUnstruResponse:UnsupportedElementDataShape','Unsupported dim: %d',nd);
            end
            scalarEle = double(scalarEle(:));
        end

        function scalarNode = extractNodeScalarLayoutC(obj, segIdx, entry, localStep)
            fn  = fieldnames(entry);
            idx = find(strcmpi(fn, obj.Component), 1);
            if isempty(idx)
                % Check sub-structs (e.g. principal.p1)
                for fi = 1:numel(fn)
                    if isstruct(entry.(fn{fi}))
                        subfn = fieldnames(entry.(fn{fi}));
                        sidx  = find(strcmpi(subfn, obj.Component), 1);
                        if ~isempty(sidx)
                            entry = entry.(fn{fi});
                            fn    = subfn;
                            idx   = sidx;
                            break;
                        end
                    end
                end
            end
            if isempty(idx)
                error('PlotUnstruResponse:ComponentNotFound', ...
                    'Component "%s" not found. Available: %s', obj.Component, strjoin(fn.',', '));
            end
            raw    = double(entry.(fn{idx}));
            si     = min(localStep, size(raw,1));
            scalarNode = double(raw(si,:).');
        end

        function scalar = extractElementScalarLayoutC(obj, segIdx, entry, localStep)
            fn  = fieldnames(entry);
            idx = find(strcmpi(fn, obj.Component), 1);
            if isempty(idx)
                % Check sub-structs (e.g. principal.p1)
                for fi = 1:numel(fn)
                    if isstruct(entry.(fn{fi}))
                        subfn = fieldnames(entry.(fn{fi}));
                        sidx  = find(strcmpi(subfn, obj.Component), 1);
                        if ~isempty(sidx)
                            entry = entry.(fn{fi});
                            fn    = subfn;
                            idx   = sidx;
                            break;
                        end
                    end
                end
            end
            if isempty(idx)
                error('PlotUnstruResponse:ComponentNotFound', ...
                    'Component "%s" not found. Available: %s', obj.Component, strjoin(fn.',', '));
            end
            raw = double(entry.(fn{idx}));
            si  = min(localStep, size(raw,1));
            nd  = ndims(raw);
            if nd == 2
                scalar = double(raw(si,:).');
                return;
            end
            if nd == 3
                slice = reshape(raw(si,:,:), size(raw,2), size(raw,3));
                blk   = reshape(slice, size(slice,1), size(slice,2), 1);
                scalar = double(squeeze(obj.reduceGaussBlock(blk)));
            elseif nd == 4
                slice  = reshape(raw(si,:,:,:), size(raw,2), size(raw,3), size(raw,4));
                fibIdx = unstru_fiber_idx(obj.FiberPoint, size(slice,3));
                slice2 = slice(:,:,fibIdx);
                blk    = reshape(slice2, size(slice2,1), size(slice2,2), 1);
                scalar = double(squeeze(obj.reduceGaussBlock(blk)));
            else
                scalar = double(raw(si,:,1).');
            end
            scalar = scalar(:);
        end

        function out = reduceGaussBlock(obj, blk)
            if isempty(blk), out = blk; return; end
            mode = lower(strtrim(char(string(obj.Opts.surf.gpReduce))));
            if isempty(mode), mode = 'mean'; end
            switch mode
                case 'mean',   out = mean(blk,2,'omitnan');
                case 'max',    out = max(blk,[],2);
                case 'min',    out = min(blk,[],2);
                case 'absmax'
                    nEle=size(blk,1); nGp=size(blk,2); nDof=size(blk,3);
                    out=NaN(nEle,1,nDof);
                    absBlk=abs(blk); absBlk(~isfinite(absBlk))=-inf;
                    [~,idx]=max(absBlk,[],2);
                    for d=1:nDof
                        id=idx(:,1,d); col=NaN(nEle,1);
                        for e=1:nEle
                            if isfinite(id(e))&&id(e)>=1&&id(e)<=nGp
                                col(e)=blk(e,id(e),d);
                            end
                        end
                        out(:,1,d)=col;
                    end
                case 'index'
                    gpIdx=round(double(obj.Opts.surf.gpIndex));
                    nGp=size(blk,2);
                    gpIdx=max(1,min(nGp,gpIdx));
                    out=blk(:,gpIdx,:);
                otherwise
                    error('PlotUnstruResponse:InvalidGpReduce','Unknown gpReduce "%s".',mode);
            end
        end

        function [respData, respTags] = normalizeRespElementData(~, respData, respTags)
            respData = double(respData);
            if isempty(respData), respTags = zeros(0,1); return; end
            if isvector(respData), respData = respData(:); end
            if isempty(respTags), return; end
            respTags = double(respTags(:));
            valid    = isfinite(respTags);
            nValid   = nnz(valid);
            nRowData = size(respData,1);
            if nRowData == numel(respTags)
                respData = respData(valid,:);
                respTags = respTags(valid);
            elseif nRowData == nValid
                respTags = respTags(valid);
            else
                respTags = respTags(valid);
                nUse = min(numel(respTags), nRowData);
                respTags = respTags(1:nUse);
                respData = respData(1:nUse,:);
            end
            if isempty(respTags), respData = zeros(0,size(respData,2)); end
        end

        function [cellsModel, modelRowsUsed, keepRows] = remapCellsToModelRows(obj, cells, segIdx)
            % Cell format: [nPts, idx1, idx2, ...] with 1-based row indices.
            % No rawToClean remapping — indices reference node coord array directly.
            cells = double(cells);
            nPdef = size(obj.getNodeCoordsRaw(segIdx), 1);
            keepRows      = false(size(cells,1),1);
            modelRowsUsed = zeros(0,1);

            if isempty(cells) || size(cells,2) < 2
                cellsModel = zeros(0, max(size(cells,2),1));
                return;
            end

            for i = 1:size(cells,1)
                nPts = round(cells(i,1));
                if ~isfinite(nPts) || nPts < 1, continue; end
                nPts = min(nPts, size(cells,2)-1);
                ids  = round(cells(i, 2:1+nPts));
                if all(isfinite(ids) & ids >= 1 & ids <= nPdef)
                    keepRows(i) = true;
                    modelRowsUsed = [modelRowsUsed; ids(:)]; %#ok<AGROW>
                end
            end
            cellsModel = cells(keepRows,:);
            if ~isempty(modelRowsUsed), modelRowsUsed = unique(modelRowsUsed,'stable'); end
        end

        % =================================================================
        % Drawing
        % =================================================================

        function [h, pts] = drawLine(obj, P, lines, solidColor, lw, tag)
            h = gobjects(0);  pts = zeros(0,3);
            if isempty(P) || isempty(lines), return; end
            s.nodes=P; s.lines=lines; s.lineWidth=lw;
            s.lineStyle=obj.Opts.line.lineStyle; s.color=solidColor; s.tag=tag;
            h = obj.Plotter.addLine(s);
            pts = P;
        end

        function [h, pts] = drawUnstructured(obj, Pdef, segIdx, Snode, Sele, clim_, asUndeformed)
            % Pdef has rows for CLEAN (kept) nodes only.
            % Cells reference the RAW coord array.  Expand Pdef back to
            % raw size so that cell indices are valid.
            h = gobjects(0);  pts = zeros(0,3);
            if ~obj.Opts.surf.show || isempty(Pdef), return; end
            R0 = obj.getRespFamily(segIdx);
            if isempty(R0)||~isfield(R0,'Cells')||isempty(R0.Cells), return; end
            if ~isfield(R0,'CellTypes')||isempty(R0.CellTypes), return; end

            [cells, types] = obj.getRespFamilyStepData(segIdx);
            if isempty(cells), return; end

            % types is [nCell x 1] — ensure column vector, never squeeze
            types = types(:);
            nCell = min(size(cells,1), numel(types));
            cells = cells(1:nCell,:);
            types = types(1:nCell);

            % Keep rows that are not entirely NaN (partial NaN = padding, OK)
            keepRowsMask = ~all(isnan(cells), 2);
            cells = cells(keepRowsMask,:);
            types = types(keepRowsMask);

            % Drop invalid cell types
            validTypes = isfinite(types);
            cells = cells(validTypes,:);
            types = types(validTypes);
            if isempty(cells), return; end

            keepRows = 1:numel(types);  % for Sele indexing (all remaining)
            cellsModel = double(cells);
            usedRows   = true;

            useNode = false;  useEle = false;
            mode = lower(char(string(obj.Opts.surf.colorMode)));
            switch mode
                case 'node',    useNode = ~isempty(Snode);
                case 'element', useEle  = ~isempty(Sele);
                otherwise
                    if unstru_is_node_based(obj.RespType), useNode = ~isempty(Snode);
                    else, useEle = ~isempty(Sele); end
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
            elseif useNode && ~isempty(Snode)
                surfOut = plotter.utils.VTKElementTriangulator.triangulate( ...
                    Pdef, types, cellsModel, 'Scalars', Snode, 'ScalarsByElement', false);
            else
                surfOut = plotter.utils.VTKElementTriangulator.triangulate(Pdef, types, cellsModel);
            end

            if isempty(surfOut)||~isfield(surfOut,'Points')||isempty(surfOut.Points), return; end

            s.nodes = double(surfOut.Points);
            s.tris  = double(surfOut.Triangles);
            s.tag   = 'Surf';
            pts = double(surfOut.Points);
            if isfield(surfOut,'EdgePoints')&&~isempty(surfOut.EdgePoints)
                pts = [pts; double(surfOut.EdgePoints)];
            end

            if asUndeformed
                s.faceColor = obj.Opts.color.undeformedColor;
                s.faceAlpha = obj.Opts.color.undeformedAlpha;
                h = obj.Plotter.addMesh(s);
            elseif useEle && isfield(surfOut,'CellScalars') && isfield(surfOut,'TriCellIds')
                s.values        = double(surfOut.CellScalars(double(surfOut.TriCellIds(:))));
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

            if obj.Opts.surf.showEdges && isfield(surfOut,'EdgePoints') && ~isempty(surfOut.EdgePoints)
                w.points=surfOut.EdgePoints; w.color=obj.Opts.surf.edgeColor;
                w.lineWidth=obj.Opts.surf.edgeWidth; obj.Plotter.addLine(w);
            end
        end

        function [h, pts] = drawFixed(obj, Pdef, segIdx)
            h = gobjects(0);  pts = zeros(0,3);
            if ~obj.Opts.fixed.show, return; end
            mi = obj.ModelInfo(segIdx);
            if ~isfield(mi,'Fixed')||~isfield(mi.Fixed,'NodeIndex')||isempty(mi.Fixed.NodeIndex)
                return;
            end
            idx = double(mi.Fixed.NodeIndex(:));
            idx = idx(isfinite(idx));
            [~, rawToClean] = obj.getNodeStepSelection(segIdx);
            valid = idx >= 1 & idx <= numel(rawToClean);
            idx   = idx(valid);
            if isempty(idx), return; end
            idx = rawToClean(round(idx));
            idx = idx(idx >= 1 & idx <= size(Pdef,1));
            if isempty(idx), return; end
            s.points=Pdef(idx,:); s.size=obj.Opts.fixed.size; s.marker=obj.Opts.fixed.marker;
            s.filled=obj.Opts.fixed.filled; s.edgeColor=obj.Opts.fixed.edgeColor;
            s.color=obj.Opts.fixed.color; s.tag='FixedNodes';
            h = obj.Plotter.addPoints(s);
            pts = s.points;
        end

        % =================================================================
        % Axes decoration
        % =================================================================

        function prepareAxes(obj, segIdx)
            if obj.Opts.general.clearAxes, cla(obj.Ax,'reset'); hold(obj.Ax,'on');
            elseif obj.Opts.general.holdOn, hold(obj.Ax,'on'); end
            if obj.Opts.general.axisEqual, axis(obj.Ax,'equal'); end
            if obj.Opts.general.grid, grid(obj.Ax,'on'); else, grid(obj.Ax,'off'); end
            if obj.Opts.general.box,  box(obj.Ax,'on');  else, box(obj.Ax,'off');  end
            colormap(obj.Ax, obj.Opts.color.colormap);
            obj.applyFigureSize();
            P = obj.getNodeCoordsRaw(segIdx);
            obj.CachedModelDim  = obj.computeModelDim(segIdx, P);
            obj.CachedModelSize = obj.computeModelLength(P);
        end

        function applyFigureSize(obj)
            figSize = obj.Opts.general.figureSize;
            if isempty(figSize), return; end
            fig = ancestor(obj.Ax,'figure');
            if isempty(fig)||~isgraphics(fig,'figure'), return; end
            fig.Units='pixels'; pos=fig.Position; figSize=double(figSize(:).');
            if numel(figSize)==2, pos(3:4)=figSize;
            elseif numel(figSize)==4, pos=figSize;
            else, error('PlotUnstruResponse:InvalidFigureSize','figureSize must be [w h] or [l b w h].'); end
            fig.Position = pos;
        end

        function applyView(obj, segIdx)
            v = lower(char(string(obj.Opts.general.view)));
            if strcmp(v,'auto')
                if obj.CachedModelDim==2, view(obj.Ax,2); else, view(obj.Ax,3); end; return;
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
                    if obj.CachedModelDim==2, view(obj.Ax,2); else, view(obj.Ax,3); end
            end
        end

        function applyDisplayLimits(obj, P)
            if isempty(P)||~ismatrix(P), return; end
            P = double(P);
            if size(P,2)<3, P(:,3)=0; end
            valid = all(isfinite(P),2);
            P = P(valid,:);
            if isempty(P), return; end
            mn = min(P,[],1);  mx = max(P,[],1);
            span = mx - mn;
            L   = max([span, obj.CachedModelSize, 1]);
            pad = max(obj.Opts.general.padRatio * L, 1e-6);
            % Ensure strictly increasing limits
            for col = 1:3
                lo = mn(col) - pad;  hi = mx(col) + pad;
                if lo >= hi, hi = lo + max(pad, 1e-6); end
                switch col
                    case 1, xlim(obj.Ax,[lo,hi]);
                    case 2, ylim(obj.Ax,[lo,hi]);
                    case 3, if obj.CachedModelDim==3, zlim(obj.Ax,[lo,hi]); end
                end
            end
        end

        function applyTitle(obj, segIdx, localStep, globalStep)
            t = string(obj.Opts.general.title);
            if strcmpi(t,'auto')
                time_ = NaN;
                nr = obj.safeGetSeg(obj.NodalResp, segIdx);
                if isfield(nr,'time') && numel(nr.time) >= localStep
                    time_ = nr.time(localStep);
                else
                    er = obj.safeGetSeg(obj.EleResp, segIdx);
                    if isfield(er,'time') && numel(er.time) >= localStep
                        time_ = er.time(localStep);
                    end
                end
                fpTxt = '';
                if ~isempty(obj.FiberPoint)
                    fpTxt = sprintf('  |  fiber=%s', char(string(obj.FiberPoint)));
                end
                gpTxt = '';
                if ~unstru_is_node_based(obj.RespType)
                    gpMode = lower(strtrim(char(string(obj.Opts.surf.gpReduce))));
                    if strcmp(gpMode,'index')
                        gpTxt = sprintf('  |  gp=%d', round(double(obj.Opts.surf.gpIndex)));
                    else
                        gpTxt = sprintf('  |  gp=%s', gpMode);
                    end
                end
                title(obj.Ax, sprintf('%s  %s  %s%s%s\nstep %d  |  t = %.4g s', ...
                    obj.EleType, obj.RespType, obj.Component, fpTxt, gpTxt, globalStep, time_));
            elseif strlength(t)>0
                title(obj.Ax, char(t));
            end
        end

        function applyColorbar(obj, clim_)
            if ~obj.Opts.color.useColormap||~obj.Opts.cbar.show
                colorbar(obj.Ax,'off'); return;
            end
            if ~isempty(clim_)&&diff(clim_)>0, clim(obj.Ax,clim_); end
            cb=colorbar(obj.Ax); cb.FontSize=11; cb.TickDirection='in';
            cb.Title.String=''; cb.Label.String=obj.getColorbarSideTitle();
            cb.Label.FontSize=13; cb.Label.FontWeight='normal';
        end

        function titleText = getColorbarSideTitle(obj)
            base  = char(string(obj.cbarTitle));
            extra = string(obj.Opts.cbar.label);
            if strlength(strtrim(extra))>0
                if isempty(strtrim(base)), titleText = char(extra);
                else, titleText = sprintf('%s | %s', base, char(extra)); end
            else
                titleText = base;
            end
        end

        function clim_ = resolveClim(obj, S)
            if ~isempty(obj.Opts.color.clim), clim_ = obj.Opts.color.clim; return; end
            mode = lower(char(string(obj.Opts.color.climMode)));
            switch mode
                case 'absmax', [a,b]=obj.globalClim(); clim_=[0,max(abs(a),abs(b))];
                case 'absmin', [a,b]=obj.globalClim(); clim_=[0,min(abs(a),abs(b))];
                case 'range',  [a,b]=obj.globalClim(); clim_=[a,b];
                otherwise
                    Sf=S(isfinite(S));
                    if isempty(Sf), clim_=[0 1]; return; end
                    a=min(Sf); b=max(Sf); if a==b, b=a+1; end; clim_=[a,b];
            end
        end

        % =================================================================
        % Geometry utilities
        % =================================================================

        function dim = computeModelDim(~, ~, P)
            % 2-D when all node z-coordinates are (numerically) zero.
            if isempty(P)||size(P,2)<3, dim=2; return; end
            z = P(:,3);  z = z(isfinite(z));
            if isempty(z)||all(abs(z)<1e-10), dim=2; else, dim=3; end
        end

        function ndm = getModelNdm(obj, segIdx)
            ndm = [];
            mi  = obj.ModelInfo(segIdx);
            if ~isfield(mi,'Nodes')||~isfield(mi.Nodes,'Ndm')||isempty(mi.Nodes.Ndm)
                return;
            end
            ndm = double(mi.Nodes.Ndm(:));
        end

        function L = computeModelLength(~, P)
            if isempty(P), L=1; return; end
            ext=max(P,[],1,'omitnan')-min(P,[],1,'omitnan');
            ext=ext(isfinite(ext));
            if isempty(ext), L=1; return; end
            L=max(ext); if ~isfinite(L)||L<=0, L=1; end
        end

        function U3 = extractXYZ(~, U)
            U3 = zeros(size(U,1),3);
            U3(:,1:min(3,size(U,2))) = U(:,1:min(3,size(U,2)));
        end

        function rt = normalizeRespType(obj, segIdx, rt)
            rt = char(rt);
            er = obj.EleResp(segIdx);
            if isfield(er,rt), return; end
            fn = fieldnames(er);
            m  = fn(strcmpi(fn,rt));
            if ~isempty(m), rt = m{1}; end
        end

        function values = trimVectorLength(~, values, nRow)
            values = values(:);
            if numel(values)<nRow, values(end+1:nRow,1)=NaN;
            elseif numel(values)>nRow, values=values(1:nRow); end
        end

        function key = makeRespKey(obj)
            if isempty(obj.FiberPoint), fp = '';
            elseif isnumeric(obj.FiberPoint)&&isscalar(obj.FiberPoint), fp=sprintf('%g',obj.FiberPoint);
            else, fp = char(string(obj.FiberPoint)); end
            gpMode = lower(strtrim(char(string(obj.Opts.surf.gpReduce))));
            gpIdx  = round(double(obj.Opts.surf.gpIndex));
            key = sprintf('%s|%s|%s|%s|%s|%d', ...
                char(string(obj.EleType)), char(string(obj.RespType)), ...
                char(string(obj.Component)), fp, gpMode, gpIdx);
        end

        function key = normalizeStepSelector(~, s)
            key = lower(strtrim(char(string(s))));
            switch key
                case 'stepmax',    key='max';
                case 'stepmin',    key='min';
                case 'stepabsmax', key='absmax';
                case 'stepabsmin', key='absmin';
            end
        end

        function vals = initStepSelectorValues(~, key, n)
            switch key
                case {'absmax','max'}, vals=-inf(n,1);
                case {'absmin','min'}, vals= inf(n,1);
                otherwise,            vals= NaN(n,1);
            end
        end

        function out = mergeStruct(obj, base, add)
            out = base;
            if isempty(add)||~isstruct(add), return; end
            for fn=fieldnames(add).'
                n=fn{1};
                if isfield(out,n)&&isstruct(out.(n))&&isstruct(add.(n))
                    out.(n)=obj.mergeStruct(out.(n),add.(n));
                else, out.(n)=add.(n); end
            end
        end

    end % private methods
end % classdef

% =========================================================================
% Package-level helper functions (unchanged from original)
% =========================================================================

function [rt, comp, fp] = unstru_check_shell(rt, comp, fp)
    if isempty(rt), rt = ''; end
    rt0   = lower(strrep(char(rt),' ',''));
    isN   = contains(rt0,'node');
    isDefo = contains(rt0,'defo');
    if isempty(comp), comp = 'mxx'; end
    cl = lower(strtrim(char(comp)));
    aliases = {'sigma11','sxx';'sigma22','syy';'sigma12','sxy';'sigma23','syz';'sigma13','sxz';...
               'eps11','exx';'eps22','eyy';'eps12','exy';'eps23','eyz';'eps13','exz'};
    for k=1:size(aliases,1); if strcmp(cl,aliases{k,1}), cl=aliases{k,2}; break; end; end
    comp = cl;
    secComp={'fxx','fyy','fxy','mxx','myy','mxy','vxz','vyz'};
    stressComp={'sxx','syy','sxy','syz','sxz'};
    strainComp={'exx','eyy','exy','eyz','exz'};
    if ismember(cl,secComp)
        if isDefo, rt='SecDefoAtGP'; if isN, rt='SecDefoAtNode'; end
        else,      rt='SecForceAtGP'; if isN, rt='SecForceAtNode'; end; end
        fp = [];
    elseif ismember(cl,stressComp)
        rt='StressAtGP'; if isN, rt='StressAtNode'; end
        if isempty(fp), fp='top'; end
        if ischar(fp)||isstring(fp)
            fp=lower(char(fp));
            if ~ismember(fp,{'top','bottom','middle'}), error('PlotUnstruResponse:BadFiberPoint','fiberPoint must be top|bottom|middle or integer.'); end
        end
    elseif ismember(cl,strainComp)
        rt='StrainAtGP'; if isN, rt='StrainAtNode'; end
        if isempty(fp), fp='top'; end
        if ischar(fp)||isstring(fp)
            fp=lower(char(fp));
            if ~ismember(fp,{'top','bottom','middle'}), error('PlotUnstruResponse:BadFiberPoint','fiberPoint must be top|bottom|middle or integer.'); end
        end
    else
        error('PlotUnstruResponse:BadComponent','Shell component "%s" not recognised.',comp);
    end
end

function [rt, comp] = unstru_check_plane(rt, comp)
    if isempty(rt), rt=''; end
    rt0=lower(strrep(char(rt),' ','')); isN=contains(rt0,'node');
    if isempty(comp), comp='sxx'; end
    cl=lower(strtrim(char(comp)));
    aliases={'sigma11','sxx';'sigma22','syy';'sigma12','sxy';'sigma33','szz';'eps11','exx';'eps22','eyy';'eps12','exy'};
    for k=1:size(aliases,1); if strcmp(cl,aliases{k,1}), cl=aliases{k,2}; break; end; end
    comp=cl;
    stressComp={'sxx','syy','szz','sxy'}; strainComp={'exx','eyy','exy'};
    measures={'sigmaoct', 'tauoct', 'taumax','vonmises','p1','p2','p3'};
    if ismember(cl,stressComp), rt='StressAtGP'; if isN, rt='StressAtNode'; end
    elseif ismember(cl,strainComp), rt='StrainAtGP'; if isN, rt='StrainAtNode'; end
    elseif ismember(cl,measures), rt='StressMeasureAtGP'; if isN, rt='StressMeasureAtNode'; end
    else, error('PlotUnstruResponse:BadComponent','Plane component "%s" not recognised.',comp); end
end

function [rt, comp] = unstru_check_solid(rt, comp)
    if isempty(rt), rt=''; end
    rt0=lower(strrep(char(rt),' ','')); isN=contains(rt0,'node');
    if isempty(comp), comp='sxx'; end
    cl=lower(strtrim(char(comp)));
    aliases={'sigma11','sxx';'sigma22','syy';'sigma33','szz';'sigma12','sxy';'sigma23','syz';'sigma13','sxz';...
             'eps11','exx';'eps22','eyy';'eps33','ezz';'eps12','exy';'eps23','eyz';'eps13','exz'};
    for k=1:size(aliases,1); if strcmp(cl,aliases{k,1}), cl=aliases{k,2}; break; end; end
    comp=cl;
    stressComp={'sxx','syy','szz','sxy','syz','sxz'}; strainComp={'exx','eyy','ezz','exy','eyz','exz'};
    measures={'sigmaoct', 'tauoct', 'taumax','vonmises','p1','p2','p3'};
    if ismember(cl,stressComp), rt='StressAtGP'; if isN, rt='StressAtNode'; end
    elseif ismember(cl,strainComp), rt='StrainAtGP'; if isN, rt='StrainAtNode'; end
    elseif ismember(cl,measures), rt='StressMeasureAtGP'; if isN, rt='StressMeasureAtNode'; end
    else, error('PlotUnstruResponse:BadComponent','Solid component "%s" not recognised.',comp); end
end

function scalar = unstru_dof_scalar(mat, dofs, component)
    if isempty(mat), scalar=zeros(0,1); return; end
    if isvector(mat), mat=mat(:); end
    comp=strtrim(char(string(component)));
    if iscell(dofs)&&isscalar(dofs)&&iscell(dofs{1}), dofs=dofs{1}; end
    for d=1:numel(dofs)
        name=strtrim(char(string(dofs{d})));
        if strcmpi(name,comp)
            if size(mat,2)>=d, scalar=mat(:,d);
            else, scalar=zeros(size(mat,1),1); end
            return;
        end
    end
    error('PlotUnstruResponse:DofNotFound','Component "%s" not found in dofs.',component);
end

function idx = unstru_fiber_idx(fp, nFib)
    if isempty(fp), idx=nFib; return; end
    if ischar(fp)||isstring(fp)
        switch lower(char(fp))
            case 'top',    idx=nFib;
            case 'bottom', idx=1;
            case 'middle', idx=max(1,round(nFib/2));
            otherwise,     idx=nFib;
        end
    else
        idx=max(1,min(nFib,round(double(fp))));
    end
end

function tf = unstru_is_node_based(rt)
    tf = ~isempty(regexpi(rt,'atnode','once'));
end
