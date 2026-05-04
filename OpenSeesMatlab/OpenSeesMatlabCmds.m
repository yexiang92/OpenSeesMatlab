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
                modelType (1,:) {mustBeTextScalar, mustBeMember(modelType, ...
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
            % eleTag: double
            %   Element tag.
            % eleNodes: double
            %   Element nodes.
            % eleArgs: cell
            %   Element arguments.

            arguments
                obj
                eleType (1, :)   {mustBeTextScalar}
                eleTag (1, 1)    {mustBeNumeric}
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
            % nodeTag: double
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
                constrValues {mustBeNumeric}
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
            % rNodeTag: double
            %   Integer tag identifying the retained, or primary node.
            % cNodeTag: double
            %   Integer tag identifying the constrained, or secondary node.
            % dofs: double
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

        function varargout = equalDOF_Mixed(obj, rNodeTag, cNodeTag, numDOF, rcdofs)
            % Define a mixed equalDOF constraint between two nodes.
            %
            % Examples
            % --------
            %     equalDOF_Mixed(rNodeTag, cNodeTag, numDOF, [rdof1, cdof1, rdof2, cdof2, ...])
            %     equalDOF_Mixed(rNodeTag, cNodeTag, numDOF, rdof1, cdof1, rdof2, cdof2, ...)
            %
            % Parameters
            % ----------
            % rNodeTag : double
            %   Integer tag identifying the reference, or primary node.
            % cNodeTag : double
            %   Integer tag identifying the constrained, or secondary node.
            % numDOF : double
            %   Number of degrees-of-freedom to be constrained.
            % rcdofs : double
            %   Nodal degrees-of-freedom that are constrained at the cNode to be the same as those at the rNode. Valid range is from **1 through ndf**, the number of nodal degrees-of-freedom. ``rcdofs = [rdof1, cdof1, rdof2, cdof2, ...]``
            arguments
                obj
                rNodeTag (1, 1) {mustBeNumeric}
                cNodeTag (1, 1) {mustBeNumeric}
                numDOF (1, 1) {mustBeNumeric}
            end

            arguments (Repeating)
                rcdofs
            end

            [varargout{1:nargout}] = obj.mexHandle('equalDOF_Mixed', rNodeTag, cNodeTag, numDOF, rcdofs{:});
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
            % cNodeTags: int
            %   The integar tags identifying the constrained (secondary) nodes.
            arguments
                obj
                perpDirn (1, 1) {mustBeNumeric, mustBeMember(perpDirn, {1, 2, 3})}
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
                linkType (1, 1) {mustBeMember(linkType, {'bar', 'beam'})}
                rNodeTag (1, 1) {mustBeNumeric}
                cNodeTag (1, 1) {mustBeNumeric}
            end

            [varargout{1:nargout}] = obj.mexHandle('rigidLink', linkType, rNodeTag, cNodeTag);
        end

    end

    % Section geometry commands
    methods (Access = public)
        function varargout = section(obj, varargin)
            % Define an OpenSees section and optionally record its geometry tag.
            %
            %   This method forwards all inputs to OpenSeesMatlabBase.section.
            %   When the section geometry recorder is enabled through
            %   opsmat.pre.setSectionGeometryRecorder(true), supported fiber
            %   section definitions are tracked so they can later be plotted with
            %   opsmat.pre.plotSection(secTag).
            %
            % Syntax
            % ------
            %       ops.section(sectionType, secTag, args...)
            %
            % Parameters
            % ----------
            % sectionType : char or string
            %       OpenSees section type, for example 'Fiber', 'fiberSec',
            %       'FiberThermal', 'NDFiber', 'FiberWarping', or
            %       'NDFiberWarping'.
            % secTag : numeric
            %       Section tag passed to OpenSees and used by the section geometry
            %       recorder.
            % args : cell
            %       Additional OpenSees section command arguments.
            %
            % Returns
            % -------
            % varargout
            %       Outputs returned by the underlying OpenSees MEX command, if any.
            %
            % Example
            % -------
            %       opsmat.pre.setSectionGeometryRecorder(true);
            %       ops.section('Fiber', 1, '-GJ', 1.0e6);
            if ~isempty(obj.parent.pre.secGeoRecorder)
                if numel(varargin) >= 2 && any(strcmpi(varargin{1}, ["Fiber","fiberSec","FiberThermal","NDFiber", "FiberWarping", "FiberWarping", "NDFiberWarping"]))
                    secTag = varargin{2};
                    obj.parent.pre.secGeoRecorder.setSectionTag(secTag);
                end
            end

            [varargout{1:nargout}] = obj.mexHandle('section', varargin{:});
        end

        function varargout = fiber(obj, varargin)
            % Define an OpenSees fiber and optionally record it for visualization.
            %
            %   This method forwards all inputs to OpenSeesMatlabBase.fiber.
            %   When section geometry recording is enabled, the same inputs are
            %   also stored in the active SectionGeometryRecorder.
            %
            % Syntax
            % ------
            %       ops.fiber(args...)
            %
            % Parameters
            % ----------
            % args : cell
            %       OpenSees fiber command arguments. The exact argument list
            %       depends on the selected OpenSees fiber definition.
            %
            % Returns
            % -------
            % varargout
            %       Outputs returned by the underlying OpenSees MEX command, if any.
            %
            % Example
            % -------
            %       opsmat.pre.setSectionGeometryRecorder(true);
            %       ops.section('Fiber', 1, '-GJ', 1.0e6);
            %       ops.fiber(0.0, 0.0, 0.01, 1);
            if ~isempty(obj.parent.pre.secGeoRecorder)
                obj.parent.pre.secGeoRecorder.addFiber(varargin{:});
            end

            [varargout{1:nargout}] = obj.mexHandle('fiber', varargin{:});
        end

        function varargout = patch(obj, varargin)
            % Define an OpenSees fiber patch and optionally record it.
            %
            %   This method forwards all inputs to OpenSeesMatlabBase.patch.
            %   When section geometry recording is enabled, the patch type and
            %   patch arguments are also stored for later section plotting.
            %
            % Syntax
            % ------
            %       ops.patch(patchType, args...)
            %
            % Parameters
            % ----------
            % patchType : char or string
            %       OpenSees patch type, for example 'rect', 'quad', or 'circ'.
            % args : cell
            %       Additional patch arguments passed directly to OpenSees.
            %
            % Returns
            % -------
            % varargout
            %       Outputs returned by the underlying OpenSees MEX command, if any.
            %
            % Example
            % -------
            %       opsmat.pre.setSectionGeometryRecorder(true);
            %       ops.section('Fiber', 1, '-GJ', 1.0e6);
            %       ops.patch('rect', 1, 10, 10, -0.2, -0.3, 0.2, 0.3);
            if ~isempty(obj.parent.pre.secGeoRecorder)
                patchType = varargin{1};
                obj.parent.pre.secGeoRecorder.addPatch(patchType, varargin{2:end});
            end

            [varargout{1:nargout}] = obj.mexHandle('patch', varargin{:});

        end

        function varargout = layer(obj, varargin)
            % Define an OpenSees reinforcement layer and optionally record it.
            %
            %   This method forwards all inputs to OpenSeesMatlabBase.layer.
            %   When section geometry recording is enabled, the layer type and
            %   layer arguments are also stored for section visualization.
            %
            % Syntax
            % ------
            %       ops.layer(layerType, args...)
            %
            % Parameters
            % ----------
            % layerType : char or string
            %       OpenSees layer type, for example 'straight' or 'circ'.
            % args : cell
            %       Additional layer arguments passed directly to OpenSees.
            %
            % Returns
            % -------
            % varargout
            %       Outputs returned by the underlying OpenSees MEX command, if any.
            %
            % Example
            % -------
            %       opsmat.pre.setSectionGeometryRecorder(true);
            %       ops.section('Fiber', 1, '-GJ', 1.0e6);
            %       ops.layer('straight', 2, 4, 0.0002, -0.15, 0.25, 0.15, 0.25);
            if ~isempty(obj.parent.pre.secGeoRecorder)
                layerType = varargin{1};
                obj.parent.pre.secGeoRecorder.addLayer(layerType, varargin{2:end});
            end

            [varargout{1:nargout}] = obj.mexHandle('layer', varargin{:});
        end
    end

end
