classdef ODB < handle
    % Output database for OpenSees response data.


    % =====================================================================
    properties (Access = private)
        ops
        outputDir       string
        respFilename    string

        odbTag
        modelUpdate     logical
        flushEvery
        stepSize
        dtype           struct
        storePath       string
        pendingSteps    double = 0
        fileIdx         double = 1

        args            struct
        globalArgs      cell

        modelInfoResp
        nodalResp
        frameResp
        trussResp
        linkResp
        shellResp
        fiberSecResp
        planeResp
        solidResp
        contactResp
        sensitivityResp
    end

    % =====================================================================
    methods

        % -----------------------------------------------------------------
        function obj = ODB(ops, odbTag, options)
            arguments
                ops
                odbTag

                options.modelUpdate             logical = false
                options.saveEvery                       = []
                options.stepSize                        = []
                options.dtype                   struct  = struct('intType','int32','floatType','single')

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
                options.fiberEleTags                   = []
                options.planeTags               double = []
                options.solidTags               double = []
                options.contactTags             double = []
                options.sensitivityParaTags     double = []

                options.elasticFrameSecPoints   double {mustBeInteger, mustBePositive} = 7
                options.interpolateBeamDisp            = false
                options.computeMechanicalMeasures      = {"principal", "vonMises", "octahedral", "tauMax"}
                % computeMechanicalMeasures = { ...
                % "principal", ...
                % "vonMises", ...
                % "octahedral", ...
                % "tauMax", ...
                % {"mohrCoulombSy", syc, syt}, ...
                % {"mohrCoulombCPhi", c, phiDeg}, ...
                % {"druckerPragerSy", syc, syt}, ...
                % {"druckerPragerCPhi", c, phiDeg, "circumscribed"} ...
                % };
                options.projectGaussToNodes     string = "copy"
            end

            obj.ops         = ops;
            obj.odbTag      = odbTag;
            obj.modelUpdate = options.modelUpdate;
            obj.flushEvery  = options.saveEvery;
            obj.dtype       = options.dtype;

            skip = {'modelUpdate','saveEvery','dtype','stepSize'};
            obj.args = rmfield(options, skip);

            if ~isempty(obj.flushEvery)
                obj.stepSize = int32(obj.flushEvery);
            elseif ~isempty(options.stepSize)
                obj.stepSize = int32(options.stepSize);
            else
                obj.stepSize = [];
            end

            obj.globalArgs = {'modelUpdate', obj.modelUpdate, 'dtype', obj.dtype, 'stepSize', obj.stepSize};

            obj.collectResponses();
        end

        function setOutputDir(obj, dir)
            obj.outputDir    = string(dir);
            obj.respFilename = "Responses";
            post.ODB.sharedConfig('set', obj.outputDir);
            obj.storePath = fullfile(obj.outputDir, ...
                sprintf('%s-%s.odb', obj.respFilename, string(obj.odbTag)));
            obj.initPath();
        end

        % -----------------------------------------------------------------
        function fetchResponseStep(obj, options)
            % Fetch response data for the current step and store it in memory. Data is flushed to disk when the number of pending steps reaches the flushEvery threshold.
            %
            % Parameters
            % ----------
            % printInfo : logical, optional
            %     If true, prints information about the collected responses and current time step to the console. Default is false.
            %
            arguments
                obj
                options.printInfo logical = false
            end

            obj.collectResponses();
            obj.pendingSteps = obj.pendingSteps + 1;

            if ~isempty(obj.flushEvery) && obj.pendingSteps >= obj.flushEvery
                obj.flushToDisk();
                obj.resetStepBuffers();
            end

            if options.printInfo
                t = obj.ops('getTime');
                fprintf('[OpenSeesMatlab] Responses at t = %.4f collected.\n', t);
            end
        end

        % -----------------------------------------------------------------
        function saveResponse(obj)
            % Save the collected response data to disk. This should be called after the final step has been fetched to ensure that any remaining data in memory is written to disk.
            if obj.pendingSteps > 0
                obj.flushToDisk();
            end
            fprintf('[OpenSeesMatlab] odbTag=%s saved → %s\n', string(obj.odbTag), obj.storePath);
        end

        % -----------------------------------------------------------------
        function reset(obj)
            % Reset the ODB by clearing all collected response data from memory and resetting the pending steps counter. This does not delete any saved files on disk.
            for r = obj.allResponders()
                if ~isempty(r{1})
                    r{1}.reset();
                end
            end
            obj.pendingSteps = 0;
        end

    end % public methods

    % =====================================================================
    methods (Static)

        % -----------------------------------------------------------------
        function odb = loadODB(odbTag, options)
            arguments
                odbTag
                options.groups  string = ""   % e.g. "NodalResponses" or ["NodalResponses","FrameResponses"]
            end
 
            outputDir    = post.ODB.sharedConfig('get');
            respFilename = "Responses";
 
            storePath = fullfile(outputDir, ...
                sprintf('%s-%s.odb', respFilename, string(odbTag)));
 
            % Fast path: read only the requested groups directly from HDF5,
            % skipping deserialisation of everything else.
            if any(strlength(options.groups) > 0)
                odb   = struct();
                parts = post.ODB.loadParts(storePath, options.groups);
                mask  = ~cellfun(@isempty, parts);
                parts = parts(mask);
                if isempty(parts)
                    return;
                end
                odb = post.utils.StructMerger.mergeParts( ...
                    parts, ...
                    'ModelUpdateField', 'modelUpdate', ...
                    'Mode', 'concat');
                groups = string(options.groups(:));
                if isscalar(groups)
                    odb = odb.(groups);
                else
                    filtered = struct();
                    for i = 1:numel(groups)
                        groupName = char(groups(i));
                        if isfield(odb, groupName)
                            filtered.(groupName) = odb.(groupName);
                        end
                    end
                    odb = filtered;
                end
                return;
            end
 
            % Default path: load and merge all groups.
            parts = post.ODB.loadParts(storePath);
 
            if isempty(parts)
                odb = struct();
                return;
            end
 
            mask  = ~cellfun(@isempty, parts);
            parts = parts(mask);
 
            if isempty(parts)
                odb = struct();
                return;
            end
 
            odb = post.utils.StructMerger.mergeParts( ...
                parts, ...
                'ModelUpdateField', 'modelUpdate', ...
                'Mode', 'concat');
        end

        function data = readNodeResponse(odbTag, options)
            arguments
                odbTag
                options.nodeTags    double = []
                options.respType    string = ""
            end
 
            odb  = post.ODB.loadODB(odbTag, groups=post.resp.NodalRespStepData.RESP_NAME);
            data = post.resp.NodalRespStepData.readResponse( ...
                odb, ...
                nodeTags = options.nodeTags, ...
                respType = options.respType);
            if ~isempty(data)
                data.odbTag = odbTag;
            end
        end

        function data = readElementResponse(odbTag, options)
            arguments
                odbTag
                options.eleType     string = ""
                options.eleTags     double = []
                options.respType    string = ""
            end
            
            switch lower(char(options.eleType))
                case {'frame','beam'}
                    groups = post.resp.FrameRespStepData.RESP_NAME;
                case {'plane'}
                    groups = post.resp.PlaneRespStepData.RESP_NAME;
                case {'solid'}
                    groups = post.resp.SolidRespStepData.RESP_NAME;
                case {'shell'}
                    groups = post.resp.ShellRespStepData.RESP_NAME;
                otherwise
                    error('Unknown element type: %s', options.eleType);
            end

            odb  = post.ODB.loadODB(odbTag, groups=groups);
            switch lower(char(options.eleType))
                case {'frame','beam'}
                    data = post.resp.FrameRespStepData.readResponse( ...
                        odb, ...
                        eleTags  = options.eleTags, ...
                        respType = options.respType);
                case {'plane'}
                    data = post.resp.PlaneRespStepData.readResponse( ...
                        odb, ...
                        eleTags  = options.eleTags, ...
                        respType = options.respType);
                case {'solid'}
                    data = post.resp.SolidRespStepData.readResponse( ...
                        odb, ...
                        eleTags  = options.eleTags, ...
                        respType = options.respType);
                case {'shell'}
                    data = post.resp.ShellRespStepData.readResponse( ...
                        odb, ...
                        eleTags  = options.eleTags, ...
                        respType = options.respType);
            end
            if ~isempty(data)
                data.odbTag = odbTag;
                data.eleType = options.eleType;
            end
        end

    end % static public methods

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

        % -----------------------------------------------------------------
        function collectResponses(obj)
            obj.collectModelInfo();
            obj.collectNodalResp();
            obj.collectFrameResp();
            obj.collectTrussResp();
            obj.collectLinkResp();
            obj.collectShellResp();
            obj.collectFiberSecResp();
            obj.collectPlaneResp();
            obj.collectSolidResp();
            obj.collectContactResp();
            obj.collectSensitivityResp();
        end

        % -----------------------------------------------------------------
        function collectModelInfo(obj)
            if isempty(obj.modelInfoResp)
                obj.modelInfoResp = post.resp.ModelInfoStepData(obj.ops, obj.globalArgs{:});
            elseif obj.modelUpdate
                obj.modelInfoResp.addRespDataOneStep();
            end
        end

        % -----------------------------------------------------------------
        function collectNodalResp(obj)
            if ~obj.args.saveNodalResp, return; end
            if isempty(obj.args.nodeTags)
                tags = obj.modelInfoResp.getCurrentNodeTags();
            else
                tags = obj.args.nodeTags;
            end
            if isempty(tags), return; end

            interp     = obj.args.interpolateBeamDisp;
            modelInfo  = [];
            if interp
                modelInfo = obj.modelInfoResp.getCurrentModelInfo();
            end

            if isempty(obj.nodalResp)
                obj.nodalResp = post.resp.NodalRespStepData(obj.ops, tags, ...
                    interp, modelInfo, obj.globalArgs{:});
            else
                obj.nodalResp.addRespDataOneStep(tags, modelInfo);
            end
        end

        % -----------------------------------------------------------------
        function collectFrameResp(obj)
            if ~obj.args.saveFrameResp, return; end
            if isempty(obj.args.frameTags)
                 tags = obj.modelInfoResp.getCurrentFrameTags();
            else
                 tags = obj.args.frameTags;
            end
            if isempty(tags), return; end

            frameLoad = obj.modelInfoResp.getCurrentFrameLoadData();

            if isempty(obj.frameResp)
                obj.frameResp = post.resp.FrameRespStepData(obj.ops, tags, frameLoad, ...
                    obj.args.elasticFrameSecPoints, ...
                    obj.globalArgs{:});
            else
                obj.frameResp.addRespDataOneStep(tags, frameLoad);
            end
        end

        % -----------------------------------------------------------------
        function collectTrussResp(obj)
            if ~obj.args.saveTrussResp, return; end
            if isempty(obj.args.trussTags)
                 tags = obj.modelInfoResp.getCurrentTrussTags();
            else
                 tags = obj.args.trussTags;
            end
            if isempty(tags), return; end

            if isempty(obj.trussResp)
                obj.trussResp = post.resp.TrussRespStepData(obj.ops, tags, obj.globalArgs{:});
            else
                obj.trussResp.addRespDataOneStep(tags);
            end
        end

        % -----------------------------------------------------------------
        function collectLinkResp(obj)
            if ~obj.args.saveLinkResp, return; end
            if isempty(obj.args.linkTags)
                 tags = obj.modelInfoResp.getCurrentLinkTags();
            else
                 tags = obj.args.linkTags;
            end
            if isempty(tags), return; end

            if isempty(obj.linkResp)
                obj.linkResp = post.resp.LinkRespStepData(obj.ops, tags, obj.globalArgs{:});
            else
                obj.linkResp.addRespDataOneStep(tags);
            end
        end

        % -----------------------------------------------------------------
        function collectShellResp(obj)
            if ~obj.args.saveShellResp, return; end
            if isempty(obj.args.shellTags)
                 tags = obj.modelInfoResp.getCurrentShellTags();
            else
                 tags = obj.args.shellTags;
            end
            if isempty(tags), return; end

            if isempty(obj.shellResp)
                obj.shellResp = post.resp.ShellRespStepData(obj.ops, tags, ...
                    'computeNodalResp', obj.args.projectGaussToNodes, ...
                    obj.globalArgs{:});
            else
                obj.shellResp.addRespDataOneStep(tags);
            end
        end

        % -----------------------------------------------------------------
        function collectFiberSecResp(obj)
            % fiberTags = obj.args.fiberEleTags;

            % if ischar(fiberTags) || isstring(fiberTags)
            %     if ~strcmpi(fiberTags, 'all')
            %         fiberTags = [];
            %     end
            % elseif ~isempty(fiberTags)
            %     fiberTags = int32(fiberTags(:).');
            % end

            % if isempty(fiberTags) && ~obj.args.saveFiberSecResp, return; end
            % if isempty(fiberTags), return; end

            % if isempty(obj.fiberSecResp)
            %     obj.fiberSecResp = FiberSecRespStepData(obj.ops, fiberTags, ...
            %         'dtype', obj.dtype);
            % else
            %     obj.fiberSecResp.addRespDataOneStep();
            % end
        end

        % -----------------------------------------------------------------
        function collectPlaneResp(obj)
            if ~obj.args.savePlaneResp, return; end
            if isempty(obj.args.planeTags)
                 tags = obj.modelInfoResp.getCurrentPlaneTags();
            else
                 tags = obj.args.planeTags;
            end
            if isempty(tags), return; end

            if isempty(obj.planeResp)
                obj.planeResp = post.resp.PlaneRespStepData(obj.ops, tags, ...
                    'computeMechanicalMeasures',  obj.args.computeMechanicalMeasures, ...
                    'computeNodalResp', obj.args.projectGaussToNodes, ...
                    obj.globalArgs{:});
            else
                obj.planeResp.addRespDataOneStep(tags);
            end
        end

        % -----------------------------------------------------------------
        function collectSolidResp(obj)
            if ~obj.args.saveSolidResp, return; end
            if isempty(obj.args.solidTags)
                 tags = obj.modelInfoResp.getCurrentSolidTags();
            else
                 tags = obj.args.solidTags;
            end
            if isempty(tags), return; end

            if isempty(obj.solidResp)
                obj.solidResp = post.resp.SolidRespStepData(obj.ops, tags, ...
                    'computeMechanicalMeasures',  obj.args.computeMechanicalMeasures, ...
                    'computeNodalResp', obj.args.projectGaussToNodes, ...
                    obj.globalArgs{:});
            else
                obj.solidResp.addRespDataOneStep(tags);
            end
        end

        % -----------------------------------------------------------------
        function collectContactResp(obj)
            if ~obj.args.saveContactResp, return; end
            if isempty(obj.args.contactTags)
                 tags = obj.modelInfoResp.getCurrentContactTags();
            else
                 tags = obj.args.contactTags;
            end
            if isempty(tags), return; end

            if isempty(obj.contactResp)
                obj.contactResp = post.resp.ContactRespStepData(obj.ops, tags, ...
                    obj.globalArgs{:});
            else
                obj.contactResp.addRespDataOneStep(tags);
            end
        end

        % -----------------------------------------------------------------
        function collectSensitivityResp(obj)
            % if ~obj.args.saveSensitivityResp, return; end

            % sensTags  = obj.resolveTags(obj.args.sensitivityParaTags, 'getParamTags');
            % nodeTags  = obj.resolveTags(obj.args.nodeTags, 'getNodeTags');
            % if isempty(nodeTags) || isempty(sensTags), return; end

            % if isempty(obj.sensitivityResp)
            %     obj.sensitivityResp = SensitivityRespStepData(obj.ops, ...
            %         nodeTags, [], sensTags, 'dtype', obj.dtype);
            % else
            %     obj.sensitivityResp.addRespDataOneStep(nodeTags, sensTags);
            % end
        end

        % -----------------------------------------------------------------
        function flushToDisk(obj)
            filename = fullfile(char(obj.storePath), ...
                sprintf('part_%d.hdf5', obj.fileIdx));

            store = post.utils.HDF5DataStore(filename, 'Overwrite', true);
            data  = struct();

            for r = obj.allResponders()
                resp = r{1};
                if ~isempty(resp) && ~resp.checkDatasetEmpty()
                    data.(resp.RESP_NAME) = resp.getRespStepData();
                end
            end

            store.write('/', data);
            obj.fileIdx      = obj.fileIdx + 1;
            obj.pendingSteps = 0;
        end

        % -----------------------------------------------------------------
        function resetStepBuffers(obj)
            for r = obj.allResponders()
                if ~isempty(r{1})
                    r{1}.resetRespStepData();
                end
            end
        end

        % -----------------------------------------------------------------
        function responders = allResponders(obj)
            responders = { ...
                obj.modelInfoResp,  obj.nodalResp,    obj.frameResp,  ...
                obj.trussResp,      obj.linkResp,     obj.shellResp,  ...
                obj.fiberSecResp,   obj.planeResp,    obj.solidResp,  ...
                obj.contactResp,    obj.sensitivityResp};
        end

    end % private methods

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

        % -----------------------------------------------------------------
        function parts = loadParts(storePath, groups)
            if nargin < 2
                groups = string.empty(0,1);
            end

            d     = char(string(storePath));
            files = dir(fullfile(d, 'part_*.hdf5'));
            if isempty(files)
                error('ODB:NoPartsFound', ...
                    'No part_*.hdf5 files found in: %s', d);
            end

            indices = zeros(1, numel(files));
            for i = 1:numel(files)
                tok = regexp(files(i).name, 'part_(\d+)\.hdf5', 'tokens', 'once');
                if ~isempty(tok)
                    indices(i) = str2double(tok{1});
                end
            end
            [~, order] = sort(indices);
            files = files(order);

            parts = cell(1, numel(files));
            for i = 1:numel(files)
                store = post.utils.HDF5DataStore( ...
                    fullfile(d, files(i).name), 'Overwrite', false);

                if isempty(groups) || ~any(strlength(groups) > 0)
                    parts{i} = store.load();
                    continue;
                end

                groupData = struct();
                reqGroups = string(groups(:));
                for j = 1:numel(reqGroups)
                    groupName = char(reqGroups(j));
                    groupPath = ['/' groupName];
                    if store.exists(groupPath)
                        groupData.(groupName) = store.read(groupPath);
                    end
                end
                parts{i} = groupData;
            end
        end

        % -----------------------------------------------------------------
        function m = eleReaderMap()
            m = containers.Map( ...
                {'frame','beam','truss','link','shell', ...
                 'plane','Solid','solid','fibersec','fibersection','contact'}, ...
                {'FrameRespStepData',    'FrameRespStepData', ...
                 'TrussRespStepData',    'LinkRespStepData',  ...
                 'ShellRespStepData',    'PlaneRespStepData', ...
                 'SolidRespStepData',    'SolidRespStepData', ...
                 'FiberSecRespStepData', 'FiberSecRespStepData', ...
                 'ContactRespStepData'});
        end

    end % static private methods

end