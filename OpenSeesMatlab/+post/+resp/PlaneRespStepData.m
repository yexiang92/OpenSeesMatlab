classdef PlaneRespStepData < post.resp.ResponseBase
    % PlaneRespStepData  Collect 2-D continuum (plane) element responses step by step.
    %
    % Response types
    % --------------
    %   Stresses             [nEle x nGP x nStressDof]
    %   Strains              [nEle x nGP x nStrainDof]
    %
    % Optional (computeNodalResp)
    %   StressesAtNodes      [nNode x nStressDof]
    %   StrainsAtNodes       [nNode x nStrainDof]
    %   StressAtNodesErr     [nNode x nStressDof]   relative peak-to-peak error
    %   StrainsAtNodesErr    [nNode x nStrainDof]
    %   PorePressureAtNodes  [nNode x 1]
    %
    % Optional (computeMechanicalMeasures)
    %   StressMeasures       [nEle x nGP x nMeasure]
    %   StressMeasuresAtNodes [nNode x nMeasure]
    %
    % Performance design
    % ------------------
    %  * Raw MEX handle (mex_) cached at construction; passed to all local
    %    helpers so every eleResponse / eleNodes call goes directly to MEX
    %    without wrapper method-dispatch overhead.
    %  * Per-element metadata (nGP, nDof, classTag, nodeList) resolved once
    %    on first encounter and stored in typed caches.
    %  * Output arrays pre-allocated to known size before element loop.
    %  * Nodal accumulation via compact integer index map; dense matrices
    %    track sum, sum-of-squares-range (max/min) and count.
    %  * All stress-measure kernels are fully vectorised (no element loops).

    % =====================================================================
    properties (Constant)
        RESP_NAME = 'PlaneResponses'

        % Element class tags that need GP reordering
        SIXNODETRI_TAG    = int32(209)   % 3 GPs,  idx = [3,1,2] (1-based)
        NINENODEQUAD_TAG  = int32(61)    % 9 GPs,  idx = [1,7,9,3,4,8,6,2,5]

        SIXNODETRI_ORDER   = int32([3,1,2])
        NINENODEQUAD_ORDER = int32([1,7,9,3,4,8,6,2,5])
    end

    % =====================================================================
    properties
        eleTags             double    % [1 x nEle]
        computeNodalResp    logical   = false
        nodalRespMethod     char      = 'extrapolation'
        includePorePressure logical   = false

        measurePrincipal    logical   = false
        measureVonMises     logical   = false
        measureTauMax       logical   = false
        measureOctahedral   logical   = false
        measureMohrCoulombSy   double = []
        measureMohrCoulombCPhi double = []
        measureDruckerPragerSy double = []
        measureDruckerPragerCPhi cell = {}

        gaussPoints         double
        stressDofs          cell
        strainDofs          cell
        nodeTags            double
        measureDofs         cell

        eleClassCache       containers.Map
        eleNGPCache         containers.Map
        eleNStressCache     containers.Map
        eleNStrainCache     containers.Map
        eleNodeCache        containers.Map

        nodeIndexMap        containers.Map
    end

    % =====================================================================
    properties (Access = private)
    end

    % =====================================================================
    methods

        function obj = PlaneRespStepData(ops, eleTags, varargin)
            % PlaneRespStepData(ops, eleTags, Name, Value, ...)

            [nodalMethod, porePressure, measureOpts, baseArgs] = ...
                plane_parse_options(varargin{:});

            obj@post.resp.ResponseBase(ops, baseArgs{:});



            obj.eleTags = eleTags(:).';

            obj.eleClassCache   = containers.Map('KeyType','double','ValueType','int32');
            obj.eleNGPCache     = containers.Map('KeyType','double','ValueType','int32');
            obj.eleNStressCache = containers.Map('KeyType','double','ValueType','int32');
            obj.eleNStrainCache = containers.Map('KeyType','double','ValueType','int32');
            obj.eleNodeCache    = containers.Map('KeyType','double','ValueType','any');
            obj.nodeIndexMap    = containers.Map('KeyType','double','ValueType','int32');

            if ~isempty(nodalMethod)
                obj.computeNodalResp    = true;
                obj.nodalRespMethod     = char(nodalMethod);
                obj.includePorePressure = porePressure;
            end

            obj = plane_apply_measure_opts(obj, measureOpts);

            obj.addRespDataOneStep(obj.eleTags);
        end

        % -----------------------------------------------------------------
        function addRespDataOneStep(obj, eleTags)
            if nargin < 2 || isempty(eleTags)
                eleTags = obj.eleTags;
            end
            eleTags = eleTags(:).';
            nEle    = numel(eleTags);

            % Fill caches; determine pre-alloc sizes
            [maxGP, maxSdof, maxEdof] = plane_fill_caches(obj, eleTags, obj.mex_);

            % ---- pre-allocate -------------------------------------------
            stresses = NaN(nEle, maxGP, maxSdof, 'double');
            strains  = NaN(nEle, maxGP, maxEdof, 'double');

            % ---- element loop -------------------------------------------
            for i = 1:nEle
                tag = eleTags(i);
                nGP = obj.eleNGPCache(tag);
                if nGP == 0; continue; end
                nSD = obj.eleNStressCache(tag);
                nED = obj.eleNStrainCache(tag);

                sf = plane_collect_resp(obj.mex_, tag, 'stresses', nGP, nSD);
                ef = plane_collect_resp(obj.mex_, tag, 'strains',  nGP, nED);

                ct = obj.eleClassCache(tag);
                [sf, ef] = plane_reorder_gp(ct, nGP, sf, ef);

                if nSD >= 4
                    sf(:, [3 4]) = sf(:, [4 3]);
                end

                stresses(i, 1:nGP, 1:nSD) = sf;
                strains (i, 1:nGP, 1:nED) = ef;
            end

            stresses = plane_trim_dof(stresses);
            strains  = plane_trim_dof(strains);
            nSD = size(stresses, 3);
            nED = size(strains,  3);

            if isempty(obj.gaussPoints)
                obj.gaussPoints = 1:maxGP;
            end
            if isempty(obj.stressDofs)
                obj.stressDofs = plane_stress_dof_labels(nSD);
            end
            if isempty(obj.strainDofs)
                obj.strainDofs = plane_strain_dof_labels(nED);
            end

            nSecF = []; nSecD = []; nErrF = []; nErrD = [];
            nPore = []; nTags = [];
            if obj.computeNodalResp
                [nSecF, nErrF, nSecD, nErrD, nTags] = ...
                    plane_get_nodal_resp(obj, eleTags, stresses, strains);
                obj.nodeTags = nTags;
                if obj.includePorePressure
                    nPore = plane_get_pore_pressure(obj.mex_, nTags);
                end
            end

            SM = []; SMA = [];
            if obj.measurePrincipal || obj.measureVonMises || ...
                    obj.measureTauMax  || obj.measureOctahedral || ...
                    ~isempty(obj.measureMohrCoulombSy) || ...
                    ~isempty(obj.measureMohrCoulombCPhi) || ...
                    ~isempty(obj.measureDruckerPragerSy) || ...
                    ~isempty(obj.measureDruckerPragerCPhi)

                [SM, mDofs] = plane_compute_measures(stresses, obj);
                if isempty(obj.measureDofs)
                    obj.measureDofs = mDofs;
                end
                if obj.computeNodalResp && ~isempty(nSecF)
                    [SMA, ~] = plane_compute_measures(reshape(nSecF, 1, size(nSecF,1), nSD), obj);
                    SMA = reshape(SMA, size(nSecF,1), []);
                end
            end

            S = struct( ...
                'eleTags',    eleTags(:), ...
                'stressDofs', {obj.stressDofs}, ...
                'strainDofs', {obj.strainDofs}, ...
                'StressAtGP', stresses, ...
                'StrainAtGP', strains);

            if obj.computeNodalResp && ~isempty(nTags)
                S.StressAtNode     = nSecF;
                S.StrainAtNode     = nSecD;
                S.StressAtNodeErr  = nErrF;
                S.StrainAtNodeErr  = nErrD;
                S.nodeTags         = nTags(:);
                if obj.includePorePressure
                    S.PorePressureAtNode = nPore(:);
                end
            end

            if ~isempty(SM)
                S.StressMeasureAtGP = SM;
                S.measureDofs   = obj.measureDofs;
                if ~isempty(SMA)
                    S.StressMeasureAtNode = SMA;
                end
            end

            obj.addStepData(S);
        end
    end

    % =====================================================================
    methods (Access = protected)
        function [parts, metaFields] = preProcessParts(obj, parts)
            groupSpecs = struct( ...
                'tagField', {'eleTags', 'nodeTags'}, ...
                'alignedFields', {{'StressAtGP', 'StrainAtGP', 'StressMeasureAtGP'}, ...
                                  {'StressAtNode', 'StrainAtNode', 'StressAtNodeErr', ...
                                   'StrainAtNodeErr', 'PorePressureAtNode', 'StressMeasureAtNode'}});
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
                'StressAtGP','StrainAtGP', ...
                'StressAtNode','StrainAtNode', ...
                'StressAtNodeErr','StrainAtNodeErr', ...
                'PorePressureAtNode', ...
                'StressMeasureAtGP','StressMeasureAtNode'};

            respTypes = post.resp.ResponseBase.resolveRespTypes(allRespTypes, options.respType);

            allEleTags = data.eleTags(:).';
            [selectedTags, eleIdx] = post.resp.ResponseBase.resolveTagSelection( ...
                allEleTags, options.eleTags, 'readResponse:InvalidEleTags', 'Element');
            selectAllEle = isempty(options.eleTags);

            nodeTypes = {'StressAtNode','StrainAtNode', ...
                         'StressAtNodeErr','StrainAtNodeErr', ...
                         'PorePressureAtNode','StressMeasureAtNode'};
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

            eleTypes     = {'StressAtGP','StrainAtGP','StressMeasureAtGP'};
            stressTypes  = {'StressAtGP','StressAtNode','StressAtNodeErr'};
            strainTypes  = {'StrainAtGP','StrainAtNode','StrainAtNodeErr'};
            measureTypes = {'StressMeasureAtGP','StressMeasureAtNode'};

            stressDofs  = {};
            strainDofs  = {};
            measureDofs = {};
            if isfield(data, 'stressDofs'),  stressDofs  = data.stressDofs;  end
            if isfield(data, 'strainDofs'),  strainDofs  = data.strainDofs;  end
            if isfield(data, 'measureDofs'), measureDofs = data.measureDofs; end

            for k = 1:numel(respTypes)
                rt = respTypes{k};
                if ~isfield(data, rt); continue; end
                d = data.(rt);
                if isempty(d) || ~isnumeric(d); continue; end

                if ismember(rt, measureTypes)
                    dofs = measureDofs;
                elseif ismember(rt, strainTypes)
                    dofs = strainDofs;
                elseif ismember(rt, stressTypes)
                    dofs = stressDofs;
                else
                    dofs = {};
                end

                if ~selectAllNode && ismember(rt, nodeTypes)
                    d = post.resp.ResponseBase.subsetSecondDim(d, nodeIdx);
                end

                if strcmp(rt, 'PorePressureAtNode')
                    S.(rt) = d;
                elseif ismember(rt, nodeTypes)
                    nDof = min(size(d, 3), numel(dofs));
                    S.(rt) = struct();
                    for di = 1:nDof
                        S.(rt).(dofs{di}) = d(:, :, di);
                    end
                else
                    if ~selectAllEle && ismember(rt, eleTypes)
                        d = post.resp.ResponseBase.subsetSecondDim(d, eleIdx);
                    end
                    nd   = ndims(d);
                    nDof = min(size(d, nd), numel(dofs));
                    S.(rt) = struct();
                    for di = 1:nDof
                        if nd == 4
                            S.(rt).(dofs{di}) = d(:, :, :, di);
                        else
                            S.(rt).(dofs{di}) = d(:, :, di);
                        end
                    end
                end
            end
        end
    end
