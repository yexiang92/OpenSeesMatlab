classdef Options
    %OPTIONS Default option templates for plotter.polyscope viewers.
    %
    %   These templates extend the existing PlotModel / PlotEigen /
    %   PlotNodalResp defaults with Polyscope-specific fields (backend,
    %   radius, material, colour map, etc.).

    methods (Static)

        function opts = defaultModelOptions()
            opts = plotter.PlotModel.defaultOptions();
            opts.polyscope = plotter.polyscope.Options.polyscopeCommon();
            opts.general.view = '3D';
            opts.polyscope.name = '';
            opts.polyscope.nodeRadius   = 0.003;   % relative to scene length
            opts.polyscope.edgeRadius   = 0.0012;  % relative to scene length
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
            opts.surf.showEdges = false;
            opts.animation = struct('play', false, 'fps', [], ...
                                    'loop', true, 'pingpong', false, ...
                                    'updateColors', true, 'updateVectors', false);
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
                                    'updateColors', true);
            opts.color.climMode = 'step';
            opts.nodes = struct('show', false);
            opts.surf.showEdges = false;
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
                                    'updateColors', true);
            opts.stepIdx = 'absmax';
            opts.color.climMode = 'current';
            opts.surf.show = false;
            opts.showZeroLine = false;
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
            p.backgroundColor = [1, 1, 1];
            p.transparency = 1.0;   % Polyscope opacity: 1 = opaque, 0 = transparent
            p.ssaaFactor = 2;       % supersampling anti-aliasing, valid range 1..4
            p.maxFps = 60;
            p.enableVsync = true;
            p.alwaysRedraw = false;
            p.frameTickLimitFpsMode = 'auto';
            p.headless = false;              % true -> force openGL_mock backend, skip window creation
            p.autoShow = true;               % false -> init but call frameTick() instead of show()
            p.groundPlaneMode = 'none'; % 'shadow_only', 'tile', or 'none'
            p.backFacePolicy = 'identical'; % 'identical', 'different', 'custom', or 'cull'
            p.showModelInfo = false; % show the Model Info window (nodes, elements)
            p.scalarColorMap = 'coolwarm';   % default scalar color map for all viewers
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
