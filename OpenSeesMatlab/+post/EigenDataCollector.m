classdef EigenDataCollector < handle
    %EIGENDATACOLLECTOR Efficient modal data collector for OpenSees MATLAB.
    %
    % Main output
    % -----------
    % data = collector.collect(...)
    %
    %   data.ModeTags
    %   data.ModalProps
    %   data.EigenVectors
    %   data.InterpolatedEigenVectors
    %   data.ModelInfo
    %
    % Notes
    % -----
    % - Node coordinates, node tags, node ndm/ndf, and interpolation
    %   geometry are all taken from modelInfo.
    % - Eigenvectors themselves are still queried from OpenSees via
    %   ops.nodeEigenvector(nodeTag, modeTag).
    % - Interpolation uses Beam3DDispInterpolator with MATLAB 1-based
    %   connectivity, which matches the current MATLAB implementation.
    %
    % Example
    % -------
    % collector = post.EigenDataCollector(ops, modelInfo);
    % data = collector.collect(10, '-genBandArpack', ...
    %     'InterpolateBeam', true, ...
    %     'NptsPerElement', 11, ...
    %     'InterpNanPolicy', 'ignore');

    properties (SetAccess = private)
        ops
    end

    properties
        ModelInfo struct = struct()
    end

    properties (Access = private)
        % Raw MEX handle for zero-overhead OpenSees calls.
        mex_

        % Cached node information extracted once from modelInfo.
        CacheNodeTags double = []
        CacheNodeCoords double = []
        CacheNodeNdm double = []
        CacheNodeNdf double = []

        % Cached interpolation geometry assembled once from modelInfo.
        CacheInterpGeometry struct = struct()
    end

    methods
        function obj = EigenDataCollector(ops, modelInfo)
            %EIGENDATACOLLECTOR Construct the collector.
            if nargin < 1 || isempty(ops)
                error('EigenDataCollector:InvalidInput', ...
                    'An OpenSees interface object ''ops'' is required.');
            end
            obj.ops = ops;
            obj.mex_ = ops.getMexHandle();

            if nargin >= 2 && ~isempty(modelInfo)
                obj.setModelInfo(modelInfo);
            end
        end

        function setModelInfo(obj, modelInfo)
            %SETMODELINFO Replace modelInfo and clear internal caches.
            if nargin < 2 || ~isstruct(modelInfo)
                error('EigenDataCollector:InvalidModelInfo', ...
                    'modelInfo must be a struct.');
            end
            obj.ModelInfo = modelInfo;
            obj.clearCache();
        end

        function clearCache(obj)
            %CLEARCACHE Clear cached node and interpolation data.
            obj.CacheNodeTags = [];
            obj.CacheNodeCoords = [];
            obj.CacheNodeNdm = [];
            obj.CacheNodeNdf = [];
            obj.CacheInterpGeometry = struct();
        end

        function data = collect(obj, modeTag, solver, varargin)
            %COLLECT Collect modal data into a plain MATLAB struct.
            if nargin < 2 || isempty(modeTag)
                modeTag = 1;
            end
            if nargin < 3 || isempty(solver)
                solver = '-genBandArpack';
            end

            p = inputParser;
            p.FunctionName = 'EigenDataCollector.collect';
            addParameter(p, 'IncludeModelInfo', false, @(x) islogical(x) || isnumeric(x));
            addParameter(p, 'InterpolateBeam', true, @(x) islogical(x) || isnumeric(x));
            addParameter(p, 'NptsPerElement', 6, @(x) isnumeric(x) && isscalar(x) && x >= 2);
            addParameter(p, 'InterpNanPolicy', 'ignore', ...
                @(x) ischar(x) || (isstring(x) && isscalar(x)));
            parse(p, varargin{:});
            opts = p.Results;

            obj.runEigenAnalysis(modeTag, solver);

            data = struct();
            data.ModeTags = (1:modeTag).';
            data.ModalProps = obj.getModalProperties(modeTag);
            data.EigenVectors = obj.getEigenVectors(modeTag);

            if logical(opts.InterpolateBeam)
                data.InterpolatedEigenVectors = obj.getInterpolatedEigenVectors( ...
                    data.EigenVectors, opts.NptsPerElement, char(opts.InterpNanPolicy));
            else
                data.InterpolatedEigenVectors = [];
            end

            if logical(opts.IncludeModelInfo)
                data.ModelInfo = obj.ModelInfo;
            else
                data.ModelInfo = struct();
            end
        end

        function save(obj, filename, modeTag, solver, varargin)
            %SAVE Save collected data to an HDF5 file.
            if nargin < 3 || isempty(modeTag)
                modeTag = 1;
            end
            if nargin < 4 || isempty(solver)
                solver = '-genBandArpack';
            end
            data = obj.collect(modeTag, solver, varargin{:});
            store = post.utils.HDF5DataStore(filename, 'overwrite', true);
            store.write('/', data);
        end

        function data = readFile(~, filename)
            %READFILE Load collected data from an HDF5 file.
            store = post.utils.HDF5DataStore(filename, 'overwrite', false);
            data = store.load();

            if ~isstruct(data)
                error('EigenDataCollector:InvalidData', ...
                    'Data read from file is not a struct. Invalid format.');
            end
        end

        function runEigenAnalysis(obj, modeTag, solver)
            %RUNEIGENANALYSIS Run OpenSees eigen analysis.
            if nargin < 2 || isempty(modeTag)
                modeTag = 1;
            end
            if nargin < 3 || isempty(solver)
                solver = '-genBandArpack';
            end

            obj.mex_('wipeAnalysis');
            if modeTag == 1
                obj.mex_('eigen', solver, 2);
            else
                obj.mex_('eigen', solver, modeTag);
            end
        end

        function modalProps = getModalProperties(obj, modeTag)
            %GETMODALPROPERTIES Collect modalProperties('-return') as a struct.
            if nargin < 2 || isempty(modeTag)
                modeTag = 1;
            end

            raw = obj.mex_('modalProperties', '-return');
            raw = obj.toStruct(raw);

            attrNames = {'domainSize', 'totalMass', 'totalFreeMass', 'centerOfMass'};
            attrs = struct();
            fns = fieldnames(raw);
            propFields = {};

            for i = 1:numel(fns)
                name = fns{i};
                value = raw.(name);
                if any(strcmp(name, attrNames))
                    value = obj.rowVector(value);
                    if strcmp(name, 'domainSize')
                        value = int64(value);
                    end
                    if isscalar(value)
                        value = value(1);
                    end
                    attrs.(name) = value;
                else
                    propFields{end+1,1} = name; %#ok<AGROW>
                end
            end

            nProp = numel(propFields);
            matrix = zeros(modeTag, nProp);
            for i = 1:nProp
                v = obj.rowVector(raw.(propFields{i}));
                nCopy = min(modeTag, numel(v));
                if nCopy > 0
                    matrix(1:nCopy, i) = v(1:nCopy).';
                end
            end

            modalProps = struct();
            modalProps.attrs = attrs;
            modalProps.data = matrix;
            modalProps.raw = raw;
        end

        function eigenVectors = getEigenVectors(obj, modeTag)
            %GETEIGENVECTORS Collect node-level eigenvectors.
            if nargin < 2 || isempty(modeTag)
                modeTag = 1;
            end

            [nodeTags, nodeCoords, nodeNdm, nodeNdf] = obj.getCachedNodeInfo();
            nNode = numel(nodeTags);
            data = zeros(modeTag, nNode, 6);

            for iMode = 1:modeTag
                for iNode = 1:nNode
                    tag = nodeTags(iNode);
                    eigv = obj.mex_('nodeEigenvector', tag, iMode);
                    data(iMode, iNode, :) = obj.normalizeEigenvector(eigv, nodeNdm(iNode), nodeNdf(iNode));
                end
            end

            eigenVectors = struct();
            eigenVectors.nodeTags = nodeTags(:);
            eigenVectors.nodeCoords = nodeCoords;
            eigenVectors.nodeNdm = nodeNdm(:);
            eigenVectors.nodeNdf = nodeNdf(:);
            eigenVectors.data = data;
        end

        function interpData = getInterpolatedEigenVectors(obj, eigenVectors, nptsPerElement, nanPolicy)
            %GETINTERPOLATEDEIGENVECTORS Interpolate modal displacements on line elements.
            if nargin < 3 || isempty(nptsPerElement)
                nptsPerElement = 11;
            end
            if nargin < 4 || isempty(nanPolicy)
                nanPolicy = 'ignore';
            end
            nanPolicy = validatestring(nanPolicy, {'ignore', 'propagate'});

            G = obj.getInterpolationGeometry();
            if isempty(fieldnames(G)) || isempty(G.cells)
                interpData = [];
                return;
            end

            [tf, loc] = ismember(G.nodeTags(:), eigenVectors.nodeTags(:));
            if ~all(tf)
                bad = G.nodeTags(~tf);
                error('EigenDataCollector:MissingNodeTags', ...
                    'Interpolation node tags are missing in eigenVectors.nodeTags. Missing tags: %s', ...
                    mat2str(bad(:).'));
            end

            nodalGlobal = eigenVectors.data(:, loc, :);

            interp = post.utils.Beam3DDispInterpolator(G.nodeCoords, G.cells, G.ax, G.ay, G.az);
            endLocal = interp.globalToLocalEnds(nodalGlobal, nanPolicy);
            [points, response, cells] = interp.interpolate(endLocal, nptsPerElement, nanPolicy);

            interpData = struct();
            interpData.points = points;
            interpData.data = response;
            interpData.cells = cells;
            interpData.modeTags = (1:size(response, 1)).';
            interpData.pointID = (1:size(points, 1)).';
            interpData.nodeTags = G.nodeTags(:);
            interpData.cellNodeTags = G.cellNodeTags;
            interpData.eleTags = G.eleTags;
            interpData.nptsPerElement = nptsPerElement;
        end
    end

    methods (Access = private)
        function [nodeTags, nodeCoords, nodeNdm, nodeNdf] = getCachedNodeInfo(obj)
            %GETCACHEDNODEINFO Return node metadata extracted from modelInfo.
            if ~isempty(obj.CacheNodeTags)
                nodeTags = obj.CacheNodeTags;
                nodeCoords = obj.CacheNodeCoords;
                nodeNdm = obj.CacheNodeNdm;
                nodeNdf = obj.CacheNodeNdf;
                return;
            end

            [nodeTags, nodeCoords, nodeNdm, nodeNdf] = obj.extractNodesFromModelInfo(obj.ModelInfo);

            obj.CacheNodeTags = nodeTags;
            obj.CacheNodeCoords = nodeCoords;
            obj.CacheNodeNdm = nodeNdm;
            obj.CacheNodeNdf = nodeNdf;
        end

        function G = getInterpolationGeometry(obj)
            %GETINTERPOLATIONGEOMETRY Assemble and cache all line-family geometry.
            %
            % Returned fields
            % ---------------
            % G.nodeCoords     [nNode x 3]
            % G.nodeTags       [nNode x 1]
            % G.cells          [nElem x 2]   node-row indices, 1-based
            % G.cellNodeTags   [nElem x 2]   original node tags
            % G.eleTags        [nElem x 1]
            % G.ax, G.ay, G.az [nElem x 3]
            % G.source         {nElem x 1}

            if ~isempty(fieldnames(obj.CacheInterpGeometry))
                G = obj.CacheInterpGeometry;
                return;
            end

            [nodeTags, nodeCoords] = obj.extractNodesFromModelInfo(obj.ModelInfo);
            nodeTags = nodeTags(:);

            if numel(unique(nodeTags)) ~= numel(nodeTags)
                error('EigenDataCollector:DuplicateNodeTags', ...
                    'modelInfo.Nodes.Tags contains duplicate node tags.');
            end

            fam = obj.getElementFamilies(obj.ModelInfo);
            if isempty(fam)
                G = struct();
                obj.CacheInterpGeometry = G;
                return;
            end

            cellsList = {};
            cellNodeTagsList = {};
            eleTagsList = {};
            axList = {};
            ayList = {};
            azList = {};
            sourceList = {};

            familyNames = {'Beam', 'Link', 'Truss'};
            for i = 1:numel(familyNames)
                name = familyNames{i};

                if ~isfield(fam, name) || isempty(fam.(name))
                    continue;
                end

                S = fam.(name);
                [cells0, cellNodeTags0, eleTags0] = obj.extractFamilyConnectivity(S, nodeTags);
                if isempty(cells0)
                    continue;
                end

                nElem = size(cells0, 1);
                [ax0, ay0, az0] = obj.extractFamilyAxes(S, cells0, nodeCoords);

                if size(ax0,1) ~= nElem || size(ay0,1) ~= nElem || size(az0,1) ~= nElem
                    error('EigenDataCollector:AxisSizeMismatch', ...
                        'Axis arrays do not match the number of elements in family %s.', name);
                end

                cellsList{end+1,1} = double(cells0); %#ok<AGROW>
                cellNodeTagsList{end+1,1} = double(cellNodeTags0); %#ok<AGROW>
                eleTagsList{end+1,1} = double(eleTags0(:)); %#ok<AGROW>
                axList{end+1,1} = double(ax0); %#ok<AGROW>
                ayList{end+1,1} = double(ay0); %#ok<AGROW>
                azList{end+1,1} = double(az0); %#ok<AGROW>
                sourceList{end+1,1} = repmat(string(name), nElem, 1); %#ok<AGROW>
            end

            if isempty(cellsList)
                G = struct();
                obj.CacheInterpGeometry = G;
                return;
            end

            cells = vertcat(cellsList{:});
            cellNodeTags = vertcat(cellNodeTagsList{:});
            eleTags = vertcat(eleTagsList{:});
            ax = vertcat(axList{:});
            ay = vertcat(ayList{:});
            az = vertcat(azList{:});
            source = vertcat(sourceList{:});

            G = struct();
            G.nodeCoords = nodeCoords;
            G.nodeTags = nodeTags;
            G.cells = double(cells);                  % internal 1-based row indices
            G.cellNodeTags = double(cellNodeTags);    % original node tags
            G.eleTags = double(eleTags);
            G.ax = double(ax);
            G.ay = double(ay);
            G.az = double(az);
            G.source = cellstr(source);

            obj.CacheInterpGeometry = G;
        end

        function [nodeTags, nodeCoords, nodeNdm, nodeNdf] = extractNodesFromModelInfo(~, modelInfo)
            %EXTRACTNODESFROMMODELINFO Extract node arrays from modelInfo.Nodes.
            if nargin < 2 || ~isstruct(modelInfo) || isempty(fieldnames(modelInfo))
                error('EigenDataCollector:EmptyModelInfo', ...
                    'modelInfo is empty. Node metadata cannot be resolved.');
            end
            if ~isfield(modelInfo, 'Nodes') || ~isstruct(modelInfo.Nodes)
                error('EigenDataCollector:MissingNodes', ...
                    'modelInfo.Nodes is required.');
            end

            S = modelInfo.Nodes;

            req = {'Tags', 'Coords'};
            for i = 1:numel(req)
                if ~isfield(S, req{i}) || isempty(S.(req{i}))
                    error('EigenDataCollector:MissingNodeField', ...
                        'modelInfo.Nodes.%s is required.', req{i});
                end
            end

            nodeTags = double(S.Tags(:));
            nodeCoords = double(S.Coords);
            if size(nodeCoords, 2) < 3
                nodeCoords(:, end+1:3) = NaN;
            elseif size(nodeCoords, 2) > 3
                nodeCoords = nodeCoords(:, 1:3);
            end

            nNode = numel(nodeTags);
            if size(nodeCoords, 1) ~= nNode
                error('EigenDataCollector:NodeSizeMismatch', ...
                    'modelInfo.Nodes.Tags and modelInfo.Nodes.Coords must have the same number of rows.');
            end

            if isfield(S, 'Ndm') && ~isempty(S.Ndm)
                nodeNdm = double(S.Ndm(:));
            else
                nodeNdm = sum(~isnan(nodeCoords), 2);
                nodeNdm(nodeNdm == 0) = 3;
            end
            if numel(nodeNdm) ~= nNode
                error('EigenDataCollector:NodeNdmSizeMismatch', ...
                    'modelInfo.Nodes.Ndm must have the same number of rows as node tags.');
            end

            if isfield(S, 'Ndf') && ~isempty(S.Ndf)
                nodeNdf = double(S.Ndf(:));
            else
                nodeNdf = 6 * ones(nNode, 1);
            end
            if numel(nodeNdf) ~= nNode
                error('EigenDataCollector:NodeNdfSizeMismatch', ...
                    'modelInfo.Nodes.Ndf must have the same number of rows as node tags.');
            end
        end

        function fam = getElementFamilies(~, modelInfo)
            %GETELEMENTFAMILIES Return modelInfo.Elements.Families when available.
            fam = struct();
            if ~isstruct(modelInfo) || isempty(fieldnames(modelInfo))
                return;
            end
            if ~isfield(modelInfo, 'Elements') || ~isstruct(modelInfo.Elements)
                return;
            end
            if ~isfield(modelInfo.Elements, 'Families') || ~isstruct(modelInfo.Elements.Families)
                return;
            end
            fam = modelInfo.Elements.Families;
        end

        function [cells, cellNodeTags, eleTags] = extractFamilyConnectivity(~, S, nodeTags)
            %EXTRACTFAMILYCONNECTIVITY Extract line-family connectivity.
            %
            % Returns
            % -------
            % cells        [nElem x 2] internal node-row indices, 1-based
            % cellNodeTags [nElem x 2] original node tags
            % eleTags      [nElem x 1]

            cells = zeros(0, 2);
            cellNodeTags = zeros(0, 2);
            eleTags = zeros(0, 1);

            if ~isstruct(S) || ~isfield(S, 'Cells') || isempty(S.Cells)
                return;
            end

            A = double(S.Cells);
            nElem = size(A, 1);

            if size(A, 2) < 2
                error('EigenDataCollector:InvalidFamilyCells', ...
                    'Family.Cells must have at least 2 columns.');
            end

            % Current FEMDataCollector stores line-family Cells as:
            %   [2, idx1, idx2]
            % or possibly [idx1, idx2]
            if size(A, 2) >= 3
                cells = A(:, end-1:end);
            else
                cells = A(:, 1:2);
            end

            if any(~isfinite(cells(:)))
                error('EigenDataCollector:InvalidConnectivity', ...
                    'Family.Cells contains NaN or Inf.');
            end

            if any(cells(:) < 1) || any(cells(:) > numel(nodeTags))
                bad = unique(cells(cells < 1 | cells > numel(nodeTags)));
                error('EigenDataCollector:InvalidConnectivityIndex', ...
                    'Connectivity indices are out of range of modelInfo.Nodes.Tags. Bad indices: %s', ...
                    mat2str(bad(:).'));
            end

            cellNodeTags = reshape(nodeTags(cells(:)), size(cells));

            if isfield(S, 'Tags') && ~isempty(S.Tags)
                eleTags = double(S.Tags(:));
            else
                eleTags = (1:nElem).';
            end

            if numel(eleTags) ~= nElem
                error('EigenDataCollector:ElementTagSizeMismatch', ...
                    'Family.Tags must have the same number of rows as Family.Cells.');
            end
        end

        function [ax, ay, az] = extractFamilyAxes(~, S, cells, nodeCoords)
            %EXTRACTFAMILYAXES Resolve local axis arrays for a line family.
            %
            % Strategy
            % --------
            % 1. Use XAxis/YAxis/ZAxis directly when present.
            % 2. If XAxis is missing, derive it from the end-node coordinates.
            % 3. Missing YAxis/ZAxis are filled with zeros.

            nElem = size(cells, 1);

            ax = post.EigenDataCollector.readAxisField(S, 'XAxis', nElem);
            ay = post.EigenDataCollector.readAxisField(S, 'YAxis', nElem);
            az = post.EigenDataCollector.readAxisField(S, 'ZAxis', nElem);

            if isempty(ax)
                ax = zeros(nElem, 3);
            end
            if isempty(ay)
                ay = zeros(nElem, 3);
            end
            if isempty(az)
                az = zeros(nElem, 3);
            end

            missingX = all(abs(ax) < eps, 2) | any(isnan(ax), 2);
            if any(missingX)
                c = cells(missingX, :);

                if any(c(:) < 1) || any(c(:) > size(nodeCoords, 1))
                    error('EigenDataCollector:AxisConnectivityMismatch', ...
                        'Failed to derive XAxis because some connectivity indices are out of bounds.');
                end

                p1 = nodeCoords(c(:, 1), :);
                p2 = nodeCoords(c(:, 2), :);
                dx = p2 - p1;
                L = sqrt(sum(dx.^2, 2));

                tmp = zeros(sum(missingX), 3);
                good = L > 0;
                tmp(good, :) = dx(good, :) ./ L(good);
                ax(missingX, :) = tmp;
            end
        end

        function v6 = normalizeEigenvector(~, eigv, ndm, ndf)
            %NORMALIZEEIGENVECTOR Map native OpenSees output to [UX UY UZ RX RY RZ].
            eigv = double(eigv(:).');
            if nargin < 4 || isempty(ndf)
                ndf = numel(eigv);
            end
            if nargin < 3 || isempty(ndm)
                ndm = 3;
            end

            nAvail = min(numel(eigv), ndf);
            eigv = eigv(1:nAvail);

            v6 = zeros(1, 6);

            if ndm == 1
                if nAvail >= 1
                    v6(1) = eigv(1);
                end
                return;
            end

            if ndm == 2
                if nAvail >= 3
                    v6([1, 2, 6]) = eigv(1:3);
                elseif nAvail == 2
                    v6(1:2) = eigv(1:2);
                elseif nAvail == 1
                    v6(1) = eigv(1);
                end
                return;
            end

            if nAvail >= 6
                v6 = eigv(1:6);
            elseif nAvail >= 3
                v6(1:nAvail) = eigv(1:nAvail);
            elseif nAvail >= 1
                v6(1:nAvail) = eigv(1:nAvail);
            end
        end

        function v = rowVector(~, v)
            %ROWVECTOR Convert an input to a numeric row vector when possible.
            if iscell(v)
                v = cell2mat(v);
            end
            if isempty(v)
                v = [];
                return;
            end
            if isnumeric(v) || islogical(v) || isinteger(v)
                v = double(v(:)).';
            end
        end

        function s = toStruct(~, x)
            %TOSTRUCT Convert struct-like modalProperties output to a struct.
            if isstruct(x)
                s = x;
                return;
            end
            if isa(x, 'containers.Map')
                keys_ = x.keys;
                s = struct();
                for i = 1:numel(keys_)
                    key = keys_{i};
                    s.(matlab.lang.makeValidName(char(key))) = x(key);
                end
                return;
            end
            try
                s = struct(x);
            catch
                error('EigenDataCollector:ConversionFailed', ...
                    'Unable to convert modalProperties output to a struct.');
            end
        end
    end

    methods (Static, Access = private)
        function A = readAxisField(S, fieldName, nElem)
            %READAXISFIELD Read an axis field and validate its shape.
            if isstruct(S) && isfield(S, fieldName) && ~isempty(S.(fieldName))
                A = double(S.(fieldName));
                if size(A, 1) ~= nElem || size(A, 2) ~= 3
                    error('EigenDataCollector:InvalidAxisField', ...
                        '%s must be an nElem-by-3 array.', fieldName);
                end
            else
                A = [];
            end
        end
    end
end
