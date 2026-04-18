classdef FrameRespStepData < post.resp.ResponseBase
    % FrameRespStepData  Collect frame element responses step by step.
    %
    % Model-update / adaptive-mesh support
    % -----------------------------------
    % When modelUpdate = true, elements may be added or removed between
    % steps. Each step struct stores an 'eleTags' column vector alongside
    % the response arrays. Before merging, local_align_parts_by_tags
    % expands every step to the global union of all element tags; entries
    % that were absent in a given step are filled with NaN.
    %
    % Caching strategy
    % ----------------
    % All quantities that never change at runtime are cached per element tag.
    %
    %   eleClassCache         eleTag -> logical
    %   eleStartCoords        eleTag -> [1x3] double
    %   eleEndCoords          eleTag -> [1x3] double
    %   eleLengths            eleTag -> double
    %   localRespNameCache    eleTag -> char
    %   basicForceNameCache   eleTag -> char
    %   basicDefoNameCache    eleTag -> char
    %   plasticRespNameCache  eleTag -> char
    %   secLocCache           eleTag -> double row vector
    %   secColMapCache        eleTag -> cell{1 x nSec} of int8 colMap
    %   eleParamCache         eleTag -> struct(E,Iz,Iy,G,Avy,Avz)

    properties (Constant)
        RESP_NAME = 'FrameResponses'

        ELASTIC_BEAM_CLASSES = int32([3, 4, 5, 5001, 145, 146, 63, 631])

        LOCAL_DOFS = {'FxI','FyI','FzI','MxI','MyI','MzI', ...
                      'FxJ','FyJ','FzJ','MxJ','MyJ','MzJ'}
        BASIC_DOFS = {'N','MzI','MzJ','MyI','MyJ','T'}
        SEC_DOFS   = {'N','Mz','Vy','My','Vz','T'}

        LOCAL_SIGN = [-1,-1,-1,-1,1,-1, 1,1,1,1,-1,1]
    end

    properties
        eleTags                         double
        beamLoadData
        elasticFrameSecPoints           double  = 7
        sectionTypeMap                  struct
        hassectionResponseTypeMethod    logical

        % Section metadata (determined on the first step)
        secPoints
        secLocDofs

        % ---- Per-element caches -----------------------------------------
        eleClassCache
        eleStartCoords
        eleEndCoords
        eleLengths

        localRespNameCache
        basicForceNameCache
        basicDefoNameCache
        plasticRespNameCache

        secLocCache
        secColMapCache
        eleParamCache
    end

    methods
        function obj = FrameRespStepData(ops, eleTags, beamLoadData, ...
                elasticFrameSecPoints, varargin)

            obj@post.resp.ResponseBase(ops, varargin{:});

            if isempty(eleTags)
                obj.eleTags = [];
            else
                obj.eleTags = double(eleTags(:).');
            end

            if nargin < 4 || isempty(elasticFrameSecPoints)
                elasticFrameSecPoints = 7;
            end

            obj.beamLoadData                 = beamLoadData;
            obj.elasticFrameSecPoints        = elasticFrameSecPoints;
            obj.hassectionResponseTypeMethod = ismethod(obj.ops, 'sectionResponseType');
            obj.sectionTypeMap               = frame_section_type_map();

            obj.eleClassCache        = containers.Map('KeyType','double','ValueType','logical');
            obj.eleStartCoords       = containers.Map('KeyType','double','ValueType','any');
            obj.eleEndCoords         = containers.Map('KeyType','double','ValueType','any');
            obj.eleLengths           = containers.Map('KeyType','double','ValueType','double');

            obj.localRespNameCache   = containers.Map('KeyType','double','ValueType','char');
            obj.basicForceNameCache  = containers.Map('KeyType','double','ValueType','char');
            obj.basicDefoNameCache   = containers.Map('KeyType','double','ValueType','char');
            obj.plasticRespNameCache = containers.Map('KeyType','double','ValueType','char');

            obj.secLocCache          = containers.Map('KeyType','double','ValueType','any');
            obj.secColMapCache       = containers.Map('KeyType','double','ValueType','any');
            obj.eleParamCache        = containers.Map('KeyType','double','ValueType','any');

            obj.addRespDataOneStep(obj.eleTags, obj.beamLoadData);
        end

        function addRespDataOneStep(obj, eleTags, beamLoadData)
            if nargin < 2 || isempty(eleTags)
                eleTags = obj.eleTags;
            end
            if nargin < 3
                beamLoadData = obj.beamLoadData;
            end

            eleTags = double(eleTags(:).');

            [localF, basicF, basicD, plasticD] = frame_get_force_defo( ...
                obj.ops, eleTags, ...
                obj.localRespNameCache, ...
                obj.basicForceNameCache, ...
                obj.basicDefoNameCache, ...
                obj.plasticRespNameCache);

            [secF, secD, secLocs] = frame_get_section_resp( ...
                obj.ops, eleTags, beamLoadData, localF, basicD, ...
                obj.elasticFrameSecPoints, obj.sectionTypeMap, ...
                obj.hassectionResponseTypeMethod, ...
                obj.eleClassCache, obj.eleStartCoords, ...
                obj.eleEndCoords,  obj.eleLengths, ...
                obj.secLocCache,   obj.secColMapCache, obj.eleParamCache, ...
                obj.ELASTIC_BEAM_CLASSES);

            if isempty(obj.secPoints)
                nPts          = size(secF, 2);
                obj.secPoints = 1:nPts;
                nLoc          = size(secLocs, 3);
                switch nLoc
                    case 2
                        obj.secLocDofs = {'alpha','X'};
                    case 3
                        obj.secLocDofs = {'alpha','X','Y'};
                    case 4
                        obj.secLocDofs = {'alpha','X','Y','Z'};
                    otherwise
                        obj.secLocDofs = arrayfun( ...
                            @(i) sprintf('loc%d', i), 1:nLoc, ...
                            'UniformOutput', false);
                end
            end

            S = struct( ...
                'eleTags',             eleTags(:), ...
                'localForces',         localF, ...
                'basicForces',         basicF, ...
                'basicDeformations',   basicD, ...
                'plasticDeformation',  plasticD, ...
                'sectionForces',       secF, ...
                'sectionDeformations', secD, ...
                'sectionLocs',         secLocs);

            obj.addStepData(S, obj.getCurrentOpsTime());
        end
    end

    methods (Access = protected)
        function [parts, metaFields] = preProcessParts(obj, parts)
            [parts, metaFields] = obj.alignPartsByTags(parts, 'eleTags');
        end
    end

    methods (Static)
        function S = readResponse(data, options)
            arguments
                data
                options.eleTags double = []
                options.respType string = ""
            end

            if ~isfield(data, "eleTags")
                S = struct();
                return;
            end


            respTypes = { ...
                'localForces', ...
                'basicForces', ...
                'basicDeformations', ...
                'plasticDeformation', ...
                'sectionForces', ...
                'sectionDeformations', ...
                'sectionLocs'};

            localDofs = {'FxI','FyI','FzI','MxI','MyI','MzI', ...
                        'FxJ','FyJ','FzJ','MxJ','MyJ','MzJ'};
            basicDofs = {'N','MzI','MzJ','MyI','MyJ','T'};
            secDofs   = {'N','Mz','Vy','My','Vz','T'};

            if strlength(options.respType) > 0
                rt = char(options.respType);
                if ~ismember(rt, respTypes)
                    error('readResponse:InvalidRespType', ...
                        'Unknown respType "%s". Valid types: %s', ...
                        options.respType, strjoin(respTypes, ', '));
                end
                respTypes = {rt};
            end

            allEleTags = double(data.eleTags(:).');
            selectAll = isempty(options.eleTags);

            if selectAll
                eleIdx = [];
                selectedTags = allEleTags;
            else
                queryTags = double(options.eleTags(:).');
                [tf, eleIdx] = ismember(queryTags, allEleTags);
                if ~all(tf)
                    missing = queryTags(~tf);
                    error('readResponse:InvalidEleTags', ...
                        'Element tags not found in data: %s', mat2str(missing));
                end
                selectedTags = allEleTags(eleIdx);
            end

            S = struct();
            S.ModelUpdate = data.ModelUpdate;
            S.time = data.time;
            S.eleTags = selectedTags(:);

            for k = 1:numel(respTypes)
                rt = respTypes{k};
                if ~isfield(data, rt)
                    continue;
                end

                d = data.(rt);
                if isempty(d) || ~isnumeric(d)
                    continue;
                end

                switch rt
                    case 'localForces'
                        if ndims(d) ~= 3, continue; end
                        if ~selectAll, d = d(:, eleIdx, :); end
                        nDof = min(size(d, 3), numel(localDofs));
                        S.(rt) = struct();
                        for di = 1:nDof
                            S.(rt).(localDofs{di}) = d(:, :, di);
                        end

                    case {'basicForces', 'basicDeformations', 'plasticDeformation'}
                        if ndims(d) ~= 3, continue; end
                        if ~selectAll, d = d(:, eleIdx, :); end
                        nDof = min(size(d, 3), numel(basicDofs));
                        S.(rt) = struct();
                        for di = 1:nDof
                            S.(rt).(basicDofs{di}) = d(:, :, di);
                        end

                    case {'sectionForces', 'sectionDeformations'}
                        if ndims(d) ~= 4, continue; end
                        if ~selectAll, d = d(:, eleIdx, :, :); end
                        nDof = min(size(d, 4), numel(secDofs));
                        S.(rt) = struct();
                        for di = 1:nDof
                            S.(rt).(secDofs{di}) = d(:, :, :, di);
                        end

                    case 'sectionLocs'
                        if ndims(d) ~= 4, continue; end
                        if ~selectAll, d = d(:, eleIdx, :, :); end
                        if isfield(data, 'secLocDofs') && ~isempty(data.secLocDofs)
                            locDofs = data.secLocDofs;
                            nLoc = min(size(d, 4), numel(locDofs));
                        else
                            nLoc = size(d, 4);
                            locDofs = arrayfun( ...
                                @(i) sprintf('loc%d', i), 1:nLoc, ...
                                'UniformOutput', false);
                        end
                        S.sectionLocs = struct();
                        for di = 1:nLoc
                            S.sectionLocs.(lower(locDofs{di})) = d(:, :, :, di);
                        end
                end
            end
        end
    end
end

% =========================================================================
% Section type map and DOF index helper
% =========================================================================

function m = frame_section_type_map()
    m = struct( ...
        'ElasticSection3d',             {{'P','MZ','MY','T'}}, ...
        'ElasticShearSection3d',        {{'P','MZ','VY','MY','VZ','T'}}, ...
        'ElasticTubeSection3d',         {{'P','MZ','MY','T','VY','VZ'}}, ...
        'FiberSection3d',               {{'P','MZ','MY','T'}}, ...
        'FiberSection3dThermal',        {{'P','MZ','MY','T'}}, ...
        'FiberSectionGJ',               {{'P','MZ','MY','T'}}, ...
        'FiberSectionGJThermal',        {{'P','MZ','MY','T'}}, ...
        'FiberSectionAsym3d',           {{'P','MZ','MY','W','T'}}, ...
        'FiberSectionWarping3d',        {{'P','MZ','MY','W','B','T'}}, ...
        'NDFiberSection3d',             {{'P','MZ','MY','VY','VZ','T'}}, ...
        'SectionAggregator3d',          {{'P','MZ','MY','T','VY','VZ'}}, ...
        'TimoshenkoSection3d',          {{'P','MZ','MY','VZ','VY','T'}}, ...
        'ASDCoupledHinge3D',            {{'P','MY','MZ','VY','VZ','T'}}, ...
        'ElasticSection2d',             {{'P','MZ'}}, ...
        'ElasticShearSection2d',        {{'P','MZ','VY'}}, ...
        'ElasticWarpingShearSection2d', {{'P','MZ','VY','R','Q'}}, ...
        'FiberSection2d',               {{'P','MZ'}}, ...
        'FiberSection2dThermal',        {{'P','MZ'}}, ...
        'Isolator2spring',              {{'P','VY','MZ'}}, ...
        'NDFiberSection2d',             {{'P','MZ','VY'}}, ...
        'NDFiberSectionWarping2d',      {{'P','MZ','VY','R','Q'}}, ...
        'SectionAggregator2d',          {{'P','MZ','VY'}}, ...
        'ElasticBDShearSection2d',      {{'P','MZ','VY'}}, ...
        'WSection2d',                   {{'P','MZ','MY','VY','VZ','T'}});
end

function idx = frame_section_dof_index(name)
    switch name
        case 'P'
            idx = 1;
        case 'MZ'
            idx = 2;
        case 'VY'
            idx = 3;
        case 'MY'
            idx = 4;
        case 'VZ'
            idx = 5;
        case 'T'
            idx = 6;
        otherwise
            idx = 0;
    end
end

% =========================================================================
% Force / deformation collection
% =========================================================================

function [localF, basicF, basicD, plasticD] = frame_get_force_defo( ...
        ops, eleTags, localNameCache, basicFNameCache, ...
        basicDNameCache, plasticNameCache)

    nEle     = numel(eleTags);
    localF   = zeros(nEle, 12);
    basicF   = zeros(nEle, 6);
    basicD   = zeros(nEle, 6);
    plasticD = zeros(nEle, 6);

    localNames   = {'localForces','localForce'};
    basicFNames  = {'basicForce','basicForces'};
    basicDNames  = {'basicDeformation','basicDeformations', ...
                    'chordRotation','chordDeformation','deformations'};
    plasticNames = {'plasticRotation','plasticDeformation'};

    for i = 1:nEle
        tag = eleTags(i);
        localF(i,:)   = frame_get_local_force(ops, tag, localNames,   localNameCache);
        basicF(i,:)   = frame_get_basic_resp( ops, tag, basicFNames,  basicFNameCache);
        basicD(i,:)   = frame_get_basic_resp( ops, tag, basicDNames,  basicDNameCache);
        plasticD(i,:) = frame_get_basic_resp( ops, tag, plasticNames, plasticNameCache);
    end
end

function f = frame_get_local_force(ops, tag, names, nameCache)
    raw = frame_try_ele_response(ops, tag, names, nameCache);
    n   = numel(raw);

    if n == 0
        f = zeros(1, 12);
        return;
    elseif n == 6
        tmp = zeros(1, 12);
        tmp([1 2 6 7 8 12]) = double(raw(1:6));
        raw = tmp;
    elseif n > 12
        raw = raw([1:6, 8:13]);
    else
        raw = double(raw(1:12));
    end

    f = [-1,-1,-1,-1,1,-1, 1,1,1,1,-1,1] .* double(raw(1:12));
end

function r = frame_get_basic_resp(ops, tag, names, nameCache)
    raw = frame_try_ele_response(ops, tag, names, nameCache);
    n   = numel(raw);

    if n == 0
        r = zeros(1, 6);
        return;
    end

    raw = double(raw(:).');
    if n == 3
        tmp = zeros(1, 6);
        tmp(1:3) = raw;
        raw = tmp;
    elseif n < 6
        tmp = zeros(1, 6);
        tmp(1:n) = raw;
        raw = tmp;
    else
        raw = raw(1:6);
    end

    r = [raw(1), -raw(2), raw(3), raw(4), -raw(5), raw(6)];  % 'N','MZ1','MZ2','MY1','MY2','T'
end

function raw = frame_try_ele_response(ops, tag, names, nameCache)
    if ~isKey(nameCache, tag)
        % First encounter: find the winning name and cache it.
        for i = 1:numel(names)
            out = ops.eleResponse(tag, names{i});
            if ~isempty(out)
                nameCache(tag) = names{i};   % handle — modifies caller's Map
                break;
            end
        end
    end

    if isKey(nameCache, tag)
        raw = ops.eleResponse(tag, nameCache(tag));
    else
        raw = [];
    end
end

% =========================================================================
% Section response collection
% =========================================================================

function [secF, secD, secLocs] = frame_get_section_resp( ...
        ops, eleTags, beamLoadData, localF, basicD, nSecElastic, ...
        sectionTypeMap, hasSRT, ...
        eleClassCache, eleStartCoords, eleEndCoords, eleLengths, ...
        secLocCache, secColMapCache, eleParamCache, elasticClasses)

    nEle = numel(eleTags);

    [patternTags, loadEleTags, loadData] = frame_extract_pattern_info(beamLoadData);
    patternFactorMap = frame_build_pattern_factor_map(ops, patternTags);

    maxPts = nSecElastic;
    needSuppress = false;

    % First pass: fill caches for first-seen tags.
    for i = 1:nEle
        tag = eleTags(i);

        if ~isKey(eleLengths, tag)
            nodes = double(ops.eleNodes(tag));
            c1    = frame_pad_coord3(double(ops.nodeCoord(nodes(1))));
            c2    = frame_pad_coord3(double(ops.nodeCoord(nodes(2))));
            eleStartCoords(tag) = c1;
            eleEndCoords(tag)   = c2;
            eleLengths(tag)     = norm(c2 - c1);
        end

        if ~isKey(eleClassCache, tag)
            eleClassCache(tag) = ismember(int32(ops.getEleClassTags(tag)), elasticClasses);
        end

        if eleClassCache(tag)
            if ~isKey(eleParamCache, tag)
                needSuppress = true;
            end
        else
            L = eleLengths(tag);

            if ~isKey(secLocCache, tag)
                secLocCache(tag) = frame_get_section_locs(ops, tag, L);
            end

            if ~isKey(secColMapCache, tag)
                locs = secLocCache(tag);
                nSec = numel(locs);
                colMaps = cell(1, nSec);

                secTags = double(ops.sectionTag(tag));
                secTypes = cell(1, numel(secTags));
                for j = 1:numel(secTags)
                    secTypes{j} = char(ops.classType('section', secTags(j)));
                end

                for k = 1:nSec
                    colMaps{k} = frame_build_col_map_cached( ...
                        ops, tag, k, secTags, secTypes, sectionTypeMap, hasSRT);
                end
                secColMapCache(tag) = colMaps;
            end

            maxPts = max(maxPts, numel(secLocCache(tag)));
        end
    end

    if needSuppress
        ops.suppressPrint(true);
        cleaner = onCleanup(@() ops.suppressPrint(false));
        for i = 1:nEle
            tag = eleTags(i);
            if eleClassCache(tag) && ~isKey(eleParamCache, tag)
                eleParamCache(tag) = frame_cache_elastic_params_no_toggle(ops, tag);
            end
        end
    end

    % Pull hot cache data into local arrays once.
    startCoords = zeros(nEle, 3);
    endCoords   = zeros(nEle, 3);
    lengths     = zeros(nEle, 1);
    isElastic   = false(nEle, 1);

    for i = 1:nEle
        tag = eleTags(i);
        startCoords(i,:) = eleStartCoords(tag);
        endCoords(i,:)   = eleEndCoords(tag);
        lengths(i)       = eleLengths(tag);
        isElastic(i)     = eleClassCache(tag);
    end

    secF  = nan(nEle, maxPts, 6);
    secD  = nan(nEle, maxPts, 6);
    xlocs = nan(nEle, maxPts);

    for i = 1:nEle
        tag = eleTags(i);
        L   = lengths(i);

        if isElastic(i)
            xi = linspace(0, 1, nSecElastic);
            sf = frame_elastic_sec_forces( ...
                tag, L, xi, localF(i,:), ...
                patternTags, loadEleTags, loadData, patternFactorMap);

            sd = frame_elastic_sec_defo_cached( ...
                sf, basicD(i,:), L, xi, eleParamCache(tag));

            nPts = numel(xi);
        else
            xi      = secLocCache(tag);
            colMaps = secColMapCache(tag);
            nPts    = numel(xi);

            if nPts == 0
                xi = 0;
                sf = nan(1, 6);
                sd = nan(1, 6);
                nPts = 1;
            else
                sf = zeros(nPts, 6);
                sd = zeros(nPts, 6);
                for k = 1:nPts
                    raw = ops.eleResponse(tag, 'section', k, 'forceAndDeformation');
                    [sd(k,:), sf(k,:)] = frame_apply_col_map(raw, colMaps{k});
                end
            end
        end

        % sf(:,2) = -sf(:,2);
        % sf(:,3) = -sf(:,3);
        % sd(:,2) = -sd(:,2);
        % sd(:,3) = -sd(:,3);

        secF(i,1:nPts,:) = sf;
        secD(i,1:nPts,:) = sd;
        xlocs(i,1:nPts)  = xi;
    end

    secLocs = frame_build_sec_coords(startCoords, endCoords, xlocs);
end

% =========================================================================
% Cache-building helpers
% =========================================================================

function colMap = frame_build_col_map_cached( ...
        ops, tag, secNum, secTags, secTypes, sectionTypeMap, hasSRT)

    if hasSRT
        dofs   = ops.sectionResponseType(tag, secNum);
        nDof   = numel(dofs);
        colMap = zeros(1, nDof, 'int8');
        for i = 1:nDof
            colMap(i) = frame_section_dof_index(char(dofs(i)));
        end
        return;
    end

    if ~isempty(secTags) && secNum <= numel(secTags)
        secType = secTypes{secNum};

        if strcmp(secType, 'SectionAggregator') && ...
                ~isfield(sectionTypeMap, 'SectionAggregator')
            probe   = ops.sectionForce(tag, secNum);
            secType = 'ElasticSection3d';
            if numel(probe) <= 3
                secType = 'ElasticSection2d';
            end
        end

        if isfield(sectionTypeMap, secType)
            dofNames = sectionTypeMap.(secType);
            nDof     = numel(dofNames);
            colMap   = zeros(1, nDof, 'int8');
            for j = 1:nDof
                colMap(j) = frame_section_dof_index(dofNames{j});
            end
            return;
        end
    end

    colMap = int8(1:6);
end

function p = frame_cache_elastic_params_no_toggle(ops, tag)
    p.E   = frame_get_param(ops, tag, 'E');
    p.Iz  = frame_get_param(ops, tag, 'Iz');
    p.Iy  = frame_get_param(ops, tag, 'Iy');
    p.G   = frame_get_param(ops, tag, 'G');
    p.Avy = frame_get_param(ops, tag, 'Avy');
    p.Avz = frame_get_param(ops, tag, 'Avz');
end

function value = frame_get_param(ops, eleTag, paramName)
    existingTags = double(ops.getParamTags());
    newTag = 1;
    if ~isempty(existingTags)
        newTag = max(existingTags) + 1;
    end
    ops.parameter(newTag, 'element', eleTag, paramName);
    value = double(ops.getParamValue(newTag));
    ops.remove('parameter', newTag);
end

% =========================================================================
% Hot-path section helpers
% =========================================================================

function [defo, force] = frame_apply_col_map(raw, colMap)
    defo  = zeros(1, 6);
    force = zeros(1, 6);

    if isempty(raw) || isempty(colMap)
        return;
    end

    nMap  = numel(colMap);
    nRaw  = numel(raw);
    nHalf = floor(nRaw / 2);
    n     = min(nHalf, nMap);

    if n == 0
        return;
    end

    rawDefo  = raw(1:n);
    rawForce = raw(nHalf + (1:n));

    for i = 1:n
        c = colMap(i);
        if c > 0
            defo(c)  = rawDefo(i);
            force(c) = rawForce(i);
        end
    end
end

function locs = frame_get_section_locs(ops, tag, length_)
    raw = ops.sectionLocation(tag);
    if ~isempty(raw)
        locs = double(raw(:).') / length_;
        return;
    end

    secTags = double(ops.sectionTag(tag));
    nSec = numel(secTags);

    if nSec == 0
        locs = [];
    elseif nSec == 1
        locs = 0.5;
    else
        locs = linspace(0, 1, nSec);
    end
end

% =========================================================================
% Elastic beam section forces and deformations
% =========================================================================

function secF = frame_elastic_sec_forces( ...
        tag, length_, xi, localF, ...
        patternTags, loadEleTags, loadData, patternFactorMap)

    % secF columns:
    % [N1, Mz1, Vy1, My1, Vz1, T1]

    secX = xi(:) * length_;
    nPts = numel(secX);
    secF = zeros(nPts, 6);

    % Restore original sign convention from OpenSees localForce
    signFix = [-1,-1,-1,-1, 1,-1, 1,1,1,1,-1,1];
    origF   = signFix(:).' .* double(localF(:).');

    % Base field from element end forces
    secF(:,1) = -origF(1);                  % N1
    secF(:,2) = -origF(6) + origF(2)*secX; % Mz1
    secF(:,3) =  origF(2);                  % Vy1
    secF(:,4) = -origF(5) - origF(3)*secX; % My1
    secF(:,5) = -origF(3);                  % Vz1
    secF(:,6) = -origF(4);                  % T1

    if isempty(loadEleTags) || isempty(loadData)
        return;
    end

    tagMask = abs(double(loadEleTags(:)) - double(tag)) < 1e-12;
    if ~any(tagMask)
        return;
    end

    matchData    = double(loadData(tagMask, :));
    matchPattern = double(patternTags(tagMask));

    for iLoad = 1:size(matchData,1)
        ptag = matchPattern(iLoad);
        if isKey(patternFactorMap, ptag)
            factor = double(patternFactorMap(ptag));
        else
            factor = 0.0;
        end

        d = matchData(iLoad,:);

        % Expected format:
        % [wya, wyb, wza, wzb, wxa, wxb, xa, xb, ...]
        %
        % For now, keep the same effective behavior as your Python reference:
        % use the "a-end" values.
        wya = getcol(d,1);  wyb = getcol(d,2);
        wza = getcol(d,3);  wzb = getcol(d,4);
        wxa = getcol(d,5);  wxb = getcol(d,6);
        xa  = getcol(d,7);
        xb  = getcol(d,8);

        wy = wya * factor;
        wz = wza * factor;
        wx = wxa * factor;

        hasDistributed = any(abs([wya wyb wza wzb wxa wxb]) > 1e-12);

        % ------------------------------------------------------------
        % Normalize malformed storage:
        % distributed load present, but xa=0 and xb=0 -> treat as full-span
        % ------------------------------------------------------------
        if hasDistributed && abs(xa) < 1e-12 && abs(xb) < 1e-12
            xa = 0.0;
            xb = 1.0;
        end

        % ------------------------------------------------------------
        % Case 1: full uniform load over full element
        % ------------------------------------------------------------
        if xb > xa && abs((xb - xa) - 1.0) < 1e-2
            secF(:,1) = secF(:,1) - wx .* secX;
            secF(:,2) = secF(:,2) + 0.5 * wy .* secX.^2;
            secF(:,3) = secF(:,3) + wy .* secX;
            secF(:,4) = secF(:,4) - 0.5 * wz .* secX.^2;
            secF(:,5) = secF(:,5) - wz .* secX;
            continue;
        end

        % ------------------------------------------------------------
        % Case 2: point load (same convention as your Python version)
        % xb < xa means point load located at xa
        % ------------------------------------------------------------
        if xb < xa
            px = wx;
            py = wy;
            pz = wz;

            xaAbs = xa * length_;
            past  = secX > xaAbs;

            secF(past,1) = secF(past,1) - px;
            secF(past,2) = secF(past,2) + py .* (secX(past) - xaAbs);
            secF(past,3) = secF(past,3) + py;
            secF(past,4) = secF(past,4) - pz .* (secX(past) - xaAbs);
            secF(past,5) = secF(past,5) - pz;
            continue;
        end

        % ------------------------------------------------------------
        % Case 3: partial uniform load on [xa, xb]
        % ------------------------------------------------------------
        xaAbs = xa * length_;
        xbAbs = xb * length_;
        fullLen = xbAbs - xaAbs;

        if fullLen <= 0
            continue;
        end

        in   = (secX > xaAbs) & (secX < xbAbs);
        past = secX >= xbAbs;

        dx = secX(in) - xaAbs;

        secF(in,1) = secF(in,1) - wx .* dx;
        secF(in,2) = secF(in,2) + 0.5 * wy .* dx.^2;
        secF(in,3) = secF(in,3) + wy .* dx;
        secF(in,4) = secF(in,4) - 0.5 * wz .* dx.^2;
        secF(in,5) = secF(in,5) - wz .* dx;

        secF(past,1) = secF(past,1) - wx * fullLen;
        secF(past,2) = secF(past,2) + wy * fullLen .* (secX(past) - 0.5*(xaAbs + xbAbs));
        secF(past,3) = secF(past,3) + wy * fullLen;
        secF(past,4) = secF(past,4) - wz * fullLen .* (secX(past) - 0.5*(xaAbs + xbAbs));
        secF(past,5) = secF(past,5) - wz * fullLen;
    end
end

function v = getcol(row, j)
    if numel(row) >= j
        v = row(j);
    else
        v = 0.0;
    end
end

function secD = frame_elastic_sec_defo_cached(secF, basicD, length_, xi, p)
    % secD columns:
    % [eps, kappa_z, gamma_y, kappa_y, gamma_z, theta_x/L]

    nPts = size(secF, 1);
    secD = zeros(nPts, 6);

    eps_ = 1e-10;
    oneL = 1.0 / length_;
    xi6  = 6.0 * xi(:);

    basicD = double(basicD(:)).';

    % axial strain / torsional twist rate
    secD(:,1) = basicD(1) * oneL;
    secD(:,6) = basicD(6) * oneL;

    % bending about z -> Mz
    if p.E * p.Iz > eps_
        secD(:,2) = secF(:,2) / (p.E * p.Iz);
    else
        secD(:,2) = oneL * ((xi6 - 4.0) .* (-basicD(2)) + (xi6 - 2.0) .* basicD(3));
    end

    % bending about y -> My
    if p.E * p.Iy > eps_
        secD(:,4) = secF(:,4) / (p.E * p.Iy);
    else
        secD(:,4) = oneL * ((xi6 - 4.0) .* basicD(4) + (xi6 - 2.0) .* (-basicD(5)));
    end

    % shear
    if p.G * p.Avy > eps_
        secD(:,3) = secF(:,3) / (p.G * p.Avy);
    end

    if p.G * p.Avz > eps_
        secD(:,5) = secF(:,5) / (p.G * p.Avz);
    end
end

% =========================================================================
% Geometry helpers
% =========================================================================

function c3 = frame_pad_coord3(c)
    c3 = zeros(1, 3);
    n  = min(numel(c), 3);
    c3(1:n) = c(1:n);
end

function secLocs = frame_build_sec_coords(startCoords, endCoords, xlocs)
    nEle = size(startCoords, 1);
    nPts = size(xlocs, 2);

    dir_ = endCoords - startCoords;
    coords = reshape(startCoords, nEle, 1, 3) + ...
             reshape(dir_,       nEle, 1, 3) .* reshape(xlocs, nEle, nPts, 1);

    secLocs = cat(3, reshape(xlocs, nEle, nPts, 1), coords);
end

% =========================================================================
% Pattern / load data extraction
% =========================================================================

function [patternTags, loadEleTags, loadData] = frame_extract_pattern_info(beamLoadData)
    % Output:
    % patternTags : [nLoad x 1]
    % loadEleTags : [nLoad x 1]
    % loadData    : [nLoad x 8]
    %
    % loadData columns:
    % [wya, wyb, wza, wzb, wxa, wxb, xa, xb]

    patternTags = zeros(0,1);
    loadEleTags = zeros(0,1);
    loadData    = zeros(0,8);

    if isempty(beamLoadData) || ~isstruct(beamLoadData)
        return;
    end
    if ~isfield(beamLoadData, 'PatternElementTags') || ...
       ~isfield(beamLoadData, 'Values')
        return;
    end

    pairTags = double(beamLoadData.PatternElementTags);
    vals     = double(beamLoadData.Values);

    if isempty(pairTags) || isempty(vals)
        return;
    end

    % ----------------------------
    % normalize PatternElementTags
    % expected: [patternTag, eleTag]
    % ----------------------------
    if isvector(pairTags)
        if numel(pairTags) ~= 2
            error('frame_extract_pattern_info:InvalidPatternElementTags', ...
                'PatternElementTags must contain [patternTag, eleTag].');
        end
        pairTags = reshape(pairTags, 1, 2);
    end

    if size(pairTags,2) ~= 2 && size(pairTags,1) == 2
        pairTags = pairTags.';
    end

    if size(pairTags,2) ~= 2
        error('frame_extract_pattern_info:InvalidPatternElementTags', ...
            'PatternElementTags must be n-by-2.');
    end

    % ----------------------------
    % normalize Values
    % ----------------------------
    if isvector(vals)
        vals = reshape(vals, 1, []);
    end

    nLoad = size(pairTags,1);
    if size(vals,1) ~= nLoad
        if size(vals,1) == 1 && nLoad == 1
            % okay
        else
            error('frame_extract_pattern_info:SizeMismatch', ...
                'PatternElementTags row count and Values row count do not match.');
        end
    end

    patternTags = pairTags(:,1);
    loadEleTags = pairTags(:,2);

    % Only first 8 entries are used here:
    % [wya, wyb, wza, wzb, wxa, wxb, xa, xb]
    nCols = min(size(vals,2), 8);
    loadData = zeros(size(vals,1), 8);
    loadData(:,1:nCols) = vals(:,1:nCols);

    % Defaults:
    % if xa/xb are absent, interpret as full-span load
    if nCols < 7
        loadData(:,7) = 0.0;
    end
    if nCols < 8
        loadData(:,8) = 1.0;
    end
end

function factorMap = frame_build_pattern_factor_map(ops, patternTags)
    factorMap = containers.Map('KeyType', 'double', 'ValueType', 'double');

    if isempty(patternTags)
        return;
    end

    uTags = unique(double(patternTags(:)));
    for i = 1:numel(uTags)
        try
            factorMap(uTags(i)) = double(ops.getLoadFactor(uTags(i)));
        catch
            factorMap(uTags(i)) = 0.0;
        end
    end
end