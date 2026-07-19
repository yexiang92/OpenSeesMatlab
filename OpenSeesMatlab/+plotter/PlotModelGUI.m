function app = PlotModelGUI(modelInfo, options)
% PlotModelGUI Interactive GUI wrapper for plotter.PlotModel.
%
% Syntax
% ------
%   app = plotter.PlotModelGUI(modelInfo)
%   app = plotter.PlotModelGUI(modelInfo, opts=opts)
%   app = plotter.PlotModelGUI(modelInfo, watchFile=true)
%   app = plotter.PlotModelGUI(modelInfo, watchFile="modelData_1.hdf5")
%   app = plotter.PlotModelGUI(modelInfo, watchFile="model.tcl", ...
%       reloadFcn=@() opsmat.post.getModelData())
%
% The GUI reuses plotter.PlotModel for all rendering. Controls only update
% the PlotModel option struct and then redraw on the embedded axes. When
% watchFile is true, the caller file is monitored. When watchFile is a path,
% that file is monitored. A MATLAB timer polls the modification time and
% reloads modelInfo when the file changes.

arguments
    modelInfo (1,1) struct
    options.opts (1,1) struct = struct()
    options.watchFile = false
    options.reloadFcn = []
    options.pollInterval (1,1) double {mustBePositive} = 1.0
    options.autoWatch (1,1) logical = true
end

watchFile = localResolveWatchFile(options.watchFile);
opts0 = localMerge(plotter.PlotModel.defaultOptions(), options.opts);
opts0.general.clearAxes = true;
opts0.general.holdOn = true;
opts0.general.figureSize = [];
opts0.summary.show = false;
if ~isfield(opts0.general, 'axesOff')
    opts0.general.axesOff = false;
end
if ~isfield(opts0.general, 'hoverInfo')
    opts0.general.hoverInfo = false;
end

fig = figure( ...
    'Name', 'OpenSeesMatlab Model Plotter | by Yexiang Yan', ...
    'NumberTitle', 'off', ...
    'Color', 'w', ...
    'MenuBar', 'none', ...
    'Toolbar', 'figure', ...
    'Units', 'pixels', ...
    'Position', [120 120 1240 760]);

ax = axes('Parent', fig, 'Units', 'normalized', 'Position', [0.28 0.16 0.70 0.78]);
panel = uipanel( ...
    'Parent', fig, ...
    'Title', 'PlotModel GUI', ...
    'Units', 'normalized', ...
    'Position', [0.015 0.035 0.25 0.93], ...
    'BackgroundColor', 'w');
infoPanel = uipanel( ...
    'Parent', fig, ...
    'Title', 'Model information', ...
    'Units', 'normalized', ...
    'Position', [0.28 0.035 0.70 0.11], ...
    'BackgroundColor', 'w');

state.opts = opts0;
state.modelInfo = modelInfo;
state.pm = [];
state.watchFile = watchFile;
state.reloadFcn = options.reloadFcn;
state.pollInterval = max(0.2, options.pollInterval);
state.watchTimer = [];
state.watchStamp = [];
state.isRedrawing = false;

controls = struct();
y = 0.955;
dy = 0.035;

addLabel('View', y);
controls.view = addPopup(localViewNames(), state.opts.general.view, y);
y = y - dy;

addLabel('Style', y);
controls.styleMode = addPopup({'byFamily','solid','wireframe'}, state.opts.style.mode, y);
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
controls.hoverInfo = addCheck('Hover info', state.opts.general.hoverInfo, y); y = y - dy;

[controls.nodesShow, controls.nodeLabels] = addCheckPair('Nodes', state.opts.nodes.show, ...
    'Node labels', state.opts.nodes.showLabels, y); y = y - dy;
[controls.elementLabels, controls.fixedShow] = addCheckPair('Element labels', state.opts.elements.showLabels, ...
    'Fixed nodes', state.opts.fixed.show, y); y = y - dy;
[controls.mpShow, controls.outlineShow] = addCheckPair('MP constraints', state.opts.mpConstraint.show, ...
    'Outline', state.opts.outline.show, y); y = y - dy;

addSeparator(y); y = y - dy * 0.55;
addText('Elements', y); y = y - dy * 0.9;
[controls.showBeam, controls.showTruss] = addCheckPair('Beam', state.opts.elements.showBeam, ...
    'Truss', state.opts.elements.showTruss, y); y = y - dy;
[controls.showLink, controls.showPlane] = addCheckPair('Link', state.opts.elements.showLink, ...
    'Plane', state.opts.elements.showPlane, y); y = y - dy;
[controls.showShell, controls.showSolid] = addCheckPair('Shell', state.opts.elements.showShell, ...
    'Solid', state.opts.elements.showSolid, y); y = y - dy;
[controls.showContact, controls.wireframeOnly] = addCheckPair('Contact', state.opts.elements.showContact, ...
    'Wireframe', state.opts.elements.wireframeOnly, y); y = y - dy;
