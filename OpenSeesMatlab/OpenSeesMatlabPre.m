classdef OpenSeesMatlabPre < handle
    % Pre-processing interface for OpenSeesMatlab. OpenSeesMatlabPre provides methods for defining and modifying OpenSees models.

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
            % Set up the section geometry recorder to track section definitions for post-processing and visualization.
            % Currently, the section geometry recorder is designed to work with fiber sections.
            %
            % Parameters
            % ----------
            % sw : logical, optional
            %     If true, the section geometry recorder will be enabled to track section definitions. If false, the recorder will be disabled. Default is true.

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
            % Plot the section geometry for a given section tag.
            % This method uses the section geometry recorder to visualize the section defined by the specified tag. It can plot fiber sections, including fiber arrangements and patch definitions.
            %
            % Parameters
            % ----------
            % secTag : double
            %     The section tag for which to plot the geometry. This should correspond to a section defined in the OpenSees model.
            % ax : axes handle, optional
            %     An optional axes handle to plot on. If not provided, a new figure will be created for the plot.

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
            % Get nodal mass data from the OpenSees model, including the
            % mass assembled from the model (node, element, and mass matrix contributions).
            %
            % Returns
            % ----------
            % nodeMass : containers.Map
            %   Key   : node tag
            %   Value : row vector of nodal masses for each DOF

            nodeMass = pre.ModelDataUtils.getNodeMass(obj.parent.opensees);

        end

        function out = getMCK(obj, matrixType, options)
            % Get the mass, damping, stiffness, or initial stiffness matrix.
            %
            % Parameters
            % ----------
            % matrixType: char or string
            %     Type of matrix to retrieve. Options are:
            %
            %     - 'm'  - Mass matrix
            %     - 'c'  - Damping matrix
            %     - 'k'  - Stiffness matrix
            %     - 'ki' - Initial stiffness matrix
            % constraintsArgs: cell array
            %     Arguments for handling constraints when forming the matrix. For example:
            %     - {'Penalty', 1e10, 1e10} to use the penalty method with specified parameters.
            % systemArgs: cell array, optional
            %     Arguments for the system of equations to solve when forming the matrix. Default is {'FullGeneral'}.
            % numbererArgs: cell array, optional
            %     Arguments for the DOF numberer to use when forming the matrix. Default is {'Plain'}.
            % 
            % Returns
            % ----------
            % matrix : struct
            %     - .Type   - Type of matrix ('m', 'c', 'k', or 'ki')
            %     - .Data   - The matrix data as a sparse matrix
            %     - .Labels - Cell array of DOF labels corresponding to the rows/columns of the matrix
            %

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
            % Apply gravity loads from nodal masses, which can be obtained from the mass matrix (from node, element, and mass matrix contributions). This method calculates the gravity loads based on the nodal masses and applies them to the model using the OpenSees command ``load``.
            %
            % Parameters
            % ----------
            % excludeNodes : double array, optional
            %     Array of node tags to exclude from gravity load application. Default is an empty array, meaning all nodes will be included.
            % direction : string, optional
            %     Direction of the gravity load. Options are 'X', 'Y', 'Z', 'x', 'y', 'z'. Default is 'Z'.
            % factor : double, optional
            %     Factor to scale the gravity load. Default is -9.81.
            %
            % Returns
            % -------
            % nodeLoads : containers.Map
            %     key   = node tag
            %     value = row vector nodal load

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
            % Transform beam uniform loads from global to local coordinates
            % and directly call ops.eleLoad(...).
            %
            % Parameters
            % ----------
            % eleTags : double array
            %     Array of element tags to which the uniform load will be applied
            % wx : double, optional
            %     Uniform load intensity in the global x-direction. Default is 0.0.
            % wy : double, optional
            %     Uniform load intensity in the global y-direction. Default is 0.0.
            % wz : double, optional
            %     Uniform load intensity in the global z-direction. Default is 0.0.

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
            % Transform beam point loads from global to local coordinates
            % and directly call ops.eleLoad(...).
            %
            % Parameters
            % ----------
            % eleTags : double array
            %     Array of element tags to which the point load will be applied
            % px : double, optional
            %     Point load magnitude in the global x-direction. Default is 0.0.
            % py : double, optional
            %     Point load magnitude in the global y-direction. Default is 0.0.
            % pz : double, optional
            %     Point load magnitude in the global z-direction. Default is 0.0.
            % xl : double, optional
            %     Location of the point load along the beam element as a fraction of the element length (0.0 to 1.0). Default is 0.5 (mid-span).

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
            % Convert uniform pressure on surface elements to equivalent
            % nodal loads in global coordinates.
            %
            % Parameters
            % ----------
            % eleTags : double array
            %     Array of surface element tags to which the pressure load will be applied
            % p : double
            %     Uniform surface load magnitude (per unit area) along the surface normal direction. The positive direction of the normal is obtained by the cross-product of the I-J and J-K edges. If a list or numpy array is provided, the length should be the same as the number of elements.

            arguments
                obj OpenSeesMatlabPre
                eleTags double
                p double = 0.0
            end

            obj.loadTools.SurfaceGlobalPressureLoad(eleTags, p);
        end
    end
end