end

% =========================================================================
% Cache population
% =========================================================================

function [maxGP, maxSdof, maxEdof] = plane_fill_caches(obj, eleTags, mex_)
    % Resolve per-element metadata for first-seen tags.
    % mex_ : raw MEX handle — avoids ops wrapper dispatch on every eleResponse call.
    prefixes = {'material','integrPoint'};

    for i = 1:numel(eleTags)
        tag = eleTags(i);

        % Node connectivity can change under model-update analyses;
        % refresh every step even when GP/DOF metadata is already cached.
        nds = mex_('eleNodes', tag);
        obj.eleNodeCache(tag) = nds(:).';

        if obj.eleNGPCache.isKey(tag); continue; end

        ct = int32(mex_('getEleClassTags', tag));
        obj.eleClassCache(tag) = ct(1);

        nGP   = int32(0);
        nSDof = int32(0);
        nEDof = int32(0);

        for gIdx = 1:2000
            gStr = num2str(gIdx);
            s = []; e = [];
            for p = 1:numel(prefixes)
                s = mex_('eleResponse', tag, prefixes{p}, gStr, 'stresses');
                if ~isempty(s); break; end
            end
            if isempty(s)
                if gIdx == 1
                    s = mex_('eleResponse', tag, 'stresses');
                    if ~isempty(s)
                        for p = 1:numel(prefixes)
                            e = mex_('eleResponse', tag, prefixes{p}, gStr, 'strains');
                            if ~isempty(e); break; end
                        end
                        if isempty(e)
                            e = mex_('eleResponse', tag, 'strains');
                        end
                        nGP   = int32(1);
                        nSDof = int32(numel(s));
                        nEDof = int32(max(numel(e), 1));
                    end
                end
                break;
            end
            for p = 1:numel(prefixes)
                e = mex_('eleResponse', tag, prefixes{p}, gStr, 'strains');
                if ~isempty(e); break; end
            end
            nGP   = int32(gIdx);
            nSDof = int32(max(numel(s), nSDof));
            nEDof = int32(max(numel(e), nEDof));
        end

        obj.eleNGPCache(tag)     = nGP;
        obj.eleNStressCache(tag) = nSDof;
        obj.eleNStrainCache(tag) = nEDof;
    end

    allNGP  = cell2mat(obj.eleNGPCache.values());
    allNSD  = cell2mat(obj.eleNStressCache.values());
    allNED  = cell2mat(obj.eleNStrainCache.values());

    maxGP   = max([allNGP(:);  int32(0)]);
    maxSdof = max([allNSD(:);  int32(1)]);
    maxEdof = max([allNED(:);  int32(1)]);
