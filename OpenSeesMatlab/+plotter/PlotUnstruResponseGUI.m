function app = PlotUnstruResponseGUI(modelInfo, nodalResp, eleResp, options)
% PlotUnstruResponseGUI Interactive GUI wrapper for plotter.PlotUnstruResponse.
%
% Syntax
% ------
%   app = plotter.PlotUnstruResponseGUI(modelInfo, nodalResp, eleResp)
%   app = plotter.PlotUnstruResponseGUI(modelInfo, nodalResp, eleResp, opts=opts)
%   app = plotter.PlotUnstruResponseGUI(..., eleType="Shell", respType="StressAtGP")

arguments
    modelInfo struct
    nodalResp struct
    eleResp struct
    options.eleType {mustBeTextScalar} = ""
    options.respType {mustBeTextScalar} = ""
    options.respComponent {mustBeTextScalar} = ""
    options.fiberPoint = "top"
    options.stepIdx = "absMax"
    options.opts (1,1) struct = struct()
end

opts0 = localMerge(plotter.PlotUnstruResponse.defaultOptions(), options.opts);
opts0.general.clearAxes = true;
opts0.general.holdOn = true;
opts0.general.figureSize = [];

eleType0 = localInitialEleType(eleResp, options.eleType);
respTypes = localResponseTypes(eleResp, eleType0);
respType0 = localInitialRespType(respTypes, eleType0, options.respType);
components = localComponents(eleResp, eleType0, respType0);
component0 = localInitialComponent(components, eleType0, respType0, options.respComponent);

probeFig = figure('Visible', 'off');
probeAx = axes('Parent', probeFig);
probe = plotter.PlotUnstruResponse(modelInfo, nodalResp, eleResp, probeAx, opts0);
nStep = max(1, probe.nSteps());
delete(probeFig);

fig = figure( ...
    'Name', 'OpenSeesMatlab Unstructured Response Plotter | by Yexiang Yan', ...
    'NumberTitle', 'off', ...
    'Color', 'w', ...
    'MenuBar', 'none', ...
    'Toolbar', 'figure', ...
    'Units', 'pixels', ...
    'Position', [150 120 1260 760]);

ax = axes('Parent', fig, 'Units', 'normalized', 'Position', [0.29 0.16 0.69 0.78]);
panel = uipanel( ...
    'Parent', fig, ...
    'Title', 'PlotUnstruResponse GUI', ...
    'Units', 'normalized', ...
    'Position', [0.015 0.035 0.26 0.93], ...
    'BackgroundColor', 'w');
infoPanel = uipanel( ...
    'Parent', fig, ...
    'Title', 'Response information', ...
    'Units', 'normalized', ...
    'Position', [0.29 0.035 0.69 0.11], ...
    'BackgroundColor', 'w');

state.opts = opts0;
state.modelInfo = modelInfo;
state.nodalResp = nodalResp;
state.eleResp = eleResp;
state.eleType = eleType0;
state.respType = respType0;
state.component = component0;
state.fiberPoint = options.fiberPoint;
state.respTypes = respTypes;
state.components = components;
state.nStep = nStep;
state.pu = [];
state.isRedrawing = false;

controls = struct();
y = 0.955;
dy = 0.035;

addLabel('Element', y);
controls.eleType = addPopup({'Shell','Plane','Solid'}, state.eleType, y, @eleTypeChanged);
y = y - dy;

addLabel('Response', y);
controls.respType = addPopup(state.respTypes, state.respType, y, @responseChanged);
y = y - dy;

addLabel('Component', y);
controls.component = addPopup(state.components, state.component, y, @redraw);
y = y - dy;

addLabel('Fiber', y);
controls.fiberPoint = addPopup({'top','middle','bottom'}, localFiberText(state.fiberPoint), y, @redraw);
y = y - dy;

addLabel('Location', y);
controls.responseLocation = addPopup({'auto','node','gp','element'}, localLocationValue(state.opts.responseLocation), y, @redraw);
y = y - dy;

addLabel('Step mode', y);
controls.stepMode = addPopup({'absMax','absMin','Max','Min','step'}, localStepMode(options.stepIdx), y, @redraw);
y = y - dy;

addLabel('Step', y);
controls.stepEdit = uicontrol(panel, 'Style', 'edit', 'Units', 'normalized', ...
    'Position', [0.42 y 0.20 0.030], ...
    'String', localStepString(options.stepIdx), ...
    'HorizontalAlignment', 'left', ...
    'Callback', @stepEditChanged);
controls.stepSlider = uicontrol(panel, 'Style', 'slider', 'Units', 'normalized', ...
    'Position', [0.65 y 0.29 0.030], ...
    'Min', 0, 'Max', max(1, state.nStep - 1), ...
    'Value', min(max(0, localStepValue(options.stepIdx)), max(0, state.nStep - 1)), ...
    'SliderStep', localSliderStep(state.nStep), ...
    'Callback', @stepSliderChanged);
y = y - dy;

