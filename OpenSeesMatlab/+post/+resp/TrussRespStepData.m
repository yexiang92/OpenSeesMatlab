classdef TrussRespStepData < post.resp.ResponseBase
    % TrussRespStepData  Collect truss element responses step by step.
    %
    % Response types  (all scalar per element)
    % -----------------------------------------
    %   axialForce  [nEle x 1]
    %   axialDefo   [nEle x 1]
    %   Stress      [nEle x 1]
    %   Strain      [nEle x 1]

    % =====================================================================
    properties (Constant)
        RESP_NAME = 'TrussResponses'
    end

    % =====================================================================
    properties
        eleTags   double   % [1 x nEle]
    end

    % =====================================================================
    methods

        function obj = TrussRespStepData(ops, eleTags, varargin)
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

            % Pre-allocate – all scalar per element
            forces  = zeros(nEle, 1, 'double');
            defos   = zeros(nEle, 1, 'double');
            stresses = zeros(nEle, 1, 'double');
            strains  = zeros(nEle, 1, 'double');

            for i = 1:nEle
                tag = eleTags(i);

                forces(i)   = truss_scalar(obj.ops.eleResponse(tag, 'axialForce'));
                defos(i)    = truss_scalar(obj.ops.eleResponse(tag, 'basicDeformation'));
                stresses(i) = truss_scalar(obj.ops.eleResponse(tag, 'material', '1', 'stress'));

                % strain: try material first, fall back to section deformation
                sv = double(obj.ops.eleResponse(tag, 'material', '1', 'strain'));
                if isempty(sv)
                    sv = double(obj.ops.eleResponse(tag, 'section', '1', 'deformation'));
                end
                strains(i) = truss_scalar(sv);
            end

            S = struct( ...
                'eleTags',    eleTags(:), ...
                'axialForce', forces, ...
                'axialDefo',  defos, ...
                'Stress',     stresses, ...
                'Strain',     strains);

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

            allRespTypes = {'axialForce','axialDefo','Stress','Strain'};

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

                S.(rt) = d;
            end
        end
    end
end

% =========================================================================
% Helper: extract first scalar from eleResponse output, default 0
% =========================================================================

function v = truss_scalar(raw)
    raw = double(raw);
    if isempty(raw)
        v = 0.0;
    else
        v = raw(1);
    end
end