controls.faceWireframe = addCheck('Face edges', state.opts.elements.showWireframeOnFaces, y); y = y - dy;

addSeparator(y); y = y - dy * 0.55;
addText('Axes / loads', y); y = y - dy * 0.9;
[controls.localBeam, controls.localLink] = addCheckPair('Beam axes', state.opts.localAxes.showBeam, ...
    'Link axes', state.opts.localAxes.showLink, y); y = y - dy;
[controls.loadNodal, controls.loadElement] = addCheckPair('Nodal loads', state.opts.loads.showNodal, ...
    'Element loads', state.opts.loads.showElement, y); y = y - dy;
[controls.loadLabels, controls.grid] = addCheckPair('Load labels', state.opts.loads.showLabels, ...
    'Grid', state.opts.general.grid, y); y = y - dy;
[controls.box, controls.axesOff] = addCheckPair('Box', state.opts.general.box, ...
    'Axes off', state.opts.general.axesOff, y); y = y - dy;

addSeparator(y); y = y - dy * 0.55;
addText('Surface alpha', y); y = y - dy * 0.8;
controls.alpha = addSlider(0, 1, state.opts.elements.surfaceAlpha, y); y = y - dy;
addText('Line width', y); y = y - dy * 0.8;
controls.lineWidth = addSlider(0.2, 6, state.opts.elements.lineWidth, y); y = y - dy;
addText('Load scale', y); y = y - dy * 0.8;
controls.loadScale = addSlider(0.1, 10, state.opts.loads.scale, y); y = y - dy;

addText('Title', y); y = y - dy * 0.8;
controls.title = uicontrol(panel, ...
    'Style', 'edit', ...
    'Units', 'normalized', ...
    'Position', [0.06 y 0.88 0.030], ...
    'String', char(string(state.opts.general.title)), ...
    'HorizontalAlignment', 'left', ...
    'Callback', @redraw);
y = y - dy * 1.25; %#ok<NASGU>

controls.watchStatus = uicontrol(panel, 'Style', 'text', 'Units', 'normalized', ...
    'Position', [0.06 0.010 0.88 0.025], ...
    'String', 'Watch: off', ...
    'HorizontalAlignment', 'left', ...
    'BackgroundColor', 'w', ...
    'ForegroundColor', [0.30 0.30 0.30]);
controls.modelInfo = uicontrol(infoPanel, 'Style', 'edit', 'Units', 'normalized', ...
    'Position', [0.015 0.08 0.97 0.78], ...
    'String', localModelSummary(state.modelInfo), ...
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
    'reset', @resetOptions, ...
    'startWatcher', @startWatcher, ...
    'stopWatcher', @stopWatcher);
fig.UserData = app;
fig.CloseRequestFcn = @closeGui;

redraw();
if options.autoWatch && strlength(string(state.watchFile)) > 0
    startWatcher();
