classdef ImPlotStyle < handle
    %IMPLOTSTYLE MATLAB wrapper for an ImPlotStyle object.
    %   Holds a 64-bit handle to the underlying C++ ImPlotStyle pointer.
    %   The C++ object is owned by ImPlot and is not freed by this class.

    properties (Access = private)
        Handle
    end

    properties (Dependent)
        LineWeight
        Marker
        MarkerSize
        MarkerWeight
        FillAlpha
        ErrorBarSize
        ErrorBarWeight
        DigitalBitHeight
        DigitalBitGap
        PlotBorderSize
        MinorAlpha
        MajorTickLen
        MinorTickLen
        MajorTickSize
        MinorTickSize
        MajorGridSize
        MinorGridSize
        PlotPadding
        LabelPadding
        LegendPadding
        LegendInnerPadding
        LegendSpacing
        MousePosPadding
        AnnotationPadding
        FitPadding
        PlotDefaultSize
        PlotMinSize
        Colormap
        UseLocalTime
        UseISO8601
        Use24HourClock
    end

    methods
        function obj = ImPlotStyle(handle)
            obj.Handle = handle;
        end

        function v = get.Handle(obj)
            v = obj.Handle;
        end

        function v = get.LineWeight(obj)
            v = call_mex('implot_style_get', obj.Handle, 'LineWeight');
        end
        function set.LineWeight(obj, v)
            call_mex('implot_style_set', obj.Handle, 'LineWeight', v);
        end

        function v = get.Marker(obj)
            v = call_mex('implot_style_get', obj.Handle, 'Marker');
        end
        function set.Marker(obj, v)
            call_mex('implot_style_set', obj.Handle, 'Marker', v);
        end

        function v = get.MarkerSize(obj)
            v = call_mex('implot_style_get', obj.Handle, 'MarkerSize');
        end
        function set.MarkerSize(obj, v)
            call_mex('implot_style_set', obj.Handle, 'MarkerSize', v);
        end

        function v = get.MarkerWeight(obj)
            v = call_mex('implot_style_get', obj.Handle, 'MarkerWeight');
        end
        function set.MarkerWeight(obj, v)
            call_mex('implot_style_set', obj.Handle, 'MarkerWeight', v);
        end

        function v = get.FillAlpha(obj)
            v = call_mex('implot_style_get', obj.Handle, 'FillAlpha');
        end
        function set.FillAlpha(obj, v)
            call_mex('implot_style_set', obj.Handle, 'FillAlpha', v);
        end

        function v = get.ErrorBarSize(obj)
            v = call_mex('implot_style_get', obj.Handle, 'ErrorBarSize');
        end
        function set.ErrorBarSize(obj, v)
            call_mex('implot_style_set', obj.Handle, 'ErrorBarSize', v);
        end

        function v = get.ErrorBarWeight(obj)
            v = call_mex('implot_style_get', obj.Handle, 'ErrorBarWeight');
        end
        function set.ErrorBarWeight(obj, v)
            call_mex('implot_style_set', obj.Handle, 'ErrorBarWeight', v);
        end

        function v = get.DigitalBitHeight(obj)
            v = call_mex('implot_style_get', obj.Handle, 'DigitalBitHeight');
        end
        function set.DigitalBitHeight(obj, v)
            call_mex('implot_style_set', obj.Handle, 'DigitalBitHeight', v);
        end

        function v = get.DigitalBitGap(obj)
            v = call_mex('implot_style_get', obj.Handle, 'DigitalBitGap');
        end
        function set.DigitalBitGap(obj, v)
            call_mex('implot_style_set', obj.Handle, 'DigitalBitGap', v);
        end

        function v = get.PlotBorderSize(obj)
            v = call_mex('implot_style_get', obj.Handle, 'PlotBorderSize');
        end
        function set.PlotBorderSize(obj, v)
            call_mex('implot_style_set', obj.Handle, 'PlotBorderSize', v);
        end

        function v = get.MinorAlpha(obj)
            v = call_mex('implot_style_get', obj.Handle, 'MinorAlpha');
        end
        function set.MinorAlpha(obj, v)
            call_mex('implot_style_set', obj.Handle, 'MinorAlpha', v);
        end

        function v = get.MajorTickLen(obj)
            v = call_mex('implot_style_get', obj.Handle, 'MajorTickLen');
        end
        function set.MajorTickLen(obj, v)
            call_mex('implot_style_set', obj.Handle, 'MajorTickLen', v);
        end

        function v = get.MinorTickLen(obj)
            v = call_mex('implot_style_get', obj.Handle, 'MinorTickLen');
        end
        function set.MinorTickLen(obj, v)
            call_mex('implot_style_set', obj.Handle, 'MinorTickLen', v);
        end

        function v = get.MajorTickSize(obj)
            v = call_mex('implot_style_get', obj.Handle, 'MajorTickSize');
        end
        function set.MajorTickSize(obj, v)
            call_mex('implot_style_set', obj.Handle, 'MajorTickSize', v);
        end

        function v = get.MinorTickSize(obj)
            v = call_mex('implot_style_get', obj.Handle, 'MinorTickSize');
        end
        function set.MinorTickSize(obj, v)
            call_mex('implot_style_set', obj.Handle, 'MinorTickSize', v);
        end

        function v = get.MajorGridSize(obj)
            v = call_mex('implot_style_get', obj.Handle, 'MajorGridSize');
        end
        function set.MajorGridSize(obj, v)
            call_mex('implot_style_set', obj.Handle, 'MajorGridSize', v);
        end

        function v = get.MinorGridSize(obj)
            v = call_mex('implot_style_get', obj.Handle, 'MinorGridSize');
        end
        function set.MinorGridSize(obj, v)
            call_mex('implot_style_set', obj.Handle, 'MinorGridSize', v);
        end

        function v = get.PlotPadding(obj)
            v = call_mex('implot_style_get', obj.Handle, 'PlotPadding');
        end
        function set.PlotPadding(obj, v)
            call_mex('implot_style_set', obj.Handle, 'PlotPadding', v);
        end

        function v = get.LabelPadding(obj)
            v = call_mex('implot_style_get', obj.Handle, 'LabelPadding');
        end
        function set.LabelPadding(obj, v)
            call_mex('implot_style_set', obj.Handle, 'LabelPadding', v);
        end

        function v = get.LegendPadding(obj)
            v = call_mex('implot_style_get', obj.Handle, 'LegendPadding');
        end
        function set.LegendPadding(obj, v)
            call_mex('implot_style_set', obj.Handle, 'LegendPadding', v);
        end

        function v = get.LegendInnerPadding(obj)
            v = call_mex('implot_style_get', obj.Handle, 'LegendInnerPadding');
        end
        function set.LegendInnerPadding(obj, v)
            call_mex('implot_style_set', obj.Handle, 'LegendInnerPadding', v);
        end

        function v = get.LegendSpacing(obj)
            v = call_mex('implot_style_get', obj.Handle, 'LegendSpacing');
        end
        function set.LegendSpacing(obj, v)
            call_mex('implot_style_set', obj.Handle, 'LegendSpacing', v);
        end

        function v = get.MousePosPadding(obj)
            v = call_mex('implot_style_get', obj.Handle, 'MousePosPadding');
        end
        function set.MousePosPadding(obj, v)
            call_mex('implot_style_set', obj.Handle, 'MousePosPadding', v);
        end

        function v = get.AnnotationPadding(obj)
            v = call_mex('implot_style_get', obj.Handle, 'AnnotationPadding');
        end
        function set.AnnotationPadding(obj, v)
            call_mex('implot_style_set', obj.Handle, 'AnnotationPadding', v);
        end

        function v = get.FitPadding(obj)
            v = call_mex('implot_style_get', obj.Handle, 'FitPadding');
        end
        function set.FitPadding(obj, v)
            call_mex('implot_style_set', obj.Handle, 'FitPadding', v);
        end

        function v = get.PlotDefaultSize(obj)
            v = call_mex('implot_style_get', obj.Handle, 'PlotDefaultSize');
        end
        function set.PlotDefaultSize(obj, v)
            call_mex('implot_style_set', obj.Handle, 'PlotDefaultSize', v);
        end

        function v = get.PlotMinSize(obj)
            v = call_mex('implot_style_get', obj.Handle, 'PlotMinSize');
        end
        function set.PlotMinSize(obj, v)
            call_mex('implot_style_set', obj.Handle, 'PlotMinSize', v);
        end

        function v = get.Colormap(obj)
            v = call_mex('implot_style_get', obj.Handle, 'Colormap');
        end
        function set.Colormap(obj, v)
            call_mex('implot_style_set', obj.Handle, 'Colormap', v);
        end

        function v = get.UseLocalTime(obj)
            v = call_mex('implot_style_get', obj.Handle, 'UseLocalTime');
        end
        function set.UseLocalTime(obj, v)
            call_mex('implot_style_set', obj.Handle, 'UseLocalTime', v);
        end

        function v = get.UseISO8601(obj)
            v = call_mex('implot_style_get', obj.Handle, 'UseISO8601');
        end
        function set.UseISO8601(obj, v)
            call_mex('implot_style_set', obj.Handle, 'UseISO8601', v);
        end

        function v = get.Use24HourClock(obj)
            v = call_mex('implot_style_get', obj.Handle, 'Use24HourClock');
        end
        function set.Use24HourClock(obj, v)
            call_mex('implot_style_set', obj.Handle, 'Use24HourClock', v);
        end
    end
end
