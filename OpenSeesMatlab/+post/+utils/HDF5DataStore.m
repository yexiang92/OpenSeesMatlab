classdef HDF5DataStore < handle
    % HDF5DataStore
    %
    % High-performance HDF5 storage for:
    % - nested scalar struct
    % - nested cell
    % - numeric/logical arrays
    % - char / scalar string
    % - explicit attributes
    %
    % Unsupported:
    % - struct array
    % - string array
    % - table / datetime / categorical
    % - sparse / complex
    % - custom class objects

    properties
        Filename char
        Overwrite logical = true
    end

    properties (Access = private)
        CreatedGroups
    end

    methods
        function obj = HDF5DataStore(filename, varargin)
            if nargin < 1
                error('HDF5DataStore:InvalidInput', ...
                    'A target filename is required.');
            end

            obj.Filename = char(filename);

            if ~isempty(varargin)
                if mod(numel(varargin), 2) ~= 0
                    error('HDF5DataStore:InvalidInput', ...
                        'Name-value arguments must come in pairs.');
                end

                for i = 1:2:numel(varargin)
                    name = lower(string(varargin{i}));
                    value = varargin{i + 1};

                    switch name
                        case "overwrite"
                            obj.Overwrite = logical(value);
                        otherwise
                            error('HDF5DataStore:InvalidOption', ...
                                'Unknown option: %s', char(name));
                    end
                end
            end

            if obj.Overwrite && exist(obj.Filename, 'file') == 2
                delete(obj.Filename);
            end

            obj.resetGroupCache();
        end

        function write(obj, path, data)
            path = obj.normalizePath(path);

            if strcmp(path, '/')
                if exist(obj.Filename, 'file') == 2
                    delete(obj.Filename);
                end
                obj.resetGroupCache();
                obj.ensureRootExists();
                obj.writeNode(path, data);
                return;
            end

            obj.ensureRootExists();
            obj.deleteIfExists(path);
            obj.writeNode(path, data);
        end

        function data = read(obj, path)
            path = obj.normalizePath(path);

            if ~obj.pathExistsLowLevel(path)
                error('HDF5DataStore:PathNotFound', ...
                    'Path does not exist: %s', path);
            end

            data = obj.readNodeFast(path, obj.getObjectKind(path));
        end

        function data = load(obj)
            data = obj.read('/');
        end

        function tf = exists(obj, path)
            path = obj.normalizePath(path);
            tf = obj.pathExistsLowLevel(path);
        end

        function info = ls(obj, path)
            if nargin < 2
                path = '/';
            end
            path = obj.normalizePath(path);
            info = h5info(obj.Filename, path);
        end

        function attrs = readAttributes(obj, path)
            path = obj.normalizePath(path);
            info = h5info(obj.Filename, path);

            attrs = struct();
            for i = 1:numel(info.Attributes)
                name = info.Attributes(i).Name;
                attrs.(matlab.lang.makeValidName(name)) = ...
                    h5readatt(obj.Filename, path, name);
            end
        end

        function writeAttributes(obj, path, attrs)
            path = obj.normalizePath(path);

            if ~isstruct(attrs)
                error('HDF5DataStore:InvalidAttributes', ...
                    'Attributes must be a struct.');
            end

            if ~obj.pathExistsLowLevel(path)
                error('HDF5DataStore:PathNotFound', ...
                    'Cannot write attributes. Path does not exist: %s', path);
            end

            f = fieldnames(attrs);
            for i = 1:numel(f)
                obj.writeSingleAttribute(path, f{i}, attrs.(f{i}));
            end
        end
    end

    methods (Static)
        function save(filename, data, varargin)
            store = post.utils.HDF5DataStore(filename, varargin{:});
            store.write('/', data);
        end
    end

    methods (Access = private)
        %% ========================= Core dispatch =========================
        function writeNode(obj, path, data)
            if isstruct(data)
                obj.writeStructNode(path, data);

            elseif iscell(data)
                obj.writeCellNode(path, data);

            elseif isnumeric(data)
                obj.writeNumericNode(path, data);

            elseif islogical(data)
                obj.writeLogicalNode(path, data);

            elseif ischar(data)
                obj.writeCharNode(path, data);

            elseif isstring(data) && isscalar(data)
                obj.writeStringNode(path, data);

            else
                error('HDF5DataStore:UnsupportedType', ...
                    'Unsupported type: %s', class(data));
            end
        end

        function data = readNodeFast(obj, path, kind)
            if nargin < 3
                kind = obj.getObjectKind(path);
            end

            switch kind
                case 'group'
                    nodeType = obj.tryReadNodeType(path);
                    if nodeType == "cell"
                        data = obj.readCellNodeFast(path);
                    else
                        data = obj.readStructNodeFast(path);
                    end

                case 'dataset'
                    nodeType = obj.tryReadNodeType(path);
                    switch nodeType
                        case "logical"
                            data = obj.readLogicalNode(path);
                        case "char"
                            data = obj.readCharNode(path);
                        case "string"
                            data = obj.readStringNode(path);
                        otherwise
                            data = obj.readNumericNode(path);
                    end

                otherwise
                    error('HDF5DataStore:PathNotFound', ...
                        'Path does not exist: %s', path);
            end
        end

        %% ========================= Struct =========================
        function writeStructNode(obj, path, S)
            if ~isscalar(S)
                error('HDF5DataStore:UnsupportedStruct', ...
                    'Only scalar struct is supported.');
            end

            obj.createGroupFast(path);

            names = fieldnames(S);
            for i = 1:numel(names)
                name = names{i};
                obj.writeNode(obj.joinPath(path, name), S.(name));
            end
        end

        function S = readStructNodeFast(obj, path)
            info = h5info(obj.Filename, path);
            S = struct();

            for i = 1:numel(info.Groups)
                childPath = info.Groups(i).Name;
                [~, name] = fileparts(childPath);
                if startsWith(name, '__')
                    continue;
                end
                S.(name) = obj.readNodeFast(childPath, 'group');
            end

            for i = 1:numel(info.Datasets)
                name = info.Datasets(i).Name;
                if startsWith(name, '__')
                    continue;
                end
                childPath = obj.joinPath(path, name);
                S.(name) = obj.readNodeFast(childPath, 'dataset');
            end
        end

        %% ========================= Cell =========================
        function writeCellNode(obj, path, C)
            obj.createGroupFast(path);
            obj.writeSingleAttribute(path, 'node_type', 'cell');
            obj.writeSingleAttribute(path, 'cell_size', int64(size(C)));

            for k = 1:numel(C)
                childPath = obj.joinPath(path, sprintf('el_%d', k));
                obj.writeNode(childPath, C{k});
            end
        end

        function C = readCellNodeFast(obj, path)
            try
                sz = obj.normalizeSize(h5readatt(obj.Filename, path, 'cell_size'));
            catch
                info = h5info(obj.Filename, path);
                n = numel(info.Groups) + numel(info.Datasets);
                sz = [n, 1];
            end

            C = cell(sz);

            for k = 1:numel(C)
                childPath = obj.joinPath(path, sprintf('el_%d', k));
                C{k} = obj.readNodeFast(childPath, obj.getObjectKind(childPath));
            end
        end

        %% ========================= Numeric =========================
        function writeNumericNode(obj, path, x)
            if ~isreal(x)
                error('HDF5DataStore:UnsupportedNumeric', ...
                    'Complex arrays are not supported.');
            end
            obj.writePlainDataset(path, x, false, []);
        end

        function x = readNumericNode(obj, path)
            x = obj.readPlainDataset(path);
        end

        %% ========================= Logical =========================
        function writeLogicalNode(obj, path, x)
            obj.writePlainDataset(path, uint8(x), true, 'logical');
        end

        function x = readLogicalNode(obj, path)
            x = logical(obj.readPlainDataset(path));
        end

        %% ========================= Char =========================
        function writeCharNode(obj, path, x)
            obj.writePlainDataset(path, uint16(x), true, 'char');
            obj.writeSingleAttribute(path, 'char_size', int64(size(x)));
        end

        function x = readCharNode(obj, path)
            codes = obj.readPlainDataset(path);
            x = char(codes);

            try
                sz = obj.normalizeSize(h5readatt(obj.Filename, path, 'char_size'));
                x = reshape(x, sz);
            catch
            end
        end

        %% ========================= String =========================
        function writeStringNode(obj, path, x)
            obj.writePlainDataset(path, uint16(char(x)), true, 'string');
            obj.writeSingleAttribute(path, 'char_size', int64(size(char(x))));
        end

        function x = readStringNode(obj, path)
            chars = char(obj.readPlainDataset(path));
            try
                sz = obj.normalizeSize(h5readatt(obj.Filename, path, 'char_size'));
                chars = reshape(chars, sz);
            catch
            end
            x = string(chars);
        end

        %% ========================= Dataset helpers =========================
        function writePlainDataset(obj, path, x, writeTypeAttr, nodeType)
            parent = obj.parentPath(path);
            obj.createGroupFast(parent);

            if isempty(x)
                placeholder = obj.emptyPlaceholderLike(x);
                h5create(obj.Filename, path, [1 1], 'Datatype', class(placeholder));
                h5write(obj.Filename, path, placeholder);

                if writeTypeAttr
                    obj.writeSingleAttribute(path, 'node_type', nodeType);
                end
                obj.writeSingleAttribute(path, 'is_empty', true);
                obj.writeSingleAttribute(path, 'original_size', int64(size(x)));
                return;
            end

            h5create(obj.Filename, path, size(x), 'Datatype', class(x));
            h5write(obj.Filename, path, x);

            if writeTypeAttr
                obj.writeSingleAttribute(path, 'node_type', nodeType);
            end
        end

        function x = readPlainDataset(obj, path)
            raw = h5read(obj.Filename, path);

            try
                isEmpty = logical(h5readatt(obj.Filename, path, 'is_empty'));
            catch
                isEmpty = false;
            end

            if isEmpty
                sz = obj.normalizeSize(h5readatt(obj.Filename, path, 'original_size'));
                x = reshape(cast([], class(raw)), sz);
            else
                x = raw;
            end
        end

        %% ========================= Node/type helpers =========================
        function nodeType = tryReadNodeType(obj, path)
            try
                nodeType = string(h5readatt(obj.Filename, path, 'node_type'));
            catch
                nodeType = "numeric";
            end
        end

        function kind = getObjectKind(obj, path)
            if ~obj.pathExistsLowLevel(path)
                kind = 'missing';
                return;
            end

            fileId = H5F.open(obj.Filename, 'H5F_ACC_RDONLY', 'H5P_DEFAULT');
            c1 = onCleanup(@() H5F.close(fileId));

            objId = H5O.open(fileId, path, 'H5P_DEFAULT');
            c2 = onCleanup(@() H5O.close(objId));

            info = H5O.get_info(objId);

            switch info.type
                case H5ML.get_constant_value('H5O_TYPE_GROUP')
                    kind = 'group';
                case H5ML.get_constant_value('H5O_TYPE_DATASET')
                    kind = 'dataset';
                otherwise
                    kind = 'other';
            end
        end

        function tf = pathExistsLowLevel(obj, path)
            if exist(obj.Filename, 'file') ~= 2
                tf = false;
                return;
            end

            fileId = H5F.open(obj.Filename, 'H5F_ACC_RDONLY', 'H5P_DEFAULT');
            c1 = onCleanup(@() H5F.close(fileId));

            tf = H5L.exists(fileId, path, 'H5P_DEFAULT') > 0;
        end

        function sz = normalizeSize(~, value)
            value = double(value(:).');
            if isempty(value)
                sz = [0 0];
            else
                sz = round(value);
            end
        end

        %% ========================= Attribute helpers =========================
        function writeSingleAttribute(obj, path, name, value)
            if isstring(value)
                value = char(value);
            elseif islogical(value)
                value = uint8(value);
            end
            h5writeatt(obj.Filename, path, name, value);
        end

        %% ========================= Group creation/cache =========================
        function resetGroupCache(obj)
            obj.CreatedGroups = containers.Map('KeyType', 'char', 'ValueType', 'logical');
            obj.CreatedGroups('/') = true;
        end

        function createGroupFast(obj, groupPath)
            groupPath = obj.normalizePath(groupPath);

            if isKey(obj.CreatedGroups, groupPath)
                return;
            end

            if strcmp(groupPath, '/')
                obj.ensureRootExists();
                obj.CreatedGroups('/') = true;
                return;
            end

            parent = obj.parentPath(groupPath);
            obj.createGroupFast(parent);

            fileId = H5F.open(obj.Filename, 'H5F_ACC_RDWR', 'H5P_DEFAULT');
            c1 = onCleanup(@() H5F.close(fileId));

            gcpl = 'H5P_DEFAULT';
            gapl = 'H5P_DEFAULT';
            gid = H5G.create(fileId, groupPath, gcpl, gapl, gapl);
            H5G.close(gid);

            obj.CreatedGroups(groupPath) = true;
        end

        function ensureRootExists(obj)
            if exist(obj.Filename, 'file') ~= 2
                h5create(obj.Filename, '/__init__', [1 1], 'Datatype', 'uint8');
                h5write(obj.Filename, '/__init__', uint8(0));
                obj.lowLevelDelete('/__init__');
            end
            obj.CreatedGroups('/') = true;
        end

        %% ========================= Delete helpers =========================
        function deleteIfExists(obj, path)
            if strcmp(path, '/')
                return;
            end
            if ~obj.pathExistsLowLevel(path)
                return;
            end
            obj.lowLevelDelete(path);
        end

        function lowLevelDelete(obj, path)
            fileId = H5F.open(obj.Filename, 'H5F_ACC_RDWR', 'H5P_DEFAULT');
            c1 = onCleanup(@() H5F.close(fileId));

            parent = obj.parentPath(path);
            [~, name] = fileparts(path);

            parentId = H5G.open(fileId, parent);
            c2 = onCleanup(@() H5G.close(parentId));

            H5L.delete(parentId, name, 'H5P_DEFAULT');
        end

        %% ========================= Path helpers =========================
        function path = normalizePath(~, path)
            path = char(string(path));
            if isempty(path)
                path = '/';
            end
            if path(1) ~= '/'
                path = ['/' path];
            end
        end

        function path = joinPath(~, parentPath, childName)
            childName = char(childName);
            if strcmp(parentPath, '/')
                path = ['/' childName];
            else
                path = [parentPath '/' childName];
            end
        end

        function p = parentPath(~, path)
            if strcmp(path, '/')
                p = '/';
                return;
            end

            idx = find(path == '/', 1, 'last');
            if isempty(idx) || idx == 1
                p = '/';
            else
                p = path(1:idx-1);
            end
        end

        %% ========================= Empty placeholder =========================
        function x = emptyPlaceholderLike(~, value)
            if isa(value, 'double')
                x = 0;
            elseif isa(value, 'single')
                x = single(0);
            elseif isa(value, 'uint8')
                x = uint8(0);
            elseif isa(value, 'uint16')
                x = uint16(0);
            elseif isa(value, 'uint32')
                x = uint32(0);
            elseif isa(value, 'uint64')
                x = uint64(0);
            elseif isa(value, 'int8')
                x = int8(0);
            elseif isa(value, 'int16')
                x = int16(0);
            elseif isa(value, 'int32')
                x = int32(0);
            elseif isa(value, 'int64')
                x = int64(0);
            elseif isa(value, 'logical')
                x = uint8(0);
            else
                x = 0;
            end
        end
    end
end