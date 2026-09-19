classdef ResponseDataset
    %RESPONSEDATASET Collection of label-aware response variables.
    properties (SetAccess = private)
        Variables struct = struct()
        Paths string = strings(0, 1)
        Attributes struct = struct()
        SourceType string = "response"
        VariableKeys string = strings(0,1)
    end
    properties (Access=private)
        PathIndex
    end
    methods
        function obj = ResponseDataset(variables, paths, attributes, sourceType, variableKeys)
            %RESPONSEDATASET Construct a collection of labeled response variables.
            %
            % Parameters
            % ----------
            % variables : struct
            %     Internal storage of ``ResponseArray`` objects.
            % paths : string array
            %     Public dotted path for each variable.
            % attributes : struct, optional
            %     Dataset-level source metadata.
            % sourceType : string, optional
            %     Response family such as ``"nodal"`` or ``"element"``.
            % variableKeys : string array, optional
            %     Internal struct keys aligned with ``paths``.
            if nargin == 0, return; end
            obj.Variables = variables; obj.Paths = string(paths(:));
            if nargin >= 3, obj.Attributes = attributes; end
            if nargin >= 4, obj.SourceType = string(sourceType); end
            if nargin < 5
                variableKeys=string(fieldnames(variables));
            end
            obj.VariableKeys=string(variableKeys(:));
            if numel(obj.VariableKeys)~=numel(obj.Paths)
                error('post:xarray:ResponseDataset:MappingMismatch', ...
                    'Paths and variable keys must have the same length.');
            end
            obj.PathIndex=containers.Map('KeyType','char','ValueType','char');
            for i=1:numel(obj.Paths)
                obj.PathIndex(char(obj.Paths(i)))=char(obj.VariableKeys(i));
            end
        end
        function names = names(obj)
            %NAMES Return all available dotted variable paths.
            %
            % Returns
            % -------
            % names : string column vector
            %     Variable paths in dataset order.
            names = obj.Paths;
        end
        function tf = has(obj, name)
            %HAS Test whether a variable path exists.
            %
            % Parameters
            % ----------
            % name : string scalar
            %     Dotted variable path.
            %
            % Returns
            % -------
            % tf : logical scalar
            %     True when the path is present.
            tf=isscalar(string(name)) && ~isempty(obj.PathIndex) && ...
                isKey(obj.PathIndex,char(string(name)));
        end
        function value = get(obj, name)
            %GET Return a response variable by dotted path.
            %
            % Parameters
            % ----------
            % name : string scalar
            %     Dotted variable path, for example ``"disp.ux"``.
            %
            % Returns
            % -------
            % value : post.xarray.ResponseArray
            %     Requested labeled response variable.
            name=string(name);
            if ~isscalar(name) || isempty(obj.PathIndex) || ...
                    ~isKey(obj.PathIndex,char(name))
                error('post:ResponseDataset:UnknownVariable', ...
                    'Unknown variable "%s". Available: %s', name, strjoin(obj.Paths, ', '));
            end
            value=obj.Variables.(obj.PathIndex(char(name)));
        end
        function out=sel(obj,varargin)
            %SEL Select Dataset variables by coordinate values.
            %
            % Parameters
            % ----------
            % varargin : dimension/value pairs
            %     Coordinate selections followed optionally by
            %     ``"Method", "nearest"``.
            %
            % Returns
            % -------
            % out : post.xarray.ResponseDataset
            %     Dataset whose applicable variables have been selected.
            %
            % Notes
            % -----
            % Variables that do not contain a requested dimension are preserved.
            out=obj.selected_("sel",varargin);
        end
        function out=isel(obj,varargin)
            %ISEL Select Dataset variables by one-based positions.
            %
            % Parameters
            % ----------
            % varargin : dimension/index pairs
            %     MATLAB indices along named dimensions.
            %
            % Returns
            % -------
            % out : post.xarray.ResponseDataset
            %     Positionally selected Dataset.
            out=obj.selected_("isel",varargin);
        end
        function out=mean(obj,dim,varargin)
            %MEAN Compute the mean of variables containing a dimension.
            %
            % Parameters
            % ----------
            % dim : string scalar
            %     Dimension to reduce.
            % varargin : optional
            %     Options accepted by MATLAB ``mean``.
            %
            % Returns
            % -------
            % out : post.xarray.ResponseDataset
            %     Dataset with applicable variables reduced.
            out=obj.reduced_("mean",dim,varargin);
        end
        function out=sum(obj,dim,varargin)
            %SUM Sum variables containing a named dimension.
            %
            % Parameters
            % ----------
            % dim : string scalar
            %     Dimension to reduce.
            % varargin : optional
            %     Options accepted by MATLAB ``sum``.
            %
            % Returns
            % -------
            % out : post.xarray.ResponseDataset
            %     Dataset with applicable variables reduced.
            out=obj.reduced_("sum",dim,varargin);
        end
        function out=min(obj,dim,varargin)
            %MIN Minimize variables along a named dimension.
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
            % out : post.xarray.ResponseDataset
            %     Dataset with applicable variables reduced.
            out=obj.reduced_("min",dim,varargin);
        end
        function out=max(obj,dim,varargin)
            %MAX Maximize variables along a named dimension.
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
            % out : post.xarray.ResponseDataset
            %     Dataset with applicable variables reduced.
            out=obj.reduced_("max",dim,varargin);
        end
        function out=std(obj,dim,varargin)
            %STD Compute standard deviation along a named dimension.
            %
            % Parameters
            % ----------
            % dim : string scalar
            %     Dimension to reduce.
            % varargin : optional
            %     Options accepted by the array-level ``std`` method.
            %
            % Returns
            % -------
            % out : post.xarray.ResponseDataset
            %     Dataset with applicable variables reduced.
            out=obj.reduced_("std",dim,varargin);
        end
        function out=median(obj,dim,varargin)
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
            % out : post.xarray.ResponseDataset
            %     Dataset with applicable variables reduced.
            out=obj.reduced_("median",dim,varargin);
        end
        function out=squeeze(obj,varargin)
            %SQUEEZE Remove singleton dimensions from Dataset variables.
            %
            % Parameters
            % ----------
            % varargin : dimension names, optional
            %     Dimensions to remove. With no input, every variable drops
            %     all of its singleton dimensions.
            %
            % Returns
            % -------
            % out : post.xarray.ResponseDataset
            %     Dataset with compacted applicable variables.
            variables=obj.Variables; requested=string(varargin); matched=false(size(requested));
            for i=1:numel(obj.VariableKeys)
                key=char(obj.VariableKeys(i)); a=variables.(key);
                if isempty(requested)
                    variables.(key)=a.squeeze();
                else
                    local=requested(ismember(requested,a.Dimensions));
                    matched=matched | ismember(requested,a.Dimensions);
                    if ~isempty(local), variables.(key)=a.squeeze(local); end
                end
            end
            if any(~matched)
                error('post:xarray:ResponseDataset:UnknownDimension', ...
                    'No variable contains dimension "%s".',requested(find(~matched,1)));
            end
            out=obj.rebuilt_(variables);
        end
        function out=renameDimension(obj,oldName,newName)
            %RENAMEDIMENSION Rename a shared dimension across Dataset variables.
            %
            % Parameters
            % ----------
            % oldName : string scalar
            %     Existing dimension name.
            % newName : string scalar
            %     New dimension name.
            %
            % Returns
            % -------
            % out : post.xarray.ResponseDataset
            %     Dataset with updated applicable variables.
            oldName=string(oldName); variables=obj.Variables; matched=false;
            for i=1:numel(obj.VariableKeys)
                key=char(obj.VariableKeys(i)); a=variables.(key);
                if any(a.Dimensions==oldName)
                    variables.(key)=a.renameDimension(oldName,newName); matched=true;
                end
            end
            if ~matched
                error('post:xarray:ResponseDataset:UnknownDimension', ...
                    'No variable contains dimension "%s".',oldName);
            end
            out=obj.rebuilt_(variables);
        end
        function out=rename(obj,oldName,newName)
            %RENAME Alias for ``renameDimension``.
            out=obj.renameDimension(oldName,newName);
        end
        function out=assignCoordinates(obj,dim,values)
            %ASSIGNCOORDINATES Replace shared dimension coordinates.
            %
            % Parameters
            % ----------
            % dim : string scalar
            %     Dimension whose coordinates are replaced.
            % values : vector
            %     New coordinate values.
            %
            % Returns
            % -------
            % out : post.xarray.ResponseDataset
            %     Dataset with updated applicable variables.
            dim=string(dim); variables=obj.Variables; matched=false;
            for i=1:numel(obj.VariableKeys)
                key=char(obj.VariableKeys(i)); a=variables.(key);
                if any(a.Dimensions==dim)
                    variables.(key)=a.assignCoordinates(dim,values); matched=true;
                end
            end
            if ~matched
                error('post:xarray:ResponseDataset:UnknownDimension', ...
                    'No variable contains dimension "%s".',dim);
            end
            out=obj.rebuilt_(variables);
        end
        function out=assignCoords(obj,dim,values)
            %ASSIGNCOORDS Alias for ``assignCoordinates``.
            out=obj.assignCoordinates(dim,values);
        end
        function out = subsref(obj, s)
            %SUBSREF Support string and dotted-path variable access.
            if strcmp(s(1).type, '()') && isscalar(s(1).subs) && ...
                    (ischar(s(1).subs{1}) || isstring(s(1).subs{1}))
                out = obj.get(s(1).subs{1});
                if numel(s)>1, out = builtin('subsref', out, s(2:end)); end
            elseif strcmp(s(1).type,'.')
                [path,nUsed]=obj.matchDotPath_(s);
                if nUsed>0
                    out=obj.get(path);
                    if nUsed<numel(s), out=subsref(out,s(nUsed+1:end)); end
                else
                    out=builtin('subsref',obj,s);
                end
            else, out = builtin('subsref', obj, s);
            end
        end
        function disp(obj)
            %DISP Display the Dataset source type and variable paths.
            fprintf('post.xarray.ResponseDataset (%s) with %d variables\n', obj.SourceType, numel(obj.Paths));
            for i=1:numel(obj.Paths), fprintf('  %s\n', obj.Paths(i)); end
        end
    end
    methods (Access=private)
        function out=selected_(obj,kind,args)
            [pairs,method]=datasetSelectionArgs_(args);
            variables=obj.Variables; matched=false(size(pairs,1),1);
            for i=1:numel(obj.VariableKeys)
                key=char(obj.VariableKeys(i)); a=variables.(key); selected={};
                for k=1:size(pairs,1)
                    if any(a.Dimensions==string(pairs{k,1}))
                        selected(end+1:end+2)=pairs(k,:);
                        matched(k)=true;
                    end
                end
                if ~isempty(selected)
                    if kind=="sel" && method~="exact"
                        selected(end+1:end+2)={'Method',method};
                    end
                    variables.(key)=feval(char(kind),a,selected{:});
                end
            end
            if any(~matched)
                missing=string(pairs(find(~matched,1),1));
                error('post:xarray:ResponseDataset:UnknownDimension', ...
                    'No variable contains dimension "%s".',missing);
            end
            out=obj.rebuilt_(variables);
        end
        function out=reduced_(obj,operation,dim,args)
            dim=string(dim); variables=obj.Variables; matched=false;
            for i=1:numel(obj.VariableKeys)
                key=char(obj.VariableKeys(i)); a=variables.(key);
                if any(a.Dimensions==dim)
                    variables.(key)=feval(char(operation),a,dim,args{:});
                    matched=true;
                end
            end
            if ~matched
                error('post:xarray:ResponseDataset:UnknownDimension', ...
                    'No variable contains dimension "%s".',dim);
            end
            out=obj.rebuilt_(variables);
        end
        function out=rebuilt_(obj,variables)
            out=post.xarray.ResponseDataset(variables,obj.Paths,obj.Attributes, ...
                obj.SourceType,obj.VariableKeys);
        end
        function [path,nUsed]=matchDotPath_(obj,s)
            path=""; nUsed=0; parts=strings(0,1);
            for i=1:numel(s)
                if ~strcmp(s(i).type,'.'), break; end
                parts(end+1,1)=string(s(i).subs); %#ok<AGROW>
                candidate=join(parts,'.');
                if obj.has(candidate), path=candidate; nUsed=i; end
            end
        end
    end
    methods (Static)
        function obj = fromStruct(response)
            %FROMSTRUCT Create a labeled Dataset from a response struct.
            %
            % Parameters
            % ----------
            % response : struct
            %     Nodal, element, or FEMData response structure.
            %
            % Returns
            % -------
            % obj : post.xarray.ResponseDataset
            %     Label-aware, non-mutating response view.
            obj = post.toResponseDataset(response);
        end
    end
end

function [pairs,method]=datasetSelectionArgs_(args)
method="exact";
if mod(numel(args),2)~=0
    error('post:xarray:ResponseDataset:NameValue','Use dimension/value pairs.');
end
pairs=cell(0,2);
for i=1:2:numel(args)
    if strcmpi(string(args{i}),"Method"), method=lower(string(args{i+1}));
    else, pairs(end+1,:)={args{i},args{i+1}}; %#ok<AGROW>
    end
end
end