end

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
        idx = find(strcmpi(items, char(string(value))), 1, 'first');
        if isempty(idx), idx = 1; end
        h = uicontrol(panel, 'Style', 'popupmenu', 'Units', 'normalized', ...
            'Position', [0.42 yy 0.52 0.030], ...
            'String', items, 'Value', idx, 'Callback', @redraw);
    end

    function h = addCheck(txt, value, yy)
        h = uicontrol(panel, 'Style', 'checkbox', 'Units', 'normalized', ...
            'Position', [0.06 yy 0.88 0.030], ...
            'String', txt, 'Value', logical(value), ...
            'BackgroundColor', 'w', 'Callback', @redraw);
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
        state.pm = plotter.PlotModel(state.modelInfo, ax, state.opts);
        state.pm.plot();
        applyAxesVisibility();
        updateModelDataTips();
        app.PlotModel = state.pm;
        app.Options = state.opts;
        app.ModelInfo = state.modelInfo;
        app.WatchTimer = state.watchTimer;
        updateModelInfo();
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

    function showHelp(~, ~)
        helpFig = figure('Name', 'PlotModel Options Help | by Yexiang Yan', 'NumberTitle', 'off', ...
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
            'Line',          {'style','lineColor'}
            'Shell surface', {'style','shellColor'}
            'Solid surface', {'style','solidColor'}
            'Wireframe',     {'style','wireframeColor'}
            'Node',          {'nodes','color'}
            'Node edge',     {'nodes','edgeColor'}
            'Fixed node',    {'fixed','color'}
            'Fixed edge',    {'fixed','edgeColor'}
            'MP constraint', {'mpConstraint','color'}
            'Nodal load',    {'loads','nodalColor'}
            'Element load',  {'loads','elementColor'}
            'Beam family',   {'style','familyColors','Beam'}
            'Truss family',  {'style','familyColors','Truss'}
            'Link family',   {'style','familyColors','Link'}
            'Plane family',  {'style','familyColors','Plane'}
            'Shell family',  {'style','familyColors','Shell'}
            'Solid family',  {'style','familyColors','Solid'}
            'Contact family',{'style','familyColors','Contact'}
            };

        colorFig = figure('Name', 'PlotModel Colors | by Yexiang Yan', 'NumberTitle', 'off', ...
            'Color', 'w', 'MenuBar', 'none', 'Toolbar', 'none', ...
            'Units', 'pixels', 'Position', [220 160 330 610]);

        nItem = size(colorItems, 1);
        rowH = 0.90 / nItem;
        for i = 1:nItem
            yy = 0.96 - i * rowH;
            label = colorItems{i,1};
            path = colorItems{i,2};
            value = localGetNested(state.opts, path);
            rgb = localColorToRgb(value);

            uicontrol(colorFig, 'Style', 'text', 'Units', 'normalized', ...
                'Position', [0.07 yy 0.52 rowH * 0.72], ...
                'String', label, ...
                'HorizontalAlignment', 'left', ...
                'BackgroundColor', 'w');
            uicontrol(colorFig, 'Style', 'pushbutton', 'Units', 'normalized', ...
                'Position', [0.63 yy 0.28 rowH * 0.72], ...
                'String', localColorLabel(value), ...
                'BackgroundColor', rgb, ...
                'ForegroundColor', localTextColorForBg(rgb), ...
                'Callback', @(src,~) pickColor(src, path, label));
        end

        uicontrol(colorFig, 'Style', 'pushbutton', 'Units', 'normalized', ...
            'Position', [0.07 0.02 0.40 0.045], ...
            'String', 'Reset colors', ...
            'Callback', @resetColors);
        uicontrol(colorFig, 'Style', 'pushbutton', 'Units', 'normalized', ...
            'Position', [0.53 0.02 0.38 0.045], ...
            'String', 'Close', ...
            'Callback', @(~,~) close(colorFig));

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
            defaults = plotter.PlotModel.defaultOptions();
            for k = 1:nItem
                path = colorItems{k,2};
                state.opts = localSetNested(state.opts, path, localGetNested(defaults, path));
            end
            if ishandle(colorFig)
                close(colorFig);
            end
            showColors();
            redraw();
        end
    end

    function startWatcher(~, ~)
        if strlength(string(state.watchFile)) == 0
            setWatchStatus('Watch: no file', [0.65 0.20 0.10]);
            return;
        end
        if ~isempty(state.watchTimer) && isvalid(state.watchTimer)
            stopWatcher();
        end

        state.watchStamp = localFileStamp(state.watchFile);
        state.watchTimer = timer( ...
            'ExecutionMode', 'fixedSpacing', ...
            'Period', state.pollInterval, ...
            'BusyMode', 'drop', ...
            'Name', 'PlotModelGUIFileWatcher', ...
            'TimerFcn', @checkWatchedFile);
        start(state.watchTimer);
        app.WatchTimer = state.watchTimer;
        app.WatchFile = state.watchFile;
        fig.UserData = app;
        setWatchStatus(sprintf('Watch: %s', localShortPath(state.watchFile)), [0.10 0.40 0.15]);
    end

    function stopWatcher(~, ~)
        if ~isempty(state.watchTimer) && isvalid(state.watchTimer)
            stop(state.watchTimer);
            delete(state.watchTimer);
        end
        state.watchTimer = [];
        app.WatchTimer = [];
        if ishandle(fig)
            fig.UserData = app;
        end
        setWatchStatus('Watch: off', [0.30 0.30 0.30]);
    end

    function checkWatchedFile(~, ~)
        if ~ishandle(fig)
            stopWatcher();
            return;
        end

        stamp = localFileStamp(state.watchFile);
        if isempty(stamp)
            setWatchStatus('Watch: file missing', [0.70 0.20 0.10]);
            return;
        end
        if isempty(state.watchStamp)
            state.watchStamp = stamp;
            return;
        end
        if stamp.datenum == state.watchStamp.datenum && stamp.bytes == state.watchStamp.bytes
            return;
        end

        state.watchStamp = stamp;
        try
            state.modelInfo = reloadModelInfo();
            redraw();
            setWatchStatus(sprintf('Updated: %s', char(datetime("now", "Format", "HH:mm:ss"))), [0.10 0.40 0.15]);
        catch ME
            setWatchStatus(sprintf('Reload failed: %s', ME.identifier), [0.70 0.20 0.10]);
            warning('PlotModelGUI:ReloadFailed', ...
                'Could not reload watched model file "%s": %s', state.watchFile, ME.message);
        end
    end

    function modelInfoNew = reloadModelInfo()
        if ~isempty(state.reloadFcn)
            modelInfoNew = state.reloadFcn();
        else
            modelInfoNew = localLoadModelInfo(state.watchFile);
        end
        localValidateModelInfo(modelInfoNew);
    end

    function setWatchStatus(txt, color)
        if isfield(controls, 'watchStatus') && ishandle(controls.watchStatus)
            controls.watchStatus.String = txt;
            controls.watchStatus.ForegroundColor = color;
        end
    end

    function updateModelInfo()
        if isfield(controls, 'modelInfo') && ishandle(controls.modelInfo)
            controls.modelInfo.String = localModelSummary(state.modelInfo);
        end
    end

    function closeGui(~, ~)
        stopWatcher();
        if ishandle(fig)
            delete(fig);
        end
    end

    function opts = readControls(opts)
        views = controls.view.String;
        styles = controls.styleMode.String;

        opts.general.view = views{controls.view.Value};
        opts.style.mode = styles{controls.styleMode.Value};
        opts.nodes.show = logical(controls.nodesShow.Value);
        opts.nodes.showLabels = logical(controls.nodeLabels.Value);
        opts.elements.showLabels = logical(controls.elementLabels.Value);
        opts.fixed.show = logical(controls.fixedShow.Value);
        opts.mpConstraint.show = logical(controls.mpShow.Value);
        opts.outline.show = logical(controls.outlineShow.Value);

        opts.elements.showBeam = logical(controls.showBeam.Value);
        opts.elements.showTruss = logical(controls.showTruss.Value);
        opts.elements.showLink = logical(controls.showLink.Value);
        opts.elements.showPlane = logical(controls.showPlane.Value);
        opts.elements.showShell = logical(controls.showShell.Value);
        opts.elements.showSolid = logical(controls.showSolid.Value);
        opts.elements.showContact = logical(controls.showContact.Value);
        opts.elements.wireframeOnly = logical(controls.wireframeOnly.Value);
        opts.elements.showWireframeOnFaces = logical(controls.faceWireframe.Value);

        opts.localAxes.showBeam = logical(controls.localBeam.Value);
        opts.localAxes.showLink = logical(controls.localLink.Value);
        opts.loads.showNodal = logical(controls.loadNodal.Value);
        opts.loads.showElement = logical(controls.loadElement.Value);
        opts.loads.showLabels = logical(controls.loadLabels.Value);
        opts.general.grid = logical(controls.grid.Value);
        opts.general.box = logical(controls.box.Value);
        opts.general.axesOff = logical(controls.axesOff.Value);
        opts.general.hoverInfo = logical(controls.hoverInfo.Value);

        opts.elements.surfaceAlpha = controls.alpha.Value;
        opts.elements.lineWidth = controls.lineWidth.Value;
        opts.loads.scale = controls.loadScale.Value;
        opts.general.title = controls.title.String;
    end

    function applyControls(opts)
        setPopup(controls.view, opts.general.view);
        setPopup(controls.styleMode, opts.style.mode);
        controls.nodesShow.Value = logical(opts.nodes.show);
        controls.nodeLabels.Value = logical(opts.nodes.showLabels);
        controls.elementLabels.Value = logical(opts.elements.showLabels);
        controls.fixedShow.Value = logical(opts.fixed.show);
        controls.mpShow.Value = logical(opts.mpConstraint.show);
        controls.outlineShow.Value = logical(opts.outline.show);

        controls.showBeam.Value = logical(opts.elements.showBeam);
        controls.showTruss.Value = logical(opts.elements.showTruss);
        controls.showLink.Value = logical(opts.elements.showLink);
        controls.showPlane.Value = logical(opts.elements.showPlane);
        controls.showShell.Value = logical(opts.elements.showShell);
        controls.showSolid.Value = logical(opts.elements.showSolid);
        controls.showContact.Value = logical(opts.elements.showContact);
        controls.wireframeOnly.Value = logical(opts.elements.wireframeOnly);
        controls.faceWireframe.Value = logical(opts.elements.showWireframeOnFaces);

        controls.localBeam.Value = logical(opts.localAxes.showBeam);
        controls.localLink.Value = logical(opts.localAxes.showLink);
        controls.loadNodal.Value = logical(opts.loads.showNodal);
        controls.loadElement.Value = logical(opts.loads.showElement);
        controls.loadLabels.Value = logical(opts.loads.showLabels);
        controls.grid.Value = logical(opts.general.grid);
        controls.box.Value = logical(opts.general.box);
        controls.axesOff.Value = logical(opts.general.axesOff);
        controls.hoverInfo.Value = logical(opts.general.hoverInfo);

        controls.alpha.Value = opts.elements.surfaceAlpha;
        controls.lineWidth.Value = opts.elements.lineWidth;
        controls.loadScale.Value = opts.loads.scale;
        controls.title.String = char(string(opts.general.title));
    end

    function applyAxesVisibility()
        if isfield(state.opts.general, 'axesOff') && state.opts.general.axesOff
            axis(ax, 'off');
        else
            axis(ax, 'on');
            if state.opts.general.grid
                grid(ax, 'on');
            else
                grid(ax, 'off');
            end
            if state.opts.general.box
                box(ax, 'on');
            else
                box(ax, 'off');
            end
        end
    end

    function updateModelDataTips()
        if ~isfield(state.opts.general, 'hoverInfo') || ~state.opts.general.hoverInfo
            disableModelDataTips();
            return;
        end

        try
            dcm = datacursormode(fig);
            dcm.UpdateFcn = @modelDataTip;
            dcm.SnapToDataVertex = 'on';
            dcm.Enable = 'on';
        catch
        end

        if isempty(state.pm) || ~isprop(state.pm, 'Handles')
            return;
        end

        H = state.pm.Handles;
        [nodeTags, nodeCoords] = localGetNodes(state.modelInfo);

        if isfield(H, 'Nodes')
            localSetTipData(H.Nodes, struct( ...
                'kind', 'Node', ...
                'tags', nodeTags, ...
                'points', nodeCoords));
        end

        if isfield(H, 'Fixed')
            [fixedTags, fixedCoords] = localGetFixedNodes(state.modelInfo);
            localSetTipData(H.Fixed, struct( ...
                'kind', 'Fixed node', ...
                'tags', fixedTags, ...
                'points', fixedCoords));
        end

        fam = localGetFamilies(state.modelInfo);
        famNames = fieldnames(fam);
        for iFam = 1:numel(famNames)
            name = famNames{iFam};
            if ~isstruct(fam.(name))
                continue;
            end

            [eleTags, centroids] = localElementCentroids(fam.(name), name, nodeCoords);
            if isempty(centroids)
                continue;
            end

            data = struct( ...
                'kind', 'Element', ...
                'family', name, ...
                'tags', eleTags, ...
                'points', centroids);

            if isfield(H, name)
                localSetTipData(H.(name), data);
            end
            wireName = [name 'Wireframe'];
            if isfield(H, wireName)
                localSetTipData(H.(wireName), data);
            end
        end

        specialNames = {'MPConstraint','NodalLoads','ElementLoads','Outline'};
        specialLabels = {'MP constraint','Nodal load','Element load','Outline'};
        for i = 1:numel(specialNames)
            if isfield(H, specialNames{i})
                localSetTipData(H.(specialNames{i}), struct( ...
                    'kind', specialLabels{i}, ...
                    'tags', [], ...
                    'points', []));
            end
        end
    end

    function disableModelDataTips()
        try
            dcm = datacursormode(fig);
            dcm.Enable = 'off';
            dcm.UpdateFcn = [];
        catch
        end
    end

    function txt = modelDataTip(~, event)
        pos = event.Position;
        target = event.Target;
        data = [];
        if isprop(target, 'UserData') && isstruct(target.UserData) && ...
                isfield(target.UserData, 'PlotModelGUIData')
            data = target.UserData.PlotModelGUIData;
        end

        txt = localPositionLines(pos);
        if isempty(data)
            return;
        end

        switch data.kind
            case {'Node','Fixed node'}
                idx = localNearestPoint(data.points, pos);
                if idx > 0
                    txt = [
                        {sprintf('%s: %s', data.kind, localTagText(data.tags, idx))}
                        localPositionLines(data.points(idx,:))
                        ];
                end
            case 'Element'
                idx = localNearestPoint(data.points, pos);
                txt = [{sprintf('Element family: %s', data.family)}; txt(:)];
                if idx > 0
                    txt = [
                        {sprintf('Element: %s', localTagText(data.tags, idx))}
                        txt(:)
                        {sprintf('Element center: %.6g, %.6g, %.6g', data.points(idx,1), data.points(idx,2), data.points(idx,3))}
                        ];
                end

                [nodeTags, nodeCoords] = localGetNodes(state.modelInfo);
                nodeIdx = localNearestPoint(nodeCoords, pos);
                if nodeIdx > 0
                    txt{end+1,1} = sprintf('Nearest node: %s', localTagText(nodeTags, nodeIdx));
                end
            otherwise
                txt = [{sprintf('Object: %s', data.kind)}; txt(:)];
        end
    end

    function setPopup(h, value)
        idx = find(strcmpi(h.String, char(string(value))), 1, 'first');
        if isempty(idx), idx = 1; end
        h.Value = idx;
    end
