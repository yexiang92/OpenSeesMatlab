classdef SupportGlyphs
    %SUPPORTGLYPHS Build SAP-like support symbols from nodal restraint DOFs.

    methods (Static)
        function [V, E, tags, rows] = build(modelInfo, nodePositions, scale, allowedRows)
            V = zeros(0, 3); E = zeros(0, 2); tags = zeros(0, 1); rows = zeros(0, 1);
            if nargin < 3 || isempty(scale), scale = 1; end
            if nargin < 4, allowedRows = []; end
            if ~isfield(modelInfo, 'Fixed') || ~isstruct(modelInfo.Fixed), return; end
            F = modelInfo.Fixed;
            nNode = size(nodePositions, 1);
            allTags = plotter.polyscope.ModelAdapter.nodeTags(modelInfo);
            if isfield(F, 'NodeIndex') && ~isempty(F.NodeIndex)
                rows = round(double(F.NodeIndex(:)));
            elseif isfield(F, 'NodeTags') && ~isempty(F.NodeTags)
                rows = plotter.polyscope.ModelAdapter.tagsToIdx(double(F.NodeTags(:)), allTags);
            else
                return;
            end
            valid = rows >= 1 & rows <= nNode;
            if ~isempty(allowedRows)
                valid = valid & ismember(rows,round(double(allowedRows(:))));
            end
            rows = rows(valid);
            if isempty(rows), return; end
            if isfield(F, 'NodeTags') && ~isempty(F.NodeTags)
                t = double(F.NodeTags(:)); t = t(1:min(numel(t), numel(valid)));
                tags = t(valid(1:numel(t)));
            else
                tags = allTags(rows);
            end
            if isfield(F, 'Dofs') && ~isempty(F.Dofs)
                dofs = logical(F.Dofs);
                if isvector(dofs) && numel(rows) == 1, dofs = reshape(dofs, 1, []); end
                dofs = dofs(1:min(size(dofs, 1), numel(valid)), :);
                dofs = dofs(valid(1:size(dofs, 1)), :);
            else
                dofs = true(numel(rows), 3);
            end
            if size(dofs, 1) < numel(rows), dofs(end+1:numel(rows), 1:6) = false; end
            if size(dofs, 2) < 6, dofs(:, end+1:6) = false; end

            % A model-length based size is useful for sparse frames but can
            % overlap badly along a finely meshed continuum boundary. Cap it
            % by the representative spacing of the restrained nodes.
            scale = plotter.polyscope.SupportGlyphs.spacingLimitedScale_( ...
                nodePositions(rows, :), scale);

            % Spatial dimension must come from Ndm, never Ndf. In particular,
            % 3-D solids and trusses commonly use Ndf=3 (Ux,Uy,Uz); treating
            % that as a 2-D frame node collapses their support glyphs.
            geometryIsPlanar = size(nodePositions, 2) < 3 || ...
                (max(nodePositions(:, 3)) - min(nodePositions(:, 3)) < 1e-10 * max(1, scale));
            planarRows = repmat(geometryIsPlanar, numel(rows), 1);
            if isfield(modelInfo, 'Nodes') && isfield(modelInfo.Nodes, 'Ndm') && ...
                    ~isempty(modelInfo.Nodes.Ndm)
                ndm = double(modelInfo.Nodes.Ndm(:));
                for i = 1:numel(rows)
                    if rows(i) <= numel(ndm) && isfinite(ndm(rows(i)))
                        planarRows(i) = ndm(rows(i)) <= 2;
                    end
                end
            end
            % Only in a true 2-D model does OpenSees DOF 3 mean Rz rather
            % than Uz. Remap it after the spatial classification above.
            for i = 1:numel(rows)
                if planarRows(i)
                    raw3 = dofs(i, 3);
                    dofs(i, 3) = false;
                    dofs(i, 6) = raw3;
                end
            end

            for i = 1:numel(rows)
                [v, e] = plotter.polyscope.SupportGlyphs.one_( ...
                    nodePositions(rows(i), :), dofs(i, 1:6), scale, planarRows(i));
                E = [E; e + size(V, 1)]; %#ok<AGROW>
                V = [V; v]; %#ok<AGROW>
            end
        end
    end

    methods (Static, Access = private)
        function [V, E] = one_(p, d, s, isPlanar)
            V = zeros(0, 3); E = zeros(0, 2);
            trans = logical(d(1:3)); rot = logical(d(4:6));
            if isPlanar
                if all(trans(1:2)) && rot(3)
                    [V, E] = plotter.polyscope.SupportGlyphs.fixedBox_(p, s, true);
                    return;
                elseif all(trans(1:2))
                    [V, E] = plotter.polyscope.SupportGlyphs.simpleSupport_(p, s, true);
                else
                    for k = find(trans(1:2))
                        [vt, et] = plotter.polyscope.SupportGlyphs.translationTriangle_(p, k, s, true);
                        [V, E] = plotter.polyscope.SupportGlyphs.addSegments_(V, E, vt, et);
                    end
                end
            else
                if all(trans) && all(rot)
                    [V, E] = plotter.polyscope.SupportGlyphs.fixedBox_(p, s, false);
                    return;
                elseif all(trans)
                    [V, E] = plotter.polyscope.SupportGlyphs.simpleSupport_(p, s, false);
                elseif nnz(trans) == 2
                    [V, E] = plotter.polyscope.SupportGlyphs.slider_(p, find(~trans,1), s);
                else
                    for k = find(trans)
                        [vt, et] = plotter.polyscope.SupportGlyphs.translationTriangle_(p, k, s, false);
                        [V, E] = plotter.polyscope.SupportGlyphs.addSegments_(V, E, vt, et);
                    end
                end
            end

            % Compact rings communicate restrained rotations without adding
            % another set of large intersecting support frames.
            for k = find(rot)
                if isPlanar && k ~= 3, continue; end
                [vr, er] = plotter.polyscope.SupportGlyphs.rotationRing_(p, k, 0.23*s);
                [V, E] = plotter.polyscope.SupportGlyphs.addSegments_(V, E, vr, er);
            end

            if isempty(E)
                [V, E] = plotter.polyscope.SupportGlyphs.star_(p, 0.35*s);
            end
        end

        function [V, E] = translationTriangle_(p, axisIdx, s, isPlanar)
            a = eye(3); a = a(axisIdx, :);
            if isPlanar
                u = [-a(2), a(1), 0];
            else
                [u, ~] = plotter.polyscope.SupportGlyphs.perp_(a);
            end
            base = p - 0.72*s*a;
            V = [p; base-0.30*s*u; base+0.30*s*u];
            E = [1,2;2,3;3,1];
        end

        function [V, E] = simpleSupport_(p, s, isPlanar)
            h = 0.82*s; q = 0.48*s;
            if isPlanar
                V = p + [0,0,0; -q,-h,0; q,-h,0];
                E = [1,2;1,3;2,3];
                return;
            end
            baseCenter = p - [0, 0, h];
            B = baseCenter + q*[-1,-1,0; 1,-1,0; 1,1,0; -1,1,0];
            V = [p; B; baseCenter];
            E = [1,2;1,3;1,4;1,5;2,3;3,4;4,5;5,2;2,6;3,6;4,6;5,6];
        end

        function [V, E] = fixedBox_(p, s, isPlanar)
            q = 0.31*s;
            zTop = -0.12*s; zBottom = -0.88*s;
            if isPlanar
                V = p + [-q,zTop,0; q,zTop,0; q,zBottom,0; -q,zBottom,0; ...
                         0,0,0; 0,zTop,0];
                E = [1,2;2,3;3,4;4,1;5,6];
                return;
            end

            % Clean three-dimensional fixed-end cage. A single stem joins
            % the restrained node to the box; there are no diagonal braces.
            V = p + [-q,-q,zBottom; q,-q,zBottom; q,q,zBottom; -q,q,zBottom; ...
                     -q,-q,zTop;    q,-q,zTop;    q,q,zTop;    -q,q,zTop; ...
                      0, 0,0;       0, 0,zTop];
            E = [1,2;2,3;3,4;4,1;5,6;6,7;7,8;8,5; ...
                 1,5;2,6;3,7;4,8; ...
                 9,10];
        end

        function s = spacingLimitedScale_(P, requested)
            s = max(eps, double(requested));
            P = double(P);
            P = P(all(isfinite(P), 2), :);
            if size(P, 1) < 2, return; end
            if size(P, 2) < 3, P(:, end+1:3) = 0; end
            % Adjacent distances in three lexicographic orderings provide a
            % cheap, toolbox-free estimate without forming an NxN matrix.
            nearest = inf(size(P, 1), 1);
            orders = [1 2 3; 2 3 1; 3 1 2];
            for k = 1:3
                [Q, idx] = sortrows(P, orders(k, :));
                d = sqrt(sum(diff(Q, 1, 1).^2, 2));
                good = isfinite(d) & d > max(eps, 1e-12 * s);
                ii = find(good);
                if isempty(ii), continue; end
                nearest(idx(ii)) = min(nearest(idx(ii)), d(ii));
                nearest(idx(ii + 1)) = min(nearest(idx(ii + 1)), d(ii));
            end
            nearest = nearest(isfinite(nearest) & nearest > 0);
            if isempty(nearest), return; end
            spacing = median(nearest);
            if isfinite(spacing) && spacing > 0
                s = min(s, 0.42 * spacing);
            end
        end

        function [V, E] = slider_(p, freeAxis, s)
            a = eye(3); a = a(freeAxis, :);
            [u, v] = plotter.polyscope.SupportGlyphs.perp_(a);
            center = p - 0.24*s*[0,0,1];
            n = 28; th = linspace(0, 2*pi, n+1).';
            ring = center + 0.38*s*cos(th)*u + 0.18*s*sin(th)*v;
            V = [p; center; ring];
            E = [1,2; (3:n+2).', (4:n+3).'];
        end

        function [V, E] = rotationMark_(p, axisIdx, s)
            [ring, ringEdges] = plotter.polyscope.SupportGlyphs.rotationRing_(p, axisIdx, 0.42*s);
            a = eye(3); a = a(axisIdx, :);
            V = [ring; p-0.28*s*a; p+0.28*s*a];
            E = [ringEdges; size(ring,1)+[1,2]];
        end

        function [V, E] = rotationRing_(p, axisIdx, radius)
            a = eye(3); a = a(axisIdx, :);
            [u, v] = plotter.polyscope.SupportGlyphs.perp_(a);
            n = 24; th = linspace(0, 2*pi, n+1).';
            V = p + radius*(cos(th)*u + sin(th)*v);
            E = [(1:n).', (2:n+1).'];
        end

        function [V, E] = star_(p, s)
            dirs = [eye(3); -eye(3); ...
                    1,1,1; 1,1,-1; 1,-1,1; -1,1,1; ...
                    -1,-1,-1; -1,-1,1; -1,1,-1; 1,-1,-1];
            dirs = dirs ./ vecnorm(dirs, 2, 2);
            V = [p; p + 0.52*s*dirs];
            E = [ones(size(dirs,1),1), (2:size(dirs,1)+1).'];
        end

        function [u, v] = perp_(a)
            ref = [0,0,1]; if abs(dot(a, ref)) > 0.9, ref = [0,1,0]; end
            u = cross(a, ref); u = u / norm(u); v = cross(a, u); v = v / norm(v);
        end

        function [V, E] = addSegments_(V, E, v, e)
            E = [E; e + size(V, 1)]; V = [V; v];
        end
    end
end
