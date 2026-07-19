classdef SparseVolumeGrid < handle
    %SPARSEVOLUMEGRID MATLAB wrapper for a Polyscope sparse volume grid structure.

    properties (SetAccess = private)
        name
    end

    methods
        function obj = SparseVolumeGrid(name)
            obj.name = name;
        end

        function n = n_cells(obj)
            n = call_mex('sparse_volume_grid_n_cells', obj.name);
        end

        function n = n_nodes(obj)
            n = call_mex('sparse_volume_grid_n_nodes', obj.name);
        end

        function o = get_origin(obj)
            o = call_mex('sparse_volume_grid_get_origin', obj.name);
        end

        function w = get_grid_cell_width(obj)
            w = call_mex('sparse_volume_grid_get_grid_cell_width', obj.name);
        end

        function c = get_occupied_cells(obj)
            c = call_mex('sparse_volume_grid_get_occupied_cells', obj.name);
        end

        function set_enabled(obj, val)
            call_mex('sparse_volume_grid_set_enabled', obj.name, val);
        end

        function set_color(obj, c)
            call_mex('sparse_volume_grid_set_color', obj.name, c);
        end

        function c = get_color(obj)
            c = call_mex('sparse_volume_grid_get_color', obj.name);
        end

        function set_edge_color(obj, c)
            call_mex('sparse_volume_grid_set_edge_color', obj.name, c);
        end

        function c = get_edge_color(obj)
            c = call_mex('sparse_volume_grid_get_edge_color', obj.name);
        end

        function set_edge_width(obj, w)
            call_mex('sparse_volume_grid_set_edge_width', obj.name, w);
        end

        function w = get_edge_width(obj)
            w = call_mex('sparse_volume_grid_get_edge_width', obj.name);
        end

        function set_material(obj, m)
            call_mex('sparse_volume_grid_set_material', obj.name, m);
        end

        function m = get_material(obj)
            m = call_mex('sparse_volume_grid_get_material', obj.name);
        end

        function set_cube_size_factor(obj, v)
            call_mex('sparse_volume_grid_set_cube_size_factor', obj.name, v);
        end

        function v = get_cube_size_factor(obj)
            v = call_mex('sparse_volume_grid_get_cube_size_factor', obj.name);
        end

        function set_render_mode(obj, mode)
            call_mex('sparse_volume_grid_set_render_mode', obj.name, mode);
        end

        function set_wireframe_radius(obj, v)
            call_mex('sparse_volume_grid_set_wireframe_radius', obj.name, v);
        end

        function set_wireframe_color(obj, c)
            call_mex('sparse_volume_grid_set_wireframe_color', obj.name, c);
        end

        function mark_nodes_as_used(obj)
            call_mex('sparse_volume_grid_mark_nodes_as_used', obj.name);
        end

        % === Quantities ===================================================
        function add_cell_scalar_quantity(obj, qname, vals, varargin)
            call_mex('sparse_volume_grid_add_cell_scalar_quantity', obj.name, qname, vals, varargin{:});
        end

        function add_node_scalar_quantity(obj, qname, node_indices, vals, varargin)
            call_mex('sparse_volume_grid_add_node_scalar_quantity', obj.name, qname, node_indices, vals, varargin{:});
        end

        function add_cell_color_quantity(obj, qname, colors, varargin)
            call_mex('sparse_volume_grid_add_cell_color_quantity', obj.name, qname, colors, varargin{:});
        end

        function add_node_color_quantity(obj, qname, node_indices, colors, varargin)
            call_mex('sparse_volume_grid_add_node_color_quantity', obj.name, qname, node_indices, colors, varargin{:});
        end
    end
end