end

% =========================================================================
% Per-element GP response collection
% =========================================================================

function out = plane_collect_resp(mex_, tag, key, nGP, nDof)
    % Returns [nGP x nDof], filled via material/integrPoint paths.
    % mex_ : raw MEX handle — no ops wrapper overhead per GP query.
    out      = zeros(nGP, nDof, 'double');
    prefixes = {'material','integrPoint'};

    for g = 1:nGP
        gStr = num2str(g);
        val  = [];
        for p = 1:numel(prefixes)
            val = mex_('eleResponse', tag, prefixes{p}, gStr, key);
            if ~isempty(val); break; end
        end
        if isempty(val) && nGP == 1
            val = mex_('eleResponse', tag, key);
        end
        if ~isempty(val)
            n = min(numel(val), nDof);
            out(g, 1:n) = val(1:n);
        end
    end
end

% =========================================================================
% GP reordering for special element types
% =========================================================================

function [sf, ef] = plane_reorder_gp(ct, nGP, sf, ef)
    if ct == post.resp.PlaneRespStepData.SIXNODETRI_TAG && nGP == 3
        idx = post.resp.PlaneRespStepData.SIXNODETRI_ORDER;
        sf  = sf(idx, :);
        ef  = ef(idx, :);
    elseif ct == post.resp.PlaneRespStepData.NINENODEQUAD_TAG && nGP == 9
        idx = post.resp.PlaneRespStepData.NINENODEQUAD_ORDER;
        sf  = sf(idx, :);
        ef  = ef(idx, :);
    end
