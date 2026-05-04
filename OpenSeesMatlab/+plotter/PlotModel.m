classdef PlotModel < handle
    properties
        ModelInfo   struct
        Plotter     plotter.PatchPlotter
        Ax          matlab.graphics.axis.Axes
        Opts        struct
        Handles     struct = struct()
    end

    properties (Access = private)
        NodeCoords   double = zeros(0,3)
        ModelDim     double = 3
        Bounds       double = nan(1,6)
        AxisBaseLen  double = 1

        NodeIdxArray double = []
        NodeIdxMap           = []

        BeamIdxArray double = []
        BeamIdxMap           = []
        BeamXAxis    double = zeros(0,3)
        BeamYAxis    double = zeros(0,3)
        BeamZAxis    double = zeros(0,3)
    end

    methods (Static)
        function opts = defaultOptions()
            opts = struct();

            opts.general = struct( ...
                'clearAxes', true, ...
                'holdOn', true, ...
                'axisEqual', true, ...
                'grid', true, ...
                'box', false, ...
                'view', 'auto', ...
                'title', '', ...
                'padRatio', 0.05, ...
                'figureSize', [1000, 618]);

            opts.style = struct( ...
                'mode',           'byFamily', ...
                'lineColor',      '#444444', ...
                'shellColor',     '#00A6A6', ...
                'solidColor',     '#00B4D8', ...
                'wireframeColor', '#000000', ...
                'familyColors', struct( ...
                    'Truss',        '#FFBE0B', ...
                    'Beam',         '#0504aa', ...
                    'Link',         '#2A9D8F', ...
                    'Line',         '#666666', ...
                    'Plane',        '#00B4D8', ...
                    'Shell',        '#8338EC', ...
                    'Solid',        '#ada587', ...
                    'Contact',      '#8D6E63', ...
                    'MPConstraint', '#3A86FF', ...
                    'Fixed',        '#D62828', ...
                    'Node',         '#111111'));

            opts.nodes = struct( ...
                'show',             false, ...
                'size',             20, ...
                'marker',           'o', ...
                'filled',           true, ...
                'edgeColor',        '#000000', ...
                'color',            '#2F2F2F', ...
                'showLabels',       false, ...
                'labelOffsetScale', 0.01, ...
                'labelColor',       '#3d9973', ...
                'fontSize',         9);

            opts.elements = struct( ...
                'showBeam',             true, ...
                'showLink',             true, ...
                'showTruss',            true, ...
                'showPlane',            true, ...
                'showShell',            true, ...
                'showSolid',            true, ...
                'showContact',          true, ...
                'showWireframeOnFaces', true, ...
                'wireframeOnly',        false, ...
                'lineWidth',            1.5, ...
                'surfaceAlpha',         0.95, ...
                'wireframeLineWidth',   0.8, ...
                'showLabels',           false, ...
                'labelOffsetScale',     0.01, ...
                'labelColor',           '#c65102', ...
                'fontSize',             9);

            opts.fixed = struct( ...
                'show',      true, ...
                'size',      46, ...
                'marker',    's', ...
                'filled',    true, ...
                'edgeColor', '#000000', ...
                'color',     '#8c000f');

            opts.mpConstraint = struct( ...
                'show',      true, ...
                'lineWidth', 1.2, ...
                'lineStyle', '--', ...
                'color',     '#a24857');

            opts.localAxes = struct( ...
                'showBeam',   false, ...
                'showLink',   false, ...
                'axisXColor', 'red', ...
                'axisYColor', 'green', ...
                'axisZColor', 'blue', ...
                'scale',      0.04, ...
                'lineWidth',  1.2, ...
                'labelAxes',  false, ...
                'fontSize',   8);

            opts.loads = struct( ...
                'showNodal',        false, ...
                'showElement',      false, ...
                'showLabels',       false, ...
                'scale',            1.0, ...
                'baseFraction',     0.08, ...
                'lineWidth',        1.4, ...
                'nodalColor',       [0.85 0.20 0.20], ...
                'elementColor',     [0.10 0.60 0.20], ...
                'textColor',        [0.15 0.15 0.15], ...
                'fontSize',         10, ...
                'labelOffset',      [0 0.14 0], ...
                'nElementArrows',   15, ...
                'normalizeLength',  false, ...
                'minNorm',          1e-12);

            opts.outline = struct( ...
                'show',      false, ...
                'color',     [0.50 0.50 0.50], ...
                'lineStyle', ':', ...
                'lineWidth', 0.9);

            opts.summary = struct( ...
                'show',      true);

            opts.performance = struct( ...
                'maxDenseLookupTag', 5e6);
        end
    end

    methods
        function obj = PlotModel(modelInfo, ax, opts)
            if nargin < 1 || isempty(modelInfo)
                error('PlotModel:InvalidInput', 'modelInfo must be provided.');
            end
            if nargin < 2, ax = []; end
            if nargin < 3, opts = []; end

            obj.ModelInfo = modelInfo;
            obj.Opts      = obj.mergeStruct(plotter.PlotModel.defaultOptions(), opts);
            obj.Plotter   = plotter.PatchPlotter(ax);
            obj.Ax        = obj.Plotter.Ax;

            obj.buildCaches();
        end

        function ax = getAxes(obj)
            ax = obj.Ax;
        end

        function h = plot(obj, opts)
            if nargin >= 2 && ~isempty(opts)
                obj.Opts = obj.mergeStruct(obj.Opts, opts);
            end

            obj.buildCaches();
            obj.prepareAxes();
            obj.Handles = struct();

            obj.plotElements();
            obj.plotNodes();
            obj.plotFixedNodes();
            obj.plotMPConstraints();
            obj.plotLocalAxes();
            obj.plotLoads();
            obj.plotOutline();
            obj.printModelSummary();

            obj.applyView();
            obj.applyTitle();
            obj.Plotter.applyDataLimits(obj.NodeCoords, obj.Opts.general.padRatio);

            xlabel(obj.Ax, 'X');
            ylabel(obj.Ax, 'Y');
            zlabel(obj.Ax, 'Z');

            h = obj.Handles;
        end
    end

    methods (Access = private)

        function buildCaches(obj)
            P = zeros(0,3);
            if isfield(obj.ModelInfo,'Nodes') && isfield(obj.ModelInfo.Nodes,'Coords')
                P = double(obj.ModelInfo.Nodes.Coords);
            end
            P = obj.pad3cols(P);

            obj.NodeCoords  = P;
            obj.ModelDim    = max(obj.ModelInfo.Nodes.Ndm);
            obj.Bounds      = obj.computeBounds(P);
            obj.AxisBaseLen = obj.computeModelLength(P);

            obj.NodeIdxArray = [];
            obj.NodeIdxMap   = [];
            if isfield(obj.ModelInfo,'Nodes') && isfield(obj.ModelInfo.Nodes,'Tags')
                [obj.NodeIdxArray, obj.NodeIdxMap] = ...
                    obj.buildTagLookup(double(obj.ModelInfo.Nodes.Tags(:)));
            end

            obj.BeamIdxArray = [];
            obj.BeamIdxMap   = [];
            obj.BeamXAxis    = zeros(0,3);
            obj.BeamYAxis    = zeros(0,3);
            obj.BeamZAxis    = zeros(0,3);

            fam = obj.getFamilies();
            if isfield(fam,'Beam') && isfield(fam.Beam,'Tags') && ~isempty(fam.Beam.Tags)
                [obj.BeamIdxArray, obj.BeamIdxMap] = ...
                    obj.buildTagLookup(double(fam.Beam.Tags(:)));

                if isfield(fam.Beam,'XAxis') && ~isempty(fam.Beam.XAxis)
                    obj.BeamXAxis = obj.pad3cols(double(fam.Beam.XAxis));
                end
                if isfield(fam.Beam,'YAxis') && ~isempty(fam.Beam.YAxis)
                    obj.BeamYAxis = obj.pad3cols(double(fam.Beam.YAxis));
                end
                if isfield(fam.Beam,'ZAxis') && ~isempty(fam.Beam.ZAxis)
                    obj.BeamZAxis = obj.pad3cols(double(fam.Beam.ZAxis));
                end
            end
        end

        function [arr, mp] = buildTagLookup(obj, tags)
            arr = [];
            mp  = [];
            if isempty(tags), return; end

            n = numel(tags);
            maxTag = max(tags);

            if isfinite(maxTag) && maxTag >= 1 && ...
               maxTag <= obj.Opts.performance.maxDenseLookupTag && ...
               maxTag <= 20 * n
                arr = zeros(maxTag,1);
                arr(tags) = 1:n;
            else
                mp = containers.Map(num2cell(tags), num2cell(1:n));
            end
        end

        function prepareAxes(obj)
            fig = ancestor(obj.Ax, 'figure');
            sz  = obj.Opts.general.figureSize;

            if isnumeric(sz) && numel(sz)==2 && all(isfinite(sz)) && all(sz>0)
                oldUnits = fig.Units;
                fig.Units = 'pixels';
                pos = fig.Position;
                pos(3:4) = sz;
                fig.Position = pos;
                fig.Units = oldUnits;
            end

            if obj.Opts.general.clearAxes
                cla(obj.Ax, 'reset');
                hold(obj.Ax, 'on');
            elseif obj.Opts.general.holdOn
                hold(obj.Ax, 'on');
            end

            if obj.Opts.general.axisEqual, axis(obj.Ax, 'equal'); end
            if obj.Opts.general.grid, grid(obj.Ax, 'on'); else, grid(obj.Ax, 'off'); end
            if obj.Opts.general.box,  box(obj.Ax, 'on');  else, box(obj.Ax, 'off');  end
        end

        function plotNodes(obj)
            if obj.Opts.nodes.showLabels
                if ~obj.Opts.nodes.show, obj.Opts.nodes.show = true; end
                obj.addEntityLabels(obj.NodeCoords, obj.ModelInfo.Nodes.Tags(:), 'N', ...
                    obj.Opts.nodes.labelOffsetScale, obj.Opts.nodes.labelColor, ...
                    obj.Opts.nodes.fontSize, 'NodeLabels');
            end

            if ~obj.Opts.nodes.show, return; end
            if ~isfield(obj.ModelInfo,'Nodes') || ~isfield(obj.ModelInfo.Nodes,'Tags') || isempty(obj.ModelInfo.Nodes.Tags)
                return;
            end
            if isempty(obj.NodeCoords), return; end

            s = struct( ...
                'points',    obj.NodeCoords, ...
                'size',      obj.Opts.nodes.size, ...
                'marker',    obj.Opts.nodes.marker, ...
                'filled',    obj.Opts.nodes.filled, ...
                'edgeColor', obj.Opts.nodes.edgeColor, ...
                'color',     obj.getFamilyColor('Node', obj.Opts.nodes.color), ...
                'tag',       'Nodes');
            obj.Handles.Nodes = obj.Plotter.addPoints(s);
        end

        function plotFixedNodes(obj)
            if ~obj.Opts.fixed.show, return; end
            if ~isfield(obj.ModelInfo,'Fixed') || ~isfield(obj.ModelInfo.Fixed,'NodeTags') || isempty(obj.ModelInfo.Fixed.NodeTags)
                return;
            end

            P = obj.pad3cols(double(obj.ModelInfo.Fixed.Coords));
            if isempty(P), return; end

            s = struct( ...
                'points',    P, ...
                'size',      obj.Opts.fixed.size, ...
                'marker',    obj.Opts.fixed.marker, ...
                'filled',    obj.Opts.fixed.filled, ...
                'edgeColor', obj.Opts.fixed.edgeColor, ...
                'color',     obj.getFamilyColor('Fixed', obj.Opts.fixed.color), ...
                'tag',       'FixedNodes');
            obj.Handles.Fixed = obj.Plotter.addPoints(s);
        end

        function plotMPConstraints(obj)
            if ~obj.Opts.mpConstraint.show, return; end
            if ~isfield(obj.ModelInfo,'MPConstraint'), return; end

            mp = obj.ModelInfo.MPConstraint;
            if ~isfield(mp,'Cells') || isempty(mp.Cells), return; end

            s = struct( ...
                'nodes',     obj.NodeCoords, ...
                'lines',     mp.Cells(:,2:end), ...
                'color',     obj.Opts.mpConstraint.color, ...
                'lineWidth', obj.Opts.mpConstraint.lineWidth, ...
                'lineStyle', obj.Opts.mpConstraint.lineStyle, ...
                'tag',       'MPConstraint');
            obj.Handles.MPConstraint = obj.Plotter.addLine(s);
        end

        function plotElements(obj)
            if ~isfield(obj.ModelInfo,'Elements') || isempty(obj.ModelInfo.Elements), return; end

            P   = obj.NodeCoords;
            fam = obj.getFamilies();

            lineFams  = {'Beam','Link','Truss','Contact'};
            lineFlags = [obj.Opts.elements.showBeam, obj.Opts.elements.showLink, ...
                         obj.Opts.elements.showTruss, obj.Opts.elements.showContact];

            for k = 1:numel(lineFams)
                if lineFlags(k), obj.plotLineFamily(fam, lineFams{k}, P); end
            end

            surfFams  = {'Plane','Shell','Solid'};
            surfFlags = [obj.Opts.elements.showPlane, obj.Opts.elements.showShell, obj.Opts.elements.showSolid];

            for k = 1:numel(surfFams)
                if surfFlags(k), obj.plotSurfaceFamily(fam, surfFams{k}, P); end
            end
        end

        function plotLineFamily(obj, fam, name, P)
            if ~isfield(fam,name), return; end
            S = fam.(name);
            if ~isfield(S,'Cells') || isempty(S.Cells), return; end

            lines = S.Cells(:,2:end);
            s = struct( ...
                'nodes',     P, ...
                'lines',     lines, ...
                'color',     obj.getStyleColor(name,'line'), ...
                'lineWidth', obj.Opts.elements.lineWidth, ...
                'tag',       name);
            obj.Handles.(name) = obj.Plotter.addLine(s);

            if obj.Opts.elements.showLabels && isfield(S,'Tags') && ~isempty(S.Tags)
                C = 0.5 * (P(lines(:,1),:) + P(lines(:,2),:));
                obj.addEntityLabels(C, S.Tags(:), 'E', ...
                    obj.Opts.elements.labelOffsetScale, obj.Opts.elements.labelColor, ...
                    obj.Opts.elements.fontSize, [name 'Labels']);
            end
        end

        function plotSurfaceFamily(obj, fam, name, P)
            if ~isfield(fam,name), return; end
            S = fam.(name);
            if ~isfield(S,'Cells') || isempty(S.Cells) || ~isfield(S,'CellTypes') || isempty(S.CellTypes)
                return;
            end

            surfOut = plotter.utils.VTKElementTriangulator.triangulate(P, S.CellTypes, S.Cells);
            if isempty(surfOut) || ~isfield(surfOut,'Points') || isempty(surfOut.Points), return; end

            wireColor = obj.Opts.style.wireframeColor;
            wireLW    = obj.Opts.elements.wireframeLineWidth;

            if ~obj.Opts.elements.wireframeOnly
                m = struct( ...
                    'nodes',     surfOut.Points, ...
                    'tris',      surfOut.Triangles, ...
                    'faceColor', obj.getStyleColor(name,'surface'), ...
                    'faceAlpha', obj.Opts.elements.surfaceAlpha, ...
                    'tag',       name);
                obj.Handles.(name) = obj.Plotter.addMesh(m);

                if obj.Opts.elements.showWireframeOnFaces && isfield(surfOut,'EdgePoints') && ~isempty(surfOut.EdgePoints)
                    w = struct( ...
                        'points',    surfOut.EdgePoints, ...
                        'color',     wireColor, ...
                        'lineWidth', wireLW, ...
                        'tag',       [name 'Wireframe']);
                    obj.Handles.([name 'Wireframe']) = obj.Plotter.addLine(w);
                end
            else
                if isfield(surfOut,'EdgePoints') && ~isempty(surfOut.EdgePoints)
                    w = struct( ...
                        'points',    surfOut.EdgePoints, ...
                        'color',     wireColor, ...
                        'lineWidth', wireLW, ...
                        'tag',       name);
                    obj.Handles.(name) = obj.Plotter.addLine(w);
                end
            end

            if obj.Opts.elements.showLabels && isfield(S,'Tags') && ~isempty(S.Tags)
                obj.addEntityLabels(surfOut.MidPoints, S.Tags(:), 'E', ...
                    obj.Opts.elements.labelOffsetScale, obj.Opts.elements.labelColor, ...
                    obj.Opts.elements.fontSize, [name 'Labels']);
            end
        end

        function plotLocalAxes(obj)
            fam = obj.getFamilies();
            if isempty(fieldnames(fam)), return; end
            axLen = obj.AxisBaseLen * obj.Opts.localAxes.scale;

            if obj.Opts.localAxes.showBeam && isfield(fam,'Beam')
                obj.plotFrameAxes(fam.Beam, 'BeamAxes', axLen);
            end
            if obj.Opts.localAxes.showLink && isfield(fam,'Link')
                obj.plotFrameAxes(fam.Link, 'LinkAxes', axLen);
            end
        end

        function plotFrameAxes(obj, S, baseName, axLen)
            if isempty(S) || ~isfield(S,'Midpoints') || isempty(S.Midpoints), return; end

            O = obj.pad3cols(double(S.Midpoints));
            axisFields = {'XAxis','YAxis','ZAxis'};
            colors     = {obj.Opts.localAxes.axisXColor, obj.Opts.localAxes.axisYColor, obj.Opts.localAxes.axisZColor};
            labels     = {'x','y','z'};

            for k = 1:3
                f = axisFields{k};
                if ~isfield(S,f) || isempty(S.(f)), continue; end

                V = obj.pad3cols(double(S.(f)));
                tag = [baseName, f(2)];

                s = struct( ...
                    'points',    O, ...
                    'vectors',   V, ...
                    'scale',     axLen, ...
                    'color',     colors{k}, ...
                    'tag',       tag, ...
                    'lineWidth', obj.Opts.localAxes.lineWidth);
                obj.Handles.(tag) = obj.Plotter.addArrows(s);

                if obj.Opts.localAxes.labelAxes
                    lbl = struct( ...
                        'points',   O + axLen * V, ...
                        'labels',   repmat(labels(k), size(O,1), 1), ...
                        'color',    colors{k}, ...
                        'fontSize', obj.Opts.localAxes.fontSize);
                    obj.Plotter.addNodeLabels(lbl);
                end
            end
        end

        function plotLoads(obj)
            if ~isfield(obj.ModelInfo,'Loads') || isempty(obj.ModelInfo.Loads), return; end
            if isempty(obj.NodeCoords), return; end

            L           = obj.ModelInfo.Loads;
            minNorm     = obj.Opts.loads.minNorm;
            baseLen     = obj.getLoadAutoLength();
            labelOffset = obj.getLoadLabelOffset();
            maxMag      = obj.computeGlobalMaxMag(L, minNorm);

            obj.plotNodalLoads(L, baseLen, labelOffset, minNorm, maxMag);
            obj.plotBeamLoads(L, baseLen, labelOffset, minNorm, maxMag);
        end

        function plotNodalLoads(obj, L, baseLen, labelOffset, minNorm, maxMag)
            if ~(obj.Opts.loads.showNodal && isfield(L,'Node') && ...
                 isfield(L.Node,'PatternNodeTags') && ~isempty(L.Node.PatternNodeTags) && ...
                 isfield(L.Node,'Values') && ~isempty(L.Node.Values))
                return;
            end

            nodeTags = double(L.Node.PatternNodeTags(:,2));
            idx      = obj.nodeTagsToIdx(nodeTags);
            valid    = idx > 0 & idx <= size(obj.NodeCoords,1);
            if ~any(valid), return; end

            idx  = idx(valid);
            vals = double(L.Node.Values(valid,:));

            V = zeros(size(vals,1),3);
            V(:,1:min(3,size(vals,2))) = vals(:,1:min(3,size(vals,2)));

            mag  = sqrt(sum(V.^2,2));
            keep = mag > minNorm;
            if ~any(keep), return; end

            idx = idx(keep);
            V   = V(keep,:);
            mag = mag(keep);

            dirs = V ./ mag;
            if obj.Opts.loads.normalizeLength
                drawLen = repmat(baseLen, size(mag));
            else
                drawLen = baseLen * mag / maxMag;
            end

            Udraw = dirs .* drawLen;
            Otip  = obj.NodeCoords(idx,:);
            Otail = Otip - Udraw;

            s = struct( ...
                'points',    Otail, ...
                'vectors',   Udraw, ...
                'scale',     1, ...
                'color',     obj.Opts.loads.nodalColor, ...
                'lineWidth', obj.Opts.loads.lineWidth, ...
                'headSize',  0.85, ...
                'tag',       'NodalLoads');
            obj.Handles.NodalLoads = obj.Plotter.addArrows(s);

            if obj.Opts.loads.showLabels
                labelPos = Otip + repmat(labelOffset, size(Otip,1), 1);
                obj.addLoadTexts(labelPos, obj.localFormatLoadLabels(V), 'NodalLoadText');
            end
        end

        function plotBeamLoads(obj, L, baseLen, labelOffset, minNorm, maxMag)
            if ~(obj.Opts.loads.showElement && isfield(L,'Element') && isfield(L.Element,'Beam') && ...
                 isfield(L.Element.Beam,'PatternElementTags') && ~isempty(L.Element.Beam.PatternElementTags) && ...
                 isfield(L.Element.Beam,'Values') && ~isempty(L.Element.Beam.Values))
                return;
            end

            pairTags = double(L.Element.Beam.PatternElementTags);
            valsAll  = double(L.Element.Beam.Values);

            if isvector(pairTags), pairTags = reshape(pairTags,1,[]); end
            if size(pairTags,2) ~= 2, return; end
            if isvector(valsAll), valsAll = reshape(valsAll,1,[]); end

            nLoad = min(size(pairTags,1), size(valsAll,1));
            if nLoad < 1, return; end

            pairTags = pairTags(1:nLoad,:);
            valsAll  = valsAll(1:nLoad,:);

            nArrowPerLoad = max(1, round(obj.Opts.loads.nElementArrows));
            maxArrowCount = 3 * nLoad * nArrowPerLoad;

            allPts  = zeros(maxArrowCount,3);
            allVec  = zeros(maxArrowCount,3);
            textPts = zeros(nLoad,3);
            textTxt = strings(nLoad,1);

            iArrow = 0;
            iText  = 0;

            for i = 1:nLoad
                eleTag = pairTags(i,2);
                row    = valsAll(i,:);

                [comps, xa, xb, isDist, isPoint] = obj.extractBeamLoadComponents(row, minNorm);
                if ~(isPoint || isDist), continue; end

                [p1, p2, ok] = obj.lookupBeamEndCoords(eleTag);
                if ~ok, continue; end

                dirVec = p2 - p1;
                if norm(dirVec) < minNorm, continue; end

                [ex, ey, ez, okAxes] = obj.lookupBeamLocalAxes(eleTag);
                if ~okAxes, continue; end
                ex = obj.normalizeRow(ex);
                ey = obj.normalizeRow(ey);
                ez = obj.normalizeRow(ez);

                if isPoint
                    posList = p1 + xa * dirVec;
                else
                    sLoc = linspace(xa, xb, nArrowPerLoad).';
                    posList = p1 + sLoc .* dirVec;
                end

                [allPts, allVec, iArrow] = obj.appendLoadComponent(allPts, allVec, iArrow, posList, ex, comps(1), baseLen, maxMag);
                [allPts, allVec, iArrow] = obj.appendLoadComponent(allPts, allVec, iArrow, posList, ey, comps(2), baseLen, maxMag);
                [allPts, allVec, iArrow] = obj.appendLoadComponent(allPts, allVec, iArrow, posList, ez, comps(3), baseLen, maxMag);

                iText = iText + 1;
                if isPoint
                    textPts(iText,:) = posList + labelOffset;
                else
                    textPts(iText,:) = p1 + 0.5*(xa+xb)*dirVec + labelOffset;
                end
                textTxt(iText) = obj.localFormatLoadLabels(comps);
            end

            if iArrow > 0
                s = struct( ...
                    'points',    allPts(1:iArrow,:), ...
                    'vectors',   allVec(1:iArrow,:), ...
                    'scale',     1, ...
                    'color',     obj.Opts.loads.elementColor, ...
                    'lineWidth', obj.Opts.loads.lineWidth, ...
                    'headSize',  0.75, ...
                    'tag',       'ElementLoads');
                obj.Handles.ElementLoads = obj.Plotter.addArrows(s);
            end

            if obj.Opts.loads.showLabels && iText > 0
                obj.addLoadTexts(textPts(1:iText,:), textTxt(1:iText), 'ElementLoadText');
            end
        end

        function [allPts, allVec, iArrow] = appendLoadComponent(obj, allPts, allVec, iArrow, posList, axisDir, qComp, baseLen, maxMag)
            if abs(qComp) <= obj.Opts.loads.minNorm, return; end

            nPos = size(posList,1);
            if obj.Opts.loads.normalizeLength
                drawLen = baseLen * sign(qComp);
            else
                drawLen = baseLen * qComp / maxMag;
            end

            Udraw = drawLen * axisDir;
            idxRange = iArrow + (1:nPos);

            allPts(idxRange,:) = posList - repmat(Udraw, nPos, 1);
            allVec(idxRange,:) = repmat(Udraw, nPos, 1);
            iArrow = iArrow + nPos;
        end

        function maxMag = computeGlobalMaxMag(obj, L, minNorm)
            allMags = [];
            if isfield(L,'Node') && isfield(L.Node,'PatternNodeTags') && ~isempty(L.Node.PatternNodeTags) && ...
                    isfield(L.Node,'Values') && ~isempty(L.Node.Values)
                nodeTags = double(L.Node.PatternNodeTags(:,2));
                idx      = obj.nodeTagsToIdx(nodeTags);
                valid    = idx > 0 & idx <= size(obj.NodeCoords,1);
                if any(valid)
                    vals = double(L.Node.Values(valid,:));
                    V = zeros(size(vals,1),3);
                    V(:,1:min(3,size(vals,2))) = vals(:,1:min(3,size(vals,2)));
                    allMags = [allMags; sqrt(sum(V.^2,2))];
                end
            end
            if isfield(L,'Element') && isfield(L.Element,'Beam') && ...
                    isfield(L.Element.Beam,'Values') && ~isempty(L.Element.Beam.Values)
                valsAll = double(L.Element.Beam.Values);
                if isvector(valsAll), valsAll = reshape(valsAll,1,[]); end
                for i = 1:size(valsAll,1)
                    [comps,~,~,isDist,isPoint] = obj.extractBeamLoadComponents(valsAll(i,:), minNorm);
                    if isPoint || isDist
                        allMags = [allMags; abs(comps(:))];
                    end
                end
            end
            allMags = allMags(allMags > minNorm);
            if isempty(allMags)
                maxMag = 1;
            else
                maxMag = max(allMags);
            end
        end

        function [qLocal, xa, xb, isDist, isPoint] = extractBeamLoadComponents(~, row, minNorm)
            % row = [wya wyb wza wzb wxa wxb xa xb clsTag rawNcol]
            qLocal  = [0 0 0];
            xa      = 0;
            xb      = 0;
            isDist  = false;
            isPoint = false;

            if isempty(row), return; end
            row = double(row(:).');
            if numel(row) < 8, row(8) = 0; end

            wy1 = row(1); wy2 = row(2);
            wz1 = row(3); wz2 = row(4);
            wx1 = row(5); wx2 = row(6);
            xa  = row(7);
            xb  = row(8);

            if abs(xb + 10000) < max(minNorm,1e-12)
                isPoint = true;
            else
                hasLoad = any(abs([wy1 wy2 wz1 wz2 wx1 wx2]) > minNorm);
                if hasLoad
                    if abs(xa) < minNorm && abs(xb) < minNorm
                        xa = 0;
                        xb = 1;
                    end
                    if xb > xa + minNorm
                        isDist = true;
                    elseif abs(xb - xa) <= minNorm
                        isPoint = true;
                        xb = -10000;
                    end
                end
            end

            if isPoint
                qLocal = [wx1 wy1 wz1];
                xa = max(0, min(1, xa));
            elseif isDist
                qLocal = [0.5*(wx1+wx2), 0.5*(wy1+wy2), 0.5*(wz1+wz2)];
                xa = max(0, min(1, xa));
                xb = max(0, min(1, xb));
                if xb < xa
                    t = xa; xa = xb; xb = t;
                end
            end
        end

        function plotOutline(obj)
            if ~obj.Opts.outline.show, return; end
            b = obj.Bounds;
            if isempty(b) || numel(b)~=6 || any(~isfinite(b)), return; end

            c  = obj.Opts.outline.color;
            lw = obj.Opts.outline.lineWidth;
            ls = obj.Opts.outline.lineStyle;

            if obj.ModelDim == 2
                x1=b(1); x2=b(2); y1=b(3); y2=b(4);
                s = struct( ...
                    'points', [x1 y1; x2 y1; x2 y2; x1 y2; x1 y1], ...
                    'color', c, 'lineWidth', lw, 'lineStyle', ls, 'tag', 'Outline');
            else
                x1=b(1); x2=b(2); y1=b(3); y2=b(4); z1=b(5); z2=b(6);
                V = [x1 y1 z1; x2 y1 z1; x2 y2 z1; x1 y2 z1; ...
                     x1 y1 z2; x2 y1 z2; x2 y2 z2; x1 y2 z2];
                E = [1 2;2 3;3 4;4 1;5 6;6 7;7 8;8 5;1 5;2 6;3 7;4 8];
                s = struct( ...
                    'nodes', V, 'lines', E, ...
                    'color', c, 'lineWidth', lw, 'lineStyle', ls, 'tag', 'Outline');
            end
            obj.Handles.Outline = obj.Plotter.addLine(s);
        end

        function printModelSummary(obj)
            if ~isfield(obj.Opts, 'summary') || ~obj.Opts.summary.show
                return;
            end

            lines = strings(0,1);

            nNode = obj.countNodes();
            if nNode > 0
                lines(end+1,1) = sprintf('Nodes: %d', nNode); %#ok<AGROW>
            end

            fam = obj.getFamilies();
            famNames = {'Beam','Link','Truss', 'Plane','Shell','Solid','Contact'};
            for i = 1:numel(famNames)
                name = famNames{i};
                if ~isfield(fam, name)
                    continue;
                end

                nEle = obj.countFamilyEntities(fam.(name));
                if nEle > 0
                    lines(end+1,1) = sprintf('%s elements: %d', name, nEle); %#ok<AGROW>
                end
            end

            nMp = obj.countMPConstraints();
            if nMp > 0
                lines(end+1,1) = sprintf('MP constraints: %d', nMp); %#ok<AGROW>
            end

            if isempty(lines)
                return;
            end

            fprintf('[OpenSeesMatlab] Model summary\n');
            for i = 1:numel(lines)
                fprintf('  %s\n', lines(i));
            end
        end

        function applyView(obj)
            v = lower(char(string(obj.Opts.general.view)));

            if strcmp(v, 'auto')
                if obj.ModelDim == 2, view(obj.Ax, 2); else, view(obj.Ax, 3); end
                return;
            end

            switch v
                case 'iso', view(obj.Ax, 3);
                case 'xy',  view(obj.Ax, 2);
                case 'yx',  view(obj.Ax, 90, 90);
                case 'xz',  view(obj.Ax, 0, 0);
                case 'zx',  view(obj.Ax, 180, 0);
                case 'yz',  view(obj.Ax, 90, 0);
                case 'zy',  view(obj.Ax, -90, 0);
                otherwise
                    if obj.ModelDim == 2, view(obj.Ax, 2); else, view(obj.Ax, 3); end
            end
        end

        function applyTitle(obj)
            if strlength(string(obj.Opts.general.title)) > 0
                title(obj.Ax, char(string(obj.Opts.general.title)));
            end
        end

        function fam = getFamilies(obj)
            fam = struct();
            if ~isfield(obj.ModelInfo,'Elements') || isempty(obj.ModelInfo.Elements), return; end
            E = obj.ModelInfo.Elements;
            if isfield(E,'Families'), fam = E.Families; else, fam = E; end
        end

        function n = countNodes(obj)
            n = 0;

            if isfield(obj.ModelInfo,'Nodes') && isfield(obj.ModelInfo.Nodes,'Tags') && ...
               ~isempty(obj.ModelInfo.Nodes.Tags)
                n = nnz(isfinite(double(obj.ModelInfo.Nodes.Tags(:))));
                return;
            end

            if ~isempty(obj.NodeCoords)
                n = nnz(any(isfinite(obj.NodeCoords), 2));
            end
        end

        function n = countFamilyEntities(~, S)
            n = 0;
            if ~isstruct(S) || isempty(S)
                return;
            end

            if isfield(S,'Tags') && ~isempty(S.Tags)
                n = nnz(isfinite(double(S.Tags(:))));
                return;
            end

            if ~isfield(S,'Cells') || isempty(S.Cells)
                return;
            end

            cells = double(S.Cells);
            while ndims(cells) > 2
                cells = squeeze(cells);
            end
            if isempty(cells)
                return;
            end
            if isvector(cells)
                cells = reshape(cells, 1, []);
            end

            n = nnz(any(isfinite(cells), 2));
        end

        function n = countMPConstraints(obj)
            n = 0;
            if ~isfield(obj.ModelInfo,'MPConstraint') || isempty(obj.ModelInfo.MPConstraint)
                return;
            end

            mp = obj.ModelInfo.MPConstraint;
            if isfield(mp,'Cells') && ~isempty(mp.Cells)
                cells = double(mp.Cells);
                while ndims(cells) > 2
                    cells = squeeze(cells);
                end
                if isempty(cells)
                    return;
                end
                if isvector(cells)
                    cells = reshape(cells, 1, []);
                end
                n = nnz(any(isfinite(cells), 2));
            end
        end

        function b = computeBounds(obj, P)
            b = nan(1,6);

            if isfield(obj.ModelInfo,'Nodes') && isfield(obj.ModelInfo.Nodes,'Bounds')
                raw = double(obj.ModelInfo.Nodes.Bounds);
                if numel(raw)==6 && all(isfinite(raw))
                    b = raw(:).';
                    return;
                end
            end

            if isempty(P), return; end
            P = obj.pad3cols(P);

            mn = min(P, [], 1, 'omitnan');
            mx = max(P, [], 1, 'omitnan');
            if any(~isfinite(mn)) || any(~isfinite(mx)), return; end
            b = [mn(1) mx(1) mn(2) mx(2) mn(3) mx(3)];
        end

        function L = computeModelLength(~, P)
            if isempty(P), L = 1; return; end
            ext = max(P, [], 1, 'omitnan') - min(P, [], 1, 'omitnan');
            ext = ext(isfinite(ext));
            if isempty(ext), L = 1; return; end
            L = max(ext);
            if ~isfinite(L) || L <= 0, L = 1; end
        end

        function color = getStyleColor(obj, familyName, kind)
            if strcmpi(kind, 'surface')
                fallback = obj.Opts.style.shellColor;
                if ismember(lower(familyName), {'solid','unstructured'})
                    fallback = obj.Opts.style.solidColor;
                end
            else
                fallback = obj.Opts.style.lineColor;
            end
            color = obj.getFamilyColor(familyName, fallback);
        end

        function color = getFamilyColor(obj, familyName, fallback)
            if strcmpi(obj.Opts.style.mode, 'mono')
                color = fallback;
                return;
            end
            if isfield(obj.Opts.style.familyColors, familyName)
                color = obj.Opts.style.familyColors.(familyName);
            else
                color = fallback;
            end
        end

        function addEntityLabels(obj, P, tags, prefix, offsetScale, color, fontSize, handleName)
            lbl = struct( ...
                'points',   P, ...
                'labels',   prefix + string(tags(:)), ...
                'offset',   [1 1 0] * offsetScale * obj.AxisBaseLen, ...
                'color',    color, ...
                'fontSize', fontSize);
            obj.Handles.(handleName) = obj.Plotter.addNodeLabels(lbl);
        end

        function len = getLoadAutoLength(obj)
            len = obj.AxisBaseLen * obj.Opts.loads.baseFraction * obj.Opts.loads.scale;
            if ~isfinite(len) || len <= 0
                len = 1.0 * obj.Opts.loads.scale;
            end
        end

        function offset = getLoadLabelOffset(obj)
            raw = obj.Opts.loads.labelOffset;
            if isempty(raw)
                raw = [0 0.14 0];
            end

            raw = double(raw);
            if isscalar(raw)
                raw = [0 raw 0];
            else
                raw = reshape(raw, 1, []);
                if numel(raw) < 3, raw(3) = 0; end
                raw = raw(1:3);
            end

            offset = raw * obj.AxisBaseLen;
        end

        function [xaxis, yaxis, zaxis, ok] = lookupBeamLocalAxes(obj, eleTag)
            xaxis = [NaN NaN NaN];
            yaxis = [NaN NaN NaN];
            zaxis = [NaN NaN NaN];
            ok = false;

            idx = obj.tagLookup(eleTag, obj.BeamIdxArray, obj.BeamIdxMap);
            if isempty(idx) || idx < 1, return; end
            if idx > size(obj.BeamXAxis,1) || idx > size(obj.BeamYAxis,1) || idx > size(obj.BeamZAxis,1), return; end

            xaxis = obj.BeamXAxis(idx,:);
            yaxis = obj.BeamYAxis(idx,:);
            zaxis = obj.BeamZAxis(idx,:);
            ok = all(isfinite([xaxis yaxis zaxis]));
        end

        function txt = localFormatLoadLabels(~, V)
            if isempty(V)
                txt = "";
                return;
            end

            if isvector(V), V = reshape(double(V), 1, []); else, V = double(V); end
            txt = strings(size(V,1),1);

            for i = 1:size(V,1)
                vals = strings(0,1);
                for k = 1:min(3,size(V,2))
                    if abs(V(i,k)) > 1e-12
                        vals(end+1,1) = sprintf('%.3g', V(i,k)); %#ok<AGROW>
                    end
                end
                if ~isempty(vals), txt(i) = strjoin(vals, ', '); end
            end

            if numel(txt)==1, txt = txt(1); end
        end

        function addLoadTexts(obj, pts, txt, tagName)
            if isempty(pts) || isempty(txt), return; end
            txt = string(txt);
            n = min(size(pts,1), numel(txt));

            for i = 1:n
                if strlength(txt(i)) == 0, continue; end
                text(obj.Ax, pts(i,1), pts(i,2), pts(i,3), char(txt(i)), ...
                    'Color', obj.Opts.loads.textColor, ...
                    'FontSize', obj.Opts.loads.fontSize, ...
                    'HorizontalAlignment', 'center', ...
                    'VerticalAlignment', 'middle', ...
                    'Tag', tagName);
            end
        end

        function idx = nodeTagsToIdx(obj, nodeTags)
            idx = obj.tagLookup(nodeTags, obj.NodeIdxArray, obj.NodeIdxMap);
        end

        function [p1, p2, ok] = lookupBeamEndCoords(obj, eleTag)
            p1 = [NaN NaN NaN];
            p2 = [NaN NaN NaN];
            ok = false;

            fam = obj.getFamilies();
            if isfield(fam,'Beam')
                [p1, p2, ok] = obj.lookupFamilyEndCoords(fam.Beam, eleTag);
                if ok, return; end
            end
            if isfield(fam,'Line')
                [p1, p2, ok] = obj.lookupFamilyEndCoords(fam.Line, eleTag);
            end
        end

        function [p1, p2, ok] = lookupFamilyEndCoords(obj, S, eleTag)
            p1 = [NaN NaN NaN];
            p2 = [NaN NaN NaN];
            ok = false;

            if ~isstruct(S) || ~isfield(S,'Tags') || isempty(S.Tags) || ~isfield(S,'Cells') || isempty(S.Cells)
                return;
            end

            eleTags = double(S.Tags(:));
            cells   = double(S.Cells);
            if ndims(cells) > 2, cells = squeeze(cells); end
            if isempty(cells), return; end
            if isvector(cells), cells = reshape(cells,1,[]); end

            idx = find(abs(eleTags-eleTag) < 1e-12, 1, 'first');
            if isempty(idx), return; end

            c = cells(idx,:);
            if numel(c) >= 3
                nodeIdx = round(c(end-1:end));
            elseif numel(c) == 2
                nodeIdx = round(c);
            else
                return;
            end

            if any(nodeIdx < 1) || any(nodeIdx > size(obj.NodeCoords,1)), return; end
            p1 = obj.NodeCoords(nodeIdx(1),:);
            p2 = obj.NodeCoords(nodeIdx(2),:);
            ok = true;
        end

        function idx = tagLookup(~, tags, arr, mp)
            tags = double(tags(:));
            idx  = zeros(numel(tags),1);
            if isempty(tags), return; end

            if ~isempty(arr)
                valid = tags >= 1 & tags <= numel(arr) & isfinite(tags) & mod(tags,1)==0;
                idx(valid) = arr(tags(valid));
                return;
            end

            if ~isempty(mp)
                keys = num2cell(tags);
                exists = isKey(mp, keys);
                if any(exists)
                    vals = values(mp, keys(exists));
                    idx(exists) = cell2mat(vals);
                end
            end
        end

        function out = mergeStruct(obj, base, add)
            out = base;
            if isempty(add) || ~isstruct(add), return; end

            f = fieldnames(add);
            for i = 1:numel(f)
                n = f{i};
                if isfield(out,n) && isstruct(out.(n)) && isstruct(add.(n))
                    out.(n) = obj.mergeStruct(out.(n), add.(n));
                else
                    out.(n) = add.(n);
                end
            end
        end

        function P = pad3cols(~, P)
            P = double(P);
            if isempty(P)
                P = zeros(0,3);
                return;
            end
            if size(P,2) < 3, P(:,3) = 0; end
            P = P(:,1:3);
        end

        function v = normalizeRow(~, v)
            v = double(v(:)).';
            n = norm(v);
            if n > 0, v = v / n; end
        end
    end
end
