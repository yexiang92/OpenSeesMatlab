classdef PlotFrameResp < handle
    % PlotFrameResp
    % Bending-moment / shear / axial-force diagram for frame elements.
    %
    % Supported response types
    % ------------------------
    %   sectionForces / sectionDeformations   [nStep x nEle x nSec x nComp]
    %   basicForces   / basicDeformations     [nStep x nEle x nComp]
    %   localForces   / plasticDeformation    [nStep x nEle x nComp]
    %
    % Data layout (frameResp fields)
    % --------------------------------
    %   frameResp.<field>          – struct with .data / .dofs / .dimNames
    %   frameResp.sectionLocs      – struct with .data [nStep x nEle x nSec x nLocDof]
    %   frameResp.eleTags          – [nEle x 1]
    %   frameResp.time             – [nStep x 1]
    %
    % Performance tips for large beam models
    % --------------------------------------
    %   Frame response plotting can become slow when a model contains many beam
    %   elements, especially if per-element text labels or auxiliary wireframes
    %   are enabled. For large models, start from the default options and disable
    %   expensive decorations:
    %
    %       opts = plotter.PlotFrameResp.defaultOptions();
    %       opts.showMaxMinLabel = 'none';          % avoid one or more text labels per element
    %       opts.performance.fastMode = true;       % skip expensive auxiliary geometry/labels
    %       opts.performance.maxSectionsPerElement = 12; % downsample section points per element
    %       opts.surf.show = false;                 % skip non-frame unstructured wireframe
    %       opts.cbar.show = false;                 % skip colorbar creation/update
    %       opts.color.useColormap = false;         % use a solid-color diagram
    %
    %   If color mapping is still needed, the default color limit mode uses only
    %   the current step. Providing fixed color limits is fastest and avoids any
    %   color-limit scan:
    %
    %       opts.color.useColormap = true;
    %       opts.color.climMode = 'current';      % 'current' | 'global'
    %       opts.color.clim = [-1.0e3, 1.0e3];   % optional fixed limits
    %
    %   The default performance.maxElementLabels setting automatically suppresses
    %   element/all labels when the beam-element count is large. Set it to Inf
    %   only when all labels are explicitly required.

    % =====================================================================
    properties
        ModelInfo   struct
        FrameResp   struct
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

        PeakCache        struct = struct('absmax',[],'absmin',[],'max',[],'min',[])
        DiagScaleCache   double = NaN
        DiagScaleStep    double = NaN
        CurrentClimCache double = []
    end

    % =====================================================================
    methods (Static)
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
                'wireColor','blue', 'wireWidth',1.2, ...
                'zeroLineColor','black', 'zeroLineWidth',0.7, ...
                'modelColor','black', 'modelWidth',1.0);

            opts.showModel     = true;
            opts.showBeamModel = true;
            opts.showZeroLine  = true;

            opts.surf = struct('show',true, 'lineColor','#d8dcd6', 'lineWidth',0.8);

            % Performance options for large frame models.
            % fastMode skips expensive auxiliary geometry/labels.
            % maxElementLabels automatically suppresses element/all labels above
            % the specified beam-element count. Use Inf to disable this limit.
            % maxSectionsPerElement downsamples section-point diagrams. Use Inf
            % to keep all section points.
            opts.performance = struct( ...
                'fastMode',false, ...
                'maxElementLabels',200, ...
                'maxSectionsPerElement',24);

            % 'none' | 'global' | 'element' | 'all'
            % true/false also accepted for backward compatibility.
            opts.showMaxMinLabel = 'global';
            opts.labelFontSize   = 9;

            opts.cbar = struct('show',true, 'label','');
        end
    end

    % =====================================================================
    methods

        function obj = PlotFrameResp(modelInfo, frameResp, ax, opts)
            if nargin < 3, ax = []; end
            if nargin < 4, opts = []; end

            obj.ModelInfo = modelInfo;
            obj.FrameResp = frameResp;
            obj.Opts      = obj.merge(plotter.PlotFrameResp.defaultOptions(), opts);
            obj.Plotter   = plotter.PatchPlotter(ax);
            obj.Ax        = obj.Plotter.Ax;

            if isfield(frameResp,'ModelUpdate')
                obj.ModelUpdateFlag = logical(frameResp.ModelUpdate);
            end

            P = obj.nodeCoords(1);
            obj.CachedModelDim  = obj.modelDim(P);
            obj.CachedModelSize = obj.modelSize(P);
        end

        function ax = getAxes(obj)
            ax = obj.Ax;
        end

        function setOptions(obj, opts)
            prev         = [char(string(obj.Opts.respType)),'|',char(string(obj.Opts.component))];
            prevScaleMode = char(string(obj.Opts.scaleMode));

            obj.Opts = obj.merge(obj.Opts, opts);

            now          = [char(string(obj.Opts.respType)),'|',char(string(obj.Opts.component))];
            nowScaleMode  = char(string(obj.Opts.scaleMode));

            if ~strcmp(prev, now) || ~strcmp(prevScaleMode, nowScaleMode)
                obj.GlobalClimCache = [];
                obj.CurrentClimCache = [];
                obj.PeakCache       = struct('absmax',[],'absmin',[],'max',[],'min',[]);
                obj.DiagScaleCache  = NaN;
                obj.DiagScaleStep   = NaN;
            end
        end

        function h = plotStep(obj, stepIdx, opts)
            if nargin >= 3 && ~isempty(opts)
                obj.setOptions(opts);
            end
            stepIdx = obj.resolveStep(stepIdx);
            obj.CurrentClimCache = [];
            obj.prepAxes();
            obj.Handles = struct();
            obj.render(stepIdx);
            h = obj.Handles;
        end

        function [cmin, cmax] = globalClim(obj)
            if ~isempty(obj.Opts.color.clim) && numel(obj.Opts.color.clim) == 2
                cmin = obj.Opts.color.clim(1);
                cmax = obj.Opts.color.clim(2);
                return;
            end

            if ~isempty(obj.GlobalClimCache) && ...
               strcmp(obj.GlobalClimField, char(string(obj.Opts.respType))) && ...
               strcmp(obj.GlobalClimComp,  char(string(obj.Opts.component)))
                cmin = obj.GlobalClimCache(1);
                cmax = obj.GlobalClimCache(2);
                return;
            end

            allV = [];
            for k = 1:obj.nSteps()
                v = obj.respFlat(k);
                allV = [allV; v(isfinite(v))]; %#ok<AGROW>
            end
            if isempty(allV), allV = [0; 1]; end

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
        % Render
        % =================================================================

        function render(obj, stepIdx)
            P    = obj.nodeCoords(stepIdx);
            info = obj.beamInfo(stepIdx);

            if obj.Opts.showModel
                if obj.Opts.showBeamModel && ~isempty(info.conn)
                    obj.drawModelLines(P, info.conn);
                end
                if obj.Opts.surf.show && ~obj.Opts.performance.fastMode
                    try
                        obj.drawUnstructuredWireframe(P, stepIdx);
                    catch ME
                        warning('PlotFrameResp:UnstructuredWireframeFailed', ...
                            'Failed to draw unstructured wireframe: %s', ME.message);
                    end
                end
            end

            if ~isempty(info.conn)
                sc = obj.diagScale(stepIdx);

                [basePts, tipPts, vals, eleStart, eleEnd] = ...
                    obj.buildDiagram(P, info, stepIdx, sc);

                if ~isempty(basePts)
                    if strcmpi(obj.Opts.style, 'surface')
                        obj.drawSurface(basePts, tipPts, vals, eleStart, eleEnd);
                    else
                        obj.drawWireframe(basePts, tipPts, vals, eleStart, eleEnd);
                    end
                end

                if obj.Opts.showZeroLine && ~isempty(basePts)
                    obj.drawZeroLines(eleStart, eleEnd);
                end

                if obj.shouldAnnotate(numel(eleStart)) && ~isempty(vals)
                    obj.annotate(basePts, tipPts, vals, eleStart, eleEnd);
                end
            end

            obj.applyColorbar();
            obj.applyTitle(stepIdx);
            obj.applyView();
            obj.Plotter.applyDataLimits(P, obj.Opts.general.padRatio);
        end

        % =================================================================
        % Unstructured mesh wireframe
        % =================================================================

        function drawUnstructuredWireframe(obj, P, stepIdx)
            fam = obj.families();
            if ~isfield(fam,'Unstructured'), return; end
            U = fam.Unstructured;
            if ~isfield(U,'Cells')||isempty(U.Cells), return; end
            if ~isfield(U,'CellTypes')||isempty(U.CellTypes), return; end

            cells     = double(U.Cells);
            cellTypes = double(U.CellTypes);

            if obj.ModelUpdateFlag
                if ndims(cells)==3
                    cells = squeeze(cells(min(stepIdx,size(cells,1)),:,:));
                end
                if ndims(cellTypes)==3
                    cellTypes = squeeze(cellTypes(min(stepIdx,size(cellTypes,1)),:,:));
                elseif ismatrix(cellTypes) && size(cellTypes,1)==obj.nSteps()
                    cellTypes = squeeze(cellTypes(min(stepIdx,size(cellTypes,1)),:));
                end
            end

            if isvector(cells)
                cells = reshape(cells, 1, []);
            elseif ~ismatrix(cells)
                cells = reshape(cells, size(cells,1), []);
            end

            cellTypes = cellTypes(:);

            if isempty(cells) || isempty(cellTypes)
                return;
            end

            keepRows = ~all(isnan(cells), 2);
            cells = cells(keepRows, :);
            if numel(cellTypes) == numel(keepRows)
                cellTypes = cellTypes(keepRows);
            end

            nCell = min(size(cells, 1), numel(cellTypes));
            if nCell == 0
                return;
            end
            cells = cells(1:nCell, :);
            cellTypes = cellTypes(1:nCell);

            keepRows = false(nCell, 1);
            for i = 1:nCell
                keepRows(i) = any(isfinite(cells(i, :)));
            end
            cells = cells(keepRows, :);
            cellTypes = cellTypes(keepRows);
            if isempty(cells)
                return;
            end

            [cells, ~, keepRows] = obj.remapCellsToModelRows(cells, stepIdx);
            if numel(cellTypes) == numel(keepRows)
                cellTypes = cellTypes(keepRows);
            end
            if isempty(cells)
                return;
            end

            surfOut = plotter.utils.VTKElementTriangulator.triangulate(P, cellTypes, cells);
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
                buildDiagram(obj, P, info, stepIdx, sc)

            valPerEle = obj.respPerEle(stepIdx);
            locPerEle = obj.secLocs(stepIdx);
            nEle      = size(info.conn,1);

            nPerEle  = zeros(nEle,1);
            eleStart = zeros(nEle,1);
            eleEnd   = zeros(nEle,1);

            totalPts = 0;
            for e = 1:nEle
                v = valPerEle{e}(:);
                s = locPerEle{e}(:);
                if isempty(v) || isempty(s), continue; end

                n = min(numel(v), numel(s));
                idx = obj.sectionSampleIndex(n);
                nPerEle(e) = numel(idx);
                totalPts = totalPts + nPerEle(e);
            end

            basePts = zeros(totalPts,3);
            tipPts  = zeros(totalPts,3);
            vals    = zeros(totalPts,1);

            row0 = 1;
            for e = 1:nEle
                n = nPerEle(e);
                if n == 0, continue; end

                rawN = min(numel(valPerEle{e}), numel(locPerEle{e}));
                idx = obj.sectionSampleIndex(rawN);
                v = valPerEle{e}(idx);
                s = locPerEle{e}(idx);
                n = numel(idx);

                p1   = P(info.conn(e,1),:);
                p2   = P(info.conn(e,2),:);
                axis = info.plotAxis(e,:);

                rows = row0:(row0+n-1);
                basePts(rows,:) = p1 + s(:) .* (p2 - p1);
                tipPts(rows,:)  = basePts(rows,:) + sc .* v(:) .* axis;
                vals(rows)      = v(:);

                eleStart(e) = row0;
                eleEnd(e)   = row0 + n - 1;
                row0 = row0 + n;
            end
        end

        function drawSurface(obj, basePts, tipPts, vals, eleStart, eleEnd)
            [cmin, cmax] = obj.colorLimits(vals);
            splitAtZero = obj.Opts.color.useColormap && ~obj.Opts.performance.fastMode;

            nEle = numel(eleStart);
            nNode = 0;
            nTri  = 0;

            for e = 1:nEle
                r0 = eleStart(e);  r1 = eleEnd(e);
                if r0==0||r1<r0, continue; end

                v = vals(r0:r1);
                n = numel(v);
                for seg = 1:n-1
                    if ~splitAtZero || v(seg)*v(seg+1) >= 0
                        nNode = nNode + 4;
                    else
                        nNode = nNode + 6;
                    end
                    nTri = nTri + 2;
                end
            end

            if nNode == 0 || nTri == 0
                return;
            end

            allNodes   = zeros(nNode,3);
            allTris    = zeros(nTri,3);
            allScalars = zeros(nNode,1);

            nodeIdx = 1;
            triIdx  = 1;

            for e = 1:nEle
                r0 = eleStart(e);  r1 = eleEnd(e);
                if r0==0||r1<r0, continue; end

                base = basePts(r0:r1,:);
                tip  = tipPts(r0:r1,:);
                v    = vals(r0:r1);
                n    = size(base,1);

                for seg = 1:n-1
                    v0 = v(seg);     v1 = v(seg+1);
                    b0 = base(seg,:); b1 = base(seg+1,:);
                    t0 = tip(seg,:);  t1 = tip(seg+1,:);

                    if ~splitAtZero || v0*v1 >= 0
                        ids = nodeIdx:nodeIdx+3;
                        allNodes(ids,:) = [b0; t0; b1; t1];
                        allScalars(ids) = [v0; v0; v1; v1];
                        allTris(triIdx:triIdx+1,:) = [ ...
                            ids(1), ids(2), ids(3); ...
                            ids(2), ids(4), ids(3)];
                        nodeIdx = nodeIdx + 4;
                    else
                        tc  = v0/(v0-v1);
                        zPt = b0 + tc*(b1-b0);
                        ids = nodeIdx:nodeIdx+5;
                        allNodes(ids,:) = [b0; t0; zPt; b1; t1; zPt];
                        allScalars(ids) = [v0; v0; 0; v1; v1; 0];
                        allTris(triIdx:triIdx+1,:) = [ ...
                            ids(1), ids(2), ids(3); ...
                            ids(4), ids(5), ids(6)];
                        nodeIdx = nodeIdx + 6;
                    end

                    triIdx = triIdx + 2;
                end
            end

            s.nodes     = allNodes;
            s.tris      = allTris;
            s.faceAlpha = obj.Opts.color.faceAlpha;
            s.tag       = 'Diagram';

            if obj.Opts.color.useColormap
                s.values = allScalars;
                s.cmap   = obj.Opts.color.colormap;
                s.clim   = obj.climVal(cmin, cmax);
                obj.Handles.Diagram = obj.Plotter.addColoredMesh(s);
            else
                s.faceColor = obj.Opts.color.solidColor;
                obj.Handles.Diagram = obj.Plotter.addMesh(s);
            end
        end

        function drawWireframe(obj, basePts, tipPts, vals, eleStart, eleEnd)
            [cmin, cmax] = obj.colorLimits(vals);

            tipNodes = zeros(0,3);
            tipLines = zeros(0,2);
            tipVals  = zeros(0,1);

            vertNodes = zeros(0,3);
            vertLines = zeros(0,2);
            vertVals  = zeros(0,1);

            nEle = numel(eleStart);
            for e = 1:nEle
                r0 = eleStart(e); r1 = eleEnd(e);
                if r0 == 0 || r1 < r0, continue; end

                base = basePts(r0:r1,:);
                tip  = tipPts(r0:r1,:);
                v    = vals(r0:r1);
                n    = size(base,1);

                i0 = size(tipNodes,1);
                tipNodes = [tipNodes; base(1,:); tip; base(end,:)]; %#ok<AGROW>
                tipLines = [tipLines; i0 + [(1:n+1)', (2:n+2)']]; %#ok<AGROW>
                tipVals  = [tipVals; 0; v; 0]; %#ok<AGROW>

                j0 = size(vertNodes,1);
                vertNodes = [vertNodes; base; tip]; %#ok<AGROW>
                vertLines = [vertLines; j0 + [(1:n)', (n+1:2*n)']]; %#ok<AGROW>
                vertVals  = [vertVals; v; v]; %#ok<AGROW>
            end

            if ~isempty(tipNodes)
                s.nodes     = tipNodes;
                s.lines     = tipLines;
                s.lineWidth = obj.Opts.color.wireWidth;
                s.lineStyle = '-';
                s.tag       = 'DiagramTip';
                if obj.Opts.color.useColormap
                    s.values = tipVals;
                    s.cmap   = obj.Opts.color.colormap;
                    s.clim   = obj.climVal(cmin,cmax);
                    obj.Handles.DiagramTip = obj.Plotter.addColoredLine(s);
                else
                    s.color = obj.Opts.color.wireColor;
                    obj.Handles.DiagramTip = obj.Plotter.addLine(s);
                end
            end

            if ~isempty(vertNodes)
                sv.nodes     = vertNodes;
                sv.lines     = vertLines;
                sv.lineWidth = obj.Opts.color.wireWidth * 0.6;
                sv.lineStyle = '-';
                sv.tag       = 'DiagramVert';
                if obj.Opts.color.useColormap
                    sv.values = vertVals;
                    sv.cmap   = obj.Opts.color.colormap;
                    sv.clim   = obj.climVal(cmin,cmax);
                    obj.Handles.DiagramVert = obj.Plotter.addColoredLine(sv);
                else
                    sv.color = obj.Opts.color.wireColor;
                    obj.Handles.DiagramVert = obj.Plotter.addLine(sv);
                end
            end
        end

        function drawZeroLines(~,~,~), end

        function drawModelLines(obj, P, conn)
            s.nodes=P; s.lines=conn;
            s.color=obj.Opts.color.modelColor;
            s.lineWidth=obj.Opts.color.modelWidth;
            s.tag='ModelLines';
            obj.Handles.ModelLines = obj.Plotter.addLine(s);
        end

        function annotate(obj, ~, tipPts, vals, eleStart, eleEnd)
            if isempty(vals), return; end
            mode = obj.resolveLabelMode();

            pts  = zeros(0,3);
            lbls = {};

            switch mode
                case 'global'
                    [vmax,imax] = max(vals);  [vmin,imin] = min(vals);
                    pts  = [tipPts(imax,:); tipPts(imin,:)];
                    lbls = {sprintf('max %.4g',vmax); sprintf('min %.4g',vmin)};

                case 'element'
                    nEle = numel(eleStart);
                    for e = 1:nEle
                        r0 = eleStart(e);  r1 = eleEnd(e);
                        if r0==0 || r1<r0, continue; end
                        v = vals(r0:r1);
                        [vmax,imax] = max(v);  [vmin,imin] = min(v);
                        imax = imax + r0 - 1;
                        imin = imin + r0 - 1;
                        pts  = [pts;  tipPts(imax,:)];           %#ok<AGROW>
                        lbls = [lbls; {sprintf('%.4g',vmax)}];   %#ok<AGROW>
                        if imin ~= imax
                            pts  = [pts;  tipPts(imin,:)];           %#ok<AGROW>
                            lbls = [lbls; {sprintf('%.4g',vmin)}];   %#ok<AGROW>
                        end
                    end

                case 'all'
                    pts  = tipPts;
                    lbls = arrayfun(@(x) sprintf('%.4g',x), vals, 'UniformOutput', false);
            end

            if isempty(pts), return; end
            lbl.points   = pts;
            lbl.labels   = lbls;
            lbl.color    = [0.1 0.1 0.1];
            lbl.fontSize = obj.Opts.labelFontSize;
            obj.Handles.Labels = obj.Plotter.addNodeLabels(lbl);
        end

        function mode = resolveLabelMode(obj)
            v = obj.Opts.showMaxMinLabel;
            if islogical(v) || (isnumeric(v) && isscalar(v))
                if v, mode = 'global'; else, mode = 'none'; end
                return;
            end
            mode = lower(strtrim(char(string(v))));
            if ~ismember(mode, {'none','global','element','all'})
                mode = 'global';
            end
        end

        function tf = shouldAnnotate(obj, nEle)
            mode = obj.resolveLabelMode();
            tf = ~strcmp(mode, 'none');
            if ~tf
                return;
            end

            if obj.Opts.performance.fastMode
                tf = strcmp(mode, 'global');
                return;
            end

            maxElementLabels = obj.Opts.performance.maxElementLabels;
            if isnumeric(maxElementLabels) && isscalar(maxElementLabels) && ...
               isfinite(maxElementLabels) && nEle > maxElementLabels && ...
               ismember(mode, {'element','all'})
                tf = false;
            end
        end

        % =================================================================
        % Response data  (handles struct layout: field.data / field.dofs)
        % =================================================================

        function arr = getRespData(obj, fieldName)
            % Returns the raw numeric array for a response field.
            %   (A) frameResp.<field>          plain numeric array  (legacy)
            %   (B) frameResp.<field>.data     numeric array        (struct wrapper)
            %   (C) frameResp.<field>.<dof>    per-DOF arrays       (current)
            if ~isfield(obj.FrameResp, fieldName)
                arr = [];  return;
            end
            entry = obj.FrameResp.(fieldName);
            if isstruct(entry)
                if isfield(entry,'data')
                    arr = entry.data;          % Layout B
                else
                    % Layout C: per-DOF struct → reconstruct along last dim
                    fn = fieldnames(entry);
                    if isempty(fn), arr = []; return; end
                    parts = cellfun(@(f) entry.(f), fn, 'UniformOutput', false);
                    if ~all(cellfun(@isnumeric, parts)), arr = []; return; end
                    nd  = ndims(parts{1});
                    arr = cat(nd + 1, parts{:});
                end
            else
                arr = entry;
            end
        end

        function dofs = getRespDofs(obj, fieldName)
            % Returns the dof label cell array for a response field.
            dofs = {};
            if ~isfield(obj.FrameResp, fieldName), return; end
            entry = obj.FrameResp.(fieldName);
            if ~isstruct(entry), return; end
            if isfield(entry,'dofs')
                dofs = entry.dofs;           % Layout B
            elseif ~isfield(entry,'data')
                dofs = fieldnames(entry).';  % Layout C
            end
        end

        function v = respFlat(obj, stepIdx)
            perEle = obj.respPerEle(stepIdx);
            if isempty(perEle), v = zeros(0,1); return; end
            v = vertcat(perEle{:});
        end

        function perEle = respPerEle(obj, stepIdx)
            beamTags = obj.getBeamTags(stepIdx);
            if isempty(beamTags)
                nEle = obj.nEles();
            else
                nEle = numel(beamTags);
            end
            perEle = cell(nEle,1);
            rt     = obj.normalizeRespType(obj.Opts.respType);
            comp   = char(string(obj.Opts.component));

            A  = obj.getRespData(rt);
            if isempty(A)
                for e=1:nEle, perEle{e}=zeros(0,1); end
                return;
            end

            si = min(stepIdx, size(A,1));
            ci = obj.compIdx(rt, comp, obj.getRespDofs(rt));
            nd = ndims(A);
            respRows = obj.getFrameRespRows(stepIdx, beamTags);

            if nd == 3
                % [nStep x nEle x nComp]
                D = squeeze(double(A(si,:,:)));
                if isvector(D), D = D(:).'; end
                for e = 1:nEle
                    row = obj.getRespRowIndex(respRows, e);
                    if row<1 || row>size(D,1)
                        perEle{e} = 0;
                    elseif ci>0 && ci<=size(D,2)
                        perEle{e} = D(row,ci);
                    else
                        perEle{e} = 0;
                    end
                end

            elseif nd == 4
                % [nStep x nEle x nSec x nComp]
                D = squeeze(double(A(si,:,:,:)));
                for e = 1:nEle
                    row = obj.getRespRowIndex(respRows, e);
                    if row<1 || row>size(D,1)
                        perEle{e} = zeros(0,1);
                        continue;
                    end
                    sec = squeeze(D(row,:,:));
                    if isvector(sec), sec=sec(:); end
                    if ci>0 && ci<=size(sec,2)
                        vv = sec(:,ci);
                        perEle{e} = vv(isfinite(vv));
                    else
                        perEle{e} = zeros(0,1);
                    end
                end
            end

            for e=1:nEle
                if isempty(perEle{e}), perEle{e}=zeros(0,1); end
            end
        end

        function perEle = secLocs(obj, stepIdx)
            beamTags = obj.getBeamTags(stepIdx);
            if isempty(beamTags)
                nEle = obj.nEles();
            else
                nEle = numel(beamTags);
            end
            perEle = cell(nEle,1);
            respForUniform = [];

            function locs = uniform(e_)
                if isempty(respForUniform)
                    respForUniform = obj.respPerEle(stepIdx);
                end
                n_ = max(numel(respForUniform{e_}),2);
                locs = linspace(0,1,n_).';
            end

            L = obj.getRespData('sectionLocs');
            if isempty(L)
                for e=1:nEle, perEle{e}=uniform(e); end
                return;
            end

            nd = ndims(L);
            respRows = obj.getFrameRespRows(stepIdx, beamTags);

            if nd == 4
                % [nStep x nEle x nSec x nLocDof]  – use first loc channel (alpha=xi)
                si = min(stepIdx, size(L,1));
                D  = squeeze(double(L(si,:,:,1)));   % [nEle x nSec]
            elseif nd == 3
                if size(L,1)>1 && size(L,1)==obj.nSteps()
                    si = min(stepIdx,size(L,1));
                    D  = squeeze(double(L(si,:,:)));
                else
                    D  = squeeze(double(L(:,:,1)));
                end
            elseif nd == 2
                D = double(L);
            else
                for e=1:nEle, perEle{e}=uniform(e); end
                return;
            end

            if isvector(D), D=D(:).'; end

            for e = 1:nEle
                row = obj.getRespRowIndex(respRows, e);
                if row<1 || row>size(D,1)
                    continue;
                end
                vv = squeeze(D(row,:)).';
                vv = vv(isfinite(vv));
                perEle{e} = vv;
            end
            for e=1:nEle
                if isempty(perEle{e}), perEle{e}=uniform(e); end
            end
        end

        function ci = compIdx(~, respType, comp, dofs)
            % Priority 1: match against .dofs labels from the data struct.
            % Priority 2: fall back to hard-coded maps.
            if nargin < 4, dofs = {}; end
            comp = upper(strtrim(char(comp)));

            % Search .dofs first
            for d = 1:numel(dofs)
                if strcmpi(dofs{d}, comp)
                    ci = d;  return;
                end
            end

            % Hard-coded fallback maps
            maps.sectionForces       = {'N','MZ','VY','MY','VZ','T'};
            maps.sectionDeformations = {'N','MZ','VY','MY','VZ','T'};
            maps.basicForces         = {'N','MZ','MY','T'};
            maps.basicDeformations   = {'N','MZ','MY','T'};
            maps.plasticDeformation  = {'N','MZ','MY','T'};
            maps.localForces         = {'FX1','FY1','FZ1','MX1','MY1','MZ1', ...
                                        'FX2','FY2','FZ2','MX2','MY2','MZ2'};
            if isfield(maps, respType)
                idx = find(strcmpi(maps.(respType), comp), 1);
                if ~isempty(idx), ci=idx; return; end
            end

            n = str2double(comp);
            ci = max(1, round(double(~isnan(n))*n + isnan(n)));
        end

        % =================================================================
        % Diagram scale
        % =================================================================

        function sc = diagScale(obj, stepIdx)
            scaleMode = lower(strtrim(char(string(obj.Opts.scaleMode))));

            if strcmpi(scaleMode,'current')
                if isfinite(obj.DiagScaleCache) && obj.DiagScaleStep==stepIdx
                    sc=obj.DiagScaleCache; return;
                end
                v=obj.respFlat(stepIdx); v=v(isfinite(v));
                maxAbs=max(abs(v),[],'omitnan');
                if isempty(maxAbs)||~isfinite(maxAbs)||maxAbs<=0, maxAbs=1; end
                sc=(obj.Opts.heightFrac*obj.CachedModelSize/maxAbs)*obj.Opts.scale;
                obj.DiagScaleCache=sc; obj.DiagScaleStep=stepIdx; return;
            end

            if isfinite(obj.DiagScaleCache)&&isnan(obj.DiagScaleStep)
                sc=obj.DiagScaleCache; return;
            end
            maxAbs=0;
            for k=1:obj.nSteps()
                v=obj.respFlat(k); v=v(isfinite(v));
                if ~isempty(v), maxAbs=max(maxAbs,max(abs(v))); end
            end
            if maxAbs<=0, maxAbs=1; end
            sc=(obj.Opts.heightFrac*obj.CachedModelSize/maxAbs)*obj.Opts.scale;
            obj.DiagScaleCache=sc; obj.DiagScaleStep=NaN;
        end

        % =================================================================
        % Beam geometry
        % =================================================================

        function [axField, axSign] = resolvePlotAxisSpec(obj)
            rt   = lower(strtrim(char(string(obj.Opts.respType))));
            comp = upper(strtrim(char(string(obj.Opts.component))));
            switch rt
                case {'localforces','localforce'}
                    switch comp
                        case {'FX','FX1','FX2','FY','FY1','FY2','MX','MX1','MX2'}
                            axField='YAxis'; axSign=1.0;
                        case {'FZ','FZ1','FZ2'}
                            axField='ZAxis'; axSign=1.0;
                        case {'MY','MY1','MY2'}
                            axField='ZAxis'; axSign=-1.0;
                        case {'MZ','MZ1','MZ2'}
                            axField='YAxis'; axSign=-1.0;
                        otherwise
                            axField='YAxis'; axSign=1.0;
                    end
                case {'basicforces','basicforce', ...
                      'basicdeformations','basicdeformation', ...
                      'plasticdeformation','plasticdeformations'}
                    switch comp
                        case 'N',  axField='YAxis'; axSign=1.0;
                        case 'MZ', axField='YAxis'; axSign=-1.0;
                        case 'MY', axField='ZAxis'; axSign=-1.0;
                        case 'T',  axField='YAxis'; axSign=1.0;
                        otherwise, axField='YAxis'; axSign=1.0;
                    end
                otherwise
                    switch comp
                        case 'MZ',         axField='YAxis'; axSign=-1.0;
                        case {'N','VY','T'},axField='YAxis'; axSign=1.0;
                        case {'VZ','MY'},   axField='ZAxis'; axSign=1.0;
                        otherwise,         axField='YAxis'; axSign=1.0;
                    end
            end
        end

        function info = beamInfo(obj, stepIdx)
            info = struct('conn',zeros(0,2),'plotAxis',zeros(0,3),'tags',zeros(0,1));
            fam  = obj.families();
            if ~isfield(fam,'Beam'), return; end
            B = fam.Beam;
            if ~isfield(B,'Cells')||isempty(B.Cells), return; end

            cells = double(B.Cells);
            if obj.ModelUpdateFlag && ndims(cells)==3
                cells=squeeze(cells(min(stepIdx,size(cells,1)),:,:));
            end
            if isvector(cells)
                cells = reshape(cells, 1, []);
            end
            if ~ismatrix(cells)
                cells = reshape(cells, size(cells,1), []);
            end
            if isempty(cells) || size(cells,2)<2, return; end

            if isfield(B,'Tags') && ~isempty(B.Tags)
                tags = obj.trimVectorLength(obj.readStepVectorData(B.Tags, stepIdx), size(cells,1));
            else
                tags = (1:size(cells,1)).';
            end

            nCell = min(size(cells,1), numel(tags));
            if nCell == 0
                return;
            end
            cells = cells(1:nCell, :);
            tags = tags(1:nCell);

            keepRows = ~all(isnan(cells), 2);
            cells = cells(keepRows, :);
            tags = tags(keepRows);
            if isempty(cells), return; end

            [~, rawToClean] = obj.getNodeStepSelection(stepIdx);
            conn = round(cells(:,end-1:end));
            validConn = all(isfinite(conn), 2) & all(conn >= 1, 2) & all(conn <= numel(rawToClean), 2);
            conn = conn(validConn, :);
            tags = tags(validConn);
            if isempty(conn), return; end

            conn = rawToClean(conn);
            keepMapped = all(conn >= 1, 2);
            conn = conn(keepMapped, :);
            tags = tags(keepMapped);
            if isempty(conn), return; end

            info.conn=conn;
            info.tags=double(tags(:));
            nEle=size(conn,1);

            P = obj.nodeCoords(stepIdx);
            [axField,axSign]=obj.resolvePlotAxisSpec();

            if isfield(B,axField)&&~isempty(B.(axField))
                ax=double(B.(axField));
                if obj.ModelUpdateFlag&&ndims(ax)==3
                    ax=squeeze(ax(min(stepIdx,size(ax,1)),:,:));
                end
                ax = obj.trimAxisRows(ax, nCell);
                ax = ax(keepRows, :);
                ax = obj.trimAxisRows(ax, numel(validConn));
                ax = ax(validConn, :);
                ax = obj.trimAxisRows(ax, numel(keepMapped));
                ax = ax(keepMapped, :);
                info.plotAxis=zeros(nEle,3);
                n=min(size(ax,1),nEle);
                info.plotAxis(1:n,:)=axSign*ax(1:n,1:3);
                for e=1:n
                    ne=norm(info.plotAxis(e,:));
                    if ne>1e-14, info.plotAxis(e,:)=info.plotAxis(e,:)/ne; end
                end
            else
                info.plotAxis=zeros(nEle,3);
                useZ=strcmpi(axField,'ZAxis');
                for e=1:nEle
                    d=P(conn(e,2),:)-P(conn(e,1),:);
                    dn=norm(d); if dn<1e-14, continue; end
                    d=d/dn;
                    up=[0 0 1];
                    if abs(dot(d,up))>0.99, up=[0 1 0]; end
                    if useZ, ax=cross(d,cross(d,up));
                    else,    ax=cross(d,up); end
                    na=norm(ax);
                    if na>1e-14, ax=ax/na; else, ax=[0 1 0]; end
                    info.plotAxis(e,:)=axSign*ax;
                end
            end
        end

        % =================================================================
        % Topology
        % =================================================================

        function P = nodeCoords(obj, stepIdx)
            [P, ~] = obj.getNodeStepData(stepIdx);
        end

        function P = nodeCoordsRaw(obj, stepIdx)
            P=zeros(0,3);
            if ~isfield(obj.ModelInfo,'Nodes')||~isfield(obj.ModelInfo.Nodes,'Coords')
                return;
            end
            C=double(obj.ModelInfo.Nodes.Coords);
            if obj.ModelUpdateFlag&&ndims(C)==3
                P=squeeze(C(min(stepIdx,size(C,1)),:,:));
            else
                P=C;
            end
            if size(P,2)<3, P(:,3)=0;
            elseif size(P,2)>3, P=P(:,1:3); end
        end

        function [P, tags] = getNodeStepData(obj, stepIdx)
            P = obj.nodeCoordsRaw(stepIdx);
            tags = obj.getModelNodeTagsRaw(stepIdx, size(P,1));
            if isempty(P)
                tags = zeros(0,1);
                return;
            end
            [keepMask, ~] = obj.getNodeStepSelection(stepIdx, P, tags);
            P = P(keepMask, :);
            tags = tags(keepMask);
        end

        function [keepMask, rawToClean] = getNodeStepSelection(obj, stepIdx, P, tags)
            if nargin < 3 || isempty(P)
                P = obj.nodeCoordsRaw(stepIdx);
            end
            if nargin < 4 || isempty(tags)
                tags = obj.getModelNodeTagsRaw(stepIdx, size(P,1));
            end
            keepMask = obj.getNodeStepMask(stepIdx, P, tags);
            rawToClean = zeros(size(keepMask));
            rawToClean(keepMask) = 1:nnz(keepMask);
        end

        function keepMask = getNodeStepMask(obj, stepIdx, P, tags)
            if nargin < 3 || isempty(P)
                P = obj.nodeCoordsRaw(stepIdx);
            end
            if nargin < 4 || isempty(tags)
                tags = obj.getModelNodeTagsRaw(stepIdx, size(P,1));
            end
            keepMask = ~all(isnan(P), 2);
            unusedTags = obj.getUnusedNodeTags();
            if isempty(unusedTags) || isempty(tags)
                return;
            end
            tags = obj.trimVectorLength(tags, numel(keepMask));
            keepMask = keepMask & ~ismember(tags, unusedTags);
        end

        function tags = getModelNodeTagsRaw(obj, stepIdx, nRow)
            if nargin < 3, nRow = []; end
            tags = [];
            if ~isfield(obj.ModelInfo,'Nodes') || ~isfield(obj.ModelInfo.Nodes,'Tags') || isempty(obj.ModelInfo.Nodes.Tags)
                return;
            end
            tags = obj.readStepVectorData(obj.ModelInfo.Nodes.Tags, stepIdx);
            if ~isempty(nRow)
                tags = obj.trimVectorLength(tags, nRow);
            end
        end

        function tags = getUnusedNodeTags(obj)
            tags = [];
            if ~isfield(obj.ModelInfo,'Nodes') || ~isfield(obj.ModelInfo.Nodes,'UnusedTags') || isempty(obj.ModelInfo.Nodes.UnusedTags)
                return;
            end
            tags = double(obj.ModelInfo.Nodes.UnusedTags(:));
            tags = unique(tags(isfinite(tags)));
        end

        function tags = getBeamTags(obj, stepIdx)
            tags = [];
            fam = obj.families();
            if ~isfield(fam,'Beam')
                return;
            end

            B = fam.Beam;
            if ~isfield(B,'Cells') || isempty(B.Cells)
                return;
            end

            cells = double(B.Cells);
            if obj.ModelUpdateFlag && ndims(cells) == 3
                cells = squeeze(cells(min(stepIdx, size(cells,1)), :, :));
            end
            if isvector(cells)
                cells = reshape(cells, 1, []);
            end
            if ~ismatrix(cells)
                cells = reshape(cells, size(cells,1), []);
            end
            if isempty(cells) || size(cells,2) < 2
                return;
            end

            if isfield(B,'Tags') && ~isempty(B.Tags)
                tags = obj.trimVectorLength(obj.readStepVectorData(B.Tags, stepIdx), size(cells,1));
            else
                tags = (1:size(cells,1)).';
            end

            nCell = min(size(cells,1), numel(tags));
            if nCell == 0
                tags = zeros(0,1);
                return;
            end
            cells = cells(1:nCell, :);
            tags = tags(1:nCell);

            keepRows = ~all(isnan(cells), 2);
            cells = cells(keepRows, :);
            tags = tags(keepRows);
            if isempty(cells)
                tags = zeros(0,1);
                return;
            end

            [~, rawToClean] = obj.getNodeStepSelection(stepIdx);
            conn = round(cells(:, end-1:end));
            validConn = all(isfinite(conn), 2) & all(conn >= 1, 2) & all(conn <= numel(rawToClean), 2);
            conn = conn(validConn, :);
            tags = tags(validConn);
            if isempty(conn)
                tags = zeros(0,1);
                return;
            end

            conn = rawToClean(conn);
            keepMapped = all(conn >= 1, 2);
            tags = tags(keepMapped);
            tags = tags(isfinite(tags));
        end

        function rows = getFrameRespRows(obj, stepIdx, beamTags)
            rows = [];
            if ~obj.ModelUpdateFlag || ~isfield(obj.FrameResp,'eleTags') || isempty(obj.FrameResp.eleTags)
                return;
            end
            if nargin < 3 || isempty(beamTags)
                beamTags = obj.getBeamTags(stepIdx);
            end
            if isempty(beamTags)
                return;
            end
            [tf, loc] = ismember(double(beamTags(:)), double(obj.FrameResp.eleTags(:)));
            rows = zeros(numel(beamTags), 1);
            rows(tf) = loc(tf);
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
                modelRowsUsed = unique(round(modelRowsUsed), 'stable');
            end
        end

        function row = getRespRowIndex(~, rows, idx)
            row = idx;
            if isempty(rows)
                return;
            end
            if idx > numel(rows)
                row = 0;
                return;
            end
            row = rows(idx);
        end

        function fam = families(obj)
            fam=struct();
            if ~isfield(obj.ModelInfo,'Elements'), return; end
            E=obj.ModelInfo.Elements;
            if isfield(E,'Families'), fam=E.Families;
            else, fam=E; end
        end

        function n = nSteps(obj)
            if isfield(obj.FrameResp,'time')&&~isempty(obj.FrameResp.time)
                n=numel(obj.FrameResp.time); return;
            end
            % Scan fields; unwrap struct layout
            for fn=fieldnames(obj.FrameResp).'
                A=obj.FrameResp.(fn{1});
                if isstruct(A)&&isfield(A,'data'), A=A.data; end
                if isnumeric(A)&&ndims(A)>=3, n=size(A,1); return; end
            end
            n=1;
        end

        function n = nEles(obj)
            if isfield(obj.FrameResp,'eleTags')
                n=numel(obj.FrameResp.eleTags); return;
            end
            for fn=fieldnames(obj.FrameResp).'
                A=obj.FrameResp.(fn{1});
                if isstruct(A)&&isfield(A,'data'), A=A.data; end
                if isnumeric(A)&&ndims(A)>=3, n=size(A,2); return; end
            end
            n=0;
        end

        % =================================================================
        % Step resolution
        % =================================================================

        function si = resolveStep(obj, si)
            if isnumeric(si)
                si = round(si);
                si = si + 1; % Convert from 0-based to 1-based index
                si=max(1,min(obj.nSteps(),round(si))); return;
            end

            key = obj.normalizeStepSelector(si);
            if isfield(obj.PeakCache,key)&&~isempty(obj.PeakCache.(key))
                si=obj.PeakCache.(key); return;
            end

            vals = obj.peakStepValues(key);
            if isempty(vals)
                si = 1;
                obj.PeakCache.(key)=si;
                return;
            end

            switch key
                case {'absmax','max'}
                    [~,si]=max(vals, [], 'omitnan');
                case {'absmin','min'}
                    [~,si]=min(vals, [], 'omitnan');
                otherwise
                    error('PlotFrameResp:BadStep', ...
                        'Unknown key "%s". Use absmax|absmin|max|min or stepMax-style aliases.',key);
            end

            if isempty(si) || ~isfinite(si)
                si = 1;
            end
            obj.PeakCache.(key)=si;
        end

        function vals = peakStepValues(obj, key)
            vals = obj.peakStepValuesFast(key);
            if isempty(vals)
                vals = obj.peakStepValuesSlow(key);
            end
        end

        function vals = peakStepValuesFast(obj, key)
            vals = [];

            % Keep model-update cases on the conservative path because active
            % element rows can change by step.
            if obj.ModelUpdateFlag
                return;
            end

            rt   = obj.normalizeRespType(obj.Opts.respType);
            comp = char(string(obj.Opts.component));
            A    = obj.getRespData(rt);
            if isempty(A)
                return;
            end

            D = obj.selectRespComponentAllSteps(A, rt, comp);
            if isempty(D)
                return;
            end

            D = double(D);
            if isempty(D) || size(D,1) == 0
                return;
            end

            M = reshape(D, size(D,1), []);
            M(~isfinite(M)) = NaN;

            switch key
                case {'absmax','absmin'}
                    vals = max(abs(M), [], 2, 'omitnan');
                case 'max'
                    vals = max(M, [], 2, 'omitnan');
                case 'min'
                    vals = min(M, [], 2, 'omitnan');
                otherwise
                    vals = [];
                    return;
            end

            vals = vals(:);
            if all(~isfinite(vals))
                vals = [];
            end
        end

        function vals = peakStepValuesSlow(obj, key)
            n = obj.nSteps();
            vals = obj.initStepSelectorValues(key, n);

            for k=1:n
                v=obj.respFlat(k); v=v(isfinite(v));
                if isempty(v), continue; end
                switch key
                    case {'absmax','absmin'}, vals(k)=max(abs(v), [], 'omitnan');
                    case 'max',              vals(k)=max(v, [], 'omitnan');
                    case 'min',              vals(k)=min(v, [], 'omitnan');
                    otherwise
                        error('PlotFrameResp:BadStep', ...
                            'Unknown key "%s". Use absmax|absmin|max|min or stepMax-style aliases.',key);
                end
            end

            vals = vals(:);
            if all(~isfinite(vals))
                vals = [];
            end
        end

        function D = selectRespComponentAllSteps(obj, A, rt, comp)
            D = [];
            ci = obj.compIdx(rt, comp, obj.getRespDofs(rt));
            nd = ndims(A);

            if nd == 3
                % [nStep x nEle x nComp]
                if ci > 0 && ci <= size(A,3)
                    D = A(:,:,ci);
                end
            elseif nd == 4
                % [nStep x nEle x nSec x nComp]
                if ci > 0 && ci <= size(A,4)
                    D = A(:,:,:,ci);
                end
            end
        end

        function rt = normalizeRespType(obj, rt)
            % Case-insensitive match against actual FrameResp field names.
            rt = char(rt);
            if isfield(obj.FrameResp, rt), return; end
            fn = fieldnames(obj.FrameResp);
            match = fn(strcmpi(fn, rt));
            if ~isempty(match), rt = match{1}; return; end
            % Fallback: match against known resp type names.
            known = {'localForces','basicForces','basicDeformations', ...
                     'plasticDeformation','sectionForces','sectionDeformations','sectionLocs'};
            match = known(strcmpi(known, rt));
            if ~isempty(match), rt = match{1}; end
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

        function ax = trimAxisRows(~, ax, nRow)
            if isempty(ax)
                ax = zeros(0,3);
                return;
            end
            if size(ax,2) < 3
                ax(:,3) = 0;
            elseif size(ax,2) > 3
                ax = ax(:,1:3);
            end
            if size(ax,1) < nRow
                ax(end+1:nRow,:) = NaN;
            elseif size(ax,1) > nRow
                ax = ax(1:nRow,:);
            end
        end

        % =================================================================
        % Axes decoration
        % =================================================================

        function prepAxes(obj)
            sz=obj.Opts.general.figureSize;
            if isnumeric(sz)&&numel(sz)==2&&all(sz>0)
                fig=ancestor(obj.Ax,'figure');
                fig.Units='pixels'; pos=fig.Position; pos(3:4)=sz;
                fig.Position=pos;
            end
            if obj.Opts.general.clearAxes
                cla(obj.Ax,'reset'); hold(obj.Ax,'on');
            elseif obj.Opts.general.holdOn
                hold(obj.Ax,'on');
            end
            if obj.Opts.general.axisEqual, axis(obj.Ax,'equal'); end
            if obj.Opts.general.grid, grid(obj.Ax,'on');
            else, grid(obj.Ax,'off'); end
            if obj.Opts.general.box, box(obj.Ax,'on');
            else, box(obj.Ax,'off'); end
            colormap(obj.Ax,obj.Opts.color.colormap);
        end

        function applyView(obj)
            v=lower(char(string(obj.Opts.general.view)));
            if strcmp(v,'auto')
                if obj.CachedModelDim==2, view(obj.Ax,2);
                else, view(obj.Ax,3); end
                return;
            end
            switch v
                case 'iso', view(obj.Ax,3);
                case 'xy',  view(obj.Ax,2);
                case 'xz',  view(obj.Ax,0,0);
                otherwise
                    if obj.CachedModelDim==2, view(obj.Ax,2);
                    else, view(obj.Ax,3); end
            end
        end

        function applyTitle(obj, stepIdx)
            t=string(obj.Opts.general.title);
            if strcmpi(t,'auto')
                if isfield(obj.FrameResp,'time')&&numel(obj.FrameResp.time)>=stepIdx
                    tval=obj.FrameResp.time(stepIdx);
                else
                    tval=NaN;
                end
                title(obj.Ax, sprintf('%s  %s  |  step %d  |  t = %.4g s', ...
                    char(string(obj.Opts.respType)), ...
                    char(string(obj.Opts.component)), stepIdx-1, tval));
            elseif strlength(t)>0
                title(obj.Ax,char(t));
            end
        end

        function applyColorbar(obj)
            if ~obj.Opts.color.useColormap||~obj.Opts.cbar.show
                colorbar(obj.Ax,'off'); return;
            end
            [cmin,cmax]=obj.colorLimits([]);
            clim(obj.Ax,obj.climVal(cmin,cmax));
            cb=colorbar(obj.Ax);
            cb.FontSize=11; cb.TickDirection='in';
            cb.Title.String='';
            cb.Label.String=obj.colorbarSideTitle();
            cb.Label.FontSize=13;
            cb.Label.FontWeight='normal';
        end

        function txt = colorbarSideTitle(obj)
            respTitle = sprintf('%s | %s', ...
                char(string(obj.Opts.respType)), char(string(obj.Opts.component)));
            extraLabel = string(obj.Opts.cbar.label);
            if strlength(strtrim(extraLabel))>0
                txt = sprintf('%s | %s', respTitle, char(extraLabel));
            else
                txt = respTitle;
            end
        end

        function cv = climVal(obj, cmin, cmax)
            if ~isempty(obj.Opts.color.clim)&&numel(obj.Opts.color.clim)==2
                cv=obj.Opts.color.clim;
            else
                cv=[cmin cmax];
            end
        end

        function [cmin, cmax] = colorLimits(obj, vals)
            if ~isempty(obj.Opts.color.clim) && numel(obj.Opts.color.clim) == 2
                cmin = obj.Opts.color.clim(1);
                cmax = obj.Opts.color.clim(2);
                return;
            end

            mode = lower(strtrim(char(string(obj.Opts.color.climMode))));
            useCurrent = strcmp(mode, 'current') || obj.Opts.performance.fastMode;

            if useCurrent && nargin >= 2 && ~isempty(vals)
                v = vals(isfinite(vals));
                if isempty(v)
                    cmin = 0; cmax = 1;
                else
                    cmin = min(v);
                    cmax = max(v);
                    if cmin == cmax, cmax = cmin + 1; end
                end
                obj.CurrentClimCache = [cmin cmax];
                return;
            end

            if useCurrent && ~isempty(obj.CurrentClimCache)
                cmin = obj.CurrentClimCache(1);
                cmax = obj.CurrentClimCache(2);
                return;
            end

            [cmin, cmax] = obj.globalClim();
        end

        % =================================================================
        % Utilities
        % =================================================================

        function idx = sectionSampleIndex(obj, n)
            if n <= 0
                idx = zeros(0,1);
                return;
            end

            maxN = obj.Opts.performance.maxSectionsPerElement;
            if ~(isnumeric(maxN) && isscalar(maxN) && isfinite(maxN) && maxN >= 2) || n <= maxN
                idx = (1:n).';
                return;
            end

            idx = unique(round(linspace(1, n, maxN))).';
            if idx(1) ~= 1
                idx = [1; idx(:)];
            end
            if idx(end) ~= n
                idx = [idx(:); n];
            end
        end

        function dim = modelDim(~, P)
            if isempty(P)||size(P,2)<3, dim=2; return; end
            z=P(:,3);
            if all(isnan(z)|abs(z)<1e-12), dim=2; else, dim=3; end
        end

        function L = modelSize(~, P)
            if isempty(P), L=1; return; end
            ext=max(P,[],1,'omitnan')-min(P,[],1,'omitnan');
            ext=ext(isfinite(ext));
            if isempty(ext), L=1; return; end
            L=max(ext);
            if ~isfinite(L)||L<=0, L=1; end
        end

        function out = merge(obj, base, add) %#ok<INUSL>
            out=base;
            if isempty(add)||~isstruct(add), return; end
            for fn=fieldnames(add).'
                n=fn{1};
                if isfield(out,n)&&isstruct(out.(n))&&isstruct(add.(n))
                    out.(n)=obj.merge(out.(n),add.(n));
                else
                    out.(n)=add.(n);
                end
            end
        end

    end
end
