function app = PlotFrameRespGUI(modelInfo, frameResp, options)
% PlotFrameRespGUI Interactive GUI wrapper for plotter.PlotFrameResp.
%
% Syntax
% ------
%   app = plotter.PlotFrameRespGUI(modelInfo, frameResp)
%   app = plotter.PlotFrameRespGUI(modelInfo, frameResp, opts=opts)
%   app = plotter.PlotFrameRespGUI(modelInfo, frameResp, stepIdx="absMax")

arguments
    modelInfo struct
    frameResp struct
    options.opts (1,1) struct = struct()
    options.stepIdx = "absMax"
end

opts0 = localMerge(plotter.PlotFrameResp.defaultOptions(), options.opts);
opts0.general.clearAxes = true;
opts0.general.holdOn = true;
opts0.general.figureSize = [];

respTypes = localResponseTypes(frameResp);
if isempty(respTypes)
    respTypes = {'sectionForces'};
end
opts0.respType = localPickExisting(respTypes, opts0.respType);
components = localComponents(frameResp, opts0.respType);
if isempty(components)
    components = {char(string(opts0.component))};
end
opts0.component = localPickExisting(components, opts0.component);

probeFig = figure('Visible', 'off');
probeAx = axes('Parent', probeFig);
probe = plotter.PlotFrameResp(modelInfo, frameResp, probeAx, opts0);
nStep = max(1, probe.nSteps());
delete(probeFig);

fig = figure( ...
    'Name', 'OpenSeesMatlab Frame Response Plotter | by Yexiang Yan', ...
    'NumberTitle', 'off', ...
    'Color', 'w', ...
    'MenuBar', 'none', ...
    'Toolbar', 'figure', ...
    'Units', 'pixels', ...
    'Position', [150 120 1260 760]);

ax = axes('Parent', fig, 'Units', 'normalized', 'Position', [0.29 0.16 0.69 0.78]);
panel = uipanel( ...
    'Parent', fig, ...
    'Title', 'PlotFrameResp GUI', ...
    'Units', 'normalized', ...
    'Position', [0.015 0.035 0.26 0.93], ...
    'BackgroundColor', 'w');
infoPanel = uipanel( ...
    'Parent', fig, ...
    'Title', 'Frame response information', ...
    'Units', 'normalized', ...
    'Position', [0.29 0.035 0.69 0.11], ...
    'BackgroundColor', 'w');

state.opts = opts0;
state.modelInfo = modelInfo;
state.frameResp = frameResp;
state.respTypes = respTypes;
state.components = components;
state.nStep = nStep;
state.pfr = [];
state.isRedrawing = false;

controls = struct();
y = 0.955;
dy = 0.035;

addLabel('Response', y);
controls.respType = addPopup(state.respTypes, state.opts.respType, y, @responseChanged);
y = y - dy;

addLabel('Component', y);
controls.component = addPopup(state.components, state.opts.component, y, @redraw);
y = y - dy;

addLabel('Location', y);
controls.responseLocation = addPopup({'auto','section','element'}, localLocationValue(state.opts.responseLocation), y, @redraw);
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

addLabel('Style', y);
controls.style = addPopup({'surface','wireframe'}, state.opts.style, y, @redraw);
y = y - dy;

addLabel('Scale mode', y);
controls.scaleMode = addPopup({'current','global'}, state.opts.scaleMode, y, @redraw);
y = y - dy;

addLabel('Color limit', y);
controls.climMode = addPopup({'current','global'}, state.opts.color.climMode, y, @redraw);
y = y - dy;

addLabel('Color map', y);
controls.colormapName = addPopup(localColormapNames(), localColormapName(state.opts.color.colormap), y, @redraw);
y = y - dy;

addLabel('Labels', y);
controls.showMaxMinLabel = addPopup({'global','element','all','none'}, state.opts.showMaxMinLabel, y, @redraw);
y = y - dy;

