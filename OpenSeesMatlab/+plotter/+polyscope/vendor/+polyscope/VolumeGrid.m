classdef VolumeGrid < handle
    %VOLUMEGRID MATLAB wrapper for a Polyscope volume grid structure.

    properties (SetAccess = private)
        name
    end

    methods
        function obj = VolumeGrid(name)
            obj.name = name;
        end

        function n = n_nodes(obj)
            n = call_mex('volume_grid_n_nodes', obj.name);
        end

        function n = n_cells(obj)
            n = call_mex('volume_grid_n_cells', obj.name);
        end

        function s = grid_spacing(obj)
            s = call_mex('volume_grid_grid_spacing', obj.name);
        end

        function d = get_grid_node_dim(obj)
            d = call_mex('volume_grid_get_grid_node_dim', obj.name);
        end

        function d = get_grid_cell_dim(obj)
            d = call_mex('volume_grid_get_grid_cell_dim', obj.name);
        end

        function b = get_bound_min(obj)
            b = call_mex('volume_grid_get_bound_min', obj.name);
        end

        function b = get_bound_max(obj)
            b = call_mex('volume_grid_get_bound_max', obj.name);
        end

        function set_enabled(obj, val)
            call_mex('volume_grid_set_enabled', obj.name, val);
        end

        function set_color(obj, c)
            call_mex('volume_grid_set_color', obj.name, c);
        end

        function c = get_color(obj)
            c = call_mex('volume_grid_get_color', obj.name);
        end

        function set_edge_color(obj, c)
            call_mex('volume_grid_set_edge_color', obj.name, c);
        end

        function c = get_edge_color(obj)
            c = call_mex('volume_grid_get_edge_color', obj.name);
        end

        function set_edge_width(obj, w)
            call_mex('volume_grid_set_edge_width', obj.name, w);
        end

        function w = get_edge_width(obj)
            w = call_mex('volume_grid_get_edge_width', obj.name);
        end

        function set_material(obj, m)
            call_mex('volume_grid_set_material', obj.name, m);
        end

        function m = get_material(obj)
            m = call_mex('volume_grid_get_material', obj.name);
        end

        function set_cube_size_factor(obj, v)
            call_mex('volume_grid_set_cube_size_factor', obj.name, v);
        end

        function v = get_cube_size_factor(obj)
            v = call_mex('volume_grid_get_cube_size_factor', obj.name);
        end

        function mark_nodes_as_used(obj)
            call_mex('volume_grid_mark_nodes_as_used', obj.name);
        end

        function mark_cells_as_used(obj)
            call_mex('volume_grid_mark_cells_as_used', obj.name);
        end

        % === Quantities ===================================================
        function add_node_scalar_quantity(obj, qname, vals, varargin)
            call_mex('volume_grid_add_node_scalar_quantity', obj.name, qname, vals, varargin{:});
        end

        function add_cell_scalar_quantity(obj, qname, vals, varargin)
            call_mex('volume_grid_add_cell_scalar_quantity', obj.name, qname, vals, varargin{:});
        end
    end
end
