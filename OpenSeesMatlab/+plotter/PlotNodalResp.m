classdef PlotNodalResp < handle
    % PlotNodalResp
    % Nodal response visualisation based on PatchPlotter.
    %
    % Data layouts
    % ------------
    % nodalResp / modelInfo can each be:
    %   - Scalar struct  : single segment, no model topology change.
    %   - Struct array   : multiple segments, each element is a scalar
    %                      struct covering a contiguous block of global
    %                      time steps.  Topology is fixed *within* a
    %                      segment; it may change across segments.
    %
    % Global step indexing
    % --------------------
    % Global step g (0-based, matching plotStep convention) maps to
    %   segment  s  = first segment whose cumulative step count exceeds g
    %   local step  = g - sum(steps in segments 1..s-1)   (1-based internally)
    %
    % Use resolveGlobalStep(g) to obtain (segIdx, localStep).
    %
    % Quick start
    % -----------
    %   pr = plotter.PlotNodalResp(modelInfo, nodalResp);
    %   pr.plotStep('absmax');

    properties
        ModelInfo           % scalar struct  OR  struct array (one per segment)
        NodalResp           % scalar struct  OR  struct array (one per segment)
        Plotter     plotter.PatchPlotter
        Ax          matlab.graphics.axis.Axes
        Opts        struct
        Handles     struct = struct()
    end

    properties (Access = private)
        % Segment bookkeeping
        SegCount        double = 1      % number of segments
        SegStepCounts   double = []     % [1 x SegCount]  steps per segment
        SegOffsets      double = []     % [1 x SegCount]  cumulative offset before each segment

        % Cached geometry scalars (refreshed per segment as needed)
        CachedModelDim   double = 3
        CachedModelSize  double = 1

        GlobalClimCache  double = []
        GlobalClimField  char   = ''
        GlobalClimComp   char   = ''

        KnnIdxCache      double = []
        KnnRefPtCount    double = 0
        KnnQueryPtCount  double = 0

        RespTagToIdx     cell = {}    % {1 x SegCount}
        RespTagToIdxMap  cell = {}    % {1 x SegCount}
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

            opts.help = strjoin({
                '====== PlotNodalResp Options ======================================='
                ''
                '-- Field display -----------------------------------------------'
                '  field.type        ''disp'' | ''vel'' | ''accel'' | ''reaction'''
                '                    Response type to colour-map onto mesh.'
                '  field.component   ''magnitude'' | ''x'' | ''y'' | ''z'' | ''rx'' | ''ry'' | ''rz'''
                '  field.show        logical   Show colour-mapped field (default true).'
                ''
                '-- Deformation -------------------------------------------------'
                '  deform.show            logical  Draw deformed shape (default true).'
                '  deform.type            ''disp''   Field used to deform geometry.'
                '  deform.scale           double   Manual deformation scale factor.'
                '  deform.autoScale       logical  Auto-fit deformation to model size.'
                '  deform.showUndeformed  logical  Also draw undeformed ghost.'
                ''
                '-- Interpolation -----------------------------------------------'
                '  interp.useInterpolation  logical  Interpolate along frame members.'
                '  interp.lineWidth         double   Deformed line width.'
                '  interp.lineStyle         string   Line style (''-'', ''--'', etc.).'
                '  interp.undeformedLineWidth double  Undeformed line width.'
                ''
                '-- Vector arrows -----------------------------------------------'
                '  vector.show        logical  Draw reaction/load vectors (default false).'
                '  vector.type        ''reaction'' | ''load'''
                '  vector.components  [1 2 3]  DOF indices to draw.'
                '  vector.scale       double   Arrow scale factor.'
                '  vector.autoScale   logical  Auto-scale arrows.'
                '  vector.color       RGB      Arrow colour.'
                '  vector.lineWidth   double   Arrow line width.'
                ''
                '-- Color -------------------------------------------------------'
                '  color.useColormap     logical  Colour by value (default true).'
                '  color.colormap        N×3     Colormap matrix (default turbo(256)).'
                '  color.clim            [lo hi] Fixed colour limits; [] = auto.'
                '  color.climMode        ''step'' | ''global'''
                '  color.solidColor      color   Solid fill when useColormap=false.'
                '  color.undeformedColor color   Colour of undeformed ghost.'
                '  color.undeformedAlpha double  Opacity of undeformed ghost (0-1).'
                '  color.deformedAlpha   double  Opacity of deformed mesh (0-1).'
                ''
                '-- Surface / mesh edges ----------------------------------------'
                '  surf.show       logical  Draw filled surface (default true).'
                '  surf.showEdges  logical  Draw mesh edges.'
                '  surf.edgeColor  color   Edge colour.'
                '  surf.edgeWidth  double  Edge line width.'
                ''
                '-- Nodes -------------------------------------------------------'
                '  nodes.show       logical  Scatter-plot nodes.'
                '  nodes.size       double   Marker size.'
                '  nodes.marker     string   Marker shape (''o'', ''s'', etc.).'
                '  nodes.filled     logical  Filled markers.'
                '  nodes.edgeColor  color   Marker edge colour.'
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
                '  general.padRatio   double   Axis padding fraction (default 0.15).'
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
                '  opts = plotter.PlotNodalResp.defaultOptions();'
                '  disp(opts.help)              % print this help'
                '  opts.field.component = ''x'';'
                '  opts.color.climMode  = ''global'';'
                '  opts.deform.scale    = 10;'
                '  pr.plotStep(''absmax'', opts);'
                '================================================================='
                }, newline);
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

            obj.buildSegmentIndex();

            % Seed geometry cache from first segment
            P   = obj.getNodeCoords(1, 1);
            ndm = obj.getModelNdm(1);
            obj.CachedModelDim  = obj.computeModelDim(P, ndm);
            obj.CachedModelSize = obj.computeModelLength(P);
        end

        function ax = getAxes(obj), ax = obj.Ax; end

        function setOptions(obj, opts)
            prevField = obj.Opts.field.type;
            prevComp  = obj.Opts.field.component;
            obj.Opts  = obj.mergeStruct(obj.Opts, opts);
            if ~strcmp(prevField, obj.Opts.field.type) || ...
               ~strcmp(prevComp,  obj.Opts.field.component)
                obj.GlobalClimCache = [];
                obj.GlobalClimField = '';
                obj.GlobalClimComp  = '';
            end
        end

        function diagUnstru(obj)
            % Diagnose unstructured mesh cell mapping.
            segIdx = 1;
            fam = obj.getFamilies(segIdx);
            if ~isfield(fam,'Unstructured'), fprintf('No Unstructured family\n'); return; end
            U0 = fam.Unstructured;
            fprintf('Unstructured.Cells size: %s\n', mat2str(size(U0.Cells)));
            fprintf('Unstructured.CellTypes size: %s\n', mat2str(size(U0.CellTypes)));
            cells = double(U0.Cells);
            fprintf('First 3 rows of cells:\n'); disp(cells(1:min(3,end),:));
            P = obj.getNodeCoordsRaw(segIdx);
            fprintf('Node coords rows: %d\n', size(P,1));
            [keepMask, rawToClean] = obj.getNodeStepSelection(segIdx);
            fprintf('keepMask nnz: %d / %d\n', nnz(keepMask), numel(keepMask));
            fprintf('rawToClean max: %d\n', max(rawToClean));
            % Try mapping first row
            row = cells(1,:);
            nPts_ = row(1);
            ids = row(2:1+nPts_);
            fprintf('First cell nPts=%d, ids=%s\n', nPts_, mat2str(ids));
            fprintf('rawToClean length=%d, max id=%d\n', numel(rawToClean), max(ids));
            if max(ids) <= numel(rawToClean)
                fprintf('Mapped ids: %s\n', mat2str(rawToClean(ids)'));
            else
                fprintf('ERROR: ids exceed rawToClean length!\n');
            end
        end

        function diag(obj)
            % Temporary diagnostic — call pr.diag() to print key values.
            fprintf('=== PlotNodalResp diagnostics ===\n');
            fprintf('SegCount      : %d\n', obj.SegCount);
            fprintf('SegStepCounts : %s\n', mat2str(obj.SegStepCounts));
            fprintf('nSteps total  : %d\n', obj.nSteps());

            % Ndm
            ndm = obj.getModelNdm(1);
            fprintf('Nodes.Ndm max : %d  (dim=%d)\n', max(ndm), obj.CachedModelDim);

            % Node coords
            P = obj.getNodeCoordsRaw(1);
            fprintf('Node coords   : %d rows, Z range [%.3g, %.3g]\n', ...
                size(P,1), min(P(:,3)), max(P(:,3)));

            % Tags
            mt = obj.getModelNodeTagsRaw(1, size(P,1));
            nr = obj.NodalResp(1);
            rt = double(nr.nodeTags(:));
            fprintf('modelInfo tags: %s\n', mat2str(mt.'));
            fprintf('nodalResp tags: %s\n', mat2str(rt.'));

            % Resp slice at step 748 (global 747)
            [si, ls] = obj.resolveGlobalStep(747);
            fprintf('Global 747 -> seg %d, localStep %d\n', si, ls);
            U = obj.getRespSlice(si, 'disp', ls);
            mag = sqrt(sum(U(:,1:3).^2, 2, 'omitnan'));
            fprintf('disp magnitude at step 747: min=%.4g  max=%.4g\n', ...
                min(mag,[],'omitnan'), max(mag,[],'omitnan'));

            % absmax search
            g = obj.resolveGlobalStepArg('absmax');
            fprintf('absmax global step: %d\n', g);
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
            for g = 0 : obj.nSteps() - 1
                [si, ls] = obj.resolveGlobalStep(g);
                S = obj.getStepScalarValues(si, ls, fieldType, component);
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

        function n = nSteps(obj)
            n = sum(obj.SegStepCounts);
        end

    end

    % =====================================================================
    methods (Access = private)

        % =================================================================
        % Segment index
        % =================================================================

        function buildSegmentIndex(obj)
            % Determine SegCount, SegStepCounts, SegOffsets, and per-
            % segment response-tag lookup tables.
            obj.SegCount = numel(obj.NodalResp);
            obj.SegStepCounts = zeros(1, obj.SegCount);
            for s = 1:obj.SegCount
                obj.SegStepCounts(s) = obj.countSegSteps(s);
            end
            obj.SegOffsets = [0, cumsum(obj.SegStepCounts(1:end-1))];

            % Per-segment tag lookups
            obj.RespTagToIdx    = cell(1, obj.SegCount);
            obj.RespTagToIdxMap = cell(1, obj.SegCount);
            for s = 1:obj.SegCount
                [obj.RespTagToIdx{s}, obj.RespTagToIdxMap{s}] = ...
                    obj.buildSegRespTagLookup(s);
            end
        end

        function n = countSegSteps(obj, segIdx)
            % Count steps in segment segIdx using its time field or data dims.
            nr = obj.NodalResp(segIdx);
            if isfield(nr, 'time') && ~isempty(nr.time)
                n = numel(nr.time);
                return;
            end
            n = 0;
            % For Layout C, prefer canonical translation DOF fields so we
            % don't accidentally pick a scalar or metadata field.
            preferDofs = {'ux','uy','uz','rx','ry','rz'};
            for fn = fieldnames(nr).'
                A = nr.(fn{1});
                if isstruct(A)
                    if isfield(A, 'data')
                        A = A.data;
                    else
                        fn2 = fieldnames(A);
                        chosen = '';
                        for pd = preferDofs
                            if ismember(pd{1}, fn2), chosen = pd{1}; break; end
                        end
                        if isempty(chosen)
                            if isempty(fn2), continue; end
                            chosen = fn2{1};
                        end
                        A = A.(chosen);
                    end
                end
                if isnumeric(A) && ~isempty(A) && ndims(A) >= 2
                    n = size(A, 1);  return;
                end
            end
        end

        % =================================================================
        % Global → (segment, localStep) resolution
        % =================================================================

        function [segIdx, localStep] = resolveGlobalStep(obj, globalStep)
            % globalStep : 0-based integer
            % Returns segIdx (1-based) and localStep (1-based, for internal use).
            if globalStep < 0 || globalStep >= obj.nSteps()
                error('PlotNodalResp:InvalidStep', ...
                    'globalStep %d out of range [0, %d].', globalStep, obj.nSteps()-1);
            end
            % Find segment: first s where SegOffsets(s)+SegStepCounts(s) > globalStep
            segIdx = find(obj.SegOffsets + obj.SegStepCounts > globalStep, 1, 'first');
            localStep = globalStep - obj.SegOffsets(segIdx) + 1;  % 1-based
        end

        function globalStep = resolveGlobalStepArg(obj, arg)
            % Convert user-facing plotStep argument to 0-based global step.
            if isnumeric(arg)
                globalStep = round(arg);    % user passes 0-based integer directly
                return;
            end
            % String selector: absmax | absmin | max | min
            key = obj.normalizeStepSelector(arg);
            vals = obj.peakStepValuesFast(key);
            if isempty(vals)
                vals = obj.peakStepValuesSlow(key);
            end
            if isempty(vals)
                globalStep = 0;  return;
            end
            switch key
                case {'absmax','max'}
                    % When multiple steps tie, pick the LAST one so the
                    % analysis step wins over the initial state (step 0).
                    bestVal = max(vals, [], 'omitnan');
                    idx = find(vals == bestVal, 1, 'last');
                case {'absmin','min'}
                    bestVal = min(vals, [], 'omitnan');
                    idx = find(vals == bestVal, 1, 'last');
                otherwise
                    error('PlotNodalResp:InvalidStepIdx', ...
                        'Unknown step selector "%s".', key);
            end
            if isempty(idx) || ~isfinite(idx), idx = 1; end
            globalStep = idx - 1;
        end

        function vals = peakStepValuesFast(obj, key)
            % Batch peak search: extract full [nStep x nNode x nDof] array
            % per segment and reduce along spatial dims in one vectorised op.
            % Falls back to empty on layouts that can't be batched.
            %
            % CRITICAL: allPeak must have exactly nSteps() entries in global
            % step order.  Each segment contributes exactly SegStepCounts(s)
            % entries, aligned with the segment's time vector (including the
            % initial state at localStep=1 when recordInitialState is on).
            % If the data array has fewer rows than SegStepCounts(s) (e.g.
            % the recorder wrote no initial state for this field), we pad
            % the missing leading entries with 0 so that the index arithmetic
            % in resolveGlobalStepArg remains correct.
            vals = [];
            [fieldType, component] = obj.getStepSearchSpec();
            allPeak = [];
            for s = 1:obj.SegCount
                nExpected = obj.SegStepCounts(s);   % steps this segment should have
                ft = obj.normalizeFieldType(s, fieldType);
                nr = obj.NodalResp(s);
                if ~isfield(nr, ft)
                    % Field missing entirely — pad with zeros for this segment
                    allPeak = [allPeak; zeros(nExpected,1)]; %#ok<AGROW>
                    continue;
                end
                entry = nr.(ft);

                % Extract full array A: [nData x nNode x nDof]
                % nData may differ from nExpected when no initial state was
                % stored for this response field.
                A = [];
                if isstruct(entry) && isfield(entry, 'data')
                    A = double(entry.data);                     % Layout B
                elseif isnumeric(entry) && ndims(entry) == 3
                    A = double(entry);                          % Layout A
                elseif isstruct(entry)
                    % Layout C: stack DOF arrays along dim 3
                    dofs = obj.getRespDofs(s, ft);
                    if isempty(dofs)
                        allPeak = [allPeak; zeros(nExpected,1)]; %#ok<AGROW>
                        continue;
                    end
                    ref = [];
                    for di = 1:numel(dofs)
                        if isfield(entry, dofs{di}) && isnumeric(entry.(dofs{di}))
                            ref = entry.(dofs{di});  break;
                        end
                    end
                    if isempty(ref)
                        allPeak = [allPeak; zeros(nExpected,1)]; %#ok<AGROW>
                        continue;
                    end
                    nT = size(ref, 1);  nN = size(ref, 2);
                    A  = NaN(nT, nN, numel(dofs));
                    for di = 1:numel(dofs)
                        if isfield(entry, dofs{di})
                            arr = entry.(dofs{di});
                            if isnumeric(arr) && size(arr,1)==nT && size(arr,2)==nN
                                A(:,:,di) = double(arr);
                            end
                        end
                    end
                end
                if isempty(A) || ndims(A) < 3
                    allPeak = [allPeak; zeros(nExpected,1)]; %#ok<AGROW>
                    continue;
                end

                % Compute scalar field for all data steps: [nData x nNode]
                comp = lower(strtrim(char(string(component))));
                dofs = obj.getRespDofs(s, ft);
                switch comp
                    case {'magnitude','mag'}
                        M = sqrt(sum(A(:,:,1:min(3,size(A,3))).^2, 3, 'omitnan'));
                    case {'magnitude6','mag6'}
                        M = sqrt(sum(A.^2, 3, 'omitnan'));
                    otherwise
                        col = 0;
                        dofMap = struct('x',1,'ux',1,'y',2,'uy',2,'z',3,'uz',3,'rx',4,'ry',5,'rz',6);
                        for d = 1:numel(dofs)
                            if strcmpi(dofs{d}, comp), col = d; break; end
                        end
                        if col == 0 && isfield(dofMap, comp)
                            col = dofMap.(comp);
                        end
                        if col > 0 && size(A,3) >= col
                            M = A(:,:,col);
                        else
                            M = sqrt(sum(A(:,:,1:min(3,size(A,3))).^2, 3, 'omitnan'));
                        end
                end
                M(~isfinite(M)) = NaN;

                % Reduce over spatial dim -> [nData x 1]
                switch key
                    case {'absmax','absmin'}, p = max(abs(M), [], 2, 'omitnan');
                    case 'max',              p = max(M,       [], 2, 'omitnan');
                    case 'min',              p = min(M,       [], 2, 'omitnan');
                    otherwise, return;
                end
                p = p(:);
                nData = numel(p);

                % Align nData rows to nExpected:
                %   nData == nExpected  → perfect, use as-is
                %   nData <  nExpected  → data has no initial-state rows;
                %                         prepend zeros so global indices match
                %   nData >  nExpected  → truncate (shouldn't happen)
                if nData < nExpected
                    p = [zeros(nExpected - nData, 1); p]; %#ok<AGROW>
                elseif nData > nExpected
                    p = p(end - nExpected + 1 : end);
                end
                allPeak = [allPeak; p]; %#ok<AGROW>
            end
            if isempty(allPeak) || all(~isfinite(allPeak)), return; end
            vals = allPeak;
        end

        function vals = peakStepValuesSlow(obj, key)
            % Fallback: per-step scalar extraction (handles interp path, etc.)
            % NOTE: when the data array has no initial-state row (nData < nSteps),
            % localStep for g=0 and g=1 both clamp to arr(1,...) via min().
            % To avoid max() picking the wrong slot, we detect clamping and
            % treat the initial-state slot (g=0 within a segment) as zero peak.
            [fieldType, component] = obj.getStepSearchSpec();
            n    = obj.nSteps();
            vals = obj.initStepSelectorValues(key, n);
            for g = 0:n-1
                [si, ls] = obj.resolveGlobalStep(g);
                % Detect whether this local step is beyond the data array size.
                % If so, it is a clamped read of a repeated row — treat as zero.
                nr = obj.NodalResp(si);
                ft = obj.normalizeFieldType(si, fieldType);
                dataRows = obj.getDataRows(nr, ft);
                if dataRows > 0 && ls > dataRows
                    % ls clamped to dataRows: this is a missing initial-state slot.
                    % Set peak to 0 (initial state has zero response).
                    switch key
                        case {'absmax','absmin','max'}, vals(g+1) = 0;
                        case 'min',                     vals(g+1) = 0;
                    end
                    continue;
                end
                S = obj.getStepScalarValues(si, ls, fieldType, component, false);
                if isempty(S), continue; end
                switch key
                    case {'absmax','absmin'}, vals(g+1) = max(abs(S), [], 'omitnan');
                    case 'max',               vals(g+1) = max(S,       [], 'omitnan');
                    case 'min',               vals(g+1) = min(S,       [], 'omitnan');
                end
            end
            vals = vals(:);
            if all(~isfinite(vals)), vals = []; end
        end

        function n = getDataRows(~, nr, fieldType)
            % Return the number of time rows in the data for fieldType.
            % Returns 0 if the field is missing or has no time dimension.
            n = 0;
            if ~isfield(nr, fieldType), return; end
            entry = nr.(fieldType);
            if isstruct(entry) && isfield(entry, 'data')
                if ~isempty(entry.data) && ndims(entry.data) >= 2
                    n = size(entry.data, 1);
                end
            elseif isnumeric(entry) && ndims(entry) >= 2
                n = size(entry, 1);
            elseif isstruct(entry)
                % Layout C: check first numeric sub-field
                for fn = fieldnames(entry).'
                    A = entry.(fn{1});
                    if isnumeric(A) && ~isempty(A) && ndims(A) >= 2
                        n = size(A, 1);  return;
                    end
                end
            end
        end

        % =================================================================
        % Core render
        % =================================================================

        function renderStep(obj, segIdx, localStep, globalStep)
            P        = obj.getNodeCoords(segIdx, localStep);
            lineConn = obj.getLineConn(segIdx);
            [Pdef, ~, ~] = obj.getDeformedCoords(P, segIdx, localStep);
            [Snode, clim_] = obj.getScalarField(segIdx, localStep);
            shownPts = Pdef;

            if obj.Opts.deform.show && obj.Opts.deform.showUndeformed
                obj.Handles.UndeformedLine = obj.drawLine( ...
                    P, lineConn, obj.Opts.color.undeformedColor, ...
                    obj.Opts.line.undeformedLineWidth, 'UndeformedLine');
                obj.Handles.UndeformedSurf = obj.drawUnstructured( ...
                    P, segIdx, [], [], true);
            end

            if obj.Opts.line.show
                if obj.hasInterpData(segIdx, localStep) && obj.Opts.interp.useInterpolation
                    [obj.Handles.Line, Pline] = obj.drawInterpolatedLine( ...
                        segIdx, localStep, Snode, clim_);
                    shownPts = [shownPts; Pline];
                else
                    obj.Handles.Line = obj.drawLine( ...
                        Pdef, lineConn, obj.Opts.color.solidColor, ...
                        obj.Opts.line.lineWidth, 'Line', Snode, clim_);
                end
            end

            if obj.Opts.surf.show
                obj.Handles.Surf = obj.drawUnstructured(Pdef, segIdx, Snode, clim_, false);
            end
            if obj.Opts.nodes.show
                obj.Handles.Nodes = obj.drawNodes(Pdef, Snode, clim_);
            end

            obj.Handles.Fixed = obj.drawFixed(Pdef, segIdx);

            if obj.Opts.vector.show
                obj.Handles.Vector = obj.drawVectorField(Pdef, segIdx, localStep);
            end

            obj.applyColorbar(clim_);
            obj.applyTitle(segIdx, localStep, globalStep);
            obj.applyView(segIdx);
            % Filter out NaN/Inf rows and ensure each axis has a nonzero
            % span before calling applyDataLimits (xlim/ylim require
            % strictly increasing limits; a zero-span axis — e.g. a purely
            % vertical 2-D frame — would otherwise crash).
            if ~isempty(shownPts)
                validRows = all(isfinite(shownPts), 2);
                shownPts  = shownPts(validRows, :);
            end
            if ~isempty(shownPts)
                % Guarantee minimum span of 1 in every direction so that
                % padded limits are always strictly increasing.
                span = max(shownPts,[],1,'omitnan') - min(shownPts,[],1,'omitnan');
                if any(~isfinite(span) | span == 0)
                    ctr  = mean(shownPts, 1, 'omitnan');
                    half = max(max(span(isfinite(span) & span > 0), [], 'omitnan') / 2, 1);
                    for col = find(~isfinite(span) | span == 0)
                        shownPts(end+1, :) = ctr; %#ok<AGROW>
                        shownPts(end,   col) = ctr(col) - half;
                        shownPts(end+1, :) = ctr; %#ok<AGROW>
                        shownPts(end,   col) = ctr(col) + half;
                    end
                end
                obj.Plotter.applyDataLimits(shownPts, obj.Opts.general.padRatio);
            end
        end

        % =================================================================
        % Interpolated beam line
        % =================================================================

        function tf = hasInterpData(obj, segIdx, localStep)
            nr = obj.NodalResp(segIdx);
            tf = isfield(nr,'interpolatePoints') && ...
                 isfield(nr,'interpolateDisp')   && ...
                 isfield(nr,'interpolateCells')  && ...
                 ~isempty(nr.interpolatePoints);
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

            % pts may be static (nPts x 3) or per-step (nStep x nPts x 3).
            if ndims(pts) == 3
                si  = min(localStep, size(pts,1));
                pts = squeeze(pts(si,:,:));
            end

            % disp_ is always per-step (nStep x nPts x 3); slice independently.
            if ndims(disp_) == 3
                si    = min(localStep, size(disp_,1));
                disp_ = squeeze(disp_(si,:,:));
            end

            if size(pts,2)   < 3, pts(:,3)   = 0; end
            if size(disp_,2) < 3, disp_(:,3) = 0; end

            if ndims(cells_) == 3
                si     = min(localStep, size(cells_,1));
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

            pts   = pts(valid,:);
            disp_ = disp_(valid,:);

            if isempty(cells_)
                cells = zeros(0, 2);
                return;
            end
            if size(cells_,2) >= 3
                cells = cells_(:,end-1:end);   % drop leading nPts col
            else
                cells = cells_;
            end
            cells = round(cells);
            validCells = all(isfinite(cells), 2) & all(cells >= 1, 2) & ...
                all(cells <= numel(rawToClean), 2);
            cells = cells(validCells, :);
            if isempty(cells), return; end
            cells = rawToClean(cells);
            cells = cells(all(cells >= 1, 2), :);
        end

        function [h, Pline] = drawInterpolatedLine(obj, segIdx, localStep, Snode, clim_)
            h = gobjects(0);
            Pline = zeros(0,3);
            [pts, disp_, cells] = obj.getInterpSlice(segIdx, localStep);
            if isempty(pts) || isempty(cells), return; end

            scale = obj.resolveDeformScale(segIdx, localStep);
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
                            obj.getRespDofs(segIdx, obj.Opts.field.type));
                        mode = lower(char(string(obj.Opts.color.climMode)));
                        if ismember(mode, {'step','local','current'})
                            clim_ = obj.localClim(sval);
                        end
                    else
                        Pnode = obj.getNodeCoords(segIdx, localStep);
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

        function [Pdef, U3, scale] = getDeformedCoords(obj, P, segIdx, localStep)
            if obj.Opts.deform.show
                U     = obj.getRespSlice(segIdx, obj.Opts.deform.type, localStep);
                U3    = obj.extractXYZ(U);
                % Replace NaN displacement with zero so Pdef stays finite.
                U3(~isfinite(U3)) = 0;
                scale = obj.resolveDeformScale(segIdx, localStep);
                % Match column count: P may be Nx2 for 2-D models.
                nCol = size(P, 2);
                Pdef = P + scale * U3(:, 1:nCol);
            else
                U3    = zeros(size(P,1), 3);
                scale = 0;
                Pdef  = P;
            end
        end

        function scale = resolveDeformScale(obj, segIdx, localStep)
            if obj.Opts.deform.autoScale
                scale = obj.currentDeformScale(segIdx, localStep);
            else
                scale = obj.Opts.deform.scale;
            end
        end

        function scale = currentDeformScale(obj, segIdx, localStep)
            baseScale = obj.Opts.deform.scale;
            if ~obj.Opts.deform.autoScale, scale = baseScale; return; end

            P = obj.getNodeCoords(segIdx, localStep);
            modelSize = obj.computeModelLength(P);
            umax = obj.getStepPeakMagnitude(segIdx, localStep, obj.Opts.deform.type);

            if ~isfinite(modelSize) || modelSize <= 0, modelSize = 1; end
            if ~isfinite(umax) || umax <= 0
                scale = baseScale;
            else
                scale = baseScale * modelSize / (10 * umax);
            end
        end

        function [S, clim_] = getScalarField(obj, segIdx, localStep)
            if obj.Opts.field.show && obj.Opts.color.useColormap
                Uf    = obj.getRespSlice(segIdx, obj.Opts.field.type, localStep);
                S     = obj.computeScalarField(segIdx, Uf);
                clim_ = obj.resolveClim(S);
            else
                S = [];  clim_ = [];
            end
        end

        % =================================================================
        % Topology access
        % =================================================================

        function P = getNodeCoords(obj, segIdx, localStep)
            [P, ~] = obj.getNodeStepData(segIdx, localStep);
        end

        function lines = getLineConn(obj, segIdx)
            % Topology is fixed within a segment — no step dimension.
            % Cell format: [nPts, idx1, idx2, ...] where idx are 1-based
            % row indices into the node coordinate array.
            lines = zeros(0, 2);
            fam   = obj.getFamilies(segIdx);
            if ~isfield(fam,'Line') || ~isfield(fam.Line,'Cells') || ...
               isempty(fam.Line.Cells), return; end
            C = double(fam.Line.Cells);
            if ~isempty(C)
                C = C(~all(isnan(C), 2), :);
            end
            % Cell format: [nPts, idx1, idx2, ...] — same as PlotEigen.
            % Extract connectivity using vtkLineCellsToConn style.
            C = double(C);
            if size(C,2) >= 3
                lines = C(:, 2:3);
            elseif size(C,2) == 2
                lines = C;
            else, return;
            end
            lines = round(lines);
            nPdef = size(obj.getNodeCoordsRaw(segIdx), 1);
            valid = all(isfinite(lines),2) & all(lines>=1,2) & all(lines<=nPdef,2);
            lines = lines(valid, :);
        end

        function fam = getFamilies(obj, segIdx)
            fam = struct();
            mi  = obj.ModelInfo(segIdx);
            if ~isfield(mi,'Elements'), return; end
            E = mi.Elements;
            if isfield(E,'Families'), fam = E.Families;
            else,                     fam = E;            end
        end

        % =================================================================
        % Response data access  (segIdx + localStep replace old stepIdx)
        % =================================================================

        function U = getRespSlice(obj, segIdx, fieldType, localStep)
            % Supports layouts A / B / C (same as before) but within the
            % chosen segment.  localStep is 1-based.
            fieldType = obj.normalizeFieldType(segIdx, fieldType);
            [Pmodel, modelTags] = obj.getNodeStepData(segIdx, localStep);
            nModel = size(Pmodel, 1);
            U = NaN(nModel, 6);

            nr = obj.NodalResp(segIdx);
            if ~isfield(nr, fieldType), return; end
            entry = nr.(fieldType);

            si = localStep;
            if isstruct(entry) && isfield(entry, 'data')
                % Layout B
                arr = entry.data;
                if isempty(arr) || ndims(arr) < 3, return; end
                si   = min(si, size(arr, 1));
                Uraw = double(reshape(arr(si,:,:), size(arr,2), size(arr,3)));
            elseif isstruct(entry)
                % Layout C: per-DOF struct — use canonical DOF order so
                % column 1=ux, 2=uy, 3=uz, 4=rx, 5=ry, 6=rz.
                dofFields = obj.getRespDofs(segIdx, fieldType);
                if isempty(dofFields), return; end
                firstArr = [];
                for dfi_ = 1:numel(dofFields)
                    if isfield(entry, dofFields{dfi_})
                        firstArr = entry.(dofFields{dfi_});  break;
                    end
                end
                if isempty(firstArr) || ~isnumeric(firstArr), return; end
                si   = min(si, size(firstArr, 1));
                nRow = size(firstArr, 2);
                nDof = numel(dofFields);
                Uraw = zeros(nRow, nDof, 'double');
                for di = 1:nDof
                    fn_ = dofFields{di};
                    if isfield(entry, fn_)
                        dArr = entry.(fn_);
                        if isnumeric(dArr) && size(dArr,1) >= si
                            Uraw(:, di) = double(dArr(si, :)).';
                        end
                    end
                end
            else
                % Layout A: raw 3-D array
                arr = entry;
                if isempty(arr) || ndims(arr) < 3, return; end
                si   = min(si, size(arr, 1));
                Uraw = double(reshape(arr(si,:,:), size(arr,2), size(arr,3)));
            end

            respTags = obj.getRespNodeTags(segIdx, fieldType);
            ncol = min(size(Uraw, 2), 6);

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
                respRows = obj.respTagsToRows(segIdx, double(modelTags(:)), respTags, fieldType);
                valid = respRows > 0 & respRows <= size(Uraw,1);
                U(valid, 1:ncol) = Uraw(respRows(valid), 1:ncol);
                return;
            end

            % Legacy path — no tag mapping
            Praw     = obj.getNodeCoordsRaw(segIdx);
            keepMask = obj.getNodeStepMask(segIdx, Praw);
            if size(Uraw,1) == size(Praw,1)
                Uraw  = Uraw(keepMask, :);
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

        function [arr, mp] = buildSegRespTagLookup(obj, segIdx)
            arr = [];  mp = [];
            nr  = obj.NodalResp(segIdx);
            if ~isfield(nr,'nodeTags') || isempty(nr.nodeTags), return; end
            tags = double(nr.nodeTags(:));
            tags = tags(isfinite(tags));
            if isempty(tags), return; end
            n    = numel(tags);
            maxT = max(tags, [], 'omitnan');
            if isfinite(maxT) && maxT >= 1 && maxT <= max(20*n, 1e6)
                arr       = zeros(maxT, 1);
                arr(tags) = 1:n;
            else
                mp = containers.Map(num2cell(tags), num2cell(1:n));
            end
        end

        function rows = respTagsToRows(obj, segIdx, modelTags, respTags, fieldType)
            rows = zeros(numel(modelTags), 1);
            arr  = obj.RespTagToIdx{segIdx};
            mp   = obj.RespTagToIdxMap{segIdx};
            useCached = obj.shouldUseCachedRespLookup(segIdx, fieldType, respTags);

            if useCached && ~isempty(arr)
                valid       = modelTags >= 1 & modelTags <= numel(arr) & isfinite(modelTags);
                rows(valid) = arr(modelTags(valid));
                return;
            end
            if useCached && ~isempty(mp)
                keys   = num2cell(modelTags);
                exists = isKey(mp, keys);
                if any(exists)
                    rows(exists) = cell2mat(values(mp, keys(exists)));
                end
                return;
            end
            if isempty(respTags), return; end
            [tf, loc] = ismember(modelTags(:), respTags(:));
            rows(tf)  = loc(tf);
        end

        function tf = shouldUseCachedRespLookup(obj, segIdx, fieldType, respTags)
            tf = false;
            if isempty(respTags) || isempty(fieldType), return; end
            nr = obj.NodalResp(segIdx);
            if ~isfield(nr, fieldType), return; end
            if ~isfield(nr,'nodeTags') || ~isvector(nr.nodeTags), return; end
            baseTags = double(nr.nodeTags(:));
            tf = numel(respTags) == numel(baseTags) && all(respTags(:) == baseTags);
        end

        function P = getNodeCoordsRaw(obj, segIdx)
            P  = zeros(0, 3);
            mi = obj.ModelInfo(segIdx);
            if ~isfield(mi,'Nodes') || ~isfield(mi.Nodes,'Coords'), return; end
            C = double(mi.Nodes.Coords);
            if isempty(C), return; end
            % No time dimension in per-segment modelInfo
            P = C;
            if size(P,2) < 3,     P(:,3) = 0;
            elseif size(P,2) > 3, P = P(:,1:3); end
        end

        function [P, tags] = getNodeStepData(obj, segIdx, ~)
            % localStep unused: node coordinates are step-invariant per segment.
            P    = obj.getNodeCoordsRaw(segIdx);
            tags = obj.getModelNodeTagsRaw(segIdx, size(P,1));
            if isempty(P), tags = zeros(0,1); return; end
            [keepMask, ~] = obj.getNodeStepSelection(segIdx, P, tags);
            P = P(keepMask,:);
            if ~isempty(tags)
                tags = obj.trimVectorLength(tags, numel(keepMask));
                tags = tags(keepMask(1:numel(tags)));
            end
        end

        function [keepMask, rawToClean, tagToClean] = getNodeStepSelection(obj, segIdx, P, tags)
            if nargin < 3 || isempty(P)
                P = obj.getNodeCoordsRaw(segIdx);
            end
            if nargin < 4 || isempty(tags)
                tags = obj.getModelNodeTagsRaw(segIdx, size(P,1));
            end
            keepMask   = obj.getNodeStepMask(segIdx, P, tags);
            rawToClean = zeros(size(keepMask));
            rawToClean(keepMask) = 1:nnz(keepMask);

            % tagToClean: node tag -> clean row index
            % Used by drawUnstructured / getLineConn / drawFixed when
            % topology cells store node tags rather than row indices.
            tagToClean = [];
            if ~isempty(tags)
                t      = double(obj.trimVectorLength(tags, numel(keepMask)));
                validT = isfinite(t) & t >= 1;
                if any(validT)
                    maxT = max(t(validT));
                    n_   = numel(t);
                    if isfinite(maxT) && maxT <= max(20*n_, 1e6)
                        tagToClean = zeros(maxT, 1);
                        for k = 1:n_
                            if validT(k) && k <= numel(rawToClean) && rawToClean(k) > 0
                                tagToClean(t(k)) = rawToClean(k);
                            end
                        end
                    end
                end
            end
        end

        function valid = getNodeStepMask(obj, segIdx, P, tags)
            if nargin < 3 || isempty(P)
                P = obj.getNodeCoordsRaw(segIdx);
            end
            if nargin < 4 || isempty(tags)
                tags = obj.getModelNodeTagsRaw(segIdx, size(P,1));
            end
            if isempty(P), valid = false(0,1); return; end
            valid = ~all(isnan(P), 2);
            unusedTags = obj.getUnusedNodeTags(segIdx);
            if ~isempty(unusedTags) && ~isempty(tags)
                tags = tags(:);
                nUse = min(numel(tags), numel(valid));
                valid(1:nUse) = valid(1:nUse) & ~ismember(tags(1:nUse), unusedTags(:));
            end
        end

        function tags = getModelNodeTagsRaw(obj, segIdx, nRow)
            if nargin < 3, nRow = []; end
            tags = [];
            mi   = obj.ModelInfo(segIdx);
            if ~isfield(mi,'Nodes') || ~isfield(mi.Nodes,'Tags') || ...
               isempty(mi.Nodes.Tags), return; end
            tags = double(mi.Nodes.Tags(:));   % no step dim in per-segment modelInfo
            if ~isempty(nRow)
                tags = obj.trimVectorLength(tags, nRow);
            end
        end

        function tags = getUnusedNodeTags(obj, segIdx)
            tags = [];
            mi   = obj.ModelInfo(segIdx);
            if ~isfield(mi,'Nodes') || ~isfield(mi.Nodes,'UnusedTags') || ...
               isempty(mi.Nodes.UnusedTags), return; end
            tags = double(mi.Nodes.UnusedTags(:));
            tags = unique(tags(isfinite(tags)));
        end

        function ndm = getModelNdm(obj, segIdx)
            % Return Nodes.Ndm vector if present, else empty.
            ndm = [];
            mi  = obj.ModelInfo(segIdx);
            if ~isfield(mi,'Nodes') || ~isfield(mi.Nodes,'Ndm') || ...
               isempty(mi.Nodes.Ndm), return; end
            ndm = double(mi.Nodes.Ndm(:));
        end

        function tags = getRespNodeTags(obj, segIdx, fieldType)
            tags = [];
            fieldType = obj.normalizeFieldType(segIdx, fieldType);
            nr    = obj.NodalResp(segIdx);
            if ~isfield(nr, fieldType), return; end
            entry = nr.(fieldType);
            if isfield(nr, 'nodeTags') && ~isempty(nr.nodeTags)
                raw = nr.nodeTags;
            elseif isstruct(entry) && isfield(entry, 'nodeTags') && ~isempty(entry.nodeTags)
                raw = entry.nodeTags;
            else
                return;
            end
            tags = double(raw(:));
            tags = tags(isfinite(tags));
        end

        % =================================================================
        % Scalar field
        % =================================================================

        function S = computeScalarField(obj, segIdx, U)
            S = obj.computeScalarFieldWithComp(U, obj.Opts.field.component, ...
                obj.getRespDofs(segIdx, obj.Opts.field.type));
        end

        function dofs = getRespDofs(obj, segIdx, fieldType)
            % Return DOF labels in canonical physical order.
            % Layout C stores per-DOF arrays as struct fields; MATLAB's
            % fieldnames() sorts alphabetically (rx < ux), which would
            % misalign translation/rotation columns.  Re-order to the
            % standard OpenSees sequence: ux uy uz rx ry rz.
            dofs = {};
            fieldType = obj.normalizeFieldType(segIdx, fieldType);
            nr    = obj.NodalResp(segIdx);
            if ~isfield(nr, fieldType), return; end
            entry = nr.(fieldType);
            if ~isstruct(entry), return; end
            if isfield(entry, 'dofs')
                dofs = entry.dofs;          % Layout B: explicit label list
            elseif ~isfield(entry, 'data')
                % Layout C: sort to canonical sequence.
                canonical = {'ux','uy','uz','rx','ry','rz'};
                present   = fieldnames(entry).';
                ordered   = [canonical(ismember(canonical, present)), ...
                             present(~ismember(present, canonical))];
                dofs = ordered;
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
                    col = 0;
                    for d = 1:numel(dofs)
                        if strcmpi(dofs{d}, comp), col = d; break; end
                    end
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
            if isempty(U), valid = false(0,1); return; end
            valid = any(isfinite(U), 2) & ~all(isnan(U), 2);
        end

        function umax = getStepPeakMagnitude(obj, segIdx, localStep, fieldType)
            umax = obj.peakVectorMagnitude(obj.getRespSlice(segIdx, fieldType, localStep));
            if obj.shouldUseInterpDisp(segIdx, localStep, fieldType)
                [~, disp_, ~] = obj.getInterpSlice(segIdx, localStep);
                umax = max(umax, obj.peakVectorMagnitude(disp_));
            end
        end

        function mag = peakVectorMagnitude(obj, U)
            U3    = obj.extractXYZ(U);
            valid = obj.getValidRespRows(U3);
            if ~any(valid), mag = 0; return; end
            mag = max(sqrt(sum(U3(valid,:).^2, 2, 'omitnan')), [], 'omitnan');
            if ~isfinite(mag), mag = 0; end
        end

        function S = getStepScalarValues(obj, segIdx, localStep, fieldType, component, useInterp)
            if nargin < 6, useInterp = true; end
            if useInterp && obj.shouldUseInterpDisp(segIdx, localStep, fieldType)
                [~, disp_, ~] = obj.getInterpSlice(segIdx, localStep);
                S = obj.computeScalarFieldWithComp(disp_, component, ...
                    obj.getRespDofs(segIdx, fieldType));
                S = S(isfinite(S));
                return;
            end
            U = obj.getRespSlice(segIdx, fieldType, localStep);
            S = obj.computeScalarFieldWithComp(U, component, ...
                obj.getRespDofs(segIdx, fieldType));
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

        function tf = shouldUseInterpDisp(obj, segIdx, localStep, fieldType)
            tf = strcmpi(fieldType, 'disp') && ...
                 obj.Opts.line.show && ...
                 obj.Opts.interp.useInterpolation && ...
                 obj.hasInterpData(segIdx, localStep);
        end

        function vals = initStepSelectorValues(~, key, n)
            switch key
                case {'absmax','max'}, vals = -inf(n, 1);
                case {'absmin','min'}, vals =  inf(n, 1);
                otherwise,            vals =  NaN(n, 1);
            end
        end

        function clim_ = resolveClim(obj, S)
            if ~isempty(obj.Opts.color.clim), clim_ = obj.Opts.color.clim; return; end
            mode = lower(char(string(obj.Opts.color.climMode)));
            switch mode
                case 'absmax', [a,b] = obj.globalClim(); clim_ = [0, max(abs(a),abs(b))];
                case 'absmin', [a,b] = obj.globalClim(); clim_ = [0, min(abs(a),abs(b))];
                case 'range',  [a,b] = obj.globalClim(); clim_ = [a, b];
                otherwise,     clim_ = obj.localClim(S);
            end
        end

        function clim_ = localClim(~, S)
            Sf = S(isfinite(S));
            if isempty(Sf), clim_ = [0 1]; return; end
            clim_ = [min(Sf,[],  'omitnan'), max(Sf,[], 'omitnan')];
            if clim_(1) == clim_(2), clim_(2) = clim_(1) + 1; end
        end

        function fieldType = normalizeFieldType(obj, segIdx, fieldType)
            fieldType = char(fieldType);
            nr = obj.NodalResp(segIdx);
            if isfield(nr, fieldType), return; end
            fn    = fieldnames(nr);
            match = fn(strcmpi(fn, fieldType));
            if ~isempty(match), fieldType = match{1}; end
        end

        function key = normalizeStepSelector(~, stepIdx)
            key = lower(strtrim(char(string(stepIdx))));
            switch key
                case 'stepmax',    key = 'max';
                case 'stepmin',    key = 'min';
                case 'stepabsmax', key = 'absmax';
                case 'stepabsmin', key = 'absmin';
            end
        end

        % =================================================================
        % Drawing primitives  (same API; segIdx replaces old stepIdx)
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

        function h = drawUnstructured(obj, Pdef, segIdx, S, clim_, asUndeformed)
            % NOTE: Pdef has rows corresponding to CLEAN (kept) nodes only.
            % Cells reference the RAW node coordinate array (full 1-based
            % indices into getNodeCoordsRaw).  We must use the raw coord
            % array for triangulation; deformed positions are composed by
            % expanding Pdef back to raw size via keepMask.
            h = gobjects(0);
            if ~obj.Opts.surf.show || isempty(Pdef), return; end
            fam = obj.getFamilies(segIdx);
            if ~isfield(fam,'Unstructured'), return; end
            U0 = fam.Unstructured;
            if ~isfield(U0,'Cells')     || isempty(U0.Cells),     return; end
            if ~isfield(U0,'CellTypes') || isempty(U0.CellTypes), return; end

            cells = double(U0.Cells);
            types = double(U0.CellTypes);

            % modelInfo has no time dimension — only squeeze if genuinely 3-D.
            if ndims(cells) == 3
                cells = squeeze(cells(1,:,:));
            end
            % types is [nCell x 1] — ensure column vector, never squeeze.
            types = types(:);

            % Align lengths
            nCell = min(size(cells,1), numel(types));
            cells = cells(1:nCell,:);
            types = types(1:nCell);

            % Keep row only if the ENTIRE row is NaN (row with some NaN
            % padding is still valid — nPts tells how many cols to use).
            keepRows = ~all(isnan(cells), 2);
            cells = cells(keepRows,:);
            types = types(keepRows);

            % Drop rows where cell type is invalid
            validCells = isfinite(types);
            cells = cells(validCells,:);
            types = types(validCells);
            if isempty(cells), return; end
            cells = double(cells);

            % Pdef and S are already aligned to the node coordinate array.
            % Cell indices are 1-based row indices into that array.
            PrawDef = Pdef;
            Sraw    = S;

            if ~isempty(Sraw)
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

        function h = drawFixed(obj, Pdef, segIdx)
            h = gobjects(0);
            if ~obj.Opts.fixed.show, return; end
            mi = obj.ModelInfo(segIdx);
            if ~isfield(mi,'Fixed') || ~isfield(mi.Fixed,'NodeIndex') || ...
               isempty(mi.Fixed.NodeIndex), return; end
            idx = double(mi.Fixed.NodeIndex(:));
            idx = double(idx(:));
            idx = idx(isfinite(idx));
            idx = round(idx);
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
        end

        function h = drawVectorField(obj, Pdef, segIdx, localStep)
            h = gobjects(0);
            U = obj.getRespSlice(segIdx, obj.Opts.vector.type, localStep);
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
            valid = all(isfinite(Pdef),2) & all(isfinite(V),2);
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

        function prepareAxes(obj, segIdx)
            obj.applyFigureSize();
            P   = obj.getNodeCoordsRaw(segIdx);
            ndm = obj.getModelNdm(segIdx);
            obj.CachedModelDim  = obj.computeModelDim(P, ndm);
            obj.CachedModelSize = obj.computeModelLength(P);
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
            if isempty(figSize), return; end
            fig = ancestor(obj.Ax, 'figure');
            if isempty(fig) || ~isgraphics(fig, 'figure'), return; end
            fig.Units = 'pixels';
            pos = fig.Position;
            figSize = double(figSize(:).');
            if numel(figSize) == 2,     pos(3:4) = figSize;
            elseif numel(figSize) == 4, pos = figSize;
            else
                error('PlotNodalResp:InvalidFigureSize', ...
                    'general.figureSize must be [width height] or [left bottom width height].');
            end
            fig.Position = pos;
        end

        function applyView(obj, segIdx)
            if nargin < 2, segIdx = 1; end
            P   = obj.getNodeCoordsRaw(segIdx);
            ndm = obj.getModelNdm(segIdx);
            dim = obj.computeModelDim(P, ndm);
            v = lower(char(string(obj.Opts.general.view)));
            if strcmp(v,'auto')
                if dim == 2, view(obj.Ax,2); else, view(obj.Ax,3); end
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
                    if dim == 2, view(obj.Ax,2); else, view(obj.Ax,3); end
            end
        end

        function applyTitle(obj, segIdx, localStep, globalStep)
            t = string(obj.Opts.general.title);
            if strcmpi(t,'auto')
                nr = obj.NodalResp(segIdx);
                if isfield(nr,'time') && numel(nr.time) >= localStep
                    time_ = nr.time(localStep);
                else
                    time_ = NaN;
                end
                title(obj.Ax, sprintf('%s  %s  |  step %d  |  t = %.4g s', ...
                    obj.Opts.field.type, obj.Opts.field.component, ...
                    globalStep, time_));
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
            titleText  = string(obj.getScalarTitle());
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
            Squery = zeros(size(queryPts,1), 1);
            if isempty(queryPts)||isempty(refPts)||isempty(refScalars), return; end
            validRef   = all(isfinite(refPts),2) & isfinite(refScalars(:));
            refPts     = refPts(validRef,:);
            refScalars = refScalars(validRef);
            if isempty(refPts), return; end
            nq = size(queryPts,1);  nr = size(refPts,1);
            if ~isempty(obj.KnnIdxCache) && ...
               obj.KnnRefPtCount == nr && obj.KnnQueryPtCount == nq
                idx = obj.KnnIdxCache;
            else
                idx = plotter.PlotNodalResp.nearestNeighbourKnn( ...
                    double(queryPts), double(refPts));
                obj.KnnIdxCache     = idx;
                obj.KnnRefPtCount   = nr;
                obj.KnnQueryPtCount = nq;
            end
            Squery = double(refScalars(idx));
        end

        % =================================================================
        % Geometry utilities
        % =================================================================

        function dim = computeModelDim(~, P, ~)
            % 2-D when all node z-coordinates are (numerically) zero.
            % This is more reliable than spread-based or Ndm-based tests:
            %   - A planar XY model always has z = 0 for every node.
            %   - Ndm can be 3 even for plane-stress / plane-frame models.
            if isempty(P) || size(P,2) < 3
                dim = 2;  return;
            end
            z = P(:,3);
            z = z(isfinite(z));
            if isempty(z) || all(abs(z) < 1e-10)
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
            L = max(ext,[],'omitnan');
            if ~isfinite(L) || L <= 0, L = 1; end
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
