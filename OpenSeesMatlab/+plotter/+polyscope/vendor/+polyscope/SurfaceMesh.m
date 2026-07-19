classdef SurfaceMesh < handle
    %SURFACEMESH MATLAB wrapper for a Polyscope surface mesh structure.

    properties (SetAccess = private)
        name
    end

    methods
        function obj = SurfaceMesh(name)
            obj.name = name;
        end

        function n = n_vertices(obj)
            n = call_mex('surface_mesh_n_vertices', obj.name);
        end

        function n = n_faces(obj)
            n = call_mex('surface_mesh_n_faces', obj.name);
        end

        function update_vertex_positions(obj, vertices)
            call_mex('surface_mesh_update_vertex_positions', obj.name, vertices);
        end

        function set_enabled(obj, val)
            call_mex('surface_mesh_set_enabled', obj.name, val);
        end

        function set_color(obj, c)
            call_mex('surface_mesh_set_color', obj.name, c);
        end

        function c = get_color(obj)
            c = call_mex('surface_mesh_get_color', obj.name);
        end

        function set_edge_color(obj, c)
            call_mex('surface_mesh_set_edge_color', obj.name, c);
        end

        function set_edge_width(obj, w)
            call_mex('surface_mesh_set_edge_width', obj.name, w);
        end

        function set_material(obj, m)
            call_mex('surface_mesh_set_material', obj.name, m);
        end

        function m = get_material(obj)
            m = call_mex('surface_mesh_get_material', obj.name);
        end

        function set_smooth_shade(obj, val)
            call_mex('surface_mesh_set_smooth_shade', obj.name, val);
        end

        function set_transparency(obj, t)
            call_mex('surface_mesh_set_transparency', obj.name, t);
        end

        function set_back_face_policy(obj, val)
            call_mex('surface_mesh_set_back_face_policy', obj.name, char(string(val)));
        end

        function set_back_face_color(obj, c)
            call_mex('surface_mesh_set_back_face_color', obj.name, c);
        end

        % === Quantities ===================================================
        function add_vertex_scalar_quantity(obj, qname, vals, varargin)
            call_mex('surface_mesh_add_vertex_scalar_quantity', obj.name, qname, vals, varargin{:});
        end

        function add_face_scalar_quantity(obj, qname, vals, varargin)
            call_mex('surface_mesh_add_face_scalar_quantity', obj.name, qname, vals, varargin{:});
        end

        function add_vertex_color_quantity(obj, qname, vals, varargin)
            call_mex('surface_mesh_add_vertex_color_quantity', obj.name, qname, vals, varargin{:});
        end

        function add_face_color_quantity(obj, qname, vals, varargin)
            call_mex('surface_mesh_add_face_color_quantity', obj.name, qname, vals, varargin{:});
        end

        function add_vertex_vector_quantity(obj, qname, vals, varargin)
            call_mex('surface_mesh_add_vertex_vector_quantity', obj.name, qname, vals, varargin{:});
        end

        function add_face_vector_quantity(obj, qname, vals, varargin)
            call_mex('surface_mesh_add_face_vector_quantity', obj.name, qname, vals, varargin{:});
        end
    end
end
