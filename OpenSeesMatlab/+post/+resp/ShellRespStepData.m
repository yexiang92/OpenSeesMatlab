classdef ShellRespStepData < post.resp.ResponseBase
    % ShellRespStepData  Collect shell element responses step by step.
    %
    % Response types collected per step
    % -----------------------------------
    %   sectionForces        [nEle x nGP x 8]   FXX,FYY,FXY,MXX,MYY,MXY,VXZ,VYZ
    %   sectionDeformations  [nEle x nGP x 8]
    %   Stresses             [nEle x nGP x nFib x 5]  sigma11,22,12,23,13
    %   Strains              [nEle x nGP x nFib x 5]
    %
    % Optional nodal responses (computeNodalResp)
    % -------------------------------------------
    %   sectionForcesAtNodes        [nNode x 8]
    %   sectionDeformationsAtNodes  [nNode x 8]
    %   StressesAtNodes             [nNode x nFib x 5]
    %   StrainsAtNodes              [nNode x nFib x 5]
    %
    % Performance design
    % ------------------
    %  * All per-element metadata (nGP, nFib, nodeTags, classTag, elastic
    %    params) is resolved once on the first call and stored in typed caches.
    %  * Output arrays are pre-allocated to the known final size before the
    %    element loop; no cell-array intermediates, no grow-on-append.
    %  * Nodal accumulation uses pre-allocated dense matrices indexed by a
    %    compact integer map instead of containers.Map<tag,struct>.
    %  * The elastic stress kernel is fully vectorised over GPs (no GP loop).
    %  * squeeze / ndims calls are avoided on the hot paths; explicit
    %    reshape with known sizes is used instead.

    % =====================================================================
    properties (Constant)
        RESP_NAME   = 'ShellResponses'
        SEC_DOFS    = {'fxx','fyy','fxy','mxx','myy','mxy','vxz','vyz'}
        STRESS_DOFS = {'sxx','syy','sxy','syz','sxz'}
        STRAIN_DOFS = {'exx','eyy','exy','eyz','exz'}

        MITC9_CLASS_TAG = int32(54)
        MITC9_GP_ORDER  = int32([1,3,5,7,2,4,6,8,9])
    end

    % =====================================================================
    properties
        eleTags          double    % [1 x nEle]
        computeNodalResp logical   = false
        nodalRespMethod  char      = 'extrapolation'

        % Populated on first step
        gaussPoints      double
        fiberPoints      double
        nodeTags         double    % [1 x nNode]

        % ---- per-element caches (filled once on first encounter) --------
        % All keyed by eleTag (double).
        eleClassCache    containers.Map   % -> int32  class tag
        eleNGPCache      containers.Map   % -> int32  number of GPs (0 = no data)
        eleNFibCache     containers.Map   % -> int32  nFib (0=elastic, -1=no stress)
        eleParamCache    containers.Map   % -> struct(E,nu,h)  elastic elements only
        eleNodeCache     containers.Map   % -> [1 x nNode] double

        % Global node-index map: nodeTag(double) -> compact 1-based index(int32)
        % Built on first addRespDataOneStep; extended if model updates.
        nodeIndexMap     containers.Map
    end

    % =====================================================================
    methods

        function obj = ShellRespStepData(ops, eleTags, varargin)
            % ShellRespStepData(ops, eleTags, 'computeNodalResp', method, ...)
            [computeNodalResp, baseArgs] = shell_parse_options(varargin{:});
            obj@post.resp.ResponseBase(ops, baseArgs{:});

            obj.eleTags = double(eleTags(:).');

            obj.eleClassCache = containers.Map('KeyType','double','ValueType','int32');
            obj.eleNGPCache   = containers.Map('KeyType','double','ValueType','int32');
            obj.eleNFibCache  = containers.Map('KeyType','double','ValueType','int32');
            obj.eleParamCache = containers.Map('KeyType','double','ValueType','any');
            obj.eleNodeCache  = containers.Map('KeyType','double','ValueType','any');
            obj.nodeIndexMap  = containers.Map('KeyType','double','ValueType','int32');

            if ~isempty(computeNodalResp)
                obj.computeNodalResp = true;
                obj.nodalRespMethod  = char(computeNodalResp);
            end

            obj.addRespDataOneStep(obj.eleTags);
        end

        % -----------------------------------------------------------------
        function addRespDataOneStep(obj, eleTags)
            if nargin < 2 || isempty(eleTags)
                eleTags = obj.eleTags;
            end
            eleTags = double(eleTags(:).');
            nEle    = numel(eleTags);

            % Populate caches for first-seen elements; get array dimensions.
            [maxGP, maxFib] = shell_fill_caches(obj, eleTags);

            % ---- pre-allocate output arrays (known size, single alloc) --
            secF     = NaN(nEle, maxGP, 8,         'double');
            secD     = NaN(nEle, maxGP, 8,         'double');
            stresses = NaN(nEle, maxGP, maxFib, 5, 'double');
            strains  = NaN(nEle, maxGP, maxFib, 5, 'double');

            % ---- element loop -------------------------------------------
            for i = 1:nEle
                tag = eleTags(i);
                nGP = double(obj.eleNGPCache(tag));
                if nGP == 0; continue; end

                % section forces / deformations
                rawF = double(obj.ops.eleResponse(tag, 'stresses'));
                rawD = double(obj.ops.eleResponse(tag, 'strains'));

                sf = reshape(rawF, nGP, 8);
                sd = reshape(rawD, nGP, 8);

                if obj.eleClassCache(tag) == post.resp.ShellRespStepData.MITC9_CLASS_TAG ...
                        && nGP == 9
                    sf = sf(post.resp.ShellRespStepData.MITC9_GP_ORDER, :);
                    sd = sd(post.resp.ShellRespStepData.MITC9_GP_ORDER, :);
                end

                secF(i, 1:nGP, :) = sf;
                secD(i, 1:nGP, :) = sd;

                % stress / strain
                nFib = double(obj.eleNFibCache(tag));

                if nFib > 0
                    [ss, se] = shell_get_fiber_resp_prealloc( ...
                        obj.ops, tag, nGP, nFib);
                elseif nFib == 0
                    p = obj.eleParamCache(tag);
                    [ss, se] = shell_elastic_stress_vec(sf, p);
                    nFib = size(ss, 2);    % always 5 for elastic
                else
                    continue;              % nFib == -1: no stress data
                end

                stresses(i, 1:nGP, 1:nFib, :) = ss;
                strains (i, 1:nGP, 1:nFib, :) = se;
            end

            % ---- initialise coordinate arrays on first step -------------
            if isempty(obj.gaussPoints)
                obj.gaussPoints = 1:maxGP;
            end
            if isempty(obj.fiberPoints)
                obj.fiberPoints = 1:maxFib;
            end

            % ---- optional GP -> node projection -------------------------
            if obj.computeNodalResp
                [nSecF, nSecD, nStress, nStrain, nTags] = ...
                    shell_get_nodal_resp(obj, eleTags, ...
                        secF, secD, stresses, strains);
                obj.nodeTags = nTags;
            end

            % ---- assemble step struct -----------------------------------
            S = struct( ...
                'eleTags',          eleTags(:), ...
                'SecForceAtGP',     secF, ...
                'SecDefoAtGP',      secD, ...
                'StressAtGP',       stresses, ...
                'StrainAtGP',       strains);

            if obj.computeNodalResp
                S.SecForceAtNode  = nSecF;
                S.SecDefoAtNode   = nSecD;
                S.StressAtNode    = nStress;
                S.StrainAtNode    = nStrain;
                S.nodeTags        = nTags(:);
            end

            obj.addStepData(S);
        end
    end

    % =====================================================================
    methods (Access = protected)
        function [parts, metaFields] = preProcessParts(obj, parts)
            groupSpecs = struct( ...
                'tagField', {'eleTags', 'nodeTags'}, ...
                'alignedFields', {{'SecForceAtGP', 'SecDefoAtGP', 'StressAtGP', 'StrainAtGP'}, ...
                                  {'SecForceAtNode', 'SecDefoAtNode', 'StressAtNode', 'StrainAtNode'}});
            [parts, metaFields] = obj.alignPartsByTagGroups(parts, groupSpecs);
        end
    end

    % =====================================================================
    methods (Static)
        function S = readResponse(data, options)
            arguments
                data
                options.eleTags  double = []
                options.nodeTags double = []
                options.respType string = ""
            end

            if ~isfield(data, "eleTags")
                S = struct();
                return;
            end

            allRespTypes = { ...
                'SecForceAtGP','SecDefoAtGP', ...
                'StressAtGP','StrainAtGP', ...
                'SecForceAtNode','SecDefoAtNode', ...
                'StressAtNode','StrainAtNode'};

            secDofs    = {'fxx','fyy','fxy','mxx','myy','mxy','vxz','vyz'};
            stressDofs = {'sxx','syy','sxy','syz','sxz'};
            strainDofs = {'exx','eyy','exy','eyz','exz'};

            respTypes = post.resp.ResponseBase.resolveRespTypes(allRespTypes, options.respType);

            allEleTags = double(data.eleTags(:).');
            [selectedTags, eleIdx] = post.resp.ResponseBase.resolveTagSelection( ...
                allEleTags, options.eleTags, 'readResponse:InvalidEleTags', 'Element');
            selectAllEle = isempty(options.eleTags);

            nodeTypes = {'SecForceAtNode','SecDefoAtNode','StressAtNode','StrainAtNode'};
            [hasNodeTags, selectedNodeTags, nodeIdx] = post.resp.ResponseBase.resolveOptionalDataTagSelection( ...
                data, 'nodeTags', options.nodeTags, respTypes, nodeTypes, ...
                'readResponse:MissingNodeTags', 'readResponse:InvalidNodeTags', 'Node');
            selectAllNode = isempty(options.nodeTags);

            S             = struct();
            S.ModelUpdate = data.ModelUpdate;
            S.time        = data.time;
            S.eleTags     = selectedTags(:);

            if hasNodeTags
                S.nodeTags = selectedNodeTags(:);
            end

            eleTypes  = {'SecForceAtGP','SecDefoAtGP','StressAtGP','StrainAtGP'};

            for k = 1:numel(respTypes)
                rt = respTypes{k};
                if ~isfield(data, rt); continue; end
                d = data.(rt);
                if isempty(d) || ~isnumeric(d); continue; end

                isStrainType = ismember(rt, {'StrainAtGP','StrainAtNode'});
                isStressType = ismember(rt, {'StressAtGP','StressAtNode'});
                if isStrainType
                    dofs = strainDofs;
                elseif isStressType
                    dofs = stressDofs;
                else
                    dofs = secDofs;
                end

                if ~selectAllNode && ismember(rt, nodeTypes)
                    d = post.resp.ResponseBase.subsetSecondDim(d, nodeIdx);
                end

                if ~selectAllEle && ismember(rt, eleTypes)
                    d = post.resp.ResponseBase.subsetSecondDim(d, eleIdx);
                end

                nd   = ndims(d);
                nDof = min(size(d, nd), numel(dofs));
                S.(rt) = struct();
                for di = 1:nDof
                    idx2 = repmat({':'}, 1, nd);
                    idx2{nd} = di;
                    S.(rt).(dofs{di}) = d(idx2{:});
                end
            end
        end
    end
end

% =========================================================================
% Cache population  (one-time per element, determines array pre-alloc sizes)
% =========================================================================

function [maxGP, maxFib] = shell_fill_caches(obj, eleTags)
    % Fills eleClassCache, eleNGPCache, eleNFibCache, eleParamCache,
    % eleNodeCache for every tag not yet seen.
    %
    % Returns maxGP and maxFib across ALL cached elements so that
    % pre-allocated arrays remain consistent across steps.

    needParam = false;

    for i = 1:numel(eleTags)
        tag = eleTags(i);

        % Shell connectivity may change under model-update analyses, so
        % refresh the current-step node list every pass while keeping the
        % GP/fiber metadata cached.
        nds = double(obj.ops.eleNodes(tag));
        obj.eleNodeCache(tag) = nds(:).';

        if isKey(obj.eleNGPCache, tag); continue; end   % already resolved

        % class tag
        ct = int32(ops_scalar(obj.ops.getEleClassTags(tag)));
        obj.eleClassCache(tag) = ct;

        % probe nGP via stresses
        rawF = double(obj.ops.eleResponse(tag, 'stresses'));
        if isempty(rawF)
            obj.eleNGPCache(tag)  = int32(0);
            obj.eleNFibCache(tag) = int32(-1);
            continue;
        end
        nGP = int32(numel(rawF) / 8);
        obj.eleNGPCache(tag) = nGP;

        % probe fiber count at GP-1, fiber-1
        s1 = obj.ops.eleResponse(tag, 'Material', 1, 'fiber', 1, 'stresses');
        if ~isempty(s1)
            % count remaining fibers
            nFib = int32(1);
            for k = 2:2000
                if isempty(obj.ops.eleResponse(tag, 'Material', 1, ...
                        'fiber', k, 'stresses'))
                    break;
                end
                nFib = int32(k);
            end
            obj.eleNFibCache(tag) = nFib;
        else
            obj.eleNFibCache(tag) = int32(0);   % elastic: compute analytically
            needParam = true;
        end
    end

    % Retrieve elastic parameters under print suppression
    if needParam
        obj.ops.suppressPrint(true);
        cleaner = onCleanup(@() obj.ops.suppressPrint(false));
        for i = 1:numel(eleTags)
            tag = eleTags(i);
            if obj.eleNFibCache(tag) ~= 0; continue; end
            if isKey(obj.eleParamCache, tag); continue; end
            p.E  = shell_get_param(obj.ops, tag, 'E');
            p.nu = shell_get_param(obj.ops, tag, 'nu');
            p.h  = shell_get_param(obj.ops, tag, 'h');
            if p.E <= 0 || p.nu < 0 || p.h <= 0
                obj.eleNFibCache(tag) = int32(-1);  % override: no stress
            else
                obj.eleParamCache(tag) = p;
            end
        end
    end

    % Compute max dimensions over all cached elements
    allNGP  = cell2mat(values(obj.eleNGPCache));    % int32 vector
    allNFib = cell2mat(values(obj.eleNFibCache));   % int32 vector

    maxGP  = double(max([allNGP(:);  int32(0)]));
    % elastic elements use 5 through-thickness points
    hasElastic = any(allNFib == 0);
    validFibs  = allNFib(allNFib > 0);
    maxFib = double(max([validFibs(:); int32(5 * hasElastic); int32(1)]));
end

% =========================================================================
% Fiber stress query  (pre-allocated, no cell arrays)
% =========================================================================

function [ss, se] = shell_get_fiber_resp_prealloc(ops, tag, nGP, nFib)
    % ss, se : [nGP x nFib x 5]  NaN-initialised
    ss = NaN(nGP, nFib, 5, 'double');
    se = NaN(nGP, nFib, 5, 'double');

    for j = 1:nGP
        for k = 1:nFib
            s = double(ops.eleResponse(tag, 'Material', j, ...
                                        'fiber', k, 'stresses'));
            e = double(ops.eleResponse(tag, 'Material', j, ...
                                        'fiber', k, 'strains'));
            if isempty(s); break; end
            ss(j, k, :) = s;
            se(j, k, :) = e;
        end
    end
end

% =========================================================================
% Elastic stress kernel  (fully vectorised over GPs)
% =========================================================================

function [ss, se] = shell_elastic_stress_vec(sf, p)
    % sf : [nGP x 8]  section forces
    % p  : struct(E, nu, h)
    % ss, se : [nGP x 5 x 5]
    %   dim-2  = 5 through-thickness points (xs = linspace(-h/2, h/2, 5))
    %   dim-3  = [sigma11, sigma22, sigma12, sigma23, sigma13]

    G    = 0.5 * p.E / (1.0 + p.nu);
    xs   = linspace(-p.h/2, p.h/2, 5);   % [1 x 5]
    invH = 1.0 / p.h;
    w    = 12.0 / (p.h ^ 3);
    invE = 1.0 / p.E;
    invG = 1.0 / G;

    % sf(:,col) is [nGP x 1]; xs is [1 x 5] -> outer product -> [nGP x 5]
    s11 = sf(:,1)*invH - w * (sf(:,4) * xs);
    s22 = sf(:,2)*invH - w * (sf(:,5) * xs);
    s12 = sf(:,3)*invH - w * (sf(:,6) * xs);
    nGP = size(sf, 1);
    s13 = repmat(sf(:,7)*invH, 1, 5);
    s23 = repmat(sf(:,8)*invH, 1, 5);

    % Stack: reshape to [nGP x 5 x 1] then cat along dim-3 -> [nGP x 5 x 5]
    ss = cat(3, reshape(s11,nGP,5,1), reshape(s22,nGP,5,1), ...
                reshape(s12,nGP,5,1), reshape(s23,nGP,5,1), ...
                reshape(s13,nGP,5,1));

    se = cat(3, ss(:,:,1)*invE, ss(:,:,2)*invE, ...
                ss(:,:,3)*invG, ss(:,:,4)*invG, ...
                ss(:,:,5)*invG);
end

% =========================================================================
% GP -> Node projection  (dense pre-allocated accumulation, no Map copies)
% =========================================================================

function [nSecF, nSecD, nStress, nStrain, nodeTags] = shell_get_nodal_resp( ...
        obj, eleTags, secF, secD, stresses, strains)
    %
    % Strategy
    % --------
    %  Pass 1 (light): register any new node tags into obj.nodeIndexMap.
    %  Pre-allocate dense accumulation arrays (sum + count).
    %  Pass 2 (heavy): project GP -> node and accumulate by compact index.
    %  Final: divide sum by count.
    %
    % All intermediate storage is plain numeric arrays; no Map-of-struct.

    method = obj.nodalRespMethod;
    nEle   = numel(eleTags);
    nFib   = size(stresses, 3);

    % Determine whether any real stress data exists (avoid NaN-only work)
    hasStress = any(~isnan(stresses(:)));

    % ---- pass 1: build the current-step node set ------------------------
    % Model-update runs may add/remove shell elements and nodes, so nodal
    % projection must be indexed by the nodes referenced by the current
    % step only rather than a cross-step accumulated node map.
    nodeIndexMap = containers.Map('KeyType','double','ValueType','int32');
    nodeTags = zeros(0,1);

    for i = 1:nEle
        tag = eleTags(i);
        if ~isKey(obj.eleNodeCache, tag); continue; end
        nds = obj.eleNodeCache(tag);
        for j = 1:numel(nds)
            nt = nds(j);
            if ~isKey(nodeIndexMap, nt)
                nodeIndexMap(nt) = int32(numel(nodeTags) + 1);
                nodeTags(end+1,1) = nt; %#ok<AGROW>
            end
        end
    end

    nNodes   = numel(nodeTags);

    % ---- pre-allocate accumulators (zeroed, single allocation) ----------
    accSecF  = zeros(nNodes, 8,        'double');
    accSecD  = zeros(nNodes, 8,        'double');
    cntSecF  = zeros(nNodes, 8,        'uint32');
    cntSecD  = zeros(nNodes, 8,        'uint32');

    if hasStress
        accSS  = zeros(nNodes, nFib, 5, 'double');
        accSE  = zeros(nNodes, nFib, 5, 'double');
        cntSS  = zeros(nNodes, nFib, 5, 'uint32');
        cntSE  = zeros(nNodes, nFib, 5, 'uint32');
    end

    % ---- pass 2: project and accumulate ---------------------------------
    for i = 1:nEle
        tag   = eleTags(i);
        nGP   = double(obj.eleNGPCache(tag));
        if nGP == 0; continue; end

        nds   = obj.eleNodeCache(tag);
        nNode = numel(nds);

        % Extract section force/defo slice without squeeze (explicit reshape)
        sf_i = reshape(secF(i, 1:nGP, :), nGP, 8);
        sd_i = reshape(secD(i, 1:nGP, :), nGP, 8);

        % Drop all-NaN GP rows (defensive; typically zero cost)
        gpMask = ~all(isnan(sf_i), 2);
        nGPv   = sum(gpMask);
        if nGPv == 0; continue; end
        if nGPv < nGP
            sf_i = sf_i(gpMask, :);
            sd_i = sd_i(gpMask, :);
        end

        eleType  = shell_ele_type_from_n(nNode);
        projFunc = post.utils.FEShapeLibrary.getShellGP2NodeFunc(eleType, nNode, nGPv);

        if isempty(projFunc)
            nodeSecF = repmat(mean(sf_i, 1), nNode, 1);   % [nNode x 8]
            nodeSecD = repmat(mean(sd_i, 1), nNode, 1);
        else
            nodeSecF = projFunc(method, sf_i);             % [nNode x 8]
            nodeSecD = projFunc(method, sd_i);
        end

        % Accumulate section responses (inner loop over nNode, typically 3-9)
        for j = 1:nNode
            idx = double(nodeIndexMap(nds(j)));
            validF = isfinite(nodeSecF(j,:));
            if any(validF)
                accSecF(idx,validF) = accSecF(idx,validF) + nodeSecF(j,validF);
                cntSecF(idx,validF) = cntSecF(idx,validF) + 1;
            end

            validD = isfinite(nodeSecD(j,:));
            if any(validD)
                accSecD(idx,validD) = accSecD(idx,validD) + nodeSecD(j,validD);
                cntSecD(idx,validD) = cntSecD(idx,validD) + 1;
            end
        end

        % Stress / strain accumulation
        if hasStress
            ns_i = reshape(stresses(i, 1:nGP, :, :), nGP, nFib, 5);
            ne_i = reshape(strains (i, 1:nGP, :, :), nGP, nFib, 5);
            if nGPv < nGP
                ns_i = ns_i(gpMask, :, :);
                ne_i = ne_i(gpMask, :, :);
            end

            if isempty(projFunc)
                % mean over GP dim -> [1 x nFib x 5], replicate to [nNode x nFib x 5]
                mS = reshape(mean(ns_i, 1), 1, nFib, 5);
                mE = reshape(mean(ne_i, 1), 1, nFib, 5);
                nodeStress = repmat(mS, nNode, 1, 1);
                nodeStrain = repmat(mE, nNode, 1, 1);
            else
                nodeStress = projFunc(method, ns_i);   % [nNode x nFib x 5]
                nodeStrain = projFunc(method, ne_i);
            end

            for j = 1:nNode
                idx = double(nodeIndexMap(nds(j)));
                validS = isfinite(squeeze(nodeStress(j,:,:)));
                validE = isfinite(squeeze(nodeStrain(j,:,:)));

                sliceS = squeeze(accSS(idx,:,:));
                sliceE = squeeze(accSE(idx,:,:));
                cntS   = squeeze(cntSS(idx,:,:));
                cntE   = squeeze(cntSE(idx,:,:));
                nodeS  = squeeze(nodeStress(j,:,:));
                nodeE  = squeeze(nodeStrain(j,:,:));

                sliceS(validS) = sliceS(validS) + nodeS(validS);
                sliceE(validE) = sliceE(validE) + nodeE(validE);
                cntS(validS) = cntS(validS) + 1;
                cntE(validE) = cntE(validE) + 1;

                accSS(idx,:,:)  = reshape(sliceS, 1, nFib, 5);
                accSE(idx,:,:)  = reshape(sliceE, 1, nFib, 5);
                cntSS(idx,:,:)  = reshape(cntS, 1, nFib, 5);
                cntSE(idx,:,:)  = reshape(cntE, 1, nFib, 5);
            end
        end
    end

    % ---- divide by count to get mean ------------------------------------
    safeNF = double(max(cntSecF, 1));
    safeND = double(max(cntSecD, 1));
    nSecF  = accSecF ./ safeNF;
    nSecD  = accSecD ./ safeND;
    nSecF(cntSecF == 0) = NaN;
    nSecD(cntSecD == 0) = NaN;

    if hasStress
        safeNS = double(max(cntSS, 1));
        safeNE = double(max(cntSE, 1));
        nStress = accSS ./ safeNS;
        nStrain = accSE ./ safeNE;
        nStress(cntSS == 0) = NaN;
        nStrain(cntSE == 0) = NaN;
    else
        nStress = zeros(nNodes, nFib, 5);
        nStrain = zeros(nNodes, nFib, 5);
    end
end

% =========================================================================
% Elastic parameter query (via OpenSees parameter mechanism)
% =========================================================================

function value = shell_get_param(ops, eleTag, paramName)
    existingTags = double(ops.getParamTags());
    newTag = 1;
    if ~isempty(existingTags)
        newTag = max(existingTags) + 1;
    end
    try
        ops.parameter(newTag, 'element', eleTag, paramName);
        value = double(ops.getParamValue(newTag));
        ops.remove('parameter', newTag);
    catch
        value = 0;
    end
end

% =========================================================================
% Option parser
% =========================================================================

function [computeNodalResp, rest] = shell_parse_options(varargin)
    computeNodalResp = '';
    rest = {};
    i = 1;
    while i <= numel(varargin)
        key = '';
        if ischar(varargin{i}) || isstring(varargin{i})
            key = lower(char(varargin{i}));
        end
        if strcmp(key, 'computenodalresp') && i+1 <= numel(varargin)
            computeNodalResp = char(varargin{i+1});
            i = i + 2;
        else
            rest{end+1} = varargin{i}; %#ok<AGROW>
            i = i + 1;
        end
    end
end

% =========================================================================
% Tiny utilities
% =========================================================================

function v = ops_scalar(x)
    % Safe scalar extraction from potentially array output
    v = x(1);
end

function t = shell_ele_type_from_n(nNode)
    if ismember(nNode, [3, 6])
        t = 'tri';
    elseif ismember(nNode, [4, 8, 9])
        t = 'quad';
    else
        error('ShellRespStepData:UnsupportedShellNodeCount', ...
            'Unsupported shell element node count: %d.', nNode);
    end
end

function names = shell_ele_dim_names(nd, isStress)
    if isStress
        base = {'time','element','GaussPoints','fiberPoints','dof'};
    else
        base = {'time','element','GaussPoints','dof'};
    end
    names = base(1:min(nd, numel(base)));
end

function names = shell_node_dim_names(nd, isStress)
    if isStress
        base = {'time','node','fiberPoints','dof'};
    else
        base = {'time','node','dof'};
    end
    names = base(1:min(nd, numel(base)));
end