uicontrol(panel, 'Style', 'pushbutton', 'Units', 'normalized', ...
    'Position', [0.06 y 0.24 0.032], 'String', 'Colors...', 'Callback', @showColors);
uicontrol(panel, 'Style', 'pushbutton', 'Units', 'normalized', ...
    'Position', [0.325 y 0.20 0.032], 'String', 'Redraw', 'Callback', @redraw);
uicontrol(panel, 'Style', 'pushbutton', 'Units', 'normalized', ...
    'Position', [0.55 y 0.20 0.032], 'String', 'Reset', 'Callback', @resetOptions);
uicontrol(panel, 'Style', 'pushbutton', 'Units', 'normalized', ...
    'Position', [0.775 y 0.165 0.032], 'String', 'Help', 'Callback', @showHelp);
y = y - dy * 1.10;

addLabel('View', y);
controls.view = addPopup(localViewNames(), state.opts.general.view, y, @redraw);
y = y - dy;

addLabel('CLim mode', y);
controls.climMode = addPopup({'range','step','absMax','absMin'}, state.opts.color.climMode, y, @redraw);
y = y - dy;

addLabel('Color map', y);
controls.colormapName = addPopup(localColormapNames(), localColormapName(state.opts.color.colormap), y, @redraw);
y = y - dy;

addLabel('Color mode', y);
controls.colorMode = addPopup({'auto','node','element'}, state.opts.surf.colorMode, y, @redraw);
y = y - dy;

addLabel('GP reduce', y);
controls.gpReduce = addPopup({'mean','max','min','index'}, state.opts.surf.gpReduce, y, @redraw);
y = y - dy;

addLabel('Line color', y);
controls.interpColorBy = addPopup({'solid','field','disp'}, state.opts.interp.colorBy, y, @redraw);
y = y - dy;

addSeparator(y); y = y - dy * 0.55;
addText('Visibility', y); y = y - dy * 0.9;
[controls.deformShow, controls.autoScale] = addCheckPair('Deform', state.opts.deform.show, ...
    'Auto scale', state.opts.deform.autoScale, y); y = y - dy;
[controls.showUndeformed, controls.surfShow] = addCheckPair('Undeformed', state.opts.deform.showUndeformed, ...
    'Surface', state.opts.surf.show, y); y = y - dy;
[controls.showEdges, controls.lineShow] = addCheckPair('Surface edges', state.opts.surf.showEdges, ...
    'Lines', state.opts.line.show, y); y = y - dy;
[controls.useColormap, controls.cbarShow] = addCheckPair('Colormap', state.opts.color.useColormap, ...
    'Colorbar', state.opts.cbar.show, y); y = y - dy;
[controls.fixedShow, controls.useInterpolation] = addCheckPair('Fixed nodes', state.opts.fixed.show, ...
    'Interpolation', state.opts.interp.useInterpolation, y); y = y - dy;
[controls.grid, controls.box] = addCheckPair('Grid', state.opts.general.grid, ...
    'Box', state.opts.general.box, y); y = y - dy;
controls.axesOff = addCheck('Axes off', localGetBool(state.opts.general, 'axesOff', false), y); y = y - dy;

addSeparator(y); y = y - dy * 0.55;
addText('Scales / widths', y); y = y - dy * 0.8;
controls.deformScale = addSlider(0.01, 100, state.opts.deform.scale, y); y = y - dy;
addText('Surface alpha', y); y = y - dy * 0.8;
controls.deformedAlpha = addSlider(0, 1, state.opts.color.deformedAlpha, y); y = y - dy;
addText('Ghost alpha', y); y = y - dy * 0.8;
controls.undeformedAlpha = addSlider(0, 1, state.opts.color.undeformedAlpha, y); y = y - dy;
addText('Edge width', y); y = y - dy * 0.8;
controls.edgeWidth = addSlider(0.1, 5, state.opts.surf.edgeWidth, y); y = y - dy;
addText('Line width', y); y = y - dy * 0.8;
controls.lineWidth = addSlider(0.1, 8, state.opts.line.lineWidth, y); y = y - dy;
addText('GP index', y); y = y - dy * 0.8;
controls.gpIndex = addSlider(1, 20, state.opts.surf.gpIndex, y); y = y - dy;

addText('Title', y); y = y - dy * 0.8;
controls.title = uicontrol(panel, ...
    'Style', 'edit', ...
    'Units', 'normalized', ...
    'Position', [0.06 y 0.88 0.030], ...
    'String', char(string(state.opts.general.title)), ...
    'HorizontalAlignment', 'left', ...
    'Callback', @redraw);

controls.info = uicontrol(infoPanel, 'Style', 'edit', 'Units', 'normalized', ...
    'Position', [0.015 0.08 0.97 0.78], ...
    'String', localResponseSummary(state), ...
    'Max', 2, ...
    'Min', 0, ...
    'Enable', 'inactive', ...
    'HorizontalAlignment', 'left', ...
    'BackgroundColor', 'w', ...
    'FontName', 'Consolas');

localEnablePanelScroll(panel);

