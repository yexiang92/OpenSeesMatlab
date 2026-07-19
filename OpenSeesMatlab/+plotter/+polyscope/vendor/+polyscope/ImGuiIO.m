classdef ImGuiIO < handle
    %IMGUIIO MATLAB wrapper for an ImGuiIO object.
    %   Holds a 64-bit handle to the underlying C++ ImGuiIO pointer.
    %   The C++ object is owned by ImGui and is not freed by this class.

    properties (Access = private)
        Handle
    end

    properties (Dependent)
        ConfigFlags
        BackendFlags
        DisplaySize
        DeltaTime
        IniSavingRate
        IniFilename
        LogFilename
        FontAllowUserScaling
        DisplayFramebufferScale
        ConfigNavSwapGamepadButtons
        ConfigNavMoveSetMousePos
        ConfigNavCaptureKeyboard
        ConfigNavEscapeClearFocusItem
        ConfigNavEscapeClearFocusWindow
        ConfigNavCursorVisibleAuto
        ConfigNavCursorVisibleAlways
        MouseDrawCursor
        ConfigMacOSXBehaviors
        MouseDoubleClickTime
        MouseDoubleClickMaxDist
        MouseDragThreshold
        KeyRepeatDelay
        KeyRepeatRate
        BackendPlatformName
        BackendRendererName
        MousePos
    end

    properties (Dependent, SetAccess = private)
        WantCaptureMouse
        WantCaptureKeyboard
        WantTextInput
        WantSetMousePos
        WantSaveIniSettings
        NavActive
        NavVisible
        Framerate
        MouseWheel
        MouseWheelH
        KeyCtrl
        KeyShift
        KeyAlt
        KeySuper
        KeyMods
        Fonts
        FontDefault
    end

    methods
        function obj = ImGuiIO(handle)
            obj.Handle = handle;
        end

        function v = get.Handle(obj)
            v = obj.Handle;
        end

        function v = get.ConfigFlags(obj)
            v = call_mex('imgui_io_get', obj.Handle, 'ConfigFlags');
        end
        function set.ConfigFlags(obj, v)
            call_mex('imgui_io_set', obj.Handle, 'ConfigFlags', v);
        end

        function v = get.BackendFlags(obj)
            v = call_mex('imgui_io_get', obj.Handle, 'BackendFlags');
        end
        function set.BackendFlags(obj, v)
            call_mex('imgui_io_set', obj.Handle, 'BackendFlags', v);
        end

        function v = get.DisplaySize(obj)
            v = call_mex('imgui_io_get', obj.Handle, 'DisplaySize');
        end
        function set.DisplaySize(obj, v)
            call_mex('imgui_io_set', obj.Handle, 'DisplaySize', v);
        end

        function v = get.DeltaTime(obj)
            v = call_mex('imgui_io_get', obj.Handle, 'DeltaTime');
        end
        function set.DeltaTime(obj, v)
            call_mex('imgui_io_set', obj.Handle, 'DeltaTime', v);
        end

        function v = get.IniSavingRate(obj)
            v = call_mex('imgui_io_get', obj.Handle, 'IniSavingRate');
        end
        function set.IniSavingRate(obj, v)
            call_mex('imgui_io_set', obj.Handle, 'IniSavingRate', v);
        end

        function v = get.IniFilename(obj)
            v = call_mex('imgui_io_get', obj.Handle, 'IniFilename');
        end
        function set.IniFilename(obj, v)
            call_mex('imgui_io_set', obj.Handle, 'IniFilename', v);
        end

        function v = get.LogFilename(obj)
            v = call_mex('imgui_io_get', obj.Handle, 'LogFilename');
        end
        function set.LogFilename(obj, v)
            call_mex('imgui_io_set', obj.Handle, 'LogFilename', v);
        end

        function v = get.FontAllowUserScaling(obj)
            v = call_mex('imgui_io_get', obj.Handle, 'FontAllowUserScaling');
        end
        function set.FontAllowUserScaling(obj, v)
            call_mex('imgui_io_set', obj.Handle, 'FontAllowUserScaling', v);
        end

        function v = get.DisplayFramebufferScale(obj)
            v = call_mex('imgui_io_get', obj.Handle, 'DisplayFramebufferScale');
        end
        function set.DisplayFramebufferScale(obj, v)
            call_mex('imgui_io_set', obj.Handle, 'DisplayFramebufferScale', v);
        end

        function v = get.ConfigNavSwapGamepadButtons(obj)
            v = call_mex('imgui_io_get', obj.Handle, 'ConfigNavSwapGamepadButtons');
        end
        function set.ConfigNavSwapGamepadButtons(obj, v)
            call_mex('imgui_io_set', obj.Handle, 'ConfigNavSwapGamepadButtons', v);
        end

        function v = get.ConfigNavMoveSetMousePos(obj)
            v = call_mex('imgui_io_get', obj.Handle, 'ConfigNavMoveSetMousePos');
        end
        function set.ConfigNavMoveSetMousePos(obj, v)
            call_mex('imgui_io_set', obj.Handle, 'ConfigNavMoveSetMousePos', v);
        end

        function v = get.ConfigNavCaptureKeyboard(obj)
            v = call_mex('imgui_io_get', obj.Handle, 'ConfigNavCaptureKeyboard');
        end
        function set.ConfigNavCaptureKeyboard(obj, v)
            call_mex('imgui_io_set', obj.Handle, 'ConfigNavCaptureKeyboard', v);
        end

        function v = get.ConfigNavEscapeClearFocusItem(obj)
            v = call_mex('imgui_io_get', obj.Handle, 'ConfigNavEscapeClearFocusItem');
        end
        function set.ConfigNavEscapeClearFocusItem(obj, v)
            call_mex('imgui_io_set', obj.Handle, 'ConfigNavEscapeClearFocusItem', v);
        end

        function v = get.ConfigNavEscapeClearFocusWindow(obj)
            v = call_mex('imgui_io_get', obj.Handle, 'ConfigNavEscapeClearFocusWindow');
        end
        function set.ConfigNavEscapeClearFocusWindow(obj, v)
            call_mex('imgui_io_set', obj.Handle, 'ConfigNavEscapeClearFocusWindow', v);
        end

        function v = get.ConfigNavCursorVisibleAuto(obj)
            v = call_mex('imgui_io_get', obj.Handle, 'ConfigNavCursorVisibleAuto');
        end
        function set.ConfigNavCursorVisibleAuto(obj, v)
            call_mex('imgui_io_set', obj.Handle, 'ConfigNavCursorVisibleAuto', v);
        end

        function v = get.ConfigNavCursorVisibleAlways(obj)
            v = call_mex('imgui_io_get', obj.Handle, 'ConfigNavCursorVisibleAlways');
        end
        function set.ConfigNavCursorVisibleAlways(obj, v)
            call_mex('imgui_io_set', obj.Handle, 'ConfigNavCursorVisibleAlways', v);
        end

        function v = get.MouseDrawCursor(obj)
            v = call_mex('imgui_io_get', obj.Handle, 'MouseDrawCursor');
        end
        function set.MouseDrawCursor(obj, v)
            call_mex('imgui_io_set', obj.Handle, 'MouseDrawCursor', v);
        end

        function v = get.ConfigMacOSXBehaviors(obj)
            v = call_mex('imgui_io_get', obj.Handle, 'ConfigMacOSXBehaviors');
        end
        function set.ConfigMacOSXBehaviors(obj, v)
            call_mex('imgui_io_set', obj.Handle, 'ConfigMacOSXBehaviors', v);
        end

        function v = get.MouseDoubleClickTime(obj)
            v = call_mex('imgui_io_get', obj.Handle, 'MouseDoubleClickTime');
        end
        function set.MouseDoubleClickTime(obj, v)
            call_mex('imgui_io_set', obj.Handle, 'MouseDoubleClickTime', v);
        end

        function v = get.MouseDoubleClickMaxDist(obj)
            v = call_mex('imgui_io_get', obj.Handle, 'MouseDoubleClickMaxDist');
        end
        function set.MouseDoubleClickMaxDist(obj, v)
            call_mex('imgui_io_set', obj.Handle, 'MouseDoubleClickMaxDist', v);
        end

        function v = get.MouseDragThreshold(obj)
            v = call_mex('imgui_io_get', obj.Handle, 'MouseDragThreshold');
        end
        function set.MouseDragThreshold(obj, v)
            call_mex('imgui_io_set', obj.Handle, 'MouseDragThreshold', v);
        end

        function v = get.KeyRepeatDelay(obj)
            v = call_mex('imgui_io_get', obj.Handle, 'KeyRepeatDelay');
        end
        function set.KeyRepeatDelay(obj, v)
            call_mex('imgui_io_set', obj.Handle, 'KeyRepeatDelay', v);
        end

        function v = get.KeyRepeatRate(obj)
            v = call_mex('imgui_io_get', obj.Handle, 'KeyRepeatRate');
        end
        function set.KeyRepeatRate(obj, v)
            call_mex('imgui_io_set', obj.Handle, 'KeyRepeatRate', v);
        end

        function v = get.BackendPlatformName(obj)
            v = call_mex('imgui_io_get', obj.Handle, 'BackendPlatformName');
        end
        function set.BackendPlatformName(obj, v)
            call_mex('imgui_io_set', obj.Handle, 'BackendPlatformName', v);
        end

        function v = get.BackendRendererName(obj)
            v = call_mex('imgui_io_get', obj.Handle, 'BackendRendererName');
        end
        function set.BackendRendererName(obj, v)
            call_mex('imgui_io_set', obj.Handle, 'BackendRendererName', v);
        end

        function v = get.WantCaptureMouse(obj)
            v = call_mex('imgui_io_get', obj.Handle, 'WantCaptureMouse');
        end

        function v = get.WantCaptureKeyboard(obj)
            v = call_mex('imgui_io_get', obj.Handle, 'WantCaptureKeyboard');
        end

        function v = get.WantTextInput(obj)
            v = call_mex('imgui_io_get', obj.Handle, 'WantTextInput');
        end

        function v = get.WantSetMousePos(obj)
            v = call_mex('imgui_io_get', obj.Handle, 'WantSetMousePos');
        end

        function v = get.WantSaveIniSettings(obj)
            v = call_mex('imgui_io_get', obj.Handle, 'WantSaveIniSettings');
        end

        function v = get.NavActive(obj)
            v = call_mex('imgui_io_get', obj.Handle, 'NavActive');
        end

        function v = get.NavVisible(obj)
            v = call_mex('imgui_io_get', obj.Handle, 'NavVisible');
        end

        function v = get.Framerate(obj)
            v = call_mex('imgui_io_get', obj.Handle, 'Framerate');
        end

        function v = get.MousePos(obj)
            v = call_mex('imgui_io_get', obj.Handle, 'MousePos');
        end
        function set.MousePos(obj, v)
            call_mex('imgui_io_set', obj.Handle, 'MousePos', v);
        end

        function v = get.MouseWheel(obj)
            v = call_mex('imgui_io_get', obj.Handle, 'MouseWheel');
        end

        function v = get.MouseWheelH(obj)
            v = call_mex('imgui_io_get', obj.Handle, 'MouseWheelH');
        end

        function v = get.KeyCtrl(obj)
            v = call_mex('imgui_io_get', obj.Handle, 'KeyCtrl');
        end

        function v = get.KeyShift(obj)
            v = call_mex('imgui_io_get', obj.Handle, 'KeyShift');
        end

        function v = get.KeyAlt(obj)
            v = call_mex('imgui_io_get', obj.Handle, 'KeyAlt');
        end

        function v = get.KeySuper(obj)
            v = call_mex('imgui_io_get', obj.Handle, 'KeySuper');
        end

        function v = get.KeyMods(obj)
            v = call_mex('imgui_io_get', obj.Handle, 'KeyMods');
        end

        function v = get.Fonts(obj)
            v = call_mex('imgui_io_get', obj.Handle, 'Fonts');
        end

        function v = get.FontDefault(obj)
            v = call_mex('imgui_io_get', obj.Handle, 'FontDefault');
        end
    end
end
