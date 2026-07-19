classdef plotUnstruResponse < plotter.polyscope.ViewerBase
    %PLOTUNSTRURESPONSE Polyscope/ImGui viewer for unstructured element responses.

    properties
        NodalResp struct
        EleResp struct
    end

    properties (Access = private)
        currentStep_ double = 0
        currentSeg_ double = 1
        currentLocalStep_ double = 1
        nSteps_ double = 1
        segStepCounts_ double = []
        segOffsets_ double = []
        eleTypes_ cell = {}
        respTypes_ cell = {}
        components_ cell = {}
        animDir_ double = 1
        meshData_ struct = struct()
        lineData_ struct = struct()
        extremeStepCache_ struct = struct()
        historyCacheKey_ char = ''
        historyCacheX_ double = []
        historyCacheY_ double = []
        historyCacheLabel_ char = ''
        initialOpts_ struct
    end

    methods
        function obj = plotUnstruResponse(modelInfo, nodalResp, eleResp, opts)
            if nargin < 1 || isempty(modelInfo)
                error('plotter:polyscope:UnstruResponse:InvalidInput', ...
                    'modelInfo is required.');
            end
            if nargin < 2 || isempty(nodalResp)
                error('plotter:polyscope:UnstruResponse:InvalidInput', ...
                    'nodalResp is required.');
            end
            if nargin < 3 || isempty(eleResp)
                error('plotter:polyscope:UnstruResponse:InvalidInput', ...
                    'eleResp is required.');
            end
            if nargin < 4 || isempty(opts)
                opts = struct();
            end

            obj = obj@plotter.polyscope.ViewerBase();
            obj.ModelInfo = modelInfo;
            obj.NodalResp = nodalResp;
            obj.EleResp = eleResp;
            obj.Opts = plotter.polyscope.Options.mergeOpts( ...
                plotter.polyscope.Options.defaultUnstructuredResponseOptions(), opts);
            obj.App = plotter.polyscope.PolyscopeApp();
            obj.P0_ = obj.nodeCoords_(1);
            obj.L_ = obj.modelLength_(obj.P0_);

            obj.buildStepIndex_();
            obj.eleTypes_ = obj.collectElementTypes_();
            if isempty(obj.eleTypes_)
                error('plotter:polyscope:UnstruResponse:NoElements', ...
                    'No Plane, Shell, or Solid family was found in modelInfo.');
            end
            obj.Opts.eleType = obj.pickExisting_(obj.eleTypes_, obj.Opts.eleType);
            obj.respTypes_ = obj.collectResponseTypes_();
            if isempty(obj.respTypes_)
                error('plotter:polyscope:UnstruResponse:NoResponses', ...
                    'No plottable element response field was found in eleResp.');
            end
            obj.Opts.respType = obj.pickExisting_(obj.respTypes_, obj.Opts.respType);
            obj.components_ = obj.componentsForResponse_(obj.Opts.respType);
            obj.Opts.component = obj.pickExisting_(obj.components_, obj.Opts.component);
            obj.currentStep_ = obj.resolveStepArg_(obj.getOptField_(obj.Opts, 'stepIdx', 'absmax'));
            obj.initialOpts_ = obj.Opts;

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
            try
                obj.App.polyscopeHandle().set_ground_plane_mode('none');
            catch
            end
            obj.setupWindowIcon_();
            obj.clear_();
            obj.handles_ = struct();
            obj.meshData_ = struct();
            obj.lineData_ = struct();
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
            if force || segIdx ~= obj.currentSeg_ || ~isfield(obj.handles_, 'def_Response')
                obj.registerSegment_(segIdx);
            end
            obj.currentStep_ = step;
            obj.currentSeg_ = segIdx;
            obj.currentLocalStep_ = localStep;
            obj.updateStep_(segIdx, localStep);
            if isfield(obj.gui_, 'step')
                obj.gui_.step = step;
            end
        end

        function n = nSteps(obj)
            n = obj.nSteps_;
        end
    end

    methods
        function guiCallback_(obj)
            try
                obj.advanceAnimation_();
                GB = plotter.polyscope.GuiBuilder;
                ws = obj.safeWindowSize_();
                panelW = 390;
                GB.begin('Unstructured Response', [max(0, ws(1) - panelW), 0], [panelW, max(560, ws(2))]);
                cleanup = onCleanup(@() GB.finish()); %#ok<NASGU>

                needsRebuild = false;
                needsUpdate = false;
                needsVisibility = false;
                GB.header('Unstructured response');
                polyscope.ImGui.ProgressBar((obj.currentStep_ + 1) / max(1, obj.nSteps_), [0, 0], ...
                    sprintf('%d / %d', obj.currentStep_, max(0, obj.nSteps_ - 1)));

                if GB.collapsingHeader('Response', int32(0))
                    [rchg, topoChg] = obj.drawResponseGui_();
                    needsUpdate = needsUpdate || rchg;
                    needsRebuild = needsRebuild || topoChg;
                    obj.gui_.showHistory = GB.checkbox('Show response history', obj.gui_.showHistory);
                end
                if GB.collapsingHeader('Geometry', int32(0))
                    [gchg, grebuild, visibilityOnly] = obj.drawGeometryGui_();
                    needsUpdate = needsUpdate || (gchg && ~visibilityOnly);
                    needsVisibility = needsVisibility || visibilityOnly;
                    needsRebuild = needsRebuild || grebuild;
                end
                if GB.collapsingHeader('Style', int32(0))
                    [dataChanged, styleChanged] = obj.drawStyleGui_();
                    needsUpdate = needsUpdate || dataChanged;
                    needsVisibility = needsVisibility || styleChanged;
                end
                if obj.drawSlicePlaneGui_('##unstru')
                    obj.registerSlicePlanes_();
                end
                if GB.collapsingHeader('Animation', int32(0))
                    if obj.drawAnimationGui_()
                        needsUpdate = true;
                    end
                end
                if GB.collapsingHeader('Debug', int32(0))
                    polyscope.ImGui.Text(sprintf('Step %d / %d', obj.currentStep_, obj.nSteps_ - 1));
                    polyscope.ImGui.Text(sprintf('Segment %d, local step %d', obj.currentSeg_, obj.currentLocalStep_));
                end

                GB.separator();
                if GB.button('Redraw##unstru')
                    obj.App.polyscopeHandle().request_redraw();
                end
                GB.sameLine();
                if GB.button('Reset##unstru')
                    obj.Opts = obj.initialOpts_;
                    obj.currentStep_ = obj.resolveStepArg_(obj.getOptField_(obj.Opts, 'stepIdx', 'absmax'));
                    obj.initGuiState_();
                    obj.setCameraForPoints_(obj.P0_, obj.Opts.general.view);
                    needsRebuild = true;
                end

                if needsRebuild
                    obj.invalidateScalarCaches_();
                    obj.setStep(obj.currentStep_, true);
                elseif needsUpdate
                    obj.setStep(obj.currentStep_, false);
                elseif needsVisibility
                    obj.registerMissingOptionalStructures_();
                    obj.applyStyle_();
                    obj.applyVisibility_();
                end
                clear cleanup
                obj.drawScreenAxesOverlay_();
                obj.updateScreenAxes3D_();
                if isfield(obj.gui_, 'showHistory') && obj.gui_.showHistory
                    obj.drawResponseHistoryWindow_(ws);
                end
            catch ME
                try
                    polyscope.ImGui.Text(['GUI error: ' ME.message]);
                catch
                end
            end
        end
    end

    methods (Access = protected)
        function initGuiState_(obj)
            initGuiState_@plotter.polyscope.ViewerBase(obj);
            obj.gui_.step = obj.currentStep_;
            obj.gui_.stepModeIdx = obj.indexOf_({'step','absmax','absmin','max','min'}, ...
                obj.getOptField_(obj.Opts, 'stepIdx', 'absmax'));
            obj.gui_.eleTypeIdx = obj.indexOf_(obj.eleTypes_, obj.Opts.eleType);
            obj.gui_.respIdx = obj.indexOf_(obj.respTypes_, obj.Opts.respType);
            obj.gui_.compIdx = obj.indexOf_(obj.components_, obj.Opts.component);
            obj.gui_.fiberIdx = obj.indexOf_({'top','middle','bottom'}, obj.Opts.fiberPoint);
            obj.gui_.locIdx = obj.indexOf_({'auto','node','gp','element'}, obj.responseLocation_());
            obj.gui_.showField = obj.Opts.color.useColormap;
            obj.gui_.useColormap = obj.Opts.color.useColormap;
            obj.gui_.showDeform = obj.Opts.deform.show;
            obj.gui_.autoScale = obj.Opts.deform.autoScale;
            obj.gui_.deformScale = obj.Opts.deform.scale;
            obj.gui_.showUndeformed = obj.Opts.deform.showUndeformed;
            obj.gui_.showMesh = obj.Opts.surf.show;
            obj.gui_.showEdges = obj.Opts.surf.showEdges;
            obj.gui_.showNodes = obj.getOptField_(obj.Opts.nodes, 'show', false);
            obj.gui_.showFixed = obj.Opts.fixed.show;
            obj.gui_.showLines = obj.Opts.line.show;
            obj.gui_.useInterpolation = obj.Opts.interp.useInterpolation;
            obj.gui_.deformedAlpha = obj.Opts.color.deformedAlpha;
            obj.gui_.ghostAlpha = obj.Opts.color.undeformedAlpha;
            obj.gui_.edgeRadius = obj.Opts.polyscope.edgeRadius;
            obj.gui_.nodeRadius = obj.Opts.polyscope.nodeRadius;
            obj.gui_.solidColor = plotter.polyscope.utils.colorToRgb(obj.Opts.color.solidColor);
            obj.gui_.edgeColor = plotter.polyscope.utils.colorToRgb(obj.Opts.surf.edgeColor);
            obj.gui_.ghostColor = plotter.polyscope.utils.colorToRgb(obj.Opts.color.undeformedColor);
            obj.gui_.climIdx = obj.indexOf_({'step','range','global','absmax','absmin'}, obj.Opts.color.climMode);
            obj.gui_.colorModeIdx = obj.indexOf_({'auto','node','element'}, obj.Opts.surf.colorMode);
            obj.gui_.gpReduceIdx = obj.indexOf_({'mean','max','min','index'}, obj.Opts.surf.gpReduce);
            obj.gui_.gpIndex = obj.Opts.surf.gpIndex;
            obj.gui_.playing = obj.getOptField_(obj.Opts.animation, 'play', false);
            obj.gui_.animationMode = obj.gui_.playing;
            obj.gui_.fps = obj.getOptField_(obj.Opts.animation, 'fps', ...
                obj.defaultAnimationFps_(obj.nSteps_));
            obj.gui_.loop = obj.getOptField_(obj.Opts.animation, 'loop', true);
            obj.gui_.pingpong = obj.getOptField_(obj.Opts.animation, 'pingpong', false);
            obj.gui_.animUpdateColors = obj.getOptField_(obj.Opts.animation, 'updateColors', true);
            obj.initColorbarGuiState_();
            obj.initSliceGuiState_();
            cmapNames = obj.colormapNames_();
            obj.gui_.cmapIdx = obj.indexOf_(cmapNames, obj.Opts.polyscope.scalarColorMap);
            obj.gui_.showHistory = false;
            obj.gui_.historyTargetType = 'node';
            obj.gui_.historyUseTag = true;
            tags = obj.historyNodeTags_(1);
            if isempty(tags), tags = 1; end
            obj.gui_.historyTag = tags(1);
            obj.gui_.historyIndex = 1;
            obj.gui_.historyAutoStep = true;
            obj.gui_.historyShowValue = true;
            obj.invalidateHistoryCache_();
        end

        function configureAnimationRenderLoop_(obj)
            isRunning = isfield(obj.gui_, 'animationMode') && obj.gui_.animationMode && obj.gui_.playing;
            fps = max(1, double(obj.getOptField_(obj.gui_, 'fps', 12)));
            configureAnimationRenderLoop_@plotter.polyscope.ViewerBase(obj, isRunning, fps);
        end
    end

    methods (Access = private)
        function [changed, topoChanged] = drawResponseGui_(obj)
            GB = plotter.polyscope.GuiBuilder;
            old = obj.gui_;
            obj.gui_.eleTypeIdx = GB.combo('Element type##unstru_response', obj.gui_.eleTypeIdx, obj.eleTypes_);
            obj.Opts.eleType = obj.eleTypes_{obj.gui_.eleTypeIdx};
            obj.respTypes_ = obj.collectResponseTypes_();
            obj.gui_.respIdx = min(obj.gui_.respIdx, numel(obj.respTypes_));
            obj.gui_.respIdx = GB.combo('Response##unstru_response', obj.gui_.respIdx, obj.respTypes_);
            obj.Opts.respType = obj.respTypes_{obj.gui_.respIdx};
            responseChanged = obj.gui_.respIdx ~= old.respIdx;
            obj.components_ = obj.componentsForResponse_(obj.Opts.respType);
            if responseChanged
                obj.gui_.compIdx = 1;
            end
            obj.gui_.compIdx = min(obj.gui_.compIdx, numel(obj.components_));
            obj.gui_.compIdx = GB.combo('Component##unstru_response', obj.gui_.compIdx, obj.components_);
            obj.Opts.component = obj.components_{obj.gui_.compIdx};
            if strcmpi(char(string(obj.Opts.eleType)), 'Shell')
                fibers = {'top','middle','bottom'};
                obj.gui_.fiberIdx = GB.combo('Fiber##unstru_response', obj.gui_.fiberIdx, fibers);
                obj.Opts.fiberPoint = fibers{obj.gui_.fiberIdx};
            end
            locs = {'auto','node','gp','element'};
            obj.gui_.locIdx = GB.combo('Location##unstru_response', obj.gui_.locIdx, locs);
            obj.Opts.responseLocation = locs{obj.gui_.locIdx};

            if ~obj.resolveResponseIsNodeBased_(obj.Opts.respType)
                gpModes = {'mean','max','min','index'};
                obj.gui_.gpReduceIdx = GB.combo('GP reduce##unstru_response', obj.gui_.gpReduceIdx, gpModes);
                obj.Opts.surf.gpReduce = gpModes{obj.gui_.gpReduceIdx};
                obj.gui_.gpIndex = GB.sliderInt('GP index##unstru_response', round(obj.gui_.gpIndex), 1, 40);
                obj.Opts.surf.gpIndex = max(1, round(obj.gui_.gpIndex));
            end

            modes = {'step','absmax','absmin','max','min'};
            obj.gui_.stepModeIdx = GB.combo('Step mode##unstru_response', obj.gui_.stepModeIdx, modes);
            if strcmp(modes{obj.gui_.stepModeIdx}, 'step')
                obj.gui_.step = GB.sliderInt('Step##unstru_response', round(obj.gui_.step), 0, max(0, obj.nSteps_ - 1));
                obj.currentStep_ = round(obj.gui_.step);
            elseif obj.gui_.stepModeIdx ~= old.stepModeIdx || responseChanged || ...
                    obj.gui_.compIdx ~= old.compIdx || obj.gui_.locIdx ~= old.locIdx
                obj.currentStep_ = obj.resolveStepArg_(modes{obj.gui_.stepModeIdx});
                obj.gui_.step = obj.currentStep_;
            end
            obj.gui_.showField = GB.checkbox('Scalar field##unstru', obj.gui_.showField);
            GB.sameLine();
            obj.gui_.useColormap = GB.checkbox('Use colormap##unstru', obj.gui_.useColormap);
            obj.Opts.color.useColormap = obj.gui_.useColormap;
            if obj.gui_.showField && obj.gui_.useColormap
                obj.drawColorbarGui_('##unstru_response', false);
            end

            topoChanged = obj.guiChanged_(old, {'eleTypeIdx'});
            changed = obj.guiChanged_(old, {'respIdx','compIdx','fiberIdx','locIdx', ...
                'gpReduceIdx','gpIndex','stepModeIdx','step','showField','useColormap', ...
                'onscreenColorbar','onscreenColorbarLocation'});
            if changed
                obj.invalidateScalarCaches_();
                obj.invalidateHistoryCache_();
            end
        end

        function [changed, rebuild, visibilityOnly] = drawGeometryGui_(obj)
            GB = plotter.polyscope.GuiBuilder;
            old = obj.gui_;
            obj.gui_.showMesh = GB.checkbox('Surfaces / solids##unstru_geometry', obj.gui_.showMesh);
            GB.sameLine();
            obj.gui_.showEdges = GB.checkbox('Mesh edges##unstru_geometry', obj.gui_.showEdges);
            obj.gui_.showNodes = GB.checkbox('Model nodes##unstru_geometry', obj.gui_.showNodes);
            GB.sameLine();
            obj.gui_.showFixed = GB.checkbox('Fixed nodes##unstru_geometry', obj.gui_.showFixed);
            obj.gui_.showLines = GB.checkbox('Line elements##unstru_geometry', obj.gui_.showLines);
            GB.sameLine();
            obj.gui_.useInterpolation = GB.checkbox('Interpolated lines##unstru_geometry', obj.gui_.useInterpolation);
            obj.gui_.showDeform = GB.checkbox('Deformed shape##unstru_geometry', obj.gui_.showDeform);
            GB.sameLine();
            obj.gui_.autoScale = GB.checkbox('Auto scale##unstru_geometry', obj.gui_.autoScale);
            obj.gui_.deformScale = GB.sliderFloat('Deformation scale##unstru_geometry', obj.gui_.deformScale, 0, 100);
            obj.gui_.showUndeformed = GB.checkbox('Undeformed ghost##unstru_geometry', obj.gui_.showUndeformed);
            obj.drawSsaaGui_('##unstru_geometry');
            obj.syncOptsFromGui_();
            changed = obj.guiChanged_(old, {'showMesh','showEdges','showNodes','showFixed', ...
                'showLines','showDeform','autoScale','deformScale','showUndeformed'});
            rebuild = obj.guiChanged_(old, {'useInterpolation'});
            geometryChanged = obj.guiChanged_(old, {'showDeform','autoScale','deformScale'});
            visibilityOnly = changed && ~geometryChanged && ~rebuild;
        end

        function [dataChanged, styleChanged] = drawStyleGui_(obj)
            GB = plotter.polyscope.GuiBuilder;
            old = obj.gui_;
            cmapNames = obj.colormapNames_();
            obj.gui_.cmapIdx = GB.combo('Colormap##unstru_style', obj.gui_.cmapIdx, cmapNames);
            obj.Opts.polyscope.scalarColorMap = cmapNames{obj.gui_.cmapIdx};
            obj.Opts.color.colormap = cmapNames{obj.gui_.cmapIdx};
            climModes = {'step','range','global','absmax','absmin'};
            obj.gui_.climIdx = GB.combo('Color limits##unstru_style', obj.gui_.climIdx, climModes);
            obj.Opts.color.climMode = climModes{obj.gui_.climIdx};
            colorModes = {'auto','node','element'};
            obj.gui_.colorModeIdx = GB.combo('Color mode##unstru_style', obj.gui_.colorModeIdx, colorModes);
            obj.Opts.surf.colorMode = colorModes{obj.gui_.colorModeIdx};
            [cchg, obj.gui_.solidColor] = GB.colorEdit3('Solid color##unstru_style', obj.gui_.solidColor);
            if cchg, obj.Opts.color.solidColor = obj.asRgb_(obj.gui_.solidColor); end
            [cchg, obj.gui_.edgeColor] = GB.colorEdit3('Edge color##unstru_style', obj.gui_.edgeColor);
            if cchg, obj.Opts.surf.edgeColor = obj.asRgb_(obj.gui_.edgeColor); end
            [cchg, obj.gui_.ghostColor] = GB.colorEdit3('Ghost color##unstru_style', obj.gui_.ghostColor);
            if cchg, obj.Opts.color.undeformedColor = obj.asRgb_(obj.gui_.ghostColor); end
            obj.gui_.deformedAlpha = GB.sliderFloat('Surface alpha##unstru_style', obj.gui_.deformedAlpha, 0, 1);
            obj.gui_.ghostAlpha = GB.sliderFloat('Ghost alpha##unstru_style', obj.gui_.ghostAlpha, 0, 1);
            obj.gui_.edgeRadius = GB.sliderFloat('Line radius##unstru_style', obj.gui_.edgeRadius, 0.0001, 0.006);
            obj.gui_.nodeRadius = GB.sliderFloat('Node radius##unstru_style', obj.gui_.nodeRadius, 0.0003, 0.012);
            views = obj.viewNames_();
            obj.gui_.viewIdx = GB.combo('View##unstru_style', obj.gui_.viewIdx, views);
            if GB.button('Apply view##unstru_style')
                obj.Opts.general.view = views{obj.gui_.viewIdx};
                obj.setCameraForPoints_(obj.nodeCoords_(obj.currentSeg_), obj.Opts.general.view);
            end
            GB.sameLine();
            if GB.button('Rebuild##unstru_style')
                obj.setStep(obj.currentStep_, true);
            end
            obj.syncOptsFromGui_();
            dataChanged = obj.guiChanged_(old, {'cmapIdx','climIdx','colorModeIdx'});
            styleChanged = obj.guiChanged_(old, {'solidColor','edgeColor','ghostColor', ...
                'deformedAlpha','ghostAlpha','edgeRadius','nodeRadius','viewIdx'});
            if dataChanged
                obj.invalidateScalarCaches_();
            end
            if styleChanged
                obj.applyStyle_();
            end
        end

        function changed = drawAnimationGui_(obj)
            GB = plotter.polyscope.GuiBuilder;
            old = obj.gui_;
            obj.gui_.animationMode = GB.checkbox('Enter animation mode', obj.gui_.animationMode);
            if obj.gui_.animationMode
                obj.gui_.autoScale = true;
                obj.Opts.deform.autoScale = true;
                if ~old.animationMode
                    % Start from the currently displayed model snapshot.
                    obj.gui_.step = obj.currentStep_;
                    obj.animDir_ = 1;
                    % Use a fixed color range during animation so variations are visible.
                    obj.gui_.climIdx = obj.indexOf_({'step','range','global','absmax','absmin'}, 'global');
                    obj.Opts.color.climMode = 'global';
                end
                if GB.button('Play / pause')
                    obj.gui_.playing = ~obj.gui_.playing;
                end
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
                obj.gui_.animUpdateColors = GB.checkbox('Update colors', obj.gui_.animUpdateColors);
            else
                obj.gui_.playing = false;
            end
            obj.Opts.animation.play = obj.gui_.playing;
            obj.Opts.animation.fps = obj.gui_.fps;
            obj.Opts.animation.loop = obj.gui_.loop;
            obj.Opts.animation.pingpong = obj.gui_.pingpong;
            obj.Opts.animation.updateColors = obj.gui_.animUpdateColors;
            obj.configureAnimationRenderLoop_();
            % FPS/loop/pingpong/playing only affect the animation loop; they do
            % not require a full scalar-field recompute. Only animation mode
            % and color-limit changes need a response update.
            changed = obj.guiChanged_(old, {'animationMode','climIdx'});
        end

        function registerSegment_(obj, segIdx)
            obj.clear_();
            obj.handles_ = struct();
            obj.meshData_ = struct();
            obj.lineData_ = struct();
            obj.currentSeg_ = segIdx;
            obj.P0_ = obj.nodeCoords_(segIdx);
            obj.L_ = obj.modelLength_(obj.P0_);
            ps = obj.App.polyscopeHandle();

            [Pdef, ~] = obj.deformedCoords_(segIdx, obj.currentLocalStep_);
            [Snode, Sele, clim, nodeBased] = obj.scalarField_(segIdx, obj.currentLocalStep_);
            obj.registerResponseMesh_(ps, segIdx, Pdef, Snode, Sele, clim, nodeBased);
            obj.registerLineStructures_(ps, segIdx, Pdef, Snode, clim);
            if obj.Opts.nodes.show, obj.registerNodes_(ps, Pdef, Snode, clim); end
            if obj.Opts.fixed.show, obj.registerFixed_(ps, segIdx, Pdef, Snode, clim); end
            if obj.Opts.deform.showUndeformed, obj.registerGhost_(ps, segIdx); end
            if ~obj.isOverlayScreenAxes_()
                obj.registerScreenAxes3D_();
            end
            obj.applyStyle_();
            obj.applyVisibility_();
        end

        function registerResponseMesh_(obj, ps, segIdx, Pdef, Snode, Sele, clim, nodeBased)
            [cells, types] = obj.familyCells_(segIdx);
            if isempty(cells) || isempty(types), return; end
            isSolid = strcmpi(char(string(obj.Opts.eleType)), 'Solid');
            qargs = obj.scalarArgs_(clim);
            qname = obj.scalarQuantityName_();
            if isSolid
                out = plotter.utils.VTKElementTriangulator.volumize(Pdef, types, cells);
                if isempty(out.Points), return; end
                if ~isempty(out.Tets) && ~isempty(out.Hexes)
                    h = ps.register_tet_hex_mesh(obj.structName_('Response', 'def'), out.Points, out.Tets, out.Hexes);
                elseif ~isempty(out.Tets)
                    h = ps.register_tet_mesh(obj.structName_('Response', 'def'), out.Points, out.Tets);
                elseif ~isempty(out.Hexes)
                    h = ps.register_hex_mesh(obj.structName_('Response', 'def'), out.Points, out.Hexes);
                else
                    return;
                end
                edgeRows = obj.expandedSurfaceEdgeRows_(types, cells);
                obj.meshData_ = struct('kind', 'volume', 'cells', cells, 'types', types, ...
                    'registerCellIds', obj.getField_(out, 'RegisterCellIds', []), ...
                    'edgeRows', edgeRows);
                if nodeBased && ~isempty(Snode)
                    h.add_vertex_scalar_quantity(qname, Snode, qargs{:});
                elseif ~isempty(Sele)
                    vals = obj.expandVolumeCellScalars_(Sele, obj.meshData_.registerCellIds);
                    h.add_cell_scalar_quantity(qname, vals, qargs{:});
                end
            else
                if nodeBased
                    out = plotter.utils.VTKElementTriangulator.triangulate(Pdef, types, cells, 'Scalars', Snode);
                else
                    out = plotter.utils.VTKElementTriangulator.triangulate(Pdef, types, cells, ...
                        'Scalars', Sele, 'ScalarsByElement', true);
                end
                if isempty(out.Points), return; end
                h = ps.register_surface_mesh(obj.structName_('Response', 'def'), out.Points, out.Triangles, ...
                    'smooth_shade', false);
                pointRows = obj.expandedSurfacePointRows_(cells);
                edgeRows = obj.expandedSurfaceEdgeRows_(types, cells);
                obj.meshData_ = struct('kind', 'surface', 'cells', cells, 'types', types, ...
                    'triCellIds', obj.getField_(out, 'TriCellIds', []), ...
                    'edgePoints', obj.getField_(out, 'EdgePoints', zeros(0, 3)), ...
                    'pointRows', pointRows, 'edgeRows', edgeRows);
                if nodeBased && isfield(out, 'PointScalars') && ~isempty(out.PointScalars)
                    h.add_vertex_scalar_quantity(qname, out.PointScalars, qargs{:});
                elseif ~nodeBased && ~isempty(Sele)
                    faceVals = obj.expandFaceScalars_(Sele, obj.meshData_.triCellIds);
                    h.add_face_scalar_quantity(qname, faceVals, qargs{:});
                end
            end
            h.set_color(obj.asRgb_(obj.Opts.color.solidColor));
            h.set_transparency(obj.Opts.color.deformedAlpha);
            try, h.set_edge_width(0); catch, end
            h.set_enabled(obj.Opts.surf.show);
            obj.handles_.def_Response = h;
            obj.registerMeshEdges_(ps, Pdef);
        end

        function registerMeshEdges_(obj, ps, P)
            if isempty(obj.meshData_) || ~isfield(obj.meshData_, 'cells'), return; end
            edgePoints = obj.meshEdgePolylineFromRows_(P);
            if isempty(edgePoints)
                out = plotter.utils.VTKElementTriangulator.triangulate(P, obj.meshData_.types, obj.meshData_.cells);
                if isempty(out) || ~isfield(out, 'EdgePoints'), return; end
                edgePoints = out.EdgePoints;
            end
            [nodes, edges] = plotter.polyscope.ModelAdapter.edgePointsToCurveNetwork(edgePoints);
            if isempty(nodes) || isempty(edges), return; end
            h = ps.register_curve_network(obj.structName_('MeshEdges', 'def'), nodes, edges);
            h.set_radius(obj.Opts.polyscope.edgeRadius, true);
            h.set_color(obj.asRgb_(obj.Opts.surf.edgeColor));
            h.set_enabled(obj.Opts.surf.showEdges && obj.Opts.surf.show);
            obj.handles_.def_MeshEdges = h;
        end

        function registerLineStructures_(obj, ps, segIdx, Pdef, ~, ~)
            fam = obj.families_(segIdx);
            if ~isfield(fam, 'Line') || ~isfield(fam.Line, 'Cells') || isempty(fam.Line.Cells)
                return;
            end
            cells = double(fam.Line.Cells);
            if isfield(fam.Line, 'CellTypes') && ~isempty(fam.Line.CellTypes)
                types = double(fam.Line.CellTypes(:));
            else
                types = repmat(3, size(cells, 1), 1);
            end
            out = plotter.utils.VTKElementTriangulator.convertLineElements(Pdef, types, cells);
            if isempty(out) || isempty(out.MeshPoints) || isempty(out.Segments), return; end
            h = ps.register_curve_network(obj.structName_('Line', 'def'), out.MeshPoints, out.Segments);
            h.set_radius(obj.Opts.polyscope.edgeRadius, true);
            h.set_color(obj.asRgb_(obj.Opts.color.solidColor));
            h.set_enabled(obj.Opts.line.show);
            nodeIds = out.MeshPointNodeIds;
            if isempty(nodeIds)
                nodeIds = (1:size(out.MeshPoints, 1)).';
            end
            obj.lineData_.Line = struct('cells', cells, 'types', types, 'pointNodeIds', nodeIds);
            obj.handles_.def_Line = h;
        end

        function registerNodes_(obj, ps, Pdef, Snode, clim)
            h = ps.register_point_cloud(obj.structName_('Nodes', 'def'), Pdef);
            h.set_radius(obj.Opts.polyscope.nodeRadius, true);
            h.set_color(obj.asRgb_(obj.Opts.color.solidColor));
            h.set_point_render_mode(obj.Opts.polyscope.pointRenderMode);
            h.set_enabled(obj.Opts.nodes.show);
            if ~isempty(Snode)
                qargs = obj.scalarArgs_(clim);
                h.add_scalar_quantity(obj.scalarQuantityName_(), Snode, qargs{:});
            end
            obj.handles_.def_Nodes = h;
        end

        function registerFixed_(obj, ps, segIdx, Pdef, ~, ~)
            [Pfix, ~] = obj.fixedNodes_(segIdx, Pdef);
            if isempty(Pfix), return; end
            h = ps.register_point_cloud(obj.structName_('Fixed', 'def'), Pfix);
            h.set_radius(obj.Opts.polyscope.nodeRadius * 1.6, true);
            h.set_color(obj.asRgb_(plotter.polyscope.utils.colorToRgb(obj.Opts.fixed.color)));
            h.set_point_render_mode(obj.Opts.polyscope.pointRenderMode);
            h.set_enabled(obj.Opts.fixed.show);
            obj.handles_.def_Fixed = h;
        end

        function registerGhost_(obj, ps, segIdx)
            P0 = obj.nodeCoords_(segIdx);
            edgePoints = obj.meshEdgePolylineFromRows_(P0);
            if isempty(edgePoints)
                [cells, types] = obj.familyCells_(segIdx);
                if isempty(cells), return; end
                out = plotter.utils.VTKElementTriangulator.triangulate(P0, types, cells);
                if isempty(out) || ~isfield(out, 'EdgePoints'), return; end
                edgePoints = out.EdgePoints;
            end
            [nodes, edges] = plotter.polyscope.ModelAdapter.edgePointsToCurveNetwork(edgePoints);
            if isempty(nodes), return; end
            h = ps.register_curve_network(obj.structName_('Ghost'), nodes, edges);
            h.set_radius(obj.Opts.polyscope.edgeRadius * 0.75, true);
            h.set_color(obj.asRgb_(obj.Opts.color.undeformedColor));
            h.set_transparency(obj.Opts.color.undeformedAlpha);
            h.set_enabled(obj.Opts.deform.showUndeformed);
            obj.handles_.ghost_Response = h;
        end

        function updateStep_(obj, segIdx, localStep)
            [Pdef, scale] = obj.deformedCoords_(segIdx, localStep);
            [Snode, Sele, clim, nodeBased] = obj.scalarField_(segIdx, localStep);
            qargs = obj.scalarArgs_(clim);
            qname = obj.scalarQuantityName_();

            if isfield(obj.handles_, 'def_Response') && ~isempty(obj.meshData_)
                h = obj.handles_.def_Response;
                if strcmp(obj.meshData_.kind, 'volume')
                    h.update_vertex_positions(Pdef);
                    if nodeBased && ~isempty(Snode)
                        h.add_vertex_scalar_quantity(qname, Snode, qargs{:});
                    elseif ~nodeBased && ~isempty(Sele)
                        h.add_cell_scalar_quantity(qname, obj.expandVolumeCellScalars_(Sele, obj.meshData_.registerCellIds), qargs{:});
                    else
                        h.add_vertex_scalar_quantity(qname, zeros(size(Pdef, 1), 1), 'enabled', false);
                    end
                else
                    pts = obj.surfacePointsFromRows_(Pdef);
                    h.update_vertex_positions(pts);
                    if nodeBased && ~isempty(Snode)
                        h.add_vertex_scalar_quantity(qname, obj.expandNodeScalarsByRows_(Snode), qargs{:});
                    elseif ~nodeBased && ~isempty(Sele)
                        h.add_face_scalar_quantity(qname, obj.expandFaceScalars_(Sele, obj.meshData_.triCellIds), qargs{:});
                    else
                        h.add_vertex_scalar_quantity(qname, zeros(size(pts, 1), 1), 'enabled', false);
                    end
                end
            end
            obj.updateMeshEdges_(Pdef);
            obj.updateLines_(Pdef, Snode, clim);
            obj.updateNodes_(segIdx, Pdef, Snode, clim);
            obj.applyVisibility_();
            obj.App.polyscopeHandle().set_program_name(sprintf( ...
                'Unstructured response | %s %s | step %d | scale %.4g', ...
                char(string(obj.Opts.eleType)), char(string(obj.Opts.respType)), ...
                obj.currentStep_, scale));
        end

        function updateMeshEdges_(obj, P)
            if ~isfield(obj.handles_, 'def_MeshEdges') || isempty(obj.meshData_), return; end
            edgePoints = obj.meshEdgePolylineFromRows_(P);
            [nodes, ~] = plotter.polyscope.ModelAdapter.edgePointsToCurveNetwork(edgePoints);
            if ~isempty(nodes)
                obj.handles_.def_MeshEdges.update_node_positions(nodes);
            end
        end

        function updateLines_(obj, Pdef, Snode, clim)
            if ~isfield(obj.handles_, 'def_Line') || ~isfield(obj.lineData_, 'Line'), return; end
            data = obj.lineData_.Line;
            ids = data.pointNodeIds(:);
            Pline = Pdef(ids, :);
            obj.handles_.def_Line.update_node_positions(Pline);
            if ~isempty(Snode)
                qargs = obj.scalarArgs_(clim);
                obj.handles_.def_Line.add_node_scalar_quantity(obj.scalarQuantityName_(), Snode(ids), qargs{:});
            end
        end

        function updateNodes_(obj, segIdx, Pdef, Snode, clim)
            if isfield(obj.handles_, 'def_Nodes')
                h = obj.handles_.def_Nodes;
                h.update_point_positions(Pdef);
                if ~isempty(Snode)
                    qargs = obj.scalarArgs_(clim);
                    h.add_scalar_quantity(obj.scalarQuantityName_(), Snode, qargs{:});
                end
            end
            if isfield(obj.handles_, 'def_Fixed')
                [Pfix, ~] = obj.fixedNodes_(segIdx, Pdef);
                if ~isempty(Pfix)
                    obj.handles_.def_Fixed.update_point_positions(Pfix);
                end
            end
        end

        function applyVisibility_(obj)
            obj.setEnabled_('def_Response', obj.Opts.surf.show);
            obj.setEnabled_('def_MeshEdges', obj.Opts.surf.show && obj.Opts.surf.showEdges);
            obj.setEnabled_('def_Line', obj.Opts.line.show);
            obj.setEnabled_('def_Nodes', obj.Opts.nodes.show);
            obj.setEnabled_('def_Fixed', obj.Opts.fixed.show);
            obj.setEnabled_('ghost_Response', obj.Opts.deform.showUndeformed);
        end

        function registerMissingOptionalStructures_(obj)
            if obj.currentSeg_ < 1 || isempty(obj.P0_)
                return;
            end
            ps = obj.App.polyscopeHandle();
            [Pdef, ~] = obj.deformedCoords_(obj.currentSeg_, obj.currentLocalStep_);
            needScalar = (obj.Opts.nodes.show && ~isfield(obj.handles_, 'def_Nodes')) || ...
                (obj.Opts.line.show && ~isfield(obj.handles_, 'def_Line'));
            Snode = [];
            clim = [];
            if needScalar
                [Snode, ~, clim, ~] = obj.scalarField_(obj.currentSeg_, obj.currentLocalStep_);
            end
            if obj.Opts.nodes.show && ~isfield(obj.handles_, 'def_Nodes')
                obj.registerNodes_(ps, Pdef, Snode, clim);
            end
            if obj.Opts.fixed.show && ~isfield(obj.handles_, 'def_Fixed')
                obj.registerFixed_(ps, obj.currentSeg_, Pdef, Snode, clim);
            end
            if obj.Opts.line.show && ~isfield(obj.handles_, 'def_Line')
                obj.registerLineStructures_(ps, obj.currentSeg_, Pdef, Snode, clim);
            end
            if obj.Opts.deform.showUndeformed && ~isfield(obj.handles_, 'ghost_Response')
                obj.registerGhost_(ps, obj.currentSeg_);
            end
        end

        function applyStyle_(obj)
            if isfield(obj.handles_, 'def_Response')
                h = obj.handles_.def_Response;
                h.set_color(obj.asRgb_(obj.Opts.color.solidColor));
                h.set_transparency(obj.Opts.color.deformedAlpha);
                try, h.set_edge_color(obj.asRgb_(obj.Opts.surf.edgeColor)); catch, end
                try, h.set_edge_width(0); catch, end
            end
            if isfield(obj.handles_, 'def_MeshEdges')
                h = obj.handles_.def_MeshEdges;
                h.set_color(obj.asRgb_(obj.Opts.surf.edgeColor));
                h.set_radius(obj.Opts.polyscope.edgeRadius, true);
            end
            if isfield(obj.handles_, 'def_Line')
                obj.handles_.def_Line.set_radius(obj.Opts.polyscope.edgeRadius, true);
                obj.handles_.def_Line.set_color(obj.asRgb_(obj.Opts.color.solidColor));
            end
            if isfield(obj.handles_, 'def_Nodes')
                obj.handles_.def_Nodes.set_radius(obj.Opts.polyscope.nodeRadius, true);
                obj.handles_.def_Nodes.set_color(obj.asRgb_(obj.Opts.color.solidColor));
            end
            if isfield(obj.handles_, 'def_Fixed')
                obj.handles_.def_Fixed.set_radius(obj.Opts.polyscope.nodeRadius * 1.6, true);
                obj.handles_.def_Fixed.set_color(obj.asRgb_(plotter.polyscope.utils.colorToRgb(obj.Opts.fixed.color)));
            end
            if isfield(obj.handles_, 'ghost_Response')
                obj.handles_.ghost_Response.set_color(obj.asRgb_(obj.Opts.color.undeformedColor));
                obj.handles_.ghost_Response.set_transparency(obj.Opts.color.undeformedAlpha);
            end
        end

        function invalidateHistoryCache_(obj)
            obj.historyCacheKey_ = '';
            obj.historyCacheX_ = [];
            obj.historyCacheY_ = [];
            obj.historyCacheLabel_ = '';
        end

        function drawResponseHistoryWindow_(obj, ws)
            if nargin < 2 || isempty(ws)
                ws = obj.safeWindowSize_();
            end
            w = min(520, max(380, ws(1) * 0.34));
            h = min(390, max(300, ws(2) * 0.36));
            x = max(12, ws(1) - 390 - w - 18);
            y = max(42, ws(2) - h - 18);
            polyscope.ImGui.SetNextWindowPos([x, y], ...
                int32(polyscope.ImGui.get_constant('ImGuiCond_FirstUseEver')));
            polyscope.ImGui.SetNextWindowSize([w, h], ...
                int32(polyscope.ImGui.get_constant('ImGuiCond_FirstUseEver')));
            visible = polyscope.ImGui.Begin('Response history');
            cleanup = onCleanup(@() polyscope.ImGui.End());
            if visible
                obj.drawResponseHistoryGui_();
            end
        end

        function drawResponseHistoryGui_(obj)
            GB = plotter.polyscope.GuiBuilder;
            oldState = obj.gui_;
            if obj.resolveResponseIsNodeBased_(obj.Opts.respType)
                expectedType = 'node';
            else
                expectedType = 'element';
            end
            if ~isfield(obj.gui_, 'historyTargetType') || ~strcmpi(obj.gui_.historyTargetType, expectedType)
                obj.gui_.historyTargetType = expectedType;
                obj.invalidateHistoryCache_();
            end
            isNode = strcmpi(obj.gui_.historyTargetType, 'node');
            polyscope.ImGui.Text(sprintf('Target: %s', char(string(obj.gui_.historyTargetType))));
            if isNode
                tags = obj.historyNodeTags_(obj.currentSeg_);
            else
                tags = obj.historyElementTags_(obj.currentSeg_);
            end
            nTarget = numel(tags);
            if nTarget == 0
                polyscope.ImGui.TextDisabled('No targets are available for the current response.');
                return;
            end

            obj.gui_.historyUseTag = GB.checkbox('Use tag##history', obj.getOptField_(obj.gui_, 'historyUseTag', true));
            if obj.gui_.historyUseTag
                [changed, tagVal] = polyscope.ImGui.InputInt('Target tag##history', ...
                    int32(round(obj.getOptField_(obj.gui_, 'historyTag', tags(1)))), int32(1), int32(100));
                if changed
                    obj.gui_.historyTag = double(tagVal);
                    idx = find(tags == obj.gui_.historyTag, 1);
                    if ~isempty(idx), obj.gui_.historyIndex = idx; end
                    obj.invalidateHistoryCache_();
                end
                if GB.button('Prev##history')
                    idx = max(1, obj.getHistoryIndex_(tags) - 1);
                    obj.gui_.historyIndex = idx;
                    obj.gui_.historyTag = tags(idx);
                    obj.invalidateHistoryCache_();
                end
                GB.sameLine();
                if GB.button('Next##history')
                    idx = min(nTarget, obj.getHistoryIndex_(tags) + 1);
                    obj.gui_.historyIndex = idx;
                    obj.gui_.historyTag = tags(idx);
                    obj.invalidateHistoryCache_();
                end
            else
                [changed, idxVal] = polyscope.ImGui.InputInt('Target index##history', ...
                    int32(round(obj.getOptField_(obj.gui_, 'historyIndex', 1))), int32(1), int32(10));
                if changed
                    obj.gui_.historyIndex = round(max(1, min(nTarget, double(idxVal))));
                    obj.gui_.historyTag = tags(obj.gui_.historyIndex);
                    obj.invalidateHistoryCache_();
                end
            end
            if GB.button('Reset##history')
                obj.resetResponseHistoryGui_(tags);
            end
            GB.sameLine();
            obj.gui_.historyAutoStep = GB.checkbox('Follow current step##history', obj.getOptField_(obj.gui_, 'historyAutoStep', true));
            obj.gui_.historyShowValue = GB.checkbox('Show current value##history', obj.getOptField_(obj.gui_, 'historyShowValue', true));

            if obj.guiChanged_(oldState, {'historyTargetType','historyUseTag'})
                obj.invalidateHistoryCache_();
            end

            polyscope.ImGui.Separator();
            polyscope.ImGui.Text(sprintf('Response: %s  |  Component: %s', ...
                char(string(obj.Opts.respType)), char(string(obj.Opts.component))));
            if strcmpi(char(string(obj.Opts.eleType)), 'Shell')
                polyscope.ImGui.Text(sprintf('Fiber: %s', char(string(obj.Opts.fiberPoint))));
            end
            gpStr = char(string(obj.Opts.surf.gpReduce));
            if strcmpi(gpStr, 'index')
                gpStr = [gpStr, ' (', num2str(round(obj.Opts.surf.gpIndex)), ')'];
            end
            polyscope.ImGui.Text(sprintf('Location: %s  |  GP reduce: %s', ...
                char(string(obj.Opts.responseLocation)), gpStr));

            [x, y, ~] = obj.responseHistorySeries_();
            finiteY = y(isfinite(y));
            if isempty(finiteY)
                polyscope.ImGui.TextDisabled('No response values for this target.');
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
            if ip.BeginPlot('##response_history_plot', [-1, 200], plotFlags)
                ip.SetupAxes('time / step', 'response');
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
                    polyscope.ImGui.Text(sprintf('Current response: %.6g', val));
                end
            end
        end

        function [x, y, label] = responseHistorySeries_(obj)
            key = obj.computeHistoryCacheKey_();
            if strcmp(obj.historyCacheKey_, key) && ~isempty(obj.historyCacheX_)
                x = obj.historyCacheX_;
                y = obj.historyCacheY_;
                label = obj.historyCacheLabel_;
                return;
            end
            x = NaN(obj.nSteps_, 1);
            y = NaN(obj.nSteps_, 1);
            label = obj.responseHistoryLabel_();
            targetType = char(string(obj.getOptField_(obj.gui_, 'historyTargetType', 'node')));
            useTag = obj.getOptField_(obj.gui_, 'historyUseTag', true);
            targetTag = obj.getOptField_(obj.gui_, 'historyTag', NaN);
            targetIndex = round(obj.getOptField_(obj.gui_, 'historyIndex', 1));
            for g = 0:obj.nSteps_ - 1
                [segIdx, localStep] = obj.resolveGlobalStep_(g);
                x(g + 1) = obj.timeAtStep_(segIdx, localStep, g);
                if strcmpi(targetType, 'element')
                    [tags, vals] = obj.responseElementValues_(segIdx, localStep);
                else
                    [tags, vals] = obj.responseNodeValues_(segIdx, localStep);
                end
                if isempty(vals), continue; end
                if useTag
                    row = find(tags == targetTag, 1);
                else
                    row = targetIndex;
                end
                if isempty(row) || row < 1 || row > numel(vals), continue; end
                y(g + 1) = vals(row);
            end
            obj.historyCacheKey_ = key;
            obj.historyCacheX_ = x;
            obj.historyCacheY_ = y;
            obj.historyCacheLabel_ = label;
        end

        function label = responseHistoryLabel_(obj)
            label = char(string(obj.Opts.respType));
            comp = char(string(obj.Opts.component));
            if ~isempty(comp) && ~any(strcmpi(comp, {'auto','value','magnitude'}))
                label = [label, ' ', comp];
            end
        end

        function key = computeHistoryCacheKey_(obj)
            key = sprintf('%s|%s|%s|%s|%s|%s|%s|%g|%g|%d|%s|%d', ...
                char(string(obj.Opts.eleType)), ...
                char(string(obj.Opts.respType)), ...
                char(string(obj.Opts.component)), ...
                char(string(obj.Opts.fiberPoint)), ...
                char(string(obj.Opts.responseLocation)), ...
                char(string(obj.Opts.surf.gpReduce)), ...
                obj.Opts.surf.gpIndex, ...
                char(string(obj.getOptField_(obj.gui_, 'historyTargetType', 'node'))), ...
                obj.getOptField_(obj.gui_, 'historyTag', NaN), ...
                obj.getOptField_(obj.gui_, 'historyIndex', 1), ...
                logical(obj.getOptField_(obj.gui_, 'historyUseTag', true)), ...
                obj.responseShapeSignature_(), ...
                obj.nSteps_);
        end

        function [tags, vals] = responseNodeValues_(obj, segIdx, localStep)
            tags = obj.historyNodeTags_(segIdx);
            vals = [];
            if isempty(tags), return; end
            [Snode, ~, ~] = obj.scalarValues_(segIdx, localStep);
            if isempty(Snode) || numel(Snode) ~= numel(tags), return; end
            vals = Snode(:);
        end

        function [tags, vals] = responseElementValues_(obj, segIdx, localStep)
            [~, ~, tags] = obj.familyCells_(segIdx);
            vals = [];
            if isempty(tags), return; end
            [~, Sele, ~] = obj.scalarValues_(segIdx, localStep);
            if isempty(Sele) || numel(Sele) ~= numel(tags), return; end
            vals = Sele(:);
        end

        function tags = historyNodeTags_(obj, segIdx)
            tags = [];
            [~, modelTags] = obj.nodeStepData_(segIdx);
            if ~isempty(modelTags)
                tags = double(modelTags(:));
            end
            if isempty(tags)
                P = obj.nodeCoords_(segIdx);
                if ~isempty(P)
                    tags = (1:size(P, 1)).';
                end
            end
        end

        function tags = historyElementTags_(obj, segIdx)
            [~, ~, tags] = obj.familyCells_(segIdx);
            if isempty(tags)
                [cells, ~, ~] = obj.familyCells_(segIdx);
                if ~isempty(cells)
                    tags = (1:size(cells, 1)).';
                end
            end
        end

        function t = timeAtStep_(obj, segIdx, localStep, globalStep)
            t = double(globalStep);
            nr = obj.safeSeg_(obj.NodalResp, segIdx);
            if isstruct(nr) && isfield(nr, 'time') && ~isempty(nr.time)
                tv = double(nr.time(:));
                if localStep >= 1 && localStep <= numel(tv)
                    t = tv(localStep);
                    return;
                end
            end
            er = obj.safeSeg_(obj.EleResp, segIdx);
            if isstruct(er) && isfield(er, 'time') && ~isempty(er.time)
                tv = double(er.time(:));
                if localStep >= 1 && localStep <= numel(tv)
                    t = tv(localStep);
                end
            end
        end

        function idx = getHistoryIndex_(obj, tags)
            idx = round(obj.getOptField_(obj.gui_, 'historyIndex', 1));
            if obj.getOptField_(obj.gui_, 'historyUseTag', true)
                hit = find(tags == obj.getOptField_(obj.gui_, 'historyTag', NaN), 1);
                if ~isempty(hit), idx = hit; end
            end
            idx = max(1, min(numel(tags), idx));
        end

        function resetResponseHistoryGui_(obj, tags)
            if nargin < 2 || isempty(tags)
                if strcmpi(obj.getOptField_(obj.gui_, 'historyTargetType', 'node'), 'element')
                    tags = obj.historyElementTags_(obj.currentSeg_);
                else
                    tags = obj.historyNodeTags_(obj.currentSeg_);
                end
            end
            obj.gui_.historyUseTag = true;
            obj.gui_.historyAutoStep = true;
            obj.gui_.historyShowValue = true;
            obj.gui_.historyIndex = 1;
            if ~isempty(tags)
                obj.gui_.historyTag = tags(1);
            else
                obj.gui_.historyTag = NaN;
            end
            obj.invalidateHistoryCache_();
        end

        function syncOptsFromGui_(obj)
            obj.Opts.surf.show = logical(obj.gui_.showMesh);
            obj.Opts.surf.showEdges = logical(obj.gui_.showEdges);
            obj.Opts.nodes.show = logical(obj.gui_.showNodes);
            obj.Opts.fixed.show = logical(obj.gui_.showFixed);
            obj.Opts.line.show = logical(obj.gui_.showLines);
            obj.Opts.interp.useInterpolation = logical(obj.gui_.useInterpolation);
            obj.Opts.deform.show = logical(obj.gui_.showDeform);
            obj.Opts.deform.autoScale = logical(obj.gui_.autoScale);
            obj.Opts.deform.scale = double(obj.gui_.deformScale);
            obj.Opts.deform.showUndeformed = logical(obj.gui_.showUndeformed);
            obj.Opts.color.deformedAlpha = double(obj.gui_.deformedAlpha);
            obj.Opts.color.undeformedAlpha = double(obj.gui_.ghostAlpha);
            obj.Opts.polyscope.edgeRadius = double(obj.gui_.edgeRadius);
            obj.Opts.polyscope.nodeRadius = double(obj.gui_.nodeRadius);
        end

        function advanceAnimation_(obj)
            if ~isfield(obj.gui_, 'animationMode') || ~obj.gui_.animationMode || ~obj.gui_.playing
                return;
            end
            step = obj.currentStep_ + obj.animDir_;
            if step >= obj.nSteps_
                if obj.gui_.pingpong
                    obj.animDir_ = -1;
                    step = max(0, obj.nSteps_ - 2);
                elseif obj.gui_.loop
                    step = 0;
                else
                    step = obj.nSteps_ - 1;
                    obj.gui_.playing = false;
                end
            elseif step < 0
                if obj.gui_.pingpong
                    obj.animDir_ = 1;
                    step = min(obj.nSteps_ - 1, 1);
                elseif obj.gui_.loop
                    step = obj.nSteps_ - 1;
                else
                    step = 0;
                    obj.gui_.playing = false;
                end
            end
            obj.currentStep_ = step;
            obj.gui_.step = step;
            obj.setStep(step, false);
        end

        function [Pdef, scale] = deformedCoords_(obj, segIdx, localStep)
            P = obj.nodeCoords_(segIdx);
            U = obj.nodalSlice_(segIdx, obj.Opts.deform.type, localStep);
            U3 = zeros(size(P));
            U3(:, 1:min(3, size(U, 2))) = U(:, 1:min(3, size(U, 2)));
            U3(~isfinite(U3)) = 0;
            scale = 0;
            if obj.Opts.deform.show
                scale = obj.deformScale_(P, U3);
                Pdef = P + scale * U3;
            else
                Pdef = P;
            end
        end

        function scale = deformScale_(obj, P, U)
            if isempty(U) || ~any(isfinite(U(:)))
                scale = 0;
                return;
            end
            if obj.Opts.deform.autoScale
                if isfield(obj.gui_, 'animationMode') && obj.gui_.animationMode
                    umax = obj.globalDeformUmax_();
                else
                    mag = sqrt(sum(U(:, 1:3).^2, 2));
                    umax = max(mag, [], 'omitnan');
                end
                if isempty(umax) || ~isfinite(umax) || umax <= 0
                    scale = 0;
                else
                    scale = 0.08 * obj.modelLength_(P) / umax;
                end
            else
                scale = double(obj.Opts.deform.scale);
            end
        end

        function U = nodalSlice_(obj, segIdx, fieldType, localStep)
            [~, modelTags] = obj.nodeStepData_(segIdx);
            U = NaN(numel(modelTags), 6);
            nr = obj.safeSeg_(obj.NodalResp, segIdx);
            if ~isstruct(nr), return; end
            fieldType = obj.normalizeNodalRespType_(nr, fieldType);
            if ~isfield(nr, fieldType), return; end
            entry = nr.(fieldType);
            [raw, dofs] = obj.responseArrayAtStep_(entry, localStep);
            if isempty(raw), return; end
            raw = obj.toCanonicalNodalDofs_(raw, dofs);
            ncol = min(size(raw, 2), 6);
            tags = [];
            if isfield(nr, 'nodeTags'), tags = double(nr.nodeTags(:)); end
            if isstruct(entry) && isfield(entry, 'nodeTags'), tags = double(entry.nodeTags(:)); end
            U(:, 1:ncol) = obj.mapNodeData_(modelTags, raw(:, 1:ncol), tags, ncol);
        end

        function [Snode, Sele, clim, nodeBased] = scalarField_(obj, segIdx, localStep)
            [Snode, Sele, nodeBased] = obj.scalarValues_(segIdx, localStep);
            vals = Snode;
            if ~nodeBased, vals = Sele; end
            if ~obj.gui_.showField || ~obj.Opts.color.useColormap
                clim = [];
            else
                clim = obj.colorLimits_(segIdx, localStep, vals);
            end
            % Preserve NaN while calculating limits, then replace missing
            % values before uploading them to Polyscope's finite buffers.
            Snode(~isfinite(Snode)) = 0;
            Sele(~isfinite(Sele)) = 0;
        end

        function [Snode, Sele, nodeBased] = scalarValues_(obj, segIdx, localStep)
            Snode = [];
            Sele = [];
            rt = obj.normalizeRespType_(segIdx, obj.Opts.respType);
            er = obj.safeSeg_(obj.EleResp, segIdx);
            [P, modelTags] = obj.nodeStepData_(segIdx);
            nodeBased = obj.resolveResponseIsNodeBased_(rt);
            if ~isstruct(er) || ~isfield(er, rt), return; end
            entry = er.(rt);
            [raw, dofs] = obj.responseArrayAtStep_(entry, localStep);
            if isempty(raw), return; end
            comp = char(string(obj.Opts.component));
            rawScalar = obj.selectComponent_(raw, dofs, comp);

            if nodeBased
                tags = [];
                if isfield(er, 'nodeTags'), tags = double(er.nodeTags(:)); end
                if isstruct(entry) && isfield(entry, 'nodeTags'), tags = double(entry.nodeTags(:)); end
                Snode = obj.mapNodeData_(modelTags, rawScalar(:), tags, 1);
                Snode = Snode(:, 1);
                return;
            end

            [cells, ~, familyTags] = obj.familyCells_(segIdx);
            if isempty(cells)
                Snode = NaN(size(P, 1), 1);
                return;
            end
            respTags = [];
            if isfield(er, 'eleTags'), respTags = double(er.eleTags(:)); end
            if isstruct(entry) && isfield(entry, 'eleTags'), respTags = double(entry.eleTags(:)); end
            Sele = obj.mapElementData_(familyTags, rawScalar(:), respTags, size(cells, 1));
            Snode = obj.elementToNodeScalars_(cells, Sele, size(P, 1));
        end

        function [raw, dofs] = responseArrayAtStep_(obj, entry, localStep)
            dofs = {};
            raw = [];
            if isstruct(entry) && isfield(entry, 'data')
                arr = double(entry.data);
                if isfield(entry, 'dofs'), dofs = cellstr(string(entry.dofs)); end
            elseif isstruct(entry)
                fn = fieldnames(entry);
                skip = {'nodetags','eletags','dofs','tags'};
                fn = fn(~ismember(lower(fn), skip));
                if isempty(fn), return; end
                parts = {};
                for i = 1:numel(fn)
                    if isnumeric(entry.(fn{i}))
                        parts{end+1} = double(entry.(fn{i})); %#ok<AGROW>
                        dofs{end+1} = fn{i}; %#ok<AGROW>
                    end
                end
                if isempty(parts), return; end
                arr = cat(ndims(parts{1}) + 1, parts{:});
            elseif isnumeric(entry)
                arr = double(entry);
            else
                return;
            end
            if isempty(arr), return; end
            si = min(max(1, localStep), size(arr, 1));
            raw = squeeze(arr(si, :, :, :, :));
            if isvector(raw), raw = raw(:); end
        end

        function raw = selectComponent_(obj, raw, dofs, comp)
            raw = double(raw);
            if isempty(raw), return; end
            if ndims(raw) == 2
                if size(raw, 2) == 1
                    raw = raw(:, 1);
                    return;
                end
                idx = obj.componentIndex_(dofs, comp, size(raw, 2));
                if idx == 0
                    raw = sqrt(sum(raw.^2, 2, 'omitnan'));
                else
                    raw = raw(:, idx);
                end
                return;
            end
            dims = size(raw);
            if numel(dims) == 3
                % nElement x nGauss/fiber x nComponent or nElement x nGauss x 1.
                idx = obj.componentIndex_(dofs, comp, dims(3));
                if idx == 0
                    vals = sqrt(sum(raw.^2, 3, 'omitnan'));
                else
                    vals = raw(:, :, idx);
                end
                if strcmpi(char(string(obj.Opts.eleType)), 'Shell') && ...
                        obj.resolveResponseIsNodeBased_(obj.Opts.respType)
                    vals = vals(:, obj.fiberIndex_(size(vals, 2)));
                    raw = vals(:);
                    return;
                end
                raw = obj.reduceGp_(vals);
                return;
            end
            if numel(dims) >= 4
                idx = obj.componentIndex_(dofs, comp, dims(end));
                if idx == 0
                    vals = sqrt(sum(raw.^2, ndims(raw), 'omitnan'));
                else
                    subs = repmat({':'}, 1, ndims(raw));
                    subs{end} = idx;
                    vals = raw(subs{:});
                end
                vals = squeeze(vals);
                if strcmpi(char(string(obj.Opts.eleType)), 'Shell') && ndims(vals) >= 3
                    fibIdx = obj.fiberIndex_(size(vals, 3));
                    vals = vals(:, :, fibIdx);
                end
                while ndims(vals) > 2
                    vals = squeeze(mean(vals, ndims(vals), 'omitnan'));
                end
                raw = obj.reduceGp_(vals);
                return;
            end
            raw = raw(:);
        end

        function vals = reduceGp_(obj, vals)
            vals = double(vals);
            if isvector(vals)
                vals = vals(:);
                return;
            end
            mode = lower(char(string(obj.Opts.surf.gpReduce)));
            switch mode
                case 'max'
                    vals = max(vals, [], 2, 'omitnan');
                case 'min'
                    vals = min(vals, [], 2, 'omitnan');
                case 'index'
                    idx = min(max(1, round(obj.Opts.surf.gpIndex)), size(vals, 2));
                    vals = vals(:, idx);
                otherwise
                    vals = mean(vals, 2, 'omitnan');
            end
        end

        function idx = fiberIndex_(obj, nFiber)
            idx = 1;
            fp = obj.Opts.fiberPoint;
            if isnumeric(fp)
                idx = min(max(1, round(double(fp))), max(1, nFiber));
                return;
            end
            switch lower(char(string(fp)))
                case 'bottom'
                    idx = max(1, nFiber);
                case 'middle'
                    idx = max(1, round((nFiber + 1) / 2));
                otherwise
                    idx = 1;
            end
        end

        function idx = componentIndex_(~, dofs, comp, nComp)
            idx = 1;
            c = lower(strtrim(char(string(comp))));
            if isempty(c) || strcmp(c, 'auto') || strcmp(c, 'value')
                idx = 1;
                return;
            end
            if any(strcmp(c, {'magnitude','mag','norm'}))
                idx = 0;
                return;
            end
            if ~isempty(dofs)
                names = lower(strtrim(cellstr(string(dofs))));
                m = find(strcmp(names, c), 1);
                if ~isempty(m)
                    idx = min(m, nComp);
                    return;
                end
            end
            num = str2double(c);
            if isfinite(num)
                idx = min(max(1, round(num)), nComp);
            else
                idx = min(1, nComp);
            end
        end

        function S = mapNodeData_(~, modelTags, data, respTags, ncol)
            if nargin < 5 || isempty(ncol), ncol = size(data, 2); end
            if isvector(data), data = data(:); end
            S = NaN(numel(modelTags), ncol);
            if isempty(respTags)
                n = min(size(data, 1), numel(modelTags));
                S(1:n, 1:min(ncol, size(data, 2))) = data(1:n, 1:min(ncol, size(data, 2)));
                return;
            end
            respTags = double(respTags(:));
            [tf, loc] = ismember(double(modelTags(:)), respTags);
            valid = tf & loc > 0 & loc <= size(data, 1);
            S(valid, 1:min(ncol, size(data, 2))) = data(loc(valid), 1:min(ncol, size(data, 2)));
            if ~any(valid) && size(data, 1) == numel(modelTags)
                S(:, 1:min(ncol, size(data, 2))) = data(:, 1:min(ncol, size(data, 2)));
            end
        end

        function Sele = mapElementData_(~, familyTags, data, respTags, nEle)
            Sele = NaN(nEle, 1);
            data = double(data(:));
            if isempty(respTags) || isempty(familyTags)
                n = min(nEle, numel(data));
                Sele(1:n) = data(1:n);
                return;
            end
            [tf, loc] = ismember(double(familyTags(:)), double(respTags(:)));
            valid = tf & loc > 0 & loc <= numel(data);
            Sele(valid) = data(loc(valid));
            if ~any(valid) && numel(data) == nEle
                Sele = data(:);
            end
        end

        function Snode = elementToNodeScalars_(~, cells, Sele, nNode)
            Snode = NaN(nNode, 1);
            acc = zeros(nNode, 1);
            cnt = zeros(nNode, 1);
            for e = 1:size(cells, 1)
                conn = double(cells(e, :));
                conn = conn(isfinite(conn));
                if numel(conn) >= 2 && conn(1) == numel(conn) - 1
                    conn = conn(2:end);
                end
                conn = round(conn(:));
                conn = conn(conn >= 1 & conn <= nNode);
                if isempty(conn) || e > numel(Sele) || ~isfinite(Sele(e)), continue; end
                acc(conn) = acc(conn) + Sele(e);
                cnt(conn) = cnt(conn) + 1;
            end
            valid = cnt > 0;
            Snode(valid) = acc(valid) ./ cnt(valid);
        end

        function clim = colorLimits_(obj, segIdx, localStep, vals)
            if isfield(obj.Opts.color, 'clim') && ~isempty(obj.Opts.color.clim)
                clim = double(obj.Opts.color.clim(:).');
                return;
            end
            mode = lower(char(string(obj.Opts.color.climMode)));
            if any(strcmp(mode, {'global','range','absmax','absmin'}))
                key = sprintf('%s|%s|%s|%s|%d', obj.Opts.eleType, obj.Opts.respType, ...
                    obj.Opts.component, obj.Opts.responseLocation, obj.nSteps_);
                clim = obj.cachedRange_('unstruClim', key, @() obj.computeGlobalClim_());
            else
                clim = obj.localClim_(vals);
            end
            if isempty(clim)
                clim = obj.localClim_(vals);
            end
            if strcmp(mode, 'absmax')
                m = max(abs(clim));
                clim = [-m, m];
            elseif strcmp(mode, 'absmin')
                m = min(abs(clim));
                clim = [-m, m];
            end
        end

        function clim = computeGlobalClim_(obj)
            allv = [];
            for g = 0:obj.nSteps_ - 1
                [s, l] = obj.resolveGlobalStep_(g);
                allv = [allv; obj.rawStepScalar_(s, l)]; %#ok<AGROW>
            end
            clim = obj.localClim_(allv);
        end

        function clim = localClim_(~, vals)
            vals = double(vals(:));
            vals = vals(isfinite(vals));
            if isempty(vals)
                clim = [];
                return;
            end
            lo = min(vals);
            hi = max(vals);
            if lo == hi
                d = max(1, abs(lo)) * 0.05;
                lo = lo - d;
                hi = hi + d;
            end
            clim = [lo, hi];
        end

        function args = scalarArgs_(obj, clim)
            args = {'enabled', logical(obj.gui_.showField && obj.Opts.color.useColormap), ...
                'cmap', char(string(obj.Opts.polyscope.scalarColorMap))};
            if ~isempty(clim) && all(isfinite(clim))
                args = [args, {'map_range', double(clim(:).')}];
            end
            cb = obj.colorbarArgs_();
            if ~isempty(cb)
                args = [args, cb];
            end
        end

        function q = scalarQuantityName_(obj)
            q = char(string(obj.Opts.respType));
            comp = char(string(obj.Opts.component));
            if ~isempty(comp) && ~any(strcmpi(comp, {'auto','value'}))
                q = [q '_' comp];
            end
        end

        function [cells, types, tags] = familyCells_(obj, segIdx)
            cells = zeros(0, 0);
            types = zeros(0, 1);
            tags = zeros(0, 1);
            fam = obj.families_(segIdx);
            nm = char(string(obj.Opts.eleType));
            if ~isfield(fam, nm), return; end
            S = fam.(nm);
            if isfield(S, 'Cells'), cells = double(S.Cells); end
            if isfield(S, 'CellTypes'), types = double(S.CellTypes(:)); end
            if isempty(types) && ~isempty(cells)
                types = obj.defaultCellType_(nm, cells);
            end
            if isfield(S, 'Tags'), tags = double(S.Tags(:)); end
            if isempty(tags), tags = (1:size(cells, 1)).'; end
            if ~isempty(cells)
                keep = ~all(isnan(cells), 2);
                cells = cells(keep, :);
                types = types(keep);
                tags = tags(keep);
            end
        end

        function rows = expandedSurfacePointRows_(obj, cells)
            rows = zeros(0, 1);
            for i = 1:size(cells, 1)
                conn = obj.normalizedCellConn_(cells(i, :));
                rows = [rows; conn(:)]; %#ok<AGROW>
            end
        end

        function rows = expandedSurfaceEdgeRows_(obj, types, cells)
            rows = zeros(0, 1);
            for i = 1:size(cells, 1)
                conn = obj.normalizedCellConn_(cells(i, :));
                if isempty(conn), continue; end
                loops = obj.surfaceBoundaryLoops_(types(i));
                for j = 1:numel(loops)
                    seq = loops{j}(:) + 1;
                    seq = seq(seq >= 1 & seq <= numel(conn));
                    if isempty(seq), continue; end
                    rows = [rows; conn(seq(:)); NaN]; %#ok<AGROW>
                end
            end
        end

        function Psurf = surfacePointsFromRows_(obj, P)
            if ~isfield(obj.meshData_, 'pointRows') || isempty(obj.meshData_.pointRows)
                Psurf = zeros(0, 3);
                return;
            end
            rows = round(double(obj.meshData_.pointRows(:)));
            valid = rows >= 1 & rows <= size(P, 1);
            Psurf = zeros(numel(rows), size(P, 2));
            Psurf(valid, :) = P(rows(valid), :);
        end

        function S = expandNodeScalarsByRows_(obj, Snode)
            rows = round(double(obj.meshData_.pointRows(:)));
            S = NaN(numel(rows), 1);
            valid = rows >= 1 & rows <= numel(Snode);
            S(valid) = Snode(rows(valid));
        end

        function edgePoints = meshEdgePolylineFromRows_(obj, P)
            edgePoints = zeros(0, 3);
            if ~isfield(obj.meshData_, 'edgeRows') || isempty(obj.meshData_.edgeRows)
                return;
            end
            rows = double(obj.meshData_.edgeRows(:));
            edgePoints = NaN(numel(rows), size(P, 2));
            valid = isfinite(rows) & rows >= 1 & rows <= size(P, 1);
            edgePoints(valid, :) = P(round(rows(valid)), :);
        end

        function conn = normalizedCellConn_(~, row)
            conn = double(row(:).');
            conn = conn(isfinite(conn));
            if isempty(conn), return; end
            if numel(conn) >= 2 && conn(1) == numel(conn) - 1
                conn = conn(2:end);
            end
            conn = round(conn(:));
        end

        function loops = surfaceBoundaryLoops_(~, cellType)
            switch double(cellType)
                case 5
                    loops = {[0 1 2 0]};
                case 22
                    loops = {[0 3 1 4 2 5 0]};
                case 34
                    loops = {[0 3 1 4 2 5 0]};
                case 9
                    loops = {[0 1 2 3 0]};
                case 23
                    loops = {[0 4 1 5 2 6 3 7 0]};
                case 28
                    loops = {[0 4 1 5 2 6 3 7 0]};
                case 10
                    loops = {[0 1 2 0], [0 1 3 0], [0 2 3 0], [1 2 3 1]};
                case 24
                    loops = {[0 4 1 5 2 6 0], [0 4 1 8 3 7 0], ...
                             [0 7 3 9 2 6 0], [1 8 3 9 2 5 1]};
                case 12
                    loops = {[0 1 2 3 0], [0 1 5 4 0], [0 3 7 4 0], ...
                             [1 2 6 5 1], [2 3 7 6 2], [4 5 6 7 4]};
                case 25
                    loops = {[0 8 1 9 2 10 3 11 0], [0 16 4 12 5 17 1 8 0], ...
                             [0 16 4 15 7 19 3 11 0], [4 12 5 13 6 14 7 15 4], ...
                             [3 19 7 14 6 18 2 10 3], [1 17 5 13 6 18 2 9 1]};
                case 29
                    loops = {[0 8 1 9 2 10 3 11 0], [0 16 4 12 5 17 1 8 0], ...
                             [0 16 4 15 7 19 3 11 0], [4 12 5 13 6 14 7 15 4], ...
                             [3 19 7 14 6 18 2 10 3], [1 17 5 13 6 18 2 9 1]};
                otherwise
                    loops = {};
            end
        end

        function types = defaultCellType_(~, nm, cells)
            n = size(cells, 2);
            if n >= 2 && all(cells(:, 1) == n - 1)
                n = n - 1;
            end
            switch lower(nm)
                case {'plane','shell'}
                    if n == 3, t = 5; else, t = 9; end
                otherwise
                    if n == 4, t = 10; else, t = 12; end
            end
            types = repmat(t, size(cells, 1), 1);
        end

        function fam = families_(obj, segIdx)
            segIdx = min(max(1, segIdx), numel(obj.ModelInfo));
            fam = plotter.polyscope.ModelAdapter.families(obj.ModelInfo(segIdx));
        end

        function P = nodeCoords_(obj, segIdx)
            segIdx = min(max(1, segIdx), numel(obj.ModelInfo));
            P = plotter.polyscope.ModelAdapter.nodeCoords(obj.ModelInfo(segIdx));
        end

        function [P, tags] = nodeStepData_(obj, segIdx)
            P = obj.nodeCoords_(segIdx);
            segIdx = min(max(1, segIdx), numel(obj.ModelInfo));
            tags = plotter.polyscope.ModelAdapter.nodeTags(obj.ModelInfo(segIdx));
        end

        function [Pfix, rows] = fixedNodes_(obj, segIdx, P)
            if nargin < 3 || isempty(P), P = obj.nodeCoords_(segIdx); end
            segIdx = min(max(1, segIdx), numel(obj.ModelInfo));
            [~, fixedTags] = plotter.polyscope.ModelAdapter.fixedNodes(obj.ModelInfo(segIdx));
            tags = plotter.polyscope.ModelAdapter.nodeTags(obj.ModelInfo(segIdx));
            [tf, rows] = ismember(double(fixedTags(:)), double(tags(:)));
            rows = rows(tf & rows > 0);
            if isempty(rows)
                Pfix = zeros(0, 3);
            else
                Pfix = P(rows, :);
            end
        end

        function buildStepIndex_(obj)
            nSeg = max([numel(obj.NodalResp), numel(obj.EleResp), numel(obj.ModelInfo)]);
            obj.segStepCounts_ = ones(1, nSeg);
            for s = 1:nSeg
                obj.segStepCounts_(s) = max([obj.countSteps_(obj.safeSeg_(obj.NodalResp, s)), ...
                    obj.countSteps_(obj.safeSeg_(obj.EleResp, s)), 1]);
            end
            obj.segOffsets_ = [0, cumsum(obj.segStepCounts_(1:end-1))];
            obj.nSteps_ = sum(obj.segStepCounts_);
        end

        function n = countSteps_(~, S)
            n = 1;
            if ~isstruct(S), return; end
            if isfield(S, 'time') && ~isempty(S.time)
                n = numel(S.time);
                return;
            end
            fn = fieldnames(S);
            for i = 1:numel(fn)
                v = S.(fn{i});
                if isnumeric(v) && ~isempty(v)
                    n = max(n, size(v, 1));
                elseif isstruct(v) && isfield(v, 'data') && isnumeric(v.data)
                    n = max(n, size(v.data, 1));
                end
            end
        end

        function [segIdx, localStep] = resolveGlobalStep_(obj, step)
            step = min(max(0, round(step)), obj.nSteps_ - 1);
            segIdx = find(step >= obj.segOffsets_, 1, 'last');
            if isempty(segIdx), segIdx = 1; end
            localStep = step - obj.segOffsets_(segIdx) + 1;
            localStep = min(max(1, localStep), obj.segStepCounts_(segIdx));
        end

        function step = resolveStepArg_(obj, arg)
            if isnumeric(arg)
                step = min(max(0, round(double(arg))), obj.nSteps_ - 1);
                return;
            end
            key = lower(char(string(arg)));
            if ismember(key, {'absmax','abs_max','absmin','abs_min','max','min'})
                cacheKey = obj.extremeStepCacheKey_(key);
                cacheField = obj.simpleHashField_(cacheKey);
                if isfield(obj.extremeStepCache_, cacheField)
                    rec = obj.extremeStepCache_.(cacheField);
                    if isstruct(rec) && isfield(rec, 'key') && strcmp(rec.key, cacheKey) && isfield(rec, 'step')
                        step = rec.step;
                        return;
                    end
                end
            end
            switch key
                case {'absmax','abs_max'}
                    step = obj.extremeStep_(true, true);
                case {'absmin','abs_min'}
                    step = obj.extremeStep_(true, false);
                case 'max'
                    step = obj.extremeStep_(false, true);
                case 'min'
                    step = obj.extremeStep_(false, false);
                otherwise
                    step = 0;
            end
            if ismember(key, {'absmax','abs_max','absmin','abs_min','max','min'})
                obj.extremeStepCache_.(cacheField) = struct('key', cacheKey, 'step', step);
            end
        end

        function step = extremeStep_(obj, useAbs, wantMax)
            bestVal = -inf;
            if ~wantMax, bestVal = inf; end
            step = 0;
            for g = 0:obj.nSteps_ - 1
                [s, l] = obj.resolveGlobalStep_(g);
                vals = obj.rawStepScalar_(s, l);
                vals = vals(isfinite(vals));
                if isempty(vals), continue; end
                if useAbs, vals = abs(vals); end
                if wantMax
                    v = max(vals);
                    if v > bestVal, bestVal = v; step = g; end
                else
                    v = min(vals);
                    if v < bestVal, bestVal = v; step = g; end
                end
            end
        end

        function vals = rawStepScalar_(obj, segIdx, localStep)
            vals = [];
            rt = obj.normalizeRespType_(segIdx, obj.Opts.respType);
            er = obj.safeSeg_(obj.EleResp, segIdx);
            if ~isstruct(er) || ~isfield(er, rt), return; end
            [raw, dofs] = obj.responseArrayAtStep_(er.(rt), localStep);
            if isempty(raw), return; end
            vals = obj.selectComponent_(raw, dofs, char(string(obj.Opts.component)));
            vals = vals(:);
        end

        function key = extremeStepCacheKey_(obj, mode)
            key = sprintf('%s|%s|%s|%s|%s|%s|%s|%d|%s', ...
                lower(char(string(mode))), char(string(obj.Opts.eleType)), ...
                char(string(obj.Opts.respType)), char(string(obj.Opts.component)), ...
                obj.responseLocation_(), char(string(obj.Opts.surf.gpReduce)), ...
                char(string(obj.Opts.fiberPoint)), obj.nSteps_, obj.responseShapeSignature_());
        end

        function sig = responseShapeSignature_(obj)
            sigParts = cell(1, numel(obj.EleResp));
            rt0 = char(string(obj.Opts.respType));
            for s = 1:numel(obj.EleResp)
                er = obj.EleResp(s);
                rt = obj.normalizeRespType_(min(s, numel(obj.EleResp)), rt0);
                if isstruct(er) && isfield(er, rt)
                    entry = er.(rt);
                    if isstruct(entry) && isfield(entry, 'data') && isnumeric(entry.data)
                        sz = size(entry.data);
                    elseif isnumeric(entry)
                        sz = size(entry);
                    elseif isstruct(entry)
                        fn = fieldnames(entry);
                        sz = [0, 0];
                        for i = 1:numel(fn)
                            if isnumeric(entry.(fn{i}))
                                sz = size(entry.(fn{i}));
                                break;
                            end
                        end
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

        function invalidateScalarCaches_(obj)
            obj.invalidateCachedRange_('unstruClim');
            obj.invalidateCachedRange_('unstruDeform');
            obj.extremeStepCache_ = struct();
        end

        function umax = globalDeformUmax_(obj)
            key = matlab.lang.makeValidName(sprintf('%s_%d_%s', ...
                char(string(obj.Opts.deform.type)), obj.nSteps_, obj.deformShapeSignature_()));
            umax = obj.cachedRange_('unstruDeform', key, @() obj.computeGlobalDeformUmax_());
        end

        function umax = computeGlobalDeformUmax_(obj)
            umax = 0;
            for g = 0:obj.nSteps_ - 1
                [segIdx, localStep] = obj.resolveGlobalStep_(g);
                U = obj.nodalSlice_(segIdx, obj.Opts.deform.type, localStep);
                U3 = zeros(size(U, 1), 3);
                U3(:, 1:min(3, size(U, 2))) = U(:, 1:min(3, size(U, 2)));
                U3(~isfinite(U3)) = 0;
                mag = sqrt(sum(U3.^2, 2, 'omitnan'));
                m = max(mag, [], 'omitnan');
                if isfinite(m)
                    umax = max(umax, m);
                end
            end
        end

        function sig = deformShapeSignature_(obj)
            sigParts = cell(1, numel(obj.NodalResp));
            field = char(string(obj.Opts.deform.type));
            for s = 1:numel(obj.NodalResp)
                nr = obj.NodalResp(s);
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

        function types = collectElementTypes_(obj)
            cand = {'Shell','Plane','Solid'};
            types = {};
            fam = obj.families_(1);
            for i = 1:numel(cand)
                if isfield(fam, cand{i}) && isfield(fam.(cand{i}), 'Cells') && ~isempty(fam.(cand{i}).Cells)
                    types{end+1} = cand{i}; %#ok<AGROW>
                end
            end
        end

        function names = collectResponseTypes_(obj)
            er = obj.safeSeg_(obj.EleResp, 1);
            names = {};
            if ~isstruct(er), return; end
            skip = {'odbtag','time','nodetags','eletags','eletype','interpolatepoints', ...
                'interpolatedisp','interpolatecells','interpolatecoords'};
            fn = fieldnames(er);
            for i = 1:numel(fn)
                if ~ismember(lower(fn{i}), skip)
                    v = er.(fn{i});
                    if isnumeric(v) || isstruct(v)
                        names{end+1} = fn{i}; %#ok<AGROW>
                    end
                end
            end
        end

        function comps = componentsForResponse_(obj, rt)
            comps = {'value'};
            er = obj.safeSeg_(obj.EleResp, 1);
            rt = obj.normalizeRespType_(1, rt);
            if ~isstruct(er) || ~isfield(er, rt), return; end
            entry = er.(rt);
            if isstruct(entry) && isfield(entry, 'dofs') && ~isempty(entry.dofs)
                comps = cellstr(string(entry.dofs));
                comps = [{'magnitude'}, comps(:).'];
            elseif isstruct(entry) && ~isfield(entry, 'data')
                fn = fieldnames(entry);
                fn = fn(~ismember(lower(fn), {'nodetags','eletags','dofs','tags'}));
                if ~isempty(fn), comps = fn(:).'; end
            elseif isnumeric(entry)
                if ndims(entry) >= 3 && size(entry, ndims(entry)) > 1
                    comps = [{'magnitude'}, arrayfun(@(i) sprintf('c%d', i), 1:size(entry, ndims(entry)), 'UniformOutput', false)];
                end
            end
        end

        function rt = normalizeRespType_(obj, segIdx, rt)
            rt = char(string(rt));
            er = obj.safeSeg_(obj.EleResp, segIdx);
            if isstruct(er) && ~isfield(er, rt)
                fn = fieldnames(er);
                m = find(strcmpi(fn, rt), 1);
                if ~isempty(m), rt = fn{m}; end
            end
        end

        function fieldType = normalizeNodalRespType_(~, nr, fieldType)
            fieldType = char(string(fieldType));
            if isstruct(nr) && ~isfield(nr, fieldType)
                fn = fieldnames(nr);
                idx = find(strcmpi(fn, fieldType), 1);
                if ~isempty(idx)
                    fieldType = fn{idx};
                end
            end
        end

        function loc = responseLocation_(obj)
            loc = char(string(obj.Opts.responseLocation));
            if isempty(loc), loc = 'auto'; end
        end

        function tf = resolveResponseIsNodeBased_(obj, rt)
            loc = lower(strtrim(obj.responseLocation_()));
            switch loc
                case {'node','nodes','nodal','atnode'}
                    tf = true;
                case {'gp','gauss','gausspoint','gausspoints','element','elements','ele','atgp'}
                    tf = false;
                otherwise
                    tf = contains(lower(char(string(rt))), 'atnode') || contains(lower(char(string(rt))), 'node');
            end
        end

        function vals = expandFaceScalars_(~, Sele, triIds)
            if isempty(triIds)
                vals = Sele(:);
                return;
            end
            triIds = max(1, min(numel(Sele), round(double(triIds(:)))));
            vals = Sele(triIds);
        end

        function vals = expandVolumeCellScalars_(~, Sele, cellIds)
            if isempty(cellIds)
                vals = Sele(:);
                return;
            end
            cellIds = max(1, min(numel(Sele), round(double(cellIds(:)))));
            vals = Sele(cellIds);
        end

        function M = toDofMatrix_(~, raw, dofs)
            raw = double(raw);
            if isvector(raw), M = raw(:); return; end
            M = raw;
            if ~isempty(dofs) && size(raw, 2) > numel(dofs) && numel(dofs) > 0
                M = raw(:, 1:numel(dofs));
            end
        end

        function M = toCanonicalNodalDofs_(obj, raw, dofs)
            raw = obj.toDofMatrix_(raw, dofs);
            if isempty(raw)
                M = raw;
                return;
            end
            canonical = {'ux','uy','uz','rx','ry','rz'};
            M = NaN(size(raw, 1), 6);
            if isempty(dofs)
                n = min(6, size(raw, 2));
                M(:, 1:n) = raw(:, 1:n);
                return;
            end
            names = obj.normalizeDofNames_(dofs);
            for i = 1:min(numel(names), size(raw, 2))
                idx = find(strcmp(canonical, names{i}), 1);
                if ~isempty(idx)
                    M(:, idx) = raw(:, i);
                elseif i <= 6 && all(~isfinite(M(:, i)))
                    M(:, i) = raw(:, i);
                end
            end
        end

        function names = normalizeDofNames_(~, dofs)
            names = lower(strtrim(cellstr(string(dofs))));
            for i = 1:numel(names)
                switch names{i}
                    case {'x','u1','dx','dof1','transx'}
                        names{i} = 'ux';
                    case {'y','u2','dy','dof2','transy'}
                        names{i} = 'uy';
                    case {'z','u3','dz','dof3','transz'}
                        names{i} = 'uz';
                    case {'r1','rotx','theta1','theta_x'}
                        names{i} = 'rx';
                    case {'r2','roty','theta2','theta_y'}
                        names{i} = 'ry';
                    case {'r3','rotz','theta3','theta_z'}
                        names{i} = 'rz';
                end
            end
        end

        function S = safeSeg_(~, A, idx)
            if isempty(A)
                S = struct();
            else
                % Match the MATLAB response viewers: a scalar input is a
                % topology/response fallback for every segment, while a
                % shorter array keeps using its latest available snapshot.
                S = A(min(max(1, idx), numel(A)));
            end
        end

        function out = getField_(~, S, name, fallback)
            out = fallback;
            if isstruct(S) && isfield(S, name)
                out = S.(name);
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
    end
end