app = struct( ...
    'Figure', fig, ...
    'Axes', ax, ...
    'Controls', controls, ...
    'getOptions', @getOptions, ...
    'refresh', @redraw, ...
    'reset', @resetOptions);
fig.UserData = app;

redraw();

    function addText(txt, yy)
        uicontrol(panel, 'Style', 'text', 'Units', 'normalized', ...
            'Position', [0.06 yy 0.88 0.025], ...
            'String', txt, 'HorizontalAlignment', 'left', ...
            'FontWeight', 'bold', 'BackgroundColor', 'w');
    end

    function addLabel(txt, yy)
        uicontrol(panel, 'Style', 'text', 'Units', 'normalized', ...
            'Position', [0.06 yy 0.32 0.028], ...
            'String', txt, 'HorizontalAlignment', 'left', ...
            'BackgroundColor', 'w');
    end

    function addSeparator(yy)
        uicontrol(panel, 'Style', 'text', 'Units', 'normalized', ...
            'Position', [0.06 yy 0.88 0.006], ...
            'String', '', 'BackgroundColor', [0.84 0.84 0.84]);
    end

    function h = addPopup(items, value, yy, cb)
        if isempty(items), items = {''}; end
        if isstring(items), items = cellstr(items); end
        idx = find(strcmpi(items, char(string(value))), 1, 'first');
        if isempty(idx), idx = 1; end
        h = uicontrol(panel, 'Style', 'popupmenu', 'Units', 'normalized', ...
            'Position', [0.42 yy 0.52 0.030], ...
            'String', items, 'Value', idx, 'Callback', cb);
    end

    function [h1, h2] = addCheckPair(txt1, value1, txt2, value2, yy)
        h1 = uicontrol(panel, 'Style', 'checkbox', 'Units', 'normalized', ...
            'Position', [0.06 yy 0.42 0.030], ...
            'String', txt1, 'Value', logical(value1), ...
            'BackgroundColor', 'w', 'Callback', @redraw);
        h2 = uicontrol(panel, 'Style', 'checkbox', 'Units', 'normalized', ...
            'Position', [0.52 yy 0.42 0.030], ...
            'String', txt2, 'Value', logical(value2), ...
            'BackgroundColor', 'w', 'Callback', @redraw);
    end

    function h = addCheck(txt, value, yy)
        h = uicontrol(panel, 'Style', 'checkbox', 'Units', 'normalized', ...
            'Position', [0.06 yy 0.88 0.030], ...
            'String', txt, 'Value', logical(value), ...
            'BackgroundColor', 'w', 'Callback', @redraw);
    end

    function h = addSlider(lo, hi, value, yy)
        value = max(lo, min(hi, double(value)));
        h = uicontrol(panel, 'Style', 'slider', 'Units', 'normalized', ...
            'Position', [0.06 yy 0.88 0.030], ...
            'Min', lo, 'Max', hi, 'Value', value, 'Callback', @redraw);
    end

    function opts = getOptions()
        opts = state.opts;
    end

    function redraw(~, ~)
        if state.isRedrawing || ~ishandle(fig) || ~ishandle(ax)
            return;
        end
        state.isRedrawing = true;
        cleanup = onCleanup(@() setRedrawFlag(false));
        state.opts = readControls(state.opts);
        state.eleType = localSelected(controls.eleType);
        state.respType = localSelected(controls.respType);
        state.component = localSelected(controls.component);
        state.fiberPoint = localSelected(controls.fiberPoint);
        stepArg = readStepArg();
        try
            state.pu = plotter.PlotUnstruResponse(state.modelInfo, state.nodalResp, state.eleResp, ax, state.opts);
            state.pu.setResponse(state.eleType, state.respType, state.component, state.fiberPoint);
            state.pu.plotStep(stepArg);
            app.PlotUnstruResponse = state.pu;
            app.Options = state.opts;
            app.EleType = state.eleType;
            app.RespType = state.respType;
            app.Component = state.component;
            app.FiberPoint = state.fiberPoint;
            app.StepArg = stepArg;
            updateInfo('');
        catch ME
            cla(ax, 'reset');
            text(ax, 0.02, 0.98, ME.message, 'Units', 'normalized', ...
                'VerticalAlignment', 'top', 'Interpreter', 'none', ...
                'Color', [0.65 0.10 0.10]);
            updateInfo(sprintf('Draw failed: %s\n%s', ME.identifier, ME.message));
        end
        fig.UserData = app;
    end

    function setRedrawFlag(value)
        state.isRedrawing = value;
    end

    function eleTypeChanged(~, ~)
        state.eleType = localSelected(controls.eleType);
        state.respTypes = localResponseTypes(state.eleResp, state.eleType);
        state.respType = localInitialRespType(state.respTypes, state.eleType, '');
        state.components = localComponents(state.eleResp, state.eleType, state.respType);
        state.component = localInitialComponent(state.components, state.eleType, state.respType, '');
        controls.respType.String = state.respTypes;
        controls.respType.Value = 1;
        controls.component.String = state.components;
        controls.component.Value = 1;
        redraw();
    end

    function responseChanged(~, ~)
        state.respType = localSelected(controls.respType);
        state.components = localComponents(state.eleResp, state.eleType, state.respType);
        state.component = localInitialComponent(state.components, state.eleType, state.respType, '');
        controls.component.String = state.components;
        controls.component.Value = 1;
        redraw();
    end

    function stepEditChanged(~, ~)
        setPopup(controls.stepMode, 'step');
        value = str2double(controls.stepEdit.String);
        if ~isfinite(value)
            value = 0;
            controls.stepEdit.String = '0';
        end
        controls.stepSlider.Value = min(max(controls.stepSlider.Min, value), controls.stepSlider.Max);
        redraw();
    end

    function stepSliderChanged(~, ~)
        setPopup(controls.stepMode, 'step');
        controls.stepSlider.Value = round(controls.stepSlider.Value);
        controls.stepEdit.String = sprintf('%d', round(controls.stepSlider.Value));
        redraw();
    end

    function resetOptions(~, ~)
        state.opts = opts0;
        applyControls(state.opts);
        redraw();
    end

    function opts = readControls(opts)
        opts.responseLocation = localSelected(controls.responseLocation);
        if strcmpi(opts.responseLocation, 'auto'), opts.responseLocation = ''; end
        opts.general.view = localSelected(controls.view);
        opts.color.climMode = localSelected(controls.climMode);
        opts.color.colormap = localBuildColormap(localSelected(controls.colormapName));
        opts.surf.colorMode = localSelected(controls.colorMode);
        opts.surf.gpReduce = localSelected(controls.gpReduce);
        opts.interp.colorBy = localSelected(controls.interpColorBy);

        wantsUndeformed = logical(controls.showUndeformed.Value);
        wantsInterpolation = logical(controls.useInterpolation.Value);
        opts.deform.show = logical(controls.deformShow.Value) || wantsUndeformed;
        opts.deform.autoScale = logical(controls.autoScale.Value);
        opts.deform.showUndeformed = wantsUndeformed;
        opts.surf.show = logical(controls.surfShow.Value);
        opts.surf.showEdges = logical(controls.showEdges.Value);
        opts.line.show = logical(controls.lineShow.Value) || wantsInterpolation;
        opts.color.useColormap = logical(controls.useColormap.Value);
        opts.cbar.show = logical(controls.cbarShow.Value);
        opts.fixed.show = logical(controls.fixedShow.Value);
        opts.interp.useInterpolation = wantsInterpolation;
        opts.general.grid = logical(controls.grid.Value);
        opts.general.box = logical(controls.box.Value);
        opts.general.axesOff = logical(controls.axesOff.Value);
        controls.deformShow.Value = opts.deform.show;
        controls.lineShow.Value = opts.line.show;

        opts.deform.scale = controls.deformScale.Value;
        opts.color.deformedAlpha = controls.deformedAlpha.Value;
        opts.color.undeformedAlpha = controls.undeformedAlpha.Value;
        opts.surf.edgeWidth = controls.edgeWidth.Value;
        opts.line.lineWidth = controls.lineWidth.Value;
        opts.interp.lineWidth = controls.lineWidth.Value;
        opts.surf.gpIndex = round(controls.gpIndex.Value);
        opts.general.title = controls.title.String;
    end

    function applyControls(opts)
        setPopup(controls.eleType, state.eleType);
        setPopup(controls.respType, state.respType);
        setPopup(controls.component, state.component);
        setPopup(controls.fiberPoint, localFiberText(state.fiberPoint));
        setPopup(controls.responseLocation, localLocationValue(opts.responseLocation));
        setPopup(controls.view, opts.general.view);
        setPopup(controls.climMode, opts.color.climMode);
        setPopup(controls.colormapName, localColormapName(opts.color.colormap));
        setPopup(controls.colorMode, opts.surf.colorMode);
        setPopup(controls.gpReduce, opts.surf.gpReduce);
        setPopup(controls.interpColorBy, opts.interp.colorBy);

        controls.deformShow.Value = logical(opts.deform.show);
        controls.autoScale.Value = logical(opts.deform.autoScale);
        controls.showUndeformed.Value = logical(opts.deform.showUndeformed);
        controls.surfShow.Value = logical(opts.surf.show);
        controls.showEdges.Value = logical(opts.surf.showEdges);
        controls.lineShow.Value = logical(opts.line.show);
        controls.useColormap.Value = logical(opts.color.useColormap);
        controls.cbarShow.Value = logical(opts.cbar.show);
        controls.fixedShow.Value = logical(opts.fixed.show);
        controls.useInterpolation.Value = logical(opts.interp.useInterpolation);
        controls.grid.Value = logical(opts.general.grid);
        controls.box.Value = logical(opts.general.box);
        controls.axesOff.Value = localGetBool(opts.general, 'axesOff', false);

        setSlider(controls.deformScale, opts.deform.scale);
        setSlider(controls.deformedAlpha, opts.color.deformedAlpha);
        setSlider(controls.undeformedAlpha, opts.color.undeformedAlpha);
        setSlider(controls.edgeWidth, opts.surf.edgeWidth);
        setSlider(controls.lineWidth, opts.line.lineWidth);
        setSlider(controls.gpIndex, opts.surf.gpIndex);
        controls.title.String = char(string(opts.general.title));
    end

    function stepArg = readStepArg()
        mode = localSelected(controls.stepMode);
        if strcmpi(mode, 'step')
            value = str2double(controls.stepEdit.String);
            if ~isfinite(value), value = 0; end
            value = round(max(0, min(state.nStep - 1, value)));
            controls.stepEdit.String = sprintf('%d', value);
            controls.stepSlider.Value = min(controls.stepSlider.Max, value);
            stepArg = value;
        else
            stepArg = mode;
        end
    end

    function updateInfo(extra)
        if ~isfield(controls, 'info') || ~ishandle(controls.info)
            return;
        end
        lines = localResponseSummary(state);
        if strlength(string(extra)) > 0
            lines = [cellstr(string(extra)); lines(:)];
        end
        controls.info.String = lines;
    end

    function showHelp(~, ~)
        helpFig = figure('Name', 'PlotUnstruResponse Options Help | by Yexiang Yan', 'NumberTitle', 'off', ...
            'Color', 'w', 'Units', 'pixels', 'Position', [180 160 850 640]);
        uicontrol(helpFig, 'Style', 'edit', 'Units', 'normalized', ...
            'Position', [0.02 0.02 0.96 0.96], ...
            'String', state.opts.help, ...
            'Max', 2, 'Min', 0, ...
            'HorizontalAlignment', 'left', ...
            'FontName', 'Consolas');
    end

    function showColors(~, ~)
        colorItems = {
            'Solid',      {'color','solidColor'}
            'Undeformed', {'color','undeformedColor'}
            'Edge',       {'surf','edgeColor'}
            'Fixed node', {'fixed','color'}
            'Fixed edge', {'fixed','edgeColor'}
            };

        colorFig = figure('Name', 'PlotUnstruResponse Colors | by Yexiang Yan', 'NumberTitle', 'off', ...
            'Color', 'w', 'MenuBar', 'none', 'Toolbar', 'none', ...
            'Units', 'pixels', 'Position', [240 180 330 280]);

        nItem = size(colorItems, 1);
        rowH = 0.72 / nItem;
        for i = 1:nItem
            yy = 0.86 - i * rowH;
            label = colorItems{i,1};
            path = colorItems{i,2};
            value = localGetNested(state.opts, path);
            rgb = localColorToRgb(value);

            uicontrol(colorFig, 'Style', 'text', 'Units', 'normalized', ...
                'Position', [0.07 yy 0.50 rowH * 0.72], ...
                'String', label, 'HorizontalAlignment', 'left', ...
                'BackgroundColor', 'w');
            uicontrol(colorFig, 'Style', 'pushbutton', 'Units', 'normalized', ...
                'Position', [0.62 yy 0.30 rowH * 0.72], ...
                'String', localColorLabel(value), ...
                'BackgroundColor', rgb, ...
                'ForegroundColor', localTextColorForBg(rgb), ...
                'Callback', @(src,~) pickColor(src, path, label));
        end

        uicontrol(colorFig, 'Style', 'pushbutton', 'Units', 'normalized', ...
            'Position', [0.07 0.03 0.40 0.07], ...
            'String', 'Reset colors', 'Callback', @resetColors);
        uicontrol(colorFig, 'Style', 'pushbutton', 'Units', 'normalized', ...
            'Position', [0.53 0.03 0.38 0.07], ...
            'String', 'Close', 'Callback', @(~,~) close(colorFig));

        function pickColor(src, path, label)
            current = localColorToRgb(localGetNested(state.opts, path));
            picked = uisetcolor(current, ['Select ' label]);
            if isnumeric(picked) && numel(picked) == 3
                newColor = localRgbToHex(picked);
                state.opts = localSetNested(state.opts, path, newColor);
                src.BackgroundColor = picked;
                src.ForegroundColor = localTextColorForBg(picked);
                src.String = newColor;
                redraw();
            end
        end

        function resetColors(~, ~)
            defaults = plotter.PlotUnstruResponse.defaultOptions();
            for k = 1:nItem
                path = colorItems{k,2};
                state.opts = localSetNested(state.opts, path, localGetNested(defaults, path));
            end
            if ishandle(colorFig), close(colorFig); end
            showColors();
            redraw();
        end
    end

    function setPopup(h, value)
        items = localPopupItems(h);
        idx = find(strcmpi(items, char(string(value))), 1, 'first');
        if isempty(idx), idx = 1; end
        h.Value = idx;
    end

    function setSlider(h, value)
        h.Value = max(h.Min, min(h.Max, double(value)));
    end
