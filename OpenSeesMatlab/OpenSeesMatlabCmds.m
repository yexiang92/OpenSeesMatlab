classdef OpenSeesMatlabCmds < OpenSeesMatlabBase
    % OpenSees command interface used by OpenSeesMatlab.
    %
    %   OpenSeesMatlabCmds exposes MATLAB methods that forward OpenSees commands
    %   to the configured OpenSees MATLAB MEX module. Most command wrappers are
    %   inherited from OpenSeesMatlabBase and follow the same argument order as
    %   OpenSees/OpenSeesPy where possible.
    %
    %   Users normally access this class through the opensees property of an
    %   OpenSeesMatlab object:
    %
    %       opsmat = OpenSeesMatlab();
    %       ops = opsmat.opensees;
    %
    % References
    % ----------
    %   OpenSeesPy documentation:
    %       https://openseespydoc.readthedocs.io/en/latest/index.html
    %
    %   OpenSees documentation:
    %       https://opensees.github.io/OpenSeesDocumentation/
    %

    properties (SetAccess = private, GetAccess = private)
        parent  % Reference to the parent OpenSeesMatlab object
    end

    methods
        function obj = OpenSeesMatlabCmds(parentObj, mexName, mexDir)
            % Construct an OpenSees command interface object.
            %
            %
            % Parameters
            % ----------
            % parentObj : OpenSeesMatlab
            %       Parent OpenSeesMatlab object that owns this command interface.
            %
            % mexName : string or char, optional
            %     Name of the OpenSees MATLAB MEX module. Default is 'OpenSeesMATLAB'.
            %
            % mexDir : string or char, optional
            %     Directory containing the MEX module. Default is 'derived/'.
            %
            % Note
            % ----
            %    You can set the your own MEX name and directory using the
            %    `mexName` and `mexDir` parameters.
            %
            % Example
            % -------
            %       opsmat = OpenSeesMatlab(mexName='OpenSeesMATLAB', mexDir='derived/');
            %       ops = opsmat.opensees;

            arguments
                parentObj (1,1) OpenSeesMatlab
                mexName  {mustBeTextScalar} = 'OpenSeesMATLAB'
                mexDir {mustBeTextScalar} = 'derived/'
            end
            obj@OpenSeesMatlabBase(mexName, mexDir);
            obj.parent = parentObj;
        end
    end

    %% OpenSees command overrides
    %   Most OpenSees command wrappers are implemented in OpenSeesMatlabBase.
    %   The overrides below add lightweight bookkeeping around section geometry
    %   commands and then delegate to the base implementation so the actual
    %   OpenSees command is still executed by the MEX module.
    %
    methods (Access = public)
        function varargout = wipe(obj)
            % Wipe the OpenSees model.
            [varargout{1:nargout}] = obj.mexHandle('wipe');
        end

        function varargout = model(obj, modelType, varargin)
            % Set the default model dimensions and number of dofs.
            %
            % Syntax
            % ------
            %     model()
            %     model('basic', '-ndm', 2)
            %     model('basic', '-ndm', 2, '-ndf', 3)
            %
            % Parameters
            % ----------
            % modelType : char | string
            %   Model type (default: 'basic')
            % ndm : int
            %   Number of spatial dimensions. Style ('-ndm', ndm) is needed.
            % ndf : int
            %   Number of degrees of freedom (default sets it to ndm*(ndm+1)/2). Style ('-ndf', ndf) is needed.
            %
            arguments
                obj
                modelType {mustBeTextScalar, mustBeMember(modelType, ...
                                    {'basic','Basic','BasicBuilder','basicBuilder'})}
            end
            arguments (Repeating)
                varargin
            end

            [varargout{1:nargout}] = obj.mexHandle('model', modelType, varargin{:});
        end

        function varargout = node(obj, nodeTag, varargin)
            % Create an OpenSees node.
            %
            % Syntax
            % ------
            %     ops.node(nodeTag, x, y)
            %     ops.node(nodeTag, x, y, z)
            %     ops.node(nodeTag, x, y, z, '-ndf', ndf)
            %     ops.node(nodeTag, x, y, z, '-mass', m1, m2, m3)
            %     ops.node(nodeTag, [x, y, z], '-mass', [m1, m2, m3])
            %
            % Parameters
            % ----------
            % nodeTag: int
            %   Node tag.
            % crds: double
            %   Nodal coordinates, multiple scalars or a double vector is supported.
            % ndf: int (optional)
            %   Number of degrees of freedom. Style ('-ndf', ndf) is needed.
            % mass: double (optional)
            %   Nodal mass vector. Style ('-mass', m1, m2, m3, ...) is needed.
            % vel: double (optional)
            %   Initial velocity vector. Style ('-vel', v1, v2, v3, ...) is needed.
            % disp: double (optional)
            %   Initial displacement vector. Style ('-disp', d1, d2, d3, ...) is needed.
            % dispLoc: double (optional)
            %   Displacement location. Style ('-dispLoc', loc1, loc2, loc3, ...) is needed.
            % temp: double (optional)
            %   Initial temperature. Style ('-temp', temp) is needed.
            arguments
                obj
                nodeTag (1,1) {mustBeNumeric}
            end

            arguments (Repeating)
                varargin
            end

            [varargout{1:nargout}] = obj.mexHandle('node', nodeTag, varargin{:});
        end

        function varargout = element(obj, eleType, eleTag, varargin)
            % Define an OpenSees element.
            % Every element has its own type, tag, nodes, and arguments.
            %
            % See also in [element commands](https://openseespydoc.readthedocs.io/en/latest/src/element.html)
            %
            % Example
            % --------
            %     eleType = 'truss';
            %     eleTag = 1;
            %     eleNodes = [iNode, jNode];
            %     eleArgs = {A, matTag};
            %     element(eleType, eleTag, eleNodes, eleArgs{:});
            %     % Or
            %     element(eleType, eleTag, iNode, jNode, A, matTag);
            %
            %
            % Parameters
            % -----------
            % eleType: string
            %   Element type.
            % eleTag: int
            %   Element tag.
            % eleNodes: varargin(int)
            %   Element nodes.
            % eleArgs: varargin
            %   Element arguments.

            arguments
                obj
                eleType {mustBeTextScalar}
                eleTag (1, 1) {mustBeNumeric}
            end

            arguments (Repeating)
                varargin
            end

            [varargout{1:nargout}] = obj.mexHandle('element', eleType, eleTag, varargin{:});
        end

        function varargout = fix(obj, nodeTag, constrValues)
            % Create a homogeneous single-point (SP) constriant.
            %
            % Syntax
            % ------
            %     fix(nodeTag, 1, 1, 1)
            %     fix(nodeTag, [1, 1, 1])
            %
            % Parameters
            % ----------
            % nodeTag: int
            %   Tag of node to be constrained.
            % constrValues: double
            %   Constraint values to be applied.
            %
            %   - 0: free
            %   - 1: fixed

            arguments
                obj
                nodeTag (1, 1) {mustBeNumeric}
            end

            arguments (Repeating)
                constrValues
            end

            [varargout{1:nargout}] = obj.mexHandle('fix', nodeTag, constrValues{:});
        end

        function varargout = fixX(obj, x, varargin)
            % Fix a node along the X direction.
            %
            % Parameters
            % ----------
            % x: double
            %   X coordinate of node to be constrained.
            %
            % constrValues: double
            %   Constraint values to be applied.
            %
            %   - 0: free
            %   - 1: fixed
            %
            % tol: double
            %   Tolerance for constraint satisfaction. Style ("-tol", tol) is needed.

            arguments
                obj
                x (1, 1) {mustBeNumeric}
            end

            arguments (Repeating)
                varargin
            end

            [varargout{1:nargout}] = obj.mexHandle('fixX', x, varargin{:});
        end

        function varargout = fixY(obj, y, varargin)
            % Fix a node along the Y direction.
            %
            % Parameters
            % ----------
            % y: double
            %   Y coordinate of node to be constrained.
            % constrValues: double
            %   Constraint values to be applied.
            %
            %   - 0: free
            %   - 1: fixed
            % tol: double
            %   Tolerance for constraint satisfaction. Style ("-tol", tol) is needed.

            arguments
                obj
                y (1, 1) {mustBeNumeric}
            end

            arguments (Repeating)
                varargin
            end

            [varargout{1:nargout}] = obj.mexHandle('fixY', y, varargin{:});
        end

        function varargout = fixZ(obj, z, varargin)
            % Fix a node along the Z direction.
            %
            % Parameters
            % ----------
            % z: double
            %   Z coordinate of node to be constrained.
            % constrValues: double
            %   Constraint values to be applied.
            %
            %   - 0: free
            %   - 1: fixed
            % tol: double
            %   Tolerance for constraint satisfaction. Style ("-tol", tol) is needed.

            arguments
                obj
                z (1, 1) {mustBeNumeric}
            end

            arguments (Repeating)
                varargin
            end

            [varargout{1:nargout}] = obj.mexHandle('fixZ', z, varargin{:});
        end

        function varargout = equalDOF(obj, rNodeTag, cNodeTag, dofs)
            % Create a multi-point constraint between nodes.
            %
            % Example
            % -------
            %     equalDOF(1, 2, [1 2 3 4 5 6]);
            %     equalDOF(1, 3, 1, 2, 3);
            %
            % Parameters
            % ----------
            % rNodeTag: int
            %   Integer tag identifying the retained, or primary node.
            % cNodeTag: int
            %   Integer tag identifying the constrained, or secondary node.
            % dofs: varargin(int)
            %   Nodal degrees-of-freedom that are constrained at the cNode to be the same as those at the rNode. Valid range is **from 1 through ndf**, the number of nodal degrees-of-freedom.
            %
            arguments
                obj
                rNodeTag (1, 1) {mustBeNumeric}
                cNodeTag (1, 1) {mustBeNumeric}
            end

            arguments (Repeating)
                dofs
            end

            [varargout{1:nargout}] = obj.mexHandle('equalDOF', rNodeTag, cNodeTag, dofs{:});
        end

        function varargout = equalDOF_Mixed(obj, rNodeTag, cNodeTag, numDOF, dofPairs)
            % Define a mixed equalDOF constraint between two nodes.
            %
            % Examples
            % --------
            %     equalDOF_Mixed(rNodeTag, cNodeTag, numDOF, [rdof1, cdof1, rdof2, cdof2, ...])
            %     equalDOF_Mixed(rNodeTag, cNodeTag, numDOF, rdof1, cdof1, rdof2, cdof2, ...)
            %
            % Parameters
            % ----------
            % rNodeTag : int
            %   Integer tag identifying the reference, or primary node.
            % cNodeTag : int
            %   Integer tag identifying the constrained, or secondary node.
            % numDOF : int
            %   Number of degrees-of-freedom to be constrained.
            % dofPairs : varargin(int)
            %   Nodal degrees-of-freedom that are constrained at the cNode to be the same as those at the rNode. Valid range is from **1 through ndf**, the number of nodal degrees-of-freedom. ``rcdofs = [rdof1, cdof1, rdof2, cdof2, ...]``
            arguments
                obj
                rNodeTag (1, 1) {mustBeNumeric}
                cNodeTag (1, 1) {mustBeNumeric}
                numDOF (1, 1) {mustBeNumeric}
            end

            arguments (Repeating)
                dofPairs
            end

            [varargout{1:nargout}] = obj.mexHandle('equalDOF_Mixed', rNodeTag, cNodeTag, numDOF, dofPairs{:});
        end

        function varargout = rigidDiaphragm(obj, perpDirn, rNodeTag, cNodeTags)
            % Define a rigid diaphragm constraint between a reference node and a set of constraint nodes.
            %
            % Example:
            % ---------
            %     rigidDiaphragm(1, 2, 3, 4, 5)
            %
            % Parameters
            % ----------
            % perpDirn: int
            %   The direction perpendicular to the rigid plane (i.e. direction 3 corresponds to the 1-2 plane).
            % rNodeTag: int
            %   Integer tag identifying the retained (primary) node.
            % cNodeTags: varargin(int)
            %   The integar tags identifying the constrained (secondary) nodes.
            arguments
                obj
                perpDirn (1, 1) {mustBeNumeric, mustBeMember(perpDirn, [1, 2, 3])}
                rNodeTag (1, 1) {mustBeNumeric}
            end

            arguments (Repeating)
                cNodeTags
            end

            [varargout{1:nargout}] = obj.mexHandle('rigidDiaphragm', perpDirn, rNodeTag, cNodeTags{:});
        end

        function varargout = rigidLink(obj, linkType, rNodeTag, cNodeTag)
            % Defines a rigid link between two nodes using the specified link type.
            %
            % Syntax:
            % -------
            %     rigidLink(linkType, rNodeTag, cNodeTag)
            %
            % Parameters
            % ----------
            % linkType: str
            %   String-based argument for rigid-link type:
            %
            %   - 'bar': only the translational degree-of-freedom will be constrained to be exactly the same as those at the master node
            %   - 'beam': both the translational and rotational degrees of freedom are constrained.
            %
            % rNodeTag: int
            %   Integer tag identifying the retained (primary) node.
            % cNodeTag: int
            %   Integer tag identifying the constrained (secondary) node.
            arguments
                obj
                linkType {mustBeTextScalar, mustBeMember(linkType, {'bar', 'beam'})}
                rNodeTag (1, 1) {mustBeNumeric}
                cNodeTag (1, 1) {mustBeNumeric}
            end

            [varargout{1:nargout}] = obj.mexHandle('rigidLink', linkType, rNodeTag, cNodeTag);
        end

        function varargout = timeSeries(obj, tsType, tsTag, tsArgs)
            % This command is used to construct a TimeSeries object which represents the relationship between the time in the domain, t, and the load factor applied to the loads, 𝜆, in the load pattern with which the TimeSeries object is associated, i.e. 𝜆 =𝐹(𝑡).
            %
            % See Also
            % --------
            %   [timeSeries commands](https://openseespydoc.readthedocs.io/en/latest/src/timeSeries.html)
            %
            % Parameters
            % ----------
            % tsType : str
            %   Type of time series to construct.
            % tsTag : int
            %   Tag identifying the time series.
            % tsArgs : varargin
            %   Additional arguments for the time series.
            arguments
                obj
                tsType {mustBeTextScalar, mustBeMember(tsType, {'Path', 'Series', 'Constant', 'Linear', 'Trig', 'Triangle', 'Rectangular', 'Pulse', 'Ramp', 'Sine', 'MPAcc', 'DiscretizedRandomProcess', 'SimulatedRandomProcess'})}
                tsTag (1, 1) {mustBeNumeric}
            end

            arguments (Repeating)
                tsArgs
            end

            [varargout{1:nargout}] = obj.mexHandle('timeSeries', tsType, tsTag, tsArgs{:});
        end

        function varargout = pattern(obj, patternType, patternTag, patternArgs)
            % Define an OpenSees load pattern. Each LoadPattern in OpenSees has a TimeSeries associated with it. In addition it may contain ElementLoads, NodalLoads and SinglePointConstraints. Some of these SinglePoint constraints may be associated with GroundMotions.
            %
            % See also
            % --------
            %     [pattern commands](https://openseespydoc.readthedocs.io/en/latest/src/pattern.html)
            %
            % Parameters
            % ----------
            % patternType : str
            %   Type of pattern to construct. Options are 'Plain', 'UniformExcitation', or 'MultipleSupport'.
            % patternTag : int
            %   Tag identifying the pattern.
            % patternArgs : varargin
            %   Additional arguments for the pattern.

            arguments
                obj
                patternType {mustBeTextScalar, mustBeMember(patternType, {'Plain', 'UniformExcitation', 'MultipleSupport'})}
                patternTag (1, 1) {mustBeNumeric}
            end

            arguments (Repeating)
                patternArgs
            end

            [varargout{1:nargout}] = obj.mexHandle('pattern', patternType, patternTag, patternArgs{:});
        end

        function varargout = load(obj, nodeTag, varargin)
            % This command is used to construct a NodalLoad object and add it to the enclosing LoadPattern.
            %
            % Syntax
            % ------
            %     load(nodeTag, -1, -1, -1);
            %     load(nodeTag, -1, -1, -1, '-pattern', patternTag);
            %
            % Note
            % ----
            %   The load values are reference loads values. It is the time series that provides the load factor. The load factor times the reference values is the load that is actually applied to the node.
            %
            % Parameters
            % ----------
            % nodeTag: int
            %   The tag of the node to which the load is applied.
            % loadValues: varargin{double}
            %   The load values to apply to the node.
            % varargin : cell
            %   Additional arguments to pass to OpenSees.
            %
            %   - if '-const' is specified, the load is applied as a constant load.
            %   - if {'-pattern', patternTag} is specified, the load is applied to this pattern.

            arguments
                obj
                nodeTag (1, 1) {mustBeNumeric}
            end

            arguments (Repeating)
                varargin
            end

            [varargout{1:nargout}] = obj.mexHandle('load', nodeTag, varargin{:});
        end

        function varargout = eleLoad(obj, varargin)
            % The eleLoad command is used to construct an ElementalLoad object and add it to the enclosing LoadPattern.
            %
            % Parameters
            % ----------
            % eleTags: varargin{int}
            %   Tag of the element to which the load is applied. Pairs style ('-ele', eleTag1, eleTag2, ...) is necessary.
            % eleRange: varargin{int}
            %   Range of element tags to which the load is applied. Pairs style ('-range', eleTag1, eleTag2) is necessary.
            % loadType: varargin{str}
            %   Type of load to apply. Pairs style ('-type', loadType) is necessary.
            %
            %   - **beamUniform**: Uniform beam load. Pairs style ``('-type', '-beamUniform', Wy, <Wz>, Wx=0.0)`` is necessary. Wy is the load along the local y-axis, Wz is the load along the local z-axis (required only for 3D), and Wx is the load along the local x-axis.
            %   - **beamPoint**: Point load at a specific fiber location. Pairs style ``('-type', '-beamPoint', Py, <Pz>, xL, Px=0.0)`` is necessary. Py is the load along the local y-axis, Pz is the load along the local z-axis (required only for 3D), xL is the fiber location along the local x-axis (0-1), and Px is the load along the local x-axis.
            %   - **surfaceLoad**: Surface load. Pairs style ``('-type', '-surfaceLoad')`` is necessary. You need define the *SurfaceLoad* or *TriSurfaceLoad* element in advance, and pass the element tag to this command. See also [How to Apply Surface Loads](https://openseesdigital.com/2025/07/12/how-to-apply-surface-loads/)
            %   - **selfWeight**: Self-weight load implemented for all continuum elements. Pairs style ``('-type', '-selfWeight', xf, yf, <zf>)`` is necessary, xf, yf, zf are the body force components. See also [Do It Your Self-Weight](https://openseesdigital.com/2023/11/05/do-it-your-self-weight/) and [Element Self-Weight](https://openseesdigital.com/2022/11/02/element-self-weight/). The element implementations of the ``addLoad()`` method handle the self-weight calculations–no script pre-processing necessary.
            %   - **beamThermal**: Thermal load. Pairs style ``('-type', '-beamThermal', T1, y1, T2, y2, ..., T9, y9)`` is necessary. Each point (T1, y1) define a temperature and location. This command may accept 2,5 or 9 temperature points.
            %   - **shellThermal**: Thermal load for shell elements. Pairs style ``('-type', '-shellThermal', T1, y1, T2, y2,)`` is necessary. Each point (T1, y1) define a temperature and location. This command only accept 2 temperature points in the current version.
            %
            % Note
            % -----
            %   1. The load values are reference load values, it is the time series that provides the load factor. The load factor times the reference values is the load that is actually applied to the element.
            %   2. At the moment, eleLoads do not work with 3D beam-column elements if Corotational geometric transformation is used.
            %
            [varargout{1:nargout}] = obj.mexHandle('eleLoad', varargin{:});
        end

        function varargout = loadConst(obj, varargin)
            % Apply a load that does not change with time.
            %
            % Parameters
            % ----------
            % varargin : varargin{any}
            %   Optional parameters for loadConst command.
            %   If ``'-time', value`` is provided, the time reset to value.
            %
            [varargout{1:nargout}] = obj.mexHandle('loadConst', varargin{:});
        end

        function varargout = sp(obj, nodeTag, dof, dofValue, varargin)
            % Apply a single-point load to a node.
            %
            % Note
            % -----
            %   The dofValue is a reference value, it is the time series that provides the load factor. The load factor times the reference value is the constraint that is actually applied to the node.
            %
            % Parameters
            % ----------
            % nodeTag : int
            %   The tag of the node to which the load is applied.
            % dof : int
            %   The degree of freedom to which the load is applied (1 through ndf).
            % dofValue : numeric
            %   The reference value of the load.
            % varargin : cell
            %   Additional arguments to pass to OpenSees.
            %
            %   - if '-const' is specified, the load is applied as a constant load.
            %   - if '-subtractInit' is specified, allow user to ignore init disp values at the node.
            %   - if {'-pattern', patternTag} is specified, the load is applied to this pattern.

            arguments
                obj
                nodeTag (1,1) {mustBeNumeric}
                dof (1,1) {mustBeNumeric}
                dofValue (1,1) {mustBeNumeric}
            end

            arguments (Repeating)
                varargin
            end
            [varargout{1:nargout}] = obj.mexHandle('sp', nodeTag, dof, dofValue, varargin{:});
        end

        function varargout = groundMotion(obj, gmTag, gmType, varargin)
            % This command is used to construct a GroundMotion object.
            %
            % Syntax
            % ------
            %     groundMotion(gmTag, 'Plain', '-accel', accelSeriesTag, '-int', 'Trapezoidal', '-fact', factor)
            %     groundMotion(gmTag, 'Interpolated', gmTag1, gmTag2, ..., '-fact', factor1, factor2, ...)
            %
            % Parameters
            % ----------
            % gmTag : int
            %   Tag identifying the ground motion.
            % gmType : str
            %   Type of ground motion. Must be one of {'Plain', 'Interpolated'}.
            %
            %   - 'Plain' : This command is used to construct a plain GroundMotion object. Each GroundMotion object is associated with a number of TimeSeries objects, which define the acceleration, velocity and displacement records for that ground motion.
            %   - 'Interpolated' : Constructs an interpolated GroundMotion object with acceleration, velocity and displacement records defined by the provided TimeSeries objects.
            arguments
                obj
                gmTag (1,1)  {mustBeNumeric}
                gmType {mustBeTextScalar, mustBeMember(gmType, {'Plain', 'Interpolated'})}
            end

            arguments (Repeating)
                varargin
            end

            [varargout{1:nargout}] = obj.mexHandle('groundMotion', gmTag, gmType, varargin{:});
        end

        function varargout = imposedMotion(obj, nodeTag, dof, gmTag)
            % This command is used to impose a ground motion on a node.
            %
            % Syntax
            % ------
            %     ops.imposedMotion(nodeTag, dof, gmTag)
            %
            % Parameters
            % ----------
            % nodeTag : int
            %   The tag of the node to which the ground motion is imposed.
            % dof : int
            %   The degree of freedom of the node to which the ground motion is imposed. Valid range is from 1 through ndf at node.
            % gmTag : int
            %   The tag of the ground motion to impose.

            arguments
                obj
                nodeTag (1,1) {mustBeNumeric}
                dof (1,1) {mustBeNumeric}
                gmTag (1,1) {mustBeNumeric}
            end

            [varargout{1:nargout}] = obj.mexHandle('imposedMotion', nodeTag, dof, gmTag);
        end

        function varargout = mass(obj, nodeTag, massValues)
            % This command is used to set the mass at a node, replacing any previously defined mass at the node.
            %
            % Syntax
            % ------
            % mass(obj, nodeTag, massValues)
            %
            % Parameters
            % ----------
            % nodeTag : int
            %   The tag of the node to which the mass is applied.
            % massValues : double
            %   The mass values to apply to the node.
            arguments
                obj
                nodeTag (1,1) {mustBeNumeric}
            end

            arguments (Repeating)
                massValues
            end

            [varargout{1:nargout}] = obj.mexHandle('mass', nodeTag, massValues{:});
        end

        function varargout = region(obj, regTag, varargin)
            % The region command is used to label a group of nodes and elements. This command is also used to assign rayleigh damping parameters to the nodes and elements in this region. The region is specified by either elements or nodes, not both. If elements are defined, the region includes these elements and the all connected nodes, unless the ``-eleOnly`` option is used in which case only elements are included. If nodes are specified, the region includes these nodes and all elements of which all nodes are prescribed to be in the region, unless the ``-nodeOnly`` option is used in which case only the nodes are included.
            %
            % See also [ region command](https://openseespydoc.readthedocs.io/en/latest/src/region.html)
            %
            % Parameters
            % ----------
            % regTag: int
            %   Unique integer tag for the region.
            % eles: int, optional
            %   Tags of selected elements in domain to be included in region (optional). Style ``'-ele', ele1, ele2, ...`` or ``'-eleOnly', ele1, ele2, ...`` is necessary.
            % nodes: int, optional
            %   Tags of selected nodes in domain to be included in region (optional). Style ``'-node', node1, node2, ...`` or ``'-nodeOnly', node1, node2, ...`` is necessary.
            % eleRange: int, optional
            %   Range of element tags to include in region (optional). Style ``'-eleRange', startEle, endEle`` or ``'-eleOnlyRange', startEle, endEle`` is necessary.
            % nodeRange: int, optional
            %   Range of node tags to include in region (optional). Style ``'-nodeRange', startNode, endNode`` or ``'-nodeOnlyRange', startNode, endNode`` is necessary.
            % Rayleigh: float, optional
            %   Rayleigh damping factors (optional). Style ``'-rayleigh', alphaM, betaK, betaKinit, betaKcomm`` is necessary.
            %
            % Note
            % ----
            %   The user cannot prescribe the region by BOTH elements and nodes.
            arguments
                obj
                regTag (1,1) {mustBeNumeric}
            end
            arguments (Repeating)
                varargin
            end
            [varargout{1:nargout}] = obj.mexHandle('region', regTag, varargin{:});
        end

        function varargout = rayleigh(obj, alphaM, betaK, betaKinit, betaKcomm)
            % This command is used to assign damping to all previously-defined elements and nodes. When using rayleigh damping in OpenSees, the damping matrix for an element or node, D is specified as a combination of stiffness and mass-proportional damping matrices:
            %
            % $$
            % 𝐷=\alpha_𝑀∗𝑀+\beta_𝐾∗𝐾_{curr}+\beta_{K_{init}}*K_{init}+\beta_{K_{commit}}*K_{commit}
            % $$
            %
            % See also
            % --------
            %   - [Damping blog by Portwood Digital](https://portwooddigital.com/tag/damping/)
            %
            % Parameters
            % ----------
            % alphaM : (1,1) {mustBeNumeric}
            %   Mass proportional damping factor for the mass matrix.
            % betaK : (1,1) {mustBeNumeric}
            %   Stiffness proportional damping factor for the current stiffness matrix.
            % betaKinit : (1,1) {mustBeNumeric}
            %   Stiffness proportional damping factor for the initial stiffness matrix.
            % betaKcomm : (1,1) {mustBeNumeric}
            %   Stiffness proportional damping factor for the committed stiffness matrix.
            arguments
                obj
                alphaM (1,1) {mustBeNumeric}
                betaK (1,1) {mustBeNumeric}
                betaKinit (1,1) {mustBeNumeric}
                betaKcomm (1,1) {mustBeNumeric}
            end
            [varargout{1:nargout}] = obj.mexHandle('rayleigh', alphaM, betaK, betaKinit, betaKcomm);
        end

        function varargout = modalDamping(obj, factors)
            % The following is used to assign the modal damping model to the model. ``eigen`` command needs to be called first.
            %
            % See also
            % --------
            %   - [Modal Damping Command](https://opensees.github.io/OpenSeesDocumentation/user/manual/model/damping/modalDamping.html)
            %   - [Be Careful with Modal Damping](https://openseesdigital.com/2019/09/12/be-careful-with-modal-damping/)
            %   - [Gimme All Your Modal Damping](https://openseesdigital.com/2022/04/03/gimme-all-your-modal-damping/)
            %
            % Parameters
            % ----------
            % factors : varargin{mustBeNumeric}
            %   Modal damping factors, its number must equals 1 or the length of eigen modes.
            %
            % Warning
            % -------
            %   Modal damping implementation is as in Perform3D. The tangent matrix is not modified for damping terms as this would result in a full matrix. Instead just the right hand side of the equation, i.e. the resisting force vector is modified. As a consequence, iteration is required at each step to obtain a converged solution, i.e. no Linear solution algorithm or explicit time stepping algorithms will work correctly with modal damping!
            arguments
                obj
            end
            arguments (Repeating)
                factors
            end
            [varargout{1:nargout}] = obj.mexHandle('modalDamping', factors{:});
        end

        function varargout = damping(obj, dampingType, dampingTag, dampingArgs)
            % The following is used to assign the damping model to a specific element. The user should append the parameters of ``'-damp', dampingTag`` to the end of the element definition.
            %
            % See also
            % --------
            %   - [Elemental Damping Command](https://opensees.github.io/OpenSeesDocumentation/user/manual/model/damping/elementalDamping.html)
            %
            % Parameters
            % ----------
            % dampingType: char | string
            %     The type of damping model to use. Must be one of ``'Uniform'``, ``'SecStif'``, ``'URD'``, or ``'URDbeta'``.
            % dampingTag: int
            %     The tag of the damping model to use.
            % dampingArgs: varargin
            %     Additional arguments to pass to the damping model.
            arguments
                obj
                dampingType {mustBeTextScalar, mustBeMember(dampingType, {'Uniform', 'SecStif', 'URD', 'URDbeta'})}
                dampingTag (1, 1) {mustBeNumeric}
            end
            arguments (Repeating)
                dampingArgs
            end
            [varargout{1:nargout}] = obj.mexHandle('damping', dampingType, dampingTag, dampingArgs{:});
        end

        function varargout = block2D(obj, numX, numY, startNode, startEle, eleType, varargin)
            % Create mesh of quadrilateral elements.
            %
            % Parameters
            % ----------
            % numX : int
            %   Number of elements in the x-direction
            % numY : int
            %   Number of elements in the y-direction
            % startNode : int
            %   Starting node tag
            % startEle : int
            %   Starting element tag
            % eleType : str
            %   Element type ('quad', 'shell', 'bbarQuad', 'enhancedQuad', or 'SSPquad')
            % eleArgs: varargin
            %   Additional element properties
            % crds: varargin
            %   coordinates of the block elements with the format:

            arguments
                obj
                numX (1,1) {mustBeNumeric}
                numY (1,1) {mustBeNumeric}
                startNode (1,1) {mustBeNumeric}
                startEle (1,1) {mustBeNumeric}
                eleType {mustBeTextScalar, mustBeMember(eleType, {'stdQuad', 'quad', 'ShellMITC4', 'shellMITC4', 'shell', 'Shell', 'ShellNLDKGQ', 'shellNLDKGQ', 'ShellDKGQ', 'shellDKGQ', 'bbarQuad', 'mixedQuad', 'enhancedQuad', 'SSPquad', 'SSPQuad'})}
            end
            arguments (Repeating)
                varargin
            end

            [varargout{1:nargout}] = obj.mexHandle('block2D', numX, numY, startNode, startEle, eleType, varargin{:});
        end

        function varargout = block3D(obj, numX, numY, numZ, startNode, startEle, eleType, varargin)
            % Create mesh of cubic elements.
            %
            % Parameters
            % ----------
            % numX : int
            %   Number of elements in the x-direction.
            % numY : int
            %   Number of elements in the y-direction.
            % numZ : int
            %   Number of elements in the z-direction.
            % startNode : int
            %   Starting node tag.
            % startEle : int
            %   Starting element tag.
            % eleType : str
            %   Element type ('stdBrick', 'bbarBrick', 'SSPbrick')
            % eleArgs: varargin
            %   Additional element properties
            % crds: varargin
            %   coordinates of the block elements with the format:
            %
            arguments
                obj
                numX (1,1) {mustBeNumeric}
                numY (1,1) {mustBeNumeric}
                numZ (1,1) {mustBeNumeric}
                startNode (1,1) {mustBeNumeric}
                startEle (1,1) {mustBeNumeric}
                eleType {mustBeTextScalar, mustBeMember(eleType, {'stdBrick', 'bbarBrick', 'SSPbrick', 'SSPBrick'})}
            end
            arguments (Repeating)
                varargin
            end

            [varargout{1:nargout}] = obj.mexHandle('block3D', numX, numY, numZ, startNode, startEle, eleType, varargin{:});
        end

        function varargout = beamIntegration(obj, integType, tag, varargin)
            % Define a beam integration rule. A wide range of numerical integration options are available in OpenSees to represent distributed plasticity or non-prismatic section details in Beam-Column Elements, i.e., across the entire element domain [0, L].
            %
            % See also
            % ---------
            %   - [beamIntegration commands](https://openseespydoc.readthedocs.io/en/latest/src/beamIntegration.html)
            %
            % Parameters
            % ----------
            % integType : str
            %   The integration type.
            % tag : int
            %   The integration rule tag.
            % varargin : cell
            %   Additional integration rule parameters. Every integration type requires specific parameters.
            arguments
                obj
                integType {mustBeTextScalar, mustBeMember(integType, ...
                           {'Lobatto', 'Legendre', 'Chebyshev', 'NewtonCotes', 'Radau', ...
                            'Trapezoidal', 'CompositeSimpson', 'Simpson', 'UserDefined', ...
                            'FixedLocation', 'LowOrder', 'MidDistance', 'RegularizedHinge', ...
                            'UserHinge', 'HingeMidpoint', 'HingeRadau', 'HingeRadauTwo', ...
                            'HingeEndpoint', 'ConcentratedPlasticity', 'ConcentratedCurvature'})}
                tag (1,1) {mustBeNumeric}
            end
            arguments (Repeating)
                varargin
            end
            [varargout{1:nargout}] = obj.mexHandle('beamIntegration', integType, tag, varargin{:});
        end

        function varargout = uniaxialMaterial(obj, matType, matTag, matArgs)
            % This command is used to construct a UniaxialMaterial object which represents uniaxial stress-strain (or force-deformation) relationships.
            %
            % See also
            % ---------
            %   - [uniaxialMaterial commands (Python)](https://openseespydoc.readthedocs.io/en/latest/src/uniaxialMaterial.html)
            %   - [uniaxialMaterial commands (Tcl)](https://opensees.berkeley.edu/wiki/index.php/UniaxialMaterial_Command)
            %
            % Parameters
            % ----------
            % matType : str
            %   The material type.
            % tag : int
            %   The material tag.
            % matArgs : cell
            %   Additional material parameters. Every material type requires specific parameters.

            arguments
                obj
                matType {mustBeTextScalar}
                matTag (1,1) {mustBeNumeric}
            end

            arguments (Repeating)
                matArgs
            end

            [varargout{1:nargout}] = obj.mexHandle('uniaxialMaterial', matType, matTag, matArgs{:});
        end

        function varargout = nDMaterial(obj, matType, matTag, matArgs)
            % This command is used to construct an NDMaterial object which represents the stress-strain relationship at the gauss-point of a continuum element.
            %
            % See also
            % --------
            %   - [nDMaterial commands (Python)](https://openseespydoc.readthedocs.io/en/latest/src/ndMaterial.html)
            %   - [nDMaterial commands (Tcl)](https://opensees.berkeley.edu/wiki/index.php?title=NDMaterial_Command)
            %
            % Parameters
            % ----------
            % matType : str
            %   The material type.
            % matTag : int
            %   The material tag.
            % matArgs : cell
            %   Additional material parameters. Every material type requires specific parameters.

            arguments
                obj
                matType {mustBeTextScalar}
                matTag (1,1) {mustBeNumeric}
            end

            arguments (Repeating)
                matArgs
            end

            [varargout{1:nargout}] = obj.mexHandle('nDMaterial', matType, matTag, matArgs{:});
        end

        function varargout = frictionModel(obj, frnType, frnTag, frnArgs)
            % The frictionModel command is used to construct a friction model object, which specifies the behavior of the coefficient of friction in terms of the absolute sliding velocity and the pressure on the contact area. The command has at least one argument, the friction model type.
            %
            % See also
            % --------
            %   - [frictionModel commands](https://openseespydoc.readthedocs.io/en/latest/src/frictionModel.html)
            %
            % Parameters
            % ----------
            % frnType : str
            %   The friction type. Must be one of the following: 'Coulomb', 'VelDependent', 'VelPressureDep', 'VelDepMultiLinear', 'VelNormalFrcDep'.
            % frnTag : int
            %   The friction tag.
            % frnArgs : varargin
            %   Additional arguments for the friction model. Every frnType requires different arguments.

            arguments
                obj
                frnType {mustBeTextScalar, mustBeMember(frnType, {'Coulomb', 'VelDependent', 'VelPressureDep', 'VelDepMultiLinear', 'VelNormalFrcDep'})}
                frnTag (1,1) {mustBeNumeric}
            end

            arguments (Repeating)
                frnArgs
            end

            [varargout{1:nargout}] = obj.mexHandle('frictionModel', frnType, frnTag, frnArgs{:});
        end

        function varargout = geomTransf(obj, transfType, transfTag, transfArgs)
            % The geometric-transformation command is used to construct a coordinate-transformation (CrdTransf) object, which transforms beam element stiffness and resisting force from the basic system to the global-coordinate system. The command has at least one argument, the transformation type.
            %
            % See also
            % --------
            %   - [geomTransf commands (Python)](https://openseespydoc.readthedocs.io/en/latest/src/geomTransf.html)
            %   - [geomTransf commands (Tcl)](https://opensees.berkeley.edu/wiki/index.php?title=Geometric_Transformation_Command)
            %
            % Parameters
            % ----------
            % transfType : str
            %   The transformation type.
            % transfTag : int
            %   The transformation tag.
            % transfArgs : varargin
            %   Additional arguments for the transformation.
            arguments
                obj
                transfType {mustBeTextScalar, mustBeMember(transfType, {'Linear', 'PDelta', 'Corotational'})}
                transfTag (1,1) {mustBeNumeric}
            end

            arguments (Repeating)
                transfArgs
            end

            [varargout{1:nargout}] = obj.mexHandle('geomTransf', transfType, transfTag, transfArgs{:});
        end

        function varargout = remove(obj, objectType, args)
            % This command is used to remove an object from the model.
            %
            % Parameters
            % ----------
            % objectType: str
            %   The type of object to remove. Must be one of the following:
            %   ``node``, ``element``,  ``pattern``, ``parameter``, ``recorders``, ``recorder``, ``timeSeries``, ``SPconstraint``,  ``MPconstraint``.
            % args: varargin
            %   Additional arguments for the object to remove.
            %
            %   - ``node``: removes a node from the model, ``remove('node', nodeTag)``.
            %   - ``element``: removes an element from the model, ``remove('element', eleTag)``.
            %   - ``pattern``: removes a load pattern from the model, ``remove('pattern', patternTag)``.
            %   - ``parameter``: removes a parameter from the model, ``remove('parameter', paramTag)``.
            %   - ``recorders``: removes all recorders from the model, ``remove('recorders')``.
            %   - ``recorder``: removes a specific recorder from the model, ``remove('recorder', recorderTag)``.
            %   - ``timeSeries``: removes a time series from the model, ``remove('timeSeries', timeSeriesTag)``.
            %   - ``SPconstraint``: removes a single-point constraint from the model, ``remove('SPconstraint', spTag)`` or ``remove('SPconstraint', nodeTag, dofTag, <patternTag?>)``.
            %   - ``MPconstraint``: removes a multi-point constraint from the model, ``remove('MPconstraint', cNodeTag)`` or ``remove('MPconstraint', '-tag', mpTag)``.
            %

            arguments
                obj
                objectType {mustBeTextScalar, mustBeMember(objectType, {'node', 'element', 'ele', 'loadPattern', 'pattern', 'parameter', 'recorders', 'recorder', 'timeSeries', 'SPconstraint', 'sp', 'MPconstraint', 'mp'})}
            end
            arguments (Repeating)
                args
            end
            [varargout{1:nargout}] = obj.mexHandle('remove', objectType, args{:});
        end

        function varargout = setCreep(obj, value)
            % Set the creep parameter for the model.
            %
            % Parameters
            % ----------
            % value : double
            %     The creep parameter value to set.

            arguments
                obj
                value (1,1) {mustBeNumeric}
            end
            [varargout{1:nargout}] = obj.mexHandle('setCreep', value);
        end

    end

    % Analysis commands
    methods (Access = public)
        function varargout = constraints(obj, constraintType, constraintArgs)
            % This command is used to construct the ConstraintHandler object. The ConstraintHandler object determines how the constraint equations are enforced in the analysis. Constraint equations enforce a specified value for a DOF, or a relationship between DOFs.
            %
            % See also
            % --------
            %   - [constraints commands](https://openseespydoc.readthedocs.io/en/latest/src/constraints.html)
            %
            % Parameters
            % ----------
            % constraintType : str
            %     The type of constraint handler to construct. Must be one of {'Plain', 'Penalty', 'Lagrange', 'Transformation', 'Auto'}.
            % constraintArgs : varargin
            %     Additional arguments for the constraint handler.

            arguments
                obj
                constraintType {mustBeTextScalar, mustBeMember(constraintType, {'Plain', 'Penalty', 'Lagrange', 'Transformation', 'Auto'})}
            end
            arguments (Repeating)
                constraintArgs
            end

            [varargout{1:nargout}] = obj.mexHandle('constraints', constraintType, constraintArgs{:});
        end

        function varargout = numberer(obj, numbererType, numbererArgs)
            % This command is used to construct the DOF_Numberer object. The DOF_Numberer object determines the mapping between equation numbers and degrees-of-freedom – how degrees-of-freedom are numbered.
            %
            % See also
            % --------
            %   - [numberer commands (Python)](https://openseespydoc.readthedocs.io/en/latest/src/numberer.html)
            %   - [analysis commands (Tcl)](https://opensees.berkeley.edu/wiki/index.php?title=Analysis_Commands)
            %
            % Parameters
            % ----------
            % numbererType : str
            %     The type of numberer to construct. Must be one of {'Plain', 'RCM', 'AMD', 'ParallelPlain', 'ParallelRCM'}.
            % numbererArgs : varargin
            %     Additional arguments for the numberer.

            arguments
                obj
                numbererType {mustBeTextScalar, mustBeMember(numbererType, {'Plain', 'RCM', 'AMD', 'ParallelPlain', 'ParallelRCM'})}
            end
            arguments (Repeating)
                numbererArgs
            end

            [varargout{1:nargout}] = obj.mexHandle('numberer', numbererType, numbererArgs{:});
        end

        function varargout = system(obj, systemType, systemArgs)
            % This command is used to construct the LinearSOE and LinearSolver objects to store and solve the system of equations in the analysis.
            %
            % See also
            % --------
            %   - [system commands (Python)](https://openseespydoc.readthedocs.io/en/latest/src/system.html)
            %   - [system commands (Tcl)](https://opensees.berkeley.edu/wiki/index.php?title=System_Command)
            %
            % Parameters
            % ----------
            % systemType : str
            %   The system type. One of {'BandGen', 'BandSPD', 'Diagonal', 'ProfileSPD', 'SuperLU', 'UmfPack', 'FullGeneral', 'SparseSYM'}
            % systemArgs : varargin
            %   Additional arguments for the system.
            arguments
                obj
                systemType {mustBeTextScalar, mustBeMember(systemType, {'BandGeneral', 'BandGEN', 'BandGen', 'BandSPD', 'Diagonal','MPIDiagonal', 'SProfileSPD', ...
                 'ProfileSPD', 'ParallelProfileSPD', 'PFEM', 'SparseGeneral', 'SuperLU', 'SparseGEN', ...
                 'SparseSPD', 'SparseSYM', 'UmfPack', 'Umfpack', 'FullGeneral', 'Petsc', 'Mumps', 'Itpack'})}
            end
            arguments (Repeating)
                systemArgs
            end

            [varargout{1:nargout}] = obj.mexHandle('system', systemType, systemArgs{:});
        end

        function varargout = test(obj, testType, testArgs)
            % This command is used to construct the LinearSOE and LinearSolver objects to store and solve the test of equations in the analysis.
            %
            % See also
            % --------
            %   - [test commands (Python)](https://openseespydoc.readthedocs.io/en/latest/src/test.html)
            %   - [test commands (Tcl)](https://opensees.berkeley.edu/wiki/index.php?title=Test_Command)
            %
            % Parameters
            % ----------
            % testType : str
            %   The test type.
            % testArgs : varargin
            %   Additional arguments for the test.
            arguments
                obj
                testType {mustBeTextScalar, mustBeMember(testType, {'NormUnbalance', ...
                                  'NormDispIncr', 'EnergyIncr', 'NormDispAndUnbalance', ...
                                  'NormDispOrUnbalance', 'PFEM', 'FixedNumIter', ...
                                  'RelativeNormUnbalance', 'RelativeNormDispIncr', ...
                                  'RelativeEnergyIncr', 'RelativeTotalNormDispIncr'})}
            end
            arguments (Repeating)
                testArgs
            end

            [varargout{1:nargout}] = obj.mexHandle('test', testType, testArgs{:});
        end

        function varargout = algorithm(obj, algoType, algoArgs)
            % Set the algorithm for the analysis.
            %
            % See also
            % ---------
            %   - [algorithm commands (OpenSeesPy)](https://openseespydoc.readthedocs.io/en/latest/src/algorithm.html#)
            %   - [algorithm commands (Tcl)](https://opensees.berkeley.edu/wiki/index.php?title=Algorithm_Command)
            %
            % Parameters
            % ----------
            % algoType : char | string
            %   Algorithm type.
            % algoArgs : varargin
            %   Additional arguments for the algorithm.
            arguments
                obj
                algoType {mustBeTextScalar, mustBeMember(algoType, ...
                         {'Linear', 'Newton', 'ModifiedNewton', ...
                          'KrylovNewton', 'RaphsonNewton', 'MillerNewton', ...
                          'SecantNewton', 'PeriodicNewton', 'ExpressNewton', ...
                          'Broyden', 'BFGS', 'NewtonLineSearch'})}
            end
            arguments (Repeating)
                algoArgs
            end

            [varargout{1:nargout}] = obj.mexHandle('algorithm', algoType, algoArgs{:});
        end

        function varargout = integrator(obj, intType, intArgs)
            % This command is used to construct the Integrator object. The Integrator object determines the meaning of the terms in the system of equation object Ax=B.
            % The Integrator object is used for the following:
            %
            % - determine the predictive step for time t+dt
            % - specify the tangent matrix and residual vector at any iteration
            % - determine the corrective step based on the displacement increment dU
            %
            % See also
            % --------
            %   - [integrator commands (OpenSeesPy)](https://openseespydoc.readthedocs.io/en/latest/src/integrator.html)
            %   - [integrator commands (Tcl)](https://opensees.berkeley.edu/wiki/index.php?title=Integrator_Command)
            %
            % Parameters
            % ----------
            % intType : char | string
            %   Integrator type.
            % intArgs : varargin
            %   Additional arguments passed directly to OpenSees.
            arguments
                obj
                intType {mustBeTextScalar, mustBeMember(intType, ...
                        {... % Static integrators
                         'LoadControl', 'DisplacementControl', ...
                         'ParallelDisplacementControl', ...
                         'ArcLength', 'ArcLength1', 'HSConstraint', ...
                         'MinUnbalDispNorm', 'HarmonicSteadyState', 'HarmonicSS', ...
                         ... % Transient integrators
                         'Newmark', 'GimmeMCK', 'ZZTop', ...
                         'TRBDF2', 'Bathe', 'TRBDF3', 'Bathe3', ...
                         'Houbolt', 'BackwardEuler', 'PFEM', ...
                         'NewmarkExplicit', 'NewmarkHSIncrLimit', ...
                         'NewmarkHSIncrReduct', 'NewmarkHSFixedNumIter', ...
                         'HHT', 'HHT_TP', 'HHTGeneralized', 'HHTGeneralized_TP', ...
                         'HHTExplicit', 'HHTExplicit_TP', ...
                         'HHTGeneralizedExplicit', 'HHTGeneralizedExplicit_TP', ...
                         'HHTHSIncrLimit', 'HHTHSIncrLimit_TP', ...
                         'HHTHSIncrReduct', 'HHTHSIncrReduct_TP', ...
                         'HHTHSFixedNumIter', 'HHTHSFixedNumIter_TP', ...
                         'GeneralizedAlpha', ...
                         'KRAlphaExplicit', 'KRAlphaExplicit_TP', ...
                         'AlphaOS', 'AlphaOS_TP', ...
                         'AlphaOSGeneralized', 'AlphaOSGeneralized_TP', ...
                         'Collocation', 'CollocationHSIncrReduct', ...
                         'CollocationHSIncrLimit', 'CollocationHSFixedNumIter', ...
                         'Newmark1', 'WilsonTheta', ...
                         'CentralDifference', 'CentralDifferenceAlternative', ...
                         'CentralDifferenceNoDamping', 'ExplicitDifference'})}
            end
            arguments (Repeating)
                intArgs
            end

            [varargout{1:nargout}] = obj.mexHandle('integrator', intType, intArgs{:});
        end

        function varargout = analysis(obj, analysisType, analysisArgs)
            % Set the analysis type.
            %
            % See also
            % --------
            %   - [analysis commands (OpenSeesPy)](https://openseespydoc.readthedocs.io/en/latest/src/analysis.html)
            %   - [analysis commands (Tcl)](https://opensees.berkeley.edu/wiki/index.php?title=Analysis_Command)
            %
            % Parameters
            % ----------
            % analysisType : char | string
            %   Analysis type. One of:
            %
            %   - 'Static'
            %   - 'Transient'
            %   - 'PFEM'
            %   - `'VariableTransient'`
            %
            %   analysisArgs : varargin
            %       Optional arguments, e.g. '-noWarnings'.
            arguments
                obj
                analysisType {mustBeTextScalar, mustBeMember(analysisType, ...
                             {'Static', ...
                              'Transient', ...
                              'PFEM', ...
                              'VariableTimeStepTransient', ...
                              'TransientWithVariableTimeStep', ...
                              'VariableTransient'})}
            end
            arguments (Repeating)
                analysisArgs
            end

            [varargout{1:nargout}] = obj.mexHandle('analysis', analysisType, analysisArgs{:});
        end

        function varargout = analyze(obj, numIncr, analyzeArgs)
            % Run the analysis.
            %
            % See also
            % --------
            %   - [analyze commands (OpenSeesPy)](https://openseespydoc.readthedocs.io/en/latest/src/analyze.html)
            %   - [analyze commands (Tcl)](https://opensees.berkeley.edu/wiki/index.php?title=Analyze_Command)
            %
            % Syntax
            % ------
            %     % Static analysis:
            %     ops.analyze(numIncr)
            %     ops.analyze(numIncr, '-noFlush')
            %
            %     % Transient analysis:
            %     ops.analyze(numIncr, dt)
            %     ops.analyze(numIncr, dt, '-noFlush')
            %
            %     % Variable transient analysis:
            %     ops.analyze(numIncr, dt, dtMin, dtMax, Jd)
            %     ops.analyze(numIncr, dt, dtMin, dtMax, Jd, '-noFlush')
            %
            %     % PFEM analysis:
            %     ops.analyze()
            %     ops.analyze('-noFlush')
            %
            % Parameters
            % ----------
            % numIncr : int
            %   Number of increments (static/transient).
            % dt : double
            %   Time step (transient).
            % dtMin : double
            %   Minimum time step (variable transient).
            % dtMax : double
            %   Maximum time step (variable transient).
            % Jd : int
            %   Number of iterations per step (variable transient).
            % '-noFlush' : char | string (optional)
            %   Suppress recorder flush after each step.
            arguments
                obj
                numIncr (1,1) {mustBeNumeric} = 1
            end
            arguments (Repeating)
                analyzeArgs
            end

            [varargout{1:nargout}] = obj.mexHandle('analyze', numIncr, analyzeArgs{:});
        end

        function varargout = eigen(obj, varargin)
            % Run an eigenvalue analysis.
            %
            % Syntax
            % ------
            %   eigen(10)
            %   eigen('-genBandArpack', 10)
            %
            % See also
            % --------
            %   - [eigen commands (OpenSeesPy)](https://openseespydoc.readthedocs.io/en/latest/src/eigen.html)
            %   - [eigen commands (Tcl)](https://opensees.berkeley.edu/wiki/index.php?title=Eigen_Command)
            %
            % Parameters
            % ----------
            % solver : char | string
            %   Solver type (default: '-genBandArpack'). One of:
            %       '-genBandArpack', '-fullGenLapack', '-symmBandLapack', '-symmGenLapack', '-standard', '-findLargest'.
            % numModes : int
            %   Number of eigenvalues to compute.
            [varargout{1:nargout}] = obj.mexHandle('eigen', varargin{:});
        end

        function varargout = modalProperties(obj, varargin)
            % This command is used to compute the modal properties of a model after an eigen command.

            % See also
            % --------
            %   - [modalProperties commands (OpenSeesPy)](https://openseespydoc.readthedocs.io/en/latest/src/modalProperties.html)
            %   - [modalProperties commands (Tcl)](https://opensees.github.io/OpenSeesDocumentation/user/manual/analysis/modalProperties.html)
            %
            [varargout{1:nargout}] = obj.mexHandle('modalProperties', varargin{:});
        end

        function varargout = responseSpectrumAnalysis(obj, varargin)
            % This command is used to perform a response spectrum analysis on a model.
            %
            % See also
            % --------
            %   - [responseSpectrumAnalysis commands (OpenSeesPy)](https://openseespydoc.readthedocs.io/en/latest/src/responseSpectrumAnalysis.html)
            %   - [responseSpectrumAnalysis commands (Tcl)](https://opensees.github.io/OpenSeesDocumentation/user/manual/analysis/responseSpectrumAnalysis.html)
            %
            [varargout{1:nargout}] = obj.mexHandle('responseSpectrumAnalysis', varargin{:});
        end

        function varargout = wipeAnalysis(obj)
            % This command is used to destroy all components of the Analysis object, i.e. any objects created with system, numberer, constraints, integrator, algorithm, and analysis commands.
            %
            [varargout{1:nargout}] = obj.mexHandle('wipeAnalysis');
        end

        function varargout = record(obj)
            % This command is used to cause all the recorders to do a record on the current state of the model.
            %
            % Note
            % ----
            %   A record is issued after every successfull static or transient analysis step. Sometimes the user may need the record to be issued on more occasions than this, for example if the user is just looking to record the eigenvectors after an eigen command or for example the user wishes to include the state of the model at time 0.0 before any analysis has been completed.
            [varargout{1:nargout}] = obj.mexHandle('record');
        end

        function ok = recorder(obj, recorderType, recorderArgs)
            % This command is used to generate a recorder object which is to monitor what is happening during the analysis and generate output for the user.
            %
            % See also:
            % ---------
            %   - [OpenSeesPyDoc](https://openseespydoc.readthedocs.io/en/latest/src/recorder.html)
            %   - [OpenSeesDocumentation](https://opensees.github.io/OpenSeesDocumentation/user/manual/output/recorder.html)
            %
            % Parameters:
            % -----------
            % recorderType: str
            %   Type of recorder to create.
            % recorderArgs: varargin
            %   Arguments for the recorder.
            %
            % Return:
            % --------
            % ok: int
            %   - >0 an integer tag that can be used as a handle on the recorder for the remove recorder commmand.
            %   - -1 recorder command failed if integer -1 returned.
            arguments
                obj
                recorderType {mustBeTextScalar, mustBeMember(recorderType, ...
                           {'Node', 'EnvelopeNode', ...
                            'Element', 'EnvelopeElement', ...
                            'Drift', 'EnvelopeDrift', ...
                            'PVD', 'BgPVD', ...
                            'Remove', 'ElementRemoval', 'NodeRemoval', 'Collapse', ...
                            'gmsh', 'mpco', 'VTKHDF'})}
            end
            arguments (Repeating)
                recorderArgs
            end

            ok = obj.mexHandle('recorder', recorderType, recorderArgs{:});
        end

    end

    % Section geometry commands
    methods (Access = public)
        function varargout = section(obj, secType, secTag, secArgs)
            % This command is used to construct a Section object which represents the section geometry of a beam element.
            %
            % See also in [section commands (Python)](https://openseespydoc.readthedocs.io/en/latest/src/section.html) and [section commands (Tcl)](https://opensees.berkeley.edu/wiki/index.php?title=Section_Command)
            %
            % Parameters
            % ----------
            % secType : str
            %   The section type.
            % secTag : int
            %   The section tag.
            % secArgs : cell
            %   Additional section parameters. Every section type requires specific parameters.

            arguments
                obj
                secType {mustBeTextScalar, mustBeMember(secType, ...
                                {'Elastic', 'ElasticBD', 'Fiber', 'fiberSec', 'FiberWarping', ...
                                 'FiberAsym', 'FiberThermal', 'NDFiber', 'NDFiberWarping', ...
                                 'Uniaxial', 'Generic1D', 'Generic1d', ...
                                 'ElasticMembranePlateSection', 'PlateFiber', 'PlateFiberThermal', ...
                                 'DoublePlateFiber', 'ElasticWarpingShear', 'ElasticTube', ...
                                 'Tube', 'HSS', 'WFSection2d', 'WSection2d', 'RCSection2d', ...
                                 'RCTBeamSection2d', 'RCTBeamSectionUniMat2d', 'Parallel', ...
                                 'ASDCoupledHinge3D', 'Aggregator', 'AddDeformation', ...
                                 'ElasticPlateSection', 'LayeredShell', 'LayeredShellThermal', ...
                                 'Bidirectional', 'Elliptical', 'Isolator2spring', ...
                                 'RCCircularSection', 'MVLEM', 'SFIMVLEM', 'SFI_MVLEM', ...
                                 'RCTunnelSection', ...
                                 'ReinforcedConcreteLayeredMembraneSection', ...
                                 'RCLayeredMembraneSection', 'RCLMS', ...
                                 'LayeredMembraneSection', 'LMS', ...
                                 'ElasticMembraneSection', 'Pipe'})}
                secTag (1,1) {mustBeNumeric}
            end
            arguments (Repeating)
                secArgs
            end

            if ~isempty(obj.parent.pre.secGeoRecorder)
                if any(strcmpi(secType, ["Fiber","fiberSec","FiberThermal","NDFiber", "FiberWarping", "FiberWarping", "NDFiberWarping"]))
                    obj.parent.pre.secGeoRecorder.setSectionTag(secTag);
                end
            end

            [varargout{1:nargout}] = obj.mexHandle('section', secType, secTag, secArgs{:});
        end

        function varargout = fiber(obj, yloc, zloc, A, matTag)
            % This command allows the user to construct a single fiber and add it to the enclosing FiberSection or NDFiberSection.
            %
            % Parameters
            % ----------
            % yloc : double
            %   Fiber y-location.
            % zloc : double
            %   Fiber z-location.
            % A : double
            %   Fiber area.
            % matTag : int
            %   Material tag associated with this fiber (UniaxialMaterial tag for a FiberSection and NDMaterial tag for use in an NDFiberSection).
            %
            % Returns
            % -------
            % varargout
            %       Outputs returned by the underlying OpenSees MEX command, if any.

            arguments
                obj
                yloc (1,1) {mustBeNumeric}
                zloc (1,1) {mustBeNumeric}
                A (1,1) {mustBeNumeric}
                matTag (1,1) {mustBeNumeric}
            end
            if ~isempty(obj.parent.pre.secGeoRecorder)
                obj.parent.pre.secGeoRecorder.addFiber(yloc, zloc, A, matTag);
            end

            [varargout{1:nargout}] = obj.mexHandle('fiber', yloc, zloc, A, matTag);
        end

        function varargout = patch(obj, patchType, matTag, varargin)
            % The patch command is used to generate a number of fibers over a cross-sectional area. Currently there are three types of cross-section that fibers can be generated: quadrilateral, rectangular and circular.
            %
            % See Also
            % --------
            %   - [patch command (OpenSeesPyDoc)](https://openseespydoc.readthedocs.io/en/latest/src/patch.html)
            %   - [patch command (OpenSees Wiki)](https://opensees.berkeley.edu/wiki/index.php?title=Patch_Command)
            %
            % Parameters
            % ----------
            % patchType : str
            %   The type of patch to generate. Must be one of 'rect', 'quad', or 'circ'.
            % matTag : int
            %   The tag of the material to use for the patch.
            % varargin : varargin
            %   Additional arguments to pass to the patch command. Every patchType requires different arguments.

            arguments
                obj
                patchType {mustBeTextScalar, mustBeMember(patchType, {'rect', 'quad', 'circ'})}
                matTag (1,1) {mustBeNumeric}
            end

            arguments (Repeating)
                varargin
            end

            if ~isempty(obj.parent.pre.secGeoRecorder)
                obj.parent.pre.secGeoRecorder.addPatch(patchType, matTag, varargin{:});
            end

            [varargout{1:nargout}] = obj.mexHandle('patch', patchType, matTag, varargin{:});

        end

        function varargout = layer(obj, layerType, matTag, varargin)
            % The layer command is used to generate a number of fibers along a line or a circular arc.
            %
            % See Also
            % --------
            %   - [layer command (OpenSeesPyDoc)](https://openseespydoc.readthedocs.io/en/latest/src/layer.html)
            %   - [layer command (OpenSees Wiki)](https://opensees.berkeley.edu/wiki/index.php?title=Layer_Command)
            %
            % Parameters
            % ----------
            % layerType : str
            %   The type of layer to generate. Must be one of 'straight', 'circ', or 'rect'.
            % matTag : int
            %   The tag of the material to use for the layer.
            % varargin : varargin
            %   Additional arguments to pass to the layer command. Every layerType requires different arguments.

            arguments
                obj
                layerType {mustBeTextScalar, mustBeMember(layerType, {'straight', 'circ', 'rect'})}
                matTag (1,1) {mustBeNumeric}
            end
            arguments (Repeating)
                varargin
            end

            if ~isempty(obj.parent.pre.secGeoRecorder)
                obj.parent.pre.secGeoRecorder.addLayer(layerType, matTag, varargin{:});
            end

            [varargout{1:nargout}] = obj.mexHandle('layer', layerType, matTag, varargin{:});
        end
    end

    % Outputs commands
    % ---------------
    methods (Access = public)
        function result = nodeDisp(obj, nodeTag, dof)
            % Get nodal displacement.
            %
            % See also
            % --------
            %   - [nodeDisp (OpenSeesPy)](https://openseespydoc.readthedocs.io/en/latest/src/nodeDisp.html)
            %
            % Syntax
            % ------
            %     disp = ops.nodeDisp(nodeTag)        % all DOFs -> double vector
            %     disp = ops.nodeDisp(nodeTag, dof)   % single DOF -> double scalar
            %
            % Parameters
            % ----------
            % nodeTag : int
            %   Node tag.
            % dof : int (optional)
            %   Degree of freedom (1-based). If omitted, returns all DOFs.
            %
            % Returns
            % -------
            % result : double scalar | double vector | []
            %   Nodal displacement(s). If dof is omitted, returns all DOFs.
            arguments
                obj
                nodeTag (1,1) {mustBeNumeric}
                dof     (1,1) {mustBeNumeric}  = -1
            end
            if dof == -1
                result = obj.mexHandle('nodeDisp', nodeTag);
            else
                result = obj.mexHandle('nodeDisp', nodeTag, dof);
            end
        end

        function result = nodeAccel(obj, nodeTag, dof)
            % Get nodal acceleration.
            %
            % See also
            % --------
            %   - [nodeAccel (OpenSeesPy)](https://openseespydoc.readthedocs.io/en/latest/src/nodeAccel.html)
            %
            % Syntax
            % ------
            %     accel = ops.nodeAccel(nodeTag)        % all DOFs -> double vector
            %     accel = ops.nodeAccel(nodeTag, dof)   % single DOF -> double scalar
            %
            % Parameters
            % ----------
            % nodeTag : int
            %   Node tag.
            % dof : int (optional)
            %   Degree of freedom (1-based). If omitted, returns all DOFs.
            %
            % Returns
            % -------
            % result : double scalar | double vector | []
            %   Nodal acceleration(s). If dof is omitted, returns all DOFs.
            arguments
                obj
                nodeTag (1,1) {mustBeNumeric}
                dof     (1,1) {mustBeNumeric}  = -1
            end
            if dof == -1
                result = obj.mexHandle('nodeAccel', nodeTag);
            else
                result = obj.mexHandle('nodeAccel', nodeTag, dof);
            end
        end

        function result = nodeVel(obj, nodeTag, dof)
            % Get nodal velocity.
            %
            % Syntax
            % ------
            %     vel = ops.nodeVel(nodeTag)        % all DOFs -> double vector
            %     vel = ops.nodeVel(nodeTag, dof)   % single DOF -> double scalar
            %
            % Parameters
            % ----------
            % nodeTag : int
            %   Node tag.
            % dof : int (optional)
            %   Degree of freedom (1-based). If omitted, returns all DOFs.
            %
            % Returns
            % -------
            % result : double scalar | double vector | []
            %   Nodal velocity(s). If dof is omitted, returns all DOFs.
            arguments
                obj
                nodeTag (1,1) {mustBeNumeric}
                dof     (1,1) {mustBeNumeric}  = -1
            end
            if dof == -1
                result = obj.mexHandle('nodeVel', nodeTag);
            else
                result = obj.mexHandle('nodeVel', nodeTag, dof);
            end
        end

        function result = nodeCoord(obj, nodeTag, dim)
            % Get nodal coordinate.
            %
            % Syntax
            % ------
            %     coord = ops.nodeCoord(nodeTag)        % all dimensions -> double vector
            %     coord = ops.nodeCoord(nodeTag, dim)   % single dimension -> double scalar
            %
            % Parameters
            % ----------
            % nodeTag : int
            %   Node tag.
            % dim : int (optional)
            %   Dimension (1-based). If omitted, returns all dimensions.
            %
            % Returns
            % -------
            % result : double scalar | double vector | []
            %   Nodal coordinate(s). If dim is omitted, returns all dimensions.
            arguments
                obj
                nodeTag (1,1) {mustBeNumeric}
                dim     (1,1) {mustBeNumeric}  = -1
            end
            if dim == -1
                result = obj.mexHandle('nodeCoord', nodeTag);
            else
                result = obj.mexHandle('nodeCoord', nodeTag, dim);
            end
        end

        function result = nodeBounds(obj)
            % Get the boundary of all nodes. Return a list of boundary values.
            %
            % Returns
            % -------
            % result : struct
            %   Struct containing min/max values for each dimension.
            %   [xmin, ymin, zmin, xmax, ymax, zmax]
            result = obj.mexHandle('nodeBounds');
        end

        function result = nodeEigenvector(obj, nodeTag, modeTag, dof)
            % Returns the eigenvector at a specified node.
            %
            % Parameters
            % ----------
            % nodeTag : numeric
            %   The tag of the node.
            % modeTag : numeric
            %   The mode number of eigenvector to be returned.
            % dof : numeric, optional
            %   The degree of freedom (1 through ndf). If -1, returns the eigenvector for all DOFs.
            %
            % Returns
            % -------
            % result : double scalar | double vector | []
            %   Nodal eigenvector value(s). If dof is omitted, returns all DOFs.
            arguments
                obj
                nodeTag (1,1) {mustBeNumeric}
                modeTag (1,1) {mustBeNumeric}
                dof     (1,1) {mustBeNumeric} = -1
            end
            if dof == -1
                result = obj.mexHandle('nodeEigenvector', nodeTag, modeTag);
            else
                result = obj.mexHandle('nodeEigenvector', nodeTag, modeTag, dof);
            end
        end

        function result = nodeDOFs(obj, nodeTag)
            % Returns the DOF numbering of a node.
            %
            % Parameters
            % ----------
            % nodeTag : numeric
            %   The tag of the node.
            %
            % Returns
            % -------
            % result : double vector
            %   The DOF numbering of the node.
            arguments
                obj
                nodeTag (1,1) {mustBeNumeric}
            end
            result = obj.mexHandle('nodeDOFs', nodeTag);
        end

        function result = nodeMass(obj, nodeTag, dof)
            % Returns the mass at a specified node.
            %
            % Parameters
            % ----------
            % nodeTag : numeric
            %   The tag of the node.
            % dof : numeric, optional
            %   The degree of freedom (1 through ndf). If -1, returns the mass values for all DOFs.
            %
            % Returns
            % -------
            % result : double scalar | double vector | []
            %   Mass value(s). If dof is omitted, returns all DOFs.
            arguments
                obj
                nodeTag (1,1) {mustBeNumeric}
                dof     (1,1) {mustBeNumeric} = -1
            end
            if dof == -1
                result = obj.mexHandle('nodeMass', nodeTag);
            else
                result = obj.mexHandle('nodeMass', nodeTag, dof);
            end
        end

        function result = nodePressure(obj, nodeTag)
            % Returns the pressure at a specified node.
            %
            % Parameters
            % ----------
            % nodeTag : numeric
            %   The tag of the node.
            %
            % Returns
            % -------
            % result : double scalar | []
            %   Pressure value.
            arguments
                obj
                nodeTag (1,1) {mustBeNumeric}
            end
            result = obj.mexHandle('nodePressure', nodeTag);
        end

        function result = nodeReaction(obj, nodeTag, dof)
            % Returns the reaction at a specified node. Must call ``reactions()`` command before this command.
            %
            % Parameters
            % ----------
            % nodeTag : numeric
            %   The tag of the node.
            % dof : numeric, optional
            %   The degree of freedom (1 through ndf). If -1, returns the reaction values for all DOFs.
            %
            % Returns
            % -------
            % result : double scalar | double vector | []
            %   Reaction value(s). If dof is omitted, returns all DOFs.
            arguments
                obj
                nodeTag (1,1) {mustBeNumeric}
                dof     (1,1) {mustBeNumeric} = -1
            end
            if dof == -1
                result = obj.mexHandle('nodeReaction', nodeTag);
            else
                result = obj.mexHandle('nodeReaction', nodeTag, dof);
            end
        end

        function varargout = reactions(obj, dynamic)
            % Calculate the reactions. Call this command before the ``nodeReaction()`` command.
            %
            % Parameters
            % ----------
            % dynamic : string scalar, optional
            %   - if dynamic is empty, calculates static reactions.
            %   - if '-dynamic' is specified, calculates dynamic reactions.
            %   - if '-rayleigh' is specified, calculates dynamic reactions with Rayleigh damping.

            arguments
                obj
                dynamic {mustBeTextScalar, mustBeMember(dynamic, {'', '-dynamic', '-incInertia', '-dynamical', '-Dynamic', '-rayleigh'})} = ''
            end

            if isempty(dynamic) || strlength(dynamic) == 0
                [varargout{1:nargout}] = obj.mexHandle('reactions');
            else
                [varargout{1:nargout}] = obj.mexHandle('reactions', dynamic);
            end
        end

        function result = nodeResponse(obj, nodeTag, dof, responseID)
            % Returns the responses at a specified node. To get reactions (id=6), must call the ``reactions`` command before this command.
            %
            % Parameters
            % ----------
            % nodeTag : numeric scalar
            %   The tag of the node.
            % dof : numeric scalar
            %   The degree of freedom (1-based index).
            % responseID : numeric scalar
            %   The response ID (1-based index).
            %
            %   - Disp = 1
            %   - Vel = 2
            %   - Accel = 3
            %   - IncrDisp = 4
            %   - IncrDeltaDisp = 5
            %   - Reaction = 6
            %   - Unbalance = 7
            %   - RayleighForces = 8
            %
            % Returns
            % -------
            % result : numeric scalar
            %   The response value.

            arguments
                obj
                nodeTag (1,1) {mustBeNumeric}
                dof     (1,1) {mustBeNumeric}
                responseID (1,1) {mustBeNumeric}
            end
            result = obj.mexHandle('nodeResponse', nodeTag, dof, responseID);
        end

        function result = nodeUnbalance(obj, nodeTag, dof)
            % Returns the unbalance at a specified node.
            %
            % Parameters
            % ----------
            % nodeTag : numeric scalar
            %   The tag of the node.
            % dof : numeric scalar, optional
            %   The specific dof at the node (1 through ndf), if no dof is provided, a vector of values for all dofs is returned.
            %
            % Returns
            % -------
            % result : numeric scalar or vector
            %   The unbalance value(s).
            arguments
                obj
                nodeTag (1,1) {mustBeNumeric}
                dof     (1,1) {mustBeNumeric} = -1
            end
            if dof == -1
                result = obj.mexHandle('nodeUnbalance', nodeTag);
            else
                result = obj.mexHandle('nodeUnbalance', nodeTag, dof);
            end
        end

        function result = basicDeformation(obj, eleTag)
            % Returns the deformation of the basic system for a beam-column element.
            %
            % Parameters
            % ----------
            % eleTag : numeric scalar
            %   The tag of the element.
            %
            % Returns
            % -------
            % result : numeric vector
            %   The basic deformation values.
            arguments
                obj
                eleTag (1,1) {mustBeNumeric}
            end
            result = obj.mexHandle('basicDeformation', eleTag);
        end

        function result = basicForce(obj, eleTag)
            % Returns the force of the basic system for a beam-column element.
            %
            % Parameters
            % ----------
            % eleTag : numeric scalar
            %   The tag of the element.
            %
            % Returns
            % -------
            % result : numeric vector
            %   The basic force values.
            arguments
                obj
                eleTag (1,1) {mustBeNumeric}
            end
            result = obj.mexHandle('basicForce', eleTag);
        end

        function result = basicStiffness(obj, eleTag)
            % Returns the stiffness of the basic system for a beam-column element. A vector of values in row order will be returned.
            %
            % Parameters
            % ----------
            % eleTag : numeric scalar
            %   The tag of the element.
            %
            % Returns
            % -------
            % result : numeric vector
            %   The basic stiffness values.
            arguments
                obj
                eleTag (1,1) {mustBeNumeric}
            end
            result = obj.mexHandle('basicStiffness', eleTag);
        end

        function result = eleDynamicalForce(obj, eleTag, dof)
            % Returns the elemental dynamic force.
            %
            % Parameters
            % ----------
            % eleTag : numeric scalar
            %   The tag of the element.
            % dof : numeric scalar, optional
            %   The degree of freedom, 1-based index.
            %
            % Returns
            % -------
            % result : numeric scalar | numeric vector
            %   The dynamical force value.
            arguments
                obj
                eleTag (1,1) {mustBeNumeric}
                dof (1,1) {mustBeNumeric} = -1
            end
            if dof <= 0
                result = obj.mexHandle('eleDynamicalForce', eleTag);
            else
                result = obj.mexHandle('eleDynamicalForce', eleTag, dof);
            end
        end

        function result = eleForce(obj, eleTag, dof)
            % Returns the elemental resisting force.
            %
            % Parameters
            % ----------
            % eleTag : numeric scalar
            %   The tag of the element.
            % dof : numeric scalar, optional
            %   The degree of freedom, 1-based index.
            %
            % Returns
            % -------
            % result : numeric scalar | numeric vector
            %   The force value.
            arguments
                obj
                eleTag (1,1) {mustBeNumeric}
                dof (1,1) {mustBeNumeric} = -1
            end
            if dof <= 0
                result = obj.mexHandle('eleForce', eleTag);
            else
                result = obj.mexHandle('eleForce', eleTag, dof);
            end
        end

        function result = eleNodes(obj, eleTag)
            % Returns the nodes of the element.
            %
            % Parameters
            % ----------
            % eleTag : numeric scalar
            %   The tag of the element.
            %
            % Returns
            % -------
            % result : numeric vector
            %   The node tags.
            arguments
                obj
                eleTag (1,1) {mustBeNumeric}
            end
            result = obj.mexHandle('eleNodes', eleTag);
        end

        function result = eleResponse(obj, eleTag, args)
            % This command is used to obtain the same element quantities as those obtained from the element recorder at a particular time step.
            %
            % Parameters
            % ----------
            % eleTag : numeric scalar
            %   The tag of the element.
            % args: varargin
            %   Same arguments as those specified in element recorder. These arguments are specific to the type of element being used.
            %
            % Returns
            % -------
            % result : string
            %   The element type.
            arguments
                obj
                eleTag (1,1) {mustBeNumeric}
            end
            arguments (Repeating)
                args
            end
            result = obj.mexHandle('eleResponse', eleTag, args{:});
        end

        function result = getEleTags(obj, varargin)
            % Get all elements in the domain or in a mesh.
            %
            % Syntax
            % ------
            %     result = getEleTags()
            %     result = getEleTags('-mesh', mtag)
            %
            % Returns
            % -------
            % result : numeric vector
            %   The tags of all elements in the domain or mesh.
            result = obj.mexHandle('getEleTags', varargin{:});
        end

        function result = getNodeTags(obj, varargin)
            % Get all nodes in the domain or in a mesh.
            %
            % Syntax
            % ------
            %     result = getNodeTags()
            %     result = getNodeTags('-mesh', mtag)
            %
            % Returns
            % -------
            % result : numeric vector
            %   The tags of all nodes in the domain or mesh.
            result = obj.mexHandle('getNodeTags', varargin{:});
        end

        function result = getLoadFactor(obj, patternTag)
            % Get the load factor for a given pattern tag.
            %
            % Parameters
            % ----------
            % patternTag : numeric scalar
            %   The tag of the pattern.
            %
            % Returns
            % -------
            % result : numeric scalar
            %   The load factor.
            arguments
                obj
                patternTag (1,1) {mustBeNumeric}
            end
            result = obj.mexHandle('getLoadFactor', patternTag);
        end

        function result = getTime(obj)
            % Get the current time in the domin.
            %
            % Returns
            % -------
            % result : numeric scalar
            %   The current time.
            result = obj.mexHandle('getTime');
        end

        function result = sectionForce(obj, eleTag, secNum, dof)
            % Returns the section force for a beam-column element. The dof of the section depends on the section type. Please check with the section manual.
            %
            % Parameters
            % ----------
            % eleTag : numeric scalar
            %   The tag of the element.
            % secNum : numeric scalar
            %   The section number, 1-based.
            % dof : numeric scalar, optional
            %   The degree of freedom, 1-based.
            %
            % Returns
            % -------
            % result : numeric scalar | numeric vector
            %   The section force, if dof is not specified, scalar; otherwise, numeric vector.
            arguments
                obj
                eleTag (1,1) {mustBeNumeric}
                secNum (1,1) {mustBeNumeric}
                dof (1,1) {mustBeNumeric} = -1
            end
            if dof <= 0
                result = obj.mexHandle('sectionForce', eleTag, secNum);
            else
                result = obj.mexHandle('sectionForce', eleTag, secNum, dof);
            end
        end

        function result = sectionDeformation(obj, eleTag, secNum, dof)
            % Returns the section deformation for a beam-column element. The dof of the section depends on the section type. Please check with the section manual.
            %
            % Parameters
            % ----------
            % eleTag : numeric scalar
            %   The tag of the element.
            % secNum : numeric scalar
            %   The section number, 1-based.
            % dof : numeric scalar, optional
            %   The degree of freedom, 1-based.
            %
            % Returns
            % -------
            % result : numeric scalar | numeric vector
            %   The section deformation, if dof is not specified, scalar; otherwise, numeric vector.
            arguments
                obj
                eleTag (1,1) {mustBeNumeric}
                secNum (1,1) {mustBeNumeric}
                dof (1,1) {mustBeNumeric} = -1
            end
            if dof <= 0
                result = obj.mexHandle('sectionDeformation', eleTag, secNum);
            else
                result = obj.mexHandle('sectionDeformation', eleTag, secNum, dof);
            end
        end

        function result = sectionStiffness(obj, eleTag, secNum)
            % Returns the section stiffness matrix for a beam-column element. A list of values in the row order will be returned.
            %
            % Parameters
            % ----------
            % eleTag : numeric scalar
            %   The tag of the element.
            % secNum : numeric scalar
            %   The section number, 1-based.
            %
            % Returns
            % -------
            % result : numeric vector
            %   The section stiffness matrix, flattened in row order.
            arguments
                obj
                eleTag (1,1) {mustBeNumeric}
                secNum (1,1) {mustBeNumeric}
            end
            result = obj.mexHandle('sectionStiffness', eleTag, secNum);
        end

        function result = sectionFlexibility(obj, eleTag, secNum)
            % Returns the section flexibility matrix for a beam-column element. A list of values in the row order will be returned.
            %
            % Parameters
            % ----------
            % eleTag : numeric scalar
            %   The tag of the element.
            % secNum : numeric scalar
            %   The section number, 1-based.
            %
            % Returns
            % -------
            % result : numeric vector
            %   The section flexibility matrix, flattened in row order.
            arguments
                obj
                eleTag (1,1) {mustBeNumeric}
                secNum (1,1) {mustBeNumeric}
            end
            result = obj.mexHandle('sectionFlexibility', eleTag, secNum);
        end

        function result = sectionLocation(obj, eleTag, secNum)
            % Returns the section location for a beam-column element.
            %
            % Parameters
            % ----------
            % eleTag : numeric scalar
            %   The tag of the element.
            % secNum : numeric scalar, optional
            %   The section number, 1-based. If not provided, returns the location of all sections.
            %
            % Returns
            % -------
            % result : numeric vector | numeric scalar
            %   The section location, flattened in row order. If secNum is not provided, returns the location of all sections.
            arguments
                obj
                eleTag (1,1) {mustBeNumeric}
                secNum (1,1) {mustBeNumeric} = -1
            end
            if secNum <= 0
                result = obj.mexHandle('sectionLocation', eleTag);
            else
                result = obj.mexHandle('sectionLocation', eleTag, secNum);
            end
        end

        function result = sectionWeight(obj, eleTag, secNum)
            % Returns the weights of integration points of a section for a beam-column element.
            %
            % Parameters
            % ----------
            % eleTag : numeric scalar
            %   The tag of the element.
            % secNum : numeric scalar, optional
            %   The section number, 1-based. If not provided, returns the weight of all sections.
            %
            % Returns
            % -------
            % result : numeric scalar | numeric vector
            %   The section weight. If secNum is not provided, returns the weight of all sections.
            arguments
                obj
                eleTag (1,1) {mustBeNumeric}
                secNum (1,1) {mustBeNumeric} = -1
            end
            if secNum <= 0
                result = obj.mexHandle('sectionWeight', eleTag);
            else
                result = obj.mexHandle('sectionWeight', eleTag, secNum);
            end
        end

        function result = systemSize(obj)
            % Return the system size.
            result = obj.mexHandle('systemSize');
        end

        function result = numIter(obj)
            % Return the number of iterations.
            result = obj.mexHandle('numIter');
        end

        function result = testIter(obj)
            % Returns the number of iterations the convergence test took in the last analysis step
            result = obj.mexHandle('testIter');
        end

        function result = testNorm(obj)
            % Returns the norms from the convergence test for the last analysis step.
            %
            % Note
            % ----
            %   The size of norms will be equal to the max number of iterations specified. The first testIter of these will be non-zero, the remaining ones will be zero.
            result = obj.mexHandle('testNorm');
        end

        function varargout = testUniaxialMaterial(obj, matTag)
            % Set the uniaxial material tag and test it.
            arguments
                obj
                matTag (1,1) {mustBeNumeric}
            end
            [varargout{1:nargout}] = obj.mexHandle('testUniaxialMaterial', matTag);
        end

        function varargout = setStrain(obj, eps)
            % Set the strain and test the uniaxial material specified by ``testUniaxialMaterial``.
            arguments
                obj
                eps {mustBeNumeric}
            end
            [varargout{1:nargout}] = obj.mexHandle('setStrain', eps);
        end

        function result = getStrain(obj)
            % Returns the strain of the uniaxial material specified by ``testUniaxialMaterial``.
            result = obj.mexHandle('getStrain');
        end

        function result = getStress(obj)
            % Returns the stress of the uniaxial material specified by ``testUniaxialMaterial``.
            result = obj.mexHandle('getStress');
        end

        function result = getTangent(obj)
            % Returns the tangent modulus of the uniaxial material specified by ``testUniaxialMaterial``.
            result = obj.mexHandle('getTangent');
        end

        function result = getDampTangent(obj)
            % Returns the damping tangent modulus of the uniaxial material specified by ``testUniaxialMaterial``.
            result = obj.mexHandle('getDampTangent');
        end

        function varargout = setTime(obj, pseudoTime)
            % This command is used to set the pseudo-time of the analysis.
            [varargout{1:nargout}] = obj.mexHandle('setTime', pseudoTime);
        end

        function varargout = reset(obj)
            % Reset the model.
            [varargout{1:nargout}] = obj.mexHandle('reset');
        end

    end
end
