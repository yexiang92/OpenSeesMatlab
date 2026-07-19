classdef ImPlot < handle
    %IMPLOT MATLAB wrapper for ImPlot functions exposed by Polyscope.
    %   Mirrors polyscope.implot from the Python bindings.

    methods (Static)
        % === Constants =====================================================
        function v = get_constant(name)
            v = call_mex('implot_get_constant', name);
        end

        % === Begin / end plot ==============================================
        function ok = BeginPlot(title_id, size, flags)
            if nargin < 2, size = [-1, 0]; end
            if nargin < 3, flags = 0; end
            ok = call_mex('implot_begin_plot', title_id, size, flags);
        end

        function EndPlot()
            call_mex('implot_end_plot');
        end

        % === Setup =========================================================
        function SetupAxes(x_label, y_label, x_flags, y_flags)
            if nargin < 3, x_flags = 0; end
            if nargin < 4, y_flags = 0; end
            call_mex('implot_setup_axes', x_label, y_label, x_flags, y_flags);
        end

        function SetupAxesLimits(x_min, x_max, y_min, y_max, cond)
            if nargin < 5, cond = int32(polyscope.ImPlot.get_constant('ImPlotCond_Once')); end
            call_mex('implot_setup_axes_limits', x_min, x_max, y_min, y_max, cond);
        end

        function SetupAxis(axis, label, flags)
            if nargin < 3, flags = 0; end
            call_mex('implot_setup_axis', axis, label, flags);
        end

        function SetupAxisLimits(axis, vmin, vmax, cond)
            if nargin < 4, cond = int32(polyscope.ImPlot.get_constant('ImPlotCond_Once')); end
            call_mex('implot_setup_axis_limits', axis, vmin, vmax, cond);
        end

        % === Plot items ====================================================
        function PlotLine(label_id, values, xscale, xstart, flags)
            if nargin < 3, xscale = 1; end
            if nargin < 4, xstart = 0; end
            if nargin < 5, flags = 0; end
            call_mex('implot_plot_line', label_id, values, xscale, xstart, flags);
        end

        function PlotLineXY(label_id, xs, ys, flags)
            if nargin < 4, flags = 0; end
            call_mex('implot_plot_line_xy', label_id, xs, ys, flags);
        end

        function PlotScatter(label_id, values, xscale, xstart, flags)
            if nargin < 3, xscale = 1; end
            if nargin < 4, xstart = 0; end
            if nargin < 5, flags = 0; end
            call_mex('implot_plot_scatter', label_id, values, xscale, xstart, flags);
        end

        function PlotInfLines(label_id, values, flags)
            if nargin < 3, flags = 0; end
            call_mex('implot_plot_inf_lines', label_id, values, flags);
        end

        function PlotScatterXY(label_id, xs, ys, flags)
            if nargin < 4, flags = 0; end
            call_mex('implot_plot_scatter_xy', label_id, xs, ys, flags);
        end

        function PlotBars(label_id, values, bar_size, shift, flags)
            if nargin < 3, bar_size = 0.67; end
            if nargin < 4, shift = 0; end
            if nargin < 5, flags = 0; end
            call_mex('implot_plot_bars', label_id, values, bar_size, shift, flags);
        end

        function PlotBarsXY(label_id, xs, ys, bar_size, flags)
            if nargin < 5, flags = 0; end
            call_mex('implot_plot_bars_xy', label_id, xs, ys, bar_size, flags);
        end

        function PlotHeatmap(label_id, values, rows, cols, scale_min, scale_max, label_fmt, bounds_min, bounds_max, flags)
            if nargin < 5, scale_min = 0; end
            if nargin < 6, scale_max = 0; end
            if nargin < 7, label_fmt = '%.1f'; end
            if nargin < 8, bounds_min = [0, 0]; end
            if nargin < 9, bounds_max = [1, 1]; end
            if nargin < 10, flags = 0; end
            call_mex('implot_plot_heatmap', label_id, values, rows, cols, scale_min, scale_max, label_fmt, bounds_min, bounds_max, flags);
        end

        % === Styling =======================================================
        function SetNextLineStyle(col, weight)
            if nargin < 1, col = [0, 0, 0, 0]; end  % IMPLOT_AUTO_COL sentinel
            if nargin < 2, weight = -1; end          % IMPLOT_AUTO
            call_mex('implot_set_next_line_style', col, weight);
        end

        function SetNextMarkerStyle(marker, size, fill, weight, outline)
            if nargin < 1, marker = -1; end
            if nargin < 2, size = -1; end
            if nargin < 3, fill = [0, 0, 0, 0]; end
            if nargin < 4, weight = -1; end
            if nargin < 5, outline = [0, 0, 0, 0]; end
            call_mex('implot_set_next_marker_style', marker, size, fill, weight, outline);
        end

        % === Subplots ======================================================
        function ok = BeginSubplots(title_id, rows, cols, size, flags)
            if nargin < 5, flags = 0; end
            ok = call_mex('implot_begin_subplots', title_id, rows, cols, size, flags);
        end

        function EndSubplots()
            call_mex('implot_end_subplots');
        end

        % === Setup =========================================================
        function SetupAxisFormat(axis, fmt)
            call_mex('implot_setup_axis_format', axis, fmt);
        end

        function SetupAxisScale(axis, scale)
            call_mex('implot_setup_axis_scale', axis, scale);
        end

        function SetupLegend(location, flags)
            if nargin < 2, flags = 0; end
            call_mex('implot_setup_legend', location, flags);
        end

        function SetupMouseText(location, flags)
            if nargin < 2, flags = 0; end
            call_mex('implot_setup_mouse_text', location, flags);
        end

        function SetupFinish()
            call_mex('implot_setup_finish');
        end

        % === Plot items ====================================================
        function PlotStairs(label_id, values, xscale, xstart, flags)
            if nargin < 3, xscale = 1; end
            if nargin < 4, xstart = 0; end
            if nargin < 5, flags = 0; end
            call_mex('implot_plot_stairs', label_id, values, xscale, xstart, flags);
        end

        function PlotStairsXY(label_id, xs, ys, flags)
            if nargin < 4, flags = 0; end
            call_mex('implot_plot_stairs_xy', label_id, xs, ys, flags);
        end

        function PlotShaded(label_id, values, yref, xscale, xstart, flags)
            if nargin < 3, yref = 0; end
            if nargin < 4, xscale = 1; end
            if nargin < 5, xstart = 0; end
            if nargin < 6, flags = 0; end
            call_mex('implot_plot_shaded', label_id, values, yref, xscale, xstart, flags);
        end

        function PlotShadedXY(label_id, xs, ys, yref, flags)
            if nargin < 4, yref = 0; end
            if nargin < 5, flags = 0; end
            call_mex('implot_plot_shaded_xy', label_id, xs, ys, yref, flags);
        end

        function PlotShadedBetween(label_id, xs, ys1, ys2, flags)
            if nargin < 5, flags = 0; end
            call_mex('implot_plot_shaded_between', label_id, xs, ys1, ys2, flags);
        end

        function PlotBarGroups(label_ids, values, group_size, shift, flags)
            if nargin < 3, group_size = 0.67; end
            if nargin < 4, shift = 0; end
            if nargin < 5, flags = 0; end
            call_mex('implot_plot_bar_groups', label_ids, values, group_size, shift, flags);
        end

        function PlotErrorBars(label_id, xs, ys, err, flags)
            if nargin < 5, flags = 0; end
            call_mex('implot_plot_error_bars', label_id, xs, ys, err, flags);
        end

        function PlotErrorBarsAsymmetric(label_id, xs, ys, neg, pos, flags)
            if nargin < 6, flags = 0; end
            call_mex('implot_plot_error_bars_asymmetric', label_id, xs, ys, neg, pos, flags);
        end

        function PlotStems(label_id, values, ref, scale, start, flags)
            if nargin < 3, ref = 0; end
            if nargin < 4, scale = 1; end
            if nargin < 5, start = 0; end
            if nargin < 6, flags = 0; end
            call_mex('implot_plot_stems', label_id, values, ref, scale, start, flags);
        end

        function PlotStemsXY(label_id, xs, ys, ref, flags)
            if nargin < 4, ref = 0; end
            if nargin < 5, flags = 0; end
            call_mex('implot_plot_stems_xy', label_id, xs, ys, ref, flags);
        end

        function max_density = PlotHistogram(label_id, values, bins, bar_scale, range_min, range_max, flags)
            if nargin < 3, bins = int32(polyscope.ImPlot.get_constant('ImPlotBin_Sturges')); end
            if nargin < 4, bar_scale = 1; end
            if nargin < 5, range_min = 0; end
            if nargin < 6, range_max = 0; end
            if nargin < 7, flags = 0; end
            max_density = call_mex('implot_plot_histogram', label_id, values, bins, bar_scale, range_min, range_max, flags);
        end

        function max_density = PlotHistogram2D(label_id, xs, ys, x_bins, y_bins, range, flags)
            if nargin < 4, x_bins = int32(polyscope.ImPlot.get_constant('ImPlotBin_Sturges')); end
            if nargin < 5, y_bins = int32(polyscope.ImPlot.get_constant('ImPlotBin_Sturges')); end
            if nargin < 6, range = [0, 0, 0, 0]; end
            if nargin < 7, flags = 0; end
            max_density = call_mex('implot_plot_histogram2d', label_id, xs, ys, x_bins, y_bins, range, flags);
        end

        function PlotDigital(label_id, xs, ys, flags)
            if nargin < 4, flags = 0; end
            call_mex('implot_plot_digital', label_id, xs, ys, flags);
        end

        % === Plot tools ====================================================
        function varargout = DragPoint(id, x, y, col, size, flags)
            if nargin < 5, size = 4; end
            if nargin < 6, flags = 0; end
            [varargout{1:3}] = call_mex('implot_drag_point', id, x, y, col, size, flags);
        end

        function varargout = DragLineX(id, x, col, thickness, flags)
            if nargin < 4, thickness = 1; end
            if nargin < 5, flags = 0; end
            [varargout{1:2}] = call_mex('implot_drag_line_x', id, x, col, thickness, flags);
        end

        function varargout = DragLineY(id, y, col, thickness, flags)
            if nargin < 4, thickness = 1; end
            if nargin < 5, flags = 0; end
            [varargout{1:2}] = call_mex('implot_drag_line_y', id, y, col, thickness, flags);
        end

        function varargout = DragRect(id, x1, y1, x2, y2, col, flags)
            if nargin < 7, flags = 0; end
            [varargout{1:5}] = call_mex('implot_drag_rect', id, x1, y1, x2, y2, col, flags);
        end

        function Annotation(x, y, col, pix_offset, clamp, text)
            call_mex('implot_annotation', x, y, col, pix_offset, clamp, text);
        end

        function TagX(x, col, text)
            call_mex('implot_tag_x', x, col, text);
        end

        function TagY(y, col, text)
            call_mex('implot_tag_y', y, col, text);
        end

        % === Axis management ===============================================
        function SetAxis(axis)
            call_mex('implot_set_axis', axis);
        end

        function SetAxes(x_axis, y_axis)
            call_mex('implot_set_axes', x_axis, y_axis);
        end

        % === Coordinate transforms =========================================
        function p = PixelsToPlot(x, y, x_axis, y_axis)
            if nargin < 3, x_axis = int32(polyscope.ImPlot.get_constant('IMPLOT_AUTO')); end
            if nargin < 4, y_axis = int32(polyscope.ImPlot.get_constant('IMPLOT_AUTO')); end
            p = call_mex('implot_pixels_to_plot', x, y, x_axis, y_axis);
        end

        function p = PlotToPixels(x, y, x_axis, y_axis)
            if nargin < 3, x_axis = int32(polyscope.ImPlot.get_constant('IMPLOT_AUTO')); end
            if nargin < 4, y_axis = int32(polyscope.ImPlot.get_constant('IMPLOT_AUTO')); end
            p = call_mex('implot_plot_to_pixels', x, y, x_axis, y_axis);
        end

        function p = GetPlotPos()
            p = call_mex('implot_get_plot_pos');
        end

        function p = GetPlotSize()
            p = call_mex('implot_get_plot_size');
        end

        function p = GetPlotMousePos(x_axis, y_axis)
            if nargin < 1, x_axis = int32(polyscope.ImPlot.get_constant('IMPLOT_AUTO')); end
            if nargin < 2, y_axis = int32(polyscope.ImPlot.get_constant('IMPLOT_AUTO')); end
            p = call_mex('implot_get_plot_mouse_pos', x_axis, y_axis);
        end

        function v = IsPlotHovered()
            v = call_mex('implot_is_plot_hovered');
        end

        function v = IsAxisHovered(axis)
            v = call_mex('implot_is_axis_hovered', axis);
        end

        % === Style =========================================================
        function PushStyleColor(idx, col)
            call_mex('implot_push_style_color', idx, col);
        end

        function PopStyleColor(count)
            if nargin < 1, count = 1; end
            call_mex('implot_pop_style_color', count);
        end

        function PushStyleVar(idx, val)
            call_mex('implot_push_style_var', idx, val);
        end

        function PopStyleVar(count)
            if nargin < 1, count = 1; end
            call_mex('implot_pop_style_var', count);
        end

        function SetNextFillStyle(col, alpha_mod)
            if nargin < 2, alpha_mod = -1; end
            call_mex('implot_set_next_fill_style', col, alpha_mod);
        end

        function v = GetLastItemColor()
            v = call_mex('implot_get_last_item_color');
        end

        % === Setup / axis ticks and constraints ============================
        function SetupAxisTicksValues(axis, values, labels, keep_default)
            if nargin < 3, labels = {}; end
            if nargin < 4, keep_default = false; end
            call_mex('implot_setup_axis_ticks_values', axis, values, labels, keep_default);
        end

        function SetupAxisTicksRange(axis, v_min, v_max, n_ticks, labels, keep_default)
            if nargin < 5, labels = {}; end
            if nargin < 6, keep_default = false; end
            call_mex('implot_setup_axis_ticks_range', axis, v_min, v_max, n_ticks, labels, keep_default);
        end

        function SetupAxisLimitsConstraints(axis, v_min, v_max)
            call_mex('implot_setup_axis_limits_constraints', axis, v_min, v_max);
        end

        function SetupAxisZoomConstraints(axis, z_min, z_max)
            call_mex('implot_setup_axis_zoom_constraints', axis, z_min, z_max);
        end

        % === Plot items not yet bound ======================================
        function PlotPieChart(label_ids, values, x, y, radius, label_fmt, angle0, flags)
            if nargin < 6, label_fmt = '%.1f'; end
            if nargin < 7, angle0 = 90; end
            if nargin < 8, flags = 0; end
            call_mex('implot_plot_pie_chart', label_ids, values, x, y, radius, label_fmt, angle0, flags);
        end

        function PlotImage(label_id, tex_id, bounds_min, bounds_max, uv0, uv1, tint_col, flags)
            if nargin < 5, uv0 = [0, 0]; end
            if nargin < 6, uv1 = [1, 1]; end
            if nargin < 7, tint_col = [1, 1, 1, 1]; end
            if nargin < 8, flags = 0; end
            call_mex('implot_plot_image', label_id, tex_id, bounds_min, bounds_max, uv0, uv1, tint_col, flags);
        end

        function PlotText(text, x, y, pix_offset, flags)
            if nargin < 4, pix_offset = [0, 0]; end
            if nargin < 5, flags = 0; end
            call_mex('implot_plot_text', text, x, y, pix_offset, flags);
        end

        function PlotDummy(label_id, flags)
            if nargin < 2, flags = 0; end
            call_mex('implot_plot_dummy', label_id, flags);
        end

        % === Subplots / selection / popup / aligned ========================
        function ok = BeginAlignedPlots(group_id, vertical)
            if nargin < 2, vertical = true; end
            ok = call_mex('implot_begin_aligned_plots', group_id, vertical);
        end

        function EndAlignedPlots()
            call_mex('implot_end_aligned_plots');
        end

        function ok = BeginLegendPopup(label_id, mouse_button)
            if nargin < 1, label_id = ''; end
            if nargin < 2, mouse_button = int32(1); end
            ok = call_mex('implot_begin_legend_popup', label_id, mouse_button);
        end

        function EndLegendPopup()
            call_mex('implot_end_legend_popup');
        end

        function v = IsLegendEntryHovered(label_id)
            v = call_mex('implot_is_legend_entry_hovered', label_id);
        end

        function HideNextItem(hidden, cond)
            if nargin < 1, hidden = true; end
            if nargin < 2, cond = int32(polyscope.ImPlot.get_constant('ImPlotCond_Once')); end
            call_mex('implot_hide_next_item', hidden, cond);
        end

        function CancelPlotSelection()
            call_mex('implot_cancel_plot_selection');
        end

        function v = IsSubplotsHovered()
            v = call_mex('implot_is_subplots_hovered');
        end

        function v = IsPlotSelected()
            v = call_mex('implot_is_plot_selected');
        end

        function v = GetPlotSelection(x_axis, y_axis)
            if nargin < 1, x_axis = int32(polyscope.ImPlot.get_constant('IMPLOT_AUTO')); end
            if nargin < 2, y_axis = int32(polyscope.ImPlot.get_constant('IMPLOT_AUTO')); end
            v = call_mex('implot_get_plot_selection', x_axis, y_axis);
        end

        function v = GetPlotLimits(x_axis, y_axis)
            if nargin < 1, x_axis = int32(polyscope.ImPlot.get_constant('IMPLOT_AUTO')); end
            if nargin < 2, y_axis = int32(polyscope.ImPlot.get_constant('IMPLOT_AUTO')); end
            v = call_mex('implot_get_plot_limits', x_axis, y_axis);
        end

        % === Drag-drop =====================================================
        function v = BeginDragDropTargetPlot()
            v = call_mex('implot_begin_drag_drop_target_plot');
        end

        function v = BeginDragDropTargetAxis(axis)
            v = call_mex('implot_begin_drag_drop_target_axis', axis);
        end

        function v = BeginDragDropTargetLegend()
            v = call_mex('implot_begin_drag_drop_target_legend');
        end

        function EndDragDropTarget()
            call_mex('implot_end_drag_drop_target');
        end

        function v = BeginDragDropSourcePlot(flags)
            if nargin < 1, flags = 0; end
            v = call_mex('implot_begin_drag_drop_source_plot', flags);
        end

        function v = BeginDragDropSourceAxis(axis, flags)
            if nargin < 2, flags = 0; end
            v = call_mex('implot_begin_drag_drop_source_axis', axis, flags);
        end

        function v = BeginDragDropSourceItem(label_id, flags)
            if nargin < 2, flags = 0; end
            v = call_mex('implot_begin_drag_drop_source_item', label_id, flags);
        end

        function EndDragDropSource()
            call_mex('implot_end_drag_drop_source');
        end

        % === Colormap ======================================================
        function idx = AddColormap(name, cols, qual)
            if nargin < 3, qual = true; end
            idx = call_mex('implot_add_colormap', name, cols, qual);
        end

        function v = GetColormapCount()
            v = call_mex('implot_get_colormap_count');
        end

        function v = GetColormapName(cmap)
            v = call_mex('implot_get_colormap_name', cmap);
        end

        function v = GetColormapIndex(name)
            v = call_mex('implot_get_colormap_index', name);
        end

        function PushColormap(cmap_or_name)
            call_mex('implot_push_colormap', cmap_or_name);
        end

        function PopColormap(count)
            if nargin < 1, count = int32(1); end
            call_mex('implot_pop_colormap', count);
        end

        function v = NextColormapColor()
            v = call_mex('implot_next_colormap_color');
        end

        function v = GetColormapSize(cmap)
            if nargin < 1, cmap = int32(polyscope.ImPlot.get_constant('IMPLOT_AUTO')); end
            v = call_mex('implot_get_colormap_size', cmap);
        end

        function v = GetColormapColor(idx, cmap)
            if nargin < 2, cmap = int32(polyscope.ImPlot.get_constant('IMPLOT_AUTO')); end
            v = call_mex('implot_get_colormap_color', idx, cmap);
        end

        function v = SampleColormap(t, cmap)
            if nargin < 2, cmap = int32(polyscope.ImPlot.get_constant('IMPLOT_AUTO')); end
            v = call_mex('implot_sample_colormap', t, cmap);
        end

        function ColormapScale(label, scale_min, scale_max, size, format, flags, cmap)
            if nargin < 4, size = [0, 0]; end
            if nargin < 5, format = '%g'; end
            if nargin < 6, flags = 0; end
            if nargin < 7, cmap = int32(polyscope.ImPlot.get_constant('IMPLOT_AUTO')); end
            call_mex('implot_colormap_scale', label, scale_min, scale_max, size, format, flags, cmap);
        end

        function varargout = ColormapSlider(label, t, format, cmap)
            if nargin < 3, format = ''; end
            if nargin < 4, cmap = int32(polyscope.ImPlot.get_constant('IMPLOT_AUTO')); end
            [varargout{1:3}] = call_mex('implot_colormap_slider', label, t, format, cmap);
        end

        function v = ColormapButton(label, size, cmap)
            if nargin < 2, size = [0, 0]; end
            if nargin < 3, cmap = int32(polyscope.ImPlot.get_constant('IMPLOT_AUTO')); end
            v = call_mex('implot_colormap_button', label, size, cmap);
        end

        function BustColorCache(plot_title_id)
            if nargin < 1, plot_title_id = ''; end
            call_mex('implot_bust_color_cache', plot_title_id);
        end

        % === Style / input map / icons / draw list / show ==================
        function s = GetStyle()
            h = call_mex('implot_get_style');
            s = polyscope.ImPlotStyle(h);
        end

        function StyleColorsAuto()
            call_mex('implot_style_colors_auto');
        end

        function StyleColorsClassic()
            call_mex('implot_style_colors_classic');
        end

        function StyleColorsDark()
            call_mex('implot_style_colors_dark');
        end

        function StyleColorsLight()
            call_mex('implot_style_colors_light');
        end

        function m = GetInputMap()
            h = call_mex('implot_get_input_map');
            m = polyscope.ImPlotInputMap(h);
        end

        function MapInputDefault()
            call_mex('implot_map_input_default');
        end

        function MapInputReverse()
            call_mex('implot_map_input_reverse');
        end

        function ItemIcon(col)
            call_mex('implot_item_icon', col);
        end

        function ColormapIcon(cmap)
            call_mex('implot_colormap_icon', cmap);
        end

        function h = GetPlotDrawList()
            h = call_mex('implot_get_plot_draw_list');
        end

        function PushPlotClipRect(expand)
            if nargin < 1, expand = 0; end
            call_mex('implot_push_plot_clip_rect', expand);
        end

        function PopPlotClipRect()
            call_mex('implot_pop_plot_clip_rect');
        end

        function v = ShowStyleSelector(label)
            v = call_mex('implot_show_style_selector', label);
        end

        function v = ShowColormapSelector(label)
            v = call_mex('implot_show_colormap_selector', label);
        end

        function v = ShowInputMapSelector(label)
            v = call_mex('implot_show_input_map_selector', label);
        end

        function ShowStyleEditor()
            call_mex('implot_show_style_editor');
        end

        function ShowUserGuide()
            call_mex('implot_show_user_guide');
        end
    end
end
