classdef SupportGlyphs
    %SUPPORTGLYPHS Build SAP-like support symbols from nodal restraint DOFs.

    methods (Static)
        function [V, E, tags, rows] = build(modelInfo, nodePositions, scale)
            V = zeros(0, 3); E = zeros(0, 2); tags = zeros(0, 1); rows = zeros(0, 1);
            if nargin < 3 || isempty(scale), scale = 1; end
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

            % In a 2-D OpenSees model DOF 3 is Rz, not Uz. The collector
            % stores OpenSees DOF numbers, so remap them to spatial glyphs.
            isPlanar = size(nodePositions, 2) < 3 || ...
                (max(nodePositions(:, 3)) - min(nodePositions(:, 3)) < 1e-10 * max(1, scale));
            if isPlanar && isfield(modelInfo, 'Nodes') && isfield(modelInfo.Nodes, 'Ndf')
                ndf = double(modelInfo.Nodes.Ndf(:));
                for i = 1:numel(rows)
                    if rows(i) <= numel(ndf) && ndf(rows(i)) == 3
                        raw3 = dofs(i, 3);
                        dofs(i, 3) = false;
                        dofs(i, 6) = raw3;
                    end
                end
            end

            for i = 1:numel(rows)
                [v, e] = plotter.polyscope.SupportGlyphs.one_(nodePositions(rows(i), :), dofs(i, 1:6), scale);
                E = [E; e + size(V, 1)]; %#ok<AGROW>
                V = [V; v]; %#ok<AGROW>
            end
        end
    end

    methods (Static, Access = private)
        function [V, E] = one_(p, d, s)
            V = zeros(0, 3); E = zeros(0, 2);
            trans = logical(d(1:3)); rot = logical(d(4:6));
            if all(trans) && all(rot)
                q = 0.42 * s;
                C = p + q * [-1,-1,-1; 1,-1,-1; 1,1,-1; -1,1,-1; ...
                              -1,-1, 1; 1,-1, 1; 1,1, 1; -1,1, 1];
                E0 = [1,2;2,3;3,4;4,1;5,6;6,7;7,8;8,5;1,5;2,6;3,7;4,8];
                V = C; E = E0; return;
            end
            if all(trans) && ~any(rot)
                q = 0.62 * s; z = [0,0,1];
                B = p - q*z + q*[-0.7,-0.7,0; 0.7,-0.7,0; 0.7,0.7,0; -0.7,0.7,0];
                V = [p; B]; E = [1,2;1,3;1,4;1,5;2,3;3,4;4,5;5,2]; return;
            end
            axes3 = eye(3);
            for k = find(trans)
                a = axes3(k, :); [u, ~] = plotter.polyscope.SupportGlyphs.perp_(a);
                e = p - 0.70*s*a;
                [V, E] = plotter.polyscope.SupportGlyphs.addSegments_(V, E, ...
                    [p; e; e-0.24*s*u; e+0.24*s*u], [1,2;3,4]);
            end
            for k = find(rot)
                a = axes3(k, :); [u, v] = plotter.polyscope.SupportGlyphs.perp_(a);
                n = 20; th = linspace(0, 2*pi, n+1).';
                ring = p + 0.38*s*(cos(th)*u + sin(th)*v);
                [V, E] = plotter.polyscope.SupportGlyphs.addSegments_(V, E, ring, [(1:n).',(2:n+1).']);
            end
            if isempty(V), V = p; E = zeros(0,2); end
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
