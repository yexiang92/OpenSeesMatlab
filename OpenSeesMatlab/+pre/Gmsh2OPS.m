classdef Gmsh2OPS < handle
    %GMSH2OPS Generate OpenSees-MATLAB commands from Gmsh `.msh` files.
    %
    % This class reads ASCII Gmsh `.msh` files and converts mesh entities,
    % nodes, elements, and physical groups into OpenSees-MATLAB commands.
    %
    % The class supports:
    %
    % * parsing `$PhysicalNames`, `$Entities`, `$Nodes`, and `$Elements`
    % * querying nodes/elements by dimension-entity tags or physical groups
    % * creating OpenSees commands directly at runtime
    % * writing MATLAB or Tcl command scripts
    %
    % Parameters
    % ----------
    % ops : object, optional
    %     OpenSees-MATLAB command object used by runtime command
    %     creation methods.
    %
    % Notes
    % -----
    % 1. This implementation is intended for ASCII Gmsh MSH 4.x files.
    % 2. Runtime Gmsh API access is intentionally not included here.
    % 3. The generated MATLAB commands assume an OpenSees-MATLAB interface
    %    such as:
    %
    %        ops.node(...)
    %        ops.element(...)
    %        ops.fix(...)
    %
    % Examples
    % --------
    % Create the converter and read a mesh file:
    %
    %     g2o = Gmsh2OPS(Ops=ops);
    %     g2o.readGmshFile('model.msh');
    %
    % Write node and element commands to a MATLAB script:
    %
    %     g2o.setOutputFile(FileName='gmsh_model.m');
    %     g2o.writeNodeFile();
    %     g2o.writeElementFile('truss', OpsEleArgs={0.01, 1});
    %
    % Create commands directly at runtime:
    %
    %     opsMAT = OpenSeesMatlab();
    %     ops = opsMAT.opensees;
    %     g2o.createNodeCmds();
    %     g2o.createElementCmds('truss', OpsEleArgs={0.01, 1});

    properties (Access = private)
        % Internal properties for storing Gmsh data and output settings.
        ops % OpenSees-MATLAB command object for runtime command creation.
    end

    properties
        % Number of spatial dimensions.
        ndm (1,1) double = 3

        % Number of degrees of freedom per node.
        ndf (1,1) double = 3

        % Gmsh entity information.
        % key = 'dim_entity', e.g. '2_15'
        gmshEntities

        % Gmsh nodes grouped by entity.
        % value = struct array with fields: tag, coords
        gmshNodes

        % Gmsh elements grouped by entity.
        % value = struct array with fields: tag, nodeTags, eleType
        gmshEles

        % Physical groups.
        % key = physical group name
        % value = [dim, entityTag; ...]
        gmshPhysicalGroups

        % Dimension and entity tag pairs, [dim, entityTag].
        gmshDimEntityTags double = zeros(0, 2)

        % All node tags.
        allNodeTags double = zeros(0, 1)

        % All element tags.
        allEleTags double = zeros(0, 1)

        % Output file path.
        outFile char = ''

        % Output type: 'matlab' or 'tcl'.
        outType char = ''
    end

    properties (Constant, Access = private)
        % Supported Gmsh element types for OpenSees-related conversion.
        OPS_GMSH_ELE_TYPE = [1, 2, 3, 4, 5, 9, 10, 11, 12, 16, 17];
    end

    methods
        function obj = Gmsh2OPS(opts)
            %GMSH2OPS Construct a Gmsh-to-OpenSees converter.
            %
            % Parameters
            % ----------
            % Ops : object, optional
            %     OpenSees-MATLAB command object used by runtime command
            %     creation methods such as `createNodeCmds`.

            arguments
                opts.Ops = []
            end

            obj.ops = opts.Ops;
            obj.reset();
        end

        function reset(obj)
            obj.gmshEntities = containers.Map('KeyType', 'char', 'ValueType', 'any');
            obj.gmshNodes = containers.Map('KeyType', 'char', 'ValueType', 'any');
            obj.gmshEles = containers.Map('KeyType', 'char', 'ValueType', 'any');
            obj.gmshPhysicalGroups = containers.Map('KeyType', 'char', 'ValueType', 'any');
            obj.gmshDimEntityTags = zeros(0, 2);
            obj.allNodeTags = zeros(0, 1);
            obj.allEleTags = zeros(0, 1);
            obj.outFile = '';
            obj.outType = '';
        end

        function setOutputFile(obj, opts)
            %SETOUTPUTFILE Set the output script file.
            %
            % Parameters
            % ----------
            % FileName : char, optional
            %     Output file name. Must end with `.m` or `.tcl`.
            %     Default is `'src.m'`.
            %
            % Notes
            % -----
            % If the file ends with `.m`, MATLAB/OpenSees commands are written.
            % If the file ends with `.tcl`, Tcl/OpenSees commands are written.
            %
            % A model header is automatically written to the file.
            %
            % Examples
            % --------
            %     g2o.setOutputFile(FileName='model_from_gmsh.m');
            %     g2o.setOutputFile(FileName='model_from_gmsh.tcl');

            arguments
                obj
            end
            arguments
                opts.FileName (1,:) char = 'src.m'
            end

            filename = opts.FileName;
            obj.outFile = filename;
            if endsWith(filename, '.tcl')
                obj.outType = 'tcl';
            elseif endsWith(filename, '.m')
                obj.outType = 'matlab';
            else
                error('Output file must end with .m or .tcl.');
            end

            fid = fopen(obj.outFile, 'w');
            assert(fid > 0, 'Cannot open output file: %s', obj.outFile);
            cleaner = onCleanup(@() fclose(fid)); %#ok<NASGU>

            fprintf(fid, '%% This file was created by %s\n\n', class(obj));
            if strcmp(obj.outType, 'matlab')
                fprintf(fid, 'ops.wipe();\n');
                fprintf(fid, 'ops.model("basic", "-ndm", %d, "-ndf", %d);\n\n', obj.ndm, obj.ndf);
            else
                fprintf(fid, 'wipe\n');
                fprintf(fid, 'model basic -ndm %d -ndf %d\n\n', obj.ndm, obj.ndf);
            end
        end

        function readGmshFile(obj, filePath, opts)
            %READGMSHFILE Read an ASCII Gmsh `.msh` file.
            %
            % Parameters
            % ----------
            % filePath : char
            %     Path to the `.msh` file.
            % PrintInfo : logical, optional
            %     If true, print geometry, physical group, and mesh summary
            %     information. Default is true.
            %
            % Notes
            % -----
            % This method parses the following sections when present:
            %
            % * `$PhysicalNames`
            % * `$Entities`
            % * `$Nodes`
            % * `$Elements`
            %
            % The parsed data are stored in:
            %
            % * `gmshEntities`
            % * `gmshNodes`
            % * `gmshEles`
            % * `gmshPhysicalGroups`
            %
            % Examples
            % --------
            %     g2o.readGmshFile('mesh.msh');
            %     g2o.readGmshFile('mesh.msh', PrintInfo=false);

            arguments
                obj
                filePath (1,:) char
            end
            arguments
                opts.PrintInfo (1,1) logical = true
            end

            txt = fileread(filePath);
            lines = regexp(txt, '\r\n|\n|\r', 'split')';
            lines = strtrim(lines);
            lines = lines(~startsWith(lines, '**'));

            nodeIdx     = [find(strcmp(lines, '$Nodes'), 1), find(strcmp(lines, '$EndNodes'), 1)];
            eleIdx      = [find(strcmp(lines, '$Elements'), 1), find(strcmp(lines, '$EndElements'), 1)];
            entitiesIdx = [find(strcmp(lines, '$Entities'), 1), find(strcmp(lines, '$EndEntities'), 1)];

            physicalIdx = [];
            i1 = find(strcmp(lines, '$PhysicalNames'), 1);
            if ~isempty(i1)
                physicalIdx = [i1, find(strcmp(lines, '$EndPhysicalNames'), 1)];
            end

            physicalTagNameMap = obj.retrievePhysicalGroups(lines, physicalIdx);
            [obj.gmshEntities, obj.gmshPhysicalGroups, obj.gmshDimEntityTags] = ...
                obj.retrieveEntities(lines, entitiesIdx, physicalTagNameMap);

            [obj.gmshNodes, obj.allNodeTags] = obj.retrieveNodes(lines, nodeIdx);
            [obj.gmshEles, obj.allEleTags] = obj.retrieveEles(lines, eleIdx);

            obj.allNodeTags = obj.allNodeTags(:);
            obj.allEleTags  = obj.allEleTags(:);

            if opts.PrintInfo
                obj.printInfo();
            end
        end

        function printInfo(obj)
            %PRINTINFO Print geometry, physical group, and mesh summary information.
            %
            % Notes
            % -----
            % This method prints:
            %
            % * entity counts by dimension
            % * physical group names
            % * total node and element counts
            % * minimum and maximum node/element tags

            dims = obj.gmshDimEntityTags(:,1);
            numPoints = sum(dims == 0);
            numCurves = sum(dims == 1);
            numSurfs  = sum(dims == 2);
            numVols   = sum(dims == 3);
            n = size(obj.gmshDimEntityTags, 1);

            fprintf('Info:: Geometry Information >>>\n');
            fprintf('%d Entities: %d Point; %d Curves; %d Surfaces; %d Volumes.\n\n', ...
                n, numPoints, numCurves, numSurfs, numVols);

            groupNames = obj.gmshPhysicalGroups.keys;
            fprintf('Info:: Physical Groups Information >>>\n');
            fprintf('%d Physical Groups.\n', numel(groupNames));
            fprintf('Physical Group names: %s\n\n', strjoin(groupNames, ', '));

            fprintf('Info:: Mesh Information >>>\n');
            if ~isempty(obj.allNodeTags)
                fprintf('%d Nodes; MaxNodeTag %d; MinNodeTag %d.\n', ...
                    numel(obj.allNodeTags), max(obj.allNodeTags), min(obj.allNodeTags));
            else
                fprintf('0 Nodes.\n');
            end
            if ~isempty(obj.allEleTags)
                fprintf('%d Elements; MaxEleTag %d; MinEleTag %d.\n\n', ...
                    numel(obj.allEleTags), max(obj.allEleTags), min(obj.allEleTags));
            else
                fprintf('0 Elements.\n\n');
            end
        end

        function setNodeElementTagsOffset(obj, opts)
            %SETNODEELEMENTTAGSOFFSET Apply offsets to node and element tags.
            %
            % Parameters
            % ----------
            % NodeOffset : double or empty, optional
            %     Node tag offset. If empty, no node offset is applied.
            % EleOffset : double or empty, optional
            %     Element tag offset. If empty, no element offset is applied.
            %
            % Notes
            % -----
            % If a node offset is applied, element connectivity is updated
            % accordingly.

            arguments
                obj
            end
            arguments
                opts.NodeOffset = []
                opts.EleOffset = []
            end

            nodeOffset = opts.NodeOffset;
            eleOffset = opts.EleOffset;

            if ~isempty(nodeOffset)
                oldKeys = obj.gmshNodes.keys;
                newMap = containers.Map('KeyType', 'char', 'ValueType', 'any');

                for i = 1:numel(oldKeys)
                    key = oldKeys{i};
                    nodeStruct = obj.gmshNodes(key);
                    tags = [nodeStruct.tag] + nodeOffset;
                    coords = {nodeStruct.coords};
                    newNodeStruct = repmat(struct('tag', 0, 'coords', []), numel(tags), 1);
                    for k = 1:numel(tags)
                        newNodeStruct(k).tag = tags(k);
                        newNodeStruct(k).coords = coords{k};
                    end
                    newMap(key) = newNodeStruct;
                end
                obj.gmshNodes = newMap;
                obj.allNodeTags = obj.allNodeTags + nodeOffset;

                oldKeys = obj.gmshEles.keys;
                for i = 1:numel(oldKeys)
                    key = oldKeys{i};
                    eleStruct = obj.gmshEles(key);
                    for k = 1:numel(eleStruct)
                        eleStruct(k).nodeTags = eleStruct(k).nodeTags + nodeOffset;
                    end
                    obj.gmshEles(key) = eleStruct;
                end
            end

            if ~isempty(eleOffset)
                oldKeys = obj.gmshEles.keys;
                newMap = containers.Map('KeyType', 'char', 'ValueType', 'any');

                for i = 1:numel(oldKeys)
                    key = oldKeys{i};
                    eleStruct = obj.gmshEles(key);
                    for k = 1:numel(eleStruct)
                        eleStruct(k).tag = eleStruct(k).tag + eleOffset;
                    end
                    newMap(key) = eleStruct;
                end
                obj.gmshEles = newMap;
                obj.allEleTags = obj.allEleTags + eleOffset;
            end
        end

        function nodeTags = getNodeTags(obj, opts)
            %GETNODETAGS Return node tags from selected entities or groups.
            %
            % Parameters
            % ----------
            % DimEntityTags : double array, optional
            %     N-by-2 array of `[dim, entityTag]`.
            %     If provided, it takes priority over `PhysicalGroupNames`.
            % PhysicalGroupNames : char, string, cellstr, optional
            %     Physical group name or list of names.
            %
            % Returns
            % -------
            % nodeTags : double column vector
            %     Unique node tags in stable order.
            %
            % Notes
            % -----
            % If both `DimEntityTags` and `PhysicalGroupNames` are empty,
            % all available mesh entities with nodes are used.
            %
            % Examples
            % --------
            %     tags = g2o.getNodeTags();
            %     tags = g2o.getNodeTags(DimEntityTags=[2 1; 2 2]);
            %     tags = g2o.getNodeTags(PhysicalGroupNames='Support');

            arguments
                obj
            end
            arguments
                opts.DimEntityTags = []
                opts.PhysicalGroupNames = []
            end

            entityTags = obj.resolveEntityTags(opts.DimEntityTags, opts.PhysicalGroupNames, 'nodes');

            nodeTags = [];
            for i = 1:size(entityTags, 1)
                key = obj.makeKey(entityTags(i,1), entityTags(i,2));
                if isKey(obj.gmshNodes, key)
                    nodeStruct = obj.gmshNodes(key);
                    nodeTags = [nodeTags; [nodeStruct.tag]']; %#ok<AGROW>
                end
            end
            nodeTags = unique(nodeTags, 'stable');
        end

        function nodeTags = createNodeCmds(obj, opts)
            %CREATENODECMDS Create OpenSees node commands at runtime.
            %
            % Parameters
            % ----------
            % DimEntityTags : double array, optional
            %     N-by-2 array of `[dim, entityTag]`.
            % PhysicalGroupNames : char, string, cellstr, optional
            %     Physical group name or list of names.
            % StartNodeTag : double, optional
            %     Starting node tag. If empty, original Gmsh node tags are used.
            %
            % Returns
            % -------
            % nodeTags : double column vector
            %     Generated OpenSees node tags.
            %
            % Notes
            % -----
            % If `StartNodeTag` is provided, node tags are reassigned in
            % ascending order from that value.

            arguments
                obj
            end
            arguments
                opts.DimEntityTags = []
                opts.PhysicalGroupNames = []
                opts.StartNodeTag = []
            end

            assert(~isempty(obj.ops), 'OpenSees command object is not configured.');

            entityTags = obj.resolveEntityTags(opts.DimEntityTags, opts.PhysicalGroupNames, 'nodes');
            nodeTags = [];

            if isempty(opts.StartNodeTag)
                for i = 1:size(entityTags, 1)
                    key = obj.makeKey(entityTags(i,1), entityTags(i,2));
                    if ~isKey(obj.gmshNodes, key), continue; end
                    nodeStruct = obj.gmshNodes(key);
                    for k = 1:numel(nodeStruct)
                        c = nodeStruct(k).coords(1:obj.ndm);
                        args = [{nodeStruct(k).tag}, num2cell(c)];
                        obj.ops.node(args{:});
                        nodeTags(end+1,1) = nodeStruct(k).tag; %#ok<AGROW>
                    end
                end
            else
                currentTag = opts.StartNodeTag;
                for i = 1:size(entityTags, 1)
                    key = obj.makeKey(entityTags(i,1), entityTags(i,2));
                    if ~isKey(obj.gmshNodes, key), continue; end
                    nodeStruct = obj.gmshNodes(key);
                    for k = 1:numel(nodeStruct)
                        c = nodeStruct(k).coords(1:obj.ndm);
                        args = [{currentTag}, num2cell(c)];
                        obj.ops.node(args{:});
                        nodeTags(end+1,1) = currentTag; %#ok<AGROW>
                        currentTag = currentTag + 1;
                    end
                end
            end
        end

        function nodeTags = writeNodeFile(obj, opts)
            %WRITENODEFILE Write node commands to the output script.
            %
            % Parameters
            % ----------
            % DimEntityTags : double array, optional
            %     N-by-2 array of `[dim, entityTag]`.
            % PhysicalGroupNames : char, string, cellstr, optional
            %     Physical group name or list of names.
            % StartNodeTag : double, optional
            %     Starting node tag. If empty, original Gmsh node tags are used.
            %
            % Returns
            % -------
            % nodeTags : double column vector
            %     Written node tags.
            %
            % Notes
            % -----
            % `setOutputFile` must be called before using this method.

            arguments
                obj
            end
            arguments
                opts.DimEntityTags = []
                opts.PhysicalGroupNames = []
                opts.StartNodeTag = []
            end

            assert(~isempty(obj.outFile), 'Output file is not set.');
            entityTags = obj.resolveEntityTags(opts.DimEntityTags, opts.PhysicalGroupNames, 'nodes');
            nodeTags = [];

            fid = fopen(obj.outFile, 'a');
            assert(fid > 0, 'Cannot open output file.');
            cleaner = onCleanup(@() fclose(fid)); %#ok<NASGU>

            fprintf(fid, '\n%% Create node commands\n\n');

            if isempty(opts.StartNodeTag)
                for i = 1:size(entityTags, 1)
                    key = obj.makeKey(entityTags(i,1), entityTags(i,2));
                    if ~isKey(obj.gmshNodes, key), continue; end
                    nodeStruct = obj.gmshNodes(key);
                    for k = 1:numel(nodeStruct)
                        tag = nodeStruct(k).tag;
                        c = nodeStruct(k).coords(1:obj.ndm);
                        obj.writeNodeLine(fid, tag, c);
                        nodeTags(end+1,1) = tag; %#ok<AGROW>
                    end
                end
            else
                currentTag = opts.StartNodeTag;
                for i = 1:size(entityTags, 1)
                    key = obj.makeKey(entityTags(i,1), entityTags(i,2));
                    if ~isKey(obj.gmshNodes, key), continue; end
                    nodeStruct = obj.gmshNodes(key);
                    for k = 1:numel(nodeStruct)
                        c = nodeStruct(k).coords(1:obj.ndm);
                        obj.writeNodeLine(fid, currentTag, c);
                        nodeTags(end+1,1) = currentTag; %#ok<AGROW>
                        currentTag = currentTag + 1;
                    end
                end
            end
        end

        function eleTags = getElementTags(obj, opts)
            %GETELEMENTTAGS Return element tags from selected entities or groups.
            %
            % Parameters
            % ----------
            % DimEntityTags : double array, optional
            %     N-by-2 array of `[dim, entityTag]`.
            % PhysicalGroupNames : char, string, cellstr, optional
            %     Physical group name or list of names.
            %
            % Returns
            % -------
            % eleTags : double column vector
            %     Unique element tags in stable order.

            arguments
                obj
            end
            arguments
                opts.DimEntityTags = []
                opts.PhysicalGroupNames = []
            end

            entityTags = obj.resolveEntityTags(opts.DimEntityTags, opts.PhysicalGroupNames, 'eles');
            eleTags = [];

            for i = 1:size(entityTags, 1)
                key = obj.makeKey(entityTags(i,1), entityTags(i,2));
                if isKey(obj.gmshEles, key)
                    eleStruct = obj.gmshEles(key);
                    eleTags = [eleTags; [eleStruct.tag]']; %#ok<AGROW>
                end
            end
            eleTags = unique(eleTags, 'stable');
        end

        function eleTags = createElementCmds(obj, opsEleType, opts)
            %CREATEELEMENTCMDS Create OpenSees element commands at runtime.
            %
            % Parameters
            % ----------
            % opsEleType : char or string
            %     OpenSees element type, such as `"truss"` or `"quad"`.
            % OpsEleArgs : cell, optional
            %     Additional arguments appended after tag and node tags.
            % DimEntityTags : double array, optional
            %     N-by-2 array of `[dim, entityTag]`.
            % PhysicalGroupNames : char, string, cellstr, optional
            %     Physical group name or names.
            % StartEleTag : double, optional
            %     Starting element tag. If empty, original Gmsh element tags
            %     are used.
            %
            % Returns
            % -------
            % eleTags : double column vector
            %     Generated OpenSees element tags.
            %
            % Notes
            % -----
            % If `StartEleTag` is provided, element tags are reassigned in
            % ascending order from that value.
            %
            % Examples
            % --------
            %     g2o.createElementCmds('truss', OpsEleArgs={0.01, 1});
            %     g2o.createElementCmds('quad', OpsEleArgs={1, 'PlaneStress', 1}, PhysicalGroupNames='Slab');

            arguments
                obj
                opsEleType
            end
            arguments
                opts.OpsEleArgs = {}
                opts.DimEntityTags = []
                opts.PhysicalGroupNames = []
                opts.StartEleTag = []
            end

            assert(~isempty(obj.ops), 'OpenSees command object is not configured.');

            entityTags = obj.resolveEntityTags(opts.DimEntityTags, opts.PhysicalGroupNames, 'eles');
            eleTags = [];

            if isempty(opts.StartEleTag)
                for i = 1:size(entityTags, 1)
                    key = obj.makeKey(entityTags(i,1), entityTags(i,2));
                    if ~isKey(obj.gmshEles, key), continue; end
                    eleStruct = obj.gmshEles(key);
                    for k = 1:numel(eleStruct)
                        args = [{opsEleType}, {eleStruct(k).tag}, num2cell(eleStruct(k).nodeTags), opts.OpsEleArgs];
                        obj.ops.element(args{:});
                        eleTags(end+1,1) = eleStruct(k).tag; %#ok<AGROW>
                    end
                end
            else
                currentTag = opts.StartEleTag;
                for i = 1:size(entityTags, 1)
                    key = obj.makeKey(entityTags(i,1), entityTags(i,2));
                    if ~isKey(obj.gmshEles, key), continue; end
                    eleStruct = obj.gmshEles(key);
                    for k = 1:numel(eleStruct)
                        args = [{opsEleType}, {currentTag}, num2cell(eleStruct(k).nodeTags), opts.OpsEleArgs];
                        obj.ops.element(args{:});
                        eleTags(end+1,1) = currentTag; %#ok<AGROW>
                        currentTag = currentTag + 1;
                    end
                end
            end
        end

        function eleTags = writeElementFile(obj, opsEleType, opts)
            %WRITEELEMENTFILE Write element commands to the output script.
            %
            % Parameters
            % ----------
            % opsEleType : char or string
            %     OpenSees element type.
            % OpsEleArgs : cell, optional
            %     Additional arguments appended after tag and node tags.
            % DimEntityTags : double array, optional
            %     N-by-2 array of `[dim, entityTag]`.
            % PhysicalGroupNames : char, string, cellstr, optional
            %     Physical group name or names.
            % StartEleTag : double, optional
            %     Starting element tag. If empty, original Gmsh element tags
            %     are used.
            %
            % Returns
            % -------
            % eleTags : double column vector
            %     Written element tags.
            %
            % Notes
            % -----
            % `setOutputFile` must be called before using this method.

            arguments
                obj
                opsEleType
            end
            arguments
                opts.OpsEleArgs = {}
                opts.DimEntityTags = []
                opts.PhysicalGroupNames = []
                opts.StartEleTag = []
            end

            assert(~isempty(obj.outFile), 'Output file is not set.');
            entityTags = obj.resolveEntityTags(opts.DimEntityTags, opts.PhysicalGroupNames, 'eles');
            eleTags = [];

            fid = fopen(obj.outFile, 'a');
            assert(fid > 0, 'Cannot open output file.');
            cleaner = onCleanup(@() fclose(fid)); %#ok<NASGU>

            fprintf(fid, '\n%% Create element commands, type=%s\n\n', opsEleType);

            if isempty(opts.StartEleTag)
                for i = 1:size(entityTags, 1)
                    key = obj.makeKey(entityTags(i,1), entityTags(i,2));
                    if ~isKey(obj.gmshEles, key), continue; end
                    eleStruct = obj.gmshEles(key);
                    for k = 1:numel(eleStruct)
                        obj.writeElementLine(fid, opsEleType, eleStruct(k).tag, eleStruct(k).nodeTags, opts.OpsEleArgs);
                        eleTags(end+1,1) = eleStruct(k).tag; %#ok<AGROW>
                    end
                end
            else
                currentTag = opts.StartEleTag;
                for i = 1:size(entityTags, 1)
                    key = obj.makeKey(entityTags(i,1), entityTags(i,2));
                    if ~isKey(obj.gmshEles, key), continue; end
                    eleStruct = obj.gmshEles(key);
                    for k = 1:numel(eleStruct)
                        obj.writeElementLine(fid, opsEleType, currentTag, eleStruct(k).nodeTags, opts.OpsEleArgs);
                        eleTags(end+1,1) = currentTag; %#ok<AGROW>
                        currentTag = currentTag + 1;
                    end
                end
            end
        end

        function fixedTags = createFixCmds(obj, dofs, opts)
            %CREATEFIXCMDS Create OpenSees fix commands at runtime.
            %
            % Parameters
            % ----------
            % dofs : cell or numeric array
            %     Constrained degrees of freedom flags, such as `{1,1,1}` or `[1 1 1]`.
            % DimEntityTags : double array, optional
            %     N-by-2 array of `[dim, entityTag]`.
            % PhysicalGroupNames : char, string, cellstr, optional
            %     Physical group name or names.
            %
            % Returns
            % -------
            % fixedTags : double column vector
            %     Fixed node tags.
            %
            % Notes
            % -----
            % Duplicate node tags are removed automatically.

            arguments
                obj
                dofs
            end
            arguments
                opts.DimEntityTags = []
                opts.PhysicalGroupNames = []
            end

            if ~iscell(dofs), dofs = num2cell(dofs); end

            assert(~isempty(obj.ops), 'OpenSees command object is not configured.');

            entityTags = obj.resolveEntityTags(opts.DimEntityTags, opts.PhysicalGroupNames, 'all');
            fixedTags = [];

            for i = 1:size(entityTags, 1)
                key = obj.makeKey(entityTags(i,1), entityTags(i,2));
                if ~isKey(obj.gmshNodes, key), continue; end
                nodeStruct = obj.gmshNodes(key);
                for k = 1:numel(nodeStruct)
                    tag = nodeStruct(k).tag;
                    if ~ismember(tag, fixedTags)
                        obj.ops.fix(tag, dofs{:});
                        fixedTags(end+1,1) = tag; %#ok<AGROW>
                    end
                end
            end
        end

        function fixedTags = writeFixFile(obj, dofs, opts)
            %WRITEFIXFILE Write fix commands to the output script.
            %
            % Parameters
            % ----------
            % dofs : cell or numeric array
            %     Constrained degrees of freedom flags.
            % DimEntityTags : double array, optional
            %     N-by-2 array of `[dim, entityTag]`.
            % PhysicalGroupNames : char, string, cellstr, optional
            %     Physical group name or names.
            %
            % Returns
            % -------
            % fixedTags : double column vector
            %     Written fixed node tags.
            %
            % Notes
            % -----
            % `setOutputFile` must be called before using this method.

            arguments
                obj
                dofs
            end
            arguments
                opts.DimEntityTags = []
                opts.PhysicalGroupNames = []
            end

            if ~iscell(dofs), dofs = num2cell(dofs); end

            assert(~isempty(obj.outFile), 'Output file is not set.');
            entityTags = obj.resolveEntityTags(opts.DimEntityTags, opts.PhysicalGroupNames, 'all');
            fixedTags = [];

            fid = fopen(obj.outFile, 'a');
            assert(fid > 0, 'Cannot open output file.');
            cleaner = onCleanup(@() fclose(fid)); %#ok<NASGU>

            fprintf(fid, '\n%% Create fix commands\n\n');

            for i = 1:size(entityTags, 1)
                key = obj.makeKey(entityTags(i,1), entityTags(i,2));
                if ~isKey(obj.gmshNodes, key), continue; end
                nodeStruct = obj.gmshNodes(key);
                for k = 1:numel(nodeStruct)
                    tag = nodeStruct(k).tag;
                    if ~ismember(tag, fixedTags)
                        obj.writeFixLine(fid, tag, dofs);
                        fixedTags(end+1,1) = tag; %#ok<AGROW>
                    end
                end
            end
        end

        function dimEntityTags = getDimEntityTags(obj, opts)
            %GETDIMENTITYTAGS Return dimension-entity tag pairs.
            %
            % Parameters
            % ----------
            % Dim : double, optional
            %     Dimension to filter. If empty, all dimension-entity tags
            %     are returned.
            %
            % Returns
            % -------
            % dimEntityTags : double array
            %     N-by-2 array of `[dim, entityTag]`.

            arguments
                obj
            end
            arguments
                opts.Dim = []
            end

            if isempty(opts.Dim)
                dimEntityTags = obj.gmshDimEntityTags;
            else
                dimEntityTags = obj.gmshDimEntityTags(obj.gmshDimEntityTags(:,1) == opts.Dim, :);
            end
        end

        function groups = getPhysicalGroups(obj)
            %GETPHYSICALGROUPS Return the physical groups map.
            %
            % Returns
            % -------
            % groups : containers.Map
            %     Map from physical group names to N-by-2 `[dim, entityTag]` arrays.

            groups = obj.gmshPhysicalGroups;
        end

        function boundaryDimTags = getBoundaryDimTags(obj, opts)
            %GETBOUNDARYDIMTAGS Return all boundary dim-entity tags recursively.
            %
            % Parameters
            % ----------
            % DimEntityTags : double array, optional
            %     N-by-2 array of `[dim, entityTag]`.
            % PhysicalGroupNames : char, string, cellstr, optional
            %     Physical group name or names.
            % IncludeSelf : logical, optional
            %     If true, the queried entities themselves are also included.
            %     Default is false.
            %
            % Returns
            % -------
            % boundaryDimTags : double array
            %     Unique sorted boundary dim-entity tags.
            %
            % Notes
            % -----
            % The boundaries are collected recursively, so surfaces return
            % their boundary curves and corner points, and volumes return
            % their boundary surfaces, curves, and points.

            arguments
                obj
            end
            arguments
                opts.DimEntityTags = []
                opts.PhysicalGroupNames = []
                opts.IncludeSelf (1,1) logical = false
            end

            entityTags = obj.resolveEntityTags(opts.DimEntityTags, opts.PhysicalGroupNames, 'all');

            boundaryDimTags = zeros(0, 2);
            if opts.IncludeSelf
                boundaryDimTags = [boundaryDimTags; entityTags];
            end

            boundaryDimTags = obj.getBoundaryDimTagsRecursive(boundaryDimTags, entityTags);
            boundaryDimTags = unique(boundaryDimTags, 'rows');
            boundaryDimTags = sortrows(boundaryDimTags, [1 2]);
        end
    end

    methods (Access = private)
        function entityTags = resolveEntityTags(obj, dimEntityTags, physicalGroupNames, mode)
            %RESOLVEENTITYTAGS Resolve selected dimension-entity tags.
            %
            % Parameters
            % ----------
            % dimEntityTags : double array or empty
            %     Explicit entity selection.
            % physicalGroupNames : char, string, cellstr, or empty
            %     Physical group selection.
            % mode : char
            %     Selection mode: `'nodes'`, `'eles'`, or `'all'`.
            %
            % Returns
            % -------
            % entityTags : double array
            %     N-by-2 `[dim, entityTag]` array.

            arguments
                obj
                dimEntityTags = []
                physicalGroupNames = []
                mode (1,:) char = 'all'
            end

            if isempty(dimEntityTags) && isempty(physicalGroupNames)
                switch mode
                    case 'nodes'
                        keys = obj.gmshNodes.keys;
                    case 'eles'
                        keys = obj.gmshEles.keys;
                    otherwise
                        entityTags = obj.gmshDimEntityTags;
                        return;
                end
                entityTags = zeros(numel(keys), 2);
                for i = 1:numel(keys)
                    entityTags(i,:) = obj.parseKey(keys{i});
                end
                return;
            end

            if ~isempty(dimEntityTags)
                entityTags = double(dimEntityTags);
                if size(entityTags,2) ~= 2
                    error('dimEntityTags must be N-by-2.');
                end
                return;
            end

            if ischar(physicalGroupNames) || isstring(physicalGroupNames)
                physicalGroupNames = cellstr(physicalGroupNames);
            end

            entityTags = zeros(0, 2);
            for i = 1:numel(physicalGroupNames)
                name = char(physicalGroupNames{i});
                if isKey(obj.gmshPhysicalGroups, name)
                    entityTags = [entityTags; obj.gmshPhysicalGroups(name)]; %#ok<AGROW>
                end
            end
            entityTags = unique(entityTags, 'rows', 'stable');
        end

        function writeNodeLine(obj, fid, tag, coords)
            %WRITENODELINE Write one node command line.

            if strcmp(obj.outType, 'tcl')
                fprintf(fid, 'node %d', tag);
                fprintf(fid, ' %.16g', coords);
                fprintf(fid, '\n');
            else
                fprintf(fid, 'ops.node(%d', tag);
                for i = 1:numel(coords)
                    fprintf(fid, ', %.16g', coords(i));
                end
                fprintf(fid, ');\n');
            end
        end

        function writeElementLine(obj, fid, opsEleType, tag, nodeTags, opsEleArgs)
            %WRITEELEMENTLINE Write one element command line.

            if strcmp(obj.outType, 'tcl')
                fprintf(fid, 'element %s %d', char(opsEleType), tag);
                fprintf(fid, ' %d', nodeTags);
                for i = 1:numel(opsEleArgs)
                    arg = opsEleArgs{i};
                    if ischar(arg) || isstring(arg)
                        fprintf(fid, ' %s', char(arg));
                    else
                        fprintf(fid, ' %.16g', arg);
                    end
                end
                fprintf(fid, '\n');
            else
                fprintf(fid, 'ops.element("%s", %d', char(opsEleType), tag);
                for i = 1:numel(nodeTags)
                    fprintf(fid, ', %d', nodeTags(i));
                end
                for i = 1:numel(opsEleArgs)
                    arg = opsEleArgs{i};
                    if ischar(arg) || isstring(arg)
                        fprintf(fid, ', "%s"', char(arg));
                    else
                        fprintf(fid, ', %.16g', arg);
                    end
                end
                fprintf(fid, ');\n');
            end
        end

        function writeFixLine(obj, fid, tag, dofs)
            %WRITEFIXLINE Write one fix command line.

            if strcmp(obj.outType, 'tcl')
                fprintf(fid, 'fix %d', tag);
                for i = 1:numel(dofs)
                    fprintf(fid, ' %d', dofs{i});
                end
                fprintf(fid, '\n');
            else
                fprintf(fid, 'ops.fix(%d', tag);
                for i = 1:numel(dofs)
                    fprintf(fid, ', %d', dofs{i});
                end
                fprintf(fid, ');\n');
            end
        end

        function key = makeKey(~, dim, etag)
            %MAKEKEY Build a map key from dimension and entity tag.
            key = sprintf('%d_%d', dim, etag);
        end

        function pair = parseKey(~, key)
            %PARSEKEY Parse a map key into `[dim, entityTag]`.
            vals = sscanf(key, '%d_%d');
            pair = vals(:).';
        end

        function [entities, physicalGroups, dimEntityTags] = retrieveEntities(obj, lines, entitiesIdx, physicalTagNameMap)
            %RETRIEVEENTITIES Parse the `$Entities` block.

            entities = containers.Map('KeyType', 'char', 'ValueType', 'any');
            physicalGroups = containers.Map('KeyType', 'char', 'ValueType', 'any');

            idx = entitiesIdx(1) + 1;
            nums = sscanf(lines{idx}, '%d %d %d %d');
            numPoint = nums(1);
            numCurve = nums(2);
            numSurf  = nums(3);
            numVol   = nums(4);
            idx = idx + 1;

            dimEntityTags = zeros(0, 2);

            [idx, dimEntityTags] = obj.parseEntitiesBlock(lines, idx, 0, numPoint, physicalTagNameMap, entities, physicalGroups, dimEntityTags);
            [idx, dimEntityTags] = obj.parseEntitiesBlock(lines, idx, 1, numCurve, physicalTagNameMap, entities, physicalGroups, dimEntityTags);
            [idx, dimEntityTags] = obj.parseEntitiesBlock(lines, idx, 2, numSurf,  physicalTagNameMap, entities, physicalGroups, dimEntityTags);
            [idx, dimEntityTags] = obj.parseEntitiesBlock(lines, idx, 3, numVol,   physicalTagNameMap, entities, physicalGroups, dimEntityTags);
        end

        function [idx, dimEntityTags] = parseEntitiesBlock(obj, lines, idx, dim, num, physicalTagNameMap, entities, physicalGroups, dimEntityTags)
            %PARSEENTITIESBLOCK Parse one dimension block within `$Entities`.

            for ii = 1:num
                parts = sscanf(lines{idx}, '%f')';
                tag = parts(1);

                data = struct();
                if dim == 0
                    data.Coord = parts(2:4);
                    offset = 5;
                else
                    data.CoordBoundary = parts(2:7);
                    offset = 8;
                end

                numTags = parts(offset);
                physicalTags = parts(offset+1 : offset+numTags);

                for p = 1:numel(physicalTags)
                    ptag = physicalTags(p);
                    mapKey = obj.makeKey(dim, ptag);
                    if ~isKey(physicalTagNameMap, mapKey)
                        error('(dim=%d, physical tag=%d) has no physical name set!', dim, ptag);
                    end
                    pname = physicalTagNameMap(mapKey);
                    if ~isKey(physicalGroups, pname)
                        physicalGroups(pname) = zeros(0, 2);
                    end
                    physicalGroups(pname) = [physicalGroups(pname); dim, tag];
                end

                data.physicalTags = physicalTags(:)';
                data.numPhysicalTags = numTags;

                if dim > 0
                    numBound = parts(offset + 1 + numTags);
                    boundStart = offset + 2 + numTags;
                    data.numBound = numBound;
                    data.BoundTags = parts(boundStart : boundStart + numBound - 1);
                else
                    data.numBound = 0;
                    data.BoundTags = [];
                end

                key = obj.makeKey(dim, tag);
                entities(key) = data;
                dimEntityTags(end+1,:) = [dim, tag]; %#ok<AGROW>
                idx = idx + 1;
            end
        end

        function physicalTagNameMap = retrievePhysicalGroups(obj, lines, physicalIdx)
            %RETRIEVEPHYSICALGROUPS Parse the `$PhysicalNames` block.

            physicalTagNameMap = containers.Map('KeyType', 'char', 'ValueType', 'char');

            if isempty(physicalIdx)
                return;
            end

            idx = physicalIdx(1) + 1;
            num = str2double(lines{idx});
            fprintf('Info:: %d Physical Names.\n', num);

            expr = '^(\d+)\s+(\d+)\s+"(.*)"$';
            for i = 1:num
                idx = idx + 1;
                tok = regexp(lines{idx}, expr, 'tokens', 'once');
                if isempty(tok)
                    error('Not all physical groups have names set.');
                end
                dim = str2double(tok{1});
                tag = str2double(tok{2});
                name = tok{3};
                physicalTagNameMap(obj.makeKey(dim, tag)) = name;
            end
        end

        function [nodesMap, allNodeTags] = retrieveNodes(obj, lines, nodeIdx)
            %RETRIEVENODES Parse the `$Nodes` block.

            nodesMap = containers.Map('KeyType', 'char', 'ValueType', 'any');
            allNodeTags = zeros(0,1);

            idx = nodeIdx(1) + 1;
            contents = sscanf(lines{idx}, '%d %d %d %d');
            numNodes = contents(2);
            minNodeTag = contents(3);
            maxNodeTag = contents(4);
            fprintf('Info:: %d Nodes; MaxNodeTag %d; MinNodeTag %d.\n', numNodes, maxNodeTag, minNodeTag);

            idx = nodeIdx(1) + 2;

            while idx < nodeIdx(2)
                head = sscanf(lines{idx}, '%d %d %d %d');
                dim = head(1);
                etag = head(2);
                numNodesInBlock = head(4);

                block = repmat(struct('tag', 0, 'coords', []), numNodesInBlock, 1);

                for i = 1:numNodesInBlock
                    tag = str2double(lines{idx + i});
                    coord = sscanf(lines{idx + numNodesInBlock + i}, '%f')';
                    block(i).tag = tag;
                    block(i).coords = coord;
                    allNodeTags(end+1,1) = tag; %#ok<AGROW>
                end

                nodesMap(obj.makeKey(dim, etag)) = block;
                idx = idx + 2*numNodesInBlock + 1;
            end
        end

        function [elesMap, allEleTags] = retrieveEles(obj, lines, eleIdx)
            %RETRIEVEELES Parse the `$Elements` block.

            elesMap = containers.Map('KeyType', 'char', 'ValueType', 'any');
            allEleTags = zeros(0,1);

            idx = eleIdx(1) + 1;
            contents = sscanf(lines{idx}, '%d %d %d %d');
            numEles = contents(2);
            minEleTag = contents(3);
            maxEleTag = contents(4);
            fprintf('Info:: %d Elements; MaxEleTag %d; MinEleTag %d.\n', numEles, maxEleTag, minEleTag);

            idx = eleIdx(1) + 2;

            while idx < eleIdx(2)
                head = sscanf(lines{idx}, '%d %d %d %d');
                dim = head(1);
                etag = head(2);
                eleType = head(3);
                numElesInBlock = head(4);

                if ismember(eleType, obj.OPS_GMSH_ELE_TYPE)
                    block = repmat(struct('tag', 0, 'nodeTags', [], 'eleType', 0), numElesInBlock, 1);
                    count = 0;

                    for i = 1:numElesInBlock
                        info = sscanf(lines{idx + i}, '%d')';
                        tag = info(1);
                        nodeTags = obj.reshapeEleNodeOrder(eleType, info(2:end));

                        count = count + 1;
                        block(count).tag = tag;
                        block(count).nodeTags = nodeTags;
                        block(count).eleType = eleType;

                        allEleTags(end+1,1) = tag; %#ok<AGROW>
                    end

                    elesMap(obj.makeKey(dim, etag)) = block(1:count);
                end

                idx = idx + numElesInBlock + 1;
            end
        end

        function tags = reshapeEleNodeOrder(obj, eleType, nodeTags)
            %RESHAPEELE_NODE_ORDER Reorder node tags for selected higher-order elements.

            switch eleType
                case 11
                    tags = obj.reshapeTetN10(nodeTags);
                case 17
                    tags = obj.reshapeHexN20(nodeTags);
                case 12
                    tags = obj.reshapeHexN27(nodeTags);
                otherwise
                    tags = nodeTags;
            end
        end

        function tags = reshapeTetN10(~, nodeTags)
            %RESHAPETETN10 Reorder 10-node tetrahedron node tags.

            tags = [ ...
                nodeTags(1), nodeTags(2), nodeTags(3), nodeTags(4), ...
                nodeTags(5), nodeTags(6), nodeTags(7), nodeTags(8), ...
                nodeTags(10), nodeTags(9)];
        end

        function tags = reshapeHexN20(~, nodeTags)
            %RESHAPEHEXN20 Reorder 20-node hexahedron node tags.

            tags = [ ...
                nodeTags(1), nodeTags(2), nodeTags(3), nodeTags(4), ...
                nodeTags(5), nodeTags(6), nodeTags(7), nodeTags(8), ...
                nodeTags(9), nodeTags(12), nodeTags(14), nodeTags(10), ...
                nodeTags(17), nodeTags(19), nodeTags(20), nodeTags(18), ...
                nodeTags(11), nodeTags(13), nodeTags(15), nodeTags(16)];
        end

        function tags = reshapeHexN27(~, nodeTags)
            %RESHAPEHEXN27 Reorder 27-node hexahedron node tags.

            tags = [ ...
                nodeTags(1), nodeTags(2), nodeTags(3), nodeTags(4), ...
                nodeTags(5), nodeTags(6), nodeTags(7), nodeTags(8), ...
                nodeTags(9), nodeTags(12), nodeTags(14), nodeTags(10), ...
                nodeTags(17), nodeTags(19), nodeTags(20), nodeTags(18), ...
                nodeTags(11), nodeTags(13), nodeTags(15), nodeTags(16), ...
                nodeTags(21), nodeTags(22), nodeTags(23), nodeTags(24), ...
                nodeTags(25), nodeTags(26), nodeTags(27)];
        end

        function boundaryDimTags = getBoundaryDimTagsRecursive(obj, boundaryDimTags, dimEntityTags)
            %GETBOUNDARYDIMTAGSRECURSIVE Recursively collect boundary entities.

            for i = 1:size(dimEntityTags, 1)
                dim = dimEntityTags(i,1);
                etag = dimEntityTags(i,2);
                if dim <= 0
                    continue;
                end
                key = obj.makeKey(dim, etag);
                if ~isKey(obj.gmshEntities, key)
                    continue;
                end
                entity = obj.gmshEntities(key);
                boundTags = entity.BoundTags;
                boundDimTags = [repmat(dim-1, numel(boundTags), 1), abs(boundTags(:))];
                boundaryDimTags = [boundaryDimTags; boundDimTags]; %#ok<AGROW>
                boundaryDimTags = obj.getBoundaryDimTagsRecursive(boundaryDimTags, boundDimTags);
            end
        end
    end
end