classdef VolumeMesh < handle
    %VOLUMEMESH MATLAB wrapper for a Polyscope volume mesh structure.

    properties (SetAccess = private)
        name
    end

    methods
        function obj = VolumeMesh(name)
            obj.name = name;
        end

        function n = n_vertices(obj)
            n = call_mex('volume_mesh_n_vertices', obj.name);
        end

        function n = n_faces(obj)
            n = call_mex('volume_mesh_n_faces', obj.name);
        end

        function n = n_cells(obj)
            n = call_mex('volume_mesh_n_cells', obj.name);
        end

        function update_vertex_positions(obj, vertices)
            call_mex('volume_mesh_update_vertex_positions', obj.name, vertices);
        end

        function set_enabled(obj, val)
            call_mex('volume_mesh_set_enabled', obj.name, val);
        end

        function set_color(obj, c)
            call_mex('volume_mesh_set_color', obj.name, c);
        end

        function c = get_color(obj)
            c = call_mex('volume_mesh_get_color', obj.name);
        end

        function set_interior_color(obj, c)
            call_mex('volume_mesh_set_interior_color', obj.name, c);
        end

        function c = get_interior_color(obj)
            c = call_mex('volume_mesh_get_interior_color', obj.name);
        end

        function set_edge_color(obj, c)
            call_mex('volume_mesh_set_edge_color', obj.name, c);
        end

        function c = get_edge_color(obj)
            c = call_mex('volume_mesh_get_edge_color', obj.name);
        end

        function set_edge_width(obj, w)
            call_mex('volume_mesh_set_edge_width', obj.name, w);
        end

        function w = get_edge_width(obj)
            w = call_mex('volume_mesh_get_edge_width', obj.name);
        end

        function set_material(obj, m)
            call_mex('volume_mesh_set_material', obj.name, m);
        end

        function m = get_material(obj)
            m = call_mex('volume_mesh_get_material', obj.name);
        end

        function set_transparency(obj, t)
            call_mex('volume_mesh_set_transparency', obj.name, t);
        end

        % === Quantities ===================================================
        function add_vertex_scalar_quantity(obj, qname, vals, varargin)
            call_mex('volume_mesh_add_vertex_scalar_quantity', obj.name, qname, vals, varargin{:});
        end

        function add_cell_scalar_quantity(obj, qname, vals, varargin)
            call_mex('volume_mesh_add_cell_scalar_quantity', obj.name, qname, vals, varargin{:});
        end

        function add_vertex_color_quantity(obj, qname, vals, varargin)
            call_mex('volume_mesh_add_vertex_color_quantity', obj.name, qname, vals, varargin{:});
        end

        function add_cell_color_quantity(obj, qname, vals, varargin)
            call_mex('volume_mesh_add_cell_color_quantity', obj.name, qname, vals, varargin{:});
        end

        function add_vertex_vector_quantity(obj, qname, vals, varargin)
            call_mex('volume_mesh_add_vertex_vector_quantity', obj.name, qname, vals, varargin{:});
        end

        function add_cell_vector_quantity(obj, qname, vals, varargin)
            call_mex('volume_mesh_add_cell_vector_quantity', obj.name, qname, vals, varargin{:});
        end
    end
end