end

function names = localViewNames()
names = {'auto','iso','xy','xz','yz','yx','zx','zy'};
end

function localEnablePanelScroll(panel)
children = allchild(panel);
children = children(arrayfun(@(h) isprop(h, 'Position'), children));
if isempty(children)
    return;
end

orig = cell(numel(children), 1);
pos = zeros(numel(children), 4);
for i = 1:numel(children)
    children(i).Units = 'normalized';
    orig{i} = children(i).Position;
    pos(i,:) = orig{i};
end

bottomPad = 0.025;
contentMin = min(pos(:,2));
maxOffset = max(0, bottomPad - contentMin);
if maxOffset <= 0
    return;
end

slider = uicontrol(panel, 'Style', 'slider', 'Units', 'normalized', ...
    'Position', [0.955 0.02 0.025 0.94], ...
    'Min', 0, 'Max', maxOffset, 'Value', maxOffset, ...
    'SliderStep', [min(1, 0.05 / maxOffset), min(1, 0.25 / maxOffset)], ...
    'Callback', @scrollPanel);
slider.UserData = struct('Targets', children, 'Positions', {orig});

fig = ancestor(panel, 'figure');
if ~isempty(fig) && isgraphics(fig, 'figure')
    fig.WindowScrollWheelFcn = @(~,evt) scrollWheel(slider, evt);