end

% =========================================================================
% Trim trailing all-NaN DOF slices
% =========================================================================

function out = plane_trim_dof(arr)
    nDof = size(arr, 3);
    last = 0;
    for d = nDof:-1:1
        if any(~isnan(arr(:,:,d)), 'all')
            last = d;
            break;
        end
    end
    if last == 0
        out = arr(:,:,1);
    else
        out = arr(:,:,1:last);
    end
end

% =========================================================================
% GP -> Node projection  (dense accumulators)
% =========================================================================

function [nStressAvg, nStressErr, nStrainAvg, nStrainErr, nodeTags] = ...
        plane_get_nodal_resp(obj, eleTags, stresses, strains)

    method = obj.nodalRespMethod;
    nEle   = numel(eleTags);
    nSD    = size(stresses, 3);
    nED    = size(strains,  3);

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

    nNodes = numel(nodeTags);

    accSS = zeros(nNodes, nSD, 'double');
    accES = zeros(nNodes, nED, 'double');
    maxSS = -inf(nNodes, nSD, 'double');
    minSS =  inf(nNodes, nSD, 'double');
    maxES = -inf(nNodes, nED, 'double');
    minES =  inf(nNodes, nED, 'double');
    cntS  = zeros(nNodes, nSD);
    cntE  = zeros(nNodes, nED);

    for i = 1:nEle
        tag   = eleTags(i);
        nGP   = obj.eleNGPCache(tag);
        if nGP == 0; continue; end

        nds   = obj.eleNodeCache(tag);
        nNode = numel(nds);

        sf_i = reshape(stresses(i, 1:nGP, :), nGP, nSD);
        ef_i = reshape(strains (i, 1:nGP, :), nGP, nED);

        gpMask = ~all(isnan(sf_i), 2);
        nGPv   = sum(gpMask);
        if nGPv == 0; continue; end
        if nGPv < nGP
            sf_i = sf_i(gpMask, :);
            ef_i = ef_i(gpMask, :);
        end

        eleType   = plane_ele_type_from_n(nNode);
        projFuncS = post.utils.FEShapeLibrary.getGP2NodeFunc(eleType, nNode, nGPv);

        if isempty(projFuncS)
            nSF = repmat(mean(sf_i, 1), nNode, 1);
            nEF = repmat(mean(ef_i, 1), nNode, 1);
        else
            nSF = projFuncS(method, sf_i);
            nEF = projFuncS(method, ef_i);
        end

        for j = 1:nNode
            idx = nodeIndexMap(nds(j));

            validS = isfinite(nSF(j,:));
            if any(validS)
                accSS(idx,validS) = accSS(idx,validS) + nSF(j,validS);
                maxSS(idx,validS) = max(maxSS(idx,validS), nSF(j,validS));
                minSS(idx,validS) = min(minSS(idx,validS), nSF(j,validS));
                cntS(idx,validS)  = cntS(idx,validS) + 1;
            end

            validE = isfinite(nEF(j,:));
            if any(validE)
                accES(idx,validE) = accES(idx,validE) + nEF(j,validE);
                maxES(idx,validE) = max(maxES(idx,validE), nEF(j,validE));
                minES(idx,validE) = min(minES(idx,validE), nEF(j,validE));
                cntE(idx,validE)  = cntE(idx,validE) + 1;
            end
        end
    end

    safeNS = max(cntS, 1);
    safeNE = max(cntE, 1);

    nStressAvg = accSS ./ safeNS;
    nStrainAvg = accES ./ safeNE;
    nStressAvg(cntS == 0) = NaN;
    nStrainAvg(cntE == 0) = NaN;

    ptpS = maxSS - minSS;
    ptpE = maxES - minES;
    ptpS(cntS == 0) = 0;
    ptpE(cntE == 0) = 0;

    nStressErr = ptpS ./ (abs(nStressAvg) + 1e-8);
    nStrainErr = ptpE ./ (abs(nStrainAvg) + 1e-8);
    nStressErr(cntS == 0) = NaN;
    nStrainErr(cntE == 0) = NaN;

    nStressErr(abs(nStressAvg) < 1e-8) = 0.0;
    nStrainErr(abs(nStrainAvg) < 1e-8) = 0.0;
