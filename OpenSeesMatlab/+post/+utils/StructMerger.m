classdef StructMerger
    %STRUCTMERGER High-performance merger for fixed-schema nested scalar structs.
    %
    % Supported merge modes
    % ---------------------
    % Mode = 'prepend'
    %   Add a new leading dimension for each part.
    %   Suitable for step-wise data, where each part is one time step.
    %
    % Mode = 'concat'
    %   Concatenate along the existing dimension 1.
    %   Suitable for part-wise data, where each part already contains a time axis.
    %
    % modelUpdate behavior
    % --------------------
    % modelUpdate = false
    %   - prepend: all shapes must match exactly, then add a new leading dim
    %   - concat  : dims 2:end must match exactly, then concatenate along dim 1
    %
    % modelUpdate = true
    %   - prepend: compute max shape across all parts, allocate [nParts, maxShape]
    %   - concat  : compute max shape on dims 2:end and total length on dim 1
    %
    % Notes
    % -----
    % - Optimized for nested scalar structs with fixed schema.
    % - Struct arrays are not supported.
    % - Cell/string/char/meta leaves are copied from the first non-empty part.
    % - Numeric/logical leaves are treated as mergeable arrays.
    %
    % Typical use
    % -----------
    % out = post.utils.StructMerger.mergeParts(parts, ...
    %     'ModelUpdateField', 'modelUpdate', ...
    %     'Mode', 'prepend');

    methods (Static)
        function out = mergeParts(parts, varargin)
            %MERGEPARTS Merge a cell array of nested scalar structs.
            %
            % Syntax
            % ------
            % out = StructMerger.mergeParts(parts)
            % out = StructMerger.mergeParts(parts, 'ModelUpdateField', 'modelUpdate')
            % out = StructMerger.mergeParts(parts, 'Mode', 'prepend')

            [modelUpdateField, mode] = post.utils.StructMerger.parseOptions(varargin{:});

            if ~iscell(parts)
                error('StructMerger:InvalidInput', ...
                    'Input "parts" must be a cell array.');
            end

            if isempty(parts)
                out = struct();
                return;
            end

            mask = ~cellfun(@isempty, parts);
            parts = parts(mask);

            if isempty(parts)
                out = struct();
                return;
            end

            idx0 = post.utils.StructMerger.findFirstNonEmpty(parts);
            if idx0 == 0
                out = struct();
                return;
            end

            base = parts{idx0};
            if ~isstruct(base) || ~isscalar(base)
                error('StructMerger:InvalidInput', ...
                    'Each part must be a non-empty scalar struct.');
            end

            if isfield(base, modelUpdateField) && ~isempty(base.(modelUpdateField))
                modelUpdate = logical(base.(modelUpdateField));
            else
                modelUpdate = false;
            end

            leafInfo = post.utils.StructMerger.collectLeafInfoFromParts( ...
                base, parts, {}, modelUpdateField, modelUpdate, mode);

            buffers = post.utils.StructMerger.mergeAllArrayLeaves(leafInfo, modelUpdate, mode);

            out = post.utils.StructMerger.copyMetaSkeleton(base);
            out = post.utils.StructMerger.assembleOutput(out, leafInfo, buffers);
        end
    end

    methods (Static, Access = private)
        function [modelUpdateField, mode] = parseOptions(varargin)
            modelUpdateField = 'modelUpdate';
            mode = 'concat';

            if isempty(varargin)
                return;
            end

            if mod(numel(varargin), 2) ~= 0
                error('StructMerger:InvalidInput', ...
                    'Optional inputs must be name-value pairs.');
            end

            for i = 1:2:numel(varargin)
                name = varargin{i};
                value = varargin{i + 1};

                if isstring(name) && isscalar(name)
                    name = char(name);
                end

                if ~ischar(name)
                    error('StructMerger:InvalidOptionName', ...
                        'Option names must be char vectors or scalar strings.');
                end

                switch lower(name)
                    case 'modelupdatefield'
                        if isstring(value) && isscalar(value)
                            value = char(value);
                        end
                        if ~ischar(value)
                            error('StructMerger:InvalidModelUpdateField', ...
                                'ModelUpdateField must be char or scalar string.');
                        end
                        modelUpdateField = value;

                    case 'mode'
                        if isstring(value) && isscalar(value)
                            value = char(value);
                        end
                        if ~ischar(value)
                            error('StructMerger:InvalidMode', ...
                                'Mode must be ''prepend'' or ''concat''.');
                        end
                        mode = lower(value);

                    otherwise
                        error('StructMerger:UnknownOption', ...
                            'Unknown option: %s', name);
                end
            end

            if ~ismember(mode, {'prepend', 'concat'})
                error('StructMerger:InvalidMode', ...
                    'Mode must be ''prepend'' or ''concat''.');
            end
        end

        function leafInfo = collectLeafInfoFromParts(baseNode, partNodes, prefix, modelUpdateField, modelUpdate, mode)
            %COLLECTLEAFINFOFROMPARTS Traverse schema once and collect leaf values.
            %
            % baseNode   : schema source from first non-empty part
            % partNodes  : cell array of corresponding nodes across parts
            % prefix     : field path
            %
            % Output leafInfo fields
            % ----------------------
            % path
            % kind      : "array" | "meta"
            % metaValue : first non-empty meta value
            % values    : cell array of leaf values across parts
            % refShape
            % maxShape
            % totalN1
            % outClass

            if ~isstruct(baseNode) || ~isscalar(baseNode)
                error('StructMerger:InvalidNode', ...
                    'Schema traversal expects scalar struct nodes.');
            end

            fn = fieldnames(baseNode);
            leafInfo = repmat(post.utils.StructMerger.emptyLeafRecord(), 0, 1);

            for k = 1:numel(fn)
                name = fn{k};
                baseValue = baseNode.(name);
                path = [prefix, {name}];

                childNodes = cell(size(partNodes));
                for p = 1:numel(partNodes)
                    node = partNodes{p};
                    if ~isempty(node) && isstruct(node) && isfield(node, name)
                        childNodes{p} = node.(name);
                    end
                end

                if isstruct(baseValue)
                    childInfo = post.utils.StructMerger.collectLeafInfoFromParts( ...
                        baseValue, childNodes, path, modelUpdateField, modelUpdate, mode);
                    leafInfo = [leafInfo; childInfo]; %#ok<AGROW>
                else
                    rec = post.utils.StructMerger.makeLeafRecord( ...
                        path, name, baseValue, childNodes, modelUpdateField, modelUpdate, mode);
                    leafInfo(end + 1, 1) = rec; %#ok<AGROW>
                end
            end
        end

        function rec = makeLeafRecord(path, fieldName, baseValue, values, modelUpdateField, modelUpdate, mode)
            rec = post.utils.StructMerger.emptyLeafRecord();
            rec.path = path;
            rec.values = values;

            if (isnumeric(baseValue) || islogical(baseValue)) && ...
                    ~(isscalar(baseValue) && strcmp(fieldName, modelUpdateField))
                rec.kind = "array";
                [rec.refShape, rec.maxShape, rec.totalN1, rec.outClass] = ...
                    post.utils.StructMerger.computeArrayStats(values, modelUpdate, mode, path);
            else
                rec.kind = "meta";
                rec.metaValue = post.utils.StructMerger.firstNonEmptyOrDefault(values, baseValue);
            end
        end

        function [refShape, maxShape, totalN1, outClass] = computeArrayStats(values, modelUpdate, mode, path)
            refShape = [];
            maxShape = [];
            totalN1 = 0;
            outClass = "";

            idx = find(~cellfun(@isempty, values));
            if isempty(idx)
                return;
            end

            for j = 1:numel(idx)
                x = values{idx(j)};
                sx = post.utils.StructMerger.normalizeSizeVector(size(x));

                if isempty(refShape)
                    refShape = sx;
                end

                if isempty(maxShape)
                    maxShape = sx;
                else
                    maxShape = post.utils.StructMerger.maxShapePair(maxShape, sx);
                end

                if modelUpdate
                    outClass = post.utils.StructMerger.mergeFloatingClass( ...
                        outClass, post.utils.StructMerger.chooseFloatingClass(x));
                else
                    if strlength(outClass) == 0
                        if islogical(x)
                            outClass = "logical";
                        else
                            outClass = string(class(x));
                        end
                    end
                end

                switch mode
                    case 'prepend'
                        totalN1 = totalN1 + 1;
                    case 'concat'
                        totalN1 = totalN1 + sx(1);
                end
            end

            if ~modelUpdate
                switch mode
                    case 'prepend'
                        for j = 1:numel(idx)
                            x = values{idx(j)};
                            sx = post.utils.StructMerger.normalizeSizeVector(size(x));
                            if ~isequal(sx, refShape)
                                error('StructMerger:SizeMismatch', ...
                                    ['Field "%s" has inconsistent shape while ', ...
                                     'Mode=''prepend'' and modelUpdate=false.'], ...
                                    strjoin(path, '.'));
                            end
                        end

                    case 'concat'
                        for j = 1:numel(idx)
                            x = values{idx(j)};
                            sx = post.utils.StructMerger.normalizeSizeVector(size(x));
                            ref = refShape;

                            if numel(sx) < numel(ref)
                                sx(end+1:numel(ref)) = 1;
                            elseif numel(ref) < numel(sx)
                                ref(end+1:numel(sx)) = 1;
                            end

                            if ~isequal(sx(2:end), ref(2:end))
                                error('StructMerger:SizeMismatch', ...
                                    ['Field "%s" has inconsistent dims 2:end while ', ...
                                     'Mode=''concat'' and modelUpdate=false.'], ...
                                    strjoin(path, '.'));
                            end
                        end
                end
            end
        end

        function buffers = mergeAllArrayLeaves(leafInfo, modelUpdate, mode)
            nLeaf = numel(leafInfo);
            buffers = cell(nLeaf, 1);

            for i = 1:nLeaf
                if leafInfo(i).kind ~= "array"
                    continue;
                end

                buffers{i} = post.utils.StructMerger.mergeOneArrayLeaf( ...
                    leafInfo(i).values, ...
                    leafInfo(i).refShape, ...
                    leafInfo(i).maxShape, ...
                    leafInfo(i).totalN1, ...
                    char(leafInfo(i).outClass), ...
                    modelUpdate, ...
                    mode);
            end
        end

        function out = mergeOneArrayLeaf(values, refShape, maxShape, totalN1, outClass, modelUpdate, mode)
            idx = find(~cellfun(@isempty, values));
            if isempty(idx)
                out = [];
                return;
            end

            vals = values(idx);

            switch mode
                case 'prepend'
                    if modelUpdate
                        out = post.utils.StructMerger.mergePrependPadded(vals, maxShape, outClass);
                    else
                        out = post.utils.StructMerger.mergePrependStatic(vals, outClass);
                    end

                case 'concat'
                    if modelUpdate
                        out = post.utils.StructMerger.mergeConcatPadded(vals, maxShape, totalN1, outClass);
                    else
                        out = post.utils.StructMerger.mergeConcatStatic(vals, outClass);
                    end
            end
        end

        function out = mergePrependStatic(vals, outClass)
            first = vals{1};
            nd = ndims(first);

            if strcmp(outClass, 'logical')
                tmp = cat(nd + 1, vals{:});
            else
                castVals = cell(size(vals));
                for i = 1:numel(vals)
                    castVals{i} = cast(vals{i}, outClass);
                end
                tmp = cat(nd + 1, castVals{:});
            end

            out = permute(tmp, [nd + 1, 1:nd]);
        end

        function out = mergePrependPadded(vals, maxShape, outClass)
            n = numel(vals);
            if isempty(maxShape)
                out = [];
                return;
            end

            out = nan([n, maxShape], outClass);

            for i = 1:n
                x = vals{i};
                sx = post.utils.StructMerger.normalizeSizeVector(size(x));
                out = post.utils.StructMerger.writeBlockPrependPadded(out, cast(x, outClass), i, sx);
            end
        end

        function out = mergeConcatStatic(vals, outClass)
            if strcmp(outClass, 'logical')
                out = cat(1, vals{:});
            else
                castVals = cell(size(vals));
                for i = 1:numel(vals)
                    castVals{i} = cast(vals{i}, outClass);
                end
                out = cat(1, castVals{:});
            end
        end

        function out = mergeConcatPadded(vals, maxShape, totalN1, outClass)
            if isempty(maxShape)
                out = [];
                return;
            end

            shape = maxShape;
            shape(1) = totalN1;
            out = nan(shape, outClass);

            pos = 1;
            for i = 1:numel(vals)
                x = vals{i};
                sx = post.utils.StructMerger.normalizeSizeVector(size(x));
                n1 = sx(1);
                pos2 = pos + n1 - 1;
                out = post.utils.StructMerger.writeBlockConcatPadded(out, cast(x, outClass), pos, pos2, sx);
                pos = pos2 + 1;
            end
        end

        function out = assembleOutput(out, leafInfo, buffers)
            for i = 1:numel(leafInfo)
                if leafInfo(i).kind == "meta"
                    out = post.utils.StructMerger.setNestedField( ...
                        out, leafInfo(i).path, leafInfo(i).metaValue);
                else
                    out = post.utils.StructMerger.setNestedField( ...
                        out, leafInfo(i).path, buffers{i});
                end
            end
        end

        function S = copyMetaSkeleton(node)
            if ~isstruct(node)
                S = [];
                return;
            end

            S = struct();
            fn = fieldnames(node);
            for k = 1:numel(fn)
                name = fn{k};
                value = node.(name);
                if isstruct(value)
                    S.(name) = post.utils.StructMerger.copyMetaSkeleton(value);
                else
                    S.(name) = [];
                end
            end
        end

        function value = firstNonEmptyOrDefault(values, defaultValue)
            idx = post.utils.StructMerger.findFirstNonEmpty(values);
            if idx == 0
                value = defaultValue;
            else
                value = values{idx};
            end
        end

        function S = setNestedField(S, path, value)
            if numel(path) == 1
                S.(path{1}) = value;
                return;
            end

            head = path{1};
            S.(head) = post.utils.StructMerger.setNestedField(S.(head), path(2:end), value);
        end

        function arr = writeBlockPrependPadded(arr, x, pos, sx)
            nd = ndims(x);
            sx = post.utils.StructMerger.normalizeSizeVector(sx);

            switch nd
                case 2
                    arr(pos, 1:sx(1), 1:sx(2)) = x;
                case 3
                    arr(pos, 1:sx(1), 1:sx(2), 1:sx(3)) = x;
                case 4
                    arr(pos, 1:sx(1), 1:sx(2), 1:sx(3), 1:sx(4)) = x;
                otherwise
                    nDims = nd + 1;
                    subs = cell(1, nDims);
                    subs{1} = pos;
                    for d = 1:nd
                        subs{d + 1} = 1:sx(d);
                    end
                    arr(subs{:}) = reshape(x, [1, sx]);
            end
        end

        function arr = writeBlockConcatPadded(arr, x, pos1, pos2, sx)
            nDims = ndims(arr);
            sx = post.utils.StructMerger.normalizeSizeVector(sx);

            switch nDims
                case 2
                    arr(pos1:pos2, 1:sx(2)) = x;
                case 3
                    arr(pos1:pos2, 1:sx(2), 1:sx(3)) = x;
                case 4
                    arr(pos1:pos2, 1:sx(2), 1:sx(3), 1:sx(4)) = x;
                otherwise
                    if numel(sx) < nDims
                        sx(end+1:nDims) = 1;
                    end

                    subs = cell(1, nDims);
                    subs{1} = pos1:pos2;
                    for d = 2:nDims
                        subs{d} = 1:sx(d);
                    end
                    arr(subs{:}) = x;
            end
        end

        function rec = emptyLeafRecord()
            rec = struct( ...
                'path', {{}}, ...
                'kind', "", ...
                'metaValue', [], ...
                'values', {{}}, ...
                'refShape', [], ...
                'maxShape', [], ...
                'totalN1', 0, ...
                'outClass', "");
        end

        function idx = findFirstNonEmpty(values)
            idx = 0;
            for i = 1:numel(values)
                if ~isempty(values{i})
                    idx = i;
                    return;
                end
            end
        end

        function sz = normalizeSizeVector(sz)
            sz = double(sz);
            if isempty(sz)
                sz = [0 0];
            elseif isscalar(sz)
                sz = [sz 1];
            end
        end

        function s = maxShapePair(a, b)
            a = post.utils.StructMerger.normalizeSizeVector(a);
            b = post.utils.StructMerger.normalizeSizeVector(b);

            na = numel(a);
            nb = numel(b);

            if na < nb
                a(end+1:nb) = 1;
            elseif nb < na
                b(end+1:na) = 1;
            end

            s = max(a, b);
        end

        function cls = chooseFloatingClass(x)
            if isa(x, 'single')
                cls = "single";
            else
                cls = "double";
            end
        end

        function cls = mergeFloatingClass(a, b)
            if strlength(a) == 0
                cls = b;
            elseif a == "double" || b == "double"
                cls = "double";
            else
                cls = "single";
            end
        end
    end
end