addSeparator(y); y = y - dy * 0.55;
addText('Visibility', y); y = y - dy * 0.9;
[controls.showModel, controls.showBeamModel] = addCheckPair('Model', state.opts.showModel, ...
    'Beam lines', state.opts.showBeamModel, y); y = y - dy;
[controls.showZeroLine, controls.surfShow] = addCheckPair('Zero line', state.opts.showZeroLine, ...
    'Mesh edges', state.opts.surf.show, y); y = y - dy;
[controls.useColormap, controls.cbarShow] = addCheckPair('Colormap', state.opts.color.useColormap, ...
    'Colorbar', state.opts.cbar.show, y); y = y - dy;
[controls.grid, controls.box] = addCheckPair('Grid', state.opts.general.grid, ...
    'Box', state.opts.general.box, y); y = y - dy;
[controls.axisEqual, controls.fastMode] = addCheckPair('Equal axis', state.opts.general.axisEqual, ...
    'Fast mode', state.opts.performance.fastMode, y); y = y - dy;
controls.axesOff = addCheck('Axes off', localGetBool(state.opts.general, 'axesOff', false), y); y = y - dy;

addSeparator(y); y = y - dy * 0.55;
addText('Diagram scale', y); y = y - dy * 0.8;
controls.scale = addSlider(0.01, 20, state.opts.scale, y); y = y - dy;
addText('Height fraction', y); y = y - dy * 0.8;
controls.heightFrac = addSlider(0.005, 0.5, state.opts.heightFrac, y); y = y - dy;
addText('Face alpha', y); y = y - dy * 0.8;
controls.faceAlpha = addSlider(0, 1, state.opts.color.faceAlpha, y); y = y - dy;
addText('Wire width', y); y = y - dy * 0.8;
controls.wireWidth = addSlider(0.2, 8, state.opts.color.wireWidth, y); y = y - dy;
addText('Model width', y); y = y - dy * 0.8;
controls.modelWidth = addSlider(0.2, 8, state.opts.color.modelWidth, y); y = y - dy;
addText('Label size', y); y = y - dy * 0.8;
controls.labelFontSize = addSlider(6, 18, state.opts.labelFontSize, y); y = y - dy;

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
    'String', localResponseSummary(state.frameResp, state.opts, state.nStep), ...
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
        stepArg = readStepArg();
        try
            state.pfr = plotter.PlotFrameResp(state.modelInfo, state.frameResp, ax, state.opts);
            state.pfr.plotStep(stepArg);
            app.PlotFrameResp = state.pfr;
            app.Options = state.opts;
            app.FrameResp = state.frameResp;
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

    function responseChanged(~, ~)
        items = localPopupItems(controls.respType);
        state.opts.respType = items{controls.respType.Value};
        state.components = localComponents(state.frameResp, state.opts.respType);
        if isempty(state.components)
            state.components = {char(string(state.opts.component))};
        end
        state.opts.component = localPickComponent(state.components, ...
            state.opts.respType, state.opts.component);
        controls.component.String = state.components;
        setPopup(controls.component, state.opts.component);
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
        respItems = localPopupItems(controls.respType);
        compItems = localPopupItems(controls.component);
        locItems = localPopupItems(controls.responseLocation);
        viewItems = localPopupItems(controls.view);
        styleItems = localPopupItems(controls.style);
        scaleModeItems = localPopupItems(controls.scaleMode);
        climModeItems = localPopupItems(controls.climMode);
        labelItems = localPopupItems(controls.showMaxMinLabel);

        opts.respType = respItems{controls.respType.Value};
        opts.component = compItems{controls.component.Value};
        opts.responseLocation = locItems{controls.responseLocation.Value};
        if strcmpi(opts.responseLocation, 'auto')
            opts.responseLocation = '';
        end
        opts.general.view = viewItems{controls.view.Value};
        opts.style = styleItems{controls.style.Value};
        opts.scaleMode = scaleModeItems{controls.scaleMode.Value};
        opts.color.climMode = climModeItems{controls.climMode.Value};
        cmapNames = localPopupItems(controls.colormapName);
        opts.color.colormap = localBuildColormap(cmapNames{controls.colormapName.Value});
        opts.showMaxMinLabel = labelItems{controls.showMaxMinLabel.Value};

        opts.showModel = logical(controls.showModel.Value);
        opts.showBeamModel = logical(controls.showBeamModel.Value);
        opts.showZeroLine = logical(controls.showZeroLine.Value);
        opts.surf.show = logical(controls.surfShow.Value);
        opts.color.useColormap = logical(controls.useColormap.Value);
        opts.cbar.show = logical(controls.cbarShow.Value);
        opts.general.grid = logical(controls.grid.Value);
        opts.general.box = logical(controls.box.Value);
        opts.general.axisEqual = logical(controls.axisEqual.Value);
        opts.general.axesOff = logical(controls.axesOff.Value);
        opts.performance.fastMode = logical(controls.fastMode.Value);

        opts.scale = controls.scale.Value;
        opts.heightFrac = controls.heightFrac.Value;
        opts.color.faceAlpha = controls.faceAlpha.Value;
        opts.color.wireWidth = controls.wireWidth.Value;
        opts.color.modelWidth = controls.modelWidth.Value;
        opts.labelFontSize = round(controls.labelFontSize.Value);
        opts.general.title = controls.title.String;
    end

    function applyControls(opts)
        setPopup(controls.respType, opts.respType);
        state.components = localComponents(state.frameResp, opts.respType);
        if isempty(state.components), state.components = {char(string(opts.component))}; end
        controls.component.String = state.components;
        setPopup(controls.component, opts.component);
        setPopup(controls.responseLocation, localLocationValue(opts.responseLocation));
        setPopup(controls.view, opts.general.view);
        setPopup(controls.style, opts.style);
        setPopup(controls.scaleMode, opts.scaleMode);
        setPopup(controls.climMode, opts.color.climMode);
        setPopup(controls.colormapName, localColormapName(opts.color.colormap));
        setPopup(controls.showMaxMinLabel, opts.showMaxMinLabel);

        controls.showModel.Value = logical(opts.showModel);
        controls.showBeamModel.Value = logical(opts.showBeamModel);
        controls.showZeroLine.Value = logical(opts.showZeroLine);
        controls.surfShow.Value = logical(opts.surf.show);
        controls.useColormap.Value = logical(opts.color.useColormap);
        controls.cbarShow.Value = logical(opts.cbar.show);
        controls.grid.Value = logical(opts.general.grid);
        controls.box.Value = logical(opts.general.box);
        controls.axisEqual.Value = logical(opts.general.axisEqual);
        controls.axesOff.Value = localGetBool(opts.general, 'axesOff', false);
        controls.fastMode.Value = logical(opts.performance.fastMode);

        setSlider(controls.scale, opts.scale);
        setSlider(controls.heightFrac, opts.heightFrac);
        setSlider(controls.faceAlpha, opts.color.faceAlpha);
        setSlider(controls.wireWidth, opts.color.wireWidth);
        setSlider(controls.modelWidth, opts.color.modelWidth);
        setSlider(controls.labelFontSize, opts.labelFontSize);
        controls.title.String = char(string(opts.general.title));
    end

    function stepArg = readStepArg()
        items = localPopupItems(controls.stepMode);
        mode = items{controls.stepMode.Value};
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
        lines = localResponseSummary(state.frameResp, state.opts, state.nStep);
        if strlength(string(extra)) > 0
            lines = [cellstr(string(extra)); lines(:)];
        end
        controls.info.String = lines;
    end

    function showHelp(~, ~)
        helpFig = figure('Name', 'PlotFrameResp Options Help | by Yexiang Yan', 'NumberTitle', 'off', ...
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
            'Solid',     {'color','solidColor'}
            'Wire',      {'color','wireColor'}
            'Zero line', {'color','zeroLineColor'}
            'Model',     {'color','modelColor'}
            'Mesh edge', {'surf','lineColor'}
            };

        colorFig = figure('Name', 'PlotFrameResp Colors | by Yexiang Yan', 'NumberTitle', 'off', ...
            'Color', 'w', 'MenuBar', 'none', 'Toolbar', 'none', ...
            'Units', 'pixels', 'Position', [240 180 320 280]);

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
            defaults = plotter.PlotFrameResp.defaultOptions();
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