end

% =========================================================================
% Pore pressure at nodes
% =========================================================================

function pore = plane_get_pore_pressure(mex_, nodeTags)
    % mex_ : raw MEX handle — no ops wrapper overhead per node query.
    nNodes = numel(nodeTags);
    pore   = zeros(nNodes, 1, 'double');
    for k = 1:nNodes
        vel = mex_('nodeVel', nodeTags(k));
        if numel(vel) >= 3
            pore(k) = vel(3);
        end
    end
end

% =========================================================================
% Stress measures  (fully vectorised)
% =========================================================================

function [SM, dofs] = plane_compute_measures(stresses, obj)
    nSD = size(stresses, 3);
    if nSD < 3
        SM = zeros(size(stresses,1), size(stresses,2), 0);
        dofs = {};
        return;
    end
    s11 = stresses(:,:,1);
    s22 = stresses(:,:,2);
    s33 = zeros(size(s11), 'double');

    if nSD >= 4
        s33 = stresses(:,:,3);
        s12 = stresses(:,:,4);
    else
        s12 = stresses(:,:,3);
    end

    [p1, p2, p3, theta] = plane_principal(s11, s22, s12, s33);

    dataCols = {};
    dofs     = {};

    if obj.measurePrincipal
        dataCols = [dataCols, {p1, p2, p3, theta}];
        dofs     = [dofs,     {'p1','p2','p3','theta'}];
    end
    if obj.measureVonMises
        vm = sqrt(((s11-s22).^2 + (s22-s33).^2 + (s33-s11).^2)/2 + 3*s12.^2);
        dataCols = [dataCols, {vm}];
        dofs     = [dofs,     {'sigmaVM'}];
    end
    if obj.measureTauMax
        dataCols = [dataCols, {0.5*(p1-p3)}];
        dofs     = [dofs,     {'tauMax'}];
    end
    if obj.measureOctahedral
        I1 = p1 + p2 + p3;
        J2 = ((p1-p2).^2 + (p2-p3).^2 + (p3-p1).^2) / 6;
        dataCols = [dataCols, {I1/3, sqrt(2/3*J2)}];
        dofs     = [dofs,     {'sigmaOct','tauOct'}];
    end
    if ~isempty(obj.measureMohrCoulombSy)
        syc = obj.measureMohrCoulombSy(1);
        syt = obj.measureMohrCoulombSy(2);
        [eq, ~] = plane_mc_sy(p1, p2, p3, syc, syt);
        dataCols = [dataCols, {eq, syc*ones(size(p1))}];
        dofs     = [dofs,     {'sigmaMohrCoulombSyEq','sigmaMohrCoulombSyIntensity'}];
    end
    if ~isempty(obj.measureMohrCoulombCPhi)
        c   = obj.measureMohrCoulombCPhi(1);
        phi = obj.measureMohrCoulombCPhi(2);
        [eq, ~] = plane_mc_cphi(p1, p2, p3, c, phi);
        dataCols = [dataCols, {eq, c*ones(size(p1))}];
        dofs     = [dofs,     {'sigmaMohrCoulombCPhiEq','sigmaMohrCoulombCPhiIntensity'}];
    end
    if ~isempty(obj.measureDruckerPragerSy)
        syc = obj.measureDruckerPragerSy(1);
        syt = obj.measureDruckerPragerSy(2);
        [eq, ~] = plane_dp_sy(p1, p2, p3, syc, syt);
        dataCols = [dataCols, {eq, syc*ones(size(p1))}];
        dofs     = [dofs,     {'sigmaDruckerPragerSyEq','sigmaDruckerPragerSyIntensity'}];
    end
    if ~isempty(obj.measureDruckerPragerCPhi)
        c    = obj.measureDruckerPragerCPhi(1);
        phi  = obj.measureDruckerPragerCPhi(2);
        kind = 'circumscribed';
        if numel(obj.measureDruckerPragerCPhi) >= 3
            kind = obj.measureDruckerPragerCPhi(3);
        end
        [eq, A] = plane_dp_cphi(p1, p2, p3, c, phi, kind);
        dataCols = [dataCols, {eq, A*ones(size(p1))}];
        dofs     = [dofs,     {'sigmaDruckerPragerCPhiEq','sigmaDruckerPragerCPhiIntensity'}];
    end

    if isempty(dataCols)
        SM   = zeros(size(stresses,1), size(stresses,2), 0);
        dofs = {};
        return;
    end

    SM = cat(3, dataCols{:});
