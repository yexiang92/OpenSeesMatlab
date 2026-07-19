classdef PointCloud < handle
    %POINTCLOUD MATLAB wrapper for a Polyscope point cloud structure.
    %   Instances are returned by polyscope.Polyscope.register_point_cloud.

    properties (SetAccess = private)
        name
    end

    methods
        function obj = PointCloud(name)
            obj.name = name;
        end

        function n = n_points(obj)
            n = call_mex('point_cloud_n_points', obj.name);
        end

        function update_point_positions(obj, points)
            call_mex('point_cloud_update_point_positions', obj.name, points);
        end

        function set_enabled(obj, val)
            call_mex('point_cloud_set_enabled', obj.name, val);
        end

        function set_radius(obj, rad, relative)
            if nargin < 3, relative = true; end
            call_mex('point_cloud_set_radius', obj.name, rad, relative);
        end

        function r = get_radius(obj)
            r = call_mex('point_cloud_get_radius', obj.name);
        end

        function set_color(obj, c)
            call_mex('point_cloud_set_color', obj.name, c);
        end

        function c = get_color(obj)
            c = call_mex('point_cloud_get_color', obj.name);
        end

        function set_material(obj, m)
            call_mex('point_cloud_set_material', obj.name, m);
        end

        function m = get_material(obj)
            m = call_mex('point_cloud_get_material', obj.name);
        end

        function set_point_render_mode(obj, mode)
            call_mex('point_cloud_set_point_render_mode', obj.name, mode);
        end

        function m = get_point_render_mode(obj)
            m = call_mex('point_cloud_get_point_render_mode', obj.name);
        end

        function set_transparency(obj, t)
            call_mex('point_cloud_set_transparency', obj.name, t);
        end

        % === Quantities ===================================================
        function add_scalar_quantity(obj, qname, vals, varargin)
            call_mex('point_cloud_add_scalar_quantity', obj.name, qname, vals, varargin{:});
        end

        function add_color_quantity(obj, qname, vals, varargin)
            call_mex('point_cloud_add_color_quantity', obj.name, qname, vals, varargin{:});
        end

        function add_vector_quantity(obj, qname, vals, varargin)
            call_mex('point_cloud_add_vector_quantity', obj.name, qname, vals, varargin{:});
        end

        function add_parameterization_quantity(obj, qname, vals, varargin)
            call_mex('point_cloud_add_parameterization_quantity', obj.name, qname, vals, varargin{:});
        end
    end
end
