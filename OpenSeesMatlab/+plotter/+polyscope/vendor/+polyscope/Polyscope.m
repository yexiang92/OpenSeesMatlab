classdef Polyscope < handle
    %POLYSCOPE MATLAB wrapper for the Polyscope viewer.
    %   This class mirrors the Python polyscope API as closely as possible.
    %   Usage:
    %       ps = polyscope.Polyscope;
    %       ps.init('openGL_mock');
    %       pc = ps.register_point_cloud('my cloud', points);
    %       pc.add_scalar_quantity('height', vals);
    %       ps.show();

    properties (Access = private)
        % MATLAB callbacks cannot be invoked from the C++ render loop (it
        % crashes the MEX adapter). We store the user callback here and run
        % it from MATLAB inside a frame_begin/frame_end loop in show().
        userCallback_ = []
        maxFps_ double = 60
    end

    methods
        function init(~, backend)
            if nargin < 2, backend = 'auto'; end
            call_mex('init', backend);
        end

        function check_initialized(~)
            call_mex('check_initialized');
        end

        function tf = is_initialized(~)
            tf = call_mex('is_initialized');
        end

        function show(obj, forFrames)
            % If the user has installed a MATLAB callback, run the render loop
            % from MATLAB so the callback executes safely between
            % frame_begin()/frame_end(). Otherwise, defer to the native C++ show().
            if ~isempty(obj.userCallback_)
                obj.show_window();
                if nargin < 2
                    while ~obj.window_requests_close()
                        tFrame = tic;
                        obj.frame_begin();
                        obj.userCallback_();
                        obj.frame_end();
                        obj.wait_after_frame_(toc(tFrame));
                    end
                else
                    frame = 1;
                    while frame <= forFrames && ~obj.window_requests_close()
                        tFrame = tic;
                        obj.frame_begin();
                        obj.userCallback_();
                        obj.frame_end();
                        obj.wait_after_frame_(toc(tFrame));
                        frame = frame + 1;
                    end
                end
                obj.hide_window();
            else
                if nargin < 2
                    call_mex('show');
                else
                    call_mex('show', forFrames);
                end
            end
        end

        function unshow(~)
            call_mex('unshow');
        end

        function hide_window(~)
            call_mex('hide_window');
        end

        function show_window(~)
            call_mex('show_window');
        end

        function focus_window(~)
            call_mex('focus_window');
        end

        function set_up_dir(~, dir, animate)
            if nargin < 2 || isempty(dir)
                dir = 'z_up';
            end
            if nargin < 3
                animate = false;
            end
            call_mex('set_up_dir', dir, animate);
        end

        function tf = window_requests_close(~)
            tf = call_mex('window_requests_close');
        end

        function frame_tick(~)
            call_mex('frame_tick');
        end

        function shutdown(~, allowMidFrame)
            if nargin < 2, allowMidFrame = false; end
            call_mex('shutdown', allowMidFrame);
        end

        function remove_everything(~)
            call_mex('remove_everything');
        end

        function remove_all_structures(~)
            call_mex('remove_all_structures');
        end

        % === Options ======================================================
        function set_program_name(~, name)
            call_mex('set_program_name', name);
        end

        function set_verbosity(~, v)
            call_mex('set_verbosity', v);
        end

        function set_print_prefix(~, p)
            call_mex('set_print_prefix', p);
        end

        function set_errors_throw_exceptions(~, val)
            call_mex('set_errors_throw_exceptions', val);
        end

        function set_max_fps(obj, f)
            obj.maxFps_ = max(1, double(f));
            call_mex('set_max_fps', f);
        end

        function set_enable_vsync(~, val)
            call_mex('set_enable_vsync', val);
        end

        function set_ssaa_factor(~, val)
            call_mex('set_ssaa_factor', int32(val));
        end

        function set_SSAA_factor(obj, val)
            obj.set_ssaa_factor(val);
        end

        function val = get_ssaa_factor(~)
            val = call_mex('get_ssaa_factor');
        end

        function set_navigation_style(~, style)
            call_mex('set_navigation_style', char(string(style)));
        end

        function style = get_navigation_style(~)
            style = call_mex('get_navigation_style');
        end

        function dir = get_up_dir(~)
            dir = call_mex('get_up_dir');
        end

        function set_front_dir(~, dir, animate)
            if nargin < 2 || isempty(dir)
                dir = 'z_front';
            end
            if nargin < 3
                animate = false;
            end
            call_mex('set_front_dir', dir, animate);
        end

        function dir = get_front_dir(~)
            dir = call_mex('get_front_dir');
        end

        function set_use_prefs_file(~, val)
            call_mex('set_use_prefs_file', val);
        end

        function set_allow_headless_backends(~, val)
            call_mex('set_allow_headless_backends', val);
        end

        function set_do_default_mouse_interaction(~, val)
            call_mex('set_do_default_mouse_interaction', val);
        end

        function request_redraw(~)
            call_mex('request_redraw');
        end

        function tf = get_redraw_requested(~)
            tf = call_mex('get_redraw_requested');
        end

        function set_always_redraw(~, val)
            call_mex('set_always_redraw', val);
        end

        function set_frame_tick_limit_fps_mode(~, mode)
            call_mex('set_frame_tick_limit_fps_mode', char(string(mode)));
        end

        function set_enable_render_error_checks(~, val)
            call_mex('set_enable_render_error_checks', val);
        end

        function set_egl_device_index(~, idx)
            call_mex('set_egl_device_index', int32(idx));
        end

        function set_autocenter_structures(~, val)
            call_mex('set_autocenter_structures', val);
        end

        function set_autoscale_structures(~, val)
            call_mex('set_autoscale_structures', val);
        end

        function set_ui_scale(~, val)
            call_mex('set_ui_scale', val);
        end

        function val = get_ui_scale(~)
            val = call_mex('get_ui_scale');
        end

        function set_build_gui(~, val)
            call_mex('set_build_gui', val);
        end

        function set_user_gui_is_on_right_side(~, val)
            call_mex('set_user_gui_is_on_right_side', val);
        end

        function set_build_default_gui_panels(~, val)
            call_mex('set_build_default_gui_panels', val);
        end

        function set_right_gui_pane_width(~, width)
            call_mex('set_right_gui_pane_width', int32(width));
        end

        function width = get_right_gui_pane_width(~)
            width = call_mex('get_right_gui_pane_width');
        end

        function set_render_scene(~, val)
            call_mex('set_render_scene', val);
        end

        function set_open_imgui_window_for_user_callback(~, val)
            call_mex('set_open_imgui_window_for_user_callback', val);
        end

        function set_invoke_user_callback_for_nested_show(~, val)
            call_mex('set_invoke_user_callback_for_nested_show', val);
        end

        function set_give_focus_on_show(~, val)
            call_mex('set_give_focus_on_show', val);
        end

        function set_hide_window_after_show(~, val)
            call_mex('set_hide_window_after_show', val);
        end

        function set_warn_for_invalid_values(~, val)
            call_mex('set_warn_for_invalid_values', val);
        end

        function set_display_message_popups(~, val)
            call_mex('set_display_message_popups', val);
        end

        function clear_configure_imgui_style_callback(~)
            call_mex('clear_configure_imgui_style_callback');
        end

        function clear_prepare_imgui_fonts_callback(~)
            call_mex('clear_prepare_imgui_fonts_callback');
        end

        function clear_files_dropped_callback(~)
            call_mex('clear_files_dropped_callback');
        end

        function set_user_callback(obj, cb)
            % Store a MATLAB function handle that will be invoked from MATLAB
            % inside the split-frame render loop (frame_begin/frame_end).
            % This avoids the unsafe C++ -> MATLAB callback re-entry that
            % crashes the MEX adapter.
            if ~isempty(cb) && ~isa(cb, 'function_handle')
                error('Polyscope:setUserCallback', ...
                      'Callback must be a function handle or empty.');
            end
            if isempty(cb)
                obj.userCallback_ = [];
            else
                obj.userCallback_ = cb;
            end
            call_mex('clear_user_callback');
        end

        function clear_user_callback(obj)
            obj.userCallback_ = [];
            call_mex('clear_user_callback');
        end

        function frame_begin(~)
            call_mex('frame_begin');
        end

        function frame_end(~)
            call_mex('frame_end');
        end

        function test_cpp_callback_frame(~)
            call_mex('test_cpp_callback_frame');
        end

        % === Scene extents ===============================================
        function set_automatically_compute_scene_extents(~, val)
            call_mex('set_automatically_compute_scene_extents', val);
        end

        function set_length_scale(~, val)
            call_mex('set_length_scale', val);
        end

        function val = get_length_scale(~)
            val = call_mex('get_length_scale');
        end

        function set_bounding_box(~, low, high)
            call_mex('set_bounding_box', low, high);
        end

        function [low, high] = get_bounding_box(~)
            [low, high] = call_mex('get_bounding_box');
        end

        function update_scene_extents(~)
            call_mex('update_scene_extents');
        end

        % === View / camera ================================================
        function set_window_size(~, w, h)
            call_mex('set_window_size', w, h);
        end

        function sz = get_window_size(~)
            sz = call_mex('get_window_size');
        end

        function reset_camera_to_home_view(~)
            call_mex('reset_camera_to_home_view');
        end

        function look_at(~, eye, target, flyTo)
            if nargin < 4, flyTo = false; end
            call_mex('look_at', eye, target, flyTo);
        end

        function look_at_dir(~, eye, target, upDir, flyTo)
            if nargin < 5, flyTo = false; end
            call_mex('look_at_dir', eye, target, upDir, flyTo);
        end

        function set_view_projection_mode(~, mode)
            call_mex('set_view_projection_mode', char(string(mode)));
        end

        function mode = get_view_projection_mode(~)
            mode = call_mex('get_view_projection_mode');
        end

        function set_vertical_fov_degrees(~, val)
            call_mex('set_vertical_fov_degrees', val);
        end

        function val = get_vertical_fov_degrees(~)
            val = call_mex('get_vertical_fov_degrees');
        end

        function val = get_aspect_ratio_width_over_height(~)
            val = call_mex('get_aspect_ratio_width_over_height');
        end

        function sz = get_buffer_size(~)
            sz = call_mex('get_buffer_size');
        end

        function set_window_resizable(~, val)
            call_mex('set_window_resizable', val);
        end

        function tf = get_window_resizable(~)
            tf = call_mex('get_window_resizable');
        end

        function set_view_from_json(~, jsonStr, flyTo)
            if nargin < 3, flyTo = false; end
            call_mex('set_view_from_json', jsonStr, flyTo);
        end

        function jsonStr = get_view_as_json(~)
            jsonStr = call_mex('get_view_as_json');
        end

        function ray = screen_coords_to_world_ray(~, screenCoords)
            ray = call_mex('screen_coords_to_world_ray', screenCoords);
        end

        function set_camera_view_matrix(~, mat)
            call_mex('set_camera_view_matrix', mat);
        end

        function mat = get_camera_view_matrix(~)
            mat = call_mex('get_camera_view_matrix');
        end

        function set_view_center_and_look_at(~, pos, flyTo)
            if nargin < 3, flyTo = false; end
            call_mex('set_view_center_and_look_at', pos, flyTo);
        end

        function set_view_center_and_project(~, pos)
            call_mex('set_view_center_and_project', pos);
        end

        function set_view_center_raw(~, pos)
            call_mex('set_view_center_raw', pos);
        end

        function pos = get_view_center(~)
            pos = call_mex('get_view_center');
        end

        function set_background_color(~, c)
            call_mex('set_background_color', c);
        end

        function c = get_background_color(~)
            c = call_mex('get_background_color');
        end

        % === Screenshots ==================================================
        function screenshot(~, filename, varargin)
            if nargin < 2
                call_mex('screenshot');
            else
                call_mex('screenshot', filename, varargin{:});
            end
        end

        function img = screenshot_to_buffer(~, varargin)
            img = call_mex('screenshot_to_buffer', varargin{:});
        end

        function capture_display(~, filename)
            call_mex('capture_display', filename);
        end

        function set_screenshot_extension(~, ext)
            call_mex('set_screenshot_extension', ext);
        end

        % === Advanced UI / messages / picking =============================
        function build_polyscope_gui(~)
            call_mex('build_polyscope_gui');
        end

        function build_structure_gui(~)
            call_mex('build_structure_gui');
        end

        function build_pick_gui(~)
            call_mex('build_pick_gui');
        end

        function build_user_gui_and_invoke_callback(~)
            call_mex('build_user_gui_and_invoke_callback');
        end

        function info(~, message, verbosity)
            if nargin < 3
                call_mex('info', message);
            else
                call_mex('info', int32(verbosity), message);
            end
        end

        function warning(~, message, detail)
            if nargin < 3
                detail = '';
            end
            call_mex('warning', message, detail);
        end

        function error(~, message)
            call_mex('error', message);
        end

        function terminating_error(~, message)
            call_mex('terminating_error', message);
        end

        function result = pick(~, varargin)
            if numel(varargin) ~= 2
                error('Polyscope:pick', 'Use pick(''screen_coords'', xy) or pick(''buffer_inds'', ij).');
            end
            key = char(string(varargin{1}));
            if strcmpi(key, 'screen_coords')
                result = call_mex('pick_at_screen_coords', varargin{2});
            elseif strcmpi(key, 'buffer_inds')
                result = call_mex('pick_at_buffer_inds', int32(varargin{2}));
            else
                error('Polyscope:pick', 'Unknown pick key: %s', key);
            end
        end

        function tf = have_selection(~)
            tf = call_mex('have_selection');
        end

        function result = get_selection(~)
            result = call_mex('get_selection');
        end

        function reset_selection(~)
            call_mex('reset_selection');
        end

        function set_ground_plane_mode(~, mode)
            call_mex('set_ground_plane_mode', char(string(mode)));
        end

        function set_ground_plane_height_mode(~, mode)
            call_mex('set_ground_plane_height_mode', char(string(mode)));
        end

        function set_ground_plane_height(~, val)
            call_mex('set_ground_plane_height', val);
        end

        function set_ground_plane_height_factor(~, val, isRelative)
            if nargin < 3, isRelative = true; end
            call_mex('set_ground_plane_height_factor', val, isRelative);
        end

        function set_shadow_blur_iters(~, val)
            call_mex('set_shadow_blur_iters', int32(val));
        end

        function set_shadow_darkness(~, val)
            call_mex('set_shadow_darkness', val);
        end

        function set_transparency_mode(~, mode)
            call_mex('set_transparency_mode', char(string(mode)));
        end

        function set_transparency_render_passes(~, val)
            call_mex('set_transparency_render_passes', int32(val));
        end

        function handle = get_final_scene_color_texture_native_handle(~)
            handle = call_mex('get_final_scene_color_texture_native_handle');
        end

        function load_static_material(~, matName, filename)
            call_mex('load_static_material', matName, filename);
        end

        function load_blendable_material(~, matName, filenamesOrBase, filenameExt)
            if nargin < 4
                call_mex('load_blendable_material', matName, filenamesOrBase);
            else
                call_mex('load_blendable_material', matName, filenamesOrBase, filenameExt);
            end
        end

        function load_color_map(~, cmapName, filename)
            call_mex('load_color_map', cmapName, filename);
        end

        % === Point clouds =================================================
        function pc = register_point_cloud(~, name, points, varargin)
            call_mex('register_point_cloud', name, points, varargin{:});
            pc = polyscope.PointCloud(name);
        end

        function tf = has_point_cloud(~, name)
            tf = call_mex('has_point_cloud', name);
        end

        function remove_point_cloud(~, name)
            call_mex('remove_point_cloud', name);
        end

        % === Surface meshes ===============================================
        function sm = register_surface_mesh(~, name, vertices, faces, varargin)
            call_mex('register_surface_mesh', name, vertices, faces, varargin{:});
            sm = polyscope.SurfaceMesh(name);
        end

        function tf = has_surface_mesh(~, name)
            tf = call_mex('has_surface_mesh', name);
        end

        function remove_surface_mesh(~, name)
            call_mex('remove_surface_mesh', name);
        end

        % === Curve networks ===============================================
        function cn = register_curve_network(~, name, nodes, edges, varargin)
            call_mex('register_curve_network', name, nodes, edges, varargin{:});
            cn = polyscope.CurveNetwork(name);
        end

        function cn = register_curve_network_line(~, name, nodes, varargin)
            call_mex('register_curve_network_line', name, nodes, varargin{:});
            cn = polyscope.CurveNetwork(name);
        end

        function cn = register_curve_network_loop(~, name, nodes, varargin)
            call_mex('register_curve_network_loop', name, nodes, varargin{:});
            cn = polyscope.CurveNetwork(name);
        end

        function cn = register_curve_network_segments(~, name, nodes, varargin)
            call_mex('register_curve_network_segments', name, nodes, varargin{:});
            cn = polyscope.CurveNetwork(name);
        end

        function tf = has_curve_network(~, name)
            tf = call_mex('has_curve_network', name);
        end

        function remove_curve_network(~, name)
            call_mex('remove_curve_network', name);
        end

        % === Volume meshes ================================================
        function vm = register_tet_mesh(~, name, vertices, tets, varargin)
            call_mex('register_tet_mesh', name, vertices, tets, varargin{:});
            vm = polyscope.VolumeMesh(name);
        end

        function vm = register_hex_mesh(~, name, vertices, hexes, varargin)
            call_mex('register_hex_mesh', name, vertices, hexes, varargin{:});
            vm = polyscope.VolumeMesh(name);
        end

        function vm = register_volume_mesh(~, name, vertices, cells, varargin)
            call_mex('register_volume_mesh', name, vertices, cells, varargin{:});
            vm = polyscope.VolumeMesh(name);
        end

        function vm = register_tet_hex_mesh(~, name, vertices, tets, hexes, varargin)
            call_mex('register_tet_hex_mesh', name, vertices, tets, hexes, varargin{:});
            vm = polyscope.VolumeMesh(name);
        end

        function tf = has_volume_mesh(~, name)
            tf = call_mex('has_volume_mesh', name);
        end

        function remove_volume_mesh(~, name)
            call_mex('remove_volume_mesh', name);
        end

        % === Volume grids =================================================
        function vg = register_volume_grid(~, name, node_dims, bound_low, bound_high, varargin)
            call_mex('register_volume_grid', name, node_dims, bound_low, bound_high, varargin{:});
            vg = polyscope.VolumeGrid(name);
        end

        function tf = has_volume_grid(~, name)
            tf = call_mex('has_volume_grid', name);
        end

        function remove_volume_grid(~, name)
            call_mex('remove_volume_grid', name);
        end

        % === Sparse volume grids ==========================================
        function svg = register_sparse_volume_grid(~, name, origin, cell_width, occupied_cells, varargin)
            call_mex('register_sparse_volume_grid', name, origin, cell_width, occupied_cells, varargin{:});
            svg = polyscope.SparseVolumeGrid(name);
        end

        function tf = has_sparse_volume_grid(~, name)
            tf = call_mex('has_sparse_volume_grid', name);
        end

        function remove_sparse_volume_grid(~, name)
            call_mex('remove_sparse_volume_grid', name);
        end

        % === Camera views =================================================
        function cv = register_camera_view(~, name, position, look_dir, up_dir, fov_deg, aspect_ratio, varargin)
            call_mex('register_camera_view', name, position, look_dir, up_dir, fov_deg, aspect_ratio, varargin{:});
            cv = polyscope.CameraView(name);
        end

        function tf = has_camera_view(~, name)
            tf = call_mex('has_camera_view', name);
        end

        function remove_camera_view(~, name)
            call_mex('remove_camera_view', name);
        end

        % === Transformation gizmos =======================================
        function gizmo = add_transformation_gizmo(~, name)
            if nargin < 2, name = ''; end
            actualName = call_mex('add_transformation_gizmo', name);
            gizmo = polyscope.TransformationGizmo(actualName);
        end

        function gizmo = get_transformation_gizmo(~, name)
            actualName = call_mex('get_transformation_gizmo', name);
            gizmo = polyscope.TransformationGizmo(actualName);
        end

        function remove_transformation_gizmo(~, name)
            call_mex('remove_transformation_gizmo', name);
        end

        function remove_all_transformation_gizmos(~)
            call_mex('remove_all_transformation_gizmos');
        end

        % === Slice planes ================================================
        function sp = add_slice_plane(~, name)
            if nargin < 2
                actualName = call_mex('add_slice_plane');
            else
                actualName = call_mex('add_slice_plane', name);
            end
            sp = polyscope.SlicePlane(actualName);
        end

        function sp = add_scene_slice_plane(~, initiallyVisible)
            if nargin < 2, initiallyVisible = false; end
            actualName = call_mex('add_scene_slice_plane', initiallyVisible);
            sp = polyscope.SlicePlane(actualName);
        end

        function sp = get_slice_plane(~, name)
            actualName = call_mex('get_slice_plane', name);
            sp = polyscope.SlicePlane(actualName);
        end

        function tf = has_slice_plane(~, name)
            tf = call_mex('has_slice_plane', name);
        end

        function remove_slice_plane(~, name)
            call_mex('remove_slice_plane', name);
        end

        function remove_last_scene_slice_plane(~)
            call_mex('remove_last_scene_slice_plane');
        end

        function remove_all_slice_planes(~)
            call_mex('remove_all_slice_planes');
        end

        % === Render engine info ===========================================
        function name = get_render_engine_backend_name(~)
            name = call_mex('get_render_engine_backend_name');
        end

        function tf = is_headless(~)
            tf = call_mex('is_headless');
        end

        function set_window_icon(~, filename)
            call_mex('set_window_icon', char(string(filename)));
        end

        % === Per-structure slice plane options =================================
        function set_structure_cull_whole_elements(~, name, val)
            call_mex('structure_set_cull_whole_elements', name, val);
        end

        function val = get_structure_cull_whole_elements(~, name)
            val = call_mex('structure_get_cull_whole_elements', name);
        end
    end

    methods (Access = private)
        function wait_after_frame_(obj, elapsed)
            targetPeriod = 1 / max(1, double(obj.maxFps_));
            remaining = targetPeriod - elapsed;
            drawnow limitrate;
            while remaining > 0.003
                pause(min(0.005, remaining));
                drawnow limitrate;
                remaining = remaining - 0.005;
            end
        end
    end
end
