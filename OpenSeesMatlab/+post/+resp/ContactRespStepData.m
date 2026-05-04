classdef ContactRespStepData < post.resp.ResponseBase
    % ContactRespStepData  Collect contact element responses step by step.
    %
    % Response types
    % --------------
    %   globalForces  [nEle x 3]   Px, Py, Pz  (global coords, constrained node)
    %   localForces   [nEle x 3]   N, Tx, Ty   (local coords)
    %   localDisp     [nEle x 3]   N, Tx, Ty
    %   slips         [nEle x 2]   Tx, Ty
    %
    % Print output from OpenSees is suppressed during collection because
    % some contact element implementations emit diagnostic text.
    %
    % Performance
    % -----------
    %   The raw MEX handle (mex_) is cached at construction time. All
    %   eleResponse calls in the element loop use mex_ directly, bypassing
    %   ops wrapper method-dispatch overhead. suppressPrint stays on ops
    %   as it is a control command called once per step.

    % =====================================================================
    properties (Constant)
        RESP_NAME   = 'ContactResponses'
        GLOBAL_DOFS = {'Px','Py','Pz'}
        LOCAL_DOFS  = {'N','Tx','Ty'}
        SLIP_DOFS   = {'Tx','Ty'}
    end

    % =====================================================================
    properties
        eleTags   double   % [1 x nEle]
    end

    % =====================================================================
    properties (Access = private)
    end

    % =====================================================================
    methods

        function obj = ContactRespStepData(ops, eleTags, varargin)
            obj@post.resp.ResponseBase(ops, varargin{:});



            obj.eleTags = double(eleTags(:).');
            obj.addRespDataOneStep(obj.eleTags);
        end

        % -----------------------------------------------------------------
        function addRespDataOneStep(obj, eleTags)
            if nargin < 2 || isempty(eleTags)
                eleTags = obj.eleTags;
            end
            eleTags = double(eleTags(:).');
            nEle    = numel(eleTags);

            globalForces = zeros(nEle, 3, 'double');
            localForces  = zeros(nEle, 3, 'double');
            localDisp    = zeros(nEle, 3, 'double');
            slips        = zeros(nEle, 2, 'double');

            % suppressPrint is a control command — stays on ops.
            obj.ops.suppressPrint(true);
            cleaner = onCleanup(@() obj.ops.suppressPrint(false));

            mex_ = obj.mex_;   % local alias avoids repeated property lookup

            for i = 1:nEle
                tag = eleTags(i);

                globalForces(i,:) = contact_format_global( ...
                    contact_try_resp(mex_, tag, {'force','forces'}));

                localDisp(i,:) = contact_format_local( ...
                    contact_try_resp(mex_, tag, {'localDisplacement','localDispJump'}));

                localForces(i,:) = contact_format_local( ...
                    contact_try_resp(mex_, tag, {'localForce','localForces','forcescalars','forcescalar'}));

                slips(i,:) = contact_format_slip( ...
                    contact_try_resp(mex_, tag, {'slip'}));
            end

            S = struct( ...
                'eleTags',      eleTags(:), ...
                'globalForces', globalForces, ...
                'localForces',  localForces, ...
                'localDisp',    localDisp, ...
                'slips',        slips);

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

            allRespTypes = {'globalForces','localForces','localDisp','slips'};

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

            dofsMap = struct( ...
                'globalForces', {{post.resp.ContactRespStepData.GLOBAL_DOFS}}, ...
                'localForces',  {{post.resp.ContactRespStepData.LOCAL_DOFS}}, ...
                'localDisp',    {{post.resp.ContactRespStepData.LOCAL_DOFS}}, ...
                'slips',        {{post.resp.ContactRespStepData.SLIP_DOFS}});

            for k = 1:numel(respTypes)
                rt = respTypes{k};
                if ~isfield(data, rt); continue; end
                d  = data.(rt);
                if isempty(d) || ~isnumeric(d); continue; end

                if ~selectAll
                    nd  = ndims(d);
                    idx = repmat({':'}, 1, nd);
                    idx{2} = eleIdx;
                    d = d(idx{:});
                end

                dofs = dofsMap.(rt);
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
% Response query helpers
% =========================================================================

function raw = contact_try_resp(mex_, tag, names)
    % mex_ : raw MEX handle — no ops wrapper overhead per eleResponse call.
    % Try each name in order; return first non-empty result (as double row).
    for k = 1:numel(names)
        raw = mex_('eleResponse', tag, names{k});
        if ~isempty(raw)
            raw = raw(:).';
            return;
        end
    end
    raw = [];
end

% -------------------------------------------------------------------------

function out = contact_format_local(raw)
    n = numel(raw);
    if     n == 0, out = [0, 0, 0];
    elseif n == 2, out = [raw(1), raw(2), 0];
    else,          out = [raw(1), raw(2), raw(3)];
    end
end

function out = contact_format_global(raw)
    n = numel(raw);
    if     n == 0, out = [0, 0, 0];
    elseif n == 2, out = [raw(1), raw(2), 0];
    elseif n >= 3, out = [raw(n-2), raw(n-1), raw(n)];
    end
end

function out = contact_format_slip(raw)
    n = numel(raw);
    if     n == 0, out = [0, 0];
    elseif n == 1, out = [raw(1), raw(1)];
    else,          out = [raw(1), raw(2)];
    end
end
