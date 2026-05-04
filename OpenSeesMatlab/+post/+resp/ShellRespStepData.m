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
    %  * Raw MEX handle (mex_) cached at construction; passed to all local
    %    helpers so every eleResponse / eleNodes call goes directly to MEX
    %    without wrapper method-dispatch overhead.
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
        eleTags          double
        computeNodalResp logical   = false
        nodalRespMethod  char      = 'extrapolation'

        gaussPoints      double
        fiberPoints      double
        nodeTags         double

        eleClassCache    containers.Map
        eleNGPCache      containers.Map
        eleNFibCache     containers.Map
        eleParamCache    containers.Map
        eleNodeCache     containers.Map

        nodeIndexMap     containers.Map
    end

    % =====================================================================
    properties (Access = private)
    end

    % =====================================================================
    methods

        function obj = ShellRespStepData(ops, eleTags, varargin)
            [computeNodalResp, baseArgs] = shell_parse_options(varargin{:});
            obj@post.resp.ResponseBase(ops, baseArgs{:});



            obj.eleTags = eleTags(:).';

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
            eleTags = eleTags(:).';
            nEle    = numel(eleTags);

            [maxGP, maxFib] = shell_fill_caches(obj, eleTags, obj.mex_);

            secF     = NaN(nEle, maxGP, 8,         'double');
            secD     = NaN(nEle, maxGP, 8,         'double');
            stresses = NaN(nEle, maxGP, maxFib, 5, 'double');
            strains  = NaN(nEle, maxGP, maxFib, 5, 'double');

            for i = 1:nEle
                tag = eleTags(i);
                nGP = obj.eleNGPCache(tag);
                if nGP == 0; continue; end

                % Direct MEX calls — no ops wrapper overhead
                rawF = obj.mex_('eleResponse', tag, 'stresses');
                rawD = obj.mex_('eleResponse', tag, 'strains');

                sf = reshape(rawF, nGP, 8);
                sd = reshape(rawD, nGP, 8);

                if obj.eleClassCache(tag) == post.resp.ShellRespStepData.MITC9_CLASS_TAG ...
                        && nGP == 9
                    sf = sf(post.resp.ShellRespStepData.MITC9_GP_ORDER, :);
                    sd = sd(post.resp.ShellRespStepData.MITC9_GP_ORDER, :);
                end

                secF(i, 1:nGP, :) = sf;
                secD(i, 1:nGP, :) = sd;

                nFib = obj.eleNFibCache(tag);

                if nFib > 0
                    [ss, se] = shell_get_fiber_resp_prealloc( ...
                        obj.mex_, tag, nGP, nFib);
                elseif nFib == 0
                    p = obj.eleParamCache(tag);
                    [ss, se] = shell_elastic_stress_vec(sf, p);
                    nFib = size(ss, 2);
                else
                    continue;
                end

                stresses(i, 1:nGP, 1:nFib, :) = ss;
                strains (i, 1:nGP, 1:nFib, :) = se;
            end

            if isempty(obj.gaussPoints)
                obj.gaussPoints = 1:maxGP;
            end
            if isempty(obj.fiberPoints)
                obj.fiberPoints = 1:maxFib;
            end

            if obj.computeNodalResp
                [nSecF, nSecD, nStress, nStrain, nTags] = ...
                    shell_get_nodal_resp(obj, eleTags, ...
                        secF, secD, stresses, strains);
                obj.nodeTags = nTags;
            end

            S = struct( ...
                'eleTags',      eleTags(:), ...
                'SecForceAtGP', secF, ...
                'SecDefoAtGP',  secD, ...
                'StressAtGP',   stresses, ...
                'StrainAtGP',   strains);

            if obj.computeNodalResp
                S.SecForceAtNode = nSecF;
                S.SecDefoAtNode  = nSecD;
                S.StressAtNode   = nStress;
                S.StrainAtNode   = nStrain;
                S.nodeTags       = nTags(:);
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

            allEleTags = data.eleTags(:).';
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

            eleTypes = {'SecForceAtGP','SecDefoAtGP','StressAtGP','StrainAtGP'};

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
% Cache population
% =========================================================================

