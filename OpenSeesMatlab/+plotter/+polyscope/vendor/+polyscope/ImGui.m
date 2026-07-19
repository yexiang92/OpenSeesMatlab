classdef ImGui < handle
    %IMGUI MATLAB wrapper for Dear ImGui functions exposed by Polyscope.
    %   Mirrors polyscope.imgui from the Python bindings.

    methods (Static)
        % === Constants =====================================================
        function v = get_constant(name)
            v = call_mex('imgui_get_constant', name);
        end

        % === Windows =======================================================
        function varargout = Begin(name, flags, open)
            if nargin < 2, flags = 0; end
            if nargin < 3
                varargout{1} = call_mex('imgui_begin', name, flags);
            else
                [varargout{1:2}] = call_mex('imgui_begin', name, flags, open);
            end
        end

        function End()
            call_mex('imgui_end');
        end

        function visible = BeginChild(name, size, child_flags, window_flags)
            if nargin < 2, size = [0, 0]; end
            if nargin < 3, child_flags = 0; end
            if nargin < 4, window_flags = 0; end
            visible = call_mex('imgui_begin_child', name, size, child_flags, window_flags);
        end

        function EndChild()
            call_mex('imgui_end_child');
        end

        function SetNextWindowPos(pos, cond, pivot)
            if nargin < 2, cond = int32(polyscope.ImGui.get_constant('ImGuiCond_Always')); end
            if nargin < 3, pivot = [0, 0]; end
            call_mex('imgui_set_next_window_pos', pos, cond, pivot);
        end

        function SetNextWindowSize(size, cond)
            if nargin < 2, cond = int32(polyscope.ImGui.get_constant('ImGuiCond_Always')); end
            call_mex('imgui_set_next_window_size', size, cond);
        end

        % === Text ==========================================================
        function Text(txt)
            call_mex('imgui_text', txt);
        end

        function TextUnformatted(txt)
            call_mex('imgui_text_unformatted', txt);
        end

        function TextColored(col, txt)
            call_mex('imgui_text_colored', col, txt);
        end

        function TextDisabled(txt)
            call_mex('imgui_text_disabled', txt);
        end

        function TextWrapped(txt)
            call_mex('imgui_text_wrapped', txt);
        end

        function LabelText(label, txt)
            call_mex('imgui_label_text', label, txt);
        end

        function BulletText(txt)
            call_mex('imgui_bullet_text', txt);
        end

        function SeparatorText(label)
            call_mex('imgui_separator_text', label);
        end

        % === Layout ========================================================
        function Separator()
            call_mex('imgui_separator');
        end

        function SameLine(offset, spacing)
            if nargin < 1, offset = 0; end
            if nargin < 2, spacing = -1; end
            call_mex('imgui_same_line', offset, spacing);
        end

        function NewLine()
            call_mex('imgui_new_line');
        end

        function Spacing()
            call_mex('imgui_spacing');
        end

        function Dummy(size)
            call_mex('imgui_dummy', size);
        end

        function PushItemWidth(width)
            call_mex('imgui_push_item_width', width);
        end

        function PopItemWidth()
            call_mex('imgui_pop_item_width');
        end

        function SetNextItemOpen(is_open, cond)
            if nargin < 2
                cond = int32(polyscope.ImGui.get_constant('ImGuiCond_Always'));
            end
            call_mex('imgui_set_next_item_open', is_open, cond);
        end

        function open = TreeNode(label, flags)
            if nargin < 2, flags = 0; end
            open = call_mex('imgui_tree_node', label, flags);
        end

        function TreePop()
            call_mex('imgui_tree_pop');
        end

        function open = BeginCombo(label, preview_value, flags)
            if nargin < 3, flags = 0; end
            open = call_mex('imgui_begin_combo', label, preview_value, flags);
        end

        function EndCombo()
            call_mex('imgui_end_combo');
        end

        function varargout = Selectable(label, selected, flags)
            if nargin < 3, flags = 0; end
            [varargout{1:2}] = call_mex('imgui_selectable', label, selected, flags);
        end

        % === Main widgets ==================================================
        function clicked = Button(label, size)
            if nargin < 2, size = [0, 0]; end
            clicked = call_mex('imgui_button', label, size);
        end

        function clicked = SmallButton(label)
            clicked = call_mex('imgui_small_button', label);
        end

        function varargout = Checkbox(label, v)
            [varargout{1:2}] = call_mex('imgui_checkbox', label, v);
        end

        function varargout = RadioButton(label, v, v_button)
            [varargout{1:2}] = call_mex('imgui_radio_button', label, v, v_button);
        end

        % === Sliders =======================================================
        function varargout = SliderFloat(label, v, v_min, v_max, format, flags)
            if nargin < 5, format = '%.3f'; end
            if nargin < 6, flags = 0; end
            [varargout{1:2}] = call_mex('imgui_slider_float', label, v, v_min, v_max, format, flags);
        end

        function varargout = SliderInt(label, v, v_min, v_max, format, flags)
            if nargin < 5, format = '%d'; end
            if nargin < 6, flags = 0; end
            [varargout{1:2}] = call_mex('imgui_slider_int', label, v, v_min, v_max, format, flags);
        end

        function varargout = SliderAngle(label, v_rad, v_degrees_min, v_degrees_max, format, flags)
            if nargin < 3, v_degrees_min = -360; end
            if nargin < 4, v_degrees_max = 360; end
            if nargin < 5, format = '%.0f deg'; end
            if nargin < 6, flags = 0; end
            [varargout{1:2}] = call_mex('imgui_slider_angle', label, v_rad, v_degrees_min, v_degrees_max, format, flags);
        end

        % === Input =========================================================
        function varargout = InputText(label, buf, flags, max_len)
            if nargin < 3, flags = 0; end
            if nargin < 4, max_len = 1024; end
            [varargout{1:2}] = call_mex('imgui_input_text', label, buf, flags, max_len);
        end

        function varargout = InputFloat(label, v, step, step_fast, format, flags)
            if nargin < 3, step = 0; end
            if nargin < 4, step_fast = 0; end
            if nargin < 5, format = '%.3f'; end
            if nargin < 6, flags = 0; end
            [varargout{1:2}] = call_mex('imgui_input_float', label, v, step, step_fast, format, flags);
        end

        function varargout = InputInt(label, v, step, step_fast, flags)
            if nargin < 3, step = 1; end
            if nargin < 4, step_fast = 100; end
            if nargin < 5, flags = 0; end
            [varargout{1:2}] = call_mex('imgui_input_int', label, v, step, step_fast, flags);
        end

        function varargout = InputDouble(label, v, step, step_fast, format, flags)
            if nargin < 3, step = 0; end
            if nargin < 4, step_fast = 0; end
            if nargin < 5, format = '%.6f'; end
            if nargin < 6, flags = 0; end
            [varargout{1:2}] = call_mex('imgui_input_double', label, v, step, step_fast, format, flags);
        end

        % === Color =========================================================
        function varargout = ColorEdit3(label, col, flags)
            if nargin < 3, flags = 0; end
            [varargout{1:2}] = call_mex('imgui_color_edit3', label, col, flags);
        end

        function varargout = ColorEdit4(label, col, flags)
            if nargin < 3, flags = 0; end
            [varargout{1:2}] = call_mex('imgui_color_edit4', label, col, flags);
        end

        function clicked = ColorButton(label, col, flags, size)
            if nargin < 3, flags = 0; end
            if nargin < 4, size = [0, 0]; end
            clicked = call_mex('imgui_color_button', label, col, flags, size);
        end

        % === Drag widgets ==================================================
        function varargout = DragFloat(label, v, v_speed, v_min, v_max, format, flags)
            if nargin < 3, v_speed = 1; end
            if nargin < 4, v_min = 0; end
            if nargin < 5, v_max = 0; end
            if nargin < 6, format = '%.3f'; end
            if nargin < 7, flags = 0; end
            [varargout{1:2}] = call_mex('imgui_drag_float', label, v, v_speed, v_min, v_max, format, flags);
        end

        function varargout = DragInt(label, v, v_speed, v_min, v_max, format, flags)
            if nargin < 3, v_speed = 1; end
            if nargin < 4, v_min = 0; end
            if nargin < 5, v_max = 0; end
            if nargin < 6, format = '%d'; end
            if nargin < 7, flags = 0; end
            [varargout{1:2}] = call_mex('imgui_drag_int', label, v, v_speed, v_min, v_max, format, flags);
        end

        % === Color pickers =================================================
        function varargout = ColorPicker3(label, col, flags)
            if nargin < 3, flags = 0; end
            [varargout{1:2}] = call_mex('imgui_color_picker3', label, col, flags);
        end

        function varargout = ColorPicker4(label, col, flags)
            if nargin < 3, flags = 0; end
            [varargout{1:2}] = call_mex('imgui_color_picker4', label, col, flags);
        end

        % === Combo / List boxes ============================================
        function varargout = Combo(label, current_item, items)
            [varargout{1:2}] = call_mex('imgui_combo', label, current_item, items);
        end

        function open = BeginListBox(label, size)
            if nargin < 2, size = [0, 0]; end
            open = call_mex('imgui_begin_list_box', label, size);
        end

        function EndListBox()
            call_mex('imgui_end_list_box');
        end

        function varargout = ListBox(label, current_item, items, height_in_items)
            if nargin < 4, height_in_items = -1; end
            [varargout{1:2}] = call_mex('imgui_list_box', label, current_item, items, height_in_items);
        end

        % === Headers / Buttons =============================================
        function open = CollapsingHeader(label, flags)
            if nargin < 2, flags = 0; end
            open = call_mex('imgui_collapsing_header', label, flags);
        end

        function clicked = InvisibleButton(str_id, size, flags)
            if nargin < 3, flags = 0; end
            clicked = call_mex('imgui_invisible_button', str_id, size, flags);
        end

        function clicked = ArrowButton(str_id, dir)
            clicked = call_mex('imgui_arrow_button', str_id, dir);
        end

        % === Menus =========================================================
        function open = BeginMenuBar()
            open = call_mex('imgui_begin_menu_bar');
        end

        function EndMenuBar()
            call_mex('imgui_end_menu_bar');
        end

        function open = BeginMainMenuBar()
            open = call_mex('imgui_begin_main_menu_bar');
        end

        function EndMainMenuBar()
            call_mex('imgui_end_main_menu_bar');
        end

        function open = BeginMenu(label, enabled)
            if nargin < 2, enabled = true; end
            open = call_mex('imgui_begin_menu', label, enabled);
        end

        function EndMenu()
            call_mex('imgui_end_menu');
        end

        function varargout = MenuItem(label, shortcut, selected, enabled)
            if nargin < 2, shortcut = ''; end
            if nargin < 4, enabled = true; end
            if nargin < 3
                varargout{1} = call_mex('imgui_menu_item', label, shortcut);
            else
                [varargout{1:2}] = call_mex('imgui_menu_item', label, shortcut, selected, enabled);
            end
        end

        % === Popups ========================================================
        function open = BeginPopup(str_id, flags)
            if nargin < 2, flags = 0; end
            open = call_mex('imgui_begin_popup', str_id, flags);
        end

        function EndPopup()
            call_mex('imgui_end_popup');
        end

        function OpenPopup(str_id, popup_flags)
            if nargin < 2, popup_flags = 0; end
            call_mex('imgui_open_popup', str_id, popup_flags);
        end

        function CloseCurrentPopup()
            call_mex('imgui_close_current_popup');
        end

        function open = IsPopupOpen(str_id, flags)
            if nargin < 2, flags = 0; end
            open = call_mex('imgui_is_popup_open', str_id, flags);
        end

        % === Item / window queries =========================================
        function v = IsItemHovered(flags)
            if nargin < 1, flags = 0; end
            v = call_mex('imgui_is_item_hovered', flags);
        end

        function v = IsItemActive()
            v = call_mex('imgui_is_item_active');
        end

        function v = IsItemClicked(mouse_button)
            if nargin < 1, mouse_button = 0; end
            v = call_mex('imgui_is_item_clicked', mouse_button);
        end

        function v = IsWindowHovered(flags)
            if nargin < 1, flags = 0; end
            v = call_mex('imgui_is_window_hovered', flags);
        end

        function v = GetWindowPos()
            v = call_mex('imgui_get_window_pos');
        end

        function v = GetWindowSize()
            v = call_mex('imgui_get_window_size');
        end

        function v = GetMousePos()
            v = call_mex('imgui_get_mouse_pos');
        end

        function v = GetContentRegionAvail()
            v = call_mex('imgui_get_content_region_avail');
        end

        function v = GetCursorPos()
            v = call_mex('imgui_get_cursor_pos');
        end

        % === Style / layout ================================================
        function PushStyleColor(idx, col)
            call_mex('imgui_push_style_color', idx, col);
        end

        function PopStyleColor(count)
            if nargin < 1, count = 1; end
            call_mex('imgui_pop_style_color', count);
        end

        function PushStyleVar(idx, val)
            call_mex('imgui_push_style_var', idx, val);
        end

        function PopStyleVar(count)
            if nargin < 1, count = 1; end
            call_mex('imgui_pop_style_var', count);
        end

        function Indent(indent_w)
            if nargin < 1, indent_w = 0; end
            call_mex('imgui_indent', indent_w);
        end

        function Unindent(indent_w)
            if nargin < 1, indent_w = 0; end
            call_mex('imgui_unindent', indent_w);
        end

        function BeginGroup()
            call_mex('imgui_begin_group');
        end

        function EndGroup()
            call_mex('imgui_end_group');
        end

        % === Demo / debug ==================================================
        function open = ShowDemoWindow(open)
            if nargin < 1, open = true; end
            open = call_mex('imgui_show_demo_window', open);
        end

        function open = ShowMetricsWindow(open)
            if nargin < 1, open = true; end
            open = call_mex('imgui_show_metrics_window', open);
        end
        % === Multi-component / advanced widgets ============================
        function varargout = DragFloat2(label, v, v_speed, v_min, v_max, format, flags)
            if nargin < 3, v_speed = 1; end
            if nargin < 4, v_min = 0; end
            if nargin < 5, v_max = 0; end
            if nargin < 6, format = '%.3f'; end
            if nargin < 7, flags = 0; end
            [varargout{1:2}] = call_mex('imgui_drag_float2', label, v, v_speed, v_min, v_max, format, flags);
        end

        function varargout = DragFloat3(label, v, v_speed, v_min, v_max, format, flags)
            if nargin < 3, v_speed = 1; end
            if nargin < 4, v_min = 0; end
            if nargin < 5, v_max = 0; end
            if nargin < 6, format = '%.3f'; end
            if nargin < 7, flags = 0; end
            [varargout{1:2}] = call_mex('imgui_drag_float3', label, v, v_speed, v_min, v_max, format, flags);
        end

        function varargout = DragFloat4(label, v, v_speed, v_min, v_max, format, flags)
            if nargin < 3, v_speed = 1; end
            if nargin < 4, v_min = 0; end
            if nargin < 5, v_max = 0; end
            if nargin < 6, format = '%.3f'; end
            if nargin < 7, flags = 0; end
            [varargout{1:2}] = call_mex('imgui_drag_float4', label, v, v_speed, v_min, v_max, format, flags);
        end

        function varargout = DragInt2(label, v, v_speed, v_min, v_max, format, flags)
            if nargin < 3, v_speed = 1; end
            if nargin < 4, v_min = 0; end
            if nargin < 5, v_max = 0; end
            if nargin < 6, format = '%d'; end
            if nargin < 7, flags = 0; end
            [varargout{1:2}] = call_mex('imgui_drag_int2', label, v, v_speed, v_min, v_max, format, flags);
        end

        function varargout = DragInt3(label, v, v_speed, v_min, v_max, format, flags)
            if nargin < 3, v_speed = 1; end
            if nargin < 4, v_min = 0; end
            if nargin < 5, v_max = 0; end
            if nargin < 6, format = '%d'; end
            if nargin < 7, flags = 0; end
            [varargout{1:2}] = call_mex('imgui_drag_int3', label, v, v_speed, v_min, v_max, format, flags);
        end

        function varargout = DragInt4(label, v, v_speed, v_min, v_max, format, flags)
            if nargin < 3, v_speed = 1; end
            if nargin < 4, v_min = 0; end
            if nargin < 5, v_max = 0; end
            if nargin < 6, format = '%d'; end
            if nargin < 7, flags = 0; end
            [varargout{1:2}] = call_mex('imgui_drag_int4', label, v, v_speed, v_min, v_max, format, flags);
        end

        function varargout = DragFloatRange2(label, v_current_min, v_current_max, v_speed, v_min, v_max, format, flags)
            if nargin < 4, v_speed = 1; end
            if nargin < 5, v_min = 0; end
            if nargin < 6, v_max = 0; end
            if nargin < 7, format = '%.3f'; end
            if nargin < 8, flags = 0; end
            [varargout{1:3}] = call_mex('imgui_drag_float_range2', label, v_current_min, v_current_max, v_speed, v_min, v_max, format, flags);
        end

        function varargout = DragIntRange2(label, v_current_min, v_current_max, v_speed, v_min, v_max, format, flags)
            if nargin < 4, v_speed = 1; end
            if nargin < 5, v_min = 0; end
            if nargin < 6, v_max = 0; end
            if nargin < 7, format = '%d'; end
            if nargin < 8, flags = 0; end
            [varargout{1:3}] = call_mex('imgui_drag_int_range2', label, v_current_min, v_current_max, v_speed, v_min, v_max, format, flags);
        end

        function varargout = SliderFloat2(label, v, v_min, v_max, format, flags)
            if nargin < 5, format = '%.3f'; end
            if nargin < 6, flags = 0; end
            [varargout{1:2}] = call_mex('imgui_slider_float2', label, v, v_min, v_max, format, flags);
        end

        function varargout = SliderFloat3(label, v, v_min, v_max, format, flags)
            if nargin < 5, format = '%.3f'; end
            if nargin < 6, flags = 0; end
            [varargout{1:2}] = call_mex('imgui_slider_float3', label, v, v_min, v_max, format, flags);
        end

        function varargout = SliderFloat4(label, v, v_min, v_max, format, flags)
            if nargin < 5, format = '%.3f'; end
            if nargin < 6, flags = 0; end
            [varargout{1:2}] = call_mex('imgui_slider_float4', label, v, v_min, v_max, format, flags);
        end

        function varargout = SliderInt2(label, v, v_min, v_max, format, flags)
            if nargin < 5, format = '%d'; end
            if nargin < 6, flags = 0; end
            [varargout{1:2}] = call_mex('imgui_slider_int2', label, v, v_min, v_max, format, flags);
        end

        function varargout = SliderInt3(label, v, v_min, v_max, format, flags)
            if nargin < 5, format = '%d'; end
            if nargin < 6, flags = 0; end
            [varargout{1:2}] = call_mex('imgui_slider_int3', label, v, v_min, v_max, format, flags);
        end

        function varargout = SliderInt4(label, v, v_min, v_max, format, flags)
            if nargin < 5, format = '%d'; end
            if nargin < 6, flags = 0; end
            [varargout{1:2}] = call_mex('imgui_slider_int4', label, v, v_min, v_max, format, flags);
        end

        function varargout = InputFloat2(label, v, format, flags)
            if nargin < 3, format = '%.3f'; end
            if nargin < 4, flags = 0; end
            [varargout{1:2}] = call_mex('imgui_input_float2', label, v, format, flags);
        end

        function varargout = InputFloat3(label, v, format, flags)
            if nargin < 3, format = '%.3f'; end
            if nargin < 4, flags = 0; end
            [varargout{1:2}] = call_mex('imgui_input_float3', label, v, format, flags);
        end

        function varargout = InputFloat4(label, v, format, flags)
            if nargin < 3, format = '%.3f'; end
            if nargin < 4, flags = 0; end
            [varargout{1:2}] = call_mex('imgui_input_float4', label, v, format, flags);
        end

        function varargout = InputInt2(label, v, flags)
            if nargin < 3, flags = 0; end
            [varargout{1:2}] = call_mex('imgui_input_int2', label, v, flags);
        end

        function varargout = InputInt3(label, v, flags)
            if nargin < 3, flags = 0; end
            [varargout{1:2}] = call_mex('imgui_input_int3', label, v, flags);
        end

        function varargout = InputInt4(label, v, flags)
            if nargin < 3, flags = 0; end
            [varargout{1:2}] = call_mex('imgui_input_int4', label, v, flags);
        end

        function varargout = VSliderFloat(label, size, v, v_min, v_max, format, flags)
            if nargin < 6, format = '%.3f'; end
            if nargin < 7, flags = 0; end
            [varargout{1:2}] = call_mex('imgui_v_slider_float', label, size, v, v_min, v_max, format, flags);
        end

        function varargout = VSliderInt(label, size, v, v_min, v_max, format, flags)
            if nargin < 6, format = '%d'; end
            if nargin < 7, flags = 0; end
            [varargout{1:2}] = call_mex('imgui_v_slider_int', label, size, v, v_min, v_max, format, flags);
        end

        function varargout = InputTextMultiline(label, buf, size, flags, max_len)
            if nargin < 3, size = [0, 0]; end
            if nargin < 4, flags = 0; end
            if nargin < 5, max_len = 1024; end
            [varargout{1:2}] = call_mex('imgui_input_text_multiline', label, buf, size, flags, max_len);
        end

        function varargout = InputTextWithHint(label, hint, buf, flags, max_len)
            if nargin < 4, flags = 0; end
            if nargin < 5, max_len = 1024; end
            [varargout{1:2}] = call_mex('imgui_input_text_with_hint', label, hint, buf, flags, max_len);
        end

        function clicked = RadioButtonActive(label, active)
            clicked = call_mex('imgui_radio_button_active', label, active);
        end

        function varargout = CheckboxFlags(label, flags, flags_value)
            [varargout{1:2}] = call_mex('imgui_checkbox_flags', label, flags, flags_value);
        end

        function ProgressBar(fraction, size, overlay)
            if nargin < 2, size = [-eps, 0]; end
            if nargin < 3, overlay = ''; end
            call_mex('imgui_progress_bar', fraction, size, overlay);
        end

        function Bullet()
            call_mex('imgui_bullet');
        end

        function clicked = TextLink(label)
            clicked = call_mex('imgui_text_link', label);
        end

        function clicked = TextLinkOpenURL(label, url)
            if nargin < 2, url = ''; end
            clicked = call_mex('imgui_text_link_open_url', label, url);
        end

        function Image(tex_id, size, uv0, uv1)
            if nargin < 3, uv0 = [0, 0]; end
            if nargin < 4, uv1 = [1, 1]; end
            call_mex('imgui_image', tex_id, size, uv0, uv1);
        end

        function clicked = ImageButton(str_id, tex_id, size, uv0, uv1, bg_col, tint_col)
            if nargin < 4, uv0 = [0, 0]; end
            if nargin < 5, uv1 = [1, 1]; end
            if nargin < 6, bg_col = [0, 0, 0, 0]; end
            if nargin < 7, tint_col = [1, 1, 1, 1]; end
            clicked = call_mex('imgui_image_button', str_id, tex_id, size, uv0, uv1, bg_col, tint_col);
        end

        function ImageWithBg(tex_id, size, uv0, uv1, bg_col, tint_col)
            if nargin < 3, uv0 = [0, 0]; end
            if nargin < 4, uv1 = [1, 1]; end
            if nargin < 5, bg_col = [0, 0, 0, 0]; end
            if nargin < 6, tint_col = [1, 1, 1, 1]; end
            call_mex('imgui_image_with_bg', tex_id, size, uv0, uv1, bg_col, tint_col);
        end

        % === Tree / ID / value =============================================
        function open = TreeNodeEx(label, flags)
            if nargin < 2, flags = 0; end
            open = call_mex('imgui_tree_node_ex', label, flags);
        end

        function TreePush(str_id)
            call_mex('imgui_tree_push', str_id);
        end

        function v = GetTreeNodeToLabelSpacing()
            v = call_mex('imgui_get_tree_node_to_label_spacing');
        end

        function SetNextItemStorageID(storage_id)
            call_mex('imgui_set_next_item_storage_id', storage_id);
        end

        function PushIdStr(str_id)
            call_mex('imgui_push_id_str', str_id);
        end

        function PushIdInt(int_id)
            call_mex('imgui_push_id_int', int_id);
        end

        function PopId(count)
            if nargin < 1, count = 1; end
            call_mex('imgui_pop_id', count);
        end

        function id = GetIdStr(str_id)
            id = call_mex('imgui_get_id_str', str_id);
        end

        function id = GetIdInt(int_id)
            id = call_mex('imgui_get_id_int', int_id);
        end

        function ValueBool(prefix, b)
            call_mex('imgui_value_bool', prefix, b);
        end

        function ValueInt(prefix, v)
            call_mex('imgui_value_int', prefix, v);
        end

        function ValueFloat(prefix, v, format)
            if nargin < 3, format = ''; end
            call_mex('imgui_value_float', prefix, v, format);
        end

        function PlotLines(label, values, offset, overlay, scale_min, scale_max, size)
            if nargin < 3, offset = 0; end
            if nargin < 4, overlay = ''; end
            if nargin < 5, scale_min = inf; end
            if nargin < 6, scale_max = inf; end
            if nargin < 7, size = [0, 0]; end
            call_mex('imgui_plot_lines', label, values, offset, overlay, scale_min, scale_max, size);
        end

        function PlotHistogram(label, values, offset, overlay, scale_min, scale_max, size)
            if nargin < 3, offset = 0; end
            if nargin < 4, overlay = ''; end
            if nargin < 5, scale_min = inf; end
            if nargin < 6, scale_max = inf; end
            if nargin < 7, size = [0, 0]; end
            call_mex('imgui_plot_histogram', label, values, offset, overlay, scale_min, scale_max, size);
        end

        % === Item / window / mouse / keyboard queries =======================
        function v = IsItemFocused()
            v = call_mex('imgui_is_item_focused');
        end

        function v = IsItemVisible()
            v = call_mex('imgui_is_item_visible');
        end

        function v = IsItemEdited()
            v = call_mex('imgui_is_item_edited');
        end

        function v = IsItemActivated()
            v = call_mex('imgui_is_item_activated');
        end

        function v = IsItemDeactivated()
            v = call_mex('imgui_is_item_deactivated');
        end

        function v = IsItemDeactivatedAfterEdit()
            v = call_mex('imgui_is_item_deactivated_after_edit');
        end

        function v = IsItemToggledOpen()
            v = call_mex('imgui_is_item_toggled_open');
        end

        function v = IsAnyItemHovered()
            v = call_mex('imgui_is_any_item_hovered');
        end

        function v = IsAnyItemActive()
            v = call_mex('imgui_is_any_item_active');
        end

        function v = IsAnyItemFocused()
            v = call_mex('imgui_is_any_item_focused');
        end

        function id = GetItemID()
            id = call_mex('imgui_get_item_id');
        end

        function v = GetItemRectMin()
            v = call_mex('imgui_get_item_rect_min');
        end

        function v = GetItemRectMax()
            v = call_mex('imgui_get_item_rect_max');
        end

        function v = GetItemRectSize()
            v = call_mex('imgui_get_item_rect_size');
        end

        function v = IsWindowAppearing()
            v = call_mex('imgui_is_window_appearing');
        end

        function v = IsWindowCollapsed()
            v = call_mex('imgui_is_window_collapsed');
        end

        function v = IsWindowFocused(flags)
            if nargin < 1, flags = 0; end
            v = call_mex('imgui_is_window_focused', flags);
        end

        function dl = GetWindowDrawList()
            h = call_mex('imgui_get_window_draw_list');
            dl = polyscope.ImDrawList(h);
        end

        function v = GetWindowWidth()
            v = call_mex('imgui_get_window_width');
        end

        function v = GetWindowHeight()
            v = call_mex('imgui_get_window_height');
        end

        function v = GetScrollX()
            v = call_mex('imgui_get_scroll_x');
        end

        function v = GetScrollY()
            v = call_mex('imgui_get_scroll_y');
        end

        function SetScrollX(x)
            call_mex('imgui_set_scroll_x', x);
        end

        function SetScrollY(y)
            call_mex('imgui_set_scroll_y', y);
        end

        function v = GetScrollMaxX()
            v = call_mex('imgui_get_scroll_max_x');
        end

        function v = GetScrollMaxY()
            v = call_mex('imgui_get_scroll_max_y');
        end

        function SetScrollHereX(center_x_ratio)
            if nargin < 1, center_x_ratio = 0.5; end
            call_mex('imgui_set_scroll_here_x', center_x_ratio);
        end

        function SetScrollHereY(center_y_ratio)
            if nargin < 1, center_y_ratio = 0.5; end
            call_mex('imgui_set_scroll_here_y', center_y_ratio);
        end

        function SetScrollFromPosX(local_x, center_x_ratio)
            if nargin < 2, center_x_ratio = 0.5; end
            call_mex('imgui_set_scroll_from_pos_x', local_x, center_x_ratio);
        end

        function SetScrollFromPosY(local_y, center_y_ratio)
            if nargin < 2, center_y_ratio = 0.5; end
            call_mex('imgui_set_scroll_from_pos_y', local_y, center_y_ratio);
        end

        function v = GetMousePosOnOpeningCurrentPopup()
            v = call_mex('imgui_get_mouse_pos_on_opening_current_popup');
        end

        function v = IsMouseHoveringRect(r_min, r_max, clip)
            if nargin < 3, clip = true; end
            v = call_mex('imgui_is_mouse_hovering_rect', r_min, r_max, clip);
        end

        function v = IsMousePosValid(pos)
            if nargin < 1
                v = call_mex('imgui_is_mouse_pos_valid');
            else
                v = call_mex('imgui_is_mouse_pos_valid', pos);
            end
        end

        function v = IsAnyMouseDown()
            v = call_mex('imgui_is_any_mouse_down');
        end

        function c = GetMouseClickedCount(button)
            c = call_mex('imgui_get_mouse_clicked_count', button);
        end

        function v = IsMouseDragging(button, lock_threshold)
            if nargin < 2, lock_threshold = -1; end
            v = call_mex('imgui_is_mouse_dragging', button, lock_threshold);
        end

        function v = GetMouseDragDelta(button, lock_threshold)
            if nargin < 1, button = 0; end
            if nargin < 2, lock_threshold = -1; end
            v = call_mex('imgui_get_mouse_drag_delta', button, lock_threshold);
        end

        function ResetMouseDragDelta(button)
            if nargin < 1, button = 0; end
            call_mex('imgui_reset_mouse_drag_delta', button);
        end

        function c = GetMouseCursor()
            c = call_mex('imgui_get_mouse_cursor');
        end

        function SetMouseCursor(cursor_type)
            call_mex('imgui_set_mouse_cursor', cursor_type);
        end

        function v = IsKeyDown(key)
            v = call_mex('imgui_is_key_down', key);
        end

        function v = IsKeyPressed(key, repeat)
            if nargin < 2, repeat = true; end
            v = call_mex('imgui_is_key_pressed', key, repeat);
        end

        function v = IsKeyReleased(key)
            v = call_mex('imgui_is_key_released', key);
        end

        function v = IsKeyChordPressed(key_chord)
            v = call_mex('imgui_is_key_chord_pressed', key_chord);
        end

        function c = GetKeyPressedAmount(key, repeat_delay, rate)
            c = call_mex('imgui_get_key_pressed_amount', key, repeat_delay, rate);
        end

        function name = GetKeyName(key)
            name = call_mex('imgui_get_key_name', key);
        end

        function SetNextFrameWantCaptureKeyboard(want)
            call_mex('imgui_set_next_frame_want_capture_keyboard', want);
        end

        function SetNextFrameWantCaptureMouse(want)
            call_mex('imgui_set_next_frame_want_capture_mouse', want);
        end

        % === Layout / style / utility =======================================
        function SetNextItemWidth(width)
            call_mex('imgui_set_next_item_width', width);
        end

        function v = CalcItemWidth()
            v = call_mex('imgui_calc_item_width');
        end

        function PushTextWrapPos(wrap_pos_x)
            if nargin < 1, wrap_pos_x = 0; end
            call_mex('imgui_push_text_wrap_pos', wrap_pos_x);
        end

        function PopTextWrapPos()
            call_mex('imgui_pop_text_wrap_pos');
        end

        function v = GetFontSize()
            v = call_mex('imgui_get_font_size');
        end

        function v = GetFontTexUvWhitePixel()
            v = call_mex('imgui_get_font_tex_uv_white_pixel');
        end

        function c = GetColorU32Idx(idx, alpha_mul)
            if nargin < 2, alpha_mul = 1; end
            c = call_mex('imgui_get_color_u32_idx', idx, alpha_mul);
        end

        function c = GetColorU32Vec4(col)
            c = call_mex('imgui_get_color_u32_vec4', col);
        end

        function c = GetColorU32U32(col, alpha_mul)
            if nargin < 2, alpha_mul = 1; end
            c = call_mex('imgui_get_color_u32_u32', col, alpha_mul);
        end

        function v = GetStyleColorVec4(idx)
            v = call_mex('imgui_get_style_color_vec4', idx);
        end

        function v = GetCursorScreenPos()
            v = call_mex('imgui_get_cursor_screen_pos');
        end

        function SetCursorScreenPos(pos)
            call_mex('imgui_set_cursor_screen_pos', pos);
        end

        function v = GetCursorPosX()
            v = call_mex('imgui_get_cursor_pos_x');
        end

        function v = GetCursorPosY()
            v = call_mex('imgui_get_cursor_pos_y');
        end

        function SetCursorPos(pos)
            call_mex('imgui_set_cursor_pos', pos);
        end

        function SetCursorPosX(x)
            call_mex('imgui_set_cursor_pos_x', x);
        end

        function SetCursorPosY(y)
            call_mex('imgui_set_cursor_pos_y', y);
        end

        function v = GetCursorStartPos()
            v = call_mex('imgui_get_cursor_start_pos');
        end

        function v = GetTextLineHeight()
            v = call_mex('imgui_get_text_line_height');
        end

        function v = GetTextLineHeightWithSpacing()
            v = call_mex('imgui_get_text_line_height_with_spacing');
        end

        function v = GetFrameHeight()
            v = call_mex('imgui_get_frame_height');
        end

        function v = GetFrameHeightWithSpacing()
            v = call_mex('imgui_get_frame_height_with_spacing');
        end

        function AlignTextToFramePadding()
            call_mex('imgui_align_text_to_frame_padding');
        end

        function v = GetTime()
            v = call_mex('imgui_get_time');
        end

        function v = GetFrameCount()
            v = call_mex('imgui_get_frame_count');
        end

        function name = GetStyleColorName(idx)
            name = call_mex('imgui_get_style_color_name', idx);
        end

        function v = CalcTextSize(text, hide_after_double_hash, wrap_width)
            if nargin < 2, hide_after_double_hash = false; end
            if nargin < 3, wrap_width = -1; end
            v = call_mex('imgui_calc_text_size', text, hide_after_double_hash, wrap_width);
        end

        function v = ColorConvertU32ToFloat4(in_val)
            v = call_mex('imgui_color_convert_u32_to_float4', in_val);
        end

        function c = ColorConvertFloat4ToU32(col)
            c = call_mex('imgui_color_convert_float4_to_u32', col);
        end

        function v = ColorConvertRgbToHsv(r, g, b)
            v = call_mex('imgui_color_convert_rgb_to_hsv', r, g, b);
        end

        function v = ColorConvertHsvToRgb(h, s, v)
            v = call_mex('imgui_color_convert_hsv_to_rgb', h, s, v);
        end

        function text = GetClipboardText()
            text = call_mex('imgui_get_clipboard_text');
        end

        function SetClipboardText(text)
            call_mex('imgui_set_clipboard_text', text);
        end

        function LoadIniSettingsFromDisk(filename)
            call_mex('imgui_load_ini_settings_from_disk', filename);
        end

        function LoadIniSettingsFromMemory(data)
            call_mex('imgui_load_ini_settings_from_memory', data);
        end

        function SaveIniSettingsToDisk(filename)
            call_mex('imgui_save_ini_settings_to_disk', filename);
        end

        function data = SaveIniSettingsToMemory()
            data = call_mex('imgui_save_ini_settings_to_memory');
        end

        function PushItemFlag(option, enabled)
            call_mex('imgui_push_item_flag', option, enabled);
        end

        function PopItemFlag(count)
            if nargin < 1, count = 1; end
            call_mex('imgui_pop_item_flag', count);
        end

        % === Window manipulation ============================================
        function SetNextWindowSizeConstraints(size_min, size_max)
            call_mex('imgui_set_next_window_size_constraints', size_min, size_max);
        end

        function SetNextWindowContentSize(size)
            call_mex('imgui_set_next_window_content_size', size);
        end

        function SetNextWindowCollapsed(collapsed, cond)
            if nargin < 2
                cond = int32(polyscope.ImGui.get_constant('ImGuiCond_Always'));
            end
            call_mex('imgui_set_next_window_collapsed', collapsed, cond);
        end

        function SetNextWindowFocus()
            call_mex('imgui_set_next_window_focus');
        end

        function SetNextWindowScroll(scroll)
            call_mex('imgui_set_next_window_scroll', scroll);
        end

        function SetNextWindowBgAlpha(alpha)
            call_mex('imgui_set_next_window_bg_alpha', alpha);
        end

        function SetWindowPos(pos, cond)
            if nargin < 2
                cond = int32(polyscope.ImGui.get_constant('ImGuiCond_Always'));
            end
            call_mex('imgui_set_window_pos', pos, cond);
        end

        function SetWindowPosNamed(name, pos, cond)
            if nargin < 3
                cond = int32(polyscope.ImGui.get_constant('ImGuiCond_Always'));
            end
            call_mex('imgui_set_window_pos_named', name, pos, cond);
        end

        function SetWindowSize(size, cond)
            if nargin < 2
                cond = int32(polyscope.ImGui.get_constant('ImGuiCond_Always'));
            end
            call_mex('imgui_set_window_size', size, cond);
        end

        function SetWindowSizeNamed(name, size, cond)
            if nargin < 3
                cond = int32(polyscope.ImGui.get_constant('ImGuiCond_Always'));
            end
            call_mex('imgui_set_window_size_named', name, size, cond);
        end

        function SetWindowCollapsed(collapsed, cond)
            if nargin < 2
                cond = int32(polyscope.ImGui.get_constant('ImGuiCond_Always'));
            end
            call_mex('imgui_set_window_collapsed', collapsed, cond);
        end

        function SetWindowCollapsedNamed(name, collapsed, cond)
            if nargin < 3
                cond = int32(polyscope.ImGui.get_constant('ImGuiCond_Always'));
            end
            call_mex('imgui_set_window_collapsed_named', name, collapsed, cond);
        end

        function SetWindowFocus()
            call_mex('imgui_set_window_focus');
        end

        function SetWindowFocusNamed(name)
            call_mex('imgui_set_window_focus_named', name);
        end

        % === Tab bar ========================================================
        function open = BeginTabBar(str_id, flags)
            if nargin < 2, flags = 0; end
            open = call_mex('imgui_begin_tab_bar', str_id, flags);
        end

        function EndTabBar()
            call_mex('imgui_end_tab_bar');
        end

        function varargout = BeginTabItem(label, p_open, flags)
            if nargin < 3, flags = 0; end
            if nargin < 2
                varargout{1} = call_mex('imgui_begin_tab_item', label, flags);
            else
                [varargout{1:2}] = call_mex('imgui_begin_tab_item', label, p_open, flags);
            end
        end

        function EndTabItem()
            call_mex('imgui_end_tab_item');
        end

        function clicked = TabItemButton(label, flags)
            if nargin < 2, flags = 0; end
            clicked = call_mex('imgui_tab_item_button', label, flags);
        end

        function SetTabItemClosed(tab_or_docked_window_label)
            call_mex('imgui_set_tab_item_closed', tab_or_docked_window_label);
        end

        % === Table ==========================================================
        function open = BeginTable(str_id, columns, flags, outer_size, inner_width)
            if nargin < 3, flags = 0; end
            if nargin < 4, outer_size = [0, 0]; end
            if nargin < 5, inner_width = 0; end
            open = call_mex('imgui_begin_table', str_id, columns, flags, outer_size, inner_width);
        end

        function EndTable()
            call_mex('imgui_end_table');
        end

        function TableNextRow(row_flags, min_row_height)
            if nargin < 1, row_flags = 0; end
            if nargin < 2, min_row_height = 0; end
            call_mex('imgui_table_next_row', row_flags, min_row_height);
        end

        function visible = TableNextColumn()
            visible = call_mex('imgui_table_next_column');
        end

        function visible = TableSetColumnIndex(column_n)
            visible = call_mex('imgui_table_set_column_index', column_n);
        end

        function TableSetupColumn(label, flags, init_width_or_weight, user_id)
            if nargin < 2, flags = 0; end
            if nargin < 3, init_width_or_weight = 0; end
            if nargin < 4, user_id = 0; end
            call_mex('imgui_table_setup_column', label, flags, init_width_or_weight, user_id);
        end

        function TableSetupScrollFreeze(cols, rows)
            call_mex('imgui_table_setup_scroll_freeze', cols, rows);
        end

        function TableHeader(label)
            call_mex('imgui_table_header', label);
        end

        function TableHeadersRow()
            call_mex('imgui_table_headers_row');
        end

        function TableAngledHeadersRow()
            call_mex('imgui_table_angled_headers_row');
        end

        function c = TableGetColumnCount()
            c = call_mex('imgui_table_get_column_count');
        end

        function c = TableGetColumnIndex()
            c = call_mex('imgui_table_get_column_index');
        end

        function r = TableGetRowIndex()
            r = call_mex('imgui_table_get_row_index');
        end

        function name = TableGetColumnName(column_n)
            if nargin < 1, column_n = -1; end
            name = call_mex('imgui_table_get_column_name', column_n);
        end

        function f = TableGetColumnFlags(column_n)
            if nargin < 1, column_n = -1; end
            f = call_mex('imgui_table_get_column_flags', column_n);
        end

        function TableSetColumnEnabled(column_n, v)
            call_mex('imgui_table_set_column_enabled', column_n, v);
        end

        function c = TableGetHoveredColumn()
            c = call_mex('imgui_table_get_hovered_column');
        end

        function TableSetBgColor(target, color, column_n)
            if nargin < 3, column_n = -1; end
            call_mex('imgui_table_set_bg_color', target, color, column_n);
        end

        % === Legacy columns =================================================
        function Columns(count, id, borders)
            if nargin < 1, count = 1; end
            if nargin < 2, id = ''; end
            if nargin < 3, borders = true; end
            call_mex('imgui_columns', count, id, borders);
        end

        function NextColumn()
            call_mex('imgui_next_column');
        end

        function c = GetColumnIndex()
            c = call_mex('imgui_get_column_index');
        end

        function w = GetColumnWidth(column_index)
            if nargin < 1, column_index = -1; end
            w = call_mex('imgui_get_column_width', column_index);
        end

        function SetColumnWidth(column_index, width)
            call_mex('imgui_set_column_width', column_index, width);
        end

        function o = GetColumnOffset(column_index)
            if nargin < 1, column_index = -1; end
            o = call_mex('imgui_get_column_offset', column_index);
        end

        function SetColumnOffset(column_index, offset_x)
            call_mex('imgui_set_column_offset', column_index, offset_x);
        end

        function c = GetColumnsCount()
            c = call_mex('imgui_get_columns_count');
        end

        % === Viewport / draw lists ==========================================
        function h = GetMainViewport()
            h = call_mex('imgui_get_main_viewport');
        end

        function io = GetIO()
            h = call_mex('imgui_get_io');
            io = polyscope.ImGuiIO(h);
        end

        function s = GetStyle()
            h = call_mex('imgui_get_style');
            s = polyscope.ImGuiStyle(h);
        end

        function dl = GetBackgroundDrawList()
            h = call_mex('imgui_get_background_draw_list');
            dl = polyscope.ImDrawList(h);
        end

        function dl = GetForegroundDrawList()
            h = call_mex('imgui_get_foreground_draw_list');
            dl = polyscope.ImDrawList(h);
        end

        function v = IsRectVisible(size)
            v = call_mex('imgui_is_rect_visible', size);
        end

        function v = IsRectVisibleRect(rect_min, rect_max)
            v = call_mex('imgui_is_rect_visible_rect', rect_min, rect_max);
        end
    end
end
