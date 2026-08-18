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
            %RESPONSEARRAY Construct a labeled response array.
            %
            % Parameters
            % ----------
            % data : numeric or logical array
            %     Response values.
            % dimensions : string array
            %     Ordered name of each logical data dimension.
            % coordinates : struct
            %     Coordinate vectors keyed by valid dimension names.
            % name : string, optional
            %     Variable path or display name.
            % attributes : struct, optional
            %     Source metadata carried with the array.
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
            if (labeledRank == 0 && ~isscalar(data)) || ...
                    numel(unique(obj.Dimensions))~=labeledRank || ...
                    (numel(physicalSize) > labeledRank && ...
                     any(physicalSize(labeledRank+1:end) ~= 1))
                error('post:xarray:ResponseArray:DimensionMismatch', ...
                    'Dimension labels must be unique and cover all non-singleton data axes.');
            end
            for d=1:labeledRank
                field=char(matlab.lang.makeValidName(obj.Dimensions(d)));
                if isfield(obj.Coordinates,field) && ...
                        numel(obj.Coordinates.(field))~=size(data,d)
                    error('post:xarray:ResponseArray:CoordinateMismatch', ...
                        'Coordinate "%s" must contain %d values.', ...
                        obj.Dimensions(d),size(data,d));
                end
            end
        end
        function out = sel(obj, varargin)
            %SEL Select data by coordinate values.
            %
            % Parameters
            % ----------
            % varargin : dimension/value pairs
            %     Coordinate selections followed optionally by
            %     ``"Method", "nearest"``.
            %
            % Returns
            % -------
            % out : post.xarray.ResponseArray
            %     Selected array with matching coordinates.
            %
            % Examples
            % --------
            % ``out = a.sel("node", 18, "time", 1.2)``
            [pairs, method] = selectionArgs_(varargin);
            indices = repmat({':'}, 1, numel(obj.Dimensions));
            for k = 1:size(pairs, 1)
                dim = string(pairs{k, 1});
                pos = find(obj.Dimensions == dim, 1);
                if isempty(pos), error('post:xarray:ResponseArray:UnknownDimension', 'Unknown dimension "%s".', dim); end
                field = char(matlab.lang.makeValidName(dim));
                if ~isfield(obj.Coordinates, field)
                    error('post:xarray:ResponseArray:MissingCoordinate', 'Dimension "%s" has no coordinates.', dim);
                end
                indices{pos} = coordinateIndices_(obj.Coordinates.(field), pairs{k, 2}, method);
            end
            out = obj.indexed_(indices);
        end
        function out = isel(obj, varargin)
            %ISEL Select data by one-based dimension positions.
            %
            % Parameters
            % ----------
            % varargin : dimension/index pairs
            %     MATLAB indices for one or more named dimensions.
            %
            % Returns
            % -------
            % out : post.xarray.ResponseArray
            %     Positionally selected array.
            [pairs, ~] = selectionArgs_(varargin);
            indices = repmat({':'}, 1, numel(obj.Dimensions));
            for k = 1:size(pairs, 1)
                dim = string(pairs{k, 1});
                pos = find(obj.Dimensions == dim, 1);
                if isempty(pos), error('post:xarray:ResponseArray:UnknownDimension', 'Unknown dimension "%s".', dim); end
                indices{pos} = pairs{k, 2};
            end
            out = obj.indexed_(indices);
        end
        function a = toArray(obj)
            %TOARRAY Return the underlying MATLAB array.
            %
            % Returns
            % -------
            % a : numeric or logical array
            %     Unlabeled response values.
            a = obj.Data;
        end
        function s = sizes(obj)
            %SIZES Return logical dimension sizes by name.
            %
            % Returns
            % -------
            % s : struct
            %     Scalar struct whose fields are dimension names.
            s=struct();
            for d=1:numel(obj.Dimensions)
                s.(char(matlab.lang.makeValidName(obj.Dimensions(d))))=size(obj.Data,d);
            end
        end
        function c = coordinate(obj,dim)
            %COORDINATE Return the coordinate vector of a dimension.
            %
            % Parameters
            % ----------
            % dim : string scalar
            %     Dimension name.
            %
            % Returns
            % -------
            % c : array
            %     Coordinate values in storage order.
            dim=string(dim); pos=obj.dimensionPosition_(dim); %#ok<NASGU>
            field=char(matlab.lang.makeValidName(dim));
            if ~isfield(obj.Coordinates,field)
                error('post:xarray:ResponseArray:MissingCoordinate', ...
                    'Dimension "%s" has no coordinates.',dim);
            end
            c=obj.Coordinates.(field);
        end
        function out = mean(obj,dim,varargin)
            %MEAN Compute the mean along a named dimension.
            %
            % Parameters
            % ----------
            % dim : string scalar
            %     Dimension to remove by averaging.
            % varargin : optional
            %     Options accepted by MATLAB ``mean``, such as ``"omitmissing"``.
            %
            % Returns
            % -------
            % out : post.xarray.ResponseArray
            %     Reduced array with the remaining coordinates.
            out=obj.reduced_("mean",dim,varargin{:});
        end
        function out = sum(obj,dim,varargin)
            %SUM Compute the sum along a named dimension.
            %
            % Parameters
            % ----------
            % dim : string scalar
            %     Dimension to remove by summation.
            % varargin : optional
            %     Options accepted by MATLAB ``sum``.
            %
            % Returns
            % -------
            % out : post.xarray.ResponseArray
            %     Reduced array.
            out=obj.reduced_("sum",dim,varargin{:});
        end
        function out = min(obj,dim,varargin)
            %MIN Compute the minimum along a named dimension.
            %
            % Parameters
            % ----------
            % dim : string scalar
            %     Dimension to reduce.
            % varargin : optional
            %     Options accepted by MATLAB ``min``.
            %
            % Returns
            % -------
            % out : post.xarray.ResponseArray
            %     Reduced array.
            out=obj.reduced_("min",dim,varargin{:});
        end
        function out = max(obj,dim,varargin)
            %MAX Compute the maximum along a named dimension.
            %
            % Parameters
            % ----------
            % dim : string scalar
            %     Dimension to reduce.
            % varargin : optional
            %     Options accepted by MATLAB ``max``.
            %
            % Returns
            % -------
            % out : post.xarray.ResponseArray
            %     Reduced array.
            out=obj.reduced_("max",dim,varargin{:});
        end
        function out = std(obj,dim,varargin)
            %STD Compute standard deviation along a named dimension.
            %
            % Parameters
            % ----------
            % dim : string scalar
            %     Dimension to reduce.
            % varargin : optional
            %     Options accepted after the dimension by MATLAB ``std``.
            %
            % Returns
            % -------
            % out : post.xarray.ResponseArray
            %     Reduced array.
            out=obj.reduced_("std",dim,varargin{:});
        end
        function out = median(obj,dim,varargin)
            %MEDIAN Compute the median along a named dimension.
            %
            % Parameters
            % ----------
            % dim : string scalar
            %     Dimension to reduce.
            % varargin : optional
            %     Options accepted by MATLAB ``median``.
            %
            % Returns
            % -------
            % out : post.xarray.ResponseArray
            %     Reduced array.
            out=obj.reduced_("median",dim,varargin{:});
        end
        function out = any(obj,dim,varargin)
            %ANY Test whether any value is true along a named dimension.
            %
            % Parameters
            % ----------
            % dim : string scalar
            %     Dimension to reduce.
            % varargin : optional
            %     Options accepted by MATLAB ``any``.
            %
            % Returns
            % -------
            % out : post.xarray.ResponseArray
            %     Logical reduced array.
            out=obj.reduced_("any",dim,varargin{:});
        end
        function out = all(obj,dim,varargin)
            %ALL Test whether all values are true along a named dimension.
            %
            % Parameters
            % ----------
            % dim : string scalar
            %     Dimension to reduce.
            % varargin : optional
            %     Options accepted by MATLAB ``all``.
            %
            % Returns
            % -------
            % out : post.xarray.ResponseArray
            %     Logical reduced array.
            out=obj.reduced_("all",dim,varargin{:});
        end
        function out = transpose(obj,varargin)
            %TRANSPOSE Reorder dimensions without changing coordinate values.
            %
            % Parameters
            % ----------
            % varargin : string array or dimension names, optional
            %     Complete new dimension order. With no input, the current
            %     order is reversed.
            %
            % Returns
            % -------
            % out : post.xarray.ResponseArray
            %     Array with permuted data and dimensions.
            if isempty(varargin)
                order=fliplr(obj.Dimensions);
            elseif isscalar(varargin)
                order=string(varargin{1}); order=order(:).';
            else
                order=string(varargin);
            end
            if numel(order)~=numel(obj.Dimensions) || ...
                    ~all(ismember(order,obj.Dimensions)) || numel(unique(order))~=numel(order)
                error('post:xarray:ResponseArray:InvalidPermutation', ...
                    'The order must contain every dimension exactly once.');
            end
            axes=zeros(1,numel(order));
            for i=1:numel(order), axes(i)=obj.dimensionPosition_(order(i)); end
            data=permute(obj.Data,axes);
            out=post.xarray.ResponseArray(data,order,obj.Coordinates,obj.Name,obj.Attributes);
        end
        function out = squeeze(obj,varargin)
            %SQUEEZE Remove singleton logical dimensions.
            %
            % Parameters
            % ----------
            % varargin : dimension names, optional
            %     Singleton dimensions to remove. With no input, all
            %     singleton dimensions are removed.
            %
            % Returns
            % -------
            % out : post.xarray.ResponseArray
            %     Array with the selected singleton dimensions removed.
            if isempty(varargin)
                remove=obj.Dimensions(arrayfun(@(d) size(obj.Data,d)==1,1:numel(obj.Dimensions)));
            else
                remove=string(varargin); remove=remove(:).';
                for dim=remove
                    pos=obj.dimensionPosition_(dim);
                    if size(obj.Data,pos)~=1
                        error('post:xarray:ResponseArray:NonSingletonDimension', ...
                            'Dimension "%s" is not singleton.',dim);
                    end
                end
            end
            keep=~ismember(obj.Dimensions,remove);
            newDims=obj.Dimensions(keep); coords=obj.Coordinates;
            for dim=remove
                field=char(matlab.lang.makeValidName(dim));
                if isfield(coords,field), coords=rmfield(coords,field); end
            end
            data=reshapeLogical_(obj.Data,arrayfun(@(d) size(obj.Data,d),find(keep)));
            out=post.xarray.ResponseArray(data,newDims,coords,obj.Name,obj.Attributes);
        end
        function out = renameDimension(obj,oldName,newName)
            %RENAMEDIMENSION Rename one dimension and its coordinate field.
            %
            % Parameters
            % ----------
            % oldName : string scalar
            %     Existing dimension name.
            % newName : string scalar
            %     New unique dimension name.
            %
            % Returns
            % -------
            % out : post.xarray.ResponseArray
            %     Array with updated labels.
            oldName=string(oldName); newName=string(newName);
            pos=obj.dimensionPosition_(oldName);
            if any(obj.Dimensions==newName)
                error('post:xarray:ResponseArray:DuplicateDimension','Dimension "%s" already exists.',newName);
            end
            dims=obj.Dimensions; dims(pos)=newName; coords=obj.Coordinates;
            oldField=char(matlab.lang.makeValidName(oldName));
            newField=char(matlab.lang.makeValidName(newName));
            if isfield(coords,oldField)
                coords.(newField)=coords.(oldField); coords=rmfield(coords,oldField);
            end
            out=post.xarray.ResponseArray(obj.Data,dims,coords,obj.Name,obj.Attributes);
        end
        function out = rename(obj,oldName,newName)
            %RENAME Alias for ``renameDimension``.
            out=obj.renameDimension(oldName,newName);
        end
        function out = assignCoordinates(obj,dim,values)
            %ASSIGNCOORDINATES Replace coordinates for a named dimension.
            %
            % Parameters
            % ----------
            % dim : string scalar
            %     Dimension whose coordinates are replaced.
            % values : vector
            %     New coordinate values; length must equal the dimension size.
            %
            % Returns
            % -------
            % out : post.xarray.ResponseArray
            %     Array with updated coordinates.
            dim=string(dim); pos=obj.dimensionPosition_(dim);
            if numel(values)~=size(obj.Data,pos)
                error('post:xarray:ResponseArray:CoordinateMismatch', ...
                    'Coordinate "%s" must contain %d values.',dim,size(obj.Data,pos));
            end
            coords=obj.Coordinates;
            coords.(char(matlab.lang.makeValidName(dim)))=values(:);
            out=post.xarray.ResponseArray(obj.Data,obj.Dimensions,coords,obj.Name,obj.Attributes);
        end
        function out = assignCoords(obj,dim,values)
            %ASSIGNCOORDS Alias for ``assignCoordinates``.
            out=obj.assignCoordinates(dim,values);
        end
        function out = where(obj,condition,other)
            %WHERE Replace values where a condition is false.
            %
            % Parameters
            % ----------
            % condition : logical array or post.xarray.ResponseArray
            %     Scalar condition or mask matching the data size.
            % other : scalar or array, optional
            %     Replacement value. Default is ``NaN``.
            %
            % Returns
            % -------
            % out : post.xarray.ResponseArray
            %     Masked array with unchanged dimensions and coordinates.
            if nargin<3, other=NaN; end
            if isa(condition,'post.xarray.ResponseArray')
                if ~isequal(condition.Dimensions,obj.Dimensions)
                    error('post:xarray:ResponseArray:Alignment', ...
                        'Condition dimensions must match the response array.');
                end
                condition=condition.Data;
            end
            if ~isequal(size(condition),size(obj.Data)) && ~isscalar(condition)
                error('post:xarray:ResponseArray:ConditionSize', ...
                    'Condition must be scalar or match the data size.');
            end
            if ~isscalar(other) && ~isequal(size(other),size(obj.Data))
                error('post:xarray:ResponseArray:ReplacementSize', ...
                    'Replacement must be scalar or match the data size.');
            end
            data=obj.Data;
            if isscalar(condition)
                if ~condition
                    if isscalar(other), data(:)=other;
                    else, data=other;
                    end
                end
            else
                if isscalar(other), data(~condition)=other;
                else, data(~condition)=other(~condition);
                end
            end
            out=post.xarray.ResponseArray(data,obj.Dimensions,obj.Coordinates,obj.Name,obj.Attributes);
        end
        function out = subsref(obj, s)
            %SUBSREF Support direct coordinate access such as ``a.time``.
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
            %TOSTRUCT Convert data, dimensions, coordinates, and metadata to a struct.
            %
            % Returns
            % -------
            % s : struct
            %     Portable labeled-array representation.
            s = struct('name', obj.Name, 'data', obj.Data, ...
                'dimensions', obj.Dimensions, 'coordinates', obj.Coordinates, ...
                'attributes', obj.Attributes);
        end
        function t = toTable(obj)
            %TOTABLE Convert a scalar, vector, or matrix response to a table.
            %
            % Returns
            % -------
            % t : table
            %     Tabular response values with the first coordinate when available.
            %
            % Notes
            % -----
            % Arrays with more than two logical dimensions are not supported.
            variableName=matlab.lang.makeValidName(obj.Name);
            if isempty(obj.Dimensions)
                t=table(obj.Data,'VariableNames',variableName);
                return
            end
            if numel(obj.Dimensions) > 2
                error('post:xarray:ResponseArray:TableRank', ...
                    'toTable supports arrays with at most two dimensions.');
            end
            if isvector(obj.Data)
                t = table(obj.Data(:), 'VariableNames', variableName);
            else
                t = array2table(obj.Data);
            end
            d1 = char(matlab.lang.makeValidName(obj.Dimensions(1)));
            if isfield(obj.Coordinates, d1) && height(t) == numel(obj.Coordinates.(d1))
                t = addvars(t, obj.Coordinates.(d1)(:), 'Before', 1, 'NewVariableNames', d1);
            end
        end
        function disp(obj)
            %DISP Display the response name, physical size, and dimension names.
            fprintf('post.xarray.ResponseArray "%s"\n', obj.Name);
            fprintf('  Size: %s\n', mat2str(size(obj.Data)));
            fprintf('  Dimensions: %s\n', strjoin(obj.Dimensions, ', '));
        end
    end
    methods (Access = private)
        function pos=dimensionPosition_(obj,dim)
            pos=find(obj.Dimensions==string(dim),1);
            if isempty(pos)
                error('post:xarray:ResponseArray:UnknownDimension','Unknown dimension "%s".',string(dim));
            end
        end
        function out=reduced_(obj,operation,dim,varargin)
            axis=obj.dimensionPosition_(dim);
            switch operation
                case {"min","max"}
                    data=feval(char(operation),obj.Data,[],axis,varargin{:});
                case "std"
                    data=std(obj.Data,0,axis,varargin{:});
                otherwise
                    data=feval(char(operation),obj.Data,axis,varargin{:});
            end
            keep=true(1,numel(obj.Dimensions)); keep(axis)=false;
            dims=obj.Dimensions(keep); coords=obj.Coordinates;
            field=char(matlab.lang.makeValidName(obj.Dimensions(axis)));
            if isfield(coords,field), coords=rmfield(coords,field); end
            shape=arrayfun(@(d) size(obj.Data,d),find(keep));
            data=reshapeLogical_(data,shape);
            attrs=obj.Attributes; attrs.reduction=operation; attrs.reducedDimension=string(dim);
            out=post.xarray.ResponseArray(data,dims,coords,obj.Name,attrs);
        end
        function out = indexed_(obj, indices)
            data = obj.Data(indices{:});
            coords = obj.Coordinates;
            for i = 1:numel(indices)
                field = char(matlab.lang.makeValidName(obj.Dimensions(i)));
                if isfield(coords, field) && ~isequal(indices{i}, ':')
                    c = coords.(field); coords.(field) = c(indices{i});
                end
            end
            out = post.xarray.ResponseArray(data, obj.Dimensions, coords, obj.Name, obj.Attributes);
        end
    end
end

function data=reshapeLogical_(data,shape)
if isempty(shape), data=reshape(data,1,1);
elseif isscalar(shape), data=reshape(data,shape(1),1);
else, data=reshape(data,shape);
end
end

function [pairs, method] = selectionArgs_(args)
method = "exact";
if mod(numel(args), 2) ~= 0, error('post:xarray:ResponseArray:NameValue', 'Use dimension/value pairs.'); end
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
    if ~isnumeric(coord) || ~isnumeric(query), error('post:xarray:ResponseArray:NearestNumeric', 'Nearest requires numeric coordinates.'); end
    idx = zeros(numel(query), 1);
    for i = 1:numel(query), [~, idx(i)] = min(abs(coord-query(i))); end
else
    [tf, idx] = ismember(query, coord);
    if any(~tf), error('post:xarray:ResponseArray:CoordinateNotFound', 'Coordinate value was not found.'); end
end
end