end

function watchFile = localResolveWatchFile(value)
if islogical(value) || (isnumeric(value) && isscalar(value))
    if logical(value)
        watchFile = localCallerFile();
    else
        watchFile = '';
    end
    return;
end

if isstring(value) || ischar(value)
    watchFile = char(string(value));
    return;
end

error('PlotModelGUI:InvalidWatchFile', ...
    'watchFile must be false, true, or a file path.');
end

function filename = localCallerFile()
stack = dbstack('-completenames');
if numel(stack) < 2
    filename = localActiveEditorFile();
    return;
end

thisFile = mfilename('fullpath');
thisFile = localNormalizePath([thisFile '.m']);
for i = numel(stack):-1:2
    candidate = '';
    if isfield(stack(i), 'file')
        candidate = stack(i).file;
    end
    if strlength(string(candidate)) == 0
        continue;
    end

    normalized = localNormalizePath(candidate);
    if strcmpi(normalized, thisFile)
        continue;
    end

    filename = candidate;
    return;
end

filename = localActiveEditorFile();
end

function filename = localActiveEditorFile()
filename = '';
try
    doc = matlab.desktop.editor.getActive;
    if ~isempty(doc) && strlength(string(doc.Filename)) > 0
        filename = doc.Filename;
    end
catch
    filename = '';