end

function [p1, p2, p3, theta_deg] = plane_principal(s11, s22, s12, s33)
    avg    = (s11 + s22) * 0.5;
    rad    = sqrt(((s11 - s22) * 0.5).^2 + s12.^2);
    p1_2d  = avg + rad;
    p2_2d  = avg - rad;

    theta  = zeros(size(s11), 'double');
    mask   = abs(s11 - s22) > 1e-10;
    theta(mask)  = 0.5 * atan2(2*s12(mask), s11(mask) - s22(mask));
    mask2  = (~mask) & (abs(s12) > 1e-10);
    theta(mask2) = 0.25 * pi * sign(s12(mask2));
    theta_deg    = rad2deg(theta);

    p_all  = cat(3, p1_2d, p2_2d, s33);
    p_sort = sort(p_all, 3, 'descend');
    p1     = p_sort(:,:,1);
    p2     = p_sort(:,:,2);
    p3     = p_sort(:,:,3);
end

function [sigma_eq, sigma_y] = plane_mc_sy(p1, p2, p3, syc, syt)
    m   = syc / (syt + 1e-10);
    K   = (m - 1) / (m + 1);
    t12 = abs(p1-p2) + K*(p1+p2);
    t13 = abs(p1-p3) + K*(p1+p3);
    t23 = abs(p2-p3) + K*(p2+p3);
    sigma_eq = 0.5*(m+1)*max(max(t12, t13), t23);
    sigma_y  = syc;
