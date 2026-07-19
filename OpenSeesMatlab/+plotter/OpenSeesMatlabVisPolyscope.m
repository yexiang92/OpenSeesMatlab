classdef OpenSeesMatlabVisPolyscope < handle
    % Polyscope visualisation interface for OpenSeesMatlab.
    %
    % This object is attached to the main vis interface as vis.polyscope,
    % so users can write:
    %
    %     opsmat.vis.polyscope.plotModel();
    %     opsmat.vis.polyscope.plotEigen(eigenData);
    %     opsmat.vis.polyscope.plotNodalResponse(nodeRespData);
    %
    % Each function opens an interactive Polyscope window with in-window
    % ImGui controls (and ImPlot for nodal-response histories). The
    % default backend is 'openGL3_glfw'; use opts.polyscope.backend =
    % 'openGL_mock' for headless rendering or automated tests.

    properties (Access = public)
        parent  % Reference to plotter.OpenSeesMatlabVis
    end

    methods
        function obj = OpenSeesMatlabVisPolyscope(parentObj)
            if nargin < 1 || isempty(parentObj)
                error('OpenSeesMatlabVisPolyscope:InvalidInput', ...
                    'A parent OpenSeesMatlabVis object is required.');
            end
            obj.parent = parentObj;
        end

        function h = plotModel(obj, options)
            % Open the Polyscope model viewer.
            %
            % Usage:
            % --------
            %     vis.polyscope.plotModel();
            arguments
                obj (1,1) plotter.OpenSeesMatlabVisPolyscope
                options.opts (1,1) struct = struct()
            end
            modelInfo = obj.parent.parent.post.getModelData();
            h = plotter.polyscope.plotModel(modelInfo, options.opts);
        end

        function h = plotEigen(obj, varargin)
            % Open the Polyscope eigen-mode viewer.
            %
            % Usage:
            % --------
            %     vis.polyscope.plotEigen(eigenData);
            %
            % If eigenData is omitted it is collected from the current model.
            % The mode number can be picked directly in the GUI; modeTag only
            % selects the mode shown on startup.

            modeTag = [];
            eigenData = [];
            opts = struct();

            if nargin == 2
                if isnumeric(varargin{1})
                    modeTag = varargin{1};
                elseif isstruct(varargin{1})
                    eigenData = varargin{1};
                else
                    error('OpenSeesMatlabVisPolyscope:InvalidInput', ...
                        'Expected modeTag (numeric) or eigenData (struct).');
                end
            elseif nargin == 3
                if isnumeric(varargin{1}) && isstruct(varargin{2})
                    modeTag = varargin{1};
                    eigenData = varargin{2};
                elseif isstruct(varargin{1}) && isstruct(varargin{2})
                    eigenData = varargin{1};
                    opts = varargin{2};
                else
                    error('OpenSeesMatlabVisPolyscope:InvalidInput', ...
                        'Expected (modeTag, eigenData) or (eigenData, opts).');
                end
            elseif nargin == 4
                modeTag = varargin{1};
                eigenData = varargin{2};
                opts = varargin{3};
            elseif nargin > 4
                error('OpenSeesMatlabVisPolyscope:InvalidInput', ...
                    'Too many input arguments.');
            end

            if isempty(eigenData) || ~isstruct(eigenData) || isempty(fieldnames(eigenData))
                numModes = 1;
                if ~isempty(modeTag) && isnumeric(modeTag) && isfinite(modeTag) && modeTag > 0
                    numModes = max(numModes, round(double(modeTag)));
                end
                eigenData = obj.parent.parent.post.getEigenData(numModes=numModes);
            end

            if ~isempty(modeTag)
                if ~isfield(opts, 'mode'), opts.mode = struct(); end
                opts.mode.modeTag = modeTag;
            end

            modelInfo = obj.parent.parent.post.getModelData();
            h = plotter.polyscope.plotEigen(modelInfo, eigenData, opts);
        end

        function h = plotNodalResponse(obj, nodeRespData, options)
            % Open the Polyscope nodal-response viewer.
            %
            % Usage:
            % --------
            %     vis.polyscope.plotNodalResponse(nodeRespData);
            %
            % Parameters
            % ----------
            % nodeRespData : struct
            %     Nodal response data, typically obtained from
            %     ``opsmat.post.getNodalResponse(odbTag)``. The struct must include an
            %     odbTag field so the corresponding model information can be
            %     loaded.
            arguments
                obj (1,1) plotter.OpenSeesMatlabVisPolyscope
                nodeRespData struct
                options.opts (1,1) struct = struct()
            end
            odbTag = nodeRespData(1).odbTag;
            modelInfo = post.ODB.readModelInfo(obj.parent.parent.opensees, odbTag);
            h = plotter.polyscope.plotNodalResponse(modelInfo, nodeRespData, options.opts);
        end

        function h = plotFrameResponse(obj, frameRespData, options)
            % Open the Polyscope frame-response viewer.
            % Usage:
            % --------
            %     vis.polyscope.plotFrameResponse(frameRespData);
            %
            % Parameters
            % ----------
            % frameRespData : struct
            %     Frame response data, typically obtained from
            %     ``opsmat.post.getFrameResponse(odbTag)``. The struct must include an
            %     odbTag field so the corresponding model information can be
            %     loaded.
            arguments
                obj (1,1) plotter.OpenSeesMatlabVisPolyscope
                frameRespData struct
                options.respType {mustBeTextScalar} = ""
                options.respComponent {mustBeTextScalar} = ""
                options.responseLocation {mustBeTextScalar} = ""
                options.stepIdx = "absMax"
                options.opts (1,1) struct = struct()
            end
            if strlength(string(options.respType)) > 0
                options.opts.respType = char(string(options.respType));
            end
            if strlength(string(options.respComponent)) > 0
                options.opts.component = char(string(options.respComponent));
            end
            if strlength(string(options.responseLocation)) > 0
                options.opts.responseLocation = char(string(options.responseLocation));
            end
            options.opts.stepIdx = options.stepIdx;
            if isfield(frameRespData(1), 'odbTag')
                odbTag = frameRespData(1).odbTag;
                modelInfo = post.ODB.readModelInfo(obj.parent.parent.opensees, odbTag);
            else
                modelInfo = obj.parent.parent.post.getModelData();
            end
            h = plotter.polyscope.plotFrameResponse(modelInfo, frameRespData, options.opts);
        end

        function h = plotShellResponse(obj, respData, options)
            % Open the Polyscope shell-response viewer.
            %
            % Usage:
            % --------
            %     vis.polyscope.plotShellResponse(respData);
            %
            % Parameters
            % ------------
            % respData : struct
            %     Shell response data, typically obtained from
            %     ``opsmat.post.getShellResponse(odbTag)``. The struct must include an
            %     odbTag field so the corresponding model information can be
            %     loaded.
            arguments
                obj (1,1) plotter.OpenSeesMatlabVisPolyscope
                respData struct
                options.respType {mustBeTextScalar} = "SecForceAtGP"
                options.respComponent {mustBeTextScalar} = "mxx"
                options.fiberPoint = "top"
                options.responseLocation {mustBeTextScalar} = ""
                options.stepIdx = "absMax"
                options.opts (1,1) struct = struct()
            end
            odbTag = respData(1).odbTag;
            modelInfo = post.ODB.readModelInfo(obj.parent.parent.opensees, odbTag);
            nodalResp = obj.parent.parent.post.getNodalResponse(odbTag, respType="disp");
            options.opts.eleType = 'Shell';
            options.opts.respType = char(string(options.respType));
            options.opts.component = char(string(options.respComponent));
            options.opts.fiberPoint = options.fiberPoint;
            options.opts.responseLocation = char(string(options.responseLocation));
            options.opts.stepIdx = options.stepIdx;
            h = plotter.polyscope.plotUnstruResponse(modelInfo, nodalResp, respData, options.opts);
        end

        function h = plotContinuumResponse(obj, respData, options)
            % Open the Polyscope continuum-response viewer.
            %
            % Usage:
            % --------
            %     vis.polyscope.plotContinuumResponse(respData);
            %
            % Parameters
            % ------------
            % respData : struct
            %     Continuum response data, typically obtained from
            %     ``opsmat.post.getContinuumResponse(odbTag)``. The struct
            %     must include an odbTag field so the corresponding model information
            %     can be loaded.
            arguments
                obj (1,1) plotter.OpenSeesMatlabVisPolyscope
                respData struct
                options.eleType {mustBeTextScalar} = ""
                options.respType {mustBeTextScalar} = "StressAtGP"
                options.respComponent {mustBeTextScalar} = "sxx"
                options.responseLocation {mustBeTextScalar} = ""
                options.stepIdx = "absMax"
                options.opts (1,1) struct = struct()
            end
            eleType = options.eleType;
            if strlength(string(eleType)) == 0 && isfield(respData(1), 'eleType')
                eleType = respData(1).eleType;
            end
            switch lower(char(string(eleType)))
                case 'plane'
                    eleType = 'Plane';
                case {'solid','brick'}
                    eleType = 'Solid';
                otherwise
                    eleType = 'Plane';
            end
            odbTag = respData(1).odbTag;
            modelInfo = post.ODB.readModelInfo(obj.parent.parent.opensees, odbTag);
            nodalResp = obj.parent.parent.post.getNodalResponse(odbTag, respType="disp");
            options.opts.eleType = char(string(eleType));
            options.opts.respType = char(string(options.respType));
            options.opts.component = char(string(options.respComponent));
            options.opts.responseLocation = char(string(options.responseLocation));
            options.opts.stepIdx = options.stepIdx;
            h = plotter.polyscope.plotUnstruResponse(modelInfo, nodalResp, respData, options.opts);
        end
    end
end
