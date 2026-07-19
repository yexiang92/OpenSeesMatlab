classdef plotFrameResponse < plotter.polyscope.ViewerBase
    %PLOTFRAMERESPONSE Polyscope/ImGui viewer for frame element response diagrams.

    properties
        FrameResp struct
    end

    properties (Access = private)
        currentStep_ double = 0
        currentSeg_ double = 1
        currentLocalStep_ double = 1
        nSteps_ double = 1
        segStepCounts_ double = []
        segOffsets_ double = []
        respTypes_ cell = {}
        components_ cell = {}
        meshData_ struct = struct()
        modelData_ struct = struct()
        animDir_ double = 1
        extremeStepCache_ struct = struct()
        responseStatsCache_ struct = struct()
        initialOpts_ struct
        beamInfoCache_ struct = struct()
        historyCacheKey_ char = ''
        historyCacheX_ double = []
        historyCacheY_ double = []
        historyRawKey_ char = ''
        historyRawX_ double = []
        historyRawValues_ cell = {}
    end

    methods
        function obj = plotFrameResponse(modelInfo, frameResp, opts)
            if nargin < 1 || isempty(modelInfo)
                error('plotter:polyscope:FrameResponse:InvalidInput', 'modelInfo is required.');
            end
            if nargin < 2 || isempty(frameResp)
                error('plotter:polyscope:FrameResponse:InvalidInput', 'frameResp is required.');
            end
            if nargin < 3 || isempty(opts), opts = struct(); end

            obj = obj@plotter.polyscope.ViewerBase();
            obj.ModelInfo = modelInfo;
            obj.FrameResp = frameResp;
            obj.Opts = plotter.polyscope.Options.mergeOpts( ...
                plotter.polyscope.Options.defaultFrameResponseOptions(), opts);
            obj.App = plotter.polyscope.PolyscopeApp();
            obj.P0_ = obj.nodeCoords_(1);
            obj.L_ = obj.modelLength_(obj.P0_);
            obj.buildStepIndex_();
            obj.respTypes_ = obj.collectResponseTypes_();
            if isempty(obj.respTypes_)
                error('plotter:polyscope:FrameResponse:NoResponses', ...
                    'No plottable frame response field was found in frameResp.');
            end
            obj.Opts.respType = obj.pickExisting_(obj.respTypes_, obj.Opts.respType);
            obj.components_ = obj.componentsForResponse_(obj.Opts.respType);
            obj.Opts.component = obj.pickExisting_(obj.components_, obj.Opts.component);
            obj.initialOpts_ = obj.Opts;
            obj.currentStep_ = obj.resolveStepArg_(obj.getOptField_(obj.Opts, 'stepIdx', 'absmax'));

            if obj.isHeadless_()
                obj.Opts.polyscope.backend = 'openGL_mock';
            end
            if obj.shouldAutoShow_()
                obj.enableGui();
                obj.show();
            else
                obj.frameTick();
            end
        end

        function build(obj)
            firstBuild = ~obj.built_;
            is2D = obj.is2DPoints_(obj.nodeCoords_(1));
            if is2D && any(strcmpi(char(string(obj.Opts.general.view)), {'auto','3D'}))
                obj.Opts.general.view = 'XY';
            end
            obj.App.init(obj.Opts.polyscope.backend, obj.Opts, is2D);
            try, obj.App.polyscopeHandle().set_ground_plane_mode('none'); catch, end
            obj.setupWindowIcon_();
            obj.clear_();
            obj.handles_ = struct();
            obj.meshData_ = struct();
            obj.modelData_ = struct();
            obj.built_ = true;
            if isempty(fieldnames(obj.gui_)), obj.initGuiState_(); end
            obj.configureAnimationRenderLoop_();
            obj.setStep(obj.currentStep_, true);
            obj.registerSlicePlanes_();
            obj.applySliceCullWholeElements_();
            if firstBuild
                obj.setCameraForPoints_(obj.P0_, obj.Opts.general.view);
            end
        end

        function setStep(obj, stepArg, force)
            if nargin < 3, force = false; end
            step = obj.resolveStepArg_(stepArg);
            [segIdx, localStep] = obj.resolveGlobalStep_(step);
            rebuild = force || segIdx ~= obj.currentSeg_ || ~isfield(obj.handles_, 'def_Diagram');
            if rebuild
                camState = obj.animationPlaneCameraState_();
                obj.registerSegment_(segIdx, localStep);
                obj.restoreCameraState_(camState);
            else
                obj.updateStep_(segIdx, localStep);
            end
            obj.currentStep_ = step;
            obj.currentSeg_ = segIdx;
            obj.currentLocalStep_ = localStep;
            if isfield(obj.gui_, 'step'), obj.gui_.step = step; end
            obj.updateProgramName_();
        end

        function n = nSteps(obj)
            n = obj.nSteps_;
        end
    end

    methods (Access = protected)
        function initGuiState_(obj)
            initGuiState_@plotter.polyscope.ViewerBase(obj);
            obj.gui_.step = obj.currentStep_;
            obj.gui_.stepModeIdx = obj.indexOf_({'step','absmax','absmin','max','min'}, ...
                obj.getOptField_(obj.Opts, 'stepIdx', 'absmax'));
            obj.gui_.respIdx = obj.indexOf_(obj.respTypes_, obj.Opts.respType);
            obj.components_ = obj.componentsForResponse_(obj.Opts.respType);
            obj.gui_.compIdx = obj.indexOf_(obj.components_, obj.Opts.component);
            obj.gui_.locIdx = obj.indexOf_({'auto','section','element'}, obj.responseLocation_());
            obj.gui_.styleIdx = obj.indexOf_({'surface','wireframe'}, obj.Opts.style);
            obj.gui_.scaleModeIdx = obj.indexOf_({'current','global'}, obj.Opts.scaleMode);
            obj.gui_.climIdx = obj.indexOf_({'current','global','range'}, obj.Opts.color.climMode);
            obj.gui_.cmapIdx = obj.indexOf_(obj.colormapNames_(), obj.Opts.polyscope.scalarColorMap);
            obj.gui_.showDiagram = true;
            obj.gui_.showModel = obj.Opts.showModel;
            obj.gui_.showZeroLine = obj.Opts.showZeroLine;
            obj.gui_.showWire = obj.Opts.surf.show;
            obj.gui_.useColormap = obj.Opts.color.useColormap;
            obj.gui_.showColorbar = obj.getOptField_(obj.Opts.cbar, 'show', true);
            obj.gui_.scale = obj.Opts.scale;
            obj.gui_.heightFrac = obj.Opts.heightFrac;
            obj.gui_.faceAlpha = obj.Opts.color.faceAlpha;
            obj.gui_.diagramRadius = obj.getOptField_(obj.Opts.polyscope, 'diagramRadius', 0.0010);
            obj.gui_.modelRadius = obj.getOptField_(obj.Opts.polyscope, 'modelRadius', 0.0008);
            obj.gui_.zeroRadius = obj.getOptField_(obj.Opts.polyscope, 'zeroRadius', 0.00055);
            obj.gui_.solidColor = plotter.polyscope.utils.colorToRgb(obj.Opts.color.solidColor);
            obj.gui_.wireColor = plotter.polyscope.utils.colorToRgb(obj.Opts.color.wireColor);
            obj.gui_.modelColor = plotter.polyscope.utils.colorToRgb(obj.Opts.color.modelColor);
            obj.gui_.zeroColor = plotter.polyscope.utils.colorToRgb(obj.Opts.color.zeroLineColor);
            obj.gui_.playing = obj.getOptField_(obj.Opts.animation, 'play', false);
            obj.gui_.animationMode = obj.gui_.playing;
            obj.gui_.fps = obj.getOptField_(obj.Opts.animation, 'fps', ...
                obj.defaultAnimationFps_(obj.nSteps_));
            obj.gui_.loop = obj.getOptField_(obj.Opts.animation, 'loop', true);
            obj.gui_.pingpong = obj.getOptField_(obj.Opts.animation, 'pingpong', false);
            info = obj.beamInfo_(1, obj.nodeCoords_(1));
            obj.gui_.showHistory = false;
            obj.gui_.historyUseTag = true;
            obj.gui_.historyEleIndex = 1;
            obj.gui_.historyEleTag = 1;
            if ~isempty(info.tags), obj.gui_.historyEleTag = info.tags(1); end
            obj.gui_.historyShowValue = true;
            obj.gui_.historySampleMode = 'absMax';
            obj.initColorbarGuiState_(obj.scalarQuantityName_());
            obj.initSliceGuiState_();
        end

        function configureAnimationRenderLoop_(obj)
            isRunning = isfield(obj.gui_, 'animationMode') && obj.gui_.animationMode && obj.gui_.playing;
            fps = max(1, double(obj.getOptField_(obj.gui_, 'fps', 12)));
            configureAnimationRenderLoop_@plotter.polyscope.ViewerBase(obj, isRunning, fps);
        end
    end

    methods
        function guiCallback_(obj)
            try
                obj.advanceAnimation_();
                GB = plotter.polyscope.GuiBuilder;
                ws = obj.safeWindowSize_();
                panelW = 390;
                GB.begin('Frame Response', [max(0, ws(1) - panelW), 0], [panelW, max(560, ws(2))]);
                cleanup = onCleanup(@() GB.finish());

                needsRebuild = false;
                needsUpdate = false;
                needsStyle = false;
                GB.header('Frame response');

                if GB.collapsingHeader('Response', int32(0))
                    [chg, rebuild] = obj.drawResponseGui_();
                    needsUpdate = needsUpdate || chg;
                    needsRebuild = needsRebuild || rebuild;
                    obj.gui_.showHistory = GB.checkbox('Show response history', obj.gui_.showHistory);
                end
                if GB.collapsingHeader('Diagram', int32(0))
                    [chg, styleOnly] = obj.drawDiagramGui_();
                    needsUpdate = needsUpdate || (chg && ~styleOnly);
                    needsStyle = needsStyle || styleOnly;
                end
                if GB.collapsingHeader('Style', int32(0))
                    [dataChanged, styleChanged] = obj.drawStyleGui_();
                    needsUpdate = needsUpdate || dataChanged;
                    needsStyle = needsStyle || styleChanged;
                end
                if obj.drawSlicePlaneGui_('##frame_resp')
                    obj.registerSlicePlanes_();
                end
                if GB.collapsingHeader('Animation', int32(0))
                    if obj.drawAnimationGui_(), needsUpdate = true; end
                end
                if GB.collapsingHeader('Render quality##frame_resp', int32(0))
                    obj.drawSsaaGui_('##frame_resp');
                end
                if GB.collapsingHeader('Debug', int32(0))
                    polyscope.ImGui.Text(sprintf('Step %d / %d', obj.currentStep_, obj.nSteps_ - 1));
                    polyscope.ImGui.Text(sprintf('Segment %d, local step %d', obj.currentSeg_, obj.currentLocalStep_));
                end
                obj.drawScreenAxesOverlay_();
                obj.updateScreenAxes3D_();
                clear cleanup
                if obj.gui_.showHistory
                    obj.drawResponseHistoryWindow_(ws);
                end

                if needsRebuild
                    obj.invalidateCaches_();
                    obj.setStep(obj.currentStep_, true);
                elseif needsUpdate
                    obj.setStep(obj.currentStep_, false);
                elseif needsStyle
                    obj.applyStyle_();
                    obj.applyVisibility_();
                end
            catch ME
                try, polyscope.ImGui.Text(['GUI error: ' ME.message]); catch, end
            end
        end
    end

    methods (Access = private)
        function [changed, rebuild] = drawResponseGui_(obj)
            GB = plotter.polyscope.GuiBuilder;
            old = obj.gui_;
            obj.gui_.respIdx = min(obj.gui_.respIdx, numel(obj.respTypes_));
            obj.gui_.respIdx = GB.combo('Response##frame_resp', obj.gui_.respIdx, obj.respTypes_);
            obj.Opts.respType = obj.respTypes_{obj.gui_.respIdx};
            responseChanged = obj.gui_.respIdx ~= old.respIdx;
            if responseChanged || isempty(obj.components_)
                obj.components_ = obj.componentsForResponse_(obj.Opts.respType);
                obj.gui_.compIdx = obj.indexOf_(obj.components_, obj.pickDefaultComponent_(obj.Opts.respType));
            end
            obj.gui_.compIdx = min(obj.gui_.compIdx, numel(obj.components_));
            obj.gui_.compIdx = GB.combo('Component##frame_resp', obj.gui_.compIdx, obj.components_);
            obj.Opts.component = obj.components_{obj.gui_.compIdx};
            locs = {'auto','section','element'};
            obj.gui_.locIdx = GB.combo('Location##frame_resp', obj.gui_.locIdx, locs);
            obj.Opts.responseLocation = locs{obj.gui_.locIdx};
            modes = {'step','absmax','absmin','max','min'};
            obj.gui_.stepModeIdx = GB.combo('Step mode##frame_resp', obj.gui_.stepModeIdx, modes);
            if strcmp(modes{obj.gui_.stepModeIdx}, 'step')
                obj.gui_.step = GB.sliderInt('Step##frame_resp', round(obj.gui_.step), 0, max(0, obj.nSteps_ - 1));
                obj.currentStep_ = round(obj.gui_.step);
            elseif obj.gui_.stepModeIdx ~= old.stepModeIdx || responseChanged || ...
                    obj.gui_.compIdx ~= old.compIdx || obj.gui_.locIdx ~= old.locIdx
                obj.currentStep_ = obj.resolveStepArg_(modes{obj.gui_.stepModeIdx});
                obj.gui_.step = obj.currentStep_;
            end
            polyscope.ImGui.ProgressBar((obj.currentStep_ + 1) / max(1, obj.nSteps_), [0, 0], ...
                sprintf('%d / %d', obj.currentStep_, max(0, obj.nSteps_ - 1)));
            dataChanged = obj.guiChanged_(old, {'respIdx','compIdx','locIdx','stepModeIdx'});
            stepChanged = obj.gui_.step ~= old.step;
            changed = dataChanged || stepChanged;
            rebuild = false;
            if dataChanged, obj.invalidateCaches_(); end
        end

        function drawResponseHistoryWindow_(obj, ws)
            w = min(520, max(380, ws(1) * 0.34));
            h = min(390, max(300, ws(2) * 0.36));
            x0 = max(12, ws(1) - 390 - w - 18);
            y0 = max(42, ws(2) - h - 18);
            polyscope.ImGui.SetNextWindowPos([x0, y0], ...
                int32(polyscope.ImGui.get_constant('ImGuiCond_FirstUseEver')));
            polyscope.ImGui.SetNextWindowSize([w, h], ...
                int32(polyscope.ImGui.get_constant('ImGuiCond_FirstUseEver')));
            visible = polyscope.ImGui.Begin('Frame response history');
            cleanup = onCleanup(@() polyscope.ImGui.End()); %#ok<NASGU>
            if ~visible, return; end

            GB = plotter.polyscope.GuiBuilder;
            info = obj.beamInfo_(max(1, obj.currentSeg_), obj.nodeCoords_(max(1, obj.currentSeg_)));
            tags = info.tags(:);
            if isempty(tags)
                polyscope.ImGui.TextDisabled('No frame elements are available.');
                return;
            end
            polyscope.ImGui.Text(sprintf('Selected: %s / %s', ...
                char(string(obj.Opts.respType)), char(string(obj.Opts.component))));
            obj.gui_.historyUseTag = GB.checkbox('Use element tag', obj.gui_.historyUseTag);
            if obj.gui_.historyUseTag
                [changed, val] = polyscope.ImGui.InputInt('Element tag##frame_history', ...
                    int32(round(obj.gui_.historyEleTag)), int32(1), int32(100));
                if changed
                    obj.gui_.historyEleTag = double(val);
                    hit = find(tags == obj.gui_.historyEleTag, 1);
                    if ~isempty(hit), obj.gui_.historyEleIndex = hit; end
                    obj.invalidateHistoryCache_();
                end
            else
                [changed, val] = polyscope.ImGui.InputInt('Element index##frame_history', ...
                    int32(round(obj.gui_.historyEleIndex)), int32(1), int32(10));
                if changed
                    obj.gui_.historyEleIndex = max(1, min(numel(tags), double(val)));
                    obj.gui_.historyEleTag = tags(obj.gui_.historyEleIndex);
                    obj.invalidateHistoryCache_();
                end
            end
            if GB.button('Previous##frame_history')
                obj.gui_.historyEleIndex = max(1, obj.historyElementIndex_(tags) - 1);
                obj.gui_.historyEleTag = tags(obj.gui_.historyEleIndex);
                obj.invalidateHistoryCache_();
            end
            GB.sameLine();
            if GB.button('Next##frame_history')
                obj.gui_.historyEleIndex = min(numel(tags), obj.historyElementIndex_(tags) + 1);
                obj.gui_.historyEleTag = tags(obj.gui_.historyEleIndex);
                obj.invalidateHistoryCache_();
            end
            [sampleChoices, sampleLabel] = obj.historySampleChoices_(info, tags);
            sampleIdx = obj.indexOf_(sampleChoices, obj.gui_.historySampleMode);
            newSampleIdx = GB.combo([sampleLabel '##frame_history'], sampleIdx, sampleChoices);
            if newSampleIdx ~= sampleIdx
                obj.gui_.historySampleMode = sampleChoices{newSampleIdx};
                obj.invalidateHistoryReducedCache_();
            elseif ~strcmp(obj.gui_.historySampleMode, sampleChoices{sampleIdx})
                obj.gui_.historySampleMode = sampleChoices{sampleIdx};
                obj.invalidateHistoryReducedCache_();
            end
            obj.gui_.historyShowValue = GB.checkbox('Show current value', obj.gui_.historyShowValue);

            [x, y] = obj.responseHistorySeries_();
            finite = isfinite(x) & isfinite(y);
            if ~any(finite)
                polyscope.ImGui.TextDisabled('No response values for this element.');
                return;
            end
            xmin = min(x(finite)); xmax = max(x(finite));
            ymin = min(y(finite)); ymax = max(y(finite));
            if xmin == xmax, xmin = xmin - 0.5; xmax = xmax + 0.5; end
            if ymin == ymax, ymin = ymin - max(1, abs(ymin))*0.05; ymax = ymax + max(1, abs(ymax))*0.05; end
            xp = 0.03 * (xmax - xmin); yp = 0.08 * (ymax - ymin);
            ip = polyscope.ImPlot;
            flags = int32(polyscope.ImPlot.get_constant('ImPlotFlags_NoLegend'));
            if ip.BeginPlot('##frame_response_history_plot', [-1, 220], flags)
                ip.SetupAxes('time / step', 'Response');
                ip.SetupAxesLimits(xmin-xp, xmax+xp, ymin-yp, ymax+yp, ...
                    int32(polyscope.ImPlot.get_constant('ImPlotCond_Always')));
                ip.PlotLineXY('response##frame_history_line', x(:), y(:));
                k = obj.currentStep_ + 1;
                if k >= 1 && k <= numel(y) && isfinite(y(k))
                    ip.PlotScatterXY('current##frame_history_current', x(k), y(k));
                end
                ip.EndPlot();
            end
            if obj.gui_.historyShowValue
                k = obj.currentStep_ + 1;
                if k >= 1 && k <= numel(y) && isfinite(y(k))
                    polyscope.ImGui.Text(sprintf('%s / %s / %s | element %g | Response: %.6g', ...
                        char(string(obj.Opts.respType)), char(string(obj.Opts.component)), ...
                        obj.gui_.historySampleMode, obj.gui_.historyEleTag, y(k)));
                end
            end
        end

        function [changed, styleOnly] = drawDiagramGui_(obj)
            GB = plotter.polyscope.GuiBuilder;
            old = obj.gui_;
            obj.gui_.showDiagram = GB.checkbox('Diagram##frame_geom', obj.gui_.showDiagram);
            GB.sameLine();
            obj.gui_.showModel = GB.checkbox('Model##frame_geom', obj.gui_.showModel);
            obj.gui_.showZeroLine = GB.checkbox('Zero line##frame_geom', obj.gui_.showZeroLine);
            GB.sameLine();
            obj.gui_.showWire = GB.checkbox('Wire edges##frame_geom', obj.gui_.showWire);
            styles = {'surface','wireframe'};
            obj.gui_.styleIdx = GB.combo('Style##frame_geom', obj.gui_.styleIdx, styles);
            obj.Opts.style = styles{obj.gui_.styleIdx};
            scales = {'current','global'};
            obj.gui_.scaleModeIdx = GB.combo('Scale mode##frame_geom', obj.gui_.scaleModeIdx, scales);
            obj.Opts.scaleMode = scales{obj.gui_.scaleModeIdx};
            obj.gui_.scale = GB.sliderFloat('Scale##frame_geom', obj.gui_.scale, 0.01, 20);
            obj.gui_.heightFrac = GB.sliderFloat('Height fraction##frame_geom', obj.gui_.heightFrac, 0.005, 0.5);
            if GB.button('Redraw##frame_geom')
                obj.App.polyscopeHandle().request_redraw();
            end
            GB.sameLine();
            if GB.button('Defaults##frame_geom')
                obj.resetPlotDefaults_();
                obj.setStep(obj.currentStep_, true);
            end
            obj.syncOptsFromGui_();
            changed = obj.guiChanged_(old, {'showDiagram','showModel','showZeroLine','showWire', ...
                'styleIdx','scaleModeIdx','scale','heightFrac'});
            styleOnly = changed && ~obj.guiChanged_(old, {'styleIdx','scaleModeIdx','scale','heightFrac'});
        end

        function [dataChanged, styleChanged] = drawStyleGui_(obj)
            GB = plotter.polyscope.GuiBuilder;
            old = obj.gui_;
            cmaps = obj.colormapNames_();
            obj.gui_.cmapIdx = GB.combo('Colormap##frame_style', obj.gui_.cmapIdx, cmaps);
            obj.Opts.polyscope.scalarColorMap = cmaps{obj.gui_.cmapIdx};
            climModes = {'current','global','range'};
            obj.gui_.climIdx = GB.combo('Color limits##frame_style', obj.gui_.climIdx, climModes);
            obj.Opts.color.climMode = climModes{obj.gui_.climIdx};
            obj.gui_.useColormap = GB.checkbox('Use colormap##frame_style', obj.gui_.useColormap);
            obj.Opts.color.useColormap = logical(obj.gui_.useColormap);
            if obj.gui_.useColormap
                obj.drawColorbarGui_('##frame_style', true);
                obj.Opts.cbar.show = logical(obj.gui_.onscreenColorbar);
            end
            [~, obj.gui_.solidColor] = GB.colorEdit3('Solid color##frame_style', obj.gui_.solidColor);
            [~, obj.gui_.wireColor] = GB.colorEdit3('Wire color##frame_style', obj.gui_.wireColor);
            [~, obj.gui_.modelColor] = GB.colorEdit3('Model color##frame_style', obj.gui_.modelColor);
            [~, obj.gui_.zeroColor] = GB.colorEdit3('Zero color##frame_style', obj.gui_.zeroColor);
            obj.gui_.faceAlpha = GB.sliderFloat('Face alpha##frame_style', obj.gui_.faceAlpha, 0, 1);
            obj.gui_.diagramRadius = GB.sliderFloat('Diagram radius##frame_style', obj.gui_.diagramRadius, 0.0001, 0.006);
            obj.gui_.modelRadius = GB.sliderFloat('Model radius##frame_style', obj.gui_.modelRadius, 0.0001, 0.006);
            obj.gui_.zeroRadius = GB.sliderFloat('Zero radius##frame_style', obj.gui_.zeroRadius, 0.0001, 0.006);
            views = obj.viewNames_();
            obj.gui_.viewIdx = GB.combo('View##frame_style', obj.gui_.viewIdx, views);
            if GB.button('Apply view##frame_style')
                obj.Opts.general.view = views{obj.gui_.viewIdx};
                obj.setCameraForPoints_(obj.nodeCoords_(obj.currentSeg_), obj.Opts.general.view);
            end
            obj.syncOptsFromGui_();
            dataChanged = obj.guiChanged_(old, {'cmapIdx','climIdx','useColormap', ...
                'onscreenColorbar','onscreenColorbarLocation','colorbarTitle'});
            styleChanged = obj.guiChanged_(old, {'solidColor','wireColor','modelColor','zeroColor', ...
                'faceAlpha','diagramRadius','modelRadius','zeroRadius','viewIdx'});
            if dataChanged, obj.invalidateCaches_(); end
        end

        function changed = drawAnimationGui_(obj)
            GB = plotter.polyscope.GuiBuilder;
            old = obj.gui_;
            obj.gui_.animationMode = GB.checkbox('Enter animation mode', obj.gui_.animationMode);
            if obj.gui_.animationMode
                if ~old.animationMode
                    % Preserve the registered topology and current segment.
                    obj.gui_.step = obj.currentStep_;
                    obj.animDir_ = 1;
                end
                obj.gui_.scaleModeIdx = obj.indexOf_({'current','global'}, 'global');
                obj.Opts.scaleMode = 'global';
                obj.gui_.climIdx = obj.indexOf_({'current','global','range'}, 'global');
                obj.Opts.color.climMode = 'global';
                if GB.button('Play / pause'), obj.gui_.playing = ~obj.gui_.playing; end
                GB.sameLine();
                if GB.button('Restart')
                    obj.currentStep_ = 0;
                    obj.gui_.step = 0;
                end
                obj.gui_.playing = GB.checkbox('Playing', obj.gui_.playing);
                obj.gui_.fps = GB.sliderFloat('FPS', obj.gui_.fps, 1, 240);
                obj.gui_.loop = GB.checkbox('Loop', obj.gui_.loop);
                GB.sameLine();
                obj.gui_.pingpong = GB.checkbox('Ping-pong', obj.gui_.pingpong);
                obj.gui_.scale = GB.sliderFloat('Scale factor##frame_animation', obj.gui_.scale, 0.01, 20);
                polyscope.ImGui.ProgressBar((obj.currentStep_ + 1) / max(1, obj.nSteps_), [0, 0], ...
                    sprintf('%d / %d', obj.currentStep_, max(0, obj.nSteps_ - 1)));
            else
                obj.gui_.playing = false;
            end
            obj.Opts.animation.play = obj.gui_.playing;
            obj.Opts.animation.fps = obj.gui_.fps;
            obj.Opts.animation.loop = obj.gui_.loop;
            obj.Opts.animation.pingpong = obj.gui_.pingpong;
            obj.Opts.scale = double(obj.gui_.scale);
            % Only reconfigure the render loop when animation state/fps change.
            if obj.guiChanged_(old, {'animationMode','playing','fps'})
                obj.configureAnimationRenderLoop_();
            end
            % FPS/loop/pingpong/playing only affect the animation loop; they do
            % not require a full diagram recompute. Only changes that alter the
            % displayed data need a response update.
            changed = obj.guiChanged_(old, {'animationMode','scaleModeIdx','scale','climIdx'});
        end

        function registerSegment_(obj, segIdx, localStep)
            obj.clear_();
            obj.handles_ = struct();
            obj.meshData_ = struct();
            obj.modelData_ = struct();
            obj.currentSeg_ = segIdx;
            obj.currentLocalStep_ = localStep;
            obj.P0_ = obj.nodeCoords_(segIdx);
            obj.L_ = obj.modelLength_(obj.P0_);
            ps = obj.App.polyscopeHandle();
            data = obj.diagramData_(segIdx, localStep);
            % Register the reference model first so the response diagram is
            % the foreground layer for coplanar 2-D views.
            obj.registerModel_(ps, data);
            obj.registerDiagram_(ps, data);
            obj.applyStyle_();
            obj.applyVisibility_();
        end

        function updateStep_(obj, segIdx, localStep)
            obj.currentSeg_ = segIdx;
            obj.currentLocalStep_ = localStep;
            data = obj.diagramData_(segIdx, localStep);
            needRebuild = false;
            desiredStyle = obj.desiredDiagramStyle_(data);
            if isfield(obj.meshData_, 'style') && ~strcmp(obj.meshData_.style, desiredStyle)
                needRebuild = true;
            end
            if isfield(obj.handles_, 'def_Diagram')
                if strcmp(obj.meshData_.style, 'surface')
                    if size(data.surfacePts, 1) == obj.meshData_.nSurfacePts
                        obj.handles_.def_Diagram.update_vertex_positions(data.surfacePts);
                        qargs = obj.scalarArgs_(data.clim);
                        obj.handles_.def_Diagram.add_vertex_scalar_quantity(obj.scalarQuantityName_(), ...
                            data.surfaceScalars, qargs{:});
                    else
                        needRebuild = true;
                    end
                else
                    if size(data.wirePts, 1) == obj.meshData_.nWirePts
                        obj.handles_.def_Diagram.update_node_positions(data.wirePts);
                        qargs = obj.scalarArgs_(data.clim);
                        obj.handles_.def_Diagram.add_node_scalar_quantity(obj.scalarQuantityName_(), ...
                            data.wireScalars, qargs{:});
                    else
                        needRebuild = true;
                    end
                end
            else
                needRebuild = true;
            end
            if isfield(obj.handles_, 'def_DiagramWire') && size(data.wirePts, 1) == obj.meshData_.nWirePts
                obj.handles_.def_DiagramWire.update_node_positions(data.wirePts);
            elseif strcmp(obj.meshData_.style, 'surface') && obj.Opts.surf.show
                needRebuild = true;
            end
            if needRebuild
                obj.registerSegment_(segIdx, localStep);
                return;
            end
            if isfield(obj.handles_, 'def_ZeroLine') && size(data.zeroPts, 1) == obj.modelData_.nZeroPts
                obj.handles_.def_ZeroLine.update_node_positions(data.zeroPts);
            end
            % Geometry and scalar data changed, but style/visibility did not.
            % Avoid redundant MEX calls on every animation frame.
        end

        function registerDiagram_(obj, ps, data)
            qname = obj.scalarQuantityName_();
            if strcmp(obj.desiredDiagramStyle_(data), 'surface')
                h = ps.register_surface_mesh(obj.structName_('Diagram', 'def'), data.surfacePts, data.surfaceFaces, ...
                    'smooth_shade', false);
                qargs = obj.scalarArgs_(data.clim);
                h.add_vertex_scalar_quantity(qname, data.surfaceScalars, qargs{:});
                obj.meshData_ = struct('style', 'surface', 'nSurfacePts', size(data.surfacePts, 1), ...
                    'nWirePts', size(data.wirePts, 1));
                if ~isempty(data.wirePts)
                    hw = ps.register_curve_network(obj.structName_('DiagramWire', 'def'), data.wirePts, data.wireEdges);
                    obj.handles_.def_DiagramWire = hw;
                end
            else
                h = ps.register_curve_network(obj.structName_('Diagram', 'def'), data.wirePts, data.wireEdges);
                if ~isempty(data.wireScalars)
                    qargs = obj.scalarArgs_(data.clim);
                    h.add_node_scalar_quantity(qname, data.wireScalars, qargs{:});
                end
                obj.meshData_ = struct('style', 'wireframe', 'nSurfacePts', 0, 'nWirePts', size(data.wirePts, 1));
            end
            obj.handles_.def_Diagram = h;
        end

        function registerModel_(obj, ps, data)
            if ~isempty(data.modelPts)
                h = ps.register_curve_network(obj.structName_('Model', 'def'), data.modelPts, data.modelEdges);
                obj.handles_.def_Model = h;
            end
            if ~isempty(data.zeroPts)
                h = ps.register_curve_network(obj.structName_('ZeroLine', 'def'), data.zeroPts, data.zeroEdges);
                obj.handles_.def_ZeroLine = h;
            end
            obj.modelData_.nZeroPts = size(data.zeroPts, 1);
        end

        function applyStyle_(obj)
            if isfield(obj.handles_, 'def_Diagram')
                h = obj.handles_.def_Diagram;
                if strcmp(obj.meshData_.style, 'surface')
                    h.set_color(obj.asRgb_(obj.Opts.color.solidColor));
                    h.set_transparency(obj.Opts.color.faceAlpha);
                    try, h.set_edge_width(0); catch, end
                else
                    h.set_color(obj.asRgb_(obj.Opts.color.wireColor));
                    h.set_radius(obj.Opts.polyscope.diagramRadius, true);
                end
            end
            if isfield(obj.handles_, 'def_DiagramWire')
                obj.handles_.def_DiagramWire.set_color(obj.asRgb_(obj.Opts.color.wireColor));
                obj.handles_.def_DiagramWire.set_radius(obj.Opts.polyscope.diagramRadius * 0.75, true);
            end
            if isfield(obj.handles_, 'def_Model')
                obj.handles_.def_Model.set_color(obj.asRgb_(obj.Opts.color.modelColor));
                obj.handles_.def_Model.set_radius(obj.Opts.polyscope.modelRadius, true);
            end
            if isfield(obj.handles_, 'def_ZeroLine')
                obj.handles_.def_ZeroLine.set_color(obj.asRgb_(obj.Opts.color.zeroLineColor));
                obj.handles_.def_ZeroLine.set_radius(obj.Opts.polyscope.zeroRadius, true);
            end
            try, obj.App.polyscopeHandle().request_redraw(); catch, end
        end

        function applyVisibility_(obj)
            obj.setEnabled_('def_Diagram', obj.gui_.showDiagram);
            showDiagramWire = obj.gui_.showDiagram && obj.Opts.surf.show && ...
                isfield(obj.meshData_, 'style') && strcmp(obj.meshData_.style, 'surface');
            obj.setEnabled_('def_DiagramWire', showDiagramWire);
            obj.setEnabled_('def_Model', obj.Opts.showModel && obj.Opts.showBeamModel);
            obj.setEnabled_('def_ZeroLine', obj.Opts.showZeroLine);
        end

        function syncOptsFromGui_(obj)
            obj.Opts.showModel = logical(obj.gui_.showModel);
            obj.Opts.showBeamModel = logical(obj.gui_.showModel);
            obj.Opts.showZeroLine = logical(obj.gui_.showZeroLine);
            obj.Opts.surf.show = logical(obj.gui_.showWire);
            obj.Opts.color.useColormap = logical(obj.gui_.useColormap);
            obj.Opts.cbar.show = logical(obj.getOptField_(obj.gui_, 'onscreenColorbar', false));
            obj.Opts.polyscope.onscreenColorbar = logical(obj.getOptField_(obj.gui_, 'onscreenColorbar', false));
            obj.Opts.scale = double(obj.gui_.scale);
            obj.Opts.heightFrac = double(obj.gui_.heightFrac);
            obj.Opts.color.faceAlpha = double(obj.gui_.faceAlpha);
            obj.Opts.color.solidColor = obj.asRgb_(obj.gui_.solidColor);
            obj.Opts.color.wireColor = obj.asRgb_(obj.gui_.wireColor);
            obj.Opts.color.modelColor = obj.asRgb_(obj.gui_.modelColor);
            obj.Opts.color.zeroLineColor = obj.asRgb_(obj.gui_.zeroColor);
            obj.Opts.polyscope.diagramRadius = double(obj.gui_.diagramRadius);
            obj.Opts.polyscope.modelRadius = double(obj.gui_.modelRadius);
            obj.Opts.polyscope.zeroRadius = double(obj.gui_.zeroRadius);
        end

        function resetPlotDefaults_(obj)
            old = obj.Opts;
            opts = obj.initialOpts_;
            opts.respType = old.respType;
            opts.component = old.component;
            opts.responseLocation = old.responseLocation;
            opts.stepIdx = obj.currentStep_;
            opts.general.view = old.general.view;
            opts.polyscope.backend = old.polyscope.backend;
            opts.polyscope.maximize = old.polyscope.maximize;
            opts.polyscope.windowSize = old.polyscope.windowSize;
            opts.polyscope.programName = obj.getOptField_(old.polyscope, 'programName', '');
            opts.animation = old.animation;
            obj.Opts = opts;
            obj.initGuiState_();
            obj.invalidateCaches_();
        end

        function data = diagramData_(obj, segIdx, localStep)
            P = obj.nodeCoords_(segIdx);
            if isfield(obj.beamInfoCache_, 'segIdx') && obj.beamInfoCache_.segIdx == segIdx
                info = obj.beamInfoCache_.info;
            else
                info = obj.beamInfo_(segIdx, P);
                obj.beamInfoCache_ = struct('segIdx', segIdx, 'info', info);
            end
            vals = obj.respPerEle_(segIdx, localStep, info);
            locs = obj.secLocs_(segIdx, localStep, info, vals);
            scale = obj.diagramScale_(segIdx, localStep, vals);
            [basePts, tipPts, valVec, eleStart, eleEnd] = obj.diagramSamples_(P, info, vals, locs, scale);
            [surfacePts, surfaceFaces, surfaceScalars] = obj.surfaceMesh_(basePts, tipPts, valVec, eleStart, eleEnd);
            [wirePts, wireEdges, wireScalars] = obj.wireNetwork_(basePts, tipPts, valVec, eleStart, eleEnd);
            data = struct();
            data.basePts = basePts;
            data.tipPts = tipPts;
            data.vals = valVec;
            data.surfacePts = surfacePts;
            data.surfaceFaces = surfaceFaces;
            data.surfaceScalars = surfaceScalars;
            data.surfaceScalars(~isfinite(data.surfaceScalars)) = 0;
            data.wirePts = wirePts;
            data.wireEdges = wireEdges;
            data.wireScalars = wireScalars;
            data.wireScalars(~isfinite(data.wireScalars)) = 0;
            data.clim = obj.colorLimits_(valVec);
            [data.modelPts, data.modelEdges] = obj.modelWireframe_(segIdx);
            [data.zeroPts, data.zeroEdges] = obj.zeroNetwork_(basePts, eleStart, eleEnd);
        end

        function [pts, edges] = modelWireframe_(obj, segIdx)
            % Build the complete model as a curve network.  Passing every
            % model node with only beam edges makes unreferenced continuum
            % nodes appear as a point cloud in Polyscope.
            pts = zeros(0, 3);
            edges = zeros(0, 2);
            mi = obj.ModelInfo(min(max(1, segIdx), numel(obj.ModelInfo)));
            P = plotter.polyscope.ModelAdapter.nodeCoords(mi);

            lineNames = plotter.polyscope.ModelAdapter.lineFamilyNames([]);
            for k = 1:numel(lineNames)
                e = plotter.polyscope.ModelAdapter.lineEdges(mi, lineNames{k});
                [pts, edges] = obj.appendNetwork_(pts, edges, P, e);
            end

            surfaceNames = plotter.polyscope.ModelAdapter.surfaceFamilyNames([]);
            for k = 1:numel(surfaceNames)
                [~, ~, ~, edgePoints] = ...
                    plotter.polyscope.ModelAdapter.surfaceMesh(mi, surfaceNames{k});
                [p, e] = plotter.polyscope.ModelAdapter.edgePointsToCurveNetwork(edgePoints);
                [pts, edges] = obj.appendNetwork_(pts, edges, p, e);
            end

            volumeNames = plotter.polyscope.ModelAdapter.volumeFamilyNames([]);
            for k = 1:numel(volumeNames)
                [~, ~, ~, ~, ~, edgePoints] = ...
                    plotter.polyscope.ModelAdapter.volumeMesh(mi, volumeNames{k}, true);
                [p, e] = plotter.polyscope.ModelAdapter.edgePointsToCurveNetwork(edgePoints);
                [pts, edges] = obj.appendNetwork_(pts, edges, p, e);
            end

            % Some ODBs store the continuum part in one mixed
            % Elements.Families.Unstructured block.
            fam = plotter.polyscope.ModelAdapter.families(mi);
            if isfield(fam, 'Unstructured')
                U = fam.Unstructured;
                if isstruct(U) && isfield(U, 'Cells') && isfield(U, 'CellTypes') && ...
                        ~isempty(U.Cells)
                    out = plotter.utils.VTKElementTriangulator.triangulate( ...
                        P, double(U.CellTypes), double(U.Cells));
                    if isstruct(out) && isfield(out, 'EdgePoints')
                        [p, e] = plotter.polyscope.ModelAdapter.edgePointsToCurveNetwork(out.EdgePoints);
                        [pts, edges] = obj.appendNetwork_(pts, edges, p, e);
                    end
                end
            end
        end

        function [pts, edges] = appendNetwork_(~, pts, edges, newPts, newEdges)
            if isempty(newPts) || isempty(newEdges), return; end
            newEdges = double(newEdges);
            valid = all(isfinite(newEdges), 2) & all(newEdges >= 1, 2) & ...
                all(newEdges <= size(newPts, 1), 2);
            newEdges = round(newEdges(valid, :));
            if isempty(newEdges), return; end
            used = unique(newEdges(:), 'stable');
            remap = zeros(size(newPts, 1), 1);
            remap(used) = 1:numel(used);
            offset = size(pts, 1);
            pts = [pts; newPts(used, :)]; %#ok<AGROW>
            edges = [edges; remap(newEdges) + offset]; %#ok<AGROW>
        end

        function [basePts, tipPts, vals, eleStart, eleEnd] = diagramSamples_(obj, P, info, valPerEle, locPerEle, scale)
            nEle = size(info.conn, 1);
            nPerEle = zeros(nEle, 1);
            eleStart = zeros(nEle, 1);
            eleEnd = zeros(nEle, 1);
            total = 0;
            for e = 1:nEle
                [~, ~, n] = obj.alignDiagramSamples_(valPerEle{e}, locPerEle{e});
                nPerEle(e) = n;
                total = total + n;
            end
            basePts = zeros(total, 3);
            tipPts = zeros(total, 3);
            vals = zeros(total, 1);
            row = 1;
            for e = 1:nEle
                n = nPerEle(e);
                if n == 0, continue; end
                rows = row:row+n-1;
                [v, s] = obj.alignDiagramSamples_(valPerEle{e}, locPerEle{e});
                p1 = P(info.conn(e,1), :);
                p2 = P(info.conn(e,2), :);
                basePts(rows, :) = p1 + s(:) .* (p2 - p1);
                tipPts(rows, :) = basePts(rows, :) + scale .* v(:) .* info.plotAxis(e, :);
                vals(rows) = v(:);
                eleStart(e) = row;
                eleEnd(e) = row + n - 1;
                row = row + n;
            end
        end

        function [v, s, n] = alignDiagramSamples_(~, vals, locs)
            v = double(vals(:));
            s = double(locs(:));
            v = v(isfinite(v));
            s = s(isfinite(s));
            if isempty(v)
                v = 0;
            end
            if isempty(s)
                s = linspace(0, 1, max(2, numel(v))).';
            end
            if numel(v) == 1 && numel(s) > 1
                v = repmat(v, numel(s), 1);
            elseif numel(s) == 1 && numel(v) > 1
                s = linspace(0, 1, numel(v)).';
            elseif numel(v) ~= numel(s)
                n0 = max(2, max(numel(v), numel(s)));
                xV = linspace(0, 1, numel(v));
                xS = linspace(0, 1, numel(s));
                x = linspace(0, 1, n0).';
                v = interp1(xV(:), v(:), x, 'linear', 'extrap');
                s = interp1(xS(:), s(:), x, 'linear', 'extrap');
            end
            if numel(v) == 1
                v = [v; v];
                s = [0; 1];
            end
            n = min(numel(v), numel(s));
            v = v(1:n);
            s = s(1:n);
        end

        function [pts, faces, scalars] = surfaceMesh_(obj, basePts, tipPts, vals, eleStart, eleEnd)
            splitAtZero = ~obj.Opts.performance.fastMode;
            pts = zeros(0, 3);
            faces = zeros(0, 3);
            scalars = zeros(0, 1);
            for e = 1:numel(eleStart)
                r0 = eleStart(e); r1 = eleEnd(e);
                if r0 == 0 || r1 <= r0, continue; end
                b = basePts(r0:r1, :); t = tipPts(r0:r1, :); v = vals(r0:r1);
                for k = 1:size(b,1)-1
                    v0 = v(k); v1 = v(k+1);
                    if ~splitAtZero || v0 * v1 >= 0
                        ids = size(pts,1) + (1:4);
                        pts = [pts; b(k,:); t(k,:); b(k+1,:); t(k+1,:)]; %#ok<AGROW>
                        scalars = [scalars; v0; v0; v1; v1]; %#ok<AGROW>
                        faces = [faces; ids([1 2 3]); ids([2 4 3])]; %#ok<AGROW>
                    else
                        tc = v0 / (v0 - v1);
                        z = b(k,:) + tc * (b(k+1,:) - b(k,:));
                        ids = size(pts,1) + (1:6);
                        pts = [pts; b(k,:); t(k,:); z; b(k+1,:); t(k+1,:); z]; %#ok<AGROW>
                        scalars = [scalars; v0; v0; 0; v1; v1; 0]; %#ok<AGROW>
                        faces = [faces; ids([1 2 3]); ids([4 5 6])]; %#ok<AGROW>
                    end
                end
            end
        end

        function [pts, edges, scalars] = wireNetwork_(~, basePts, tipPts, vals, eleStart, eleEnd)
            pts = zeros(0, 3);
            edges = zeros(0, 2);
            scalars = zeros(0, 1);
            for e = 1:numel(eleStart)
                r0 = eleStart(e); r1 = eleEnd(e);
                if r0 == 0 || r1 < r0, continue; end
                b = basePts(r0:r1,:); t = tipPts(r0:r1,:); v = vals(r0:r1); n = size(b,1);
                i0 = size(pts,1);
                pts = [pts; b(1,:); t; b(end,:)]; %#ok<AGROW>
                edges = [edges; i0 + [(1:n+1).', (2:n+2).']]; %#ok<AGROW>
                scalars = [scalars; 0; v; 0]; %#ok<AGROW>
                j0 = size(pts,1);
                pts = [pts; b; t]; %#ok<AGROW>
                edges = [edges; j0 + [(1:n).', (n+1:2*n).']]; %#ok<AGROW>
                scalars = [scalars; v; v]; %#ok<AGROW>
            end
        end

        function [pts, edges] = zeroNetwork_(~, basePts, eleStart, eleEnd)
            pts = zeros(0, 3);
            edges = zeros(0, 2);
            for e = 1:numel(eleStart)
                r0 = eleStart(e); r1 = eleEnd(e);
                if r0 == 0 || r1 < r0, continue; end
                block = basePts(r0:r1,:);
                base = size(pts, 1);
                pts = [pts; block]; %#ok<AGROW>
                n = size(block, 1);
                if n > 1
                    edges = [edges; base + [(1:n-1).', (2:n).']]; %#ok<AGROW>
                end
            end
        end

        function info = beamInfo_(obj, segIdx, P)
            info = struct('conn', zeros(0,2), 'plotAxis', zeros(0,3), 'tags', zeros(0,1));
            fam = obj.families_(segIdx);
            if ~isfield(fam, 'Beam'), return; end
            B = fam.Beam;
            if ~isfield(B, 'Cells') || isempty(B.Cells), return; end
            cells = double(B.Cells);
            if isvector(cells), cells = reshape(cells, 1, []); end
            if size(cells,2) < 2, return; end
            conn = obj.remapBeamConn_(segIdx, round(cells(:, end-1:end)), size(P, 1));
            valid = all(isfinite(conn),2) & all(conn >= 1,2) & all(conn <= size(P,1),2);
            conn = conn(valid,:);
            if isempty(conn), return; end
            if isfield(B, 'Tags') && ~isempty(B.Tags)
                tags = obj.trimVectorLength_(double(B.Tags(:)), size(cells,1));
                tags = tags(valid);
            else
                tags = find(valid);
            end
            info.conn = conn;
            info.tags = tags(:);
            [axisField, axisSign] = obj.resolvePlotAxisSpec_();
            is2D = obj.is2DPoints_(P);
            ax = zeros(size(conn,1), 3);
            if isfield(B, axisField) && ~isempty(B.(axisField))
                raw = obj.trimAxisRows_(double(B.(axisField)), size(cells,1));
                raw = raw(valid, :);
                ax(1:size(raw,1), :) = axisSign * raw(:,1:3);
            end
            for e = 1:size(conn,1)
                if is2D, ax(e,3) = 0; end
                if norm(ax(e,:)) < 1e-12
                    d = P(conn(e,2), :) - P(conn(e,1), :);
                    dn = norm(d);
                    if dn < 1e-12, d = [1 0 0]; else, d = d / dn; end
                    up = [0 0 1];
                    if abs(dot(d, up)) > 0.99, up = [0 1 0]; end
                    if strcmpi(axisField, 'ZAxis')
                        a = cross(d, cross(d, up));
                    else
                        a = cross(d, up);
                    end
                    if norm(a) < 1e-12, a = [0 1 0]; end
                    ax(e,:) = axisSign * a / norm(a);
                else
                    ax(e,:) = ax(e,:) / norm(ax(e,:));
                end
            end
            info.plotAxis = ax;
        end

        function perEle = respPerEle_(obj, segIdx, localStep, info)
            nEle = size(info.conn, 1);
            perEle = repmat({0}, nEle, 1);
            rt = obj.normalizeRespType_(segIdx, obj.Opts.respType);
            A = obj.getRespData_(segIdx, rt);
            if isempty(A), return; end
            si = min(localStep, size(A, 1));
            dofs = obj.getRespDofs_(segIdx, rt);
            ci = obj.componentIndex_(rt, obj.Opts.component, dofs);
            rows = obj.respRowsForBeamInfo_(segIdx, rt, localStep, info, size(A,2));
            nd = ndims(A);
            if nd == 2
                D = double(A(si,:)).';
                for e = 1:nEle
                    r = rows(e);
                    if r >= 1 && r <= numel(D), perEle{e} = D(r); end
                end
            elseif nd == 3
                D = squeeze(double(A(si,:,:)));
                if isvector(D), D = D(:).'; end
                pair = obj.componentEndPair_(rt, obj.Opts.component, dofs, size(D,2));
                for e = 1:nEle
                    r = rows(e);
                    if r < 1 || r > size(D,1), continue; end
                    if numel(pair) == 2 && all(pair > 0) && all(pair <= size(D,2))
                        perEle{e} = D(r, pair(:)).';
                    elseif ci > 0 && ci <= size(D,2)
                        perEle{e} = D(r, ci);
                    end
                end
            elseif nd == 4
                D = double(A(si,:,:,:));
                for e = 1:nEle
                    r = rows(e);
                    if r < 1 || r > size(D,2), continue; end
                    sec = squeeze(D(1,r,:,:));
                    if isvector(sec), sec = sec(:); end
                    if ci > 0 && ci <= size(sec,2)
                        vv = sec(:,ci);
                        perEle{e} = vv(isfinite(vv));
                    end
                end
            end
            for e = 1:nEle
                if isempty(perEle{e}), perEle{e} = 0; end
            end
        end

        function perEle = secLocs_(obj, segIdx, localStep, info, valPerEle)
            nEle = size(info.conn, 1);
            perEle = cell(nEle, 1);
            rt = obj.normalizeRespType_(segIdx, obj.Opts.respType);
            useSection = obj.usesRecordedSectionLocs_(rt);
            L = [];
            if useSection, L = obj.getRespData_(segIdx, 'sectionLocs'); end
            for e = 1:nEle
                n = max(2, numel(valPerEle{e}));
                perEle{e} = linspace(0, 1, n).';
            end
            if isempty(L), return; end
            si = min(localStep, size(L,1));
            if ndims(L) == 4
                D = squeeze(double(L(si,:,:,1)));
                if size(D, 1) ~= nEle && size(D, 2) == nEle
                    D = D.';
                elseif isvector(D) && nEle == 1
                    D = reshape(D, 1, []);
                end
            elseif ndims(L) == 3
                D = squeeze(double(L(si,:,:)));
                if size(D, 1) ~= nEle && size(D, 2) == nEle
                    D = D.';
                elseif isvector(D) && nEle == 1
                    D = reshape(D, 1, []);
                end
            elseif ismatrix(L)
                D = double(L);
            else
                return;
            end
            if isvector(D), D = D(:).'; end
            rows = obj.respRowsForBeamInfo_(segIdx, 'sectionLocs', localStep, info, size(D,1));
            for e = 1:nEle
                r = rows(e);
                if r < 1 || r > size(D,1), continue; end
                vv = squeeze(D(r,:)).';
                vv = vv(isfinite(vv));
                if numel(vv) == numel(valPerEle{e})
                    perEle{e} = vv(:);
                end
            end
        end

        function scale = diagramScale_(obj, segIdx, localStep, valPerEle)
            if strcmpi(char(string(obj.Opts.scaleMode)), 'global')
                key = sprintf('%s|scale=%0.12g|height=%0.12g', obj.responseKey_(), ...
                    double(obj.Opts.scale), double(obj.Opts.heightFrac));
                scale = obj.cachedRange_('frameScale', key, @() obj.computeGlobalDiagramScale_());
                return;
            end
            vals = obj.flattenCell_(valPerEle);
            maxAbs = max(abs(vals(isfinite(vals))), [], 'omitnan');
            if isempty(maxAbs) || ~isfinite(maxAbs) || maxAbs <= 0, maxAbs = 1; end
            scale = obj.Opts.heightFrac * obj.L_ / maxAbs * obj.Opts.scale;
        end

        function scale = computeGlobalDiagramScale_(obj)
            stats = obj.responseStats_();
            maxAbs = stats.globalMaxAbs;
            if isempty(maxAbs) || ~isfinite(maxAbs) || maxAbs <= 0, maxAbs = 1; end
            scale = obj.Opts.heightFrac * obj.L_ / maxAbs * obj.Opts.scale;
        end

        function clim = colorLimits_(obj, vals)
            if ~obj.Opts.color.useColormap
                clim = [];
                return;
            end
            if isfield(obj.Opts.color, 'clim') && numel(obj.Opts.color.clim) == 2
                clim = double(obj.Opts.color.clim(:).');
                return;
            end
            mode = lower(char(string(obj.Opts.color.climMode)));
            if strcmp(mode, 'global')
                clim = obj.cachedRange_('frameClim', obj.responseKey_(), @() obj.computeGlobalClim_());
            else
                clim = obj.rangeFromVals_(vals);
            end
        end

        function clim = computeGlobalClim_(obj)
            stats = obj.responseStats_();
            clim = [stats.globalMin, stats.globalMax];
            if any(~isfinite(clim))
                clim = [-1, 1];
            elseif clim(1) == clim(2)
                d = max(1, abs(clim(1))) * 1e-9;
                clim = clim + [-d, d];
            end
        end

        function args = scalarArgs_(obj, clim)
            if ~obj.Opts.color.useColormap
                args = {'enabled', false};
                return;
            end
            args = {'enabled', logical(obj.Opts.color.useColormap), ...
                'cmap', char(string(obj.Opts.polyscope.scalarColorMap))};
            if ~isempty(clim) && all(isfinite(clim))
                args = [args, {'map_range', double(clim(:).')}];
            end
            if obj.getOptField_(obj.Opts.polyscope, 'onscreenColorbar', false)
                cb = obj.colorbarArgs_();
                if ~isempty(cb), args = [args, cb]; end
            end
        end

        function style = desiredDiagramStyle_(obj, data)
            if strcmpi(char(string(obj.Opts.style)), 'surface') && ~isempty(data.surfacePts)
                style = 'surface';
            else
                style = 'wireframe';
            end
        end

        function advanceAnimation_(obj)
            if ~isfield(obj.gui_, 'animationMode') || ~obj.gui_.animationMode || ~obj.gui_.playing
                return;
            end
            nextStep = obj.currentStep_ + obj.animDir_;
            if nextStep >= obj.nSteps_
                if obj.gui_.pingpong
                    obj.animDir_ = -1;
                    nextStep = max(0, obj.nSteps_ - 2);
                elseif obj.gui_.loop
                    nextStep = 0;
                else
                    nextStep = obj.nSteps_ - 1;
                    obj.gui_.playing = false;
                end
            elseif nextStep < 0
                if obj.gui_.pingpong
                    obj.animDir_ = 1;
                    nextStep = min(obj.nSteps_ - 1, 1);
                elseif obj.gui_.loop
                    nextStep = obj.nSteps_ - 1;
                else
                    nextStep = 0;
                    obj.gui_.playing = false;
                end
            end
            obj.setStep(nextStep, false);
        end

        function buildStepIndex_(obj)
            obj.segStepCounts_ = zeros(1, numel(obj.FrameResp));
            for s = 1:numel(obj.FrameResp)
                obj.segStepCounts_(s) = obj.countSegSteps_(s);
            end
            obj.segOffsets_ = [0, cumsum(obj.segStepCounts_(1:end-1))];
            obj.nSteps_ = max(1, sum(obj.segStepCounts_));
        end

        function n = countSegSteps_(obj, segIdx)
            fr = obj.FrameResp(segIdx);
            if isfield(fr, 'time') && ~isempty(fr.time), n = numel(fr.time); return; end
            n = 1;
            for fn = fieldnames(fr).'
                A = obj.entryData_(fr.(fn{1}));
                if isnumeric(A) && ~isempty(A) && ndims(A) >= 2
                    n = size(A,1);
                    return;
                end
            end
        end

        function [segIdx, localStep] = resolveGlobalStep_(obj, step)
            step = max(0, min(obj.nSteps_ - 1, round(double(step))));
            segIdx = find(obj.segOffsets_ + obj.segStepCounts_ > step, 1, 'first');
            if isempty(segIdx), segIdx = numel(obj.segStepCounts_); end
            localStep = step - obj.segOffsets_(segIdx) + 1;
        end

        function step = resolveStepArg_(obj, arg)
            key = lower(strtrim(char(string(arg))));
            num = str2double(key);
            if isfinite(num)
                step = max(0, min(obj.nSteps_ - 1, round(num)));
                return;
            end
            switch key
                case {'absmax','abs_max','stepabsmax'}
                    step = obj.extremeStep_('absmax');
                case {'absmin','abs_min','stepabsmin'}
                    step = obj.extremeStep_('absmin');
                case {'max','stepmax'}
                    step = obj.extremeStep_('max');
                case {'min','stepmin'}
                    step = obj.extremeStep_('min');
                otherwise
                    step = 0;
            end
        end

        function step = extremeStep_(obj, mode)
            key = matlab.lang.makeValidName([obj.responseKey_() '|' mode]);
            if isfield(obj.extremeStepCache_, key)
                step = obj.extremeStepCache_.(key);
                return;
            end
            stats = obj.responseStats_();
            switch mode
                case {'absmax','absmin'}, vals = stats.stepMaxAbs;
                case 'max', vals = stats.stepMax;
                case 'min', vals = stats.stepMin;
            end
            if all(~isfinite(vals)), step = 0;
            elseif strcmp(mode, 'min') || strcmp(mode, 'absmin')
                [~, idx] = min(vals);
                step = idx - 1;
            else
                [~, idx] = max(vals);
                step = idx - 1;
            end
            obj.extremeStepCache_.(key) = step;
        end

        function stats = responseStats_(obj)
            % Vectorized statistics avoid a MATLAB loop over every time step.
            key = matlab.lang.makeValidName(obj.responseKey_());
            if isfield(obj.responseStatsCache_, key)
                stats = obj.responseStatsCache_.(key);
                return;
            end
            stepMaxAbs = NaN(obj.nSteps_, 1);
            stepMax = NaN(obj.nSteps_, 1);
            stepMin = NaN(obj.nSteps_, 1);
            globalMin = Inf;
            globalMax = -Inf;
            globalMaxAbs = 0;
            for s = 1:numel(obj.FrameResp)
                A = obj.selectedResponseArray_(s);
                if isempty(A), continue; end
                n = min(obj.segStepCounts_(s), size(A, 1));
                B = reshape(double(A(1:n,:,:,:)), n, []);
                B(~isfinite(B)) = NaN;
                rows = obj.segOffsets_(s) + (1:n);
                stepMaxAbs(rows) = max(abs(B), [], 2, 'omitnan');
                stepMax(rows) = max(B, [], 2, 'omitnan');
                stepMin(rows) = min(B, [], 2, 'omitnan');
                lo = min(B, [], 'all', 'omitnan');
                hi = max(B, [], 'all', 'omitnan');
                ma = max(abs(B), [], 'all', 'omitnan');
                if isfinite(lo), globalMin = min(globalMin, lo); end
                if isfinite(hi), globalMax = max(globalMax, hi); end
                if isfinite(ma), globalMaxAbs = max(globalMaxAbs, ma); end
            end
            if ~isfinite(globalMin), globalMin = NaN; end
            if ~isfinite(globalMax), globalMax = NaN; end
            stats = struct('stepMaxAbs', stepMaxAbs, 'stepMax', stepMax, ...
                'stepMin', stepMin, 'globalMin', globalMin, ...
                'globalMax', globalMax, 'globalMaxAbs', globalMaxAbs);
            obj.responseStatsCache_.(key) = stats;
        end

        function A = selectedResponseArray_(obj, segIdx)
            rt = obj.normalizeRespType_(segIdx, obj.Opts.respType);
            A = obj.getRespData_(segIdx, rt);
            if isempty(A), return; end
            dofs = obj.getRespDofs_(segIdx, rt);
            ci = obj.componentIndex_(rt, obj.Opts.component, dofs);
            if ndims(A) == 3
                pair = obj.componentEndPair_(rt, obj.Opts.component, dofs, size(A, 3));
                if numel(pair) == 2 && all(pair > 0) && all(pair <= size(A, 3))
                    A = A(:, :, pair);
                elseif ci > 0 && ci <= size(A, 3)
                    A = A(:, :, ci);
                end
            elseif ndims(A) >= 4 && ci > 0 && ci <= size(A, 4)
                A = A(:, :, :, ci);
            end
        end

        function names = collectResponseTypes_(obj)
            fr = obj.FrameResp(1);
            skip = {'odbtag','eletype','time','eletags','sectionlocs'};
            names = {};
            for fn = fieldnames(fr).'
                if ismember(lower(fn{1}), skip), continue; end
                v = fr.(fn{1});
                if isnumeric(v) || isstruct(v), names{end+1} = fn{1}; end %#ok<AGROW>
            end
            preferred = {'sectionForces','sectionDeformations','basicForces', ...
                'basicDeformations','localForces','plasticDeformation'};
            names = [preferred(ismember(lower(preferred), lower(names))), ...
                names(~ismember(lower(names), lower(preferred)))];
            names = unique(names, 'stable');
        end

        function comps = componentsForResponse_(obj, rt)
            rt = char(string(rt));
            switch lower(rt)
                case {'sectionforces','sectiondeformations'}
                    comps = {'N','MZ','VY','MY','VZ','T'};
                case {'basicforces','basicdeformations','plasticdeformation'}
                    comps = {'N','MZ','MY','T'};
                case 'localforces'
                    comps = {'FX','FY','FZ','MX','MY','MZ','FX1','FY1','FZ1','MX1','MY1','MZ1','FX2','FY2','FZ2','MX2','MY2','MZ2'};
                otherwise
                    dofs = obj.getRespDofs_(1, rt);
                    if isempty(dofs), comps = {'value'}; else, comps = cellstr(string(dofs)); end
            end
            dofs = obj.getRespDofs_(1, rt);
            if ~isempty(dofs)
                comps = obj.mergeComponents_(comps, obj.expandEndPairComponents_(dofs));
            end
        end

        function c = pickDefaultComponent_(~, rt)
            switch lower(char(string(rt)))
                case {'sectionforces','sectiondeformations','basicforces','basicdeformations'}
                    c = 'MZ';
                case 'localforces'
                    c = 'MZ';
                otherwise
                    c = 'value';
            end
        end

        function A = getRespData_(obj, segIdx, rt)
            A = [];
            fr = obj.FrameResp(segIdx);
            rt = obj.normalizeRespType_(segIdx, rt);
            if ~isfield(fr, rt), return; end
            A = obj.entryData_(fr.(rt));
        end

        function A = entryData_(obj, entry)
            A = [];
            if isnumeric(entry), A = double(entry); return; end
            if isstruct(entry)
                if isfield(entry, 'data'), A = double(entry.data); return; end
                dofs = obj.entryDofs_(entry);
                if isempty(dofs), return; end
                parts = cell(1, numel(dofs));
                refSize = [];
                for i = 1:numel(dofs)
                    if isfield(entry, dofs{i}) && isnumeric(entry.(dofs{i}))
                        parts{i} = double(entry.(dofs{i}));
                        if isempty(refSize), refSize = size(parts{i}); end
                    end
                end
                if isempty(refSize), return; end
                for i = 1:numel(parts)
                    if isempty(parts{i})
                        parts{i} = NaN(refSize);
                    end
                end
                A = cat(numel(refSize) + 1, parts{:});
            end
        end

        function dofs = getRespDofs_(obj, segIdx, rt)
            dofs = {};
            fr = obj.FrameResp(segIdx);
            rt = obj.normalizeRespType_(segIdx, rt);
            if isfield(fr, rt) && isstruct(fr.(rt))
                dofs = obj.entryDofs_(fr.(rt));
            end
        end

        function rt = normalizeRespType_(obj, segIdx, rt)
            rt = char(string(rt));
            fr = obj.FrameResp(segIdx);
            if isfield(fr, rt), return; end
            fn = fieldnames(fr);
            idx = find(strcmpi(fn, rt), 1);
            if ~isempty(idx), rt = fn{idx}; end
        end

        function ci = componentIndex_(~, rt, comp, dofs)
            comp = upper(strtrim(char(string(comp))));
            for i = 1:numel(dofs)
                if strcmpi(dofs{i}, comp), ci = i; return; end
            end
            maps.sectionForces = {'N','MZ','VY','MY','VZ','T'};
            maps.sectionDeformations = maps.sectionForces;
            maps.basicForces = {'N','MZ','MY','T'};
            maps.basicDeformations = maps.basicForces;
            maps.plasticDeformation = maps.basicForces;
            maps.localForces = {'FX1','FY1','FZ1','MX1','MY1','MZ1','FX2','FY2','FZ2','MX2','MY2','MZ2'};
            fields = fieldnames(maps);
            hit = fields(strcmpi(fields, char(string(rt))));
            if ~isempty(hit)
                idx = find(strcmpi(maps.(hit{1}), comp), 1);
                if ~isempty(idx), ci = idx; return; end
            end
            n = str2double(comp);
            if isfinite(n), ci = max(1, round(n));
            elseif numel(dofs) == 1 || strcmpi(comp, 'value'), ci = 1;
            else, ci = 0; end
        end

        function pair = componentEndPair_(~, rt, comp, dofs, nComp)
            pair = [];
            base = upper(strtrim(char(string(comp))));
            names = upper(strtrim(cellstr(string(dofs))));
            i1 = find(strcmp(names, [base '1']) | strcmp(names, [base 'I']), 1);
            i2 = find(strcmp(names, [base '2']) | strcmp(names, [base 'J']), 1);
            if ~isempty(i1) && ~isempty(i2), pair = [i1 i2]; return; end
            if strcmpi(char(string(rt)), 'localForces')
                if nComp <= 6
                    map = struct('FX',[1 4], 'FY',[2 5], 'MZ',[3 6]);
                else
                    map = struct('FX',[1 7], 'FY',[2 8], 'FZ',[3 9], ...
                        'MX',[4 10], 'MY',[5 11], 'MZ',[6 12]);
                end
                if isfield(map, base), pair = map.(base); end
            end
        end

        function dofs = entryDofs_(obj, entry)
            dofs = {};
            if ~isstruct(entry), return; end
            if isfield(entry, 'dofs') && ~isempty(entry.dofs)
                dofs = obj.normalizeDofs_(entry.dofs);
                return;
            end
            if isfield(entry, 'data'), return; end
            names = fieldnames(entry).';
            skip = {'data','dofs','eletags','nodetags','tags','time','sectionlocs', ...
                'interpolatepoints','interpolatedisp','interpolatecells','interpolatecoords'};
            names = names(~ismember(lower(names), skip));
            keep = {};
            for i = 1:numel(names)
                if isnumeric(entry.(names{i}))
                    keep{end+1} = names{i}; %#ok<AGROW>
                end
            end
            if isempty(keep), return; end
            upperKeep = upper(keep);
            canonical = {'N','MZ','VY','MY','VZ','T','FXI','FYI','FZI','MXI','MYI','MZI', ...
                'FXJ','FYJ','FZJ','MXJ','MYJ','MZJ','FX1','FY1','FZ1','MX1','MY1','MZ1', ...
                'FX2','FY2','FZ2','MX2','MY2','MZ2'};
            ordered = {};
            for i = 1:numel(canonical)
                hit = find(strcmpi(upperKeep, canonical{i}), 1);
                if ~isempty(hit)
                    ordered{end+1} = keep{hit}; %#ok<AGROW>
                end
            end
            extras = keep(~ismember(lower(keep), lower(ordered)));
            dofs = [ordered, extras];
        end

        function dofs = normalizeDofs_(~, raw)
            if isempty(raw)
                dofs = {};
            elseif iscell(raw) && isscalar(raw) && iscell(raw{1})
                dofs = raw{1};
            elseif iscell(raw)
                dofs = raw(:).';
            elseif isstring(raw)
                dofs = cellstr(raw(:).');
            elseif ischar(raw)
                dofs = {raw};
            else
                dofs = cellstr(string(raw(:).'));
            end
        end

        function comps = expandEndPairComponents_(~, comps)
            comps = cellstr(string(comps(:).'));
            out = {};
            upperComps = upper(comps);
            for i = 1:numel(comps)
                name = upperComps{i};
                if endsWith(name, {'I','J'})
                    base = name(1:end-1);
                    pair = {[base 'I'], [base 'J']};
                elseif endsWith(name, {'1','2'})
                    base = name(1:end-1);
                    pair = {[base '1'], [base '2']};
                else
                    continue;
                end
                if all(ismember(pair, upperComps)) && ~any(strcmpi(out, base))
                    out{end+1} = base; %#ok<AGROW>
                end
            end
            comps = [out, comps];
        end

        function comps = mergeComponents_(~, base, add)
            comps = cellstr(string(base(:).'));
            add = cellstr(string(add(:).'));
            for i = 1:numel(add)
                if ~any(strcmpi(comps, add{i}))
                    comps{end+1} = add{i}; %#ok<AGROW>
                end
            end
        end

        function rows = respRowsForBeamInfo_(obj, segIdx, rt, localStep, info, nRespRows)
            rows = zeros(size(info.conn,1), 1);
            [tags, tagRows] = obj.respEleTags_(segIdx, rt, localStep, nRespRows);
            if ~isempty(tags) && ~isempty(info.tags)
                [tf, loc] = ismember(double(info.tags(:)), double(tags(:)));
                use = tf & loc > 0 & loc <= numel(tagRows);
                rows(use) = tagRows(loc(use));
            end
            if ~any(rows > 0)
                n = min(numel(rows), nRespRows);
                rows(1:n) = 1:n;
            end
        end

        function [tags, rows] = respEleTags_(obj, segIdx, rt, localStep, nRespRows)
            tags = [];
            rows = [];
            fr = obj.FrameResp(segIdx);
            rt = obj.normalizeRespType_(segIdx, rt);
            raw = [];
            if isfield(fr, rt) && isstruct(fr.(rt)) && isfield(fr.(rt), 'eleTags')
                raw = fr.(rt).eleTags;
            end
            if isempty(raw) && isfield(fr, 'eleTags'), raw = fr.eleTags; end
            if isempty(raw), return; end
            raw = double(raw);
            if isvector(raw)
                tags = raw(:);
            elseif size(raw,2) == nRespRows
                tags = raw(min(localStep, size(raw,1)), :).';
            elseif size(raw,1) == nRespRows
                tags = raw(:, min(localStep, size(raw,2)));
            else
                tags = raw(:);
            end
            rows = (1:numel(tags)).';
        end

        function tf = usesRecordedSectionLocs_(obj, rt)
            loc = lower(strtrim(obj.responseLocation_()));
            if any(strcmp(loc, {'section','sections','sec'})), tf = true; return; end
            if any(strcmp(loc, {'element','elements','ele','member','end','ends'})), tf = false; return; end
            tf = any(strcmpi(char(string(rt)), {'sectionForces','sectionDeformations'}));
        end

        function loc = responseLocation_(obj)
            loc = char(string(obj.Opts.responseLocation));
            if isempty(loc), loc = 'auto'; end
        end

        function [axisField, axisSign] = resolvePlotAxisSpec_(obj)
            rt = lower(strtrim(char(string(obj.Opts.respType))));
            comp = upper(strtrim(char(string(obj.Opts.component))));
            axisField = 'YAxis';
            axisSign = 1;
            if any(strcmp(rt, {'localforces','localforce'}))
                if any(strcmp(comp, {'FZ','FZ1','FZ2'})), axisField = 'ZAxis'; axisSign = 1;
                elseif any(strcmp(comp, {'MY','MY1','MY2'})), axisField = 'ZAxis'; axisSign = -1;
                elseif any(strcmp(comp, {'MZ','MZ1','MZ2'})), axisField = 'YAxis'; axisSign = -1; end
            elseif any(strcmp(comp, {'MZ','MY'}))
                axisSign = -1;
                if strcmp(comp, 'MY'), axisField = 'ZAxis'; end
            elseif any(strcmp(comp, {'VZ'}))
                axisField = 'ZAxis';
            end
        end

        function fam = families_(obj, segIdx)
            fam = struct();
            segIdx = min(max(1, segIdx), numel(obj.ModelInfo));
            mi = obj.ModelInfo(segIdx);
            if ~isfield(mi, 'Elements'), return; end
            E = mi.Elements;
            if isfield(E, 'Families'), fam = E.Families; else, fam = E; end
        end

        function P = nodeCoords_(obj, segIdx)
            P = zeros(0, 3);
            segIdx = min(max(1, segIdx), numel(obj.ModelInfo));
            P = plotter.polyscope.ModelAdapter.nodeCoords(obj.ModelInfo(segIdx));
            P = P(~all(isnan(P),2), :);
        end

        function conn = remapBeamConn_(obj, segIdx, conn, nNode)
            conn = double(conn);
            validIdx = all(isfinite(conn), 2) & all(conn >= 1, 2) & all(conn <= nNode, 2);
            if all(validIdx)
                conn = round(conn);
                return;
            end
            segIdx = min(max(1, segIdx), numel(obj.ModelInfo));
            tags = plotter.polyscope.ModelAdapter.nodeTags(obj.ModelInfo(segIdx));
            mapped = zeros(size(conn));
            for j = 1:size(conn, 2)
                mapped(:, j) = plotter.polyscope.ModelAdapter.tagsToIdx(conn(:, j), tags);
            end
            useMapped = all(mapped > 0, 2);
            conn(useMapped, :) = mapped(useMapped, :);
            conn = round(conn);
        end

        function r = rangeFromVals_(~, vals)
            vals = vals(isfinite(vals));
            if isempty(vals), r = [0 1]; return; end
            lo = min(vals); hi = max(vals);
            if lo == hi
                d = max(1, abs(lo)) * 0.05;
                lo = lo - d; hi = hi + d;
            end
            r = [lo hi];
        end

        function vals = flattenCell_(~, C)
            vals = zeros(0,1);
            for i = 1:numel(C)
                vals = [vals; C{i}(:)]; %#ok<AGROW>
            end
        end

        function key = responseKey_(obj)
            key = sprintf('%s|%s|%s|%s', char(string(obj.Opts.respType)), ...
                char(string(obj.Opts.component)), obj.responseLocation_(), char(string(obj.Opts.scaleMode)));
        end

        function q = scalarQuantityName_(obj)
            q = sprintf('%s_%s', char(string(obj.Opts.respType)), char(string(obj.Opts.component)));
        end

        function updateProgramName_(obj)
            try
                obj.App.polyscopeHandle().set_program_name(sprintf( ...
                    'OpenSeesMatlab | Frame response | %s %s | step %d - by Yexiang Yan', ...
                    char(string(obj.Opts.respType)), char(string(obj.Opts.component)), obj.currentStep_));
            catch
            end
        end

        function invalidateCaches_(obj)
            obj.invalidateCachedRange_('frameClim');
            obj.invalidateCachedRange_('frameScale');
            obj.extremeStepCache_ = struct();
            obj.responseStatsCache_ = struct();
            obj.invalidateHistoryCache_();
        end

        function invalidateHistoryCache_(obj)
            obj.invalidateHistoryReducedCache_();
            obj.historyRawKey_ = '';
            obj.historyRawX_ = [];
            obj.historyRawValues_ = {};
        end

        function invalidateHistoryReducedCache_(obj)
            obj.historyCacheKey_ = '';
            obj.historyCacheX_ = [];
            obj.historyCacheY_ = [];
        end

        function idx = historyElementIndex_(obj, tags)
            idx = round(obj.getOptField_(obj.gui_, 'historyEleIndex', 1));
            if obj.getOptField_(obj.gui_, 'historyUseTag', true)
                hit = find(tags == obj.getOptField_(obj.gui_, 'historyEleTag', NaN), 1);
                if ~isempty(hit), idx = hit; end
            end
            idx = max(1, min(numel(tags), idx));
        end

        function [choices, label] = historySampleChoices_(obj, info, tags)
            nValue = 1;
            row = obj.historyElementIndex_(tags);
            values = obj.respPerEle_(obj.currentSeg_, obj.currentLocalStep_, info);
            if row <= numel(values), nValue = max(1, numel(values{row})); end
            indexChoices = cellstr(string(1:nValue));
            choices = [indexChoices(:).', {'max','min','absMax','absMin'}];
            rt = obj.normalizeRespType_(obj.currentSeg_, obj.Opts.respType);
            if obj.usesRecordedSectionLocs_(rt) || nValue > 2
                label = 'Section index / reduce';
            elseif nValue == 2
                label = 'Element end / reduce';
            else
                label = 'Value / reduce';
            end
        end

        function value = reduceHistoryValues_(~, values, mode)
            value = NaN;
            values = double(values(:));
            mode = char(string(mode));
            numericIndex = str2double(mode);
            if isfinite(numericIndex)
                idx = round(numericIndex);
                if idx >= 1 && idx <= numel(values) && isfinite(values(idx))
                    value = values(idx);
                end
                return;
            end
            valid = find(isfinite(values));
            if isempty(valid), return; end
            switch lower(mode)
                case 'max'
                    [~, k] = max(values(valid));
                case 'min'
                    [~, k] = min(values(valid));
                case 'absmin'
                    [~, k] = min(abs(values(valid)));
                otherwise % absMax
                    [~, k] = max(abs(values(valid)));
            end
            value = values(valid(k));
        end

        function [x, y] = responseHistorySeries_(obj)
            key = sprintf('%s|%s|%s|tag:%g|idx:%g|useTag:%d|n:%d', ...
                char(string(obj.Opts.respType)), char(string(obj.Opts.component)), ...
                char(string(obj.gui_.historySampleMode)), ...
                obj.gui_.historyEleTag, obj.gui_.historyEleIndex, ...
                logical(obj.gui_.historyUseTag), obj.nSteps_);
            if strcmp(obj.historyCacheKey_, key) && ~isempty(obj.historyCacheX_)
                x = obj.historyCacheX_; y = obj.historyCacheY_;
                return;
            end
            rawKey = sprintf('%s|%s|tag:%g|idx:%g|useTag:%d|n:%d', ...
                char(string(obj.Opts.respType)), char(string(obj.Opts.component)), ...
                obj.gui_.historyEleTag, obj.gui_.historyEleIndex, ...
                logical(obj.gui_.historyUseTag), obj.nSteps_);
            if strcmp(obj.historyRawKey_, rawKey) && numel(obj.historyRawValues_) == obj.nSteps_
                x = obj.historyRawX_;
                rawValues = obj.historyRawValues_;
            else
                [x, rawValues] = obj.extractResponseHistoryRaw_();
                obj.historyRawKey_ = rawKey;
                obj.historyRawX_ = x;
                obj.historyRawValues_ = rawValues;
            end
            y = NaN(obj.nSteps_, 1);
            for k = 1:obj.nSteps_
                y(k) = obj.reduceHistoryValues_(rawValues{k}, obj.gui_.historySampleMode);
            end
            obj.historyCacheKey_ = key;
            obj.historyCacheX_ = x;
            obj.historyCacheY_ = y;
        end

        function [x, rawValues] = extractResponseHistoryRaw_(obj)
            x = NaN(obj.nSteps_, 1);
            rawValues = cell(obj.nSteps_, 1);
            targetTag = obj.gui_.historyEleTag;
            targetIndex = round(obj.gui_.historyEleIndex);
            for si = 1:numel(obj.segStepCounts_)
                fr = obj.FrameResp(si);
                P = obj.nodeCoords_(si);
                info = obj.beamInfo_(si, P);
                if isempty(info.tags), continue; end
                row = [];
                if obj.gui_.historyUseTag, row = find(info.tags == targetTag, 1);
                else, row = min(max(1, targetIndex), numel(info.tags));
                end
                nLocal = obj.segStepCounts_(si);
                offset = obj.segOffsets_(si);
                tv = [];
                if isfield(fr, 'time') && ~isempty(fr.time), tv = double(fr.time(:)); end
                for ls = 1:nLocal
                    g = offset + ls - 1;
                    x(g + 1) = g;
                    if ls <= numel(tv), x(g + 1) = tv(ls); end
                    if isempty(row), continue; end
                    values = obj.respPerEle_(si, ls, info);
                    if row <= numel(values), rawValues{g + 1} = double(values{row}(:)); end
                end
            end
        end

        function setEnabled_(obj, name, val)
            if isfield(obj.handles_, name)
                try
                    obj.handles_.(name).set_enabled(logical(val));
                catch
                end
            end
        end

        function v = trimVectorLength_(~, v, n)
            v = v(:);
            if numel(v) < n, v(end+1:n,1) = NaN; end
            v = v(1:n);
        end

        function A = trimAxisRows_(~, A, n)
            if size(A,2) < 3, A(:,end+1:3) = 0; end
            if size(A,1) < n, A(end+1:n,1:3) = NaN; end
            A = A(1:n,1:3);
        end
    end
end
