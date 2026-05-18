
classdef ODB2 < handle
    % Output database for OpenSees response data.
    % =====================================================================
    properties (Access = private)
        ops
        outputDir       string
        respFilename    string
        storePath       string
        filename        string

        odbTag
        kargs           struct

        OPS_recorderTag double

    end

    % =====================================================================
    methods

        % -----------------------------------------------------------------
        function obj = ODB2(ops, odbTag, options)
            arguments
                ops
                odbTag
                options.flushEvery                       = 20

                options.saveNodalResp           logical = true
                options.saveFrameResp           logical = true
                options.saveTrussResp           logical = true
                options.saveLinkResp            logical = true
                options.saveShellResp           logical = true
                options.saveFiberSecResp        logical = false
                options.savePlaneResp           logical = true
                options.saveSolidResp           logical = true
                options.saveContactResp         logical = true
                options.saveSensitivityResp     logical = false

                options.nodeTags                double = []
                options.frameTags               double = []
                options.trussTags               double = []
                options.linkTags                double = []
                options.shellTags               double = []
                options.planeTags               double = []
                options.solidTags               double = []
                options.contactTags             double = []

                options.elasticFrameSecPoints   double {mustBeInteger, mustBePositive} = 7
                options.interpolateBeamDisp            = false
                options.computeMechanicalMeasures      = {"principal", "tauMax", "octahedral", "vonMises"}
                options.projectGaussToNodes     string = "copy"
            end

            obj.ops         = ops;
            obj.odbTag      = odbTag;

            obj.kargs       = options;
        end

        function setFEMDataRecorder(obj)
            % Build cell array of arguments for FEMDataRecorder.
            % Switch options (e.g. -saveNodalResp) are passed without a
            % boolean value; they enable the feature simply by being present.
            kargs = {obj.filename, '-flushEvery', obj.kargs.flushEvery};

            if obj.kargs.saveNodalResp
                kargs = {kargs{:}, '-saveNodalResp'};
                if ~isempty(obj.kargs.nodeTags)
                    tagCell = num2cell(obj.kargs.nodeTags);
                    kargs = {kargs{:}, tagCell{:}};
                end
            end
            if obj.kargs.saveTrussResp
                kargs = {kargs{:}, '-saveTrussResp'};
                if ~isempty(obj.kargs.trussTags)
                    tagCell = num2cell(obj.kargs.trussTags);
                    kargs = {kargs{:}, tagCell{:}};
                end
            end
            if obj.kargs.saveFrameResp
                kargs = {kargs{:}, '-saveFrameResp'};
                if ~isempty(obj.kargs.frameTags)
                    tagCell = num2cell(obj.kargs.frameTags);
                    kargs = {kargs{:}, tagCell{:}};
                end
            end
            if obj.kargs.saveFiberSecResp
                kargs = {kargs{:}, '-saveFrameFiber'};
            end
            if obj.kargs.saveShellResp
                kargs = {kargs{:}, '-saveShellResp'};
                if ~isempty(obj.kargs.shellTags)
                    tagCell = num2cell(obj.kargs.shellTags);
                    kargs = {kargs{:}, tagCell{:}};
                end
            end
            if obj.kargs.saveSolidResp
                kargs = {kargs{:}, '-saveSolidResp'};
                if ~isempty(obj.kargs.solidTags)
                    tagCell = num2cell(obj.kargs.solidTags);
                    kargs = {kargs{:}, tagCell{:}};
                end
            end
            if obj.kargs.savePlaneResp
                kargs = {kargs{:}, '-savePlaneResp'};
                if ~isempty(obj.kargs.planeTags)
                    tagCell = num2cell(obj.kargs.planeTags);
                    kargs = {kargs{:}, tagCell{:}};
                end
            end
            if obj.kargs.saveLinkResp
                kargs = {kargs{:}, '-saveLinkResp'};
                if ~isempty(obj.kargs.linkTags)
                    tagCell = num2cell(obj.kargs.linkTags);
                    kargs = {kargs{:}, tagCell{:}};
                end
            end
            if obj.kargs.saveContactResp
                kargs = {kargs{:}, '-saveContactResp'};
                if ~isempty(obj.kargs.contactTags)
                    tagCell = num2cell(obj.kargs.contactTags);
                    kargs = {kargs{:}, tagCell{:}};
                end
            end

            kargs = {kargs{:}, '-elasticFrameSecPoints', obj.kargs.elasticFrameSecPoints};
            kargs = {kargs{:}, '-interpolateBeamDisp', obj.kargs.interpolateBeamDisp};
            kargs = {kargs{:}, '-stressMeasures', obj.kargs.computeMechanicalMeasures{:}};
            kargs = {kargs{:}, '-projectGaussToNodes', obj.kargs.projectGaussToNodes};

            obj.OPS_recorderTag = obj.ops.FEMDataRecorder(kargs{:});
        end

        function setOutputDir(obj, dir)
            obj.outputDir    = string(dir);
            obj.respFilename = "Responses";
            post.ODB2.sharedConfig('set', obj.outputDir);
            obj.storePath = fullfile(obj.outputDir, ...
                sprintf('%s-%s.odb', obj.respFilename, string(obj.odbTag)));
            obj.initPath();
            obj.filename = fullfile(char(obj.storePath), 'output.h5');
        end

        function close(obj)
            tag = obj.OPS_recorderTag;
            if ~isempty(tag)
                obj.ops.remove('recorder', tag);
            end
        end

    end

    % =====================================================================
    methods (Access = private)
        % -----------------------------------------------------------------
        function initPath(obj)
            d = char(obj.storePath);
            if exist(d, 'dir')
                listing = dir(d);
                for i = 1:numel(listing)
                    n = listing(i).name;
                    if strcmp(n,'.') || strcmp(n,'..'), continue; end
                    full = fullfile(d, n);
                    if listing(i).isdir
                        rmdir(full, 's');
                    else
                        delete(full);
                    end
                end
            else
                mkdir(d);
            end
        end
    end

    % =====================================================================
    methods (Static, Access = private)
        % -----------------------------------------------------------------
        function outDir = sharedConfig(action, newDir)
            % Persistent getter/setter for the shared output directory.
            %   sharedConfig('get')        – return current outputDir
            %   sharedConfig('set', dir)   – update outputDir, return new value
            persistent dir
            if isempty(dir)
                dir = ".openseesmatlab.output";
            end
            if nargin >= 1 && strcmp(action, 'set') && nargin >= 2
                dir = string(newDir);
            end
            outDir = dir;
        end

        function filename = getFilename(odbTag)
            outputDir    = post.ODB2.sharedConfig("get");
            respFilename = "Responses";
            storePath = fullfile(outputDir, ...
                sprintf("%s-%s.odb", respFilename, string(odbTag)));
            filename = fullfile(char(storePath), "output.h5");
        end

        function args = buildArgs(options)
            % Build key-value argument list for C++ readFEMData.
            args = {};
            if isfield(options, "eleTags") && ~isempty(options.eleTags)
                args = [args, {"eleTags", options.eleTags}];
            end
            if isfield(options, "nodeTags") && ~isempty(options.nodeTags)
                args = [args, {"nodeTags", options.nodeTags}];
            end
            if isfield(options, "respType") && strlength(options.respType) > 0
                args = [args, {"respType", char(options.respType)}];
            end
        end

        function [groups, respName] = eleTypeMap(eleType)
            switch lower(char(eleType))
                case {"frame", "beam"}
                    groups = "frame";   respName = "FrameResponses";
                case "plane"
                    groups = "plane";   respName = "PlaneResponses";
                case {"solid", "brick"}
                    groups = "solid";   respName = "SolidResponses";
                case "shell"
                    groups = "shell";   respName = "ShellResponses";
                case "truss"
                    groups = "truss";   respName = "TrussResponses";
                case "link"
                    groups = "link";    respName = "LinkResponses";
                case "contact"
                    groups = "contact"; respName = "ContactResponses";
                otherwise
                    error("Unknown element type: %s", eleType);
            end
        end
    end

    methods (Static, Access = public)

        %% Core loader ----------------------------------------------------
        function odb = loadODB(ops, odbTag, options)
            % loadODB  Load an ODB database.
            %
            % Syntax:
            %   odb = ODB2.loadODB(ops, odbTag)
            %   odb = ODB2.loadODB(ops, odbTag, groups="model")
            %
            % Inputs:
            %   ops     – OpenSees MEX interface object
            %   odbTag  – ODB tag (string or numeric)
            %   options.groups – query type (default "" reads everything)
            %       "model", "nodal", "frame", "beam", "truss", "plane",
            %       "shell", "solid", "brick", "link", "contact", "all"
            %
            % Output:
            %   odb – scalar struct (single stage) or struct array (multi stage)
            %         with fields .model, .results, .time

            arguments
                ops
                odbTag
                options.groups  string = ""
            end

            filename = post.ODB2.getFilename(odbTag);

            if all(strlength(options.groups) == 0)
                odb = ops.readFEMData(filename);
            else
                odb = ops.readFEMData(filename, options.groups);
            end
        end

        %% Model info -----------------------------------------------------
        function data = readModelInfo(ops, odbTag)
            % readModelInfo  Read model geometry.
            %
            % Output fields:
            %   .Nodes.Tags, .Nodes.Coords
            %   .Elements.Tags, .Elements.Types, .Elements.Connectivity, .Elements.NodeTags

            data = post.ODB2.loadODB(ops, odbTag, groups="model");
            data = addField(data, 'odbTag', odbTag);
        end

        %% Nodal responses ------------------------------------------------
        function data = readNodeResponse(ops, odbTag, options)
            % readNodeResponse  Read nodal responses.
            %
            % Syntax:
            %   data = ODB2.readNodeResponse(ops, odbTag)
            %   data = ODB2.readNodeResponse(ops, odbTag, nodeTags=[1,2,3])
            %   data = ODB2.readNodeResponse(ops, odbTag, respType="disp")
            %
            % Inputs:
            %   options.nodeTags – node tag filter (default [] = all)
            %   options.respType – response type (default "" = all)
            %       "disp", "vel", "accel", "reaction",
            %       "reactionIncInertia", "rayleighForces", "pressure"
            %
            % Output:
            %   data – scalar struct (single stage) or struct array (multi stage)
            %          fields: .nodeTags, .disp, .vel, .accel, ...
            %          plus .odbTag and .time on every element

            arguments
                ops
                odbTag
                options.nodeTags  double = []
                options.respType  string = ""
            end

            filename = post.ODB2.getFilename(odbTag);
            args = post.ODB2.buildArgs(options);
            data = ops.readFEMData(filename, "nodal", args{:});
            data = addField(data, 'odbTag', odbTag);
        end

        %% Element responses ----------------------------------------------
        function data = readElementResponse(ops, odbTag, options)
            % readElementResponse  Read element responses.
            %
            % Syntax:
            %   data = ODB2.readElementResponse(ops, odbTag, eleType="solid")
            %   data = ODB2.readElementResponse(ops, odbTag, eleType="solid", eleTags=[1,2])
            %   data = ODB2.readElementResponse(ops, odbTag, eleType="solid", respType="StressAtNode")
            %
            % Inputs:
            %   options.eleType  – element type (required)
            %   options.eleTags  – element tag filter (default [] = all)
            %   options.respType – response type (default "" = all)
            %
            % Output (solid example):
            %   data – scalar struct (single stage) or struct array (multi stage)
            %          fields: .eleTags, .nodeTags, .StressAtNode, ...
            %          plus .odbTag, .eleType and .time on every element

            arguments
                ops
                odbTag
                options.eleType   string = ""
                options.eleTags   double = []
                options.respType  string = ""
            end

            [groups, respName] = post.ODB2.eleTypeMap(options.eleType);
            filename = post.ODB2.getFilename(odbTag);
            args = post.ODB2.buildArgs(options);
            data = ops.readFEMData(filename, groups, args{:});

            data = addField(data, 'odbTag', odbTag);
            data = addField(data, 'eleType', options.eleType);

        end

    end