function [maxGP, maxFib] = shell_fill_caches(obj, eleTags, mex_)
    % mex_ : raw MEX handle — all eleResponse / eleNodes calls go direct.
    needParam = false;

    for i = 1:numel(eleTags)
        tag = eleTags(i);

        % Refresh node connectivity every step (model-update support).
        nds = mex_('eleNodes', tag);
        obj.eleNodeCache(tag) = nds(:).';

        if obj.eleNGPCache.isKey(tag); continue; end

        ct = int32(mex_('getEleClassTags', tag));
        obj.eleClassCache(tag) = ct(1);

        rawF = mex_('eleResponse', tag, 'stresses');
        if isempty(rawF)
            obj.eleNGPCache(tag)  = int32(0);
            obj.eleNFibCache(tag) = int32(-1);
            continue;
        end
        nGP = int32(numel(rawF) / 8);
        obj.eleNGPCache(tag) = nGP;

        % Probe fiber count via Material-1 / fiber-1
        s1 = mex_('eleResponse', tag, 'Material', 1, 'fiber', 1, 'stresses');
        if ~isempty(s1)
            nFib = int32(1);
            for k = 2:2000
                if isempty(mex_('eleResponse', tag, 'Material', 1, ...
                        'fiber', k, 'stresses'))
                    break;
                end
                nFib = int32(k);
            end
            obj.eleNFibCache(tag) = nFib;
        else
            obj.eleNFibCache(tag) = int32(0);  % elastic
            needParam = true;
        end
    end

    % Retrieve elastic parameters (suppressPrint still goes through ops wrapper
    % since it is a control command, not a data query).
    if needParam
        obj.ops.suppressPrint(true);
        cleaner = onCleanup(@() obj.ops.suppressPrint(false));
        for i = 1:numel(eleTags)
            tag = eleTags(i);
            if obj.eleNFibCache(tag) ~= 0; continue; end
            if obj.eleParamCache.isKey(tag); continue; end
            p.E  = shell_get_param(obj.ops, tag, 'E');
            p.nu = shell_get_param(obj.ops, tag, 'nu');
            p.h  = shell_get_param(obj.ops, tag, 'h');
            if p.E <= 0 || p.nu < 0 || p.h <= 0
                obj.eleNFibCache(tag) = int32(-1);
            else
                obj.eleParamCache(tag) = p;
            end
        end
    end

    allNGP  = cell2mat(obj.eleNGPCache.values());
    allNFib = cell2mat(obj.eleNFibCache.values());

    maxGP  = max([allNGP(:);  int32(0)]);
    hasElastic = any(allNFib == 0);
    validFibs  = allNFib(allNFib > 0);
    maxFib = max([validFibs(:); int32(5 * hasElastic); int32(1)]);
end

% =========================================================================
% Fiber stress query  (pre-allocated, no cell arrays)
% =========================================================================

function [ss, se] = shell_get_fiber_resp_prealloc(mex_, tag, nGP, nFib)
    % mex_ : raw MEX handle — no ops wrapper overhead per GP/fiber query.
    ss = NaN(nGP, nFib, 5, 'double');
    se = NaN(nGP, nFib, 5, 'double');

    for j = 1:nGP
        for k = 1:nFib
            s = mex_('eleResponse', tag, 'Material', j, ...
                             'fiber', k, 'stresses');
            e = mex_('eleResponse', tag, 'Material', j, ...
                             'fiber', k, 'strains');
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
    G    = 0.5 * p.E / (1.0 + p.nu);
    xs   = linspace(-p.h/2, p.h/2, 5);
    invH = 1.0 / p.h;
    w    = 12.0 / (p.h ^ 3);
    invE = 1.0 / p.E;
    invG = 1.0 / G;

    s11 = sf(:,1)*invH - w * (sf(:,4) * xs);
    s22 = sf(:,2)*invH - w * (sf(:,5) * xs);
    s12 = sf(:,3)*invH - w * (sf(:,6) * xs);
    nGP = size(sf, 1);
    s13 = repmat(sf(:,7)*invH, 1, 5);
    s23 = repmat(sf(:,8)*invH, 1, 5);

    ss = cat(3, reshape(s11,nGP,5,1), reshape(s22,nGP,5,1), ...
                reshape(s12,nGP,5,1), reshape(s23,nGP,5,1), ...
                reshape(s13,nGP,5,1));

    se = cat(3, ss(:,:,1)*invE, ss(:,:,2)*invE, ...
                ss(:,:,3)*invG, ss(:,:,4)*invG, ...
                ss(:,:,5)*invG);
end

% =========================================================================
% GP -> Node projection
% =========================================================================