end
end

function path = localNormalizePath(path)
path = char(string(path));
try
    info = dir(path);
    if ~isempty(info)
        path = fullfile(info(1).folder, info(1).name);
    end
catch
end
path = lower(strrep(path, '/', filesep));
end

function modelInfo = localLoadModelInfo(filename)
filename = char(string(filename));
[~,~,ext] = fileparts(filename);
ext = lower(ext);

switch ext
    case {'.hdf5', '.h5'}
        store = post.utils.HDF5DataStore(filename, 'overwrite', false);
        modelInfo = store.load();
    case '.mat'
        data = load(filename);
        modelInfo = localExtractModelInfo(data);
    case '.json'
        modelInfo = jsondecode(fileread(filename));
    otherwise
        error('PlotModelGUI:UnsupportedWatchFile', ...
            ['No default loader is available for "%s". ', ...
             'Pass reloadFcn=@() ... to return a fresh modelInfo struct.'], ext);
end

localValidateModelInfo(modelInfo);
end

function modelInfo = localExtractModelInfo(data)
if isfield(data, 'modelInfo')
    modelInfo = data.modelInfo;
    return;
end
if isfield(data, 'ModelInfo')
    modelInfo = data.ModelInfo;
    return;
end

names = fieldnames(data);
for i = 1:numel(names)
    value = data.(names{i});
    if isstruct(value) && isfield(value, 'Nodes')
        modelInfo = value;
        return;
    end
