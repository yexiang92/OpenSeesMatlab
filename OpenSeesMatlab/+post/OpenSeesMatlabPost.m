classdef OpenSeesMatlabPost < handle
    % OpenSeesMatlabPost Post-processing interface for OpenSeesMatlab.
    %
    %   OpenSeesMatlabPost provides high-level utilities for collecting model
    %   information, saving/loading model metadata, collecting eigenvalue results,
    %   and creating output databases for step-by-step response storage.
    %
    %   Users normally access this class through the post property of the main
    %   OpenSeesMatlab object:
    %
    %       opsmat = OpenSeesMatlab();
    %       post = opsmat.post;
    %
    %   The post-processing workflow is typically:
    %
    %   1. Build an OpenSees model with opsmat.opensees.
    %   2. Collect or save model metadata with getModelData or saveModelData.
    %   3. Collect eigen data with getEigenData or saveEigenData when needed.
    %   4. Create an ODB with createODB for response history storage.
    %   5. Use opsmat.vis to visualize collected model/eigen/response data.
    %
    % Example
    % -------
    %       opsmat = OpenSeesMatlab();
    %       ops = opsmat.opensees;
    %
    %       % Build model with ops...
    %       % ops.wipe();
    %       % ops.model(...);
    %       % ops.node(...);
    %       % ops.element(...);
    %
    %       post = opsmat.post;
    %       post.setOutputDir(".openseesmatlab.output");
    %
    %       modelInfo = post.getModelData();
    %       post.saveModelData("ModelA");
    %
    %       eigenData = post.getEigenData(numModes=3, solver="-genBandArpack");
    %       post.saveEigenData("ModelA", 3, solver="-genBandArpack");

    properties (Access = private)
        parent  % Reference to the parent OpenSeesMatlab object
        outputDir = ".openseesmatlab.output"  % Output directory for OpenSeesMatlabPost
    end

    methods
        function obj = OpenSeesMatlabPost(parentObj)
            % Construct an OpenSeesMatlabPost object.
            %
            %   The constructor is called by OpenSeesMatlab and normally should
            %   not be called directly. It stores the parent OpenSeesMatlab object
            %   so post-processing utilities can access the shared OpenSees command
            %   interface through parentObj.opensees.
            %
            % Parameters
            % ----------
            % parentObj : OpenSeesMatlab
            %     Parent OpenSeesMatlab object that owns this post-processing
            %     interface.
            %
            % Example
            % -------
            %     opsmat = OpenSeesMatlab();
            %     post = opsmat.post;

            if nargin < 1 || isempty(parentObj)
                error('OpenSeesMatlabPost:InvalidInput', ...
                    'A parent OpenSeesMatlab object is required.');
            end
            obj.parent = parentObj;
        end

        function setOutputDir(obj, dir)
            % Set the output directory used by post-processing save operations.
            %
            %   The output directory is used by saveModelData, saveEigenData, and
            %   response database utilities. If the directory does not exist, it is
            %   created automatically.
            %
            % Parameters
            % ----------
            % dir : char or string
            %     Output directory path. Relative paths are interpreted relative to
            %     the current MATLAB working directory.
            %
            % Example
            % -------
            %     post = opsmat.post;
            %     post.setOutputDir(".openseesmatlab.output");

            arguments
                obj (1,1) post.OpenSeesMatlabPost
                dir {mustBeTextScalar} = ".openseesmatlab.output"
            end

            obj.outputDir = char(dir);
            obj.checkOutputDir();

        end

        function outDir = getOutputDir(obj)
            % Get the current post-processing output directory.
            %
            % Returns
            % -------
            % outDir : char or string
            %     Directory used by post-processing save operations.
            %
            % Example
            % -------
            %     outDir = opsmat.post.getOutputDir();
            outDir = obj.outputDir;
        end


        function saveModelData(obj, odbTag)
            % Collect and save current OpenSees model information to an HDF5 file.
            %
            %   The saved file is named modelData_<odbTag>.hdf5 and is written to
            %   the directory returned by getOutputDir. Use getModelData(odbTag)
            %   to read the saved model data back from disk.
            %
            % Parameters
            % ----------
            % odbTag : char, string, or numeric, optional
            %     Identifier used in the saved file name. Default is 1.
            %
            % Example
            % -------
            %     post = opsmat.post;
            %     post.setOutputDir(".openseesmatlab.output");
            %     post.saveModelData("ModelA");
            %

            arguments
                obj (1,1) post.OpenSeesMatlabPost
                odbTag = "1"
            end

            filename = sprintf('modelData_%s.hdf5', string(odbTag));

            filename = fullfile(obj.outputDir, filename);
            obj.checkOutputDir();

            modelData = post.FEMDataCollector(obj.parent.opensees, post.utils.OpenSeesTagMaps());
            modelData.collect();
            modelData.save(filename);
        end

        function modelInfo = getModelData(obj, odbTag)
            % Get model information from the current OpenSees model or from file.
            %
            %   Without odbTag, this method collects model metadata directly from
            %   the current OpenSees model in memory. With odbTag, it reads the
            %   file modelData_<odbTag>.hdf5 from the current output directory.
            %
            % Parameters
            % ----------
            % odbTag : char, string, or numeric, optional
            %     Identifier of saved model data. If omitted or empty, model data
            %     is collected from the current OpenSees model.
            %
            % Returns
            % -------
            % modelInfo : struct
            %     Model information structure used by post-processing and
            %     visualization utilities.
            %
            % Examples
            % --------
            %     modelInfo = opsmat.post.getModelData();
            %     modelInfo = opsmat.post.getModelData("ModelA");

            arguments
                obj (1,1) post.OpenSeesMatlabPost
                odbTag  = ""
            end

            odbTag = string(odbTag);

            modelData = post.FEMDataCollector(obj.parent.opensees, post.utils.OpenSeesTagMaps());

            if strlength(odbTag) == 0
                modelInfo = modelData.getModelInfo();
            else
                filename = sprintf('modelData_%s.hdf5', string(odbTag));
                filename = fullfile(obj.outputDir, filename);
                modelInfo = modelData.readFile(filename);
            end
        end

        function saveEigenData(obj, odbTag, numModes, options)
            % Collect eigenvalue analysis results and save them to an HDF5 file.
            %
            %   The saved file is named eigenData_<odbTag>.hdf5 and is written to
            %   the directory returned by getOutputDir. The method first collects
            %   model information from the current OpenSees model, then computes
            %   and stores the requested eigen data.
            %
            % Parameters
            % ----------
            % odbTag : char, string, or numeric, optional
            %     Identifier used in the saved file name. Default is 1.
            % numModes : positive integer, optional
            %     Number of modes to collect and save. Default is 1.
            % solver : char or string, optional
            %     OpenSees eigen solver option. Default is "-genBandArpack".
            % IncludeModelInfo : logical, optional
            %     If true, include model information in the saved eigen-data
            %     structure. Default is false.
            % InterpolateBeam : logical, optional
            %     If true, interpolate beam element modal displacements by shape
            %     functions. Default is true.
            % NptsPerElement : integer >= 2, optional
            %     Number of interpolation points per beam element. Default is 6.
            %
            % Examples
            % --------
            %     post.saveEigenData("ModelA", 3);
            %     post.saveEigenData("ModelA", 3, solver="-genBandArpack");
            %     post.saveEigenData("ModelA", 3, ...
            %         solver="-genBandArpack", ...
            %         IncludeModelInfo=true, ...
            %         InterpolateBeam=false, ...
            %         NptsPerElement=8);

            arguments
                obj (1,1) post.OpenSeesMatlabPost
                odbTag  = "1"
                numModes (1,1) {mustBeInteger, mustBePositive} = 1
                options.solver {mustBeTextScalar, mustBeMember(options.solver, ["-genBandArpack", "-fullGenLapack"])} = "-genBandArpack"
                options.IncludeModelInfo (1,1) logical = false
                options.InterpolateBeam (1,1) logical = true
                options.NptsPerElement (1,1) double {mustBeInteger, mustBeGreaterThanOrEqual(options.NptsPerElement, 2)} = 6
            end

            filename = sprintf('eigenData_%s.hdf5', string(odbTag));
            filename = fullfile(obj.outputDir, filename);
            obj.checkOutputDir();

            solver = char(options.solver);

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
            % Get eigen data from file or collect it from the current model.
            %
            %   If odbTag is provided, this method reads eigenData_<odbTag>.hdf5
            %   from the current output directory. Otherwise, it collects eigen
            %   data from the current OpenSees model using the requested number of
            %   modes and solver options.
            %
            % Parameters
            % ----------
            % odbTag : char, string, or numeric, optional
            %     Identifier of saved eigen data. If provided and nonempty, data is
            %     loaded from eigenData_<odbTag>.hdf5.
            % numModes : positive integer, optional
            %     Number of modes to collect when odbTag is not provided. Default
            %     is 1.
            % solver : char or string, optional
            %     OpenSees eigen solver option. Default is "-genBandArpack".
            % IncludeModelInfo : logical, optional
            %     If true, include model information in the output structure.
            %     Default is false.
            % InterpolateBeam : logical, optional
            %     If true, interpolate beam element modal displacements. Default
            %     is true.
            % NptsPerElement : integer >= 2, optional
            %     Number of interpolation points per beam element. Default is 6.
            %
            % Returns
            % -------
            % out : struct
            %     Eigenvalue analysis results.
            %
            % Examples
            % --------
            %     eigenData = post.getEigenData(numModes=3);
            %     eigenData = post.getEigenData(numModes=3, solver="-genBandArpack");
            %     eigenData = post.getEigenData(numModes=3, InterpolateBeam=false);
            %     eigenData = post.getEigenData(odbTag="ModelA");

            arguments
                obj (1,1) post.OpenSeesMatlabPost
                options.odbTag  = ""
                options.numModes (1,1) {mustBeInteger, mustBePositive} = 1
                options.solver {mustBeTextScalar, mustBeMember(options.solver, ["-genBandArpack", "-fullGenLapack"])} = "-genBandArpack"
                options.IncludeModelInfo (1,1) logical = false
                options.InterpolateBeam (1,1) logical = true
                options.NptsPerElement (1,1) double {mustBeInteger, mustBeGreaterThanOrEqual(options.NptsPerElement, 2)} = 6
            end

            odbTag = string(options.odbTag);
            if strlength(odbTag) > 0
                filename = sprintf('eigenData_%s.hdf5', odbTag);
                filename = fullfile(obj.outputDir, filename);
                modeData = post.EigenDataCollector(obj.parent.opensees, []);
                out = modeData.readFile(char(filename));
                return;
            end

            numModes = options.numModes;
            solver = char(options.solver);
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
            % Create an output database for storing response data over analysis steps.
            %
            %   The returned ODB object can fetch and store model responses after
            %   each analysis step. This is the recommended workflow for response
            %   histories that will later be loaded, queried, or visualized.
            %
            % Example
            % -------
            %     odb = post.createODB("MyODB", flushEvery=50);
            %
            % Parameters
            % ----------
            % odbTag : char | string | numeric
            %     A unique identifier for the ODB.
            % flushEvery : integer, optional
            %     If provided, specifies the frequency (in steps) at which to save data to disk.
            % elasticFrameSecPoints : integer, optional, default 9
            %     Number of points to use for elastic frame section integration.
            % interpolateBeamDisp : char | string | integer, optional, default "off"
            %     If "on", interpolate beam element displacements to integration points. If int, treat as number of points per element for interpolation.
            % computeMechanicalMeasures : cell array of char | string, optional, default {"principal", "vonMises", "octahedral", "tauMax"}
            %     Specifies which mechanical measures to compute for frame responses. Options include:
            %
            %     - "principal" (principal stresses)
            %     - "vonMises" (von Mises stress)
            %     - "octahedral" (octahedral shear and normal stress)
            %     - "tauMax" (maximum shear stress)

            % projectGaussToNodes : char | string, optional, default "extrapolate"
            %     Method to project Gauss point data to nodes for shell responses. Options are "
            %
            %     - "copy" (copy values from nearest Gauss point)
            %     - "extrapolate" (interpolate values from all Gauss points).
            %     - "average" (average values from all Gauss points).
            % saveNodalResp: logical, optional, default true
            %     Flag to save nodal response data.
            % nodeTags: double array, optional
            %     Array of node tags specifying which nodes to save responses for.
            % saveFrameResp: logical, optional, default true
            %     Flag to save frame response data.
            % frameTags: double array, optional
            %     Array of frame tags specifying which frames to save responses for.
            % saveFiberSecResp: logical, optional, default false
            %     Flag to save fiber section response data for frame elements.
            %     If true, fiber section responses are saved for all frame elements.
            %     This may be slow and memory-intensive for large models.
            % saveTrussResp: logical, optional, default true
            %     Flag to save truss response data.
            % trussTags: double array, optional
            %     Array of truss tags specifying which trusses to save responses for.
            % saveLinkResp: logical, optional, default true
            %     Flag to save link response data.
            % linkTags: double array, optional
            %     Array of link tags specifying which links to save responses for.
            % saveShellResp: logical, optional, default true
            %     Flag to save shell response data.
            % shellTags: double array, optional
            %     Array of shell tags specifying which shells to save responses for.
            % savePlaneResp: logical, optional, default true
            %     Flag to save plane response data.
            % planeTags: double array, optional
            %     Array of plane tags specifying which planes to save responses for.
            % saveBrickResp: logical, optional, default true
            %     Flag to save brick response data.
            % brickTags: double array, optional
            %     Array of brick tags specifying which bricks to save responses for.
            % saveContactResp: logical, optional, default true
            %     Flag to save contact response data.
            % contactTags: double array, optional
            %     Array of contact tags specifying which contacts to save responses for.
            %
            % Returns
            % -------
            % odb : post.ODB
            %     The created output database object.

            arguments
                obj (1,1) post.OpenSeesMatlabPost
                odbTag  = ""

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

                options.nodeTags                double = []
                options.frameTags               double = []
                options.trussTags               double = []
                options.linkTags                double = []
                options.shellTags               double = []
                options.planeTags               double = []
                options.solidTags               double = []
                options.contactTags             double = []

                options.elasticFrameSecPoints   double {mustBeInteger, mustBePositive} = 9
                options.interpolateBeamDisp             = "off"
                options.computeMechanicalMeasures       = {"principal", "tauMax", "octahedral", "vonMises"}
                options.projectGaussToNodes {mustBeTextScalar, mustBeMember(options.projectGaussToNodes, ["extrapolate", "average", "copy"])} = "extrapolate"
            end
            odbTag = string(odbTag);
            if strlength(odbTag) == 0
                error('getODBData:InvalidODBTag', ...
                    'An odbTag must be provided.');
            end
            opts = namedargs2cell(options);

            odb = post.ODB(obj.parent.opensees, odbTag, opts{:});
            odb.setOutputDir(obj.outputDir);
            odb.setFEMDataRecorder();
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
                obj (1,1) post.OpenSeesMatlabPost
                odbTag  = ""
            end

            odbTag = string(odbTag);
            if strlength(odbTag) == 0
                error('getODBData:InvalidODBTag', ...
                    'An odbTag must be provided.');
            end

            data = post.ODB.loadODB(obj.parent.opensees, odbTag);
        end

        function data = getModelDataFromODB(obj, odbTag)
            % Get model data from an ODB.
            %
            % Parameters
            % ----------
            % odbTag : char | string | numeric
            %     The identifier of the ODB to read from.
            %
            % Returns
            % -------
            % data : struct
            %     The model data from the ODB.

            arguments
                obj (1,1) post.OpenSeesMatlabPost
                odbTag  = ""
            end

            data = post.ODB.readModelInfo(obj.parent.opensees, odbTag);
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
                obj (1,1) post.OpenSeesMatlabPost
                odbTag  = ""

                options.nodeTags    double = []
                options.respType    {mustBeTextScalar, mustBeMember(options.respType, ["", "disp", "vel", "accel", "reaction","reactionIncInertia", "rayleighForces", "pressure"])} = ""
            end

            odbTag = string(odbTag);
            if strlength(odbTag) == 0
                error('getODBData:InvalidODBTag', ...
                    'An odbTag must be provided.');
            end

            data = post.ODB.readNodeResponse(obj.parent.opensees, odbTag, nodeTags=options.nodeTags, respType=options.respType);
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
                obj (1,1) post.OpenSeesMatlabPost
                odbTag = ""

                options.eleType   {mustBeTextScalar, mustBeMember(options.eleType, ["", "Frame", "Truss", "Shell", "Plane", "Solid"])} = ""
                options.eleTags   double = []
                options.respType  {mustBeTextScalar} = ""
            end

            odbTag = string(odbTag);
            if strlength(odbTag) == 0
                error('getODBData:InvalidODBTag', ...
                    'An odbTag must be provided.');
            end
            data = post.ODB.readElementResponse(obj.parent.opensees, ...
                    odbTag, eleType=options.eleType, eleTags=options.eleTags, respType=options.respType);
         end

        function results = writeResponsePVD(obj, odbTag, outDir, baseName, options)
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
            %     The base name for the output files. Default is "pv".
            % includeNodal, includeShell, includePlane, includeSolid : logical, optional
            %     Flags to specify which types of responses to include in the output. By default, all types are included.

            arguments
                obj (1,1) post.OpenSeesMatlabPost
                odbTag  = ""
                outDir {mustBeTextScalar} = "paraview_output"
                baseName {mustBeTextScalar} = "pv"
                options.includeNodal (1,1) logical = true
                options.includeShell (1,1) logical = true
                options.includePlane (1,1) logical = true
                options.includeSolid (1,1) logical = true
                % options.binary (1,1) logical = false
            end

            results = post.ODB.writePVD(obj.parent.opensees, odbTag, outDir, baseName, ...
                                includeNodal=options.includeNodal, ...
                                includeShell=options.includeShell, ...
                                includePlane=options.includePlane, ...
                                includeSolid=options.includeSolid);
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
            arguments
                loaded = []
                groupName {mustBeTextScalar} = ""
            end

            data = struct();
            groupName = char(groupName);
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
