
classdef ODB < handle
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
        function obj = ODB(ops, odbTag, options)
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
                options.computeMechanicalMeasures      = {"principal", "tauMax", "sigmaOct", "tauOct", "vonMises"}
                options.projectGaussToNodes     string = "copy"
            end

            obj.ops         = ops;
            obj.odbTag      = odbTag;

            obj.kargs       = options;
        end

        function setFEMDataRecorder(obj)
            % Build cell array of arguments for FEMDataRecorder.
            % Switch options, such as -saveNodalResp, are passed without a boolean
            % value. They enable the corresponding feature simply by being present.
            %
            % Empty [] and logical false options are filtered where needed to avoid
            % passing invalid tokens to the C++ parser.

            args = {obj.filename};

            if ~isempty(obj.kargs.flushEvery)
                args = [args, {'-flushEvery', obj.kargs.flushEvery}];
            end

            if obj.kargs.saveNodalResp
                args = [args, {'-saveNodalResp'}];
                if ~isempty(obj.kargs.nodeTags)
                    args = [args, num2cell(obj.kargs.nodeTags(:).')];
                end
            end

            if obj.kargs.saveTrussResp
                args = [args, {'-saveTrussResp'}];
                if ~isempty(obj.kargs.trussTags)
                    args = [args, num2cell(obj.kargs.trussTags(:).')];
                end
            end

            if obj.kargs.saveFrameResp
                args = [args, {'-saveFrameResp'}];
                if ~isempty(obj.kargs.frameTags)
                    args = [args, num2cell(obj.kargs.frameTags(:).')];
                end
            end

            if obj.kargs.saveFiberSecResp
                args = [args, {'-saveFrameFiber'}];
            end

            if obj.kargs.saveShellResp
                args = [args, {'-saveShellResp'}];
                if ~isempty(obj.kargs.shellTags)
                    args = [args, num2cell(obj.kargs.shellTags(:).')];
                end
            end

            if obj.kargs.saveSolidResp
                args = [args, {'-saveSolidResp'}];
                if ~isempty(obj.kargs.solidTags)
                    args = [args, num2cell(obj.kargs.solidTags(:).')];
                end
            end

            if obj.kargs.savePlaneResp
                args = [args, {'-savePlaneResp'}];
                if ~isempty(obj.kargs.planeTags)
                    args = [args, num2cell(obj.kargs.planeTags(:).')];
                end
            end

            if obj.kargs.saveLinkResp
                args = [args, {'-saveLinkResp'}];
                if ~isempty(obj.kargs.linkTags)
                    args = [args, num2cell(obj.kargs.linkTags(:).')];
                end
            end

            if obj.kargs.saveContactResp
                args = [args, {'-saveContactResp'}];
                if ~isempty(obj.kargs.contactTags)
                    args = [args, num2cell(obj.kargs.contactTags(:).')];
                end
            end

            args = [args, {'-elasticFrameSecPoints', obj.kargs.elasticFrameSecPoints}];

            % interpolateBeamDisp: pass string/integer value; filter out logical false.
            if ~islogical(obj.kargs.interpolateBeamDisp) || obj.kargs.interpolateBeamDisp
                args = [args, {'-interpolateBeamDisp', obj.kargs.interpolateBeamDisp}];
            end

            if ~isempty(obj.kargs.computeMechanicalMeasures)
                args = [args, {'-stressMeasures'}, obj.kargs.computeMechanicalMeasures(:).'];
            end

            args = [args, {'-projectGaussToNodes', obj.kargs.projectGaussToNodes}];

            obj.OPS_recorderTag = obj.ops.FEMDataRecorder(args{:});
        end

        function setOutputDir(obj, dir)
            obj.outputDir    = string(dir);
            obj.respFilename = "Responses";
            post.ODB.sharedConfig('set', obj.outputDir);
            obj.storePath = fullfile(obj.outputDir, ...
                sprintf('%s-%s.odb', obj.respFilename, string(obj.odbTag)));
            obj.initPath();
            obj.filename = fullfile(char(obj.storePath), 'output.h5');
            fprintf('Output file: %s\n', obj.filename);
        end

        function close(obj)
            % Remove the recorder tag if it exists.
            % This will stop the recorder from collecting data.
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
            outputDir    = post.ODB.sharedConfig("get");
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
            %   odb = ODB.loadODB(ops, odbTag)
            %   odb = ODB.loadODB(ops, odbTag, groups="model")
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

            filename = post.ODB.getFilename(odbTag);

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

            data = post.ODB.loadODB(ops, odbTag, groups="model");
            data = addField(data, 'odbTag', odbTag);
        end

        %% Nodal responses ------------------------------------------------
        function data = readNodeResponse(ops, odbTag, options)
            % readNodeResponse  Read nodal responses.
            %
            % Syntax:
            %   data = ODB.readNodeResponse(ops, odbTag)
            %   data = ODB.readNodeResponse(ops, odbTag, nodeTags=[1,2,3])
            %   data = ODB.readNodeResponse(ops, odbTag, respType="disp")
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

            filename = post.ODB.getFilename(odbTag);
            args = post.ODB.buildArgs(options);
            data = ops.readFEMData(filename, "nodal", args{:});
            data = addField(data, 'odbTag', odbTag);
        end

        %% Element responses ----------------------------------------------
        function data = readElementResponse(ops, odbTag, options)
            % readElementResponse  Read element responses.
            %
            % Syntax:
            %   data = ODB.readElementResponse(ops, odbTag, eleType="solid")
            %   data = ODB.readElementResponse(ops, odbTag, eleType="solid", eleTags=[1,2])
            %   data = ODB.readElementResponse(ops, odbTag, eleType="solid", respType="StressAtNode")
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

            [groups, respName] = post.ODB.eleTypeMap(options.eleType);
            filename = post.ODB.getFilename(odbTag);
            args = post.ODB.buildArgs(options);
            data = ops.readFEMData(filename, groups, args{:});

            data = addField(data, 'odbTag', odbTag);
            data = addField(data, 'eleType', options.eleType);

        end

        function out = writePVD(ops, odbTag, outDir, baseName, options)
            % Write nodal and Shell, Plane, Solid element responses to ParaView-readable VTU/PVD files.
            %
            % Example
            % --------
            %     obj.writeResponsePVD("MyODB")
            %     obj.writeResponsePVD("MyODB", includeShell=true, includePlane=true, includeSolid=true)
            %
            % Parameters
            % ----------
            % odbTag : char | string | numeric
            %     The identifier of the ODB to read from.
            % outDir : char | string, optional
            %     The directory to save the output files. Default is "paraview_output".
            % baseName : char | string, optional
            %     The base name for the output files. Default is "paraview_anim".
            % includeNodal, includeShell, includePlane, includeSolid : logical, optional
            %     Flags to specify which types of responses to include in the output. By default, all types are included.

            arguments
                ops
                odbTag {mustBeTextScalar} = ""
                outDir {mustBeTextScalar} = "paraview_output"
                baseName {mustBeTextScalar} = "pv"
                options.includeNodal (1,1) logical = true
                options.includeShell (1,1) logical = true
                options.includePlane (1,1) logical = true
                options.includeSolid (1,1) logical = true
                % options.binary (1,1) logical = false
            end

            filename = post.ODB.getFilename(odbTag);
            out = ops.writeFEMDataPVD(filename, outDir, baseName, ...
                'includeNodal', options.includeNodal, ...
                'includeShell', options.includeShell, ...
                'includePlane', options.includePlane, ...
                'includeSolid', options.includeSolid);
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
