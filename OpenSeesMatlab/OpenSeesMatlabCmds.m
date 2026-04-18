classdef OpenSeesMatlabCmds < OpenSeesMatlabBase
    % MATLAB interface cmds for OpenSees commands.
    %
    %   ``OpenSeesMatlab`` provides a user-facing MATLAB interface for executing
    %   OpenSees commands through the OpenSees MATLAB MEX module.
    %   ``OpenSeesMatlab`` implements all OpenSees commands, and the command calls have the same format as ``OpenSeesPy``. Please refer to the following for various commands:
    %
    % [OpenSeesPy](https://openseespydoc.readthedocs.io/en/latest/index.html)
    %
    % [OpenSees](https://opensees.github.io/OpenSeesDocumentation/)
    %
    %   Example
    %   -------
    %       ops = OpenSeesMatlab();
    %
    %       ops.wipe();
    %       ops.model('basic', '-ndm', 2, '-ndf', 3);
    %       ...
    %       ops.node(1, 0.0, 0.0);
    %       ops.node(2, 5.0, 0.0);
    %       ops.fix(1, 1, 1, 1);
    %       ops.element(...);
    %       ...
    %       ops.post.getModelData();
    %       ops.vis.plotModel();

    properties (SetAccess = private, GetAccess = private)
        parent  % Reference to the parent OpenSeesMatlab object
    end

    methods
        function obj = OpenSeesMatlabCmds(parentObj, mexName, mexDir)
            % Construct an OpenSees MATLAB command interface object.
            %
            % Parameters
            % ----------
            % parentObj : OpenSeesMatlab
            %       Reference to the parent OpenSeesMatlab object.
            %
            % mexName : string or char
            %       Name of the OpenSees MATLAB MEX module.
            %
            % mexDir : string or char
            %       Directory containing the MEX module.

            arguments
                parentObj (1,1) OpenSeesMatlab
                mexName  {mustBeTextScalar} = 'OpenSeesMATLAB'
                mexDir {mustBeTextScalar} = 'derived/'
            end
            obj@OpenSeesMatlabBase(mexName, mexDir);
            obj.parent = parentObj;
        end
    end

    %%   The OpenSees command methods are implemented in the OpenSeesMatlabBase class. 
    % Some commands can be overridden here to provide additional functionality or to handle specific cases, but the core command implementations are in the base class.
    methods (Access = public)
        function varargout = section(obj, varargin)
            if ~isempty(obj.parent.pre.secGeoRecorder)
                if numel(varargin) >= 2 && any(strcmpi(varargin{1}, ["Fiber","fiberSec","FiberThermal","NDFiber", "FiberWarping", "FiberWarping", "NDFiberWarping"]))
                    secTag = varargin{2};
                    obj.parent.pre.secGeoRecorder.setSectionTag(secTag);
                end
            end

            [varargout{1:nargout}] = section@OpenSeesMatlabBase(obj, varargin{:});
        end

        function varargout = fiber(obj, varargin)
            if ~isempty(obj.parent.pre.secGeoRecorder)
                obj.parent.pre.secGeoRecorder.addFiber(varargin{:});
            end
            
            [varargout{1:nargout}] = fiber@OpenSeesMatlabBase(obj, varargin{:});
        end

        function varargout = patch(obj, varargin)
            if ~isempty(obj.parent.pre.secGeoRecorder)
                patchType = varargin{1};
                obj.parent.pre.secGeoRecorder.addPatch(patchType, varargin{2:end});
            end

            [varargout{1:nargout}] = patch@OpenSeesMatlabBase(obj, varargin{:});
            
        end

        function varargout = layer(obj, varargin)
            if ~isempty(obj.parent.pre.secGeoRecorder)
                layerType = varargin{1};
                obj.parent.pre.secGeoRecorder.addLayer(layerType, varargin{2:end});
            end
            
            [varargout{1:nargout}] = layer@OpenSeesMatlabBase(obj, varargin{:});
        end
    end

end