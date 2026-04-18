classdef OpenSeesModelDataTrack < handle
    %OPENSEESMODELDATATRACK MATLAB-side bookkeeping container for OpenSees models.
    %
    %   OpenSeesModelDataTrack stores optional model metadata such as node
    %   coordinates, element definitions, and nodal fixities. This class
    %   is designed to keep data management separate from command dispatch.
    %
    %   Example
    %   -------
    %       dm = OpenSeesModelDataTrack(true);
    %       dm.recordModel('basic', '-ndm', 2, '-ndf', 3);
    %       dm.recordNode(1, 0.0, 0.0);
    %       dm.recordElement('elasticBeamColumn', 1, 1, 2, 1.0, 2.1e11, 1e-4, 1);
    %       T = dm.getNodeTable();

    properties
        %TRACKDATA Enable or disable MATLAB-side bookkeeping.
        %
        %   If true, the record* methods store metadata.
        %   If false, the record* methods return immediately.
        trackData (1,1) logical = true
    end

    properties (SetAccess = private)
        %NODEMAP Map from node tag to node information struct.
        %
        %   Each value is a struct with fields:
        %       - tag
        %       - coords
        %       - ndm
        nodeMap

        %NODEORDER Insertion order of node tags.
        nodeOrder (:,1) double = zeros(0,1)

        %ELEMENTMAP Map from element tag to element information struct.
        %
        %   Each value is a struct with fields:
        %       - tag
        %       - type
        %       - args
        elementMap

        %ELEMENTORDER Insertion order of element tags.
        elementOrder (:,1) double = zeros(0,1)

        %FIXMAP Map from node tag to fixity information struct.
        %
        %   Each value is a struct with fields:
        %       - nodeTag
        %       - fixity
        fixMap

        %MODELNDM Cached model dimension.
        modelNdm (1,1) double = NaN

        %MODELNDF Cached model degrees of freedom per node.
        modelNdf (1,1) double = NaN
    end

    methods
        function obj = OpenSeesModelDataTrack(trackData)
            %OPENSEESMODELDATATRACK Construct a model-data manager.
            %
            %   DM = OPENSEESMODELDATATRACK()
            %   DM = OPENSEESMODELDATATRACK(TRACKDATA)

            if nargin >= 1 && ~isempty(trackData)
                obj.trackData = logical(trackData);
            end

            obj.clear();
        end

        function clear(obj)
            %CLEAR Reset all stored model metadata.

            obj.nodeMap = containers.Map('KeyType', 'double', 'ValueType', 'any');
            obj.nodeOrder = zeros(0,1);

            obj.elementMap = containers.Map('KeyType', 'double', 'ValueType', 'any');
            obj.elementOrder = zeros(0,1);

            obj.fixMap = containers.Map('KeyType', 'double', 'ValueType', 'any');

            obj.modelNdm = NaN;
            obj.modelNdf = NaN;
        end

        function recordModel(obj, varargin)
            %RECORDMODEL Cache model builder metadata such as ndm and ndf.

            if ~obj.trackData
                return;
            end

            ndm = obj.findFlagValue(varargin, '-ndm');
            ndf = obj.findFlagValue(varargin, '-ndf');

            if ~isempty(ndm)
                obj.modelNdm = ndm;
            end

            if ~isempty(ndf)
                obj.modelNdf = ndf;
            end
        end

        function recordNode(obj, tag, varargin)
            %RECORDNODE Store node metadata.

            if ~obj.trackData
                return;
            end

            % obj.validateNumericScalar(tag, 'tag');
            coords = obj.findFlagValue(varargin, NaN, Inf);
            ndm = numel(coords);
            ndf = obj.findFlagValue(varargin, {'-ndf', "ndf"}, 1);
            if ~isscalar(ndf)
                ndf = obj.modelNdf;
            end

            if ndm == 1
                coords = [coords(1), 0, 0];
            elseif ndm == 2
                coords = [coords(1), coords(2), 0];
            elseif ndm >= 3
                coords = coords(1:3);
            end

            info = struct( ...
                'tag', double(tag), ...
                'coords', coords(:).', ...
                'ndm', ndm, ...
                'ndf', ndf);

            key = double(tag);
            isNew = ~isKey(obj.nodeMap, key);
            obj.nodeMap(key) = info;

            if isNew
                obj.nodeOrder(end+1,1) = key;
            end
        end

        function recordElement(obj, eleType, tag, varargin)
            %RECORDELEMENT Store element metadata.

            if ~obj.trackData
                return;
            end

            eleType = obj.toCharText(eleType, 'eleType');
            obj.validateNumericScalar(tag, 'tag');

            info = struct( ...
                'tag', double(tag), ...
                'type', eleType, ...
                'args', {varargin});

            key = double(tag);
            isNew = ~isKey(obj.elementMap, key);
            obj.elementMap(key) = info;

            if isNew
                obj.elementOrder(end+1,1) = key;
            end
        end

        function recordFix(obj, nodeTag, varargin)
            %RECORDFIX Store nodal fixity metadata.

            if ~obj.trackData
                return;
            end

            % obj.validateNumericScalar(nodeTag, 'nodeTag');
            fixity = obj.findFlagValue(varargin, NaN, Inf);

            obj.fixMap(double(nodeTag)) = struct( ...
                'nodeTag', double(nodeTag), ...
                'fixity', fixity);
        end

        function tf = hasNode(obj, tag)
            %HASNODE Return true if the specified node tag is stored.

            obj.validateNumericScalar(tag, 'tag');
            tf = isKey(obj.nodeMap, double(tag));
        end

        function tf = hasElement(obj, tag)
            %HASELEMENT Return true if the specified element tag is stored.

            obj.validateNumericScalar(tag, 'tag');
            tf = isKey(obj.elementMap, double(tag));
        end

        function coords = getNodeCoord(obj, tag)
            %GETNODECOORD Return stored coordinates for a node tag.

            info = obj.getNodeInfo(tag);
            coords = info.coords;
        end

        function info = getNodeInfo(obj, tag)
            %GETNODEINFO Return the stored node information struct.

            obj.validateNumericScalar(tag, 'tag');
            key = double(tag);

            if ~isKey(obj.nodeMap, key)
                error('OpenSeesModelData:NodeNotTracked', ...
                    'Node tag %g is not available in stored metadata.', key);
            end

            info = obj.nodeMap(key);
        end

        function info = getElementInfo(obj, tag)
            %GETELEMENTINFO Return the stored element information struct.

            obj.validateNumericScalar(tag, 'tag');
            key = double(tag);

            if ~isKey(obj.elementMap, key)
                error('OpenSeesModelData:ElementNotTracked', ...
                    'Element tag %g is not available in stored metadata.', key);
            end

            info = obj.elementMap(key);
        end

        function info = getFixInfo(obj, nodeTag)
            %GETFIXINFO Return the stored fixity information for a node.

            obj.validateNumericScalar(nodeTag, 'nodeTag');
            key = double(nodeTag);

            if ~isKey(obj.fixMap, key)
                error('OpenSeesModelData:FixNotTracked', ...
                    'Fixity for node tag %g is not available in stored metadata.', key);
            end

            info = obj.fixMap(key);
        end

        function tags = getTrackedNodeTags(obj)
            %GETTRACKEDNODETAGS Return stored node tags.

            tags = obj.nodeOrder;
        end

        function tags = getTrackedElementTags(obj)
            %GETTRACKEDELEMENTTAGS Return stored element tags.

            tags = obj.elementOrder;
        end

        function T = getNodeTable(obj)
            %GETNODETABLE Return stored node metadata as a table.
            %
            %   The returned table contains:
            %       - tag
            %       - x
            %       - y
            %       - z
            %       - ndm
            %
            %   For 2D nodes, z is filled with NaN.

            n = numel(obj.nodeOrder);
            tag = zeros(n,1);
            x   = NaN(n,1);
            y   = NaN(n,1);
            z   = NaN(n,1);
            ndm = NaN(n,1);
            ndf = NaN(n,1);

            for i = 1:n
                key = obj.nodeOrder(i);
                info = obj.nodeMap(key);

                tag(i) = info.tag;
                ndm(i) = info.ndm;
                ndf(i) = info.ndf;

                c = info.coords;
                if numel(c) >= 1, x(i) = c(1); end
                if numel(c) >= 2, y(i) = c(2); end
                if numel(c) >= 3, z(i) = c(3); end
            end

            T = table(tag, x, y, z, ndm, ndf);
        end

        function T = getElementTable(obj)
            %GETELEMENTTABLE Return stored element metadata as a table.
            %
            %   The returned table contains:
            %       - tag
            %       - type
            %       - args

            n = numel(obj.elementOrder);
            tag  = zeros(n,1);
            type = strings(n,1);
            args = cell(n,1);

            for i = 1:n
                key = obj.elementOrder(i);
                info = obj.elementMap(key);

                tag(i)  = info.tag;
                type(i) = string(info.type);
                args{i} = info.args;
            end

            T = table(tag, type, args);
        end

        function T = getFixTable(obj)
            %GETFIXTABLE Return stored fixity metadata as a table.
            %
            %   The returned table contains:
            %       - nodeTag
            %       - fixity

            keys = obj.fixMap.keys();
            n = numel(keys);

            nodeTag = zeros(n,1);
            fixity  = cell(n,1);

            for i = 1:n
                key = keys{i};
                info = obj.fixMap(key);
                nodeTag(i) = info.nodeTag;
                fixity{i} = info.fixity;
            end

            T = table(nodeTag, fixity);
        end

        function disp(obj)
            %DISP Display a summary of the stored model metadata.

            fprintf('%s object\n', class(obj));
            fprintf('  trackData         : %s\n', string(obj.trackData));
            fprintf('  stored nodes      : %d\n', numel(obj.nodeOrder));
            fprintf('  stored elements   : %d\n', numel(obj.elementOrder));
            fprintf('  stored fixities   : %d\n', obj.fixMap.Count);

            if ~isnan(obj.modelNdm)
                fprintf('  model ndm         : %g\n', obj.modelNdm);
            end

            if ~isnan(obj.modelNdf)
                fprintf('  model ndf         : %g\n', obj.modelNdf);
            end
        end
    end

    methods (Access = private)
        function value = findFlagValue(obj, args, flag, n)
        %FINDFLAGVALUE Extract numeric value(s) following a flag in an argument list.
        %
        % value = findFlagValue(obj, args, flag)
        % value = findFlagValue(obj, args, flag, n)
        %
        % DESCRIPTION
        %   Searches a cell array of input arguments for a specified flag and
        %   returns the numeric value(s) that follow the flag.
        %
        % INPUT
        %   args : cell
        %       Argument list (typically varargin or a parsed command cell array).
        %
        %   flag : char | string | string array | cell array of text | NaN
        %       Flag(s) to search for.
        %       If flag is NaN, extraction starts from args{1} without searching.
        %
        %   n : positive integer | Inf | NaN (optional)
        %       Number of numeric values to read after the flag.
        %
        %       n = 1 (default)
        %           Return the first numeric scalar after the flag.
        %
        %       n = k
        %           Return up to k numeric values.
        %
        %       n = Inf or NaN
        %           Read all consecutive numeric values until another text token
        %           (interpreted as a flag) or the end of the argument list.
        %
        % OUTPUT
        %   value : double | double row vector | []
        %
        %       []  → flag not found or no numeric values follow
        %       scalar double → single numeric value
        %       row vector → multiple numeric values
        %
        % NOTES
        %   - Text tokens are treated as potential flags.
        %   - Flag comparison is case-sensitive.
        %   - Only finite numeric scalars are extracted.

            if nargin < 4 || isempty(n)
                n = 1;
            end

            % Default output if nothing is found
            value = [];

            if isempty(args) || ~iscell(args)
                return
            end

            nArgs = numel(args);

            %% Determine starting index
            if isnumeric(flag) && isscalar(flag) && isnan(flag)
                % No flag search; start reading from the first argument
                startIdx = 1;

            else
                % Normalize flag aliases
                flags = obj.normalizeFlags(flag);
                startIdx = [];

                for i = 1:nArgs
                    if obj.isTextScalar(args{i})
                        txt = obj.toCharText(args{i}, 'flag');

                        if any(strcmp(txt, flags))
                            startIdx = i + 1;
                            break
                        end
                    end
                end

                % Flag not found
                if isempty(startIdx)
                    return
                end
            end

            % If flag is the last element
            if startIdx > nArgs
                return
            end

            %% Single-value mode
            if isscalar(n) && n == 1

                for j = startIdx:nArgs
                    token = args{j};

                    if obj.isTextScalar(token)
                        % Stop at next flag-like token
                        return
                    end

                    if isnumeric(token) && isscalar(token) && isfinite(token)
                        value = double(token);
                        return
                    else
                        return
                    end
                end

                return
            end

            %% Multi-value mode
            if isnan(n)
                n = Inf;
            end

            vals = [];

            for j = startIdx:nArgs

                token = args{j};

                % Stop if another flag appears
                if obj.isTextScalar(token)
                    break
                end

                if isnumeric(token) && isscalar(token) && isfinite(token)
                    vals(end+1) = double(token); %#ok<AGROW>

                    if ~isinf(n) && numel(vals) >= n
                        break
                    end
                else
                    break
                end
            end

            value = vals;
        end

        function flags = normalizeFlags(obj, flag)
        %NORMALIZEFLAGS Normalize flag input to a cell array of char.

            if ischar(flag) || (isstring(flag) && isscalar(flag))
                flags = {obj.toCharText(flag, 'flag')};

            elseif isstring(flag)
                flags = cell(size(flag));
                for k = 1:numel(flag)
                    flags{k} = obj.toCharText(flag(k), 'flag');
                end

            elseif iscell(flag)
                flags = cell(size(flag));
                for k = 1:numel(flag)
                    flags{k} = obj.toCharText(flag{k}, 'flag');
                end

            else
                error('OpenSeesMatlab:InvalidInput', ...
                    '"flag" must be a char, string, string array, or cell array of text.');
            end
        end

        function tf = isTextScalar(~, x)
            %ISTEXTSCALAR Return true if x is a char or string scalar.
            tf = ischar(x) || (isstring(x) && isscalar(x));
        end

        function tf = hasFlag(obj, args, flag)
            %HASFLAG Check whether a flag exists in an argument list.
            %
            % tf = hasFlag(obj, args, flag)
            %
            % Inputs
            % ------
            % args : cell
            %     Argument list (e.g., varargin).
            %
            % flag : char | string scalar | string array | cell array
            %     A flag or multiple alias flags.
            %
            % Output
            % ------
            % tf : logical
            %     True if any matching flag is found in args.
            %
            % Notes
            % -----
            % Comparison is case-sensitive.

            tf = false;

            if isempty(args) || ~iscell(args)
                return;
            end

            % Normalize flag(s) into cell array of char
            flags = obj.normalizeFlags(flag);

            for i = 1:numel(args)

                token = args{i};

                if obj.isTextScalar(token)

                    thisFlag = obj.toCharText(token,'flag');

                    % Case-sensitive comparison
                    if any(strcmp(thisFlag, flags))
                        tf = true;
                        return;
                    end

                end
            end
        end

        function coords = parseNodeCoordinates(obj, varargin)
            %PARSENODECOORDINATES Parse node coordinates from input arguments.

            coords = obj.parseNumericRow(varargin);

            if isempty(coords)
                error('OpenSeesModelData:InvalidNodeCoordinates', ...
                    'Node coordinates must not be empty.');
            end

            if numel(coords) > 3
                error('OpenSeesModelData:InvalidNodeCoordinates', ...
                    'Stored node coordinates must contain 1, 2, or 3 numeric values.');
            end
        end

        function row = parseNumericRow(~, c)
            %PARSENUMERICROW Convert a cell array of numeric scalars into a row vector.

            n = numel(c);
            row = zeros(1,n);

            for i = 1:n
                v = c{i};
                row(i) = double(v);
            end
        end

        function validateNumericScalar(~, value, name)
            %VALIDATENUMERICSCALAR Validate a finite numeric scalar.

            if ~(isnumeric(value) && isscalar(value) && isfinite(value))
                error('OpenSeesModelData:InvalidInput', ...
                    '"%s" must be a finite numeric scalar.', name);
            end
        end

        function out = toCharText(~, value, name)
            %TOCHARTEXT Validate and convert text input to char.

            if isstring(value)
                if ~isscalar(value)
                    error('OpenSeesModelData:InvalidInput', ...
                        '"%s" must be a text scalar.', name);
                end
                out = char(value);
            elseif ischar(value)
                out = value;
            else
                error('OpenSeesModelData:InvalidInput', ...
                    '"%s" must be a char array or string scalar.', name);
            end

            if isempty(out)
                error('OpenSeesModelData:InvalidInput', ...
                    '"%s" must not be empty.', name);
            end
        end
    end
end