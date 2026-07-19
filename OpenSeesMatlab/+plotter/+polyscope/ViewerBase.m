classdef (Abstract) ViewerBase < handle
    %VIEWERBASE Abstract base class for Polyscope-based OpenSees viewers.
    %
    %   This class contains common infrastructure shared by Polyscope-based
    %   viewers. Subclasses must implement build() and guiCallback_().

    properties
        ModelInfo struct
        EigenInfo struct = struct()
        Opts      struct
        App       plotter.polyscope.PolyscopeApp
    end

    properties (Access = protected)
        built_      logical = false
        handles_    struct = struct()
        gui_        struct = struct()
        L_          double = 1
        P0_         double = zeros(0, 3)
        query_      struct = struct()
        highlight_  struct = struct()
        rangeCache_ struct = struct()
        windowSizeCache_ double = zeros(0, 2)
        windowSizeCacheTimer_ = []
        screenAxesUpdateTimer_ = []
    end

    methods
        function show(obj)
            if ~obj.built_
                obj.build();
            end
            obj.App.show();
        end

        function frameTick(obj)
            if ~obj.built_
                obj.build();
            end
            obj.App.frameTick();
        end

        function update(obj, opts)
            if nargin >= 2 && ~isempty(opts)
                obj.Opts = plotter.polyscope.Options.mergeOpts(obj.Opts, opts);
            end
            obj.build();
        end

        function enableGui(obj)
            if ~obj.built_
                obj.build();
            end
            obj.initGuiState_();
            obj.App.setUserCallback(@obj.guiCallback_);
        end

        function screenshot(obj, filename, varargin)
            obj.App.screenshot(filename, varargin{:});
        end

        function addSlicePlane(obj)
            %ADDSLICEPLANE Add a new slice plane (public API).
            obj.addSlicePlane_();
        end

        function removeSlicePlane(obj, idx)
            %REMOVESLICEPLANE Remove a slice plane by index (public API).
            %   If idx is omitted, the last plane is removed.
            if nargin < 2 || isempty(idx)
                if ~isfield(obj.Opts, 'slice') || ~isfield(obj.Opts.slice, 'planes')
                    return;
                end
                idx = numel(obj.Opts.slice.planes);
            end
            obj.removeSlicePlaneByIdx_(idx);
        end

        function applySlicePlanes(obj)
            %APPLYSLICEPLANES Apply current slice-plane state to Polyscope.
            obj.applySlicePlane_();
        end
    end

    methods (Abstract)
        build(obj)
        guiCallback_(obj)
    end

    methods (Access = protected)

        function clear_(obj)
            obj.removeScreenAxesGizmo_();
            obj.removeSlicePlane_();
            obj.App.removeAllStructures();
            obj.handles_ = struct();
            obj.query_ = struct();
            obj.highlight_ = struct();
        end

        function initGuiState_(obj)
            %INITGUISTATE_ Skeleton GUI-state initialisation.
            %   Subclasses should override this to set up viewer-specific GUI
            %   fields; call the superclass method first if the common view
            %   state is needed.
            obj.gui_ = struct();
            views = obj.viewNames_();
            if isfield(obj.Opts, 'general') && isfield(obj.Opts.general, 'view')
                obj.gui_.viewIdx = find(strcmpi(views, char(string(obj.Opts.general.view))), 1);
            else
                obj.gui_.viewIdx = [];
            end
            if isempty(obj.gui_.viewIdx)
                obj.gui_.viewIdx = 1;
            end
            obj.gui_.ssaaFactor = obj.getOptField_(obj.Opts.polyscope, 'ssaaFactor', 2);
        end

        function name = structName_(obj, base, prefix)
            if nargin < 3 || isempty(prefix)
                prefix = '';
            end
            topPrefix = char(string(obj.Opts.polyscope.name));
            displayBase = obj.displayBaseName_(base);
            displayPrefix = obj.displayPrefix_(prefix);
            parts = {};
            if ~isempty(topPrefix), parts{end+1} = topPrefix; end
            if ~isempty(displayPrefix), parts{end+1} = displayPrefix; end
            if ~isempty(displayBase), parts{end+1} = displayBase; end
            if isempty(parts)
                name = '';
            else
                name = strjoin(parts, ' ');
            end
        end

        function p = displayPrefix_(~, prefix)
            %DISPLAYPREFIX_ Map internal prefixes to user-friendly labels.
            if isempty(prefix)
                p = '';
                return;
            end
            switch char(string(prefix))
                case {'def', ''}
                    p = '';
                case 'ghost'
                    p = 'Undeformed';
                case 'ghostWire'
                    p = 'Undeformed wireframe';
                case 'wire'
                    p = 'Wireframe';
                case 'frame'
                    p = 'Frame';
                otherwise
                    p = char(string(prefix));
            end
        end

        function db = displayBaseName_(obj, base)
            %DISPLAYBASENAME_ Return user-friendly display name for a structure.
            %   Users can customize via opts.polyscope.displayNames.(base).
            %   Element class names are shown as-is from the data.
            dn = obj.getOptField_(obj.Opts.polyscope, 'displayNames', struct());
            if isstruct(dn) && isfield(dn, base) && ~isempty(dn.(base))
                db = char(string(dn.(base)));
                return;
            end
            b = char(string(base));
            % Generic suffix rules for family-specific helpers (e.g. BeamEdges -> Beam edges,
            % ShellGhost -> Shell edges).  Keep the literal base for short names.
            if numel(b) > 5 && strcmpi(b(end-4:end), 'Edges')
                db = [b(1:end-5) ' edges'];
            elseif numel(b) > 5 && strcmpi(b(end-4:end), 'Ghost')
                db = [b(1:end-5) ' edges'];
            elseif numel(b) > 4 && strcmpi(b(end-3:end), 'Wire')
                db = [b(1:end-4) ' wireframe'];
            else
                db = b;
            end
        end

        function key = structKey_(obj, base, prefix)
            %STRUCTKEY_ Return a valid MATLAB field name for internal query maps.
            %   Based on the display name from structName_, but safe for dynamic
            %   field access (no spaces or other invalid characters).
            if nargin < 3, prefix = ''; end
            key = obj.validQueryKey_(obj.structName_(base, prefix));
        end

        function key = validQueryKey_(~, name)
            %VALIDQUERYKEY_ Convert any structure name to a valid field name.
            key = matlab.lang.makeValidName(char(string(name)));
        end

        function val = getOptField_(~, S, fieldName, fallback)
            val = fallback;
            if isstruct(S) && isfield(S, fieldName) && ~isempty(S.(fieldName))
                val = S.(fieldName);
            end
        end

        function value = pickExisting_(~, items, value)
            if isempty(items)
                value = '';
                return;
            end
            idx = find(strcmpi(items, char(string(value))), 1);
            if isempty(idx)
                value = items{1};
            else
                value = items{idx};
            end
        end

        function idx = indexOf_(~, items, value)
            idx = find(strcmpi(items, char(string(value))), 1);
            if isempty(idx)
                idx = 1;
            end
        end

        function tf = guiChanged_(obj, oldState, names)
            tf = false;
            for i = 1:numel(names)
                nm = names{i};
                if ~isfield(oldState, nm) || ~isfield(obj.gui_, nm)
                    tf = true;
                    return;
                end
                oldVal = oldState.(nm);
                newVal = obj.gui_.(nm);
                if isnumeric(oldVal) || islogical(oldVal)
                    if ~isequal(size(oldVal), size(newVal)) || ...
                            any(abs(double(oldVal(:)) - double(newVal(:))) > eps)
                        tf = true;
                        return;
                    end
                elseif ~isequal(oldVal, newVal)
                    tf = true;
                    return;
                end
            end
        end

        function ws = safeWindowSize_(obj, fallback)
            if nargin < 2 || isempty(fallback)
                fallback = [1280, 720];
            end
            % Several GUI helpers request the window size during the same
            % frame. Cache briefly to avoid repeated MATLAB/MEX crossings while
            % retaining responsive resize behaviour.
            if ~isempty(obj.windowSizeCache_) && ~isempty(obj.windowSizeCacheTimer_)
                try
                    if toc(obj.windowSizeCacheTimer_) < 0.05
                        ws = obj.windowSizeCache_;
                        return;
                    end
                catch
                end
            end
            ws = double(fallback(:).');
            try
                raw = double(obj.App.polyscopeHandle().get_window_size());
                raw = raw(:).';
                if numel(raw) >= 2 && all(isfinite(raw(1:2))) && all(raw(1:2) > 0)
                    ws = raw(1:2);
                end
            catch
            end
            ws(1) = max(640, ws(1));
            ws(2) = max(420, ws(2));
            obj.windowSizeCache_ = ws;
            obj.windowSizeCacheTimer_ = tic;
        end

        function rgb = asRgb_(~, c)
            rgb = double(c(:).');
            if isempty(rgb)
                rgb = [1, 1, 1];
            end
            if numel(rgb) < 3
                rgb = [rgb, repmat(rgb(end), 1, 3 - numel(rgb))];
            end
            rgb = rgb(1:3);
            if any(rgb > 1)
                rgb = rgb / 255;
            end
            rgb = max(0, min(1, rgb));
        end

        function names = colormapNames_(~)
            names = {'viridis', 'blues', 'reds', 'coolwarm', 'pink-green', ...
                     'phase', 'spectral', 'rainbow', 'jet', 'turbo'};
        end

        function fps = defaultAnimationFps_(~, nSteps)
            % Target roughly a 20-second pass, bounded for usability and by
            % the default interactive render-loop limit.
            fps = max(5, min(60, round(double(max(1, nSteps)) / 20)));
        end

        function initColorbarGuiState_(obj, defaultTitle)
            if nargin < 2
                defaultTitle = '';
            end
            obj.gui_.onscreenColorbar = obj.getOptField_(obj.Opts.polyscope, ...
                'onscreenColorbar', false);
            obj.gui_.onscreenColorbarLocation = obj.getOptField_(obj.Opts.polyscope, ...
                'onscreenColorbarLocation', []);
            obj.gui_.colorbarTitle = char(string(obj.getOptField_(obj.Opts.polyscope, ...
                'colorbarTitle', defaultTitle)));
        end

        function changed = drawColorbarGui_(obj, idSuffix, includeTitle)
            if nargin < 2 || isempty(idSuffix), idSuffix = ''; end
            if nargin < 3, includeTitle = true; end
            changed = false;
            labelSuffix = char(string(idSuffix));
            oldState = obj.gui_;
            GB = plotter.polyscope.GuiBuilder;
            obj.gui_.onscreenColorbar = GB.checkbox(['Colorbar' labelSuffix], obj.gui_.onscreenColorbar);
            obj.Opts.polyscope.onscreenColorbar = logical(obj.gui_.onscreenColorbar);
            if obj.gui_.onscreenColorbar
                loc = obj.gui_.onscreenColorbarLocation;
                if numel(loc) < 2 || any(~isfinite(loc))
                    loc = [1200, 800];
                end
                [moved, loc] = polyscope.ImGui.InputFloat2(['Colorbar pos' labelSuffix], double(loc(:).'));
                if moved
                    obj.gui_.onscreenColorbarLocation = loc;
                    obj.Opts.polyscope.onscreenColorbarLocation = loc;
                end
                if includeTitle
                    title = char(string(obj.gui_.colorbarTitle));
                    [tchg, title] = polyscope.ImGui.InputText(['Colorbar title' labelSuffix], title);
                    if tchg
                        obj.gui_.colorbarTitle = title;
                        obj.Opts.polyscope.colorbarTitle = title;
                    end
                end
            end
            fields = {'onscreenColorbar','onscreenColorbarLocation','colorbarTitle'};
            for i = 1:numel(fields)
                nm = fields{i};
                if isfield(oldState, nm) && isfield(obj.gui_, nm) && ~isequal(oldState.(nm), obj.gui_.(nm))
                    changed = true;
                    return;
                end
            end
        end

        function cb = colorbarArgs_(obj)
            cb = {};
            if ~obj.getOptField_(obj.Opts.polyscope, 'onscreenColorbar', false)
                return;
            end
            cb = {'onscreen_colorbar_enabled', true};
            loc = obj.getOptField_(obj.Opts.polyscope, 'onscreenColorbarLocation', []);
            if ~isempty(loc) && numel(loc) == 2 && all(isfinite(loc))
                cb = [cb, {'onscreen_colorbar_location', double(loc(:).')}];
            end
        end

        function changed = drawSsaaGui_(obj, idSuffix)
            %DRAWSSAAGUI_ Draw a shared SSAA control and apply it immediately.
            if nargin < 2 || isempty(idSuffix)
                idSuffix = '';
            end
            changed = false;
            GB = plotter.polyscope.GuiBuilder;
            if ~isfield(obj.gui_, 'ssaaFactor') || isempty(obj.gui_.ssaaFactor)
                obj.gui_.ssaaFactor = obj.getOptField_(obj.Opts.polyscope, 'ssaaFactor', 2);
            end
            oldVal = obj.gui_.ssaaFactor;
            obj.gui_.ssaaFactor = GB.sliderInt(['SSAA' char(string(idSuffix))], ...
                obj.gui_.ssaaFactor, 1, 4);
            if obj.gui_.ssaaFactor ~= oldVal
                obj.gui_.ssaaFactor = max(1, min(4, round(double(obj.gui_.ssaaFactor))));
                obj.Opts.polyscope.ssaaFactor = obj.gui_.ssaaFactor;
                try
                    obj.App.setSSAAFactor(obj.gui_.ssaaFactor);
                catch
                end
                changed = true;
            end
        end

        function initSliceGuiState_(obj)
            if ~isfield(obj.Opts, 'slice') || isempty(obj.Opts.slice)
                obj.Opts.slice = struct();
            end
            obj.normalizeSliceOpts_();
            n = numel(obj.Opts.slice.planes);
            obj.gui_.slicePlaneIdx = 1;
            obj.gui_.slicePlanes = repmat(obj.emptySliceGuiPlane_(), 0);
            for i = 1:n
                obj.gui_.slicePlanes(i) = obj.slicePlaneOptsToGui_(obj.Opts.slice.planes(i));
            end
        end

        function g = emptySliceGuiPlane_(~)
            g = struct('show', false, 'drawPlane', true, 'drawWidget', false, ...
                       'center', [0, 0, 0], 'normal', [0, 0, 1], ...
                       'widgetSize', 0.75, 'transparency', 0.45, ...
                       'color', [0.90, 0.35, 0.55], 'gridColor', [1, 1, 1], ...
                       'cullWholeElements', false);
        end

        function g = slicePlaneOptsToGui_(obj, p)
            g.show = logical(obj.getOptField_(p, 'show', false));
            g.drawPlane = logical(obj.getOptField_(p, 'drawPlane', true));
            g.drawWidget = logical(obj.getOptField_(p, 'drawWidget', false));
            g.center = obj.resolveSliceCenterForPlane_(p);
            n = double(obj.getOptField_(p, 'normal', [0, 0, 1]));
            n = n(:).';
            if ~all(isfinite(n)) || norm(n) <= 1e-12
                n = [0, 0, 1];
            end
            g.normal = n;
            g.widgetSize = double(obj.getOptField_(p, 'widgetSize', 0.75));
            g.transparency = double(obj.getOptField_(p, 'transparency', 0.45));
            g.color = plotter.polyscope.utils.colorToRgb(obj.getOptField_(p, 'color', [0.90, 0.35, 0.55]));
            g.gridColor = plotter.polyscope.utils.colorToRgb(obj.getOptField_(p, 'gridColor', [1, 1, 1]));
            g.cullWholeElements = logical(obj.getOptField_(p, 'cullWholeElements', false));
        end

        function normalizeSliceOpts_(obj)
            if ~isfield(obj.Opts, 'slice') || isempty(obj.Opts.slice)
                obj.Opts.slice = struct();
            end
            s = obj.Opts.slice;
            if ~isstruct(s)
                s = struct();
            end
            defaults = struct('name', 'Slice plane', ...
                              'show', false, ...
                              'center', [], ...
                              'normal', [0, 0, 1], ...
                              'drawPlane', true, ...
                              'drawWidget', false, ...
                              'widgetSize', 0.75, ...
                              'color', [0.90, 0.35, 0.55], ...
                              'gridColor', [1, 1, 1], ...
                              'transparency', 0.45, ...
                              'cullWholeElements', false);
            fields = fieldnames(defaults);
            % Legacy scalar slice options -> wrap into planes(1)
            if ~isfield(s, 'planes')
                plane = defaults;
                for k = 1:numel(fields)
                    f = fields{k};
                    if isfield(s, f) && ~isempty(s.(f))
                        plane.(f) = s.(f);
                    end
                end
                s.planes = plane;
            end
            if isempty(s.planes)
                obj.Opts.slice = s;
                return;
            end
            % Ensure every plane has all fields and a valid name
            for i = 1:numel(s.planes)
                for k = 1:numel(fields)
                    f = fields{k};
                    if ~isfield(s.planes(i), f) || isempty(s.planes(i).(f))
                        s.planes(i).(f) = defaults.(f);
                    end
                end
                nm = char(string(s.planes(i).name));
                if isempty(nm)
                    s.planes(i).name = sprintf('Slice plane %d', i);
                else
                    s.planes(i).name = nm;
                end
            end
            obj.Opts.slice = s;
        end

        function r = absRadius_(obj, rel)
            r = double(rel) * obj.L_;
        end

        function c = geometryCenter_(~, P)
            if isempty(P)
                c = [0, 0, 0];
                return;
            end
            c = (min(P, [], 1, 'omitnan') + max(P, [], 1, 'omitnan')) / 2;
            if any(~isfinite(c))
                c = [0, 0, 0];
            end
        end

        function L = modelLength_(~, P)
            if isempty(P)
                L = 1;
                return;
            end
            ext = max(P, [], 1, 'omitnan') - min(P, [], 1, 'omitnan');
            L = max(ext(isfinite(ext)));
            if isempty(L) || ~isfinite(L) || L <= 0
                L = 1;
            end
        end

        function tf = is2DPoints_(~, P)
            tf = false;
            if isempty(P) || size(P, 2) < 3
                return;
            end
            z = P(:, 3);
            z = z(isfinite(z));
            if isempty(z)
                return;
            end
            tf = (max(z) - min(z)) <= 1e-10 * max(1, max(abs(z)));
        end

        function tf = is2DModel_(obj)
            P = plotter.polyscope.ModelAdapter.nodeCoords(obj.ModelInfo);
            if isempty(P)
                tf = false;
                return;
            end
            z = P(:, 3);
            z = z(isfinite(z));
            if isempty(z)
                tf = false;
                return;
            end
            span = max(z) - min(z);
            scale = max(1, max(abs(z)));
            tf = span <= 1e-10 * scale;
        end

        function setDefaultCamera_(obj)
            if isfield(obj.Opts, 'general') && isfield(obj.Opts.general, 'view')
                obj.setCameraView_(obj.Opts.general.view);
            else
                obj.setCameraView_('3D');
            end
        end

        function setCameraView_(obj, name)
            P = plotter.polyscope.ModelAdapter.nodeCoords(obj.ModelInfo);
            if isempty(P), return; end
            mn = min(P, [], 1, 'omitnan');
            mx = max(P, [], 1, 'omitnan');
            target = (mn + mx) / 2;
            L = max(mx - mn);
            if ~isfinite(L) || L <= 0, L = 1; end
            r = L * 2.5;

            viewName = lower(char(string(name)));
            isPlaneView = any(strcmp(viewName, {'xy', 'xz', 'yz', 'yx', 'zx', 'zy'}));
            if isPlaneView
                obj.setNavigationStyle_('turntable');
            end

            switch viewName
                case 'xy'
                    eye = target + [0, 0, r];
                    up = [0, 1, 0];
                case 'xz'
                    eye = target + [0, -r, 0];
                    up = [0, 0, 1];
                case 'yz'
                    eye = target + [r, 0, 0];
                    up = [0, 0, 1];
                case 'yx'
                    eye = target + [0, 0, -r];
                    up = [1, 0, 0];
                case 'zx'
                    eye = target + [0, r, 0];
                    up = [1, 0, 0];
                case 'zy'
                    eye = target + [-r, 0, 0];
                    up = [0, 1, 0];
                otherwise
                    eye = target + [r * cosd(-37.5) * cosd(30), ...
                                    -r * sind(-37.5) * cosd(30), ...
                                    r * sind(30)];
                    up = [0, 0, 1];
            end

            if ~isPlaneView
                obj.setUpDir_(obj.upDirNameForVector_(up));
            end
            obj.setSceneScaleForPoints_(P);
            if isPlaneView
                obj.App.setProjectionMode('orthographic');
                obj.setPlaneViewFov_();
                obj.setNavigationStyle_('planar');
            else
                obj.App.setProjectionMode('perspective');
                obj.setPerspectiveViewFov_();
                obj.setNavigationStyle_('turntable');
            end

            viewMat = obj.cameraViewMatrix_(eye, target, up);
            obj.App.setCameraViewMatrix(viewMat);
            obj.App.setViewCenter(target);
            try
                obj.App.polyscopeHandle().request_redraw();
            catch
            end
        end

        function setSceneScaleForPoints_(obj, P)
            if isempty(P), return; end
            mn = min(P, [], 1, 'omitnan');
            mx = max(P, [], 1, 'omitnan');
            ext = mx - mn;
            L = max(ext);
            if ~isfinite(L) || L <= 0, L = 1; end
            pad = max(0.05 * L, eps(max(1, L)) * 32);
            low = mn - pad;
            high = mx + pad;
            thin = (high - low) <= eps(max(1, L)) * 64;
            center = (mn + mx) / 2;
            low(thin) = center(thin) - pad;
            high(thin) = center(thin) + pad;
            try
                ps = obj.App.polyscopeHandle();
                ps.set_length_scale(L);
                ps.set_bounding_box(low, high);
                ps.update_scene_extents();
            catch
            end
        end

        function setCameraForPoints_(obj, P, viewName)
            if isempty(P)
                return;
            end
            mn = min(P, [], 1, 'omitnan');
            mx = max(P, [], 1, 'omitnan');
            target = (mn + mx) / 2;
            L = max(mx - mn);
            if ~isfinite(L) || L <= 0
                L = 1;
            end
            r = L * 2.5;
            viewName = lower(char(string(viewName)));
            if strcmp(viewName, 'auto')
                viewName = '3d';
            end
            switch viewName
                case 'xy'
                    eye = target + [0, 0, r];
                    up = [0, 1, 0];
                    obj.App.setProjectionMode('orthographic');
                    obj.setPlaneViewFov_();
                    obj.setNavigationStyle_('planar');
                case 'yx'
                    eye = target + [0, 0, -r];
                    up = [1, 0, 0];
                    obj.App.setProjectionMode('orthographic');
                    obj.setPlaneViewFov_();
                    obj.setNavigationStyle_('planar');
                case 'xz'
                    eye = target + [0, -r, 0];
                    up = [0, 0, 1];
                    obj.App.setProjectionMode('orthographic');
                    obj.setPlaneViewFov_();
                    obj.setNavigationStyle_('planar');
                case 'zx'
                    eye = target + [0, r, 0];
                    up = [1, 0, 0];
                    obj.App.setProjectionMode('orthographic');
                    obj.setPlaneViewFov_();
                    obj.setNavigationStyle_('planar');
                case 'yz'
                    eye = target + [r, 0, 0];
                    up = [0, 0, 1];
                    obj.App.setProjectionMode('orthographic');
                    obj.setPlaneViewFov_();
                    obj.setNavigationStyle_('planar');
                case 'zy'
                    eye = target + [-r, 0, 0];
                    up = [0, 1, 0];
                    obj.App.setProjectionMode('orthographic');
                    obj.setPlaneViewFov_();
                    obj.setNavigationStyle_('planar');
                otherwise
                    eye = target + [r * cosd(-37.5) * cosd(30), ...
                                    -r * sind(-37.5) * cosd(30), ...
                                     r * sind(30)];
                    up = [0, 0, 1];
                    obj.App.setProjectionMode('perspective');
                    obj.setPerspectiveViewFov_();
                    obj.setNavigationStyle_('turntable');
            end
            isPlaneView = any(strcmp(viewName, {'xy', 'xz', 'yz', 'yx', 'zx', 'zy'}));
            if ~isPlaneView
                obj.setUpDir_(obj.upDirNameForVector_(up));
            end
            obj.setSceneScaleForPoints_(P);
            viewMat = obj.cameraViewMatrix_(eye, target, up);
            obj.App.setCameraViewMatrix(viewMat);
            obj.App.setViewCenter(target);
            try
                obj.App.polyscopeHandle().request_redraw();
            catch
            end
        end

        function state = animationPlaneCameraState_(obj)
            state = [];
            try
                if ~isfield(obj.gui_, 'animationMode') || ~obj.gui_.animationMode
                    return;
                end
                if ~isfield(obj.Opts, 'general') || ~isfield(obj.Opts.general, 'view') || ...
                        ~obj.isPlaneView_(obj.Opts.general.view)
                    return;
                end
                ps = obj.App.polyscopeHandle();
                state.viewMat = double(ps.get_camera_view_matrix());
                state.center = double(ps.get_view_center());
            catch
                state = [];
            end
        end

        function restoreCameraState_(obj, state)
            if isempty(state) || ~isstruct(state)
                return;
            end
            try
                if isfield(state, 'viewMat') && all(size(state.viewMat) >= [3, 4])
                    viewMat = state.viewMat;
                    if size(viewMat, 1) == 3
                        viewMat = [viewMat(1:3, 1:4); 0, 0, 0, 1];
                    end
                    obj.App.setCameraViewMatrix(viewMat);
                end
                if isfield(state, 'center') && numel(state.center) >= 3 && all(isfinite(state.center(1:3)))
                    obj.App.setViewCenter(state.center(1:3));
                end
                obj.App.polyscopeHandle().request_redraw();
            catch
            end
        end

        function tf = isPlaneView_(~, viewName)
            tf = any(strcmpi(char(string(viewName)), {'xy', 'xz', 'yz', 'yx', 'zx', 'zy'}));
        end

        function names = viewNames_(~)
            names = {'3D', 'XY', 'XZ', 'YZ', 'YX', 'ZX', 'ZY'};
        end

        function viewMat = cameraViewMatrix_(obj, eye, target, up)
            eye = double(eye(:)).';
            target = double(target(:)).';
            up = obj.normalizeRow_(up);

            f = obj.normalizeRow_(target - eye);
            if norm(f) <= 0
                f = [0, 0, -1];
            end

            right = cross(f, up);
            if norm(right) <= 1e-12
                up = obj.fallbackUp_(f);
                right = cross(f, up);
            end
            right = obj.normalizeRow_(right);
            camUp = obj.normalizeRow_(cross(right, f));

            viewMat = [right(1), right(2), right(3), -dot(right, eye); ...
                       camUp(1), camUp(2), camUp(3), -dot(camUp, eye); ...
                       -f(1),    -f(2),    -f(3),     dot(f, eye); ...
                       0,        0,        0,         1];
        end

        function setupWindowIcon_(obj)
            try
                candidates = {'logo.png', 'OpenSeesMatlab/logo.png', ...
                              '../OpenSeesMatlab/logo.png', '../logo.png'};
                logoPath = '';
                for k = 1:numel(candidates)
                    if isfile(candidates{k})
                        logoPath = candidates{k};
                        break;
                    end
                end
                if isempty(logoPath)
                    classPath = mfilename('fullpath');
                    pkgRoot = fileparts(fileparts(fileparts(classPath)));
                    logoPath = fullfile(pkgRoot, 'logo.png');
                    if ~isfile(logoPath)
                        return;
                    end
                end
                obj.App.polyscopeHandle().set_window_icon(logoPath);
            catch
            end
        end

        function drawScreenAxesOverlay_(obj)
            if ~obj.getOptField_(obj.Opts.polyscope, 'showScreenAxes', true)
                return;
            end
            if isfield(obj.gui_, 'showScreenAxes') && ~obj.gui_.showScreenAxes
                return;
            end

            try
                io = polyscope.ImGui.GetIO();
                displaySize = double(io.DisplaySize);
                if numel(displaySize) < 2 || any(~isfinite(displaySize(1:2))) || ...
                        any(displaySize(1:2) <= 0)
                    return;
                end

                dl = polyscope.ImGui.GetForegroundDrawList();
                sizePx = double(obj.getOptField_(obj.Opts.polyscope, 'screenAxesSize', 58));
                sizePx = max(36, min(110, sizePx));
                margin = 28;
                leftPanelW = min(420, displaySize(1) * 0.22);
                origin = [leftPanelW + margin + sizePx, displaySize(2) - margin - sizePx];

                bg = double(polyscope.ImGui.GetColorU32Vec4([1, 1, 1, 0.55]));
                border = double(polyscope.ImGui.GetColorU32Vec4([0.15, 0.15, 0.15, 0.35]));
                dl.AddCircleFilled(origin, sizePx * 0.72, bg, 32);
                dl.AddCircle(origin, sizePx * 0.72, border, 32, 1.0);

                dirs = obj.screenAxisDirections_();
                axes = {'X', 'Y', 'Z'};
                colors = [0.88, 0.12, 0.10, 1.0; ...
                          0.10, 0.62, 0.18, 1.0; ...
                          0.12, 0.32, 0.92, 1.0];
                for ia = 1:3
                    obj.drawScreenAxisArrow_(dl, origin, dirs(ia, :), sizePx, ...
                        double(polyscope.ImGui.GetColorU32Vec4(colors(ia, :))), axes{ia});
                end
            catch
            end
        end

        function dirs = screenAxisDirections_(obj)
            dirs = [1, 0; 0, -1; 0, 0];
            try
                viewMat = double(obj.App.polyscopeHandle().get_camera_view_matrix());
                if all(size(viewMat) >= [3, 3])
                    right = viewMat(1, 1:3);
                    up = viewMat(2, 1:3);
                    worldAxes = eye(3);
                    for ia = 1:3
                        v = worldAxes(ia, :);
                        d = [dot(v, right), -dot(v, up)];
                        if all(isfinite(d))
                            dirs(ia, :) = d;
                        end
                    end
                end
            catch ME
                fprintf('screenAxisDirections_ error: %s\n', ME.message);
            end
        end

        function drawScreenAxisArrow_(~, dl, origin, dir2, sizePx, color, label)
            dir2 = double(dir2(:)).';
            if numel(dir2) < 2
                return;
            end
            n = norm(dir2(1:2));
            if n <= 0.18
                dl.AddCircleFilled(origin, sizePx * 0.13, color, 12);
                dl.AddText(origin + [sizePx * 0.16, -sizePx * 0.12], color, label);
                return;
            end
            dir2 = dir2(1:2) ./ n;
            len = 0.62 * sizePx * min(1.0, n);
            tip = origin + len * dir2;
            base = origin + 0.14 * sizePx * dir2;
            perp = [-dir2(2), dir2(1)];
            headLen = 0.18 * sizePx;
            headHalf = 0.08 * sizePx;
            p1 = tip;
            p2 = tip - headLen * dir2 + headHalf * perp;
            p3 = tip - headLen * dir2 - headHalf * perp;

            dl.AddLine(base, tip, color, 2.2);
            dl.AddTriangleFilled(p1, p2, p3, color);
            dl.AddText(tip + 5 * dir2 + [-4, -7], color, label);
        end

        function drawModelInfoWindow_(obj)
            if ~obj.getOptField_(obj.Opts.polyscope, 'showModelInfo', false)
                return;
            end
            if ~isfield(obj.gui_, 'modelStats')
                return;
            end
            try
                io = polyscope.ImGui.GetIO();
                ws = double(io.DisplaySize);
                if numel(ws) < 2 || any(~isfinite(ws(1:2))) || any(ws(1:2) <= 0)
                    return;
                end

                margin = 16;
                rightPanelW = 340;
                width = 200;
                height = 72;
                pos = [ws(1) - rightPanelW - margin - width, ws(2) - height - margin];
                cond = int32(polyscope.ImGui.get_constant('ImGuiCond_FirstUseEver'));
                polyscope.ImGui.SetNextWindowPos(pos, cond, [0, 0]);
                polyscope.ImGui.SetNextWindowSize([width, height], cond);

                flags = int32(0);
                visible = polyscope.ImGui.Begin('Model Info', flags);
                if visible
                    try
                        stats = obj.gui_.modelStats;
                        polyscope.ImGui.Text(sprintf('Nodes: %d', stats.nNodes));
                        polyscope.ImGui.Text(sprintf('Elements: %d', stats.nElements));
                    catch ME_inner
                        fprintf('drawModelInfoWindow_ content error: %s\n', ME_inner.message);
                    end
                end
                polyscope.ImGui.End();
            catch ME
                fprintf('drawModelInfoWindow_ error: %s\n', ME.message);
            end
        end

        function stats = computeModelStats_(obj)
            stats = struct('nNodes', 0, 'nElements', 0);
            P = plotter.polyscope.ModelAdapter.nodeCoords(obj.ModelInfo);
            if ~isempty(P)
                stats.nNodes = size(P, 1);
            end
            if obj.hasElementClasses_()
                C = obj.elementClasses_();
                names = fieldnames(C);
                for k = 1:numel(names)
                    S = C.(names{k});
                    if isstruct(S) && isfield(S, 'Cells') && ~isempty(S.Cells)
                        stats.nElements = stats.nElements + size(S.Cells, 1);
                    end
                end
            else
                fam = plotter.polyscope.ModelAdapter.families(obj.ModelInfo);
                familyNames = [plotter.polyscope.ModelAdapter.lineFamilyNames(), ...
                               plotter.polyscope.ModelAdapter.surfaceFamilyNames(), ...
                               plotter.polyscope.ModelAdapter.volumeFamilyNames()];
                for k = 1:numel(familyNames)
                    name = familyNames{k};
                    if isfield(fam, name) && isstruct(fam.(name)) && ...
                            isfield(fam.(name), 'Cells') && ~isempty(fam.(name).Cells)
                        stats.nElements = stats.nElements + size(fam.(name).Cells, 1);
                    end
                end
            end
        end

        function registerSlicePlanes_(obj)
            if ~isfield(obj.Opts, 'slice') || isempty(obj.Opts.slice)
                return;
            end
            obj.normalizeSliceOpts_();
            try
                ps = obj.App.polyscopeHandle();
                planes = obj.Opts.slice.planes;
                desiredNames = cell(numel(planes), 1);
                for i = 1:numel(planes)
                    name = char(string(planes(i).name));
                    if isempty(name)
                        name = sprintf('Slice plane %d', i);
                    end
                    desiredNames{i} = name;
                    hasPlane = ps.has_slice_plane(name);
                    if ~planes(i).show && ~hasPlane
                        continue;
                    end
                    if hasPlane
                        sp = ps.get_slice_plane(name);
                    else
                        sp = ps.add_slice_plane(name);
                    end
                    obj.configureSlicePlane_(sp, planes(i));
                end
                % Remove Polyscope planes that are no longer in our list
                if ~isfield(obj.handles_, 'SlicePlanes')
                    obj.handles_.SlicePlanes = {};
                end
                toRemove = {};
                for k = 1:numel(obj.handles_.SlicePlanes)
                    oldName = obj.handles_.SlicePlanes{k}{1};
                    if ~ismember(oldName, desiredNames)
                        toRemove{end+1} = oldName; %#ok<AGROW>
                    end
                end
                for k = 1:numel(toRemove)
                    try ps.remove_slice_plane(toRemove{k}); catch, end
                end
                % Rebuild handles list
                obj.handles_.SlicePlanes = {};
                for i = 1:numel(planes)
                    name = desiredNames{i};
                    if ps.has_slice_plane(name)
                        obj.handles_.SlicePlanes{end+1} = {name, ps.get_slice_plane(name)};
                    end
                end
            catch
            end
        end

        function configureSlicePlane_(obj, sp, planeOpts)
            sp.set_enabled(logical(planeOpts.show));
            center = obj.resolveSliceCenterForPlane_(planeOpts);
            normal = double(planeOpts.normal(:)).';
            if ~all(isfinite(normal)) || norm(normal) <= 1e-12
                normal = [0, 0, 1];
            end
            sp.set_pose(center, normal);
            sp.set_draw_plane(logical(planeOpts.drawPlane));
            sp.set_draw_widget(logical(planeOpts.drawWidget));
            try
                sp.set_widget_size(double(obj.getOptField_(planeOpts, 'widgetSize', 0.75)));
            catch
            end
            sp.set_color(obj.asRgb_(plotter.polyscope.utils.colorToRgb(planeOpts.color)));
            sp.set_grid_line_color(obj.asRgb_(plotter.polyscope.utils.colorToRgb(planeOpts.gridColor)));
            sp.set_transparency(double(planeOpts.transparency));
        end

        function applySlicePlane_(obj)
            if ~isfield(obj.Opts, 'slice') || isempty(obj.Opts.slice)
                return;
            end
            obj.registerSlicePlanes_();
            obj.applySliceCullWholeElements_();
            try
                obj.App.polyscopeHandle().request_redraw();
            catch
            end
        end

        function sliceDirty = drawSlicePlaneGui_(obj, idSuffix)
            if nargin < 2 || isempty(idSuffix), idSuffix = ''; end
            sliceDirty = false;
            if ~isfield(obj.Opts, 'slice') || isempty(obj.Opts.slice)
                return;
            end
            obj.normalizeSliceOpts_();
            GB = plotter.polyscope.GuiBuilder;
            suffix = char(string(idSuffix));
            if startsWith(suffix, '##')
                suffix = suffix(3:end);
            end
            if isempty(suffix)
                tag = '';
            else
                tag = ['_' suffix];
            end
            if ~GB.collapsingHeader(['Slice planes##slice_header' tag], int32(0))
                return;
            end
            n = numel(obj.Opts.slice.planes);
            % Add / Remove buttons
            if GB.button(['Add plane##slice_add' tag])
                obj.addSlicePlane_();
                sliceDirty = true;
                n = numel(obj.Opts.slice.planes);
                if obj.gui_.slicePlaneIdx > n
                    obj.gui_.slicePlaneIdx = n;
                end
            end
            if n > 0
                GB.sameLine();
                if GB.button(['Remove plane##slice_remove' tag])
                    obj.removeSlicePlaneByIdx_(obj.gui_.slicePlaneIdx);
                    sliceDirty = true;
                    n = numel(obj.Opts.slice.planes);
                    if obj.gui_.slicePlaneIdx > n
                        obj.gui_.slicePlaneIdx = max(1, n);
                    end
                end
            end
            if n == 0
                return;
            end
            % Active-plane selector
            names = cell(n, 1);
            for i = 1:n
                names{i} = char(string(obj.Opts.slice.planes(i).name));
            end
            oldIdx = obj.gui_.slicePlaneIdx;
            if oldIdx < 1 || oldIdx > n
                oldIdx = 1;
                obj.gui_.slicePlaneIdx = 1;
            end
            obj.gui_.slicePlaneIdx = GB.combo(['Active plane##slice_active' tag], obj.gui_.slicePlaneIdx, names);
            if obj.gui_.slicePlaneIdx ~= oldIdx
                obj.syncGuiSlicePlaneFromOpts_(obj.gui_.slicePlaneIdx);
            end
            idx = obj.gui_.slicePlaneIdx;
            g = obj.gui_.slicePlanes(idx);
            % ---- per-plane controls ----
            tf = GB.checkbox(['Enable##slice_enable' tag], g.show);
            if tf ~= g.show
                g.show = tf;
                sliceDirty = true;
            end
            GB.sameLine();
            tf = GB.checkbox(['Draw plane##slice_drawplane' tag], g.drawPlane);
            if tf ~= g.drawPlane
                g.drawPlane = tf;
                sliceDirty = true;
            end
            GB.sameLine();
            tf = GB.checkbox(['Draw widget##slice_drawwidget' tag], g.drawWidget);
            if tf ~= g.drawWidget
                g.drawWidget = tf;
                sliceDirty = true;
            end
            c = GB.inputFloat3(['Center##slice_center' tag], g.center);
            if any(abs(c - g.center) > eps)
                g.center = c;
                sliceDirty = true;
            end
            if GB.button(['Center at model##slice_centermodel' tag])
                g.center = obj.defaultSliceCenter_();
                sliceDirty = true;
            end
            nrm = GB.inputFloat3(['Normal##slice_normal' tag], g.normal);
            if any(abs(nrm - g.normal) > eps)
                g.normal = nrm;
                sliceDirty = true;
            end
            sz = GB.sliderFloat(['Widget size##slice_widget' tag], g.widgetSize, 0.25, 2.00);
            if abs(sz - g.widgetSize) > eps
                g.widgetSize = sz;
                sliceDirty = true;
            end
            a = GB.sliderFloat(['Slice alpha##slice_alpha' tag], g.transparency, 0.0, 1.0);
            if abs(a - g.transparency) > eps
                g.transparency = a;
                sliceDirty = true;
            end
            [cchg, g.color] = GB.colorEdit3(['Slice color##slice_color' tag], g.color);
            if cchg
                sliceDirty = true;
            end
            [cchg, g.gridColor] = GB.colorEdit3(['Grid color##slice_gridcolor' tag], g.gridColor);
            if cchg
                sliceDirty = true;
            end
            tf = GB.checkbox(['Cull whole elements##slice_cull' tag], g.cullWholeElements);
            if tf ~= g.cullWholeElements
                g.cullWholeElements = tf;
                sliceDirty = true;
            end
            % Write back
            obj.gui_.slicePlanes(idx) = g;
            obj.syncOptsSlicePlaneFromGui_(idx);
        end

        function applySliceCullWholeElements_(obj)
            if ~isfield(obj.Opts, 'slice') || isempty(obj.Opts.slice)
                return;
            end
            obj.normalizeSliceOpts_();
            val = false;
            for i = 1:numel(obj.Opts.slice.planes)
                if logical(obj.getOptField_(obj.Opts.slice.planes(i), 'cullWholeElements', false))
                    val = true;
                    break;
                end
            end
            names = fieldnames(obj.handles_);
            ps = obj.App.polyscopeHandle();
            for k = 1:numel(names)
                try
                    ps.set_structure_cull_whole_elements(names{k}, val);
                catch
                end
            end
        end

        function registerScreenAxes3D_(obj)
            if ~obj.getOptField_(obj.Opts.polyscope, 'showScreenAxes', true)
                return;
            end
            if obj.isOverlayScreenAxes_()
                return;
            end
            if obj.getOptField_(obj.Opts.polyscope, 'useScreenAxesGizmo', true)
                obj.registerScreenAxesGizmo_();
            end

            [axisPts, labelPts, labelEdges, ok] = obj.screenAxes3DGeometry_();
            if ~ok, return; end

            colors = struct('X', [0.88, 0.12, 0.10], ...
                            'Y', [0.10, 0.62, 0.18], ...
                            'Z', [0.12, 0.32, 0.92]);
            axes = {'X', 'Y', 'Z'};
            for ia = 1:numel(axes)
                ax = axes{ia};
                axisName = ['ScreenAxis' ax];
                labelName = ['ScreenAxisLabel' ax];
                if ~isfield(obj.handles_, axisName)
                    cn = obj.App.polyscopeHandle().register_curve_network( ...
                        obj.structName_(axisName), squeeze(axisPts(ia, :, :)), [1, 2]);
                    cn.set_color(colors.(ax));
                    cn.set_radius(obj.screenAxesRadius_(axisPts), false);
                    cn.set_material(obj.Opts.polyscope.lineMaterial);
                    cn.set_enabled(obj.guiScreenAxesEnabled_());
                    obj.handles_.(axisName) = cn;
                end
                if ~isfield(obj.handles_, labelName)
                    cn = obj.App.polyscopeHandle().register_curve_network( ...
                        obj.structName_(labelName), labelPts.(ax), labelEdges.(ax));
                    cn.set_color(colors.(ax));
                    cn.set_radius(obj.screenAxesRadius_(axisPts) * 0.75, false);
                    cn.set_material(obj.Opts.polyscope.lineMaterial);
                    cn.set_enabled(obj.guiScreenAxesEnabled_());
                    obj.handles_.(labelName) = cn;
                end
            end
        end

        function updateScreenAxes3D_(obj)
            if obj.isOverlayScreenAxes_()
                return;
            end
            % Updating the six axis/label curve networks is relatively costly
            % because each operation crosses the MEX boundary. Camera motion is
            % still visually smooth at 30 Hz, even when the main UI renders at
            % 60 Hz.
            if ~isempty(obj.screenAxesUpdateTimer_)
                try
                    if toc(obj.screenAxesUpdateTimer_) < (1 / 30)
                        return;
                    end
                catch
                end
            end
            obj.screenAxesUpdateTimer_ = tic;
            if isempty(fieldnames(obj.handles_)), return; end
            showAxes = obj.guiScreenAxesEnabled_();
            if isfield(obj.handles_, 'ScreenAxesGizmo')
                obj.handles_.ScreenAxesGizmo.set_enabled(showAxes);
                if showAxes
                    obj.updateScreenAxesGizmo_();
                end
            end
            axisFields = {'ScreenAxisX', 'ScreenAxisY', 'ScreenAxisZ', ...
                          'ScreenAxisLabelX', 'ScreenAxisLabelY', 'ScreenAxisLabelZ'};
            if ~showAxes
                for i = 1:numel(axisFields)
                    if isfield(obj.handles_, axisFields{i})
                        obj.handles_.(axisFields{i}).set_enabled(false);
                    end
                end
                return;
            end

            if ~isfield(obj.handles_, 'ScreenAxisX')
                obj.registerScreenAxes3D_();
            end

            [axisPts, labelPts, ~, ok] = obj.screenAxes3DGeometry_();
            if ~ok, return; end
            axes = {'X', 'Y', 'Z'};
            r = obj.screenAxesRadius_(axisPts);
            for ia = 1:numel(axes)
                ax = axes{ia};
                axisName = ['ScreenAxis' ax];
                labelName = ['ScreenAxisLabel' ax];
                if isfield(obj.handles_, axisName)
                    obj.handles_.(axisName).update_node_positions(squeeze(axisPts(ia, :, :)));
                    obj.handles_.(axisName).set_radius(r, false);
                    obj.handles_.(axisName).set_enabled(true);
                end
                if isfield(obj.handles_, labelName)
                    obj.handles_.(labelName).update_node_positions(labelPts.(ax));
                    obj.handles_.(labelName).set_radius(r * 0.75, false);
                    obj.handles_.(labelName).set_enabled(true);
                end
            end
        end

        function ok = registerScreenAxesGizmo_(obj)
            ok = false;
            try
                [axisPts, ~, ~, geomOk] = obj.screenAxes3DGeometry_();
                if ~geomOk, return; end

                ps = obj.App.polyscopeHandle();
                name = obj.structName_('ScreenAxesGizmo');
                try
                    gizmo = ps.add_transformation_gizmo(name);
                catch
                    gizmo = ps.get_transformation_gizmo(name);
                end
                obj.configureScreenAxesGizmo_(gizmo, axisPts);
                obj.handles_.ScreenAxesGizmo = gizmo;
                ok = true;
            catch
                ok = false;
            end
        end

        function updateScreenAxesGizmo_(obj)
            if ~isfield(obj.handles_, 'ScreenAxesGizmo'), return; end
            try
                [axisPts, ~, ~, ok] = obj.screenAxes3DGeometry_();
                if ~ok, return; end
                obj.configureScreenAxesGizmo_(obj.handles_.ScreenAxesGizmo, axisPts);
            catch
            end
        end

        function removeScreenAxesGizmo_(obj)
            try
                obj.App.polyscopeHandle().remove_transformation_gizmo(obj.structName_('ScreenAxesGizmo'));
            catch
            end
        end

        function tf = guiScreenAxesEnabled_(obj)
            tf = obj.getOptField_(obj.Opts.polyscope, 'showScreenAxes', true);
            if isfield(obj.gui_, 'showScreenAxes')
                tf = tf && obj.gui_.showScreenAxes;
            end
        end

        function tf = isOverlayScreenAxes_(obj)
            mode = char(string(obj.getOptField_(obj.Opts.polyscope, 'screenAxesMode', 'overlay')));
            tf = strcmpi(mode, 'overlay');
        end

        % ------------------------------------------------------------------
        % Helpers required by the methods above
        % ------------------------------------------------------------------

        function center = resolveSliceCenter_(obj)
            if isfield(obj.Opts, 'slice') && isfield(obj.Opts.slice, 'planes') && ...
                    ~isempty(obj.Opts.slice.planes)
                center = obj.resolveSliceCenterForPlane_(obj.Opts.slice.planes(1));
            else
                center = obj.defaultSliceCenter_();
            end
        end

        function center = resolveSliceCenterForPlane_(obj, p)
            center = [];
            if isfield(p, 'center') && ~isempty(p.center)
                center = double(p.center(:)).';
                if numel(center) >= 3
                    center = center(1:3);
                    if ~all(isfinite(center))
                        center = [];
                    end
                else
                    center = [];
                end
            end
            if isempty(center)
                center = obj.defaultSliceCenter_();
            end
        end

        function center = defaultSliceCenter_(obj)
            P = plotter.polyscope.ModelAdapter.nodeCoords(obj.ModelInfo);
            if isempty(P)
                center = [0, 0, 0];
                return;
            end
            mn = min(P, [], 1, 'omitnan');
            mx = max(P, [], 1, 'omitnan');
            center = (mn + mx) / 2;
            if ~all(isfinite(center))
                center = [0, 0, 0];
            end
        end

        function removeSlicePlane_(obj)
            try
                ps = obj.App.polyscopeHandle();
                if isfield(obj.handles_, 'SlicePlanes')
                    for k = 1:numel(obj.handles_.SlicePlanes)
                        try ps.remove_slice_plane(obj.handles_.SlicePlanes{k}{1}); catch, end
                    end
                    obj.handles_.SlicePlanes = {};
                end
                if isfield(obj.Opts, 'slice') && isfield(obj.Opts.slice, 'planes')
                    for i = 1:numel(obj.Opts.slice.planes)
                        name = char(string(obj.Opts.slice.planes(i).name));
                        if ps.has_slice_plane(name)
                            try ps.remove_slice_plane(name); catch, end
                        end
                    end
                end
            catch
            end
        end

        function removeSlicePlaneByIdx_(obj, idx)
            if ~isfield(obj.Opts, 'slice') || ~isfield(obj.Opts.slice, 'planes')
                return;
            end
            n = numel(obj.Opts.slice.planes);
            if idx < 1 || idx > n
                return;
            end
            name = char(string(obj.Opts.slice.planes(idx).name));
            try
                ps = obj.App.polyscopeHandle();
                if ps.has_slice_plane(name)
                    ps.remove_slice_plane(name);
                end
            catch
            end
            obj.Opts.slice.planes(idx) = [];
            if isfield(obj.gui_, 'slicePlanes') && numel(obj.gui_.slicePlanes) >= idx
                obj.gui_.slicePlanes(idx) = [];
            end
            if isfield(obj.handles_, 'SlicePlanes')
                keep = {};
                for k = 1:numel(obj.handles_.SlicePlanes)
                    if ~strcmp(obj.handles_.SlicePlanes{k}{1}, name)
                        keep{end+1} = obj.handles_.SlicePlanes{k}; %#ok<AGROW>
                    end
                end
                obj.handles_.SlicePlanes = keep;
            end
        end

        function addSlicePlane_(obj)
            obj.normalizeSliceOpts_();
            planes = obj.Opts.slice.planes;
            if isempty(planes)
                defaults = struct('name', 'Slice plane', ...
                                  'show', true, ...
                                  'center', [], ...
                                  'normal', [0, 0, 1], ...
                                  'drawPlane', true, ...
                                  'drawWidget', false, ...
                                  'widgetSize', 0.75, ...
                                  'color', [0.90, 0.35, 0.55], ...
                                  'gridColor', [1, 1, 1], ...
                                  'transparency', 0.45, ...
                                  'cullWholeElements', false);
                newPlane = defaults;
                newIdx = 1;
            else
                newIdx = numel(planes) + 1;
                newPlane = planes(end);
                newPlane.show = true;
            end
            newPlane.name = obj.uniqueSlicePlaneName_();
            planes(newIdx) = newPlane;
            obj.Opts.slice.planes = planes;
            if ~isfield(obj.gui_, 'slicePlanes')
                obj.gui_.slicePlanes = repmat(obj.emptySliceGuiPlane_(), 0);
            end
            obj.gui_.slicePlanes(newIdx) = obj.slicePlaneOptsToGui_(newPlane);
            obj.gui_.slicePlaneIdx = newIdx;
        end

        function name = uniqueSlicePlaneName_(obj)
            existing = {};
            if isfield(obj.Opts, 'slice') && isfield(obj.Opts.slice, 'planes')
                for i = 1:numel(obj.Opts.slice.planes)
                    existing{end+1} = char(string(obj.Opts.slice.planes(i).name)); %#ok<AGROW>
                end
            end
            k = 1;
            while true
                name = sprintf('Slice plane %d', k);
                if ~ismember(name, existing)
                    return;
                end
                k = k + 1;
            end
        end

        function syncGuiSlicePlaneFromOpts_(obj, idx)
            if idx < 1 || idx > numel(obj.Opts.slice.planes)
                return;
            end
            obj.gui_.slicePlanes(idx) = obj.slicePlaneOptsToGui_(obj.Opts.slice.planes(idx));
        end

        function syncOptsSlicePlaneFromGui_(obj, idx)
            if idx < 1 || idx > numel(obj.gui_.slicePlanes)
                return;
            end
            g = obj.gui_.slicePlanes(idx);
            p = obj.Opts.slice.planes(idx);
            p.show = g.show;
            p.drawPlane = g.drawPlane;
            p.drawWidget = g.drawWidget;
            p.center = g.center;
            p.normal = g.normal;
            p.widgetSize = g.widgetSize;
            p.transparency = g.transparency;
            p.color = g.color;
            p.gridColor = g.gridColor;
            p.cullWholeElements = g.cullWholeElements;
            obj.Opts.slice.planes(idx) = p;
        end

        function [axisPts, labelPts, labelEdges, ok] = screenAxes3DGeometry_(obj)
            ok = false;
            axisPts = zeros(3, 2, 3);
            labelPts = struct('X', zeros(0, 3), 'Y', zeros(0, 3), 'Z', zeros(0, 3));
            labelEdges = struct('X', zeros(0, 2), 'Y', zeros(0, 2), 'Z', zeros(0, 2));

            P = plotter.polyscope.ModelAdapter.nodeCoords(obj.ModelInfo);
            if isempty(P), return; end
            target = mean(P, 1, 'omitnan');
            target = double(target(:)).';
            span = max(max(P, [], 1) - min(P, [], 1));
            if ~isfinite(span) || span <= 0, span = obj.L_; end
            if ~isfinite(span) || span <= 0, span = 1; end

            right = [1, 0, 0];
            up = [0, 1, 0];
            fwd = [0, 0, -1];
            dist = 4 * span;
            try
                ps = obj.App.polyscopeHandle();
                vc = double(ps.get_view_center());
                if numel(vc) >= 3 && all(isfinite(vc(1:3)))
                    target = vc(1:3);
                    target = double(target(:)).';
                end
                viewMat = double(ps.get_camera_view_matrix());
                if all(size(viewMat) >= [3, 4]) && all(all(isfinite(viewMat(1:3, 1:4))))
                    right = obj.normalizeRow_(viewMat(1, 1:3));
                    up = obj.normalizeRow_(viewMat(2, 1:3));
                    fwd = obj.normalizeRow_(-viewMat(3, 1:3));
                    R = viewMat(1:3, 1:3);
                    t = viewMat(1:3, 4);
                    eye = -(R.') * t(:);
                    dist = norm(eye(:).' - target);
                    if ~isfinite(dist) || dist <= 1e-12
                        dist = 4 * span;
                    end
                end
            catch
            end

            len = max(0.08 * dist, 0.18 * span);
            len = min(len, 0.35 * span);
            origin = target - 0.20 * dist * right - 0.24 * dist * up + 0.03 * dist * fwd;

            worldAxes = diag(ones(3, 1));
            for ia = 1:3
                axisPts(ia, 1, :) = origin;
                axisPts(ia, 2, :) = origin + len * worldAxes(ia, :);
            end

            labelSize = 0.24 * len;
            labelOffset = 1.12 * len;
            labelPts.X = obj.screenAxisLetterX_(origin + labelOffset * worldAxes(1, :), right, up, labelSize);
            labelPts.Y = obj.screenAxisLetterY_(origin + labelOffset * worldAxes(2, :), right, up, labelSize);
            labelPts.Z = obj.screenAxisLetterZ_(origin + labelOffset * worldAxes(3, :), right, up, labelSize);
            labelEdges.X = [1 2; 3 4];
            labelEdges.Y = [1 2; 1 3; 1 4];
            labelEdges.Z = [1 2; 2 3; 3 4];
            ok = true;
        end

        function pts = screenAxisLetterX_(~, c, right, up, s)
            pts = [c - s * right - s * up; c + s * right + s * up; ...
                   c - s * right + s * up; c + s * right - s * up];
        end

        function pts = screenAxisLetterY_(~, c, right, up, s)
            top = c + s * up;
            mid = c;
            pts = [mid; top - s * right; top + s * right; c - s * up];
        end

        function pts = screenAxisLetterZ_(~, c, right, up, s)
            pts = [c - s * right + s * up; c + s * right + s * up; ...
                   c - s * right - s * up; c + s * right - s * up];
        end

        function r = screenAxesRadius_(~, axisPts)
            len = norm(squeeze(axisPts(1, 2, :) - axisPts(1, 1, :)));
            if ~isfinite(len) || len <= 0, len = 1; end
            r = max(len * 0.035, eps);
        end

        function configureScreenAxesGizmo_(obj, gizmo, axisPts)
            origin = squeeze(axisPts(1, 1, :)).';
            gizmo.set_enabled(obj.guiScreenAxesEnabled_());
            gizmo.set_allow_translation(true);
            gizmo.set_allow_rotation(true);
            gizmo.set_allow_scaling(false);
            gizmo.set_interact_in_local_space(false);
            gizmo.set_gizmo_scale(obj.getOptField_(obj.Opts.polyscope, 'screenAxesGizmoSize', 1.15));
            gizmo.set_position(origin);
        end

        function tf = hasElementClasses_(obj)
            C = obj.elementClasses_();
            tf = isstruct(C) && ~isempty(fieldnames(C));
        end

        function C = elementClasses_(obj)
            C = struct();
            if isfield(obj.ModelInfo, 'Elements') && isstruct(obj.ModelInfo.Elements) && ...
                    isfield(obj.ModelInfo.Elements, 'Classes') && isstruct(obj.ModelInfo.Elements.Classes)
                C = obj.ModelInfo.Elements.Classes;
            end
        end

        function v = normalizeRow_(~, v)
            v = double(v(:)).';
            n = norm(v);
            if n > 0, v = v / n; end
        end

        function up = fallbackUp_(obj, f)
            candidates = [0, 0, 1; 0, 1, 0; 1, 0, 0];
            [~, idx] = min(abs(candidates * f(:)));
            up = obj.normalizeRow_(candidates(idx, :));
        end

        function name = upDirNameForVector_(~, up)
            [~, idx] = max(abs(double(up(:))));
            names = {'x_up', 'y_up', 'z_up'};
            name = names{idx};
        end

        function setUpDir_(obj, upDir)
            try
                obj.App.polyscopeHandle().set_up_dir(upDir, false);
            catch
            end
        end

        function setPlaneViewFov_(obj)
            try
                fov = double(obj.getOptField_(obj.Opts.polyscope, 'planeViewFov', 62.0));
                if ~isfinite(fov)
                    fov = 62.0;
                end
                fov = max(5.0, min(160.0, fov));
                obj.App.polyscopeHandle().set_vertical_fov_degrees(fov);
            catch
            end
        end

        function setPerspectiveViewFov_(obj)
            try
                fov = double(obj.getOptField_(obj.Opts.polyscope, 'perspectiveViewFov', 45.0));
                if ~isfinite(fov)
                    fov = 45.0;
                end
                fov = max(5.0, min(160.0, fov));
                obj.App.polyscopeHandle().set_vertical_fov_degrees(fov);
            catch
            end
        end

        function setNavigationStyle_(obj, style)
            try
                obj.App.polyscopeHandle().set_navigation_style(style);
            catch
            end
        end

        function tf = isHeadless_(obj)
            tf = logical(obj.getOptField_(obj.Opts.polyscope, 'headless', false));
        end

        function tf = shouldAutoShow_(obj)
            tf = logical(obj.getOptField_(obj.Opts.polyscope, 'autoShow', true)) && ~obj.isHeadless_();
        end

        function configureAnimationRenderLoop_(obj, isRunning, fps)
            try
                ps = obj.App.polyscopeHandle();
                if isRunning
                    fps = max(1, double(fps));
                    ps.set_max_fps(fps);
                    ps.set_always_redraw(true);
                    ps.set_enable_vsync(false);
                else
                    ps.set_max_fps(max(1, double(obj.getOptField_(obj.Opts.polyscope, 'maxFps', 30))));
                    ps.set_always_redraw(obj.getOptField_(obj.Opts.polyscope, 'alwaysRedraw', false));
                    ps.set_enable_vsync(obj.getOptField_(obj.Opts.polyscope, 'enableVsync', true));
                end
            catch
            end
        end

        function val = cachedRange_(obj, namespace, key, computeFcn)
            %CACHEDRANGE_ Generic [lo, hi] / scalar cache with namespace/key invalidation.
            if isfield(obj.rangeCache_, namespace)
                slot = obj.rangeCache_.(namespace);
                if isfield(slot, 'key') && isfield(slot, 'value') && ...
                        strcmp(char(string(slot.key)), char(string(key)))
                    val = slot.value;
                    return;
                end
            end
            val = computeFcn();
            obj.rangeCache_.(namespace) = struct('key', key, 'value', val);
        end

        function invalidateCachedRange_(obj, namespace)
            if isfield(obj.rangeCache_, namespace)
                obj.rangeCache_.(namespace).key = '';
            end
        end

        function delete(obj)
            try
                obj.App.shutdown();
            catch
            end
        end

    end
end
