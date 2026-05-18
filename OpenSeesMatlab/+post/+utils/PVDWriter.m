classdef PVDWriter < handle
    % PVDWriter
    % Export modelInfo + response datasets to ParaView-readable VTU/PVD files.
    %
    % Data layouts
    % ------------
    % modelInfo / nodalResp / eleResp can each be:
    %   - Scalar struct  : single segment.
    %   - Struct array   : multiple segments, each element is a scalar struct
    %                      covering a contiguous block of global time steps.
    %                      Topology is fixed *within* a segment.
    %
    % Global step indexing
    % --------------------
    % Global step g (0-based) maps to:
    %   segment s   = first segment whose cumulative step count exceeds g
    %   localStep   = g - sum(steps in segments 1..s-1)  (1-based internally)
    %
    % Implemented
    % -----------
    %   nodalResp  -> nodal PointData dataset on raw mesh
    %   nodalResp with interpolatePoints/interpolateDisp/interpolateCells
    %              -> combined raw-mesh + interpolated-beam dataset
    %
    % Reserved
    % --------
    %   shellResp, solidResp, planeResp -> element CellData datasets

    properties
        ModelInfo       % scalar struct OR struct array (one per segment)
    end

    properties (Access = private)
        % Segment bookkeeping
        SegCount        double = 1
        SegStepCounts   double = []
        SegOffsets      double = []

        % Each entry: struct with fields .resp .kind .label .famName
        Datasets cell = {}
        NodalResp       % scalar struct OR struct array (one per segment)
        HasInterpResp logical = false

        % Per-segment caches (cell arrays, one entry per segment)
        StaticNodeCache     cell = {}   % {1 x SegCount}
        StaticRawMeshCache  cell = {}   % {1 x SegCount}
        StaticFamilyMeshCache cell = {} % {1 x SegCount} each is a struct of famName->cached
    end

    methods

        function obj = PVDWriter(modelInfo, opts)
            arguments
                modelInfo               struct
                opts.nodalResp          struct = struct()
                opts.shellResp          struct = struct()
                opts.solidResp          struct = struct()
                opts.planeResp          struct = struct()
            end

            if ~isfield(modelInfo(1),'Nodes')
                error('PVDWriter:InvalidInput', ...
                    'modelInfo must contain a Nodes field.');
            end

            obj.ModelInfo = modelInfo;
            obj.NodalResp = obj.normalizeNodalResp(opts.nodalResp);
            shellResp = obj.normalizeElementResp(opts.shellResp, 'Shell');
            solidResp = obj.normalizeElementResp(opts.solidResp, 'Solid');
            planeResp = obj.normalizeElementResp(opts.planeResp, 'Plane');
            obj.HasInterpResp = obj.isInterpResp(obj.NodalResp);

            obj.buildSegmentIndex();

            obj.tryRegisterNodal(obj.NodalResp);
            obj.tryRegisterElement(shellResp, 'Shell');
            obj.tryRegisterElement(solidResp, 'Solid');
            obj.tryRegisterElement(planeResp, 'Plane');

            if isempty(obj.Datasets)
                warning('PVDWriter:NoDatasets', ...
                    'No response datasets were provided.');
            end
        end

        function write(obj, outDir, baseName, opts)
            arguments
                obj
                outDir   (1,:) char = 'paraview_output'
                baseName (1,:) char = 'model'
                opts.binary (1,1) logical = false
            end

            if ~exist(outDir,'dir')
                mkdir(outDir);
            end

            for di = 1:numel(obj.Datasets)
                ds = obj.Datasets{di};
                switch ds.kind
                    case 'nodal'
                        obj.writeNodalDataset(ds, outDir, baseName, opts.binary);
                    case 'interpolated'
                        obj.writeInterpolatedDataset(ds, outDir, baseName, opts.binary);
                    case 'element'
                        obj.writeElementDataset(ds, outDir, baseName, opts.binary);
                end
            end
        end

        function n = nSteps(obj)
            n = sum(obj.SegStepCounts);
        end

    end

    methods (Access = private)

        % =================================================================
        % Segment index
        % =================================================================

        function buildSegmentIndex(obj)
            obj.SegCount = numel(obj.ModelInfo);
            obj.SegStepCounts = zeros(1, obj.SegCount);
            for s = 1:obj.SegCount
                obj.SegStepCounts(s) = obj.countSegSteps(s);
            end
            obj.SegOffsets = [0, cumsum(obj.SegStepCounts(1:end-1))];

            % Pre-allocate per-segment caches
            obj.StaticNodeCache      = cell(1, obj.SegCount);
            obj.StaticRawMeshCache   = cell(1, obj.SegCount);
            obj.StaticFamilyMeshCache = cell(1, obj.SegCount);
            for s = 1:obj.SegCount
                obj.StaticNodeCache{s}      = struct('ready', false);
                obj.StaticRawMeshCache{s}   = struct();
                obj.StaticFamilyMeshCache{s} = struct();
            end
        end

        function n = countSegSteps(obj, segIdx)
            % Count steps using nodalResp time field or data dims.
            resp = obj.getNodalRespSeg(segIdx);
            if isstruct(resp) && isfield(resp,'time') && ~isempty(resp.time)
                n = numel(resp.time);  return;
            end
            if isstruct(resp)
                preferDofs = {'ux','uy','uz','rx','ry','rz'};
                for fn = fieldnames(resp).'
                    A = resp.(fn{1});
                    if isstruct(A)
                        if isfield(A,'data'), A = A.data;
                        else
                            fn2 = fieldnames(A); chosen = '';
                            for pd = preferDofs
                                if ismember(pd{1},fn2), chosen=pd{1}; break; end
                            end
                            if isempty(chosen)
                                if isempty(fn2), continue; end
                                chosen = fn2{1};
                            end
                            A = A.(chosen);
                        end
                    end
                    if isnumeric(A) && ~isempty(A) && ndims(A)>=2
                        n = size(A,1);  return;
                    end
                end
            end
            n = 0;
        end

        function [segIdx, localStep] = resolveGlobalStep(obj, globalStep)
            % globalStep: 0-based. Returns segIdx (1-based), localStep (1-based).
            if globalStep < 0 || globalStep >= obj.nSteps()
                error('PVDWriter:InvalidStep', ...
                    'globalStep %d out of range [0, %d].', globalStep, obj.nSteps()-1);
            end
            segIdx    = find(obj.SegOffsets + obj.SegStepCounts > globalStep, 1, 'first');
            localStep = globalStep - obj.SegOffsets(segIdx) + 1;
        end

        function resp = getNodalRespSeg(obj, segIdx)
            if numel(obj.NodalResp) >= segIdx
                resp = obj.NodalResp(segIdx);
            elseif numel(obj.NodalResp) >= 1
                resp = obj.NodalResp(1);
            else
                resp = struct();
            end
        end

        % =================================================================
        % Dataset registration
        % =================================================================

        function tryRegisterNodal(obj, resp)
            if ~isstruct(resp) || isempty(fieldnames(resp(1))), return; end
            if ~pvdHasExportableData(resp(1)), return; end

            obj.Datasets{end+1} = struct( ...
                'resp', resp, 'kind', 'nodal', ...
                'label', 'nodal', 'famName', '');

            if obj.isInterpResp(resp(1))
                obj.Datasets{end+1} = struct( ...
                    'resp', resp, 'kind', 'interpolated', ...
                    'label', 'interp', 'famName', '');
            end
        end

        function tryRegisterElement(obj, resp, famName)
            if ~isstruct(resp) || isempty(fieldnames(resp(1))), return; end
            if ~pvdHasExportableData(resp(1)), return; end

            obj.Datasets{end+1} = struct( ...
                'resp', resp, 'kind', 'element', ...
                'label', lower(famName), 'famName', famName);
        end

        function tf = isInterpResp(~, resp)
            if numel(resp) >= 1, resp = resp(1); end
            tf = isstruct(resp) && ...
                 isfield(resp,'interpolatePoints') && ~isempty(resp.interpolatePoints) && ...
                 isfield(resp,'interpolateDisp')   && ~isempty(resp.interpolateDisp)   && ...
                 isfield(resp,'interpolateCells')  && ~isempty(resp.interpolateCells);
        end

        function resp = normalizeNodalResp(~, resp)
            if ~isstruct(resp) || isempty(fieldnames(resp(1))), return; end
            resp = pvdUnwrapResponseGroup(resp, post.resp.NodalRespStepData.RESP_NAME);
        end

        function resp = normalizeElementResp(~, resp, famName)
            if ~isstruct(resp) || isempty(fieldnames(resp(1))), return; end
            switch lower(famName)
                case 'shell'
                    resp = pvdUnwrapResponseGroup(resp, post.resp.ShellRespStepData.RESP_NAME);
                case 'plane'
                    resp = pvdUnwrapResponseGroup(resp, post.resp.PlaneRespStepData.RESP_NAME);
                case 'solid'
                    resp = pvdUnwrapResponseGroup(resp, post.resp.SolidRespStepData.RESP_NAME);
            end
        end

        % =================================================================
        % Mesh helpers — per-segment, no time dim
        % =================================================================

        function [pts, conn, off, typ, modelTags, familyTags] = getFamilyMeshVTK(obj, segIdx, famName)
            cacheKey = obj.makeCacheFieldName(famName);
            if isfield(obj.StaticFamilyMeshCache{segIdx}, cacheKey)
                cached = obj.StaticFamilyMeshCache{segIdx}.(cacheKey);
                pts = cached.pts;  conn = cached.conn;
                off = cached.off;  typ  = cached.typ;
                modelTags  = cached.modelTags;
                familyTags = cached.familyTags;
                return;
            end

            pts = zeros(0,3);  conn = zeros(0,1,'int32');
            off = zeros(0,1,'int32');  typ = zeros(0,1,'uint8');
            modelTags = zeros(0,1);   familyTags = zeros(0,1);

            fam = obj.getFamilies(segIdx);
            if ~isfield(fam, famName), return; end
            S = fam.(famName);
            if ~isstruct(S) || ~isfield(S,'Cells') || isempty(S.Cells), return; end

            cells = obj.getFamilyCells(S);
            if isempty(cells), return; end

            tags = obj.getFamilyTags(S, size(cells,1));
            [cells, keepRows] = obj.remapCellsToCurrentNodes(segIdx, cells);
            if isempty(cells), return; end

            if isfield(S,'CellTypes') && ~isempty(S.CellTypes)
                typ = obj.getFamilyCellTypes(S, keepRows);
            else
                typ = pvdInferVTKCellTypes(cells);
            end

            tags = obj.trimVectorLength(tags, numel(keepRows));
            familyTags = tags(keepRows);

            [allPts, allTags] = obj.getNodeStepData(segIdx);
            usedRows = obj.extractUsedRowsFromCells(cells);
            if isempty(usedRows), return; end

            localMap = zeros(size(allTags));
            localMap(usedRows) = 1:numel(usedRows);

            cells = obj.compactCellsToUsedRows(cells, localMap);
            [conn, off] = pvdVtkRowCellsToConnectivity(cells);
            pts = allPts(usedRows, :);
            modelTags = allTags(usedRows);

            obj.StaticFamilyMeshCache{segIdx}.(cacheKey) = struct( ...
                'pts', pts, 'conn', conn, 'off', off, 'typ', typ, ...
                'modelTags', modelTags, 'familyTags', familyTags);
        end

        function [pts, conn, off, typ] = getRawMeshVTK(obj, segIdx, skipRawLineFamilies)
            if nargin < 3, skipRawLineFamilies = false; end
            [pts, ~] = obj.getNodeStepData(segIdx);
            [conn, off, typ] = obj.collectFamiliesVTK(segIdx, skipRawLineFamilies);
        end

        function [conn, off, typ] = collectFamiliesVTK(obj, segIdx, skipRawLineFamilies)
            if nargin < 3, skipRawLineFamilies = false; end
            cacheKey = 'withLines';
            if skipRawLineFamilies, cacheKey = 'withoutLines'; end
            if isfield(obj.StaticRawMeshCache{segIdx}, cacheKey)
                cached = obj.StaticRawMeshCache{segIdx}.(cacheKey);
                conn = cached.conn;  off = cached.off;  typ = cached.typ;
                return;
            end

            fam = obj.getFamilies(segIdx);
            connParts = {};  offParts = {};  typParts = {};
            offsetBase = int32(0);

            for fn = fieldnames(fam).'
                if skipRawLineFamilies && pvdIsLineFamilyName(fn{1}), continue; end
                S = fam.(fn{1});
                if ~isstruct(S)||~isfield(S,'Cells')||isempty(S.Cells), continue; end

                cells = obj.getFamilyCells(S);
                if isempty(cells), continue; end
                [cells, keepRows] = obj.remapCellsToCurrentNodes(segIdx, cells);
                if isempty(cells), continue; end

                if isfield(S,'CellTypes') && ~isempty(S.CellTypes)
                    ct = obj.getFamilyCellTypes(S, keepRows);
                else
                    ct = pvdInferVTKCellTypes(cells);
                end

                [cL, oL] = pvdVtkRowCellsToConnectivity(cells);
                if skipRawLineFamilies
                    [cL, oL, ct] = pvdFilterLineConnectivity(cL, oL, ct);
                    if isempty(oL), continue; end
                end

                connParts{end+1} = cL; %#ok<AGROW>
                offParts{end+1}  = oL + offsetBase; %#ok<AGROW>
                typParts{end+1}  = ct; %#ok<AGROW>
                if ~isempty(oL), offsetBase = offsetBase + oL(end); end
            end

            if isempty(connParts)
                conn = zeros(0,1,'int32');
                off  = zeros(0,1,'int32');
                typ  = zeros(0,1,'uint8');
            else
                conn = vertcat(connParts{:});
                off  = vertcat(offParts{:});
                typ  = vertcat(typParts{:});
            end
            obj.StaticRawMeshCache{segIdx}.(cacheKey) = struct('conn',conn,'off',off,'typ',typ);
        end

        % =================================================================
        % Node data — per segment, no time dim
        % =================================================================

        function [P, tags] = getNodeStepData(obj, segIdx)
            cache = obj.getStaticNodeCache(segIdx);
            P    = cache.pts;
            tags = cache.tags;
        end

        function [keepMask, rawToClean] = getNodeStepSelection(obj, segIdx)
            cache = obj.getStaticNodeCache(segIdx);
            keepMask   = cache.keepMask;
            rawToClean = cache.rawToClean;
        end

        function cache = getStaticNodeCache(obj, segIdx)
            if obj.StaticNodeCache{segIdx}.ready
                cache = obj.StaticNodeCache{segIdx};
                return;
            end

            P    = obj.getNodeCoordsRaw(segIdx);
            tags = obj.getModelNodeTagsRaw(segIdx, size(P,1));
            keepMask = obj.getExistingNodeStepMask(P, tags);

            cache.ready      = true;
            cache.keepMask   = keepMask;
            cache.rawToClean = zeros(size(keepMask));
            cache.rawToClean(keepMask) = 1:nnz(keepMask);
            cache.pts  = P(keepMask, :);
            tags = obj.trimVectorLength(tags, numel(keepMask));
            cache.tags = tags(keepMask);

            obj.StaticNodeCache{segIdx} = cache;
        end

        function P = getNodeCoordsRaw(obj, segIdx)
            % Per-segment: Coords has no time dimension.
            mi = obj.ModelInfo(segIdx);
            P  = double(mi.Nodes.Coords);
            if isempty(P), P = zeros(0,3); return; end
            if isvector(P), P = reshape(P,1,[]); end
            if size(P,2) < 3,     P(:,end+1:3) = 0;
            elseif size(P,2) > 3, P = P(:,1:3); end
        end

        function keepMask = getExistingNodeStepMask(obj, P, tags)
            if isempty(P), keepMask = false(0,1); return; end
            keepMask = ~all(isnan(P), 2);
            if nargin < 3 || isempty(tags), return; end
            tags = obj.trimVectorLength(tags, numel(keepMask));
            keepMask = keepMask & isfinite(tags);
            unusedTags = obj.getUnusedNodeTags();
            if ~isempty(unusedTags)
                keepMask = keepMask & ~ismember(tags, unusedTags);
            end
        end

        function tags = getModelNodeTagsRaw(obj, segIdx, nRow)
            if nargin < 3, nRow = []; end
            mi = obj.ModelInfo(segIdx);
            if isfield(mi,'Nodes') && isfield(mi.Nodes,'Tags') && ~isempty(mi.Nodes.Tags)
                tags = double(mi.Nodes.Tags(:));
            else
                tags = (1:size(obj.getNodeCoordsRaw(segIdx),1)).';
            end
            if ~isempty(nRow), tags = obj.trimVectorLength(tags, nRow); end
        end

        function tags = getUnusedNodeTags(obj)
            % Use first segment; topology changes across segments are handled
            % by separate cache entries.
            tags = [];
            mi = obj.ModelInfo(1);
            if ~isfield(mi,'Nodes')||~isfield(mi.Nodes,'UnusedTags')||isempty(mi.Nodes.UnusedTags)
                return;
            end
            tags = unique(double(mi.Nodes.UnusedTags(isfinite(mi.Nodes.UnusedTags))));
        end

        function fam = getFamilies(obj, segIdx)
            mi = obj.ModelInfo(segIdx);
            if isfield(mi,'Elements') && isfield(mi.Elements,'Families')
                fam = mi.Elements.Families;
            elseif isfield(mi,'Elements')
                fam = mi.Elements;
            else
                fam = struct();
            end
        end

        % =================================================================
        % Family cell helpers — static per segment (no time dim)
        % =================================================================

        function cells = getFamilyCells(~, family)
            cells = double(family.Cells);
            if isempty(cells), return; end
            if isvector(cells), cells = reshape(cells,1,[]); end
            cells = cells(~all(isnan(cells),2),:);
        end

        function ct = getFamilyCellTypes(obj, family, keepRows)
            ct = uint8(double(family.CellTypes(:)));
            ct = obj.trimVectorLength(ct, numel(keepRows));
            ct = ct(keepRows);
        end

        function tags = getFamilyTags(obj, family, nRow)
            if isfield(family,'Tags') && ~isempty(family.Tags)
                tags = double(family.Tags(:));
            else
                tags = (1:nRow).';
            end
            tags = obj.trimVectorLength(tags, nRow);
        end

        function [cellsOut, keepRows] = remapCellsToCurrentNodes(obj, segIdx, cells)
            cellsOut = zeros(size(cells));
            keepRows = false(size(cells,1),1);
            if isempty(cells), cellsOut = zeros(0,0); return; end
            [~, rawToClean] = obj.getNodeStepSelection(segIdx);
            if isempty(rawToClean)
                cellsOut = zeros(0,size(cells,2)); keepRows = false(0,1); return;
            end
            for i = 1:size(cells,1)
                row = double(cells(i,:));
                row = row(isfinite(row) & row>0);
                if isempty(row), continue; end
                n1 = row(1);
                if isfinite(n1)&&n1>=1&&abs(round(n1)-n1)<1e-12&&numel(row)>=n1+1
                    ids = round(row(2:1+n1));
                    if any(ids<1|ids>numel(rawToClean)), continue; end
                    rr = rawToClean(ids(:));
                    if any(rr<=0), continue; end
                    cellsOut(i,1:1+n1) = [n1, rr(:).'];
                    keepRows(i) = true;
                end
            end
            cellsOut = cellsOut(keepRows,:);
        end

        function rows = extractUsedRowsFromCells(~, cells)
            rows = zeros(0,1);
            if isempty(cells), return; end
            for i = 1:size(cells,1)
                row = double(cells(i,:));
                row = row(isfinite(row)&row>0);
                if isempty(row), continue; end
                n1 = row(1);
                if isfinite(n1)&&n1>=1&&abs(round(n1)-n1)<1e-12&&numel(row)>=n1+1
                    ids = row(2:1+n1);
                else
                    ids = row;
                end
                rows = [rows; ids(:)]; %#ok<AGROW>
            end
            if ~isempty(rows), rows = unique(round(rows),'stable'); end
        end

        function cellsOut = compactCellsToUsedRows(~, cells, localMap)
            cellsOut = cells;
            for i = 1:size(cells,1)
                row = double(cells(i,:));
                row = row(isfinite(row)&row>0);
                if isempty(row), continue; end
                n1 = row(1);
                if isfinite(n1)&&n1>=1&&abs(round(n1)-n1)<1e-12&&numel(row)>=n1+1
                    ids = round(row(2:1+n1));
                    cellsOut(i,2:1+n1) = localMap(ids).';
                end
            end
        end

        % =================================================================
        % Step loop
        % =================================================================

        function runStepLoop(obj, ds, outDir, baseName, binary, buildFn)
            % Collect time values across all segments
            timeVals = obj.collectTimeValues();
            nStep    = numel(timeVals);
            if strcmp(baseName, "")
                setDir = fullfile(outDir, ds.label);
            else
                setDir = fullfile(outDir, [baseName '_' ds.label]);
            end
            vtuDir = fullfile(setDir, 'vtu');
            if ~exist(setDir,'dir'), mkdir(setDir); end
            if ~exist(vtuDir,'dir'), mkdir(vtuDir);  end

            files = strings(nStep,1);
            for g = 0:nStep-1
                k = g + 1;
                [segIdx, localStep] = obj.resolveGlobalStep(g);
                [pts, conn, off, typ, pd, cd] = buildFn(segIdx, localStep);

                fname = sprintf('%s_%s_%06d.vtu', baseName, ds.label, k);
                obj.writeVTU(fullfile(vtuDir, fname), pts, conn, off, typ, pd, cd, binary);
                files(k) = fullfile("vtu", fname);
            end

            if strcmp(baseName, "")
                pvdPath = fullfile(setDir, sprintf('%s.pvd', ds.label));
            else
                pvdPath = fullfile(setDir, sprintf('%s_%s.pvd', baseName, ds.label));
            end
            obj.writePVD(pvdPath, files, timeVals);
            fprintf('%-14s %d steps -> %s\n', [ds.label ':'], nStep, pvdPath);
        end

        function timeVals = collectTimeValues(obj)
            % Concatenate time vectors across all segments.
            timeVals = zeros(obj.nSteps(), 1);
            for s = 1:obj.SegCount
                resp = obj.getNodalRespSeg(s);
                r0   = obj.SegOffsets(s);
                n    = obj.SegStepCounts(s);
                if isstruct(resp) && isfield(resp,'time') && numel(resp.time) >= n
                    timeVals(r0+1:r0+n) = double(resp.time(1:n));
                else
                    timeVals(r0+1:r0+n) = r0 + (0:n-1).';
                end
            end
        end

        % =================================================================
        % Nodal dataset
        % =================================================================

        function writeNodalDataset(obj, ds, outDir, baseName, binary)
            obj.runStepLoop(ds, outDir, baseName, binary, ...
                @(si,ls) obj.buildNodalVTK(ds.resp, si, ls));
        end

        function [pts, conn, off, typ, pd, cd] = buildNodalVTK(obj, resp, segIdx, localStep)
            [pts, conn, off, typ] = obj.getRawMeshVTK(segIdx, false);
            [~, modelTags] = obj.getNodeStepData(segIdx);
            respSeg = obj.getRespSeg(resp, segIdx);
            pd = obj.extractNodalFields(respSeg, localStep, modelTags);
            cd = struct();
        end

        function pd = extractNodalFields(obj, resp, localStep, modelTags)
            pd   = struct();
            nPt  = numel(modelTags);
            skip = {'time','ModelUpdate','nodeTags', ...
                    'interpolatePoints','interpolateDisp','interpolateCells', ...
                    'interpolateCoords'};

            U = obj.getAlignedNodalField(resp, 'disp', localStep, modelTags);
            if ~isempty(U)
                U3 = zeros(nPt,3);
                U3(:,1:min(3,size(U,2))) = U(:,1:min(3,size(U,2)));
                pd.disp = U3;
                if isfield(resp,'disp')
                    pd = obj.appendNodalExpandedFieldData(pd,'disp',U,resp.disp);
                end
            end

            fns = fieldnames(resp);
            for i = 1:numel(fns)
                name = fns{i};
                if ismember(name,skip)||strcmp(name,'disp'), continue; end
                entry = resp.(name);
                D = obj.getAlignedNodalField(resp, name, localStep, modelTags);
                if isempty(D), continue; end
                nCol = size(D,2);
                spatialVecNames = {'vel','accel','reaction', ...
                    'reactionIncInertia','rayleighForces'};
                isSpatialVec = ismember(name, spatialVecNames);
                if isSpatialVec || (nCol>=1 && nCol<=3)
                    V3 = zeros(nPt,3);
                    V3(:,1:min(3,nCol)) = D(:,1:min(3,nCol));
                    pd.(obj.makeFieldName(name)) = V3;
                elseif nCol > 3
                    pd.(obj.makeFieldName(name)) = D;
                end
                pd = obj.appendNodalExpandedFieldData(pd, name, D, entry);
            end
        end

        function U3 = extractRawDisp(obj, resp, localStep, modelTags)
            nPt = numel(modelTags);
            U3  = zeros(nPt,3);
            U   = obj.getAlignedNodalField(resp, 'disp', localStep, modelTags);
            if isempty(U), return; end
            U3(:,1:min(3,size(U,2))) = U(:,1:min(3,size(U,2)));
        end

        % =================================================================
        % Interpolated dataset
        % =================================================================

        function writeInterpolatedDataset(obj, ds, outDir, baseName, binary)
            obj.runStepLoop(ds, outDir, baseName, binary, ...
                @(si,ls) obj.buildInterpolatedVTK(ds.resp, si, ls));
        end

        function [pts, conn, off, typ, pd, cd] = buildInterpolatedVTK(obj, resp, segIdx, localStep)
            [rawPts, rawConn, rawOff, rawTyp] = obj.getRawMeshVTK(segIdx, obj.HasInterpResp);
            [~, modelTags] = obj.getNodeStepData(segIdx);
            nRawPt   = size(rawPts,1);
            nRawCell = numel(rawOff);

            respSeg = obj.getRespSeg(resp, segIdx);
            [intPts, intDisp, intCells] = pvdGetInterpSlice(respSeg, localStep);
            if isempty(intPts), intPts=zeros(0,3); intDisp=zeros(0,3); intCells=zeros(0,2); end
            nIntPt = size(intPts,1);

            pd.disp = obj.extractRawDisp(respSeg, localStep, modelTags);
            if isfield(respSeg,'disp')
                rawDisp = obj.getAlignedNodalField(respSeg,'disp',localStep,modelTags);
                if ~isempty(rawDisp)
                    pd = obj.appendNodalExpandedFieldData(pd,'disp',rawDisp,respSeg.disp);
                end
            end

            if nIntPt==0 || isempty(intCells)
                pts=rawPts; conn=rawConn; off=rawOff; typ=rawTyp; cd=struct(); return;
            end

            nSeg = size(intCells,1);
            lineConn = int32(intCells.' - 1 + nRawPt);  lineConn = lineConn(:);
            lineOff  = int32((1:nSeg).' * 2);
            if nRawCell>0, lineOff = lineOff + rawOff(end); end

            pts  = [rawPts; intPts];
            conn = [rawConn; lineConn];
            off  = [rawOff;  lineOff];
            typ  = [rawTyp;  repmat(uint8(3),nSeg,1)];

            intDisp3 = zeros(nIntPt,3);
            intDisp3(:,1:min(3,size(intDisp,2))) = intDisp(:,1:min(3,size(intDisp,2)));
            pd.disp = [pd.disp; intDisp3];
            cd = struct();
        end

        % =================================================================
        % Element dataset
        % =================================================================

        function writeElementDataset(obj, ds, outDir, baseName, binary)
            obj.runStepLoop(ds, outDir, baseName, binary, ...
                @(si,ls) obj.buildElementVTK(ds, si, ls));
        end

        function [pts, conn, off, typ, pd, cd] = buildElementVTK(obj, ds, segIdx, localStep)
            [pts, conn, off, typ, modelTags, familyTags] = obj.getFamilyMeshVTK(segIdx, ds.famName);
            nRespCell = numel(off);

            [pts, conn, off, typ, modelTags, nContextCell] = obj.mergeContextFamiliesIntoMesh( ...
                ds.famName, segIdx, pts, conn, off, typ, modelTags);

            respSeg = obj.getRespSeg(ds.resp, segIdx);
            pd = obj.buildElementPointData(respSeg, localStep, modelTags);
            cd = obj.buildElementCellData(respSeg, localStep, familyTags, nRespCell);
            if nContextCell > 0
                cd = obj.appendEmptyCellData(cd, nContextCell);
            end

            if obj.HasInterpResp
                nodalSeg = obj.getNodalRespSeg(segIdx);
                [pts, conn, off, typ, pd, cd] = obj.mergeInterpolatedIntoDataset( ...
                    pts, conn, off, typ, pd, cd, nodalSeg, localStep);
            end
        end

        function [pts, conn, off, typ, modelTags, nAddedCell] = mergeContextFamiliesIntoMesh(obj, targetFamName, segIdx, pts, conn, off, typ, modelTags)
            nAddedCell = 0;
            fam = obj.getFamilies(segIdx);
            for fn = fieldnames(fam).'
                famName = fn{1};
                if strcmpi(famName, targetFamName), continue; end
                if obj.HasInterpResp && pvdIsLineFamilyName(famName), continue; end

                [pts2, conn2, off2, typ2, modelTags2] = obj.getFamilyMeshVTK(segIdx, famName);
                if obj.HasInterpResp
                    [conn2, off2, typ2] = pvdFilterLineConnectivity(conn2, off2, typ2);
                end
                if isempty(off2)||isempty(modelTags2), continue; end

                [pts, modelTags, localToMerged] = obj.mergePointsByTags(pts, modelTags, pts2, modelTags2);
                remappedConn = int32(localToMerged(double(conn2)+1)-1);
                offsetBase = int32(0);
                if ~isempty(off), offsetBase = off(end); end
                conn = [conn; remappedConn(:)]; %#ok<AGROW>
                off  = [off;  off2 + offsetBase]; %#ok<AGROW>
                typ  = [typ;  typ2(:)]; %#ok<AGROW>
                nAddedCell = nAddedCell + numel(off2);
            end
        end

        function [pts, modelTags, localToMerged] = mergePointsByTags(~, pts, modelTags, pts2, modelTags2)
            pts=double(pts); pts2=double(pts2);
            modelTags=double(modelTags(:)); modelTags2=double(modelTags2(:));
            localToMerged = zeros(numel(modelTags2),1,'int32');
            if isempty(modelTags2), return; end
            [tf, loc] = ismember(modelTags2, modelTags);
            localToMerged(tf) = int32(loc(tf));
            newMask = ~tf;
            if any(newMask)
                startIdx = numel(modelTags);
                newIdx   = int32((startIdx+1):(startIdx+nnz(newMask))).';
                pts        = [pts; pts2(newMask,:)];
                modelTags  = [modelTags; modelTags2(newMask)];
                localToMerged(newMask) = newIdx;
            end
        end

        function pd = buildElementPointData(obj, resp, localStep, modelTags)
            pd = struct();
            if isempty(modelTags), return; end
            if isstruct(obj.NodalResp) && ~isempty(fieldnames(obj.NodalResp(1)))
                % Use first segment's nodal resp as fallback; caller passes correct seg resp
                fullDisp  = obj.getAlignedNodalField(resp, 'disp', localStep, modelTags);
                dispField = obj.extractRawDisp(resp, localStep, modelTags);
                if ~isempty(dispField)
                    pd.disp = dispField;
                    if ~isempty(fullDisp) && isfield(resp,'disp')
                        pd = obj.appendNodalExpandedFieldData(pd,'disp',fullDisp,resp.disp);
                    end
                end
            end
            fns = fieldnames(resp);
            for i = 1:numel(fns)
                name = fns{i};
                if ~obj.isRespDataField(resp,name)||~obj.isNodeBasedRespType(name), continue; end
                entry = resp.(name);
                D = obj.getAlignedNodalField(resp, name, localStep, modelTags);
                if isempty(D), continue; end
                pd = obj.appendNodalExpandedFieldData(pd, name, D, entry);
            end
        end

        function cd = buildElementCellData(obj, resp, localStep, familyTags, nCell)
            cd = struct();
            if nCell<=0, return; end
            fns = fieldnames(resp);
            for i = 1:numel(fns)
                name = fns{i};
                if ~obj.isRespDataField(resp,name)||obj.isNodeBasedRespType(name), continue; end
                entry = resp.(name);
                [fieldNames, fieldArrays] = obj.buildAggregatedElementFieldData(name, entry, localStep);
                if isempty(fieldNames), continue; end
                for j = 1:numel(fieldNames)
                    mapped = obj.mapElementDataToFamilyCells(resp, fieldArrays{j}, familyTags, nCell, localStep);
                    cd.(fieldNames{j}) = mapped;
                end
            end
        end

        function [pts, conn, off, typ, pd, cd] = mergeInterpolatedIntoDataset(obj, pts, conn, off, typ, pd, cd, respSeg, localStep)
            [intPts, intDisp, intCells] = pvdGetInterpSlice(respSeg, localStep);
            if isempty(intPts)||isempty(intCells), return; end
            nRawPt   = size(pts,1);
            nRawCell = numel(off);
            nSeg     = size(intCells,1);
            lineConn = int32(intCells.'-1+nRawPt);  lineConn=lineConn(:);
            lineOff  = int32((1:nSeg).'*2);
            if nRawCell>0, lineOff=lineOff+off(end); end
            pts  = [pts;intPts];
            conn = [conn;lineConn];
            off  = [off; lineOff];
            typ  = [typ; repmat(uint8(3),nSeg,1)];
            pd   = obj.appendInterpolatedPointData(pd, nRawPt, intDisp);
            cd   = obj.appendEmptyCellData(cd, nSeg);
        end

        function pd = appendInterpolatedPointData(~, pd, nRawPt, intDisp)
            if ~isfield(pd,'disp'), pd.disp = zeros(nRawPt,3); end
            if size(pd.disp,2)<3, pd.disp(:,end+1:3)=0;
            elseif size(pd.disp,2)>3, pd.disp=pd.disp(:,1:3); end
            dispExtra = zeros(size(intDisp,1),3);
            dispExtra(:,1:min(3,size(intDisp,2))) = intDisp(:,1:min(3,size(intDisp,2)));
            for fn = fieldnames(pd).'
                name = fn{1};
                A = pd.(name);
                if isvector(A), A=A(:); end
                if strcmp(name,'disp')
                    pd.(name) = [A; dispExtra];
                else
                    pd.(name) = [A; NaN(size(intDisp,1),size(A,2))];
                end
            end
        end

        function cd = appendEmptyCellData(~, cd, nExtraCell)
            for fn = fieldnames(cd).'
                name = fn{1};
                A = cd.(name); if isvector(A), A=A(:); end
                cd.(name) = [A; NaN(nExtraCell, size(A,2))];
            end
        end

        % =================================================================
        % Segment resp accessor
        % =================================================================

        function respSeg = getRespSeg(~, resp, segIdx)
            % Get the correct segment from a scalar or struct-array resp.
            if numel(resp) >= segIdx
                respSeg = resp(segIdx);
            else
                respSeg = resp(1);
            end
        end

        % =================================================================
        % Nodal field extraction — localStep-based (was stepIdx)
        % =================================================================

        function D = getAlignedNodalField(obj, resp, fieldName, localStep, modelTags)
            D = [];
            if ~isfield(resp, fieldName), return; end
            entry = resp.(fieldName);
            respTags = obj.getRespNodeTags(resp, entry, localStep);
            entityCount = numel(modelTags);
            if ~isempty(respTags), entityCount = numel(respTags); end

            if isstruct(entry) && isfield(entry,'data')
                if isempty(entry.data)||~isnumeric(entry.data), return; end
                D = obj.extractStepFieldMatrix(entry.data, localStep, entityCount, entry);
            elseif isstruct(entry) && ~isfield(entry,'data')
                % Layout C: re-order to canonical DOF sequence to match
                % PlotNodalResp (MATLAB's fieldnames() sorts alphabetically,
                % so rx/ry/rz would come before ux/uy/uz without reordering).
                canonical = {'ux','uy','uz','rx','ry','rz'};
                present   = fieldnames(entry).';
                % Canonical fields first, then any extras
                ordered = [canonical(ismember(canonical, present)), ...
                           present(~ismember(present, canonical))];
                cols = {};
                for fn = ordered
                    fn_ = fn{1};
                    if ~isfield(entry, fn_), continue; end
                    arr = entry.(fn_);
                    if ~isnumeric(arr)||isempty(arr), continue; end
                    arr = double(arr);
                    si  = min(localStep, size(arr,1));
                    cols{end+1} = double(arr(si,:)).'; %#ok<AGROW>
                end
                if isempty(cols), return; end
                D = horzcat(cols{:});
            elseif isnumeric(entry)
                if isempty(entry), return; end
                D = obj.extractStepFieldMatrix(double(entry), localStep, entityCount, struct());
            else
                return;
            end

            if isempty(D), return; end
            D = obj.mapRespDataToModelTags(modelTags, D, respTags, localStep);
        end

        function tags = getRespNodeTags(~, resp, entry, localStep)
            tags = [];
            if isfield(resp,'nodeTags')&&~isempty(resp.nodeTags)
                raw = resp.nodeTags;
            elseif isstruct(entry)&&isfield(entry,'nodeTags')&&~isempty(entry.nodeTags)
                raw = entry.nodeTags;
            else, return; end
            raw = double(raw);
            if isvector(raw), tags = raw(:);
            elseif ismatrix(raw), tags = raw(min(localStep,size(raw,1)),:).';
            else, tags = squeeze(raw(min(localStep,size(raw,1)),:,:)); tags=tags(:); end
        end

        function out = mapRespDataToModelTags(obj, modelTags, respData, respTags, localStep)
            nRow = numel(modelTags);
            if isempty(respData), out=[]; return; end
            respData = double(respData);
            if isvector(respData), respData=respData(:); end
            out = NaN(nRow, size(respData,2));

            if ~isempty(respTags)
                [respData, respTags] = obj.normalizeRespNodeData(respData, respTags);
                if isempty(respData)||isempty(respTags), return; end
                [tf, loc] = ismember(double(modelTags(:)), respTags(:));
                valid = tf & loc>0 & loc<=size(respData,1);
                out(valid,:) = respData(loc(valid),:);
                return;
            end

            % No tags — use segIdx=1 as reference for keepMask
            % (caller already passes model-filtered tags so nRow == size(Pclean))
            nCopy = min(nRow, size(respData,1));
            out(1:nCopy,:) = respData(1:nCopy,:);
        end

        function [respData, respTags] = normalizeRespNodeData(~, respData, respTags)
            respData=double(respData); if isvector(respData), respData=respData(:); end
            if isempty(respTags), return; end
            respTags=double(respTags(:)); valid=isfinite(respTags);
            nValid=nnz(valid); nRow=size(respData,1);
            if nRow==numel(respTags), respData=respData(valid,:); respTags=respTags(valid);
            elseif nRow==nValid, respTags=respTags(valid);
            else
                respTags=respTags(valid); nUse=min(numel(respTags),nRow);
                respTags=respTags(1:nUse); respData=respData(1:nUse,:);
            end
            if isempty(respTags), respData=zeros(0,size(respData,2)); end
        end

        % =================================================================
        % Element field extraction — localStep-based
        % =================================================================

        function [fieldNames, fieldArrays] = buildAggregatedElementFieldData(obj, baseName, entry, localStep)
            fieldNames  = {};
            fieldArrays = {};

            if isstruct(entry) && ~isfield(entry,'data')
                statNames = {'min','mean','max'};
                for fn = fieldnames(entry).'
                    dofName = fn{1};
                    arr = entry.(dofName);
                    if ~isnumeric(arr)||isempty(arr), continue; end
                    arr=double(arr); si=min(localStep,size(arr,1)); nd=ndims(arr);
                    if nd==2
                        col=double(arr(si,:)).';
                        fieldNames{end+1} = obj.makeFieldName(sprintf('%s_%s',baseName,dofName)); %#ok<AGROW>
                        fieldArrays{end+1} = col(:); %#ok<AGROW>
                    elseif nd==3
                        slice=reshape(arr(si,:,:),size(arr,2),size(arr,3));
                        if size(slice,2)==1
                            fieldNames{end+1} = obj.makeFieldName(sprintf('%s_%s',baseName,dofName)); %#ok<AGROW>
                            fieldArrays{end+1} = slice(:,1); %#ok<AGROW>
                        else
                            reduceFns={@(x)min(x,[],2,'omitnan'),@(x)mean(x,2,'omitnan'),@(x)max(x,[],2,'omitnan')};
                            for s=1:numel(statNames)
                                fName=obj.makeFieldName(sprintf('%s_%s_%s',baseName,dofName,statNames{s}));
                                fieldNames{end+1}=fName; %#ok<AGROW>
                                fieldArrays{end+1}=reduceFns{s}(slice); %#ok<AGROW>
                            end
                        end
                    end
                end
                return;
            end

            if ~isstruct(entry)||~isfield(entry,'data')||isempty(entry.data)||~isnumeric(entry.data)
                return;
            end

            slice = obj.extractStepFieldSlice(entry.data, localStep);
            if isempty(slice), return; end
            [needAgg, hasCompAxis, nComp] = obj.getElementAggregationInfo(slice, entry);
            if ~needAgg
                D = obj.extractStepFieldMatrix(entry.data, localStep, [], entry);
                if isempty(D), return; end
                [fieldNames, fieldArrays] = obj.expandFieldArrays(baseName, D, entry);
                return;
            end

            statNames = {'min','mean','max'};
            compLabels = obj.getAggregateComponentLabels(entry, nComp);
            statValues = obj.aggregateElementSlice(slice, hasCompAxis);
            for i = 1:numel(statNames)
                values = statValues{i};
                for j = 1:nComp
                    if nComp==1, rawName=sprintf('%s_%s',baseName,statNames{i});
                    else, rawName=sprintf('%s_%s_%s',baseName,compLabels{j},statNames{i}); end
                    fieldNames{end+1}  = obj.makeFieldName(rawName); %#ok<AGROW>
                    fieldArrays{end+1} = values(:,j); %#ok<AGROW>
                end
            end
        end

        function out = mapElementDataToFamilyCells(obj, resp, respData, familyTags, nCell, localStep)
            out = NaN(nCell, size(respData,2));
            if isempty(respData), return; end
            if ~isempty(familyTags)&&isfield(resp,'eleTags')&&~isempty(resp.eleTags)
                respTags = obj.getRespEleTags(resp, localStep);
                [respData, respTags] = obj.normalizeRespElementData(respData, respTags);
                respRows = obj.getRespEleRowsAtStep(respTags, familyTags);
                valid = respRows>0 & respRows<=size(respData,1);
                out(valid,:) = respData(respRows(valid),:);
                return;
            end
            nCopy = min(nCell, size(respData,1));
            out(1:nCopy,:) = respData(1:nCopy,:);
        end

        function tags = getRespEleTags(obj, resp, localStep)
            tags = [];
            if ~isfield(resp,'eleTags')||isempty(resp.eleTags), return; end
            tags = obj.readStepVectorData(resp.eleTags, localStep);
            tags = double(tags(isfinite(tags(:))));
        end

        function rows = getRespEleRowsAtStep(~, respTags, familyTags)
            rows = [];
            if isempty(familyTags)||isempty(respTags), return; end
            [tf, loc] = ismember(double(familyTags(:)), double(respTags(:)));
            rows = zeros(numel(familyTags),1);
            rows(tf) = loc(tf);
        end

        function [respData, respTags] = normalizeRespElementData(~, respData, respTags)
            respData=double(respData); if isvector(respData), respData=respData(:); end
            if isempty(respTags), return; end
            respTags=double(respTags(:)); valid=isfinite(respTags);
            nValid=nnz(valid); nRow=size(respData,1);
            if nRow==numel(respTags), respData=respData(valid,:); respTags=respTags(valid);
            elseif nRow==nValid, respTags=respTags(valid);
            else, respTags=respTags(valid); nUse=min(numel(respTags),nRow);
                  respTags=respTags(1:nUse); respData=respData(1:nUse,:); end
            if isempty(respTags), respData=zeros(0,size(respData,2)); end
        end

        % =================================================================
        % Shared field helpers (unchanged from doc5)
        % =================================================================

        function outStruct = appendNodalExpandedFieldData(obj, outStruct, baseName, values, entry)
            [fieldNames, fieldArrays] = obj.expandFieldArrays(baseName, values, entry);
            startIdx = 1;
            if obj.isSpatialNodalVectorField(baseName)
                startIdx = min(3,numel(fieldNames)) + 1;
            end
            for i = startIdx:numel(fieldNames)
                outStruct.(fieldNames{i}) = fieldArrays{i};
            end
        end

        function [fieldNames, fieldArrays] = expandFieldArrays(obj, baseName, values, entry)
            fieldNames={};  fieldArrays={};
            if isempty(values), return; end
            if strcmp(baseName,'disp')
                fieldNames = {obj.makeFieldName(baseName)};
                fieldArrays = {values};  return;
            end
            dofs = obj.getEntryDofs(entry);
            if numel(dofs)<=1 && size(values,2)==1
                fieldNames = {obj.makeFieldName(baseName)};
                fieldArrays = {values(:,1)};  return;
            end
            compNames = obj.getExpandedComponentNames(baseName, entry, size(values,2));
            if numel(compNames) ~= size(values,2)
                compNames = arrayfun(@(i) obj.makeFieldName(sprintf('%s_%d',baseName,i)), ...
                    1:size(values,2), 'UniformOutput', false);
            end
            for i = 1:size(values,2)
                fieldNames{end+1}  = compNames{i}; %#ok<AGROW>
                fieldArrays{end+1} = values(:,i); %#ok<AGROW>
            end
        end

        function compNames = getExpandedComponentNames(obj, baseName, entry, nComp)
            compNames = {};
            if ~isstruct(entry), return; end
            if ~isfield(entry,'data')
                dofs = obj.getEntryDofs(entry);
                if numel(dofs)==nComp
                    compNames = cellfun(@(d) obj.makeFieldName(sprintf('%s_%s',baseName,char(string(d)))), ...
                        dofs, 'UniformOutput', false);
                end
                return;
            end
            dofs = obj.getEntryDofs(entry);
            dimNames = {};
            if isfield(entry,'dimNames')&&~isempty(entry.dimNames), dimNames=entry.dimNames; end
            if ~isfield(entry,'data')||isempty(entry.data)||~isnumeric(entry.data), return; end
            rawSize = size(double(entry.data));
            tailDims = rawSize(3:end);
            if isempty(tailDims)||all(tailDims==1)
                compNames = {obj.makeFieldName(baseName)}; return;
            end
            if prod(tailDims) ~= nComp, return; end
            tailDimNames = {};
            if ~isempty(dimNames)&&numel(dimNames)>=3
                tailDimNames = dimNames(3:min(numel(dimNames),2+numel(tailDims)));
            end
            for i = numel(tailDimNames)+1:numel(tailDims)
                tailDimNames{i} = sprintf('dim%d',i);
            end
            useDofs = ~isempty(dofs)&&numel(dofs)==tailDims(end);
            idxCell = cell(1,numel(tailDims));
            compNames = cell(1,nComp);
            for linearIdx = 1:nComp
                if numel(tailDims)==1, idxCell{1}=linearIdx;
                else, [idxCell{:}] = ind2sub(tailDims,linearIdx); end
                parts = {char(baseName)};
                for dimIdx = 1:numel(tailDims)
                    if useDofs&&dimIdx==numel(tailDims)
                        parts{end+1}=char(string(dofs{idxCell{dimIdx}})); %#ok<AGROW>
                    else
                        dimLabel = obj.normalizeDimLabel(tailDimNames{dimIdx});
                        parts{end+1}=sprintf('%s%d',dimLabel,idxCell{dimIdx}); %#ok<AGROW>
                    end
                end
                compNames{linearIdx} = obj.makeFieldName(strjoin(parts,'_'));
            end
        end

        function tf = isSpatialNodalVectorField(~, baseName)
            tf = ismember(baseName,{'disp','vel','accel','reaction','reactionIncInertia','rayleighForces'});
        end

        function dofs = getEntryDofs(~, entry)
            dofs = {};
            if ~isstruct(entry), return; end
            if isfield(entry,'dofs')
                dofs = localNormalizeDofs(entry.dofs); return;
            end
            if ~isfield(entry,'data')
                % Layout C: re-order to canonical sequence so DOF labels
                % match the column order produced by getAlignedNodalField.
                canonical = {'ux','uy','uz','rx','ry','rz'};
                present   = {};
                for fn = fieldnames(entry).'
                    if isnumeric(entry.(fn{1})), present{end+1} = fn{1}; end %#ok<AGROW>
                end
                dofs = [canonical(ismember(canonical, present)), ...
                        present(~ismember(present, canonical))];
            end
        end

        function labels = getAggregateComponentLabels(~, entry, nComp)
            dofs = {};
            if isstruct(entry)&&isfield(entry,'dofs')
                dofs = localNormalizeDofs(entry.dofs);
            end
            if numel(dofs)>=nComp
                labels = cellfun(@(d) char(string(d)), dofs(1:nComp), 'UniformOutput', false);
            else
                labels = arrayfun(@(i) sprintf('%d',i), 1:nComp, 'UniformOutput', false);
            end
        end

        function slice = extractStepFieldSlice(~, raw, localStep)
            slice = [];
            if isempty(raw)||~isnumeric(raw), return; end
            raw = double(raw);
            if isvector(raw), slice=raw(:); return; end
            if ismatrix(raw)
                si=min(localStep,size(raw,1));
                slice=reshape(raw(si,:),[size(raw,2),1]); return;
            end
            sz=size(raw); si=min(localStep,sz(1));
            idx=repmat({':'},1,ndims(raw)); idx{1}=si;
            slice=double(raw(idx{:}));
            tailSize=sz(2:end);
            if isempty(tailSize), slice=slice(:);
            else, slice=reshape(slice,tailSize); end
        end

        function D = extractStepFieldMatrix(~, raw, localStep, entityCount, entry)
            D=[];
            if isempty(raw)||~isnumeric(raw), return; end
            raw=double(raw);
            if isvector(raw), D=raw(:); return; end
            dimNames={};  dofs={};
            if isstruct(entry)
                if isfield(entry,'dimNames')&&~isempty(entry.dimNames), dimNames=entry.dimNames; end
                if isfield(entry,'dofs')&&~isempty(entry.dofs), dofs=entry.dofs; end
            end
            if ismatrix(raw)
                hasTimeDim=~isempty(dimNames)&&strcmpi(char(string(dimNames{1})),'time');
                hasSingleDof=~isempty(dofs)&&numel(dofs)<=1;
                isTimeEntityScalar=false;
                if hasTimeDim, isTimeEntityScalar=true;
                elseif hasSingleDof&&size(raw,2)>1, isTimeEntityScalar=true;
                elseif ~isempty(entityCount)&&size(raw,2)==entityCount, isTimeEntityScalar=true; end
                if isTimeEntityScalar
                    si=min(localStep,size(raw,1));
                    D=reshape(raw(si,:),[size(raw,2),1]);
                else, D=raw; end
                return;
            end
            sz=size(raw); si=min(localStep,sz(1));
            idx=repmat({':'},1,ndims(raw)); idx{1}=si;
            slice=raw(idx{:});
            D=reshape(double(slice),[sz(2),prod(sz(3:end))]);
        end

        function [needAgg, hasCompAxis, nComp] = getElementAggregationInfo(~, slice, entry)
            sz=size(slice); if isvector(slice), sz=[numel(slice),1]; end
            dofs={};
            if isstruct(entry)&&isfield(entry,'dofs'), dofs=localNormalizeDofs(entry.dofs); end
            hasCompAxis=false; nComp=1;
            if ~isempty(dofs)&&sz(end)==numel(dofs), hasCompAxis=true; nComp=sz(end);
            elseif numel(sz)>=2&&sz(end)>1&&isempty(dofs), nComp=sz(end); end
            aggDims=sz(2:end);
            if hasCompAxis&&numel(aggDims)>=1, aggDims=aggDims(1:end-1); end
            needAgg=~isempty(aggDims);
        end

        function statValues = aggregateElementSlice(~, slice, hasCompAxis)
            if isvector(slice), slice=slice(:); end
            sz=size(slice); nEle=sz(1);
            if hasCompAxis, nComp=sz(end); aggCount=prod(sz(2:end-1)); else, nComp=1; aggCount=prod(sz(2:end)); end
            work=reshape(slice,[nEle,aggCount,nComp]);
            valid=~isnan(work); count=sum(valid,2);
            minWork=work; minWork(~valid)=inf;
            maxWork=work; maxWork(~valid)=-inf;
            sumWork=work; sumWork(~valid)=0;
            minVals=squeeze(min(minWork,[],2));
            maxVals=squeeze(max(maxWork,[],2));
            meanVals=squeeze(sum(sumWork,2)./max(count,1));
            emptyMask=squeeze(count==0);
            minVals(emptyMask)=NaN; meanVals(emptyMask)=NaN; maxVals(emptyMask)=NaN;
            if nComp==1
                minVals=minVals(:); meanVals=meanVals(:); maxVals=maxVals(:);
            else
                minVals=reshape(minVals,[nEle,nComp]); meanVals=reshape(meanVals,[nEle,nComp]); maxVals=reshape(maxVals,[nEle,nComp]);
            end
            statValues={minVals,meanVals,maxVals};
        end

        function tf = isRespDataField(~, resp, fieldName)
            tf=false;
            skip={'time','ModelUpdate','nodeTags','eleTags','interpolatePoints','interpolateDisp','interpolateCells','interpolateCoords'};
            if ismember(fieldName,skip)||~isfield(resp,fieldName), return; end
            entry=resp.(fieldName);
            if isstruct(entry)&&isfield(entry,'data')&&~isempty(entry.data)&&isnumeric(entry.data), tf=true; return; end
            if isstruct(entry)&&~isfield(entry,'data')
                for fn=fieldnames(entry).'
                    if isnumeric(entry.(fn{1}))&&~isempty(entry.(fn{1})), tf=true; return; end
                end
            end
            if isnumeric(entry)&&~isempty(entry), tf=true; end
        end

        function tf = isNodeBasedRespType(~, fieldName)
            tf = ~isempty(regexpi(fieldName,'AtNode','once'));
        end

        function values = readStepVectorData(~, raw, localStep)
            raw=double(raw);
            if isvector(raw), values=raw(:);
            elseif ismatrix(raw), values=raw(min(localStep,size(raw,1)),:).';
            else, values=squeeze(raw(min(localStep,size(raw,1)),:,:)); values=values(:); end
        end

        function label = normalizeDimLabel(~, label)
            label=char(string(label));
            label=regexprep(label,'[^A-Za-z0-9]+','');
            if isempty(label), label='dim'; end
        end

        function name = makeFieldName(~, rawName)
            name=char(string(rawName));
            name=regexprep(name,'[^A-Za-z0-9_]+','_');
            name=regexprep(name,'_+','_');
            name=regexprep(name,'^_+|_+$','');
            if isempty(name), name='field'; end
            if ~isletter(name(1)), name=['f_' name]; end
        end

        function name = makeCacheFieldName(~, rawName)
            name=char(string(rawName));
            name=regexprep(name,'[^A-Za-z0-9_]+','_');
            if isempty(name)||~isletter(name(1)), name=['f_' name]; end
        end

        function values = trimVectorLength(~, values, nRow)
            values=values(:);
            if numel(values)<nRow, values(end+1:nRow,1)=NaN;
            elseif numel(values)>nRow, values=values(1:nRow); end
        end

    end

    % =====================================================================
    % VTU / PVD I/O (unchanged from doc5)
    % =====================================================================
    methods (Access = private)

        function writeVTU(~, filePath, pts, conn, off, typ, pd, cd, binary)
            pdNames=fieldnames(pd); cdNames=fieldnames(cd);
            arrays={};
            for i=1:numel(pdNames), A=pd.(pdNames{i}); arrays{end+1}={A,pdNames{i},pvdMatlabClassToVTK(A)}; end %#ok<AGROW>
            for i=1:numel(cdNames), A=cd.(cdNames{i}); arrays{end+1}={A,cdNames{i},pvdMatlabClassToVTK(A)}; end %#ok<AGROW>
            arrays{end+1}={pts,'Points','Float64'};
            arrays{end+1}={int32(conn(:)),'connectivity','Int32'};
            arrays{end+1}={int32(off(:)),'offsets','Int32'};
            arrays{end+1}={uint8(typ(:)),'types','UInt8'};
            nPt=size(pts,1); nCell=numel(off);

            if binary
                byteOffsets=zeros(numel(arrays),1,'uint64'); cursor=uint64(0);
                for i=1:numel(arrays)
                    byteOffsets(i)=cursor; A=arrays{i}{1};
                    A=pvdToRawArray(A,arrays{i}{3});
                    cursor=cursor+uint64(4)+uint64(numel(A)*pvdByteSize(arrays{i}{3}));
                end
                fid=fopen(filePath,'w');
                if fid<0, error('PVDWriter:FileOpenFailed','Cannot open %s.',filePath); end
                cleanup=onCleanup(@()fclose(fid)); %#ok<NASGU>
                fprintf(fid,'<?xml version="1.0"?>\n<VTKFile type="UnstructuredGrid" version="0.1" byte_order="LittleEndian">\n  <UnstructuredGrid>\n    <Piece NumberOfPoints="%d" NumberOfCells="%d">\n',nPt,nCell);
                ai=1;
                fprintf(fid,'      <PointData>\n');
                for i=1:numel(pdNames), pvdWriteArrayHeader(fid,arrays{ai}{2},arrays{ai}{3},pvdNumComponents(arrays{ai}{1}),byteOffsets(ai)); ai=ai+1; end
                fprintf(fid,'      </PointData>\n      <CellData>\n');
                for i=1:numel(cdNames), pvdWriteArrayHeader(fid,arrays{ai}{2},arrays{ai}{3},pvdNumComponents(arrays{ai}{1}),byteOffsets(ai)); ai=ai+1; end
                fprintf(fid,'      </CellData>\n      <Points>\n');
                pvdWriteArrayHeader(fid,'Points','Float64',3,byteOffsets(ai)); ai=ai+1;
                fprintf(fid,'      </Points>\n      <Cells>\n');
                pvdWriteArrayHeader(fid,'connectivity','Int32',1,byteOffsets(ai)); ai=ai+1;
                pvdWriteArrayHeader(fid,'offsets','Int32',1,byteOffsets(ai)); ai=ai+1;
                pvdWriteArrayHeader(fid,'types','UInt8',1,byteOffsets(ai));
                fprintf(fid,'      </Cells>\n    </Piece>\n  </UnstructuredGrid>\n  <AppendedData encoding="raw">\n_');
                fclose(fid); fid=fopen(filePath,'ab'); cleanup=onCleanup(@()fclose(fid)); %#ok<NASGU>
                for i=1:numel(arrays)
                    raw=pvdToRawArray(arrays{i}{1},arrays{i}{3});
                    nBytes=uint32(numel(raw)*pvdByteSize(arrays{i}{3}));
                    fwrite(fid,nBytes,'uint32',0,'l');
                    fwrite(fid,raw,pvdMatlabBinaryClass(arrays{i}{3}),0,'l');
                end
                fclose(fid); fid=fopen(filePath,'a'); cleanup=onCleanup(@()fclose(fid)); %#ok<NASGU>
                fprintf(fid,'\n  </AppendedData>\n</VTKFile>\n');
            else
                fid=fopen(filePath,'w');
                if fid<0, error('PVDWriter:FileOpenFailed','Cannot open %s.',filePath); end
                cleanup=onCleanup(@()fclose(fid)); %#ok<NASGU>
                fprintf(fid,'<?xml version="1.0"?>\n<VTKFile type="UnstructuredGrid" version="0.1" byte_order="LittleEndian">\n  <UnstructuredGrid>\n    <Piece NumberOfPoints="%d" NumberOfCells="%d">\n',nPt,nCell);
                fprintf(fid,'      <PointData>\n'); pvdWriteDataArrayBlock(fid,pd); fprintf(fid,'      </PointData>\n');
                fprintf(fid,'      <CellData>\n');  pvdWriteDataArrayBlock(fid,cd); fprintf(fid,'      </CellData>\n');
                fprintf(fid,'      <Points>\n'); pvdWriteArrayAscii(fid,pts,'Points','Float64'); fprintf(fid,'      </Points>\n');
                fprintf(fid,'      <Cells>\n');
                pvdWriteArrayAscii(fid,int32(conn(:)),'connectivity','Int32');
                pvdWriteArrayAscii(fid,int32(off(:)),'offsets','Int32');
                pvdWriteArrayAscii(fid,uint8(typ(:)),'types','UInt8');
                fprintf(fid,'      </Cells>\n    </Piece>\n  </UnstructuredGrid>\n</VTKFile>\n');
            end
        end

        function writePVD(~, filePath, fileNames, timeVals)
            fid=fopen(filePath,'w');
            if fid<0, error('PVDWriter:FileOpenFailed','Cannot open %s.',filePath); end
            cleanup=onCleanup(@()fclose(fid)); %#ok<NASGU>
            fprintf(fid,'<?xml version="1.0"?>\n<VTKFile type="Collection" version="0.1" byte_order="LittleEndian">\n  <Collection>\n');
            for i=1:numel(fileNames)
                fprintf(fid,'    <DataSet timestep="%.16g" group="" part="0" file="%s"/>\n',timeVals(i),fileNames(i));
            end
            fprintf(fid,'  </Collection>\n</VTKFile>\n');
        end

    end
end


% =========================================================================
% Package-level helper functions (unchanged from doc5)
% =========================================================================

function pvdWriteDataArrayBlock(fid, S)
fns = fieldnames(S);
for i = 1:numel(fns)
    A = S.(fns{i});
    pvdWriteArrayAscii(fid, A, fns{i}, pvdMatlabClassToVTK(A));
end
end

function pvdWriteArrayAscii(fid, A, name, vtkType)
if strcmp(vtkType,'Int32'), A=int32(A);
elseif strcmp(vtkType,'UInt8'), A=uint8(A);
else, A=double(A); end
if isvector(A), A=A(:); nComp=1; else, nComp=size(A,2); end
ind='        ';
fprintf(fid,'%s<DataArray type="%s" Name="%s"',ind,vtkType,name);
if nComp>1, fprintf(fid,' NumberOfComponents="%d"',nComp); end
fprintf(fid,' format="ascii">\n%s  ',ind);
flat=A.'; flat=flat(:);
if isa(flat,'double')||isa(flat,'single'), str=sprintf('%.10g ',flat);
else, str=sprintf('%d ',flat); end
fwrite(fid,str,'char');
fprintf(fid,'\n%s</DataArray>\n',ind);
end

function [conn, off] = pvdVtkRowCellsToConnectivity(cells)
cells=double(cells); nCell=size(cells,1); nPerRow=cells(:,1);
if all(nPerRow==nPerRow(1))
    n=nPerRow(1); ids=cells(:,2:1+n); conn=int32(ids.'-1); conn=conn(:); off=int32((1:nCell).'*n);
else
    totalPts=sum(nPerRow); conn=zeros(totalPts,1,'int32'); off=zeros(nCell,1,'int32'); pos=1;
    for i=1:nCell
        n=nPerRow(i); conn(pos:pos+n-1)=int32(cells(i,2:1+n))-1; pos=pos+n; off(i)=pos-1;
    end
end
end

function types = pvdInferVTKCellTypes(cells)
nPer=double(cells(:,1)); types=repmat(uint8(7),numel(nPer),1);
types(nPer==1)=uint8(1); types(nPer==2)=uint8(3); types(nPer==3)=uint8(5);
types(nPer==4)=uint8(9); types(nPer==5)=uint8(14); types(nPer==6)=uint8(13); types(nPer==8)=uint8(12);
end

function vtkType = pvdMatlabClassToVTK(A)
if isa(A,'uint8'), vtkType='UInt8'; elseif isa(A,'int32'), vtkType='Int32';
elseif isa(A,'single'), vtkType='Float32'; else, vtkType='Float64'; end
end

function pvdWriteArrayHeader(fid, name, vtkType, nComp_, byteOffset)
ind='        ';
fprintf(fid,'%s<DataArray type="%s" Name="%s"',ind,vtkType,name);
if nComp_>1, fprintf(fid,' NumberOfComponents="%d"',nComp_); end
fprintf(fid,' format="appended" offset="%d"/>\n',byteOffset);
end

function n = pvdNumComponents(A)
if isvector(A), n=1; else, n=size(A,2); end
end

function raw = pvdToRawArray(A, vtkType)
switch vtkType
    case 'Float64', raw=double(A); case 'Float32', raw=single(A);
    case 'Int32',   raw=int32(A);  case 'UInt8',   raw=uint8(A);
    otherwise,      raw=double(A);
end
raw=raw.'; raw=raw(:);
end

function nb = pvdByteSize(vtkType)
switch vtkType
    case {'Float64','Int64','UInt64'}, nb=8;
    case {'Float32','Int32','UInt32'}, nb=4;
    case {'Int16','UInt16'},           nb=2;
    otherwise,                         nb=1;
end
end

function cls = pvdMatlabBinaryClass(vtkType)
switch vtkType
    case 'Float64', cls='double'; case 'Float32', cls='single';
    case 'Int32',   cls='int32';  case 'UInt8',   cls='uint8';
    otherwise,      cls='double';
end
end

function tf = pvdHasExportableData(resp)
tf=false;
if ~isstruct(resp)||isempty(fieldnames(resp)), return; end
skip={'time','ModelUpdate','nodeTags','eleTags','odbTag','interpolatePoints','interpolateDisp','interpolateCells','interpolateCoords'};
for fn=fieldnames(resp).'
    name=fn{1}; if ismember(name,skip), continue; end
    value=resp.(name);
    if isstruct(value)&&isfield(value,'data')&&isnumeric(value.data)&&~isempty(value.data), tf=true; return; end
    if isstruct(value)&&~isfield(value,'data')
        for fn2=fieldnames(value).'
            if isnumeric(value.(fn2{1}))&&~isempty(value.(fn2{1})), tf=true; return; end
        end
    end
    if isnumeric(value)&&~isempty(value), tf=true; return; end
end
if isfield(resp,'interpolatePoints')&&~isempty(resp.interpolatePoints)&&...
   isfield(resp,'interpolateDisp')&&~isempty(resp.interpolateDisp)&&...
   isfield(resp,'interpolateCells')&&~isempty(resp.interpolateCells), tf=true; end
end

function [pts, disp3, cells] = pvdGetInterpSlice(resp, localStep)
pts=double(resp.interpolatePoints); disp_=double(resp.interpolateDisp); C=double(resp.interpolateCells);
if ndims(pts)==3
    si=min(localStep,size(pts,1)); pts=squeeze(pts(si,:,:)); disp_=squeeze(disp_(si,:,:));
end
if isempty(pts), pts=zeros(0,3); disp3=zeros(0,3); cells=zeros(0,2); return;
elseif isvector(pts), pts=reshape(pts,1,[]); end
if size(pts,2)<3, pts(:,end+1:3)=0; elseif size(pts,2)>3, pts=pts(:,1:3); end
if isempty(disp_), disp_=zeros(size(pts,1),3); elseif isvector(disp_), disp_=reshape(disp_,1,[]); end
if size(disp_,2)<3, disp_(:,end+1:3)=0; elseif size(disp_,2)>3, disp_=disp_(:,1:3); end
if ndims(C)==3, si=min(localStep,size(C,1)); C=squeeze(C(si,:,:)); end
keepPts=~all(isnan(pts),2);
if size(disp_,1)==size(pts,1), keepPts=keepPts&~all(isnan(disp_),2); end
rawToClean=zeros(size(pts,1),1); rawToClean(keepPts)=1:nnz(keepPts);
pts=pts(keepPts,:); disp_=disp_(keepPts,:);
disp3=zeros(size(pts,1),3); disp3(:,1:min(3,size(disp_,2)))=disp_(:,1:min(3,size(disp_,2)));
if isempty(C), cells=zeros(0,2); return; elseif isvector(C), C=reshape(C,1,[]); end
keepCell=~all(isnan(C),2); C=C(keepCell,:);
if isempty(C), cells=zeros(0,2); return; end
if size(C,2)>=3, cells=C(:,end-1:end); else, cells=C; end
cells=round(cells);
valid=all(isfinite(cells),2)&all(cells>=1,2)&all(cells<=numel(rawToClean),2);
cells=cells(valid,:); if isempty(cells), return; end
cells=rawToClean(cells); cells=cells(all(cells>=1,2),:);
end

function out = pvdUnwrapResponseGroup(resp, groupName)
out=resp;
if ~isstruct(resp)||isempty(fieldnames(resp(1)))||~isfield(resp(1),groupName), return; end
% Unwrap each segment
for s=1:numel(resp)
    if isfield(resp(s),groupName), out(s)=resp(s).(groupName); end
end
end

function tf = pvdIsLineFamilyName(famName)
tf=ismember(lower(char(string(famName))),{'beam','truss','link','line'});
end

function [connOut, offOut, typOut] = pvdFilterLineConnectivity(conn, off, typ)
connOut=int32(conn(:)); offOut=int32(off(:)); typOut=uint8(typ(:));
if isempty(offOut)||isempty(typOut), return; end
lineTypes=uint8([3,4,21]);
keepCell=~ismember(typOut,lineTypes);
if all(keepCell), return; end
if ~any(keepCell), connOut=zeros(0,1,'int32'); offOut=zeros(0,1,'int32'); typOut=zeros(0,1,'uint8'); return; end
startIdx=[1;double(offOut(1:end-1))+1];
connParts=cell(nnz(keepCell),1); newOff=zeros(nnz(keepCell),1,'int32');
cursor=int32(0); writeIdx=0;
for i=1:numel(offOut)
    if ~keepCell(i), continue; end
    writeIdx=writeIdx+1;
    seg=connOut(startIdx(i):double(offOut(i)));
    connParts{writeIdx}=seg; cursor=cursor+int32(numel(seg)); newOff(writeIdx)=cursor;
end
connOut=vertcat(connParts{:}); offOut=newOff; typOut=typOut(keepCell);
end

function dofs = localNormalizeDofs(rawDofs)
dofs={};
if isempty(rawDofs), return; end
value=rawDofs;
while iscell(value)&&isscalar(value)&&~isempty(value{1})
    inner=value{1};
    if iscell(inner)||isstring(inner), value=inner; else, break; end
end
if isstring(value), dofs=cellstr(value(:).');
elseif ischar(value), dofs={value};
elseif iscell(value)
    dofs=cell(1,numel(value));
    for i=1:numel(value), dofs{i}=char(string(value{i})); end
end
end
