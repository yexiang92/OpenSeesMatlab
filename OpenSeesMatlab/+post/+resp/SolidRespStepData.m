classdef SolidRespStepData < post.resp.ResponseBase
    % SolidRespStepData
    % Collect 3-D solid element stress/strain responses step by step.
    %
    % Response fields
    % ---------------
    %   StressAtGP            [nEle x nGP x nStressDof]
    %   StrainAtGP            [nEle x nGP x nStrainDof]
    %
    % Optional nodal responses
    % ------------------------
    %   StressAtNode          [nNode x nStressDof]
    %   StrainAtNode          [nNode x nStrainDof]
    %   StressAtNodeErr       [nNode x nStressDof]
    %   StrainAtNodeErr       [nNode x nStrainDof]
    %   PorePressureAtNode    [nNode x 1]
    %
    % Optional mechanical measures
    % ----------------------------
    %   StressMeasureAtGP     [nEle x nGP x nMeasure]
    %   StressMeasureAtNode   [nNode x nMeasure]

    properties (Constant)
        RESP_NAME   = 'SolidResponses'
        STRESS_DOFS = {'sxx','syy','szz','sxy','syz','sxz'}
        STRAIN_DOFS = {'exx','eyy','ezz','exy','eyz','exz'}
    end

    properties
        eleTags             double
        computeNodalResp    logical = false
        nodalRespMethod     char    = 'extrapolation'
        includePorePressure logical = false

        % Mechanical measure flags
        measurePrincipal       logical = false
        measureVonMises        logical = false
        measureTauMax          logical = false
        measureOctahedral      logical = false
        measureMohrCoulombSy   double  = []   % [syc, syt]
        measureMohrCoulombCPhi double  = []   % [c, phi_rad]
        measureDruckerPragerSy double  = []   % [syc, syt]
        measureDruckerPragerCPhi cell   = {}              % {c, phi, [kind]}

        % Labels / metadata populated on first step
        gaussPoints double
        stressDofs  cell
        strainDofs  cell
        nodeTags    double
        measureDofs cell

        % Per-element caches
        eleClassCache   containers.Map
        eleNGPCache     containers.Map
        eleNStressCache containers.Map
        eleNStrainCache containers.Map
        eleNodeCache    containers.Map

        % Global compact node index map: nodeTag -> compact row index
        nodeIndexMap    containers.Map
    end

    methods

        function obj = SolidRespStepData(ops, eleTags, varargin)
            % SolidRespStepData(ops, eleTags, Name, Value, ...)
            %
            % Supported options
            % -----------------
            % 'computeNodalResp'         : char method or ''
            % 'includePorePressure'      : logical
            % 'computeMechanicalMeasures': string / string array / cell array
            %
            % Examples
            % --------
            % {'principal','vonMises','tauMax','octahedral'}
            %
            % {
            %   'principal',
            %   {'mohrCoulombSy', syc, syt},
            %   {'mohrCoulombCPhi', c, phiDeg},
            %   {'druckerPragerSy', syc, syt},
            %   {'druckerPragerCPhi', c, phiDeg, 'circumscribed'}
            % }

            [nodalMethod, porePressure, measureOpts, baseArgs] = ...
                Solid_parse_options(varargin{:});

            obj@post.resp.ResponseBase(ops, baseArgs{:});

            obj.eleTags = double(eleTags(:).');

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

            obj = Solid_apply_measure_opts(obj, measureOpts);

            obj.addRespDataOneStep(obj.eleTags);
        end

        function addRespDataOneStep(obj, eleTags)
            if nargin < 2 || isempty(eleTags)
                eleTags = obj.eleTags;
            end
            eleTags = double(eleTags(:).');
            nEle    = numel(eleTags);

            % Resolve cache info and determine allocation sizes
            [maxGP, maxSdof, maxEdof] = Solid_fill_caches(obj, eleTags);

            stresses = NaN(nEle, maxGP, maxSdof, 'double');
            strains  = NaN(nEle, maxGP, maxEdof, 'double');

            % Collect element responses
            for i = 1:nEle
                tag = eleTags(i);
                nGP = double(obj.eleNGPCache(tag));
                if nGP == 0
                    continue;
                end

                nSD = double(obj.eleNStressCache(tag));
                nED = double(obj.eleNStrainCache(tag));

                sf = Solid_collect_resp(obj.ops, tag, 'stresses', nGP, nSD);
                ef = Solid_collect_resp(obj.ops, tag, 'strains',  nGP, nED);

                stresses(i,1:nGP,1:nSD) = sf;
                strains(i,1:nGP,1:nED)  = ef;
            end

            % Remove fully empty trailing DOF slices
            stresses = Solid_trim_dof(stresses);
            strains  = Solid_trim_dof(strains);

            nSD = size(stresses, 3);
            nED = size(strains,  3);

            % Initialize labels only once
            if isempty(obj.gaussPoints)
                obj.gaussPoints = 1:maxGP;
            end
            if isempty(obj.stressDofs)
                obj.stressDofs = Solid_stress_dof_labels(nSD);
            end
            if isempty(obj.strainDofs)
                obj.strainDofs = Solid_strain_dof_labels(nED);
            end

            % Optional nodal projection
            nSecF = [];
            nErrF = [];
            nSecD = [];
            nErrD = [];
            nPore = [];
            nTags = [];

            if obj.computeNodalResp
                [nSecF, nErrF, nSecD, nErrD, nTags] = ...
                    Solid_get_nodal_resp(obj, eleTags, stresses, strains);

                obj.nodeTags = nTags;

                if obj.includePorePressure && ~isempty(nTags)
                    nPore = Solid_get_pore_pressure(obj.ops, nTags);
                end
            end

            % Optional mechanical measures
            SM  = [];
            SMA = [];

            if obj.measurePrincipal || obj.measureVonMises || ...
               obj.measureTauMax  || obj.measureOctahedral || ...
               ~isempty(obj.measureMohrCoulombSy)   || ...
               ~isempty(obj.measureMohrCoulombCPhi) || ...
               ~isempty(obj.measureDruckerPragerSy) || ...
               ~isempty(obj.measureDruckerPragerCPhi)

                if nSD >= 6
                    [SM, mDofs] = Solid_compute_measures(stresses, obj);

                    if isempty(obj.measureDofs)
                        obj.measureDofs = mDofs;
                    end

                    if obj.computeNodalResp && ~isempty(nSecF)
                        tmp = reshape(nSecF, 1, size(nSecF,1), nSD);
                        [tmp2, ~] = Solid_compute_measures(tmp, obj);
                        SMA = reshape(tmp2, size(nSecF,1), []);
                    end
                end
            end

            % Assemble step data
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

            allEleTags = double(data.eleTags(:).');
            [selectedTags, eleIdx] = post.resp.ResponseBase.resolveTagSelection( ...
                allEleTags, options.eleTags, 'readResponse:InvalidEleTags', 'Element');
            selectAllEle = isempty(options.eleTags);

            nodeTypes    = {'StressAtNode','StrainAtNode', ...
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

                % pick dof labels for this response type
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
                    % plain [nTime x nNode] matrix, no DOF struct
                    S.(rt) = d;

                elseif ismember(rt, nodeTypes)
                    % [nTime x nNode x nDof] -> per-DOF fields
                    nDof = min(size(d, 3), numel(dofs));
                    S.(rt) = struct();
                    for di = 1:nDof
                        S.(rt).(dofs{di}) = d(:, :, di);
                    end

                else
                    % ele-based: [nTime x nEle x nGP x nDof]
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

function [maxGP, maxSdof, maxEdof] = Solid_fill_caches(obj, eleTags)
    prefixes = {'material','integrPoint'};

    for i = 1:numel(eleTags)
        tag = eleTags(i);

        % Connectivity can vary from step to step in model-update runs, so
        % refresh the node list every call even when response metadata is
        % already cached.
        nds = double(obj.ops.eleNodes(tag));
        obj.eleNodeCache(tag) = nds(:).';

        if isKey(obj.eleNGPCache, tag)
            continue;
        end

        ct = int32(obj.ops.getEleClassTags(tag));
        obj.eleClassCache(tag) = ct(1);

        nGP   = int32(0);
        nSDof = int32(0);
        nEDof = int32(0);

        for gIdx = 1:2000
            gStr = num2str(gIdx);
            s = [];
            e = [];

            for p = 1:numel(prefixes)
                s = double(obj.ops.eleResponse(tag, prefixes{p}, gStr, 'stresses'));
                if ~isempty(s)
                    break;
                end
            end

            if isempty(s)
                if gIdx == 1
                    s = double(obj.ops.eleResponse(tag, 'stresses'));
                    e = double(obj.ops.eleResponse(tag, 'strains'));
                    if ~isempty(s)
                        nGP   = int32(1);
                        nSDof = int32(numel(s));
                        nEDof = int32(max(numel(e), 1));
                    end
                end
                break;
            end

            for p = 1:numel(prefixes)
                e = double(obj.ops.eleResponse(tag, prefixes{p}, gStr, 'strains'));
                if ~isempty(e)
                    break;
                end
            end

            nGP   = int32(gIdx);
            nSDof = int32(max(numel(s), double(nSDof)));
            nEDof = int32(max(numel(e), double(nEDof)));
        end

        obj.eleNGPCache(tag)     = nGP;
        obj.eleNStressCache(tag) = nSDof;
        obj.eleNStrainCache(tag) = nEDof;
    end

    allNGP = cell2mat(values(obj.eleNGPCache));
    allNSD = cell2mat(values(obj.eleNStressCache));
    allNED = cell2mat(values(obj.eleNStrainCache));

    maxGP   = double(max([allNGP(:); int32(0)]));
    maxSdof = double(max([allNSD(:); int32(1)]));
    maxEdof = double(max([allNED(:); int32(1)]));
end

% =========================================================================
% Per-element response collection
% =========================================================================

function out = Solid_collect_resp(ops, tag, key, nGP, nDof)
    out      = NaN(nGP, nDof, 'double');
    prefixes = {'material','integrPoint'};

    for g = 1:nGP
        gStr = num2str(g);
        val  = [];

        for p = 1:numel(prefixes)
            val = double(ops.eleResponse(tag, prefixes{p}, gStr, key));
            if ~isempty(val)
                break;
            end
        end

        if isempty(val) && nGP == 1
            val = double(ops.eleResponse(tag, key));
        end

        if ~isempty(val)
            n = min(numel(val), nDof);
            out(g,1:n) = val(1:n);
        end
    end
end

% =========================================================================
% Remove trailing all-NaN dof slices
% =========================================================================

function out = Solid_trim_dof(arr)
    nDof = size(arr, 3);
    last = 0;

    for d = nDof:-1:1
        if any(~isnan(arr(:,:,d)), 'all')
            last = d;
            break;
        end
    end

    out = arr(:,:,1:max(last,1));
end

% =========================================================================
% GP-to-node projection
% =========================================================================

function [nStressAvg, nStressErr, nStrainAvg, nStrainErr, nodeTags] = ...
        Solid_get_nodal_resp(obj, eleTags, stresses, strains)

    method = obj.nodalRespMethod;
    nEle   = numel(eleTags);
    nSD    = size(stresses, 3);
    nED    = size(strains,  3);

    % Build the node set for the current step only. Model-update runs may
    % add/remove solid elements and nodes between steps, so nodal
    % projection must not reuse a cross-step accumulated node map.
    nodeIndexMap = containers.Map('KeyType','double','ValueType','int32');
    nodeTags = zeros(0,1);

    for i = 1:nEle
        tag = eleTags(i);
        if ~isKey(obj.eleNodeCache, tag)
            continue;
        end

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

    accSS = zeros(nNodes, nSD, 'double');
    accES = zeros(nNodes, nED, 'double');
    maxSS = -inf(nNodes, nSD, 'double');
    minSS =  inf(nNodes, nSD, 'double');
    maxES = -inf(nNodes, nED, 'double');
    minES =  inf(nNodes, nED, 'double');
    cntS  = zeros(nNodes, nSD, 'uint32');
    cntE  = zeros(nNodes, nED, 'uint32');

    for i = 1:nEle
        tag = eleTags(i);
        nGP = double(obj.eleNGPCache(tag));
        if nGP == 0
            continue;
        end

        nds   = obj.eleNodeCache(tag);
        nNode = numel(nds);

        sf_i = reshape(stresses(i,1:nGP,:), nGP, nSD);
        ef_i = reshape(strains(i,1:nGP,:),  nGP, nED);

        gpMask = ~all(isnan(sf_i), 2);
        nGPv   = sum(gpMask);
        if nGPv == 0
            continue;
        end

        if nGPv < nGP
            sf_i = sf_i(gpMask,:);
            ef_i = ef_i(gpMask,:);
        end

        eleType  = Solid_ele_type_from_n(nNode);
        projFunc = post.utils.FEShapeLibrary.getGP2NodeFunc(eleType, nNode, nGPv);

        if isempty(projFunc)
            nSF = repmat(mean(sf_i, 1, 'omitnan'), nNode, 1);
            nEF = repmat(mean(ef_i, 1, 'omitnan'), nNode, 1);
        else
            nSF = projFunc(method, sf_i);
            nEF = projFunc(method, ef_i);
        end

        for j = 1:nNode
            idx = double(nodeIndexMap(nds(j)));

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

    safeNS = double(max(cntS, 1));
    safeNE = double(max(cntE, 1));

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

    nStressErr(abs(nStressAvg) < 1e-8) = 0;
    nStrainErr(abs(nStrainAvg) < 1e-8) = 0;
end

% =========================================================================
% Pore pressure
% =========================================================================

function pore = Solid_get_pore_pressure(ops, nodeTags)
    nNodes = numel(nodeTags);
    pore   = zeros(nNodes, 1, 'double');

    for k = 1:nNodes
        vel = double(ops.nodeVel(nodeTags(k)));
        if numel(vel) >= 4
            pore(k) = vel(4);
        end
    end
end

% =========================================================================
% Mechanical measures
% =========================================================================

function [SM, dofs] = Solid_compute_measures(stresses, obj)
    % stresses: [nEle x nGP x nSD], nSD >= 6

    sz = size(stresses);

    s11 = stresses(:,:,1);
    s22 = stresses(:,:,2);
    s33 = stresses(:,:,3);
    s12 = stresses(:,:,4);
    s23 = stresses(:,:,5);
    s13 = stresses(:,:,6);

    [p1, p2, p3] = Solid_principal_batched(s11, s22, s33, s12, s23, s13);

    dataCols = {};
    dofs     = {};

    if obj.measurePrincipal
        dataCols = [dataCols, {p1, p2, p3}];
        dofs     = [dofs, {'p1','p2','p3'}];
    end

    if obj.measureVonMises
        vm = sqrt(0.5*((s11-s22).^2 + (s22-s33).^2 + (s33-s11).^2) + ...
                  3*(s12.^2 + s23.^2 + s13.^2));
        dataCols = [dataCols, {vm}];
        dofs     = [dofs, {'sigmaVM'}];
    end

    if obj.measureTauMax
        dataCols = [dataCols, {0.5*(p1-p3)}];
        dofs     = [dofs, {'tauMax'}];
    end

    if obj.measureOctahedral
        I1 = p1 + p2 + p3;
        J2 = ((p1-p2).^2 + (p2-p3).^2 + (p3-p1).^2) / 6;
        dataCols = [dataCols, {I1/3, sqrt(2/3*J2)}];
        dofs     = [dofs, {'sigmaOct','tauOct'}];
    end

    if ~isempty(obj.measureMohrCoulombSy)
        syc = obj.measureMohrCoulombSy(1);
        syt = obj.measureMohrCoulombSy(2);
        [eq, ~] = Solid_mc_sy(p1, p2, p3, syc, syt);
        dataCols = [dataCols, {eq, syc*ones(sz(1),sz(2))}];
        dofs     = [dofs, {'sigmaMohrCoulombSyEq','sigmaMohrCoulombSyIntensity'}];
    end

    if ~isempty(obj.measureMohrCoulombCPhi)
        c   = obj.measureMohrCoulombCPhi(1);
        phi = obj.measureMohrCoulombCPhi(2);
        [eq, ~] = Solid_mc_cphi(p1, p2, p3, c, phi);
        dataCols = [dataCols, {eq, c*ones(sz(1),sz(2))}];
        dofs     = [dofs, {'sigmaMohrCoulombCPhiEq','sigmaMohrCoulombCPhiIntensity'}];
    end

    if ~isempty(obj.measureDruckerPragerSy)
        syc = obj.measureDruckerPragerSy(1);
        syt = obj.measureDruckerPragerSy(2);
        [eq, ~] = Solid_dp_sy(p1, p2, p3, syc, syt);
        dataCols = [dataCols, {eq, syc*ones(sz(1),sz(2))}];
        dofs     = [dofs, {'sigmaDruckerPragerSyEq','sigmaDruckerPragerSyIntensity'}];
    end

    if ~isempty(obj.measureDruckerPragerCPhi)
        c = obj.measureDruckerPragerCPhi(1);
        phi = obj.measureDruckerPragerCPhi(2);
        kind = 'circumscribed';
        if numel(obj.measureDruckerPragerCPhi) >= 3
            kind = obj.measureDruckerPragerCPhi(3);
        end
        [eq, A] = Solid_dp_cphi(p1, p2, p3, c, phi, kind);
        dataCols = [dataCols, {eq, A*ones(sz(1),sz(2))}];
        dofs     = [dofs, {'sigmaDruckerPragerCPhiEq','sigmaDruckerPragerCPhiIntensity'}];
    end

    if isempty(dataCols)
        SM   = zeros(sz(1), sz(2), 0);
        dofs = {};
        return;
    end

    SM = cat(3, dataCols{:});
end

% =========================================================================
% Batched principal stresses for symmetric 3x3 stress tensor
% =========================================================================

function [p1, p2, p3] = Solid_principal_batched(s11, s22, s33, s12, s23, s13)
    s11 = Solid_nanfill(s11);
    s22 = Solid_nanfill(s22);
    s33 = Solid_nanfill(s33);
    s12 = Solid_nanfill(s12);
    s23 = Solid_nanfill(s23);
    s13 = Solid_nanfill(s13);

    I1 = s11 + s22 + s33;
    sm = I1 / 3;

    d11 = s11 - sm;
    d22 = s22 - sm;
    d33 = s33 - sm;

    J2 = 0.5*(d11.^2 + d22.^2 + d33.^2) + s12.^2 + s23.^2 + s13.^2;
    p  = sqrt(max(J2/3, 0));

    J3 = d11.*(d22.*d33 - s23.^2) ...
       - s12.*(s12.*d33 - s23.*s13) ...
       + s13.*(s12.*s23 - d22.*s13);

    tiny  = 1e-12;
    ratio = -0.5 * J3 ./ max(p.^3, tiny);
    ratio = min(max(ratio, -1), 1);
    phi   = acos(ratio) / 3;

    two_p = 2 * p;
    p1 = sm + two_p .* cos(phi);
    p2 = sm + two_p .* cos(phi + 2*pi/3);
    p3 = sm + two_p .* cos(phi + 4*pi/3);

    pall = cat(3, p1, p2, p3);
    pall = sort(pall, 3, 'descend');
    p1 = pall(:,:,1);
    p2 = pall(:,:,2);
    p3 = pall(:,:,3);
end

function x = Solid_nanfill(x)
    x(isnan(x)) = 0;
end

% =========================================================================
% Failure criteria
% =========================================================================

function [sigma_eq, sigma_y] = Solid_mc_sy(p1, p2, p3, syc, syt)
    m   = syc / (syt + 1e-10);
    K   = (m - 1) / (m + 1);
    t12 = abs(p1-p2) + K*(p1+p2);
    t13 = abs(p1-p3) + K*(p1+p3);
    t23 = abs(p2-p3) + K*(p2+p3);
    sigma_eq = 0.5*(m+1)*max(max(t12,t13), t23);
    sigma_y  = syc;
end

function [sigma_eq, sigma_y] = Solid_mc_cphi(p1, p2, p3, c, phi)
    cp = cos(phi);
    tp = tan(phi);
    fn = @(si,sj) 0.5*abs(si-sj)/cp - 0.5*(si+sj)*tp;
    sigma_eq = max(max(fn(p1,p2), fn(p1,p3)), fn(p2,p3));
    sigma_y  = c;
end

function [sigma_eq, sigma_y] = Solid_dp_sy(p1, p2, p3, syc, syt)
    m  = syc / (syt + 1e-10);
    I1 = p1 + p2 + p3;
    q  = sqrt(0.5*((p1-p2).^2 + (p2-p3).^2 + (p3-p1).^2));
    sigma_eq = 0.5*(m-1)*I1 + 0.5*(m+1)*q;
    sigma_y  = syc;
end

function [sigma_eq, sigma_y] = Solid_dp_cphi(p1, p2, p3, c, phi, kind)
    I1   = p1 + p2 + p3;
    J2   = ((p1-p2).^2 + (p2-p3).^2 + (p3-p1).^2) / 6;
    sqJ2 = sqrt(J2);
    sp   = sin(phi);
    cp   = cos(phi);

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
            error('Solid_dp_cphi:UnknownKind', ...
                'kind must be circumscribed, middle, or inscribed.');
    end

    sigma_eq = sqJ2 - B*I1;
    sigma_y  = A;
end

% =========================================================================
% Option parsing
% =========================================================================

function [nodalMethod, porePressure, measureOpts, rest] = Solid_parse_options(varargin)
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

                if isempty(measures)
                    continue;
                end

                if ischar(measures) || isstring(measures)
                    measures = cellstr(string(measures));
                end

                if ~iscell(measures)
                    error('solid_parse_options:InvalidMeasures', ...
                        'computeMechanicalMeasures must be a string, string array, or cell array.');
                end

                for j = 1:numel(measures)
                    item = measures{j};

                    if ischar(item) || isstring(item)
                        m = lower(char(string(item)));
                        switch m
                            case 'principal'
                                measureOpts.principal = true;
                            case 'vonmises'
                                measureOpts.vonmises = true;
                            case 'taumax'
                                measureOpts.taumax = true;
                            case 'octahedral'
                                measureOpts.octahedral = true;
                            otherwise
                                error('solid_parse_options:UnknownMeasure', ...
                                    'Unknown mechanical measure: %s', char(string(item)));
                        end
                    elseif iscell(item)
                        if isempty(item)
                            continue;
                        end

                        name = item{1};
                        if ~(ischar(name) || isstring(name))
                            error('solid_parse_options:InvalidMeasureName', ...
                                'The first entry of a measure cell must be a string.');
                        end

                        m = lower(char(string(name)));

                        switch m
                            case 'mohrcoulombsy'
                                if numel(item) < 3
                                    error('solid_parse_options:InvalidMohrCoulombSy', ...
                                        'mohrCoulombSy requires {name, syc, syt}.');
                                end
                                measureOpts.mohrcoulombsy = [double(item{2}), double(item{3})];

                            case 'mohrcoulombcphi'
                                if numel(item) < 3
                                    error('solid_parse_options:InvalidMohrCoulombCPhi', ...
                                        'mohrCoulombCPhi requires {name, c, phi}.');
                                end
                                measureOpts.mohrcoulombcphi = [double(item{2}), double(item{3})];

                            case 'druckerpragersy'
                                if numel(item) < 3
                                    error('solid_parse_options:InvalidDruckerPragerSy', ...
                                        'druckerPragerSy requires {name, syc, syt}.');
                                end
                                measureOpts.druckerpragersy = [double(item{2}), double(item{3})];

                            case 'druckerpragercphi'
                                if numel(item) < 3
                                    error('solid_parse_options:InvalidDruckerPragerCPhi', ...
                                        'druckerPragerCPhi requires {name, c, phi, [kind]}.');
                                end
                                if numel(item) >= 4
                                    measureOpts.druckerpragercphi = {double(item{2}), double(item{3}), char(string(item{4}))};
                                else
                                    measureOpts.druckerpragercphi = {double(item{2}), double(item{3}), 'circumscribed'};
                                end

                            otherwise
                                error('solid_parse_options:UnknownAdvancedMeasure', ...
                                    'Unknown advanced mechanical measure: %s', m);
                        end

                    else
                        error('solid_parse_options:InvalidMeasureItem', ...
                            'Each mechanical measure entry must be a string or a cell.');
                    end
                end

            otherwise
                rest{end+1} = varargin{i}; %#ok<AGROW>
                i = i + 1;
        end
    end
end

function obj = Solid_apply_measure_opts(obj, opts)
    fields = fieldnames(opts);
    for k = 1:numel(fields)
        switch lower(char(fields{k}))
            case 'principal'
                obj.measurePrincipal = true;
            case 'vonmises'
                obj.measureVonMises = true;
            case 'taumax'
                obj.measureTauMax = true;
            case 'octahedral'
                obj.measureOctahedral = true;
            case 'mohrcoulombsy'
                obj.measureMohrCoulombSy = double(opts.mohrcoulombsy(:).');
            case 'mohrcoulombcphi'
                obj.measureMohrCoulombCPhi = double(opts.mohrcoulombcphi(:).');
            case 'druckerpragersy'
                obj.measureDruckerPragerSy = double(opts.druckerpragersy(:).');
            case 'druckerpragercphi'
                obj.measureDruckerPragerCPhi = opts.druckerpragercphi;  % cell with fields 'c', 'phi', optional 'kind'
        end
    end
end

% =========================================================================
% Utilities
% =========================================================================

function t = Solid_ele_type_from_n(nNode)
    if ismember(nNode, [4, 10])
        t = 'tet';
    elseif ismember(nNode, [8, 20, 27])
        t = 'brick';
    else
        error('SolidRespStepData:UnsupportedSolidNodeCount', ...
            'Unsupported solid element node count: %d.', nNode);
    end
end

function labels = Solid_stress_dof_labels(n)
    base = {'sxx','syy','szz','sxy','syz','sxz'};
    labels = cell(1, n);
    for k = 1:n
        if k <= numel(base)
            labels{k} = base{k};
        else
            labels{k} = sprintf('para%d', k - numel(base));
        end
    end
end

function labels = Solid_strain_dof_labels(n)
    base = {'exx','eyy','ezz','exy','eyz','exz'};
    labels = cell(1, n);
    for k = 1:n
        if k <= numel(base)
            labels{k} = base{k};
        else
            labels{k} = sprintf('para%d', k - numel(base));
        end
    end
end