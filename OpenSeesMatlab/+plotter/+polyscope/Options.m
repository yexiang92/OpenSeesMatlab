classdef Options
    %OPTIONS Default option templates for plotter.polyscope viewers.
    %
    %   These templates extend the existing PlotModel / PlotEigen /
    %   PlotNodalResp defaults with Polyscope-specific fields (backend,
    %   radius, material, colour map, etc.).

    methods (Static)

        function opts = defaultModelOptions()
            opts = plotter.PlotModel.defaultOptions();
            % Shared boundary/support green for model and deformation views.
            opts.fixed.color = '#21FC0D';
            opts.fixed.symbolScale = 1.0;
            if isfield(opts, 'style') && isfield(opts.style, 'familyColors')
                opts.style.familyColors.Fixed = '#21FC0D';
            end
            % High-contrast local-axis palette which stays distinct from
            % the common blue/green beam and link family colors.
            opts.localAxes.axisXColor = '#E85D75'; % rose
            opts.localAxes.axisYColor = '#F4A261'; % amber
            opts.localAxes.axisZColor = '#9B5DE5'; % violet
            opts.polyscope = plotter.polyscope.Options.polyscopeCommon();
            opts.general.view = '3D';
            opts.polyscope.name = '';
            opts.polyscope.nodeRadius   = 0.003;   % relative to scene length
            opts.polyscope.edgeRadius   = 0.0012;  % relative to scene length
            opts.polyscope.supportLineRadiusFactor = 0.80;
            opts.polyscope.pointRenderMode = 'sphere';
            opts.polyscope.surfaceMaterial = 'flat';
            opts.polyscope.lineMaterial    = 'flat';
            opts.polyscope.surfaceSmoothShade = false;
            opts.polyscope.vectorRadius = 0.0012;
            opts.polyscope.vectorLength = 0.04;
            opts.polyscope.showNodes = false;
            opts.polyscope.showFixed = true;
            opts.polyscope.showMPConstraint = true;
            opts.elements.showWireframeOnFaces = false;
            opts.mvlem.internalLines = struct('show', false, ...
                'fiberWidths', [], 'fiberCount', 10, ...
                'color', [0.20 0.20 0.20], 'radius', 0.00055);
            opts.outline.show = false;
            opts.polyscope.showScreenAxes = true;
            opts.polyscope.screenAxesSize = 78;
            opts.polyscope.useScreenAxesGizmo = true;
            opts.polyscope.screenAxesGizmoSize = 1.15;
            opts.polyscope.screenAxesMode = 'overlay';
            opts.slice = struct();
            opts.slice.show = false;
            opts.slice.name = 'Slice plane';
            opts.slice.center = [];  % empty means model bounding-box center
            opts.slice.normal = [0, 0, 1];
            opts.slice.drawPlane = true;
            opts.slice.drawWidget = false;
            opts.slice.widgetSize = 0.75;
            opts.slice.color = [0.90, 0.35, 0.55];
            opts.slice.gridColor = [1.00, 1.00, 1.00];
            opts.slice.transparency = 0.45;
            opts.slice.cullWholeElements = false;
        end

        function opts = defaultEigenOptions()
            opts = plotter.PlotEigen.defaultOptions();
            opts.fixed.color = '#21FC0D';
            opts.fixed.symbolScale = 1.0;
            opts.polyscope = plotter.polyscope.Options.polyscopeCommon();
            opts.polyscope.name = '';
            opts.polyscope.nodeRadius   = 0.003;
            opts.polyscope.edgeRadius   = 0.001;
            opts.polyscope.pointRenderMode = 'sphere';
            opts.polyscope.surfaceMaterial = 'flat';
            opts.polyscope.lineMaterial    = 'flat';
            opts.polyscope.surfaceSmoothShade = false;
            opts.polyscope.showScreenAxes = true;
            opts.polyscope.screenAxesSize = 78;
            opts.polyscope.useScreenAxesGizmo = true;
            opts.polyscope.screenAxesGizmoSize = 1.15;
            opts.polyscope.screenAxesMode = 'overlay';
            opts.polyscope.ghostColor       = [0.82 0.82 0.82];
            opts.polyscope.ghostTransparency = 0.35;
            opts.polyscope.scalarSymmetry   = false;
            opts.polyscope.onscreenColorbar = false;
            opts.polyscope.onscreenColorbarLocation = [];  % empty = auto, placed near top center
            opts.polyscope.onscreenColorbarSize = 1.0;  % multiplier for the native colorbar size
            opts.polyscope.colorbarTitle = '';  % custom title for the onscreen colorbar
            opts.unstructured.showEdges = false;
            opts.slice = struct();
            opts.slice.show = false;
            opts.slice.name = 'Slice plane';
            opts.slice.center = [];
            opts.slice.normal = [0, 0, 1];
            opts.slice.drawPlane = true;
            opts.slice.drawWidget = false;
            opts.slice.widgetSize = 0.75;
            opts.slice.color = [0.90, 0.35, 0.55];
            opts.slice.gridColor = [1.00, 1.00, 1.00];
            opts.slice.transparency = 0.45;
            opts.slice.cullWholeElements = false;
            opts.unstructured.wireframe = false;
        end

        function opts = defaultNodalResponseOptions()
            opts = plotter.PlotNodalResp.defaultOptions();
            opts.fixed.color = '#21FC0D';
            opts.fixed.symbolScale = 1.0;
            opts.polyscope = plotter.polyscope.Options.polyscopeCommon();
            opts.polyscope.name = '';
            opts.polyscope.nodeRadius   = 0.0025;
            opts.polyscope.edgeRadius   = 0.00075;
            opts.polyscope.pointRenderMode = 'sphere';
            opts.polyscope.surfaceMaterial = 'flat';
            opts.polyscope.lineMaterial    = 'flat';
            opts.polyscope.surfaceSmoothShade = false;
            opts.polyscope.onscreenColorbar = false;
            opts.polyscope.onscreenColorbarLocation = [1200, 800];
            opts.polyscope.colorbarTitle = '';
            opts.polyscope.vectorColor      = [0.85 0.33 0.10];
            opts.polyscope.vectorLength     = 0.05;  % relative
            opts.polyscope.vectorRadius     = 0.001; % relative
            opts.color.historyLineColor = [];
            opts.color.historyLineAlpha = 1.0;
            opts.surf.showEdges = false;
            opts.surf.renderMode = 'surface';
            opts.mvlem.internalLines = struct('show', false, ...
                'fiberWidths', [], 'fiberCount', 10, ...
                'color', [0.20 0.20 0.20], 'radius', 0.00055);
            opts.animation = struct('play', false, 'fps', [], ...
                                    'loop', true, 'pingpong', false, ...
                                    'updateColors', true, 'updateVectors', false, ...
                                    'autoFrameStride', true, 'frameStride', [], ...
                                    'duration', 10);
            opts.slice = struct();
            opts.slice.show = false;
            opts.slice.name = 'Slice plane';
            opts.slice.center = [];
            opts.slice.normal = [0, 0, 1];
            opts.slice.drawPlane = true;
            opts.slice.drawWidget = false;
            opts.slice.widgetSize = 0.75;
            opts.slice.color = [0.90, 0.35, 0.55];
            opts.slice.gridColor = [1.00, 1.00, 1.00];
            opts.slice.transparency = 0.45;
            opts.slice.cullWholeElements = false;
            opts.stepIdx = 'absmax';
        end

        function opts = defaultUnstructuredResponseOptions()
            opts = plotter.PlotUnstruResponse.defaultOptions();
            opts.fixed.color = '#21FC0D';
            opts.fixed.symbolScale = 1.0;
            opts.polyscope = plotter.polyscope.Options.polyscopeCommon();
            opts.polyscope.name = '';
            opts.polyscope.nodeRadius   = 0.0025;
            opts.polyscope.edgeRadius   = 0.00075;
            opts.polyscope.pointRenderMode = 'sphere';
            opts.polyscope.surfaceMaterial = 'flat';
            opts.polyscope.lineMaterial    = 'flat';
            opts.polyscope.surfaceSmoothShade = false;
            opts.polyscope.onscreenColorbar = false;
            opts.polyscope.onscreenColorbarLocation = [1200, 800];
            opts.polyscope.colorbarTitle = '';
            opts.animation = struct('play', false, 'fps', [], ...
                                    'loop', true, 'pingpong', false, ...
                                    'updateColors', true, ...
                                    'autoFrameStride', true, 'frameStride', [], ...
                                    'duration', 10);
            opts.color.climMode = 'step';
            opts.color.historyLineColor = [];
            opts.color.historyLineAlpha = 1.0;
            opts.nodes = struct('show', false);
            opts.surf.showEdges = false;
            opts.surf.renderMode = 'surface';
            opts.slice = struct();
            opts.slice.show = false;
            opts.slice.name = 'Slice plane';
            opts.slice.center = [];
            opts.slice.normal = [0, 0, 1];
            opts.slice.drawPlane = true;
            opts.slice.drawWidget = false;
            opts.slice.widgetSize = 0.75;
            opts.slice.color = [0.90, 0.35, 0.55];
            opts.slice.gridColor = [1.00, 1.00, 1.00];
            opts.slice.transparency = 0.45;
            opts.slice.cullWholeElements = false;
            opts.stepIdx = 'absmax';
            opts.eleType = 'auto';
            opts.respType = 'auto';
            opts.component = 'auto';
            opts.fiberPoint = 'top';
        end

        function opts = defaultFrameResponseOptions()
            opts = plotter.PlotFrameResp.defaultOptions();
            opts.fixed = struct('show', true, 'color', '#21FC0D', 'symbolScale', 1.0);
            opts.polyscope = plotter.polyscope.Options.polyscopeCommon();
            opts.polyscope.name = '';
            opts.polyscope.edgeRadius = 0.0009;
            opts.polyscope.modelRadius = 0.0008;
            opts.polyscope.zeroRadius = 0.00055;
            opts.polyscope.diagramRadius = 0.0010;
            opts.polyscope.surfaceMaterial = 'flat';
            opts.polyscope.surfaceSmoothShade = false;
            opts.polyscope.onscreenColorbar = false;
            opts.polyscope.onscreenColorbarLocation = [1200, 800];
            opts.polyscope.colorbarTitle = '';
            opts.animation = struct('play', false, 'fps', [], ...
                                    'loop', true, 'pingpong', false, ...
                                    'updateColors', true, ...
                                    'autoFrameStride', true, 'frameStride', [], ...
                                    'duration', 10);
            opts.stepIdx = 'absmax';
            opts.color.climMode = 'current';
            % Empty uses the light/dark theme-aware history-curve color.
            opts.color.historyLineColor = [];
            opts.color.historyLineAlpha = 1.0;
            opts.surf.show = false;
            opts.showZeroLine = false;
            opts.showMPConstraint = true;
            opts.showMaxMinLabel = 'none';
            opts.slice = struct();
            opts.slice.show = false;
            opts.slice.name = 'Slice plane';
            opts.slice.center = [];
            opts.slice.normal = [0, 0, 1];
            opts.slice.drawPlane = true;
            opts.slice.drawWidget = false;
            opts.slice.widgetSize = 0.75;
            opts.slice.color = [0.90, 0.35, 0.55];
            opts.slice.gridColor = [1.00, 1.00, 1.00];
            opts.slice.transparency = 0.45;
            opts.slice.cullWholeElements = false;
        end

        function opts = defaultMVLEMResponseOptions()
            opts = plotter.polyscope.Options.defaultModelOptions();
            opts.respType = 'curvature';
            opts.responseDisplay = 'auto'; % auto | contour | diagram | both
            opts.diagramStyle = 'surface'; % surface | wireframe
            opts.localForceFlipEnd = true; % display end actions with section-force signs
            opts.forceResultantFlipEnd = true; % common section sign at both wall ends
            opts.topology = 'all'; % all | line | surface
            opts.component = 'auto';
            opts.stepIdx = 'absmax';
            opts.color.useColormap = true;
            opts.color.climMode = 'step';
            opts.polyscope.scalarColorMap = 'coolwarm';
            opts.polyscope.onscreenColorbar = false;
            opts.polyscope.onscreenColorbarLocation = [1200, 800];
            opts.polyscope.colorbarTitle = '';
            opts.animation = struct('play', false, 'fps', 12, ...
                                    'loop', true, 'pingpong', false, ...
                                    'autoFrameStride', true, 'frameStride', [], ...
                                    'duration', 10);
            opts.deform = struct('show', true, 'autoScale', true, ...
                'scale', 1.0, 'targetFraction', 0.10, 'showUndeformed', false);
            opts.nodes = struct('show', false);
            opts.lineDiagram = struct('show', true, 'showModel', true, ...
                'scale', 1.0, 'heightFraction', 0.15, 'scaleMode', 'global');
            opts.surfaceDiagram = struct('show', true, 'showContour', true, ...
                'scale', 1.0, 'heightFraction', 0.12, 'scaleMode', 'current');
            opts.surf.showEdges = false;
            opts.surf.renderMode = 'surface';
            opts.surf.edgeColor = [0.15 0.15 0.15];
            opts.color.deformedAlpha = 1.0;
            opts.color.solidColor = [0.72 0.74 0.78];
            opts.color.undeformedAlpha = 0.30;
            opts.color.undeformedColor = [0.72 0.72 0.72];
            opts.fixed.show = true;
            opts.fixed.symbolScale = 1.0;
            opts.fibers = struct('show', true, 'width', [], 'fiberWidths', [], ...
                'widthToHeight', 0.5, 'gapFraction', 0.0, ...
                'showEdges', false, 'edgeRadius', 0.00045);
            opts.mvlem.internalLines = struct('show', false, ...
                'color', [0.18 0.18 0.18], 'radius', 0.00055);
        end

        function out = mergeOpts(base, user)
            out = base;
            if nargin < 2 || isempty(user) || ~isstruct(user)
                return;
            end
            out = plotter.polyscope.Options.mergeStruct_(out, user);
        end

    end

    methods (Static, Access = private)

        function p = polyscopeCommon()
            p = struct();
            p.backend      = 'openGL3_glfw';  % or 'openGL_mock' for headless/tests
            p.maximize     = true;            % maximize the main window on first show
            p.windowSize   = [1280, 800];     % used when maximize == false
            p.plotTheme = 'light';            % scene theme; does not style the ImGui controls
            p.showLogo = true;
            p.logoWidth = 280;
            p.logoMargin = 22;
            p.copyrightText = 'Copyright © Yexiang Yan. All rights reserved.';
            p.copyrightLine1 = 'Copyright © Yexiang Yan.';
            p.copyrightLine2 = 'All rights reserved.';
            p.backgroundColor = [1, 1, 1];
            p.transparency = 1.0;   % Polyscope opacity: 1 = opaque, 0 = transparent
            p.ssaaFactor = 2;       % supersampling anti-aliasing, valid range 1..4
            p.maxFps = 60;
            p.verbosity = 0;                 % suppress routine backend initialization messages
            p.giveFocusOnShow = true;        % raise the viewer above MATLAB when shown
            p.enableVsync = true;
            p.alwaysRedraw = false;
            p.frameTickLimitFpsMode = 'auto';
            p.headless = false;              % true -> force openGL_mock backend, skip window creation
            p.autoShow = true;               % false -> init but call frameTick() instead of show()
            p.groundPlaneMode = 'none'; % 'shadow_only', 'tile', or 'none'
            p.backFacePolicy = 'identical'; % 'identical', 'different', 'custom', or 'cull'
            p.showModelInfo = false; % show the Model Info window (nodes, elements)
            p.showNodeLabels = false;
            p.showElementLabels = false;
            p.maxLabels = 0; % 0 = all labels; positive values impose a per-kind limit
            p.nodeLabelColor = []; % empty = theme-aware
            p.elementLabelColor = []; % empty = theme-aware
            p.scalarColorMap = 'coolwarm';   % default scalar color map for all viewers
            p.supportColor = '#21FC0D';      % shared boundary/support glyph colour
            p.supportLineRadiusFactor = 0.80;
            p.showMPConstraints = true;
            p.mpConstraintColor = [0.64, 0.28, 0.34];
            p.onscreenColorbar = false;
            p.onscreenColorbarLocation = [];
            p.colorbarTitle = '';
            p.colorbarBackgroundColor = [1, 1, 1, 0.70];
            p.colorbarTickColor = [0, 0, 0, 1];
            p.colorbarLabelColor = [0, 0, 0, 1];
            p.colorbarTitleColor = [0, 0, 0, 1];
            p.displayNames = struct(...       % user-friendly names for non-element structures in the left panel
                'Nodes', 'Nodes', ...
                'Fixed', 'Fixed supports', ...
                'MPConstraint', 'MP constraints', ...
                'Outline', 'Outline', ...
                'NodalLoads', 'Nodal loads', ...
                'ElementLoads', 'Element loads', ...
                'BeamAxes', 'Beam axes', ...
                'LinkAxes', 'Link axes', ...
                'Diagram', 'Diagram', ...
                'DiagramWire', 'Diagram wireframe', ...
                'Model', 'Model', ...
                'ZeroLine', 'Zero line', ...
                'Response', 'Response mesh', ...
                'MeshEdges', 'Mesh edges', ...
                'Line', 'Line elements', ...
                'InterpLine', 'Interpolated lines', ...
                'Vectors', 'Nodal vectors', ...
                'Ghost', 'Undeformed mesh');
            p.planeViewFov = 35; % tighter default framing for orthographic plane views
            p.perspectiveViewFov = 45.0;
        end

        function out = mergeStruct_(base, add)
            out = base;
            f = fieldnames(add);
            for i = 1:numel(f)
                n = f{i};
                if isfield(out, n) && isstruct(out.(n)) && isstruct(add.(n))
                    out.(n) = plotter.polyscope.Options.mergeStruct_(out.(n), add.(n));
                else
                    out.(n) = add.(n);
                end
            end
        end

    end
end
