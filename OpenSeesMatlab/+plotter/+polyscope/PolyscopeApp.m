classdef PolyscopeApp < handle
    %POLYSCOPEAPP Lifecycle manager for the Polyscope viewer.
    %
    %   Wraps the bundled Polyscope MATLAB binding so multiple viewer
    %   classes can share
    %   one viewer instance without re-initialising it.
    %
    %   Example
    %   -------
    %       app = plotter.polyscope.PolyscopeApp();
    %       app.init('openGL3_glfw');
    %       % register structures ...
    %       app.show();
    %       app.shutdown();

    properties (Access = private)
        ps_            % polyscope.Polyscope handle
        initialized_   logical = false
        backend_       char = 'openGL3_glfw'
    end

    methods
        function obj = PolyscopeApp()
            plotter.polyscope.setupPath();
            obj.ps_ = polyscope.Polyscope();
        end

        function init(obj, backend, opts, is2D)
            if nargin < 2 || isempty(backend)
                backend = obj.backend_;
            end
            if nargin < 3
                opts = struct();
            end
            if nargin < 4
                is2D = false;
            end
            if obj.isInitialized()
                plotter.polyscope.initialize(obj.ps_, opts, is2D, "postUpdate");
                return;
            end
            plotter.polyscope.initialize(obj.ps_, opts, is2D, "pre");
            obj.ps_.init(backend);
            plotter.polyscope.initialize(obj.ps_, opts, is2D, "post");
            obj.backend_ = backend;
            obj.initialized_ = true;
        end

        function setSSAAFactor(obj, factor)
            obj.ensureInit();
            factor = max(1, min(4, round(double(factor))));
            try
                obj.ps_.set_ssaa_factor(factor);
            catch
                % Older bundled MEX builds may not expose this command.
            end
        end

        function val = getSSAAFactor(obj)
            obj.ensureInit();
            try
                val = obj.ps_.get_ssaa_factor();
            catch
                % Older bundled MEX builds may not expose this command.
                val = 1;
            end
        end

        function tf = isInitialized(obj)
            tf = false;
            if ~obj.initialized_, return; end
            try
                tf = logical(obj.ps_.is_initialized());
            catch
                % The MEX may already be unloading during MATLAB clear/exit.
            end
            if ~tf, obj.initialized_ = false; end
        end

        function ensureInit(obj)
            if ~obj.isInitialized()
                obj.init();
            end
        end

        function show(obj, forFrames)
            obj.ensureInit();
            if nargin < 2
                obj.ps_.show();
            else
                obj.ps_.show(forFrames);
            end
        end

        function frameTick(obj)
            obj.ensureInit();
            obj.ps_.frame_tick();
        end

        function shutdown(obj)
            if ~obj.initialized_, return; end
            % Clear the local flag first so repeated/re-entrant destruction is
            % harmless. Polyscope itself is process-global, whereas several
            % viewer wrappers may each believe they own the initialized state.
            obj.initialized_ = false;
            try
                if obj.ps_.is_initialized()
                    obj.ps_.shutdown();
                end
            catch
                % Destructors must remain silent if another viewer has already
                % shut down Polyscope or the MEX is being cleared by MATLAB.
            end
        end

        function removeAllStructures(obj)
            obj.ensureInit();
            obj.ps_.remove_all_structures();
        end

        function removeEverything(obj)
            obj.ensureInit();
            obj.ps_.remove_everything();
        end

        function setUserCallback(obj, cb)
            obj.ensureInit();
            if nargin < 2 || isempty(cb)
                obj.ps_.clear_user_callback();
            else
                obj.ps_.set_user_callback(cb);
            end
        end

        function clearUserCallback(obj)
            obj.setUserCallback([]);
        end

        function setWindowSize(obj, w, h)
            obj.ensureInit();
            obj.ps_.set_window_size(w, h);
        end

        function maximizeWindow(obj)
            obj.ensureInit();
            try
                sz = get(0, 'ScreenSize');
                w = max(800, round(sz(3)));
                h = max(600, round(sz(4)));
            catch
                w = 1920; h = 1080;
            end
            obj.ps_.set_window_size(w, h);
        end

        function setBackgroundColor(obj, c)
            obj.ensureInit();
            obj.ps_.set_background_color(c);
        end

        function resetCamera(obj)
            obj.ensureInit();
            obj.ps_.reset_camera_to_home_view();
        end

        function lookAt(obj, eye, target, flyTo)
            if nargin < 4, flyTo = false; end
            obj.ensureInit();
            obj.setViewCenter(target);
            obj.ps_.look_at(eye, target, flyTo);
            obj.setViewCenter(target);
        end

        function lookAtDir(obj, eye, target, upDir, flyTo)
            if nargin < 5, flyTo = false; end
            obj.ensureInit();
            obj.setViewCenter(target);
            try
                obj.ps_.look_at_dir(eye, target, upDir, flyTo);
            catch
                obj.ps_.look_at(eye, target, flyTo);
            end
            obj.setViewCenter(target);
        end

        function setCameraViewMatrix(obj, mat)
            obj.ensureInit();
            obj.ps_.set_camera_view_matrix(mat);
        end

        function setProjectionMode(obj, mode)
            obj.ensureInit();
            try
                obj.ps_.set_view_projection_mode(char(string(mode)));
            catch
            end
        end

        function setViewCenter(obj, target)
            obj.ensureInit();
            try
                obj.ps_.set_view_center_raw(target);
            catch
            end
        end

        function screenshot(obj, filename, varargin)
            obj.ensureInit();
            if nargin < 2
                obj.ps_.screenshot();
            else
                obj.ps_.screenshot(filename, varargin{:});
            end
        end

        function ps = polyscopeHandle(obj)
            ps = obj.ps_;
        end
    end
end
