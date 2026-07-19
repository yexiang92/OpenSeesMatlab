classdef TransformationGizmo < handle
    %TRANSFORMATIONGIZMO MATLAB wrapper for a Polyscope transformation gizmo.

    properties (SetAccess = private)
        name
    end

    methods
        function obj = TransformationGizmo(name)
            obj.name = name;
        end

        function name = get_name(obj)
            name = call_mex('transformation_gizmo_get_name', obj.name);
        end

        function remove(obj)
            call_mex('transformation_gizmo_remove', obj.name);
        end

        function set_enabled(obj, val)
            call_mex('transformation_gizmo_set_enabled', obj.name, val);
        end

        function val = get_enabled(obj)
            val = call_mex('transformation_gizmo_get_enabled', obj.name);
        end

        function set_transform(obj, transform)
            call_mex('transformation_gizmo_set_transform', obj.name, transform);
        end

        function transform = get_transform(obj)
            transform = call_mex('transformation_gizmo_get_transform', obj.name);
        end

        function set_position(obj, position)
            call_mex('transformation_gizmo_set_position', obj.name, position);
        end

        function position = get_position(obj)
            position = call_mex('transformation_gizmo_get_position', obj.name);
        end

        function set_allow_translation(obj, val)
            call_mex('transformation_gizmo_set_allow_translation', obj.name, val);
        end

        function val = get_allow_translation(obj)
            val = call_mex('transformation_gizmo_get_allow_translation', obj.name);
        end

        function set_allow_rotation(obj, val)
            call_mex('transformation_gizmo_set_allow_rotation', obj.name, val);
        end

        function val = get_allow_rotation(obj)
            val = call_mex('transformation_gizmo_get_allow_rotation', obj.name);
        end

        function set_allow_scaling(obj, val)
            call_mex('transformation_gizmo_set_allow_scaling', obj.name, val);
        end

        function val = get_allow_scaling(obj)
            val = call_mex('transformation_gizmo_get_allow_scaling', obj.name);
        end

        function set_allow_nonuniform_scaling(obj, val)
            call_mex('transformation_gizmo_set_allow_nonuniform_scaling', obj.name, val);
        end

        function val = get_allow_nonuniform_scaling(obj)
            val = call_mex('transformation_gizmo_get_allow_nonuniform_scaling', obj.name);
        end

        function set_interact_in_local_space(obj, val)
            call_mex('transformation_gizmo_set_interact_in_local_space', obj.name, val);
        end

        function val = get_interact_in_local_space(obj)
            val = call_mex('transformation_gizmo_get_interact_in_local_space', obj.name);
        end

        function set_gizmo_size(obj, val)
            call_mex('transformation_gizmo_set_gizmo_size', obj.name, val);
        end

        function val = get_gizmo_size(obj)
            val = call_mex('transformation_gizmo_get_gizmo_size', obj.name);
        end

        function set_gizmo_scale(obj, val)
            call_mex('transformation_gizmo_set_gizmo_scale', obj.name, val);
        end

        function val = get_gizmo_scale(obj)
            val = call_mex('transformation_gizmo_get_gizmo_scale', obj.name);
        end

        function build_inline_transform_ui(obj)
            call_mex('transformation_gizmo_build_inline_transform_ui', obj.name);
        end
    end
end
