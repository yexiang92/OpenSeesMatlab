classdef ImGuiStyle < handle
    %IMGUISTYLE MATLAB wrapper for an ImGuiStyle object.
    %   Holds a 64-bit handle to the underlying C++ ImGuiStyle pointer.
    %   The C++ object is owned by ImGui and is not freed by this class.

    properties (Access = private)
        Handle
    end

    properties (Dependent)
        Alpha
        DisabledAlpha
        WindowPadding
        WindowRounding
        WindowBorderSize
        WindowMinSize
        WindowTitleAlign
        ChildRounding
        ChildBorderSize
        PopupRounding
        PopupBorderSize
        FramePadding
        FrameRounding
        FrameBorderSize
        ItemSpacing
        ItemInnerSpacing
        CellPadding
        TouchExtraPadding
        IndentSpacing
        ColumnsMinSpacing
        ScrollbarSize
        ScrollbarRounding
        ScrollbarPadding
        GrabMinSize
        GrabRounding
        LogSliderDeadzone
        ImageBorderSize
        TabRounding
        TabBorderSize
        TabCloseButtonMinWidthSelected
        TabCloseButtonMinWidthUnselected
        TabBarBorderSize
        TabBarOverlineSize
        TableAngledHeadersAngle
        TableAngledHeadersTextAlign
        TreeLinesFlags
        TreeLinesSize
        TreeLinesRounding
        DragDropTargetRounding
        DragDropTargetBorderSize
        DragDropTargetPadding
        ColorButtonPosition
        ButtonTextAlign
        SelectableTextAlign
        SeparatorTextBorderSize
        SeparatorTextAlign
        SeparatorTextPadding
        DisplayWindowPadding
        DisplaySafeAreaPadding
        MouseCursorScale
        AntiAliasedLines
        AntiAliasedLinesUseTex
        AntiAliasedFill
        CurveTessellationTol
        CircleTessellationMaxError
        HoverStationaryDelay
        HoverDelayShort
        HoverDelayNormal
        HoverFlagsForTooltipMouse
        HoverFlagsForTooltipNav
    end

    methods
        function obj = ImGuiStyle(handle)
            obj.Handle = handle;
        end

        function v = get.Handle(obj)
            v = obj.Handle;
        end

        function v = get.Alpha(obj)
            v = call_mex('imgui_style_get', obj.Handle, 'Alpha');
        end
        function set.Alpha(obj, v)
            call_mex('imgui_style_set', obj.Handle, 'Alpha', v);
        end

        function v = get.DisabledAlpha(obj)
            v = call_mex('imgui_style_get', obj.Handle, 'DisabledAlpha');
        end
        function set.DisabledAlpha(obj, v)
            call_mex('imgui_style_set', obj.Handle, 'DisabledAlpha', v);
        end

        function v = get.WindowPadding(obj)
            v = call_mex('imgui_style_get', obj.Handle, 'WindowPadding');
        end
        function set.WindowPadding(obj, v)
            call_mex('imgui_style_set', obj.Handle, 'WindowPadding', v);
        end

        function v = get.WindowRounding(obj)
            v = call_mex('imgui_style_get', obj.Handle, 'WindowRounding');
        end
        function set.WindowRounding(obj, v)
            call_mex('imgui_style_set', obj.Handle, 'WindowRounding', v);
        end

        function v = get.WindowBorderSize(obj)
            v = call_mex('imgui_style_get', obj.Handle, 'WindowBorderSize');
        end
        function set.WindowBorderSize(obj, v)
            call_mex('imgui_style_set', obj.Handle, 'WindowBorderSize', v);
        end

        function v = get.WindowMinSize(obj)
            v = call_mex('imgui_style_get', obj.Handle, 'WindowMinSize');
        end
        function set.WindowMinSize(obj, v)
            call_mex('imgui_style_set', obj.Handle, 'WindowMinSize', v);
        end

        function v = get.WindowTitleAlign(obj)
            v = call_mex('imgui_style_get', obj.Handle, 'WindowTitleAlign');
        end
        function set.WindowTitleAlign(obj, v)
            call_mex('imgui_style_set', obj.Handle, 'WindowTitleAlign', v);
        end

        function v = get.ChildRounding(obj)
            v = call_mex('imgui_style_get', obj.Handle, 'ChildRounding');
        end
        function set.ChildRounding(obj, v)
            call_mex('imgui_style_set', obj.Handle, 'ChildRounding', v);
        end

        function v = get.ChildBorderSize(obj)
            v = call_mex('imgui_style_get', obj.Handle, 'ChildBorderSize');
        end
        function set.ChildBorderSize(obj, v)
            call_mex('imgui_style_set', obj.Handle, 'ChildBorderSize', v);
        end

        function v = get.PopupRounding(obj)
            v = call_mex('imgui_style_get', obj.Handle, 'PopupRounding');
        end
        function set.PopupRounding(obj, v)
            call_mex('imgui_style_set', obj.Handle, 'PopupRounding', v);
        end

        function v = get.PopupBorderSize(obj)
            v = call_mex('imgui_style_get', obj.Handle, 'PopupBorderSize');
        end
        function set.PopupBorderSize(obj, v)
            call_mex('imgui_style_set', obj.Handle, 'PopupBorderSize', v);
        end

        function v = get.FramePadding(obj)
            v = call_mex('imgui_style_get', obj.Handle, 'FramePadding');
        end
        function set.FramePadding(obj, v)
            call_mex('imgui_style_set', obj.Handle, 'FramePadding', v);
        end

        function v = get.FrameRounding(obj)
            v = call_mex('imgui_style_get', obj.Handle, 'FrameRounding');
        end
        function set.FrameRounding(obj, v)
            call_mex('imgui_style_set', obj.Handle, 'FrameRounding', v);
        end

        function v = get.FrameBorderSize(obj)
            v = call_mex('imgui_style_get', obj.Handle, 'FrameBorderSize');
        end
        function set.FrameBorderSize(obj, v)
            call_mex('imgui_style_set', obj.Handle, 'FrameBorderSize', v);
        end

        function v = get.ItemSpacing(obj)
            v = call_mex('imgui_style_get', obj.Handle, 'ItemSpacing');
        end
        function set.ItemSpacing(obj, v)
            call_mex('imgui_style_set', obj.Handle, 'ItemSpacing', v);
        end

        function v = get.ItemInnerSpacing(obj)
            v = call_mex('imgui_style_get', obj.Handle, 'ItemInnerSpacing');
        end
        function set.ItemInnerSpacing(obj, v)
            call_mex('imgui_style_set', obj.Handle, 'ItemInnerSpacing', v);
        end

        function v = get.CellPadding(obj)
            v = call_mex('imgui_style_get', obj.Handle, 'CellPadding');
        end
        function set.CellPadding(obj, v)
            call_mex('imgui_style_set', obj.Handle, 'CellPadding', v);
        end

        function v = get.TouchExtraPadding(obj)
            v = call_mex('imgui_style_get', obj.Handle, 'TouchExtraPadding');
        end
        function set.TouchExtraPadding(obj, v)
            call_mex('imgui_style_set', obj.Handle, 'TouchExtraPadding', v);
        end

        function v = get.IndentSpacing(obj)
            v = call_mex('imgui_style_get', obj.Handle, 'IndentSpacing');
        end
        function set.IndentSpacing(obj, v)
            call_mex('imgui_style_set', obj.Handle, 'IndentSpacing', v);
        end

        function v = get.ColumnsMinSpacing(obj)
            v = call_mex('imgui_style_get', obj.Handle, 'ColumnsMinSpacing');
        end
        function set.ColumnsMinSpacing(obj, v)
            call_mex('imgui_style_set', obj.Handle, 'ColumnsMinSpacing', v);
        end

        function v = get.ScrollbarSize(obj)
            v = call_mex('imgui_style_get', obj.Handle, 'ScrollbarSize');
        end
        function set.ScrollbarSize(obj, v)
            call_mex('imgui_style_set', obj.Handle, 'ScrollbarSize', v);
        end

        function v = get.ScrollbarRounding(obj)
            v = call_mex('imgui_style_get', obj.Handle, 'ScrollbarRounding');
        end
        function set.ScrollbarRounding(obj, v)
            call_mex('imgui_style_set', obj.Handle, 'ScrollbarRounding', v);
        end

        function v = get.ScrollbarPadding(obj)
            v = call_mex('imgui_style_get', obj.Handle, 'ScrollbarPadding');
        end
        function set.ScrollbarPadding(obj, v)
            call_mex('imgui_style_set', obj.Handle, 'ScrollbarPadding', v);
        end

        function v = get.GrabMinSize(obj)
            v = call_mex('imgui_style_get', obj.Handle, 'GrabMinSize');
        end
        function set.GrabMinSize(obj, v)
            call_mex('imgui_style_set', obj.Handle, 'GrabMinSize', v);
        end

        function v = get.GrabRounding(obj)
            v = call_mex('imgui_style_get', obj.Handle, 'GrabRounding');
        end
        function set.GrabRounding(obj, v)
            call_mex('imgui_style_set', obj.Handle, 'GrabRounding', v);
        end

        function v = get.LogSliderDeadzone(obj)
            v = call_mex('imgui_style_get', obj.Handle, 'LogSliderDeadzone');
        end
        function set.LogSliderDeadzone(obj, v)
            call_mex('imgui_style_set', obj.Handle, 'LogSliderDeadzone', v);
        end

        function v = get.ImageBorderSize(obj)
            v = call_mex('imgui_style_get', obj.Handle, 'ImageBorderSize');
        end
        function set.ImageBorderSize(obj, v)
            call_mex('imgui_style_set', obj.Handle, 'ImageBorderSize', v);
        end

        function v = get.TabRounding(obj)
            v = call_mex('imgui_style_get', obj.Handle, 'TabRounding');
        end
        function set.TabRounding(obj, v)
            call_mex('imgui_style_set', obj.Handle, 'TabRounding', v);
        end

        function v = get.TabBorderSize(obj)
            v = call_mex('imgui_style_get', obj.Handle, 'TabBorderSize');
        end
        function set.TabBorderSize(obj, v)
            call_mex('imgui_style_set', obj.Handle, 'TabBorderSize', v);
        end

        function v = get.TabCloseButtonMinWidthSelected(obj)
            v = call_mex('imgui_style_get', obj.Handle, 'TabCloseButtonMinWidthSelected');
        end
        function set.TabCloseButtonMinWidthSelected(obj, v)
            call_mex('imgui_style_set', obj.Handle, 'TabCloseButtonMinWidthSelected', v);
        end

        function v = get.TabCloseButtonMinWidthUnselected(obj)
            v = call_mex('imgui_style_get', obj.Handle, 'TabCloseButtonMinWidthUnselected');
        end
        function set.TabCloseButtonMinWidthUnselected(obj, v)
            call_mex('imgui_style_set', obj.Handle, 'TabCloseButtonMinWidthUnselected', v);
        end

        function v = get.TabBarBorderSize(obj)
            v = call_mex('imgui_style_get', obj.Handle, 'TabBarBorderSize');
        end
        function set.TabBarBorderSize(obj, v)
            call_mex('imgui_style_set', obj.Handle, 'TabBarBorderSize', v);
        end

        function v = get.TabBarOverlineSize(obj)
            v = call_mex('imgui_style_get', obj.Handle, 'TabBarOverlineSize');
        end
        function set.TabBarOverlineSize(obj, v)
            call_mex('imgui_style_set', obj.Handle, 'TabBarOverlineSize', v);
        end

        function v = get.TableAngledHeadersAngle(obj)
            v = call_mex('imgui_style_get', obj.Handle, 'TableAngledHeadersAngle');
        end
        function set.TableAngledHeadersAngle(obj, v)
            call_mex('imgui_style_set', obj.Handle, 'TableAngledHeadersAngle', v);
        end

        function v = get.TableAngledHeadersTextAlign(obj)
            v = call_mex('imgui_style_get', obj.Handle, 'TableAngledHeadersTextAlign');
        end
        function set.TableAngledHeadersTextAlign(obj, v)
            call_mex('imgui_style_set', obj.Handle, 'TableAngledHeadersTextAlign', v);
        end

        function v = get.TreeLinesFlags(obj)
            v = call_mex('imgui_style_get', obj.Handle, 'TreeLinesFlags');
        end
        function set.TreeLinesFlags(obj, v)
            call_mex('imgui_style_set', obj.Handle, 'TreeLinesFlags', v);
        end

        function v = get.TreeLinesSize(obj)
            v = call_mex('imgui_style_get', obj.Handle, 'TreeLinesSize');
        end
        function set.TreeLinesSize(obj, v)
            call_mex('imgui_style_set', obj.Handle, 'TreeLinesSize', v);
        end

        function v = get.TreeLinesRounding(obj)
            v = call_mex('imgui_style_get', obj.Handle, 'TreeLinesRounding');
        end
        function set.TreeLinesRounding(obj, v)
            call_mex('imgui_style_set', obj.Handle, 'TreeLinesRounding', v);
        end

        function v = get.DragDropTargetRounding(obj)
            v = call_mex('imgui_style_get', obj.Handle, 'DragDropTargetRounding');
        end
        function set.DragDropTargetRounding(obj, v)
            call_mex('imgui_style_set', obj.Handle, 'DragDropTargetRounding', v);
        end

        function v = get.DragDropTargetBorderSize(obj)
            v = call_mex('imgui_style_get', obj.Handle, 'DragDropTargetBorderSize');
        end
        function set.DragDropTargetBorderSize(obj, v)
            call_mex('imgui_style_set', obj.Handle, 'DragDropTargetBorderSize', v);
        end

        function v = get.DragDropTargetPadding(obj)
            v = call_mex('imgui_style_get', obj.Handle, 'DragDropTargetPadding');
        end
        function set.DragDropTargetPadding(obj, v)
            call_mex('imgui_style_set', obj.Handle, 'DragDropTargetPadding', v);
        end

        function v = get.ColorButtonPosition(obj)
            v = call_mex('imgui_style_get', obj.Handle, 'ColorButtonPosition');
        end
        function set.ColorButtonPosition(obj, v)
            call_mex('imgui_style_set', obj.Handle, 'ColorButtonPosition', v);
        end

        function v = get.ButtonTextAlign(obj)
            v = call_mex('imgui_style_get', obj.Handle, 'ButtonTextAlign');
        end
        function set.ButtonTextAlign(obj, v)
            call_mex('imgui_style_set', obj.Handle, 'ButtonTextAlign', v);
        end

        function v = get.SelectableTextAlign(obj)
            v = call_mex('imgui_style_get', obj.Handle, 'SelectableTextAlign');
        end
        function set.SelectableTextAlign(obj, v)
            call_mex('imgui_style_set', obj.Handle, 'SelectableTextAlign', v);
        end

        function v = get.SeparatorTextBorderSize(obj)
            v = call_mex('imgui_style_get', obj.Handle, 'SeparatorTextBorderSize');
        end
        function set.SeparatorTextBorderSize(obj, v)
            call_mex('imgui_style_set', obj.Handle, 'SeparatorTextBorderSize', v);
        end

        function v = get.SeparatorTextAlign(obj)
            v = call_mex('imgui_style_get', obj.Handle, 'SeparatorTextAlign');
        end
        function set.SeparatorTextAlign(obj, v)
            call_mex('imgui_style_set', obj.Handle, 'SeparatorTextAlign', v);
        end

        function v = get.SeparatorTextPadding(obj)
            v = call_mex('imgui_style_get', obj.Handle, 'SeparatorTextPadding');
        end
        function set.SeparatorTextPadding(obj, v)
            call_mex('imgui_style_set', obj.Handle, 'SeparatorTextPadding', v);
        end

        function v = get.DisplayWindowPadding(obj)
            v = call_mex('imgui_style_get', obj.Handle, 'DisplayWindowPadding');
        end
        function set.DisplayWindowPadding(obj, v)
            call_mex('imgui_style_set', obj.Handle, 'DisplayWindowPadding', v);
        end

        function v = get.DisplaySafeAreaPadding(obj)
            v = call_mex('imgui_style_get', obj.Handle, 'DisplaySafeAreaPadding');
        end
        function set.DisplaySafeAreaPadding(obj, v)
            call_mex('imgui_style_set', obj.Handle, 'DisplaySafeAreaPadding', v);
        end

        function v = get.MouseCursorScale(obj)
            v = call_mex('imgui_style_get', obj.Handle, 'MouseCursorScale');
        end
        function set.MouseCursorScale(obj, v)
            call_mex('imgui_style_set', obj.Handle, 'MouseCursorScale', v);
        end

        function v = get.AntiAliasedLines(obj)
            v = call_mex('imgui_style_get', obj.Handle, 'AntiAliasedLines');
        end
        function set.AntiAliasedLines(obj, v)
            call_mex('imgui_style_set', obj.Handle, 'AntiAliasedLines', v);
        end

        function v = get.AntiAliasedLinesUseTex(obj)
            v = call_mex('imgui_style_get', obj.Handle, 'AntiAliasedLinesUseTex');
        end
        function set.AntiAliasedLinesUseTex(obj, v)
            call_mex('imgui_style_set', obj.Handle, 'AntiAliasedLinesUseTex', v);
        end

        function v = get.AntiAliasedFill(obj)
            v = call_mex('imgui_style_get', obj.Handle, 'AntiAliasedFill');
        end
        function set.AntiAliasedFill(obj, v)
            call_mex('imgui_style_set', obj.Handle, 'AntiAliasedFill', v);
        end

        function v = get.CurveTessellationTol(obj)
            v = call_mex('imgui_style_get', obj.Handle, 'CurveTessellationTol');
        end
        function set.CurveTessellationTol(obj, v)
            call_mex('imgui_style_set', obj.Handle, 'CurveTessellationTol', v);
        end

        function v = get.CircleTessellationMaxError(obj)
            v = call_mex('imgui_style_get', obj.Handle, 'CircleTessellationMaxError');
        end
        function set.CircleTessellationMaxError(obj, v)
            call_mex('imgui_style_set', obj.Handle, 'CircleTessellationMaxError', v);
        end

        function v = get.HoverStationaryDelay(obj)
            v = call_mex('imgui_style_get', obj.Handle, 'HoverStationaryDelay');
        end
        function set.HoverStationaryDelay(obj, v)
            call_mex('imgui_style_set', obj.Handle, 'HoverStationaryDelay', v);
        end

        function v = get.HoverDelayShort(obj)
            v = call_mex('imgui_style_get', obj.Handle, 'HoverDelayShort');
        end
        function set.HoverDelayShort(obj, v)
            call_mex('imgui_style_set', obj.Handle, 'HoverDelayShort', v);
        end

        function v = get.HoverDelayNormal(obj)
            v = call_mex('imgui_style_get', obj.Handle, 'HoverDelayNormal');
        end
        function set.HoverDelayNormal(obj, v)
            call_mex('imgui_style_set', obj.Handle, 'HoverDelayNormal', v);
        end

        function v = get.HoverFlagsForTooltipMouse(obj)
            v = call_mex('imgui_style_get', obj.Handle, 'HoverFlagsForTooltipMouse');
        end
        function set.HoverFlagsForTooltipMouse(obj, v)
            call_mex('imgui_style_set', obj.Handle, 'HoverFlagsForTooltipMouse', v);
        end

        function v = get.HoverFlagsForTooltipNav(obj)
            v = call_mex('imgui_style_get', obj.Handle, 'HoverFlagsForTooltipNav');
        end
        function set.HoverFlagsForTooltipNav(obj, v)
            call_mex('imgui_style_set', obj.Handle, 'HoverFlagsForTooltipNav', v);
        end

        function ScaleAllSizes(obj, scale_factor)
            call_mex('imgui_style_scale_all_sizes', obj.Handle, scale_factor);
        end
    end
end