end

function s = addField(s, fieldName, value)
    % Add a field to scalar struct or struct array
    if isscalar(s)
        s.(fieldName) = value;
    else
        for i = 1:numel(s)
            s(i).(fieldName) = value;
        end
    end
end

%     methods (Static, Access = public)
%         function odb = loadODB(ops, odbTag, options)
%             % 'model', 'nodal', 'frame', 'truss', 'plane', 'shell', 'solid', 'link', 'contact', 'all'
%             arguments
%                 ops
%                 odbTag
%                 options.groups  string = ""
%             end

%             outputDir    = post.ODB2.sharedConfig('get');
%             respFilename = "Responses";

%             storePath = fullfile(outputDir, ...
%                 sprintf('%s-%s.odb', respFilename, string(odbTag)));
%             filename = fullfile(char(storePath), 'output.h5');

%             % Fast path: read only the requested groups directly from HDF5,
%             % skipping deserialisation of everything else.
%             if any(strlength(options.groups) > 0)
%                 odb = ops.readFEMData(filename, options.groups);
%             else
%                 odb = ops.readFEMData(filename);
%             end
%         end

%         function data = readModelInfo(ops, odbTag)
%             odb = post.ODB2.loadODB(ops, odbTag, groups="model");
%             if isscalar(odb)
%                 data = odb.model;
%                 data = readModelInfo(data);
%                 if ~isempty(data)
%                     data.odbTag = odbTag;
%                 end
%             else
%                 n = numel(odb);
%                 data = struct();
%                 for i = 1:n
%                     d = readModelInfo(odb(i).model);
%                     if ~isempty(d)
%                         d.time = odb(i).time;
%                         d.odbTag = odbTag;
%                     end
%                     data = post.ODB2.mergeStructArrayElement(data, d, i);
%                 end
%             end
%         end