end

error('PlotModelGUI:MissingModelInfo', ...
    'MAT file must contain modelInfo, ModelInfo, or a struct with a Nodes field.');
end

function localValidateModelInfo(modelInfo)
if ~isstruct(modelInfo) || ~isfield(modelInfo, 'Nodes')
    error('PlotModelGUI:InvalidModelInfo', ...
        'Reloaded data must be a modelInfo struct with a Nodes field.');
end
end

function names = localViewNames()
names = {'auto','iso','xy','xz','yz','yx','zx','zy'};
end

function lines = localModelSummary(modelInfo)
lines = strings(0,1);

nNode = localCountNodes(modelInfo);
if nNode > 0
    lines(end+1,1) = sprintf('Nodes: %d', nNode);
end

[famNames, famCounts] = localCountElementFamilies(modelInfo);
totalEle = sum(famCounts);
if totalEle > 0
    lines(end+1,1) = sprintf('Elements: %d', totalEle);
    famLines = strings(nnz(famCounts > 0), 1);
    iLine = 0;
    for i = 1:numel(famNames)
        if famCounts(i) > 0
            iLine = iLine + 1;
            famLines(iLine,1) = sprintf('  %-12s %d', famNames(i), famCounts(i));
        end
    end
    lines = [lines; famLines];
end

nFixed = localCountFixedNodes(modelInfo);
if nFixed > 0
    lines(end+1,1) = sprintf('Fixed nodes: %d', nFixed);
end

nMp = localCountMPConstraints(modelInfo);
if nMp > 0
    lines(end+1,1) = sprintf('MP constraints: %d', nMp);
end

[nNodalLoads, nElementLoads] = localCountLoads(modelInfo);
if nNodalLoads > 0 || nElementLoads > 0
    lines(end+1,1) = sprintf('Loads: nodal %d, element %d', nNodalLoads, nElementLoads);
end

if isempty(lines)
    lines = "No model information available.";
end

lines = cellstr(lines);
end

function n = localCountNodes(modelInfo)
n = 0;
if isfield(modelInfo, 'Nodes') && isfield(modelInfo.Nodes, 'Tags') && ~isempty(modelInfo.Nodes.Tags)
    n = nnz(isfinite(double(modelInfo.Nodes.Tags(:))));
elseif isfield(modelInfo, 'Nodes') && isfield(modelInfo.Nodes, 'Coords') && ~isempty(modelInfo.Nodes.Coords)
    coords = double(modelInfo.Nodes.Coords);
    if isvector(coords)
        coords = reshape(coords, [], 1);
    end
    n = nnz(any(isfinite(coords), 2));
end
end

