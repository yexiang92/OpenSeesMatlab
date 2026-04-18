classdef LoadTools < handle
    % LoadTools
    % Utilities for creating nodal and element loads in OpenSees MATLAB.

    properties (SetAccess = private)
        Ops
    end

    methods
        function obj = LoadTools(ops)
            arguments
                ops
            end
            obj.Ops = ops;
        end

        % -----------------------------------------------------------------
        function nodeLoads = createGravityLoad(obj, opts)
            % Apply gravity loads derived from nodal lumped masses.

            arguments
                obj
                opts.excludeNodes double = []
                opts.direction string ...
                    {mustBeMember(opts.direction,["X","Y","Z","x","y","z"])} = "Z"
                opts.factor (1,1) double = -9.81
            end

            gravDOF = find(strcmpi(char(opts.direction), {'X','Y','Z'}), 1);

            nodeTags = double(obj.Ops.getNodeTags());
            if ~isempty(opts.excludeNodes)
                nodeTags = setdiff(nodeTags, double(opts.excludeNodes(:)).', 'stable');
            end

            nodeMass  = pre.ModelDataUtils.getNodeMass(obj.Ops);
            nodeLoads = containers.Map('KeyType','double','ValueType','any');

            for i = 1:numel(nodeTags)
                ntag = nodeTags(i);
                if ~isKey(nodeMass, ntag)
                    continue;
                end

                mass = nodeMass(ntag);
                ndof = numel(mass);
                if gravDOF > ndof
                    continue;
                end

                p = opts.factor * mass(gravDOF);
                if p == 0
                    continue;
                end

                loadVec = zeros(1, ndof);
                loadVec(gravDOF) = p;

                obj.applyNodalLoad(ntag, loadVec);
                nodeLoads(ntag) = loadVec;
            end
        end

        % -----------------------------------------------------------------
        function BeamGlobalUniformLoad(obj, eleTags, opts)
            arguments
                obj
                eleTags
                opts.wx = 0.0
                opts.wy = 0.0
                opts.wz = 0.0
            end

            [T, ndim, eleTags] = obj.buildBeamTransformMatrix(eleTags);
            nEle = numel(eleTags);

            qx = obj.expandScalar(opts.wx, nEle);
            qy = obj.expandScalar(opts.wy, nEle);
            qz = obj.expandScalar(opts.wz, nEle);

            for i = 1:nEle
                Ti = T(:,:,i);
                qG = [qx(i); qy(i); qz(i)];
                qL = Ti * qG;

                etag = eleTags(i);
                if ndim == 3
                    obj.Ops.eleLoad('-ele', etag, '-type', '-beamUniform', ...
                        qL(2), qL(3), qL(1));
                else
                    obj.Ops.eleLoad('-ele', etag, '-type', '-beamUniform', ...
                        qL(2), qL(1));
                end
            end
        end

        % -----------------------------------------------------------------
        function BeamGlobalPointLoad(obj, eleTags, opts)
            arguments
                obj
                eleTags
                opts.px = 0.0
                opts.py = 0.0
                opts.pz = 0.0
                opts.xl = 0.5
            end

            [T, ndim, eleTags] = obj.buildBeamTransformMatrix(eleTags);
            nEle = numel(eleTags);

            px = obj.expandScalar(opts.px, nEle);
            py = obj.expandScalar(opts.py, nEle);
            pz = obj.expandScalar(opts.pz, nEle);
            xl = obj.expandScalar(opts.xl, nEle);

            for i = 1:nEle
                Ti = T(:,:,i);
                pG = [px(i); py(i); pz(i)];
                pL = Ti * pG;

                etag = eleTags(i);
                x    = xl(i);

                if ndim == 3
                    obj.Ops.eleLoad('-ele', etag, '-type', '-beamPoint', ...
                        pL(2), pL(3), x, pL(1));
                else
                    obj.Ops.eleLoad('-ele', etag, '-type', '-beamPoint', ...
                        pL(2), x, pL(1));
                end
            end
        end

        % -----------------------------------------------------------------
        function SurfaceGlobalPressureLoad(obj, eleTags, p)
            % Convert uniform pressure on surface elements to equivalent
            % nodal loads in global coordinates.

            arguments
                obj
                eleTags
                p = 0.0
            end

            eleTags = obj.normalizeTags(eleTags);
            nEle    = numel(eleTags);
            pVals   = obj.expandScalar(p, nEle);

            nodalForces = containers.Map('KeyType','double','ValueType','any');
            nodalNDFs   = containers.Map('KeyType','double','ValueType','double');

            for i = 1:nEle
                etag    = eleTags(i);
                pVal    = pVals(i);
                nodeIds = double(obj.Ops.eleNodes(etag));
                nNode   = numel(nodeIds);

                verts = zeros(nNode, 3);
                for j = 1:nNode
                    c = double(obj.Ops.nodeCoord(nodeIds(j)));
                    c = obj.pad3(c);
                    verts(j,:) = c;
                end

                switch nNode
                    case 3
                        [area, normal] = obj.triAreaNormal(verts);
                    case 4
                        [area, normal] = obj.quadAreaNormal(verts);
                    otherwise
                        error('LoadTools:UnsupportedElement', ...
                            'Surface element %d has %d nodes (only 3 or 4 supported).', ...
                            etag, nNode);
                end

                eleForce     = pVal * area * normal;   % [1 x 3]
                forcePerNode = eleForce / nNode;

                for j = 1:nNode
                    ntag = nodeIds(j);

                    if isKey(nodalForces, ntag)
                        nodalForces(ntag) = nodalForces(ntag) + forcePerNode;
                    else
                        nodalForces(ntag) = forcePerNode;
                    end

                    if ~isKey(nodalNDFs, ntag)
                        ndf = double(obj.Ops.getNDF(ntag));
                        if numel(ndf) > 1
                            ndf = ndf(1);
                        end
                        nodalNDFs(ntag) = ndf;
                    end
                end
            end

            nTags = cell2mat(keys(nodalForces));
            for i = 1:numel(nTags)
                ntag = nTags(i);
                obj.applyNodalLoad(ntag, nodalForces(ntag), nodalNDFs(ntag));
            end
        end
    end

    % =====================================================================
    methods (Access = private)

        % -----------------------------------------------------------------
        function [T, ndim, eleTags] = buildBeamTransformMatrix(obj, eleTags)
            % Build [3 x 3 x nEle] transformation matrices exactly following
            % the Python implementation:
            %   T(:,:,i) = [xaxis; yaxis; zaxis]
            % and q_local = T(:,:,i) * q_global

            eleTags = obj.normalizeTags(eleTags);
            nEle    = numel(eleTags);
            T       = zeros(3, 3, nEle);
            ndim    = 2;

            for i = 1:nEle
                etag = eleTags(i);

                nodes = double(obj.Ops.eleNodes(etag));
                if isempty(nodes)
                    error('LoadTools:InvalidElement', ...
                        'Element %d has no connected nodes.', etag);
                end

                coords = double(obj.Ops.nodeCoord(nodes(1)));
                ndim_ = numel(coords);
                if ndim_ > ndim
                    ndim = ndim_;
                end

                xaxis = double(obj.Ops.eleResponse(etag, 'xaxis'));
                yaxis = double(obj.Ops.eleResponse(etag, 'yaxis'));
                zaxis = double(obj.Ops.eleResponse(etag, 'zaxis'));

                if isempty(xaxis) || isempty(yaxis) || isempty(zaxis)
                    error('LoadTools:MissingLocalAxes', ...
                        ['Element %d does not return complete local axes from eleResponse ', ...
                        '(xaxis/yaxis/zaxis). To match the Python implementation, ', ...
                        'LoadTools will not reconstruct local axes automatically.'], etag);
                end

                xaxis = obj.pad3(xaxis);
                yaxis = obj.pad3(yaxis);
                zaxis = obj.pad3(zaxis);

                T(:,:,i) = [xaxis(:).'; yaxis(:).'; zaxis(:).'];
            end
        end

        % -----------------------------------------------------------------
        function applyNodalLoad(obj, ntag, loadVec, ndf)
            % Call ops.load() expanding loadVec as individual arguments.
            if nargin < 4
                ndf = double(obj.Ops.getNDF(ntag));
                if numel(ndf) > 1
                    ndf = ndf(1);
                end
            end

            lv = zeros(1, ndf);
            nc = min(numel(loadVec), ndf);
            lv(1:nc) = loadVec(1:nc);

            args = num2cell(lv);
            obj.Ops.load(ntag, args{:});
        end

        % -----------------------------------------------------------------
        function [area, normal] = triAreaNormal(~, verts)
            a = verts(2,:) - verts(1,:);
            b = verts(3,:) - verts(2,:);  % or verts(3,:) - verts(1,:), area/normal is the same
            cp = cross(a, b);
            len = norm(cp);

            if len < 1e-14
                error('LoadTools:DegenerateTriangle', ...
                    'Degenerate triangular element (zero area).');
            end

            area   = 0.5 * len;
            normal = cp / len;
        end

        % -----------------------------------------------------------------
        function [area, normal] = quadAreaNormal(obj, verts)
            [a1, n1] = obj.triAreaNormal(verts(1:3,:));
            [a2, n2] = obj.triAreaNormal(verts([1 3 4],:));

            area = a1 + a2;

            % Python 版是 (normal1 + normal2) / 2
            % 这里做归一化更稳
            nAvg = 0.5 * (n1 + n2);
            len  = norm(nAvg);
            if len < 1e-14
                error('LoadTools:DegenerateQuad', ...
                    'Degenerate quadrilateral element (zero area).');
            end
            normal = nAvg / len;
        end

        % -----------------------------------------------------------------
        function vals = expandScalar(~, x, n)
            if isscalar(x)
                vals = repmat(double(x), n, 1);
            else
                vals = double(x(:));
                if numel(vals) ~= n
                    error('LoadTools:SizeMismatch', ...
                        'Input length must be 1 or match element count (%d).', n);
                end
            end
        end

        % -----------------------------------------------------------------
        function tags = normalizeTags(~, tags)
            tags = double(tags(:)).';
        end

        % -----------------------------------------------------------------
        function v = pad3(~, v)
            v = double(v(:)).';
            if numel(v) < 3
                v(end+1:3) = 0;
            end
            v = v(1:3);
        end
    end
end