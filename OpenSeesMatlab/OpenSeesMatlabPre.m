classdef OpenSeesMatlabPre < handle
    % OpenSeesMatlabPre Pre-processing utilities for OpenSeesMatlab.
    %
    %   OpenSeesMatlabPre groups helper tools used before and during model
    %   construction. It is created automatically by OpenSeesMatlab and is
    %   accessed through the pre property:
    %
    %       opsmat = OpenSeesMatlab();
    %       pre = opsmat.pre;
    %       ops = opsmat.opensees;
    %
    %   The interface includes:
    %
    %   - unitSystem for unit metadata and conversion helpers.
    %   - Gmsh2OPS for converting Gmsh meshes to OpenSees definitions.
    %   - section geometry recording for plotting fiber sections.
    %   - model-data utilities such as nodal mass and M/C/K matrix extraction.
    %   - load transformation helpers for gravity, beam, and surface loads.
    %
    % Example
    % -------
    %       opsmat = OpenSeesMatlab();
    %       ops = opsmat.opensees;
    %
    %       ops.wipe();
    %       ops.model('basic', '-ndm', 2, '-ndf', 3);
    %
    %       opsmat.pre.setSectionGeometryRecorder(true);
    %       ops.section('Fiber', 1, '-GJ', 1.0e6);
    %       ops.patch('rect', 1, 10, 10, -0.2, -0.3, 0.2, 0.3);
    %       opsmat.pre.plotSection(1);
    %       opsmat.pre.setSectionGeometryRecorder(false);
    %
    %       nodeMass = opsmat.pre.getNodeMass();
    %       K = opsmat.pre.getMCK('k');

    properties (Access = private)
        parent    % Reference to the parent OpenSeesMatlab object
    end

    properties (Access = private)
        loadTools pre.LoadTools    % Load tools for applying loads and transformations
    end

    properties
        secGeoRecorder = []    % pre.utils.SectionGeometryRecorder
        unitSystem    % Unit system information for the model, including length, force, time, etc. This can be used for unit conversions and ensuring consistency in model definitions and results interpretation. See pre.UnitSystem for details.
        Gmsh2OPS   % Gmsh2OPS object for converting Gmsh mesh files to OpenSees model definitions. This can be used to import complex geometries and meshes created in Gmsh into OpenSees for analysis. See pre.Gmsh2OPS for details.
    end

    methods
        function obj = OpenSeesMatlabPre(parentObj)
            % Construct the pre-processing interface.
            %
            %   Users normally do not instantiate this class directly. The main
            %   OpenSeesMatlab constructor creates it and stores it as opsmat.pre.
            %   The constructor initializes the unit system, load tools, and Gmsh
            %   mesh converter using the parent OpenSees command interface.
            %
            % Parameters
            % ----------
            % parentObj : OpenSeesMatlab
            %     Parent OpenSeesMatlab object. The pre-processing interface uses
            %     parentObj.opensees to query model data and issue load commands.
            %
            % Example
            % -------
            %     opsmat = OpenSeesMatlab();
            %     pre = opsmat.pre;
            if nargin < 1 || isempty(parentObj)
                error('OpenSeesMatlabPre:InvalidInput', ...
                    'A parent OpenSeesMatlab object is required.');
            end
            obj.parent = parentObj;
            obj.unitSystem = pre.UnitSystem();

            obj.loadTools = pre.LoadTools(obj.parent.opensees);

            obj.Gmsh2OPS = pre.Gmsh2OPS(Ops=obj.parent.opensees);
        end
    end

    methods
        function setSectionGeometryRecorder(obj, sw)
            % Enable or disable section geometry recording.
            %
            %   When enabled, fiber-section-related OpenSees commands issued
            %   through opsmat.opensees are recorded by a SectionGeometryRecorder.
            %   The recorded geometry can then be plotted with plotSection. This
            %   is useful because OpenSees itself does not retain enough section
            %   construction history for visualization in all workflows.
            %
            % Syntax
            % ------
            %     pre.setSectionGeometryRecorder()
            %     pre.setSectionGeometryRecorder(true)
            %     pre.setSectionGeometryRecorder(false)
            %
            % Parameters
            % ----------
            % sw : logical, optional
            %     If true, enable section geometry recording. If false, disable it
            %     and clear the current recorder. Default is true.
            %
            % Example
            % -------
            %     opsmat = OpenSeesMatlab();
            %     ops = opsmat.opensees;
            %
            %     opsmat.pre.setSectionGeometryRecorder(true);
            %     ops.section('Fiber', 1, '-GJ', 1.0e6);
            %     ops.patch('rect', 1, 10, 10, -0.2, -0.3, 0.2, 0.3);
            %     opsmat.pre.plotSection(1);

            arguments
                obj (1,1) OpenSeesMatlabPre
                sw logical = true  % If true, disable the section geometry recorder
            end

            if sw
                obj.secGeoRecorder = pre.utils.SectionGeometryRecorder();
            else
                obj.secGeoRecorder = [];
            end
        end

        function plotSection(obj, secTag, ax)
            % Plot recorded fiber-section geometry.
            %
            %   plotSection visualizes a section previously recorded by
            %   setSectionGeometryRecorder(true). The recorder must be enabled
            %   before the corresponding OpenSees section, fiber, patch, and layer
            %   commands are issued.
            %
            % Syntax
            % ------
            %     pre.plotSection(secTag)
            %     pre.plotSection(secTag, ax)
            %
            % Parameters
            % ----------
            % secTag : double
            %     Section tag to plot. It should match a section tag previously
            %     defined through ops.section while recording was enabled.
            % ax : axes handle, optional
            %     Target axes for plotting. If empty or omitted, the recorder will
            %     create a suitable figure/axes.
            %
            % Example
            % -------
            %     opsmat.pre.setSectionGeometryRecorder(true);
            %     ops.section('Fiber', 1, '-GJ', 1.0e6);
            %     ops.fiber(0.0, 0.0, 0.01, 1);
            %     opsmat.pre.plotSection(1);

            arguments
                obj (1,1) OpenSeesMatlabPre
                secTag (1,1) double  % Section tag to plot
                ax  = []  % Optional axes handle to plot on. If not provided, a new figure will be created.
            end
            if isempty(obj.secGeoRecorder)
                error('Section geometry recorder is not set up. Please call setSectionGeometryRecorder(true) to enable it before plotting sections.');
            end
            obj.secGeoRecorder.plotSection(secTag, ax);
        end

        function nodeMass = getNodeMass(obj)
            % Get assembled nodal mass data from the current OpenSees model.
            %
            %   The returned map contains nodal mass contributions assembled from
            %   model definitions, element mass contributions, and mass matrix
            %   information supported by the underlying utility implementation.
            %
            % Syntax
            % ------
            %     nodeMass = pre.getNodeMass()
            %
            % Returns
            % -------
            % nodeMass : containers.Map
            %     Map of nodal masses.
            %
            %     - Key   : node tag
            %     - Value : row vector of nodal masses for each degree of freedom
            %
            % Example
            % -------
            %     nodeMass = opsmat.pre.getNodeMass();
            %     m1 = nodeMass(1);

            nodeMass = pre.ModelDataUtils.getNodeMass(obj.parent.opensees);

        end

        function out = getMCK(obj, matrixType, options)
            % Assemble and return a global model matrix.
            %
            %   getMCK extracts the current global mass, damping, stiffness, or
            %   initial stiffness matrix from the OpenSees model using the
            %   specified constraint handler, system, and numberer settings.
            %
            % Syntax
            % ------
            %     out = pre.getMCK(matrixType)
            %     out = pre.getMCK(matrixType, constraintsArgs=args)
            %     out = pre.getMCK(matrixType, systemArgs=args, numbererArgs=args)
            %
            % Parameters
            % ----------
            % matrixType : char or string
            %     Type of matrix to retrieve. Options are:
            %
            %     - 'm'  : mass matrix
            %     - 'c'  : damping matrix
            %     - 'k'  : tangent stiffness matrix
            %     - 'ki' : initial stiffness matrix
            % constraintsArgs : cell array, optional
            %     Arguments passed to the OpenSees constraints command when
            %     forming the matrix. Default is {'Penalty', 1e12, 1e12}.
            % systemArgs : cell array, optional
            %     Arguments passed to the OpenSees system command. Default is
            %     {'FullGeneral'}.
            % numbererArgs : cell array, optional
            %     Arguments passed to the OpenSees numberer command. Default is
            %     {'Plain'}.
            %
            % Returns
            % -------
            % out : struct
            %     Matrix data and labels.
            %
            %     - .Type   : matrix type, one of 'm', 'c', 'k', or 'ki'
            %     - .Data   : sparse matrix data
            %     - .Labels : cell array of DOF labels for rows/columns
            %
            % Example
            % -------
            %     K = opsmat.pre.getMCK('k');
            %     M = opsmat.pre.getMCK('m', ...
            %         constraintsArgs={'Penalty', 1e12, 1e12}, ...
            %         systemArgs={'FullGeneral'}, ...
            %         numbererArgs={'Plain'});

            arguments
                obj (1,1) OpenSeesMatlabPre
                matrixType {mustBeTextScalar, mustBeMember(matrixType, {'m', 'c', 'k', 'ki'})}
                options.constraintsArgs cell = {'Penalty', 1e12, 1e12}
                options.systemArgs cell = {'FullGeneral'}
                options.numbererArgs cell = {'Plain'}
            end

            out = pre.ModelDataUtils.getMCK(obj.parent.opensees, matrixType, options.constraintsArgs, options.systemArgs, options.numbererArgs);
        end

        function nodeLoads = createGravityLoad(obj, opts)
            % Create and apply gravity loads from assembled nodal masses.
            %
            %   This method obtains nodal mass information and converts it to
            %   equivalent nodal gravity loads. The generated loads are applied to
            %   the active OpenSees load pattern by calling the OpenSees load
            %   command through the parent command interface.
            %
            % Syntax
            % ------
            %     nodeLoads = pre.createGravityLoad()
            %     nodeLoads = pre.createGravityLoad(direction="Z", factor=-9.81)
            %     nodeLoads = pre.createGravityLoad(excludeNodes=[1 2], direction="Y")
            %
            % Parameters
            % ----------
            % excludeNodes : double array, optional
            %     Node tags to exclude from gravity load application. Default is
            %     empty, meaning all nodes with assembled mass are included.
            % direction : string, optional
            %     Gravity direction. Must be "X", "Y", "Z", "x", "y", or "z".
            %     Default is "Z".
            % factor : double, optional
            %     Gravity/load scale factor. Default is -9.81.
            %
            % Returns
            % -------
            % nodeLoads : containers.Map
            %     Applied nodal loads.
            %
            %     - Key   : node tag
            %     - Value : row vector nodal load
            %
            % Example
            % -------
            %     ops.timeSeries('Linear', 1);
            %     ops.pattern('Plain', 1, 1);
            %     nodeLoads = opsmat.pre.createGravityLoad(direction="Z", factor=-9.81);

            arguments
                obj
                opts.excludeNodes double = []
                opts.direction string {mustBeMember(opts.direction, ["X","Y","Z","x","y","z"])} = "Z"
                opts.factor (1,1) double = -9.81
            end

            nodeLoads = obj.loadTools.createGravityLoad(...
                            excludeNodes=opts.excludeNodes,...
                            direction=opts.direction,...
                            factor=opts.factor);
        end

        function beamGlobalUniformLoad(obj, eleTags, opts)
            % Apply global uniform loads to beam elements.
            %
            %   The input load components are defined in the global coordinate
            %   system. They are transformed to each beam element's local
            %   coordinate system and then applied through ops.eleLoad(...).
            %
            % Syntax
            % ------
            %     pre.beamGlobalUniformLoad(eleTags)
            %     pre.beamGlobalUniformLoad(eleTags, wx=wx, wy=wy, wz=wz)
            %
            % Parameters
            % ----------
            % eleTags : double array
            %     Element tags to which the uniform load will be applied.
            % wx : double, optional
            %     Uniform load intensity in the global x direction. Default is 0.0.
            % wy : double, optional
            %     Uniform load intensity in the global y direction. Default is 0.0.
            % wz : double, optional
            %     Uniform load intensity in the global z direction. Default is 0.0.
            %
            % Example
            % -------
            %     ops.timeSeries('Linear', 1);
            %     ops.pattern('Plain', 1, 1);
            %     opsmat.pre.beamGlobalUniformLoad([1 2 3], wx=0, wy=-10, wz=0);

            arguments
                obj OpenSeesMatlabPre
                eleTags double
                opts.wx double = 0.0
                opts.wy double = 0.0
                opts.wz double = 0.0
            end
            obj.loadTools.BeamGlobalUniformLoad(eleTags, wx=opts.wx, wy=opts.wy, wz=opts.wz);
        end

        function beamGlobalPointLoad(obj, eleTags, opts)
            % Apply global point loads to beam elements.
            %
            %   The input load components are defined in the global coordinate
            %   system. They are transformed to each beam element's local
            %   coordinate system and then applied through ops.eleLoad(...).
            %
            % Syntax
            % ------
            %     pre.beamGlobalPointLoad(eleTags)
            %     pre.beamGlobalPointLoad(eleTags, px=px, py=py, pz=pz, xl=xl)
            %
            % Parameters
            % ----------
            % eleTags : double array
            %     Element tags to which the point load will be applied.
            % px : double, optional
            %     Point load magnitude in the global x direction. Default is 0.0.
            % py : double, optional
            %     Point load magnitude in the global y direction. Default is 0.0.
            % pz : double, optional
            %     Point load magnitude in the global z direction. Default is 0.0.
            % xl : double, optional
            %     Location along each beam element as a fraction of the element
            %     length. Use 0.0 at the I end, 1.0 at the J end, and 0.5 for
            %     midspan. Default is 0.5.
            %
            % Example
            % -------
            %     ops.timeSeries('Linear', 1);
            %     ops.pattern('Plain', 1, 1);
            %     opsmat.pre.beamGlobalPointLoad([1 2], py=-100, xl=0.5);

            arguments
                obj OpenSeesMatlabPre
                eleTags double
                opts.px double = 0.0
                opts.py double = 0.0
                opts.pz double = 0.0
                opts.xl double = 0.5
            end
             obj.loadTools.BeamGlobalPointLoad(eleTags, px=opts.px, py=opts.py, pz=opts.pz, xl=opts.xl);
         end

        function surfaceGlobalPressureLoad(obj, eleTags, p)
            % Apply uniform pressure loads to surface elements.
            %
            %   This method converts uniform pressure on surface elements to
            %   equivalent nodal loads in global coordinates. The positive surface
            %   normal follows the cross product of the I-J and J-K element edges.
            %
            % Syntax
            % ------
            %     pre.surfaceGlobalPressureLoad(eleTags, p)
            %
            % Parameters
            % ----------
            % eleTags : double array
            %     Surface element tags to which the pressure load will be applied.
            % p : double
            %     Uniform pressure magnitude per unit area. p can be scalar or a
            %     vector with one value per element tag.
            %
            % Example
            % -------
            %     ops.timeSeries('Linear', 1);
            %     ops.pattern('Plain', 1, 1);
            %     opsmat.pre.surfaceGlobalPressureLoad([101 102 103], -5.0);

            arguments
                obj OpenSeesMatlabPre
                eleTags double
                p double = 0.0
            end

            obj.loadTools.SurfaceGlobalPressureLoad(eleTags, p);
        end
    end
end