function [names, counts] = localCountElementFamilies(modelInfo)
names = strings(0,1);
counts = zeros(0,1);

if ~isfield(modelInfo, 'Elements') || ~isstruct(modelInfo.Elements)
    return;
end

elements = modelInfo.Elements;
if isfield(elements, 'Families') && isstruct(elements.Families)
    families = elements.Families;
else
    families = elements;
end

fields = fieldnames(families);
for i = 1:numel(fields)
    value = families.(fields{i});
    if ~isstruct(value)
        continue;
    end
    n = localCountFamilyEntities(value);
    if n > 0
        names(end+1,1) = string(fields{i}); %#ok<AGROW>
        counts(end+1,1) = n; %#ok<AGROW>
    end
end
end

function n = localCountFamilyEntities(value)
n = 0;
if isfield(value, 'Tags') && ~isempty(value.Tags)
    n = nnz(isfinite(double(value.Tags(:))));
elseif isfield(value, 'Cells') && ~isempty(value.Cells)
    cells = double(value.Cells);
    while ~ismatrix(cells)
        cells = squeeze(cells);
    end
    if isempty(cells)
        return;
    end
    if isvector(cells)
        cells = reshape(cells, 1, []);
    end
    n = nnz(any(isfinite(cells), 2));
end
end

function n = localCountFixedNodes(modelInfo)
n = 0;
if isfield(modelInfo, 'Fixed') && isstruct(modelInfo.Fixed)
    fixed = modelInfo.Fixed;
    if isfield(fixed, 'NodeTags') && ~isempty(fixed.NodeTags)
        n = nnz(isfinite(double(fixed.NodeTags(:))));
    elseif isfield(fixed, 'NodeIndex') && ~isempty(fixed.NodeIndex)
        n = nnz(isfinite(double(fixed.NodeIndex(:))));
    end
end
end

function n = localCountMPConstraints(modelInfo)
n = 0;
if isfield(modelInfo, 'MPConstraint') && isstruct(modelInfo.MPConstraint) && ...
        isfield(modelInfo.MPConstraint, 'Cells') && ~isempty(modelInfo.MPConstraint.Cells)
    cells = double(modelInfo.MPConstraint.Cells);
    while ~ismatrix(cells)
        cells = squeeze(cells);
    end
    if isvector(cells)
        cells = reshape(cells, 1, []);
    end
    n = nnz(any(isfinite(cells), 2));
end
end

function [nNodal, nElement] = localCountLoads(modelInfo)
nNodal = 0;
nElement = 0;
if ~isfield(modelInfo, 'Loads') || ~isstruct(modelInfo.Loads)
    return;
end

loads = modelInfo.Loads;
if isfield(loads, 'Node') && isstruct(loads.Node)
    if isfield(loads.Node, 'PatternNodeTags') && ~isempty(loads.Node.PatternNodeTags)
        tags = double(loads.Node.PatternNodeTags);
        if isvector(tags)
            tags = reshape(tags, [], 1);
        end
        nNodal = size(tags, 1);
    elseif isfield(loads.Node, 'Values') && ~isempty(loads.Node.Values)
        vals = double(loads.Node.Values);
        if isvector(vals)
            vals = reshape(vals, 1, []);
        end
        nNodal = size(vals, 1);
    end
end

if isfield(loads, 'Element') && isstruct(loads.Element)
    elementLoads = loads.Element;
    fields = fieldnames(elementLoads);
    for i = 1:numel(fields)
        value = elementLoads.(fields{i});
        if isstruct(value) && isfield(value, 'Values') && ~isempty(value.Values)
            vals = double(value.Values);
            if isvector(vals)
                vals = reshape(vals, 1, []);
            end
            nElement = nElement + size(vals, 1);
        end
    end
end
end

function localSetTipData(h, data)
if isempty(h)
    return;
end
for i = 1:numel(h)
    if isgraphics(h(i))
        ud = struct();
        ud.PlotModelGUIData = data;
        h(i).UserData = ud;
    end
end
end

function [tags, coords] = localGetNodes(modelInfo)
tags = zeros(0,1);
coords = zeros(0,3);
if ~isfield(modelInfo, 'Nodes') || ~isstruct(modelInfo.Nodes)
    return;
end

nodes = modelInfo.Nodes;
if isfield(nodes, 'Coords') && ~isempty(nodes.Coords)
    coords = localPad3(double(nodes.Coords));
end
if isfield(nodes, 'Tags') && ~isempty(nodes.Tags)
    tags = double(nodes.Tags(:));
elseif ~isempty(coords)
    tags = (1:size(coords,1)).';
end

n = min(numel(tags), size(coords,1));
tags = tags(1:n);
coords = coords(1:n,:);
end

function [tags, coords] = localGetFixedNodes(modelInfo)
tags = zeros(0,1);
coords = zeros(0,3);
if ~isfield(modelInfo, 'Fixed') || ~isstruct(modelInfo.Fixed)
    return;
