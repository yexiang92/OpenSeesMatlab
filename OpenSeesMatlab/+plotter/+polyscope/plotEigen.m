classdef plotEigen < plotter.polyscope.ViewerBase
    %PLOTEIGEN Polyscope-based modal shape visualisation.
    %
    %   Example
    %   -------
    %       h = plotter.polyscope.plotEigen(modelInfo, eigenInfo);
    %
    %   The constructor opens the interactive viewer window. Use the
    %   in-window GUI to change the mode, component, scale and style.

    properties (Access = private)
        modeTags_     double = []
        currentIdx_   double = 1
        surfData_     struct = struct()
        classData_    struct = struct()
        initialOpts_  struct
    end

    methods (Access = public)

        function obj = plotEigen(modelInfo, eigenInfo, opts)
            if nargin < 1 || isempty(modelInfo)
                error('plotter:polyscope:plotEigen:InvalidInput', ...
                    'modelInfo is required.');
            end
            if nargin < 2 || isempty(eigenInfo)
                error('plotter:polyscope:plotEigen:InvalidInput', ...
                    'eigenInfo is required.');
            end
            if nargin < 3 || isempty(opts)
                opts = struct();
            end
            obj = obj@plotter.polyscope.ViewerBase();
            obj.ModelInfo = modelInfo;
            obj.EigenInfo = eigenInfo;
            obj.Opts = plotter.polyscope.Options.mergeOpts( ...
                plotter.polyscope.Options.defaultEigenOptions(), opts);
            obj.App = plotter.polyscope.PolyscopeApp();
            obj.P0_ = plotter.polyscope.ModelAdapter.nodeCoords(modelInfo);
            obj.L_  = plotter.polyscope.ModelAdapter.modelLength(modelInfo);
            obj.modeTags_ = obj.collectModeTags_();
            try
                obj.currentIdx_ = obj.resolveModeIndex_(obj.Opts.mode.modeTag);
            catch
                obj.currentIdx_ = 1;
                if ~isempty(obj.modeTags_)
                    obj.Opts.mode.modeTag = obj.modeTags_(1);
                end
            end
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
            is2D = obj.is2DModel_();
            if is2D && strcmpi(char(string(obj.Opts.general.view)), '3D')
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
            obj.surfData_ = struct();
            obj.classData_ = struct();

            if obj.hasElementClasses_()
                obj.registerElementClassStructures_();
            else
                obj.registerLineStructures_();
                obj.registerSurfaceStructures_();
            end
            obj.registerNodeStructure_();
            obj.registerFixedStructure_();
            obj.registerMPStructure_();

            if ~obj.isOverlayScreenAxes_()
                obj.registerScreenAxes3D_();
            end
            obj.registerSlicePlanes_();
            obj.applySliceCullWholeElements_();

            obj.built_ = true;
            if obj.getOptField_(obj.Opts.polyscope, 'onscreenColorbar', false)
                obj.resolveColorbarLocation_();
            end
            obj.setMode(obj.modeTags_(obj.currentIdx_));
            if firstBuild
                obj.setDefaultCamera_();
            end
            obj.updateScreenAxes3D_();
            if isfield(obj.gui_, 'modelStats')
                obj.gui_.modelStats = obj.computeModelStats_();
            end
        end

        function setMode(obj, modeTag)
            if nargin < 2 || isempty(modeTag)
                modeTag = obj.Opts.mode.modeTag;
            end
            idx = obj.resolveModeIndex_(modeTag);
            obj.currentIdx_ = idx;
            obj.Opts.mode.modeTag = obj.modeTags_(idx);
            if ~obj.built_
                return;
            end

            [Uraw, scale] = obj.computeModeDisplacement_(idx);
            Pdef = obj.P0_ + scale * Uraw;
            S = obj.computeScalarField_(Uraw);

            obj.updateStructures_(Pdef, S);
            obj.updateProgramName_();

            if isfield(obj.gui_, 'modeIdx')
                obj.gui_.modeIdx = idx;
            end
        end

        function nextMode(obj)
            idx = obj.currentIdx_ + 1;
            if idx > numel(obj.modeTags_)
                idx = 1;
            end
            obj.setMode(obj.modeTags_(idx));
        end

        function prevMode(obj)
            idx = obj.currentIdx_ - 1;
            if idx < 1
                idx = numel(obj.modeTags_);
            end
            obj.setMode(obj.modeTags_(idx));
        end

        function tags = getModeTags(obj)
            tags = obj.modeTags_;
        end

    end

    methods (Access = protected)

        function initGuiState_(obj)
            initGuiState_@plotter.polyscope.ViewerBase(obj);

            components = {'magnitude', 'ux', 'uy', 'uz'};
            obj.gui_.modeIdx = obj.currentIdx_;
            if obj.gui_.modeIdx < 1 || obj.gui_.modeIdx > numel(obj.modeTags_)
                obj.gui_.modeIdx = 1;
            end
            compIdx = find(strcmpi(components, char(string(obj.Opts.mode.component))), 1);
            if isempty(compIdx), compIdx = 1; end
            obj.gui_.compIdx = compIdx;

            obj.gui_.scale = obj.Opts.mode.scale;
            obj.gui_.autoScale = obj.Opts.mode.autoScale;
            obj.gui_.showUndeformed = obj.Opts.mode.showUndeformed;
            obj.gui_.useColormap = obj.Opts.color.useColormap;
            obj.gui_.showScreenAxes = obj.getOptField_(obj.Opts.polyscope, 'showScreenAxes', true);
            obj.gui_.showModeInfo = obj.getOptField_(obj.Opts.polyscope, 'showModelInfo', false);

            obj.gui_.showLines = obj.Opts.line.show;
            obj.gui_.showSurfaces = obj.Opts.unstructured.show;
            obj.gui_.showSurfaceEdges = obj.Opts.unstructured.showEdges;
            obj.gui_.wireframe = obj.getOptField_(obj.Opts.unstructured, 'wireframe', false);
            obj.gui_.showNodes = obj.Opts.nodes.show;
            obj.gui_.showFixed = obj.Opts.fixed.show;
            obj.gui_.showMP = obj.Opts.mpConstraint.show;

            obj.gui_.deformedAlpha = obj.Opts.color.deformedAlpha;
            obj.gui_.undeformedAlpha = obj.Opts.color.undeformedAlpha;
            obj.gui_.undeformedColor = plotter.polyscope.utils.colorToRgb( ...
                obj.Opts.color.undeformedColor);
            obj.gui_.onscreenColorbar = obj.getOptField_(obj.Opts.polyscope, ...
                'onscreenColorbar', false);
            obj.gui_.onscreenColorbarLocation = obj.getOptField_(obj.Opts.polyscope, ...
                'onscreenColorbarLocation', []);
            obj.gui_.colorbarTitle = char(string(obj.getOptField_(obj.Opts.polyscope, ...
                'colorbarTitle', 'Mode')));
            obj.gui_.colorbarForcePos = obj.gui_.onscreenColorbar;
            obj.gui_.nodeRadius = obj.Opts.polyscope.nodeRadius;
            obj.gui_.edgeRadius = obj.Opts.polyscope.edgeRadius;

            cmapNames = obj.colormapNames_();
            cmapName = lower(char(string(obj.Opts.polyscope.scalarColorMap)));
            if ischar(obj.Opts.color.colormap) || isstring(obj.Opts.color.colormap)
                cmapName = lower(char(string(obj.Opts.color.colormap)));
            end
            cmapIdx = find(strcmpi(cmapNames, cmapName), 1);
            if isempty(cmapIdx), cmapIdx = find(strcmpi(cmapNames, 'viridis'), 1); end
            if isempty(cmapIdx), cmapIdx = 1; end
            obj.gui_.cmapIdx = cmapIdx;

            obj.gui_.showHelp = false;
            obj.gui_.modelStats = obj.computeModelStats_();

            obj.initSliceGuiState_();
        end

        function cb = colorbarArgs_(obj)
            cb = {};
            if ~obj.getOptField_(obj.Opts.polyscope, 'onscreenColorbar', false)
                return;
            end
            cb = {'onscreen_colorbar_enabled', true};
            loc = obj.getOptField_(obj.Opts.polyscope, 'onscreenColorbarLocation', []);
            if ~isempty(loc) && numel(loc) == 2 && all(isfinite(loc))
                cb = [cb, {'onscreen_colorbar_location', double(loc(:).')}];
            end
        end

        function names = colormapNames_(~)
            names = {'viridis', 'blues', 'reds', 'coolwarm', 'pink-green', ...
                     'phase', 'spectral', 'rainbow', 'jet', 'turbo'};
        end

    end

    methods (Access = private)

        function registerLineStructures_(obj)
            if ~obj.Opts.line.show
                return;
            end
            famNames = plotter.polyscope.ModelAdapter.lineFamilyNames();
            ps = obj.App.polyscopeHandle();
            for k = 1:numel(famNames)
                name = famNames{k};
                edges = plotter.polyscope.ModelAdapter.lineEdges(obj.ModelInfo, name);
                if isempty(edges), continue; end

                if obj.Opts.mode.showUndeformed
                    gName = obj.structName_(name, 'ghost');
                    gRgb = plotter.polyscope.utils.colorToRgb(obj.Opts.color.undeformedColor);
                    gCn = ps.register_curve_network(gName, obj.P0_, edges);
                    gCn.set_color(gRgb);
                    gCn.set_radius(obj.Opts.polyscope.edgeRadius * 0.8, true);
                    gCn.set_transparency(obj.Opts.color.undeformedAlpha);
                    gCn.set_material(obj.Opts.polyscope.lineMaterial);
                    obj.handles_.(['ghost_' name]) = gCn;
                end

                dName = obj.structName_(name, 'def');
                dRgb = plotter.polyscope.utils.colorToRgb(obj.Opts.color.lineColor);
                dCn = ps.register_curve_network(dName, obj.P0_, edges);
                dCn.set_color(dRgb);
                dCn.set_radius(obj.Opts.polyscope.edgeRadius, true);
                dCn.set_transparency(obj.Opts.color.deformedAlpha);
                dCn.set_material(obj.Opts.polyscope.lineMaterial);
                obj.handles_.(['def_' name]) = dCn;
            end
        end

        function registerSurfaceStructures_(obj)
            fam = plotter.polyscope.ModelAdapter.families(obj.ModelInfo);
            famNames = [plotter.polyscope.ModelAdapter.surfaceFamilyNames(), ...
                        plotter.polyscope.ModelAdapter.volumeFamilyNames()];
            ps = obj.App.polyscopeHandle();
            wireframe = obj.getOptField_(obj.Opts.unstructured, 'wireframe', false);
            showSurf = obj.Opts.unstructured.show;
            showEdges = obj.Opts.unstructured.showEdges;
            for k = 1:numel(famNames)
                name = famNames{k};
                if ~isfield(fam, name), continue; end
                S = fam.(name);
                if ~isstruct(S) || ~isfield(S, 'Cells') || isempty(S.Cells) || ...
                   ~isfield(S, 'CellTypes') || isempty(S.CellTypes)
                    continue;
                end
                cellTypes = double(S.CellTypes);
                cells = plotter.polyscope.ModelAdapter.normalizeCells( ...
                    obj.ModelInfo, double(S.Cells));
                if strcmpi(name, 'Solid') && obj.isVolumeClass_(cellTypes)
                    vol0 = plotter.utils.VTKElementTriangulator.volumize( ...
                        obj.P0_, cellTypes, cells);
                    out0 = plotter.utils.VTKElementTriangulator.triangulate( ...
                        obj.P0_, cellTypes, cells);
                    if isempty(vol0) || ~isfield(vol0, 'Points') || isempty(vol0.Points) || ...
                       ((~isfield(vol0, 'Tets') || isempty(vol0.Tets)) && ...
                        (~isfield(vol0, 'Hexes') || isempty(vol0.Hexes)))
                        continue;
                    end
                    edgePoints = zeros(0, 3);
                    if isfield(out0, 'EdgePoints')
                        edgePoints = out0.EdgePoints;
                    end
                    hasWire = ~isempty(edgePoints);
                    obj.surfData_.(name) = struct('kind', 'volume', ...
                                                  'cellTypes', cellTypes, ...
                                                  'cells', cells, ...
                                                  'V0', vol0.Points, ...
                                                  'tets', vol0.Tets, ...
                                                  'hexes', vol0.Hexes, ...
                                                  'edgePoints', edgePoints);

                    if obj.Opts.mode.showUndeformed && hasWire
                        gName = ['ghost_' name 'Wire'];
                        gRgb = plotter.polyscope.utils.colorToRgb(obj.Opts.color.undeformedColor);
                        h = obj.registerWireframe_(name, edgePoints, gRgb, ...
                            obj.Opts.polyscope.edgeRadius * 0.5, ...
                            obj.Opts.color.undeformedAlpha, 'ghostWire');
                        if ~isempty(h), obj.handles_.(gName) = h; end
                    end

                    dName = obj.structName_(name, 'def');
                    dRgb = plotter.polyscope.utils.colorToRgb(obj.Opts.color.solidColor);
                    vm = obj.registerVolumeMesh_(dName, vol0.Points, vol0.Tets, vol0.Hexes, ...
                        dRgb, showSurf && ~wireframe);
                    if isempty(vm), continue; end
                    obj.handles_.(['def_' name]) = vm;

                    if hasWire
                        wName = ['def_' name 'Wire'];
                        wRgb = plotter.polyscope.utils.colorToRgb( ...
                            obj.Opts.unstructured.edgeColor);
                        h = obj.registerWireframe_(name, edgePoints, wRgb, ...
                            obj.Opts.polyscope.edgeRadius * 0.6, ...
                            obj.Opts.color.deformedAlpha, 'wire');
                        if ~isempty(h)
                            h.set_enabled(showSurf && showEdges && ~wireframe);
                            obj.handles_.(wName) = h;
                        end

                        fName = ['def_' name 'Frame'];
                        fRgb = plotter.polyscope.utils.colorToRgb(obj.Opts.color.solidColor);
                        fh = obj.registerWireframe_(name, edgePoints, fRgb, ...
                            obj.Opts.polyscope.edgeRadius, ...
                            obj.Opts.color.deformedAlpha, 'frame');
                        if ~isempty(fh)
                            fh.set_enabled(showSurf && wireframe);
                            obj.handles_.(fName) = fh;
                        end
                    end
                    continue;
                end
                out0 = plotter.utils.VTKElementTriangulator.triangulate( ...
                    obj.P0_, cellTypes, cells);
                if isempty(out0) || ~isfield(out0, 'Points') || isempty(out0.Points) || ...
                   ~isfield(out0, 'Triangles') || isempty(out0.Triangles)
                    continue;
                end
                edgePoints = zeros(0, 3);
                if isfield(out0, 'EdgePoints')
                    edgePoints = out0.EdgePoints;
                end
                hasWire = ~isempty(edgePoints);
                obj.surfData_.(name) = struct('cellTypes', cellTypes, ...
                                              'cells', cells, ...
                                              'V0', out0.Points, ...
                                              'F', out0.Triangles, ...
                                              'edgePoints', edgePoints);

                % Undeformed ghost as a wireframe, not as surface edges
                if obj.Opts.mode.showUndeformed && hasWire
                    gName = ['ghost_' name 'Wire'];
                    gRgb = plotter.polyscope.utils.colorToRgb(obj.Opts.color.undeformedColor);
                    h = obj.registerWireframe_(name, edgePoints, gRgb, ...
                        obj.Opts.polyscope.edgeRadius * 0.5, ...
                        obj.Opts.color.undeformedAlpha, 'ghostWire');
                    if ~isempty(h), obj.handles_.(gName) = h; end
                end

                dName = obj.structName_(name, 'def');
                dRgb = plotter.polyscope.utils.colorToRgb(obj.Opts.color.solidColor);
                dSm = ps.register_surface_mesh(dName, out0.Points, out0.Triangles, ...
                    'back_face_policy', obj.getOptField_(obj.Opts.polyscope, 'backFacePolicy', 'identical'));
                dSm.set_color(dRgb);
                dSm.set_material(obj.Opts.polyscope.surfaceMaterial);
                dSm.set_smooth_shade(obj.Opts.polyscope.surfaceSmoothShade);
                dSm.set_transparency(obj.Opts.color.deformedAlpha);
                dSm.set_edge_width(0);
                dSm.set_enabled(showSurf && ~wireframe);
                obj.handles_.(['def_' name]) = dSm;

                % Real face edges as a separate curve network
                if hasWire
                    wName = ['def_' name 'Wire'];
                    wRgb = plotter.polyscope.utils.colorToRgb( ...
                        obj.Opts.unstructured.edgeColor);
                    h = obj.registerWireframe_(name, edgePoints, wRgb, ...
                        obj.Opts.polyscope.edgeRadius * 0.6, ...
                        obj.Opts.color.deformedAlpha, 'wire');
                    if ~isempty(h)
                        h.set_enabled(showSurf && showEdges && ~wireframe);
                        obj.handles_.(wName) = h;
                    end

                    fName = ['def_' name 'Frame'];
                    fRgb = plotter.polyscope.utils.colorToRgb(obj.Opts.color.solidColor);
                    fh = obj.registerWireframe_(name, edgePoints, fRgb, ...
                        obj.Opts.polyscope.edgeRadius, ...
                        obj.Opts.color.deformedAlpha, 'frame');
                    if ~isempty(fh)
                        fh.set_enabled(showSurf && wireframe);
                        obj.handles_.(fName) = fh;
                    end
                end
            end
        end

        function registerNodeStructure_(obj)
            if ~obj.Opts.nodes.show || isempty(obj.P0_)
                return;
            end
            ps = obj.App.polyscopeHandle();
            name = obj.structName_('Nodes', 'def');
            rgb = plotter.polyscope.utils.colorToRgb(obj.Opts.color.solidColor);
            pc = ps.register_point_cloud(name, obj.P0_);
            pc.set_radius(obj.Opts.polyscope.nodeRadius, true);
            pc.set_color(rgb);
            pc.set_material(obj.Opts.polyscope.lineMaterial);
            pc.set_point_render_mode(obj.Opts.polyscope.pointRenderMode);
            obj.handles_.def_Nodes = pc;
        end

        function registerFixedStructure_(obj)
            if ~obj.Opts.fixed.show
                return;
            end
            [Pfixed, ~] = plotter.polyscope.ModelAdapter.fixedNodes(obj.ModelInfo);
            if isempty(Pfixed), return; end
            ps = obj.App.polyscopeHandle();
            name = obj.structName_('Fixed');
            rgb = plotter.polyscope.utils.colorToRgb(obj.Opts.fixed.color);
            pc = ps.register_point_cloud(name, Pfixed);
            pc.set_radius(obj.Opts.polyscope.nodeRadius * 1.5, true);
            pc.set_color(rgb);
            pc.set_material(obj.Opts.polyscope.lineMaterial);
            pc.set_point_render_mode(obj.Opts.polyscope.pointRenderMode);
            obj.handles_.Fixed = pc;
        end

        function registerMPStructure_(obj)
            if ~obj.Opts.mpConstraint.show
                return;
            end
            edges = plotter.polyscope.ModelAdapter.mpConstraintEdges(obj.ModelInfo);
            if isempty(edges), return; end
            ps = obj.App.polyscopeHandle();
            name = obj.structName_('MPConstraint', 'def');
            rgb = plotter.polyscope.utils.colorToRgb(obj.Opts.mpConstraint.color);
            cn = ps.register_curve_network(name, obj.P0_, edges);
            cn.set_color(rgb);
            cn.set_radius(obj.Opts.polyscope.edgeRadius * 0.8, true);
            cn.set_transparency(obj.Opts.polyscope.transparency);
            cn.set_material(obj.Opts.polyscope.lineMaterial);
            obj.handles_.def_MPConstraint = cn;
        end

        function h = registerWireframe_(obj, base, edgePoints, rgb, radius, alpha, prefix)
            h = [];
            if isempty(edgePoints), return; end
            [nodes, edges] = plotter.polyscope.ModelAdapter.edgePointsToCurveNetwork(edgePoints);
            if isempty(nodes) || isempty(edges), return; end
            ps = obj.App.polyscopeHandle();
            name = obj.structName_(base, prefix);
            cn = ps.register_curve_network(name, nodes, edges);
            cn.set_color(rgb);
            cn.set_radius(radius, true);
            cn.set_transparency(alpha);
            cn.set_material(obj.Opts.polyscope.lineMaterial);
            h = cn;
        end

        function vm = registerVolumeMesh_(obj, name, V, tets, hexes, rgb, enabled)
            vm = [];
            if isempty(V), return; end
            ps = obj.App.polyscopeHandle();
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
            vm.set_transparency(obj.Opts.color.deformedAlpha);
            try
                vm.set_edge_color(plotter.polyscope.utils.colorToRgb(obj.Opts.unstructured.edgeColor));
                vm.set_edge_width(0);
            catch
            end
            vm.set_enabled(enabled);
        end

        function registerElementClassStructures_(obj)
            C = obj.elementClasses_();
            classNames = fieldnames(C);
            if isempty(classNames), return; end
            ps = obj.App.polyscopeHandle();
            gRgb = plotter.polyscope.utils.colorToRgb(obj.Opts.color.undeformedColor);
            for k = 1:numel(classNames)
                name = classNames{k};
                S = C.(name);
                if ~isstruct(S) || ~isfield(S, 'Cells') || isempty(S.Cells) || ...
                   ~isfield(S, 'CellTypes') || isempty(S.CellTypes)
                    continue;
                end
                cells = double(S.Cells);
                cellTypes = double(S.CellTypes(:));

                if obj.isLineClass_(cellTypes)
                    if ~obj.Opts.line.show, continue; end
                    rgb = plotter.polyscope.utils.colorToRgb(obj.Opts.color.lineColor);
                    edges = plotter.polyscope.ModelAdapter.cellsToLineEdges( ...
                        cells, obj.ModelInfo);
                    if isempty(edges), continue; end

                    if obj.Opts.mode.showUndeformed
                        gName = obj.structName_(name, 'ghost');
                        gCn = ps.register_curve_network(gName, obj.P0_, edges);
                        gCn.set_color(gRgb);
                        gCn.set_radius(obj.Opts.polyscope.edgeRadius * 0.8, true);
                        gCn.set_transparency(obj.Opts.color.undeformedAlpha);
                        gCn.set_material(obj.Opts.polyscope.lineMaterial);
                        obj.handles_.(['ghost_' name]) = gCn;
                    end

                    dName = obj.structName_(name, 'def');
                    dCn = ps.register_curve_network(dName, obj.P0_, edges);
                    dCn.set_color(rgb);
                    dCn.set_radius(obj.Opts.polyscope.edgeRadius, true);
                    dCn.set_transparency(obj.Opts.color.deformedAlpha);
                    dCn.set_material(obj.Opts.polyscope.lineMaterial);
                    obj.handles_.(['def_' name]) = dCn;
                    obj.classData_.(name) = struct('kind', 'line', 'edges', edges);
                elseif obj.isVolumeClass_(cellTypes)
                    rgb = plotter.polyscope.utils.colorToRgb(obj.Opts.color.solidColor);
                    vol0 = plotter.utils.VTKElementTriangulator.volumize( ...
                        obj.P0_, cellTypes, cells);
                    out0 = plotter.utils.VTKElementTriangulator.triangulate( ...
                        obj.P0_, cellTypes, cells);
                    if isempty(vol0) || ~isfield(vol0, 'Points') || isempty(vol0.Points) || ...
                       ((~isfield(vol0, 'Tets') || isempty(vol0.Tets)) && ...
                        (~isfield(vol0, 'Hexes') || isempty(vol0.Hexes)))
                        continue;
                    end
                    edgePoints = zeros(0, 3);
                    if isfield(out0, 'EdgePoints')
                        edgePoints = out0.EdgePoints;
                    end
                    hasWire = ~isempty(edgePoints);
                    wireframe = obj.getOptField_(obj.Opts.unstructured, 'wireframe', false);
                    showSurf = obj.Opts.unstructured.show;
                    showEdges = obj.Opts.unstructured.showEdges;

                    if obj.Opts.mode.showUndeformed && hasWire
                        gName = ['ghost_' name 'Wire'];
                        h = obj.registerWireframe_(name, edgePoints, gRgb, ...
                            obj.Opts.polyscope.edgeRadius * 0.5, ...
                            obj.Opts.color.undeformedAlpha, 'ghostWire');
                        if ~isempty(h), obj.handles_.(gName) = h; end
                    end

                    dName = obj.structName_(name, 'def');
                    vm = obj.registerVolumeMesh_(dName, vol0.Points, vol0.Tets, vol0.Hexes, ...
                        rgb, showSurf && ~wireframe);
                    if isempty(vm), continue; end
                    obj.handles_.(['def_' name]) = vm;

                    if hasWire
                        wName = ['def_' name 'Wire'];
                        wRgb = plotter.polyscope.utils.colorToRgb( ...
                            obj.Opts.unstructured.edgeColor);
                        h = obj.registerWireframe_(name, edgePoints, wRgb, ...
                            obj.Opts.polyscope.edgeRadius * 0.6, ...
                            obj.Opts.color.deformedAlpha, 'wire');
                        if ~isempty(h)
                            h.set_enabled(showSurf && showEdges && ~wireframe);
                            obj.handles_.(wName) = h;
                        end

                        fName = ['def_' name 'Frame'];
                        fRgb = plotter.polyscope.utils.colorToRgb(obj.Opts.color.solidColor);
                        fh = obj.registerWireframe_(name, edgePoints, fRgb, ...
                            obj.Opts.polyscope.edgeRadius, ...
                            obj.Opts.color.deformedAlpha, 'frame');
                        if ~isempty(fh)
                            fh.set_enabled(showSurf && wireframe);
                            obj.handles_.(fName) = fh;
                        end
                    end

                    obj.classData_.(name) = struct('kind', 'volume', ...
                        'cellTypes', cellTypes, 'cells', cells, ...
                        'V0', vol0.Points, 'tets', vol0.Tets, 'hexes', vol0.Hexes, ...
                        'edgePoints', edgePoints);
                else
                    rgb = plotter.polyscope.utils.colorToRgb(obj.Opts.color.solidColor);
                    out0 = plotter.utils.VTKElementTriangulator.triangulate( ...
                        obj.P0_, cellTypes, cells);
                    if isempty(out0) || ~isfield(out0, 'Points') || isempty(out0.Points) || ...
                       ~isfield(out0, 'Triangles') || isempty(out0.Triangles)
                        continue;
                    end
                    F = out0.Triangles;
                    edgePoints = zeros(0, 3);
                    if isfield(out0, 'EdgePoints')
                        edgePoints = out0.EdgePoints;
                    end
                    hasWire = ~isempty(edgePoints);
                    wireframe = obj.getOptField_(obj.Opts.unstructured, 'wireframe', false);
                    showSurf = obj.Opts.unstructured.show;
                    showEdges = obj.Opts.unstructured.showEdges;

                    % Undeformed ghost as a wireframe
                    if obj.Opts.mode.showUndeformed && hasWire
                        gName = ['ghost_' name 'Wire'];
                        h = obj.registerWireframe_(name, edgePoints, gRgb, ...
                            obj.Opts.polyscope.edgeRadius * 0.5, ...
                            obj.Opts.color.undeformedAlpha, 'ghostWire');
                        if ~isempty(h), obj.handles_.(gName) = h; end
                    end

                    dName = obj.structName_(name, 'def');
                    dSm = ps.register_surface_mesh(dName, out0.Points, F, ...
                        'back_face_policy', obj.getOptField_(obj.Opts.polyscope, 'backFacePolicy', 'identical'));
                    dSm.set_color(rgb);
                    dSm.set_material(obj.Opts.polyscope.surfaceMaterial);
                    dSm.set_smooth_shade(obj.Opts.polyscope.surfaceSmoothShade);
                    dSm.set_transparency(obj.Opts.color.deformedAlpha);
                    dSm.set_edge_width(0);
                    dSm.set_enabled(showSurf && ~wireframe);
                    obj.handles_.(['def_' name]) = dSm;

                    % Real face edges as a separate curve network
                    if hasWire
                        wName = ['def_' name 'Wire'];
                        wRgb = plotter.polyscope.utils.colorToRgb( ...
                            obj.Opts.unstructured.edgeColor);
                        h = obj.registerWireframe_(name, edgePoints, wRgb, ...
                            obj.Opts.polyscope.edgeRadius * 0.6, ...
                            obj.Opts.color.deformedAlpha, 'wire');
                        if ~isempty(h)
                            h.set_enabled(showSurf && showEdges && ~wireframe);
                            obj.handles_.(wName) = h;
                        end

                        fName = ['def_' name 'Frame'];
                        fRgb = plotter.polyscope.utils.colorToRgb(obj.Opts.color.solidColor);
                        fh = obj.registerWireframe_(name, edgePoints, fRgb, ...
                            obj.Opts.polyscope.edgeRadius, ...
                            obj.Opts.color.deformedAlpha, 'frame');
                        if ~isempty(fh)
                            fh.set_enabled(showSurf && wireframe);
                            obj.handles_.(fName) = fh;
                        end
                    end

                    obj.classData_.(name) = struct('kind', 'surface', ...
                        'cellTypes', cellTypes, 'cells', cells, ...
                        'V0', out0.Points, 'F', F, ...
                        'edgePoints', edgePoints);
                end
            end
        end

        function updateStructures_(obj, Pdef, S)
            qargs = obj.scalarOpts_();
            cbArgs = obj.colorbarArgs_();
            cbAdded = false;

            if obj.hasElementClasses_()
                classNames = fieldnames(obj.classData_);
                for k = 1:numel(classNames)
                    name = classNames{k};
                    hName = ['def_' name];
                    if ~isfield(obj.handles_, hName), continue; end
                    data = obj.classData_.(name);
                    if strcmp(data.kind, 'line')
                        cn = obj.handles_.(hName);
                        cn.update_node_positions(Pdef);
                        if ~cbAdded && ~isempty(cbArgs)
                            cn.add_node_scalar_quantity('mode', S, qargs{:}, cbArgs{:});
                            cbAdded = true;
                        else
                            cn.add_node_scalar_quantity('mode', S, qargs{:});
                        end
                    elseif strcmp(data.kind, 'volume')
                        vm = obj.handles_.(hName);
                        vm.update_vertex_positions(Pdef);
                        if ~cbAdded && ~isempty(cbArgs)
                            vm.add_vertex_scalar_quantity('mode', S, qargs{:}, cbArgs{:});
                            cbAdded = true;
                        else
                            vm.add_vertex_scalar_quantity('mode', S, qargs{:});
                        end
                        out = plotter.utils.VTKElementTriangulator.triangulate( ...
                            Pdef, data.cellTypes, data.cells, 'Scalars', S);
                        edgeScalars = [];
                        if isfield(out, 'EdgeScalars')
                            edgeScalars = out.EdgeScalars;
                        end
                        obj.updateWirePositions_([hName 'Wire'], out.EdgePoints);
                        cbAdded = obj.updateWireScalar_([hName 'Frame'], ...
                            out.EdgePoints, edgeScalars, qargs, cbArgs, cbAdded);
                    else
                        out = plotter.utils.VTKElementTriangulator.triangulate( ...
                            Pdef, data.cellTypes, data.cells, 'Scalars', S);
                        if isempty(out) || ~isfield(out, 'Points') || isempty(out.Points)
                            continue;
                        end
                        sm = obj.handles_.(hName);
                        sm.update_vertex_positions(out.Points);
                        if isfield(out, 'PointScalars')
                            if ~cbAdded && ~isempty(cbArgs)
                                sm.add_vertex_scalar_quantity('mode', out.PointScalars, qargs{:}, cbArgs{:});
                                cbAdded = true;
                            else
                                sm.add_vertex_scalar_quantity('mode', out.PointScalars, qargs{:});
                            end
                        end
                        edgeScalars = [];
                        if isfield(out, 'EdgeScalars')
                            edgeScalars = out.EdgeScalars;
                        end
                        obj.updateWirePositions_([hName 'Wire'], out.EdgePoints);
                        cbAdded = obj.updateWireScalar_([hName 'Frame'], ...
                            out.EdgePoints, edgeScalars, qargs, cbArgs, cbAdded);
                    end
                end
            else
                famNames = plotter.polyscope.ModelAdapter.lineFamilyNames();
                for k = 1:numel(famNames)
                    name = famNames{k};
                    hName = ['def_' name];
                    if ~isfield(obj.handles_, hName), continue; end
                    cn = obj.handles_.(hName);
                    cn.update_node_positions(Pdef);
                    if ~cbAdded && ~isempty(cbArgs)
                        cn.add_node_scalar_quantity('mode', S, qargs{:}, cbArgs{:});
                        cbAdded = true;
                    else
                        cn.add_node_scalar_quantity('mode', S, qargs{:});
                    end
                end

                surfNames = fieldnames(obj.surfData_);
                for k = 1:numel(surfNames)
                    name = surfNames{k};
                    hName = ['def_' name];
                    if ~isfield(obj.handles_, hName), continue; end
                    data = obj.surfData_.(name);
                    out = plotter.utils.VTKElementTriangulator.triangulate( ...
                        Pdef, data.cellTypes, data.cells, 'Scalars', S);
                    if isempty(out) || ~isfield(out, 'Points') || isempty(out.Points)
                        continue;
                    end
                    if isfield(data, 'kind') && strcmp(data.kind, 'volume')
                        vm = obj.handles_.(hName);
                        vm.update_vertex_positions(Pdef);
                        if ~cbAdded && ~isempty(cbArgs)
                            vm.add_vertex_scalar_quantity('mode', S, qargs{:}, cbArgs{:});
                            cbAdded = true;
                        else
                            vm.add_vertex_scalar_quantity('mode', S, qargs{:});
                        end
                    else
                        sm = obj.handles_.(hName);
                        sm.update_vertex_positions(out.Points);
                        if isfield(out, 'PointScalars')
                            if ~cbAdded && ~isempty(cbArgs)
                                sm.add_vertex_scalar_quantity('mode', out.PointScalars, qargs{:}, cbArgs{:});
                                cbAdded = true;
                            else
                                sm.add_vertex_scalar_quantity('mode', out.PointScalars, qargs{:});
                            end
                        end
                    end
                    edgeScalars = [];
                    if isfield(out, 'EdgeScalars')
                        edgeScalars = out.EdgeScalars;
                    end
                    obj.updateWirePositions_([hName 'Wire'], out.EdgePoints);
                    cbAdded = obj.updateWireScalar_([hName 'Frame'], ...
                        out.EdgePoints, edgeScalars, qargs, cbArgs, cbAdded);
                end
            end

            if isfield(obj.handles_, 'def_Nodes')
                pc = obj.handles_.def_Nodes;
                pc.update_point_positions(Pdef);
                if ~cbAdded && ~isempty(cbArgs)
                    pc.add_scalar_quantity('mode', S, qargs{:}, cbArgs{:});
                else
                    pc.add_scalar_quantity('mode', S, qargs{:});
                end
            end

            if isfield(obj.handles_, 'def_MPConstraint')
                obj.handles_.def_MPConstraint.update_node_positions(Pdef);
            end
        end

        function updateWirePositions_(obj, wireName, edgePoints)
            if ~isfield(obj.handles_, wireName), return; end
            if isempty(edgePoints), return; end
            valid = ~any(isnan(edgePoints), 2);
            if ~any(valid), return; end
            obj.handles_.(wireName).update_node_positions(edgePoints(valid, :));
        end

        function cbAdded = updateWireScalar_(obj, wireName, edgePoints, edgeScalars, qargs, cbArgs, cbAdded)
            if ~isfield(obj.handles_, wireName), return; end
            if isempty(edgePoints), return; end
            valid = ~any(isnan(edgePoints), 2);
            if ~any(valid), return; end
            cn = obj.handles_.(wireName);
            cn.update_node_positions(edgePoints(valid, :));
            if ~isempty(edgeScalars) && numel(edgeScalars) >= size(edgePoints, 1)
                sVals = edgeScalars(valid);
                if ~cbAdded && ~isempty(cbArgs)
                    cn.add_node_scalar_quantity('mode', sVals, qargs{:}, cbArgs{:});
                    cbAdded = true;
                else
                    cn.add_node_scalar_quantity('mode', sVals, qargs{:});
                end
            end
        end

        function applySurfaceVisibility_(obj)
            if isempty(fieldnames(obj.handles_)), return; end
            wireframe = obj.getOptField_(obj.Opts.unstructured, 'wireframe', false);
            showSurf = obj.Opts.unstructured.show;
            showEdges = obj.Opts.unstructured.showEdges;
            if obj.hasElementClasses_()
                names = fieldnames(obj.classData_);
                for k = 1:numel(names)
                    name = names{k};
                    data = obj.classData_.(name);
                    if ~(strcmp(data.kind, 'surface') || strcmp(data.kind, 'volume')), continue; end
                    hName = ['def_' name];
                    obj.setHandleEnabled_(hName, showSurf && ~wireframe);
                    obj.setHandleEnabled_([hName 'Wire'], showSurf && showEdges && ~wireframe);
                    obj.setHandleEnabled_([hName 'Frame'], showSurf && wireframe);
                end
            else
                names = fieldnames(obj.surfData_);
                for k = 1:numel(names)
                    name = names{k};
                    hName = ['def_' name];
                    obj.setHandleEnabled_(hName, showSurf && ~wireframe);
                    obj.setHandleEnabled_([hName 'Wire'], showSurf && showEdges && ~wireframe);
                    obj.setHandleEnabled_([hName 'Frame'], showSurf && wireframe);
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

        function needsRebuild = applyVisibility_(obj)
            needsRebuild = false;
            if obj.Opts.mode.showUndeformed
                names = fieldnames(obj.handles_);
                hasGhost = any(startsWith(names, 'ghost_'));
                if ~hasGhost
                    needsRebuild = true;
                else
                    for i = 1:numel(names)
                        if startsWith(names{i}, 'ghost_')
                            obj.handles_.(names{i}).set_enabled(true);
                        end
                    end
                end
            else
                names = fieldnames(obj.handles_);
                for i = 1:numel(names)
                    if startsWith(names{i}, 'ghost_')
                        obj.handles_.(names{i}).set_enabled(false);
                    end
                end
            end

            lineNames = plotter.polyscope.ModelAdapter.lineFamilyNames();
            hasLine = false;
            for k = 1:numel(lineNames)
                hName = ['def_' lineNames{k}];
                if isfield(obj.handles_, hName)
                    hasLine = true;
                    obj.handles_.(hName).set_enabled(obj.Opts.line.show);
                end
            end
            if obj.Opts.line.show && ~hasLine
                needsRebuild = true;
            end

            if obj.Opts.nodes.show && ~isfield(obj.handles_, 'def_Nodes')
                needsRebuild = true;
            elseif isfield(obj.handles_, 'def_Nodes')
                obj.handles_.def_Nodes.set_enabled(obj.Opts.nodes.show);
            end

            if obj.Opts.fixed.show && ~isfield(obj.handles_, 'Fixed')
                needsRebuild = true;
            elseif isfield(obj.handles_, 'Fixed')
                obj.handles_.Fixed.set_enabled(obj.Opts.fixed.show);
            end

            if obj.Opts.mpConstraint.show && ~isfield(obj.handles_, 'def_MPConstraint')
                needsRebuild = true;
            elseif isfield(obj.handles_, 'def_MPConstraint')
                obj.handles_.def_MPConstraint.set_enabled(obj.Opts.mpConstraint.show);
            end
        end

        function applyStyle_(obj)
            names = fieldnames(obj.handles_);
            for i = 1:numel(names)
                nm = names{i};
                h = obj.handles_.(nm);
                try
                    if startsWith(nm, 'ghost_')
                        h.set_transparency(obj.Opts.color.undeformedAlpha);
                        h.set_color(obj.asRgb_(obj.Opts.color.undeformedColor));
                    else
                        h.set_transparency(obj.Opts.color.deformedAlpha);
                    end
                    if isa(h, 'polyscope.PointCloud')
                        h.set_radius(obj.Opts.polyscope.nodeRadius, true);
                    elseif isa(h, 'polyscope.CurveNetwork')
                        h.set_radius(obj.Opts.polyscope.edgeRadius, true);
                    end
                catch
                end
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

        function opts = scalarOpts_(obj)
            idx = obj.currentIdx_;
            [Uraw, ~] = obj.computeModeDisplacement_(idx);
            S = obj.computeScalarField_(Uraw);
            S = S(isfinite(S));
            if ~isempty(S)
                smin = double(min(S)); smax = double(max(S));
                if smin == smax, smax = smin + 1; end
            else
                smin = 0; smax = 1;
            end
            if ~isempty(obj.Opts.color.clim) && numel(obj.Opts.color.clim) == 2
                smin = obj.Opts.color.clim(1);
                smax = obj.Opts.color.clim(2);
            end

            cmap = obj.Opts.polyscope.scalarColorMap;
            if ischar(obj.Opts.color.colormap) || isstring(obj.Opts.color.colormap)
                cmap = lower(char(string(obj.Opts.color.colormap)));
            end

            comp = lower(char(string(obj.Opts.mode.component)));
            if ismember(comp, {'magnitude', 'mag'})
                datatype = 'standard';
            else
                datatype = 'symmetric';
            end

            opts = {'color_map', cmap, ...
                    'datatype', datatype, ...
                    'map_range', [smin, smax], ...
                    'enabled', obj.Opts.color.useColormap};
        end

        function resolveColorbarLocation_(obj)
            loc = obj.getOptField_(obj.Opts.polyscope, 'onscreenColorbarLocation', []);
            if ~isempty(loc) && numel(loc) == 2 && all(isfinite(loc))
                obj.gui_.onscreenColorbarLocation = double(loc(:).');
                return;
            end
            try
                ws = obj.safeWindowSize_();
                if numel(ws) >= 2 && all(isfinite(ws(1:2))) && all(ws(1:2) > 0)
                    % Place horizontally centered near the top, away from side panels
                    loc = [max(20, round(ws(1) / 2) - 60), 40];
                else
                    loc = [400, 40];
                end
            catch
                loc = [400, 40];
            end
            obj.Opts.polyscope.onscreenColorbarLocation = loc;
            obj.gui_.onscreenColorbarLocation = loc;
        end

        function [Uraw, scale] = computeModeDisplacement_(obj, idx)
            Uraw = zeros(size(obj.P0_));
            scale = 1;
            if ~isfield(obj.EigenInfo, 'EigenVectors') || ...
               ~isstruct(obj.EigenInfo.EigenVectors) || ...
               ~isfield(obj.EigenInfo.EigenVectors, 'data') || ...
               isempty(obj.EigenInfo.EigenVectors.data)
                return;
            end
            data = double(obj.EigenInfo.EigenVectors.data);
            if ndims(data) < 3 %#ok<ISMAT>
                U = data(idx, :);
            else
                U = squeeze(data(idx, :, :));
            end
            U = plotter.polyscope.ModelAdapter.pad3(U);
            Uraw = obj.alignEigenRowsToModel_(U);
            umax = max(sqrt(sum(U.^2, 2)), [], 'omitnan');
            if isempty(umax) || ~isfinite(umax) || umax <= 0
                umax = 1;
            end
            if obj.Opts.mode.autoScale
                scale = obj.L_ / (10 * umax) * obj.Opts.mode.scale;
            else
                scale = obj.Opts.mode.scale;
            end
        end

        function S = computeScalarField_(obj, U)
            comp = lower(char(string(obj.Opts.mode.component)));
            switch comp
                case {'magnitude', 'mag'}
                    S = sqrt(sum(U(:, 1:min(3, size(U, 2))).^2, 2));
                case {'x', 'ux'}
                    S = U(:, 1);
                case {'y', 'uy'}
                    S = obj.safeCol_(U, 2);
                case {'z', 'uz'}
                    S = obj.safeCol_(U, 3);
                otherwise
                    S = sqrt(sum(U(:, 1:min(3, size(U, 2))).^2, 2));
            end
            if obj.Opts.scalar.useAbsoluteForComponent && ...
               ~ismember(comp, {'magnitude', 'mag'})
                S = abs(S);
            end
            S = double(S(:));
        end

        function col = safeCol_(~, U, j)
            if size(U, 2) >= j
                col = U(:, j);
            else
                col = zeros(size(U, 1), 1);
            end
        end

        function tags = collectModeTags_(obj)
            if isfield(obj.EigenInfo, 'ModeTags') && ~isempty(obj.EigenInfo.ModeTags)
                tags = double(obj.EigenInfo.ModeTags(:));
            elseif isfield(obj.EigenInfo, 'EigenVectors') && ...
                   isfield(obj.EigenInfo.EigenVectors, 'data') && ...
                   ~isempty(obj.EigenInfo.EigenVectors.data)
                tags = (1:size(obj.EigenInfo.EigenVectors.data, 1))';
            else
                tags = 1;
            end
        end

        function Umodel = alignEigenRowsToModel_(obj, U)
            Umodel = zeros(size(obj.P0_));
            if isempty(U), return; end
            U = plotter.polyscope.ModelAdapter.pad3(U);
            nModel = size(obj.P0_, 1);
            if size(U, 1) == nModel
                Umodel = U(1:nModel, :);
                return;
            end
            if isfield(obj.EigenInfo, 'EigenVectors') && ...
               isfield(obj.EigenInfo.EigenVectors, 'nodeTags') && ...
               ~isempty(obj.EigenInfo.EigenVectors.nodeTags)
                modelTags = plotter.polyscope.ModelAdapter.nodeTags(obj.ModelInfo);
                eigTags = double(obj.EigenInfo.EigenVectors.nodeTags(:));
                idx = plotter.polyscope.ModelAdapter.tagsToIdx(eigTags, modelTags);
                n = min(size(U, 1), numel(idx));
                valid = idx(1:n) >= 1 & idx(1:n) <= nModel;
                Umodel(idx(valid), :) = U(valid, :);
            end
        end

        function idx = resolveModeIndex_(obj, modeTag)
            modeTag = double(modeTag);
            idx = find(obj.modeTags_ == modeTag, 1, 'first');
            if isempty(idx)
                if modeTag >= 1 && modeTag <= numel(obj.modeTags_) && mod(modeTag, 1) == 0
                    idx = modeTag;
                else
                    error('plotter:polyscope:plotEigen:ModeNotFound', ...
                        'Cannot find requested modeTag %g.', modeTag);
                end
            end
        end

        function updateProgramName_(obj)
            tag = obj.modeTags_(obj.currentIdx_);
            titleStr = sprintf('Mode %g', tag);
            if isfield(obj.EigenInfo, 'ModalProps') && ...
               isfield(obj.EigenInfo.ModalProps, 'raw') && ...
               isfield(obj.EigenInfo.ModalProps.raw, 'eigenFrequency')
                freqs = double(obj.EigenInfo.ModalProps.raw.eigenFrequency(:));
                if numel(freqs) >= obj.currentIdx_
                    f = freqs(obj.currentIdx_);
                    if isfinite(f) && f > 0
                        titleStr = sprintf('%s | T = %.6g s', titleStr, 1/f);
                    end
                end
            end
            titleStr = ['OpenSeesMatlab | ' titleStr ' - by Yexiang Yan'];
            obj.App.polyscopeHandle().set_program_name(titleStr);
        end

        function labels = modeLabels_(obj)
            tags = obj.modeTags_;
            labels = cell(numel(tags), 1);
            freqs = [];
            if isfield(obj.EigenInfo, 'ModalProps') && ...
               isfield(obj.EigenInfo.ModalProps, 'raw') && ...
               isfield(obj.EigenInfo.ModalProps.raw, 'eigenFrequency')
                freqs = double(obj.EigenInfo.ModalProps.raw.eigenFrequency(:));
            end
            for i = 1:numel(tags)
                labels{i} = sprintf('%g', tags(i));
                if numel(freqs) >= i && isfinite(freqs(i)) && freqs(i) > 0
                    labels{i} = sprintf('%g  (T %.4g s)', tags(i), 1/freqs(i));
                end
            end
        end

        function lines = modeSummary_(obj, modeTag)
            tags = obj.modeTags_;
            idx = find(abs(tags - double(modeTag)) < 1e-12, 1, 'first');
            if isempty(idx) && double(modeTag) >= 1 && double(modeTag) <= numel(tags)
                idx = double(modeTag);
            end

            lines = {};
            lines{end+1} = sprintf('Available modes: %d', numel(tags));
            lines{end+1} = sprintf('Selected mode: %g', double(modeTag));

            if ~isempty(idx) && isfield(obj.EigenInfo, 'ModalProps') && ...
               isfield(obj.EigenInfo.ModalProps, 'raw')
                raw = obj.EigenInfo.ModalProps.raw;

                freq = obj.modalValue_(raw, 'eigenFrequency', idx);
                period = obj.modalValue_(raw, 'eigenPeriod', idx);
                lambda = obj.modalValue_(raw, 'eigenLambda', idx);
                omega = obj.modalValue_(raw, 'eigenOmega', idx);

                if isfinite(freq)
                    lines{end+1} = sprintf('Frequency: %.6g Hz', freq);
                end
                if isfinite(period)
                    lines{end+1} = sprintf('Period: %.6g s', period);
                elseif isfinite(freq) && freq > 0
                    lines{end+1} = sprintf('Period: %.6g s', 1/freq);
                end
                if isfinite(lambda)
                    lines{end+1} = sprintf('Eigenvalue lambda: %.6g', lambda);
                end
                if isfinite(omega)
                    lines{end+1} = sprintf('Omega: %.6g rad/s', omega);
                end

                [massRatio, hasMass] = obj.directionalValues_(raw, 'partiMassRatios', idx, {'MX','MY','MZ'});
                if hasMass
                    lines{end+1} = sprintf('Mass ratio: %s', ...
                        obj.formatDirectional_({'MX','MY','MZ'}, massRatio));
                end
                [massCumu, hasCumu] = obj.directionalValues_(raw, 'partiMassRatiosCumu', idx, {'MX','MY','MZ'});
                if hasCumu
                    lines{end+1} = sprintf('Cumulative: %s', ...
                        obj.formatDirectional_({'MX','MY','MZ'}, massCumu));
                end
                [rotRatio, hasRot] = obj.directionalValues_(raw, 'partiMassRatios', idx, {'RMX','RMY','RMZ'});
                if hasRot
                    lines{end+1} = sprintf('Rot ratio: %s', ...
                        obj.formatDirectional_({'RMX','RMY','RMZ'}, rotRatio));
                end
                [rotCumu, hasRotCumu] = obj.directionalValues_(raw, 'partiMassRatiosCumu', idx, {'RMX','RMY','RMZ'});
                if hasRotCumu
                    lines{end+1} = sprintf('Rot cumulative: %s', ...
                        obj.formatDirectional_({'RMX','RMY','RMZ'}, rotCumu));
                end
            end
            if isempty(idx)
                lines{end+1} = 'Selected mode was not found in eigenInfo.ModeTags.';
            end
        end

        function value = modalValue_(~, raw, fieldName, idx)
            value = NaN;
            if isfield(raw, fieldName) && numel(raw.(fieldName)) >= idx
                vals = double(raw.(fieldName)(:));
                value = vals(idx);
            end
        end

        function [values, hasAny] = directionalValues_(obj, raw, prefix, idx, dirs)
            values = nan(1, numel(dirs));
            for i = 1:numel(dirs)
                values(i) = obj.modalValue_(raw, [prefix dirs{i}], idx);
            end
            hasAny = any(isfinite(values));
        end

        function txt = formatDirectional_(~, dirs, values)
            parts = {};
            for i = 1:numel(dirs)
                if isfinite(values(i))
                    parts{end+1} = sprintf('%s %.4g%%', dirs{i}, values(i)); %#ok<AGROW>
                end
            end
            if isempty(parts)
                txt = '';
            else
                txt = strjoin(parts, ', ');
            end
        end

    end

    methods (Access = public)

        function guiCallback_(obj)
            try
                GB = plotter.polyscope.GuiBuilder;
                ws = obj.safeWindowSize_();
                panelW = 340;
                panelH = max(420, ws(2));
                GB.begin('Mode controls', [max(0, ws(1) - panelW), 0], [panelW, panelH]);

                GB.header('Eigenmodes');

                needsRebuild = false;
                needsSetMode = false;
                sliceDirty = false;

                components = {'magnitude', 'ux', 'uy', 'uz'};
                views = obj.viewNames_();
                cmapNames = obj.colormapNames_();

                % Mode
                labels = obj.modeLabels_();
                newIdx = GB.combo('Mode', obj.gui_.modeIdx, labels);
                if newIdx ~= obj.gui_.modeIdx
                    obj.gui_.modeIdx = newIdx;
                    needsSetMode = true;
                end

                % View preset
                newView = GB.combo('View', obj.gui_.viewIdx, views);
                if newView ~= obj.gui_.viewIdx
                    obj.gui_.viewIdx = newView;
                    obj.setCameraView_(views{newView});
                end

                % Component
                newComp = GB.combo('Component', obj.gui_.compIdx, components);
                if newComp ~= obj.gui_.compIdx
                    obj.gui_.compIdx = newComp;
                    obj.Opts.mode.component = components{newComp};
                    needsSetMode = true;
                end

                % Toggles
                tf = GB.checkbox('Auto scale', obj.gui_.autoScale);
                if tf ~= obj.gui_.autoScale
                    obj.gui_.autoScale = tf;
                    obj.Opts.mode.autoScale = tf;
                    needsSetMode = true;
                end
                tf = GB.checkbox('Show undeformed', obj.gui_.showUndeformed);
                if tf ~= obj.gui_.showUndeformed
                    obj.gui_.showUndeformed = tf;
                    obj.Opts.mode.showUndeformed = tf;
                    needsRebuild = needsRebuild || obj.applyVisibility_();
                end
                tf = GB.checkbox('Use colormap', obj.gui_.useColormap);
                if tf ~= obj.gui_.useColormap
                    obj.gui_.useColormap = tf;
                    obj.Opts.color.useColormap = tf;
                    needsSetMode = true;
                end
                tf = GB.checkbox('Wireframe mode', obj.gui_.wireframe);
                if tf ~= obj.gui_.wireframe
                    obj.gui_.wireframe = tf;
                    obj.Opts.unstructured.wireframe = tf;
                    obj.applySurfaceVisibility_();
                end
                tf = GB.checkbox('Show axes', obj.gui_.showScreenAxes);
                if tf ~= obj.gui_.showScreenAxes
                    obj.gui_.showScreenAxes = tf;
                    obj.Opts.polyscope.showScreenAxes = tf;
                    obj.updateScreenAxes3D_();
                end
                tf = GB.checkbox('Show mode info', obj.gui_.showModeInfo);
                if tf ~= obj.gui_.showModeInfo
                    obj.gui_.showModeInfo = tf;
                    obj.Opts.polyscope.showModelInfo = tf;
                end

                GB.separator();
                GB.subtitle('Geometry');
                tf = GB.checkbox('Lines', obj.gui_.showLines);
                if tf ~= obj.gui_.showLines
                    obj.gui_.showLines = tf;
                    obj.Opts.line.show = tf;
                    needsRebuild = needsRebuild || obj.applyVisibility_();
                end
                tf = GB.checkbox('Surfaces', obj.gui_.showSurfaces);
                if tf ~= obj.gui_.showSurfaces
                    obj.gui_.showSurfaces = tf;
                    obj.Opts.unstructured.show = tf;
                    obj.applySurfaceVisibility_();
                end
                tf = GB.checkbox('Surface edges', obj.gui_.showSurfaceEdges);
                if tf ~= obj.gui_.showSurfaceEdges
                    obj.gui_.showSurfaceEdges = tf;
                    obj.Opts.unstructured.showEdges = tf;
                    obj.applySurfaceVisibility_();
                end
                tf = GB.checkbox('Nodes', obj.gui_.showNodes);
                if tf ~= obj.gui_.showNodes
                    obj.gui_.showNodes = tf;
                    obj.Opts.nodes.show = tf;
                    needsRebuild = needsRebuild || obj.applyVisibility_();
                end
                tf = GB.checkbox('Fixed nodes', obj.gui_.showFixed);
                if tf ~= obj.gui_.showFixed
                    obj.gui_.showFixed = tf;
                    obj.Opts.fixed.show = tf;
                    needsRebuild = needsRebuild || obj.applyVisibility_();
                end
                tf = GB.checkbox('MP constraints', obj.gui_.showMP);
                if tf ~= obj.gui_.showMP
                    obj.gui_.showMP = tf;
                    obj.Opts.mpConstraint.show = tf;
                    needsRebuild = needsRebuild || obj.applyVisibility_();
                end

                obj.drawSsaaGui_('##eigen_geometry');

                GB.separator();
                GB.subtitle('Scale && Style');
                s = GB.sliderFloat('Scale', obj.gui_.scale, 0.01, 20);
                if abs(s - obj.gui_.scale) > eps
                    obj.gui_.scale = s;
                    obj.Opts.mode.scale = s;
                    needsSetMode = true;
                end
                s = GB.sliderFloat('Deformed alpha', obj.gui_.deformedAlpha, 0, 1);
                if abs(s - obj.gui_.deformedAlpha) > eps
                    obj.gui_.deformedAlpha = s;
                    obj.Opts.color.deformedAlpha = s;
                    obj.applyStyle_();
                end
                s = GB.sliderFloat('Undeformed alpha', obj.gui_.undeformedAlpha, 0, 1);
                if abs(s - obj.gui_.undeformedAlpha) > eps
                    obj.gui_.undeformedAlpha = s;
                    obj.Opts.color.undeformedAlpha = s;
                    obj.applyStyle_();
                end
                s = GB.sliderFloat('Node radius', obj.gui_.nodeRadius, 0.0001, 0.012);
                if abs(s - obj.gui_.nodeRadius) > eps
                    obj.gui_.nodeRadius = s;
                    obj.Opts.polyscope.nodeRadius = s;
                    obj.applyStyle_();
                end
                s = GB.sliderFloat('Edge radius', obj.gui_.edgeRadius, 0.0001, 0.006);
                if abs(s - obj.gui_.edgeRadius) > eps
                    obj.gui_.edgeRadius = s;
                    obj.Opts.polyscope.edgeRadius = s;
                    obj.applyStyle_();
                end

                [cchg, obj.gui_.undeformedColor] = GB.colorEdit3( ...
                    'Undeformed color', obj.gui_.undeformedColor);
                if cchg
                    obj.Opts.color.undeformedColor = obj.gui_.undeformedColor;
                    obj.applyStyle_();
                end

                GB.separator();
                GB.subtitle('Colormap');
                newCmap = GB.combo('Colormap', obj.gui_.cmapIdx, cmapNames);
                if newCmap ~= obj.gui_.cmapIdx
                    obj.gui_.cmapIdx = newCmap;
                    obj.Opts.color.colormap = cmapNames{newCmap};
                    obj.Opts.polyscope.scalarColorMap = cmapNames{newCmap};
                    needsSetMode = true;
                end

                tf = GB.checkbox('Colorbar', obj.gui_.onscreenColorbar);
                if tf ~= obj.gui_.onscreenColorbar
                    obj.gui_.onscreenColorbar = tf;
                    obj.Opts.polyscope.onscreenColorbar = tf;
                    needsSetMode = true;
                end
                if obj.gui_.onscreenColorbar
                    loc = obj.gui_.onscreenColorbarLocation;
                    if numel(loc) < 2 || any(~isfinite(loc))
                        loc = [20, 100];
                    end
                    [moved, loc] = polyscope.ImGui.InputFloat2( ...
                        'Colorbar pos', double(loc(:).'));
                    if moved
                        obj.gui_.onscreenColorbarLocation = loc;
                        obj.Opts.polyscope.onscreenColorbarLocation = loc;
                        obj.gui_.colorbarForcePos = true;
                        needsSetMode = true;
                    end
                    title = char(string(obj.gui_.colorbarTitle));
                    [tchg, title] = polyscope.ImGui.InputText( ...
                        'Colorbar title', title);
                    if tchg
                        obj.gui_.colorbarTitle = title;
                        obj.Opts.polyscope.colorbarTitle = title;
                    end
                end

                % Slice plane panel
                if obj.drawSlicePlaneGui_()
                    sliceDirty = true;
                end

                % Actions
                GB.separator();
                if GB.button('Redraw')
                    try
                        obj.App.polyscopeHandle().request_redraw();
                    catch
                    end
                end
                GB.sameLine();
                if GB.button('Reset')
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

                obj.drawModeInfoWindow_();
                obj.drawScreenAxesOverlay_();
                obj.updateScreenAxes3D_();

                if obj.gui_.onscreenColorbar
                    if obj.drawColorbarHandle_()
                        needsSetMode = true;
                    end
                end

                if needsSetMode
                    obj.setMode(obj.modeTags_(obj.gui_.modeIdx));
                end
                if sliceDirty
                    obj.applySlicePlane_();
                end
                if needsRebuild
                    obj.build();
                end
            catch ME
                fprintf('plotEigen.guiCallback_ error: %s\n', ME.message);
            end
        end

    end

    methods (Access = private)

        function drawModeInfoWindow_(obj)
            if ~obj.getOptField_(obj.Opts.polyscope, 'showModelInfo', false)
                return;
            end
            if ~isfield(obj.gui_, 'showModeInfo') || ~obj.gui_.showModeInfo
                return;
            end
            try
                ws = obj.safeWindowSize_();
                if numel(ws) < 2 || any(~isfinite(ws(1:2))) || any(ws(1:2) <= 0)
                    return;
                end
                margin = 16;
                rightPanelW = 340;
                width = 260;
                height = 160;
                pos = [ws(1) - rightPanelW - margin - width, ws(2) - height - margin];
                cond = int32(polyscope.ImGui.get_constant('ImGuiCond_FirstUseEver'));
                polyscope.ImGui.SetNextWindowPos(pos, cond, [0, 0]);
                polyscope.ImGui.SetNextWindowSize([width, height], cond);
                flags = int32(0);
                visible = polyscope.ImGui.Begin('Mode Info', flags);
                if visible
                    lines = obj.modeSummary_(obj.modeTags_(obj.currentIdx_));
                    valueColor = [0.30, 0.85, 1.00, 1.00];  % bright cyan
                    for i = 1:numel(lines)
                        line = lines{i};
                        colon = strfind(line, ':');
                        try
                            if ~isempty(colon)
                                label = line(1:colon(1));
                                value = line(colon(1)+1:end);
                                polyscope.ImGui.Text(label);
                                polyscope.ImGui.SameLine();
                                polyscope.ImGui.TextColored(valueColor, value);
                            else
                                polyscope.ImGui.Text(line);
                            end
                        catch
                            try
                                polyscope.ImGui.TextUnformatted(line);
                            catch
                                polyscope.ImGui.Text(line);
                            end
                        end
                    end
                end
                polyscope.ImGui.End();
            catch ME
                fprintf('drawModeInfoWindow_ error: %s\n', ME.message);
            end
        end

        function moved = drawColorbarHandle_(obj)
            moved = false;
            if ~isfield(obj.gui_, 'onscreenColorbarLocation')
                return;
            end
            try
                loc = obj.gui_.onscreenColorbarLocation;
                if numel(loc) < 2 || any(~isfinite(loc))
                    loc = [1200, 800];
                end
                if isfield(obj.gui_, 'colorbarForcePos') && obj.gui_.colorbarForcePos
                    cond = int32(polyscope.ImGui.get_constant('ImGuiCond_Always'));
                    obj.gui_.colorbarForcePos = false;
                else
                    cond = int32(polyscope.ImGui.get_constant('ImGuiCond_FirstUseEver'));
                end
                polyscope.ImGui.SetNextWindowPos(double(loc(:).'), cond, [0, 0]);
                flags = int32(0);

                title = 'Mode';
                if isfield(obj.gui_, 'colorbarTitle') && ~isempty(obj.gui_.colorbarTitle)
                    title = char(string(obj.gui_.colorbarTitle));
                end
                % Use a stable ImGui ID (###ColorbarHandle) while allowing the
                % displayed title to change.
                winLabel = sprintf('%s###ColorbarHandle', title);
                visible = polyscope.ImGui.Begin(winLabel, flags);
                if visible
                    pos = polyscope.ImGui.GetWindowPos();
                    if norm(double(pos(:).') - double(loc(:).')) > 1
                        obj.gui_.onscreenColorbarLocation = double(pos(:).');
                        obj.Opts.polyscope.onscreenColorbarLocation = double(pos(:).');
                        moved = true;
                    end
                end
                polyscope.ImGui.End();
            catch ME
                fprintf('drawColorbarHandle_ error: %s\n', ME.message);
            end
        end

    end
end
