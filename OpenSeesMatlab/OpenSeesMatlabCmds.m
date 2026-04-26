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
    %   The methods section, fiber, patch, and layer are overridden in this class
    %   so that OpenSees commands are still forwarded to the MEX module while
    %   optional section-geometry information is recorded for pre-processing,
    %   post-processing, and visualization workflows.
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
            %   The constructor is called by OpenSeesMatlab and usually does not
            %   need to be called directly. It initializes the inherited MEX
            %   command dispatcher and stores the parent OpenSeesMatlab object so
            %   command overrides can access pre-processing utilities.
            %
            % Parameters
            % ----------
            % parentObj : OpenSeesMatlab
            %       Parent OpenSeesMatlab object that owns this command interface.
            %
            % mexName : string or char, optional
            %       Name of the OpenSees MATLAB MEX module. Default is
            %       'OpenSeesMATLAB'.
            %
            % mexDir : string or char, optional
            %       Directory containing the MEX module. Relative paths are
            %       resolved by OpenSeesMatlabBase. Default is 'derived/'.
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

            [varargout{1:nargout}] = section@OpenSeesMatlabBase(obj, varargin{:});
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

            [varargout{1:nargout}] = fiber@OpenSeesMatlabBase(obj, varargin{:});
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

            [varargout{1:nargout}] = patch@OpenSeesMatlabBase(obj, varargin{:});

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

            [varargout{1:nargout}] = layer@OpenSeesMatlabBase(obj, varargin{:});
        end
    end

end