function [nSecF, nSecD, nStress, nStrain, nodeTags] = shell_get_nodal_resp( ...
        obj, eleTags, secF, secD, stresses, strains)

    method = obj.nodalRespMethod;
    nEle   = numel(eleTags);
    nFib   = size(stresses, 3);
    hasStress = any(~isnan(stresses(:)));

    % Pass 1: build current-step node set
    nodeIndexMap = containers.Map('KeyType','double','ValueType','int32');
    nodeTags = zeros(0,1);

    for i = 1:nEle
        tag = eleTags(i);
        if ~obj.eleNodeCache.isKey(tag); continue; end
        nds = obj.eleNodeCache(tag);
        for j = 1:numel(nds)
            nt = nds(j);
            if ~nodeIndexMap.isKey(nt)
                nodeIndexMap(nt) = int32(numel(nodeTags) + 1);
                nodeTags(end+1,1) = nt; %#ok<AGROW>
            end
        end
    end

    nNodes  = numel(nodeTags);
    accSecF = zeros(nNodes, 8, 'double');
    accSecD = zeros(nNodes, 8, 'double');
    cntSecF = zeros(nNodes, 8);
    cntSecD = zeros(nNodes, 8);

    if hasStress
        accSS = zeros(nNodes, nFib, 5, 'double');
        accSE = zeros(nNodes, nFib, 5, 'double');
        cntSS = zeros(nNodes, nFib, 5);
        cntSE = zeros(nNodes, nFib, 5);
    end

    % Pass 2: project and accumulate
    for i = 1:nEle
        tag   = eleTags(i);
        nGP   = obj.eleNGPCache(tag);
        if nGP == 0; continue; end

        nds   = obj.eleNodeCache(tag);
        nNode = numel(nds);

        sf_i = reshape(secF(i, 1:nGP, :), nGP, 8);
        sd_i = reshape(secD(i, 1:nGP, :), nGP, 8);

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
            nodeSecF = repmat(mean(sf_i, 1), nNode, 1);
            nodeSecD = repmat(mean(sd_i, 1), nNode, 1);
        else
            nodeSecF = projFunc(method, sf_i);
            nodeSecD = projFunc(method, sd_i);
        end

        for j = 1:nNode
            idx = nodeIndexMap(nds(j));
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

        if hasStress
            ns_i = reshape(stresses(i, 1:nGP, :, :), nGP, nFib, 5);
            ne_i = reshape(strains (i, 1:nGP, :, :), nGP, nFib, 5);
            if nGPv < nGP
                ns_i = ns_i(gpMask, :, :);
                ne_i = ne_i(gpMask, :, :);
            end

            if isempty(projFunc)
                mS = reshape(mean(ns_i, 1), 1, nFib, 5);
                mE = reshape(mean(ne_i, 1), 1, nFib, 5);
                nodeStress = repmat(mS, nNode, 1, 1);
                nodeStrain = repmat(mE, nNode, 1, 1);
            else
                nodeStress = projFunc(method, ns_i);
                nodeStrain = projFunc(method, ne_i);
            end

            for j = 1:nNode
                idx = nodeIndexMap(nds(j));
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
                cntS(validS)   = cntS(validS)   + 1;
                cntE(validE)   = cntE(validE)   + 1;

                accSS(idx,:,:) = reshape(sliceS, 1, nFib, 5);
                accSE(idx,:,:) = reshape(sliceE, 1, nFib, 5);
                cntSS(idx,:,:) = reshape(cntS,   1, nFib, 5);
                cntSE(idx,:,:) = reshape(cntE,   1, nFib, 5);
            end
        end
    end

    safeNF = max(cntSecF, 1);
    safeND = max(cntSecD, 1);
    nSecF  = accSecF ./ safeNF;
    nSecD  = accSecD ./ safeND;
    nSecF(cntSecF == 0) = NaN;
    nSecD(cntSecD == 0) = NaN;

    if hasStress
        safeNS  = max(cntSS, 1);
        safeNE  = max(cntSE, 1);
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
% Elastic parameter query (uses ops wrapper — control command, not data)
% =========================================================================

function value = shell_get_param(ops, eleTag, paramName)
    existingTags = ops.getParamTags();
    newTag = 1;
    if ~isempty(existingTags)
        newTag = max(existingTags) + 1;
    end
    try
        ops.parameter(newTag, 'element', eleTag, paramName);
        value = ops.getParamValue(newTag);
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
% Utilities
% =========================================================================

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