end

    function scrollPanel(src, ~)
        data = src.UserData;
        offset = src.Max - src.Value;
        for k = 1:numel(data.Targets)
            if isgraphics(data.Targets(k))
                p = data.Positions{k};
                p(2) = p(2) + offset;
                data.Targets(k).Position = p;
            end
        end
    end

    function scrollWheel(src, evt)
        step = maxOffset / 10;
        src.Value = max(src.Min, min(src.Max, src.Value - evt.VerticalScrollCount * step));
        scrollPanel(src, []);
    end
end

function value = localGetBool(s, name, defaultValue)
value = defaultValue;
if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
    value = logical(s.(name));
end
end

function names = localColormapNames()
names = {'jet','parula','turbo','hot','cool','spring','summer','autumn','winter','gray'};
end

function cmap = localBuildColormap(name)
name = lower(char(string(name)));
try
    cmap = feval(name, 256);
catch
    cmap = jet(256);
end
end

function name = localColormapName(cmap)
names = localColormapNames();
name = names{1};
if isempty(cmap) || ~isnumeric(cmap) || size(cmap,2) ~= 3
    return;
end
for i = 1:numel(names)
    ref = localBuildColormap(names{i});
    if isequal(size(cmap), size(ref)) && max(abs(double(cmap(:)) - ref(:))) < 1e-12
        name = names{i};
        return;
    end
