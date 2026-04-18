classdef Beam3DDispInterpolator < handle
    %BEAM3DDISPINTERPOLATOR Interpolate 3D beam displacements in MATLAB style.
    %
    % Purpose
    % -------
    % This class is designed for one practical task:
    %   given beam-element end DOFs, interpolate interior translational
    %   displacements along each element for visualization/post-processing.
    %
    % Main workflow
    % -------------
    %   1) globalToLocalEnds:
    %        nodal global DOFs (..., nNodes, 6)   OR  (nNodes, 6)
    %        -> element local end DOFs (..., nEles, 12)  OR  (nEles, 12)
    %
    %   2) interpolate:
    %        element local end DOFs (..., nEles, 12)  OR  (nEles, 12)
    %        -> interior points, interior global translations, line cells
    %
    % Minimum input dimensionality
    % ----------------------------
    % Both globalToLocalEnds and interpolate now accept 2-D inputs:
    %   nodalGlobal : (nNodes, 6)     -- single step, no batch dimension
    %   endLocal    : (nEles,  12)    -- single step, no batch dimension
    % as well as the original N-D batched forms.
    %
    % Indexing rule
    % -------------
    % This MATLAB implementation uses 1-based indexing everywhere.
    %
    % Input conventions
    % -----------------
    % nodeCoords : (nNodes x 3)
    % conn       : (nEles  x 2), MATLAB 1-based node indices
    % ex, ey, ez : (nEles  x 3), element local axes in global coordinates
    %
    % Nodal DOF order
    % ---------------
    % [ux, uy, uz, rx, ry, rz]
    %
    % Element end vector order
    % ------------------------
    % [ui(1:6), uj(1:6)]
    %
    % Notes
    % -----
    % 1. Invalid-axis or zero-length elements are treated as special cases:
    %      - no local-axis rotation is performed
    %      - only two endpoints are returned in interpolate()
    % 2. All returned line cells are VTK-style:
    %      [2, point_i, point_j]
    %    but point indices are MATLAB 1-based.
    % 3. Point ordering is strictly element-major:
    %      ele1:p1...pm, ele2:p1...pm, ...

    properties (SetAccess = private)
        nodeCoords (:, 3) double
        conn       (:, 2) int64
        ex         (:, 3) double
        ey         (:, 3) double
        ez         (:, 3) double
    end

    properties (Access = private)
        Xi (:, 3) double
        Xj (:, 3) double
        dX (:, 3) double
        L  (:, 1) double
        R  (:, 3, 3) double

        invalidAxes (:, 1) logical
        zeroLength  (:, 1) logical

        shapeCache containers.Map
    end

    % =====================================================================
    methods

        function obj = Beam3DDispInterpolator(nodeCoords, conn, ex, ey, ez)
            obj.nodeCoords = double(nodeCoords);
            obj.conn       = int64(conn);
            obj.ex         = double(ex);
            obj.ey         = double(ey);
            obj.ez         = double(ez);

            nEles = size(obj.conn, 1);

            if size(obj.nodeCoords, 2) ~= 3
                error('Beam3DDispInterpolator:InvalidNodeCoords', ...
                    'nodeCoords must have size (nNodes, 3).');
            end
            if size(obj.conn, 2) ~= 2
                error('Beam3DDispInterpolator:InvalidConnectivity', ...
                    'conn must have size (nEles, 2).');
            end
            if ~isequal(size(obj.ex), [nEles, 3]) || ...
               ~isequal(size(obj.ey), [nEles, 3]) || ...
               ~isequal(size(obj.ez), [nEles, 3])
                error('Beam3DDispInterpolator:InvalidAxes', ...
                    'ex, ey, ez must each have size (nEles, 3).');
            end

            obj.shapeCache = containers.Map('KeyType','char','ValueType','any');
            obj.buildGeometryCache();
            obj.buildInvalidAxesMask();
        end

        % -----------------------------------------------------------------
        function endLocal = globalToLocalEnds(obj, nodalGlobal, nanPolicy)
            %GLOBALTOLOCALENDS Convert nodal global DOFs to local end DOFs.
            %
            % Accepts:
            %   nodalGlobal : (nNodes, 6)            2-D single step
            %   nodalGlobal : (..., nNodes, 6)        N-D batched
            %
            % Returns:
            %   endLocal    : (nEles, 12)             when input was 2-D
            %   endLocal    : (..., nEles, 12)        when input was N-D

            if nargin < 3 || isempty(nanPolicy)
                nanPolicy = 'ignore';
            end
            nanPolicy = validatestring(nanPolicy, {'ignore','propagate'});

            g     = double(nodalGlobal);
            sz    = size(g);
            was2D = (numel(sz) == 2);

            % Promote 2-D (nNodes, 6) -> 3-D (1, nNodes, 6)
            if was2D
                g  = reshape(g, [1, sz(1), sz(2)]);
                sz = size(g);
            end

            if numel(sz) < 3 || sz(end) < 6
                error('Beam3DDispInterpolator:InvalidNodalGlobal', ...
                    'nodalGlobal must have size (nNodes, >=6) or (..., nNodes, >=6).');
            end
            if sz(end-1) ~= size(obj.nodeCoords, 1)
                error('Beam3DDispInterpolator:NodeCountMismatch', ...
                    'The nNodes dimension of nodalGlobal must match nodeCoords.');
            end

            batchShape = sz(1:end-2);
            nBatch     = prod(batchShape);

            g = reshape(g, [nBatch, sz(end-1), sz(end)]);
            g = g(:, :, 1:6);

            nEles        = size(obj.conn, 1);
            endLocalFlat = zeros(nBatch, nEles, 12);

            ni = double(obj.conn(:, 1));
            nj = double(obj.conn(:, 2));

            for e = 1:nEles
                diG = squeeze(g(:, ni(e), :));   % [nBatch, 6]
                djG = squeeze(g(:, nj(e), :));

                if nBatch == 1
                    diG = reshape(diG, [1, 6]);
                    djG = reshape(djG, [1, 6]);
                end

                if strcmp(nanPolicy, 'ignore')
                    diG(isnan(diG)) = 0;
                    djG(isnan(djG)) = 0;
                end

                if obj.invalidAxes(e)
                    diL = zeros(nBatch, 6);
                    djL = zeros(nBatch, 6);
                    diL(:, 1:3) = diG(:, 1:3);
                    djL(:, 1:3) = djG(:, 1:3);
                else
                    Re  = squeeze(obj.R(e, :, :));   % [3,3]
                    diL = obj.rotate6(diG, Re);
                    djL = obj.rotate6(djG, Re);
                end

                endLocalFlat(:, e, 1:6)  = diL;
                endLocalFlat(:, e, 7:12) = djL;
            end

            endLocal = reshape(endLocalFlat, [batchShape, nEles, 12]);

            % Strip the leading singleton batch dimension added for 2-D input.
            if was2D
                endLocal = squeeze(endLocal);   % (nEles, 12)
            end
        end

        % -----------------------------------------------------------------
        function [points, response, cells] = interpolate(obj, endLocal, nptsPerEle, nanPolicy)
            %INTERPOLATE Interpolate element end vectors to interior points.
            %
            % Accepts:
            %   endLocal : (nEles, 12)            2-D single step
            %   endLocal : (..., nEles, 12)        N-D batched
            %
            % Returns:
            %   points   : (N, 3)
            %   response : (N, 3)                 when input was 2-D
            %   response : (..., N, 3)            when input was N-D
            %   cells    : (M, 3) int64, VTK-style [2, i, j]

            if nargin < 3 || isempty(nptsPerEle), nptsPerEle = 11; end
            if nargin < 4 || isempty(nanPolicy),  nanPolicy  = 'ignore'; end
            nanPolicy = validatestring(nanPolicy, {'ignore','propagate'});

            el    = double(endLocal);
            sz    = size(el);
            was2D = (numel(sz) == 2);

            % Promote 2-D (nEles, 12) -> 3-D (1, nEles, 12)
            if was2D
                el = reshape(el, [1, sz(1), sz(2)]);
                sz = size(el);
            end

            if numel(sz) < 3 || sz(end) ~= 12
                error('Beam3DDispInterpolator:InvalidEndLocal', ...
                    'endLocal must have size (nEles, 12) or (..., nEles, 12).');
            end
            if sz(end-1) ~= size(obj.conn, 1)
                error('Beam3DDispInterpolator:ElementCountMismatch', ...
                    'The nEles dimension of endLocal must match conn.');
            end

            batchShape = sz(1:end-2);
            nBatch     = prod(batchShape);
            el         = reshape(el, [nBatch, sz(end-1), 12]);

            m = double(nptsPerEle);
            if m < 2 || mod(m,1) ~= 0
                error('Beam3DDispInterpolator:InvalidNpts', ...
                    'nptsPerEle must be an integer >= 2.');
            end

            [s, L1, L2, N1, N2, N3, N4] = obj.getShapes(m);
            nEles = size(obj.conn, 1);

            % Pre-count output sizes.
            nPts = 0;  nSeg = 0;
            for e = 1:nEles
                if obj.invalidAxes(e)
                    nPts = nPts + 2;  nSeg = nSeg + 1;
                else
                    nPts = nPts + m;  nSeg = nSeg + (m - 1);
                end
            end

            points       = zeros(nPts, 3);
            responseFlat = zeros(nBatch, nPts, 3);
            cells        = zeros(nSeg, 3, 'int64');
            cells(:, 1)  = 2;

            pRow = 1;  cRow = 1;

            for e = 1:nEles
                ui = squeeze(el(:, e, 1:6));    % [nBatch, 6]
                uj = squeeze(el(:, e, 7:12));

                if nBatch == 1
                    ui = reshape(ui, [1, 6]);
                    uj = reshape(uj, [1, 6]);
                end

                Xi = obj.Xi(e, :);
                Xj = obj.Xj(e, :);

                if obj.invalidAxes(e)
                    ids = pRow:(pRow+1);
                    points(ids(1), :) = Xi;
                    points(ids(2), :) = Xj;

                    Ui = ui(:, 1:3);  Uj = uj(:, 1:3);
                    if strcmp(nanPolicy,'ignore')
                        Ui(isnan(Ui)) = 0;  Uj(isnan(Uj)) = 0;
                    end
                    responseFlat(:, ids(1), :) = reshape(Ui, [nBatch,1,3]);
                    responseFlat(:, ids(2), :) = reshape(Uj, [nBatch,1,3]);

                    cells(cRow,2) = int64(ids(1));
                    cells(cRow,3) = int64(ids(2));
                    pRow = pRow + 2;  cRow = cRow + 1;
                    continue;
                end

                ids = pRow:(pRow+m-1);
                for k = 1:m
                    points(ids(k), :) = Xi + obj.dX(e,:) * s(k);
                end

                uxi = ui(:,1); uyi = ui(:,2); uzi = ui(:,3);
                ryi = ui(:,5); rzi = ui(:,6);
                uxj = uj(:,1); uyj = uj(:,2); uzj = uj(:,3);
                ryj = uj(:,5); rzj = uj(:,6);

                uxL = obj.interpLinear(uxi, uxj, L1, L2, nanPolicy);
                uyL = obj.interpHermiteOrLinear(uyi, rzi, uyj, rzj, obj.L(e), ...
                    N1, N2, N3, N4, L1, L2, +1.0, nanPolicy);
                uzL = obj.interpHermiteOrLinear(uzi, ryi, uzj, ryj, obj.L(e), ...
                    N1, N2, N3, N4, L1, L2, -1.0, nanPolicy);

                exv = obj.ex(e,:);  eyv = obj.ey(e,:);  ezv = obj.ez(e,:);

                for k = 1:m
                    ug = uxL(:,k).*exv + uyL(:,k).*eyv + uzL(:,k).*ezv;
                    responseFlat(:, ids(k), :) = reshape(ug, [nBatch,1,3]);
                end

                for k = 1:m-1
                    cells(cRow,2) = int64(ids(k));
                    cells(cRow,3) = int64(ids(k+1));
                    cRow = cRow + 1;
                end

                pRow = pRow + m;
            end

            response = reshape(responseFlat, [batchShape, size(responseFlat,2), 3]);

            % Strip the leading singleton batch dimension added for 2-D input.
            if was2D
                response = squeeze(response);   % (N, 3)
            end
        end

        function clearShapeCache(obj)
            obj.shapeCache = containers.Map('KeyType','char','ValueType','any');
        end

        function tf = isInvalidElement(obj)
            tf = obj.invalidAxes;
        end

        function S = toStruct(obj)
            S.nodeCoords  = obj.nodeCoords;
            S.conn        = obj.conn;
            S.ex          = obj.ex;
            S.ey          = obj.ey;
            S.ez          = obj.ez;
            S.Xi          = obj.Xi;
            S.Xj          = obj.Xj;
            S.dX          = obj.dX;
            S.L           = obj.L;
            S.R           = obj.R;
            S.invalidAxes = obj.invalidAxes;
            S.zeroLength  = obj.zeroLength;
        end

    end % public methods

    % =====================================================================
    methods (Access = private)

        function buildGeometryCache(obj, tolLen)
            if nargin < 2, tolLen = 1e-14; end

            if any(obj.conn(:) < 1) || any(obj.conn(:) > size(obj.nodeCoords,1))
                error('Beam3DDispInterpolator:ConnectivityOutOfRange', ...
                    'conn must use MATLAB 1-based node indices in [1, nNodes].');
            end

            ni = double(obj.conn(:,1));
            nj = double(obj.conn(:,2));

            obj.Xi = obj.nodeCoords(ni, :);
            obj.Xj = obj.nodeCoords(nj, :);
            obj.dX = obj.Xj - obj.Xi;
            obj.L  = sqrt(sum(obj.dX.^2, 2));
            obj.zeroLength = obj.L <= tolLen;

            nEles    = size(obj.conn, 1);
            obj.R    = zeros(nEles, 3, 3);
            obj.R(:,1,:) = obj.ex;
            obj.R(:,2,:) = obj.ey;
            obj.R(:,3,:) = obj.ez;
        end

        function buildInvalidAxesMask(obj, tolAxis)
            if nargin < 2, tolAxis = 1e-14; end

            exn = sqrt(sum(obj.ex.^2, 2));
            eyn = sqrt(sum(obj.ey.^2, 2));
            ezn = sqrt(sum(obj.ez.^2, 2));

            obj.invalidAxes = (exn < tolAxis) | (eyn < tolAxis) | ...
                              (ezn < tolAxis) | obj.zeroLength;
        end

        function [s, L1, L2, N1, N2, N3, N4] = getShapes(obj, nptsPerEle)
            key = sprintf('%d', nptsPerEle);

            if isKey(obj.shapeCache, key)
                c  = obj.shapeCache(key);
                s  = c.s;  L1 = c.L1; L2 = c.L2;
                N1 = c.N1; N2 = c.N2; N3 = c.N3; N4 = c.N4;
                return;
            end

            s  = linspace(0.0, 1.0, nptsPerEle).';
            L1 = 1.0 - s;
            L2 = s;
            s2 = s.^2;  s3 = s.^3;
            N1 = 1.0 - 3.*s2 + 2.*s3;
            N2 = s   - 2.*s2 +    s3;
            N3 =       3.*s2 - 2.*s3;
            N4 =         -s2 +    s3;

            obj.shapeCache(key) = struct( ...
                's',s,'L1',L1,'L2',L2,'N1',N1,'N2',N2,'N3',N3,'N4',N4);
        end

        function d6L = rotate6(~, d6G, R)
            uL = (R * d6G(:,1:3).').';
            rL = (R * d6G(:,4:6).').';
            d6L = [uL, rL];
        end

        function out = interpLinear(~, a, b, L1, L2, nanPolicy)
            a = reshape(a, [], 1);  b = reshape(b, [], 1);
            nBatch = size(a,1);     m = numel(L1);

            if strcmp(nanPolicy,'propagate')
                out = a .* reshape(L1,[1,m]) + b .* reshape(L2,[1,m]);
                return;
            end

            out  = nan(nBatch, m);
            aOk  = isfinite(a);   bOk  = isfinite(b);
            both = aOk & bOk;

            if any(both)
                out(both,:) = a(both).*reshape(L1,[1,m]) + b(both).*reshape(L2,[1,m]);
            end
            if any(aOk & ~bOk), out(aOk & ~bOk,:) = repmat(a(aOk & ~bOk), 1, m); end
            if any(~aOk & bOk), out(~aOk & bOk,:) = repmat(b(~aOk & bOk), 1, m); end
        end

        function out = interpHermiteOrLinear(~, uI, thI, uJ, thJ, L, ...
                N1, N2, N3, N4, L1, L2, thSign, nanPolicy)
            uI  = reshape(uI,  [], 1);  thI = reshape(thI, [], 1);
            uJ  = reshape(uJ,  [], 1);  thJ = reshape(thJ, [], 1);
            nBatch = size(uI,1);  m = numel(N1);

            if strcmp(nanPolicy,'propagate')
                out = uI  .* reshape(N1,[1,m]) + ...
                      (L*thSign*thI) .* reshape(N2,[1,m]) + ...
                      uJ  .* reshape(N3,[1,m]) + ...
                      (L*thSign*thJ) .* reshape(N4,[1,m]);
                return;
            end

            out      = nan(nBatch, m);
            fullMask = isfinite(uI) & isfinite(thI) & isfinite(uJ) & isfinite(thJ);

            if any(fullMask)
                out(fullMask,:) = ...
                    uI(fullMask)  .* reshape(N1,[1,m]) + ...
                    (L*thSign*thI(fullMask)) .* reshape(N2,[1,m]) + ...
                    uJ(fullMask)  .* reshape(N3,[1,m]) + ...
                    (L*thSign*thJ(fullMask)) .* reshape(N4,[1,m]);
            end

            % Fallback: linear when rotations are unavailable.
            pm = ~fullMask;
            if any(pm)
                out(pm,:) = uI(pm).*reshape(L1,[1,m]) + uJ(pm).*reshape(L2,[1,m]);
            end
        end

    end % private methods

end % classdef