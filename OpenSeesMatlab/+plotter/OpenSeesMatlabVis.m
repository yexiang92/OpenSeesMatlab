classdef OpenSeesMatlabVis < handle
    % OpenSeesMatlabVis Visualization interface for OpenSeesMatlab.
    %
    %   OpenSeesMatlabVis provides high-level plotting utilities for OpenSees
    %   models and analysis results. It is created automatically by
    %   OpenSeesMatlab and is normally accessed through the vis property:
    %
    %       opsmat = OpenSeesMatlab();
    %       vis = opsmat.vis;
    %
    %   The visualization methods use model information collected by
    %   opsmat.post.getModelData or response/eigen data collected by the
    %   post-processing interface. Most plotting methods accept an optional opts
    %   struct and an optional target axes handle. Default option templates are
    %   exposed as public properties and can be copied before customization.
    %
    % Common workflow
    % ---------------
    %       opsmat = OpenSeesMatlab();
    %       ops = opsmat.opensees;
    %
    %       % Build or load an OpenSees model with ops...
    %       % ops.wipe();
    %       % ops.model(...);
    %
    %       modelInfo = opsmat.post.getModelData();
    %       hModel = opsmat.vis.plotModel();
    %
    %       eigenData = opsmat.post.getEigenData(numModes=3);
    %       hMode1 = opsmat.vis.plotEigen(1, eigenData);
    %
    % Properties
    % ----------
    % defaultPlotModelOptions : struct
    %     Default option template used by plotModel. See ``.help`` for details.
    % defaultPlotEigenOptions : struct
    %     Default option template used by plotEigen. See ``.help`` for details.
    % defaultPlotNodalResponseOptions : struct
    %     Default option template used by plotNodalResponse and plotDeformation. See ``.help`` for details.
    % defaultPlotFrameResponseOptions : struct
    %     Default option template used by plotFrameResponse. See ``.help`` for details.
    % defaultPlotShellResponseOptions : struct
    %     Default option template used by shell response plotting. See ``.help`` for details.
    % defaultPlotContinuumResponseOptions : struct
    %     Default option template used by continuum response plotting. See ``.help`` for details.

    properties (Access = public)
        parent  % Reference to the parent OpenSeesMatlab object
    end

    properties (Access = public)
        defaultPlotModelOptions = plotter.PlotModel.defaultOptions();
        % Default options for plotModel, see ``.help`` for details.
    end

    properties (Access = public)
        defaultPlotEigenOptions = plotter.PlotEigen.defaultOptions();
        % Default options for plotEigen, see ``.help`` for details.
    end

    properties (Access = public)
        defaultPlotNodalResponseOptions = plotter.PlotNodalResp.defaultOptions();
        % Default options for plotNodalResponse, see ``.help`` for details.
    end

    properties (Access = public)
        defaultPlotFrameResponseOptions = plotter.PlotFrameResp.defaultOptions();
        % Default options for plotFrameResponse, see ``.help`` for details.
    end

    properties (Access = public)
        defaultPlotShellResponseOptions = plotter.PlotUnstruResponse.defaultOptions();
        % Default options for plotShellResponse, see ``.help`` for details.
    end

    properties (Access = public)
        defaultPlotContinuumResponseOptions = plotter.PlotUnstruResponse.defaultOptions();
        % Default options for plotContinuumResponse, see ``.help`` for details.
    end

    properties (Access = public)
        polyscope  plotter.OpenSeesMatlabVisPolyscope  % Polyscope-based visualisation interface (plotter.OpenSeesMatlabVisPolyscope)
    end

    methods
        function obj = OpenSeesMatlabVis(parentObj)
            % Construct an OpenSeesMatlabVis visualization interface.
            %
            %   Users normally do not construct this class directly. A
            %   visualization interface is created automatically by OpenSeesMatlab
            %   and can be accessed as opsmat.vis.
            %
            % Parameters
            % ----------
            % parentObj : OpenSeesMatlab
            %     Parent OpenSeesMatlab object. The visualization interface uses
            %     parentObj.post to collect or load model and response data needed
            %     by the plotter classes.
            %
            % Example
            % -------
            %     opsmat = OpenSeesMatlab();
            %     vis = opsmat.vis;
            %     h = vis.plotModel();
            if nargin < 1 || isempty(parentObj)
                error('OpenSeesMatlabVis:InvalidInput', ...
                    'A parent OpenSeesMatlab object is required.');
            end
            obj.parent = parentObj;
            obj.polyscope = plotter.OpenSeesMatlabVisPolyscope(obj);
        end

        function h = plotModel(obj, options)
            % Visualize the current OpenSees model.
            %
            %   plotModel collects model information from the current OpenSees
            %   model through obj.parent.post.getModelData and renders the model
            %   geometry using plotter.PlotModel.
            %
            % Syntax
            % ------
            %     h = vis.plotModel()
            %     h = vis.plotModel(opts=opts)
            %     h = vis.plotModel(ax=ax)
            %     h = vis.plotModel(opts=opts, ax=ax)
            %
            % Parameters
            % ----------
            % opts : struct, optional
            %     Visualization options passed to plotter.PlotModel. Start from
            %     vis.defaultPlotModelOptions when you want to customize the
            %     default model-plot appearance.
            % ax : matlab.graphics.axis.Axes, optional
            %     Target axes. If omitted or empty, a new figure/axes is created by
            %     the underlying plotter.
            %
            % Returns
            % -------
            % h : array of graphics objects
            %     Handles to the created graphics objects.
            %
            % Example
            % -------
            %     opsmat = OpenSeesMatlab();
            %     % Build model with opsmat.opensees...
            %     h = opsmat.vis.plotModel();
            %
            %     opts = opsmat.vis.defaultPlotModelOptions;
            %     figure;
            %     ax = axes();
            %     h = opsmat.vis.plotModel(opts=opts, ax=ax);

            arguments
                obj (1,1) plotter.OpenSeesMatlabVis
                options.opts (1,1) struct = struct()
                options.ax {plotter.OpenSeesMatlabVis.mustBeAxesOrEmpty} = []
            end

            modelInfo = obj.parent.post.getModelData();

            if isempty(options.ax)
                pm = plotter.PlotModel(modelInfo, [], options.opts);
            else
                pm = plotter.PlotModel(modelInfo, options.ax, options.opts);
            end

            h = pm.plot();
        end

        function app = plotModelGUI(obj, options)
            % Open an interactive GUI for the current OpenSees model.
            %
            %   plotModelGUI collects model information from the current
            %   OpenSees model and opens a small control panel around
            %   plotter.PlotModel. The GUI toggles common PlotModel options and
            %   redraws the same axes.
            %
            % Syntax
            % ------
            %     app = vis.plotModelGUI()
            %     app = vis.plotModelGUI(opts=opts)
            %     app = vis.plotModelGUI(watchFile=true)
            %     app = vis.plotModelGUI(watchFile="modelData_1.hdf5")
            %
            % Parameters
            % ----------
            % opts : struct, optional
            %     Initial visualization options passed to plotter.PlotModelGUI.
            % watchFile : char or string, optional
            %     false disables watching. true watches the caller file. A text
            %     value watches that path.
            % reloadFcn : function handle, optional
            %     Function returning a fresh modelInfo struct after watchFile
            %     changes. If omitted, PlotModelGUI tries to read .hdf5/.h5,
            %     .mat, or .json modelInfo files directly.
            % pollInterval : double, optional
            %     File polling interval in seconds. Default is 1.0.
            %
            % Returns
            % -------
            % app : struct
            %     GUI handles and helper callbacks. Use app.getOptions() to read
            %     the current PlotModel option struct.

            arguments
                obj (1,1) plotter.OpenSeesMatlabVis
                options.opts (1,1) struct = struct()
                options.watchFile = false
                options.reloadFcn = []
                options.pollInterval (1,1) double {mustBePositive} = 1.0
                options.autoWatch (1,1) logical = true
            end

            modelInfo = obj.parent.post.getModelData();
            reloadFcn = options.reloadFcn;
            isBoolWatch = islogical(options.watchFile) || ...
                (isnumeric(options.watchFile) && isscalar(options.watchFile));
            if isempty(reloadFcn) && isBoolWatch && logical(options.watchFile)
                reloadFcn = @() obj.parent.post.getModelData();
            end

            app = plotter.PlotModelGUI(modelInfo, ...
                opts=options.opts, ...
                watchFile=options.watchFile, ...
                reloadFcn=reloadFcn, ...
                pollInterval=options.pollInterval, ...
                autoWatch=options.autoWatch);
        end

        function h = plotEigen(obj, modeTag, eigenData, options)
            % Visualize one mode shape from eigenvalue analysis results.
            %
            %   eigenData is usually collected with opsmat.post.getEigenData or
            %   loaded from a file generated by opsmat.post.saveEigenData.
            %
            % Syntax
            % ------
            %     h = vis.plotEigen(modeTag, eigenData)
            %     h = vis.plotEigen(modeTag, eigenData, opts=opts)
            %     h = vis.plotEigen(modeTag, eigenData, ax=ax)
            %     h = vis.plotEigen(modeTag, eigenData, opts=opts, ax=ax)
            %
            % Parameters
            % ----------
            % modeTag : integer
            %     Mode number to visualize. For example, modeTag=1 plots the first
            %     mode shape.
            % eigenData : struct
            %     Eigenvalue analysis results, typically returned by
            %     opsmat.post.getEigenData.
            % opts : struct, optional
            %     Visualization options passed to plotter.PlotEigen. Start from
            %     vis.defaultPlotEigenOptions for customization.
            % ax : matlab.graphics.axis.Axes, optional
            %     Target axes. If omitted or empty, a new figure/axes is created.
            %
            % Returns
            % -------
            % h : array of graphics objects
            %     Handles to the created graphics objects.
            %
            % Example
            % -------
            %     eigenData = opsmat.post.getEigenData(numModes=3);
            %     h = opsmat.vis.plotEigen(1, eigenData);
            %
            %     opts = opsmat.vis.defaultPlotEigenOptions;
            %     opts.deform.scale = 10;
            %     h = opsmat.vis.plotEigen(2, eigenData, opts=opts);

            arguments
                obj (1,1) plotter.OpenSeesMatlabVis
                modeTag (1,1) double {mustBeInteger, mustBePositive}
                eigenData (1,1) struct
                options.opts (1,1) struct = struct()
                options.ax {plotter.OpenSeesMatlabVis.mustBeAxesOrEmpty} = []
            end

            modelInfo = obj.parent.post.getModelData();
            pe = plotter.PlotEigen(modelInfo, eigenData, options.ax, options.opts);
            h = pe.plotMode(modeTag);
        end

        function app = plotEigenGUI(obj, eigenData, options)
            % Open an interactive GUI for eigen mode visualization.
            %
            %   plotEigenGUI collects model information from the current
            %   OpenSees model and opens a control panel around plotter.PlotEigen.
            %   The GUI lets users switch mode tags and common PlotEigen options.
            %
            % Syntax
            % ------
            %     app = vis.plotEigenGUI(eigenData)
            %     app = vis.plotEigenGUI(eigenData, opts=opts)
            %
            % Parameters
            % ----------
            % eigenData : struct
            %     Eigenvalue analysis results, typically returned by
            %     opsmat.post.getEigenData.
            % opts : struct, optional
            %     Initial visualization options passed to plotter.PlotEigenGUI.
            %
            % Returns
            % -------
            % app : struct
            %     GUI handles and helper callbacks. Use app.getOptions() to read
            %     the current PlotEigen option struct.

            arguments
                obj (1,1) plotter.OpenSeesMatlabVis
                eigenData (1,1) struct
                options.opts (1,1) struct = struct()
            end

            modelInfo = obj.parent.post.getModelData();
            app = plotter.PlotEigenGUI(modelInfo, eigenData, opts=options.opts);
        end

        function plotNodalResponse(obj, nodeRespData, options)
            % Visualize nodal response data at a selected analysis step.
            %
            %   plotNodalResponse renders nodal scalar or vector response fields
            %   such as displacement, velocity, acceleration, reaction, Rayleigh
            %   force, or pressure. The model information is loaded from the ODB
            %   referenced by nodeRespData.odbTag.
            %
            % Syntax
            % ------
            %     vis.plotNodalResponse(nodeRespData)
            %     vis.plotNodalResponse(nodeRespData, respType=respType)
            %     vis.plotNodalResponse(nodeRespData, respComponent=component)
            %     vis.plotNodalResponse(nodeRespData, stepIdx=stepIdx)
            %     vis.plotNodalResponse(nodeRespData, opts=opts, ax=ax)
            %
            % Parameters
            % ----------
            % nodeRespData : struct
            %     Nodal response data, typically obtained from
            %     ``opsmat.post.getNodalResponse(odbTag)``. The struct must include an
            %     odbTag field so the corresponding model information can be
            %     loaded.
            % respType : string, optional
            %     Response type to visualize. Default is "disp". Common values
            %     include "disp", "vel", "accel", "reaction",
            %     "reactionIncInertia", "rayleighForces", and "pressure".
            %     Custom fields in nodeRespData are also accepted.
            % respComponent : string, optional
            %     Response component to visualize. Default is "magnitude". For
            %     vector responses, common values include "ux", "uy", "uz", "rx",
            %     "ry", "rz", and "magnitude". For custom fields, use a name in
            %     nodeRespData.(respType).dofs or a Layout-C subfield name.
            %     Scalar custom fields may use any label for the colorbar.
            % stepIdx : integer or string, optional
            %     Analysis step selector. Default is "absMax".
            %
            %     - "absMax": step with the maximum absolute response.
            %     - "absMin": step with the minimum absolute response.
            %     - "Max": step with the maximum response.
            %     - "Min": step with the minimum response.
            %     - integer: explicit step index.
            % opts : struct, optional
            %     Visualization options passed to plotter.PlotNodalResp. Start
            %     from vis.defaultPlotNodalResponseOptions for customization.
            % ax : matlab.graphics.axis.Axes, optional
            %     Target axes. If omitted or empty, a new figure/axes is created.
            %
            % Custom node response field layouts
            % ----------------------------------
            %     % Scalar:
            %     nodeRespData.MyScalar = [nStep x nNode]
            %
            %     % Vector with component list:
            %     nodeRespData.MyVector.data = [nStep x nNode x nComp]
            %     nodeRespData.MyVector.dofs = {'c1','c2',...}
            %
            %     % Layout-C:
            %     nodeRespData.MyLayoutC.c1 = [nStep x nNode]
            %     nodeRespData.MyLayoutC.c2 = [nStep x nNode]
            %
            %     % Optional node tags:
            %     nodeRespData.nodeTags = [nNode x 1]
            %     nodeRespData.MyVector.nodeTags = [nNode x 1]
            %
            % Example
            % -------
            %     nodeRespData = opsmat.post.getNodalResponse("MyODB");
            %     opsmat.vis.plotNodalResponse(nodeRespData);
            %     opsmat.vis.plotNodalResponse(nodeRespData, ...
            %         respType="disp", ...
            %         respComponent="magnitude", ...
            %         stepIdx="absMax");

            arguments
                obj (1,1) plotter.OpenSeesMatlabVis
                nodeRespData struct
                options.respType {mustBeTextScalar} = "disp"
                options.respComponent {mustBeTextScalar} = "magnitude"
                options.stepIdx = "absMax"
                options.opts (1,1) struct = struct()
                options.ax {plotter.OpenSeesMatlabVis.mustBeAxesOrEmpty} = []
            end

            odbTag = nodeRespData.odbTag;
            modelInfo = post.ODB.readModelInfo(obj.parent.opensees, odbTag);

            options.opts.field.type = options.respType;
            options.opts.field.component = options.respComponent;
            pr = plotter.PlotNodalResp(modelInfo, nodeRespData, options.ax, options.opts);
            pr.plotStep(options.stepIdx);
        end

        function app = plotNodalResponseGUI(obj, nodeRespData, options)
            % Open an interactive GUI for nodal response visualization.
            %
            % Syntax
            % ------
            %     app = vis.plotNodalResponseGUI(nodeRespData)
            %     app = vis.plotNodalResponseGUI(nodeRespData, opts=opts)
            %     app = vis.plotNodalResponseGUI(nodeRespData, respType="disp", respComponent="magnitude")
            %
            % Parameters
            % ----------
            % nodeRespData : struct
            %     Nodal response data, typically obtained from
            %     ``opsmat.post.getNodalResponse(odbTag)``.
            % respType : string, optional
            %     Initial response field. Default is "disp".
            % respComponent : string, optional
            %     Initial response component. Default is "magnitude".
            % stepIdx : integer or string, optional
            %     Initial step selector. Use a 0-based integer, "absMax",
            %     "absMin", "Max", or "Min".
            % opts : struct, optional
            %     Initial visualization options passed to plotter.PlotNodalRespGUI.

            arguments
                obj (1,1) plotter.OpenSeesMatlabVis
                nodeRespData struct
                options.respType {mustBeTextScalar} = "disp"
                options.respComponent {mustBeTextScalar} = "magnitude"
                options.stepIdx = "absMax"
                options.opts (1,1) struct = struct()
            end

            odbTag = nodeRespData(1).odbTag;
            modelInfo = post.ODB.readModelInfo(obj.parent.opensees, odbTag);
            app = plotter.PlotNodalRespGUI(modelInfo, nodeRespData, ...
                respType=options.respType, ...
                respComponent=options.respComponent, ...
                stepIdx=options.stepIdx, ...
                opts=options.opts);
        end

        function plotDeformation(obj, nodeRespData, options)
            % Visualize deformed model geometry from nodal displacement data.
            %
            %   plotDeformation is a convenience wrapper around the nodal response
            %   plotter. It enables deformation display, uses displacement data
            %   from nodeRespData, and allows direct control of deformation color,
            %   interpolation, scale factor, and undeformed-shape visibility.
            %
            % Syntax
            % ------
            %     vis.plotDeformation(nodeRespData)
            %     vis.plotDeformation(nodeRespData, scaleFactor=scale)
            %     vis.plotDeformation(nodeRespData, showUndeformed=tf)
            %     vis.plotDeformation(nodeRespData, ax=ax)
            %
            % Parameters
            % ----------
            % nodeRespData : struct
            %     Nodal response data containing displacement information,
            %     typically obtained from opsmat.post.getNodalResponse(odbTag).
            %     The struct must include an odbTag field.
            % stepIdx : integer or string, optional
            %     Analysis step selector. Default is "absMax". Supported string
            %     selectors include "absMax", "absMin", "Max", and "Min".
            % color : char or string, optional
            %     Solid color used for the deformed shape. Default is "blue".
            % useInterpolation : logical, optional
            %     Whether to use interpolation for smoother visualized
            %     deformation. Default is true.
            % scaleFactor : double, optional
            %     Deformation scale factor. Default is 1.0.
            % showUndeformed : logical, optional
            %     Whether to show the undeformed model together with the deformed
            %     shape. Default is false.
            % ax : matlab.graphics.axis.Axes, optional
            %     Target axes. If omitted or empty, a new figure/axes is created.
            %
            % Example
            % -------
            %     nodeRespData = opsmat.post.getNodalResponse("MyODB");
            %     opsmat.vis.plotDeformation(nodeRespData, ...
            %         stepIdx="absMax", ...
            %         color="red", ...
            %         useInterpolation=true, ...
            %         scaleFactor=20, ...
            %         showUndeformed=true);

            arguments
                obj (1,1) plotter.OpenSeesMatlabVis
                nodeRespData struct
                options.stepIdx = "absMax"
                options.color  string = "blue"
                options.useInterpolation (1,1) logical = true
                options.scaleFactor (1,1) double = 1.0
                options.showUndeformed (1,1) logical = false
                options.ax {plotter.OpenSeesMatlabVis.mustBeAxesOrEmpty} = []
            end

            odbTag = nodeRespData.odbTag;
            modelInfo = post.ODB.readModelInfo(obj.parent.opensees, odbTag);
            opts = obj.defaultPlotNodalResponseOptions;
            opts.deform.show = true;
            opts.deform.autoScale = false;
            opts.deform.scale = options.scaleFactor;
            opts.deform.showUndeformed = options.showUndeformed;
            opts.interp.useInterpolation = options.useInterpolation;
            opts.color.useColormap = false;
            opts.color.solidColor = options.color;
            pr = plotter.PlotNodalResp(modelInfo, nodeRespData, options.ax, opts);
            pr.plotStep(options.stepIdx);
        end

        function plotFrameResponse(obj, respData, options)
            % Visualize frame element response at a selected analysis step.
            %
            %   plotFrameResponse displays frame-element result fields such as
            %   section forces, section deformations, basic forces, basic
            %   deformations, local forces, and plastic deformation. The response
            %   data is typically collected from an ODB through the post-processing
            %   interface.
            %
            % Syntax
            % ------
            %     vis.plotFrameResponse(respData, respType=respType, respComponent=component, stepIdx=stepIdx, opts=opts, ax=ax)
            %
            % Parameters
            % ----------
            % respData : struct
            %     Frame response data containing element response information,
            %     typically obtained from
            %     ``opsmat.post.getElementResponse(odbTag, eleType="Frame")``.
            % respType : string, optional. The type of response to visualize. Default is "sectionForces". Common options include
            %     - 'sectionForces'
            %     - 'sectionDeformations'
            %     - 'basicForces'
            %     - 'basicDeformations'
            %     - 'localForces'
            %     - 'plasticDeformation'
            %     - Any custom field in respData.
            % respComponent : string, optional. The component of the response to visualize. Default is "MZ". Common options include
            %     - For 'sectionForces' and 'sectionDeformations', components include 'N','MZ','VY','MY','VZ','T'.
            %     - For 'basicForces', 'basicDeformations' and 'plasticDeformation', components include 'N','MZ','MY','T'.
            %     - For 'localForces', components include 'FX','FY','MZ' in 2D
            %       and 'FX','FY','FZ','MX','MY','MZ' in 3D.
            %     - For custom fields, use a name listed in respData.(respType).dofs or a Layout-C subfield name. Scalar custom fields may use any label for the colorbar.
            %
            % responseLocation : string, optional
            %     Controls where values are placed along each frame element.
            %
            %     - "" or "auto":
            %       Built-in responses use fixed rules:
            %       - sectionForces, sectionDeformations -> "section"
            %       - basicForces, basicDeformations, localForces,
            %         plasticDeformation -> "element"
            %     - "section":
            %       Values are interpreted as section/sample-point values and are
            %       placed using recorded sectionLocs. Use this for arrays such as
            %       [nStep x nEle x nSec] or [nStep x nEle x nSec x nComp].
            %     - "element":
            %       Values are placed uniformly along each element. A scalar is
            %       drawn as an element-constant diagram; two values are placed at
            %       element locations [0,1]. Use this for local/basic/end values.
            %
            % stepIdx : integer or "absMax", optional
            %     - The index of the analysis step to visualize. Default is "absMax".
            %     - If "absMax", the step with the maximum absolute response will be visualized.
            %     - If "absMin", the step with the minimum absolute response will be visualized.
            %     - If "Max", the step with the maximum response will be visualized.
            %     - If "Min", the step with the minimum response will be visualized.
            %     - If an integer, the step with the specified index will be visualized.
            %
            %     For large response histories, passing a numeric step index is
            %     faster than using "absMax", "absMin", "Max", or "Min", because
            %     those string selectors scan all analysis steps to find the
            %     requested peak step.
            %
            % opts : struct, optional
            %     Visualization options. Use ``vis.defaultPlotFrameResponseOptions`` to get default options.
            %
            % ax : matlab.graphics.axis.Axes, optional
            %     Target axes. If omitted, a new figure/axes will be created.
            %
            % Custom frame response field layouts
            % -----------------------------------
            %     % Element scalar, element-constant diagram:
            %     respData.MyScalar = [nStep x nEle]
            %     responseLocation="element"
            %
            %     % Element vector with component list:
            %     respData.MyVector.data = [nStep x nEle x nComp]
            %     respData.MyVector.dofs = {'c1','c2',...}
            %     responseLocation="element"
            %     
            %     % End-pair labels such as {'c1I','c1J'} or {'c11','c12'} 
            %     % can be plotted by passing respComponent="c1"; the two end values
            %     % are drawn at element locations [0,1]. A single matching
            %     % component is drawn as an element constant.
            %
            %     % Section-style vector, section/sample-point diagram:
            %     respData.MySection.data = [nStep x nEle x nSec x nComp]
            %     respData.MySection.dofs = {'c1','c2',...}
            %     responseLocation="section"
            %
            %     % Layout-C:
            %     respData.MyLayoutC.c1 = [nStep x nEle]
            %     responseLocation="element"
            %     respData.MyLayoutC.c1 = [nStep x nEle x nSec]
            %     responseLocation="section"
            %
            %     % For custom fields, set responseLocation explicitly when the
            %     % same data shape could mean either element or section values.
            %
            % Large-model example
            % -------------------
            %     opts = opsmat.vis.defaultPlotFrameResponseOptions;
            %     opts.showMaxMinLabel = "none";
            %     opts.performance.fastMode = true;
            %     opts.performance.maxSectionsPerElement = 12;
            %     opts.surf.show = false;
            %     opts.cbar.show = false;
            %     opts.color.useColormap = false;
            %
            %     opsmat.vis.plotFrameResponse(frameRespData, ...
            %         respType="sectionForces", ...
            %         respComponent="MZ", ...
            %         stepIdx=0, ...  % numeric step index is faster than "absMax"
            %         opts=opts);

            arguments
                obj (1,1) plotter.OpenSeesMatlabVis
                respData struct
                options.respType {mustBeTextScalar} = "sectionForces"
                options.respComponent {mustBeTextScalar} = "MZ"
                options.responseLocation {mustBeTextScalar} = ""
                options.stepIdx = "absMax"
                options.opts (1,1) struct = struct()
                options.ax {plotter.OpenSeesMatlabVis.mustBeAxesOrEmpty} = []
            end
            odbTag = respData.odbTag;
            modelInfo = post.ODB.readModelInfo(obj.parent.opensees, odbTag);

            options.opts.respType = options.respType;
            options.opts.component = options.respComponent;
            options.opts.responseLocation = options.responseLocation;

            pf = plotter.PlotFrameResp(modelInfo, respData, options.ax, options.opts);
            pf.plotStep(options.stepIdx);

        end

        function app = plotFrameResponseGUI(obj, respData, options)
            % Open an interactive GUI for frame element response diagrams.
            %
            %   plotFrameResponseGUI displays frame response data with controls
            %   for response type, component, step selection, style, scaling,
            %   colours, labels, and common performance options.
            %
            % Syntax
            % ------
            %     app = vis.plotFrameResponseGUI(respData)
            %     app = vis.plotFrameResponseGUI(respData, opts=opts)
            %     app = vis.plotFrameResponseGUI(respData, stepIdx=0)
            %
            % Parameters
            % ----------
            % respData : struct
            %     Frame response data, typically obtained from
            %     ``opsmat.post.getElementResponse(odbTag, eleType="Frame")``.
            % opts : struct, optional
            %     Initial visualization options passed to plotter.PlotFrameRespGUI.
            % stepIdx : integer or string, optional
            %     Initial step selector. Use a 0-based integer, "absMax",
            %     "absMin", "Max", or "Min".
            %
            % Returns
            % -------
            % app : struct
            %     GUI handles and helper callbacks. Use app.getOptions() to read
            %     the current PlotFrameResp option struct.

            arguments
                obj (1,1) plotter.OpenSeesMatlabVis
                respData struct
                options.opts (1,1) struct = struct()
                options.stepIdx = "absMax"
            end

            odbTag = respData(1).odbTag;
            modelInfo = post.ODB.readModelInfo(obj.parent.opensees, odbTag);
            app = plotter.PlotFrameRespGUI(modelInfo, respData, ...
                opts=options.opts, ...
                stepIdx=options.stepIdx);
        end

        function plotShellResponse(obj, respData, options)
            % Visualize Shell element response for a specific step.
            %
            % Example
            % -------
            %     plotShellResponse(respData)
            %     plotShellResponse(respData, respType="StressAtGP", ...
            %         respComponent="sxx", fiberPoint="top", ...
            %         stepIdx="absMax", ax=ax, opts=opts)
            %
            % Parameters
            % ----------
            % respData : struct
            %     Shell element response data. Typically obtained from ``post.getElementResponse(odbTag, eleType="Shell")``.
            %
            % respType : string, optional  (default "SecForceAtGP")
            %     - "SecForceAtGP" | "SecDefoAtGP" | "SecForceAtNode" | "SecDefoAtNode"
            %     - "StressAtGP" | "StrainAtGP" | "StressAtNode" | "StrainAtNode"
            %     - Any custom EleResp field name. Names containing "AtNode"
            %       are node-based; all other custom names are element-based.
            %
            % respComponent : string, optional  (default "mxx")
            %     - Section responses : "fxx" "fyy" "fxy" "mxx" "myy" "mxy" "vxz" "vyz"
            %     - Stress / Strain   : "sxx" "syy" "sxy" "syz" "sxz" | "exx" "eyy" "exy" "eyz" "exz"
            %     - For custom fields, a name listed in EleResp.(respType).dofs
            %       or a numeric subfield EleResp.(respType).(respComponent).
            %
            % responseLocation : string, optional
            %     Controls how the response rows are interpreted.
            %
            %     - "" or "auto":
            %       Infer from respType. Names containing "AtNode" are nodal;
            %       names containing "AtGP" are Gauss-point/element responses.
            %       Custom names without either token are treated as element data.
            %
            %     - "node":
            %       Response rows are nodes. Use [nStep x nNode] scalar data or
            %       [nStep x nNode x nComp] vector data.
            %
            %     - "gp":
            %       Response rows are elements with a Gauss-point dimension.
            %       Gauss-point values are averaged per element before plotting.
            %
            %     - "element":
            %       Response rows are already element-level values. If the data
            %       still contains a GP dimension, opts.surf.gpReduce controls
            %       the reduction.
            %
            % fiberPoint : string or integer, optional  (default "top")
            %     Through-thickness location for stress/strain responses.
            %     "top" | "bottom" | "middle"  or 1-based integer fiber index.
            %     Also applies to custom data with a fiber dimension:
            %     ```matlab
            %     EleResp.MyVector.data = [nStep x nEle x nGP x nFiber x nComp]
            %     EleResp.MyVectorAtNode.data = [nStep x nNode x nFiber x nComp]
            %     EleResp.MyLayoutC.c1 = [nStep x nEle x nGP x nFiber]
            %     EleResp.MyLayoutCAtNode.c1 = [nStep x nNode x nFiber]
            %     ```
            %
            % stepIdx : integer or string, optional  (default "absMax")
            %     "absMax" | "absMin" | "Max" | "Min" | integer step index.
            %
            % opts : struct, optional
            %     Visualisation options.
            %     Obtain defaults via plotter.PlotUnstruResponse.defaultOptions().
            %
            % ax : matlab.graphics.axis.Axes, optional
            %     Target axes. A new figure is created when omitted.
            %
            % Custom EleResp field layouts
            % ----------------------------
            %     % Element scalar:
            %     EleResp.MyScalar = [nStep x nEle]
            %     responseLocation="element"
            %
            %     % Node scalar:
            %     EleResp.MyScalarAtNode = [nStep x nNode]
            %     responseLocation="node"
            %
            %     % Element vector:
            %     EleResp.MyVector.data = [nStep x nEle x nComp]
            %     EleResp.MyVector.dofs = {'c1','c2',...}
            %     responseLocation="element"
            %
            %     % Node vector:
            %     EleResp.MyVectorAtNode.data = [nStep x nNode x nComp]
            %     EleResp.MyVectorAtNode.dofs = {'c1','c2',...}
            %     responseLocation="node"
            %
            %     % Element Layout-C:
            %     EleResp.MyLayoutC.c1 = [nStep x nEle]
            %     responseLocation="element"
            %     EleResp.MyLayoutC.c1 = [nStep x nEle x nGP]
            %     responseLocation="gp"
            %     EleResp.MyLayoutC.c1 = [nStep x nEle x nGP x nFiber]
            %     responseLocation="gp"
            %
            %     % Node Layout-C:
            %     EleResp.MyLayoutCAtNode.c1 = [nStep x nNode]
            %     responseLocation="node"
            %     EleResp.MyLayoutCAtNode.c1 = [nStep x nNode x nFiber]
            %     responseLocation="node"

            arguments
                obj     (1,1) plotter.OpenSeesMatlabVis
                respData struct

                options.respType {mustBeTextScalar} = "SecForceAtGP"
                options.respComponent {mustBeTextScalar} = "mxx"
                options.fiberPoint = "top"
                options.responseLocation {mustBeTextScalar} = ""
                options.stepIdx    = "absMax"
                options.opts          (1,1) struct = struct()
                options.ax            {plotter.OpenSeesMatlabVis.mustBeAxesOrEmpty} = []
            end

            odbTag = respData(1).odbTag;

            modelInfo = post.ODB.readModelInfo(obj.parent.opensees, odbTag);
            nodalResp = obj.parent.post.getNodalResponse(odbTag, respType="disp");
            options.opts.responseLocation = options.responseLocation;

            pu = plotter.PlotUnstruResponse( ...
                modelInfo, nodalResp, respData, options.ax, options.opts);
            pu.setResponse('Shell', options.respType, options.respComponent, ...
                options.fiberPoint);
            pu.plotStep(options.stepIdx);
        end

        function app = plotShellResponseGUI(obj, respData, options)
            % Open an interactive GUI for shell element response visualization.
            %
            % Syntax
            % ------
            %     app = vis.plotShellResponseGUI(respData)
            %     app = vis.plotShellResponseGUI(respData, opts=opts)
            %     app = vis.plotShellResponseGUI(respData, respType="StressAtGP", respComponent="sxx")

            arguments
                obj     (1,1) plotter.OpenSeesMatlabVis
                respData struct
                options.respType {mustBeTextScalar} = "SecForceAtGP"
                options.respComponent {mustBeTextScalar} = "mxx"
                options.fiberPoint = "top"
                options.responseLocation {mustBeTextScalar} = ""
                options.stepIdx    = "absMax"
                options.opts          (1,1) struct = struct()
            end

            odbTag = respData(1).odbTag;
            modelInfo = post.ODB.readModelInfo(obj.parent.opensees, odbTag);
            nodalResp = obj.parent.post.getNodalResponse(odbTag, respType="disp");
            options.opts.responseLocation = options.responseLocation;

            app = plotter.PlotUnstruResponseGUI( ...
                modelInfo, nodalResp, respData, ...
                eleType="Shell", ...
                respType=options.respType, ...
                respComponent=options.respComponent, ...
                fiberPoint=options.fiberPoint, ...
                stepIdx=options.stepIdx, ...
                opts=options.opts);
        end

        % -----------------------------------------------------------------

        function plotContinuumResponse(obj, respData, options)
            % Visualize Plane or Solid continuum element response for a step.
            %
            % Example
            % -------
            %     plotContinuumResponse(respData, eleType="Solid", ...
            %         respType="StressAtGP", respComponent="sigmavm", ...
            %         stepIdx="absMax", ax=ax, opts=opts)
            %
            % Parameters
            % ----------
            % respData : struct
            %     Continuum element response data. Typically obtained from
            %     ``post.getElementResponse(odbTag, eleType="Plane")`` or
            %     ``post.getElementResponse(odbTag, eleType="Solid")``.
            %
            % respType : string, optional  (default "StressAtGP")
            %     - "StressAtGP" | "StressAtNode" | "StrainAtGP" | "StrainAtNode"
            %     - "StressMeasureAtGP" | "StressMeasureAtNode"
            %     - Any custom EleResp field name. Element-based custom fields
            %       should normally use a name without "AtNode"; node-based
            %       custom fields should include "AtNode" in the field name.
            %
            % respComponent : string, optional  (default "sxx")
            %     - Plane stress  : "sxx" "syy" "sxy" "szz"
            %     - Solid stress  : "sxx" "syy" "szz" "sxy" "syz" "sxz"
            %     - Plane strain  : "exx" "eyy" "exy"
            %     - Solid strain  : "exx" "eyy" "ezz" "exy" "eyz" "exz"
            %     - Measures      : "sigmaOct" "tauOct" "tauMax" "vonMises"
            %                       "p1" "p2" "p3"
            %     - For custom fields, a name listed in EleResp.(respType).dofs
            %       or a numeric subfield EleResp.(respType).(respComponent).
            %       Scalar custom fields may use any label for the colorbar.
            %     - Layout-C custom fields use subfield names as components, so
            %       respComponent="c1" reads EleResp.(respType).c1.
            % responseLocation : string, optional
            %     Controls how the response rows are interpreted.
            %
            %     - "" or "auto":
            %       Infer from respType. Names containing "AtNode" are nodal;
            %       names containing "AtGP" are Gauss-point/element responses.
            %       Custom names without either token are treated as element data.
            %
            %     - "node":
            %       Response rows are nodes. Use [nStep x nNode] scalar data or
            %       [nStep x nNode x nComp] vector data.
            %
            %     - "gp":
            %       Response rows are elements with a Gauss-point dimension.
            %       Gauss-point values are averaged per element before plotting.
            %
            %     - "element":
            %       Response rows are already element-level values. If the data
            %       still contains a GP dimension, opts.surf.gpReduce controls
            %       the reduction.
            % stepIdx : integer or string, optional  (default "absMax")
            %     "absmax" | "absmin" | "max" | "min" | 0-based integer step index.
            %
            % opts : struct, optional
            %     Visualisation options.
            %     Obtain defaults via plotter.PlotUnstruResponse.defaultOptions().
            %
            % ax : matlab.graphics.axis.Axes, optional
            %     Target axes. A new figure is created when omitted.
            %
            % Custom EleResp field layouts
            % ----------------------------
            %     % The field name decides whether custom data is element- or
            %     % node-based. Names containing "AtNode" are node-based; all other
            %     % custom names are element-based.
            %
            %     % Element scalar:
            %     EleResp.MyScalar = [nStep x nEle]
            %     responseLocation="element"
            %
            %     % Node scalar:
            %     EleResp.MyScalarAtNode = [nStep x nNode]
            %     responseLocation="node"
            %
            %     % Element vector with component list:
            %     EleResp.MyVector.data = [nStep x nEle x nComp]
            %     EleResp.MyVector.dofs = {'c1','c2',...}
            %     responseLocation="element"
            %
            %     % Node vector with component list:
            %     EleResp.MyVectorAtNode.data = [nStep x nNode x nComp]
            %     EleResp.MyVectorAtNode.dofs = {'c1','c2',...}
            %     responseLocation="node"
            %
            %     % Element Layout-C:
            %     EleResp.MyLayoutC.c1 = [nStep x nEle]
            %     responseLocation="element"
            %     EleResp.MyLayoutC.c1 = [nStep x nEle x nGP]
            %     responseLocation="gp"
            %
            %     % Node Layout-C:
            %     EleResp.MyLayoutCAtNode.c1 = [nStep x nNode]
            %     responseLocation="node"
            arguments
                obj      (1,1) plotter.OpenSeesMatlabVis
                respData struct
                options.respType {mustBeTextScalar} = "StressAtGP"
                options.respComponent {mustBeTextScalar} = "sxx"
                options.responseLocation {mustBeTextScalar} = ""
                options.stepIdx   = "absmax"
                options.opts          (1,1) struct = struct()
                options.ax            {plotter.OpenSeesMatlabVis.mustBeAxesOrEmpty} = []
            end
            eleType = respData(1).eleType;
            switch lower(char(string(eleType)))
                case 'plane'
                    eleType = 'Plane';
                case {'solid', 'brick'}
                    eleType = 'Solid';
                otherwise
                    error('plotContinuumResponse:BadEleType', ...
                        'eleType must be "Plane" or "Solid". Got "%s".', eleType);
            end
            odbTag = respData(1).odbTag;
            modelInfo = post.ODB.readModelInfo(obj.parent.opensees, odbTag);
            nodalResp = obj.parent.post.getNodalResponse(odbTag, respType="disp");
            options.opts.responseLocation = options.responseLocation;
            pu = plotter.PlotUnstruResponse( ...
                modelInfo, nodalResp, respData, options.ax, options.opts);
            pu.setResponse(eleType, options.respType, options.respComponent);
            pu.plotStep(options.stepIdx);
        end

        function app = plotContinuumResponseGUI(obj, respData, options)
            % Open an interactive GUI for plane or solid continuum response visualization.
            %
            % Syntax
            % ------
            %     app = vis.plotContinuumResponseGUI(respData)
            %     app = vis.plotContinuumResponseGUI(respData, eleType="Solid")
            %     app = vis.plotContinuumResponseGUI(respData, respType="StressAtGP", respComponent="sxx")

            arguments
                obj      (1,1) plotter.OpenSeesMatlabVis
                respData struct
                options.eleType {mustBeTextScalar} = ""
                options.respType {mustBeTextScalar} = "StressAtGP"
                options.respComponent {mustBeTextScalar} = "sxx"
                options.responseLocation {mustBeTextScalar} = ""
                options.stepIdx   = "absMax"
                options.opts          (1,1) struct = struct()
            end

            eleType = options.eleType;
            if strlength(string(eleType)) == 0
                eleType = respData(1).eleType;
            end
            switch lower(char(string(eleType)))
                case 'plane'
                    eleType = 'Plane';
                case {'solid', 'brick'}
                    eleType = 'Solid';
                otherwise
                    error('plotContinuumResponseGUI:BadEleType', ...
                        'eleType must be "Plane" or "Solid". Got "%s".', eleType);
            end

            odbTag = respData(1).odbTag;
            modelInfo = post.ODB.readModelInfo(obj.parent.opensees, odbTag);
            nodalResp = obj.parent.post.getNodalResponse(odbTag, respType="disp");
            options.opts.responseLocation = options.responseLocation;

            app = plotter.PlotUnstruResponseGUI( ...
                modelInfo, nodalResp, respData, ...
                eleType=eleType, ...
                respType=options.respType, ...
                respComponent=options.respComponent, ...
                stepIdx=options.stepIdx, ...
                opts=options.opts);
        end

    end

    methods (Access = private)
        function parentObj = getParent(obj)
            parentObj = obj.parent;
        end
    end

    methods (Static, Access = private)
        function mustBeAxesOrEmpty(ax)
            if isempty(ax)
                return;
            end
            mustBeA(ax, ["matlab.graphics.axis.Axes", "matlab.ui.control.UIAxes"]);
        end
    end
end
