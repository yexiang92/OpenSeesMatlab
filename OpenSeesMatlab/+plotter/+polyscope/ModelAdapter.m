classdef ModelAdapter
    %MODELADAPTER Convert OpenSeesMatlab ModelInfo to Polyscope geometry.
    %
    %   Static helper used by plotModel, plotEigen and
    %   NodalResponseViewer. It knows how to read node coordinates, element
    %   families, fixed nodes, MP constraints and loads from the standard
    %   ModelInfo struct produced by opsmat.post.getModelData().

    methods (Static)

        function P = nodeCoords(modelInfo)
            P = plotter.polyscope.ModelAdapter.rawNodeCoords(modelInfo);
            if isempty(P), return; end
            P = P - plotter.polyscope.ModelAdapter.geometryCenter(modelInfo);
        end

        function P = rawNodeCoords(modelInfo)
            modelInfo = plotter.polyscope.ModelAdapter.modelSnapshot_(modelInfo);
            P = zeros(0, 3);
            if isstruct(modelInfo) && isfield(modelInfo, 'Nodes') && ...
                    isstruct(modelInfo.Nodes) && isfield(modelInfo.Nodes, 'Coords')
                P = double(modelInfo.Nodes.Coords);
            end
            P = plotter.polyscope.ModelAdapter.pad3(P);
        end

        function tags = nodeTags(modelInfo)
            modelInfo = plotter.polyscope.ModelAdapter.modelSnapshot_(modelInfo);
            P = plotter.polyscope.ModelAdapter.nodeCoords(modelInfo);
            if isstruct(modelInfo) && isfield(modelInfo, 'Nodes') && ...
                    isstruct(modelInfo.Nodes) && isfield(modelInfo.Nodes, 'Tags')
                tags = double(modelInfo.Nodes.Tags(:));
            else
                tags = (1:size(P,1))';
            end
        end

        function fam = families(modelInfo)
            modelInfo = plotter.polyscope.ModelAdapter.modelSnapshot_(modelInfo);
            fam = struct();
            if isstruct(modelInfo) && isfield(modelInfo, 'Elements') && ~isempty(modelInfo.Elements)
                E = modelInfo.Elements;
                if isfield(E, 'Families') && isstruct(E.Families)
                    fam = E.Families;
                elseif isstruct(E)
                    fam = E;
                end
            end
        end

        function names = lineFamilyNames(~)
            names = {'Beam', 'Truss', 'Link', 'Contact'};
        end

        function names = surfaceFamilyNames(~)
            names = {'Plane', 'Shell'};
        end

        function names = volumeFamilyNames(~)
            names = {'Solid'};
        end

        function edges = lineEdges(modelInfo, familyName)
            edges = zeros(0, 2);
            fam = plotter.polyscope.ModelAdapter.families(modelInfo);
            if ~isfield(fam, familyName), return; end
            S = fam.(familyName);
            if ~isstruct(S) || ~isfield(S, 'Cells') || isempty(S.Cells)
                return;
            end
            edges = plotter.polyscope.ModelAdapter.cellsToLineEdges( ...
                double(S.Cells), modelInfo);
            edges = plotter.polyscope.ModelAdapter.keepValidEdges_( ...
                edges, size(plotter.polyscope.ModelAdapter.nodeCoords(modelInfo), 1));
        end

        function [V, F, midPoints, edgePoints, out] = surfaceMesh(modelInfo, familyName)
            V = zeros(0, 3);
            F = zeros(0, 3);
            midPoints = zeros(0, 3);
            edgePoints = zeros(0, 3);
            out = [];
            fam = plotter.polyscope.ModelAdapter.families(modelInfo);
            if ~isfield(fam, familyName), return; end
            S = fam.(familyName);
            if ~isstruct(S) || ~isfield(S, 'Cells') || isempty(S.Cells) || ...
               ~isfield(S, 'CellTypes') || isempty(S.CellTypes)
                return;
            end
            P = plotter.polyscope.ModelAdapter.nodeCoords(modelInfo);
            out = plotter.utils.VTKElementTriangulator.triangulate( ...
                P, double(S.CellTypes), double(S.Cells));
            if isempty(out) || ~isfield(out, 'Points') || isempty(out.Points)
                out = [];
                return;
            end
            V = out.Points;
            F = out.Triangles;
            if isfield(out, 'MidPoints')
                midPoints = out.MidPoints;
            end
            if isfield(out, 'EdgePoints')
                edgePoints = out.EdgePoints;
            end
        end

        function [V, tets, hexes, cells, cellIds, edgePoints, surfOut] = volumeMesh(modelInfo, familyName, needEdgePoints)
            V = zeros(0, 3);
            tets = zeros(0, 4);
            hexes = zeros(0, 8);
            cells = zeros(0, 8);
            cellIds = zeros(0, 1);
            edgePoints = zeros(0, 3);
            surfOut = [];

            if nargin < 3 || isempty(needEdgePoints)
                needEdgePoints = true;
            end

            fam = plotter.polyscope.ModelAdapter.families(modelInfo);
            if ~isfield(fam, familyName), return; end
            S = fam.(familyName);
            if ~isstruct(S) || ~isfield(S, 'Cells') || isempty(S.Cells) || ...
               ~isfield(S, 'CellTypes') || isempty(S.CellTypes)
                return;
            end

            P = plotter.polyscope.ModelAdapter.nodeCoords(modelInfo);
            out = plotter.utils.VTKElementTriangulator.volumize( ...
                P, double(S.CellTypes), double(S.Cells));
            if isempty(out) || ~isfield(out, 'Points') || isempty(out.Points)
                return;
            end

            V = out.Points;
            if isfield(out, 'Tets'), tets = out.Tets; end
            if isfield(out, 'Hexes'), hexes = out.Hexes; end
            if isfield(out, 'Cells'), cells = out.Cells; end
            if isfield(out, 'RegisterCellIds')
                cellIds = out.RegisterCellIds;
            elseif isfield(out, 'CellIds')
                cellIds = out.CellIds;
            end

            if ~needEdgePoints
                return;
            end
            surfOut = plotter.utils.VTKElementTriangulator.triangulate( ...
                P, double(S.CellTypes), double(S.Cells));
            if isfield(surfOut, 'EdgePoints')
                edgePoints = surfOut.EdgePoints;
            end
        end

        function [nodes, edges] = edgePointsToCurveNetwork(edgePoints)
            %EDGEPOINTSTOCURVENETWORK Convert NaN-separated edge polylines to
            %a Polyscope curve network (nodes + edge connectivity).
            nodes = zeros(0, 3);
            edges = zeros(0, 2);
            if isempty(edgePoints), return; end

            valid = ~any(isnan(edgePoints), 2);
            if ~any(valid), return; end

            rowToNode = zeros(size(edgePoints, 1), 1);
            rowToNode(valid) = 1:nnz(valid);
            nodes = edgePoints(valid, :);

            idx = find(valid);
            % connect consecutive valid rows; NaN rows break the chain
            keep = (diff(idx) == 1);
            if any(keep)
                edges = [rowToNode(idx(1:end-1)), rowToNode(idx(2:end))];
                edges = edges(keep, :);
            end
        end

        function [nodes, edges] = triangleEdgesToCurveNetwork(V, F)
            nodes = zeros(0, 3);
            edges = zeros(0, 2);
            if isempty(V) || isempty(F), return; end

            F = double(F);
            valid = all(isfinite(F), 2) & all(F >= 1, 2) & all(F <= size(V, 1), 2);
            F = round(F(valid, :));
            if isempty(F), return; end

            edges = [F(:, [1 2]); F(:, [2 3]); F(:, [3 1])];
            edges = sort(edges, 2);
            edges = unique(edges, 'rows', 'stable');
            nodes = V;
        end

        function [Pfixed, fixedTags] = fixedNodes(modelInfo)
            modelInfo = plotter.polyscope.ModelAdapter.modelSnapshot_(modelInfo);
            P = plotter.polyscope.ModelAdapter.nodeCoords(modelInfo);
            tags = plotter.polyscope.ModelAdapter.nodeTags(modelInfo);
            Pfixed = zeros(0, 3);
            fixedTags = zeros(0, 1);

            if ~isfield(modelInfo, 'Fixed') || ~isstruct(modelInfo.Fixed)
                return;
            end
            F = modelInfo.Fixed;

            if isfield(F, 'Coords') && ~isempty(F.Coords)
                Pfixed = plotter.polyscope.ModelAdapter.pad3(double(F.Coords));
                Pfixed = Pfixed - plotter.polyscope.ModelAdapter.geometryCenter(modelInfo);
                if isfield(F, 'NodeTags')
                    fixedTags = double(F.NodeTags(:));
                end
                return;
            end

            if isfield(F, 'NodeTags') && ~isempty(F.NodeTags)
                fixedTags = double(F.NodeTags(:));
                idx = plotter.polyscope.ModelAdapter.tagsToIdx(fixedTags, tags);
                valid = idx > 0;
                Pfixed = P(idx(valid), :);
                fixedTags = fixedTags(valid);
                return;
            end

            if isfield(F, 'NodeIndex') && ~isempty(F.NodeIndex)
                idx = double(F.NodeIndex(:));
                valid = idx >= 1 & idx <= size(P,1);
                Pfixed = P(idx(valid), :);
                fixedTags = tags(idx(valid));
            end
        end

        function edges = mpConstraintEdges(modelInfo)
            modelInfo = plotter.polyscope.ModelAdapter.modelSnapshot_(modelInfo);
            edges = zeros(0, 2);
            if ~isfield(modelInfo, 'MPConstraint') || ~isstruct(modelInfo.MPConstraint)
                return;
            end
            mp = modelInfo.MPConstraint;
            if ~isfield(mp, 'Cells') || isempty(mp.Cells)
                return;
            end
            cells = double(mp.Cells);
            edges = plotter.polyscope.ModelAdapter.cellsToLineEdges(cells, modelInfo);
            edges = plotter.polyscope.ModelAdapter.keepValidEdges_( ...
                edges, size(plotter.polyscope.ModelAdapter.nodeCoords(modelInfo), 1));
        end

        function cellsOut = normalizeCells(~, cells)
            cellsOut = double(cells);
        end

        function edges = cellsToLineEdges(cells, modelInfo)
            edges = zeros(0, 2);
            if isempty(cells), return; end
            cells = double(cells);
            [nRows, nCols] = size(cells);
            nNode = size(plotter.polyscope.ModelAdapter.nodeCoords(modelInfo), 1);

            % First pass: count valid segments per row to preallocate.
            segCounts = zeros(nRows, 1);
            for i = 1:nRows
                row = cells(i, :);
                row = row(isfinite(row));

                if nCols > 2
                    n = row(1);
                    if isfinite(n) && n >= 2 && numel(row) >= n + 1
                        ids = row(2:1+n);
                    else
                        ids = row(row >= 1);
                    end
                else
                    ids = row;
                end

                ids = round(ids(ids >= 1 & ids <= nNode));
                segCounts(i) = max(0, numel(ids) - 1);
            end

            total = sum(segCounts);
            if total == 0, return; end
            edges = zeros(total, 2);

            pos = 0;
            for i = 1:nRows
                if segCounts(i) == 0, continue; end
                row = cells(i, :);
                row = row(isfinite(row));

                if nCols > 2
                    n = row(1);
                    if isfinite(n) && n >= 2 && numel(row) >= n + 1
                        ids = row(2:1+n);
                    else
                        ids = row(row >= 1);
                    end
                else
                    ids = row;
                end

                ids = round(ids(ids >= 1 & ids <= nNode));
                nSeg = segCounts(i);
                edges(pos + 1:pos + nSeg, :) = [ids(1:end-1).', ids(2:end).'];
                pos = pos + nSeg;
            end
        end

        function c = geometryCenter(modelInfo)
            P = plotter.polyscope.ModelAdapter.rawNodeCoords(modelInfo);
            if isempty(P)
                c = [0, 0, 0];
                return;
            end
            mn = min(P, [], 1, 'omitnan');
            mx = max(P, [], 1, 'omitnan');
            c = (mn + mx) / 2;
            if any(~isfinite(c))
                c = [0, 0, 0];
            end
        end

        function L = modelLength(modelInfo)
            P = plotter.polyscope.ModelAdapter.nodeCoords(modelInfo);
            L = plotter.polyscope.ModelAdapter.computeLength(P);
        end

        function idx = tagsToIdx(queryTags, allTags)
            idx = zeros(numel(queryTags), 1);
            if isempty(queryTags) || isempty(allTags), return; end
            queryTags = double(queryTags(:));
            allTags   = double(allTags(:));
            mp = containers.Map(num2cell(allTags), num2cell((1:numel(allTags))'));
            keys = num2cell(queryTags);
            exists = isKey(mp, keys);
            if any(exists)
                idx(exists) = cell2mat(values(mp, keys(exists)));
            end
        end

    end

    methods (Static)

        function P = pad3(P)
            if isempty(P), P = zeros(0, 3); return; end
            if size(P, 2) < 3, P(:, 3) = 0; end
            if size(P, 2) > 3, P = P(:, 1:3); end
        end

    end

    methods (Static, Access = private)

        function modelInfo = modelSnapshot_(modelInfo)
            % A response with model updates stores one ModelInfo per segment.
            % Geometry helpers operate on a single segment; callers that need
            % another segment already pass that snapshot explicitly.
            if numel(modelInfo) > 1
                modelInfo = modelInfo(1);
            end
        end

        function edges = keepValidEdges_(edges, nNode)
            if isempty(edges), return; end
            good = all(isfinite(edges), 2) & all(edges >= 1, 2) & all(edges <= nNode, 2);
            edges = edges(good, :);
        end

        function L = computeLength(P)
            if isempty(P), L = 1; return; end
            ext = max(P, [], 1, 'omitnan') - min(P, [], 1, 'omitnan');
            ext = ext(isfinite(ext));
            L = max(ext);
            if ~isfinite(L) || L <= 0, L = 1; end
        end

    end
end
