function app = PlotEigenGUI(modelInfo, eigenInfo, options)
% PlotEigenGUI Interactive GUI wrapper for plotter.PlotEigen.
%
% Syntax
% ------
%   app = plotter.PlotEigenGUI(modelInfo, eigenInfo)
%   app = plotter.PlotEigenGUI(modelInfo, eigenInfo, opts=opts)

arguments
    modelInfo (1,1) struct
    eigenInfo (1,1) struct
    options.opts (1,1) struct = struct()
end

opts0 = localMerge(plotter.PlotEigen.defaultOptions(), options.opts);
opts0.general.clearAxes = true;
opts0.general.holdOn = true;
opts0.general.figureSize = [];
if ~isfield(opts0.general, 'axesOff')
    opts0.general.axesOff = false;
end

modeTags = localModeTags(eigenInfo);
if isempty(modeTags)
    modeTags = 1;
end
if ~ismember(double(opts0.mode.modeTag), double(modeTags))
    opts0.mode.modeTag = modeTags(1);
end

fig = figure( ...
    'Name', 'OpenSeesMatlab Eigen Plotter | by Yexiang Yan', ...
    'NumberTitle', 'off', ...
    'Color', 'w', ...
    'MenuBar', 'none', ...
    'Toolbar', 'figure', ...
    'Units', 'pixels', ...
    'Position', [140 120 1240 760]);

ax = axes('Parent', fig, 'Units', 'normalized', 'Position', [0.28 0.16 0.70 0.78]);
panel = uipanel( ...
    'Parent', fig, ...
    'Title', 'PlotEigen GUI', ...
    'Units', 'normalized', ...
    'Position', [0.015 0.035 0.25 0.93], ...
    'BackgroundColor', 'w');
infoPanel = uipanel( ...
    'Parent', fig, ...
    'Title', 'Mode information', ...
    'Units', 'normalized', ...
    'Position', [0.28 0.035 0.70 0.11], ...
    'BackgroundColor', 'w');

state.opts = opts0;
state.modelInfo = modelInfo;
state.eigenInfo = eigenInfo;
state.modeTags = modeTags(:);
state.pe = [];
state.isRedrawing = false;

controls = struct();
y = 0.955;
dy = 0.036;

addLabel('Mode', y);
controls.modeTag = addPopup(localModeLabels(state.modeTags, state.eigenInfo), state.opts.mode.modeTag, y);
y = y - dy;

addLabel('View', y);
controls.view = addPopup(localViewNames(), state.opts.general.view, y);
y = y - dy;

addLabel('Component', y);
controls.component = addPopup({'magnitude','ux','uy','uz'}, state.opts.mode.component, y);
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

[controls.autoScale, controls.useInterpolation] = addCheckPair('Auto scale', state.opts.mode.autoScale, ...
    'Interpolation', state.opts.mode.useInterpolation, y); y = y - dy;
[controls.showUndeformed, controls.useColormap] = addCheckPair('Undeformed', state.opts.mode.showUndeformed, ...
    'Colormap', state.opts.color.useColormap, y); y = y - dy;
[controls.showColorbar, controls.axesOff] = addCheckPair('Colorbar', state.opts.scalar.showColorbar, ...
    'Axes off', state.opts.general.axesOff, y); y = y - dy;

addLabel('Color map', y);
controls.colormapName = addPopup(localColormapNames(), localColormapName(state.opts.color.colormap), y);
y = y - dy;

addSeparator(y); y = y - dy * 0.55;
addText('Geometry', y); y = y - dy * 0.9;
[controls.lineShow, controls.unstructuredShow] = addCheckPair('Lines', state.opts.line.show, ...
    'Surfaces', state.opts.unstructured.show, y); y = y - dy;
[controls.showEdges, controls.nodesShow] = addCheckPair('Surface edges', state.opts.unstructured.showEdges, ...
    'Nodes', state.opts.nodes.show, y); y = y - dy;
[controls.fixedShow, controls.mpShow] = addCheckPair('Fixed nodes', state.opts.fixed.show, ...
    'MP constraints', state.opts.mpConstraint.show, y); y = y - dy;
[controls.grid, controls.box] = addCheckPair('Grid', state.opts.general.grid, ...
    'Box', state.opts.general.box, y); y = y - dy;

addSeparator(y); y = y - dy * 0.55;
addText('Mode scale', y); y = y - dy * 0.8;
controls.scale = addSlider(0.01, 20, state.opts.mode.scale, y); y = y - dy;
addText('Line width', y); y = y - dy * 0.8;
controls.lineWidth = addSlider(0.2, 8, state.opts.line.lineWidth, y); y = y - dy;
addText('Surface alpha', y); y = y - dy * 0.8;
controls.deformedAlpha = addSlider(0, 1, state.opts.color.deformedAlpha, y); y = y - dy;
addText('Ghost alpha', y); y = y - dy * 0.8;
controls.undeformedAlpha = addSlider(0, 1, state.opts.color.undeformedAlpha, y); y = y - dy;

