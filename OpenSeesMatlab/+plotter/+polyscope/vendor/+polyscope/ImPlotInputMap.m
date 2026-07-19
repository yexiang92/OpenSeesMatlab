classdef ImPlotInputMap < handle
    %IMPLOTINPUTMAP MATLAB wrapper for an ImPlotInputMap object.
    %   Holds a 64-bit handle to the underlying C++ ImPlotInputMap pointer.
    %   The C++ object is owned by ImPlot and is not freed by this class.

    properties (Access = private)
        Handle
    end

    properties (Dependent)
        Pan
        PanMod
        Fit
        Select
        SelectCancel
        SelectMod
        SelectHorzMod
        SelectVertMod
        Menu
        OverrideMod
        ZoomMod
        ZoomRate
    end

    methods
        function obj = ImPlotInputMap(handle)
            obj.Handle = handle;
        end

        function v = get.Handle(obj)
            v = obj.Handle;
        end

        function v = get.Pan(obj)
            v = call_mex('implot_input_map_get', obj.Handle, 'Pan');
        end
        function set.Pan(obj, v)
            call_mex('implot_input_map_set', obj.Handle, 'Pan', v);
        end

        function v = get.PanMod(obj)
            v = call_mex('implot_input_map_get', obj.Handle, 'PanMod');
        end
        function set.PanMod(obj, v)
            call_mex('implot_input_map_set', obj.Handle, 'PanMod', v);
        end

        function v = get.Fit(obj)
            v = call_mex('implot_input_map_get', obj.Handle, 'Fit');
        end
        function set.Fit(obj, v)
            call_mex('implot_input_map_set', obj.Handle, 'Fit', v);
        end

        function v = get.Select(obj)
            v = call_mex('implot_input_map_get', obj.Handle, 'Select');
        end
        function set.Select(obj, v)
            call_mex('implot_input_map_set', obj.Handle, 'Select', v);
        end

        function v = get.SelectCancel(obj)
            v = call_mex('implot_input_map_get', obj.Handle, 'SelectCancel');
        end
        function set.SelectCancel(obj, v)
            call_mex('implot_input_map_set', obj.Handle, 'SelectCancel', v);
        end

        function v = get.SelectMod(obj)
            v = call_mex('implot_input_map_get', obj.Handle, 'SelectMod');
        end
        function set.SelectMod(obj, v)
            call_mex('implot_input_map_set', obj.Handle, 'SelectMod', v);
        end

        function v = get.SelectHorzMod(obj)
            v = call_mex('implot_input_map_get', obj.Handle, 'SelectHorzMod');
        end
        function set.SelectHorzMod(obj, v)
            call_mex('implot_input_map_set', obj.Handle, 'SelectHorzMod', v);
        end

        function v = get.SelectVertMod(obj)
            v = call_mex('implot_input_map_get', obj.Handle, 'SelectVertMod');
        end
        function set.SelectVertMod(obj, v)
            call_mex('implot_input_map_set', obj.Handle, 'SelectVertMod', v);
        end

        function v = get.Menu(obj)
            v = call_mex('implot_input_map_get', obj.Handle, 'Menu');
        end
        function set.Menu(obj, v)
            call_mex('implot_input_map_set', obj.Handle, 'Menu', v);
        end

        function v = get.OverrideMod(obj)
            v = call_mex('implot_input_map_get', obj.Handle, 'OverrideMod');
        end
        function set.OverrideMod(obj, v)
            call_mex('implot_input_map_set', obj.Handle, 'OverrideMod', v);
        end

        function v = get.ZoomMod(obj)
            v = call_mex('implot_input_map_get', obj.Handle, 'ZoomMod');
        end
        function set.ZoomMod(obj, v)
            call_mex('implot_input_map_set', obj.Handle, 'ZoomMod', v);
        end

        function v = get.ZoomRate(obj)
            v = call_mex('implot_input_map_get', obj.Handle, 'ZoomRate');
        end
        function set.ZoomRate(obj, v)
            call_mex('implot_input_map_set', obj.Handle, 'ZoomRate', v);
        end
    end
end
