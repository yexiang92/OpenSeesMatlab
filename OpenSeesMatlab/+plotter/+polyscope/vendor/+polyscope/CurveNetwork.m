classdef CurveNetwork < handle
    %CURVENETWORK MATLAB wrapper for a Polyscope curve network structure.

    properties (SetAccess = private)
        name
    end

    methods
        function obj = CurveNetwork(name)
            obj.name = name;
        end

        function n = n_nodes(obj)
            n = call_mex('curve_network_n_nodes', obj.name);
        end

        function n = n_edges(obj)
            n = call_mex('curve_network_n_edges', obj.name);
        end

        function update_node_positions(obj, nodes)
            call_mex('curve_network_update_node_positions', obj.name, nodes);
        end

        function set_enabled(obj, val)
            call_mex('curve_network_set_enabled', obj.name, val);
        end

        function set_radius(obj, rad, relative)
            if nargin < 3, relative = true; end
            call_mex('curve_network_set_radius', obj.name, rad, relative);
        end

        function r = get_radius(obj)
            r = call_mex('curve_network_get_radius', obj.name);
        end

        function set_color(obj, c)
            call_mex('curve_network_set_color', obj.name, c);
        end

        function c = get_color(obj)
            c = call_mex('curve_network_get_color', obj.name);
        end

        function set_material(obj, m)
            call_mex('curve_network_set_material', obj.name, m);
        end

        function m = get_material(obj)
            m = call_mex('curve_network_get_material', obj.name);
        end

        function set_transparency(obj, t)
            call_mex('curve_network_set_transparency', obj.name, t);
        end

        function set_node_radius_quantity(obj, qname, autoscale)
            if nargin < 3, autoscale = true; end
            call_mex('curve_network_set_node_radius_quantity', obj.name, qname, autoscale);
        end

        function clear_node_radius_quantity(obj)
            call_mex('curve_network_clear_node_radius_quantity', obj.name);
        end

        function set_edge_radius_quantity(obj, qname, autoscale)
            if nargin < 3, autoscale = true; end
            call_mex('curve_network_set_edge_radius_quantity', obj.name, qname, autoscale);
        end

        function clear_edge_radius_quantity(obj)
            call_mex('curve_network_clear_edge_radius_quantity', obj.name);
        end

        % === Quantities ===================================================
        function add_node_scalar_quantity(obj, qname, vals, varargin)
            call_mex('curve_network_add_node_scalar_quantity', obj.name, qname, vals, varargin{:});
        end

        function add_edge_scalar_quantity(obj, qname, vals, varargin)
            call_mex('curve_network_add_edge_scalar_quantity', obj.name, qname, vals, varargin{:});
        end

        function add_node_color_quantity(obj, qname, vals, varargin)
            call_mex('curve_network_add_node_color_quantity', obj.name, qname, vals, varargin{:});
        end

        function add_edge_color_quantity(obj, qname, vals, varargin)
            call_mex('curve_network_add_edge_color_quantity', obj.name, qname, vals, varargin{:});
        end

        function add_node_vector_quantity(obj, qname, vals, varargin)
            call_mex('curve_network_add_node_vector_quantity', obj.name, qname, vals, varargin{:});
        end

        function add_edge_vector_quantity(obj, qname, vals, varargin)
            call_mex('curve_network_add_edge_vector_quantity', obj.name, qname, vals, varargin{:});
        end
    end
end
