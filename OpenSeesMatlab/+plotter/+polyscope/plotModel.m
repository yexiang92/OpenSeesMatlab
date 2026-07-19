classdef plotModel < plotter.polyscope.ViewerBase
    %PLOTMODEL Polyscope-based visualisation of an OpenSees model.
    %
    %   Example
    %   -------
    %       viewer = plotter.polyscope.plotModel(modelInfo);
    %       viewer.show();
    %
    %   Customise with an opts struct (start from
    %   plotter.polyscope.Options.defaultModelOptions()).

    properties (Access = private)
        initialOpts_ struct
    end

    methods
        function obj = plotModel(modelInfo, opts)
            if nargin < 1 || isempty(modelInfo)
                error('plotter:polyscope:plotModel:InvalidInput', ...
                    'modelInfo is required.');
            end
            if nargin < 2 || isempty(opts)
                opts = struct();
            end
            obj = obj@plotter.polyscope.ViewerBase();
            obj.ModelInfo = modelInfo;
            obj.Opts = plotter.polyscope.Options.mergeOpts( ...
                plotter.polyscope.Options.defaultModelOptions(), opts);
            obj.initialOpts_ = obj.Opts;
            obj.App = plotter.polyscope.PolyscopeApp();
            obj.L_ = plotter.polyscope.ModelAdapter.modelLength(modelInfo);
            obj.P0_ = plotter.polyscope.ModelAdapter.nodeCoords(modelInfo);
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
            P = plotter.polyscope.ModelAdapter.nodeCoords(obj.ModelInfo);
            is2D = obj.is2DModel_();
            if is2D && strcmpi(char(string(obj.Opts.general.view)), '3D')
                obj.Opts.general.view = 'XY';
            end
            obj.App.init(obj.Opts.polyscope.backend, obj.Opts, is2D);
            obj.setupWindowIcon_();
            try
                gpMode = char(string(obj.getOptField_(obj.Opts.polyscope, 'groundPlaneMode', 'shadow_only')));
                obj.App.polyscopeHandle().set_ground_plane_mode(gpMode);
            catch
            end
            obj.clear_();

            obj.handles_ = struct();

            obj.registerNodes_(P);
            obj.registerFixedNodes_();
            if obj.hasElementClasses_()
                obj.registerElementClasses_(P);
            else
                obj.registerLineFamilies_(P);
                obj.registerSurfaceFamilies_();
            end
            obj.registerMPConstraints_(P);
            obj.registerLocalAxes_();
            obj.registerLoads_(P);
            obj.registerOutline_(P);
            if ~obj.isOverlayScreenAxes_()
                obj.registerScreenAxes3D_();
            end
            obj.registerSlicePlanes_();
            obj.applySliceCullWholeElements_();

            if isfield(obj, 'gui_') && isstruct(obj.gui_)
                obj.gui_.modelStats = obj.computeModelStats_();
            end

            obj.built_ = true;
            if firstBuild
                obj.setDefaultCamera_();
            end
            obj.updateScreenAxes3D_();
        end

        function guiCallback_(obj)
            GB = plotter.polyscope.GuiBuilder;
            obj.pollQueryClick_();
            ws = obj.safeWindowSize_();
            panelW = 340;
            panelH = max(420, ws(2));
            GB.begin('Model controls', [max(0, ws(1) - panelW), 0], [panelW, panelH]);

            GB.header('Model');

            needsRebuild = false;
            sliceDirty = false;

            % View
            if GB.collapsingHeader('View', int32(0))
                views = obj.viewNames_();
                idx = GB.combo('Preset', obj.gui_.viewIdx, views);
                if idx ~= obj.gui_.viewIdx
                    obj.gui_.viewIdx = idx;
                    obj.setCameraView_(views{idx});
                end
                if GB.button('Reset camera')
                    obj.setDefaultCamera_();
                end
                tf = GB.checkbox('View axes', obj.gui_.showScreenAxes);
                if tf ~= obj.gui_.showScreenAxes
                    obj.gui_.showScreenAxes = tf;
                    obj.Opts.polyscope.showScreenAxes = tf;
                    obj.updateScreenAxes3D_();
                end
                tf = GB.checkbox('Model info', obj.gui_.showModelInfo);
                if tf ~= obj.gui_.showModelInfo
                    obj.gui_.showModelInfo = tf;
                    obj.Opts.polyscope.showModelInfo = tf;
                end
                GB.separator();
                GB.subtitle('Element view');
                tf = GB.checkbox('Wireframe only', obj.gui_.wireframeOnly);
                if tf ~= obj.gui_.wireframeOnly
                    obj.gui_.wireframeOnly = tf;
                    obj.Opts.elements.wireframeOnly = tf;
                    obj.applyElementVisibility_();
                    obj.applyStyleColors_();
                end

                tf = GB.checkbox('Face edges', obj.gui_.showWireframeOnFaces);
                if tf ~= obj.gui_.showWireframeOnFaces
                    obj.gui_.showWireframeOnFaces = tf;
                    obj.Opts.elements.showWireframeOnFaces = tf;
                    obj.applyElementVisibility_();
                end
                GB.separator();
            end

            % Style & Colors
            if GB.collapsingHeader('Style && Colors', int32(0))
                styles = {'byFamily', 'solid', 'wireframe'};
                idx = GB.combo('Mode', obj.gui_.styleIdx, styles);
                if idx ~= obj.gui_.styleIdx
                    obj.gui_.styleIdx = idx;
                    obj.Opts.style.mode = styles{idx};
                    obj.applyElementVisibility_();
                    obj.applyStyleColors_();
                end

                if GB.collapsingHeader('Colors', int32(0))
                    [cchg, obj.gui_.colors.line] = GB.colorEdit3('Line', obj.gui_.colors.line);
                    if cchg
                        obj.Opts.style.lineColor = obj.gui_.colors.line;
                        obj.applyStyleColors_();
                    end
                    [cchg, obj.gui_.colors.shell] = GB.colorEdit3('Shell', obj.gui_.colors.shell);
                    if cchg
                        obj.Opts.style.shellColor = obj.gui_.colors.shell;
                        obj.applyStyleColors_();
                    end
                    [cchg, obj.gui_.colors.solid] = GB.colorEdit3('Solid', obj.gui_.colors.solid);
                    if cchg
                        obj.Opts.style.solidColor = obj.gui_.colors.solid;
                        obj.applyStyleColors_();
                    end
                    [cchg, obj.gui_.colors.wireframe] = GB.colorEdit3('Wireframe', obj.gui_.colors.wireframe);
                    if cchg
                        obj.Opts.style.wireframeColor = obj.gui_.colors.wireframe;
                        obj.applyStyleColors_();
                    end
                    [cchg, obj.gui_.colors.node] = GB.colorEdit3('Node', obj.gui_.colors.node);
                    if cchg
                        obj.Opts.nodes.color = obj.gui_.colors.node;
                        obj.applyStyleColors_();
                    end
                    [cchg, obj.gui_.colors.fixed] = GB.colorEdit3('Fixed', obj.gui_.colors.fixed);
                    if cchg
                        obj.Opts.fixed.color = obj.gui_.colors.fixed;
                        obj.applyStyleColors_();
                    end
                    [cchg, obj.gui_.colors.mp] = GB.colorEdit3('MP', obj.gui_.colors.mp);
                    if cchg
                        obj.Opts.mpConstraint.color = obj.gui_.colors.mp;
                        obj.applyStyleColors_();
                    end
                    [cchg, obj.gui_.colors.outline] = GB.colorEdit3('Outline', obj.gui_.colors.outline);
                    if cchg
                        obj.Opts.outline.color = obj.gui_.colors.outline;
                        obj.applyStyleColors_();
                    end
                    [cchg, obj.gui_.colors.loadNode] = GB.colorEdit3('Nodal load', obj.gui_.colors.loadNode);
                    if cchg
                        obj.Opts.loads.nodalColor = obj.gui_.colors.loadNode;
                        obj.updateLoads_();
                    end
                    [cchg, obj.gui_.colors.loadElement] = GB.colorEdit3('Element load', obj.gui_.colors.loadElement);
                    if cchg
                        obj.Opts.loads.elementColor = obj.gui_.colors.loadElement;
                        obj.updateLoads_();
                    end
                    if isfield(obj.gui_, 'classNames') && ~isempty(obj.gui_.classNames)
                        GB.separator();
                        for ic = 1:numel(obj.gui_.classNames)
                            cname = obj.gui_.classNames{ic};
                            [cchg, obj.gui_.colors.class.(cname)] = GB.colorEdit3(cname, obj.gui_.colors.class.(cname));
                            if cchg, obj.applyStyleColors_(); end
                        end
                    end
                end
                GB.separator();
            end

            % Display toggles
            if GB.collapsingHeader('Display', int32(0))
                GB.subtitle('Nodes');
                tf = GB.checkbox('Nodes', obj.gui_.showNodes);
                if tf ~= obj.gui_.showNodes
                    obj.gui_.showNodes = tf;
                    obj.Opts.nodes.show = tf;
                    obj.setHandleEnabled_('Nodes', tf);
                end

                tf = GB.checkbox('Fixed nodes', obj.gui_.showFixed);
                if tf ~= obj.gui_.showFixed
                    obj.gui_.showFixed = tf;
                    obj.Opts.fixed.show = tf;
                    obj.setHandleEnabled_('Fixed', tf);
                end

                tf = GB.checkbox('MP constraints', obj.gui_.showMP);
                if tf ~= obj.gui_.showMP
                    obj.gui_.showMP = tf;
                    obj.Opts.mpConstraint.show = tf;
                    obj.setHandleEnabled_('MPConstraint', tf);
                end

                tf = GB.checkbox('Outline', obj.gui_.showOutline);
                if tf ~= obj.gui_.showOutline
                    obj.gui_.showOutline = tf;
                    obj.Opts.outline.show = tf;
                    obj.setHandleEnabled_('Outline', tf);
                end

                if isfield(obj.gui_, 'classNames') && ~isempty(obj.gui_.classNames)
                    GB.subtitle('Element classes');
                else
                    GB.subtitle('Element families');
                end
                if isfield(obj.gui_, 'classNames') && ~isempty(obj.gui_.classNames)
                    for ie = 1:numel(obj.gui_.classNames)
                        cname = obj.gui_.classNames{ie};
                        tf = GB.checkbox(cname, obj.gui_.classShow.(cname));
                        if tf ~= obj.gui_.classShow.(cname)
                            obj.gui_.classShow.(cname) = tf;
                            obj.applyElementVisibility_();
                        end
                    end
                else
                    elemNames = {'Beam', 'Truss', 'Link', 'Plane', 'Shell', 'Solid', 'Contact'};
                    elemFields = {'showBeam', 'showTruss', 'showLink', 'showPlane', ...
                                  'showShell', 'showSolid', 'showContact'};
                    guiFields = {'showBeam', 'showTruss', 'showLink', 'showPlane', ...
                                 'showShell', 'showSolid', 'showContact'};
                    familyDirty = false;
                    for ie = 1:numel(elemNames)
                        tf = GB.checkbox(elemNames{ie}, obj.gui_.(guiFields{ie}));
                        if tf ~= obj.gui_.(guiFields{ie})
                            obj.gui_.(guiFields{ie}) = tf;
                            obj.Opts.elements.(elemFields{ie}) = tf;
                            familyDirty = true;
                        end
                    end
                    if familyDirty
                        obj.applyElementVisibility_();
                    end
                end

                GB.separator();

                GB.subtitle('Axes and loads');
                tf = GB.checkbox('Beam axes', obj.gui_.showBeamAxes);
                if tf ~= obj.gui_.showBeamAxes
                    obj.gui_.showBeamAxes = tf;
                    obj.Opts.localAxes.showBeam = tf;
                    obj.setAxesEnabled_('BeamAxes', tf);
                end

                tf = GB.checkbox('Link axes', obj.gui_.showLinkAxes);
                if tf ~= obj.gui_.showLinkAxes
                    obj.gui_.showLinkAxes = tf;
                    obj.Opts.localAxes.showLink = tf;
                    obj.setAxesEnabled_('LinkAxes', tf);
                end

                tf = GB.checkbox('Nodal loads', obj.gui_.showNodalLoads);
                if tf ~= obj.gui_.showNodalLoads
                    obj.gui_.showNodalLoads = tf;
                    obj.Opts.loads.showNodal = tf;
                    obj.setHandleEnabled_('NodalLoads', tf);
                end

                tf = GB.checkbox('Element loads', obj.gui_.showElementLoads);
                if tf ~= obj.gui_.showElementLoads
                    obj.gui_.showElementLoads = tf;
                    obj.Opts.loads.showElement = tf;
                    obj.setHandleEnabled_('ElementLoads', tf);
                end

                s = GB.sliderFloat('Load scale', obj.gui_.loadScale, 0.1, 10.0);
                if abs(s - obj.gui_.loadScale) > eps
                    obj.gui_.loadScale = s;
                    obj.Opts.loads.scale = s;
                    obj.updateLoads_();
                end

                GB.separator();
            end

            % Slice plane
            if obj.drawSlicePlaneGui_()
                sliceDirty = true;
            end

            % Query
            if GB.collapsingHeader('Query', int32(0))
                tf = GB.checkbox('Enable query', obj.gui_.queryEnabled);
                if tf ~= obj.gui_.queryEnabled
                    obj.gui_.queryEnabled = tf;
                    obj.setDefaultMouseInteraction_(true);
                    if tf
                        obj.gui_.queryText = 'Click a node or element in the scene.';
                    else
                        obj.clearSelection_();
                        obj.gui_.queryText = 'No selection.';
                        obj.gui_.queryPopupOpen = false;
                    end
                end
                if obj.gui_.queryEnabled
                    if GB.button('Show result')
                        obj.gui_.queryPopupOpen = true;
                    end
                    GB.labelDisabled('Click a node or element in the scene.');
                    if GB.button('Clear selection')
                        obj.clearSelection_();
                        obj.gui_.queryText = 'Click a node or element in the scene.';
                        obj.gui_.queryPopupOpen = false;
                    end
                else
                    GB.labelDisabled('Enable query and select a model item.');
                end
                GB.separator();
            end



            % Appearance
            if GB.collapsingHeader('Appearance', int32(0))
                r = GB.sliderFloat('Node radius', obj.gui_.nodeRadius, 0.0001, 0.012);
                if abs(r - obj.gui_.nodeRadius) > eps
                    obj.gui_.nodeRadius = r;
                    obj.Opts.polyscope.nodeRadius = r;
                    obj.applyNodeRadius_();
                end

                r = GB.sliderFloat('Edge radius', obj.gui_.edgeRadius, 0.0001, 0.006);
                if abs(r - obj.gui_.edgeRadius) > eps
                    obj.gui_.edgeRadius = r;
                    obj.Opts.polyscope.edgeRadius = r;
                    obj.applyEdgeRadius_();
                end

                r = GB.sliderFloat('Vector radius', obj.gui_.vectorRadius, 0.0001, 0.006);
                if abs(r - obj.gui_.vectorRadius) > eps
                    obj.gui_.vectorRadius = r;
                    obj.Opts.polyscope.vectorRadius = r;
                    obj.applyVectorRadius_();
                end

                a = GB.sliderFloat('Surface alpha', obj.gui_.surfaceAlpha, 0.0, 1.0);
                if abs(a - obj.gui_.surfaceAlpha) > eps
                    obj.gui_.surfaceAlpha = a;
                    obj.Opts.elements.surfaceAlpha = a;
                    obj.applySurfaceAlpha_();
                end

                materials = {'flat', 'wax', 'ceramic', 'candy'};
                matIdx = find(strcmpi(materials, obj.gui_.surfaceMaterial), 1);
                if isempty(matIdx), matIdx = 1; end
                matIdxNew = GB.combo('Surface material', matIdx, materials);
                if matIdxNew ~= matIdx
                    obj.gui_.surfaceMaterial = materials{matIdxNew};
                    obj.Opts.polyscope.surfaceMaterial = materials{matIdxNew};
                    obj.applySurfaceMaterial_();
                end

                tf = GB.checkbox('Smooth shade', obj.gui_.surfaceSmoothShade);
                if tf ~= obj.gui_.surfaceSmoothShade
                    obj.gui_.surfaceSmoothShade = tf;
                    obj.Opts.polyscope.surfaceSmoothShade = tf;
                    obj.applySurfaceSmoothShade_();
                end

                groundModes = {'shadow_only', 'tile', 'none'};
                gpIdx = find(strcmpi(groundModes, obj.gui_.groundPlaneMode), 1);
                if isempty(gpIdx), gpIdx = 1; end
                gpIdxNew = GB.combo('Ground plane', gpIdx, groundModes);
                if gpIdxNew ~= gpIdx
                    obj.gui_.groundPlaneMode = groundModes{gpIdxNew};
                    obj.Opts.polyscope.groundPlaneMode = groundModes{gpIdxNew};
                    try
                        obj.App.polyscopeHandle().set_ground_plane_mode(obj.gui_.groundPlaneMode);
                    catch
                    end
                end

                titleStr = GB.inputText('Title', obj.gui_.title);
                if ~strcmp(titleStr, obj.gui_.title)
                    obj.gui_.title = titleStr;
                    obj.Opts.general.title = titleStr;
                    displayTitle = 'OpenSeesMatlab - by Yexiang Yan';
                    if ~isempty(strtrim(titleStr)) && ~strcmpi(strtrim(titleStr), 'auto')
                        displayTitle = ['OpenSeesMatlab | ' titleStr ' - by Yexiang Yan'];
                    end
                    obj.App.polyscopeHandle().set_program_name(displayTitle);
                end
                GB.separator();
            end

            % Render quality
            if GB.collapsingHeader('Render quality', int32(0))
                obj.drawSsaaGui_();
                GB.separator();
            end

            % Actions
            if GB.button('Redraw')
                try
                    obj.App.polyscopeHandle().request_redraw();
                catch
                end
            end
            GB.sameLine();
            if GB.button('Reset')
                obj.setDefaultMouseInteraction_(true);
                obj.Opts = obj.initialOpts_;
                obj.initGuiState_();
                obj.setDefaultCamera_();
                needsRebuild = true;
            end
            GB.sameLine();
            if GB.button('Help')
                obj.gui_.showHelp = ~obj.gui_.showHelp;
            end

            GB.finish();

            if obj.gui_.showHelp
                GB.begin('Help', [20, 20], [420, 480]);
                GB.label(obj.Opts.help);
                GB.finish();
            end

            obj.drawQueryPopup_();
            obj.drawScreenAxesOverlay_();
            obj.drawModelInfoWindow_();
            obj.updateScreenAxes3D_();

            if sliceDirty
                obj.applySlicePlane_();
            end

            if needsRebuild
                obj.build();
            end
        end

    end

    methods (Access = protected)
        function initGuiState_(obj)
            initGuiState_@plotter.polyscope.ViewerBase(obj);
            styles = {'byFamily', 'solid', 'wireframe'};
            obj.gui_.styleIdx = find(strcmpi(styles, char(string(obj.Opts.style.mode))), 1);
            if isempty(obj.gui_.styleIdx), obj.gui_.styleIdx = 1; end

            obj.gui_.showNodes = obj.Opts.nodes.show;
            obj.gui_.showFixed = obj.Opts.fixed.show;
            obj.gui_.showMP    = obj.Opts.mpConstraint.show;

            obj.gui_.showBeam   = obj.Opts.elements.showBeam;
            obj.gui_.showTruss  = obj.Opts.elements.showTruss;
            obj.gui_.showLink   = obj.Opts.elements.showLink;
            obj.gui_.showPlane  = obj.Opts.elements.showPlane;
            obj.gui_.showShell  = obj.Opts.elements.showShell;
            obj.gui_.showSolid  = obj.Opts.elements.showSolid;
            obj.gui_.showContact = obj.Opts.elements.showContact;

            obj.gui_.wireframeOnly = obj.Opts.elements.wireframeOnly;
            obj.gui_.showWireframeOnFaces = obj.Opts.elements.showWireframeOnFaces;
            obj.gui_.showOutline = obj.Opts.outline.show;
            obj.gui_.showScreenAxes = obj.getOptField_(obj.Opts.polyscope, 'showScreenAxes', true);
            obj.gui_.showModelInfo = obj.getOptField_(obj.Opts.polyscope, 'showModelInfo', false);
            obj.gui_.showBeamAxes = obj.Opts.localAxes.showBeam;
            obj.gui_.showLinkAxes = obj.Opts.localAxes.showLink;
            obj.gui_.modelStats = obj.computeModelStats_();
            obj.gui_.showNodalLoads = obj.Opts.loads.showNodal;
            obj.gui_.showElementLoads = obj.Opts.loads.showElement;

            obj.gui_.nodeRadius   = obj.Opts.polyscope.nodeRadius;
            obj.gui_.edgeRadius   = obj.Opts.polyscope.edgeRadius;
            obj.gui_.vectorRadius = obj.Opts.polyscope.vectorRadius;
            obj.gui_.surfaceAlpha = obj.Opts.elements.surfaceAlpha;
            obj.gui_.surfaceMaterial = char(string(obj.getOptField_(obj.Opts.polyscope, 'surfaceMaterial', 'flat')));
            obj.gui_.surfaceSmoothShade = obj.getOptField_(obj.Opts.polyscope, 'surfaceSmoothShade', false);
            obj.gui_.groundPlaneMode = char(string(obj.getOptField_(obj.Opts.polyscope, 'groundPlaneMode', 'shadow_only')));
            obj.gui_.loadScale = obj.Opts.loads.scale;

            obj.gui_.colors = struct();
            obj.gui_.colors.line       = plotter.polyscope.utils.colorToRgb(obj.Opts.style.lineColor);
            obj.gui_.colors.shell      = plotter.polyscope.utils.colorToRgb(obj.Opts.style.shellColor);
            obj.gui_.colors.solid      = plotter.polyscope.utils.colorToRgb(obj.Opts.style.solidColor);
            obj.gui_.colors.wireframe  = plotter.polyscope.utils.colorToRgb(obj.Opts.style.wireframeColor);
            obj.gui_.colors.node       = plotter.polyscope.utils.colorToRgb(obj.Opts.nodes.color);
            obj.gui_.colors.fixed      = plotter.polyscope.utils.colorToRgb(obj.Opts.fixed.color);
            obj.gui_.colors.mp         = plotter.polyscope.utils.colorToRgb(obj.Opts.mpConstraint.color);
            obj.gui_.colors.outline    = plotter.polyscope.utils.colorToRgb(obj.Opts.outline.color);
            obj.gui_.colors.loadNode   = plotter.polyscope.utils.colorToRgb(obj.Opts.loads.nodalColor);
            obj.gui_.colors.loadElement = plotter.polyscope.utils.colorToRgb(obj.Opts.loads.elementColor);

            famNames = [plotter.polyscope.ModelAdapter.lineFamilyNames(), ...
                        plotter.polyscope.ModelAdapter.surfaceFamilyNames(), ...
                        plotter.polyscope.ModelAdapter.volumeFamilyNames()];
            for k = 1:numel(famNames)
                name = famNames{k};
                obj.gui_.colors.family.(name) = obj.familyColor_(name, [0.5 0.5 0.5]);
            end

            obj.gui_.classNames = fieldnames(obj.elementClasses_());
            obj.gui_.classShow = struct();
            obj.gui_.colors.class = struct();
            for k = 1:numel(obj.gui_.classNames)
                name = obj.gui_.classNames{k};
                obj.gui_.classShow.(name) = true;
                obj.gui_.colors.class.(name) = obj.classColor_(name, k);
            end

            obj.gui_.title = char(string(obj.Opts.general.title));
            obj.gui_.showHelp = false;
            obj.gui_.queryEnabled = false;
            obj.gui_.queryText = 'No selection.';
            obj.gui_.queryLastMouse = [NaN NaN];
            obj.gui_.queryPopupOpen = false;
            obj.initSliceGuiState_();
        end

    end

    methods (Access = private)
        function registerNodes_(obj, P)
            if isempty(P)
                return;
            end
            name = obj.structName_('Nodes');
            rgb = obj.familyColor_('Node', obj.Opts.nodes.color);
            pc = obj.App.polyscopeHandle().register_point_cloud(name, P);
            pc.set_radius(obj.Opts.polyscope.nodeRadius, true);
            pc.set_color(rgb);
            pc.set_material(obj.Opts.polyscope.lineMaterial);
            pc.set_point_render_mode(obj.Opts.polyscope.pointRenderMode);
            pc.set_enabled(obj.Opts.nodes.show);
            obj.handles_.Nodes = pc;
            tags = plotter.polyscope.ModelAdapter.nodeTags(obj.ModelInfo);
            rawP = plotter.polyscope.ModelAdapter.rawNodeCoords(obj.ModelInfo);
            obj.query_.(obj.structKey_('Nodes')) = struct( ...
                'kind', 'node', 'family', 'Node', 'tags', tags(:), ...
                'coords', P, 'rawCoords', rawP);
        end

        function registerFixedNodes_(obj)
            [Pfixed, fixedTags] = plotter.polyscope.ModelAdapter.fixedNodes(obj.ModelInfo);
            if isempty(Pfixed), return; end
            name = obj.structName_('Fixed');
            rgb = obj.familyColor_('Fixed', obj.Opts.fixed.color);
            pc = obj.App.polyscopeHandle().register_point_cloud(name, Pfixed);
            pc.set_radius(obj.Opts.polyscope.nodeRadius * 1.5, true);
            pc.set_color(rgb);
            pc.set_material(obj.Opts.polyscope.lineMaterial);
            pc.set_point_render_mode(obj.Opts.polyscope.pointRenderMode);
            pc.set_enabled(obj.Opts.fixed.show);
            obj.handles_.Fixed = pc;
            rawFixed = obj.rawCoordsForTags_(fixedTags);
            obj.query_.(obj.structKey_('Fixed')) = struct( ...
                'kind', 'node', 'family', 'Fixed', 'tags', fixedTags(:), ...
                'coords', Pfixed, 'rawCoords', rawFixed);
        end

        function registerElementClasses_(obj, P)
            C = obj.elementClasses_();
            classNames = fieldnames(C);
            wireframeOnly = obj.isWireframeOnly_();
            wireColor = plotter.polyscope.utils.colorToRgb( ...
                obj.Opts.style.wireframeColor);
            wireRadius = obj.wireframeRadius_();

            for k = 1:numel(classNames)
                name = classNames{k};
                S = C.(name);
                if ~isstruct(S) || ~isfield(S, 'Cells') || isempty(S.Cells) || ...
                        ~isfield(S, 'CellTypes') || isempty(S.CellTypes)
                    continue;
                end
                classShow = obj.classVisible_(name);
                cells = double(S.Cells);
                cellTypes = double(S.CellTypes(:));
                tags = obj.classElementTags_(S);
                rgb = obj.classColor_(name, k);

                if obj.isLineClass_(cellTypes)
                    edges = obj.classCellsToEdges_(cells, size(P, 1));
                    if isempty(edges), continue; end
                    cn = obj.App.polyscopeHandle().register_curve_network( ...
                        obj.structName_(name), P, edges);
                    cn.set_color(rgb);
                    cn.set_radius(obj.Opts.polyscope.edgeRadius, true);
                    cn.set_material(obj.Opts.polyscope.lineMaterial);
                    cn.set_transparency(obj.Opts.polyscope.transparency);
                    cn.set_enabled(classShow);
                    obj.handles_.(name) = cn;
                    qInfo = obj.classLineQueryInfo_(name, cells, tags, edges);
                    obj.query_.(obj.structKey_(name)) = qInfo;
                elseif obj.isVolumeClass_(cellTypes)
                    needWire = classShow && (wireframeOnly || obj.Opts.elements.showWireframeOnFaces);
                    try
                        vol = plotter.utils.VTKElementTriangulator.volumize(P, cellTypes, cells);
                        if needWire
                            surfOut = plotter.utils.VTKElementTriangulator.triangulate(P, cellTypes, cells);
                        else
                            surfOut = [];
                        end
                    catch
                        vol = [];
                        surfOut = [];
                    end
                    hasVolume = ~isempty(vol) && isfield(vol, 'Points') && ~isempty(vol.Points) && ...
                                ((isfield(vol, 'Tets') && ~isempty(vol.Tets)) || ...
                                 (isfield(vol, 'Hexes') && ~isempty(vol.Hexes)));
                    if ~hasVolume, continue; end

                    edgePoints = zeros(0, 3);
                    if ~isempty(surfOut) && isfield(surfOut, 'EdgePoints')
                        edgePoints = surfOut.EdgePoints;
                    end
                    hasWire = needWire && ~isempty(edgePoints);
                    meshEnabled = classShow && ~wireframeOnly;
                    wireEnabled = classShow && hasWire;
                    wireRenderColor = wireColor;
                    if wireframeOnly
                        wireRenderColor = rgb;
                    end

                    vm = obj.registerVolumeMesh_(name, vol.Points, vol.Tets, vol.Hexes, rgb, meshEnabled);
                    if isempty(vm), continue; end
                    obj.handles_.(name) = vm;
                    qInfo = obj.classVolumeQueryInfo_(name, cells, cellTypes, tags, vol);
                    obj.query_.(obj.structKey_(name)) = qInfo;

                    if hasWire
                        obj.registerElementWire_([name 'Wire'], edgePoints, wireRenderColor, wireRadius, ...
                            obj.classSurfaceWireQueryInfo_(name, cells, cellTypes, tags, surfOut), wireEnabled);
                    end
                else
                    try
                        out = plotter.utils.VTKElementTriangulator.triangulate(P, cellTypes, cells);
                    catch
                        out = [];
                    end
                    hasMesh = ~isempty(out) && isfield(out, 'Points') && ~isempty(out.Points) && ...
                              isfield(out, 'Triangles') && ~isempty(out.Triangles);
                    if ~hasMesh, continue; end
                    edgePoints = zeros(0, 3);
                    if isfield(out, 'EdgePoints')
                        edgePoints = out.EdgePoints;
                    end
                    hasWire = ~isempty(edgePoints);
                    meshEnabled = classShow && ~wireframeOnly;
                    wireEnabled = classShow && (wireframeOnly || obj.Opts.elements.showWireframeOnFaces) && hasWire;
                    wireRenderColor = wireColor;
                    if wireframeOnly
                        wireRenderColor = rgb;
                    end

                    sm = obj.App.polyscopeHandle().register_surface_mesh( ...
                        obj.structName_(name), out.Points, out.Triangles, ...
                        'back_face_policy', obj.getOptField_(obj.Opts.polyscope, 'backFacePolicy', 'identical'));
                    sm.set_color(rgb);
                    sm.set_material(obj.Opts.polyscope.surfaceMaterial);
                    sm.set_smooth_shade(obj.Opts.polyscope.surfaceSmoothShade);
                    sm.set_transparency(obj.Opts.elements.surfaceAlpha);
                    sm.set_edge_width(0);
                    sm.set_enabled(meshEnabled);
                    obj.handles_.(name) = sm;
                    qInfo = obj.classSurfaceQueryInfo_(name, cells, cellTypes, tags, out);
                    obj.query_.(obj.structKey_(name)) = qInfo;

                    if hasWire
                        obj.registerElementWire_([name 'Wire'], edgePoints, wireRenderColor, wireRadius, ...
                            obj.classSurfaceWireQueryInfo_(name, cells, cellTypes, tags, out), wireEnabled);
                    end
                end
            end
        end

        function registerLineFamilies_(obj, P)
            famNames = plotter.polyscope.ModelAdapter.lineFamilyNames();
            showFlags = [obj.Opts.elements.showBeam, ...
                         obj.Opts.elements.showTruss, ...
                         obj.Opts.elements.showLink, ...
                         obj.Opts.elements.showContact];
            for k = 1:numel(famNames)
                name = famNames{k};
                edges = plotter.polyscope.ModelAdapter.lineEdges(obj.ModelInfo, name);
                if isempty(edges), continue; end
                rgb = obj.getStyleColor_(name, 'line');
                cn = obj.App.polyscopeHandle().register_curve_network( ...
                    obj.structName_(name), P, edges);
                cn.set_color(rgb);
                cn.set_radius(obj.Opts.polyscope.edgeRadius, true);
                cn.set_material(obj.Opts.polyscope.lineMaterial);
                cn.set_transparency(obj.Opts.polyscope.transparency);
                cn.set_enabled(showFlags(k));
                obj.handles_.(name) = cn;
                qInfo = obj.lineQueryInfo_(name, edges);
                obj.query_.(obj.structKey_(name)) = qInfo;
            end
        end

        function registerElementWire_(obj, baseName, edgePoints, wireColor, wireRadius, qInfo, enabled)
            if nargin < 7, enabled = true; end
            if isempty(edgePoints), return; end
            [nodes, edges] = plotter.polyscope.ModelAdapter.edgePointsToCurveNetwork(edgePoints);
            if isempty(nodes) || isempty(edges), return; end

            wireName = obj.structName_(baseName);
            cn = obj.App.polyscopeHandle().register_curve_network(wireName, nodes, edges);
            cn.set_color(wireColor);
            cn.set_radius(wireRadius, true);
            cn.set_material(obj.Opts.polyscope.lineMaterial);
            cn.set_transparency(obj.Opts.polyscope.transparency);
            cn.set_enabled(enabled);
            obj.handles_.(baseName) = cn;
            if nargin >= 6 && ~isempty(qInfo)
                if ~isfield(qInfo, 'edgeToElement') || isempty(qInfo.edgeToElement)
                    qInfo.edgeToElement = (1:size(edges, 1)).';
                end
                obj.query_.(obj.validQueryKey_(wireName)) = qInfo;
            end
        end

        function vm = registerVolumeMesh_(obj, baseName, V, tets, hexes, rgb, enabled)
            vm = [];
            if isempty(V), return; end
            if nargin < 7, enabled = true; end
            ps = obj.App.polyscopeHandle();
            name = obj.structName_(baseName);

            hasTets = ~isempty(tets);
            hasHexes = ~isempty(hexes);
            if hasTets && hasHexes
                vm = ps.register_tet_hex_mesh(name, V, tets, hexes);
            elseif hasTets
                vm = ps.register_tet_mesh(name, V, tets);
            elseif hasHexes
                vm = ps.register_hex_mesh(name, V, hexes);
            else
                return;
            end

            vm.set_color(rgb);
            try
                vm.set_interior_color(rgb);
            catch
            end
            vm.set_material(obj.Opts.polyscope.surfaceMaterial);
            vm.set_transparency(obj.Opts.elements.surfaceAlpha);
            try
                vm.set_edge_color(plotter.polyscope.utils.colorToRgb(obj.Opts.style.wireframeColor));
                vm.set_edge_width(0);
            catch
            end
            vm.set_enabled(enabled);
        end

        function registerSurfaceFamilies_(obj)
            famNames = [plotter.polyscope.ModelAdapter.surfaceFamilyNames(), ...
                        plotter.polyscope.ModelAdapter.volumeFamilyNames()];
            showFlags = [obj.Opts.elements.showPlane, ...
                         obj.Opts.elements.showShell, ...
                         obj.Opts.elements.showSolid];
            wireframeOnly = obj.isWireframeOnly_();
            wireColor = plotter.polyscope.utils.colorToRgb( ...
                obj.Opts.style.wireframeColor);
            wireRadius = obj.wireframeRadius_();

            for k = 1:numel(famNames)
                name = famNames{k};
                needWire = wireframeOnly || obj.Opts.elements.showWireframeOnFaces;
                if strcmpi(name, 'Solid')
                    [Vv, tets, hexes, ~, ~, EP, surfOut] = plotter.polyscope.ModelAdapter.volumeMesh( ...
                        obj.ModelInfo, name, needWire);
                    hasVolume = ~isempty(Vv) && (~isempty(tets) || ~isempty(hexes));
                    hasWire = needWire && ~isempty(EP);
                    if ~hasVolume && ~hasWire, continue; end

                    faceColor = obj.getStyleColor_(name, 'surface');
                    showFlag = showFlags(k);
                    meshEnabled = showFlag && ~wireframeOnly && hasVolume;
                    wireEnabled = showFlag && hasWire;
                    wireRenderColor = wireColor;
                    if wireframeOnly
                        wireRenderColor = faceColor;
                    end

                    if hasVolume
                        vm = obj.registerVolumeMesh_(name, Vv, tets, hexes, faceColor, meshEnabled);
                        if ~isempty(vm)
                            obj.handles_.(name) = vm;
                            obj.query_.(obj.structKey_(name)) = obj.volumeQueryInfo_(name, surfOut);
                        end
                    end

                    if hasWire
                        [nodes, edges] = plotter.polyscope.ModelAdapter.edgePointsToCurveNetwork(EP);
                        if ~isempty(nodes) && ~isempty(edges)
                            wireName = obj.structName_([name 'Wire']);
                            cn = obj.App.polyscopeHandle().register_curve_network( ...
                                wireName, nodes, edges);
                            cn.set_color(wireRenderColor);
                            cn.set_radius(wireRadius, true);
                            cn.set_material(obj.Opts.polyscope.lineMaterial);
                            cn.set_transparency(obj.Opts.polyscope.transparency);
                            cn.set_enabled(wireEnabled);
                            obj.handles_.([name 'Wire']) = cn;
                            obj.query_.(obj.validQueryKey_(wireName)) = obj.surfaceWireQueryInfo_(name, edges, surfOut);
                        end
                    end
                    continue;
                end

                [V, F, ~, EP, out] = plotter.polyscope.ModelAdapter.surfaceMesh( ...
                    obj.ModelInfo, name);
                hasMesh = ~isempty(V) && ~isempty(F);
                hasWire = needWire && ~isempty(EP);
                if ~hasMesh && ~hasWire, continue; end

                faceColor = obj.getStyleColor_(name, 'surface');
                showFlag = showFlags(k);
                meshEnabled = showFlag && ~wireframeOnly && hasMesh;
                wireEnabled = showFlag && hasWire;
                wireRenderColor = wireColor;
                if wireframeOnly
                    wireRenderColor = faceColor;
                end

                if hasMesh
                    sm = obj.App.polyscopeHandle().register_surface_mesh( ...
                        obj.structName_(name), V, F, ...
                        'back_face_policy', obj.getOptField_(obj.Opts.polyscope, 'backFacePolicy', 'identical'));
                    sm.set_color(faceColor);
                    sm.set_material(obj.Opts.polyscope.surfaceMaterial);
                    sm.set_smooth_shade(obj.Opts.polyscope.surfaceSmoothShade);
                    sm.set_transparency(obj.Opts.elements.surfaceAlpha);
                    sm.set_edge_width(0);
                    sm.set_enabled(meshEnabled);
                    obj.handles_.(name) = sm;
                    obj.query_.(obj.structKey_(name)) = obj.surfaceQueryInfo_(name, out);
                end

                if hasWire
                    [nodes, edges] = plotter.polyscope.ModelAdapter.edgePointsToCurveNetwork(EP);
                    if ~isempty(nodes) && ~isempty(edges)
                        wireName = obj.structName_([name 'Wire']);
                        cn = obj.App.polyscopeHandle().register_curve_network( ...
                            wireName, nodes, edges);
                        cn.set_color(wireRenderColor);
                        cn.set_radius(wireRadius, true);
                        cn.set_material(obj.Opts.polyscope.lineMaterial);
                        cn.set_transparency(obj.Opts.polyscope.transparency);
                        cn.set_enabled(wireEnabled);
                        obj.handles_.([name 'Wire']) = cn;
                        obj.query_.(obj.validQueryKey_(wireName)) = obj.surfaceWireQueryInfo_(name, edges, out);
                    end
                end
            end
        end

        function registerMPConstraints_(obj, P)
            edges = plotter.polyscope.ModelAdapter.mpConstraintEdges(obj.ModelInfo);
            if isempty(edges), return; end
            name = obj.structName_('MPConstraint');
            rgb = plotter.polyscope.utils.colorToRgb(obj.Opts.mpConstraint.color);
            cn = obj.App.polyscopeHandle().register_curve_network(name, P, edges);
            cn.set_color(rgb);
            cn.set_radius(obj.Opts.polyscope.edgeRadius * 0.8, true);
            cn.set_material(obj.Opts.polyscope.lineMaterial);
            cn.set_transparency(obj.Opts.polyscope.transparency);
            cn.set_enabled(obj.Opts.mpConstraint.show);
            obj.handles_.MPConstraint = cn;
            obj.query_.(obj.validQueryKey_(name)) = struct( ...
                'kind', 'mp', 'family', 'MPConstraint', 'tags', (1:size(edges, 1)).', ...
                'cells', edges, 'edgeToElement', (1:size(edges, 1)).');
        end

        function registerLocalAxes_(obj)
            fam = plotter.polyscope.ModelAdapter.families(obj.ModelInfo);
            if isempty(fieldnames(fam)), return; end

            axLen = obj.L_ * obj.Opts.localAxes.scale;
            if ~isfinite(axLen) || axLen <= 0
                axLen = obj.Opts.polyscope.vectorLength;
            end

            if isfield(fam, 'Beam')
                obj.registerFrameAxes_(fam.Beam, 'BeamAxes', axLen, obj.Opts.localAxes.showBeam);
            end
            if isfield(fam, 'Link')
                obj.registerFrameAxes_(fam.Link, 'LinkAxes', axLen, obj.Opts.localAxes.showLink);
            end
        end

        function registerFrameAxes_(obj, S, baseName, axLen, enabled)
            if nargin < 5, enabled = true; end
            if ~isstruct(S) || ~isfield(S, 'Midpoints') || isempty(S.Midpoints)
                return;
            end

            O = plotter.polyscope.ModelAdapter.pad3(double(S.Midpoints));
            O = O - plotter.polyscope.ModelAdapter.geometryCenter(obj.ModelInfo);
            axisFields = {'XAxis', 'YAxis', 'ZAxis'};
            suffixes   = {'X', 'Y', 'Z'};
            colors = {obj.Opts.localAxes.axisXColor, ...
                      obj.Opts.localAxes.axisYColor, ...
                      obj.Opts.localAxes.axisZColor};

            for k = 1:3
                f = axisFields{k};
                if ~isfield(S, f) || isempty(S.(f)), continue; end
                V = plotter.polyscope.ModelAdapter.pad3(double(S.(f)));
                n = min(size(O, 1), size(V, 1));
                if n < 1, continue; end
                obj.registerVectorCloud_([baseName suffixes{k}], O(1:n, :), ...
                    V(1:n, :) * axLen, plotter.polyscope.utils.colorToRgb(colors{k}), ...
                    obj.Opts.polyscope.vectorRadius, enabled);
            end
        end

        function registerLoads_(obj, P)
            if ~isfield(obj.ModelInfo, 'Loads') || isempty(obj.ModelInfo.Loads) || isempty(P)
                return;
            end

            L = obj.ModelInfo.Loads;
            minNorm = obj.Opts.loads.minNorm;
            baseLen = obj.getLoadAutoLength_();
            maxMag = obj.computeGlobalMaxMag_(L, P, minNorm);

            obj.registerNodalLoads_(L, P, baseLen, minNorm, maxMag);
            obj.registerBeamLoads_(L, P, baseLen, minNorm, maxMag);
        end

        function registerNodalLoads_(obj, L, P, baseLen, minNorm, maxMag)
            if ~(isfield(L, 'Node') && ...
                 isfield(L.Node, 'PatternNodeTags') && ~isempty(L.Node.PatternNodeTags) && ...
                 isfield(L.Node, 'Values') && ~isempty(L.Node.Values))
                return;
            end

            tags = double(L.Node.PatternNodeTags);
            if size(tags, 2) < 2, return; end
            nodeTags = tags(:, 2);
            idx = obj.nodeTagsToIdx_(nodeTags);
            valid = idx > 0 & idx <= size(P, 1);
            if ~any(valid), return; end

            vals = double(L.Node.Values);
            n = min(size(vals, 1), numel(valid));
            vals = vals(1:n, :);
            idx = idx(1:n);
            valid = valid(1:n);
            idx = idx(valid);
            vals = vals(valid, :);

            V = zeros(size(vals, 1), 3);
            V(:, 1:min(3, size(vals, 2))) = vals(:, 1:min(3, size(vals, 2)));
            mag = sqrt(sum(V.^2, 2));
            keep = mag > minNorm;
            if ~any(keep), return; end

            idx = idx(keep);
            V = V(keep, :);
            mag = mag(keep);
            dirs = V ./ mag;
            if obj.Opts.loads.normalizeLength
                drawLen = repmat(baseLen, size(mag));
            else
                drawLen = baseLen * mag / max(maxMag, minNorm);
            end
            Udraw = dirs .* drawLen;
            Otail = P(idx, :) - Udraw;

            obj.registerVectorCloud_('NodalLoads', Otail, Udraw, ...
                plotter.polyscope.utils.colorToRgb(obj.Opts.loads.nodalColor), ...
                obj.Opts.polyscope.vectorRadius, obj.Opts.loads.showNodal);
        end

        function registerBeamLoads_(obj, L, P, baseLen, minNorm, maxMag)
            if ~(isfield(L, 'Element') && ...
                 isfield(L.Element, 'Beam') && ...
                 isfield(L.Element.Beam, 'PatternElementTags') && ...
                 ~isempty(L.Element.Beam.PatternElementTags) && ...
                 isfield(L.Element.Beam, 'Values') && ~isempty(L.Element.Beam.Values))
                return;
            end

            pairTags = double(L.Element.Beam.PatternElementTags);
            valsAll = double(L.Element.Beam.Values);
            if isvector(pairTags), pairTags = reshape(pairTags, 1, []); end
            if isvector(valsAll), valsAll = reshape(valsAll, 1, []); end
            if size(pairTags, 2) ~= 2, return; end

            nLoad = min(size(pairTags, 1), size(valsAll, 1));
            if nLoad < 1, return; end

            nArrowPerLoad = max(1, round(obj.Opts.loads.nElementArrows));
            allPts = zeros(3 * nLoad * nArrowPerLoad, 3);
            allVec = zeros(3 * nLoad * nArrowPerLoad, 3);
            iArrow = 0;

            for i = 1:nLoad
                eleTag = pairTags(i, 2);
                [comps, xa, xb, isDist, isPoint] = ...
                    obj.extractBeamLoadComponents_(valsAll(i, :), minNorm);
                if ~(isPoint || isDist), continue; end

                [p1, p2, ok] = obj.lookupBeamEndCoords_(eleTag, P);
                if ~ok, continue; end
                dirVec = p2 - p1;
                if norm(dirVec) < minNorm, continue; end

                [ex, ey, ez, okAxes] = obj.lookupBeamLocalAxes_(eleTag);
                if ~okAxes, continue; end
                ex = obj.normalizeRow_(ex);
                ey = obj.normalizeRow_(ey);
                ez = obj.normalizeRow_(ez);

                if isPoint
                    posList = p1 + xa * dirVec;
                else
                    sLoc = linspace(xa, xb, nArrowPerLoad).';
                    posList = p1 + sLoc .* dirVec;
                end

                [allPts, allVec, iArrow] = obj.appendLoadComponent_( ...
                    allPts, allVec, iArrow, posList, ex, comps(1), baseLen, maxMag);
                [allPts, allVec, iArrow] = obj.appendLoadComponent_( ...
                    allPts, allVec, iArrow, posList, ey, comps(2), baseLen, maxMag);
                [allPts, allVec, iArrow] = obj.appendLoadComponent_( ...
                    allPts, allVec, iArrow, posList, ez, comps(3), baseLen, maxMag);
            end

            if iArrow > 0
                obj.registerVectorCloud_('ElementLoads', allPts(1:iArrow, :), ...
                    allVec(1:iArrow, :), ...
                    plotter.polyscope.utils.colorToRgb(obj.Opts.loads.elementColor), ...
                    obj.Opts.polyscope.vectorRadius, obj.Opts.loads.showElement);
            end
        end

        function registerOutline_(obj, P)
            if isempty(P), return; end

            mn = min(P, [], 1, 'omitnan');
            mx = max(P, [], 1, 'omitnan');
            if any(~isfinite(mn)) || any(~isfinite(mx)), return; end

            x1 = mn(1); x2 = mx(1);
            y1 = mn(2); y2 = mx(2);
            z1 = mn(3); z2 = mx(3);
            if abs(z2 - z1) < eps(max(abs([z1 z2 1])))
                V = [x1 y1 z1; x2 y1 z1; x2 y2 z1; x1 y2 z1];
                E = [1 2; 2 3; 3 4; 4 1];
            else
                V = [x1 y1 z1; x2 y1 z1; x2 y2 z1; x1 y2 z1; ...
                     x1 y1 z2; x2 y1 z2; x2 y2 z2; x1 y2 z2];
                E = [1 2; 2 3; 3 4; 4 1; 5 6; 6 7; 7 8; 8 5; ...
                     1 5; 2 6; 3 7; 4 8];
            end

            cn = obj.App.polyscopeHandle().register_curve_network( ...
                obj.structName_('Outline'), V, E);
            cn.set_color(plotter.polyscope.utils.colorToRgb(obj.Opts.outline.color));
            cn.set_radius(obj.Opts.polyscope.edgeRadius * 0.7, true);
            cn.set_material(obj.Opts.polyscope.lineMaterial);
            cn.set_transparency(obj.Opts.polyscope.transparency);
            cn.set_enabled(obj.Opts.outline.show);
            obj.handles_.Outline = cn;
        end

        function registerVectorCloud_(obj, baseName, O, V, rgb, radius, enabled)
            if nargin < 7, enabled = true; end
            if isempty(O) || isempty(V), return; end
            n = min(size(O, 1), size(V, 1));
            if n < 1, return; end
            O = O(1:n, :);
            V = V(1:n, :);
            keep = all(isfinite(O), 2) & all(isfinite(V), 2) & sqrt(sum(V.^2, 2)) > 0;
            if ~any(keep), return; end
            O = O(keep, :);
            V = V(keep, :);

            pc = obj.App.polyscopeHandle().register_point_cloud(obj.structName_(baseName), O);
            pc.set_radius(max(radius * 0.35, 0.0001), true);
            pc.set_color(rgb);
            pc.set_material(obj.Opts.polyscope.lineMaterial);
            pc.set_point_render_mode(obj.Opts.polyscope.pointRenderMode);
            pc.add_vector_quantity('vec', V, ...
                'vectortype', 'ambient', ...
                'length', 1.0, ...
                'length_relative', false, ...
                'radius', radius, ...
                'radius_relative', true, ...
                'color', rgb, ...
                'material', obj.Opts.polyscope.lineMaterial, ...
                'enabled', true);
            pc.set_enabled(enabled);
            obj.handles_.(baseName) = pc;
        end

    end

    methods (Access = private)
        function rgb = familyColor_(obj, familyName, fallback)
            mode = lower(char(string(obj.Opts.style.mode)));
            if ismember(mode, {'solid','mono'})
                rgb = plotter.polyscope.utils.colorToRgb(fallback);
                return;
            end
            if isfield(obj.Opts.style, 'familyColors') && ...
               isfield(obj.Opts.style.familyColors, familyName)
                rgb = plotter.polyscope.utils.colorToRgb( ...
                    obj.Opts.style.familyColors.(familyName));
            else
                rgb = plotter.polyscope.utils.colorToRgb(fallback);
            end
        end

        function rgb = getStyleColor_(obj, familyName, kind)
            mode = char(string(obj.Opts.style.mode));
            if strcmpi(mode, 'wireframe')
                rgb = plotter.polyscope.utils.colorToRgb( ...
                    obj.Opts.style.wireframeColor);
                return;
            end

            if strcmpi(kind, 'surface')
                fallback = obj.Opts.style.shellColor;
                if ismember(lower(familyName), {'solid','unstructured'})
                    fallback = obj.Opts.style.solidColor;
                end
            else
                fallback = obj.Opts.style.lineColor;
            end
            rgb = obj.familyColor_(familyName, fallback);
        end

        function tags = classElementTags_(~, S)
            if isfield(S, 'ElementTags')
                tags = double(S.ElementTags(:));
            elseif isfield(S, 'Tags')
                tags = double(S.Tags(:));
            else
                tags = (1:size(S.Cells, 1)).';
            end
        end

        function tf = isLineClass_(~, cellTypes)
            lineTypes = [3, 4, 21];
            tf = ~isempty(cellTypes) && all(ismember(double(cellTypes(:)).', lineTypes));
        end

        function tf = isVolumeClass_(~, cellTypes)
            volumeTypes = [10, 12, 24, 25, 29];
            tf = ~isempty(cellTypes) && all(ismember(double(cellTypes(:)).', volumeTypes));
        end

        function tf = classVisible_(obj, className)
            tf = true;
            if isfield(obj.gui_, 'classShow') && isfield(obj.gui_.classShow, className)
                tf = logical(obj.gui_.classShow.(className));
            end
        end

        function rgb = classColor_(obj, className, idx)
            if strcmpi(obj.Opts.style.mode, 'solid')
                rgb = plotter.polyscope.utils.colorToRgb(obj.Opts.style.lineColor);
                return;
            end
            palette = [ ...
                0.08 0.23 0.82
                0.55 0.23 0.86
                0.10 0.55 0.36
                0.88 0.45 0.10
                0.73 0.13 0.22
                0.10 0.48 0.70
                0.55 0.45 0.12
                0.38 0.38 0.38];
            if isfield(obj.gui_, 'colors') && isfield(obj.gui_.colors, 'class') && ...
                    isfield(obj.gui_.colors.class, className)
                rgb = obj.gui_.colors.class.(className);
            else
                rgb = palette(mod(idx - 1, size(palette, 1)) + 1, :);
            end
        end

        function coords = rawCoordsForTags_(obj, tags)
            rawP = plotter.polyscope.ModelAdapter.rawNodeCoords(obj.ModelInfo);
            allTags = plotter.polyscope.ModelAdapter.nodeTags(obj.ModelInfo);
            idx = plotter.polyscope.ModelAdapter.tagsToIdx(tags, allTags);
            coords = nan(numel(tags), 3);
            valid = idx > 0 & idx <= size(rawP, 1);
            coords(valid, :) = rawP(idx(valid), :);
        end

        function edges = classCellsToEdges_(obj, cells, nNode)
            n = size(cells, 1);
            segCounts = zeros(n, 1);
            for i = 1:n
                ids = obj.cellNodeIds_(cells(i, :), nNode);
                segCounts(i) = max(0, numel(ids) - 1);
            end
            total = sum(segCounts);
            if total == 0
                edges = zeros(0, 2);
                return;
            end
            edges = zeros(total, 2);
            pos = 0;
            for i = 1:n
                if segCounts(i) == 0, continue; end
                ids = obj.cellNodeIds_(cells(i, :), nNode);
                edges(pos + 1:pos + segCounts(i), :) = [ids(1:end-1).', ids(2:end).'];
                pos = pos + segCounts(i);
            end
        end

        function info = classLineQueryInfo_(obj, className, cells, tags, edges)
            edgeToElement = obj.lineEdgeToElementRows_(cells, size(edges, 1));
            typeNames = repmat(string(className), numel(tags), 1);
            info = struct('kind', 'line', 'family', className, ...
                'tags', tags, 'cells', cells, 'classTags', zeros(0, 1), ...
                'typeNames', typeNames, 'edgeToElement', edgeToElement(:), ...
                'centers', obj.cellCenters_(cells));
        end

        function info = classSurfaceQueryInfo_(obj, className, cells, cellTypes, tags, out)
            triCellIds = zeros(0, 1);
            edgeCellIds = zeros(0, 1);
            if isfield(out, 'TriCellIds')
                triCellIds = double(out.TriCellIds(:));
            end
            if isfield(out, 'EdgeCellIds')
                edgeCellIds = double(out.EdgeCellIds(:));
            end
            typeNames = repmat(string(className), numel(tags), 1);
            info = struct('kind', 'surface', 'family', className, ...
                'tags', tags, 'cells', cells, 'cellTypes', cellTypes, ...
                'classTags', zeros(0, 1), 'typeNames', typeNames, ...
                'triCellIds', triCellIds, 'edgeToElement', edgeCellIds, ...
                'centers', obj.cellCenters_(cells));
        end

        function info = classSurfaceWireQueryInfo_(obj, className, cells, cellTypes, tags, out)
            info = obj.classSurfaceQueryInfo_(className, cells, cellTypes, tags, out);
            info.kind = 'surfaceWire';
            if isfield(out, 'EdgeCellIds')
                info.edgeToElement = double(out.EdgeCellIds(:));
            end
        end

        function info = classVolumeQueryInfo_(obj, className, cells, cellTypes, tags, out)
            volumeCellIds = zeros(0, 1);
            edgeCellIds = zeros(0, 1);
            if isfield(out, 'RegisterCellIds')
                volumeCellIds = double(out.RegisterCellIds(:));
            elseif isfield(out, 'CellIds')
                volumeCellIds = double(out.CellIds(:));
            end
            if isfield(out, 'EdgeCellIds')
                edgeCellIds = double(out.EdgeCellIds(:));
            end
            typeNames = repmat(string(className), numel(tags), 1);
            info = struct('kind', 'volume', 'family', className, ...
                'tags', tags, 'cells', cells, 'cellTypes', cellTypes, ...
                'classTags', zeros(0, 1), 'typeNames', typeNames, ...
                'volumeCellIds', volumeCellIds, 'edgeToElement', edgeCellIds, ...
                'centers', obj.cellCenters_(cells));
        end

        function info = lineQueryInfo_(obj, familyName, edges)
            fam = plotter.polyscope.ModelAdapter.families(obj.ModelInfo);
            tags = zeros(0, 1);
            cells = zeros(0, 0);
            classTags = zeros(0, 1);
            typeNames = strings(0, 1);
            if isfield(fam, familyName) && isstruct(fam.(familyName))
                S = fam.(familyName);
                if isfield(S, 'Tags'), tags = double(S.Tags(:)); end
                if isfield(S, 'Cells'), cells = double(S.Cells); end
                classTags = obj.familyClassTags_(S);
                typeNames = obj.familyTypeNames_(S, classTags);
            end
            edgeToElement = obj.lineEdgeToElementRows_(cells, size(edges, 1));
            info = struct('kind', 'line', 'family', familyName, ...
                'tags', tags, 'cells', cells, 'classTags', classTags, ...
                'typeNames', typeNames, 'edgeToElement', edgeToElement(:), ...
                'centers', obj.cellCenters_(cells));
        end

        function info = surfaceQueryInfo_(obj, familyName, out)
            fam = plotter.polyscope.ModelAdapter.families(obj.ModelInfo);
            tags = zeros(0, 1);
            cells = zeros(0, 0);
            cellTypes = zeros(0, 1);
            classTags = zeros(0, 1);
            typeNames = strings(0, 1);
            triCellIds = zeros(0, 1);
            edgeCellIds = zeros(0, 1);
            computeOut = nargin < 3 || isempty(out);
            if isfield(fam, familyName) && isstruct(fam.(familyName))
                S = fam.(familyName);
                if isfield(S, 'Tags'), tags = double(S.Tags(:)); end
                if isfield(S, 'Cells'), cells = double(S.Cells); end
                if isfield(S, 'CellTypes'), cellTypes = double(S.CellTypes(:)); end
                classTags = obj.familyClassTags_(S);
                typeNames = obj.familyTypeNames_(S, classTags);
                if computeOut && isfield(S, 'CellTypes') && ~isempty(S.CellTypes) && ~isempty(cells)
                    P = plotter.polyscope.ModelAdapter.nodeCoords(obj.ModelInfo);
                    out = plotter.utils.VTKElementTriangulator.triangulate( ...
                        P, double(S.CellTypes), cells);
                end
                if ~isempty(out)
                    if isfield(out, 'TriCellIds')
                        triCellIds = double(out.TriCellIds(:));
                    end
                    if isfield(out, 'EdgeCellIds')
                        edgeCellIds = double(out.EdgeCellIds(:));
                    end
                end
            end
            info = struct('kind', 'surface', 'family', familyName, ...
                'tags', tags, 'cells', cells, 'cellTypes', cellTypes, ...
                'classTags', classTags, 'typeNames', typeNames, ...
                'triCellIds', triCellIds, 'edgeToElement', edgeCellIds, ...
                'centers', obj.cellCenters_(cells));
        end

        function info = surfaceWireQueryInfo_(obj, familyName, edges, out)
            if nargin < 4
                info = obj.surfaceQueryInfo_(familyName);
            else
                info = obj.surfaceQueryInfo_(familyName, out);
            end
            info.kind = 'surfaceWire';
            if ~isfield(info, 'edgeToElement') || isempty(info.edgeToElement)
                info.edgeToElement = (1:size(edges, 1)).';
            end
        end

        function info = volumeQueryInfo_(obj, familyName, out)
            fam = plotter.polyscope.ModelAdapter.families(obj.ModelInfo);
            tags = zeros(0, 1);
            cells = zeros(0, 0);
            cellTypes = zeros(0, 1);
            classTags = zeros(0, 1);
            typeNames = strings(0, 1);
            volumeCellIds = zeros(0, 1);
            computeOut = nargin < 3 || isempty(out);
            if isfield(fam, familyName) && isstruct(fam.(familyName))
                S = fam.(familyName);
                if isfield(S, 'Tags'), tags = double(S.Tags(:)); end
                if isfield(S, 'Cells'), cells = double(S.Cells); end
                if isfield(S, 'CellTypes'), cellTypes = double(S.CellTypes(:)); end
                classTags = obj.familyClassTags_(S);
                typeNames = obj.familyTypeNames_(S, classTags);
                if computeOut && isfield(S, 'CellTypes') && ~isempty(S.CellTypes) && ~isempty(cells)
                    P = plotter.polyscope.ModelAdapter.nodeCoords(obj.ModelInfo);
                    out = plotter.utils.VTKElementTriangulator.volumize( ...
                        P, double(S.CellTypes), cells);
                end
                if ~isempty(out)
                    if isfield(out, 'RegisterCellIds')
                        volumeCellIds = double(out.RegisterCellIds(:));
                    elseif isfield(out, 'CellIds')
                        volumeCellIds = double(out.CellIds(:));
                    end
                end
            end
            info = struct('kind', 'volume', 'family', familyName, ...
                'tags', tags, 'cells', cells, 'cellTypes', cellTypes, ...
                'classTags', classTags, 'typeNames', typeNames, ...
                'volumeCellIds', volumeCellIds, 'centers', obj.cellCenters_(cells));
        end

        function classTags = familyClassTags_(~, S)
            classTags = zeros(0, 1);
            names = {'ClassTags', 'ClassTag', 'classTags', 'classTag'};
            for i = 1:numel(names)
                if isfield(S, names{i}) && ~isempty(S.(names{i}))
                    classTags = double(S.(names{i})(:));
                    return;
                end
            end
        end

        function typeNames = familyTypeNames_(obj, S, classTags)
            typeNames = strings(0, 1);
            if ~isempty(classTags)
                typeNames = strings(numel(classTags), 1);
                for i = 1:numel(classTags)
                    try
                        typeNames(i) = post.utils.OpenSeesTagMaps.getClassName(classTags(i));
                    catch
                        typeNames(i) = "ClassTag_" + string(classTags(i));
                    end
                end
                return;
            end

            names = {'TypeNames', 'ElementTypes', 'ElementType', 'Types', 'Type', ...
                     'ClassNames', 'ClassName', 'Names', 'Name'};
            for i = 1:numel(names)
                if isfield(S, names{i}) && ~isempty(S.(names{i}))
                    typeNames = obj.toStringColumn_(S.(names{i}));
                    return;
                end
            end
        end

        function out = toStringColumn_(~, value)
            if isstring(value)
                out = value(:);
            elseif ischar(value)
                out = string(cellstr(value));
                out = out(:);
            elseif iscell(value)
                out = strings(numel(value), 1);
                for i = 1:numel(value)
                    out(i) = string(value{i});
                end
            elseif isnumeric(value)
                out = string(value(:));
            else
                out = string(value);
                out = out(:);
            end
        end

        function edgeToElement = lineEdgeToElementRows_(obj, cells, nEdge)
            edgeToElement = zeros(nEdge, 1);
            if isempty(cells) || nEdge < 1, return; end
            nNode = size(plotter.polyscope.ModelAdapter.nodeCoords(obj.ModelInfo), 1);
            iEdge = 0;
            for i = 1:size(cells, 1)
                row = double(cells(i, :));
                row = row(isfinite(row));
                if size(cells, 2) > 2
                    n = row(1);
                    if isfinite(n) && n >= 2 && numel(row) >= n + 1
                        ids = row(2:1+n);
                    else
                        ids = row;
                        ids = ids(ids >= 1);
                    end
                else
                    ids = row;
                end
                ids = round(ids(ids >= 1));
                ids = ids(ids >= 1 & ids <= nNode);
                nSeg = max(0, numel(ids) - 1);
                for j = 1:nSeg
                    iEdge = iEdge + 1;
                    if iEdge <= nEdge
                        edgeToElement(iEdge) = i;
                    end
                end
            end
        end

        function C = cellCenters_(obj, cells)
            P = plotter.polyscope.ModelAdapter.nodeCoords(obj.ModelInfo);
            C = nan(size(cells, 1), 3);
            for i = 1:size(cells, 1)
                ids = obj.cellNodeIds_(cells(i, :), size(P, 1));
                if ~isempty(ids)
                    C(i, :) = mean(P(ids, :), 1);
                end
            end
        end

        function updateSelectionInfo_(obj)
            obj.pickAtMouse_();
        end

        function pickAtMouse_(obj)
            try
                mousePos = polyscope.ImGui.GetMousePos();
                if isempty(mousePos) || numel(mousePos) < 2 || any(~isfinite(double(mousePos(1:2))))
                    obj.gui_.queryText = 'Mouse position unavailable.';
                    return;
                end
                obj.gui_.queryLastMouse = double(mousePos(1:2));
                sel = obj.App.polyscopeHandle().pick('screen_coords', obj.gui_.queryLastMouse);
                obj.gui_.queryText = obj.describeSelection_(sel);
                try
                    obj.App.polyscopeHandle().reset_selection();
                catch
                end
                obj.applySelectionHighlight_(sel);
                obj.gui_.queryPopupOpen = true;
            catch ME
                obj.gui_.queryText = sprintf('Pick unavailable:\n%s', ME.message);
                obj.gui_.queryPopupOpen = true;
            end
        end

        function pollQueryClick_(obj)
            if ~isfield(obj.gui_, 'queryEnabled') || ~obj.gui_.queryEnabled
                return;
            end
            try
                io = polyscope.ImGui.GetIO();
                if logical(io.WantCaptureMouse)
                    return;
                end
                if polyscope.ImGui.GetMouseClickedCount(0) > 0
                    obj.pickAtMouse_();
                end
            catch
            end
        end

        function clearSelection_(obj)
            try
                obj.App.polyscopeHandle().reset_selection();
            catch
            end
            obj.clearHighlight_();
        end

        function setDefaultMouseInteraction_(obj, tf)
            try
                obj.App.polyscopeHandle().set_do_default_mouse_interaction(tf);
            catch
            end
        end

        function drawQueryPopup_(obj)
            if ~isfield(obj.gui_, 'queryPopupOpen') || ~obj.gui_.queryPopupOpen
                return;
            end
            try
                GB = plotter.polyscope.GuiBuilder;
                ws = obj.safeWindowSize_();
                w = 460;
                h = 260;
                x = max(20, min(ws(1) - w - 20, 360));
                y = 80;
                GB.begin('Query result', [x, y], [w, h]);
                polyscope.ImGui.TextWrapped(obj.gui_.queryText);
                if GB.button('Close')
                    obj.gui_.queryPopupOpen = false;
                end
                GB.finish();
            catch
                obj.gui_.queryPopupOpen = false;
            end
        end

        function applySelectionHighlight_(obj, sel)
            obj.clearHighlight_();
            if ~isstruct(sel) || ~obj.scalarLogicalField_(sel, 'is_hit')
                return;
            end
            sName = obj.charField_(sel, 'structure_name');
            idx = round(obj.doubleField_(sel, 'local_index'));
            pos = obj.vectorField_(sel, 'position');
            key = obj.validQueryKey_(sName);
            if ~isfield(obj.query_, key) || ~isfinite(idx) || idx < 1
                return;
            end
            info = obj.query_.(key);
            switch info.kind
                case 'node'
                    obj.highlightNode_(info, idx);
                case 'line'
                    eleRow = obj.lookupElementRow_(info, idx, 'edgeToElement', pos);
                    obj.highlightLineElement_(info, eleRow);
                case 'surface'
                    eleRow = obj.lookupElementRow_(info, idx, 'triCellIds', pos);
                    obj.highlightSurfaceElement_(info, eleRow);
                case 'volume'
                    eleRow = obj.lookupElementRow_(info, idx, 'volumeCellIds', pos);
                    obj.highlightSurfaceElement_(info, eleRow);
                case 'surfaceWire'
                    eleRow = obj.lookupElementRow_(info, idx, 'edgeToElement', pos);
                    obj.highlightSurfaceElement_(info, eleRow);
                case 'mp'
                    obj.highlightLineElement_(info, idx);
            end
        end

        function clearHighlight_(obj)
            names = unique([fieldnames(obj.highlight_); ...
                {'QueryHighlightNode'; 'QueryHighlightElement'}], 'stable');
            for i = 1:numel(names)
                sName = obj.structName_(names{i});
                try
                    obj.App.polyscopeHandle().remove_point_cloud(sName);
                catch
                end
                try
                    obj.App.polyscopeHandle().remove_curve_network(sName);
                catch
                end
                try
                    obj.App.polyscopeHandle().remove_surface_mesh(sName);
                catch
                end
                try
                    obj.App.polyscopeHandle().remove_volume_mesh(sName);
                catch
                end
            end
            obj.highlight_ = struct();
        end

        function highlightNode_(obj, info, idx)
            if ~isfield(info, 'coords') || idx > size(info.coords, 1), return; end
            obj.highlightNodePoint_(info.coords(idx, :), 'QueryHighlightNode');
        end

        function highlightLineElement_(obj, info, eleRow)
            if ~isfield(info, 'cells') || eleRow < 1 || eleRow > size(info.cells, 1), return; end
            P = plotter.polyscope.ModelAdapter.nodeCoords(obj.ModelInfo);
            ids = obj.cellNodeIds_(info.cells(eleRow, :), size(P, 1));
            if numel(ids) < 2, return; end
            edges = [(1:numel(ids)-1).', (2:numel(ids)).'];
            obj.highlightCurve_(P(ids, :), edges, 'QueryHighlightElement');
        end

        function highlightSurfaceElement_(obj, info, eleRow)
            if ~isfield(info, 'cells') || eleRow < 1 || eleRow > size(info.cells, 1), return; end
            P = plotter.polyscope.ModelAdapter.nodeCoords(obj.ModelInfo);
            ids = obj.cellNodeIds_(info.cells(eleRow, :), size(P, 1));
            if numel(ids) < 1, return; end
            if isfield(info, 'kind') && strcmp(info.kind, 'volume')
                edges = obj.volumeCellEdges_(numel(ids));
            else
                edges = obj.surfaceCellEdges_(numel(ids));
            end
            if isempty(edges), return; end
            obj.highlightCurve_(P(ids, :), edges, 'QueryHighlightElement');
        end

        function highlightNodePoint_(obj, pos, baseName)
            pos = double(pos(:).');
            if numel(pos) < 3 || any(~isfinite(pos(1:3))), return; end
            try
                obj.App.polyscopeHandle().remove_point_cloud(obj.structName_(baseName));
            catch
            end
            pc = obj.App.polyscopeHandle().register_point_cloud( ...
                obj.structName_(baseName), pos);
            pc.set_enabled(true);
            pc.set_radius(obj.highlightNodeRadius_(), true);
            pc.set_color([1.0, 0.78, 0.0]);
            pc.set_material(obj.Opts.polyscope.lineMaterial);
            pc.set_point_render_mode(obj.Opts.polyscope.pointRenderMode);
            obj.highlight_.(baseName) = pc;
        end

        function highlightCurve_(obj, nodes, edges, baseName)
            try
                obj.App.polyscopeHandle().remove_curve_network(obj.structName_(baseName));
            catch
            end
            if isempty(nodes) || isempty(edges), return; end
            cn = obj.App.polyscopeHandle().register_curve_network( ...
                obj.structName_(baseName), double(nodes), double(edges));
            cn.set_enabled(true);
            cn.set_radius(obj.highlightRadius_(), true);
            cn.set_color([1.0, 0.78, 0.0]);
            cn.set_material(obj.Opts.polyscope.lineMaterial);
            cn.set_transparency(1.0);
            obj.highlight_.(baseName) = cn;
        end

        function r = highlightRadius_(obj)
            base = obj.currentElementLineRadius_();
            r = min(max(base * 2.0, 0.001), 0.03);
            if ~isfinite(r) || r <= 0
                r = 0.002;
            end
        end

        function r = currentElementLineRadius_(obj)
            if obj.isWireframeOnly_()
                r = obj.wireframeRadius_();
            else
                r = obj.Opts.polyscope.edgeRadius;
            end
            if ~isfinite(r) || r <= 0
                r = obj.Opts.polyscope.edgeRadius;
            end
            if ~isfinite(r) || r <= 0
                r = 0.001;
            end
        end

        function r = highlightNodeRadius_(obj)
            base = max(obj.Opts.polyscope.nodeRadius, obj.Opts.polyscope.edgeRadius * 2);
            r = min(max(base * 1.4, 0.002), 0.014);
            if ~isfinite(r) || r <= 0
                r = 0.006;
            end
        end

        function edges = surfaceCellEdges_(~, n)
            if n == 3
                edges = [1 2; 2 3; 3 1];
            elseif n >= 4
                edges = [(1:n).', [2:n, 1].'];
            else
                edges = zeros(0, 2);
            end
        end

        function edges = volumeCellEdges_(~, n)
            if n == 4
                edges = [1 2; 1 3; 1 4; 2 3; 2 4; 3 4];
            elseif n == 10
                edges = [1 5; 5 2; 2 6; 6 3; 1 7; 7 3; ...
                         1 8; 8 4; 2 9; 9 4; 3 10; 10 4];
            elseif n >= 20
                edges = [1 9; 9 2; 2 10; 10 3; 3 11; 11 4; 4 12; 12 1; ...
                         5 13; 13 6; 6 14; 14 7; 7 15; 15 8; 8 16; 16 5; ...
                         1 17; 17 5; 2 18; 18 6; 3 19; 19 7; 4 20; 20 8];
            elseif n >= 8
                edges = [1 2; 2 3; 3 4; 4 1; ...
                         5 6; 6 7; 7 8; 8 5; ...
                         1 5; 2 6; 3 7; 4 8];
            else
                edges = zeros(0, 2);
            end
        end

        function txt = describeSelection_(obj, sel)
            if ~isstruct(sel) || ~obj.scalarLogicalField_(sel, 'is_hit')
                txt = 'No hit.';
                return;
            end

            sName = obj.charField_(sel, 'structure_name');
            idx = round(obj.doubleField_(sel, 'local_index'));
            pos = obj.vectorField_(sel, 'position');

            key = obj.validQueryKey_(sName);
            if isfield(obj.query_, key)
                lines = obj.describeMappedSelection_(obj.query_.(key), idx, pos);
            else
                lines = "No OpenSees mapping.";
            end

            txt = char(strjoin(lines, newline));
        end

        function lines = describeMappedSelection_(obj, info, idx, pos)
            lines = strings(0, 1);
            if ~isfinite(idx) || idx < 1
                lines(end+1) = "OpenSees mapping: invalid local index";
                return;
            end

            switch info.kind
                case 'node'
                    if idx <= numel(info.tags)
                        lines(end+1) = "Node: " + string(obj.formatNumber_(info.tags(idx)));
                    end
                    if isfield(info, 'rawCoords') && idx <= size(info.rawCoords, 1) && ...
                            all(isfinite(info.rawCoords(idx, :)))
                        lines(end+1) = "Coord: " + string(obj.formatVec_(info.rawCoords(idx, :)));
                    elseif isfield(info, 'coords') && idx <= size(info.coords, 1)
                        lines(end+1) = "Coord: " + string(obj.formatVec_(info.coords(idx, :)));
                    end

                case 'line'
                    eleRow = obj.lookupElementRow_(info, idx, 'edgeToElement', pos);
                    lines = obj.describeElementRow_(info, eleRow);

                case 'surface'
                    eleRow = obj.lookupElementRow_(info, idx, 'triCellIds', pos);
                    lines = obj.describeElementRow_(info, eleRow);

                case 'volume'
                    eleRow = obj.lookupElementRow_(info, idx, 'volumeCellIds', pos);
                    lines = obj.describeElementRow_(info, eleRow);

                case 'surfaceWire'
                    eleRow = obj.lookupElementRow_(info, idx, 'edgeToElement', pos);
                    lines = obj.describeElementRow_(info, eleRow);
                    lines(end+1) = "Boundary segment: " + string(idx);

                case 'mp'
                    if idx <= size(info.cells, 1)
                        lines(end+1) = "MP constraint: " + string(idx);
                        lines(end+1) = "Nodes: " + string(obj.formatVec_(obj.cellNodeTags_(info.cells(idx, :))));
                    end

                otherwise
                    lines(end+1) = "Unsupported selection.";
            end
        end

        function eleRow = lookupElementRow_(obj, info, idx, fieldName, pos)
            if isfield(info, fieldName)
                map = double(info.(fieldName));
                if idx <= numel(map) && map(idx) >= 1
                    eleRow = round(map(idx));
                    return;
                end
            end
            if isfield(info, 'cells') && idx <= size(info.cells, 1)
                eleRow = idx;
                return;
            end
            eleRow = obj.nearestElementRow_(info, pos);
            if ~isfinite(eleRow)
                eleRow = idx;
            end
        end

        function eleRow = nearestElementRow_(~, info, pos)
            eleRow = NaN;
            if nargin < 3 || numel(pos) < 3 || ~isfield(info, 'centers') || isempty(info.centers)
                return;
            end
            P = double(info.centers);
            valid = all(isfinite(P), 2);
            if ~any(valid), return; end
            d2 = sum((P(valid, :) - double(pos(1:3))).^2, 2);
            [~, j] = min(d2);
            rows = find(valid);
            eleRow = rows(j);
        end

        function lines = describeElementRow_(obj, info, eleRow)
            lines = strings(0, 1);
            if ~isfinite(eleRow) || eleRow < 1 || ...
                    (isfield(info, 'cells') && eleRow > size(info.cells, 1))
                lines(end+1) = "Element: unavailable";
                return;
            end
            typeName = obj.elementTypeName_(info, eleRow);
            if strlength(typeName) > 0
                lines(end+1) = "Element type: " + typeName;
            end
            lines(end+1) = "Class: " + string(info.family);
            if isfield(info, 'tags') && eleRow <= numel(info.tags)
                lines(end+1) = "Element: " + string(obj.formatNumber_(info.tags(eleRow)));
            else
                lines(end+1) = "Element row: " + string(eleRow);
            end
            if isfield(info, 'cells') && eleRow <= size(info.cells, 1)
                lines(end+1) = "Nodes: " + string(obj.formatVec_(obj.cellNodeTags_(info.cells(eleRow, :))));
            end
        end

        function typeName = elementTypeName_(obj, info, eleRow)
            typeName = "";
            if eleRow < 1, return; end
            if isfield(info, 'typeNames') && eleRow <= numel(info.typeNames)
                typeName = string(info.typeNames(eleRow));
                if strlength(typeName) > 0, return; end
            end
            if isfield(info, 'classTags') && eleRow <= numel(info.classTags)
                try
                    typeName = post.utils.OpenSeesTagMaps.getClassName(info.classTags(eleRow));
                catch
                    typeName = "ClassTag_" + string(obj.formatNumber_(info.classTags(eleRow)));
                end
            end
        end

        function ids = cellNodeIds_(~, row, nNode)
            ids = double(row(:).');
            ids = ids(isfinite(ids));
            if isempty(ids), return; end
            if numel(ids) > 2
                n = ids(1);
                if isfinite(n) && n >= 2 && numel(ids) >= n + 1
                    ids = ids(2:1+n);
                end
            end
            ids = round(ids(ids >= 1));
            ids = ids(ids >= 1 & ids <= nNode);
        end

        function tags = cellNodeTags_(obj, row)
            allTags = plotter.polyscope.ModelAdapter.nodeTags(obj.ModelInfo);
            ids = obj.cellNodeIds_(row, numel(allTags));
            tags = ids;
            valid = ids >= 1 & ids <= numel(allTags);
            tags(valid) = allTags(ids(valid));
        end

        function tf = scalarLogicalField_(~, s, name)
            tf = false;
            if isfield(s, name)
                val = s.(name);
                if islogical(val) || isnumeric(val)
                    tf = logical(val(1));
                end
            end
        end

        function val = charField_(~, s, name)
            val = '';
            if isfield(s, name)
                raw = s.(name);
                if isstring(raw) || ischar(raw)
                    val = char(string(raw));
                end
            end
        end

        function val = doubleField_(~, s, name)
            val = NaN;
            if isfield(s, name) && ~isempty(s.(name))
                val = double(s.(name));
                val = val(1);
            end
        end

        function val = vectorField_(~, s, name)
            val = [];
            if isfield(s, name) && ~isempty(s.(name))
                val = double(s.(name));
                val = val(:).';
            end
        end

        function txt = formatVec_(obj, v)
            v = double(v(:)).';
            v = v(isfinite(v));
            if isempty(v)
                txt = '';
                return;
            end
            parts = strings(1, numel(v));
            for i = 1:numel(v)
                parts(i) = string(obj.formatNumber_(v(i)));
            end
            txt = char(strjoin(parts, ', '));
        end

        function txt = formatNumber_(~, x)
            if abs(x - round(x)) < 1e-10
                txt = sprintf('%.0f', x);
            else
                txt = sprintf('%.6g', x);
            end
        end

        function tf = isWireframeOnly_(obj)
            tf = obj.Opts.elements.wireframeOnly || ...
                 strcmpi(obj.Opts.style.mode, 'wireframe');
        end

        function r = wireframeRadius_(obj)
            lw = obj.Opts.elements.wireframeLineWidth;
            ref = obj.Opts.elements.lineWidth;
            base = obj.Opts.polyscope.edgeRadius;
            r = base * lw / max(ref, 1);
        end

        function len = getLoadAutoLength_(obj)
            len = obj.L_ * obj.Opts.loads.baseFraction * obj.Opts.loads.scale;
            if ~isfinite(len) || len <= 0
                len = obj.Opts.loads.scale;
            end
        end

        function maxMag = computeGlobalMaxMag_(obj, L, P, minNorm)
            allMags = [];
            if isfield(L, 'Node') && isfield(L.Node, 'PatternNodeTags') && ...
                    ~isempty(L.Node.PatternNodeTags) && isfield(L.Node, 'Values') && ...
                    ~isempty(L.Node.Values)
                tags = double(L.Node.PatternNodeTags);
                if size(tags, 2) >= 2
                    idx = obj.nodeTagsToIdx_(tags(:, 2));
                    valid = idx > 0 & idx <= size(P, 1);
                    vals = double(L.Node.Values);
                    n = min(numel(valid), size(vals, 1));
                    if n > 0
                        vals = vals(1:n, :);
                        valid = valid(1:n);
                        vals = vals(valid, :);
                        V = zeros(size(vals, 1), 3);
                        V(:, 1:min(3, size(vals, 2))) = vals(:, 1:min(3, size(vals, 2)));
                        allMags = [allMags; sqrt(sum(V.^2, 2))];
                    end
                end
            end
            if isfield(L, 'Element') && isfield(L.Element, 'Beam') && ...
                    isfield(L.Element.Beam, 'Values') && ~isempty(L.Element.Beam.Values)
                valsAll = double(L.Element.Beam.Values);
                if isvector(valsAll), valsAll = reshape(valsAll, 1, []); end
                for i = 1:size(valsAll, 1)
                    [comps, ~, ~, isDist, isPoint] = ...
                        obj.extractBeamLoadComponents_(valsAll(i, :), minNorm);
                    if isPoint || isDist
                        allMags = [allMags; abs(comps(:))]; %#ok<AGROW>
                    end
                end
            end

            allMags = allMags(allMags > minNorm);
            if isempty(allMags)
                maxMag = 1;
            else
                maxMag = max(allMags);
            end
        end


        function [qLocal, xa, xb, isDist, isPoint] = extractBeamLoadComponents_(~, row, minNorm)
            qLocal = [0 0 0];
            xa = 0;
            xb = 0;
            isDist = false;
            isPoint = false;

            if isempty(row), return; end
            row = double(row(:).');
            if numel(row) < 8, row(8) = 0; end

            wy1 = row(1); wy2 = row(2);
            wz1 = row(3); wz2 = row(4);
            wx1 = row(5); wx2 = row(6);
            xa = row(7);
            xb = row(8);

            if abs(xb + 10000) < max(minNorm, 1e-12)
                isPoint = true;
            else
                hasLoad = any(abs([wy1 wy2 wz1 wz2 wx1 wx2]) > minNorm);
                if hasLoad
                    if abs(xa) < minNorm && abs(xb) < minNorm
                        xa = 0;
                        xb = 1;
                    end
                    if xb > xa + minNorm
                        isDist = true;
                    elseif abs(xb - xa) <= minNorm
                        isPoint = true;
                        xb = -10000;
                    end
                end
            end

            if isPoint
                qLocal = [wx1 wy1 wz1];
                xa = max(0, min(1, xa));
            elseif isDist
                qLocal = [0.5 * (wx1 + wx2), 0.5 * (wy1 + wy2), 0.5 * (wz1 + wz2)];
                xa = max(0, min(1, xa));
                xb = max(0, min(1, xb));
                if xb < xa
                    t = xa; xa = xb; xb = t;
                end
            end
        end

        function [allPts, allVec, iArrow] = appendLoadComponent_(obj, allPts, allVec, iArrow, posList, axisDir, qComp, baseLen, maxMag)
            if abs(qComp) <= obj.Opts.loads.minNorm, return; end

            nPos = size(posList, 1);
            if obj.Opts.loads.normalizeLength
                drawLen = baseLen * sign(qComp);
            else
                drawLen = baseLen * qComp / max(maxMag, obj.Opts.loads.minNorm);
            end

            Udraw = drawLen * axisDir;
            idxRange = iArrow + (1:nPos);
            allPts(idxRange, :) = posList - repmat(Udraw, nPos, 1);
            allVec(idxRange, :) = repmat(Udraw, nPos, 1);
            iArrow = iArrow + nPos;
        end

        function [p1, p2, ok] = lookupBeamEndCoords_(obj, eleTag, P)
            p1 = [NaN NaN NaN];
            p2 = [NaN NaN NaN];
            ok = false;

            fam = plotter.polyscope.ModelAdapter.families(obj.ModelInfo);
            if isfield(fam, 'Beam')
                [p1, p2, ok] = obj.lookupFamilyEndCoords_(fam.Beam, eleTag, P);
                if ok, return; end
            end
            if isfield(fam, 'Line')
                [p1, p2, ok] = obj.lookupFamilyEndCoords_(fam.Line, eleTag, P);
            end
        end

        function [p1, p2, ok] = lookupFamilyEndCoords_(~, S, eleTag, P)
            p1 = [NaN NaN NaN];
            p2 = [NaN NaN NaN];
            ok = false;
            if ~isstruct(S) || ~isfield(S, 'Tags') || isempty(S.Tags) || ...
                    ~isfield(S, 'Cells') || isempty(S.Cells)
                return;
            end

            eleTags = double(S.Tags(:));
            cells = double(S.Cells);
            if ~ismatrix(cells), cells = squeeze(cells); end
            if isempty(cells), return; end
            if isvector(cells), cells = reshape(cells, 1, []); end

            idx = find(abs(eleTags - eleTag) < 1e-12, 1, 'first');
            if isempty(idx) || idx > size(cells, 1), return; end

            row = cells(idx, :);
            row = row(isfinite(row));
            if numel(row) >= 3
                nodeIdx = round(row(end-1:end));
            elseif numel(row) == 2
                nodeIdx = round(row);
            else
                return;
            end
            if any(nodeIdx < 1) || any(nodeIdx > size(P, 1)), return; end
            p1 = P(nodeIdx(1), :);
            p2 = P(nodeIdx(2), :);
            ok = true;
        end

        function [xaxis, yaxis, zaxis, ok] = lookupBeamLocalAxes_(obj, eleTag)
            xaxis = [NaN NaN NaN];
            yaxis = [NaN NaN NaN];
            zaxis = [NaN NaN NaN];
            ok = false;

            fam = plotter.polyscope.ModelAdapter.families(obj.ModelInfo);
            if ~isfield(fam, 'Beam') || ~isstruct(fam.Beam) || ...
                    ~isfield(fam.Beam, 'Tags') || isempty(fam.Beam.Tags)
                return;
            end
            S = fam.Beam;
            idx = find(abs(double(S.Tags(:)) - eleTag) < 1e-12, 1, 'first');
            if isempty(idx), return; end
            if ~isfield(S, 'XAxis') || ~isfield(S, 'YAxis') || ~isfield(S, 'ZAxis')
                return;
            end
            if idx > size(S.XAxis, 1) || idx > size(S.YAxis, 1) || idx > size(S.ZAxis, 1)
                return;
            end
            xaxis = S.XAxis(idx, :);
            yaxis = S.YAxis(idx, :);
            zaxis = S.ZAxis(idx, :);
            ok = all(isfinite([xaxis yaxis zaxis]));
        end

        function idx = nodeTagsToIdx_(obj, nodeTags)
            allTags = plotter.polyscope.ModelAdapter.nodeTags(obj.ModelInfo);
            idx = plotter.polyscope.ModelAdapter.tagsToIdx(nodeTags, allTags);
        end

        function applyNodeRadius_(obj)
            r = obj.gui_.nodeRadius;
            if isfield(obj.handles_, 'Nodes'), obj.handles_.Nodes.set_radius(r, true); end
            if isfield(obj.handles_, 'Fixed'), obj.handles_.Fixed.set_radius(r * 1.5, true); end
        end

        function applyEdgeRadius_(obj)
            rEdge = obj.gui_.edgeRadius;
            names = fieldnames(obj.handles_);
            for k = 1:numel(names)
                name = names{k};
                if isa(obj.handles_.(name), 'polyscope.CurveNetwork')
                    obj.handles_.(name).set_radius(rEdge, true);
                end
            end
            if isfield(obj.handles_, 'MPConstraint')
                obj.handles_.MPConstraint.set_radius(rEdge * 0.8, true);
            end
            if isfield(obj.handles_, 'Outline')
                obj.handles_.Outline.set_radius(rEdge * 0.7, true);
            end
        end

        function applySurfaceAlpha_(obj)
            alpha = obj.gui_.surfaceAlpha;
            names = fieldnames(obj.handles_);
            for k = 1:numel(names)
                name = names{k};
                if isa(obj.handles_.(name), 'polyscope.SurfaceMesh')
                    obj.handles_.(name).set_transparency(alpha);
                end
            end
        end

        function applySurfaceMaterial_(obj)
            m = obj.gui_.surfaceMaterial;
            names = fieldnames(obj.handles_);
            for k = 1:numel(names)
                name = names{k};
                if isa(obj.handles_.(name), 'polyscope.SurfaceMesh')
                    try
                        obj.handles_.(name).set_material(m);
                    catch
                    end
                end
            end
        end

        function applySurfaceSmoothShade_(obj)
            tf = obj.gui_.surfaceSmoothShade;
            names = fieldnames(obj.handles_);
            for k = 1:numel(names)
                name = names{k};
                if isa(obj.handles_.(name), 'polyscope.SurfaceMesh')
                    try
                        obj.handles_.(name).set_smooth_shade(tf);
                    catch
                    end
                end
            end
        end

        function applyStyleColors_(obj)
            if isempty(fieldnames(obj.handles_)), return; end
            lineNames = plotter.polyscope.ModelAdapter.lineFamilyNames();
            for k = 1:numel(lineNames)
                name = lineNames{k};
                if isfield(obj.handles_, name)
                    obj.handles_.(name).set_color(obj.getStyleColor_(name, 'line'));
                end
            end
            continuumNames = [plotter.polyscope.ModelAdapter.surfaceFamilyNames(), ...
                              plotter.polyscope.ModelAdapter.volumeFamilyNames()];
            for k = 1:numel(continuumNames)
                name = continuumNames{k};
                if isfield(obj.handles_, name)
                    obj.handles_.(name).set_color(obj.getStyleColor_(name, 'surface'));
                end
                wireName = [name 'Wire'];
                if isfield(obj.handles_, wireName)
                    if obj.isWireframeOnly_()
                        obj.handles_.(wireName).set_color(obj.getStyleColor_(name, 'surface'));
                    else
                        obj.handles_.(wireName).set_color(plotter.polyscope.utils.colorToRgb(obj.Opts.style.wireframeColor));
                    end
                end
            end
            if isfield(obj.gui_, 'classNames')
                for k = 1:numel(obj.gui_.classNames)
                    name = obj.gui_.classNames{k};
                    if isfield(obj.handles_, name)
                        obj.handles_.(name).set_color(obj.classColor_(name, k));
                    end
                    wireName = [name 'Wire'];
                    if isfield(obj.handles_, wireName)
                        if obj.isWireframeOnly_()
                            obj.handles_.(wireName).set_color(obj.classColor_(name, k));
                        else
                            obj.handles_.(wireName).set_color(plotter.polyscope.utils.colorToRgb(obj.Opts.style.wireframeColor));
                        end
                    end
                end
            end
            if isfield(obj.handles_, 'Nodes'), obj.handles_.Nodes.set_color(obj.gui_.colors.node); end
            if isfield(obj.handles_, 'Fixed'), obj.handles_.Fixed.set_color(obj.gui_.colors.fixed); end
            if isfield(obj.handles_, 'MPConstraint'), obj.handles_.MPConstraint.set_color(obj.gui_.colors.mp); end
            if isfield(obj.handles_, 'Outline'), obj.handles_.Outline.set_color(obj.gui_.colors.outline); end
        end

        function applyElementVisibility_(obj)
            if isempty(fieldnames(obj.handles_)), return; end
            lineNames = plotter.polyscope.ModelAdapter.lineFamilyNames();
            lineFlags = [obj.Opts.elements.showBeam, ...
                         obj.Opts.elements.showTruss, ...
                         obj.Opts.elements.showLink, ...
                         obj.Opts.elements.showContact];
            for k = 1:numel(lineNames)
                obj.setHandleEnabled_(lineNames{k}, lineFlags(k));
            end
            surfaceNames = [plotter.polyscope.ModelAdapter.surfaceFamilyNames(), ...
                            plotter.polyscope.ModelAdapter.volumeFamilyNames()];
            surfaceFlags = [obj.Opts.elements.showPlane, ...
                            obj.Opts.elements.showShell, ...
                            obj.Opts.elements.showSolid];
            wireframeOnly = obj.isWireframeOnly_();
            showWireframeOnFaces = obj.Opts.elements.showWireframeOnFaces;
            for k = 1:numel(surfaceNames)
                name = surfaceNames{k};
                showFlag = surfaceFlags(k);
                obj.setHandleEnabled_(name, showFlag && ~wireframeOnly);
                obj.setHandleEnabled_([name 'Wire'], showFlag && (wireframeOnly || showWireframeOnFaces));
            end
            if isfield(obj.gui_, 'classNames')
                for k = 1:numel(obj.gui_.classNames)
                    name = obj.gui_.classNames{k};
                    showFlag = obj.gui_.classShow.(name);
                    if isfield(obj.handles_, name)
                        h = obj.handles_.(name);
                        if isa(h, 'polyscope.SurfaceMesh') || isa(h, 'polyscope.VolumeMesh')
                            h.set_enabled(showFlag && ~wireframeOnly);
                        else
                            h.set_enabled(showFlag);
                        end
                    end
                    obj.setHandleEnabled_([name 'Wire'], showFlag && (wireframeOnly || showWireframeOnFaces));
                end
            end
        end

        function setHandleEnabled_(obj, name, tf)
            if isfield(obj.handles_, name)
                try
                    obj.handles_.(name).set_enabled(tf);
                catch
                end
            end
        end

        function setAxesEnabled_(obj, baseName, tf)
            suffixes = {'X', 'Y', 'Z'};
            for k = 1:numel(suffixes)
                obj.setHandleEnabled_([baseName suffixes{k}], tf);
            end
        end

        function updateLoads_(obj)
            P = plotter.polyscope.ModelAdapter.nodeCoords(obj.ModelInfo);
            if isempty(P), return; end
            ps = obj.App.polyscopeHandle();
            loadNames = {'NodalLoads', 'ElementLoads'};
            for k = 1:numel(loadNames)
                baseName = loadNames{k};
                try
                    ps.remove_point_cloud(obj.structName_(baseName));
                catch
                end
                if isfield(obj.handles_, baseName)
                    obj.handles_ = rmfield(obj.handles_, baseName);
                end
            end
            obj.registerLoads_(P);
        end

        function updateLocalAxes_(obj)
            ps = obj.App.polyscopeHandle();
            suffixes = {'X', 'Y', 'Z'};
            bases = {'BeamAxes', 'LinkAxes'};
            for ib = 1:numel(bases)
                for k = 1:numel(suffixes)
                    name = [bases{ib} suffixes{k}];
                    try
                        ps.remove_point_cloud(obj.structName_(name));
                    catch
                    end
                    if isfield(obj.handles_, name)
                        obj.handles_ = rmfield(obj.handles_, name);
                    end
                end
            end
            obj.registerLocalAxes_();
        end

        function applyVectorRadius_(obj)
            obj.updateLocalAxes_();
            obj.updateLoads_();
        end

    end
end
