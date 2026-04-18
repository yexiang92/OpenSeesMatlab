classdef OpenSeesMatlabPost < handle
    % OpenSeesMatlabPost Post-processing interface for OpenSeesMatlab.
    %   OpenSeesMatlabPost provides methods for collecting, saving, and retrieving
    %   model information, eigenvalue analysis and responses results from OpenSeesMatlab.

    properties (Access = private)
        parent  % Reference to the parent OpenSeesMatlab object
        outputDir = ".openseesmatlab.output"  % Output directory for OpenSeesMatlabPost
    end

    methods
        function obj = OpenSeesMatlabPost(parentObj)
            if nargin < 1 || isempty(parentObj)
                error('OpenSeesMatlabPost:InvalidInput', ...
                    'A parent OpenSeesMatlab object is required.');
            end
            obj.parent = parentObj;
        end

        function setOutputDir(obj, dir)
            % Set the output directory for OpenSeesMatlabPost. 
            %
            %  Parameters
            %  ----------
            %  dir : char | string
            %      The directory to set as the output directory for OpenSeesMatlabPost. If the directory does not exist, it will be created.

            obj.outputDir = dir;
            obj.checkOutputDir();

        end

        function outDir = getOutputDir(obj)
            % Get the output directory for OpenSeesMatlabPost.
            %
            % Returns
            % -------
            % outDir : char | string
            %     The current output directory for OpenSeesMatlabPost.
            outDir = obj.outputDir;
        end


        function saveModelData(obj, odbTag)
            % Save model information to a file.
            %
            % Example
            % --------
            %     saveModelData(1)
            %
            % Parameters
            % -----------
            % odbTag : char | string | numeric
            %     A unique identifier for the ODB.
            %

            arguments
                obj (1,1) OpenSeesMatlabPost
                odbTag (1,1)  = 1
            end

            filename = sprintf('modelData_%s.hdf5', string(odbTag));

            filename = fullfile(obj.outputDir, filename);
            obj.checkOutputDir();

            modelData = post.FEMDataCollector(obj.parent.opensees, post.utils.OpenSeesTagMaps());
            modelData.collect();
            modelData.save(filename);
        end

        function modelInfo = getModelData(obj, odbTag)
            % Get model information from memory or file.
            %
            % Example
            % --------
            %     modelInfo = obj.getModelData()  % from memory
            %     modelInfo = obj.getModelData(odbTag)
            %
            % Parameters
            % ----------
            % odbTag : char | string | numeric
            %     A unique identifier for the ODB.
            %
            % Returns
            % -------
            % modelInfo : struct
            %     Model information structure.

            arguments
                obj (1,1) OpenSeesMatlabPost
                odbTag (1,1)  = ""
            end

            odbTag = string(odbTag);

            modelData = post.FEMDataCollector(obj.parent.opensees, post.utils.OpenSeesTagMaps());

            if isempty(odbTag) || odbTag == ""
                modelInfo = modelData.getModelInfo();
            else
                filename = sprintf('modelData_%s.hdf5', string(odbTag));
                filename = fullfile(obj.outputDir, filename);
                modelInfo = modelData.readFile(filename);
            end
        end

        function saveEigenData(obj, odbTag, numModes, options)
            % Save eigenvalue analysis results to a file.
            %
            % Example
            % --------
            %     saveEigenData(odbTag, numModes)
            %     saveEigenData(odbTag, numModes, solver="-genBandArpack")
            %     saveEigenData(odbTag, numModes, solver="-genBandArpack", InterpolateBeam=false)
            %
            % Parameters
            % -----------
            % odbTag : char | string | numeric
            %     A unique identifier for the ODB.
            % numModes : integer
            %     The number of modes to collect and save.
            % solver : char | string
            %     The solver to use for eigenvalue analysis (e.g., '-genBandArpack').
            % IncludeModelInfo : logical, default false
            %     If true, include obj.ModelInfo in the output struct.
            % InterpolateBeam : logical, default true
            %     If true, interpolate beam element modal displacements by shape functions.
            % NptsPerElement : integer >= 2, default 6
            %     Number of interpolation points per element.

            arguments
                obj (1,1) OpenSeesMatlabPost
                odbTag (1,1) = 1
                numModes (1,1) {mustBeInteger, mustBePositive} = 1
                options.solver {mustBeTextScalar} = "-genBandArpack"
                options.IncludeModelInfo (1,1) logical = false
                options.InterpolateBeam (1,1) logical = true
                options.NptsPerElement (1,1) double {mustBeInteger, mustBeGreaterThanOrEqual(options.NptsPerElement, 2)} = 6
            end

            filename = sprintf('eigenData_%s.hdf5', string(odbTag));
            filename = fullfile(obj.outputDir, filename);
            obj.checkOutputDir();

            solver = char(string(options.solver));

            modelInfo = obj.getModelData();
            modeData = post.EigenDataCollector(obj.parent.opensees, modelInfo);
            modeData.save( ...
                filename, ...
                numModes, ...
                solver, ...
                'IncludeModelInfo', options.IncludeModelInfo, ...
                'InterpolateBeam', options.InterpolateBeam, ...
                'NptsPerElement', options.NptsPerElement);
        end

        function out = getEigenData(obj, options)
            % Get eigen data from file or collect from current model.
            %
            % Example
            % --------
            %     out = obj.getEigenData(numModes=10)
            %     out = obj.getEigenData(numModes=10, solver="-genBandArpack")
            %     out = obj.getEigenData(numModes=10, InterpolateBeam=false)
            %     out = obj.getEigenData(odbTag="MyODB")  % read from file, which should be generated by ``saveEigenData``
            %
            % Parameters
            % ----------
            % odbTag : char | string | numeric, optional
            %     If the first input is a text scalar or numeric, it is treated as a unique identifier for the ODB.
            %     If the first input is not a text scalar or numeric, it is treated as numModes and eigen data will be collected from the current model.
            % numModes : integer, optional
            %     Number of modes to collect. Default is 1.
            % solver : char | string, optional
            %     Solver to use for eigenvalue analysis. Default is '-genBandArpack'.
            % IncludeModelInfo : logical, default false
            %     If true, include model information in the output struct.
            % InterpolateBeam : logical, default true
            %     If true, interpolate beam element modal displacements.
            % NptsPerElement : integer >= 2, default 6
            %     Number of interpolation points per element.
            %
            % Returns
            % ---------
            % out : struct
            %     Eigenvalue analysis results.

            arguments
                obj (1,1) OpenSeesMatlabPost
                options.odbTag = ""
                options.numModes (1,1) {mustBeInteger, mustBePositive} = 1
                options.solver {mustBeTextScalar} = "-genBandArpack"
                options.IncludeModelInfo (1,1) logical = false
                options.InterpolateBeam (1,1) logical = true
                options.NptsPerElement (1,1) double {mustBeInteger, mustBeGreaterThanOrEqual(options.NptsPerElement, 2)} = 6
            end

            odbTag = string(options.odbTag);
            if ~isempty(odbTag) && odbTag ~= ""
                filename = sprintf('eigenData_%s.hdf5', odbTag);
                filename = fullfile(obj.outputDir, filename);
                modeData = post.EigenDataCollector(obj.parent.opensees, []);
                out = modeData.readFile(char(filename));
                return;
            end

            numModes = options.numModes;
            solver = char(string(options.solver));
            extraArgs = { ...
                'IncludeModelInfo', options.IncludeModelInfo, ...
                'InterpolateBeam', options.InterpolateBeam, ...
                'NptsPerElement', options.NptsPerElement};

            modelInfo = obj.getModelData();
            modeData = post.EigenDataCollector(obj.parent.opensees, modelInfo);
            out = modeData.collect(numModes, solver, extraArgs{:});
        end
    end

    % Responses
    methods
        function odb = createODB(obj, odbTag, options)
            % Create an output database (ODB) for storing response data.
            %
            % Example
            % --------
            %     odb = obj.createODB("MyODB")
            %     odb = obj.createODB("MyODB", modelUpdate=true)
            %     for i = 1 : Nsteps
            %         ... run analysis step ...
            %         odb.fetchResponseStep()  %  fetch response data for the current step and save to ODB
            %     end
            %     odb.saveResponse()  % save ODB to disk
            %
            % Parameters
            % ----------
            % odbTag : char | string | numeric
            %     A unique identifier for the ODB.
            % modelUpdate : logical, optional, default false
            %     If true, the ODB will be updated with new model information at each step.
            % stepSize : integer, optional
            %     If provided, pre-allocate space in the ODB for the specified number of steps to improve performance.
            % saveEvery : integer, optional
            %     If provided, specifies the frequency (in steps) at which to save data to disk.
            % dtype : struct, optional
            %     A struct specifying data types for integers and floats, with fields 'intType' and 'floatType'.
            % elasticFrameSecPoints : integer, optional, default 7
            %     Number of points to use for elastic frame section integration.
            % interpolateBeamDisp : logical | integer, optional, default false
            %     If true, interpolate beam element displacements to integration points. If int, treat as number of points per element for interpolation.
            % computeMechanicalMeasures : cell array of char | string, optional, default {"principal", "vonMises", "octahedral", "tauMax"}
            %     Specifies which mechanical measures to compute for frame responses. Options include:
            %
            %     - "principal" (principal stresses)
            %     - "vonMises" (von Mises stress)
            %     - "octahedral" (octahedral shear stress)
            %     - "tauMax" (maximum shear stress)
            %     - {"mohrCoulombSy", syc, syt}, Mohr-Coulomb failure criterion with specified shear strength parameters syc and syt.
            %     - {"mohrCoulombCPhi", c, phiDeg}, Mohr-Coulomb failure criterion with specified cohesion and friction angle.
            %     - {"druckerPragerSy", syc, syt}, Drucker-Prager failure criterion with specified shear strength parameters syc and syt.
            %     - {"druckerPragerCPhi", c, phiDeg, "circumscribed"}, Drucker-Prager failure criterion with specified cohesion, friction angle, and circumscribed option.
            %     
            %     For Mohr-Coulomb and Drucker-Prager options, subcell arrays should be used to specify the parameters. For example, computeMechanicalMeasures = {"principal", "vonMises", "octahedral", "tauMax", {"mohrCoulombSy", syc, syc}}.
            % projectGaussToNodes : char | string, optional, default "extrapolation"
            %     Method to project Gauss point data to nodes for shell responses. Options are "
            %
            %     - "copy" (copy values from nearest Gauss point)
            %     - "extrapolation" (interpolate values from all Gauss points).
            %     - "average" (average values from all Gauss points).
            % saveNodalResp, saveFrameResp, saveTrussResp, saveLinkResp, saveShellResp, saveFiberSecResp, savePlaneResp, saveBrickResp, saveContactResp, saveSensitivityResp : logical, optional
            %     Flags to specify which types of response data to save.
            % nodeTags, frameTags, trussTags, linkTags, shellTags, fiberEleTags, planeTags, brickTags, contactTags, sensitivityParaTags : double array, optional
            %     Arrays of tags specifying which nodes/elements to save responses for .
            % 
            % Returns
            % -------
            % odb : post.ODB
            %     The created output database object.

            arguments
                obj (1,1) OpenSeesMatlabPost
                odbTag (1,1) = ""

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

                options.elasticFrameSecPoints   double {mustBeInteger, mustBePositive} = 9
                options.interpolateBeamDisp             = false
                options.computeMechanicalMeasures       = {"principal", "vonMises", "octahedral", "tauMax"}
                options.projectGaussToNodes     string  = "extrapolation"
            end
            odbTag = string(odbTag);
            if strlength(odbTag) == 0
                error('getODBData:InvalidODBTag', ...
                    'An odbTag must be provided.');
            end
            opts = namedargs2cell(options);
     
            odb = post.ODB(obj.parent.opensees, odbTag, opts{:});
            odb.setOutputDir(obj.outputDir);
        end

        function data = getODBData(obj, odbTag)
            % Get response data from an ODB file.
            %
            % Example
            % --------
            %     data = obj.getODBData("MyODB")
            %
            % Parameters
            % ----------
            % odbTag : char | string | numeric
            %     The identifier of the ODB to read from.
            %
            % Returns
            % -------
            % data : struct
            %     A struct containing the response data for the specified step and frame.

            arguments
                obj (1,1) OpenSeesMatlabPost
                odbTag (1,1) = ""
            end

            odbTag = string(odbTag);
            if strlength(odbTag) == 0
                error('getODBData:InvalidODBTag', ...
                    'An odbTag must be provided.');
            end

            data = post.ODB.loadODB(odbTag);
        end

        function data = getNodalResponse(obj, odbTag, options)
            % Get nodal response data from an ODB.
            %
            % Example
            % --------
            %     data = obj.getNodalResponse("MyODB")
            %     data = obj.getNodalResponse("MyODB", nodeTags=[1,2,3], respType="disp")
            %
            % Parameters
            % ----------
            % odbTag : char | string | numeric
            %     The identifier of the ODB to read from.
            % nodeTags : double array, optional
            %     An array of node tags to filter the response data. If empty or not provided, responses for all nodes will be returned.
            % respType : char | string, optional
            %     The type of nodal response to retrieve (e.g., "disp", "vel", "acc"). If empty or not provided, all types of nodal responses will be returned.
            %
            % Returns
            % -------
            % data : struct
            %     A struct containing the nodal response data for the specified nodes and response type.

            arguments
                obj (1,1) OpenSeesMatlabPost
                odbTag (1,1) = ""

                options.nodeTags    double = []
                options.respType    {mustBeTextScalar} = ""
            end
            
            odbTag = string(odbTag);
            if strlength(odbTag) == 0
                error('getODBData:InvalidODBTag', ...
                    'An odbTag must be provided.');
            end

            data = post.ODB.readNodeResponse(odbTag, nodeTags=options.nodeTags, respType=options.respType);
         end

         function data = getElementResponse(obj, odbTag, options)
            % Get element response data from an ODB.
            %
            % Example
            % --------
            %     data = obj.getElementResponse("MyODB")
            %     data = obj.getElementResponse("MyODB", eleTags=[1,2,3], respType="force")
            %
            % Parameters
            % ----------
            % odbTag : char | string | numeric
            %     The identifier of the ODB to read from.
            % eleTags : double array, optional
            %     An array of element tags to filter the response data. If empty or not provided, responses for all elements will be returned.
            % eleType : char | string, optional
            %     The type of element to filter the response data (e.g., "Frame", "Truss", "Shell", "Plane", "Solid"). If empty or not provided, responses for all element types will be returned.
            % respType : char | string, optional
            %     The type of element response to retrieve (e.g., "force", "stress"). If empty or not provided, all types of element responses will be returned.
            %
            % Returns
            % -------
            % data : struct
            %     A struct containing the element response data for the specified elements and response type.

            arguments
                obj (1,1) OpenSeesMatlabPost
                odbTag (1,1) = ""

                options.eleType   {mustBeTextScalar} = ""
                options.eleTags   double = []
                options.respType  {mustBeTextScalar} = ""
            end
            
            odbTag = string(odbTag);
            if strlength(odbTag) == 0
                error('getODBData:InvalidODBTag', ...
                    'An odbTag must be provided.');
            end
            data = post.ODB.readElementResponse(...
                    odbTag, eleType=options.eleType, eleTags=options.eleTags, respType=options.respType);
         end

        function writeResponsePVD(obj, odbTag, outDir, fileName, options)
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
            % fileName : char | string, optional
            %     The base name for the output files. Default is "paraview_anim".
            % includeNodal, includeShell, includePlane, includeSolid : logical, optional
            %     Flags to specify which types of responses to include in the output. By default, all types are included.



            arguments
                obj (1,1) OpenSeesMatlabPost
                odbTag (1,1) = ""
                outDir (1,:) {mustBeTextScalar} = "paraview_output"
                fileName (1,:) {mustBeTextScalar} = ''
                options.includeNodal (1,1) logical = true
                options.includeShell (1,1) logical = true
                options.includePlane (1,1) logical = true
                options.includeSolid (1,1) logical = true
                % options.binary (1,1) logical = false
            end

            groups = string(post.resp.ModelInfoStepData.RESP_NAME);
            if options.includeNodal
                groups(end+1) = string(post.resp.NodalRespStepData.RESP_NAME);
            end
            if options.includeShell
                groups(end+1) = string(post.resp.ShellRespStepData.RESP_NAME);
            end
            if options.includePlane
                groups(end+1) = string(post.resp.PlaneRespStepData.RESP_NAME);
            end
            if options.includeSolid
                groups(end+1) = string(post.resp.SolidRespStepData.RESP_NAME);
            end

            loaded = obj.localLoadODBGroup(odbTag, groups);
            modelInfo = obj.localGetODBGroup(loaded, post.resp.ModelInfoStepData.RESP_NAME);
            if isempty(fieldnames(modelInfo))
                error('OpenSeesMatlabPost:MissingModelInfo', ...
                    'ModelInfo was not found for odbTag=%s.', string(odbTag));
            end

            nodalResp = struct();
            shellResp = struct();
            planeResp = struct();
            solidResp = struct();

            if options.includeNodal
                nodalResp = post.resp.NodalRespStepData.readResponse( ...
                    obj.localGetODBGroup(loaded, post.resp.NodalRespStepData.RESP_NAME));
                if ~isempty(fieldnames(nodalResp))
                    nodalResp.odbTag = odbTag;
                end
            end
            if options.includeShell
                shellResp = post.resp.ShellRespStepData.readResponse( ...
                    obj.localGetODBGroup(loaded, post.resp.ShellRespStepData.RESP_NAME));
                if ~isempty(fieldnames(shellResp))
                    shellResp.odbTag = odbTag;
                end
            end
            if options.includePlane
                planeResp = post.resp.PlaneRespStepData.readResponse( ...
                    obj.localGetODBGroup(loaded, post.resp.PlaneRespStepData.RESP_NAME));
                if ~isempty(fieldnames(planeResp))
                    planeResp.odbTag = odbTag;
                end
            end
            if options.includeSolid
                solidResp = post.resp.SolidRespStepData.readResponse( ...
                    obj.localGetODBGroup(loaded, post.resp.SolidRespStepData.RESP_NAME));
                if ~isempty(fieldnames(solidResp))
                    solidResp.odbTag = odbTag;
                end
            end

            writer = post.utils.PVDWriter(modelInfo, ...
                nodalResp=nodalResp, shellResp=shellResp, planeResp=planeResp, solidResp=solidResp);
            writer.write(char(outDir), char(fileName), binary=false);
        end
    end

    methods (Access = private)
        function checkOutputDir(obj)
            % Check if the output directory exists, and create it if it does not.
            if ~exist(obj.outputDir, 'dir')
                mkdir(obj.outputDir);
            end
        end
    end

    methods (Static, Access = private)
        function data = localLoadODBGroup(odbTag, groupName)
            try
                data = post.ODB.loadODB(odbTag, groups=groupName);
            catch
                data = struct();
            end
        end

        function data = localGetODBGroup(loaded, groupName)
            data = struct();
            groupName = char(string(groupName));
            if ~isstruct(loaded) || ~isfield(loaded, groupName)
                return;
            end

            data = loaded.(groupName);
            if isempty(data)
                data = struct();
            end
        end
    end
end