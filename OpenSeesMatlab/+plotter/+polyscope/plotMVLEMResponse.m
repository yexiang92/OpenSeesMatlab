classdef plotMVLEMResponse < plotter.polyscope.ViewerBase
    %PLOTMVLEMRESPONSE Polyscope scalar-response viewer for MVLEM elements.

    properties
        MVLEMResp struct
        NodalResp struct
    end

    properties (Access = private)
        responseNames_ cell = {}
        componentNames_ cell = {}
        nSteps_ double = 1
        currentStep_ double = 0
        lastTick_ uint64 = uint64(0)
        animDir_ double = 1
        initialOpts_ struct
        segCounts_ double = []
        currentSeg_ double = 0
        hasMixedTopology_ logical = false
        lastGuiError_ char = ''
    end

    methods
        function obj = plotMVLEMResponse(modelInfo, respData, opts, nodalResp)
            if nargin < 2 || isempty(modelInfo) || isempty(respData)
                error('plotter:polyscope:plotMVLEMResponse:InvalidInput', ...
                    'modelInfo and MVLEM response data are required.');
            end
            if nargin < 3, opts = struct(); end
            if nargin < 4, nodalResp = struct(); end
            obj = obj@plotter.polyscope.ViewerBase();
            obj.ModelInfo = modelInfo;
            obj.MVLEMResp = respData;
            obj.NodalResp = nodalResp;
            obj.Opts = plotter.polyscope.Options.mergeOpts( ...
                plotter.polyscope.Options.defaultMVLEMResponseOptions(), opts);
            obj.App = plotter.polyscope.PolyscopeApp();
            obj.responseNames_ = obj.collectResponses_();
            if isempty(obj.responseNames_)
                error('plotter:polyscope:plotMVLEMResponse:NoResponse', ...
                    ['No numeric MVLEM response field was found. The ODB may ', ...
                     'contain model geometry only. Remove/flush the recorders ', ...
                     'before reading it, and regenerate ODB files created with ', ...
                     'an older OpenSeesMATLAB MEX.']);
            end
            obj.Opts.respType = obj.pick_(obj.responseNames_, obj.Opts.respType);
            obj.componentNames_ = obj.components_();
            obj.Opts.component = obj.pick_(obj.componentNames_, obj.Opts.component);
            obj.segCounts_ = obj.segmentCounts_();
            obj.nSteps_ = obj.responseStepCount_();
            obj.currentStep_ = obj.resolveStep_(obj.Opts.stepIdx);
            obj.initialOpts_ = obj.Opts;
            obj.P0_ = plotter.polyscope.ModelAdapter.nodeCoords(obj.modelAtStep_());
            fam0 = plotter.polyscope.ModelAdapter.families(obj.modelAtStep_());
            obj.hasMixedTopology_ = isfield(fam0,'MVLEM') && isfield(fam0,'MVLEM3D');
            used=obj.mvlemNodeIndices_(obj.modelAtStep_(),size(obj.P0_,1));
            obj.L_=max(1,obj.physicalModelLength_(obj.P0_(used,:)));
            if obj.isHeadless_(), obj.Opts.polyscope.backend = 'openGL_mock'; end
            if obj.shouldAutoShow_()
                obj.enableGui(); obj.show();
            else
                obj.frameTick();
            end
        end

        function build(obj)
            firstBuild = ~obj.built_;
            P = plotter.polyscope.ModelAdapter.nodeCoords(obj.modelAtStep_());
            used=obj.mvlemNodeIndices_(obj.modelAtStep_(),size(P,1));
            physicalP=P(used,:);
            is2D = obj.is2DPoints_(physicalP);
            if is2D, obj.Opts.general.view = 'XY'; end
            obj.App.init(obj.Opts.polyscope.backend, obj.Opts, is2D);
            obj.setupWindowIcon_();
            obj.built_ = true;
            if isempty(fieldnames(obj.gui_)), obj.initGuiState_(); end
            obj.setStep(obj.currentStep_, true);
            obj.registerSlicePlanes_();
            obj.applySliceCullWholeElements_();
            if firstBuild, obj.setCameraForPoints_(physicalP, obj.Opts.general.view); end
        end

        function setStep(obj, stepArg, force)
            if nargin < 3, force = false; end
            obj.currentStep_ = obj.resolveStep_(stepArg);
            [~,~,seg] = obj.respAtStep_();
            rebuild = force || seg ~= obj.currentSeg_ || isempty(fieldnames(obj.handles_));
            if rebuild
                obj.clear_();
                obj.registerResponse_(true);
                obj.currentSeg_ = seg;
            else
                % Response structure names and topology are stable within a
                % segment. Replacing those structures in place avoids clearing
                % and rebuilding supports, constraints, slices, and overlays.
                obj.registerResponse_(false);
            end
            if isfield(obj.gui_, 'step'), obj.gui_.step = obj.currentStep_; end
        end

        function n = nSteps(obj)
            n = obj.nSteps_;
        end

        function guiCallback_(obj)
            try
                obj.advanceAnimation_();
                GB = plotter.polyscope.GuiBuilder;
                obj.ensureUiThemeForFrame_();
                ws = obj.safeWindowSize_();
                GB.beginDockedRight('MVLEM Response', [ws(1), 0], [390, max(560, ws(2))]);
                cleanup = onCleanup(@() GB.finish()); %#ok<NASGU>
                GB.header('MVLEM response');
                if obj.drawPlotThemeGui_('##mvlem_theme'),obj.setStep(obj.currentStep_,true);end
                if GB.collapsingHeader('Response', int32(0))
                    obj.drawResponseGui_();
                end
                if GB.collapsingHeader('Geometry', int32(0))
                    obj.drawGeometryGui_();
                end
                if GB.collapsingHeader('Style', int32(0))
                    obj.drawStyleGui_();
                end
                if ~isfield(obj.gui_,'slicePlaneIdx') || ~isfield(obj.gui_,'slicePlanes')
                    obj.initSliceGuiState_();
                end
                if obj.drawSlicePlaneGui_('##mvlem'),obj.registerSlicePlanes_();end
                if GB.collapsingHeader('Animation', int32(0))
                    obj.drawAnimationGui_();
                end
                if GB.collapsingHeader('Render quality##mvlem', int32(0))
                    obj.drawSsaaGui_('##mvlem');
                end
                if GB.collapsingHeader('Debug', int32(0))
                    [~,localStep,seg] = obj.respAtStep_();
                    polyscope.ImGui.Text(sprintf('Step %d / %d',obj.currentStep_,obj.nSteps_-1));
                    polyscope.ImGui.Text(sprintf('Segment %d, local step %d',seg,localStep-1));
                    polyscope.ImGui.Text(sprintf('%d MVLEM response fields',numel(obj.responseNames_)));
                end
                if GB.button('Reset')
                    obj.Opts = obj.initialOpts_; obj.initGuiState_(); obj.setStep(obj.resolveStep_(obj.Opts.stepIdx), true);
                end
                obj.drawScreenAxesOverlay_();
                if obj.gui_.showHistory,obj.drawHistoryWindow_(ws);end
                obj.lastGuiError_='';
            catch ME
                if ~strcmp(obj.lastGuiError_,ME.message)
                    fprintf('plotMVLEMResponse.guiCallback_ error: %s\n',ME.message);
                    obj.lastGuiError_=ME.message;
                end
            end
        end
    end

    methods (Access = protected)
        function initGuiState_(obj)
            initGuiState_@plotter.polyscope.ViewerBase(obj);
            obj.gui_.respIdx = obj.index_(obj.responseNames_, obj.Opts.respType);
            obj.gui_.responseDisplayIdx=obj.index_( ...
                {'auto','contour','diagram','both'},obj.Opts.responseDisplay);
            obj.gui_.diagramStyleIdx=obj.index_({'surface','wireframe'},obj.Opts.diagramStyle);
            obj.gui_.localForceFlipEnd=logical(obj.Opts.localForceFlipEnd);
            obj.gui_.forceResultantFlipEnd=logical(obj.Opts.forceResultantFlipEnd);
            obj.gui_.compIdx = obj.index_(obj.componentNames_, obj.Opts.component);
            obj.gui_.step = obj.currentStep_;
            obj.gui_.playing = logical(obj.Opts.animation.play);
            if obj.gui_.playing
                obj.Opts.deform.scaleMode='global';
                obj.Opts.lineDiagram.scaleMode='global';
                obj.Opts.surfaceDiagram.scaleMode='global';
            end
            obj.gui_.fps = obj.clampAnimationFps_( ...
                obj.Opts.animation.fps, obj.nSteps_);
            obj.gui_.playDuration = obj.getOptField_(obj.Opts.animation,'duration',10);
            obj.gui_.autoFrameStride = obj.getOptField_( ...
                obj.Opts.animation,'autoFrameStride',true);
            obj.gui_.frameStride = obj.getOptField_(obj.Opts.animation,'frameStride', ...
                obj.recommendedFrameStride_(obj.nSteps_,obj.gui_.fps,obj.gui_.playDuration));
            obj.gui_.loop = logical(obj.Opts.animation.loop);
            obj.gui_.pingpong = logical(obj.Opts.animation.pingpong);
            obj.gui_.showFibers = logical(obj.Opts.fibers.show);
            obj.gui_.widthToHeight = double(obj.Opts.fibers.widthToHeight);
            obj.gui_.gapFraction = double(obj.Opts.fibers.gapFraction);
            obj.gui_.showEdges = logical(obj.Opts.fibers.showEdges);
            obj.gui_.cmapIdx = obj.index_(obj.colormapNames_(), obj.Opts.polyscope.scalarColorMap);
            obj.gui_.climIdx = obj.index_({'step','global'}, obj.Opts.color.climMode);
            obj.gui_.stepModeIdx = obj.index_({'step','absmax','absmin','max','min'}, obj.Opts.stepIdx);
            obj.gui_.showDeform = logical(obj.Opts.deform.show);
            obj.gui_.autoScale = logical(obj.Opts.deform.autoScale);
            obj.gui_.deformScale = double(obj.Opts.deform.scale);
            obj.gui_.showUndeformed = logical(obj.Opts.deform.showUndeformed);
            obj.gui_.showNodes = logical(obj.Opts.nodes.show);
            obj.gui_.showFixed = logical(obj.Opts.fixed.show);
            obj.gui_.showMP = true;
            obj.gui_.fixedSymbolScale = double(obj.Opts.fixed.symbolScale);
            obj.gui_.showDiagram = logical(obj.Opts.lineDiagram.show);
            obj.gui_.showLineModel = logical(obj.Opts.lineDiagram.showModel);
            obj.gui_.diagramScale = double(obj.Opts.lineDiagram.scale);
            obj.gui_.diagramHeight = double(obj.Opts.lineDiagram.heightFraction);
            obj.gui_.diagramScaleModeIdx = obj.index_({'current','global'},obj.Opts.lineDiagram.scaleMode);
            obj.gui_.surfaceRenderModeIdx = obj.index_({'surface','wireframe'},obj.Opts.surf.renderMode);
            obj.gui_.surfaceEdges = logical(obj.Opts.surf.showEdges);
            obj.gui_.showInternalLines = logical(obj.Opts.mvlem.internalLines.show);
            obj.gui_.showSurfaceDiagram = logical(obj.Opts.surfaceDiagram.show);
            obj.gui_.showSurfaceContour = logical(obj.Opts.surfaceDiagram.showContour);
            obj.gui_.surfaceDiagramScale = double(obj.Opts.surfaceDiagram.scale);
            obj.gui_.surfaceDiagramHeight = double(obj.Opts.surfaceDiagram.heightFraction);
            obj.gui_.surfaceDiagramScaleModeIdx = obj.index_( ...
                {'current','global'},obj.Opts.surfaceDiagram.scaleMode);
            obj.gui_.surfaceAlpha = double(obj.Opts.color.deformedAlpha);
            obj.gui_.edgeColor = obj.asRgb_(obj.Opts.surf.edgeColor);
            obj.gui_.ghostAlpha = double(obj.Opts.color.undeformedAlpha);
            obj.gui_.showHistory = false;
            obj.gui_.historyEleIndex = 1;
            obj.gui_.historyShowValue = true;
            obj.gui_.historyLocationIdx = 1;
            obj.gui_.topologyIdx = obj.index_({'all','line','surface'},obj.Opts.topology);
            obj.initColorbarGuiState_(obj.quantityName_());
            obj.initSliceGuiState_();
            obj.initHistoryPlotAppearanceGui_();
        end
    end

    methods (Access = private)
        function drawResponseGui_(obj)
            GB=plotter.polyscope.GuiBuilder;
            if obj.hasMixedTopology_
                topologies={'all','line','surface'};
                oldTopology=obj.gui_.topologyIdx;
                obj.gui_.topologyIdx=GB.combo('Topology##mvlem',oldTopology,topologies);
                obj.Opts.topology=topologies{obj.gui_.topologyIdx};
                if obj.gui_.topologyIdx~=oldTopology,obj.setStep(obj.currentStep_,true);end
            end
            oldResp=obj.gui_.respIdx;
            obj.gui_.respIdx=GB.combo('Response##mvlem',oldResp,obj.responseNames_);
            if obj.gui_.respIdx~=oldResp
                obj.Opts.respType=obj.responseNames_{obj.gui_.respIdx};
                obj.componentNames_=obj.components_();
                obj.gui_.compIdx=1; obj.Opts.component=obj.componentNames_{1};
                obj.segCounts_=obj.segmentCounts_(); obj.nSteps_=obj.responseStepCount_();
                obj.gui_.fps=obj.clampAnimationFps_(obj.gui_.fps,obj.nSteps_);
                obj.Opts.animation.fps=obj.gui_.fps;
                obj.setStep(min(obj.currentStep_,obj.nSteps_-1),true);
            end
            if obj.isFiberResponse_() && obj.Opts.fibers.show
                polyscope.ImGui.Text('Field: all fiber strips');
            else
                oldComp=obj.gui_.compIdx;
                obj.gui_.compIdx=GB.combo('Component##mvlem',oldComp,obj.componentNames_);
                if obj.gui_.compIdx~=oldComp
                    obj.Opts.component=obj.componentNames_{obj.gui_.compIdx};
                    obj.setStep(obj.currentStep_,true);
                end
            end
            displayModes={'auto','contour','diagram','both'};
            oldDisplay=obj.gui_.responseDisplayIdx;
            obj.gui_.responseDisplayIdx=GB.combo( ...
                'Display##mvlem',oldDisplay,displayModes);
            obj.Opts.responseDisplay=displayModes{obj.gui_.responseDisplayIdx};
            if obj.gui_.responseDisplayIdx~=oldDisplay
                obj.setStep(obj.currentStep_,true);
            end
            effective=obj.effectiveDisplayMode_();
            polyscope.ImGui.TextDisabled(['Effective: ' effective]);
            switch effective
                case 'fibers'
                    polyscope.ImGui.TextWrapped('Cloud values are drawn on the individual macro-fiber strips.');
                case 'diagram'
                    polyscope.ImGui.TextWrapped( ...
                        'Wall-end resultants are plotted on each element centreline along the surface normal.');
                case 'both'
                    polyscope.ImGui.TextWrapped('Surface contour and normal-offset edge diagrams are shown together.');
                otherwise
                    polyscope.ImGui.TextWrapped('Element values are mapped to the MVLEM surface as a contour field.');
            end
            if any(strcmp(effective,{'diagram','both'}))
                styles={'surface','wireframe'};
                oldStyle=obj.gui_.diagramStyleIdx;
                obj.gui_.diagramStyleIdx=GB.combo('Diagram style##mvlem',oldStyle,styles);
                obj.Opts.diagramStyle=styles{obj.gui_.diagramStyleIdx};
                if obj.gui_.diagramStyleIdx~=oldStyle,obj.setStep(obj.currentStep_,true);end
            end
            if any(strcmpi(obj.Opts.respType,{'globalForces','localForces'}))
                oldFlip=obj.gui_.forceResultantFlipEnd;
                obj.gui_.forceResultantFlipEnd=GB.checkbox( ...
                    'Section-force end signs##mvlem',obj.gui_.forceResultantFlipEnd);
                obj.Opts.forceResultantFlipEnd=obj.gui_.forceResultantFlipEnd;
                if obj.gui_.forceResultantFlipEnd~=oldFlip,obj.setStep(obj.currentStep_,true);end
                polyscope.ImGui.TextDisabled('On: negate the complete L/K end resultant.');
            end
            modes={'step','absmax','absmin','max','min'};
            oldMode=obj.gui_.stepModeIdx;
            obj.gui_.stepModeIdx=GB.combo('Step mode##mvlem',oldMode,modes);
            if obj.gui_.stepModeIdx~=oldMode && obj.gui_.stepModeIdx>1
                obj.setStep(obj.resolveStep_(modes{obj.gui_.stepModeIdx}),true);
                obj.gui_.step=obj.currentStep_;
            end
            oldStep=obj.gui_.step;
            obj.gui_.step=GB.sliderInt('Step##mvlem',oldStep,0,max(0,obj.nSteps_-1));
            if obj.gui_.step~=oldStep
                obj.gui_.stepModeIdx=1;
                obj.Opts.stepIdx='step';
                obj.setStep(obj.gui_.step);
            end
            polyscope.ImGui.ProgressBar((obj.currentStep_+1)/max(1,obj.nSteps_),[0,0], ...
                sprintf('%d / %d',obj.currentStep_,max(0,obj.nSteps_-1)));
            obj.gui_.showHistory=GB.checkbox('Show response history##mvlem',obj.gui_.showHistory);
        end

        function drawHistoryWindow_(obj,ws)
            w=min(520,max(380,ws(1)*0.34));h=min(390,max(300,ws(2)*0.36));
            polyscope.ImGui.SetNextWindowPos([max(12,ws(1)-390-w-18),max(42,ws(2)-h-18)], ...
                int32(polyscope.ImGui.get_constant('ImGuiCond_FirstUseEver')));
            polyscope.ImGui.SetNextWindowSize([w,h],int32(polyscope.ImGui.get_constant('ImGuiCond_FirstUseEver')));
            visible=polyscope.ImGui.Begin('MVLEM response history');
            cleanup=onCleanup(@()polyscope.ImGui.End()); %#ok<NASGU>
            if ~visible,return;end
            GB=plotter.polyscope.GuiBuilder; tags=double(obj.MVLEMResp(1).eleTags(:));
            if isempty(tags),polyscope.ImGui.TextDisabled('No MVLEM elements are available.');return;end
            obj.gui_.historyEleIndex=GB.sliderInt('Element index##mvlem_history', ...
                obj.gui_.historyEleIndex,1,numel(tags));
            tag=tags(obj.gui_.historyEleIndex);
            if obj.isFiberResponse_()
                oldComp=obj.gui_.compIdx;
                obj.gui_.compIdx=GB.combo('Fiber##mvlem_history',oldComp,obj.componentNames_);
                if obj.gui_.compIdx~=oldComp,obj.Opts.component=obj.componentNames_{obj.gui_.compIdx};end
            elseif any(strcmpi(obj.Opts.respType,{'globalForces','localForces'}))
                A=obj.firstArray_();nLoc=floor(size(A,3)/6);
                locs={'mean','I','J','L','K'};locs=locs(1:min(numel(locs),nLoc+1));
                obj.gui_.historyLocationIdx=min(obj.gui_.historyLocationIdx,numel(locs));
                obj.gui_.historyLocationIdx=GB.combo('Node location##mvlem_history', ...
                    obj.gui_.historyLocationIdx,locs);
            end
            obj.gui_.historyShowValue=GB.checkbox('Show current value##mvlem_history',obj.gui_.historyShowValue);
            obj.drawHistoryPlotAppearanceGui_('##mvlem_history');
            [x,y]=obj.historySeries_(tag);finite=isfinite(x)&isfinite(y);
            if ~any(finite),polyscope.ImGui.TextDisabled('No response values for this element.');return;end
            xmin=min(x(finite));xmax=max(x(finite));ymin=min(y(finite));ymax=max(y(finite));
            if xmin==xmax,xmin=xmin-.5;xmax=xmax+.5;end
            if ymin==ymax,d=max(1,abs(ymin))*.05;ymin=ymin-d;ymax=ymax+d;end
            ip=polyscope.ImPlot;flags=int32(polyscope.ImPlot.get_constant('ImPlotFlags_NoLegend'));
            if ip.BeginPlot('##mvlem_history_plot',[-1,220],flags)
                ip.SetupAxes('time / step','Response');
                ip.SetupAxesLimits(xmin,xmax,ymin,ymax,int32(polyscope.ImPlot.get_constant('ImPlotCond_Always')));
                [lc,mf,mo]=obj.historyPlotColors_();ip.SetNextLineStyle(lc,2);ip.PlotLineXY('response',x(:),y(:));
                k=min(obj.currentStep_+1,numel(y));
                if isfinite(y(k))
                    ip.SetNextMarkerStyle(int32(polyscope.ImPlot.get_constant('ImPlotMarker_Circle')),8,mf,2,mo);
                    ip.PlotScatterXY('current',x(k),y(k));
                end
                ip.EndPlot();
            end
            if obj.gui_.historyShowValue
                k=min(obj.currentStep_+1,numel(y));
                polyscope.ImGui.Text(sprintf('%s / %s | element %g | %.6g', ...
                    obj.Opts.respType,obj.Opts.component,tag,y(k)));
            end
        end

        function [x,y]=historySeries_(obj,tag)
            x=[];y=[];c=obj.index_(obj.componentNames_,obj.Opts.component);offset=0;
            for s=1:numel(obj.MVLEMResp)
                R=obj.MVLEMResp(s);if ~isfield(R,obj.Opts.respType),continue;end
                idx=find(double(R.eleTags(:))==tag,1);A=double(R.(obj.Opts.respType));
                if isempty(idx),ys=nan(size(A,1),1);
                elseif any(strcmpi(obj.Opts.respType,{'globalForces','localForces'}))
                    B=reshape(A(:,idx,c:6:size(A,3)),size(A,1),[]);
                    B=obj.applyLocalForceEndSigns_(B);
                    if obj.gui_.historyLocationIdx==1,ys=mean(B,2,'omitnan');
                    else,ys=B(:,min(obj.gui_.historyLocationIdx-1,size(B,2)));end
                else,ys=A(:,idx,min(c,size(A,3)));end
                if isfield(R,'time')&&isnumeric(R.time)&&numel(R.time)==size(A,1)
                    xs=double(R.time(:));
                else,xs=(offset+(1:size(A,1))).';end
                x=[x;xs];y=[y;ys(:)];offset=offset+size(A,1); %#ok<AGROW>
            end
        end

        function drawGeometryGui_(obj)
            GB=plotter.polyscope.GuiBuilder;
            old=obj.gui_;
            GB.subtitle('Deformation');
            obj.gui_.showDeform=GB.checkbox('Deformed shape##mvlem',obj.gui_.showDeform);
            GB.sameLine();
            obj.gui_.autoScale=GB.checkbox('Auto scale##mvlem',obj.gui_.autoScale);
            obj.gui_.deformScale=GB.sliderFloat('Deformation scale##mvlem',obj.gui_.deformScale,0,100);
            obj.gui_.showUndeformed=GB.checkbox('Undeformed ghost##mvlem',obj.gui_.showUndeformed);
            obj.Opts.deform.show=obj.gui_.showDeform;
            obj.Opts.deform.autoScale=obj.gui_.autoScale;
            obj.Opts.deform.scale=obj.gui_.deformScale;
            obj.Opts.deform.showUndeformed=obj.gui_.showUndeformed;
            GB.separator(); GB.subtitle('Model visibility');
            obj.gui_.showNodes=GB.checkbox('Model nodes##mvlem',obj.gui_.showNodes);
            GB.sameLine(); obj.gui_.showFixed=GB.checkbox('Fixed nodes##mvlem',obj.gui_.showFixed);
            GB.sameLine(); obj.gui_.showMP=GB.checkbox('MP constraints##mvlem',obj.gui_.showMP);
            obj.gui_.fixedSymbolScale=GB.sliderFloat('Support size##mvlem',obj.gui_.fixedSymbolScale,0.1,2.0);
            obj.Opts.nodes.show=obj.gui_.showNodes;
            obj.Opts.fixed.show=obj.gui_.showFixed;
            obj.Opts.fixed.symbolScale=obj.gui_.fixedSymbolScale;
            if obj.guiChanged_(old,{'showDeform','autoScale','deformScale','showUndeformed', ...
                    'showNodes','showFixed','showMP','fixedSymbolScale'})
                obj.setStep(obj.currentStep_,true);
                old=obj.gui_;
            end
            fam=plotter.polyscope.ModelAdapter.families(obj.modelAtStep_());
            if isfield(fam,'MVLEM3D')
                GB.separator(); GB.subtitle('Surface representation');
                rm={'surface','wireframe'};
                obj.gui_.surfaceRenderModeIdx=GB.combo('Surface##mvlem',obj.gui_.surfaceRenderModeIdx,rm);
                obj.gui_.surfaceEdges=GB.checkbox('Mesh edges##mvlem',obj.gui_.surfaceEdges);
                obj.gui_.showInternalLines=GB.checkbox( ...
                    'MVLEM internal lines##mvlem',obj.gui_.showInternalLines);
                obj.Opts.surf.renderMode=rm{obj.gui_.surfaceRenderModeIdx};
                obj.Opts.surf.showEdges=obj.gui_.surfaceEdges;
                obj.Opts.mvlem.internalLines.show=obj.gui_.showInternalLines;
                if ~obj.isFiberResponse_()
                    effective=obj.effectiveDisplayMode_();
                    polyscope.ImGui.TextDisabled(['Response display: ' effective]);
                    if any(strcmp(effective,{'diagram','both'}))
                        sm={'current','global'};
                        obj.gui_.surfaceDiagramScaleModeIdx=GB.combo('Diagram scale mode##mvlem_surface', ...
                            obj.gui_.surfaceDiagramScaleModeIdx,sm);
                        obj.gui_.surfaceDiagramScale=GB.sliderFloat('Diagram scale##mvlem_surface', ...
                            obj.gui_.surfaceDiagramScale,0.01,20);
                        obj.gui_.surfaceDiagramHeight=GB.sliderFloat('Diagram height##mvlem_surface', ...
                            obj.gui_.surfaceDiagramHeight,0.005,0.5);
                        obj.Opts.surfaceDiagram.scaleMode=sm{obj.gui_.surfaceDiagramScaleModeIdx};
                        obj.Opts.surfaceDiagram.scale=obj.gui_.surfaceDiagramScale;
                        obj.Opts.surfaceDiagram.heightFraction=obj.gui_.surfaceDiagramHeight;
                    end
                end
                if obj.guiChanged_(old,{'surfaceRenderModeIdx','surfaceEdges','showInternalLines', ...
                        'surfaceDiagramScaleModeIdx','surfaceDiagramScale','surfaceDiagramHeight'})
                    obj.setStep(obj.currentStep_,true);old=obj.gui_;
                end
            end
            if isfield(fam,'MVLEM') && ~obj.isFiberResponse_()
                GB.separator(); GB.subtitle('Line response diagram');
                obj.gui_.showLineModel=GB.checkbox('Element line##mvlem',obj.gui_.showLineModel);
                sm={'current','global'};
                obj.gui_.diagramScaleModeIdx=GB.combo('Scale mode##mvlem',obj.gui_.diagramScaleModeIdx,sm);
                obj.gui_.diagramScale=GB.sliderFloat('Diagram scale##mvlem',obj.gui_.diagramScale,0.01,20);
                obj.gui_.diagramHeight=GB.sliderFloat('Height fraction##mvlem',obj.gui_.diagramHeight,0.005,0.5);
                obj.Opts.lineDiagram.show=true;
                obj.Opts.lineDiagram.showModel=obj.gui_.showLineModel;
                obj.Opts.lineDiagram.scaleMode=sm{obj.gui_.diagramScaleModeIdx};
                obj.Opts.lineDiagram.scale=obj.gui_.diagramScale;
                obj.Opts.lineDiagram.heightFraction=obj.gui_.diagramHeight;
                if obj.guiChanged_(old,{'showLineModel','diagramScaleModeIdx','diagramScale','diagramHeight'})
                    obj.setStep(obj.currentStep_,true); old=obj.gui_;
                end
            end
            if obj.isFiberResponse_()
                obj.gui_.showFibers=GB.checkbox('Show fiber strips##mvlem',obj.gui_.showFibers);
                obj.gui_.showEdges=GB.checkbox('Strip edges##mvlem',obj.gui_.showEdges);
                obj.gui_.gapFraction=GB.sliderFloat('Strip gap##mvlem',obj.gui_.gapFraction,0,0.25);
                obj.gui_.widthToHeight=GB.sliderFloat('2D width / height##mvlem',obj.gui_.widthToHeight,0.05,2.0);
                obj.Opts.fibers.show=obj.gui_.showFibers;
                obj.Opts.fibers.showEdges=obj.gui_.showEdges;
                obj.Opts.fibers.gapFraction=obj.gui_.gapFraction;
                obj.Opts.fibers.widthToHeight=obj.gui_.widthToHeight;
                if obj.guiChanged_(old,{'showFibers','showEdges','gapFraction','widthToHeight'})
                    obj.setStep(obj.currentStep_,true);
                end
            else
                polyscope.ImGui.Text('Element surface colored by the selected component.');
            end
            views=obj.viewNames_();
            obj.gui_.viewIdx=GB.combo('View##mvlem',obj.gui_.viewIdx,views);
            if GB.button('Apply view##mvlem')
                obj.Opts.general.view=views{obj.gui_.viewIdx};
                M=obj.modelAtStep_();P=plotter.polyscope.ModelAdapter.nodeCoords(M);
                used=obj.mvlemNodeIndices_(M,size(P,1));
                obj.setCameraForPoints_(P(used,:),obj.Opts.general.view);
            end
        end

        function drawStyleGui_(obj)
            GB=plotter.polyscope.GuiBuilder;
            if ~isfield(obj.gui_,'onscreenColorbar')
                obj.initColorbarGuiState_(obj.quantityName_());
            end
            old=obj.gui_;
            cmaps=obj.colormapNames_();
            obj.gui_.cmapIdx=GB.combo('Colormap##mvlem',obj.gui_.cmapIdx,cmaps);
            obj.Opts.polyscope.scalarColorMap=cmaps{obj.gui_.cmapIdx};
            modes={'step','global'};
            obj.gui_.climIdx=GB.combo('Color limits##mvlem',obj.gui_.climIdx,modes);
            obj.Opts.color.climMode=modes{obj.gui_.climIdx};
            obj.drawColorbarGui_('##mvlem',true);
            [chg,obj.gui_.edgeColor]=GB.colorEdit3('Edge color##mvlem',obj.gui_.edgeColor);
            if chg,obj.Opts.surf.edgeColor=obj.gui_.edgeColor;end
            obj.gui_.surfaceAlpha=GB.sliderFloat('Surface alpha##mvlem',obj.gui_.surfaceAlpha,0,1);
            obj.gui_.ghostAlpha=GB.sliderFloat('Ghost alpha##mvlem',obj.gui_.ghostAlpha,0,1);
            obj.Opts.color.deformedAlpha=obj.gui_.surfaceAlpha;
            obj.Opts.color.undeformedAlpha=obj.gui_.ghostAlpha;
            scalarChanged=obj.guiChanged_(old,{'cmapIdx','climIdx','onscreenColorbar', ...
                    'onscreenColorbarLocation','colorbarTitle'});
            appearanceChanged=obj.guiChanged_(old,{'edgeColor','surfaceAlpha','ghostAlpha'});
            if scalarChanged
                obj.setStep(obj.currentStep_,false);
            end
            if appearanceChanged
                obj.applyAppearance_();
            end
        end

        function applyAppearance_(obj)
            surfaceNames={'MVLEMFibers','MVLEM3DFibers','MVLEM3D', ...
                'MVLEMDiagram','MVLEM3DDiagram'};
            for i=1:numel(surfaceNames)
                if isfield(obj.handles_,surfaceNames{i})
                    try,obj.handles_.(surfaceNames{i}).set_transparency( ...
                        obj.Opts.color.deformedAlpha);catch,end
                end
            end
            edgeNames={'MVLEMFiberEdges','MVLEM3DFiberEdges','MVLEM3DEdges', ...
                'MVLEM3DDiagramZero'};
            for i=1:numel(edgeNames)
                if isfield(obj.handles_,edgeNames{i})
                    try,obj.handles_.(edgeNames{i}).set_color( ...
                        obj.asRgb_(obj.Opts.surf.edgeColor));catch,end
                end
            end
            ghostNames={'ghost_MVLEM','ghost_MVLEM3D'};
            for i=1:numel(ghostNames)
                if isfield(obj.handles_,ghostNames{i})
                    try,obj.handles_.(ghostNames{i}).set_transparency( ...
                        obj.Opts.color.undeformedAlpha);catch,end
                end
            end
            try,obj.App.polyscopeHandle().request_redraw();catch,end
        end

        function drawAnimationGui_(obj)
            GB=plotter.polyscope.GuiBuilder;
            oldPlaying=obj.gui_.playing;
            oldFps=obj.gui_.fps;
            if obj.gui_.playing
                if GB.button('Pause##mvlem'),obj.gui_.playing=false;end
            else
                if GB.button('Play##mvlem')
                    obj.gui_.playing=true;
                    obj.Opts.deform.scaleMode='global';
                    obj.Opts.lineDiagram.scaleMode='global';
                    obj.Opts.surfaceDiagram.scaleMode='global';
                    obj.gui_.diagramScaleModeIdx=obj.index_({'current','global'},'global');
                    obj.gui_.surfaceDiagramScaleModeIdx=obj.index_({'current','global'},'global');
                    obj.lastTick_=tic;
                end
            end
            GB.sameLine();
            if GB.button('Restart##mvlem'),obj.animDir_=1;obj.setStep(0);end
            GB.sameLine();
            if GB.button('Step##mvlem'),obj.advanceAnimationStep_();end
            polyscope.ImGui.ProgressBar((obj.currentStep_+1)/max(1,obj.nSteps_),[0,0], ...
                sprintf('%d / %d',obj.currentStep_,max(0,obj.nSteps_-1)));
            obj.gui_.loop=GB.checkbox('Loop##mvlem',obj.gui_.loop); GB.sameLine();
            obj.gui_.pingpong=GB.checkbox('Ping-pong##mvlem',obj.gui_.pingpong);
            maxFps=obj.animationFpsUpperBound_(obj.nSteps_);
            obj.gui_.fps=GB.sliderFloat('FPS##mvlem',obj.gui_.fps,1,maxFps);
            obj.gui_.autoFrameStride=GB.checkbox( ...
                'Auto frame stride##mvlem',obj.gui_.autoFrameStride);
            obj.gui_.playDuration=GB.sliderFloat( ...
                'Target duration (s)##mvlem',obj.gui_.playDuration,2,60);
            if obj.gui_.autoFrameStride
                obj.gui_.frameStride=obj.recommendedFrameStride_( ...
                    obj.nSteps_,obj.gui_.fps,obj.gui_.playDuration);
                polyscope.ImGui.TextDisabled(sprintf('Frame stride: %d (automatic)', ...
                    obj.gui_.frameStride));
            else
                obj.gui_.frameStride=GB.sliderInt('Frame stride##mvlem', ...
                    obj.gui_.frameStride,1,max(1,obj.nSteps_-1));
            end
            passTime=obj.estimatedAnimationDuration_( ...
                obj.nSteps_,obj.gui_.fps,obj.gui_.frameStride);
            polyscope.ImGui.TextDisabled(sprintf('Estimated pass: %.1f s',passTime));
            obj.Opts.animation.play=obj.gui_.playing;
            obj.Opts.animation.fps=obj.gui_.fps;
            obj.Opts.animation.loop=obj.gui_.loop;
            obj.Opts.animation.pingpong=obj.gui_.pingpong;
            obj.Opts.animation.autoFrameStride=obj.gui_.autoFrameStride;
            obj.Opts.animation.frameStride=obj.gui_.frameStride;
            obj.Opts.animation.duration=obj.gui_.playDuration;
            if oldPlaying~=obj.gui_.playing || oldFps~=obj.gui_.fps
                obj.configureAnimationRenderLoop_(obj.gui_.playing,obj.gui_.fps);
            end
            if oldPlaying && ~obj.gui_.playing
                obj.setStep(obj.currentStep_,true);
            end
        end

        function registerResponse_(obj, includeContext)
            if nargin < 2, includeContext = true; end
            ps = obj.App.polyscopeHandle();
            M = obj.modelAtStep_();
            P0 = plotter.polyscope.ModelAdapter.nodeCoords(M);
            P = obj.deformedCoords_(P0,M);
            [tags, locationVals] = obj.locationValuesAtStep_();
            fam = plotter.polyscope.ModelAdapter.families(M);
            displayMode=obj.effectiveDisplayMode_();
            showContour=any(strcmp(displayMode,{'contour','both','fibers'}));
            showDiagram=any(strcmp(displayMode,{'diagram','both'}));
            diagramOnly=showDiagram && ~showContour;
            showLine=~strcmpi(obj.Opts.topology,'surface');
            showSurface=~strcmpi(obj.Opts.topology,'line');
            if showLine && isfield(fam, 'MVLEM')
                edges = plotter.polyscope.ModelAdapter.lineEdges(M, 'MVLEM');
                ftags = obj.familyTags_(fam.MVLEM, size(edges,1));
                eloc = obj.matchLocationValues_(ftags,tags,locationVals);
                useStrips = obj.isFiberResponse_() && obj.Opts.fibers.show;
                if useStrips && ~isempty(edges)
                    [fiberVals, fiberCounts] = obj.fiberValuesAtStep_(ftags);
                    [Vf, Ff, Sf] = obj.fiberMesh_(P, edges, fiberVals, fiberCounts);
                    if ~isempty(Ff)
                        h = ps.register_surface_mesh(obj.structName_('MVLEM fibers', 'def'), Vf, Ff, 'smooth_shade', false);
                        qargs = obj.scalarArgs_(Sf);
                        h.add_face_scalar_quantity(obj.quantityName_(), obj.finiteValues_(Sf), qargs{:});
                        h.set_enabled(true);
                        obj.handles_.MVLEMFibers = h;
                        if obj.Opts.fibers.showEdges
                            [Pe,Ee] = obj.quadMeshEdges_(Vf);
                            he = ps.register_curve_network(obj.structName_('MVLEM fiber edges','def'),Pe,Ee);
                            try, he.set_radius(obj.Opts.fibers.edgeRadius*obj.L_, false); catch, end
                            he.set_color(obj.asRgb_(obj.Opts.surf.edgeColor));
                            he.set_enabled(true);
                            obj.handles_.MVLEMFiberEdges = he;
                        end
                    end
                elseif ~isempty(edges)
                    if obj.Opts.lineDiagram.show
                        [Vd,Fd,Sd]=obj.lineDiagramMesh_(P,edges,eloc);
                        if ~isempty(Fd)
                            qargs=obj.scalarArgs_(Sd);
                            if strcmpi(obj.Opts.diagramStyle,'wireframe')
                                [~,Ed]=obj.quadMeshEdges_(Vd);
                                h=ps.register_curve_network(obj.structName_('MVLEM diagram','def'),Vd,Ed);
                                h.add_node_scalar_quantity(obj.quantityName_(),obj.finiteValues_(Sd),qargs{:});
                                try,h.set_radius(obj.Opts.polyscope.diagramRadius,true);catch,end
                                h.set_enabled(true);
                            else
                                h=ps.register_surface_mesh(obj.structName_('MVLEM diagram','def'),Vd,Fd,'smooth_shade',false);
                            h.add_vertex_scalar_quantity(obj.quantityName_(),obj.finiteValues_(Sd),qargs{:});
                            h.set_enabled(true);
                            end
                            obj.handles_.MVLEMDiagram=h;
                        end
                    end
                    if obj.Opts.lineDiagram.showModel
                        % Do not pass the complete model point array here:
                        % Polyscope also draws unreferenced curve-network
                        % vertices, which exposes auxiliary MVLEM nodes as
                        % apparently random points.
                        [Pm,Em] = obj.compactCurveNetwork_(P,edges);
                        h = ps.register_curve_network(obj.structName_('MVLEM', 'def'), Pm, Em);
                        h.set_radius(obj.Opts.polyscope.edgeRadius,true);
                        h.set_enabled(true);
                        obj.handles_.MVLEM = h;
                    end
                end
            end
            if showSurface && isfield(fam, 'MVLEM3D')
                ftags = obj.familyTags_(fam.MVLEM3D, size(fam.MVLEM3D.Cells,1));
                eloc = obj.matchLocationValues_(ftags,tags,locationVals);
                if any(strcmpi(obj.Opts.respType,{'globalForces','localForces'}))
                    % Force-system translation must use the physical model
                    % geometry, never the auto-scaled display deformation.
                    eloc=obj.surfaceForceResultantsAtStep_(P0,fam.MVLEM3D.Cells,ftags);
                end
                useStrips = obj.isFiberResponse_() && obj.Opts.fibers.show;
                if useStrips
                    [fiberVals, fiberCounts] = obj.fiberValuesAtStep_(ftags);
                    [V,F,faceVals] = obj.fiberSurfaceMesh_(P, fam.MVLEM3D.Cells, ...
                        fiberVals, fiberCounts);
                    if ~isempty(F)
                        h = ps.register_surface_mesh(obj.structName_('MVLEM3D fibers', 'def'), V, F, 'smooth_shade', false);
                        qargs = obj.scalarArgs_(faceVals);
                            h.add_face_scalar_quantity(obj.quantityName_(), obj.finiteValues_(faceVals), qargs{:});
                            h.set_transparency(obj.Opts.color.deformedAlpha);
                            h.set_enabled(true);
                        obj.handles_.MVLEM3DFibers = h;
                        if obj.Opts.fibers.showEdges
                            [Pe,Ee] = obj.quadMeshEdges_(V);
                            he = ps.register_curve_network(obj.structName_('MVLEM3D fiber edges','def'),Pe,Ee);
                            try, he.set_radius(obj.Opts.fibers.edgeRadius*obj.L_,false); catch, end
                            he.set_color(obj.asRgb_(obj.Opts.surf.edgeColor));
                            he.set_enabled(true);
                            obj.handles_.MVLEM3DFiberEdges = he;
                        end
                    end
                else
                    [V,F,S] = obj.surfaceContourMesh_(P,fam.MVLEM3D.Cells,eloc);
                    if ~isempty(F)
                        h = ps.register_surface_mesh(obj.structName_('MVLEM3D', 'def'), V, F, 'smooth_shade', false);
                        if showContour
                            qargs=obj.scalarArgs_(S);
                            h.add_vertex_scalar_quantity(obj.quantityName_(),obj.finiteValues_(S),qargs{:});
                        else
                            h.set_color(obj.asRgb_(obj.Opts.color.solidColor));
                        end
                        h.set_transparency(obj.Opts.color.deformedAlpha);
                        h.set_enabled(~strcmpi(obj.Opts.surf.renderMode,'wireframe') && ~diagramOnly);
                        obj.handles_.MVLEM3D = h;
                        if showDiagram
                            [Vd,Fd,Sd]=obj.surfaceDiagramMesh_(P,fam.MVLEM3D.Cells,eloc);
                            if ~isempty(Fd)
                                qargs=obj.scalarArgs_(Sd);
                                if strcmpi(obj.Opts.diagramStyle,'wireframe')
                                    [~,Ed]=obj.quadMeshEdges_(Vd);
                                hd=ps.register_curve_network(obj.structName_('MVLEM3D diagram','def'),Vd,Ed);
                                hd.add_node_scalar_quantity(obj.quantityName_(),obj.finiteValues_(Sd),qargs{:});
                                try,hd.set_radius(obj.Opts.polyscope.diagramRadius,true);catch,end
                                hd.set_enabled(true);
                                else
                                    hd=ps.register_surface_mesh(obj.structName_('MVLEM3D diagram','def'),Vd,Fd,'smooth_shade',false);
                                    hd.add_vertex_scalar_quantity(obj.quantityName_(),obj.finiteValues_(Sd),qargs{:});
                                    hd.set_enabled(true);
                                end
                                obj.handles_.MVLEM3DDiagram=hd;
                            end
                            [Pz,Ez]=obj.surfaceCenterlineNetwork_(P,fam.MVLEM3D.Cells);
                            if ~isempty(Ez)
                                hz=ps.register_curve_network(obj.structName_( ...
                                    'MVLEM3D diagram zero line','def'),Pz,Ez);
                                hz.set_color(obj.asRgb_(obj.Opts.surf.edgeColor));
                                try,hz.set_radius(obj.Opts.polyscope.edgeRadius*0.75,true);catch,end
                                hz.set_enabled(true);
                                obj.handles_.MVLEM3DDiagramZero=hz;
                            end
                        end
                    end
                end
                contourWire=strcmpi(obj.Opts.surf.renderMode,'wireframe') && ...
                    ~useStrips && showContour && exist('V','var') && exist('S','var');
                if obj.Opts.surf.showEdges || strcmpi(obj.Opts.surf.renderMode,'wireframe') || diagramOnly
                    if contourWire
                        Pe=V;[~,Ee]=obj.quadMeshEdges_(V);
                    else
                        [Pe,Ee]=obj.quadBoundaryNetwork_(P,fam.MVLEM3D.Cells);
                    end
                    if ~isempty(Ee)
                        he=ps.register_curve_network(obj.structName_('MVLEM3D edges','def'),Pe,Ee);
                        he.set_radius(obj.Opts.polyscope.edgeRadius,true);
                        if contourWire
                            qargs=obj.scalarArgs_(S);
                            he.add_node_scalar_quantity(obj.quantityName_(), ...
                                obj.finiteValues_(S),qargs{:});
                        else
                            he.set_color(obj.asRgb_(obj.Opts.surf.edgeColor));
                        end
                        he.set_enabled(true);
                        obj.handles_.MVLEM3DEdges=he;
                    end
                end
                if obj.Opts.mvlem.internalLines.show
                    counts=obj.macroFiberCounts_(ftags);
                    [Pi,Ei]=plotter.polyscope.MVLEMGeometry.internalLines( ...
                        P,fam.MVLEM3D.Cells,obj.Opts.fibers.fiberWidths,counts);
                    if ~isempty(Ei)
                        hi=ps.register_curve_network(obj.structName_( ...
                            'MVLEM3D internal lines','def'),Pi,Ei);
                        hi.set_color(obj.asRgb_(obj.Opts.mvlem.internalLines.color));
                        try,hi.set_radius(obj.Opts.mvlem.internalLines.radius*obj.L_,false);catch,end
                        try,hi.set_material(obj.Opts.polyscope.lineMaterial);catch,end
                        hi.set_enabled(true);
                        obj.handles_.MVLEM3DInternalLines=hi;
                    end
                end
            end
            if includeContext
                obj.registerContext_(ps,M,P0,P);
            end
        end

        function P = deformedCoords_(obj,P0,M)
            if nargin < 3 || isempty(M), M=obj.modelAtStep_(); end
            P=P0;
            if ~obj.Opts.deform.show || isempty(obj.NodalResp),return;end
            [R,localStep,seg]=obj.respAtStep_();
            seg=min(seg,numel(obj.NodalResp));
            if isfield(R,'odbTag') && isfield(obj.NodalResp,'odbTag')
                hit=find(strcmp(string({obj.NodalResp.odbTag}),string(R.odbTag)),1);
                if ~isempty(hit),seg=hit;end
            end
            N=obj.NodalResp(seg);
            if ~isfield(N,'disp') || ~isstruct(N.disp) || ~isfield(N,'nodeTags'),return;end
            names={'ux','uy','uz'}; D=zeros(numel(N.nodeTags),3);
            nNodalSteps=0;
            for d=1:3
                if isfield(N.disp,names{d}) && isnumeric(N.disp.(names{d}))
                    nNodalSteps=size(N.disp.(names{d}),1);
                    if nNodalSteps>0,break;end
                end
            end
            if nNodalSteps<1,return;end
            nodalStep=obj.alignedNodalStep_(R,N,localStep,nNodalSteps);
            for d=1:3
                if isfield(N.disp,names{d})
                    A=double(N.disp.(names{d}));
                    D(:,d)=A(min(nodalStep,size(A,1)),:).';
                end
            end
            modelTags=plotter.polyscope.ModelAdapter.nodeTags(M);
            [tf,ix]=ismember(modelTags,double(N.nodeTags(:)));
            mapped=zeros(size(P0)); mapped(tf,:)=D(ix(tf),:);
            used=obj.mvlemNodeIndices_(M,size(P0,1));
            physical=false(size(P0,1),1);physical(used)=true;
            mapped(~physical,:)=0;
            factor=double(obj.Opts.deform.scale);
            if obj.Opts.deform.autoScale
                if strcmpi(char(string(obj.getOptField_(obj.Opts.deform, ...
                        'scaleMode','current'))),'global')
                    md=obj.globalDeformUmax_();
                else
                    md=max(vecnorm(mapped(used,:),2,2),[],'omitnan');
                end
                if isfinite(md) && md>eps
                    factor=factor*double(obj.Opts.deform.targetFraction)*obj.L_/md;
                end
            end
            P=P0+factor*mapped;
        end

        function umax=globalDeformUmax_(obj)
            parts=cell(1,numel(obj.NodalResp));
            for s=1:numel(obj.NodalResp)
                N=obj.NodalResp(s);
                sz=[0,0];
                if isfield(N,'disp') && isstruct(N.disp) && isfield(N.disp,'ux')
                    sz=size(N.disp.ux);
                end
                parts{s}=sprintf('%d:%s',s,strjoin(string(sz),'x'));
            end
            key=matlab.lang.makeValidName(strjoin(parts,'|'));
            umax=obj.cachedRange_('mvlemDeform',key,@() obj.computeGlobalDeformUmax_());
        end

        function umax=computeGlobalDeformUmax_(obj)
            umax=0;
            for s=1:numel(obj.NodalResp)
                N=obj.NodalResp(s);
                if ~isfield(N,'disp') || ~isstruct(N.disp) || ...
                        ~isfield(N,'nodeTags')
                    continue;
                end
                M=obj.ModelInfo(min(s,numel(obj.ModelInfo)));
                P=plotter.polyscope.ModelAdapter.nodeCoords(M);
                used=obj.mvlemNodeIndices_(M,size(P,1));
                modelTags=plotter.polyscope.ModelAdapter.nodeTags(M);
                physicalTags=modelTags(used);
                [keep,~]=ismember(double(N.nodeTags(:)),physicalTags);
                if ~any(keep),continue;end
                names={'ux','uy','uz'};
                nStep=0;
                for d=1:3
                    if isfield(N.disp,names{d}) && isnumeric(N.disp.(names{d}))
                        nStep=max(nStep,size(N.disp.(names{d}),1));
                    end
                end
                if nStep<1,continue;end
                mag2=zeros(nStep,sum(keep));
                for d=1:3
                    if ~isfield(N.disp,names{d}),continue;end
                    A=double(N.disp.(names{d}));
                    rows=min(nStep,size(A,1));
                    cols=min(numel(keep),size(A,2));
                    selected=find(keep(1:cols));
                    if ~isempty(selected)
                        mag2(1:rows,1:numel(selected))=mag2(1:rows,1:numel(selected))+ ...
                            A(1:rows,selected).^2;
                    end
                end
                m=max(sqrt(mag2),[],'all','omitnan');
                if isfinite(m),umax=max(umax,m);end
            end
        end

        function nodalStep=alignedNodalStep_(~,R,N,localStep,nNodalSteps)
            % Recorder rows are normally index-aligned.  Prefer that exact
            % correspondence because loadConst -time can make Domain times
            % repeat across load sequences; a global nearest-time search
            % would then select an earlier sequence with the same time.
            nodalStep=max(1,min(nNodalSteps,round(double(localStep))));
            if ~isfield(R,'time') || ~isnumeric(R.time) || ...
                    numel(R.time)<localStep || ~isfield(N,'time') || ...
                    ~isnumeric(N.time) || isempty(N.time)
                return;
            end
            responseTime=double(R.time(:));
            nodalTime=double(N.time(:));
            target=responseTime(localStep);
            scale=max(1,abs(target));
            timeTol=64*eps(scale);
            if nodalStep<=numel(nodalTime) && ...
                    abs(nodalTime(nodalStep)-target)<=timeTol
                return;
            end

            % Different recorder sampling rates require time matching.  If
            % the time value occurs more than once, choose the occurrence
            % nearest the index predicted from the two history lengths.
            delta=abs(nodalTime-target);
            best=min(delta,[],'omitnan');
            if isempty(best)||~isfinite(best),return;end
            candidates=find(delta<=best+max(timeTol,8*eps(max(1,best))));
            if isempty(candidates),return;end
            expected=1+(localStep-1)*max(0,numel(nodalTime)-1)/ ...
                max(1,numel(responseTime)-1);
            [~,k]=min(abs(double(candidates)-expected));
            nodalStep=max(1,min(nNodalSteps,candidates(k)));
        end

        function registerContext_(obj,ps,M,P0,P)
            used=obj.mvlemNodeIndices_(M,size(P,1));
            if obj.Opts.nodes.show && ~isempty(used)
                h=ps.register_point_cloud(obj.structName_('Nodes','def'),P(used,:));
                h.set_radius(obj.Opts.polyscope.nodeRadius,true);
                h.set_point_render_mode(obj.Opts.polyscope.pointRenderMode);
                h.set_enabled(true);
                obj.handles_.def_Nodes=h;
            end
            if obj.Opts.fixed.show
                [Pf,E]=plotter.polyscope.SupportGlyphs.build(M,P, ...
                    obj.L_*0.035*obj.Opts.fixed.symbolScale,used);
                if ~isempty(E)
                    h=ps.register_curve_network(obj.structName_('Fixed','def'),Pf,E);
                    h.set_radius(obj.Opts.polyscope.edgeRadius,true); h.set_color(obj.supportColor_());
                    h.set_enabled(true);
                    obj.handles_.def_Fixed=h;
                end
            end
            if obj.gui_.showMP
                edges=plotter.polyscope.ModelAdapter.mpConstraintEdges(M);
                keep=all(ismember(edges,used),2);edges=edges(keep,:);
                if ~isempty(edges)
                    [Pc,Ec]=obj.compactCurveNetwork_(P,edges);
                    h=ps.register_curve_network(obj.structName_('MPConstraint','def'),Pc,Ec);
                    h.set_color(obj.asRgb_(obj.getOptField_(obj.Opts.polyscope, ...
                        'mpConstraintColor',[0.75 0.20 0.25])));
                    h.set_radius(obj.Opts.polyscope.edgeRadius*0.7,true);
                    h.set_enabled(true);
                    obj.handles_.def_MPConstraint=h;
                end
            end
            if obj.Opts.deform.showUndeformed && obj.Opts.deform.show
                fam=plotter.polyscope.ModelAdapter.families(M);
                if ~strcmpi(obj.Opts.topology,'surface') && isfield(fam,'MVLEM')
                    E=plotter.polyscope.ModelAdapter.lineEdges(M,'MVLEM');
                    if ~isempty(E)
                        h=ps.register_curve_network(obj.structName_('MVLEM ghost'),P0,E);
                        h.set_radius(obj.Opts.polyscope.edgeRadius*0.75,true);
                        h.set_color(obj.asRgb_(obj.Opts.color.undeformedColor));
                        h.set_transparency(obj.Opts.color.undeformedAlpha);
                        h.set_enabled(true);
                        obj.handles_.ghost_MVLEM=h;
                    end
                end
                if ~strcmpi(obj.Opts.topology,'line') && isfield(fam,'MVLEM3D')
                    [Pe,Ee]=obj.quadBoundaryNetwork_(P0,fam.MVLEM3D.Cells);
                    if ~isempty(Ee)
                        h=ps.register_curve_network(obj.structName_('MVLEM3D ghost'),Pe,Ee);
                        h.set_radius(obj.Opts.polyscope.edgeRadius*0.75,true);
                        h.set_color(obj.asRgb_(obj.Opts.color.undeformedColor));
                        h.set_transparency(obj.Opts.color.undeformedAlpha);
                        h.set_enabled(true);
                        obj.handles_.ghost_MVLEM3D=h;
                    end
                end
            end
        end

        function [tags, vals] = valuesAtStep_(obj)
            [tags,locVals]=obj.locationValuesAtStep_();
            vals=mean(locVals,2,'omitnan');
        end

        function [tags, vals] = locationValuesAtStep_(obj)
            [R, localStep] = obj.respAtStep_();
            tags = double(R.eleTags(:));
            A = double(R.(obj.Opts.respType));
            k = min(localStep, size(A,1));
            B = reshape(A(k,:,:), size(A,2), []);
            c = obj.index_(obj.componentNames_, obj.Opts.component);
            if any(strcmpi(obj.Opts.respType,{'globalForces','localForces'}))
                ids=c:6:size(B,2);
                vals=B(:,ids);
                vals=obj.applyLocalForceEndSigns_(vals);
            else
                c=min(c,size(B,2));vals=B(:,c);
            end
        end

        function [values, fiberCounts] = fiberValuesAtStep_(obj, familyTags)
            [R, localStep] = obj.respAtStep_();
            A = double(R.(obj.Opts.respType));
            B = reshape(A(min(localStep,size(A,1)),:,:),size(A,2),[]);
            nFiber = size(B,2);
            values = nan(numel(familyTags),nFiber);
            fiberCounts = zeros(numel(familyTags),1);
            [tf,ix] = ismember(familyTags,double(R.eleTags(:)));
            values(tf,:) = B(ix(tf),:);
            validByElement = squeeze(any(isfinite(A),1));
            if isvector(validByElement), validByElement=reshape(validByElement,size(A,2),[]); end
            fiberCounts(tf) = sum(validByElement(ix(tf),:),2);
        end

        function counts=macroFiberCounts_(obj,familyTags)
            counts=zeros(numel(familyTags),1);
            names={'fiberStrain','fiberConcreteStress','fiberSteelStress'};
            for k=1:numel(names)
                for s=1:numel(obj.MVLEMResp)
                    R=obj.MVLEMResp(s);
                    if ~isfield(R,names{k})||isempty(R.(names{k})),continue;end
                    A=double(R.(names{k}));valid=squeeze(any(isfinite(A),1));
                    if isvector(valid),valid=reshape(valid,size(A,2),[]);end
                    c=sum(valid,2);[tf,ix]=ismember(familyTags,double(R.eleTags(:)));
                    counts(tf)=max(counts(tf),c(ix(tf)));break;
                end
                if any(counts),break;end
            end
        end

        function [V,F,S] = fiberMesh_(obj,P,edges,values,fiberCounts)
            V=zeros(0,3); F=zeros(0,3); S=zeros(0,1);
            if isempty(fiberCounts), return; end
            gap=max(0,min(0.45,double(obj.Opts.fibers.gapFraction)));
            widths=obj.Opts.fibers.width;
            fiberWidths=obj.Opts.fibers.fiberWidths;
            for e=1:size(edges,1)
                nFiber=fiberCounts(e); if nFiber<1, continue; end
                p1=P(edges(e,1),:); p2=P(edges(e,2),:); axis=p2-p1;
                height=norm(axis); if height<=eps, continue; end
                % In a planar model this is the in-plane normal to the wall axis.
                transverse=[-axis(2),axis(1),0];
                if norm(transverse)<=eps
                    transverse=cross(axis,[0 0 1]);
                    if norm(transverse)<=eps, transverse=cross(axis,[0 1 0]); end
                end
                transverse=transverse/norm(transverse);
                if ~isempty(fiberWidths)
                    if iscell(fiberWidths), fw=double(fiberWidths{min(e,numel(fiberWidths))}(:).');
                    elseif isvector(fiberWidths), fw=double(fiberWidths(:).');
                    else, fw=double(fiberWidths(min(e,size(fiberWidths,1)),1:nFiber)); end
                    if numel(fw)~=nFiber || any(~isfinite(fw)) || any(fw<=0)
                        error('plotter:polyscope:plotMVLEMResponse:InvalidFiberWidths', ...
                            'opts.fibers.fiberWidths must contain %d positive widths per element.',nFiber);
                    end
                    bounds=[0,cumsum(fw)]; bounds=bounds-bounds(end)/2;
                else
                    if isempty(widths), wallWidth=height*double(obj.Opts.fibers.widthToHeight);
                    elseif isscalar(widths), wallWidth=double(widths);
                    else, wallWidth=double(widths(min(e,numel(widths)))); end
                    bounds=linspace(-wallWidth/2,wallWidth/2,nFiber+1);
                end
                for f=1:nFiber
                    halfGap=(bounds(f+1)-bounds(f))*gap/2;
                    a=bounds(f)+halfGap; b=bounds(f+1)-halfGap;
                    q=[p1+a*transverse;p1+b*transverse;p2+b*transverse;p2+a*transverse];
                    i0=size(V,1); V=[V;q]; %#ok<AGROW>
                    F=[F;i0+[1 2 3];i0+[1 3 4]]; %#ok<AGROW>
                    S=[S;values(e,f);values(e,f)]; %#ok<AGROW>
                end
            end
        end

        function [V,F,S] = lineDiagramMesh_(obj,P,edges,values)
            V=zeros(0,3);F=zeros(0,3);S=zeros(0,1);
            finite=abs(values(isfinite(values)));
            maxAbs=max(finite,[],'omitnan');
            if strcmpi(obj.Opts.lineDiagram.scaleMode,'global')
                maxAbs=obj.globalComponentMax_();
            end
            if isempty(maxAbs)||~isfinite(maxAbs)||maxAbs<=eps,maxAbs=1;end
            sf=obj.Opts.lineDiagram.heightFraction*obj.L_*obj.Opts.lineDiagram.scale/maxAbs;
            for e=1:size(edges,1)
                row=values(e,:);row=row(isfinite(row));if isempty(row),continue;end
                if numel(row)>=2,v1=row(1);v2=row(end);else,v1=row(1);v2=v1;end
                p1=P(edges(e,1),:);p2=P(edges(e,2),:);axis=p2-p1;
                transverse=[-axis(2),axis(1),0];
                if norm(transverse)<=eps
                    transverse=cross(axis,[0 0 1]);
                    if norm(transverse)<=eps,transverse=cross(axis,[0 1 0]);end
                end
                transverse=transverse/max(norm(transverse),eps);
                q=[p1;p2;p2+sf*v2*transverse;p1+sf*v1*transverse];
                i0=size(V,1);V=[V;q];F=[F;i0+[1 2 3];i0+[1 3 4]]; %#ok<AGROW>
                S=[S;v1;v2;v2;v1]; %#ok<AGROW>
            end
        end

        function [V,F,S] = surfaceDiagramMesh_(obj,P,cells,values)
            V=zeros(0,3);F=zeros(0,3);S=zeros(0,1);
            isForce=any(strcmpi(obj.Opts.respType,{'globalForces','localForces'}));
            finite=abs(values(isfinite(values)));maxAbs=max(finite,[],'omitnan');
            if strcmpi(obj.Opts.surfaceDiagram.scaleMode,'global')
                maxAbs=obj.globalComponentMax_();
            end
            if isempty(maxAbs)||~isfinite(maxAbs)||maxAbs<=eps,maxAbs=1;end
            sf=obj.Opts.surfaceDiagram.heightFraction*obj.L_*obj.Opts.surfaceDiagram.scale/maxAbs;
            for e=1:size(cells,1)
                ids=obj.orderedQuadIds_(P,cells(e,:));if isempty(ids),continue;end
                rv=values(e,:);rv=rv(isfinite(rv));if isempty(rv),continue;end
                q=P(ids,:);normal=cross(q(2,:)-q(1,:),q(4,:)-q(1,:));
                if norm(normal)<=eps,continue;end
                normal=normal/norm(normal);
                if isForce && numel(rv)>=4
                    % Preserve the four raw nodal actions. Draw only the two
                    % wall-height edge pairs I-L and J-K; drawing the top and
                    % bottom edges falsely makes the diagrams look like slabs.
                    % Geometry order is I,J,K,L; response order is I,J,L,K.
                    edgeIds=[1 4;2 3];valueIds=[1 3;2 4];
                    for edge=1:2
                        a=edgeIds(edge,1);b=edgeIds(edge,2);
                        va=rv(valueIds(edge,1));vb=rv(valueIds(edge,2));
                        qq=[q(a,:);q(b,:);q(b,:)+sf*vb*normal;q(a,:)+sf*va*normal];
                        i0=size(V,1);V=[V;qq];F=[F;i0+[1 2 3];i0+[1 3 4]]; %#ok<AGROW>
                        S=[S;va;vb;vb;va]; %#ok<AGROW>
                    end
                    continue;
                elseif isForce && numel(rv)>=2
                    % The two values are complete wall-end resultants about
                    % the I/J and L/K edge centres, respectively.
                    pStart=(q(1,:)+q(2,:))/2;pEnd=(q(3,:)+q(4,:))/2;
                    vStart=rv(1);vEnd=rv(2);
                    qq=[pStart;pEnd;pEnd+sf*vEnd*normal;pStart+sf*vStart*normal];
                    i0=size(V,1);V=[V;qq];F=[F;i0+[1 2 3];i0+[1 3 4]]; %#ok<AGROW>
                    S=[S;vStart;vEnd;vEnd;vStart]; %#ok<AGROW>
                    continue;
                elseif numel(rv)>=4
                    % OpenSees force order I,J,L,K -> perimeter I,J,K,L.
                    rv=rv([1 2 4 3]);
                elseif numel(rv)==1,rv=repmat(rv,1,4);
                else,rv=repmat(mean(rv,'omitnan'),1,4);end
                for j=1:4
                    j2=mod(j,4)+1;va=rv(j);vb=rv(j2);
                    qq=[q(j,:);q(j2,:);q(j2,:)+sf*vb*normal;q(j,:)+sf*va*normal];
                    i0=size(V,1);V=[V;qq];F=[F;i0+[1 2 3];i0+[1 3 4]]; %#ok<AGROW>
                    S=[S;va;vb;vb;va]; %#ok<AGROW>
                end
            end
        end

        function m=globalComponentMax_(obj)
            c=obj.index_(obj.componentNames_,obj.Opts.component);m=0;
            for k=1:numel(obj.MVLEMResp)
                if ~isfield(obj.MVLEMResp(k),obj.Opts.respType),continue;end
                A=double(obj.MVLEMResp(k).(obj.Opts.respType));
                if any(strcmpi(obj.Opts.respType,{'globalForces','localForces'}))
                    B=abs(A(:,:,c:6:size(A,3)));
                else,B=abs(A(:,:,min(c,size(A,3))));end
                m=max(m,max(B,[],'all','omitnan'));
            end
        end

        function [Pe,Ee]=quadBoundaryNetwork_(obj,P,cells)
            Pe=P;Ee=zeros(0,2);
            for e=1:size(cells,1)
                ids=obj.orderedQuadIds_(P,cells(e,:));if isempty(ids),continue;end
                Ee=[Ee;ids([1 2]);ids([2 3]);ids([3 4]);ids([4 1])]; %#ok<AGROW>
            end
            if ~isempty(Ee)
                Ee=unique(sort(Ee,2),'rows','stable');
                [Pe,Ee]=obj.compactCurveNetwork_(P,Ee);
            end
        end

        function [Pc,Ec]=surfaceCenterlineNetwork_(obj,P,cells)
            Pc=zeros(0,3);Ec=zeros(0,2);
            for e=1:size(cells,1)
                ids=obj.orderedQuadIds_(P,cells(e,:));if isempty(ids),continue;end
                q=P(ids,:);i0=size(Pc,1);
                Pc=[Pc;(q(1,:)+q(2,:))/2;(q(3,:)+q(4,:))/2]; %#ok<AGROW>
                Ec=[Ec;i0+[1 2]]; %#ok<AGROW>
            end
        end

        function [Pc,Ec]=compactCurveNetwork_(~,P,E)
            % Polyscope renders curve-network vertices even when no edge
            % references them. Compacting prevents auxiliary/orphan nodes
            % from appearing as unexplained points in the response view.
            if isempty(E),Pc=zeros(0,3);Ec=zeros(0,2);return;end
            ids=unique(E(:),'stable');map=zeros(size(P,1),1);map(ids)=1:numel(ids);
            Pc=P(ids,:);Ec=reshape(map(E),size(E));
        end

        function ids=mvlemNodeIndices_(~,M,nNode)
            % Display only nodes referenced by MVLEM geometry. Internal or
            % orphan control nodes may remain in the ODB for index stability.
            ids=zeros(0,1);fam=plotter.polyscope.ModelAdapter.families(M);
            names={'MVLEM','MVLEM3D'};
            for k=1:numel(names)
                if ~isfield(fam,names{k}) || ~isfield(fam.(names{k}),'Cells'),continue;end
                C=double(fam.(names{k}).Cells);
                for r=1:size(C,1)
                    row=C(r,:);row=row(isfinite(row));
                    if ~isempty(row) && any(round(row(1))==[2 4]) && numel(row)>round(row(1))
                        row=row(2:round(row(1))+1);
                    end
                    ids=[ids;round(row(:))]; %#ok<AGROW>
                end
            end
            ids=unique(ids(ids>=1 & ids<=nNode),'stable');
            if isempty(ids),ids=(1:nNode).';end
        end

        function [Pe,Ee]=quadMeshEdges_(~,V)
            % Fiber meshes store every physical strip as four consecutive
            % vertices.  Only its four perimeter edges are displayable;
            % triangulation diagonals are deliberately never exposed.
            Pe=V; nQuad=floor(size(V,1)/4); Ee=zeros(4*nQuad,2);
            for q=1:nQuad
                i=4*(q-1)+(1:4);
                Ee(4*(q-1)+(1:4),:)=[i([1 2]);i([2 3]);i([3 4]);i([4 1])];
            end
        end

        function L=physicalModelLength_(~,P)
            P=double(P);P=P(all(isfinite(P),2),:);
            if isempty(P),L=1;return;end
            L=norm(max(P,[],1)-min(P,[],1));
            if ~isfinite(L)||L<=eps,L=1;end
        end

        function [V,F,S]=surfaceContourMesh_(obj,P,cells,values)
            % Duplicate each quad so nodal force values can vary independently
            % on adjacent elements without introducing visible triangle edges.
            V=zeros(0,3);F=zeros(0,3);S=zeros(0,1);
            for e=1:size(cells,1)
                ids=obj.orderedQuadIds_(P,cells(e,:)); if isempty(ids),continue;end
                rv=values(e,:); rv=rv(isfinite(rv));
                if isempty(rv),rv=nan(1,4);
                elseif numel(rv)>=4,rv=rv([1 2 4 3]);
                elseif numel(rv)==1,rv=repmat(rv,1,4);
                else,rv=repmat(mean(rv,'omitnan'),1,4);end
                i0=size(V,1);V=[V;P(ids,:)]; %#ok<AGROW>
                F=[F;i0+[1 2 3];i0+[1 3 4]]; %#ok<AGROW>
                S=[S;rv(:)]; %#ok<AGROW>
            end
        end

        function ids=orderedQuadIds_(~,P,row)
            row=double(row);row=row(isfinite(row));ids=[];
            if numel(row)>=5&&round(row(1))==4,ids=round(row(2:5));
            elseif numel(row)>=4,ids=round(row(1:4));end
            if numel(ids)~=4||any(ids<1|ids>size(P,1)),ids=[];return;end
            q=P(ids,:);l0=sum(vecnorm(q([2 3 4 1],:)-q,2,2));
            alt=ids([1 2 4 3]);qa=P(alt,:);l1=sum(vecnorm(qa([2 3 4 1],:)-qa,2,2));
            if l1+eps(max(l0,l1))<l0,ids=alt;end
        end

        function [V,F,S] = fiberSurfaceMesh_(obj,P,cells,values,fiberCounts)
            V=zeros(0,3); F=zeros(0,3); S=zeros(0,1);
            cells=double(cells);
            gap=max(0,min(0.45,double(obj.Opts.fibers.gapFraction)));
            fiberWidths=obj.Opts.fibers.fiberWidths;
            for e=1:size(cells,1)
                nFiber=fiberCounts(e); if nFiber<1, continue; end
                row=cells(e,:); row=row(isfinite(row));
                if numel(row)>=5 && round(row(1))==4, ids=round(row(2:5));
                elseif numel(row)>=4, ids=round(row(1:4));
                else, continue; end
                if any(ids<1 | ids>size(P,1)), continue; end

                % Older ODB files contain MVLEM_3D external-node order
                % I,J,L,K. Choose the shorter closed boundary so those files
                % are displayed as I,J,K,L without requiring regeneration.
                q0=P(ids,:);
                len0=sum(vecnorm(q0([2 3 4 1],:)-q0,2,2));
                alt=ids([1 2 4 3]); q1=P(alt,:);
                len1=sum(vecnorm(q1([2 3 4 1],:)-q1,2,2));
                if len1+eps(max(len0,len1))<len0, ids=alt; end

                if ~isempty(fiberWidths)
                    if iscell(fiberWidths), fw=double(fiberWidths{min(e,numel(fiberWidths))}(:).');
                    elseif isvector(fiberWidths), fw=double(fiberWidths(:).');
                    else, fw=double(fiberWidths(min(e,size(fiberWidths,1)),1:nFiber)); end
                    if numel(fw)~=nFiber || any(~isfinite(fw)) || any(fw<=0)
                        error('plotter:polyscope:plotMVLEMResponse:InvalidFiberWidths', ...
                            'opts.fibers.fiberWidths must contain %d positive widths per element.',nFiber);
                    end
                    bounds=[0,cumsum(fw)]; bounds=bounds/bounds(end);
                else
                    bounds=linspace(0,1,nFiber+1);
                end

                % Perimeter order is lower-left, lower-right, upper-right,
                % upper-left. Interpolate matching points on both edges.
                p1=P(ids(1),:); p2=P(ids(2),:);
                p3=P(ids(3),:); p4=P(ids(4),:);
                if gap<=eps && ~obj.Opts.fibers.showEdges
                    % One connected grid per element. Adjacent strips share
                    % their boundary vertices, preventing background-colored
                    % raster cracks when line overlays are disabled.
                    lower=(1-bounds(:))*p1+bounds(:)*p2;
                    upper=(1-bounds(:))*p4+bounds(:)*p3;
                    i0=size(V,1);V=[V;lower;upper]; %#ok<AGROW>
                    nB=nFiber+1;
                    for f=1:nFiber
                        a=i0+f;b=i0+f+1;c=i0+nB+f+1;d=i0+nB+f;
                        F=[F;a b c;a c d]; %#ok<AGROW>
                        S=[S;values(e,f);values(e,f)]; %#ok<AGROW>
                    end
                    continue;
                end
                for f=1:nFiber
                    halfGap=(bounds(f+1)-bounds(f))*gap/2;
                    a=bounds(f)+halfGap; b=bounds(f+1)-halfGap;
                    q=[(1-a)*p1+a*p2; (1-b)*p1+b*p2; ...
                       (1-b)*p4+b*p3; (1-a)*p4+a*p3];
                    i0=size(V,1); V=[V;q]; %#ok<AGROW>
                    F=[F;i0+[1 2 3];i0+[1 3 4]]; %#ok<AGROW>
                    S=[S;values(e,f);values(e,f)]; %#ok<AGROW>
                end
            end
        end

        function args = scalarArgs_(obj, vals)
            if strcmpi(char(string(obj.Opts.color.climMode)),'global')
                c=obj.index_(obj.componentNames_,obj.Opts.component);
                f=[];
                for k=1:numel(obj.MVLEMResp)
                    if ~isfield(obj.MVLEMResp(k),obj.Opts.respType),continue;end
                    A=double(obj.MVLEMResp(k).(obj.Opts.respType));
                    if obj.isFiberResponse_() && obj.Opts.fibers.show
                        f=[f;A(isfinite(A))]; %#ok<AGROW>
                    else
                        if any(strcmpi(obj.Opts.respType,{'globalForces','localForces'}))
                            B=A(:,:,c:6:size(A,3));
                        else,B=A(:,:,min(c,size(A,3)));end
                        f=[f;B(isfinite(B))]; %#ok<AGROW>
                    end
                end
            else
                f = vals(isfinite(vals));
            end
            if isempty(f)
                clim = [-1 1];
            else
                clim = [min(f), max(f)];
                if clim(1) == clim(2)
                    % One element or a uniform field must not be mapped to
                    % the neutral midpoint of a diverging colour map.
                    a=abs(clim(1));
                    if a<=eps,a=1;end
                    clim=[-a a];
                end
            end
            args = {'enabled', true, 'cmap', char(string(obj.Opts.polyscope.scalarColorMap)), ...
                    'map_range', clim};
            if obj.getOptField_(obj.Opts.polyscope,'onscreenColorbar',false)
                cb=obj.colorbarArgs_();
                if isempty(char(string(obj.getOptField_(obj.Opts.polyscope,'colorbarTitle',''))))
                    cb=[cb,{'onscreen_colorbar_title',obj.quantityName_()}];
                end
                if ~isempty(cb),args=[args,cb];end
            end
        end

        function names = collectResponses_(obj)
            skip = {'eleTags','time','odbTag','eleType','nodeTags'};
            names = {};
            for k=1:numel(obj.MVLEMResp)
                fn = fieldnames(obj.MVLEMResp(k));
                for j=1:numel(fn)
                    if ~any(strcmp(fn{j},skip)) && isnumeric(obj.MVLEMResp(k).(fn{j})) && ~isempty(obj.MVLEMResp(k).(fn{j}))
                        names{end+1}=fn{j}; %#ok<AGROW>
                    end
                end
            end
            names = unique(names,'stable');
        end

        function names = components_(obj)
            A = obj.firstArray_(); n = max(1, size(A,3));
            switch lower(obj.Opts.respType)
                case 'shearforcedeformation', base={'deformation','force'};
                case {'globalforces','localforces'}
                    n=min(6,n);
                    base={'Fx','Fy','Fz','Mx','My','Mz'};
                case 'curvature', base={'value'};
                otherwise, base=arrayfun(@(x)sprintf('fiber%d',x),1:n,'UniformOutput',false);
            end
            if numel(base)<n, base=[base arrayfun(@(x)sprintf('component%d',x),numel(base)+1:n,'UniformOutput',false)]; end
            names=base(1:n);
        end

        function A = firstArray_(obj)
            A=[]; for k=1:numel(obj.MVLEMResp), if isfield(obj.MVLEMResp(k),obj.Opts.respType), A=obj.MVLEMResp(k).(obj.Opts.respType); if ~isempty(A), return; end, end, end
        end
        function counts = segmentCounts_(obj)
            counts=zeros(1,numel(obj.MVLEMResp));
            for k=1:numel(counts)
                if isfield(obj.MVLEMResp(k),obj.Opts.respType)
                    counts(k)=size(obj.MVLEMResp(k).(obj.Opts.respType),1);
                end
            end
            counts(counts<1)=1;
        end
        function n = responseStepCount_(obj), n=max(1,sum(obj.segCounts_)); end
        function [R, localStep, seg] = respAtStep_(obj)
            offsets=[0 cumsum(obj.segCounts_)];
            seg=find(obj.currentStep_<offsets(2:end),1);
            if isempty(seg),seg=numel(obj.MVLEMResp);end
            localStep=obj.currentStep_-offsets(seg)+1;
            R=obj.MVLEMResp(seg);
        end
        function M = modelAtStep_(obj)
            if isempty(obj.segCounts_), seg=1; else, [~,~,seg]=obj.respAtStep_(); end
            M=obj.ModelInfo(min(numel(obj.ModelInfo),seg));
        end
        function tags = familyTags_(~,S,n), if isfield(S,'Tags')&&~isempty(S.Tags), tags=double(S.Tags(:)); else, tags=(1:n)'; end, end
        function v = matchValues_(~,ft,rt,rv), v=nan(numel(ft),1); [tf,ix]=ismember(ft,rt); v(tf)=rv(ix(tf)); end
        function v = matchLocationValues_(~,ft,rt,rv), v=nan(numel(ft),size(rv,2)); [tf,ix]=ismember(ft,rt); v(tf,:)=rv(ix(tf),:); end
        function v = finiteValues_(~,v), v(~isfinite(v))=0; end
        function q = quantityName_(obj), q=[char(obj.Opts.respType) ' - ' char(obj.Opts.component)]; end
        function tf = isFiberResponse_(obj), tf=startsWith(lower(char(obj.Opts.respType)),'fiber'); end
        function values=surfaceForceResultantsAtStep_(obj,P,cells,familyTags)
            [R,localStep]=obj.respAtStep_();
            A=double(R.(obj.Opts.respType));
            B=reshape(A(min(localStep,size(A,1)),:,:),size(A,2),[]);
            values=nan(numel(familyTags),2);
            [tf,ix]=ismember(familyTags,double(R.eleTags(:)));
            c=obj.index_(obj.componentNames_,obj.Opts.component);
            for e=find(tf(:)).'
                if size(B,2)<24,continue;end
                ids=obj.orderedQuadIds_(P,cells(e,:));if isempty(ids),continue;end
                q=P(ids,:);row=B(ix(e),1:24);
                W=obj.combineWallEndActions_(q,row,strcmpi(obj.Opts.respType,'localForces'));
                values(e,:)=W(:,c).';
            end
        end

        function W=combineWallEndActions_(obj,q,row,isLocal)
            % q geometry order: I,J,K,L. OpenSees response order: I,J,L,K.
            X=reshape(double(row(1:24)),6,4).';
            qr=q([1 2 4 3],:);
            if isLocal
                ex=q(2,:)-q(1,:);ex=ex/max(norm(ex),eps);
                ey=q(3,:)-q(1,:);ey=ey/max(norm(ey),eps);
                ez=cross(ex,ey);ez=ez/max(norm(ez),eps);
                qr=[qr*ex(:),qr*ey(:),qr*ez(:)];
            end
            W=zeros(2,6);pairs={[1 2],[3 4]};
            for endIdx=1:2
                ii=pairs{endIdx};rc=mean(qr(ii,:),1);
                force=sum(X(ii,1:3),1);
                moment=zeros(1,3);
                for a=ii
                    moment=moment+X(a,4:6)+cross(qr(a,:)-rc,X(a,1:3));
                end
                W(endIdx,:)=[force,moment];
            end
            if obj.Opts.forceResultantFlipEnd,W(2,:)=-W(2,:);end
        end
        function values=applyLocalForceEndSigns_(obj,values)
            if ~any(strcmpi(obj.Opts.respType,{'globalForces','localForces'})) || ...
                    ~obj.Opts.forceResultantFlipEnd || isempty(values)
                return;
            end
            nLocation=size(values,2);
            if nLocation==2
                values(:,2)=-values(:,2);
            elseif nLocation>=4
                % MVLEM_3D response order is I,J,L,K.  I/J are the start
                % edge and L/K are the end edge in the element formulation.
                values(:,3:4)=-values(:,3:4);
            else
                values(:,end)=-values(:,end);
            end
        end
        function mode=effectiveDisplayMode_(obj)
            if obj.isFiberResponse_(),mode='fibers';return;end
            requested=lower(char(string(obj.Opts.responseDisplay)));
            if ~strcmp(requested,'auto'),mode=requested;return;end
            switch lower(char(obj.Opts.respType))
                case {'globalforces','localforces'}
                    mode='diagram';
                case 'shearforcedeformation'
                    if strcmpi(char(string(obj.Opts.component)),'force')
                        mode='diagram';
                    else
                        mode='contour';
                    end
                case 'curvature'
                    mode='contour';
                otherwise
                    mode='contour';
            end
        end
        function s = pick_(obj,list,want), if strcmpi(string(want),'auto'), s=list{1}; else, s=list{obj.index_(list,want)}; end, end
        function i = index_(~,list,want), i=find(strcmpi(list,char(string(want))),1); if isempty(i),i=1;end, end
        function step = resolveStep_(obj,arg)
            if isnumeric(arg), step=round(double(arg(1))); else
                mode=lower(char(string(arg))); c=obj.index_(obj.components_(),obj.Opts.component); B=[];
                for k=1:numel(obj.MVLEMResp)
                    if ~isfield(obj.MVLEMResp(k),obj.Opts.respType), continue; end
                    A=double(obj.MVLEMResp(k).(obj.Opts.respType));
                    if any(strcmpi(obj.Opts.respType,{'globalForces','localForces'}))
                        Ak=A(:,:,c:6:size(A,3));Ak=reshape(Ak,size(A,1),[]);
                    else,Ak=reshape(A(:,:,min(c,size(A,3))),size(A,1),[]);end
                    B=[B; Ak]; %#ok<AGROW>
                end
                switch mode
                    case 'absmin', score=min(abs(B),[],2,'omitnan');[~,i]=min(score);
                    case 'max', score=max(B,[],2,'omitnan');[~,i]=max(score);
                    case 'min', score=min(B,[],2,'omitnan');[~,i]=min(score);
                    otherwise, score=max(abs(B),[],2,'omitnan');[~,i]=max(score);
                end
                step=i-1;
            end
            step=max(0,min(obj.nSteps_-1,step));
        end
        function advanceAnimation_(obj)
            if ~isfield(obj.gui_,'playing')||~obj.gui_.playing||obj.nSteps_<2, return; end
            if obj.lastTick_==uint64(0), obj.lastTick_=tic; return; end
            if toc(obj.lastTick_) < 1/max(1,obj.gui_.fps), return; end
            obj.lastTick_=tic;
            obj.advanceAnimationStep_();
        end
        function advanceAnimationStep_(obj)
            stride=max(1,round(double(obj.gui_.frameStride)));
            next=obj.currentStep_+obj.animDir_*stride;
            stopped=false;
            if next>=obj.nSteps_||next<0
                if obj.gui_.pingpong
                    obj.animDir_=-obj.animDir_;
                    if obj.animDir_<0,next=obj.nSteps_-1;else,next=0;end
                elseif obj.gui_.loop,next=mod(next,obj.nSteps_);
                else
                    obj.gui_.playing=false;
                    obj.Opts.animation.play=false;
                    obj.configureAnimationRenderLoop_(false,obj.gui_.fps);
                    stopped=true;
                    next=max(0,min(obj.nSteps_-1,next));
                end
            end
            obj.setStep(next,stopped);
        end
    end
end