%         function data = readNodeResponse(ops, odbTag, options)
%             arguments
%                 ops
%                 odbTag
%                 options.nodeTags    double = []
%                 options.respType    string = ""
%             end

%             odb  = post.ODB2.loadODB(ops, odbTag, groups="nodal");

%             if isscalar(odb)
%                 data = odb.results.NodalResponses;
%                 data = readNodeResponse( ...
%                     data, ...
%                     nodeTags = options.nodeTags, ...
%                     respType = options.respType);
%                 if ~isempty(data)
%                     data.odbTag = odbTag;
%                     data.time = odb.time;
%                 end
%             else
%                 n = numel(odb);
%                 data = struct();
%                 for i = 1:n
%                     d = readNodeResponse( ...
%                         odb(i).results.NodalResponses, ...
%                         nodeTags = options.nodeTags, ...
%                         respType = options.respType);
%                     if ~isempty(d)
%                         d.odbTag = odbTag;
%                         d.time = odb(i).time;
%                     end
%                     data = post.ODB2.mergeStructArrayElement(data, d, i);
%                 end
%             end
%         end

%         function data = readElementResponse(ops, odbTag, options)
%             arguments
%                 ops
%                 odbTag
%                 options.eleType     string = ""
%                 options.eleTags     double = []
%                 options.respType    string = ""
%             end

%             respName = '';

%             switch lower(char(options.eleType))
%                 case {'frame','beam'}
%                     groups = 'frame';
%                     respName = 'FrameResponses';
%                 case {'plane'}
%                     groups = 'plane';
%                     respName = 'PlaneResponses';
%                 case {'solid', 'brick'}
%                     groups = 'solid';
%                     respName = 'SolidResponses';
%                 case {'shell'}
%                     groups = 'shell';
%                     respName = 'ShellResponses';
%                 case {'truss'}
%                     groups = 'truss';
%                     respName = 'TrussResponses';
%                 case {'link'}
%                     groups = 'link';
%                     respName = 'LinkResponses';
%                 case {'contact'}
%                     groups = 'contact';
%                     respName = 'ContactResponses';
%                 otherwise
%                     error('Unknown element type: %s', options.eleType);
%             end

%             odb  = post.ODB2.loadODB(ops, odbTag, groups=groups);

%             % Select the response reader function once
%             switch lower(char(options.eleType))
%                 case {'frame','beam'}
%                     respReader = @(d) readFrameResponse(d, eleTags=options.eleTags, respType=options.respType);
%                 case {'plane'}
%                     respReader = @(d) readPlaneResponse(d, eleTags=options.eleTags, respType=options.respType);
%                 case {'solid', 'brick'}
%                     respReader = @(d) readSolidResponse(d, eleTags=options.eleTags, respType=options.respType);
%                 case {'shell'}
%                     respReader = @(d) readShellResponse(d, eleTags=options.eleTags, respType=options.respType);
%                 case {'truss'}
%                     respReader = @(d) readTrussResponse(d, eleTags=options.eleTags, respType=options.respType);
%                 case {'link'}
%                     respReader = @(d) readLinkResponse(d, eleTags=options.eleTags, respType=options.respType);
%                 case {'contact'}
%                     respReader = @(d) readContactResponse(d, eleTags=options.eleTags, respType=options.respType);
%             end

%             if isscalar(odb)
%                 data = odb.results.(respName);
%                 data = respReader(data);
%                 if ~isempty(data)
%                     data.odbTag = odbTag;
%                     data.eleType = options.eleType;
%                     data.time = odb.time;
%                 end
%             else
%                 n = numel(odb);
%                 data = struct();
%                 for i = 1:n
%                     d = respReader(odb(i).results.(respName));
%                     if ~isempty(d)
%                         d.odbTag = odbTag;
%                         d.eleType = options.eleType;
%                         d.time = odb(i).time;
%                     end
%                     data = post.ODB2.mergeStructArrayElement(data, d, i);
%                 end
%             end
%         end

%         function data = mergeStructArrayElement(data, elem, idx)
%             %MERGESTRUCTARRAYELEMENT Safely assign elem into data(idx).
%             %
%             % Handles the case where data or elem may be empty structs
%             % with mismatched fields.
%             if idx == 1
%                 data = elem;
%                 return;
%             end

%             elemFn = fieldnames(elem);
%             dataFn = fieldnames(data);
%             elemEmpty = isempty(elemFn);
%             dataEmpty = isempty(dataFn);

