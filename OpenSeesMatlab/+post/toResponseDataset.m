function ds = toResponseDataset(response)
%TORESPONSEDATASET Create a labeled, non-mutating view of response structs.
%   DS = post.toResponseDataset(RESPONSE)
%   R  = DS("disp.ux")
%   U  = R.sel("node", 12, "time", 1.0, "Method", "nearest")

arguments
    response struct
end

wasArray = ~isscalar(response);
if wasArray, merged = post.utils.ResponseStructTransformer.merge(response);
else, merged = response;
end

meta = {'odbTag','eleType','time','nodeTags','eleTags','responseSchema'};
attrs = struct('segmentCount', numel(response), 'mergedSegments', wasArray);
for i=1:numel(meta)
    if isfield(merged,meta{i}), attrs.(meta{i})=merged.(meta{i}); end
end
coords=struct();
if isfield(merged,'time'), coords.time=merged.time(:); end
if isfield(merged,'nodeTags'), coords.node=merged.nodeTags(:); end
if isfield(merged,'eleTags'), coords.element=merged.eleTags(:); end

variables=struct(); paths=strings(0,1);
[variables,paths]=collect_(merged,"",coords,attrs,variables,paths,struct());
sourceType="response";
if isfield(merged,'nodeTags') && ~isfield(merged,'eleTags'), sourceType="nodal"; end
if isfield(merged,'eleTags'), sourceType="element"; end
ds=post.ResponseDataset(variables,paths,attrs,sourceType);
end

function [variables,paths]=collect_(s,prefix,coords,attrs,variables,paths,schema)
skip={'odbTag','eleType','time','nodeTags','eleTags','dofs','responseSchema'};
names=fieldnames(s); localDofs=[];
if isfield(s,'dofs'), localDofs=s.dofs; end
if isfield(s,'responseSchema'), schema=s.responseSchema; end
if isfield(s,'time'), coords.time=s.time(:); end
if isfield(s,'nodeTags'), coords.node=s.nodeTags(:); end
if isfield(s,'eleTags'), coords.element=s.eleTags(:); end
if isfield(s,'ElementTags'), coords.element=s.ElementTags(:); end
for i=1:numel(names)
    name=names{i}; if ismember(name,skip), continue; end
    value=s.(name); path=string(name);
    if strlength(prefix)>0, path=prefix+"."+path; end
    if isstruct(value) && isscalar(value)
        [variables,paths]=collect_(value,path,coords,attrs,variables,paths,schema);
    elseif (isnumeric(value)||islogical(value)) && ~isempty(value)
        schemaPath=path;
        if isfield(attrs,'eleType') && ~isempty(attrs.eleType)
            schemaPath=string(attrs.eleType)+"Responses."+path;
        end
        dims=schemaDimensions_(schema,path,value);
        if isempty(dims)
            [dims,varCoords]=post.utils.ResponseSchema.dimensions(schemaPath,value,coords,localDofs);
        else
            varCoords=coordinates_(dims,value,coords,localDofs);
        end
        base=matlab.lang.makeValidName(char(replace(path,'.','_')));
        key=matlab.lang.makeUniqueStrings(base,fieldnames(variables));
        varAttrs=attrs; varAttrs.path=path;
        variables.(key)=post.ResponseArray(value,dims,varCoords,path,varAttrs);
        paths(end+1,1)=path; %#ok<AGROW>
    end
end
end

function dims=schemaDimensions_(schema,path,value)
dims=strings(1,0);
if ~isstruct(schema) || ~isfield(schema,'paths') || ~isfield(schema,'dimensions'), return; end
schemaPaths=string(schema.paths(:));
relativePath=string(path);
idx=find(schemaPaths==relativePath,1);
if isempty(idx)
    parts=split(relativePath,'.');
    for first=2:numel(parts)
        idx=find(schemaPaths==join(parts(first:end),'.'),1);
        if ~isempty(idx), break; end
    end
end
if isempty(idx), return; end
raw=schema.dimensions;
if iscell(raw), raw=raw{idx}; end
dims=string(raw(:)).';
physicalSize=size(value);
if isempty(dims) || numel(unique(dims))~=numel(dims) || ...
        (numel(physicalSize)>numel(dims) && ...
         any(physicalSize(numel(dims)+1:end)~=1))
    dims=strings(1,0);
end
end

function out=coordinates_(dims,value,coords,dofs)
out=struct();
for d=1:numel(dims)
    axisSize=size(value,d);
    field=char(matlab.lang.makeValidName(dims(d)));
    if isfield(coords,field) && numel(coords.(field))==axisSize
        out.(field)=coords.(field)(:);
    elseif dims(d)=="component" && ~isempty(dofs) && numel(dofs)==axisSize
        out.(field)=string(dofs(:));
    else
        out.(field)=(1:axisSize).';
    end
end
end
