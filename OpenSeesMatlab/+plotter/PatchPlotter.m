classdef PatchPlotter < handle
    % PatchPlotter  Patch-based MATLAB plotting helper for FE geometry.
    %
    % Renders points, line segments, and surface meshes in 2D/3D using
    % PATCH as the main primitive.
    %
    % Dimension detection
    % -------------------
    %   2D : input has 2 columns, OR 3 columns with all-zero/NaN z values.
    %   3D : otherwise.

    properties
        Ax  matlab.graphics.axis.Axes
    end

    methods

        function obj = PatchPlotter(ax)
            if nargin < 1 || isempty(ax)
                f  = figure('Color','w','Position',[200 200 1200 800]);
                ax = axes('Parent',f,'Position',[0.05 0.06 0.92 0.90]);
            end
            obj.Ax = ax;
            hold(obj.Ax,'on');
            axis(obj.Ax,'equal');
            box(obj.Ax,'on');
            grid(obj.Ax,'on');
        end

        function ax = getAxes(obj)
            ax = obj.Ax;
        end

        % -----------------------------------------------------------------
        function h = addPoints(obj, s)
            P = obj.prep(s.points);
            d = size(P,2);

            sz  = obj.getf(s,'size',36);
            mk  = obj.getf(s,'marker','o');
            col = obj.getf(s,'color',[0 0 0]);
            ec  = obj.getf(s,'edgeColor',[0 0 0]);
            fl  = obj.getf(s,'filled',true);
            tag = char(string(obj.getf(s,'tag','')));

            vals = [];
            if isfield(s,'values')  && ~isempty(s.values),  vals = s.values(:);  end
            if isfield(s,'scalars') && ~isempty(s.scalars), vals = s.scalars(:); end

            if d == 2
                if isempty(vals)
                    h = scatter(obj.Ax, P(:,1), P(:,2), sz, 'Marker', mk, 'Tag', tag, 'Clipping', 'off');
                else
                    h = scatter(obj.Ax, P(:,1), P(:,2), sz, vals(:), 'Marker', mk, 'Tag', tag, 'Clipping', 'off');
                end
            else
                if isempty(vals)
                    h = scatter3(obj.Ax, P(:,1), P(:,2), P(:,3), sz, 'Marker', mk, 'Tag', tag, 'Clipping', 'off');
                else
                    h = scatter3(obj.Ax, P(:,1), P(:,2), P(:,3), sz, vals(:), 'Marker', mk, 'Tag', tag, 'Clipping', 'off');
                end
            end

            if isempty(vals)
                if fl
                    h.MarkerFaceColor = col;
                else
                    h.MarkerFaceColor = 'none';
                end
            else
                h.MarkerFaceColor = 'flat';
                obj.applyColormapClim(s);
            end
            h.MarkerEdgeColor = ec;
        end

        % -----------------------------------------------------------------
        function h = addLine(obj, s)
            [V, F, d] = obj.parseLineGeom(s);

            x = [V(F(:,1),1), V(F(:,2),1), NaN(size(F,1),1)].';
            y = [V(F(:,1),2), V(F(:,2),2), NaN(size(F,1),1)].';

            args = {
                'Color',     obj.getf(s,'color',[0 0 0]), ...
                'Clipping',  'off', ...
                'LineWidth', obj.getf(s,'lineWidth',1.5), ...
                'LineStyle', obj.getf(s,'lineStyle','-'), ...
                'Visible',   obj.getf(s,'visible','on'), ...
                'Tag',       char(string(obj.getf(s,'tag','')))
            };

            if d == 2
                h = plot(obj.Ax, x(:), y(:), args{:});
            else
                z = [V(F(:,1),3), V(F(:,2),3), NaN(size(F,1),1)].';
                h = plot3(obj.Ax, x(:), y(:), z(:), args{:});
            end
        end

        % -----------------------------------------------------------------
        function h = addColoredLine(obj, s)
            [V, F, d, vals] = obj.parseColoredLineGeom(s);
            h = patch(obj.Ax, ...
                'Faces',           F, ...
                'Vertices',        V(:,1:d), ...
                'FaceVertexCData', vals, ...
                'FaceColor',       'none', ...
                'EdgeColor',       'interp', ...
                'Clipping',        'off', ...
                'LineWidth',       obj.getf(s,'lineWidth',2), ...
                'Visible',         obj.getf(s,'visible','on'), ...
                'Tag',             char(string(obj.getf(s,'tag',''))));
            obj.applyColormapClim(s);
        end

        % -----------------------------------------------------------------
        function h = addMesh(obj, s)
            [V, F, d] = obj.parseFaceGeom(s);
            h = patch(obj.Ax, ...
                'Faces',     F, ...
                'Vertices',  V(:,1:d), ...
                'FaceColor', obj.getf(s,'faceColor',[0.8 0.8 0.8]), ...
                'EdgeColor', 'none', ...
                'Clipping',  'off', ...
                'FaceAlpha', obj.getf(s,'faceAlpha',1), ...
                'Visible',   obj.getf(s,'visible','on'), ...
                'Tag',       char(string(obj.getf(s,'tag',''))));
        end

        % -----------------------------------------------------------------
        function h = addColoredMesh(obj, s)
            [V, F, d] = obj.parseFaceGeom(s);
            nV = size(V,1);
            nF = size(F,1);

            vals = obj.getf(s,'values',(1:nV).');
            vals = vals(:);

            if numel(vals) == nV
                fmode = 'interp';   % nodal colouring
            elseif numel(vals) == nF
                fmode = 'flat';     % face / cell colouring
            else
                error('PatchPlotter:addColoredMesh', ...
                    'values length must equal nNodes (%d) or nFaces (%d).', nV, nF);
            end

            if isfield(s,'faceColorMode') && ~isempty(s.faceColorMode)
                fmode = s.faceColorMode;
            end

            h = patch(obj.Ax, ...
                'Faces',           F, ...
                'Vertices',        V(:,1:d), ...
                'FaceVertexCData', vals, ...
                'FaceColor',       fmode, ...
                'EdgeColor',       'none', ...
                'Clipping',        'off', ...
                'FaceAlpha',       obj.getf(s,'faceAlpha',1), ...
                'Visible',         obj.getf(s,'visible','on'), ...
                'Tag',             char(string(obj.getf(s,'tag',''))));

            obj.applyColormapClim(s);
        end

        % -----------------------------------------------------------------
        function h = addWireframe(obj, s)
            [V, F, d] = obj.parseFaceGeom(s);
            E = obj.uniqueEdges(F);
            h = patch(obj.Ax, ...
                'Faces',     E, ...
                'Vertices',  V(:,1:d), ...
                'FaceColor', 'none', ...
                'EdgeColor', obj.getf(s,'color',[0 0 0]), ...
                'Clipping',  'off', ...
                'LineWidth', obj.getf(s,'lineWidth',1), ...
                'Visible',   obj.getf(s,'visible','on'), ...
                'Tag',       char(string(obj.getf(s,'tag',''))));
        end

        % -----------------------------------------------------------------
        function h = addColoredWireframe(obj, s)
            [V, F, d] = obj.parseFaceGeom(s);
            E = obj.uniqueEdges(F);
            vals = obj.getf(s,'values',[]);
            if numel(vals) ~= size(V,1)
                error('PatchPlotter:addColoredWireframe', ...
                    'values length must equal nNodes.');
            end

            h = patch(obj.Ax, ...
                'Faces',           E, ...
                'Vertices',        V(:,1:d), ...
                'FaceVertexCData', vals(:), ...
                'FaceColor',       'none', ...
                'EdgeColor',       'interp', ...
                'Clipping',        'off', ...
                'LineWidth',       obj.getf(s,'lineWidth',1.5), ...
                'Visible',         obj.getf(s,'visible','on'), ...
                'Tag',             char(string(obj.getf(s,'tag',''))));
            obj.applyColormapClim(s);
        end

        % -----------------------------------------------------------------
        function h = addArrows(obj, s)
            % Dimension follows prep(points):
            %   2D if z is all zero/NaN
            %   3D otherwise

            P = obj.prep(s.points);
            d = size(P,2);

            U = double(s.vectors);
            if ~ismatrix(U) || isempty(U)
                error('PatchPlotter:addArrows', 'vectors must be a non-empty matrix.');
            end
            if size(P,1) ~= size(U,1)
                error('PatchPlotter:addArrows', ...
                    'points and vectors must have the same number of rows.');
            end

            if d == 2
                if size(U,2) < 2
                    error('PatchPlotter:addArrows', ...
                        'For 2D arrows, vectors must have at least 2 columns.');
                end
                U = U(:,1:2);
                U(isnan(U)) = 0;
            else
                if size(U,2) == 2
                    U(:,3) = 0;
                elseif size(U,2) >= 3
                    U = U(:,1:3);
                else
                    error('PatchPlotter:addArrows', ...
                        'For 3D arrows, vectors must have at least 2 columns.');
                end
                U(isnan(U)) = 0;
            end

            sc  = obj.getf(s,'scale',1);
            col = obj.getf(s,'color',[0 0 0]);
            lw  = obj.getf(s,'lineWidth',1.5);
            hs  = obj.getf(s,'headSize',0.2);
            tag = char(string(obj.getf(s,'tag','')));

            if d == 2
                h = quiver(obj.Ax, ...
                    P(:,1), P(:,2), ...
                    sc*U(:,1), sc*U(:,2), 0, ...
                    'Color', col, ...
                    'LineWidth', lw, ...
                    'ShowArrowHead', 'on', ...
                    'Clipping',  'off');
            else
                h = quiver3(obj.Ax, ...
                    P(:,1), P(:,2), P(:,3), ...
                    sc*U(:,1), sc*U(:,2), sc*U(:,3), 0, ...
                    'Color', col, ...
                    'LineWidth', lw, ...
                    'ShowArrowHead', 'on', ...
                    'Clipping',  'off');
            end

            h.MaxHeadSize = hs;
            h.Tag = tag;
        end

        % -----------------------------------------------------------------
        function h = addNodeLabels(obj, s)
            P      = obj.prep(s.points);
            d      = size(P,2);
            labels = obj.toStringCol(obj.getf(s,'labels',1:size(P,1)), size(P,1));
            off    = obj.getf(s,'offset',[0 0 0]);
            if numel(off)==2, off(3)=0; end
            col    = obj.getf(s,'color',[0 0 0]);
            fs     = obj.getf(s,'fontSize',10);

            args = {'Color',col,'FontSize',fs, ...
                    'HorizontalAlignment','left','VerticalAlignment','middle','Clipping','off'};

            x = P(:,1) + off(1);
            y = P(:,2) + off(2);

            if d == 2
                h = text(obj.Ax, x, y, labels, args{:});
            else
                h = text(obj.Ax, x, y, P(:,3)+off(3), labels, args{:});
            end
            h = h(:);
        end

        % -----------------------------------------------------------------
        function applyDataLimits(obj, P, padRatio)
            if nargin < 3 || isempty(padRatio), padRatio = 0.05; end

            P = obj.prep(P);
            mn = min(P, [], 1, 'omitnan');
            mx = max(P, [], 1, 'omitnan');
            L  = mx - mn;
            pd = max(padRatio * L, 1e-6);

            xlim(obj.Ax, [mn(1)-pd(1), mx(1)+pd(1)]);
            ylim(obj.Ax, [mn(2)-pd(2), mx(2)+pd(2)]);

            if size(P,2) >= 3
                zlim(obj.Ax, [mn(3)-pd(3), mx(3)+pd(3)]);
            end
        end

        % -----------------------------------------------------------------
        function applyAxesStyle(obj, s)
            if obj.getf(s,'equal',true), axis(obj.Ax,'equal'); end
            box(obj.Ax,  obj.getf(s,'box','on'));
            grid(obj.Ax, obj.getf(s,'grid','on'));
            v = obj.getf(s,'view',[]);
            if ~isempty(v), view(obj.Ax, v); end
            xlabel(obj.Ax, obj.getf(s,'xlabel',''));
            ylabel(obj.Ax, obj.getf(s,'ylabel',''));
            zlabel(obj.Ax, obj.getf(s,'zlabel',''));
            title(obj.Ax,  obj.getf(s,'title',''));
        end
    end

    methods (Static)
        function demo2D()
            pp = plotter.PatchPlotter();
            pp.addLine(struct('points',[0 0;1 0;1 1;0 1],'closed',true,'color','k'));
            pp.addColoredLine(struct('points',[0 0;0.5 0.3;1.0 0.1;1.3 0.8], ...
                'values',[0;1;0.2;0.8],'lineWidth',3,'cmap',parula(256)));
            m.nodes=[0 0;1 0;1 1;0 1;0.5 1.4];
            m.tris=[1 2 3;1 3 4;4 3 5];
            m.values=[0;0.2;1;0.4;0.8];
            m.faceAlpha=0.6;
            m.cmap=parula(256);
            pp.addColoredMesh(m);
            pp.addColoredWireframe(m);
            colorbar(pp.Ax);
            title(pp.Ax,'PatchPlotter 2D Demo');
        end

        function demo3D()
            pp = plotter.PatchPlotter();
            t  = linspace(0,4*pi,120).';
            pp.addColoredLine(struct('points',[cos(t),sin(t),t/(2*pi)], ...
                'values',t/(4*pi),'lineWidth',2.5,'cmap',turbo(256)));
            [x,y] = meshgrid(linspace(-1,1,21));
            z = 0.3*sin(2*pi*x).*cos(2*pi*y);
            m.nodes=[x(:),y(:),z(:)];
            m.tris=delaunay(x(:),y(:));
            m.values=z(:);
            m.cmap=parula(256);
            pp.addColoredMesh(m);
            colorbar(pp.Ax);
            view(pp.Ax,3);
            title(pp.Ax,'PatchPlotter 3D Demo');
        end
    end

    methods (Access = private)

        function [V, F, d] = parseLineGeom(obj, s)
            if isfield(s,'nodes') && ~isempty(s.nodes) && ...
               isfield(s,'lines') && ~isempty(s.lines)
                % Explicit nodes + connectivity table — highest priority.
                V = obj.prep(s.nodes);
                F = double(s.lines);
            else
                % Points-only path: resolve vertex array first.
                if isfield(s,'nodes') && ~isempty(s.nodes)
                    V = obj.prep(s.nodes);
                else
                    V = obj.prep(s.points);
                end
                n    = size(V,1);
                kind = lower(strtrim(char(obj.getf(s,'kind',''))));
                switch kind
                    case 'segments'
                        % Every consecutive pair of rows is one independent
                        % segment: rows 1-2, rows 3-4, rows 5-6, …
                        % Odd trailing row is silently ignored.
                        nSeg = floor(n / 2);
                        F    = [2*(1:nSeg)'-1, 2*(1:nSeg)'];
                    otherwise
                        % Default: sequential polyline, optionally closed.
                        closed = isfield(s,'closed') && s.closed;
                        if closed
                            F = [(1:n)', [2:n,1]'];
                        else
                            F = [(1:n-1)', (2:n)'];
                        end
                end
            end
            d = size(V,2);
        end

        function [V, F, d, vals] = parseColoredLineGeom(obj, s)
            [V, F, d] = obj.parseLineGeom(s);
            vals = obj.getf(s,'values',linspace(0,1,size(V,1)).');
            vals = vals(:);

            nV = size(V,1);
            nF = size(F,1);

            if numel(vals) == nV
                return;
            elseif numel(vals) == nF
                V    = [V(F(:,1),:); V(F(:,2),:)];
                vals = repelem(vals,2);
                F    = reshape(1:2*nF, 2, []).';
            else
                error('PatchPlotter:parseColoredLineGeom', ...
                    'values length must equal nNodes (%d) or nSegs (%d).', nV, nF);
            end
        end

        function [V, F, d] = parseFaceGeom(obj, s)
            V = obj.prep(s.nodes);
            d = size(V,2);

            if isfield(s,'tris') && ~isempty(s.tris)
                F = double(s.tris);
            elseif isfield(s,'quads') && ~isempty(s.quads)
                F = double(s.quads);
            elseif isfield(s,'faces') && ~isempty(s.faces)
                F = double(s.faces);
            else
                error('PatchPlotter:parseFaceGeom','Provide tris, quads, or faces.');
            end
        end

        function P = prep(~, Praw)
            % 2D if:
            %   - input has 2 columns
            %   - input has 3 columns and z is all zero/NaN
            % 3D otherwise

            P = double(Praw);
            if ~ismatrix(P) || isempty(P)
                error('PatchPlotter:prep', 'Coordinates must be a non-empty matrix.');
            end

            nc = size(P,2);
            if nc == 2
                return;
            elseif nc == 3
                z = P(:,3);
                if all(isnan(z) | abs(z) < 1e-12)
                    P = P(:,1:2);
                else
                    P = P(:,1:3);
                end
            else
                error('PatchPlotter:prep', 'Coordinates must have 2 or 3 columns.');
            end
        end

        function E = uniqueEdges(~, F)
            nCol = size(F,2);
            a = F(:,1:nCol);
            b = F(:,[2:nCol,1]);
            valid = ~isnan(a) & ~isnan(b);
            a = a(valid);
            b = b(valid);
            E = unique(sort([a(:), b(:)], 2), 'rows');
        end

        function v = getf(~, s, fname, default)
            if isfield(s, fname) && ~isempty(s.(fname))
                v = s.(fname);
            else
                v = default;
            end
        end

        function applyColormapClim(obj, s)
            cmap = obj.getf(s,'cmap',[]);
            clim_ = obj.getf(s,'clim',[]);
            if ~isempty(cmap), colormap(obj.Ax, cmap); end
            if ~isempty(clim_) && numel(clim_)==2 && diff(clim_)>0
                clim(obj.Ax, clim_);
            end
        end

        function labels = toStringCol(~, labels, n)
            if isnumeric(labels), labels = string(labels); end
            labels = string(labels);
            labels = labels(:);
            if numel(labels) ~= n
                error('PatchPlotter:toStringCol', ...
                    'labels length (%d) must equal point count (%d).', numel(labels), n);
            end
        end
    end
end