%             if elemEmpty && dataEmpty
%                 % both empty, just expand
%                 data(idx) = elem;
%             elseif elemEmpty
%                 % data has fields, elem doesn't: create placeholder
%                 placeholder = data(1);
%                 fn = dataFn;
%                 for k = 1:numel(fn)
%                     placeholder.(fn{k}) = [];
%                 end
%                 data(idx) = placeholder;
%             elseif dataEmpty
%                 % elem has fields, data doesn't: rebuild from scratch
%                 % Pre-allocate with empty placeholders, then set elem at idx
%                 fn = elemFn;
%                 placeholder = elem;
%                 for k = 1:numel(fn)
%                     placeholder.(fn{k}) = [];
%                 end
%                 newData(idx) = elem;
%                 for j = 1:idx-1
%                     newData(j) = placeholder;
%                 end
%                 data = newData;
%             else
%                 % Both have fields: normal assignment
%                 % Ensure field compatibility
%                 missingInElem = setdiff(dataFn, elemFn, 'stable');
%                 missingInData = setdiff(elemFn, dataFn, 'stable');
%                 if ~isempty(missingInElem)
%                     for k = 1:numel(missingInElem)
%                         elem.(missingInElem{k}) = [];
%                     end
%                 end
%                 if ~isempty(missingInData)
%                     for k = 1:numel(missingInData)
%                         data(1).(missingInData{k}) = [];
%                     end
%                 end
%                 data(idx) = elem;
%             end
%         end
%     end
% end



% function out = readModelInfo(respData, dataType)
%     if nargin < 2
%         dataType = '';
%     end

%     if isempty(dataType)
%         out = respData;
%     elseif isfield(respData, dataType)
%         out = respData.(dataType);
%     else
%         out = [];
%     end
% end


% function S = readNodeResponse(data, options)
%     %READRESPONSE Read merged nodal response data using an array-oriented interface.

%     arguments
%         data
%         options.nodeTags double = []
%         options.respType string = ""
%     end

%     if ~isfield(data, 'nodeTags')
%         S = struct();
%         return;
%     end

%     DOFs = {'ux','uy','uz','rx','ry','rz'};
%     respTypes = {'disp','vel','accel','reaction','reactionIncInertia', ...
%                 'rayleighForces','pressure'};

%     % Filter to one response type if requested
%     if strlength(options.respType) > 0
%         if ~ismember(options.respType, respTypes)
%             error('readResponse:InvalidRespType', ...
%                 'Unknown respType "%s". Valid types: %s', ...
%                 options.respType, strjoin(respTypes, ', '));
%         end
%         respTypes = {char(options.respType)};
%     end

%     % Resolve requested node subset
%     allNodeTags = data.nodeTags(:).';
%     selectAll   = isempty(options.nodeTags);