addText('Title', y); y = y - dy * 0.8;
controls.title = uicontrol(panel, ...
    'Style', 'edit', ...
    'Units', 'normalized', ...
    'Position', [0.06 y 0.88 0.030], ...
    'String', char(string(state.opts.general.title)), ...
    'HorizontalAlignment', 'left', ...
    'Callback', @redraw);

controls.modeInfo = uicontrol(infoPanel, 'Style', 'edit', 'Units', 'normalized', ...
    'Position', [0.015 0.08 0.97 0.78], ...
    'String', localModeSummary(state.eigenInfo, state.opts.mode.modeTag), ...
    'Max', 2, ...
    'Min', 0, ...
    'Enable', 'inactive', ...
    'HorizontalAlignment', 'left', ...
    'BackgroundColor', 'w', ...
    'FontName', 'Consolas');

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

    function h = addPopup(items, value, yy)
        if isstring(items), items = cellstr(items); end
        idx = find(strcmpi(items, char(string(value))), 1, 'first');
        if isempty(idx) && isnumeric(value)
            raw = regexp(items, '^[-+]?\d+(\.\d+)?', 'match', 'once');
            idx = find(abs(str2double(raw) - double(value)) < 1e-12, 1, 'first');
        end
        if isempty(idx), idx = 1; end
        h = uicontrol(panel, 'Style', 'popupmenu', 'Units', 'normalized', ...
            'Position', [0.42 yy 0.52 0.030], ...
            'String', items, 'Value', idx, 'Callback', @redraw);
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
        state.pe = plotter.PlotEigen(state.modelInfo, state.eigenInfo, ax, state.opts);
        state.pe.plotMode(state.opts.mode.modeTag);
        applyAxesVisibility();
        updateModeInfo();
        app.PlotEigen = state.pe;
        app.Options = state.opts;
        app.EigenInfo = state.eigenInfo;
        fig.UserData = app;
    end

    function setRedrawFlag(value)
        state.isRedrawing = value;
    end

    function resetOptions(~, ~)
        state.opts = opts0;
        applyControls(state.opts);
        redraw();
    end

    function opts = readControls(opts)
        views = controls.view.String;
        comps = controls.component.String;

        idx = max(1, min(numel(state.modeTags), controls.modeTag.Value));
        opts.mode.modeTag = state.modeTags(idx);
        opts.general.view = views{controls.view.Value};
        opts.mode.component = comps{controls.component.Value};

        opts.mode.autoScale = logical(controls.autoScale.Value);
        opts.mode.useInterpolation = logical(controls.useInterpolation.Value);
        opts.mode.showUndeformed = logical(controls.showUndeformed.Value);
        opts.color.useColormap = logical(controls.useColormap.Value);
        opts.scalar.showColorbar = logical(controls.showColorbar.Value);
        opts.general.axesOff = logical(controls.axesOff.Value);
        cmapNames = controls.colormapName.String;
        opts.color.colormap = localBuildColormap(cmapNames{controls.colormapName.Value});

        opts.line.show = logical(controls.lineShow.Value);
        opts.unstructured.show = logical(controls.unstructuredShow.Value);
        opts.unstructured.showEdges = logical(controls.showEdges.Value);
        opts.nodes.show = logical(controls.nodesShow.Value);
        opts.fixed.show = logical(controls.fixedShow.Value);
        opts.mpConstraint.show = logical(controls.mpShow.Value);
        opts.general.grid = logical(controls.grid.Value);
        opts.general.box = logical(controls.box.Value);

        opts.mode.scale = controls.scale.Value;
        opts.line.lineWidth = controls.lineWidth.Value;
        opts.color.deformedAlpha = controls.deformedAlpha.Value;
        opts.color.undeformedAlpha = controls.undeformedAlpha.Value;
        opts.general.title = controls.title.String;
    end

    function applyControls(opts)
        setPopup(controls.modeTag, opts.mode.modeTag);
        setPopup(controls.view, opts.general.view);
        setPopup(controls.component, opts.mode.component);

        controls.autoScale.Value = logical(opts.mode.autoScale);
        controls.useInterpolation.Value = logical(opts.mode.useInterpolation);
        controls.showUndeformed.Value = logical(opts.mode.showUndeformed);
        controls.useColormap.Value = logical(opts.color.useColormap);
        controls.showColorbar.Value = logical(opts.scalar.showColorbar);
        controls.axesOff.Value = logical(opts.general.axesOff);
        setPopup(controls.colormapName, localColormapName(opts.color.colormap));

        controls.lineShow.Value = logical(opts.line.show);
        controls.unstructuredShow.Value = logical(opts.unstructured.show);
        controls.showEdges.Value = logical(opts.unstructured.showEdges);
        controls.nodesShow.Value = logical(opts.nodes.show);
        controls.fixedShow.Value = logical(opts.fixed.show);
        controls.mpShow.Value = logical(opts.mpConstraint.show);
        controls.grid.Value = logical(opts.general.grid);
        controls.box.Value = logical(opts.general.box);

        controls.scale.Value = max(controls.scale.Min, min(controls.scale.Max, opts.mode.scale));
        controls.lineWidth.Value = max(controls.lineWidth.Min, min(controls.lineWidth.Max, opts.line.lineWidth));
        controls.deformedAlpha.Value = max(controls.deformedAlpha.Min, min(controls.deformedAlpha.Max, opts.color.deformedAlpha));
        controls.undeformedAlpha.Value = max(controls.undeformedAlpha.Min, min(controls.undeformedAlpha.Max, opts.color.undeformedAlpha));
        controls.title.String = char(string(opts.general.title));
    end

    function setPopup(h, value)
        items = h.String;
        idx = find(strcmpi(items, char(string(value))), 1, 'first');
        if isempty(idx) && isnumeric(value)
            raw = regexp(items, '^[-+]?\d+(\.\d+)?', 'match', 'once');
            idx = find(abs(str2double(raw) - double(value)) < 1e-12, 1, 'first');
        end
        if isempty(idx), idx = 1; end
        h.Value = idx;
    end

    function applyAxesVisibility()
        if isfield(state.opts.general, 'axesOff') && state.opts.general.axesOff
            axis(ax, 'off');
        else
            axis(ax, 'on');
            if state.opts.general.grid, grid(ax, 'on'); else, grid(ax, 'off'); end
            if state.opts.general.box, box(ax, 'on'); else, box(ax, 'off'); end
        end
    end

    function updateModeInfo()
        if isfield(controls, 'modeInfo') && ishandle(controls.modeInfo)
            controls.modeInfo.String = localModeSummary(state.eigenInfo, state.opts.mode.modeTag);
        end
    end

    function showHelp(~, ~)
        helpFig = figure('Name', 'PlotEigen Options Help | by Yexiang Yan', 'NumberTitle', 'off', ...
            'Color', 'w', 'Units', 'pixels', 'Position', [180 160 820 620]);
        uicontrol(helpFig, 'Style', 'edit', 'Units', 'normalized', ...
            'Position', [0.02 0.02 0.96 0.96], ...
            'String', state.opts.help, ...
            'Max', 2, 'Min', 0, ...
            'HorizontalAlignment', 'left', ...
            'FontName', 'Consolas');
    end

    function showColors(~, ~)
        colorItems = {
            'Line',       {'color','lineColor'}
            'Surface',    {'color','solidColor'}
            'Undeformed', {'color','undeformedColor'}
            'Edge',       {'unstructured','edgeColor'}
            'Fixed node', {'fixed','color'}
            'Fixed edge', {'fixed','edgeColor'}
            'MP constraint', {'mpConstraint','color'}
            };

        colorFig = figure('Name', 'PlotEigen Colors | by Yexiang Yan', 'NumberTitle', 'off', ...
            'Color', 'w', 'MenuBar', 'none', 'Toolbar', 'none', ...
            'Units', 'pixels', 'Position', [240 180 320 330]);

        nItem = size(colorItems, 1);
        rowH = 0.78 / nItem;
        for i = 1:nItem
            yy = 0.90 - i * rowH;
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
            defaults = plotter.PlotEigen.defaultOptions();
            for k = 1:nItem
                path = colorItems{k,2};
                state.opts = localSetNested(state.opts, path, localGetNested(defaults, path));
            end
            if ishandle(colorFig), close(colorFig); end
            showColors();
            redraw();
        end
    end
