classdef ResponseArray
    %RESPONSEARRAY Label-aware view of one response array.
    properties (SetAccess = private)
        Data
        Dimensions string = strings(1, 0)
        Coordinates struct = struct()
        Name string = ""
        Attributes struct = struct()
    end
    methods
        function obj = ResponseArray(data, dimensions, coordinates, name, attributes)
            if nargin == 0, return; end
            obj.Data = data;
            obj.Dimensions = string(dimensions(:)).';
            obj.Coordinates = coordinates;
            if nargin >= 4, obj.Name = string(name); end
            if nargin >= 5, obj.Attributes = attributes; end
            % MATLAB removes trailing singleton dimensions from ndims/size.
            % A labeled [time x element x section] selection can therefore
            % physically appear as [time x 1] while its logical rank is 3.
            % Reject only real, non-singleton axes beyond the labeled rank.
            labeledRank = numel(obj.Dimensions);
            physicalSize = size(data);
            if labeledRank == 0 || numel(unique(obj.Dimensions))~=labeledRank || ...
                    (numel(physicalSize) > labeledRank && ...
                     any(physicalSize(labeledRank+1:end) ~= 1))
                error('post:ResponseArray:DimensionMismatch', ...
                    'Dimension labels must be unique and cover all non-singleton data axes.');
            end
            for d=1:labeledRank
                field=char(matlab.lang.makeValidName(obj.Dimensions(d)));
                if isfield(obj.Coordinates,field) && ...
                        numel(obj.Coordinates.(field))~=size(data,d)
                    error('post:ResponseArray:CoordinateMismatch', ...
                        'Coordinate "%s" must contain %d values.', ...
                        obj.Dimensions(d),size(data,d));
                end
            end
        end
        function out = sel(obj, varargin)
            [pairs, method] = selectionArgs_(varargin);
            indices = repmat({':'}, 1, numel(obj.Dimensions));
            for k = 1:size(pairs, 1)
                dim = string(pairs{k, 1});
                pos = find(obj.Dimensions == dim, 1);
                if isempty(pos), error('post:ResponseArray:UnknownDimension', 'Unknown dimension "%s".', dim); end
                field = char(matlab.lang.makeValidName(dim));
                if ~isfield(obj.Coordinates, field)
                    error('post:ResponseArray:MissingCoordinate', 'Dimension "%s" has no coordinates.', dim);
                end
                indices{pos} = coordinateIndices_(obj.Coordinates.(field), pairs{k, 2}, method);
            end
            out = obj.indexed_(indices);
        end
        function out = isel(obj, varargin)
            [pairs, ~] = selectionArgs_(varargin);
            indices = repmat({':'}, 1, numel(obj.Dimensions));
            for k = 1:size(pairs, 1)
                dim = string(pairs{k, 1});
                pos = find(obj.Dimensions == dim, 1);
                if isempty(pos), error('post:ResponseArray:UnknownDimension', 'Unknown dimension "%s".', dim); end
                indices{pos} = pairs{k, 2};
            end
            out = obj.indexed_(indices);
        end
        function a = toArray(obj), a = obj.Data; end
        function out = subsref(obj, s)
            if strcmp(s(1).type,'.')
                dim=string(s(1).subs);
                pos=find(obj.Dimensions==dim,1);
                field=char(matlab.lang.makeValidName(dim));
                if ~isempty(pos) && isfield(obj.Coordinates,field)
                    out=obj.Coordinates.(field);
                    if numel(s)>1, out=builtin('subsref',out,s(2:end)); end
                    return
                end
            end
            out=builtin('subsref',obj,s);
        end
        function s = toStruct(obj)
            s = struct('name', obj.Name, 'data', obj.Data, ...
                'dimensions', obj.Dimensions, 'coordinates', obj.Coordinates, ...
                'attributes', obj.Attributes);
        end
        function t = toTable(obj)
            if numel(obj.Dimensions) > 2
                error('post:ResponseArray:TableRank', ...
                    'toTable supports arrays with at most two dimensions.');
            end
            if isvector(obj.Data)
                t = table(obj.Data(:), 'VariableNames', matlab.lang.makeValidName(obj.Name));
            else
                t = array2table(obj.Data);
            end
            d1 = char(matlab.lang.makeValidName(obj.Dimensions(1)));
            if isfield(obj.Coordinates, d1) && height(t) == numel(obj.Coordinates.(d1))
                t = addvars(t, obj.Coordinates.(d1)(:), 'Before', 1, 'NewVariableNames', d1);
            end
        end
        function disp(obj)
            fprintf('post.ResponseArray "%s"\n', obj.Name);
            fprintf('  Size: %s\n', mat2str(size(obj.Data)));
            fprintf('  Dimensions: %s\n', strjoin(obj.Dimensions, ', '));
        end
    end
    methods (Access = private)
        function out = indexed_(obj, indices)
            data = obj.Data(indices{:});
            coords = obj.Coordinates;
            for i = 1:numel(indices)
                field = char(matlab.lang.makeValidName(obj.Dimensions(i)));
                if isfield(coords, field) && ~isequal(indices{i}, ':')
                    c = coords.(field); coords.(field) = c(indices{i});
                end
            end
            out = post.ResponseArray(data, obj.Dimensions, coords, obj.Name, obj.Attributes);
        end
    end
end

function [pairs, method] = selectionArgs_(args)
method = "exact";
if mod(numel(args), 2) ~= 0, error('post:ResponseArray:NameValue', 'Use dimension/value pairs.'); end
pairs = cell(0, 2);
for i = 1:2:numel(args)
    name = string(args{i});
    if strcmpi(name, 'Method'), method = lower(string(args{i+1}));
    else, pairs(end+1, :) = {name, args{i+1}}; %#ok<AGROW>
    end
end
end

function idx = coordinateIndices_(coord, query, method)
coord = coord(:); query = query(:);
if method == "nearest"
    if ~isnumeric(coord) || ~isnumeric(query), error('post:ResponseArray:NearestNumeric', 'Nearest requires numeric coordinates.'); end
    idx = zeros(numel(query), 1);
    for i = 1:numel(query), [~, idx(i)] = min(abs(coord-query(i))); end
else
    [tf, idx] = ismember(query, coord);
    if any(~tf), error('post:ResponseArray:CoordinateNotFound', 'Coordinate value was not found.'); end
end
end
