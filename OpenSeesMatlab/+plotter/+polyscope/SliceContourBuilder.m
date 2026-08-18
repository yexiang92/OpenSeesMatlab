classdef SliceContourBuilder
    %SLICECONTOURBUILDER Intersect linear 3-D finite elements with a plane.

    methods (Static)
        function [V, F, values, boundaryV, boundaryE] = build(P, cellTypes, cells, nodalValues, center, normal)
            P = plotter.polyscope.ModelAdapter.pad3(double(P));
            cellTypes = double(cellTypes(:));
            cells = double(cells);
            nodalValues = double(nodalValues(:));
            center = double(center(:)).';
            normal = double(normal(:)).';
            V = zeros(0, 3); F = zeros(0, 3); values = zeros(0, 1);
            boundaryV = zeros(0, 3); boundaryE = zeros(0, 2);
            if isempty(P) || isempty(cells) || numel(normal) ~= 3 || ...
                    ~all(isfinite(normal)) || norm(normal) <= eps
                return;
            end
            normal = normal / norm(normal);
            tol = max(1, norm(max(P, [], 1) - min(P, [], 1))) * 1e-10;
            nCell = min(size(cells, 1), numel(cellTypes));
            for i = 1:nCell
                [ids, edges] = plotter.polyscope.SliceContourBuilder.cellTopology_( ...
                    cells(i, :), cellTypes(i), size(P, 1));
                if isempty(ids) || isempty(edges), continue; end
                Q = P(ids, :);
                d = (Q - center) * normal(:);
                if min(d) > tol || max(d) < -tol, continue; end
                qVal = nan(numel(ids), 1);
                validValueIds = ids <= numel(nodalValues);
                qVal(validValueIds) = nodalValues(ids(validValueIds));
                X = zeros(0, 3); C = zeros(0, 1);
                for e = 1:size(edges, 1)
                    a = edges(e, 1); b = edges(e, 2);
                    da = d(a); db = d(b);
                    if abs(da) <= tol && abs(db) <= tol
                        X = [X; Q(a, :); Q(b, :)]; %#ok<AGROW>
                        C = [C; qVal(a); qVal(b)]; %#ok<AGROW>
                    elseif abs(da) <= tol
                        X = [X; Q(a, :)]; C = [C; qVal(a)]; %#ok<AGROW>
                    elseif abs(db) <= tol
                        X = [X; Q(b, :)]; C = [C; qVal(b)]; %#ok<AGROW>
                    elseif da * db < 0
                        t = da / (da - db);
                        X = [X; Q(a, :) + t * (Q(b, :) - Q(a, :))]; %#ok<AGROW>
                        C = [C; qVal(a) + t * (qVal(b) - qVal(a))]; %#ok<AGROW>
                    end
                end
                [X, keep] = plotter.polyscope.SliceContourBuilder.uniqueRowsTol_(X, tol);
                C = C(keep);
                if size(X, 1) < 3, continue; end
                order = plotter.polyscope.SliceContourBuilder.orderOnPlane_(X, normal);
                X = X(order, :); C = C(order);
                i0 = size(V, 1);
                V = [V; X]; values = [values; C]; %#ok<AGROW>
                F = [F; i0 + [ones(size(X, 1)-2, 1), ...
                    (2:size(X, 1)-1).', (3:size(X, 1)).']]; %#ok<AGROW>
                b0 = size(boundaryV, 1);
                boundaryV = [boundaryV; X]; %#ok<AGROW>
                boundaryE = [boundaryE; b0 + [(1:size(X, 1)).', ...
                    [2:size(X, 1), 1].']]; %#ok<AGROW>
            end
            values(~isfinite(values)) = 0;
        end
    end

    methods (Static, Access = private)
        function [ids, edges] = cellTopology_(row, vtkType, nNode)
            row = row(isfinite(row));
            if isempty(row), ids = []; edges = []; return; end
            nCorner = 0;
            switch round(vtkType)
                case {10, 24} % tetra / quadratic tetra
                    nCorner = 4;
                    edges = [1 2; 2 3; 3 1; 1 4; 2 4; 3 4];
                case {12, 25, 29} % hex / quadratic / triquadratic hex
                    nCorner = 8;
                    edges = [1 2;2 3;3 4;4 1;5 6;6 7;7 8;8 5;1 5;2 6;3 7;4 8];
                otherwise
                    ids = []; edges = []; return;
            end
            if numel(row) >= nCorner + 1 && round(row(1)) >= nCorner
                row = row(2:end);
            end
            ids = round(row(1:min(nCorner, numel(row))));
            if numel(ids) ~= nCorner || any(ids < 1 | ids > nNode)
                ids = []; edges = [];
            end
        end

        function [X, keep] = uniqueRowsTol_(X, tol)
            if isempty(X), keep = zeros(0, 1); return; end
            scale = max(tol, eps);
            [~, keep] = unique(round(X / scale), 'rows', 'stable');
            keep = sort(keep);
            X = X(keep, :);
        end

        function order = orderOnPlane_(X, normal)
            [~, axisIdx] = min(abs(normal));
            basis = zeros(1, 3); basis(axisIdx) = 1;
            u = cross(normal, basis); u = u / max(norm(u), eps);
            v = cross(normal, u);
            X0 = X - mean(X, 1);
            order = sortAngle_(atan2(X0 * v(:), X0 * u(:)));
        end
    end
end

function order = sortAngle_(angle)
    [~, order] = sort(angle);
end
