classdef NodalRespStepData < post.resp.ResponseBase
    % NodalRespStepData  Collect nodal responses step by step.
    %
    % Model-update / adaptive-mesh support
    % -------------------------------------
    % When modelUpdate = true, nodes may be added or removed between steps.
    % Each step struct stores a 'nodeTags' column vector alongside the
    % response arrays.  Before merging, local_align_parts_by_tags expands
    % every step to the global union of all node tags; entries that were
    % absent in a given step are filled with NaN.  This guarantees that
    % after merging, dimension 2 of every response array corresponds to a
    % fixed, globally consistent node ordering.
    %
    % Caching strategy
    % ----------------
    % ops.nodeCoord is called only to obtain ndim (space dimension), which
    % never changes for a given node tag.  After the first query the result
    % is stored in nodeNdimCache and reused for every subsequent step,
    % eliminating repeated ops.nodeCoord calls.
    %
    % ndim is collected once per step into a plain double vector before the
    % reaction loops, so the cache is queried exactly nNode times per step
    % instead of 3*nNode times.
    %
    % Performance
    % -----------
    % The raw MEX handle (mex_) is cached at construction time and passed
    % to all local helper functions.  This bypasses the ops wrapper's method
    % dispatch overhead (~2-5 µs per call) on every nodeDisp, nodeVel,
    % nodeAccel, nodeReaction, nodePressure, and nodeCoord query.

    properties (Constant)
        RESP_NAME = 'NodalResponses'
        DOF_NAMES = {'ux','uy','uz','rx','ry','rz'}
    end

    properties
        node_tags        double
        interpolate_beam logical = false
        npts_per_ele     double  = 6
        model_info
        attrs            struct

        % nodeTag -> ndim  (populated on first encounter, never invalidated)
        nodeNdimCache
    end

    properties (Access = private)
    end

    methods

        % -----------------------------------------------------------------
        function obj = NodalRespStepData(ops, node_tags, interpolate_beam, ...
                model_info, varargin)

            obj@post.resp.ResponseBase(ops, varargin{:});

            if nargin < 2 || isempty(node_tags)
                tmp = obj.mex_('getNodeTags');
                obj.node_tags = tmp(:).';
            else
                obj.node_tags = node_tags(:).';
            end

            if nargin < 3 || isempty(interpolate_beam)
                interpolate_beam = false;
            end

            % A positive integer is treated as npts_per_ele, not a logical flag.
            if isnumeric(interpolate_beam) && isscalar(interpolate_beam) && ...
                    interpolate_beam == floor(interpolate_beam) && ...
                    interpolate_beam ~= 0 && ~islogical(interpolate_beam)
                obj.interpolate_beam = true;
                obj.npts_per_ele     = interpolate_beam;
            else
                obj.interpolate_beam = logical(interpolate_beam);
                obj.npts_per_ele     = 6;
            end

            if nargin < 4 || isempty(model_info)
                model_info = [];
            end
            obj.model_info = model_info;

            if obj.interpolate_beam && isempty(model_info)
                error('NodalRespStepData:MissingModelInfo', ...
                    'model_info must be provided when interpolate_beam is true.');
            end

            obj.attrs = struct( ...
                'UX', 'Displacement in X direction', ...
                'UY', 'Displacement in Y direction', ...
                'UZ', 'Displacement in Z direction', ...
                'RX', 'Rotation about X axis',       ...
                'RY', 'Rotation about Y axis',       ...
                'RZ', 'Rotation about Z axis');

            obj.nodeNdimCache = containers.Map('KeyType','double','ValueType','double');

            obj.addRespDataOneStep(obj.node_tags, obj.model_info);
        end

        % -----------------------------------------------------------------
        function addRespDataOneStep(obj, node_tags, model_info)
            if nargin < 2 || isempty(node_tags)
                node_tags  = obj.node_tags;
            end
            if nargin < 3
                model_info = obj.model_info;
            end

            node_tags = node_tags(:).';

            if ~isempty(model_info) && isstruct(model_info) && ...
               isfield(model_info, 'Nodes') && isfield(model_info.Nodes, 'UnusedTags') && ...
               ~isempty(model_info.Nodes.UnusedTags)
                unusedTags = model_info.Nodes.UnusedTags;
                unusedTags = unique(unusedTags(isfinite(unusedTags))).';
                node_tags  = node_tags(~ismember(node_tags, unusedTags));
            end

            % Pass mex_ to all local helpers — zero method-dispatch overhead
            [disp_, vel_, accel_, pressure_] = ...
                local_get_nodal_resp(obj.mex_, node_tags, obj.dtype, obj.nodeNdimCache);

            [reacts_, reacts_inertia_, rayleigh_forces_] = ...
                local_get_nodal_react(obj.mex_, node_tags, obj.dtype, obj.nodeNdimCache);

            % nodeTags stored as a column vector so StructMerger treats it
            % as a meta field (shape [nNode x 1]) and does not try to concat
            % it along the time axis.  The tag-alignment pre-pass in
            % buildDataset will later expand every step to the global union.
            S = struct( ...
                'nodeTags',           node_tags(:),    ...
                'disp',               disp_,           ...
                'vel',                vel_,            ...
                'accel',              accel_,          ...
                'reaction',           reacts_,         ...
                'reactionIncInertia', reacts_inertia_, ...
                'rayleighForces',     rayleigh_forces_,...
                'pressure',           pressure_);

            if obj.interpolate_beam
                Sinterp = obj.interpolate_beam_disp(model_info, disp_, node_tags);
                if ~isempty(Sinterp)
                    fn = fieldnames(Sinterp);
                    for i = 1:numel(fn)
                        S.(fn{i}) = Sinterp.(fn{i});
                    end
                end
            end

            obj.addStepData(S);
        end

        % -----------------------------------------------------------------
        function out = interpolate_beam_disp(obj, model_info, disp_vectors, node_tags)
            [points, response, cells, coords] = local_interpolator_nodal_disp( ...
                model_info, node_tags, disp_vectors, obj.npts_per_ele);

            if isempty(points) && isempty(response) && isempty(cells)
                out = [];
                return;
            end

            out = struct( ...
                'interpolatePoints', points,   ...
                'interpolateDisp',   response, ...
                'interpolateCells',  cells,    ...
                'interpolateCoords', coords);
        end

    end % public methods

    % =====================================================================
    methods (Access = protected)
        function [parts, metaFields] = preProcessParts(obj, parts)
            [parts, metaFields] = obj.alignPartsByTags(parts, 'nodeTags');
        end
    end

    % =====================================================================
    methods (Static)

        function S = readResponse(data, options)
            %READRESPONSE Read merged nodal response data using an array-oriented interface.

            arguments
                data
                options.nodeTags double = []
                options.respType string = ""
            end

            if ~isfield(data, 'nodeTags')
                S = struct();
                return;
            end

            DOFs = {'ux','uy','uz','rx','ry','rz'};
            respTypes = {'disp','vel','accel','reaction','reactionIncInertia', ...
                        'rayleighForces','pressure'};

            % Filter to one response type if requested
            if strlength(options.respType) > 0
                if ~ismember(options.respType, respTypes)
                    error('readResponse:InvalidRespType', ...
                        'Unknown respType "%s". Valid types: %s', ...
                        options.respType, strjoin(respTypes, ', '));
                end
                respTypes = {char(options.respType)};
            end

            % Resolve requested node subset
            allNodeTags = data.nodeTags(:).';
            selectAll   = isempty(options.nodeTags);

            if selectAll
                selectedTags = allNodeTags;
                nodeIdx = [];
            else
                queryTags = double(options.nodeTags(:).');
                [tf, nodeIdx] = ismember(queryTags, allNodeTags);
                if ~all(tf)
                    missing = queryTags(~tf);
                    error('readResponse:InvalidNodeTags', ...
                        'Node tags not found in data: %s', mat2str(missing));
                end
                selectedTags = allNodeTags(nodeIdx);
            end

            S = struct();
            S.ModelUpdate = data.ModelUpdate;
            S.time        = data.time.';
            S.nodeTags    = selectedTags(:);

            for k = 1:numel(respTypes)
                rt = respTypes{k};
                if ~isfield(data, rt), continue; end

                d = data.(rt);

                if strcmp(rt, 'pressure')
                    if ismatrix(d)
                        if ~selectAll, d = d(:, nodeIdx); end
                    elseif ndims(d) == 3
                        if ~selectAll, d = d(:, nodeIdx, :); end
                        d = d(:, :, 1);
                    else
                        continue;
                    end
                    S.pressure = d;
                else
                    if ndims(d) ~= 3, continue; end
                    if ~selectAll, d = d(:, nodeIdx, :); end

                    nDOF = min(size(d, 3), numel(DOFs));
                    S.(rt) = struct();
                    for di = 1:nDOF
                        S.(rt).(DOFs{di}) = d(:, :, di);
                    end
                end
            end

            % Pass through interpolation arrays without node filtering
            if isfield(data, 'interpolatePoints')
                S.interpolatePoints = data.interpolatePoints;
                if isfield(data, 'interpolateDisp'),   S.interpolateDisp   = data.interpolateDisp;   end
                if isfield(data, 'interpolateCells'),  S.interpolateCells  = data.interpolateCells;  end
                if isfield(data, 'interpolateCoords'), S.interpolateCoords = data.interpolateCoords; end
            end
        end

    end % static methods

end % classdef


% ============================================================================
% ndim cache helpers
% ============================================================================

function ndim = local_get_ndim(mex_, tag, ndimCache)
% Return cached ndim for tag; call mex_('nodeCoord', tag) on first encounter.
    if ~ndimCache.isKey(tag)
        ndimCache(tag) = numel(mex_('nodeCoord', tag));
    end
    ndim = ndimCache(tag);
end


function ndims = local_collect_ndims(mex_, node_tags, ndimCache)
% Collect ndim for all node tags into a plain double vector.
% Querying once before the reaction loops avoids 3*nNode Map lookups.
    n     = numel(node_tags);
    ndims = zeros(1, n);
    for i = 1:n
        ndims(i) = local_get_ndim(mex_, node_tags(i), ndimCache);
    end
end


% ============================================================================
% Nodal response collection
% ============================================================================

function [node_disp, node_vel, node_accel, node_pressure] = ...
        local_get_nodal_resp(mex_, node_tags, dtype, ndimCache)
% Retrieve nodal displacements, velocities, accelerations, and pressures.
% mex_ is the raw MEX function handle — no wrapper method dispatch overhead.

    n             = numel(node_tags);
    node_disp     = zeros(n, 6);
    node_vel      = zeros(n, 6);
    node_accel    = zeros(n, 6);
    node_pressure = zeros(n, 1);

    for i = 1:n
        tag  = node_tags(i);
        ndim = local_get_ndim(mex_, tag, ndimCache);

        [d, v, a] = local_dof_to_6( ...
            mex_('nodeDisp',  tag), ...
            mex_('nodeVel',   tag), ...
            mex_('nodeAccel', tag), ndim);

        node_disp(i, :)  = d;
        node_vel(i, :)   = v;
        node_accel(i, :) = a;

        p = mex_('nodePressure', tag);
        if ~isempty(p)
            node_pressure(i) = p(1);
        end
    end

    node_disp     = cast(node_disp,     dtype.floatType);
    node_vel      = cast(node_vel,      dtype.floatType);
    node_accel    = cast(node_accel,    dtype.floatType);
    node_pressure = cast(node_pressure, dtype.floatType);
end


function [reacts, reacts_inertia, rayleigh_forces] = ...
        local_get_nodal_react(mex_, node_tags, dtype, ndimCache)
% Retrieve standard, Rayleigh, and inertia reaction forces.
%
% ndims is pre-collected once and shared across the three reaction loops,
% reducing Map lookups from 3*nNode to nNode per step.

    n               = numel(node_tags);
    reacts          = zeros(n, 6);
    reacts_inertia  = zeros(n, 6);
    rayleigh_forces = zeros(n, 6);

    ndims = local_collect_ndims(mex_, node_tags, ndimCache);

    mex_('reactions');
    for i = 1:n
        reacts(i, :) = local_react_to_6( ...
            mex_('nodeReaction', node_tags(i)), ndims(i));
    end

    mex_('reactions', '-rayleigh');
    for i = 1:n
        rayleigh_forces(i, :) = local_react_to_6( ...
            mex_('nodeReaction', node_tags(i)), ndims(i));
    end

    mex_('reactions', '-dynamic');
    for i = 1:n
        reacts_inertia(i, :) = local_react_to_6( ...
            mex_('nodeReaction', node_tags(i)), ndims(i));
    end

    reacts          = cast(reacts,          dtype.floatType);
    reacts_inertia  = cast(reacts_inertia,  dtype.floatType);
    rayleigh_forces = cast(rayleigh_forces, dtype.floatType);
end


function out6 = local_react_to_6(fo, ndim)
% Map a nodeReaction vector of arbitrary length to a fixed 1-by-6 row.
    out6 = zeros(1, 6);
    ndf  = numel(fo);
    if ndf == 0, return; end

    if ndim == 2 && ndf >= 3
        out6([1, 2, 6]) = fo(1:3);
    elseif ndim == 3 && ndf == 4
        out6([1, 2, 3, 6]) = fo(1:4);
    else
        m = min(ndf, 6);
        out6(1:m) = fo(1:m);
    end
end


function [d, v, a] = local_dof_to_6(disp_, vel_, accel_, ndim)
% Map nodal response vectors to fixed-length 1-by-6 rows.
    d = zeros(1, 6);  v = zeros(1, 6);  a = zeros(1, 6);

    ndf = numel(disp_);
    if ndf == 0, return; end

    if ndim <= 1
        d(1) = disp_(1);  v(1) = vel_(1);  a(1) = accel_(1);

    elseif ndim == 2
        if ndf == 2
            d(1:2) = disp_(1:2);  v(1:2) = vel_(1:2);  a(1:2) = accel_(1:2);
        elseif ndf >= 3
            d([1,2,6]) = disp_(1:3);  v([1,2,6]) = vel_(1:3);  a([1,2,6]) = accel_(1:3);
        else
            d(1) = disp_(1);  v(1) = vel_(1);  a(1) = accel_(1);
        end

    else  % 3-D
        if ndf == 4
            d([1,2,3,6]) = disp_(1:4);
            v([1,2,3,6]) = vel_(1:4);
            a([1,2,3,6]) = accel_(1:4);
        else
            m = min(ndf, 6);
            d(1:m) = disp_(1:m);  v(1:m) = vel_(1:m);  a(1:m) = accel_(1:m);
        end
    end
end


% ============================================================================
% Beam interpolation  (pure MATLAB — no MEX calls, unchanged)
% ============================================================================

function [points, response, cells, coords] = local_interpolator_nodal_disp( ...
        model_info, node_tags, disp_vectors, npts_per_ele)
% Interpolate nodal displacements onto beam/link/truss line elements.

    points = []; response = []; cells = []; coords = [];

    if nargin < 4 || isempty(npts_per_ele), npts_per_ele = 6; end
    if isempty(model_info) || ~isstruct(model_info), return; end

    allNodeTags = model_info.Nodes.Tags(:);
    nodeCoord   = model_info.Nodes.Coords;
    if isempty(allNodeTags) || isempty(nodeCoord), return; end

    nCols = size(nodeCoord, 2);
    if nCols < 3
        nodeCoord(:, nCols+1:3) = NaN;
    elseif nCols > 3
        nodeCoord = nodeCoord(:, 1:3);
    end

    if size(nodeCoord, 1) ~= numel(allNodeTags)
        error('local_interpolator_nodal_disp:NodeSizeMismatch', ...
            'model_info.Nodes.Tags and model_info.Nodes.Coords size mismatch.');
    end

    usedNodeTags = double(node_tags(:));
    [tf, loc]    = ismember(usedNodeTags, allNodeTags);
    if ~all(tf)
        dd = usedNodeTags(~tf);
        error('local_interpolator_nodal_disp:MissingNodeTags', ...
            'node_tags not in model_info.Nodes.Tags: %s', ...
            mat2str(dd(:).'));
    end
    usedNodeCoord = nodeCoord(loc, :);
    dispNodeTags  = usedNodeTags;

    fam = struct();
    if isfield(model_info,'Elements') && isfield(model_info.Elements,'Families') ...
            && isstruct(model_info.Elements.Families)
        fam = model_info.Elements.Families;
    end

    cellAll = zeros(0,2); axs = zeros(0,3); ays = zeros(0,3); azs = zeros(0,3);

    for famName = {'Beam','Link','Truss'}
        famName = famName{1}; %#ok<FXSET>
        if ~isfield(fam, famName) || isempty(fam.(famName)), continue; end
        S = fam.(famName);
        if ~isstruct(S) || ~isfield(S,'Cells') || isempty(S.Cells), continue; end

        A = double(S.Cells);
        if     size(A,2) >= 3, c = A(:,end-1:end);
        elseif size(A,2) == 2, c = A;
        else, continue;
        end

        nEle = size(c,1);
        if any(c(:) < 1) || any(c(:) > numel(allNodeTags))
            error('local_interpolator_nodal_disp:InvalidConnectivity', ...
                'Element connectivity index out of range.');
        end

        cellNodeTags      = reshape(allNodeTags(c(:)), size(c));
        [tfCell, locCell] = ismember(cellNodeTags, dispNodeTags);
        keep = all(tfCell, 2);
        if ~any(keep), continue; end

        cKeep   = locCell(keep,:);
        nKeep   = size(cKeep, 1);
        isTruss = strcmp(famName, 'Truss');
        [ax, ay, az] = local_read_axes(S, nEle, keep, nKeep, cKeep, usedNodeCoord, isTruss);

        cellAll = [cellAll; cKeep]; %#ok<AGROW>
        axs = [axs; ax]; ays = [ays; ay]; azs = [azs; az]; %#ok<AGROW>
    end

    if isempty(cellAll), return; end

    interp    = post.utils.Beam3DDispInterpolator(usedNodeCoord, cellAll, axs, ays, azs);
    local_vec = interp.globalToLocalEnds(disp_vectors, 'ignore');
    [points, response, cells] = interp.interpolate(local_vec, npts_per_ele, 'ignore');
    coords = points;
end


function [ax, ay, az] = local_read_axes(S, nEle, keep, nKeep, cKeep, nodeCoord, isTruss)
    if isTruss
        ax = zeros(nKeep,3); ay = zeros(nKeep,3); az = zeros(nKeep,3);
        return;
    end
    ax = local_read_axis_field(S, 'XAxis', nEle, keep);
    ay = local_read_axis_field(S, 'YAxis', nEle, keep);
    az = local_read_axis_field(S, 'ZAxis', nEle, keep);

    missingX = all(abs(ax) < eps, 2) | any(isnan(ax), 2);
    if any(missingX)
        dx = nodeCoord(cKeep(missingX,2),:) - nodeCoord(cKeep(missingX,1),:);
        L  = sqrt(sum(dx.^2, 2));
        derived = zeros(sum(missingX), 3);
        good    = L > 0;
        derived(good,:)  = dx(good,:) ./ L(good);
        ax(missingX,:)   = derived;
    end
end


function out = local_read_axis_field(S, fieldName, nEle, keep)
    nKeep = sum(keep);
    if isfield(S, fieldName) && ~isempty(S.(fieldName))
        A = double(S.(fieldName));
        if size(A,1) == nEle && size(A,2) == 3
            out = A(keep,:);
            return;
        end
    end
    out = zeros(nKeep, 3);
end