end

function tags = localModeTags(eigenInfo)
tags = [];
if isfield(eigenInfo, 'ModeTags') && ~isempty(eigenInfo.ModeTags)
    tags = double(eigenInfo.ModeTags(:));
elseif isfield(eigenInfo, 'EigenVectors') && isfield(eigenInfo.EigenVectors, 'data') && ~isempty(eigenInfo.EigenVectors.data)
    tags = (1:size(eigenInfo.EigenVectors.data, 1)).';
end
end

function labels = localModeLabels(tags, eigenInfo)
labels = strings(numel(tags), 1);
freqs = [];
if isfield(eigenInfo, 'ModalProps') && isfield(eigenInfo.ModalProps, 'raw') && ...
        isfield(eigenInfo.ModalProps.raw, 'eigenFrequency')
    freqs = double(eigenInfo.ModalProps.raw.eigenFrequency(:));
end
for i = 1:numel(tags)
    labels(i) = sprintf('%g', tags(i));
    if numel(freqs) >= i && isfinite(freqs(i)) && freqs(i) > 0
        labels(i) = sprintf('%g  (T %.4g s)', tags(i), 1/freqs(i));
    end
end
labels = cellstr(labels);
end

function names = localColormapNames()
names = {'jet','parula','turbo','hot','cool','spring','summer','autumn','winter','gray'};
end

