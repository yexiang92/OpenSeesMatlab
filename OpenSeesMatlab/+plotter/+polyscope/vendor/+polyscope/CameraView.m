classdef CameraView < handle
    %CAMERAVIEW MATLAB wrapper for a Polyscope camera view structure.

    properties (SetAccess = private)
        name
    end

    methods
        function obj = CameraView(name)
            obj.name = name;
        end

        function update_camera_parameters(obj, position, look_dir, up_dir, fov_deg, aspect_ratio)
            call_mex('camera_view_update_camera_parameters', obj.name, position, look_dir, up_dir, fov_deg, aspect_ratio);
        end

        function p = get_camera_parameters(obj)
            p = call_mex('camera_view_get_camera_parameters', obj.name);
        end

        function set_view_to_this_camera(obj, flyTo)
            if nargin < 2, flyTo = false; end
            call_mex('camera_view_set_view_to_this_camera', obj.name, flyTo);
        end

        function set_enabled(obj, val)
            call_mex('camera_view_set_enabled', obj.name, val);
        end

        function set_widget_focal_length(obj, v, relative)
            if nargin < 3, relative = true; end
            call_mex('camera_view_set_widget_focal_length', obj.name, v, relative);
        end

        function v = get_widget_focal_length(obj)
            v = call_mex('camera_view_get_widget_focal_length', obj.name);
        end

        function set_widget_thickness(obj, v)
            call_mex('camera_view_set_widget_thickness', obj.name, v);
        end

        function v = get_widget_thickness(obj)
            v = call_mex('camera_view_get_widget_thickness', obj.name);
        end

        function set_widget_color(obj, c)
            call_mex('camera_view_set_widget_color', obj.name, c);
        end

        function c = get_widget_color(obj)
            c = call_mex('camera_view_get_widget_color', obj.name);
        end
    end
end