end
end

function eleType = localInitialEleType(eleResp, requested)
txt = char(string(requested));
if strlength(string(txt)) > 0
    eleType = localNormalizeEleType(txt);
    return;
end
eleType = 'Plane';
if isstruct(eleResp) && isfield(eleResp(1), 'eleType') && ~isempty(eleResp(1).eleType)
    eleType = localNormalizeEleType(eleResp(1).eleType);
end
end

function eleType = localNormalizeEleType(value)
txt = lower(char(string(value)));
switch txt
    case 'shell'
        eleType = 'Shell';
    case {'solid','brick'}
        eleType = 'Solid';
    otherwise
        eleType = 'Plane';
end
end

function types = localResponseTypes(eleResp, eleType)
switch lower(char(string(eleType)))
    case 'shell'
        builtins = {'SecForceAtGP','SecDefoAtGP','SecForceAtNode','SecDefoAtNode', ...
            'StressAtGP','StrainAtGP','StressAtNode','StrainAtNode'};
    otherwise
        builtins = {'StressAtGP','StressAtNode','StrainAtGP','StrainAtNode', ...
            'StressMeasureAtGP','StressMeasureAtNode'};
end

custom = {};
meta = {'odbTag','eleType','time','eleTags','nodeTags'};
if isstruct(eleResp) && ~isempty(eleResp)
    fields = fieldnames(eleResp(1));
    for i = 1:numel(fields)
        name = fields{i};
        if any(strcmpi(name, meta))
            continue;
        end
        value = eleResp(1).(name);
        if isnumeric(value) || isstruct(value)
            custom{end+1} = name; %#ok<AGROW>
        end
    end
end

types = {};
for i = 1:numel(builtins)
    idx = find(strcmpi(custom, builtins{i}), 1, 'first');
    if ~isempty(idx)
        types{end+1} = custom{idx}; %#ok<AGROW>
    else
        types{end+1} = builtins{i}; %#ok<AGROW>
    end
end
for i = 1:numel(custom)
    if ~any(strcmpi(types, custom{i}))
        types{end+1} = custom{i}; %#ok<AGROW>
    end
end
end

function respType = localInitialRespType(types, eleType, requested)
if strlength(string(requested)) > 0
    respType = localPickExisting(types, requested);
    return;
end
switch lower(char(string(eleType)))
    case 'shell'
        respType = localPickExisting(types, 'SecForceAtGP');
    otherwise
        respType = localPickExisting(types, 'StressAtGP');
