classdef PlotEigen < handle
    % PlotEigen  Modal shape visualisation built on PatchPlotter.
    %
    % Concepts
    % --------
    %   plotOrigin()        Draw the undeformed structure.
    %   plotMode(modeTag)   Draw a scaled, optionally coloured mode shape.
    %
    % Line geometry  : raw nodal deformation, or Hermite-interpolated when
    %                  InterpolatedEigenVectors is present and
    %                  opts.mode.useInterpolation = true.
    % Surface/solid  : always from ModelInfo.Elements.Families.Unstructured,
    %                  deformed by nodal eigenvectors.
    %
    % Quick start
    % -----------
    %   pe = plotter.PlotEigen(modelInfo, eigenInfo);
    %   pe.plotOrigin();
    %   pe.plotMode(1);

    % =====================================================================
    properties
        ModelInfo   struct
        EigenInfo   struct
        Plotter     plotter.PatchPlotter
        Ax          matlab.graphics.axis.Axes
        Opts        struct
        Handles     struct = struct()
    end

    properties (Access = private)
        CachedNodeCoords    double = zeros(0, 3)
        CachedBounds        double = nan(1, 6)
        CachedModelDim      double = 3
        CachedModelSize     double = 1
        CachedLineConn      double = zeros(0, 2)
        CachedUnstru        struct = struct()

        NodeTagToIdxArray   double = []
        NodeTagToIdxMap            = []
    end

    % =====================================================================
    methods (Static)

        function opts = defaultOptions()
            opts = struct();

            opts.general = struct( ...
                'clearAxes', true,   ...
                'holdOn',    true,   ...
                'axisEqual', true,   ...
                'grid',      true,   ...
                'box',       false,  ...
                'view',      'auto', ...
                'title',     '',     ...
                'padRatio',  0.05,   ...
                'fixAxisLimits', false, ...
                'figureSize', [1000, 618]);

            opts.mode = struct( ...
                'modeTag',          1,           ...
                'scale',            1,           ...
                'autoScale',        true,        ...
                'useInterpolation', true,        ...
                'showUndeformed',   false,       ...
                'component',        'magnitude');

            opts.color = struct( ...
                'useColormap',     false,             ...
                'colormap',        jet(256),          ...
                'clim',            [],                ...
                'solidColor',      '#0504aa',         ...
                'lineColor',       '#0504aa',         ...
                'undeformedColor', "#d8dcd6",  ...
                'undeformedAlpha', 1.00,              ...
                'deformedAlpha',   1.00);

            opts.line = struct( ...
                'show',                true,  ...
                'lineWidth',           1.5,   ...
                'undeformedLineWidth', 0.8,   ...
                'lineStyle',           '-');

            opts.unstructured = struct( ...
                'show',      true,    ...
                'showEdges', true,    ...
                'edgeColor', 'black', ...
                'edgeWidth', 0.8);

            opts.scalar = struct( ...
                'showColorbar',            true, ...
                'useAbsoluteForComponent', true);

            opts.nodes = struct( ...
                'show',      false,   ...
                'size',      20,      ...
                'marker',    'o',     ...
                'filled',    true,    ...
                'edgeColor', 'black');

            opts.fixed = struct( ...
                'show',      true,      ...
                'size',      46,        ...
                'marker',    's',       ...
                'filled',    true,      ...
                'edgeColor', '#000000', ...
                'color',     '#8c000f');

            opts.mpConstraint = struct( ...
                'show',      false,      ...
                'lineWidth', 1.2,       ...
                'lineStyle', '--',      ...
                'color',     '#a24857');

            opts.performance = struct( ...
                'maxDenseLookupTag', 5e6);
        end

    end % static methods

    % =====================================================================
    methods

        function obj = PlotEigen(modelInfo, eigenInfo, ax, opts)
            if nargin < 1 || isempty(modelInfo)
                error('PlotEigen:InvalidInput', 'modelInfo must be provided.');
            end
            if nargin < 2 || isempty(eigenInfo)
                error('PlotEigen:InvalidInput', 'eigenInfo must be provided.');
            end
            if nargin < 3, ax   = []; end
            if nargin < 4, opts = []; end

            obj.ModelInfo = modelInfo;
            obj.EigenInfo = eigenInfo;
            obj.Opts      = obj.mergeStruct(plotter.PlotEigen.defaultOptions(), opts);
            obj.Plotter   = plotter.PatchPlotter(ax);
            obj.Ax        = obj.Plotter.Ax;
            obj.buildCaches();
        end

        function ax = getAxes(obj), ax = obj.Ax; end

        function setOptions(obj, opts)
            if nargin >= 2 && ~isempty(opts)
                obj.Opts = obj.mergeStruct(obj.Opts, opts);
                obj.buildCaches();
            end
        end

        % -----------------------------------------------------------------
        function h = plotOrigin(obj, opts)
            if nargin >= 2 && ~isempty(opts)
                obj.Opts = obj.mergeStruct(obj.Opts, opts);
                obj.buildCaches();
            end
            obj.prepareAxes();
            obj.Handles = struct();

            if obj.Opts.line.show
                obj.Handles.ShapeLine = obj.plotOriginLine();
            end
            if obj.Opts.unstructured.show
                obj.Handles.ShapeUnstructured = obj.plotOriginUnstructured();
            end

            obj.applyView();
            obj.applyDataLimits(obj.CachedNodeCoords);
            h = obj.Handles;
        end

        % -----------------------------------------------------------------
        function h = plotMode(obj, modeTag, opts)
            if nargin >= 2 && ~isempty(modeTag)
                obj.Opts.mode.modeTag = modeTag;
            end
            if nargin >= 3 && ~isempty(opts)
                obj.Opts = obj.mergeStruct(obj.Opts, opts);
            end

            obj.prepareAxes();
            obj.Handles = struct();
            modeIdx = obj.resolveModeIndex(obj.Opts.mode.modeTag);

            if obj.Opts.mode.showUndeformed
                if obj.Opts.line.show
                    obj.Handles.UndeformedLine = obj.plotOriginLine();
                end
                if obj.Opts.unstructured.show
                    obj.Handles.UndeformedUnstructured = obj.plotOriginUnstructured();
                end
            end

            if obj.Opts.line.show
                if obj.hasInterpolatedLines()
                    obj.Handles.ModeLine = obj.plotModeLineInterpolated(modeIdx);
                else
                    obj.Handles.ModeLine = obj.plotModeLineRaw(modeIdx);
                end
            end

            if obj.Opts.unstructured.show
                obj.Handles.ModeUnstructured = obj.plotModeUnstructured(modeIdx);
            end
            if obj.Opts.nodes.show
                obj.Handles.ModeNodes = obj.plotModeNodes(modeIdx);
            end

            obj.plotFixedNodes(modeIdx);
            obj.plotMPConstraints(modeIdx);

            obj.applyView();
            % obj.applyColorbar(modeIdx);
            obj.applyDataLimitsForMode(modeIdx);
            obj.applyTitle(modeIdx);
            h = obj.Handles;
        end

    end % public methods

    % =====================================================================
    methods (Access = private)

        % =================================================================
        % Cache construction
        % =================================================================

        function buildCaches(obj)
            P = obj.getNodeCoordsRaw();
            if isempty(P),    P = zeros(0,3); end
            if size(P,2) < 3, P(:,3) = 0;    end

            obj.CachedNodeCoords = P;
            obj.CachedModelDim   = obj.computeModelDim(P);
            obj.CachedBounds     = obj.computeBounds(P);
            obj.CachedModelSize  = obj.computeModelLength(P);
            obj.CachedLineConn   = obj.buildLineConnectivity();

            obj.buildNodeLookup();
            obj.buildUnstructuredCache();
        end

        function buildNodeLookup(obj)
            obj.NodeTagToIdxArray = [];
            obj.NodeTagToIdxMap   = [];
            tags = obj.resolveNodeTags();
            if isempty(tags), return; end

            n      = numel(tags);
            maxTag = max(tags);
            if isfinite(maxTag) && maxTag >= 1 && ...
               maxTag <= obj.Opts.performance.maxDenseLookupTag && ...
               maxTag <= 20*n
                arr       = zeros(maxTag,1);
                arr(tags) = 1:n;
                obj.NodeTagToIdxArray = arr;
            else
                obj.NodeTagToIdxMap = containers.Map( ...
                    num2cell(tags), num2cell(1:n));
            end
        end

        function buildUnstructuredCache(obj)
            obj.CachedUnstru = struct();
            fam = obj.getFamilies();
            if ~isfield(fam,'Unstructured'), return; end
            U = fam.Unstructured;
            if ~isfield(U,'Cells')     || isempty(U.Cells),     return; end
            if ~isfield(U,'CellTypes') || isempty(U.CellTypes), return; end
            surfOut = plotter.utils.VTKElementTriangulator.triangulate( ...
                obj.CachedNodeCoords, double(U.CellTypes), double(U.Cells));
            if isempty(surfOut) || ~isfield(surfOut,'Points') || ...
               isempty(surfOut.Points), return; end
            obj.CachedUnstru = surfOut;
        end

        % =================================================================
        % Axes preparation
        % =================================================================

        function prepareAxes(obj)
            fig = ancestor(obj.Ax, 'figure');
            figSize = obj.Opts.general.figureSize;

            if isnumeric(figSize) && numel(figSize)==2 && ...
               all(isfinite(figSize)) && all(figSize>0)
                oldUnits = fig.Units;
                fig.Units = 'pixels';
                pos = fig.Position;
                pos(3) = figSize(1);  pos(4) = figSize(2);
                fig.Position = pos;
                fig.Units = oldUnits;
            end

            if obj.Opts.general.clearAxes
                cla(obj.Ax,'reset');  hold(obj.Ax,'on');
            elseif obj.Opts.general.holdOn
                hold(obj.Ax,'on');
            end
            if obj.Opts.general.axisEqual, axis(obj.Ax,'equal'); end
            if obj.Opts.general.grid,  grid(obj.Ax,'on');
            else,                      grid(obj.Ax,'off'); end
            if obj.Opts.general.box,   box(obj.Ax,'on');
            else,                      box(obj.Ax,'off');  end
            colormap(obj.Ax, obj.Opts.color.colormap);
        end

        % =================================================================
        % Drawing helpers
        % =================================================================

        function h = plotOriginLine(obj)
            h = gobjects(0);
            P = obj.CachedNodeCoords;  lines = obj.CachedLineConn;
            if isempty(P) || isempty(lines), return; end
            s.nodes     = P;
            s.lines     = lines;
            s.color     = obj.Opts.color.undeformedColor;
            s.lineWidth = obj.Opts.line.undeformedLineWidth;
            s.lineStyle = obj.Opts.line.lineStyle;
            s.tag       = 'UndeformedLine';
            h = obj.Plotter.addLine(s);
        end

        function h = plotOriginUnstructured(obj)
            h = gobjects(0);
            U = obj.CachedUnstru;
            if isempty(U) || ~isfield(U,'EdgePoints'), return; end
            s.points    = U.EdgePoints;
            s.color     = obj.Opts.color.undeformedColor;
            s.lineWidth = obj.Opts.line.undeformedLineWidth;
            s.tag       = 'UndeformedUnstructured';
            h = obj.Plotter.addLine(s);
        end

        function h = plotModeLineRaw(obj, modeIdx)
            h = gobjects(0);
            [Pdef, Snode] = obj.getDeformedNodalPoints(modeIdx);
            lines = obj.CachedLineConn;
            if isempty(Pdef) || isempty(lines), return; end
            s.nodes     = Pdef;
            s.lines     = lines;
            s.lineWidth = obj.Opts.line.lineWidth;
            s.lineStyle = obj.Opts.line.lineStyle;
            s.tag       = 'ModeLineRaw';
            h = obj.addLineWithColor(s, Snode);
        end

        function h = plotModeLineInterpolated(obj, modeIdx)
            h = gobjects(0);
            I = obj.EigenInfo.InterpolatedEigenVectors;
            if ~obj.isValidInterp(I), return; end

            P     = obj.padTo3Col(double(I.points));
            U     = obj.extractModeDisp(I.data, modeIdx);
            scale = obj.computeModeScale(modeIdx);
            Pdef  = P + scale * U;
            S     = obj.computeScalarField(U);
            lines = double(I.cells(:, 2:end));

            s.nodes     = Pdef;
            s.lines     = lines;
            s.lineWidth = obj.Opts.line.lineWidth;
            s.lineStyle = obj.Opts.line.lineStyle;
            s.tag       = 'ModeLineInterpolated';
            h = obj.addLineWithColor(s, S);
        end

        function h = plotModeUnstructured(obj, modeIdx)
            h = gobjects(0);
            fam = obj.getFamilies();
            if ~isfield(fam,'Unstructured'), return; end
            S0 = fam.Unstructured;
            if ~isfield(S0,'Cells') || isempty(S0.Cells), return; end

            [Pdef, Snode] = obj.getDeformedNodalPoints(modeIdx);
            surfOut = plotter.utils.VTKElementTriangulator.triangulate( ...
                Pdef, double(S0.CellTypes), double(S0.Cells));
            if isempty(surfOut) || ~isfield(surfOut,'Points') || ...
               isempty(surfOut.Points), return; end

            s.nodes     = double(surfOut.Points);
            s.tris      = double(surfOut.Triangles);
            s.faceAlpha = obj.Opts.color.deformedAlpha;
            s.tag       = 'ModeUnstructured';

            if obj.Opts.color.useColormap
                s.values = obj.mapScalarsByNN(s.nodes, Pdef, Snode);
                s.cmap   = obj.Opts.color.colormap;
                if ~isempty(obj.Opts.color.clim), s.clim = obj.Opts.color.clim; end
                h = obj.Plotter.addColoredMesh(s);
            else
                s.faceColor = obj.Opts.color.solidColor;
                h = obj.Plotter.addMesh(s);
            end

            if obj.Opts.unstructured.showEdges && ...
               isfield(surfOut,'EdgePoints') && ~isempty(surfOut.EdgePoints)
                w.points    = surfOut.EdgePoints;
                w.color     = obj.Opts.unstructured.edgeColor;
                w.lineWidth = obj.Opts.unstructured.edgeWidth;
                obj.Plotter.addLine(w);
            end
        end

        function h = plotModeNodes(obj, modeIdx)
            h = gobjects(0);
            [Pdef, Snode] = obj.getDeformedNodalPoints(modeIdx);
            if isempty(Pdef), return; end
            s.points    = Pdef;
            s.size      = obj.Opts.nodes.size;
            s.marker    = obj.Opts.nodes.marker;
            s.filled    = obj.Opts.nodes.filled;
            s.edgeColor = obj.Opts.nodes.edgeColor;
            s.tag       = 'ModeNodes';
            if obj.Opts.color.useColormap
                s.scalars = Snode;
                s.cmap    = obj.Opts.color.colormap;
                if ~isempty(obj.Opts.color.clim), s.clim = obj.Opts.color.clim; end
            else
                s.color = obj.Opts.color.solidColor;
            end
            h = obj.Plotter.addPoints(s);
        end

        function plotFixedNodes(obj, modeIdx)
            if ~obj.Opts.fixed.show, return; end
            if ~isfield(obj.ModelInfo,'Fixed') || ...
               ~isfield(obj.ModelInfo.Fixed,'NodeIndex') || ...
               isempty(obj.ModelInfo.Fixed.NodeIndex), return; end

            [Pdef, ~] = obj.getDeformedNodalPoints(modeIdx);
            if isempty(Pdef), return; end
            idx = obj.ModelInfo.Fixed.NodeIndex;
            idx = idx(idx >= 1 & idx <= size(Pdef,1));
            if isempty(idx), return; end

            s.points    = Pdef(idx,:);
            s.size      = obj.Opts.fixed.size;
            s.marker    = obj.Opts.fixed.marker;
            s.filled    = obj.Opts.fixed.filled;
            s.edgeColor = obj.Opts.fixed.edgeColor;
            s.color     = obj.Opts.fixed.color;
            s.tag       = 'FixedNodes';
            obj.Handles.Fixed = obj.Plotter.addPoints(s);
        end

        function plotMPConstraints(obj, modeIdx)
            if ~obj.Opts.mpConstraint.show, return; end
            if ~isfield(obj.ModelInfo,'MPConstraint'), return; end
            mp = obj.ModelInfo.MPConstraint;
            if ~isfield(mp,'Cells') || isempty(mp.Cells), return; end

            [Pdef, ~] = obj.getDeformedNodalPoints(modeIdx);
            s.nodes     = Pdef;
            s.lines     = mp.Cells(:, 2:end);
            s.color     = obj.Opts.mpConstraint.color;
            s.lineWidth = obj.Opts.mpConstraint.lineWidth;
            s.lineStyle = obj.Opts.mpConstraint.lineStyle;
            s.tag       = 'MPConstraint';
            obj.Handles.MPConstraint = obj.Plotter.addLine(s);
        end

        % =================================================================
        % Deformation helpers
        % =================================================================

        function [Pdef, Snode] = getDeformedNodalPoints(obj, modeIdx)
            P     = obj.CachedNodeCoords;
            U     = obj.getRawModeDisplacement(modeIdx);
            scale = obj.computeModeScale(modeIdx);
            Pdef  = P + scale * U;
            Snode = obj.computeScalarField(U);
        end

        function U = getRawModeDisplacement(obj, modeIdx)
            if ~isfield(obj.EigenInfo,'EigenVectors') || ...
               isempty(obj.EigenInfo.EigenVectors)
                error('PlotEigen:InvalidData','eigenInfo.EigenVectors is missing.');
            end
            E = obj.EigenInfo.EigenVectors;
            if ~isfield(E,'data') || isempty(E.data)
                error('PlotEigen:InvalidData','EigenVectors.data is empty.');
            end
            U = obj.extractModeDisp(E.data, modeIdx);
            if isempty(U), U = zeros(size(obj.CachedNodeCoords)); end
        end

        function U = extractModeDisp(~, data, modeIdx)
            U = squeeze(double(data(modeIdx,:,:)));
            U = plotter.PlotEigen.padTo3ColStatic(U);
        end

        function scaleVal = computeModeScale(obj, modeIdx)
            U    = obj.getRawModeDisplacement(modeIdx);
            umax = max(sqrt(sum(U.^2,2)),[],'omitnan');
            if isempty(umax) || ~isfinite(umax) || umax <= 0, umax = 1; end
            if obj.Opts.mode.autoScale
                scaleVal = obj.CachedModelSize / umax / 10;
            else
                scaleVal = 1;
            end
            scaleVal = scaleVal * obj.Opts.mode.scale;
        end

        function S = computeScalarField(obj, U)
            comp = lower(string(obj.Opts.mode.component));
            switch comp
                case {'magnitude','mag'}
                    S = sqrt(sum(U(:,1:min(3,size(U,2))).^2, 2));
                case {'x','ux'},  S = U(:,1);
                case {'y','uy'},  S = obj.safeCol(U,2);
                case {'z','uz'},  S = obj.safeCol(U,3);
                otherwise
                    S = sqrt(sum(U(:,1:min(3,size(U,2))).^2, 2));
            end
            if obj.Opts.scalar.useAbsoluteForComponent && ...
               ~ismember(comp, ["magnitude","mag"])
                S = abs(S);
            end
            S = double(S(:));
        end

        % =================================================================
        % Axes decoration
        % =================================================================

        function applyView(obj)
            v = lower(char(string(obj.Opts.general.view)));
            if strcmp(v,'auto')
                if obj.CachedModelDim==2, view(obj.Ax,2);
                else,                     view(obj.Ax,3); end
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
                    if obj.CachedModelDim==2, view(obj.Ax,2);
                    else,                     view(obj.Ax,3); end
            end
        end

        function applyTitle(obj, modeIdx)
            if strlength(string(obj.Opts.general.title)) > 0
                title(obj.Ax, char(string(obj.Opts.general.title)));  return;
            end
            if isempty(modeIdx)
                title(obj.Ax,'Model Shape');  return;
            end

            txt = sprintf('Mode %g', obj.getModeTag(modeIdx));

            if isfield(obj.EigenInfo,'ModalProps') && ...
               isfield(obj.EigenInfo.ModalProps,'raw') && ...
               ~isempty(obj.EigenInfo.ModalProps.raw)
                freqs = obj.EigenInfo.ModalProps.raw.eigenFrequency;
                if ~isempty(freqs) && numel(freqs) >= modeIdx
                    f = freqs(modeIdx);
                    if isfinite(f) && f > 0
                        txt = sprintf('%s  |  T = %.6g s', txt, 1/f);
                    end
                end
            end
            title(obj.Ax, txt);
        end

        function applyColorbar(obj, modeIdx)
            if ~obj.Opts.color.useColormap || ~obj.Opts.scalar.showColorbar || ...
               isempty(modeIdx)
                colorbar(obj.Ax,'off');  return;
            end
            if isempty(obj.Opts.color.clim)
                U = obj.getRawModeDisplacement(modeIdx);
                S = obj.computeScalarField(U);
                S = S(isfinite(S));
                if isempty(S), colorbar(obj.Ax,'off'); return; end
                smin = min(S);  smax = max(S);
                if smin == smax, smin = 0; smax = max(1,smax); end
                clim(obj.Ax, [smin smax]);
            else
                clim(obj.Ax, obj.Opts.color.clim);
            end
            cb               = colorbar(obj.Ax);
            cb.FontSize      = 10;
            cb.TickDirection = 'in';
        end

        function applyDataLimits(obj, P)
            if nargin < 2 || isempty(P), P = obj.CachedNodeCoords; end
            obj.Plotter.applyDataLimits(P, obj.Opts.general.padRatio);
            axis(obj.Ax,'auto');
        end

        function applyDataLimitsForMode(obj, modeIdx)
            [Pdef, ~] = obj.getDeformedNodalPoints(modeIdx);
            P = Pdef;
            if obj.hasInterpolatedLines()
                I    = obj.EigenInfo.InterpolatedEigenVectors;
                Pint = obj.padTo3Col(double(I.points));
                Uint = obj.extractModeDisp(I.data, modeIdx);
                P    = [P; Pint + obj.computeModeScale(modeIdx) * Uint];
            end
            obj.applyDataLimits(P);
        end

        % =================================================================
        % Geometry helpers
        % =================================================================

        function P = getNodeCoordsRaw(obj)
            P = zeros(0,3);
            if isfield(obj.ModelInfo,'Nodes') && isfield(obj.ModelInfo.Nodes,'Coords')
                P = double(obj.ModelInfo.Nodes.Coords);
            elseif isfield(obj.EigenInfo,'EigenVectors') && ...
               isfield(obj.EigenInfo.EigenVectors,'nodeCoords')
                P = double(obj.EigenInfo.EigenVectors.nodeCoords);
            end
        end

        function tags = resolveNodeTags(obj)
            tags = [];
            if isfield(obj.ModelInfo,'Nodes') && isfield(obj.ModelInfo.Nodes,'Tags')
                tags = double(obj.ModelInfo.Nodes.Tags(:));
            elseif isfield(obj.EigenInfo,'EigenVectors') && ...
               isfield(obj.EigenInfo.EigenVectors,'nodeTags')
                tags = double(obj.EigenInfo.EigenVectors.nodeTags(:));
            end
        end

        function fam = getFamilies(obj)
            fam = struct();
            if ~isfield(obj.ModelInfo,'Elements') || isempty(obj.ModelInfo.Elements)
                return;
            end
            E = obj.ModelInfo.Elements;
            if isfield(E,'Families'), fam = E.Families;
            else,                     fam = E;           end
        end

        function lines = buildLineConnectivity(obj)
            lines = zeros(0,2);
            fam   = obj.getFamilies();
            if ~isfield(fam,'Line') || ~isfield(fam.Line,'Cells') || ...
               isempty(fam.Line.Cells), return; end
            lines = obj.vtkLineCellsToConn(double(fam.Line.Cells));
        end

        function modeIdx = resolveModeIndex(obj, modeTag)
            if ~isfield(obj.EigenInfo,'ModeTags') || isempty(obj.EigenInfo.ModeTags)
                error('PlotEigen:InvalidData','eigenInfo.ModeTags is empty.');
            end
            tags    = double(obj.EigenInfo.ModeTags(:));
            modeTag = double(modeTag);
            modeIdx = find(tags == modeTag, 1, 'first');
            if isempty(modeIdx)
                if modeTag >= 1 && modeTag <= numel(tags) && mod(modeTag,1) == 0
                    modeIdx = modeTag;
                else
                    error('PlotEigen:ModeNotFound', ...
                        'Cannot find requested modeTag %g.', modeTag);
                end
            end
        end

        function tag = getModeTag(obj, modeIdx)
            tags = double(obj.EigenInfo.ModeTags(:));
            if modeIdx >= 1 && modeIdx <= numel(tags), tag = tags(modeIdx);
            else,                                       tag = modeIdx;       end
        end

        % =================================================================
        % Scalar mapping  (no Statistics / Text Analytics Toolbox needed)
        % =================================================================

        function Squery = mapScalarsByNN(~, queryPts, refPts, refScalars)
            % Chunked brute-force nearest-neighbour — no toolbox required.
            % Memory budget: ~50 MB per chunk (nR*3 doubles per query point).
            Squery = zeros(size(queryPts,1),1);
            if isempty(queryPts)||isempty(refPts)||isempty(refScalars), return; end
            qP = double(queryPts);  rP = double(refPts);
            nQ = size(qP,1);        nR = size(rP,1);
            idx = ones(nQ,1);
            chunkSize = max(1, floor(50e6 / (nR * 3)));
            for i = 1:chunkSize:nQ
                iEnd = min(i + chunkSize - 1, nQ);
                % d2: [chunkSize x nR] squared distances
                d2 = sum(bsxfun(@minus, ...
                    permute(qP(i:iEnd,:), [1 3 2]), ...
                    permute(rP,           [3 1 2])).^2, 3);
                [~, idx(i:iEnd)] = min(d2, [], 2);
            end
            Squery = double(refScalars(idx));
        end

        % =================================================================
        % Tag lookup  (batch Map query, no loop)
        % =================================================================

        function idx = nodeTagsToIdx(obj, nodeTags)
            nodeTags = double(nodeTags(:));
            idx      = zeros(numel(nodeTags),1);
            if isempty(nodeTags), return; end

            arr = obj.NodeTagToIdxArray;
            if ~isempty(arr)
                valid      = nodeTags >= 1 & nodeTags <= numel(arr) & ...
                             isfinite(nodeTags) & mod(nodeTags,1) == 0;
                idx(valid) = arr(nodeTags(valid));
                return;
            end

            mp = obj.NodeTagToIdxMap;
            if ~isempty(mp)
                keys   = num2cell(nodeTags);
                exists = isKey(mp, keys);
                if any(exists)
                    idx(exists) = cell2mat(values(mp, keys(exists)));
                end
            end
        end

        % =================================================================
        % Geometry utilities
        % =================================================================

        function conn = vtkLineCellsToConn(~, cells)
            conn = zeros(0,2);
            if isempty(cells), return; end
            cells = double(cells);

            if size(cells,2) == 2, conn = cells; return; end
            if size(cells,2)  < 3, return; end

            nnode = cells(:,1);
            if all(nnode == 2, 'all')
                conn = cells(:,2:3);  return;
            end

            valid = isfinite(nnode) & nnode >= 2;
            if ~any(valid), return; end
            cells = cells(valid,:);
            nnode = nnode(valid);
            nSeg  = sum(max(nnode-1, 0));
            conn  = zeros(nSeg,2);
            ncol  = size(cells,2);
            k     = 0;

            for i = 1:size(cells,1)
                ni  = nnode(i);
                row = cells(i, 2:min(1+ni,ncol));
                row = row(isfinite(row));
                m   = numel(row);
                if m < 2, continue; end
                conn(k+1:k+m-1,:) = [row(1:end-1)', row(2:end)'];
                k = k + m - 1;
            end
            conn = conn(1:k,:);
        end

        function dim = computeModelDim(~, P)
            if isempty(P)||size(P,2)<3, dim=2; return; end
            z = P(:,3);
            if all(isnan(z)|abs(z)<1e-12), dim=2; else, dim=3; end
        end

        function b = computeBounds(obj, P)
            b = nan(1,6);
            if isfield(obj.ModelInfo,'Nodes') && isfield(obj.ModelInfo.Nodes,'Bounds')
                raw = double(obj.ModelInfo.Nodes.Bounds);
                if numel(raw)==6 && all(isfinite(raw)), b=raw(:).'; return; end
            end
            if isempty(P), return; end
            if size(P,2)<3, P(:,3)=0; end
            mn = min(P,[],1,'omitnan');  mx = max(P,[],1,'omitnan');
            b  = [mn(1) mx(1) mn(2) mx(2) mn(3) mx(3)];
        end

        function L = computeModelLength(~, P)
            if isempty(P), L=1; return; end
            ext = max(P,[],1,'omitnan') - min(P,[],1,'omitnan');
            ext = ext(isfinite(ext));
            if isempty(ext), L=1; return; end
            L = max(ext);
            if ~isfinite(L)||L<=0, L=1; end
        end

        % =================================================================
        % Small shared helpers
        % =================================================================

        function h = addLineWithColor(obj, s, S)
            if obj.Opts.color.useColormap
                s.values = S;
                s.cmap   = obj.Opts.color.colormap;
                if ~isempty(obj.Opts.color.clim), s.clim = obj.Opts.color.clim; end
                h = obj.Plotter.addColoredLine(s);
            else
                s.color = obj.Opts.color.lineColor;
                h = obj.Plotter.addLine(s);
            end
        end

        function P = padTo3Col(~, P)
            if size(P,2)<3, P(:,3)=0;    end
            if size(P,2)>3, P=P(:,1:3);  end
        end

        function tf = hasInterpolatedLines(obj)
            if ~obj.Opts.mode.useInterpolation, tf=false; return; end
            if ~isfield(obj.EigenInfo,'InterpolatedEigenVectors'), tf=false; return; end
            tf = obj.isValidInterp(obj.EigenInfo.InterpolatedEigenVectors);
        end

        function tf = isValidInterp(~, I)
            tf = isstruct(I) && ...
                 isfield(I,'points') && ~isempty(I.points) && ...
                 isfield(I,'data')   && ~isempty(I.data)   && ...
                 isfield(I,'cells')  && ~isempty(I.cells);
        end

        function col = safeCol(~, U, j)
            if size(U,2)>=j, col=U(:,j);
            else,            col=zeros(size(U,1),1); end
        end

        function out = mergeStruct(obj, base, add) %#ok<INUSL>
            out = base;
            if isempty(add)||~isstruct(add), return; end
            f = fieldnames(add);
            for i = 1:numel(f)
                n = f{i};
                if isfield(out,n)&&isstruct(out.(n))&&isstruct(add.(n))
                    out.(n) = obj.mergeStruct(out.(n), add.(n));
                else
                    out.(n) = add.(n);
                end
            end
        end

    end % private methods

    % =====================================================================
    methods (Static, Access = private)

        function P = padTo3ColStatic(P)
            if size(P,2)<3, P(:,3)=0;    end
            if size(P,2)>3, P=P(:,1:3);  end
        end

    end % static private methods

end % classdef