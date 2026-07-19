classdef ImDrawList < handle
    %IMDRAWLIST MATLAB wrapper for an ImDrawList object.
    %   Holds a 64-bit handle to the underlying C++ ImDrawList pointer.
    %   The C++ object is owned by ImGui and is not freed by this class.

    properties (Access = private)
        Handle
    end

    methods
        function obj = ImDrawList(handle)
            obj.Handle = handle;
        end

        function v = get.Handle(obj)
            v = obj.Handle;
        end

        function AddLine(obj, p1, p2, col, thickness)
            if nargin < 5, thickness = 1.0; end
            call_mex('imgui_drawlist_add_line', obj.Handle, p1, p2, col, thickness);
        end

        function AddRect(obj, p_min, p_max, col, rounding, flags, thickness)
            if nargin < 5, rounding = 0; end
            if nargin < 6, flags = 0; end
            if nargin < 7, thickness = 1.0; end
            call_mex('imgui_drawlist_add_rect', obj.Handle, p_min, p_max, col, rounding, flags, thickness);
        end

        function AddRectFilled(obj, p_min, p_max, col, rounding, flags)
            if nargin < 5, rounding = 0; end
            if nargin < 6, flags = 0; end
            call_mex('imgui_drawlist_add_rect_filled', obj.Handle, p_min, p_max, col, rounding, flags);
        end

        function AddCircle(obj, center, radius, col, num_segments, thickness)
            if nargin < 5, num_segments = 0; end
            if nargin < 6, thickness = 1.0; end
            call_mex('imgui_drawlist_add_circle', obj.Handle, center, radius, col, num_segments, thickness);
        end

        function AddCircleFilled(obj, center, radius, col, num_segments)
            if nargin < 5, num_segments = 0; end
            call_mex('imgui_drawlist_add_circle_filled', obj.Handle, center, radius, col, num_segments);
        end

        function AddText(obj, pos, col, text)
            call_mex('imgui_drawlist_add_text', obj.Handle, pos, col, text);
        end

        function AddTriangle(obj, p1, p2, p3, col, thickness)
            if nargin < 6, thickness = 1.0; end
            call_mex('imgui_drawlist_add_triangle', obj.Handle, p1, p2, p3, col, thickness);
        end

        function AddTriangleFilled(obj, p1, p2, p3, col)
            call_mex('imgui_drawlist_add_triangle_filled', obj.Handle, p1, p2, p3, col);
        end

        function PathClear(obj)
            call_mex('imgui_drawlist_path_clear', obj.Handle);
        end

        function PathLineTo(obj, pos)
            call_mex('imgui_drawlist_path_line_to', obj.Handle, pos);
        end

        function PathStroke(obj, col, flags, thickness)
            if nargin < 3, flags = 0; end
            if nargin < 4, thickness = 1.0; end
            call_mex('imgui_drawlist_path_stroke', obj.Handle, col, flags, thickness);
        end

        function PathFillConvex(obj, col)
            call_mex('imgui_drawlist_path_fill_convex', obj.Handle, col);
        end

        function PushClipRect(obj, clip_rect_min, clip_rect_max, intersect_current)
            if nargin < 4, intersect_current = false; end
            call_mex('imgui_drawlist_push_clip_rect', obj.Handle, clip_rect_min, clip_rect_max, intersect_current);
        end

        function PopClipRect(obj)
            call_mex('imgui_drawlist_pop_clip_rect', obj.Handle);
        end

        function v = GetClipRectMin(obj)
            v = call_mex('imgui_drawlist_get_clip_rect_min', obj.Handle);
        end

        function v = GetClipRectMax(obj)
            v = call_mex('imgui_drawlist_get_clip_rect_max', obj.Handle);
        end
    end
end