function names = localViewNames()
names = {'auto','iso','xy','xz','yz','yx','zx','zy'};
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

function lines = localModeSummary(eigenInfo, modeTag)
tags = localModeTags(eigenInfo);
idx = find(abs(tags - double(modeTag)) < 1e-12, 1, 'first');
if isempty(idx) && modeTag >= 1 && modeTag <= numel(tags)
    idx = modeTag;
end

lines = strings(0,1);
lines(end+1,1) = sprintf('Available modes: %d', numel(tags));
lines(end+1,1) = sprintf('Selected mode: %g', double(modeTag));

if ~isempty(idx) && isfield(eigenInfo, 'ModalProps') && isfield(eigenInfo.ModalProps, 'raw')
    raw = eigenInfo.ModalProps.raw;

    freq = localModalValue(raw, 'eigenFrequency', idx);
    period = localModalValue(raw, 'eigenPeriod', idx);
    lambda = localModalValue(raw, 'eigenLambda', idx);
    omega = localModalValue(raw, 'eigenOmega', idx);

    if isfinite(freq)
        lines(end+1,1) = sprintf('Frequency: %.6g Hz', freq);
    end
    if isfinite(period)
        lines(end+1,1) = sprintf('Period: %.6g s', period);
    elseif isfinite(freq) && freq > 0
        lines(end+1,1) = sprintf('Period: %.6g s', 1/freq);
    end
    if isfinite(lambda)
        lines(end+1,1) = sprintf('Eigenvalue lambda: %.6g', lambda);
    end
    if isfinite(omega)
        lines(end+1,1) = sprintf('Omega: %.6g rad/s', omega);
    end

    massRatio = localDirectionalValues(raw, 'partiMassRatios', idx, {'MX','MY','MZ'});
    massCumu = localDirectionalValues(raw, 'partiMassRatiosCumu', idx, {'MX','MY','MZ'});
    if any(isfinite(massRatio))
        lines(end+1,1) = sprintf('Mass ratio: %s', localFormatDirectional({'MX','MY','MZ'}, massRatio));
    end
    if any(isfinite(massCumu))
        lines(end+1,1) = sprintf('Cumulative: %s', localFormatDirectional({'MX','MY','MZ'}, massCumu));
    end

    rotRatio = localDirectionalValues(raw, 'partiMassRatios', idx, {'RMX','RMY','RMZ'});
    rotCumu = localDirectionalValues(raw, 'partiMassRatiosCumu', idx, {'RMX','RMY','RMZ'});
    if any(isfinite(rotRatio))
        lines(end+1,1) = sprintf('Rot ratio: %s', localFormatDirectional({'RMX','RMY','RMZ'}, rotRatio));
    end
    if any(isfinite(rotCumu))
        lines(end+1,1) = sprintf('Rot cumulative: %s', localFormatDirectional({'RMX','RMY','RMZ'}, rotCumu));
    end
end

if isempty(idx)
    lines(end+1,1) = 'Selected mode was not found in eigenInfo.ModeTags.';
end
lines = cellstr(lines);
end

function value = localModalValue(raw, fieldName, idx)
value = NaN;
if isfield(raw, fieldName) && numel(raw.(fieldName)) >= idx
    vals = double(raw.(fieldName)(:));
    value = vals(idx);
end
end

function values = localDirectionalValues(raw, prefix, idx, dirs)
values = nan(1, numel(dirs));
for i = 1:numel(dirs)
    fieldName = [prefix dirs{i}];
    values(i) = localModalValue(raw, fieldName, idx);
end
end

function txt = localFormatDirectional(dirs, values)
parts = strings(0,1);
for i = 1:numel(dirs)
    if isfinite(values(i))
        parts(end+1,1) = sprintf('%s %.4g%%', dirs{i}, values(i)); %#ok<AGROW>
    end
end
if isempty(parts)
    txt = '';
else
    txt = strjoin(parts, ', ');
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