end

function [sigma_eq, sigma_y] = plane_mc_cphi(p1, p2, p3, c, phi)
    cp  = cos(phi);
    tp  = tan(phi);
    fn  = @(si,sj) 0.5*abs(si-sj)/cp - 0.5*(si+sj)*tp;
    sigma_eq = max(max(fn(p1,p2), fn(p1,p3)), fn(p2,p3));
    sigma_y  = c;
end

function [sigma_eq, sigma_y] = plane_dp_sy(p1, p2, p3, syc, syt)
    m   = syc / (syt + 1e-10);
    I1  = p1 + p2 + p3;
    q   = sqrt(0.5*((p1-p2).^2 + (p2-p3).^2 + (p3-p1).^2));
    sigma_eq = 0.5*(m-1)*I1 + 0.5*(m+1)*q;
    sigma_y  = syc;
end

function [sigma_eq, sigma_y] = plane_dp_cphi(p1, p2, p3, c, phi, kind)
    I1   = p1 + p2 + p3;
    J2   = ((p1-p2).^2 + (p2-p3).^2 + (p3-p1).^2) / 6;
    sqJ2 = sqrt(J2);
    sp   = sin(phi);  cp = cos(phi);
    switch lower(kind)
        case 'circumscribed'
            A = 6*c*cp / (sqrt(3)*(3-sp));
            B = 2*sp   / (sqrt(3)*(3-sp));
        case 'middle'
            A = 6*c*cp / (sqrt(3)*(3+sp));
            B = 2*sp   / (sqrt(3)*(3+sp));
        case 'inscribed'
            A = 3*c*cp / sqrt(9 + 3*sp^2);
            B = sp     / sqrt(9 + 3*sp^2);
        otherwise
            error('plane_dp_cphi:UnknownKind', ...
                'kind must be circumscribed, middle, or inscribed.');
    end
    sigma_eq = sqJ2 - B*I1;
    sigma_y  = A;
end

% =========================================================================
% Option parser
% =========================================================================

