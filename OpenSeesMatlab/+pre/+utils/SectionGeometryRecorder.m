classdef SectionGeometryRecorder < handle
    properties
        CurrentSecTag double = NaN
        Data struct = struct()
    end

    methods
        function setSectionTag(obj, secTag)
            obj.CurrentSecTag = double(secTag);
            key = obj.secKey(secTag);
            if ~isfield(obj.Data, key)
                obj.Data.(key) = struct( ...
                    'Fibers', {{}}, ...
                    'Patches', {{}}, ...
                    'Layers', {{}}, ...
                    'Lines',  {{}}, ...
                    'Adds',   {{}});
            end
        end

        function addFiber(obj, y, z, area, matTag, varargin)
            if isnan(obj.CurrentSecTag)
                return;
            end

            S = struct();
            S.Type = 'fiber';
            S.y = double(y);
            S.z = double(z);
            S.area = double(area);
            S.matTag = double(matTag);
            S.Args = varargin;

            key = obj.secKey(obj.CurrentSecTag);
            obj.Data.(key).Fibers{end+1} = S;

            A = struct();
            A.Kind = 'Fiber';
            A.Index = numel(obj.Data.(key).Fibers);
            obj.Data.(key).Adds{end+1} = A;
        end

        function addPatch(obj, patchType, varargin)
            if isnan(obj.CurrentSecTag)
                return;
            end

            S = struct();
            S.Type = char(string(patchType));
            S.Args = varargin;

            key = obj.secKey(obj.CurrentSecTag);
            obj.Data.(key).Patches{end+1} = S;

            L = obj.makePatchLines(S);
            if ~isempty(L)
                obj.Data.(key).Lines = [obj.Data.(key).Lines, L];
            end

            A = struct();
            A.Kind = 'Patch';
            A.Index = numel(obj.Data.(key).Patches);
            obj.Data.(key).Adds{end+1} = A;
        end

        function addLayer(obj, layerType, varargin)
            if isnan(obj.CurrentSecTag)
                return;
            end

            S = struct();
            S.Type = char(string(layerType));
            S.Args = varargin;

            key = obj.secKey(obj.CurrentSecTag);
            obj.Data.(key).Layers{end+1} = S;

            A = struct();
            A.Kind = 'Layer';
            A.Index = numel(obj.Data.(key).Layers);
            obj.Data.(key).Adds{end+1} = A;
        end

        function plotSection(obj, secTag, ax)
            arguments
                obj
                secTag (1,1) double
                ax = []
            end

            if isempty(ax)
                figure;
                ax = axes();
            end
            hold(ax, 'on');
            axis(ax, 'equal');

            key = obj.secKey(secTag);
            if ~isfield(obj.Data, key)
                error('SectionGeometryRecorder:NotFound', ...
                    'Section tag %g not recorded.', secTag);
            end

            sec = obj.Data.(key);
            nAdd = numel(sec.Adds);

            if nAdd > 0
                % only patches participate in colormap allocation
                isPatchAdd = false(1, nAdd);
                for i = 1:nAdd
                    isPatchAdd(i) = strcmp(sec.Adds{i}.Kind, 'Patch');
                end

                nPatchAdd = sum(isPatchAdd);

                if nPatchAdd > 0
                    cmap = colormap(ax);
                    if isempty(cmap)
                        cmap = parula(64);
                    end
                    idx = round(linspace(1, size(cmap,1), nPatchAdd));
                    patchColors = cmap(idx, :);
                else
                    patchColors = zeros(0, 3);
                end

                ip = 0;
                for i = 1:nAdd
                    A = sec.Adds{i};

                    switch A.Kind
                        case 'Patch'
                            ip = ip + 1;
                            c = patchColors(ip, :);
                            obj.drawPatch(ax, sec.Patches{A.Index}, c);

                        case 'Layer'
                            obj.drawLayer(ax, sec.Layers{A.Index}, [0 0 0]);

                        case 'Fiber'
                            obj.drawFiber(ax, sec.Fibers{A.Index}, [0 0 0]);
                    end
                end
            end

            for i = 1:numel(sec.Lines)
                xy = sec.Lines{i};
                plot(ax, xy(:,1), xy(:,2), 'k-', 'LineWidth', 0.5);
            end

            xlabel(ax, 'y');
            ylabel(ax, 'z');
            title(ax, sprintf('Section %g', secTag));
            box(ax, 'on');
            grid(ax, 'off');
        end

        function clear(obj)
            obj.CurrentSecTag = NaN;
            obj.Data = struct();
        end
    end

    methods (Access = private)
        function key = secKey(~, secTag)
            key = sprintf('Sec_%d', round(secTag));
        end

        function drawFiber(~, ax, S, faceColor)
            r = sqrt(S.area / pi);
            rectangle(ax, ...
                'Position', [S.y - r, S.z - r, 2*r, 2*r], ...
                'Curvature', [1 1], ...
                'FaceColor', faceColor, ...
                'EdgeColor', 'none');
        end

        function drawPatch(~, ax, S, faceColor)
            t = lower(S.Type);
            a = S.Args;

            switch t
                case {'rect','rectangular'}
                    yi = double(a{4});
                    zi = double(a{5});
                    yj = double(a{6});
                    zj = double(a{7});

                    patch(ax, [yi yj yj yi], [zi zi zj zj], faceColor, ...
                        'FaceAlpha', 0.25, 'EdgeColor', 'none');

                case {'quad','quadr','quadrilateral'}
                    yy = double([a{4} a{6} a{8} a{10}]);
                    zz = double([a{5} a{7} a{9} a{11}]);

                    patch(ax, yy, zz, faceColor, ...
                        'FaceAlpha', 0.25, 'EdgeColor', 'none');

                case {'circ','circular'}
                    yc   = double(a{4});
                    zc   = double(a{5});
                    rIn  = double(a{6});
                    rOut = double(a{7});

                    if numel(a) >= 9
                        ang1 = deg2rad(double(a{8}));
                        ang2 = deg2rad(double(a{9}));
                    else
                        ang1 = 0.0;
                        ang2 = 2*pi;
                    end

                    th = linspace(ang1, ang2, 181);
                    y1 = yc + rOut*cos(th);
                    z1 = zc + rOut*sin(th);
                    y2 = yc + rIn*cos(fliplr(th));
                    z2 = zc + rIn*sin(fliplr(th));

                    patch(ax, [y1 y2], [z1 z2], faceColor, ...
                        'FaceAlpha', 0.25, 'EdgeColor', 'none');
            end
        end

        function drawLayer(obj, ax, S, faceColor)
            t = lower(S.Type);
            a = S.Args;

            switch t
                case 'straight'
                    % {matTag, numFiber, areaFiber, yi, zi, yj, zj}
                    num  = double(a{2});
                    area = double(a{3});
                    yi   = double(a{4});
                    zi   = double(a{5});
                    yj   = double(a{6});
                    zj   = double(a{7});

                    if num <= 0
                        return;
                    end

                    y = linspace(yi, yj, num);
                    z = linspace(zi, zj, num);
                    r = sqrt(area / pi);

                    for i = 1:num
                        rectangle(ax, ...
                            'Position', [y(i)-r, z(i)-r, 2*r, 2*r], ...
                            'Curvature', [1 1], ...
                            'FaceColor', faceColor, ...
                            'EdgeColor', 'none');
                    end

                case {'circ','circular'}
                    % {matTag, numFiber, areaFiber, yc, zc, radius, ang1, ang2}
                    num  = double(a{2});
                    area = double(a{3});
                    yc   = double(a{4});
                    zc   = double(a{5});
                    rr   = double(a{6});

                    if num <= 0
                        return;
                    end

                    if numel(a) >= 8
                        ang1Deg = double(a{7});
                        ang2Deg = double(a{8});
                    else
                        ang1Deg = 0.0;
                        ang2Deg = 360.0 - 360.0/num;
                    end

                    pts = obj.arcLayerPoints(ang1Deg, ang2Deg, rr, num, yc, zc);
                    r = sqrt(area / pi);

                    for i = 1:size(pts,1)
                        rectangle(ax, ...
                            'Position', [pts(i,1)-r, pts(i,2)-r, 2*r, 2*r], ...
                            'Curvature', [1 1], ...
                            'FaceColor', faceColor, ...
                            'EdgeColor', 'none');
                    end

                case {'rect','rectangular'}
                    % {matTag, numFiberY, numFiberZ, areaFiber, yc, zc, distY, distZ}
                    numY  = double(a{2});
                    numZ  = double(a{3});
                    area  = double(a{4});
                    yc    = double(a{5});
                    zc    = double(a{6});
                    distY = double(a{7});
                    distZ = double(a{8});

                    yMin = yc - distY/2;
                    yMax = yc + distY/2;
                    zMin = zc - distZ/2;
                    zMax = zc + distZ/2;

                    pts = zeros(0,2);

                    % 4 corners
                    pts(end+1,:) = [yMin, zMin];
                    pts(end+1,:) = [yMax, zMin];
                    pts(end+1,:) = [yMax, zMax];
                    pts(end+1,:) = [yMin, zMax];

                    if numY > 0
                        yEdge = linspace(yMin, yMax, numY + 2);
                        yEdge = yEdge(2:end-1);
                        for i = 1:numel(yEdge)
                            pts(end+1,:) = [yEdge(i), zMin];
                            pts(end+1,:) = [yEdge(i), zMax];
                        end
                    end

                    if numZ > 0
                        zEdge = linspace(zMin, zMax, numZ + 2);
                        zEdge = zEdge(2:end-1);
                        for i = 1:numel(zEdge)
                            pts(end+1,:) = [yMin, zEdge(i)];
                            pts(end+1,:) = [yMax, zEdge(i)];
                        end
                    end

                    r = sqrt(area / pi);
                    for i = 1:size(pts,1)
                        rectangle(ax, ...
                            'Position', [pts(i,1)-r, pts(i,2)-r, 2*r, 2*r], ...
                            'Curvature', [1 1], ...
                            'FaceColor', faceColor, ...
                            'EdgeColor', 'none');
                    end
            end
        end

        function L = makePatchLines(obj, S)
            t = lower(S.Type);
            a = S.Args;
            L = {};

            switch t
                case {'rect','rectangular'}
                    numY = double(a{2});
                    numZ = double(a{3});
                    yi   = double(a{4});
                    zi   = double(a{5});
                    yj   = double(a{6});
                    zj   = double(a{7});

                    yg = linspace(yi, yj, numY + 1);
                    zg = linspace(zi, zj, numZ + 1);

                    for i = 1:numel(yg)
                        L{end+1} = [yg(i) zi; yg(i) zj]; %#ok<AGROW>
                    end
                    for i = 1:numel(zg)
                        L{end+1} = [yi zg(i); yj zg(i)]; %#ok<AGROW>
                    end

                case {'quad','quadr','quadrilateral'}
                    numIJ = double(a{2});
                    numJK = double(a{3});
                    yi = double(a{4});  zi = double(a{5});
                    yj = double(a{6});  zj = double(a{7});
                    yk = double(a{8});  zk = double(a{9});
                    yl = double(a{10}); zl = double(a{11});

                    yzIJ = obj.lineMesh(yi, zi, yj, zj, numIJ);
                    yzJK = obj.lineMesh(yj, zj, yk, zk, numJK);
                    yzKL = obj.lineMesh(yk, zk, yl, zl, numIJ);
                    yzLI = obj.lineMesh(yl, zl, yi, zi, numJK);

                    for i = 1:size(yzIJ,1)
                        L{end+1} = [yzIJ(i,:); yzKL(end-i+1,:)]; %#ok<AGROW>
                    end
                    for i = 1:size(yzJK,1)
                        L{end+1} = [yzJK(i,:); yzLI(end-i+1,:)]; %#ok<AGROW>
                    end

                case {'circ','circular'}
                    numCirc = double(a{2});
                    numRad  = double(a{3});
                    yc   = double(a{4});
                    zc   = double(a{5});
                    rIn  = double(a{6});
                    rOut = double(a{7});

                    if numel(a) >= 9
                        ang1 = double(a{8});
                        ang2 = double(a{9});
                    else
                        ang1 = 0.0;
                        ang2 = 360.0;
                    end

                    nodeOut = obj.arcMesh(ang1, ang2, rOut, numCirc, yc, zc);
                    nodeIn  = obj.arcMesh(ang1, ang2, rIn,  numCirc, yc, zc);

                    for i = 1:size(nodeOut,1)
                        L{end+1} = [nodeIn(i,:); nodeOut(i,:)]; %#ok<AGROW>
                    end

                    th = linspace(deg2rad(ang1), deg2rad(ang2), 181);
                    for i = 0:numRad
                        rr = rIn + (rOut - rIn) * i / numRad;
                        yy = yc + rr*cos(th);
                        zz = zc + rr*sin(th);
                        L{end+1} = [yy(:), zz(:)]; %#ok<AGROW>
                    end
            end
        end

        function pts = lineMesh(~, y1, z1, y2, z2, num)
            pts = [linspace(y1, y2, num+1).', linspace(z1, z2, num+1).'];
        end

        function pts = arcMesh(~, ang1, ang2, r, num, yc, zc)
            th = linspace(deg2rad(ang1), deg2rad(ang2), num+1).';
            pts = [yc + r*cos(th), zc + r*sin(th)];
        end

        function pts = arcLayerPoints(~, ang1Deg, ang2Deg, r, num, yc, zc)
            % OpenSees layer('circ', ...) semantics:
            % - full circle should place num unique points without duplicating start/end
            % - partial arc should include both ends

            span = ang2Deg - ang1Deg;

            if num == 1
                th = deg2rad((ang1Deg + ang2Deg) / 2);
            else
                if abs(abs(span) - 360.0) < 1e-10
                    % full circle: avoid duplicated end point
                    th = deg2rad(ang1Deg) + (0:num-1).' * deg2rad(span / num);
                else
                    % partial arc: include both ends
                    th = linspace(deg2rad(ang1Deg), deg2rad(ang2Deg), num).';
                end
            end

            pts = [yc + r*cos(th), zc + r*sin(th)];
        end
    end
end