function types = localResponseTypes(frameResp)
meta = {'odbTag','eleType','time','eleTags','sectionLocs'};
types = {};
if isempty(frameResp) || ~isstruct(frameResp)
    return;
end
fields = fieldnames(frameResp(1));
for i = 1:numel(fields)
    name = fields{i};
    if any(strcmpi(name, meta))
        continue;
    end
    value = frameResp(1).(name);
    if isnumeric(value) || isstruct(value)
        types{end+1} = name; %#ok<AGROW>
    end
end
preferred = {'sectionForces','sectionDeformations','basicForces', ...
    'basicDeformations','localForces','plasticDeformation'};
ordered = {};
for i = 1:numel(preferred)
    idx = find(strcmpi(types, preferred{i}), 1, 'first');
    if ~isempty(idx)
        ordered{end+1} = types{idx}; %#ok<AGROW>
    end
end
for i = 1:numel(types)
    if ~any(strcmpi(ordered, types{i}))
        ordered{end+1} = types{i}; %#ok<AGROW>
    end
end
types = ordered;
end

function comps = localComponents(frameResp, respType)
rt = char(string(respType));
builtIn = true;
switch lower(rt)
    case {'sectionforces','sectiondeformations'}
        comps = {'N','MZ','VY','MY','VZ','T'};
    case {'basicforces','basicdeformations','plasticdeformation'}
        comps = {'N','MZ','MY','T'};
    case 'localforces'
        comps = {'FX','FY','FZ','MX','MY','MZ'};
    otherwise
        comps = {};
        builtIn = false;
