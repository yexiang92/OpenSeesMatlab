classdef PlotFrameResp < handle
    % PlotFrameResp
    % Bending-moment / shear / axial-force diagram for frame elements.
    %
    % Data layouts
    % ------------
    % modelInfo / frameResp can each be:
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
    %
    % Response field layouts (per segment)
    % -------------------------------------
    %   Layout B: frameResp.<field>.data  [nStep x nEle x ...]
    %             frameResp.<field>.dofs  cell of label strings
    %   Layout C: frameResp.<field>.<dof> [nStep x nEle x nSec]  (per-DOF)
    %             e.g. sectionForces.Mz   [2501 x 24 x 4]
    %
    % Supported response types
    % ------------------------
    %   sectionForces / sectionDeformations   Layout C: N Mz Vy My Vz T
    %   basicForces   / basicDeformations     Layout C: N Mz My T
    %   localForces   / plasticDeformation    Layout C
    %
    % Quick start
    % -----------
    %   pfr = plotter.PlotFrameResp(modelInfo, frameResp);
    %   pfr.plotStep('absmax');

    % =====================================================================
    properties
        ModelInfo               % scalar struct OR struct array (one per segment)
        FrameResp               % scalar struct OR struct array (one per segment)
        Plotter     plotter.PatchPlotter
        Ax          matlab.graphics.axis.Axes
        Opts        struct
        Handles     struct = struct()
    end

    properties (Access = private)
        % Segment bookkeeping
        SegCount        double = 1
        SegStepCounts   double = []
        SegOffsets      double = []

        CachedModelDim   double = 3
        CachedModelSize  double = 1

        GlobalClimCache  double = []
        GlobalClimField  char   = ''
        GlobalClimComp   char   = ''

        PeakCache        struct = struct('absmax',[],'absmin',[],'max',[],'min',[])
        DiagScaleCache   double = NaN
        DiagScaleStep    double = NaN   % NaN = global scale, number = per-step
        CurrentClimCache double = []
    end

    % =====================================================================
    methods (Static)

        function describeOptions()
            % Print a formatted description of all available options.
            % Call:  plotter.PlotFrameResp.describeOptions()
            fprintf('\n');
            fprintf('PlotFrameResp options (pass as struct to plotStep or constructor)\n');
            fprintf('=================================================================\n');
            fprintf('\n');
            fprintf('── Response selection ────────────────────────────────────────\n');
            fprintf('  respType   string  Response field name.\n');
            fprintf('             ''sectionForces'' | ''sectionDeformations''\n');
            fprintf('             ''basicForces''   | ''basicDeformations''\n');
            fprintf('             ''localForces''   | ''plasticDeformation''\n');
            fprintf('  component  string  DOF component to plot.\n');
            fprintf('             sectionForces/Deformations: ''N'' ''MZ'' ''VY'' ''MY'' ''VZ'' ''T''\n');
            fprintf('             basicForces/Deformations:   ''N'' ''MZ'' ''MY'' ''T''\n');
            fprintf('\n');
            fprintf('── Diagram style ─────────────────────────────────────────────\n');
            fprintf('  style      ''surface'' | ''wireframe''   Fill or outline only.\n');
            fprintf('  scale      double  Manual scale multiplier (default 1.0).\n');
            fprintf('  heightFrac double  Diagram height as fraction of model size\n');
            fprintf('                     at peak value (default 0.05 = 5%%).\n');
            fprintf('  scaleMode  ''current'' | ''global''\n');
            fprintf('             current = scale per step; global = fixed across all steps.\n');
            fprintf('\n');
            fprintf('── Color ─────────────────────────────────────────────────────\n');
            fprintf('  color.useColormap  logical  Color by value (true) or solid (false).\n');
            fprintf('  color.colormap     N×3      Colormap matrix (default jet(256)).\n');
            fprintf('  color.clim         [lo hi]  Fixed color limits; [] = auto.\n');
            fprintf('  color.climMode     ''current'' | ''global''\n');
            fprintf('  color.solidColor   color    Fill color when useColormap=false.\n');
            fprintf('  color.faceAlpha    double   Surface opacity 0–1 (default 1.0).\n');
            fprintf('  color.wireColor    color    Wireframe color.\n');
            fprintf('  color.wireWidth    double   Wireframe line width.\n');
            fprintf('  color.modelColor   color    Beam model line color.\n');
            fprintf('  color.modelWidth   double   Beam model line width.\n');
            fprintf('\n');
            fprintf('── Visibility ────────────────────────────────────────────────\n');
            fprintf('  showModel      logical  Draw beam centreline (default true).\n');
            fprintf('  showBeamModel  logical  Draw beam connectivity (default true).\n');
            fprintf('  showZeroLine   logical  Draw zero-value baseline (default true).\n');
            fprintf('  surf.show      logical  Draw unstructured mesh wireframe.\n');
            fprintf('\n');
            fprintf('── Labels ────────────────────────────────────────────────────\n');
            fprintf('  showMaxMinLabel  ''global'' | ''element'' | ''all'' | ''none''\n');
            fprintf('                   Which extreme values to annotate.\n');
            fprintf('  labelFontSize    double   Label font size (default 9).\n');
            fprintf('  labelGap         double   Extra gap beyond tip as fraction of\n');
            fprintf('                   diagram height (default 0.1 = 10%% extra).\n');
            fprintf('                   0 = label at tip; 0.5 = half diagram height beyond.\n');
            fprintf('\n');
            fprintf('── Layout ────────────────────────────────────────────────────\n');
            fprintf('  general.view      ''auto''|''xy''|''xz''|''iso''  Camera view.\n');
            fprintf('  general.padRatio  double  Axis padding fraction (default 0.25).\n');
            fprintf('  general.figureSize [w h]  Figure size in pixels.\n');
            fprintf('  general.title     ''auto'' | string  Plot title.\n');
            fprintf('\n');
            fprintf('── Performance ───────────────────────────────────────────────\n');
            fprintf('  performance.fastMode            logical  Skip slow extras.\n');
            fprintf('  performance.maxElementLabels    int     Max elements labelled.\n');
            fprintf('  performance.maxSectionsPerElement int   Max section points drawn.\n');
            fprintf('\n');
            fprintf('── Colorbar ──────────────────────────────────────────────────\n');
            fprintf('  cbar.show   logical  Show colorbar (default true).\n');
            fprintf('  cbar.label  string   Extra colorbar label suffix.\n');
            fprintf('\n');
            fprintf('Example:\n');
            fprintf('  opts = plotter.PlotFrameResp.defaultOptions();\n');
            fprintf('  opts.component  = ''VY'';\n');
            fprintf('  opts.scaleMode  = ''global'';\n');
            fprintf('  opts.labelGap   = 0.2;\n');
            fprintf('  pfr.plotStep(''absmax'', opts);\n');
            fprintf('\n');
        end

        function opts = defaultOptions()
            opts.general = struct( ...
                'clearAxes',true, 'holdOn',true, 'axisEqual',true, ...
                'grid',true, 'box',false, 'view','auto', ...
                'title','auto', 'padRatio',0.25, 'figureSize',[1000,618]);

            opts.respType   = 'sectionForces';
            opts.component  = 'MZ';
            opts.style      = 'surface';   % 'surface' | 'wireframe'
            opts.scale      = 1.0;
            opts.heightFrac = 0.05;
            opts.scaleMode  = 'current';   % 'current' | 'global'

            opts.color = struct( ...
                'useColormap',true, 'colormap',jet(256), 'clim',[], ...
                'climMode','current', ...
                'solidColor','blue', 'faceAlpha',1.0, ...
                'wireColor','blue', 'wireWidth',2.0, ...
                'zeroLineColor','black', 'zeroLineWidth',0.7, ...
                'modelColor','black', 'modelWidth',1.0);

            opts.showModel     = true;
            opts.showBeamModel = true;
            opts.showZeroLine  = true;

            opts.surf = struct('show',true, 'lineColor','#d8dcd6', 'lineWidth',1.0);

            opts.performance = struct( ...
                'fastMode',false, ...
                'maxElementLabels',200, ...
                'maxSectionsPerElement',24);

            opts.showMaxMinLabel = 'global';
            opts.labelFontSize   = 9;
            opts.labelGap        = 0.1;   % extra fraction beyond tip (0 = at tip, 0.1 = 10% beyond)

            opts.cbar = struct('show',true, 'label','');

            opts.help = strjoin({
                '====== PlotFrameResp Options ======================================'
                ''
                '-- Response selection -------------------------------------------'
                '  respType    string   Response field name.'
                '               ''sectionForces'' | ''sectionDeformations'''
                '               ''basicForces''   | ''basicDeformations'''
                '               ''localForces''   | ''plasticDeformation'''
                '  component   string   DOF component to plot.'
                '               sectionForces/Deformations : N  MZ  VY  MY  VZ  T'
                '               basicForces/Deformations   : N  MZ  MY  T'
                ''
                '-- Diagram style ------------------------------------------------'
                '  style       ''surface'' | ''wireframe''   Fill or outline only.'
                '  scale       double   Manual scale multiplier (default 1.0).'
                '  heightFrac  double   Diagram height as fraction of model size'
                '                       at peak value (default 0.05 = 5%).'
                '  scaleMode   ''current'' | ''global'''
                '               current = rescale each step; global = fixed scale.'
                ''
                '-- Color --------------------------------------------------------'
                '  color.useColormap   logical  Color by value (default true).'
                '  color.colormap      N×3      Colormap matrix (default jet(256)).'
                '  color.clim          [lo hi]  Fixed color limits; [] = auto.'
                '  color.climMode      ''current'' | ''global'''
                '  color.solidColor    color    Fill color when useColormap=false.'
                '  color.faceAlpha     double   Surface opacity 0-1 (default 1.0).'
                '  color.wireColor     color    Wireframe color.'
                '  color.wireWidth     double   Wireframe line width.'
                '  color.modelColor    color    Beam centreline color.'
                '  color.modelWidth    double   Beam centreline line width.'
                ''
                '-- Visibility ---------------------------------------------------'
                '  showModel      logical  Draw beam centreline (default true).'
                '  showBeamModel  logical  Draw beam connectivity (default true).'
                '  showZeroLine   logical  Draw zero-value baseline (default true).'
                '  surf.show      logical  Draw unstructured mesh wireframe.'
                '  surf.lineColor color   Wireframe edge colour.'
                '  surf.lineWidth  double  Wireframe edge width.'
                ''
                '-- Labels -------------------------------------------------------'
                '  showMaxMinLabel  ''global'' | ''element'' | ''all'' | ''none'''
                '                   Which extreme values to annotate.'
                '  labelFontSize    double   Label font size (default 9).'
                '  labelGap         double   Extra gap beyond tip as fraction of'
                '                   diagram height at that point (default 0.1).'
                '                   0 = label at tip; 0.2 = 20% beyond tip.'
                ''
                '-- Layout -------------------------------------------------------'
                '  general.view       ''auto''|''xy''|''xz''|''iso''  Camera view.'
                '  general.padRatio   double   Axis padding fraction (default 0.25).'
                '  general.figureSize [w h]    Figure size in pixels.'
                '  general.title      ''auto'' | string   Plot title.'
                '  general.clearAxes  logical  Clear axes before each plot.'
                '  general.axisEqual  logical  Equal axis scaling.'
                '  general.grid       logical  Show grid.'
                ''
                '-- Performance --------------------------------------------------'
                '  performance.fastMode              logical  Skip slow extras.'
                '  performance.maxElementLabels      int   Max labelled elements.'
                '  performance.maxSectionsPerElement int   Max section pts drawn.'
                ''
                '-- Colorbar -----------------------------------------------------'
                '  cbar.show   logical  Show colorbar (default true).'
                '  cbar.label  string   Extra suffix appended to colorbar label.'
                ''
                '== Example ======================================================'
                '  opts = plotter.PlotFrameResp.defaultOptions();'
                '  disp(opts.help)          % print this help'
                '  opts.component  = ''VY'';'
                '  opts.scaleMode  = ''global'';'
                '  opts.labelGap   = 0.2;'
                '  opts.color.climMode = ''global'';'
                '  pfr.plotStep(''absmax'', opts);'
                '=================================================================='
                }, newline);
        end
    end

    % =====================================================================
    methods

        function obj = PlotFrameResp(modelInfo, frameResp, ax, opts)
            if nargin < 3, ax   = []; end
            if nargin < 4, opts = []; end

            obj.ModelInfo = modelInfo;
            obj.FrameResp = frameResp;
            obj.Opts      = obj.merge(plotter.PlotFrameResp.defaultOptions(), opts);
            obj.Plotter   = plotter.PatchPlotter(ax);
            obj.Ax        = obj.Plotter.Ax;

            obj.buildSegmentIndex();

            P = obj.nodeCoords(1, 1);
            obj.CachedModelDim  = obj.modelDim(1, P);
            obj.CachedModelSize = obj.modelSize(P);
        end

        function ax = getAxes(obj), ax = obj.Ax; end

        function setOptions(obj, opts)
            prev  = [char(string(obj.Opts.respType)),'|',char(string(obj.Opts.component))];
            prevSM = char(string(obj.Opts.scaleMode));
            obj.Opts = obj.merge(obj.Opts, opts);
            now   = [char(string(obj.Opts.respType)),'|',char(string(obj.Opts.component))];
            nowSM  = char(string(obj.Opts.scaleMode));
            if ~strcmp(prev,now) || ~strcmp(prevSM,nowSM)
                obj.GlobalClimCache  = [];
                obj.CurrentClimCache = [];
                obj.PeakCache        = struct('absmax',[],'absmin',[],'max',[],'min',[]);
                obj.DiagScaleCache   = NaN;
                obj.DiagScaleStep    = NaN;
            end
        end

        function h = plotStep(obj, globalStepArg, opts)
            if nargin >= 3 && ~isempty(opts), obj.setOptions(opts); end
            globalStep = obj.resolveGlobalStepArg(globalStepArg);
            [segIdx, localStep] = obj.resolveGlobalStep(globalStep);
            obj.CurrentClimCache = [];
            obj.prepAxes(segIdx);
            obj.Handles = struct();
            obj.render(segIdx, localStep, globalStep);
            h = obj.Handles;
        end

        function n = nSteps(obj)
            n = sum(obj.SegStepCounts);
        end

        function [cmin, cmax] = globalClim(obj)
            if ~isempty(obj.Opts.color.clim) && numel(obj.Opts.color.clim) == 2
                cmin = obj.Opts.color.clim(1);  cmax = obj.Opts.color.clim(2);  return;
            end
            if ~isempty(obj.GlobalClimCache) && ...
               strcmp(obj.GlobalClimField, char(string(obj.Opts.respType))) && ...
               strcmp(obj.GlobalClimComp,  char(string(obj.Opts.component)))
                cmin = obj.GlobalClimCache(1);  cmax = obj.GlobalClimCache(2);  return;
            end
            allV = [];
            for g = 0:obj.nSteps()-1
                [si, ls] = obj.resolveGlobalStep(g);
                v = obj.respFlat(si, ls);
                allV = [allV; v(isfinite(v))]; %#ok<AGROW>
            end
            if isempty(allV), allV = [0;1]; end
            a = min(allV);  b = max(allV);
            if a == b, b = a + 1; end
            obj.GlobalClimCache = [a b];
            obj.GlobalClimField = char(string(obj.Opts.respType));
            obj.GlobalClimComp  = char(string(obj.Opts.component));
            cmin = a;  cmax = b;
        end

    end

    % =====================================================================
    methods (Access = private)

        % =================================================================
        % Segment index
        % =================================================================

        function buildSegmentIndex(obj)
            obj.SegCount = numel(obj.FrameResp);
            obj.SegStepCounts = zeros(1, obj.SegCount);
            for s = 1:obj.SegCount
                obj.SegStepCounts(s) = obj.countSegSteps(s);
            end
            obj.SegOffsets = [0, cumsum(obj.SegStepCounts(1:end-1))];
        end

        function n = countSegSteps(obj, segIdx)
            fr = obj.FrameResp(segIdx);
            if isfield(fr,'time') && ~isempty(fr.time)
                n = numel(fr.time);  return;
            end
            preferDofs = {'N','Mz','Vy','My','Vz','T', ...
                          'n','mz','vy','my','vz','t', ...
                          'FX','FY','FZ','MX','MY','MZ'};
            n = 0;
            for fn = fieldnames(fr).'
                A = fr.(fn{1});
                if isstruct(A)
                    if isfield(A,'data')
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
                    n = size(A,1);  return;
                end
            end
        end

        % =================================================================
        % Global step resolution
        % =================================================================

        function [segIdx, localStep] = resolveGlobalStep(obj, globalStep)
            % globalStep: 0-based.  Returns segIdx (1-based) and localStep (1-based).
            if globalStep < 0 || globalStep >= obj.nSteps()
                error('PlotFrameResp:InvalidStep', ...
                    'globalStep %d out of range [0, %d].', globalStep, obj.nSteps()-1);
            end
            segIdx    = find(obj.SegOffsets + obj.SegStepCounts > globalStep, 1, 'first');
            localStep = globalStep - obj.SegOffsets(segIdx) + 1;  % 1-based
        end

        function globalStep = resolveGlobalStepArg(obj, arg)
            if isnumeric(arg)
                globalStep = round(arg);  % user passes 0-based
                return;
            end
            key = obj.normalizeStepSelector(arg);
            % Try fast path first (avoids per-step loop for static topology)
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
                    error('PlotFrameResp:BadStep', ...
                        'Unknown selector "%s".', key);
            end
            if isempty(idx) || ~isfinite(idx), idx = 1; end
            globalStep = idx - 1;  % back to 0-based
        end

        % =================================================================
        % Render
        % =================================================================

        function render(obj, segIdx, localStep, globalStep)
            P    = obj.nodeCoords(segIdx, localStep);
            info = obj.beamInfo(segIdx, localStep);
            basePts = zeros(0,3);  tipPts = zeros(0,3);  % init for applyDataLimits

            if obj.Opts.showModel
                if obj.Opts.showBeamModel && ~isempty(info.conn)
                    obj.drawModelLines(P, info.conn);
                end
                if obj.Opts.surf.show && ~obj.Opts.performance.fastMode
                    try
                        obj.drawUnstructuredWireframe(P, segIdx);
                    catch ME
                        warning('PlotFrameResp:WireframeFailed','%s', ME.message);
                    end
                end
            end

            if ~isempty(info.conn)
                sc = obj.diagScale(segIdx, localStep);
                [basePts, tipPts, vals, eleStart, eleEnd] = ...
                    obj.buildDiagram(P, info, segIdx, localStep, sc);

                if ~isempty(basePts)
                    if strcmpi(obj.Opts.style,'surface')
                        obj.drawSurface(basePts, tipPts, vals, eleStart, eleEnd);
                    else
                        obj.drawWireframe(basePts, tipPts, vals, eleStart, eleEnd);
                    end
                end

                if obj.Opts.showZeroLine && ~isempty(basePts)
                    obj.drawZeroLines(eleStart, eleEnd);
                end

                if obj.shouldAnnotate(numel(eleStart)) && ~isempty(vals)
                    obj.annotate(basePts, tipPts, vals, eleStart, eleEnd, info);
                end
            end

            obj.applyColorbar();
            obj.applyTitle(segIdx, localStep, globalStep);
            obj.applyView(segIdx);
            % Include diagram tip points in data limits so the bending-moment
            % surface is fully visible (tipPts may extend into Z for 2-D frames).
            if ~isempty(basePts) && ~isempty(tipPts)
                allPts = [P; basePts; tipPts];
            else
                allPts = P;
            end
            allPts = allPts(all(isfinite(allPts),2),:);
            if isempty(allPts), allPts = P; end
            obj.Plotter.applyDataLimits(allPts, obj.Opts.general.padRatio);
        end

        % =================================================================
        % Unstructured wireframe (topology fixed per segment)
        % =================================================================

        function drawUnstructuredWireframe(obj, P, segIdx)
            fam = obj.families(segIdx);
            if ~isfield(fam,'Unstructured'), return; end
            U = fam.Unstructured;
            if ~isfield(U,'Cells')||isempty(U.Cells), return; end
            if ~isfield(U,'CellTypes')||isempty(U.CellTypes), return; end

            cells     = double(U.Cells);
            cellTypes = double(U.CellTypes);

            if isvector(cells), cells = reshape(cells,1,[]); end
            if ~ismatrix(cells), cells = reshape(cells,size(cells,1),[]); end
            cellTypes = cellTypes(:);
            if isempty(cells)||isempty(cellTypes), return; end

            keepRows = ~all(isnan(cells),2);
            cells    = cells(keepRows,:);
            if numel(cellTypes)==numel(keepRows), cellTypes=cellTypes(keepRows); end
            nCell = min(size(cells,1),numel(cellTypes));
            if nCell==0, return; end
            cells = cells(1:nCell,:);  cellTypes = cellTypes(1:nCell);

            keepRows2 = any(isfinite(cells),2);
            cells     = cells(keepRows2,:);  cellTypes = cellTypes(keepRows2);
            if isempty(cells), return; end

            [cells, ~, kRows] = obj.remapCellsToModelRows(cells, segIdx);
            if numel(cellTypes)==numel(kRows), cellTypes=cellTypes(kRows); end
            if isempty(cells), return; end

            surfOut = plotter.utils.VTKElementTriangulator.triangulate(P,cellTypes,cells);
            if isempty(surfOut)||~isfield(surfOut,'EdgePoints')||isempty(surfOut.EdgePoints)
                return;
            end
            s.points    = double(surfOut.EdgePoints);
            s.color     = obj.Opts.surf.lineColor;
            s.lineWidth = obj.Opts.surf.lineWidth;
            s.tag       = 'UnstructuredWireframe';
            obj.Handles.UnstructuredWireframe = obj.Plotter.addLine(s);
        end

        % =================================================================
        % Diagram geometry
        % =================================================================

        function [basePts, tipPts, vals, eleStart, eleEnd] = ...
                buildDiagram(obj, P, info, segIdx, localStep, sc)

            valPerEle = obj.respPerEle(segIdx, localStep);
            locPerEle = obj.secLocs(segIdx, localStep);
            nEle      = size(info.conn,1);

            nPerEle  = zeros(nEle,1);
            eleStart = zeros(nEle,1);
            eleEnd   = zeros(nEle,1);
            totalPts = 0;
            for e = 1:nEle
                v = valPerEle{e}(:);  s_ = locPerEle{e}(:);
                if isempty(v)||isempty(s_), continue; end
                idx = obj.sectionSampleIndex(min(numel(v),numel(s_)));
                nPerEle(e)  = numel(idx);
                totalPts    = totalPts + nPerEle(e);
            end

            basePts = zeros(totalPts,3);
            tipPts  = zeros(totalPts,3);
            vals    = zeros(totalPts,1);
            row0    = 1;

            for e = 1:nEle
                if nPerEle(e)==0, continue; end
                rawN = min(numel(valPerEle{e}),numel(locPerEle{e}));
                idx  = obj.sectionSampleIndex(rawN);
                v    = valPerEle{e}(idx);
                s_   = locPerEle{e}(idx);
                n    = numel(idx);

                p1   = P(info.conn(e,1),:);
                p2   = P(info.conn(e,2),:);
                axis = info.plotAxis(e,:);

                rows = row0:(row0+n-1);
                basePts(rows,:) = p1 + s_(:).*(p2-p1);
                tipPts(rows,:)  = basePts(rows,:) + sc.*v(:).*axis;
                vals(rows)      = v(:);

                eleStart(e) = row0;
                eleEnd(e)   = row0 + n - 1;
                row0 = row0 + n;
            end
        end

        function drawSurface(obj, basePts, tipPts, vals, eleStart, eleEnd)
            [cmin, cmax] = obj.colorLimits(vals);
            splitAtZero  = obj.Opts.color.useColormap && ~obj.Opts.performance.fastMode;

            nEle = numel(eleStart);
            nNode=0; nTri=0;
            for e=1:nEle
                r0=eleStart(e); r1=eleEnd(e);
                if r0==0||r1<r0, continue; end
                v=vals(r0:r1); n=numel(v);
                for seg=1:n-1
                    if ~splitAtZero || v(seg)*v(seg+1)>=0, nNode=nNode+4;
                    else, nNode=nNode+6; end
                    nTri=nTri+2;
                end
            end
            if nNode==0||nTri==0, return; end

            allNodes   = zeros(nNode,3);
            allTris    = zeros(nTri,3);
            allScalars = zeros(nNode,1);
            nodeIdx=1; triIdx=1;

            for e=1:nEle
                r0=eleStart(e); r1=eleEnd(e);
                if r0==0||r1<r0, continue; end
                base=basePts(r0:r1,:); tip=tipPts(r0:r1,:);
                v=vals(r0:r1); n=size(base,1);
                for seg=1:n-1
                    v0=v(seg); v1=v(seg+1);
                    b0=base(seg,:); b1=base(seg+1,:);
                    t0=tip(seg,:);  t1=tip(seg+1,:);
                    if ~splitAtZero || v0*v1>=0
                        ids=nodeIdx:nodeIdx+3;
                        allNodes(ids,:)   = [b0;t0;b1;t1];
                        allScalars(ids)   = [v0;v0;v1;v1];
                        allTris(triIdx:triIdx+1,:) = [ids(1),ids(2),ids(3);ids(2),ids(4),ids(3)];
                        nodeIdx=nodeIdx+4;
                    else
                        tc=v0/(v0-v1); zPt=b0+tc*(b1-b0);
                        ids=nodeIdx:nodeIdx+5;
                        allNodes(ids,:)   = [b0;t0;zPt;b1;t1;zPt];
                        allScalars(ids)   = [v0;v0;0;v1;v1;0];
                        allTris(triIdx:triIdx+1,:) = [ids(1),ids(2),ids(3);ids(4),ids(5),ids(6)];
                        nodeIdx=nodeIdx+6;
                    end
                    triIdx=triIdx+2;
                end
            end

            s.nodes=allNodes; s.tris=allTris; s.faceAlpha=obj.Opts.color.faceAlpha; s.tag='Diagram';
            if obj.Opts.color.useColormap
                s.values=allScalars; s.cmap=obj.Opts.color.colormap;
                s.clim=obj.climVal(cmin,cmax);
                obj.Handles.Diagram = obj.Plotter.addColoredMesh(s);
            else
                s.faceColor=obj.Opts.color.solidColor;
                obj.Handles.Diagram = obj.Plotter.addMesh(s);
            end
        end

        function drawWireframe(obj, basePts, tipPts, vals, eleStart, eleEnd)
            [cmin,cmax]=obj.colorLimits(vals);
            tipNodes=zeros(0,3); tipLines=zeros(0,2); tipVals=zeros(0,1);
            vertNodes=zeros(0,3); vertLines=zeros(0,2); vertVals=zeros(0,1);
            nEle=numel(eleStart);
            for e=1:nEle
                r0=eleStart(e); r1=eleEnd(e);
                if r0==0||r1<r0, continue; end
                base=basePts(r0:r1,:); tip=tipPts(r0:r1,:); v=vals(r0:r1); n=size(base,1);
                i0=size(tipNodes,1);
                tipNodes=[tipNodes;base(1,:);tip;base(end,:)]; %#ok<AGROW>
                tipLines=[tipLines;i0+[(1:n+1)',(2:n+2)']]; %#ok<AGROW>
                tipVals=[tipVals;0;v;0]; %#ok<AGROW>
                j0=size(vertNodes,1);
                vertNodes=[vertNodes;base;tip]; %#ok<AGROW>
                vertLines=[vertLines;j0+[(1:n)',(n+1:2*n)']]; %#ok<AGROW>
                vertVals=[vertVals;v;v]; %#ok<AGROW>
            end
            if ~isempty(tipNodes)
                s.nodes=tipNodes; s.lines=tipLines; s.lineWidth=obj.Opts.color.wireWidth;
                s.lineStyle='-'; s.tag='DiagramTip';
                if obj.Opts.color.useColormap
                    s.values=tipVals; s.cmap=obj.Opts.color.colormap; s.clim=obj.climVal(cmin,cmax);
                    obj.Handles.DiagramTip=obj.Plotter.addColoredLine(s);
                else, s.color=obj.Opts.color.wireColor; obj.Handles.DiagramTip=obj.Plotter.addLine(s); end
            end
            if ~isempty(vertNodes)
                sv.nodes=vertNodes; sv.lines=vertLines; sv.lineWidth=obj.Opts.color.wireWidth*0.6;
                sv.lineStyle='-'; sv.tag='DiagramVert';
                if obj.Opts.color.useColormap
                    sv.values=vertVals; sv.cmap=obj.Opts.color.colormap; sv.clim=obj.climVal(cmin,cmax);
                    obj.Handles.DiagramVert=obj.Plotter.addColoredLine(sv);
                else, sv.color=obj.Opts.color.wireColor; obj.Handles.DiagramVert=obj.Plotter.addLine(sv); end
            end
        end

        function drawZeroLines(~,~,~), end

        function drawModelLines(obj,P,conn)
            s.nodes=P; s.lines=conn;
            s.color=obj.Opts.color.modelColor;
            s.lineWidth=obj.Opts.color.modelWidth;
            s.tag='ModelLines';
            obj.Handles.ModelLines=obj.Plotter.addLine(s);
        end

                function annotate(obj, basePts, tipPts, vals, eleStart, eleEnd, info)
            % Place labels just outside the diagram tip.
            %
            % Label position for point k:
            %   offset_vec = tipPts(k) - basePts(k)   (already scaled by diagScale)
            %   labelPt    = tipPts(k) + gap * offset_vec
            %
            % This reuses vectors already computed by buildDiagram — no
            % redundant distance computation.  opts.labelGap (default 0.1)
            % controls how far beyond the tip the label sits.
            %
            % Text is rotated to be parallel to the local beam direction.
            if isempty(vals), return; end
            mode = obj.resolveLabelMode();
            gap  = obj.Opts.labelGap;
            if ~isnumeric(gap)||~isscalar(gap)||~isfinite(gap), gap = 0.1; end

            nEle = numel(eleStart);

            % Per-element beam direction (for text rotation) from info.
            Pn     = obj.nodeCoords(1, 1);
            eleDir = zeros(nEle, 3);
            for e = 1:nEle
                if eleStart(e)==0, continue; end
                if ~isempty(info.conn) && e<=size(info.conn,1)
                    d  = Pn(info.conn(e,2),:) - Pn(info.conn(e,1),:);
                    dn = norm(d);
                    if dn>1e-14, eleDir(e,:) = d/dn; end
                end
            end

            % Map each point index -> element index
            eleOfPt = zeros(size(vals));
            for e = 1:nEle
                r0=eleStart(e); r1=eleEnd(e);
                if r0==0||r1<r0, continue; end
                eleOfPt(r0:r1) = e;
            end

            % Collect (tip index, label string)
            tipIdx = zeros(0,1);
            lbls   = {};

            switch mode
                case 'global'
                    [vmax,imax] = max(vals);
                    [vmin,imin] = min(vals);
                    tipIdx = [imax; imin];
                    lbls   = {sprintf('max %.4g',vmax); sprintf('min %.4g',vmin)};
                case 'element'
                    for e = 1:nEle
                        r0=eleStart(e); r1=eleEnd(e);
                        if r0==0||r1<r0, continue; end
                        v = vals(r0:r1);
                        [vmax,imax] = max(v); imax = imax+r0-1;
                        [vmin,imin] = min(v); imin = imin+r0-1;
                        tipIdx = [tipIdx; imax];                          %#ok<AGROW>
                        lbls   = [lbls;   {sprintf('%.4g',vmax)}];        %#ok<AGROW>
                        if imin ~= imax
                            tipIdx = [tipIdx; imin];                      %#ok<AGROW>
                            lbls   = [lbls;   {sprintf('%.4g',vmin)}];    %#ok<AGROW>
                        end
                    end
                case 'all'
                    tipIdx = (1:numel(vals)).';
                    lbls   = arrayfun(@(x)sprintf('%.4g',x),vals,'UniformOutput',false);
                otherwise
                    return;
            end

            if isempty(tipIdx), return; end
            nLbl = numel(tipIdx);

            % Compute label positions and rotations
            for k = 1:nLbl
                ti  = tipIdx(k);
                tp  = tipPts(ti,:);
                bp  = basePts(ti,:);
                % offset vector already contains the scaled diagram height
                ov  = tp - bp;                      % base -> tip
                lp  = tp + gap * ov;                % beyond tip by gap fraction
                % beam rotation in XY plane
                e   = eleOfPt(ti);
                rot = 0;
                if e>=1 && e<=nEle
                    d = eleDir(e,:);
                    if norm(d(1:2)) > 1e-14
                        rot = rad2deg(atan2(d(2), d(1)));
                    end
                end
                text(obj.Ax, lp(1), lp(2), lp(3), lbls{k}, ...
                    'FontSize',            obj.Opts.labelFontSize, ...
                    'Color',               [0.1 0.1 0.1], ...
                    'Rotation',            rot, ...
                    'HorizontalAlignment', 'center', ...
                    'VerticalAlignment',   'bottom', ...
                    'Interpreter',         'none', ...
                    'Tag',                 'FrameRespLabel');
            end
        end
        function mode=resolveLabelMode(obj)
            v=obj.Opts.showMaxMinLabel;
            if islogical(v)||(isnumeric(v)&&isscalar(v))
                if v, mode='global'; else, mode='none'; end; return;
            end
            mode=lower(strtrim(char(string(v))));
            if ~ismember(mode,{'none','global','element','all'}), mode='global'; end
        end

        function tf=shouldAnnotate(obj,nEle)
            mode=obj.resolveLabelMode(); tf=~strcmp(mode,'none');
            if ~tf, return; end
            if obj.Opts.performance.fastMode, tf=strcmp(mode,'global'); return; end
            maxEl=obj.Opts.performance.maxElementLabels;
            if isnumeric(maxEl)&&isscalar(maxEl)&&isfinite(maxEl)&&nEle>maxEl&&ismember(mode,{'element','all'})
                tf=false;
            end
        end

        % =================================================================
        % Response data access
        % =================================================================

        function arr = getRespData(obj, segIdx, fieldName)
            % Returns the raw [nStep x nEle x ...] array for a response field
            % within segment segIdx.
            %
            %   Layout B: fr.<field>.data   [nStep x nEle x nComp]
            %   Layout C: fr.<field>.<dof>  [nStep x nEle x nSec]
            %             -> reconstructed along a new last dim in canonical order
            arr = [];
            fr = obj.FrameResp(segIdx);
            fieldName = obj.normalizeRespType(segIdx, fieldName);
            if ~isfield(fr, fieldName), return; end
            entry = fr.(fieldName);
            if isstruct(entry)
                if isfield(entry,'data')
                    arr = entry.data;      % Layout B
                else
                    % Layout C — rebuild in canonical dof order
                    dofs = obj.getRespDofs(segIdx, fieldName);
                    if isempty(dofs), return; end
                    parts = cell(1,numel(dofs));
                    for di = 1:numel(dofs)
                        if isfield(entry, dofs{di})
                            parts{di} = entry.(dofs{di});
                        else
                            % field not present; will be filled with NaN later
                            parts{di} = [];
                        end
                    end
                    % determine reference size from first non-empty part
                    refSz = [];
                    for di = 1:numel(parts)
                        if ~isempty(parts{di}) && isnumeric(parts{di})
                            refSz = size(parts{di});  break;
                        end
                    end
                    if isempty(refSz), return; end
                    nd = numel(refSz);
                    for di = 1:numel(parts)
                        if isempty(parts{di}) || ~isnumeric(parts{di})
                            parts{di} = NaN(refSz);
                        end
                    end
                    arr = cat(nd+1, parts{:});   % [nStep x nEle x nSec x nComp]
                end
            else
                arr = entry;
            end
        end

        function dofs = getRespDofs(obj, segIdx, fieldName)
            % Return DOF labels in canonical physical order for the field.
            % Layout C fields have mixed-case names (N, Mz, Vy, My, Vz, T);
            % we normalise to uppercase for matching, but return the actual
            % field names so getRespData can index into the struct.
            dofs = {};
            fr = obj.FrameResp(segIdx);
            fieldName = obj.normalizeRespType(segIdx, fieldName);
            if ~isfield(fr, fieldName), return; end
            entry = fr.(fieldName);
            if ~isstruct(entry), return; end
            if isfield(entry,'dofs')
                dofs = entry.dofs;  return;   % Layout B explicit labels
            end
            if isfield(entry,'data'), return; end
            % Layout C: re-order to canonical sequence by matching uppercase
            present   = fieldnames(entry).';
            presentUC = upper(present);
            % Canonical sequences per response type (uppercase)
            rt = upper(fieldName);
            if contains(rt,'SECTIONFORCE') || contains(rt,'SECTIONDEFORM')
                canonical = {'N','MZ','VY','MY','VZ','T'};
            elseif contains(rt,'BASICFORCE') || contains(rt,'BASICDEFORM') || contains(rt,'PLASTIC')
                canonical = {'N','MZ','MY','T'};
            elseif contains(rt,'LOCALFORCE')
                canonical = {'FX1','FY1','FZ1','MX1','MY1','MZ1','FX2','FY2','FZ2','MX2','MY2','MZ2'};
            else
                canonical = {};
            end
            % Map canonical → actual field name (case-insensitive)
            ordered = {};
            usedIdx = false(1,numel(present));
            for c = canonical
                idx = find(strcmpi(presentUC, c{1}), 1);
                if ~isempty(idx)
                    ordered{end+1} = present{idx}; %#ok<AGROW>
                    usedIdx(idx) = true;
                end
            end
            % Append any extra fields not in canonical list
            extras = present(~usedIdx);
            dofs = [ordered, extras];
        end

        function v = respFlat(obj, segIdx, localStep)
            perEle = obj.respPerEle(segIdx, localStep);
            if isempty(perEle), v=zeros(0,1); return; end
            v = vertcat(perEle{:});
        end

        function perEle = respPerEle(obj, segIdx, localStep)
            fr    = obj.FrameResp(segIdx);
            nEle  = obj.nEles(segIdx);
            perEle = cell(nEle,1);
            rt    = obj.normalizeRespType(segIdx, obj.Opts.respType);
            comp  = char(string(obj.Opts.component));

            A  = obj.getRespData(segIdx, rt);
            if isempty(A)
                for e=1:nEle, perEle{e}=zeros(0,1); end; return;
            end

            si = min(localStep, size(A,1));
            ci = obj.compIdx(rt, comp, obj.getRespDofs(segIdx, rt));
            nd = ndims(A);

            if nd == 3
                % [nStep x nEle x nComp]
                D = squeeze(double(A(si,:,:)));
                if isvector(D), D=D(:).'; end
                for e=1:nEle
                    if e>size(D,1), perEle{e}=0; continue; end
                    if ci>0&&ci<=size(D,2), perEle{e}=D(e,ci);
                    else, perEle{e}=0; end
                end
            elseif nd == 4
                % [nStep x nEle x nSec x nComp]
                D = squeeze(double(A(si,:,:,:)));
                for e=1:nEle
                    if e>size(D,1), perEle{e}=zeros(0,1); continue; end
                    sec = squeeze(D(e,:,:));
                    if isvector(sec), sec=sec(:); end
                    if ci>0&&ci<=size(sec,2)
                        vv=sec(:,ci); perEle{e}=vv(isfinite(vv));
                    else, perEle{e}=zeros(0,1); end
                end
            end

            for e=1:nEle
                if isempty(perEle{e}), perEle{e}=zeros(0,1); end
            end
        end

        function perEle = secLocs(obj, segIdx, localStep)
            nEle   = obj.nEles(segIdx);
            perEle = cell(nEle,1);
            respCache = [];

            function locs = uniform(e_)
                if isempty(respCache), respCache = obj.respPerEle(segIdx, localStep); end
                n_ = max(numel(respCache{e_}),2);
                locs = linspace(0,1,n_).';
            end

            L  = obj.getRespData(segIdx, 'sectionLocs');
            if isempty(L)
                for e=1:nEle, perEle{e}=uniform(e); end; return;
            end

            nd = ndims(L);
            si = min(localStep, size(L,1));

            if nd==4
                D = squeeze(double(L(si,:,:,1)));   % [nEle x nSec]
            elseif nd==3
                D = squeeze(double(L(si,:,:)));
            elseif nd==2
                D = double(L);
            else
                for e=1:nEle, perEle{e}=uniform(e); end; return;
            end
            if isvector(D), D=D(:).'; end

            for e=1:nEle
                if e>size(D,1), continue; end
                vv=squeeze(D(e,:)).'; vv=vv(isfinite(vv));
                perEle{e}=vv;
            end
            for e=1:nEle
                if isempty(perEle{e}), perEle{e}=uniform(e); end
            end
        end

        function ci = compIdx(~, respType, comp, dofs)
            if nargin<4, dofs={}; end
            comp = upper(strtrim(char(comp)));
            for d=1:numel(dofs)
                if strcmpi(dofs{d}, comp), ci=d; return; end
            end
            maps.sectionForces       = {'N','MZ','VY','MY','VZ','T'};
            maps.sectionDeformations = {'N','MZ','VY','MY','VZ','T'};
            maps.basicForces         = {'N','MZ','MY','T'};
            maps.basicDeformations   = {'N','MZ','MY','T'};
            maps.plasticDeformation  = {'N','MZ','MY','T'};
            maps.localForces         = {'FX1','FY1','FZ1','MX1','MY1','MZ1', ...
                                        'FX2','FY2','FZ2','MX2','MY2','MZ2'};
            rt = char(respType);
            if isfield(maps,rt)
                idx=find(strcmpi(maps.(rt),comp),1);
                if ~isempty(idx), ci=idx; return; end
            end
            n=str2double(comp);
            ci=max(1,round(double(~isnan(n))*n+isnan(n)));
        end

        % =================================================================
        % Diagram scale
        % =================================================================

        function sc = diagScale(obj, segIdx, localStep)
            scaleMode = lower(strtrim(char(string(obj.Opts.scaleMode))));
            if strcmpi(scaleMode,'current')
                % Cache keyed by (segIdx, localStep) encoded as single number
                key = obj.SegOffsets(segIdx) + localStep;
                if isfinite(obj.DiagScaleCache) && obj.DiagScaleStep==key
                    sc=obj.DiagScaleCache; return;
                end
                v=obj.respFlat(segIdx, localStep); v=v(isfinite(v));
                maxAbs=max(abs(v),[],'omitnan');
                if isempty(maxAbs)||~isfinite(maxAbs)||maxAbs<=0, maxAbs=1; end
                sc=(obj.Opts.heightFrac*obj.CachedModelSize/maxAbs)*obj.Opts.scale;
                obj.DiagScaleCache=sc; obj.DiagScaleStep=key; return;
            end
            % Global scale — cache with NaN key
            if isfinite(obj.DiagScaleCache) && isnan(obj.DiagScaleStep)
                sc=obj.DiagScaleCache; return;
            end
            maxAbs=0;
            for g=0:obj.nSteps()-1
                [si,ls]=obj.resolveGlobalStep(g);
                v=obj.respFlat(si,ls); v=v(isfinite(v));
                if ~isempty(v), maxAbs=max(maxAbs,max(abs(v))); end
            end
            if maxAbs<=0, maxAbs=1; end
            sc=(obj.Opts.heightFrac*obj.CachedModelSize/maxAbs)*obj.Opts.scale;
            obj.DiagScaleCache=sc; obj.DiagScaleStep=NaN;
        end

        % =================================================================
        % Beam geometry (topology fixed per segment)
        % =================================================================

        function [axField,axSign] = resolvePlotAxisSpec(obj)
            rt   = lower(strtrim(char(string(obj.Opts.respType))));
            comp = upper(strtrim(char(string(obj.Opts.component))));
            switch rt
                case {'localforces','localforce'}
                    switch comp
                        case {'FX','FX1','FX2','FY','FY1','FY2','MX','MX1','MX2'}
                            axField='YAxis'; axSign=1.0;
                        case {'FZ','FZ1','FZ2'}, axField='ZAxis'; axSign=1.0;
                        case {'MY','MY1','MY2'}, axField='ZAxis'; axSign=-1.0;
                        case {'MZ','MZ1','MZ2'}, axField='YAxis'; axSign=-1.0;
                        otherwise, axField='YAxis'; axSign=1.0;
                    end
                case {'basicforces','basicforce','basicdeformations','basicdeformation','plasticdeformation','plasticdeformations'}
                    switch comp
                        case 'N',  axField='YAxis'; axSign=1.0;
                        case 'MZ', axField='YAxis'; axSign=-1.0;
                        case 'MY', axField='ZAxis'; axSign=-1.0;
                        case 'T',  axField='YAxis'; axSign=1.0;
                        otherwise, axField='YAxis'; axSign=1.0;
                    end
                otherwise
                    switch comp
                        case 'MZ',            axField='YAxis'; axSign=-1.0;
                        case {'N','VY','T'},   axField='YAxis'; axSign=1.0;
                        case {'VZ','MY'},      axField='ZAxis'; axSign=1.0;
                        otherwise,            axField='YAxis'; axSign=1.0;
                    end
            end
        end

        function info = beamInfo(obj, segIdx, ~)
            % Topology is fixed within a segment; localStep is unused.
            info = struct('conn',zeros(0,2),'plotAxis',zeros(0,3),'tags',zeros(0,1));
            fam  = obj.families(segIdx);
            if ~isfield(fam,'Beam'), return; end
            B = fam.Beam;
            if ~isfield(B,'Cells')||isempty(B.Cells), return; end

            cells = double(B.Cells);
            if isvector(cells), cells=reshape(cells,1,[]); end
            if ~ismatrix(cells), cells=reshape(cells,size(cells,1),[]); end
            if isempty(cells)||size(cells,2)<2, return; end

            if isfield(B,'Tags')&&~isempty(B.Tags)
                tags=obj.trimVectorLength(double(B.Tags(:)),size(cells,1));
            else
                tags=(1:size(cells,1)).';
            end

            nCell=min(size(cells,1),numel(tags));
            if nCell==0, return; end
            cells=cells(1:nCell,:); tags=tags(1:nCell);

            keepRows=~all(isnan(cells),2);
            cells=cells(keepRows,:); tags=tags(keepRows);
            if isempty(cells), return; end

            [~,rawToClean]=obj.getNodeStepSelection(segIdx);
            conn=round(cells(:,end-1:end));
            validConn=all(isfinite(conn),2)&all(conn>=1,2)&all(conn<=numel(rawToClean),2);
            conn=conn(validConn,:); tags=tags(validConn);
            if isempty(conn), return; end
            conn=rawToClean(conn);
            keepMapped=all(conn>=1,2);
            conn=conn(keepMapped,:); tags=tags(keepMapped);
            if isempty(conn), return; end

            info.conn=conn; info.tags=double(tags(:));
            nEle=size(conn,1);
            P=obj.nodeCoords(segIdx, 1);
            [axField,axSign]=obj.resolvePlotAxisSpec();

            % Build plotAxis from stored axis field, with geometry fallback.
            % Stored YAxis/ZAxis follow OpenSees local-axis convention:
            %   YAxis = local y (in-plane for 2D, or element strong/weak axis)
            %   ZAxis = local z
            % Prefer stored axis; fall back to geometry when zero or NaN.
            useZ = strcmpi(axField,'ZAxis');
            info.plotAxis = zeros(nEle,3);

            % Detect 2-D model (all Z=0): diagram must stay in XY plane.
            is2D = obj.CachedModelDim == 2;

            % Geometry-derived fallback axis (used when stored axis is missing/zero).
            axGeom = zeros(nEle,3);
            for e=1:nEle
                d=P(conn(e,2),:)-P(conn(e,1),:);
                dn=norm(d); if dn<1e-14, continue; end; d=d/dn;
                up=[0 0 1];
                if abs(dot(d,up))>0.99, up=[0 1 0]; end
                if useZ, ax_=cross(d,cross(d,up)); else, ax_=cross(d,up); end
                na=norm(ax_);
                if na>1e-14, ax_=ax_/na; else, ax_=[0 1 0]; end
                axGeom(e,:) = axSign*ax_;
            end

            if isfield(B,axField) && ~isempty(B.(axField))
                ax=double(B.(axField));
                ax=obj.trimAxisRows(ax,nCell);
                ax=ax(keepRows,:);
                ax=obj.trimAxisRows(ax,numel(validConn));
                ax=ax(validConn,:);
                ax=obj.trimAxisRows(ax,numel(keepMapped));
                ax=ax(keepMapped,:);
                n=min(size(ax,1),nEle);
                stored=axSign*ax(1:n,1:3);
                for e=1:n
                    sv = stored(e,:);
                    if is2D, sv(3) = 0; end   % clamp to XY plane for 2-D models
                    ne = norm(sv);
                    if ne>1e-14
                        info.plotAxis(e,:) = sv/ne;
                    else
                        info.plotAxis(e,:) = axGeom(e,:);
                    end
                end
                for e=n+1:nEle
                    info.plotAxis(e,:)=axGeom(e,:);
                end
            else
                info.plotAxis = axGeom;
            end
        end

        % =================================================================
        % Topology helpers (per-segment, no time dim)
        % =================================================================

        function P = nodeCoords(obj, segIdx, ~)
            [P,~] = obj.getNodeStepData(segIdx);
        end

        function P = nodeCoordsRaw(obj, segIdx)
            P = zeros(0,3);
            mi = obj.ModelInfo(segIdx);
            if ~isfield(mi,'Nodes')||~isfield(mi.Nodes,'Coords'), return; end
            C = double(mi.Nodes.Coords);
            if isempty(C), return; end
            P = C;
            if size(P,2)<3, P(:,3)=0; elseif size(P,2)>3, P=P(:,1:3); end
        end

        function [P, tags] = getNodeStepData(obj, segIdx)
            P    = obj.nodeCoordsRaw(segIdx);
            tags = obj.getModelNodeTagsRaw(segIdx, size(P,1));
            if isempty(P), tags=zeros(0,1); return; end
            [keepMask,~] = obj.getNodeStepSelection(segIdx, P, tags);
            P    = P(keepMask,:);
            tags = tags(keepMask);
        end

        function [keepMask, rawToClean] = getNodeStepSelection(obj, segIdx, P, tags)
            if nargin<3||isempty(P),    P    = obj.nodeCoordsRaw(segIdx); end
            if nargin<4||isempty(tags), tags = obj.getModelNodeTagsRaw(segIdx,size(P,1)); end
            keepMask   = obj.getNodeStepMask(segIdx, P, tags);
            rawToClean = zeros(size(keepMask));
            rawToClean(keepMask) = 1:nnz(keepMask);
        end

        function keepMask = getNodeStepMask(obj, segIdx, P, tags)
            if nargin<3||isempty(P),    P    = obj.nodeCoordsRaw(segIdx); end
            if nargin<4||isempty(tags), tags = obj.getModelNodeTagsRaw(segIdx,size(P,1)); end
            keepMask = ~all(isnan(P),2);
            unusedTags = obj.getUnusedNodeTags(segIdx);
            if isempty(unusedTags)||isempty(tags), return; end
            tags = obj.trimVectorLength(tags, numel(keepMask));
            keepMask = keepMask & ~ismember(tags, unusedTags);
        end

        function tags = getModelNodeTagsRaw(obj, segIdx, nRow)
            if nargin<3, nRow=[]; end
            tags = [];
            mi = obj.ModelInfo(segIdx);
            if ~isfield(mi,'Nodes')||~isfield(mi.Nodes,'Tags')||isempty(mi.Nodes.Tags)
                return;
            end
            tags = double(mi.Nodes.Tags(:));
            if ~isempty(nRow), tags=obj.trimVectorLength(tags,nRow); end
        end

        function tags = getUnusedNodeTags(obj, segIdx)
            tags = [];
            mi = obj.ModelInfo(segIdx);
            if ~isfield(mi,'Nodes')||~isfield(mi.Nodes,'UnusedTags')||isempty(mi.Nodes.UnusedTags)
                return;
            end
            tags = unique(double(mi.Nodes.UnusedTags(isfinite(mi.Nodes.UnusedTags))));
        end

        function fam = families(obj, segIdx)
            fam = struct();
            mi  = obj.ModelInfo(segIdx);
            if ~isfield(mi,'Elements'), return; end
            E = mi.Elements;
            if isfield(E,'Families'), fam=E.Families; else, fam=E; end
        end

        function n = nEles(obj, segIdx)
            fr = obj.FrameResp(segIdx);
            if isfield(fr,'eleTags'), n=numel(fr.eleTags); return; end
            for fn=fieldnames(fr).'
                A=fr.(fn{1});
                if isstruct(A)&&isfield(A,'data'), A=A.data; end
                if isnumeric(A)&&ndims(A)>=3, n=size(A,2); return; end
            end
            n=0;
        end

        function [cells, modelRowsUsed, keepRows] = remapCellsToModelRows(obj, cells, segIdx)
            modelRowsUsed=zeros(0,1); keepRows=false(size(cells,1),1);
            if isempty(cells), return; end
            [~,rawToClean]=obj.getNodeStepSelection(segIdx);
            if isempty(rawToClean), cells=zeros(0,size(cells,2)); keepRows=false(0,1); return; end
            for i=1:size(cells,1)
                row=double(cells(i,:)); row=row(isfinite(row)&row>0);
                if isempty(row), continue; end
                ids=round(row(:));
                if any(ids<1|ids>numel(rawToClean)), continue; end
                rr=rawToClean(ids);
                if any(rr<=0), continue; end
                cells(i,1:numel(rr))=rr(:).';
                modelRowsUsed=[modelRowsUsed;rr(:)]; %#ok<AGROW>
                keepRows(i)=true;
            end
            cells=cells(keepRows,:);
            if ~isempty(modelRowsUsed), modelRowsUsed=unique(round(modelRowsUsed),'stable'); end
        end

        % =================================================================
        % Step peak search
        % =================================================================

        function vals = peakStepValuesFast(obj, key)
            % Vectorised peak search across all steps — avoids the per-step
            % loop in peakStepValuesSlow by extracting the full time axis of
            % the response component in one array operation.
            % Supports all segment counts (concatenates across segments).
            vals = [];
            rt   = char(string(obj.Opts.respType));
            comp = char(string(obj.Opts.component));
            allPeak = [];
            for s = 1:obj.SegCount
                rt_s = obj.normalizeRespType(s, rt);
                A    = obj.getRespData(s, rt_s);
                if isempty(A), continue; end
                D = obj.selectRespComponentAllSteps(s, A, rt_s, comp);
                if isempty(D), continue; end
                D = double(D);
                M = reshape(D, size(D,1), []);
                M(~isfinite(M)) = NaN;
                switch key
                    case {'absmax','absmin'}, p = max(abs(M),[],2,'omitnan');
                    case 'max',              p = max(M,[],2,'omitnan');
                    case 'min',              p = min(M,[],2,'omitnan');
                    otherwise, return;
                end
                allPeak = [allPeak; p(:)]; %#ok<AGROW>
            end
            if isempty(allPeak)||all(~isfinite(allPeak)), return; end
            vals = allPeak;
        end

        function vals = peakStepValuesSlow(obj, key)
            n = obj.nSteps();
            vals = obj.initStepSelectorValues(key, n);
            for g=0:n-1
                [si,ls]=obj.resolveGlobalStep(g);
                v=obj.respFlat(si,ls); v=v(isfinite(v));
                if isempty(v), continue; end
                switch key
                    case {'absmax','absmin'}, vals(g+1)=max(abs(v),[],  'omitnan');
                    case 'max',              vals(g+1)=max(v,[],     'omitnan');
                    case 'min',              vals(g+1)=min(v,[],     'omitnan');
                end
            end
            vals=vals(:);
            if all(~isfinite(vals)), vals=[]; end
        end

        function D = selectRespComponentAllSteps(obj, segIdx, A, rt, comp)
            D  = [];
            ci = obj.compIdx(rt, comp, obj.getRespDofs(segIdx, rt));
            nd = ndims(A);
            if nd==3&&ci>0&&ci<=size(A,3),       D=A(:,:,ci);
            elseif nd==4&&ci>0&&ci<=size(A,4),   D=A(:,:,:,ci);
            end
        end

        % =================================================================
        % Step / respType normalisation
        % =================================================================

        function rt = normalizeRespType(obj, segIdx, rt)
            rt = char(rt);
            fr = obj.FrameResp(segIdx);
            if isfield(fr,rt), return; end
            fn = fieldnames(fr);
            match = fn(strcmpi(fn,rt));
            if ~isempty(match), rt=match{1}; return; end
            known={'localForces','basicForces','basicDeformations','plasticDeformation', ...
                   'sectionForces','sectionDeformations','sectionLocs'};
            match=known(strcmpi(known,rt));
            if ~isempty(match), rt=match{1}; end
        end

        function key = normalizeStepSelector(~, stepIdx)
            key=lower(strtrim(char(string(stepIdx))));
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

        % =================================================================
        % Axes decoration
        % =================================================================

        function prepAxes(obj, segIdx)
            sz=obj.Opts.general.figureSize;
            if isnumeric(sz)&&numel(sz)==2&&all(sz>0)
                fig=ancestor(obj.Ax,'figure');
                fig.Units='pixels'; pos=fig.Position; pos(3:4)=sz; fig.Position=pos;
            end
            if obj.Opts.general.clearAxes
                cla(obj.Ax,'reset'); hold(obj.Ax,'on');
            elseif obj.Opts.general.holdOn
                hold(obj.Ax,'on');
            end
            if obj.Opts.general.axisEqual, axis(obj.Ax,'equal'); end
            if obj.Opts.general.grid, grid(obj.Ax,'on'); else, grid(obj.Ax,'off'); end
            if obj.Opts.general.box,  box(obj.Ax,'on');  else, box(obj.Ax,'off');  end
            colormap(obj.Ax, obj.Opts.color.colormap);
            % Refresh model dim for this segment
            P = obj.nodeCoordsRaw(segIdx);
            obj.CachedModelDim  = obj.modelDim(segIdx, P);
            obj.CachedModelSize = obj.modelSize(P);
        end

        function applyView(obj, segIdx)
            v=lower(char(string(obj.Opts.general.view)));
            if strcmp(v,'auto')
                if obj.CachedModelDim==2
                    % 2-D model: diagram stays in XY plane, use top-down view.
                    view(obj.Ax, 2);
                else
                    view(obj.Ax, 3);
                end
                return;
            end
            switch v
                case 'iso', view(obj.Ax,3);
                case 'xy',  view(obj.Ax,2);
                case 'xz',  view(obj.Ax,0,0);
                otherwise
                    if obj.CachedModelDim==2, view(obj.Ax,3); else, view(obj.Ax,3); end
            end
        end

        function applyTitle(obj, segIdx, localStep, globalStep)
            t = string(obj.Opts.general.title);
            if strcmpi(t,'auto')
                fr = obj.FrameResp(segIdx);
                if isfield(fr,'time')&&numel(fr.time)>=localStep
                    tval=fr.time(localStep);
                else, tval=NaN; end
                title(obj.Ax, sprintf('%s  %s  |  step %d  |  t = %.4g s', ...
                    char(string(obj.Opts.respType)), char(string(obj.Opts.component)), ...
                    globalStep, tval));
            elseif strlength(t)>0
                title(obj.Ax, char(t));
            end
        end

        function applyColorbar(obj)
            if ~obj.Opts.color.useColormap||~obj.Opts.cbar.show
                colorbar(obj.Ax,'off'); return;
            end
            [cmin,cmax]=obj.colorLimits([]);
            clim(obj.Ax, obj.climVal(cmin,cmax));
            cb=colorbar(obj.Ax);
            cb.FontSize=11; cb.TickDirection='in';
            cb.Title.String='';
            cb.Label.String=obj.colorbarSideTitle();
            cb.Label.FontSize=13;
        end

        function txt=colorbarSideTitle(obj)
            respTitle=sprintf('%s | %s',char(string(obj.Opts.respType)),char(string(obj.Opts.component)));
            extraLabel=string(obj.Opts.cbar.label);
            if strlength(strtrim(extraLabel))>0, txt=sprintf('%s | %s',respTitle,char(extraLabel));
            else, txt=respTitle; end
        end

        function cv=climVal(obj,cmin,cmax)
            if ~isempty(obj.Opts.color.clim)&&numel(obj.Opts.color.clim)==2
                cv=obj.Opts.color.clim;
            else, cv=[cmin cmax]; end
        end

        function [cmin,cmax]=colorLimits(obj,vals)
            if ~isempty(obj.Opts.color.clim)&&numel(obj.Opts.color.clim)==2
                cmin=obj.Opts.color.clim(1); cmax=obj.Opts.color.clim(2); return;
            end
            mode=lower(strtrim(char(string(obj.Opts.color.climMode))));
            useCurrent=strcmp(mode,'current')||obj.Opts.performance.fastMode;
            if useCurrent&&nargin>=2&&~isempty(vals)
                v=vals(isfinite(vals));
                if isempty(v), cmin=0; cmax=1;
                else, cmin=min(v); cmax=max(v); if cmin==cmax, cmax=cmin+1; end; end
                obj.CurrentClimCache=[cmin cmax]; return;
            end
            if useCurrent&&~isempty(obj.CurrentClimCache)
                cmin=obj.CurrentClimCache(1); cmax=obj.CurrentClimCache(2); return;
            end
            [cmin,cmax]=obj.globalClim();
        end

        % =================================================================
        % Geometry utilities
        % =================================================================

        function dim = modelDim(obj, segIdx, P)
            % Determine 2-D vs 3-D by checking whether ALL node z-coordinates
            % are (numerically) zero.  This is the most reliable criterion:
            %   - A planar XY model always has z = 0 for every node.
            %   - Ndm can be misleading (a 3-D element class in a 2-D model).
            %   - Spread-based tests fail when z spans a small but nonzero range.
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

        function ndm = getModelNdm(obj, segIdx)
            ndm = [];
            mi  = obj.ModelInfo(segIdx);
            if ~isfield(mi,'Nodes')||~isfield(mi.Nodes,'Ndm')||isempty(mi.Nodes.Ndm)
                return;
            end
            ndm = double(mi.Nodes.Ndm(:));
        end

        function L=modelSize(~,P)
            if isempty(P), L=1; return; end
            ext=max(P,[],1,'omitnan')-min(P,[],1,'omitnan');
            ext=ext(isfinite(ext));
            if isempty(ext), L=1; return; end
            L=max(ext); if ~isfinite(L)||L<=0, L=1; end
        end

        function idx=sectionSampleIndex(obj,n)
            if n<=0, idx=zeros(0,1); return; end
            maxN=obj.Opts.performance.maxSectionsPerElement;
            if ~(isnumeric(maxN)&&isscalar(maxN)&&isfinite(maxN)&&maxN>=2)||n<=maxN
                idx=(1:n).'; return;
            end
            idx=unique(round(linspace(1,n,maxN))).';
            if idx(1)~=1, idx=[1;idx(:)]; end
            if idx(end)~=n, idx=[idx(:);n]; end
        end

        function values=trimVectorLength(~,values,nRow)
            values=values(:);
            if numel(values)<nRow, values(end+1:nRow,1)=NaN;
            elseif numel(values)>nRow, values=values(1:nRow); end
        end

        function ax=trimAxisRows(~,ax,nRow)
            if isempty(ax), ax=zeros(0,3); return; end
            if size(ax,2)<3, ax(:,3)=0; elseif size(ax,2)>3, ax=ax(:,1:3); end
            if size(ax,1)<nRow, ax(end+1:nRow,:)=NaN;
            elseif size(ax,1)>nRow, ax=ax(1:nRow,:); end
        end

        function out=merge(obj,base,add) %#ok<INUSL>
            out=base;
            if isempty(add)||~isstruct(add), return; end
            for fn=fieldnames(add).'
                n=fn{1};
                if isfield(out,n)&&isstruct(out.(n))&&isstruct(add.(n))
                    out.(n)=obj.merge(out.(n),add.(n));
                else, out.(n)=add.(n); end
            end
        end

    end % private methods
end % classdef