end
end

function comps = localComponents(eleResp, eleType, respType)
switch lower(char(string(eleType)))
    case 'shell'
        if contains(lower(char(string(respType))), 'sec')
            comps = {'mxx','myy','mxy','fxx','fyy','fxy','vxz','vyz'};
        elseif contains(lower(char(string(respType))), 'strain')
            comps = {'exx','eyy','exy','eyz','exz'};
        else
            comps = {'sxx','syy','sxy','syz','sxz'};
        end
    otherwise
        if contains(lower(char(string(respType))), 'measure')
            comps = {'vonMises','sigmaOct','tauOct','tauMax','p1','p2','p3'};
        elseif contains(lower(char(string(respType))), 'strain')
            comps = {'exx','eyy','ezz','exy','eyz','exz'};
        elseif strcmpi(eleType, 'Plane')
            comps = {'sxx','syy','sxy','szz'};
        else
            comps = {'sxx','syy','szz','sxy','syz','sxz'};
        end
end

custom = localCustomComponents(eleResp, respType);
if ~isempty(custom)
    comps = localMergeComponents(comps, custom);
end
end

function comps = localMergeComponents(base, add)
comps = cellstr(string(base(:).'));
add = cellstr(string(add(:).'));
for i = 1:numel(add)
    if ~any(strcmpi(comps, add{i}))
        comps{end+1} = add{i}; %#ok<AGROW>
    end
end
end

function comps = localCustomComponents(eleResp, respType)
comps = {};
if isempty(eleResp) || ~isstruct(eleResp)
    return;
end
fieldName = localFieldName(eleResp(1), char(string(respType)));
if isempty(fieldName)
    return;
end
entry = eleResp(1).(fieldName);
if isstruct(entry)
    if isfield(entry, 'dofs') && ~isempty(entry.dofs)
        comps = localNormalizeDofs(entry.dofs);
    elseif ~isfield(entry, 'data')
        names = fieldnames(entry);
        skip = {'dofs','eleTags','nodeTags','time'};
        for i = 1:numel(names)
            if any(strcmpi(names{i}, skip))
                continue;
            end
            if isnumeric(entry.(names{i}))
                comps{end+1} = names{i}; %#ok<AGROW>
            end
        end
    end
elseif isnumeric(entry)
    comps = {'value'};
end
end

function component = localInitialComponent(comps, eleType, respType, requested)
if isempty(comps)
    comps = {''};
end
if strlength(string(requested)) > 0
    component = localPickExisting(comps, requested);
    return;
end
switch lower(char(string(eleType)))
    case 'shell'
        if contains(lower(char(string(respType))), 'sec')
            component = localPickExisting(comps, 'mxx');
        else
            component = localPickExisting(comps, 'sxx');
        end
    otherwise
        component = localPickExisting(comps, 'sxx');
end
end

function name = localFieldName(s, wanted)
name = '';
if isfield(s, wanted)
    name = wanted;
    return;
end
fields = fieldnames(s);
idx = find(strcmpi(fields, wanted), 1, 'first');
if ~isempty(idx)
    name = fields{idx};
end
end

function dofs = localNormalizeDofs(dofs)
if isempty(dofs)
    dofs = {};
elseif iscell(dofs) && isscalar(dofs) && iscell(dofs{1})
    dofs = dofs{1};
elseif iscell(dofs)
    dofs = dofs(:).';
elseif isstring(dofs)
    dofs = cellstr(dofs(:).');
elseif ischar(dofs)
    dofs = {dofs};
else
    dofs = cellstr(string(dofs(:).'));
end
end

function value = localPickExisting(items, value)
idx = find(strcmpi(items, char(string(value))), 1, 'first');
if isempty(idx)
    value = items{1};
else
    value = items{idx};
end
end

function value = localLocationValue(value)
if strlength(string(value)) == 0
    value = 'auto';
else
    value = char(string(value));
end
end

function txt = localFiberText(value)
if isnumeric(value)
    txt = sprintf('%g', value);
else
    txt = char(string(value));
end
if isempty(txt)
    txt = 'top';
end
end

function mode = localStepMode(stepIdx)
if isnumeric(stepIdx)
    mode = 'step';
else
    txt = char(string(stepIdx));
    switch lower(txt)
        case {'absmax','absmin','max','min'}
            mode = txt;
        otherwise
            mode = 'step';
    end
end
end

function txt = localStepString(stepIdx)
if isnumeric(stepIdx)
    txt = sprintf('%d', round(double(stepIdx)));
else
    v = str2double(char(string(stepIdx)));
    if isfinite(v)
        txt = sprintf('%d', round(v));
    else
        txt = '0';
    end
end
end

function value = localStepValue(stepIdx)
value = str2double(localStepString(stepIdx));
if ~isfinite(value), value = 0; end
end

function step = localSliderStep(nStep)
if nStep <= 2
    step = [1 1];
else
    step = [1 / (nStep - 1), min(1, 10 / (nStep - 1))];
end
end

function value = localSelected(h)
items = localPopupItems(h);
value = items{max(1, min(numel(items), h.Value))};
end

function items = localPopupItems(h)
items = h.String;
if ischar(items)
    items = cellstr(items);
elseif isstring(items)
    items = cellstr(items);
end
end

function lines = localResponseSummary(state)
lines = strings(0,1);
lines(end+1,1) = sprintf('Element type: %s | Response: %s | Component: %s', ...
    state.eleType, state.respType, state.component);
lines(end+1,1) = sprintf('Steps: %d (0 to %d) | Segments: %d', ...
    state.nStep, max(0, state.nStep - 1), max([numel(state.modelInfo), numel(state.nodalResp), numel(state.eleResp)]));
loc = char(string(state.opts.responseLocation));
if isempty(loc), loc = 'auto'; end
lines(end+1,1) = sprintf('Location: %s | CLim: %s | GP: %s %d', ...
    loc, char(string(state.opts.color.climMode)), ...
    char(string(state.opts.surf.gpReduce)), round(double(state.opts.surf.gpIndex)));
[nRow, nExtra] = localResponseShape(state.eleResp, state.respType);
if nRow > 0
    if nExtra > 0
        lines(end+1,1) = sprintf('Response rows: %d, extra dimension: %d', nRow, nExtra);
    else
        lines(end+1,1) = sprintf('Response rows: %d', nRow);
    end
end
lines = cellstr(lines);
end

function [nRow, nExtra] = localResponseShape(eleResp, respType)
nRow = 0;
nExtra = 0;
if isempty(eleResp) || ~isstruct(eleResp)
    return;
end
fieldName = localFieldName(eleResp(1), char(string(respType)));
if isempty(fieldName)
    return;
end
entry = eleResp(1).(fieldName);
if isstruct(entry) && isfield(entry, 'data')
    A = entry.data;
elseif isstruct(entry)
    comps = localCustomComponents(eleResp, respType);
    if isempty(comps) || ~isfield(entry, comps{1})
        return;
    end
    A = entry.(comps{1});
else
    A = entry;
end
if isnumeric(A) && ndims(A) >= 2
    nRow = size(A, 2);
end
if isnumeric(A) && ~ismatrix(A)
    nExtra = size(A, 3);
end
end

function value = localGetNested(s, path)
value = s;
for i = 1:numel(path)
    name = path{i};
    if ~isstruct(value) || ~isfield(value, name)
        value = [];
        return;
    end
    value = value.(name);
end
end

function s = localSetNested(s, path, value)
name = path{1};
if isscalar(path)
    s.(name) = value;
    return;
end
if ~isfield(s, name) || ~isstruct(s.(name))
    s.(name) = struct();
end
s.(name) = localSetNested(s.(name), path(2:end), value);
end

function rgb = localColorToRgb(value)
if isnumeric(value) && numel(value) >= 3
    rgb = double(value(1:3));
    if any(rgb > 1), rgb = rgb / 255; end
    rgb = max(0, min(1, rgb(:).'));
    return;
end

txt = lower(strtrim(char(string(value))));
named = struct('black',[0 0 0],'white',[1 1 1],'red',[1 0 0], ...
    'green',[0 1 0],'blue',[0 0 1],'cyan',[0 1 1], ...
    'magenta',[1 0 1],'yellow',[1 1 0]);
if isfield(named, txt)
    rgb = named.(txt);
    return;
end

shortNames = {'k','w','r','g','b','c','m','y'};
longNames = {'black','white','red','green','blue','cyan','magenta','yellow'};
idx = find(strcmp(txt, shortNames), 1, 'first');
if ~isempty(idx)
    rgb = named.(longNames{idx});
    return;
end

if startsWith(txt, '#') && strlength(string(txt)) == 7
    vals = sscanf(txt(2:end), '%2x%2x%2x');
    if numel(vals) == 3
        rgb = double(vals(:).') / 255;
        return;
    end
end
rgb = [0 0 0];
end

function txt = localRgbToHex(rgb)
rgb = max(0, min(1, double(rgb(1:3))));
vals = round(rgb * 255);
txt = sprintf('#%02X%02X%02X', vals(1), vals(2), vals(3));
end

function txt = localColorLabel(value)
if isnumeric(value) && numel(value) >= 3
    txt = localRgbToHex(localColorToRgb(value));
else
    txt = char(string(value));
end
end

function color = localTextColorForBg(rgb)
rgb = localColorToRgb(rgb);
luma = 0.2126 * rgb(1) + 0.7152 * rgb(2) + 0.0722 * rgb(3);
if luma < 0.45
    color = [1 1 1];
else
    color = [0 0 0];
end
end

function out = localMerge(base, add)
out = base;
if isempty(add) || ~isstruct(add), return; end
f = fieldnames(add);
for i = 1:numel(f)
    name = f{i};
    if isfield(out, name) && isstruct(out.(name)) && isstruct(add.(name))
        out.(name) = localMerge(out.(name), add.(name));
    else
        out.(name) = add.(name);
    end
end
end
