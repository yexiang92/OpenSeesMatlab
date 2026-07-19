classdef SlicePlane < handle
    %SLICEPLANE MATLAB wrapper for a Polyscope slice plane.

    properties (SetAccess = private)
        name
    end

    methods
        function obj = SlicePlane(name)
            obj.name = name;
        end

        function remove(obj), call_mex('slice_plane_remove', obj.name); end
        function set_enabled(obj, val), call_mex('slice_plane_set_enabled', obj.name, val); end
        function val = get_enabled(obj), val = call_mex('slice_plane_get_enabled', obj.name); end
        function set_active(obj, val), call_mex('slice_plane_set_active', obj.name, val); end
        function val = get_active(obj), val = call_mex('slice_plane_get_active', obj.name); end
        function set_pose(obj, center, normal), call_mex('slice_plane_set_pose', obj.name, center, normal); end
        function c = get_center(obj), c = call_mex('slice_plane_get_center', obj.name); end
        function n = get_normal(obj), n = call_mex('slice_plane_get_normal', obj.name); end
        function set_draw_plane(obj, val), call_mex('slice_plane_set_draw_plane', obj.name, val); end
        function val = get_draw_plane(obj), val = call_mex('slice_plane_get_draw_plane', obj.name); end
        function set_draw_widget(obj, val), call_mex('slice_plane_set_draw_widget', obj.name, val); end
        function val = get_draw_widget(obj), val = call_mex('slice_plane_get_draw_widget', obj.name); end
        function set_widget_size(obj, val), call_mex('slice_plane_set_widget_size', obj.name, val); end
        function val = get_widget_size(obj), val = call_mex('slice_plane_get_widget_size', obj.name); end
        function set_color(obj, c), call_mex('slice_plane_set_color', obj.name, c); end
        function set_grid_line_color(obj, c), call_mex('slice_plane_set_grid_line_color', obj.name, c); end
        function set_transparency(obj, val), call_mex('slice_plane_set_transparency', obj.name, val); end
    end
end
