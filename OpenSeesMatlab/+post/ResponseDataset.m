classdef ResponseDataset
    %RESPONSEDATASET Collection of label-aware response variables.
    properties (SetAccess = private)
        Variables struct = struct()
        Paths string = strings(0, 1)
        Attributes struct = struct()
        SourceType string = "response"
    end
    methods
        function obj = ResponseDataset(variables, paths, attributes, sourceType)
            if nargin == 0, return; end
            obj.Variables = variables; obj.Paths = string(paths(:));
            if nargin >= 3, obj.Attributes = attributes; end
            if nargin >= 4, obj.SourceType = string(sourceType); end
        end
        function names = names(obj), names = obj.Paths; end
        function tf = has(obj, name), tf = any(obj.Paths == string(name)); end
        function value = get(obj, name)
            idx = find(obj.Paths == string(name), 1);
            if isempty(idx)
                error('post:ResponseDataset:UnknownVariable', ...
                    'Unknown variable "%s". Available: %s', string(name), strjoin(obj.Paths, ', '));
            end
            keys = fieldnames(obj.Variables);
            value = [];
            for i=1:numel(keys)
                candidate=obj.Variables.(keys{i});
                if candidate.Name==string(name), value=candidate; break; end
            end
            if isempty(value)
                error('post:ResponseDataset:InternalMapping', ...
                    'Variable storage for path "%s" is inconsistent.',string(name));
            end
        end
        function out = subsref(obj, s)
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
            fprintf('post.ResponseDataset (%s) with %d variables\n', obj.SourceType, numel(obj.Paths));
            for i=1:numel(obj.Paths), fprintf('  %s\n', obj.Paths(i)); end
        end
    end
    methods (Access=private)
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
        function obj = fromStruct(response), obj = post.toResponseDataset(response); end
    end
end
