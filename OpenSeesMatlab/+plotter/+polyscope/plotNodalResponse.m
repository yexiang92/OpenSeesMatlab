classdef plotNodalResponse < plotter.polyscope.ViewerBase
    %NODALRESPONSEVIEWER Polyscope viewer for transient nodal responses.

    properties
        NodalResp struct
    end

    properties (Access = private)
        currentStep_ double = 0
        currentSeg_ double = 0
        currentLocalStep_ double = 1
        nSteps_ double = 1
        segStepCounts_ double = []
        segOffsets_ double = []
        respLookup_ cell = {}
        fieldTypes_ cell = {}
        fieldComponents_ cell = {}
        lineData_ struct = struct()
        surfData_ struct = struct()
        volumeData_ struct = struct()
        extremeStepCache_ struct = struct()
        initialOpts_ struct
        historyCacheKey_ char = ''
        historyCacheX_ double = []
        historyCacheY_ double = []
        historyCacheLabel_ char = ''
    end

    methods
        function obj = plotNodalResponse(modelInfo, nodalResp, opts)
            if nargin < 1 || isempty(modelInfo)
                error('plotter:polyscope:NodalResponseViewer:InvalidInput', ...
                    'modelInfo is required.');
            end
            if nargin < 2 || isempty(nodalResp)
                error('plotter:polyscope:NodalResponseViewer:InvalidInput', ...
                    'nodalResp is required.');
            end
            if nargin < 3 || isempty(opts)
                opts = struct();
            end

            obj = obj@plotter.polyscope.ViewerBase();
            obj.ModelInfo = modelInfo;
            obj.NodalResp = nodalResp;
            obj.Opts = plotter.polyscope.Options.mergeOpts( ...
                plotter.polyscope.Options.defaultNodalResponseOptions(), opts);
            obj.App = plotter.polyscope.PolyscopeApp();
            obj.P0_ = obj.nodeCoords_(1);
            obj.L_ = obj.modelLength_(obj.P0_);
            obj.buildStepIndex_();
            obj.fieldTypes_ = obj.collectFieldTypes_();
            if isempty(obj.fieldTypes_), obj.fieldTypes_ = {'disp'}; end
            obj.Opts.field.type = obj.pickExisting_(obj.fieldTypes_, obj.Opts.field.type);
            obj.fieldComponents_ = obj.componentsForField_(obj.Opts.field.type);
            obj.Opts.field.component = obj.pickExisting_(obj.fieldComponents_, obj.Opts.field.component);
            obj.Opts.deform.type = obj.pickExisting_(obj.deformFieldTypes_(), obj.Opts.deform.type);
            obj.Opts.vector.type = obj.pickExisting_(obj.fieldTypes_, obj.Opts.vector.type);
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
            view0 = char(string(obj.Opts.general.view));
            if is2D && any(strcmpi(view0, {'auto', '3D'}))
                obj.Opts.general.view = 'XY';
            end

            obj.App.init(obj.Opts.polyscope.backend, obj.Opts, is2D);
            try
                obj.App.polyscopeHandle().set_ground_plane_mode('none');
            catch
            end
            obj.setupWindowIcon_();
            obj.clear_();
            obj.handles_ = struct();
            obj.lineData_ = struct();
            obj.surfData_ = struct();
            obj.volumeData_ = struct();
            obj.currentSeg_ = 0;
            obj.built_ = true;
            if isempty(fieldnames(obj.gui_))
                obj.initGuiState_();
            end
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
            camState = obj.animationPlaneCameraState_();
            targetP = obj.nodeCoords_(segIdx);
            topologySizeChanged = size(targetP, 1) ~= size(obj.P0_, 1);
            if force || segIdx ~= obj.currentSeg_ || topologySizeChanged
                obj.registerSegment_(segIdx);
            end
            obj.currentStep_ = step;
            obj.currentSeg_ = segIdx;
            obj.currentLocalStep_ = localStep;
            obj.updateStep_(segIdx, localStep);
            obj.restoreCameraState_(camState);
            obj.updateProgramName_();
            if isfield(obj.gui_, 'step')
                obj.gui_.step = step;
            end
        end

        function n = nSteps(obj)
            n = obj.nSteps_;
        end
    end

    methods (Access = protected)
        function initGuiState_(obj)
            initGuiState_@plotter.polyscope.ViewerBase(obj);
            obj.gui_.step = obj.currentStep_;
            stepModes = {'step','absmax','absmin','max','min'};
            obj.gui_.stepModeIdx = obj.indexOf_(stepModes, obj.getOptField_(obj.Opts, 'stepIdx', 'absmax'));
            obj.gui_.playing = obj.getOptField_(obj.Opts.animation, 'play', false);
            obj.gui_.animationMode = obj.gui_.playing;
            obj.gui_.fps = obj.getOptField_(obj.Opts.animation, 'fps', ...
                obj.defaultAnimationFps_(obj.nSteps_));
            obj.gui_.loop = obj.getOptField_(obj.Opts.animation, 'loop', true);
            obj.gui_.pingpong = obj.getOptField_(obj.Opts.animation, 'pingpong', false);
            obj.gui_.animUpdateColors = obj.getOptField_(obj.Opts.animation, 'updateColors', true);
            obj.gui_.animUpdateVectors = obj.getOptField_(obj.Opts.animation, 'updateVectors', false);
            obj.gui_.animDir = 1;

            obj.gui_.fieldIdx = obj.indexOf_(obj.fieldTypes_, obj.Opts.field.type);
            obj.fieldComponents_ = obj.componentsForField_(obj.Opts.field.type);
            obj.gui_.compIdx = obj.indexOf_(obj.fieldComponents_, obj.Opts.field.component);
            deformFields = obj.deformFieldTypes_();
            obj.gui_.deformIdx = obj.indexOf_(deformFields, obj.Opts.deform.type);
            obj.gui_.vectorIdx = obj.indexOf_(obj.fieldTypes_, obj.Opts.vector.type);
            tags = obj.historyTags_(1);
            if isempty(tags), tags = 1; end
            obj.gui_.showHistory = false;
            obj.gui_.historyNodeTag = tags(1);
            obj.gui_.historyNodeIndex = 1;
            obj.gui_.historyUseTag = true;
            obj.gui_.historyAutoStep = true;
            obj.gui_.historyShowValue = true;
            obj.gui_.historyFieldIdx = obj.gui_.fieldIdx;
            obj.gui_.historyCompIdx = obj.gui_.compIdx;

            obj.gui_.showField = obj.Opts.field.show;
            obj.gui_.showDeform = obj.Opts.deform.show;
            obj.gui_.autoScale = obj.Opts.deform.autoScale;
            obj.gui_.deformScale = obj.Opts.deform.scale;
            obj.gui_.showUndeformed = obj.Opts.deform.showUndeformed;
            obj.gui_.showLines = obj.Opts.line.show;
            obj.gui_.useInterpolation = obj.getOptField_(obj.Opts.interp, 'useInterpolation', true);
            obj.gui_.showSurfaces = obj.Opts.surf.show;
            obj.gui_.showSurfaceEdges = obj.Opts.surf.showEdges;
            obj.gui_.showNodes = obj.Opts.nodes.show;
            obj.gui_.showFixed = obj.Opts.fixed.show;
            obj.gui_.showVectors = obj.Opts.vector.show;
            obj.gui_.vectorAuto = obj.Opts.vector.autoScale;
            obj.gui_.vectorScale = obj.Opts.vector.scale;
            obj.gui_.useColormap = obj.Opts.color.useColormap;
            obj.gui_.climIdx = obj.indexOf_({'step','global','range','absmax','absmin'}, obj.Opts.color.climMode);
            obj.gui_.deformedAlpha = obj.Opts.color.deformedAlpha;
            obj.gui_.undeformedAlpha = obj.Opts.color.undeformedAlpha;
            obj.gui_.edgeRadius = obj.Opts.polyscope.edgeRadius;
            obj.gui_.nodeRadius = obj.Opts.polyscope.nodeRadius;
            obj.gui_.vectorRadius = obj.Opts.polyscope.vectorRadius;
            obj.gui_.solidColor = plotter.polyscope.utils.colorToRgb(obj.Opts.color.solidColor);
            obj.gui_.ghostColor = plotter.polyscope.utils.colorToRgb(obj.Opts.color.undeformedColor);
            obj.gui_.vectorColor = plotter.polyscope.utils.colorToRgb(obj.Opts.vector.color);
            obj.initColorbarGuiState_();
            obj.initSliceGuiState_();

            cmapNames = obj.colormapNames_();
            obj.gui_.cmapIdx = obj.indexOf_(cmapNames, obj.Opts.polyscope.scalarColorMap);
            obj.gui_.showInfo = true;
        end

        function configureAnimationRenderLoop_(obj)
            isRunning = isfield(obj.gui_, 'animationMode') && obj.gui_.animationMode && ...
                isfield(obj.gui_, 'playing') && obj.gui_.playing;
            fps = max(1, double(obj.getOptField_(obj.gui_, 'fps', 12)));
            configureAnimationRenderLoop_@plotter.polyscope.ViewerBase(obj, isRunning, fps);
        end
    end

    methods
        function guiCallback_(obj)
            try
                GB = plotter.polyscope.GuiBuilder;
                ws = obj.safeWindowSize_();
                obj.advanceAnimation_();
                panelW = 380;
                panelH = max(520, ws(2));
                GB.begin('Nodal Response', [max(0, ws(1) - panelW), 0], [panelW, panelH]);
                windowCleanup = onCleanup(@() GB.finish());

                needsRebuild = false;
                needsUpdate = false;

                GB.header('Nodal response');
                if GB.collapsingHeader('Response', int32(0))
                    if obj.drawStepGui_()
                        needsUpdate = true;
                    end
                    GB.separator();
                    if obj.drawDisplayGui_()
                        if obj.Opts.deform.showUndeformed && ~obj.hasGhostHandles_()
                            obj.registerGhosts_(obj.App.polyscopeHandle(), obj.currentSeg_);
                        end
                        obj.registerMissingOptionalStructures_();
                        needsUpdate = true;
                    end
                    obj.gui_.showHistory = GB.checkbox('Show node history', obj.gui_.showHistory);
                end

                GB.separator();
                if GB.collapsingHeader('Geometry', int32(0))
                    geomRebuild = obj.drawGeometryGui_();
                    needsRebuild = needsRebuild || geomRebuild;
                end

                GB.separator();
                if GB.collapsingHeader('Style', int32(0))
                if obj.drawStyleGui_()
                    needsUpdate = true;
                end
                end

                GB.separator();
                if GB.collapsingHeader('Animation', int32(0))
                    if obj.drawAnimationGui_()
                        needsUpdate = true;
                    end
                end

                GB.separator();
                if obj.drawSlicePlaneGui_('##response')
                    obj.applySlicePlane_();
                end

                GB.separator();
                if GB.button('Redraw')
                    obj.App.polyscopeHandle().request_redraw();
                end
                GB.sameLine();
                if GB.button('Reset')
                    obj.Opts = obj.initialOpts_;
                    obj.initGuiState_();
                    needsRebuild = true;
                end
                obj.drawScreenAxesOverlay_();
                obj.updateScreenAxes3D_();
                clear windowCleanup
                if isfield(obj.gui_, 'showHistory') && obj.gui_.showHistory
                    obj.drawNodeHistoryWindow_(ws);
                end

                if needsRebuild
                    obj.setStep(obj.currentStep_, true);
                elseif needsUpdate
                    obj.applyVisibility_();
                    obj.applyStyle_();
                    obj.updateStep_(obj.currentSeg_, obj.currentLocalStep_);
                end
            catch ME
                fprintf('plotNodalResponse.guiCallback_ error: %s\n', ME.message);
            end
        end
    end

    methods (Access = private)
        function changed = drawStepGui_(obj)
            changed = false;
            GB = plotter.polyscope.GuiBuilder;
            stepModes = {'step','absmax','absmin','max','min'};
            oldStep = obj.gui_.step;
            oldMode = obj.gui_.stepModeIdx;
            obj.gui_.stepModeIdx = GB.combo('Mode', obj.gui_.stepModeIdx, stepModes);
            if obj.gui_.stepModeIdx == 1
                obj.gui_.step = GB.sliderInt('Step##response', obj.gui_.step, 0, max(0, obj.nSteps_ - 1));
            else
                polyscope.ImGui.Text(sprintf('Resolved step: %d / %d', obj.gui_.step, max(0, obj.nSteps_ - 1)));
            end

            if GB.button('Prev')
                obj.gui_.step = max(0, obj.gui_.step - 1);
            end
            GB.sameLine();
            if GB.button('Next')
                obj.gui_.step = min(max(0, obj.nSteps_ - 1), obj.gui_.step + 1);
            end
            GB.sameLine();
            if GB.button('Apply')
                if obj.gui_.stepModeIdx == 1
                    oldStep = NaN;
                else
                    obj.gui_.step = obj.resolveStepArg_(stepModes{obj.gui_.stepModeIdx});
                    oldStep = NaN;
                end
            end
            if obj.gui_.stepModeIdx ~= oldMode && obj.gui_.stepModeIdx ~= 1
                obj.gui_.step = obj.resolveStepArg_(stepModes{obj.gui_.stepModeIdx});
            end

            polyscope.ImGui.ProgressBar((obj.gui_.step + 1) / max(1, obj.nSteps_), [0, 0], ...
                sprintf('%d / %d', obj.gui_.step, max(0, obj.nSteps_ - 1)));

            if obj.gui_.step ~= oldStep
                obj.setStep(obj.gui_.step);
                changed = false;
            end

            GB.separator();
            [segIdx, localStep] = obj.resolveGlobalStep_(obj.currentStep_);
            polyscope.ImGui.Text(sprintf('Segment %d, local step %d', segIdx, localStep));
            polyscope.ImGui.Text(sprintf('Nodes: %d | Total steps: %d', size(obj.nodeCoords_(segIdx), 1), obj.nSteps_));
        end

        function changed = drawAnimationGui_(obj)
            changed = false;
            GB = plotter.polyscope.GuiBuilder;
            oldState = obj.gui_;
            oldMode = obj.gui_.animationMode;

            if ~obj.gui_.animationMode
                if GB.button('Enter animation')
                    obj.gui_.animationMode = true;
                    obj.gui_.playing = true;
                    obj.gui_.animDir = 1;
                    % Keep the displayed step and its registered topology.
                    % Changing only the segment index is invalid when a model
                    % update changes the number of nodes.
                    obj.gui_.step = obj.currentStep_;
                    obj.gui_.autoScale = true;
                    obj.Opts.deform.autoScale = true;
                    obj.gui_.climIdx = obj.indexOf_({'step','global','range','absmax','absmin'}, 'global');
                    obj.Opts.color.climMode = 'global';
                    obj.configureAnimationRenderLoop_();
                    changed = true;
                end
                polyscope.ImGui.TextWrapped('Static mode updates only when controls are changed or a step is applied.');
            else
                if GB.button('Exit animation')
                    obj.gui_.animationMode = false;
                    obj.gui_.playing = false;
                    obj.configureAnimationRenderLoop_();
                    changed = true;
                end
                GB.sameLine();
                if GB.button('Restart')
                    obj.gui_.step = 0;
                    obj.gui_.animDir = 1;
                    obj.setStep(0);
                    changed = false;
                end
                if obj.gui_.playing
                    if GB.button('Pause')
                        obj.gui_.playing = false;
                        obj.configureAnimationRenderLoop_();
                    end
                else
                    if GB.button('Play')
                        obj.gui_.playing = true;
                        obj.configureAnimationRenderLoop_();
                    end
                end
                GB.sameLine();
                if GB.button('Step##animation')
                    obj.stepAnimationOnce_();
                    changed = false;
                end
                obj.gui_.loop = GB.checkbox('Loop', obj.gui_.loop);
                GB.sameLine();
                obj.gui_.pingpong = GB.checkbox('Ping-pong', obj.gui_.pingpong);
                obj.gui_.animUpdateColors = GB.checkbox('Update colors', obj.gui_.animUpdateColors);
                GB.sameLine();
                obj.gui_.animUpdateVectors = GB.checkbox('Update vectors', obj.gui_.animUpdateVectors);
                obj.gui_.autoScale = true;
                obj.Opts.deform.autoScale = true;
                obj.gui_.deformScale = GB.sliderFloat('Scale factor##animation', obj.gui_.deformScale, 0, 100);
                oldFps = obj.gui_.fps;
                obj.gui_.fps = GB.sliderFloat('FPS##animation', obj.gui_.fps, 1, 240);
                if abs(oldFps - obj.gui_.fps) > eps
                    obj.configureAnimationRenderLoop_();
                end

                polyscope.ImGui.ProgressBar((obj.gui_.step + 1) / max(1, obj.nSteps_), [0, 0], ...
                    sprintf('%d / %d', obj.gui_.step, max(0, obj.nSteps_ - 1)));
            end
            obj.Opts.animation.play = logical(obj.gui_.playing);
            obj.Opts.animation.loop = logical(obj.gui_.loop);
            obj.Opts.animation.pingpong = logical(obj.gui_.pingpong);
            obj.Opts.animation.fps = obj.gui_.fps;
            obj.Opts.animation.updateColors = logical(obj.gui_.animUpdateColors);
            obj.Opts.animation.updateVectors = logical(obj.gui_.animUpdateVectors);
            obj.Opts.deform.scale = obj.gui_.deformScale;
            changed = changed || oldMode ~= obj.gui_.animationMode || ...
                obj.guiChanged_(oldState, {'autoScale','deformScale','climIdx'});
        end

        function drawNodeHistoryGui_(obj)
            GB = plotter.polyscope.GuiBuilder;
            tags = obj.historyTags_(max(1, obj.currentSeg_));
            nNode = numel(tags);
            if nNode == 0
                polyscope.ImGui.TextDisabled('No response nodes are available.');
                return;
            end

            oldState = obj.gui_;
            obj.gui_.historyFieldIdx = GB.combo('Response##history', ...
                obj.gui_.historyFieldIdx, obj.fieldTypes_);
            historyField = obj.fieldTypes_{obj.gui_.historyFieldIdx};
            historyComps = obj.componentsForField_(historyField);
            if isempty(historyComps), historyComps = {'magnitude'}; end
            obj.gui_.historyCompIdx = max(1, min(numel(historyComps), obj.gui_.historyCompIdx));
            obj.gui_.historyCompIdx = GB.combo('Component##history', ...
                obj.gui_.historyCompIdx, historyComps);
            if obj.guiChanged_(oldState, {'historyFieldIdx','historyCompIdx'})
                obj.invalidateHistoryCache_();
            end

            obj.gui_.historyUseTag = GB.checkbox('Use node tag', obj.gui_.historyUseTag);
            if obj.gui_.historyUseTag
                [changed, tagVal] = polyscope.ImGui.InputInt('Node tag##history', ...
                    int32(round(obj.gui_.historyNodeTag)), int32(1), int32(100));
                if changed
                    obj.gui_.historyNodeTag = double(tagVal);
                    idx = find(tags == obj.gui_.historyNodeTag, 1);
                    if ~isempty(idx), obj.gui_.historyNodeIndex = idx; end
                    obj.invalidateHistoryCache_();
                end
                if GB.button('Prev node##history')
                    idx = max(1, obj.historyNodeIndex_(tags) - 1);
                    obj.gui_.historyNodeIndex = idx;
                    obj.gui_.historyNodeTag = tags(idx);
                    obj.invalidateHistoryCache_();
                end
                GB.sameLine();
                if GB.button('Next node##history')
                    idx = min(nNode, obj.historyNodeIndex_(tags) + 1);
                    obj.gui_.historyNodeIndex = idx;
                    obj.gui_.historyNodeTag = tags(idx);
                    obj.invalidateHistoryCache_();
                end
            else
                [changed, idxVal] = polyscope.ImGui.InputInt('Node index##history', ...
                    int32(round(obj.gui_.historyNodeIndex)), int32(1), int32(10));
                if changed
                    obj.gui_.historyNodeIndex = round(max(1, min(nNode, double(idxVal))));
                    obj.gui_.historyNodeTag = tags(obj.gui_.historyNodeIndex);
                    obj.invalidateHistoryCache_();
                end
            end
            if GB.button('Reset##history')
                obj.resetNodeHistoryGui_(tags);
            end
            GB.sameLine();
            obj.gui_.historyAutoStep = GB.checkbox('Follow current step', obj.gui_.historyAutoStep);
            obj.gui_.historyShowValue = GB.checkbox('Show current value', obj.gui_.historyShowValue);

            [x, y, label] = obj.nodeHistorySeries_();
            finiteY = y(isfinite(y));
            if isempty(finiteY)
                polyscope.ImGui.TextDisabled('No response values for this node/field.');
                return;
            end
            ymin = min(finiteY);
            ymax = max(finiteY);
            if ymin == ymax
                pad = max(1, abs(ymin)) * 0.05;
                ymin = ymin - pad;
                ymax = ymax + pad;
            end
            xmin = min(x(isfinite(x)));
            xmax = max(x(isfinite(x)));
            if xmin == xmax, xmax = xmin + 1; end
            xpad = 0.02 * max(1, xmax - xmin);
            ypad = 0.08 * max(1e-12, ymax - ymin);
            xmin = xmin - xpad;
            xmax = xmax + xpad;
            ymin = ymin - ypad;
            ymax = ymax + ypad;

            ip = polyscope.ImPlot;
            plotFlags = int32(polyscope.ImPlot.get_constant('ImPlotFlags_NoLegend'));
            if ip.BeginPlot(['##history_plot_' label], [-1, 220], plotFlags)
                ip.SetupAxes('time / step', label);
                ip.SetupAxesLimits(xmin, xmax, ymin, ymax, ...
                    int32(polyscope.ImPlot.get_constant('ImPlotCond_Always')));
                ip.PlotLineXY('response##history_line', x(:), y(:));
                if obj.currentStep_ >= 0 && obj.currentStep_ < numel(x)
                    k = obj.currentStep_ + 1;
                    if isfinite(y(k))
                        try
                            ip.SetNextMarkerStyle( ...
                                int32(polyscope.ImPlot.get_constant('ImPlotMarker_Circle')), ...
                                8, [1.0, 0.78, 0.05, 1.0], 2.0, [0.05, 0.05, 0.05, 1.0]);
                        catch
                        end
                        ip.PlotScatterXY('current##history_current', x(k), y(k));
                    end
                end
                ip.EndPlot();
            end
            if obj.gui_.historyShowValue && obj.currentStep_ >= 0 && obj.currentStep_ < numel(y)
                val = y(obj.currentStep_ + 1);
                if isfinite(val)
                    polyscope.ImGui.Text(sprintf('Current %s: %.6g', label, val));
                end
            end
        end

        function resetNodeHistoryGui_(obj, tags)
            if nargin < 2 || isempty(tags)
                tags = obj.historyTags_(max(1, obj.currentSeg_));
            end
            obj.gui_.historyFieldIdx = obj.gui_.fieldIdx;
            obj.gui_.historyCompIdx = obj.gui_.compIdx;
            obj.gui_.historyUseTag = true;
            obj.gui_.historyAutoStep = true;
            obj.gui_.historyShowValue = true;
            obj.gui_.historyNodeIndex = 1;
            if ~isempty(tags)
                obj.gui_.historyNodeTag = tags(1);
            end
            obj.invalidateHistoryCache_();
        end

        function drawNodeHistoryWindow_(obj, ws)
            if nargin < 2 || isempty(ws)
                ws = obj.safeWindowSize_();
            end
            w = min(520, max(380, ws(1) * 0.34));
            h = min(390, max(300, ws(2) * 0.36));
            x = max(12, ws(1) - 380 - w - 18);
            y = max(42, ws(2) - h - 18);
            polyscope.ImGui.SetNextWindowPos([x, y], ...
                int32(polyscope.ImGui.get_constant('ImGuiCond_FirstUseEver')));
            polyscope.ImGui.SetNextWindowSize([w, h], ...
                int32(polyscope.ImGui.get_constant('ImGuiCond_FirstUseEver')));
            visible = polyscope.ImGui.Begin('Node history');
            cleanup = onCleanup(@() polyscope.ImGui.End());
            if visible
                obj.drawNodeHistoryGui_();
            end
        end

        function changed = drawDisplayGui_(obj)
            GB = plotter.polyscope.GuiBuilder;
            oldField = obj.gui_.fieldIdx;
            oldState = obj.gui_;
            obj.gui_.fieldIdx = GB.combo('Scalar field', obj.gui_.fieldIdx, obj.fieldTypes_);
            if obj.gui_.fieldIdx ~= oldField
                obj.Opts.field.type = obj.fieldTypes_{obj.gui_.fieldIdx};
                obj.fieldComponents_ = obj.componentsForField_(obj.Opts.field.type);
                obj.gui_.compIdx = 1;
                obj.invalidateClimCache_();
            end
            obj.gui_.compIdx = GB.combo('Component', obj.gui_.compIdx, obj.fieldComponents_);
            obj.Opts.field.component = obj.fieldComponents_{obj.gui_.compIdx};

            deformFields = obj.deformFieldTypes_();
            obj.gui_.deformIdx = GB.combo('Deform field', obj.gui_.deformIdx, deformFields);
            obj.Opts.deform.type = deformFields{obj.gui_.deformIdx};
            obj.gui_.vectorIdx = GB.combo('Vector field', obj.gui_.vectorIdx, obj.fieldTypes_);
            obj.Opts.vector.type = obj.fieldTypes_{obj.gui_.vectorIdx};

            obj.gui_.showField = GB.checkbox('Scalar field##response', obj.gui_.showField);
            GB.sameLine();
            obj.gui_.useColormap = GB.checkbox('Use colormap##response', obj.gui_.useColormap);
            if obj.gui_.showField && obj.gui_.useColormap
                obj.drawColorbarGui_('##response', false);
            end
            obj.gui_.showVectors = GB.checkbox('Vector field##response', obj.gui_.showVectors);
            obj.gui_.showDeform = GB.checkbox('Deformed shape', obj.gui_.showDeform);
            GB.sameLine();
            obj.gui_.autoScale = GB.checkbox('Auto scale', obj.gui_.autoScale);
            obj.gui_.deformScale = GB.sliderFloat('Deformation scale', obj.gui_.deformScale, 0, 100);
            obj.gui_.showUndeformed = GB.checkbox('Undeformed ghost', obj.gui_.showUndeformed);

            obj.syncOptsFromGui_();
            changed = obj.guiChanged_(oldState, {'fieldIdx','compIdx','deformIdx','vectorIdx', ...
                'showField','useColormap','onscreenColorbar','onscreenColorbarLocation', ...
                'showVectors','showDeform','autoScale','deformScale','showUndeformed'});
            if changed && (obj.gui_.fieldIdx ~= oldState.fieldIdx || obj.gui_.compIdx ~= oldState.compIdx)
                obj.invalidateClimCache_();
            end
        end

        function needsRebuild = drawGeometryGui_(obj)
            GB = plotter.polyscope.GuiBuilder;
            oldState = obj.gui_;

            obj.gui_.showLines = GB.checkbox('Lines', obj.gui_.showLines);
            GB.sameLine();
            obj.gui_.useInterpolation = GB.checkbox('Interpolated lines', obj.gui_.useInterpolation);
            obj.gui_.showSurfaces = GB.checkbox('Surfaces / solids', obj.gui_.showSurfaces);
            GB.sameLine();
            obj.gui_.showSurfaceEdges = GB.checkbox('Mesh edges', obj.gui_.showSurfaceEdges);
            GB.sameLine();
            obj.gui_.showNodes = GB.checkbox('Model nodes', obj.gui_.showNodes);
            obj.gui_.showFixed = GB.checkbox('Fixed nodes', obj.gui_.showFixed);
            GB.sameLine();
            obj.gui_.vectorAuto = GB.checkbox('Vector auto scale', obj.gui_.vectorAuto);
            obj.gui_.vectorScale = GB.sliderFloat('Vector scale', obj.gui_.vectorScale, 0, 2);

            obj.drawSsaaGui_('##nodal_geometry');

            obj.syncOptsFromGui_();
            visibilityChanged = obj.guiChanged_(oldState, {'showLines','showSurfaces', ...
                'showSurfaceEdges','showNodes','showFixed','vectorAuto','vectorScale'});
            needsRebuild = obj.guiChanged_(oldState, {'useInterpolation'});
            if visibilityChanged
                obj.registerMissingOptionalStructures_();
                obj.applyVisibility_();
            end
        end

        function changed = drawStyleGui_(obj)
            GB = plotter.polyscope.GuiBuilder;
            oldState = obj.gui_;
            cmapNames = obj.colormapNames_();
            obj.gui_.cmapIdx = GB.combo('Colormap##style', obj.gui_.cmapIdx, cmapNames);
            obj.Opts.color.colormap = cmapNames{obj.gui_.cmapIdx};
            obj.Opts.polyscope.scalarColorMap = cmapNames{obj.gui_.cmapIdx};
            climModes = {'step','global','range','absmax','absmin'};
            obj.gui_.climIdx = GB.combo('Color limits', obj.gui_.climIdx, climModes);
            obj.Opts.color.climMode = climModes{obj.gui_.climIdx};

            title = char(string(obj.gui_.colorbarTitle));
            [tchg, title] = polyscope.ImGui.InputText('Colorbar title', title);
            if tchg
                obj.gui_.colorbarTitle = title;
                obj.Opts.polyscope.colorbarTitle = title;
            end

            [changed, obj.gui_.solidColor] = GB.colorEdit3('Solid color', obj.gui_.solidColor);
            obj.gui_.solidColor = obj.asRgb_(obj.gui_.solidColor);
            if changed, obj.Opts.color.solidColor = obj.gui_.solidColor; end
            [changed, obj.gui_.ghostColor] = GB.colorEdit3('Ghost color', obj.gui_.ghostColor);
            obj.gui_.ghostColor = obj.asRgb_(obj.gui_.ghostColor);
            if changed, obj.Opts.color.undeformedColor = obj.gui_.ghostColor; end
            [changed, obj.gui_.vectorColor] = GB.colorEdit3('Vector color', obj.gui_.vectorColor);
            obj.gui_.vectorColor = obj.asRgb_(obj.gui_.vectorColor);
            if changed, obj.Opts.vector.color = obj.gui_.vectorColor; end

            obj.gui_.deformedAlpha = GB.sliderFloat('Deformed alpha', obj.gui_.deformedAlpha, 0, 1);
            obj.gui_.undeformedAlpha = GB.sliderFloat('Ghost alpha', obj.gui_.undeformedAlpha, 0, 1);
            obj.gui_.edgeRadius = GB.sliderFloat('Line radius', obj.gui_.edgeRadius, 0.0001, 0.006);
            obj.gui_.nodeRadius = GB.sliderFloat('Node radius', obj.gui_.nodeRadius, 0.0003, 0.012);
            obj.gui_.vectorRadius = GB.sliderFloat('Vector radius', obj.gui_.vectorRadius, 0.0002, 0.006);

            views = obj.viewNames_();
            obj.gui_.viewIdx = GB.combo('View', obj.gui_.viewIdx, views);
            if GB.button('Apply view')
                obj.Opts.general.view = views{obj.gui_.viewIdx};
                obj.setCameraForPoints_(obj.nodeCoords_(obj.currentSeg_), obj.Opts.general.view);
            end
            GB.sameLine();
            if GB.button('Rebuild')
                obj.syncOptsFromGui_();
                obj.setStep(obj.currentStep_, true);
            end
            obj.syncOptsFromGui_();
            styleChanged = obj.guiChanged_(oldState, {'solidColor','ghostColor', ...
                'vectorColor','deformedAlpha','undeformedAlpha','edgeRadius','nodeRadius','vectorRadius'});
            changed = obj.guiChanged_(oldState, {'cmapIdx','climIdx','onscreenColorbar','onscreenColorbarLocation','colorbarTitle'});
            if styleChanged
                obj.applyStyle_();
            end
            changed = changed || styleChanged;
            if changed
                obj.invalidateClimCache_();
            end
        end

        function registerSegment_(obj, segIdx)
            obj.clear_();
            obj.handles_ = struct();
            obj.lineData_ = struct();
            obj.surfData_ = struct();
            obj.volumeData_ = struct();
            obj.P0_ = obj.nodeCoords_(segIdx);
            obj.L_ = obj.modelLength_(obj.P0_);
            ps = obj.App.polyscopeHandle();

            obj.registerLineFamilies_(ps, segIdx);
            obj.registerSurfaceFamilies_(ps, segIdx);
            obj.registerVolumeFamilies_(ps, segIdx);
            if obj.Opts.nodes.show
                obj.registerNodes_(ps, segIdx);
            end
            if obj.Opts.fixed.show
                obj.registerFixed_(ps, segIdx);
            end
            if obj.Opts.vector.show
                obj.registerVectorCloud_(ps, segIdx);
            end
            obj.registerGhosts_(ps, segIdx);

            if ~obj.isOverlayScreenAxes_()
                obj.registerScreenAxes3D_();
            end
            obj.applyVisibility_();
            obj.applyStyle_();
            obj.registerSlicePlanes_();
            obj.applySliceCullWholeElements_();
        end

        function names = geometryFamilyNames_(obj, fam, kind)
            names = {};
            if ~isstruct(fam)
                return;
            end

            allNames = fieldnames(fam).';
            explicitNames = allNames(~strcmp(allNames, 'Unstructured'));
            fallbackNames = allNames(strcmp(allNames, 'Unstructured'));
            if isempty(explicitNames)
                scanNames = fallbackNames;
            else
                scanNames = explicitNames;
            end

            knownLine = [plotter.polyscope.ModelAdapter.lineFamilyNames(), {'Line'}];
            knownSurface = plotter.polyscope.ModelAdapter.surfaceFamilyNames();
            knownVolume = plotter.polyscope.ModelAdapter.volumeFamilyNames();

            for i = 1:numel(scanNames)
                nm = scanNames{i};
                S = fam.(nm);
                if ~isstruct(S) || ~isfield(S, 'Cells') || isempty(S.Cells)
                    continue;
                end
                hasTypes = isfield(S, 'CellTypes') && ~isempty(S.CellTypes);
                switch lower(kind)
                    case 'line'
                        isMatch = any(strcmp(nm, knownLine)) || ~hasTypes;
                    case 'surface'
                        isMatch = any(strcmp(nm, knownSurface)) || ...
                            (hasTypes && ~obj.isVolumeTypes_(double(S.CellTypes)) && ~any(strcmp(nm, knownLine)));
                    case 'volume'
                        isMatch = any(strcmp(nm, knownVolume)) || ...
                            (hasTypes && obj.isVolumeTypes_(double(S.CellTypes)));
                    otherwise
                        isMatch = false;
                end
                if isMatch
                    names{end+1} = nm; %#ok<AGROW>
                end
            end
            names = unique(names, 'stable');
        end

        function registerLineFamilies_(obj, ps, segIdx)
            fam = obj.families_(segIdx);
            if obj.Opts.interp.useInterpolation && obj.hasInterpData_(segIdx, 1)
                obj.registerInterpolatedLine_(ps, segIdx);
                return;
            end
            names = obj.geometryFamilyNames_(fam, 'line');
            for k = 1:numel(names)
                nm = names{k};
                if ~isfield(fam, nm), continue; end
                S = fam.(nm);
                if ~isfield(S, 'Cells') || isempty(S.Cells), continue; end
                edges = obj.cellsToLineEdges_(double(S.Cells), size(obj.P0_, 1));
                if isempty(edges), continue; end
                h = ps.register_curve_network(obj.structName_(nm, 'def'), obj.P0_, edges);
                h.set_color(obj.asRgb_(obj.gui_.solidColor));
                h.set_radius(obj.Opts.polyscope.edgeRadius, true);
                h.set_material(obj.Opts.polyscope.lineMaterial);
                obj.handles_.(['def_' nm]) = h;
                obj.lineData_.(nm) = struct('type', 'raw', 'edges', edges);
            end
        end

        function registerInterpolatedLine_(obj, ps, segIdx)
            [pts, ~, edges] = obj.interpSlice_(segIdx, 1);
            if isempty(pts) || isempty(edges), return; end
            h = ps.register_curve_network(obj.structName_('InterpLine', 'def'), pts, edges);
            h.set_color(obj.asRgb_(obj.gui_.solidColor));
            h.set_radius(obj.Opts.polyscope.edgeRadius, true);
            h.set_material(obj.Opts.polyscope.lineMaterial);
            obj.handles_.def_InterpLine = h;
            obj.lineData_.InterpLine = struct('type', 'interp', 'edges', edges, 'points', pts);
        end

        function registerSurfaceFamilies_(obj, ps, segIdx)
            fam = obj.families_(segIdx);
            names = obj.geometryFamilyNames_(fam, 'surface');
            for k = 1:numel(names)
                nm = names{k};
                if ~isfield(fam, nm), continue; end
                S = fam.(nm);
                if ~isfield(S, 'Cells') || ~isfield(S, 'CellTypes') || isempty(S.Cells), continue; end
                if obj.isVolumeTypes_(double(S.CellTypes)), continue; end
                out = plotter.utils.VTKElementTriangulator.triangulate(obj.P0_, double(S.CellTypes), double(S.Cells));
                if isempty(out.Points) || isempty(out.Triangles), continue; end
                h = ps.register_surface_mesh(obj.structName_(nm, 'def'), out.Points, out.Triangles, ...
                    'back_face_policy', obj.getOptField_(obj.Opts.polyscope, 'backFacePolicy', 'identical'));
                h.set_color(obj.asRgb_(obj.gui_.solidColor));
                h.set_material(obj.Opts.polyscope.surfaceMaterial);
                h.set_smooth_shade(obj.Opts.polyscope.surfaceSmoothShade);
                h.set_edge_width(0);
                obj.handles_.(['def_' nm]) = h;
                edgeHandle = obj.registerCellEdgeNetwork_(ps, nm, obj.P0_, double(S.CellTypes), double(S.Cells), 'def');
                pointNodeIds = out.PointNodeIds;
                if isempty(pointNodeIds)
                    pointNodeIds = (1:size(out.Points, 1)).';
                end
                obj.surfData_.(nm) = struct('cellTypes', double(S.CellTypes), 'cells', double(S.Cells), ...
                    'points', out.Points, 'triangles', out.Triangles, 'pointNodeIds', pointNodeIds, ...
                    'edgeHandle', edgeHandle);
            end
        end

        function registerVolumeFamilies_(obj, ps, segIdx)
            fam = obj.families_(segIdx);
            names = obj.geometryFamilyNames_(fam, 'volume');
            for k = 1:numel(names)
                nm = names{k};
                if ~isfield(fam, nm), continue; end
                S = fam.(nm);
                if ~isfield(S, 'Cells') || ~isfield(S, 'CellTypes') || isempty(S.Cells), continue; end
                if ~obj.isVolumeTypes_(double(S.CellTypes)), continue; end
                vol = plotter.utils.VTKElementTriangulator.volumize(obj.P0_, double(S.CellTypes), double(S.Cells));
                if isempty(vol.Points) || (isempty(vol.Tets) && isempty(vol.Hexes))
                    continue;
                end
                h = obj.registerVolumeMesh_(ps, obj.structName_(nm, 'def'), vol.Points, vol.Tets, vol.Hexes);
                h.set_color(obj.asRgb_(obj.gui_.solidColor));
                try
                    h.set_interior_color(obj.asRgb_(obj.gui_.solidColor));
                catch
                end
                h.set_material(obj.Opts.polyscope.surfaceMaterial);
                obj.handles_.(['def_' nm]) = h;
                edgeHandle = obj.registerCellEdgeNetwork_(ps, nm, obj.P0_, double(S.CellTypes), double(S.Cells), 'def');
                obj.volumeData_.(nm) = struct('cellTypes', double(S.CellTypes), 'cells', double(S.Cells), ...
                    'edgeHandle', edgeHandle);
            end
        end

        function h = registerVolumeMesh_(~, ps, name, V, tets, hexes)
            if ~isempty(tets) && ~isempty(hexes)
                h = ps.register_tet_hex_mesh(name, V, tets, hexes);
            elseif ~isempty(tets)
                h = ps.register_tet_mesh(name, V, tets);
            else
                h = ps.register_hex_mesh(name, V, hexes);
            end
        end

        function h = registerEdgeNetwork_(obj, ps, base, edgePoints, prefix)
            h = [];
            if isempty(edgePoints), return; end
            [nodes, edges] = plotter.polyscope.ModelAdapter.edgePointsToCurveNetwork(edgePoints);
            if isempty(nodes) || isempty(edges), return; end
            h = ps.register_curve_network(obj.structName_([base 'Edges'], prefix), nodes, edges);
            h.set_color(obj.asRgb_(plotter.polyscope.utils.colorToRgb(obj.Opts.surf.edgeColor)));
            h.set_radius(obj.Opts.polyscope.edgeRadius * 0.65, true);
            h.set_material(obj.Opts.polyscope.lineMaterial);
        end

        function h = registerCellEdgeNetwork_(obj, ps, base, P, cellTypes, cells, prefix)
            h = [];
            edges = obj.cellsToElementEdges_(cellTypes, cells, size(P, 1));
            if isempty(edges), return; end
            h = ps.register_curve_network(obj.structName_([base 'Edges'], prefix), P, edges);
            h.set_color(obj.asRgb_(plotter.polyscope.utils.colorToRgb(obj.Opts.surf.edgeColor)));
            h.set_radius(obj.Opts.polyscope.edgeRadius * 0.55, true);
            h.set_material(obj.Opts.polyscope.lineMaterial);
        end

        function registerNodes_(obj, ps, ~)
            h = ps.register_point_cloud(obj.structName_('Nodes', 'def'), obj.P0_);
            h.set_radius(obj.Opts.polyscope.nodeRadius, true);
            h.set_color(obj.asRgb_(obj.gui_.solidColor));
            h.set_point_render_mode(obj.Opts.polyscope.pointRenderMode);
            h.set_material(obj.Opts.polyscope.lineMaterial);
            obj.handles_.def_Nodes = h;
        end

        function registerFixed_(obj, ps, segIdx)
            [Pfix, ~] = obj.fixedNodes_(segIdx);
            if isempty(Pfix), return; end
            h = ps.register_point_cloud(obj.structName_('Fixed', 'def'), Pfix);
            h.set_radius(obj.Opts.polyscope.nodeRadius * 1.6, true);
            h.set_color(obj.asRgb_(plotter.polyscope.utils.colorToRgb(obj.Opts.fixed.color)));
            h.set_point_render_mode(obj.Opts.polyscope.pointRenderMode);
            obj.handles_.def_Fixed = h;
        end

        function registerVectorCloud_(obj, ps, ~)
            h = ps.register_point_cloud(obj.structName_('Vectors', 'def'), obj.P0_);
            h.set_radius(max(obj.Opts.polyscope.nodeRadius * 0.15, 0.0005), true);
            h.set_color(obj.asRgb_(obj.gui_.vectorColor));
            h.set_enabled(obj.Opts.vector.show);
            obj.handles_.def_Vectors = h;
        end

        function registerGhosts_(obj, ps, segIdx)
            if ~obj.Opts.deform.showUndeformed, return; end
            names = fieldnames(obj.lineData_);
            for k = 1:numel(names)
                nm = names{k};
                data = obj.lineData_.(nm);
                if isfield(data, 'points') && ~isempty(data.points)
                    Pghost = data.points;
                else
                    Pghost = obj.P0_;
                end
                h = ps.register_curve_network(obj.structName_(nm, 'ghost'), Pghost, data.edges);
                h.set_color(obj.asRgb_(obj.gui_.ghostColor));
                h.set_radius(obj.Opts.polyscope.edgeRadius * 0.75, true);
                h.set_transparency(obj.Opts.color.undeformedAlpha);
                obj.handles_.(['ghost_' nm]) = h;
            end
            fam = obj.families_(segIdx);
            names = [obj.geometryFamilyNames_(fam, 'surface'), obj.geometryFamilyNames_(fam, 'volume')];
            names = unique(names, 'stable');
            for k = 1:numel(names)
                nm = names{k};
                if ~isfield(fam, nm), continue; end
                S = fam.(nm);
                if ~isfield(S, 'Cells') || ~isfield(S, 'CellTypes'), continue; end
                h = obj.registerCellEdgeNetwork_(ps, [nm 'Ghost'], obj.P0_, double(S.CellTypes), double(S.Cells), 'ghost');
                if ~isempty(h)
                    h.set_color(obj.asRgb_(obj.gui_.ghostColor));
                    h.set_transparency(obj.Opts.color.undeformedAlpha);
                    obj.handles_.(['ghost_' nm]) = h;
                end
            end
        end

        function registerMissingOptionalStructures_(obj)
            if obj.currentSeg_ < 1
                return;
            end
            ps = obj.App.polyscopeHandle();
            if obj.Opts.nodes.show && ~isfield(obj.handles_, 'def_Nodes')
                obj.registerNodes_(ps, obj.currentSeg_);
            end
            if obj.Opts.fixed.show && ~isfield(obj.handles_, 'def_Fixed')
                obj.registerFixed_(ps, obj.currentSeg_);
            end
            if obj.Opts.vector.show && ~isfield(obj.handles_, 'def_Vectors')
                obj.registerVectorCloud_(ps, obj.currentSeg_);
            end
            if obj.Opts.deform.showUndeformed && ~obj.hasGhostHandles_()
                obj.registerGhosts_(ps, obj.currentSeg_);
            end
            obj.updateNodeStructures_(obj.nodeCoordsForCurrentStep_(), [], {}, obj.currentSeg_, obj.scalarQuantityName_());
            obj.updateVectorStructure_(obj.nodeCoordsForCurrentStep_(), obj.currentSeg_, obj.currentLocalStep_);
            obj.applyStyle_();
        end

        function updateStep_(obj, segIdx, localStep)
            if segIdx < 1 || isempty(obj.P0_), return; end
            Pbase = obj.nodeCoords_(segIdx);
            [Pdef, ~, scale] = obj.deformedCoords_(Pbase, segIdx, localStep);
            Pdef = obj.interpAdjustedNodeCoords_(Pbase, Pdef, segIdx, localStep, scale);
            [Snode, clim] = obj.scalarField_(segIdx, localStep);
            qargs = obj.scalarArgs_(clim);
            scalarName = obj.scalarQuantityName_();

            obj.updateLineStructures_(Pdef, Snode, qargs, scalarName);
            obj.updateSurfaceStructures_(Pdef, Snode, qargs, scalarName);
            obj.updateVolumeStructures_(Pdef, Snode, qargs, scalarName);
            obj.updateNodeStructures_(Pdef, Snode, qargs, segIdx, scalarName);
            obj.updateVectorStructure_(Pdef, segIdx, localStep);
            obj.applyVisibility_();

            if scale > 0 && obj.Opts.deform.show
                obj.App.polyscopeHandle().set_program_name(sprintf('OpenSeesMatlab | Nodal response | step %d | scale %.4g - by Yexiang Yan', obj.currentStep_, scale));
            end
        end

        function updateLineStructures_(obj, Pdef, Snode, qargs, qname)
            names = fieldnames(obj.lineData_);
            for k = 1:numel(names)
                nm = names{k};
                hName = ['def_' names{k}];
                if ~isfield(obj.handles_, hName), continue; end
                h = obj.handles_.(hName);
                data = obj.lineData_.(nm);
                if isfield(data, 'type') && strcmpi(data.type, 'interp')
                    [Pline, Sline] = obj.interpLineStep_(obj.currentSeg_, obj.currentLocalStep_, Snode);
                    if isempty(Pline), continue; end
                    h.update_node_positions(Pline);
                    if ~isempty(Sline)
                        iqargs = qargs;
                        mode = char(string(obj.Opts.color.climMode));
                        if strcmpi(char(string(obj.Opts.field.type)), 'disp') && ...
                                any(strcmpi(mode, {'step','local','current'}))
                            iqargs = obj.scalarArgs_(obj.localClim_(Sline));
                        end
                        h.add_node_scalar_quantity(qname, Sline, iqargs{:});
                    else
                        h.add_node_scalar_quantity(qname, zeros(size(Pline, 1), 1), 'enabled', false);
                    end
                else
                    h.update_node_positions(Pdef);
                    if ~isempty(Snode)
                        h.add_node_scalar_quantity(qname, Snode, qargs{:});
                    else
                        h.add_node_scalar_quantity(qname, zeros(size(Pdef, 1), 1), 'enabled', false);
                    end
                end
            end
        end

        function [Pline, Sline] = interpLineStep_(obj, segIdx, localStep, Snode)
            Pline = zeros(0, 3);
            Sline = [];
            [pts, dispVals, ~] = obj.interpSlice_(segIdx, localStep);
            if isempty(pts), return; end
            Pline = pts;
            if obj.Opts.deform.show
                U3 = zeros(size(dispVals, 1), 3);
                U3(:, 1:min(3, size(dispVals, 2))) = dispVals(:, 1:min(3, size(dispVals, 2)));
                U3(~isfinite(U3)) = 0;
                Unode = obj.respSlice_(segIdx, obj.Opts.deform.type, localStep);
                Unode3 = zeros(size(Unode, 1), 3);
                Unode3(:, 1:min(3, size(Unode, 2))) = Unode(:, 1:min(3, size(Unode, 2)));
                Pline = pts + obj.deformScale_(obj.nodeCoords_(segIdx), Unode3) * U3;
            end
            if isempty(Snode)
                return;
            end
            if strcmpi(char(string(obj.Opts.field.type)), 'disp')
                Sline = obj.scalarFromComp_(dispVals, obj.Opts.field.component, obj.dofsForField_(segIdx, 'disp'));
            else
                Pnode = obj.nodeCoords_(segIdx);
                if numel(Snode) == size(Pnode, 1)
                    Sline = obj.mapScalarsByNearest_(pts, Pnode, Snode);
                else
                    Sline = [];
                end
            end
        end

        function Pdef = interpAdjustedNodeCoords_(obj, Pbase, Pdef, segIdx, localStep, scale)
            if ~obj.Opts.deform.show || scale == 0 || ~obj.hasInterpData_(segIdx, localStep)
                return;
            end
            [pts, dispVals, ~] = obj.interpSlice_(segIdx, localStep);
            if isempty(pts) || isempty(dispVals)
                return;
            end
            U3 = zeros(size(dispVals, 1), 3);
            U3(:, 1:min(3, size(dispVals, 2))) = dispVals(:, 1:min(3, size(dispVals, 2)));
            U3(~isfinite(U3)) = 0;

            L = obj.modelLength_(Pbase);
            tol2 = max(1e-10, 1e-7 * L)^2;
            for i = 1:size(Pbase, 1)
                d2 = sum((pts - Pbase(i, :)).^2, 2);
                [best, idx] = min(d2);
                if isfinite(best) && best <= tol2
                    Pdef(i, :) = Pbase(i, :) + scale * U3(idx, :);
                end
            end
        end

        function updateSurfaceStructures_(obj, Pdef, Snode, qargs, qname)
            names = fieldnames(obj.surfData_);
            for k = 1:numel(names)
                nm = names{k}; data = obj.surfData_.(nm);
                hName = ['def_' nm];
                if ~isfield(obj.handles_, hName), continue; end
                h = obj.handles_.(hName);
                ids = data.pointNodeIds(:);
                Ptri = Pdef(ids, :);
                h.update_vertex_positions(Ptri);
                if ~isempty(Snode)
                    Stri = Snode(ids);
                    h.add_vertex_scalar_quantity(qname, Stri, qargs{:});
                else
                    h.add_vertex_scalar_quantity(qname, zeros(size(Ptri, 1), 1), 'enabled', false);
                end
                obj.updateEdgeNetwork_(data.edgeHandle, Pdef);
            end
        end

        function updateVolumeStructures_(obj, Pdef, Snode, qargs, qname)
            names = fieldnames(obj.volumeData_);
            for k = 1:numel(names)
                nm = names{k}; data = obj.volumeData_.(nm);
                hName = ['def_' nm];
                if isfield(obj.handles_, hName)
                    h = obj.handles_.(hName);
                    h.update_vertex_positions(Pdef);
                    if ~isempty(Snode)
                        h.add_vertex_scalar_quantity(qname, Snode, qargs{:});
                    else
                        h.add_vertex_scalar_quantity(qname, zeros(size(Pdef, 1), 1), 'enabled', false);
                    end
                end
                obj.updateEdgeNetwork_(data.edgeHandle, Pdef);
            end
        end

        function updateNodeStructures_(obj, Pdef, Snode, qargs, segIdx, qname)
            if isfield(obj.handles_, 'def_Nodes')
                h = obj.handles_.def_Nodes;
                h.update_point_positions(Pdef);
                if ~isempty(Snode)
                    h.add_scalar_quantity(qname, Snode, qargs{:});
                else
                    h.add_scalar_quantity(qname, zeros(size(Pdef, 1), 1), 'enabled', false);
                end
            end
            if isfield(obj.handles_, 'def_Fixed')
                [Pfix, fixedRows] = obj.fixedNodes_(segIdx, Pdef);
                if ~isempty(Pfix)
                    obj.handles_.def_Fixed.update_point_positions(Pfix);
                    if ~isempty(Snode) && ~isempty(fixedRows)
                        obj.handles_.def_Fixed.add_scalar_quantity(qname, Snode(fixedRows), qargs{:});
                    else
                        obj.handles_.def_Fixed.add_scalar_quantity(qname, zeros(size(Pfix, 1), 1), 'enabled', false);
                    end
                end
            end
            try
                obj.App.polyscopeHandle().request_redraw();
            catch
            end
        end

        function updateVectorStructure_(obj, Pdef, segIdx, localStep)
            if ~isfield(obj.handles_, 'def_Vectors'), return; end
            h = obj.handles_.def_Vectors;
            h.update_point_positions(Pdef);
            V = obj.vectorField_(segIdx, localStep);
            if isempty(V), V = zeros(size(Pdef)); end
            h.add_vector_quantity(obj.vectorQuantityName_(), V, ...
                'enabled', obj.Opts.vector.show, ...
                'vectortype', 'standard', ...
                'length', obj.Opts.polyscope.vectorLength, ...
                'radius', obj.Opts.polyscope.vectorRadius, ...
                'color', obj.asRgb_(obj.gui_.vectorColor));
        end

        function updateEdgeNetwork_(~, h, P)
            if isempty(h) || isempty(P), return; end
            try
                h.update_node_positions(P);
            catch
            end
        end

        function applyVisibility_(obj)
            names = fieldnames(obj.lineData_);
            for k = 1:numel(names), obj.setEnabled_(['def_' names{k}], obj.Opts.line.show); end
            names = fieldnames(obj.surfData_);
            for k = 1:numel(names)
                obj.setEnabled_(['def_' names{k}], obj.Opts.surf.show);
                obj.setEdgeEnabled_(obj.surfData_.(names{k}).edgeHandle, obj.Opts.surf.showEdges && obj.Opts.surf.show);
            end
            names = fieldnames(obj.volumeData_);
            for k = 1:numel(names)
                obj.setEnabled_(['def_' names{k}], obj.Opts.surf.show);
                obj.setEdgeEnabled_(obj.volumeData_.(names{k}).edgeHandle, obj.Opts.surf.showEdges && obj.Opts.surf.show);
            end
            obj.setEnabled_('def_Nodes', obj.Opts.nodes.show);
            obj.setEnabled_('def_Fixed', obj.Opts.fixed.show);
            obj.setEnabled_('def_Vectors', obj.Opts.vector.show);
            ghostNames = fieldnames(obj.handles_);
            for k = 1:numel(ghostNames)
                if startsWith(ghostNames{k}, 'ghost_')
                    obj.setEnabled_(ghostNames{k}, obj.Opts.deform.showUndeformed);
                end
            end
        end

        function applyStyle_(obj)
            allNames = fieldnames(obj.handles_);
            for k = 1:numel(allNames)
                h = obj.handles_.(allNames{k});
                try
                    if contains(allNames{k}, 'ghost_')
                        h.set_color(obj.asRgb_(obj.gui_.ghostColor));
                        h.set_transparency(obj.Opts.color.undeformedAlpha);
                    elseif contains(allNames{k}, 'Vectors')
                        h.set_color(obj.asRgb_(obj.gui_.vectorColor));
                    else
                        h.set_color(obj.asRgb_(obj.gui_.solidColor));
                        if isa(h, 'polyscope.SurfaceMesh') || isa(h, 'polyscope.VolumeMesh')
                            h.set_transparency(obj.Opts.color.deformedAlpha);
                        end
                        if isa(h, 'polyscope.VolumeMesh')
                            try
                                h.set_interior_color(obj.asRgb_(obj.gui_.solidColor));
                            catch
                            end
                        end
                    end
                catch
                end
                try
                    if isa(h, 'polyscope.CurveNetwork')
                        if contains(allNames{k}, 'Edges') || contains(allNames{k}, 'ghost_')
                            h.set_radius(obj.Opts.polyscope.edgeRadius * 0.55, true);
                        else
                            h.set_radius(obj.Opts.polyscope.edgeRadius, true);
                        end
                    elseif isa(h, 'polyscope.PointCloud')
                        if contains(allNames{k}, 'Vectors')
                            h.set_radius(max(obj.Opts.polyscope.vectorRadius * 0.2, 0.0002), true);
                        elseif contains(allNames{k}, 'Fixed')
                            h.set_radius(obj.Opts.polyscope.nodeRadius * 1.4, true);
                        else
                            h.set_radius(obj.Opts.polyscope.nodeRadius, true);
                        end
                    end
                catch
                end
            end
        end

        function setEnabled_(obj, name, tf)
            if isfield(obj.handles_, name)
                try
                    obj.handles_.(name).set_enabled(tf);
                catch
                end
            end
        end

        function setEdgeEnabled_(~, h, tf)
            if ~isempty(h)
                try
                    h.set_enabled(tf);
                catch
                end
            end
        end

        function tf = hasGhostHandles_(obj)
            names = fieldnames(obj.handles_);
            tf = any(startsWith(names, 'ghost_'));
        end

        function syncOptsFromGui_(obj)
            obj.Opts.field.show = logical(obj.gui_.showField);
            obj.Opts.color.useColormap = logical(obj.gui_.useColormap);
            obj.Opts.deform.show = logical(obj.gui_.showDeform);
            obj.Opts.deform.autoScale = logical(obj.gui_.autoScale);
            obj.Opts.deform.scale = obj.gui_.deformScale;
            obj.Opts.deform.showUndeformed = logical(obj.gui_.showUndeformed);
            obj.Opts.line.show = logical(obj.gui_.showLines);
            obj.Opts.interp.useInterpolation = logical(obj.gui_.useInterpolation);
            obj.Opts.surf.show = logical(obj.gui_.showSurfaces);
            obj.Opts.surf.showEdges = logical(obj.gui_.showSurfaceEdges);
            obj.Opts.nodes.show = logical(obj.gui_.showNodes);
            obj.Opts.fixed.show = logical(obj.gui_.showFixed);
            obj.Opts.vector.show = logical(obj.gui_.showVectors);
            obj.Opts.vector.autoScale = logical(obj.gui_.vectorAuto);
            obj.Opts.vector.scale = obj.gui_.vectorScale;
            obj.Opts.polyscope.edgeRadius = obj.gui_.edgeRadius;
            obj.Opts.polyscope.nodeRadius = obj.gui_.nodeRadius;
            obj.Opts.polyscope.vectorRadius = obj.gui_.vectorRadius;
            obj.Opts.color.deformedAlpha = obj.gui_.deformedAlpha;
            obj.Opts.color.undeformedAlpha = obj.gui_.undeformedAlpha;
            obj.Opts.color.solidColor = obj.asRgb_(obj.gui_.solidColor);
            obj.Opts.color.undeformedColor = obj.asRgb_(obj.gui_.ghostColor);
            obj.Opts.vector.color = obj.asRgb_(obj.gui_.vectorColor);
        end

        function advanceAnimation_(obj)
            if ~isfield(obj.gui_, 'animationMode') || ~obj.gui_.animationMode || ...
               ~isfield(obj.gui_, 'playing') || ~obj.gui_.playing || obj.nSteps_ <= 1
                return;
            end
            obj.stepAnimationOnce_();
        end

        function stepAnimationOnce_(obj)
            next = obj.gui_.step + obj.gui_.animDir;
            if next > obj.nSteps_ - 1 || next < 0
                if obj.gui_.pingpong
                    obj.gui_.animDir = -obj.gui_.animDir;
                    next = obj.gui_.step + obj.gui_.animDir;
                elseif obj.gui_.loop
                    next = 0;
                else
                    obj.gui_.playing = false;
                    next = max(0, min(obj.nSteps_ - 1, next));
                end
            end
            obj.setStep(next);
        end

        function [Pdef, U3, scale] = deformedCoords_(obj, P, segIdx, localStep)
            U = obj.respSlice_(segIdx, obj.Opts.deform.type, localStep);
            U3 = zeros(size(P, 1), 3);
            U3(:, 1:min(3, size(U, 2))) = U(:, 1:min(3, size(U, 2)));
            U3(~isfinite(U3)) = 0;
            if obj.Opts.deform.show
                scale = obj.deformScale_(P, U3);
                Pdef = P + scale * U3(:, 1:size(P, 2));
            else
                scale = 0;
                Pdef = P;
            end
        end

        function Pdef = nodeCoordsForCurrentStep_(obj)
            if obj.currentSeg_ < 1
                Pdef = obj.P0_;
                return;
            end
            Pbase = obj.nodeCoords_(obj.currentSeg_);
            [Pdef, ~, scale] = obj.deformedCoords_(Pbase, obj.currentSeg_, obj.currentLocalStep_);
            Pdef = obj.interpAdjustedNodeCoords_(Pbase, Pdef, obj.currentSeg_, obj.currentLocalStep_, scale);
        end

        function scale = deformScale_(obj, P, U3)
            if ~obj.Opts.deform.autoScale
                scale = obj.Opts.deform.scale;
                return;
            end
            if isfield(obj.gui_, 'animationMode') && obj.gui_.animationMode
                umax = obj.globalDeformUmax_();
            else
                umax = max(sqrt(sum(U3.^2, 2)), [], 'omitnan');
            end
            if ~isfinite(umax) || umax <= 0
                scale = obj.Opts.deform.scale;
            else
                scale = obj.Opts.deform.scale * obj.modelLength_(P) / (10 * umax);
            end
        end

        function umax = globalDeformUmax_(obj)
            key = matlab.lang.makeValidName(sprintf('%s_%d_%s', ...
                char(string(obj.Opts.deform.type)), obj.nSteps_, obj.stepShapeSignature_()));
            umax = obj.cachedRange_('nodalDeform', key, @() obj.computeGlobalDeformUmax_());
        end

        function umax = computeGlobalDeformUmax_(obj)
            umax = 0;
            for g = 0:obj.nSteps_ - 1
                [segIdx, localStep] = obj.resolveGlobalStep_(g);
                U = obj.respSlice_(segIdx, obj.Opts.deform.type, localStep);
                U3 = zeros(size(U, 1), 3);
                U3(:, 1:min(3, size(U, 2))) = U(:, 1:min(3, size(U, 2)));
                U3(~isfinite(U3)) = 0;
                mag = max(sqrt(sum(U3.^2, 2)), [], 'omitnan');
                if isfinite(mag)
                    umax = max(umax, mag);
                end
            end
        end

        function [S, clim] = scalarField_(obj, segIdx, localStep)
            if obj.Opts.field.show && obj.Opts.color.useColormap
                U = obj.respSlice_(segIdx, obj.Opts.field.type, localStep);
                S = obj.scalarFromComp_(U, obj.Opts.field.component, obj.dofsForField_(segIdx, obj.Opts.field.type));
                clim = obj.resolveClim_(S);
                % NaN marks nodes which do not exist in this model-update
                % segment. Polyscope buffers must nevertheless be finite.
                S(~isfinite(S)) = 0;
            else
                S = [];
                clim = [];
            end
        end

        function V = vectorField_(obj, segIdx, localStep)
            U = obj.respSlice_(segIdx, obj.Opts.vector.type, localStep);
            V = zeros(size(U, 1), 3);
            V(:, 1:min(3, size(U, 2))) = U(:, 1:min(3, size(U, 2)));
            V(~isfinite(V)) = 0;
            mag = max(sqrt(sum(V.^2, 2)), [], 'omitnan');
            if obj.Opts.vector.autoScale && isfinite(mag) && mag > 0
                V = V * (obj.modelLength_(obj.nodeCoords_(segIdx)) * obj.Opts.vector.scale / mag);
            else
                V = V * obj.Opts.vector.scale;
            end
        end

        function args = scalarArgs_(obj, clim)
            cmap = obj.Opts.polyscope.scalarColorMap;
            if ischar(obj.Opts.color.colormap) || isstring(obj.Opts.color.colormap)
                cmap = lower(char(string(obj.Opts.color.colormap)));
            end
            args = {'enabled', obj.Opts.field.show && obj.Opts.color.useColormap, ...
                    'color_map', cmap};
            if ~isempty(clim) && numel(clim) == 2 && all(isfinite(clim))
                args = [args, {'map_range', double(clim(:).')}];
            end
            args = [args, obj.colorbarArgs_()];
        end

        function name = scalarQuantityName_(obj)
            name = obj.quantityName_(obj.Opts.field.type, obj.Opts.field.component);
        end

        function name = quantityName_(~, fieldType, component)
            fld = char(string(fieldType));
            comp = char(string(component));
            if isempty(comp) || any(strcmpi(comp, {'magnitude','mag'}))
                name = [fld ' magnitude'];
            else
                name = [fld ' ' comp];
            end
        end

        function name = vectorQuantityName_(obj)
            name = char(string(obj.Opts.vector.type));
        end

        function clim = resolveClim_(obj, S)
            if ~isempty(obj.Opts.color.clim) && numel(obj.Opts.color.clim) == 2
                clim = obj.Opts.color.clim;
                return;
            end
            mode = lower(char(string(obj.Opts.color.climMode)));
            switch mode
                case {'global','range','absmax','absmin'}
                    [lo, hi] = obj.globalClim_();
                    if strcmp(mode, 'absmax'), m = max(abs([lo hi])); clim = [-m m];
                    elseif strcmp(mode, 'absmin'), m = min(abs([lo hi])); clim = [-m m];
                    else, clim = [lo hi];
                    end
                otherwise
                    clim = obj.localClim_(S);
            end
        end

        function [lo, hi] = globalClim_(obj)
            range = obj.cachedRange_('nodalClim', obj.climCacheKey_(), @() obj.computeGlobalClim_());
            lo = range(1);
            hi = range(2);
        end

        function range = computeGlobalClim_(obj)
            lo = inf; hi = -inf;
            for g = 0:obj.nSteps_-1
                [si, ls] = obj.resolveGlobalStep_(g);
                U = obj.respSlice_(si, obj.Opts.field.type, ls);
                S = obj.scalarFromComp_(U, obj.Opts.field.component, obj.dofsForField_(si, obj.Opts.field.type));
                Sf = S(isfinite(S));
                if isempty(Sf), continue; end
                lo = min(lo, min(Sf));
                hi = max(hi, max(Sf));
            end
            if ~isfinite(lo), lo = 0; end
            if ~isfinite(hi), hi = 1; end
            if lo == hi, hi = lo + 1; end
            range = [lo, hi];
        end

        function key = climCacheKey_(obj)
            key = sprintf('%s|%s|%d', char(string(obj.Opts.field.type)), ...
                char(string(obj.Opts.field.component)), obj.nSteps_);
        end

        function invalidateClimCache_(obj)
            obj.invalidateCachedRange_('nodalClim');
            obj.invalidateCachedRange_('nodalDeform');
            obj.extremeStepCache_ = struct();
        end

        function invalidateHistoryCache_(obj)
            obj.historyCacheKey_ = '';
            obj.historyCacheX_ = [];
            obj.historyCacheY_ = [];
            obj.historyCacheLabel_ = '';
        end

        function [x, y, label] = nodeHistorySeries_(obj)
            key = obj.historyCacheKeyForGui_();
            if strcmp(obj.historyCacheKey_, key) && ~isempty(obj.historyCacheX_)
                x = obj.historyCacheX_;
                y = obj.historyCacheY_;
                label = obj.historyCacheLabel_;
                return;
            end
            x = NaN(obj.nSteps_, 1);
            y = NaN(obj.nSteps_, 1);
            [fieldType, comp] = obj.historyFieldSpec_();
            label = obj.quantityName_(fieldType, comp);
            useTag = isfield(obj.gui_, 'historyUseTag') && obj.gui_.historyUseTag;
            targetTag = obj.getOptField_(obj.gui_, 'historyNodeTag', NaN);
            targetIndex = round(obj.getOptField_(obj.gui_, 'historyNodeIndex', 1));

            for g = 0:obj.nSteps_ - 1
                [si, ls] = obj.resolveGlobalStep_(g);
                x(g + 1) = obj.timeAtStep_(si, ls, g);
                nr = obj.NodalResp(si);
                ft = obj.normalizeField_(si, fieldType);
                if ~isfield(nr, ft)
                    continue;
                end
                entry = nr.(ft);
                [Uraw, dofs] = obj.rawRespArray_(entry, ls);
                if isempty(Uraw)
                    continue;
                end
                tags = obj.respTags_(nr, entry);
                if isempty(tags)
                    tags = (1:size(Uraw, 1)).';
                end
                if useTag
                    row = find(tags == targetTag, 1);
                else
                    row = targetIndex;
                end
                if isempty(row) || row < 1 || row > size(Uraw, 1)
                    continue;
                end
                S = obj.scalarFromComp_(Uraw, comp, dofs);
                if row <= numel(S)
                    y(g + 1) = S(row);
                end
            end

            obj.historyCacheKey_ = key;
            obj.historyCacheX_ = x;
            obj.historyCacheY_ = y;
            obj.historyCacheLabel_ = label;
        end

        function key = historyCacheKeyForGui_(obj)
            [fieldType, comp] = obj.historyFieldSpec_();
            key = sprintf('%s|%s|tag:%g|idx:%g|useTag:%d|n:%d', ...
                char(string(fieldType)), ...
                char(string(comp)), ...
                obj.getOptField_(obj.gui_, 'historyNodeTag', NaN), ...
                obj.getOptField_(obj.gui_, 'historyNodeIndex', NaN), ...
                logical(obj.getOptField_(obj.gui_, 'historyUseTag', true)), ...
                obj.nSteps_);
        end

        function [fieldType, comp] = historyFieldSpec_(obj)
            hFieldIdx = round(obj.getOptField_(obj.gui_, 'historyFieldIdx', obj.gui_.fieldIdx));
            hFieldIdx = max(1, min(numel(obj.fieldTypes_), hFieldIdx));
            fieldType = obj.fieldTypes_{hFieldIdx};
            comps = obj.componentsForField_(fieldType);
            if isempty(comps), comps = {'magnitude'}; end
            hCompIdx = round(obj.getOptField_(obj.gui_, 'historyCompIdx', 1));
            hCompIdx = max(1, min(numel(comps), hCompIdx));
            comp = comps{hCompIdx};
        end

        function idx = historyNodeIndex_(obj, tags)
            idx = round(obj.getOptField_(obj.gui_, 'historyNodeIndex', 1));
            if obj.getOptField_(obj.gui_, 'historyUseTag', true)
                hit = find(tags == obj.getOptField_(obj.gui_, 'historyNodeTag', NaN), 1);
                if ~isempty(hit), idx = hit; end
            end
            idx = max(1, min(numel(tags), idx));
        end

        function tags = historyTags_(obj, segIdx)
            tags = [];
            if isempty(obj.NodalResp), return; end
            segIdx = max(1, min(numel(obj.NodalResp), segIdx));
            nr = obj.NodalResp(segIdx);
            if isfield(nr, 'nodeTags') && ~isempty(nr.nodeTags)
                tags = double(nr.nodeTags(:));
                return;
            end
            ft = obj.normalizeField_(segIdx, obj.Opts.field.type);
            if isfield(nr, ft)
                tags = obj.respTags_(nr, nr.(ft));
            end
            if isempty(tags)
                P = obj.nodeCoords_(segIdx);
                tags = obj.nodeTags_(segIdx, size(P, 1));
            end
        end

        function t = timeAtStep_(obj, segIdx, localStep, globalStep)
            t = double(globalStep);
            nr = obj.NodalResp(segIdx);
            if isfield(nr, 'time') && ~isempty(nr.time)
                tv = double(nr.time(:));
                if localStep >= 1 && localStep <= numel(tv)
                    t = tv(localStep);
                end
            end
        end

        function clim = localClim_(~, S)
            Sf = S(isfinite(S));
            if isempty(Sf), clim = [0 1]; return; end
            clim = [min(Sf), max(Sf)];
            if clim(1) == clim(2), clim(2) = clim(1) + 1; end
        end

        function S = scalarFromComp_(~, U, comp, dofs)
            if nargin < 4, dofs = {}; end
            comp = lower(char(string(comp)));
            map = struct('ux',1,'uy',2,'uz',3,'rx',4,'ry',5,'rz',6);
            col = 0;
            for i = 1:numel(dofs)
                if strcmpi(dofs{i}, comp), col = i; break; end
            end
            if col == 0 && isfield(map, comp), col = map.(comp); end
            if any(strcmp(comp, {'magnitude','mag'}))
                Uuse = U(:, 1:min(3, size(U, 2)));
                S = sqrt(sum(Uuse.^2, 2, 'omitnan'));
            elseif col > 0 && size(U, 2) >= col
                S = U(:, col);
            elseif size(U, 2) == 1
                S = U(:, 1);
            else
                Uuse = U(:, 1:min(3, size(U, 2)));
                S = sqrt(sum(Uuse.^2, 2, 'omitnan'));
            end
            S = double(S(:));
        end

        function U = respSlice_(obj, segIdx, fieldType, localStep)
            P = obj.nodeCoords_(segIdx);
            tags = obj.nodeTags_(segIdx, size(P, 1));
            U = NaN(size(P, 1), 6);
            fieldType = obj.normalizeField_(segIdx, fieldType);
            nr = obj.NodalResp(segIdx);
            if ~isfield(nr, fieldType), return; end
            [Uraw, dofs] = obj.rawRespArray_(nr.(fieldType), localStep);
            if isempty(Uraw), return; end
            ncol = min(size(Uraw, 2), 6);
            respTags = obj.respTags_(nr, nr.(fieldType));
            if ~isempty(respTags) && ~isempty(tags)
                rows = obj.mapTags_(segIdx, tags, respTags);
                valid = rows > 0 & rows <= size(Uraw, 1);
                U(valid, 1:ncol) = Uraw(rows(valid), 1:ncol);
            else
                n = min(size(P, 1), size(Uraw, 1));
                U(1:n, 1:ncol) = Uraw(1:n, 1:ncol);
            end
            if ~isempty(dofs) && size(Uraw, 2) ~= 6
                % Keep physical order supplied by dofs; scalarFromComp_ uses it.
            end
        end

        function [Uraw, dofs] = rawRespArray_(obj, entry, localStep)
            Uraw = []; dofs = {};
            if isstruct(entry) && isfield(entry, 'data')
                A = entry.data; dofs = obj.normalizeDofs_(obj.getOptField_(entry, 'dofs', {}));
            elseif isstruct(entry)
                dofs = obj.normalizeDofs_(fieldnames(entry));
                dofs = dofs(~ismember(lower(dofs), {'dofs','nodetags','time'}));
                if isempty(dofs), return; end
                ref = [];
                for i = 1:numel(dofs)
                    if isfield(entry, dofs{i}) && isnumeric(entry.(dofs{i}))
                        ref = entry.(dofs{i}); break;
                    end
                end
                if isempty(ref), return; end
                si = min(localStep, size(ref, 1));
                Uraw = zeros(size(ref, 2), numel(dofs));
                for i = 1:numel(dofs)
                    if isfield(entry, dofs{i}) && isnumeric(entry.(dofs{i}))
                        A = entry.(dofs{i});
                        Uraw(:, i) = double(A(si, :)).';
                    end
                end
                return;
            else
                A = entry;
            end
            if ~isnumeric(A) || isempty(A) || (~ismatrix(A) && ndims(A) < 2)
                return;
            end
            si = min(localStep, size(A, 1));
            if ismatrix(A)
                Uraw = double(A(si, :).');
            else
                Uraw = double(reshape(A(si, :, :), size(A, 2), size(A, 3)));
            end
        end

        function dofs = dofsForField_(obj, segIdx, fieldType)
            dofs = {};
            nr = obj.NodalResp(segIdx);
            fieldType = obj.normalizeField_(segIdx, fieldType);
            if ~isfield(nr, fieldType), return; end
            entry = nr.(fieldType);
            if isstruct(entry) && isfield(entry, 'dofs')
                dofs = obj.normalizeDofs_(entry.dofs);
            elseif isstruct(entry) && ~isfield(entry, 'data')
                dofs = obj.normalizeDofs_(fieldnames(entry));
                dofs = dofs(~ismember(lower(dofs), {'dofs','nodetags','time'}));
            end
        end

        function buildStepIndex_(obj)
            nSeg = numel(obj.NodalResp);
            obj.segStepCounts_ = zeros(1, nSeg);
            for s = 1:nSeg, obj.segStepCounts_(s) = obj.countSteps_(obj.NodalResp(s)); end
            obj.segOffsets_ = [0, cumsum(obj.segStepCounts_(1:end-1))];
            obj.nSteps_ = max(1, sum(obj.segStepCounts_));
            obj.respLookup_ = cell(1, nSeg);
            for s = 1:nSeg
                nr = obj.NodalResp(s);
                if isfield(nr, 'nodeTags') && ~isempty(nr.nodeTags)
                    tags = double(nr.nodeTags(:));
                    obj.respLookup_{s} = containers.Map(num2cell(tags), num2cell(1:numel(tags)));
                else
                    obj.respLookup_{s} = [];
                end
            end
        end

        function n = countSteps_(~, nr)
            if isfield(nr, 'time') && ~isempty(nr.time), n = numel(nr.time); return; end
            n = 1;
            f = fieldnames(nr);
            for i = 1:numel(f)
                if any(strcmpi(f{i}, {'odbTag','time','nodeTags'})), continue; end
                entry = nr.(f{i});
                if isstruct(entry) && isfield(entry, 'data'), A = entry.data;
                elseif isstruct(entry)
                    names = fieldnames(entry); A = [];
                    for j = 1:numel(names)
                        if isnumeric(entry.(names{j})), A = entry.(names{j}); break; end
                    end
                else, A = entry;
                end
                if isnumeric(A) && ndims(A) >= 2, n = size(A, 1); return; end
            end
        end

        function [segIdx, localStep] = resolveGlobalStep_(obj, step)
            step = max(0, min(obj.nSteps_ - 1, round(double(step))));
            segIdx = find(obj.segOffsets_ + obj.segStepCounts_ > step, 1, 'first');
            if isempty(segIdx), segIdx = numel(obj.segStepCounts_); end
            localStep = step - obj.segOffsets_(segIdx) + 1;
        end

        function step = resolveStepArg_(obj, arg)
            if isnumeric(arg), step = round(double(arg)); step = max(0, min(obj.nSteps_-1, step)); return; end
            key = lower(char(string(arg)));
            if ~ismember(key, {'absmax','absmin','max','min'}), step = 0; return; end
            cacheKey = obj.extremeStepCacheKey_(key);
            cacheField = obj.simpleHashField_(cacheKey);
            if isfield(obj.extremeStepCache_, cacheField)
                rec = obj.extremeStepCache_.(cacheField);
                if isstruct(rec) && isfield(rec, 'key') && strcmp(rec.key, cacheKey) && isfield(rec, 'step')
                    step = rec.step;
                    return;
                end
            end
            vals = zeros(obj.nSteps_, 1);
            for g = 0:obj.nSteps_-1
                [si, ls] = obj.resolveGlobalStep_(g);
                U = obj.respSlice_(si, obj.Opts.field.type, ls);
                S = obj.scalarFromComp_(U, obj.Opts.field.component, obj.dofsForField_(si, obj.Opts.field.type));
                switch key
                    case {'absmax','absmin'}, vals(g+1) = max(abs(S), [], 'omitnan');
                    case 'max', vals(g+1) = max(S, [], 'omitnan');
                    case 'min', vals(g+1) = min(S, [], 'omitnan');
                end
            end
            switch key
                case {'absmax','max'}, [~, idx] = max(vals);
                otherwise, [~, idx] = min(vals);
            end
            step = idx - 1;
            obj.extremeStepCache_.(cacheField) = struct('key', cacheKey, 'step', step);
        end

        function key = extremeStepCacheKey_(obj, mode)
            key = sprintf('%s|%s|%s|%d|%s', lower(char(string(mode))), ...
                char(string(obj.Opts.field.type)), char(string(obj.Opts.field.component)), ...
                obj.nSteps_, obj.stepShapeSignature_());
        end

        function sig = stepShapeSignature_(obj)
            sigParts = cell(1, numel(obj.NodalResp));
            for s = 1:numel(obj.NodalResp)
                nr = obj.NodalResp(s);
                field = char(string(obj.Opts.field.type));
                if isstruct(nr) && isfield(nr, field)
                    entry = nr.(field);
                    if isstruct(entry) && isfield(entry, 'data') && isnumeric(entry.data)
                        sz = size(entry.data);
                    elseif isnumeric(entry)
                        sz = size(entry);
                    else
                        sz = [0, 0];
                    end
                    sigParts{s} = [sprintf('%d:', s), char(strjoin(string(sz), 'x'))];
                else
                    sigParts{s} = sprintf('%d:none', s);
                end
            end
            sig = strjoin(sigParts, '|');
        end

        function field = simpleHashField_(~, txt)
            bytes = uint8(char(txt));
            h = uint32(2166136261);
            for ii = 1:numel(bytes)
                h = bitxor(h, uint32(bytes(ii)));
                h = uint32(mod(uint64(h) * uint64(16777619), uint64(2)^32));
            end
            field = sprintf('k_%08x', h);
        end

        function P = nodeCoords_(obj, segIdx)
            P = zeros(0, 3);
            mi = obj.ModelInfo(min(segIdx, numel(obj.ModelInfo)));
            if isfield(mi, 'Nodes') && isfield(mi.Nodes, 'Coords')
                P = double(mi.Nodes.Coords);
            end
            P = plotter.polyscope.ModelAdapter.pad3(P);
            c = obj.geometryCenter_(P);
            P = P - c;
        end

        function tags = nodeTags_(obj, segIdx, n)
            tags = (1:n).';
            mi = obj.ModelInfo(min(segIdx, numel(obj.ModelInfo)));
            if isfield(mi, 'Nodes') && isfield(mi.Nodes, 'Tags') && ~isempty(mi.Nodes.Tags)
                tags = double(mi.Nodes.Tags(:));
                tags = tags(1:min(n, numel(tags)));
            end
        end

        function fam = families_(obj, segIdx)
            fam = struct();
            mi = obj.ModelInfo(min(segIdx, numel(obj.ModelInfo)));
            if isfield(mi, 'Elements')
                E = mi.Elements;
                if isfield(E, 'Families'), fam = E.Families; else, fam = E; end
            end
        end

        function [Pfix, rows] = fixedNodes_(obj, segIdx, Poverride)
            if nargin < 3 || isempty(Poverride), P = obj.nodeCoords_(segIdx); else, P = Poverride; end
            rows = zeros(0, 1); Pfix = zeros(0, 3);
            mi = obj.ModelInfo(min(segIdx, numel(obj.ModelInfo)));
            if ~isfield(mi, 'Fixed') || ~isstruct(mi.Fixed), return; end
            F = mi.Fixed;
            rows = obj.fixedNodeRows_(segIdx, size(P, 1));
            if ~isempty(rows), Pfix = P(rows, :); return; end
            if nargin < 3 && isfield(F, 'Coords') && ~isempty(F.Coords)
                Pfix = plotter.polyscope.ModelAdapter.pad3(double(F.Coords));
                if isfield(mi, 'Nodes') && isfield(mi.Nodes, 'Coords')
                    rawP = plotter.polyscope.ModelAdapter.pad3(double(mi.Nodes.Coords));
                    if ~isempty(rawP)
                        Pfix = Pfix - obj.geometryCenter_(rawP);
                    end
                end
            end
        end

        function rows = fixedNodeRows_(obj, segIdx, nNode)
            rows = zeros(0, 1);
            mi = obj.ModelInfo(min(segIdx, numel(obj.ModelInfo)));
            if ~isfield(mi, 'Fixed') || ~isstruct(mi.Fixed), return; end
            F = mi.Fixed;
            if isfield(F, 'NodeIndex') && ~isempty(F.NodeIndex)
                rows = double(F.NodeIndex(:));
                rows = round(rows(isfinite(rows)));
                rows = rows(rows >= 1 & rows <= nNode);
                return;
            end
            if isfield(F, 'NodeTags') && ~isempty(F.NodeTags)
                tags = obj.nodeTags_(segIdx, nNode);
                [tf, loc] = ismember(double(F.NodeTags(:)), tags);
                rows = loc(tf);
                rows = rows(rows >= 1 & rows <= nNode);
                if ~isempty(rows), return; end
            end
            if isfield(F, 'Coords') && ~isempty(F.Coords) && ...
                    isfield(mi, 'Nodes') && isfield(mi.Nodes, 'Coords')
                Praw = plotter.polyscope.ModelAdapter.pad3(double(mi.Nodes.Coords));
                Craw = plotter.polyscope.ModelAdapter.pad3(double(F.Coords));
                if isempty(Praw) || isempty(Craw), return; end
                rows = NaN(size(Craw, 1), 1);
                for i = 1:size(Craw, 1)
                    d2 = sum((Praw - Craw(i, :)).^2, 2);
                    [best, idx] = min(d2);
                    if isfinite(best)
                        rows(i) = idx;
                    end
                end
                rows = unique(rows(isfinite(rows) & rows >= 1 & rows <= nNode), 'stable');
            end
        end

        function edges = cellsToLineEdges_(~, cells, nNode)
            edges = zeros(0, 2);
            if isempty(cells), return; end
            for i = 1:size(cells, 1)
                row = double(cells(i, :)); row = row(isfinite(row));
                if numel(row) >= 3 && row(1) == numel(row) - 1, ids = row(2:end); else, ids = row; end
                ids = round(ids(ids >= 1 & ids <= nNode));
                if numel(ids) >= 2
                    edges = [edges; [ids(1:end-1).', ids(2:end).']]; %#ok<AGROW>
                end
            end
        end

        function edges = cellsToElementEdges_(~, cellTypes, cells, nNode)
            edges = zeros(0, 2);
            if isempty(cells), return; end
            for i = 1:size(cells, 1)
                row = double(cells(i, :));
                row = row(isfinite(row));
                if isempty(row), continue; end
                if row(1) == numel(row) - 1
                    ids = row(2:end);
                else
                    ids = row;
                end
                ids = round(ids(ids >= 1 & ids <= nNode));
                if isempty(ids), continue; end
                if numel(cellTypes) >= i
                    ct = double(cellTypes(i));
                elseif ~isempty(cellTypes)
                    ct = double(cellTypes(1));
                else
                    ct = NaN;
                end
                switch ct
                    case {5, 21, 22}
                        loc = [1 2; 2 3; 3 1];
                    case {9, 23, 28}
                        loc = [1 2; 2 3; 3 4; 4 1];
                    case {10, 24}
                        loc = [1 2; 2 3; 3 1; 1 4; 2 4; 3 4];
                    case {12, 25, 29}
                        loc = [1 2; 2 3; 3 4; 4 1; ...
                               5 6; 6 7; 7 8; 8 5; ...
                               1 5; 2 6; 3 7; 4 8];
                    otherwise
                        if numel(ids) == 3
                            loc = [1 2; 2 3; 3 1];
                        elseif numel(ids) >= 8
                            loc = [1 2; 2 3; 3 4; 4 1; ...
                                   5 6; 6 7; 7 8; 8 5; ...
                                   1 5; 2 6; 3 7; 4 8];
                        elseif numel(ids) == 4
                            loc = [1 2; 2 3; 3 4; 4 1];
                        else
                            loc = [(1:numel(ids)-1).', (2:numel(ids)).'];
                        end
                end
                loc = loc(all(loc <= numel(ids), 2), :);
                if ~isempty(loc)
                    edges = [edges; ids(loc)]; %#ok<AGROW>
                end
            end
            if ~isempty(edges)
                edges = sort(edges, 2);
                edges = unique(edges, 'rows', 'stable');
            end
        end

        function tf = hasInterpData_(obj, segIdx, localStep)
            tf = false;
            if ~isfield(obj.Opts, 'interp') || ~obj.getOptField_(obj.Opts.interp, 'useInterpolation', true)
                return;
            end
            nr = obj.NodalResp(segIdx);
            tf = isfield(nr, 'interpolatePoints') && ...
                 isfield(nr, 'interpolateDisp') && ...
                 isfield(nr, 'interpolateCells') && ...
                 ~isempty(nr.interpolatePoints);
            if ~tf, return; end
            pts = nr.interpolatePoints;
            if ndims(pts) == 3
                si = min(localStep, size(pts, 1));
                pts = squeeze(pts(si, :, :));
                tf = ~isempty(pts) && any(isfinite(pts(:)));
            end
        end

        function [pts, dispVals, edges] = interpSlice_(obj, segIdx, localStep)
            pts = zeros(0, 3);
            dispVals = zeros(0, 3);
            edges = zeros(0, 2);
            if ~obj.hasInterpData_(segIdx, localStep), return; end
            nr = obj.NodalResp(segIdx);
            ptsRaw = double(nr.interpolatePoints);
            dispRaw = double(nr.interpolateDisp);
            cellsRaw = double(nr.interpolateCells);

            if ndims(ptsRaw) == 3
                ptsRaw = squeeze(ptsRaw(min(localStep, size(ptsRaw, 1)), :, :));
            end
            if ndims(dispRaw) == 3
                dispRaw = squeeze(dispRaw(min(localStep, size(dispRaw, 1)), :, :));
            end
            if ndims(cellsRaw) == 3
                cellsRaw = squeeze(cellsRaw(min(localStep, size(cellsRaw, 1)), :, :));
            end
            if isempty(ptsRaw), return; end
            if size(ptsRaw, 2) < 3, ptsRaw(:, end+1:3) = 0; end
            mi = obj.ModelInfo(min(segIdx, numel(obj.ModelInfo)));
            if isfield(mi, 'Nodes') && isfield(mi.Nodes, 'Coords')
                rawP = plotter.polyscope.ModelAdapter.pad3(double(mi.Nodes.Coords));
                if ~isempty(rawP)
                    ptsRaw = ptsRaw - obj.geometryCenter_(rawP);
                end
            end
            if isempty(dispRaw)
                dispRaw = zeros(size(ptsRaw, 1), 3);
            elseif size(dispRaw, 2) < 3
                dispRaw(:, end+1:3) = 0;
            end

            valid = ~all(isnan(ptsRaw), 2);
            if size(dispRaw, 1) == size(ptsRaw, 1)
                valid = valid & ~all(isnan(dispRaw), 2);
            else
                dispRaw = zeros(size(ptsRaw, 1), 3);
            end
            rawToClean = zeros(size(ptsRaw, 1), 1);
            rawToClean(valid) = 1:nnz(valid);
            pts = ptsRaw(valid, :);
            dispVals = dispRaw(valid, :);

            if isempty(cellsRaw), return; end
            cellsRaw = cellsRaw(~all(isnan(cellsRaw), 2), :);
            if isempty(cellsRaw), return; end
            if size(cellsRaw, 2) >= 3
                edges = cellsRaw(:, end-1:end);
            else
                edges = cellsRaw;
            end
            edges = round(edges);
            validEdges = all(isfinite(edges), 2) & all(edges >= 1, 2) & ...
                all(edges <= numel(rawToClean), 2);
            edges = edges(validEdges, :);
            if isempty(edges), return; end
            edges = rawToClean(edges);
            edges = edges(all(edges >= 1, 2), :);
        end

        function Sline = mapScalarsByNearest_(~, pts, Pnode, Snode)
            Sline = [];
            if isempty(pts) || isempty(Pnode) || isempty(Snode), return; end
            Snode = double(Snode(:));
            n = min(size(Pnode, 1), numel(Snode));
            Pnode = double(Pnode(1:n, :));
            Snode = Snode(1:n);
            valid = all(isfinite(Pnode), 2) & isfinite(Snode);
            Pnode = Pnode(valid, :);
            Snode = Snode(valid);
            if isempty(Pnode), return; end
            Sline = NaN(size(pts, 1), 1);
            chunk = 2048;
            for i = 1:chunk:size(pts, 1)
                rows = i:min(size(pts, 1), i + chunk - 1);
                Q = double(pts(rows, :));
                D = sum((reshape(Q, [], 1, 3) - reshape(Pnode, 1, [], 3)).^2, 3);
                [~, idx] = min(D, [], 2);
                Sline(rows) = Snode(idx);
            end
        end

        function tf = isVolumeTypes_(~, cellTypes)
            volumeTypes = [10, 12, 24, 25, 29];
            tf = ~isempty(cellTypes) && all(ismember(double(cellTypes(:)).', volumeTypes));
        end

        function rows = mapTags_(obj, segIdx, modelTags, respTags)
            rows = zeros(numel(modelTags), 1);
            mp = obj.respLookup_{segIdx};
            if ~isempty(mp) && numel(respTags) == mp.Count
                keys = num2cell(modelTags(:));
                exists = isKey(mp, keys);
                if any(exists), rows(exists) = cell2mat(values(mp, keys(exists))); end
            else
                [tf, loc] = ismember(modelTags(:), respTags(:));
                rows(tf) = loc(tf);
            end
        end

        function tags = respTags_(~, nr, entry)
            tags = [];
            if isfield(nr, 'nodeTags') && ~isempty(nr.nodeTags)
                tags = double(nr.nodeTags(:));
            elseif isstruct(entry) && isfield(entry, 'nodeTags') && ~isempty(entry.nodeTags)
                tags = double(entry.nodeTags(:));
            end
        end

        function fields = collectFieldTypes_(obj)
            nr = obj.NodalResp(1);
            fields = {};
            skip = {'odbTag','time','nodeTags','interpolatePoints','interpolateDisp','interpolateCells','interpolateCoords'};
            preferred = {'disp','vel','accel','reaction','reactionIncInertia','rayleighForces','pressure'};
            names = fieldnames(nr);
            for i = 1:numel(preferred)
                idx = find(strcmpi(names, preferred{i}), 1);
                if ~isempty(idx), fields{end+1} = names{idx}; end %#ok<AGROW>
            end
            for i = 1:numel(names)
                if any(strcmpi(names{i}, skip)) || any(strcmpi(fields, names{i})), continue; end
                if isnumeric(nr.(names{i})) || isstruct(nr.(names{i}))
                    fields{end+1} = names{i}; %#ok<AGROW>
                end
            end
        end

        function comps = componentsForField_(obj, field)
            comps = {'magnitude'};
            nr = obj.NodalResp(1);
            field = obj.normalizeField_(1, field);
            if ~isfield(nr, field), return; end
            entry = nr.(field);
            extra = {};
            if isstruct(entry) && isfield(entry, 'dofs')
                extra = obj.normalizeDofs_(entry.dofs);
            elseif isstruct(entry) && ~isfield(entry, 'data')
                extra = obj.normalizeDofs_(fieldnames(entry));
                extra = extra(~ismember(lower(extra), {'dofs','nodetags','time'}));
            elseif isnumeric(entry) && ismatrix(entry)
                extra = {'value'};
            end
            canonical = {'ux','uy','uz','rx','ry','rz'};
            extraLower = lower(string(extra));
            for i = 1:numel(canonical)
                if any(extraLower == canonical{i}) || isempty(extra)
                    comps{end+1} = canonical{i}; %#ok<AGROW>
                end
            end
            for i = 1:numel(extra)
                val = char(string(extra{i}));
                if any(strcmpi(val, {'x','y','z'})), continue; end
                if ~any(strcmpi(comps, val)), comps{end+1} = val; end %#ok<AGROW>
            end
        end

        function fields = deformFieldTypes_(obj)
            idx = find(strcmpi(obj.fieldTypes_, 'disp'), 1);
            if ~isempty(idx)
                fields = obj.fieldTypes_(idx);
            elseif ~isempty(obj.fieldTypes_)
                fields = obj.fieldTypes_(1);
            else
                fields = {'disp'};
            end
        end

        function field = normalizeField_(obj, segIdx, field)
            field = char(string(field));
            names = fieldnames(obj.NodalResp(segIdx));
            idx = find(strcmpi(names, field), 1);
            if ~isempty(idx), field = names{idx}; end
        end

        function out = normalizeDofs_(~, dofs)
            if isempty(dofs), out = {}; return; end
            if iscell(dofs), out = cellstr(string(dofs(:).'));
            elseif isstring(dofs), out = cellstr(dofs(:).');
            elseif ischar(dofs), out = {dofs};
            else, out = cellstr(string(dofs(:).'));
            end
            canonical = {'ux','uy','uz','rx','ry','rz'};
            out = [canonical(ismember(canonical, out)), out(~ismember(out, canonical))];
        end

        function updateProgramName_(obj)
            obj.App.polyscopeHandle().set_program_name(sprintf('OpenSeesMatlab | Nodal response | step %d/%d - by Yexiang Yan', ...
                obj.currentStep_, max(0, obj.nSteps_ - 1)));
        end
    end
end