end

if isempty(frameResp) || ~isstruct(frameResp)
    return;
end
fr = frameResp(1);
fieldName = localFieldName(fr, rt);
if isempty(fieldName)
    return;
end
entry = fr.(fieldName);
custom = localComponentsFromEntry(entry);
if ~isempty(custom)
    if strcmpi(rt, 'localForces')
        comps = localUniqueComponents(comps);
    elseif builtIn
        custom = localCollapseEndComponents(custom);
        comps = localMergeComponents(comps, custom);
    else
        comps = localUniqueComponents(custom);
    end
end
end

function comps = localComponentsFromEntry(entry)
comps = {};
if isstruct(entry)
    if isfield(entry, 'dofs') && ~isempty(entry.dofs)
        comps = localExpandEndPairComponents(localNormalizeDofs(entry.dofs));
        return;
    end
    names = fieldnames(entry);
    skip = {'data','dofs','eleTags','nodeTags','sectionLocs','time'};
    keep = {};
    for i = 1:numel(names)
        if any(strcmpi(names{i}, skip))
            continue;
        end
        if isnumeric(entry.(names{i}))
            keep{end+1} = names{i}; %#ok<AGROW>
        end
    end
    comps = localExpandEndPairComponents(keep);
elseif isnumeric(entry)
    comps = {'value'};
end
end

function comps = localExpandEndPairComponents(comps)
if isempty(comps)
    return;