function [nodalMethod, porePressure, measureOpts, rest] = plane_parse_options(varargin)
    nodalMethod  = '';
    porePressure = false;
    measureOpts  = struct();
    rest         = {};

    i = 1;
    while i <= numel(varargin)
        key = '';
        if ischar(varargin{i}) || isstring(varargin{i})
            key = lower(char(varargin{i}));
        end

        switch key
            case 'computenodalresp'
                nodalMethod = char(varargin{i+1});
                i = i + 2;

            case 'includeporepressure'
                porePressure = logical(varargin{i+1});
                i = i + 2;

            case 'computemechanicalmeasures'
                measures = varargin{i+1};
                i = i + 2;

                if isempty(measures), continue; end

                if ischar(measures) || isstring(measures)
                    measures = cellstr(string(measures));
                end
                if ~iscell(measures)
                    error('plane_parse_options:InvalidMeasures', ...
                        'computeMechanicalMeasures must be a string, string array, or cell array.');
                end

                for j = 1:numel(measures)
                    item = measures{j};
                    if ischar(item) || isstring(item)
                        m = lower(char(string(item)));
                        switch m
                            case 'principal',   measureOpts.principal  = true;
                            case 'vonmises',    measureOpts.vonmises   = true;
                            case 'taumax',      measureOpts.taumax     = true;
                            case 'octahedral',  measureOpts.octahedral = true;
                            otherwise
                                error('plane_parse_options:UnknownMeasure', ...
                                    'Unknown mechanical measure: %s', char(string(item)));
                        end
                    elseif iscell(item)
                        if isempty(item), continue; end
                        name = item{1};
                        if ~(ischar(name) || isstring(name))
                            error('plane_parse_options:InvalidMeasureName', ...
                                'The first entry of a measure cell must be a string.');
                        end
                        m = lower(char(string(name)));
                        switch m
                            case 'mohrcoulombsy'
                                if numel(item) < 3
                                    error('plane_parse_options:InvalidMohrCoulombSy', ...
                                        'mohrCoulombSy requires {name, syc, syt}.');
                                end
                                measureOpts.mohrcoulombsy = [double(item{2}), double(item{3})];
                            case 'mohrcoulombcphi'
                                if numel(item) < 3
                                    error('plane_parse_options:InvalidMohrCoulombCPhi', ...
                                        'mohrCoulombCPhi requires {name, c, phi}.');
                                end
                                measureOpts.mohrcoulombcphi = [double(item{2}), double(item{3})];
                            case 'druckerpragersy'
                                if numel(item) < 3
                                    error('plane_parse_options:InvalidDruckerPragerSy', ...
                                        'druckerPragerSy requires {name, syc, syt}.');
                                end
                                measureOpts.druckerpragersy = [double(item{2}), double(item{3})];
                            case 'druckerpragercphi'
                                if numel(item) < 3
                                    error('plane_parse_options:InvalidDruckerPragerCPhi', ...
                                        'druckerPragerCPhi requires {name, c, phi, [kind]}.');
                                end
                                if numel(item) >= 4
                                    measureOpts.druckerpragercphi = {double(item{2}), double(item{3}), char(string(item{4}))};
                                else
                                    measureOpts.druckerpragercphi = {double(item{2}), double(item{3}), 'circumscribed'};
                                end
                            otherwise
                                error('plane_parse_options:UnknownAdvancedMeasure', ...
                                    'Unknown advanced mechanical measure: %s', m);
                        end
                    else
                        error('plane_parse_options:InvalidMeasureItem', ...
                            'Each mechanical measure entry must be a string or a cell.');
                    end
                end

            otherwise
                rest{end+1} = varargin{i}; %#ok<AGROW>
                i = i + 1;
        end
    end
end

function obj = plane_apply_measure_opts(obj, opts)
    fields = fieldnames(opts);
    for k = 1:numel(fields)
        switch lower(char(fields{k}))
            case 'principal',          obj.measurePrincipal        = true;
            case 'vonmises',           obj.measureVonMises         = true;
            case 'taumax',             obj.measureTauMax           = true;
            case 'octahedral',         obj.measureOctahedral       = true;
            case 'mohrcoulombsy',      obj.measureMohrCoulombSy    = double(opts.mohrcoulombsy(:).');
            case 'mohrcoulombcphi',    obj.measureMohrCoulombCPhi  = double(opts.mohrcoulombcphi(:).');
            case 'druckerpragersy',    obj.measureDruckerPragerSy  = double(opts.druckerpragersy(:).');
            case 'druckerpragercphi',  obj.measureDruckerPragerCPhi = opts.druckerpragercphi;
        end
    end
end

% =========================================================================
% Utilities
% =========================================================================

function t = plane_ele_type_from_n(nNode)
    if ismember(nNode, [3, 6])
        t = 'tri';
    elseif ismember(nNode, [4, 8, 9])
        t = 'quad';
    else
        error('PlaneRespStepData:UnsupportedPlaneNodeCount', ...
            'Unsupported plane element node count: %d.', nNode);
    end
end

function labels = plane_stress_dof_labels(n)
    base = {'sxx','syy','szz','sxy'};
    labels = cell(1, n);
    for k = 1:n
        if k <= numel(base)
            labels{k} = base{k};
        else
            labels{k} = sprintf('para%d', k - numel(base));
        end
    end
end

function labels = plane_strain_dof_labels(n)
    base = {'exx','eyy','exy'};
    labels = cell(1, n);
    for k = 1:n
        if k <= numel(base)
            labels{k} = base{k};
        else
            labels{k} = sprintf('para%d', k - numel(base));
        end
    end
end
