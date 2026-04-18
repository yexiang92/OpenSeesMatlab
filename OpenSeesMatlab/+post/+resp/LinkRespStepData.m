classdef LinkRespStepData < post.resp.ResponseBase
    % LinkRespStepData  Collect link/zero-length element responses step by step.
    %
    % Response types
    % --------------
    %   basicDeformation  [nEle x 6]   UX,UY,UZ,RX,RY,RZ  (local coords)
    %   basicForce        [nEle x 6]
    %
    % DOF padding rule
    % ----------------
    %   2-D elements with 3 components: [d1, d2, 0, 0, 0, d3]
    %   Fewer than 6 components: zero-padded to 6.
    %   More than 6 components: truncated to 6.
    %
    % Performance notes
    % -----------------
    %   * Both response arrays are pre-allocated [nEle x 6] before the loop.
    %   * eleNodes / nodeCoord queries for ndim are cached on first encounter.

    % =====================================================================
    properties (Constant)
        RESP_NAME = 'LinkResponses'
        DOFS      = {'Ux','Uy','Uz','Rx','Ry','Rz'}
    end

    % =====================================================================
    properties
        eleTags     double   % [1 x nEle]

        % Per-element cache: eleTag -> int32 ndim (2 or 3)
        eleNdimCache  containers.Map
    end

    % =====================================================================
    methods

        function obj = LinkRespStepData(ops, eleTags, varargin)
            obj@post.resp.ResponseBase(ops, varargin{:});

            obj.eleTags      = double(eleTags(:).');
            obj.eleNdimCache = containers.Map('KeyType','double','ValueType','int32');

            obj.addRespDataOneStep(obj.eleTags);
        end

        % -----------------------------------------------------------------
        function addRespDataOneStep(obj, eleTags)
            if nargin < 2 || isempty(eleTags)
                eleTags = obj.eleTags;
            end
            eleTags = double(eleTags(:).');
            nEle    = numel(eleTags);

            % ---- pre-allocate [nEle x 6] --------------------------------
            defos  = zeros(nEle, 6, 'double');
            forces = zeros(nEle, 6, 'double');

            defoNames  = {'basicDeformations','basicDeformation', ...
                          'deformations','deformation', ...
                          'basicDisplacements','basicDisplacement'};
            forceNames = {'basicForces','basicForce'};

            % ---- element loop -------------------------------------------
            for i = 1:nEle
                tag = eleTags(i);

                % cache ndim
                if ~isKey(obj.eleNdimCache, tag)
                    nds  = double(obj.ops.eleNodes(tag));
                    crd  = double(obj.ops.nodeCoord(nds(1)));
                    obj.eleNdimCache(tag) = int32(numel(crd));
                end
                ndim = double(obj.eleNdimCache(tag));

                defos(i,:)  = link_get_resp(obj.ops, tag, defoNames,  ndim);
                forces(i,:) = link_get_resp(obj.ops, tag, forceNames, ndim);
            end

            S = struct( ...
                'eleTags',          eleTags(:), ...
                'basicDeformation', defos, ...
                'basicForce',       forces);

            obj.addStepData(S);
        end
    end

    % =====================================================================
    methods (Access = protected)
        function [parts, metaFields] = preProcessParts(obj, parts)
            [parts, metaFields] = obj.alignPartsByTags(parts, 'eleTags');
        end
    end

    % =====================================================================
    methods (Static)
        function S = readResponse(data, options)
            arguments
                data
                options.eleTags  double = []
                options.respType string = ""
            end

            if ~isfield(data, "eleTags")
                S = struct();
                return;
            end

            allRespTypes = {'basicDeformation','basicForce'};

            if strlength(options.respType) > 0
                rt = char(options.respType);
                if ~ismember(rt, allRespTypes)
                    error('readResponse:InvalidRespType', ...
                        'Unknown respType "%s". Valid: %s', rt, strjoin(allRespTypes,', '));
                end
                respTypes = {rt};
            else
                respTypes = allRespTypes;
            end

            allEleTags = double(data.eleTags(:).');
            selectAll  = isempty(options.eleTags);

            if selectAll
                eleIdx       = [];
                selectedTags = allEleTags;
            else
                queryTags = double(options.eleTags(:).');
                [tf, eleIdx] = ismember(queryTags, allEleTags);
                if ~all(tf)
                    error('readResponse:InvalidEleTags', ...
                        'Element tags not found: %s', mat2str(queryTags(~tf)));
                end
                selectedTags = allEleTags(eleIdx);
            end

            S             = struct();
            S.ModelUpdate = data.ModelUpdate;
            S.time        = data.time;
            S.eleTags     = selectedTags(:);

            dofs = post.resp.LinkRespStepData.DOFS;

            for k = 1:numel(respTypes)
                rt = respTypes{k};
                if ~isfield(data, rt); continue; end
                d  = data.(rt);
                if isempty(d) || ~isnumeric(d); continue; end

                nd = ndims(d);
                if ~selectAll
                    idx    = repmat({':'}, 1, nd);
                    idx{2} = eleIdx;
                    d      = d(idx{:});
                end

                nDof = min(size(d, 3), numel(dofs));
                S.(rt) = struct();
                for di = 1:nDof
                    S.(rt).(dofs{di}) = d(:, :, di);
                end
            end
        end
    end
end

% =========================================================================
% Single-element response fetch with padding / truncation
% =========================================================================

function out = link_get_resp(ops, tag, names, ndim)
    % Try each name in order; use the first non-empty response.
    raw = [];
    for k = 1:numel(names)
        raw = double(ops.eleResponse(tag, names{k}));
        if ~isempty(raw); break; end
    end

    n = numel(raw);

    if n == 0
        out = zeros(1, 6);
        return;
    end

    % 2-D element returning 3 DOFs: map [d1,d2,d3] -> [d1,d2,0,0,0,d3]
    if ndim == 2 && n == 3
        out    = zeros(1, 6);
        out(1) = raw(1);
        out(2) = raw(2);
        out(6) = raw(3);
        return;
    end

    % General: pad or truncate to exactly 6
    out = zeros(1, 6);
    m   = min(n, 6);
    out(1:m) = raw(1:m);
end