end

fixed = modelInfo.Fixed;
if isfield(fixed, 'NodeTags') && ~isempty(fixed.NodeTags)
    tags = double(fixed.NodeTags(:));
end
if isfield(fixed, 'Coords') && ~isempty(fixed.Coords)
    coords = localPad3(double(fixed.Coords));
elseif ~isempty(tags)
    [nodeTags, nodeCoords] = localGetNodes(modelInfo);
    coords = nan(numel(tags), 3);
    for i = 1:numel(tags)
        idx = find(abs(nodeTags - tags(i)) < 1e-12, 1, 'first');
        if ~isempty(idx)
            coords(i,:) = nodeCoords(idx,:);
        end
    end
end

valid = all(isfinite(coords), 2);
tags = tags(valid);
coords = coords(valid,:);
end

function fam = localGetFamilies(modelInfo)
fam = struct();
if ~isfield(modelInfo, 'Elements') || ~isstruct(modelInfo.Elements)
    return;
end
if isfield(modelInfo.Elements, 'Families') && isstruct(modelInfo.Elements.Families)
    fam = modelInfo.Elements.Families;
else
    fam = modelInfo.Elements;
end
end

function [tags, centroids] = localElementCentroids(S, familyName, nodeCoords)
tags = zeros(0,1);
centroids = zeros(0,3);
if ~isstruct(S) || ~isfield(S, 'Cells') || isempty(S.Cells) || isempty(nodeCoords)
    return;
end

cells = double(S.Cells);
while ~ismatrix(cells)
    cells = squeeze(cells);
end
if isempty(cells)
    return;
end
if isvector(cells)
    cells = reshape(cells, 1, []);
end

nEle = size(cells, 1);
if isfield(S, 'Tags') && ~isempty(S.Tags)
    tags = double(S.Tags(:));
else
    tags = (1:nEle).';
end
nEle = min(nEle, numel(tags));
tags = tags(1:nEle);
centroids = nan(nEle, 3);
nNode = size(nodeCoords, 1);
isLineFamily = ismember(lower(char(string(familyName))), {'beam','truss','link','line','contact'});

for i = 1:nEle
    idx = localCellNodeIndices(cells(i,:), nNode, isLineFamily);
    if isempty(idx)
        continue;
    end
    centroids(i,:) = mean(nodeCoords(idx,:), 1, 'omitnan');
end

valid = all(isfinite(centroids), 2);
tags = tags(valid);
centroids = centroids(valid,:);
end

function idx = localCellNodeIndices(row, nNode, isLineFamily)
row = double(row(:).');
idx = row(isfinite(row) & mod(row, 1) == 0 & row >= 1 & row <= nNode);
idx = round(idx);
if isLineFamily && numel(idx) >= 2
    idx = idx(end-1:end);
end
idx = unique(idx, 'stable');
end

function idx = localNearestPoint(points, pos)
idx = 0;
if isempty(points)
    return;
end
points = localPad3(points);
pos = localPad3(pos);
delta = points - pos(1,:);
d2 = sum(delta.^2, 2, 'omitnan');
[best, idx] = min(d2);
if isempty(best) || ~isfinite(best)
    idx = 0;
end
end

function txt = localPositionLines(pos)
pos = localPad3(pos);
txt = {
    sprintf('X: %.6g', pos(1,1))
    sprintf('Y: %.6g', pos(1,2))
    sprintf('Z: %.6g', pos(1,3))
    };
end

function txt = localTagText(tags, idx)
if isempty(tags) || idx < 1 || idx > numel(tags) || ~isfinite(tags(idx))
    txt = 'unknown';
else
    txt = sprintf('%.15g', tags(idx));
end
end

function P = localPad3(P)
P = double(P);
if isempty(P)
    P = zeros(0,3);
    return;
end
if isvector(P)
    P = reshape(P, 1, []);
end
if size(P,2) < 3
    P(:,3) = 0;
end
P = P(:,1:3);
end

function stamp = localFileStamp(filename)
info = dir(filename);
if isempty(info)
    stamp = [];
else
    stamp = struct('datenum', info(1).datenum, 'bytes', info(1).bytes);
end
end

function txt = localShortPath(filename)
txt = char(string(filename));
[~, name, ext] = fileparts(txt);
txt = [name ext];
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
    if any(rgb > 1)
        rgb = rgb / 255;
    end
    rgb = max(0, min(1, rgb(:).'));
    return;
end

txt = lower(strtrim(char(string(value))));
named = struct( ...
    'black', [0 0 0], ...
    'white', [1 1 1], ...
    'red',   [1 0 0], ...
    'green', [0 1 0], ...
    'blue',  [0 0 1], ...
    'cyan',  [0 1 1], ...
    'magenta', [1 0 1], ...
    'yellow', [1 1 0]);
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