%     if selectAll
%         selectedTags = allNodeTags;
%         nodeIdx = [];
%     else
%         queryTags = double(options.nodeTags(:).');
%         [tf, nodeIdx] = ismember(queryTags, allNodeTags);
%         if ~all(tf)
%             missing = queryTags(~tf);
%             error('readResponse:InvalidNodeTags', ...
%                 'Node tags not found in data: %s', mat2str(missing));
%         end
%         selectedTags = allNodeTags(nodeIdx);
%     end

%     S = struct();
%     S.nodeTags    = selectedTags(:);

%     for k = 1:numel(respTypes)
%         rt = respTypes{k};
%         if ~isfield(data, rt), continue; end

%         d = data.(rt);

%         if strcmp(rt, 'pressure')
%             if ismatrix(d)
%                 if ~selectAll, d = d(:, nodeIdx); end
%             elseif ndims(d) == 3
%                 if ~selectAll, d = d(:, nodeIdx, :); end
%                 d = d(:, :, 1);
%             else
%                 continue;
%             end
%             S.pressure = d;
%         else
%             if ndims(d) ~= 3, continue; end
%             if ~selectAll, d = d(:, nodeIdx, :); end

%             nDOF = min(size(d, 3), numel(DOFs));
%             S.(rt) = struct();
%             for di = 1:nDOF
%                 S.(rt).(DOFs{di}) = d(:, :, di);
%             end
%         end
%     end

%     % Pass through interpolation arrays without node filtering
%     if isfield(data, 'interpolateDisp')
%         S.interpolatePoints = data.interpolatePoints;
%         if isfield(data, 'interpolateDisp'),   S.interpolateDisp   = data.interpolateDisp;   end
%         if isfield(data, 'interpolateCells'),  S.interpolateCells  = data.interpolateCells;  end
%         if isfield(data, 'interpolateCoords'), S.interpolateCoords = data.interpolateCoords; end
%     end
% end

% function S = readFrameResponse(data, options)
%     arguments
%         data
%         options.eleTags double = []
%         options.respType string = ""
%     end

%     if ~isfield(data, "eleTags")
%         S = struct();
%         return;
%     end


%     respTypes = { ...
%         'localForces', ...
%         'basicForces', ...
%         'basicDeformations', ...
%         'plasticDeformation', ...
%         'sectionForces', ...
%         'sectionDeformations', ...
%         'sectionLocs'};

%     localDofs = {'FxI','FyI','FzI','MxI','MyI','MzI', ...
%                 'FxJ','FyJ','FzJ','MxJ','MyJ','MzJ'};
%     basicDofs = {'N','MzI','MzJ','MyI','MyJ','T'};
%     secDofs   = {'N','Mz','Vy','My','Vz','T'};

%     if strlength(options.respType) > 0
%         rt = char(options.respType);
%         if ~ismember(rt, respTypes)
%             error('readResponse:InvalidRespType', ...
%                 'Unknown respType "%s". Valid types: %s', ...
%                 options.respType, strjoin(respTypes, ', '));
%         end
%         respTypes = {rt};
%     end

%     allEleTags = double(data.eleTags(:).');
%     selectAll = isempty(options.eleTags);

%     if selectAll
%         eleIdx = [];
%         selectedTags = allEleTags;
%     else
%         queryTags = double(options.eleTags(:).');
%         [tf, eleIdx] = ismember(queryTags, allEleTags);
%         if ~all(tf)
%             missing = queryTags(~tf);
%             error('readResponse:InvalidEleTags', ...
%                 'Element tags not found in data: %s', mat2str(missing));
%         end
%         selectedTags = allEleTags(eleIdx);
%     end

%     S = struct();
%     S.eleTags = selectedTags(:);

%     for k = 1:numel(respTypes)
%         rt = respTypes{k};
%         if ~isfield(data, rt)
%             continue;
%         end

%         d = data.(rt);
%         if isempty(d) || ~isnumeric(d)
%             continue;
%         end

%         switch rt
%             case 'localForces'
%                 if ndims(d) ~= 3, continue; end
%                 if ~selectAll, d = d(:, eleIdx, :); end
%                 nDof = min(size(d, 3), numel(localDofs));
%                 S.(rt) = struct();
%                 for di = 1:nDof
%                     S.(rt).(localDofs{di}) = d(:, :, di);
%                 end

%             case {'basicForces', 'basicDeformations', 'plasticDeformation'}
%                 if ndims(d) ~= 3, continue; end
%                 if ~selectAll, d = d(:, eleIdx, :); end
%                 nDof = min(size(d, 3), numel(basicDofs));
%                 S.(rt) = struct();
%                 for di = 1:nDof
%                     S.(rt).(basicDofs{di}) = d(:, :, di);
%                 end

%             case {'sectionForces', 'sectionDeformations'}
%                 if ndims(d) ~= 4, continue; end
%                 if ~selectAll, d = d(:, eleIdx, :, :); end
%                 nDof = min(size(d, 4), numel(secDofs));
%                 S.(rt) = struct();
%                 for di = 1:nDof
%                     S.(rt).(secDofs{di}) = d(:, :, :, di);
%                 end

%             case 'sectionLocs'
%                 if ndims(d) ~= 4, continue; end
%                 if ~selectAll, d = d(:, eleIdx, :, :); end
%                 if isfield(data, 'secLocDofs') && ~isempty(data.secLocDofs)
%                     locDofs = data.secLocDofs;
%                     nLoc = min(size(d, 4), numel(locDofs));
%                 else
%                     nLoc = size(d, 4);
%                     locDofs = arrayfun( ...
%                         @(i) sprintf('loc%d', i), 1:nLoc, ...
%                         'UniformOutput', false);
%                 end
%                 S.sectionLocs = struct();
%                 for di = 1:nLoc
%                     S.sectionLocs.(lower(locDofs{di})) = d(:, :, :, di);
%                 end
%         end
%     end
% end



% function S = readLinkResponse(data, options)
%     arguments
%         data
%         options.eleTags  double = []
%         options.respType string = ""
%     end

%     if ~isfield(data, "eleTags")
%         S = struct();
%         return;
%     end

%     allRespTypes = {'basicDeformation','basicForce'};

%     if strlength(options.respType) > 0
%         rt = char(options.respType);
%         if ~ismember(rt, allRespTypes)
%             error('readResponse:InvalidRespType', ...
%                 'Unknown respType "%s". Valid: %s', rt, strjoin(allRespTypes,', '));
%         end
%         respTypes = {rt};
%     else
%         respTypes = allRespTypes;
%     end

%     allEleTags = data.eleTags(:).';
%     selectAll  = isempty(options.eleTags);

%     if selectAll
%         eleIdx       = [];
%         selectedTags = allEleTags;
%     else
%         queryTags = options.eleTags(:).';
%         [tf, eleIdx] = ismember(queryTags, allEleTags);
%         if ~all(tf)
%             error('readResponse:InvalidEleTags', ...
%                 'Element tags not found: %s', mat2str(queryTags(~tf)));
%         end
%         selectedTags = allEleTags(eleIdx);
%     end

%     S             = struct();
%     S.eleTags     = selectedTags(:);

%     dofs = post.resp.LinkRespStepData.DOFS;

%     for k = 1:numel(respTypes)
%         rt = respTypes{k};
%         if ~isfield(data, rt); continue; end
%         d  = data.(rt);
%         if isempty(d) || ~isnumeric(d); continue; end

%         nd = ndims(d);
%         if ~selectAll
%             idx    = repmat({':'}, 1, nd);
%             idx{2} = eleIdx;
%             d      = d(idx{:});
%         end

%         nDof = min(size(d, 3), numel(dofs));
%         S.(rt) = struct();
%         for di = 1:nDof
%             S.(rt).(dofs{di}) = d(:, :, di);
%         end
%     end
% end


% function S = readPlaneResponse(data, options)
%     arguments
%         data
%         options.eleTags  double = []
%         options.nodeTags double = []
%         options.respType string = ""
%     end

%     if ~isfield(data, "eleTags")
%         S = struct();
%         return;
%     end

%     allRespTypes = { ...
%         'StressAtGP','StrainAtGP', ...
%         'StressAtNode','StrainAtNode', ...
%         'StressAtNodeErr','StrainAtNodeErr', ...
%         'PorePressureAtNode', ...
%         'StressMeasureAtGP','StressMeasureAtNode'};

%     respTypes = resolveRespTypes(allRespTypes, options.respType);

%     allEleTags = data.eleTags(:).';
%     [selectedTags, eleIdx] = resolveTagSelection( ...
%         allEleTags, options.eleTags, 'readResponse:InvalidEleTags', 'Element');
%     selectAllEle = isempty(options.eleTags);

%     nodeTypes = {'StressAtNode','StrainAtNode', ...
%                  'StressAtNodeErr','StrainAtNodeErr', ...
%                  'PorePressureAtNode','StressMeasureAtNode'};
%     [hasNodeTags, selectedNodeTags, nodeIdx] = resolveOptionalDataTagSelection( ...
%         data, 'nodeTags', options.nodeTags, respTypes, nodeTypes, ...
%         'readResponse:MissingNodeTags', 'readResponse:InvalidNodeTags', 'Node');
%     selectAllNode = isempty(options.nodeTags);

%     S             = struct();
%     S.eleTags     = selectedTags(:);
%     if hasNodeTags
%         S.nodeTags = selectedNodeTags(:);
%     end

%     eleTypes     = {'StressAtGP','StrainAtGP','StressMeasureAtGP'};
%     stressTypes  = {'StressAtGP','StressAtNode','StressAtNodeErr'};
%     strainTypes  = {'StrainAtGP','StrainAtNode','StrainAtNodeErr'};
%     measureTypes = {'StressMeasureAtGP','StressMeasureAtNode'};

%     nSD = size(data.StressAtGP, 4);
%     nED = size(data.StrainAtGP, 4);
%     stressDofs  = plane_stress_dof_labels(nSD);
%     strainDofs  = plane_strain_dof_labels(nED);

%     for k = 1:numel(respTypes)
%         rt = respTypes{k};
%         if ~isfield(data, rt); continue; end
%         d = data.(rt);
%         if isempty(d); continue; end

%         % ===== Stress/Strain: monolithic 4D array, split by component =====
%         if ismember(rt, [stressTypes, strainTypes])
%             if ~isnumeric(d); continue; end

%             if ismember(rt, strainTypes)
%                 dofs = strainDofs;
%             else
%                 dofs = stressDofs;
%             end

%             if ~selectAllNode && ismember(rt, nodeTypes)
%                 d = subsetSecondDim(d, nodeIdx);
%             end
%             if ~selectAllEle && ismember(rt, eleTypes)
%                 d = subsetSecondDim(d, eleIdx);
%             end

%             nd   = ndims(d);
%             nDof = min(size(d, nd), numel(dofs));
%             S.(rt) = struct();
%             for di = 1:nDof
%                 if nd == 4
%                     S.(rt).(dofs{di}) = d(:, :, :, di);
%                 else
%                     S.(rt).(dofs{di}) = d(:, :, di);
%                 end
%             end
%             continue;
%         end

%         % ===== PorePressure =====
%         if strcmp(rt, 'PorePressureAtNode')
%             S.(rt) = d;
%             continue;
%         end

%         % ===== Stress Measures: already split in HDF5 =====
%         if ismember(rt, measureTypes)
%             % d is a struct with fields: vonMises, principal, hydrostatic, tauMax
%             % principal is itself a struct with p1, p2, p3
%             if ~isstruct(d); continue; end

%             S.(rt) = struct();
%             fn = fieldnames(d);
%             for fi = 1:numel(fn)
%                 subName = fn{fi};
%                 subData = d.(subName);

%                 if isstruct(subData)
%                     % principal → p1, p2, p3
%                     S.(rt).(subName) = struct();
%                     subFn = fieldnames(subData);
%                     for sfi = 1:numel(subFn)
%                         S.(rt).(subName).(subFn{sfi}) = subsetMeasure(subData.(subFn{sfi}), ...
%                             rt, eleIdx, nodeIdx, selectAllEle, selectAllNode, eleTypes, nodeTypes);
%                     end
%                 else
%                     S.(rt).(subName) = subsetMeasure(subData, ...
%                         rt, eleIdx, nodeIdx, selectAllEle, selectAllNode, eleTypes, nodeTypes);
%                 end
%             end
%             continue;
%         end
%     end
% end

% function dOut = subsetMeasure(d, rt, eleIdx, nodeIdx, selectAllEle, selectAllNode, eleTypes, nodeTypes)
%     dOut = d;
%     if ~selectAllNode && ismember(rt, nodeTypes)
%         dOut = subsetSecondDim(dOut, nodeIdx);
%     end
%     if ~selectAllEle && ismember(rt, eleTypes)
%         dOut = subsetSecondDim(dOut, eleIdx);
%     end
% end

% function labels = plane_stress_dof_labels(n)
%     base = {'sxx','syy','szz','sxy'};
%     labels = cell(1, n);
%     for k = 1:n
%         if k <= numel(base)
%             labels{k} = base{k};
%         else
%             labels{k} = sprintf('para%d', k - numel(base));
%         end
%     end
% end

% function labels = plane_strain_dof_labels(n)
%     base = {'exx','eyy','exy'};
%     labels = cell(1, n);
%     for k = 1:n
%         if k <= numel(base)
%             labels{k} = base{k};
%         else
%             labels{k} = sprintf('para%d', k - numel(base));
%         end
%     end
% end


% function S = readSolidResponse(data, options)
%     arguments
%         data
%         options.eleTags  double = []
%         options.nodeTags double = []
%         options.respType string = ""
%     end

%     if ~isfield(data, "eleTags")
%         S = struct();
%         return;
%     end

%     allRespTypes = { ...
%         'StressAtGP','StrainAtGP', ...
%         'StressAtNode','StrainAtNode', ...
%         'StressAtNodeErr','StrainAtNodeErr', ...
%         'PorePressureAtNode', ...
%         'StressMeasureAtGP','StressMeasureAtNode'};

%     respTypes = resolveRespTypes(allRespTypes, options.respType);

%     allEleTags = double(data.eleTags(:).');
%     [selectedTags, eleIdx] = resolveTagSelection( ...
%         allEleTags, options.eleTags, 'readResponse:InvalidEleTags', 'Element');
%     selectAllEle = isempty(options.eleTags);

%     nodeTypes = {'StressAtNode','StrainAtNode', ...
%                  'StressAtNodeErr','StrainAtNodeErr', ...
%                  'PorePressureAtNode','StressMeasureAtNode'};
%     [hasNodeTags, selectedNodeTags, nodeIdx] = resolveOptionalDataTagSelection( ...
%         data, 'nodeTags', options.nodeTags, respTypes, nodeTypes, ...
%         'readResponse:MissingNodeTags', 'readResponse:InvalidNodeTags', 'Node');
%     selectAllNode = isempty(options.nodeTags);

%     S             = struct();
%     S.eleTags     = selectedTags(:);
%     if hasNodeTags
%         S.nodeTags = selectedNodeTags(:);
%     end

%     eleTypes     = {'StressAtGP','StrainAtGP','StressMeasureAtGP'};
%     stressTypes  = {'StressAtGP','StressAtNode','StressAtNodeErr'};
%     strainTypes  = {'StrainAtGP','StrainAtNode','StrainAtNodeErr'};
%     measureTypes = {'StressMeasureAtGP','StressMeasureAtNode'};

%     nSD = size(data.StressAtGP, 4);
%     nED = size(data.StrainAtGP, 4);
%     stressDofs  = solid_stress_dof_labels(nSD);   % ← 小写 s
%     strainDofs  = solid_strain_dof_labels(nED);   % ← 小写 s

%     for k = 1:numel(respTypes)
%         rt = respTypes{k};
%         if ~isfield(data, rt); continue; end
%         d = data.(rt);
%         if isempty(d); continue; end

%         % ===== Stress/Strain: monolithic 4D array, split by component =====
%         if ismember(rt, [stressTypes, strainTypes])
%             if ~isnumeric(d); continue; end

%             if ismember(rt, strainTypes)
%                 dofs = strainDofs;
%             else
%                 dofs = stressDofs;
%             end

%             if ~selectAllNode && ismember(rt, nodeTypes)
%                 d = subsetSecondDim(d, nodeIdx);
%             end
%             if ~selectAllEle && ismember(rt, eleTypes)
%                 d = subsetSecondDim(d, eleIdx);
%             end

%             nd   = ndims(d);
%             nDof = min(size(d, nd), numel(dofs));
%             S.(rt) = struct();
%             for di = 1:nDof
%                 if nd == 4
%                     S.(rt).(dofs{di}) = d(:, :, :, di);
%                 else
%                     S.(rt).(dofs{di}) = d(:, :, di);
%                 end
%             end
%             continue;
%         end

%         % ===== PorePressure =====
%         if strcmp(rt, 'PorePressureAtNode')
%             S.(rt) = d;
%             continue;
%         end

%         % ===== Stress Measures: already split in HDF5 =====
%         if ismember(rt, measureTypes)
%             if ~isstruct(d); continue; end

%             S.(rt) = struct();
%             fn = fieldnames(d);
%             for fi = 1:numel(fn)
%                 subName = fn{fi};
%                 subData = d.(subName);

%                 if isstruct(subData)
%                     % principal → p1, p2, p3
%                     S.(rt).(subName) = struct();
%                     subFn = fieldnames(subData);
%                     for sfi = 1:numel(subFn)
%                         S.(rt).(subName).(subFn{sfi}) = subsetMeasure(subData.(subFn{sfi}), ...
%                             rt, eleIdx, nodeIdx, selectAllEle, selectAllNode, eleTypes, nodeTypes);
%                     end
%                 else
%                     S.(rt).(subName) = subsetMeasure(subData, ...
%                         rt, eleIdx, nodeIdx, selectAllEle, selectAllNode, eleTypes, nodeTypes);
%                 end
%             end
%             continue;
%         end
%     end
% end


% function labels = solid_stress_dof_labels(n)
%     base = {'sxx','syy','szz','sxy','syz','sxz'};
%     labels = cell(1, n);
%     for k = 1:n
%         if k <= numel(base)
%             labels{k} = base{k};
%         else
%             labels{k} = sprintf('para%d', k - numel(base));
%         end
%     end
% end

% function labels = solid_strain_dof_labels(n)
%     base = {'exx','eyy','ezz','exy','eyz','exz'};
%     labels = cell(1, n);
%     for k = 1:n
%         if k <= numel(base)
%             labels{k} = base{k};
%         else
%             labels{k} = sprintf('para%d', k - numel(base));
%         end
%     end
% end


% function S = readTrussResponse(data, options)
%     arguments
%         data
%         options.eleTags  double = []
%         options.respType string = ""
%     end

%     if ~isfield(data, "eleTags")
%         S = struct();
%         return;
%     end

%     allRespTypes = {'axialForce','axialDefo','Stress','Strain'};

%     if strlength(options.respType) > 0
%         rt = char(options.respType);
%         if ~ismember(rt, allRespTypes)
%             error('readResponse:InvalidRespType', ...
%                 'Unknown respType "%s". Valid: %s', rt, strjoin(allRespTypes,', '));
%         end
%         respTypes = {rt};
%     else
%         respTypes = allRespTypes;
%     end

%     allEleTags = double(data.eleTags(:).');
%     selectAll  = isempty(options.eleTags);

%     if selectAll
%         eleIdx       = [];
%         selectedTags = allEleTags;
%     else
%         queryTags = double(options.eleTags(:).');
%         [tf, eleIdx] = ismember(queryTags, allEleTags);
%         if ~all(tf)
%             error('readResponse:InvalidEleTags', ...
%                 'Element tags not found: %s', mat2str(queryTags(~tf)));
%         end
%         selectedTags = allEleTags(eleIdx);
%     end

%     S             = struct();
%     S.eleTags     = selectedTags(:);

%     for k = 1:numel(respTypes)
%         rt = respTypes{k};
%         if ~isfield(data, rt); continue; end
%         d  = data.(rt);
%         if isempty(d) || ~isnumeric(d); continue; end

%         if ~selectAll
%             nd  = ndims(d);
%             idx = repmat({':'}, 1, nd);
%             idx{2} = eleIdx;
%             d = d(idx{:});
%         end

%         S.(rt) = d;
%     end
% end

% function S = readShellResponse(data, options)
%     arguments
%         data
%         options.eleTags  double = []
%         options.nodeTags double = []
%         options.respType string = ""
%     end

%     if ~isfield(data, "eleTags")
%         S = struct();
%         return;
%     end

%     allRespTypes = { ...
%         'SecForceAtGP','SecDefoAtGP', ...
%         'StressAtGP','StrainAtGP', ...
%         'SecForceAtNode','SecDefoAtNode', ...
%         'StressAtNode','StrainAtNode'};

%     secDofs    = {'fxx','fyy','fxy','mxx','myy','mxy','vxz','vyz'};
%     stressDofs = {'sxx','syy','sxy','syz','sxz'};
%     strainDofs = {'exx','eyy','exy','eyz','exz'};

%     respTypes = resolveRespTypes(allRespTypes, options.respType);

%     allEleTags = data.eleTags(:).';
%     [selectedTags, eleIdx] = resolveTagSelection( ...
%         allEleTags, options.eleTags, 'readResponse:InvalidEleTags', 'Element');
%     selectAllEle = isempty(options.eleTags);

%     nodeTypes = {'SecForceAtNode','SecDefoAtNode','StressAtNode','StrainAtNode'};
%     [hasNodeTags, selectedNodeTags, nodeIdx] = resolveOptionalDataTagSelection( ...
%         data, 'nodeTags', options.nodeTags, respTypes, nodeTypes, ...
%         'readResponse:MissingNodeTags', 'readResponse:InvalidNodeTags', 'Node');
%     selectAllNode = isempty(options.nodeTags);

%     S             = struct();
%     S.eleTags     = selectedTags(:);

%     if hasNodeTags
%         S.nodeTags = selectedNodeTags(:);
%     end

%     eleTypes = {'SecForceAtGP','SecDefoAtGP','StressAtGP','StrainAtGP'};

%     for k = 1:numel(respTypes)
%         rt = respTypes{k};
%         if ~isfield(data, rt); continue; end
%         d = data.(rt);
%         if isempty(d) || ~isnumeric(d); continue; end

%         isStrainType = ismember(rt, {'StrainAtGP','StrainAtNode'});
%         isStressType = ismember(rt, {'StressAtGP','StressAtNode'});
%         if isStrainType
%             dofs = strainDofs;
%         elseif isStressType
%             dofs = stressDofs;
%         else
%             dofs = secDofs;
%         end

%         if ~selectAllNode && ismember(rt, nodeTypes)
%             d = subsetSecondDim(d, nodeIdx);
%         end
%         if ~selectAllEle && ismember(rt, eleTypes)
%             d = subsetSecondDim(d, eleIdx);
%         end

%         nd   = ndims(d);
%         nDof = min(size(d, nd), numel(dofs));
%         S.(rt) = struct();
%         for di = 1:nDof
%             idx2 = repmat({':'}, 1, nd);
%             idx2{nd} = di;
%             S.(rt).(dofs{di}) = d(idx2{:});
%         end
%     end
% end

% function S = readContactResponse(data, options)
%     arguments
%         data
%         options.eleTags  double = []
%         options.respType string = ""
%     end

%     if ~isfield(data, "eleTags")
%         S = struct();
%         return;
%     end

%     allRespTypes = {'globalForces','localForces','localDisp','slips'};

%     if strlength(options.respType) > 0
%         rt = char(options.respType);
%         if ~ismember(rt, allRespTypes)
%             error('readResponse:InvalidRespType', ...
%                 'Unknown respType "%s". Valid: %s', rt, strjoin(allRespTypes,', '));
%         end
%         respTypes = {rt};
%     else
%         respTypes = allRespTypes;
%     end

%     allEleTags = double(data.eleTags(:).');
%     selectAll  = isempty(options.eleTags);

%     if selectAll
%         eleIdx       = [];
%         selectedTags = allEleTags;
%     else
%         queryTags = double(options.eleTags(:).');
%         [tf, eleIdx] = ismember(queryTags, allEleTags);
%         if ~all(tf)
%             error('readResponse:InvalidEleTags', ...
%                 'Element tags not found: %s', mat2str(queryTags(~tf)));
%         end
%         selectedTags = allEleTags(eleIdx);
%     end

%     S             = struct();
%     S.eleTags     = selectedTags(:);

%     dofsMap = struct( ...
%         'globalForces', {{post.resp.ContactRespStepData.GLOBAL_DOFS}}, ...
%         'localForces',  {{post.resp.ContactRespStepData.LOCAL_DOFS}}, ...
%         'localDisp',    {{post.resp.ContactRespStepData.LOCAL_DOFS}}, ...
%         'slips',        {{post.resp.ContactRespStepData.SLIP_DOFS}});

%     for k = 1:numel(respTypes)
%         rt = respTypes{k};
%         if ~isfield(data, rt); continue; end
%         d  = data.(rt);
%         if isempty(d) || ~isnumeric(d); continue; end

%         if ~selectAll
%             nd  = ndims(d);
%             idx = repmat({':'}, 1, nd);
%             idx{2} = eleIdx;
%             d = d(idx{:});
%         end

%         dofs = dofsMap.(rt);
%         nDof = min(size(d, 3), numel(dofs));
%         S.(rt) = struct();
%         for di = 1:nDof
%             S.(rt).(dofs{di}) = d(:, :, di);
%         end
%     end
% end


% function respTypes = resolveRespTypes(allRespTypes, requestedRespType)
%     if strlength(requestedRespType) > 0
%         rt = char(requestedRespType);
%         if ~ismember(rt, allRespTypes)
%             error('readResponse:InvalidRespType', ...
%                 'Unknown respType "%s". Valid: %s', rt, strjoin(allRespTypes, ', '));
%         end
%         respTypes = {rt};
%     else
%         respTypes = allRespTypes;
%     end
% end

% function [selectedTags, tagIdx] = resolveTagSelection(allTags, queryTags, errorId, entityLabel)
%     allTags = double(allTags(:).');
%     if isempty(queryTags)
%         selectedTags = allTags;
%         tagIdx = [];
%         return;
%     end

%     queryTags = double(queryTags(:).');
%     [tf, tagIdx] = ismember(queryTags, allTags);
%     if ~all(tf)
%         error(errorId, '%s tags not found: %s', entityLabel, mat2str(queryTags(~tf)));
%     end
%     selectedTags = allTags(tagIdx);
% end

% function [hasTags, selectedTags, tagIdx] = resolveOptionalDataTagSelection(data, tagField, queryTags, respTypes, dependentRespTypes, missingDataId, invalidQueryId, entityLabel)
%     hasTags = isfield(data, tagField) && ~isempty(data.(tagField));
%     selectedTags = [];
%     tagIdx = [];

%     requiresTags = ~isempty(queryTags) && any(ismember(respTypes, dependentRespTypes));
%     if requiresTags && ~hasTags
%         error(missingDataId, 'This dataset does not contain %s response tags.', lower(entityLabel));
%     end

%     if ~hasTags
%         return;
%     end

%     tmp = data.(tagField);
%     allTags = double(tmp(:).');
%     [selectedTags, tagIdx] = resolveTagSelection( ...
%         allTags, queryTags, invalidQueryId, entityLabel);
% end

% function out = subsetSecondDim(in, idx)
%     nd = ndims(in);
%     subs = repmat({':'}, 1, nd);
%     subs{2} = idx;
%     out = in(subs{:});
% end