end
comps = cellstr(string(comps(:).'));
extras = {};
upperComps = upper(comps);
for i = 1:numel(comps)
    name = upperComps{i};
    if endsWith(name, {'I','J'})
        base = name(1:end-1);
        other = {[base 'I'], [base 'J']};
        if all(ismember(other, upperComps)) && ~any(strcmpi(extras, base))
            extras{end+1} = base; %#ok<AGROW>
        end
    elseif endsWith(name, {'1','2'})
        base = name(1:end-1);
        other = {[base '1'], [base '2']};
        if all(ismember(other, upperComps)) && ~any(strcmpi(extras, base))
            extras{end+1} = base; %#ok<AGROW>
        end
    end
end
comps = [extras, comps];
end

function comps = localCollapseEndComponents(comps)
if isempty(comps)
    return;
end
raw = cellstr(string(comps(:).'));
upperRaw = upper(raw);
physical = {'N','MZ','VY','MY','VZ','T','FX','FY','FZ','MX'};
out = {};
for i = 1:numel(raw)
    name = upperRaw{i};
    if numel(name) > 1 && ismember(name(end), {'I','J','1','2'})
        base = name(1:end-1);
        if ismember(base, physical)
            if ~any(strcmpi(out, base))
                out{end+1} = base; %#ok<AGROW>
            end
            continue;
        end
    end
    if ~any(strcmpi(out, raw{i}))
        out{end+1} = raw{i}; %#ok<AGROW>
    end
end
comps = out;
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

function comps = localUniqueComponents(comps)
raw = cellstr(string(comps(:).'));
comps = {};
for i = 1:numel(raw)
    if ~any(strcmpi(comps, raw{i}))
        comps{end+1} = raw{i}; %#ok<AGROW>
    end
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

function value = localPickComponent(items, respType, currentValue)
idx = find(strcmpi(items, char(string(currentValue))), 1, 'first');
if ~isempty(idx)
    value = items{idx};
    return;
end

switch lower(char(string(respType)))
    case {'sectionforces','sectiondeformations','basicforces','basicdeformations','plasticdeformation'}
        preferred = {'MZ','MY','N','T'};
    case 'localforces'
        preferred = {'MZ','MY','FX','FY','FZ','MX'};
    otherwise
        preferred = {};
end

for i = 1:numel(preferred)
    idx = find(strcmpi(items, preferred{i}), 1, 'first');
    if ~isempty(idx)
        value = items{idx};
        return;
    end
end
value = items{1};
end

function value = localLocationValue(value)
if strlength(string(value)) == 0
    value = 'auto';
else
    value = char(string(value));
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

function items = localPopupItems(h)
items = h.String;
if ischar(items)
    items = cellstr(items);
elseif isstring(items)
    items = cellstr(items);
end
end

function lines = localResponseSummary(frameResp, opts, nStep)
lines = strings(0,1);
lines(end+1,1) = sprintf('Segments: %d', max(1, numel(frameResp)));
lines(end+1,1) = sprintf('Steps: %d (0 to %d)', nStep, max(0, nStep - 1));
lines(end+1,1) = sprintf('Response: %s | Component: %s', ...
    char(string(opts.respType)), char(string(opts.component)));
loc = char(string(opts.responseLocation));
if isempty(loc), loc = 'auto'; end
lines(end+1,1) = sprintf('Location: %s | Scale: %s | CLim: %s', ...
    loc, char(string(opts.scaleMode)), char(string(opts.color.climMode)));
[nEle, nSec] = localResponseShape(frameResp, opts.respType);
if nEle > 0
    if nSec > 0
        lines(end+1,1) = sprintf('Response rows: %d elements, %d samples/sections', nEle, nSec);
    else
        lines(end+1,1) = sprintf('Response rows: %d elements', nEle);
    end
end
lines = cellstr(lines);
end

function [nEle, nSec] = localResponseShape(frameResp, respType)
nEle = 0;
nSec = 0;
if isempty(frameResp) || ~isstruct(frameResp)
    return;
end
fr = frameResp(1);
fieldName = localFieldName(fr, char(string(respType)));
if isempty(fieldName)
    return;
end
entry = fr.(fieldName);
if isstruct(entry) && isfield(entry, 'data')
    A = entry.data;
elseif isstruct(entry)
    comps = localComponentsFromEntry(entry);
    if isempty(comps) || ~isfield(entry, comps{1})
        return;
    end
    A = entry.(comps{1});
else
    A = entry;
end
if isnumeric(A) && ndims(A) >= 2
    nEle = size(A, 2);
end
if isnumeric(A) && ~ismatrix(A)
    nSec = size(A, 3);
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
