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
    %     Default option template used by plotModel.
    % defaultPlotEigenOptions : struct
    %     Default option template used by plotEigen.
    % defaultPlotNodalResponseOptions : struct
    %     Default option template used by plotNodalResponse and plotDeformation.
    % defaultPlotFrameResponseOptions : struct
    %     Default option template used by plotFrameResponse.
    % defaultPlotShellResponseOptions : struct
    %     Default option template used by shell response plotting.
    % defaultPlotContinuumResponseOptions : struct
    %     Default option template used by continuum response plotting.

    properties (Access = private)
        parent  % Reference to the parent OpenSeesMatlab object
    end

    properties (Access = public)
        defaultPlotModelOptions = plotter.PlotModel.defaultOptions();
        % Default options for plotModel
    end

    properties (Access = public)
        defaultPlotEigenOptions = plotter.PlotEigen.defaultOptions();
        % Default options for plotEigen
    end

    properties (Access = public)
        defaultPlotNodalResponseOptions = plotter.PlotNodalResp.defaultOptions();
        % Default options for plotNodalResponse
    end

    properties (Access = public)
        defaultPlotFrameResponseOptions = plotter.PlotFrameResp.defaultOptions();
        % Default options for plotFrameResponse
    end

    properties (Access = public)
        defaultPlotShellResponseOptions = plotter.PlotUnstruResponse.defaultOptions();
        % Default options for plotShellResponse
    end

    properties (Access = public)
        defaultPlotContinuumResponseOptions = plotter.PlotUnstruResponse.defaultOptions();
        % Default options for plotContinuumResponse
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
                obj (1,1) OpenSeesMatlabVis
                options.opts (1,1) struct = struct()
                options.ax {OpenSeesMatlabVis.mustBeAxesOrEmpty} = []
            end

            modelInfo = obj.parent.post.getModelData();

            if isempty(options.ax)
                pm = plotter.PlotModel(modelInfo, [], options.opts);
            else
                pm = plotter.PlotModel(modelInfo, options.ax, options.opts);
            end

            h = pm.plot();
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
                obj (1,1) OpenSeesMatlabVis
                modeTag (1,1) double {mustBeInteger, mustBePositive}
                eigenData (1,1) struct
                options.opts (1,1) struct = struct()
                options.ax {OpenSeesMatlabVis.mustBeAxesOrEmpty} = []
            end

            modelInfo = obj.parent.post.getModelData();
            pe = plotter.PlotEigen(modelInfo, eigenData, options.ax, options.opts);
            h = pe.plotMode(modeTag);
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
            %     opsmat.post.getNodalResponse(odbTag). The struct must include an
            %     odbTag field so the corresponding model information can be
            %     loaded.
            % respType : string, optional
            %     Response type to visualize. Default is "disp". Common values
            %     include "disp", "vel", "accel", "reaction",
            %     "reactionIncInertia", "rayleighForces", and "pressure".
            % respComponent : string, optional
            %     Response component to visualize. Default is "magnitude". For
            %     vector responses, common values include "x", "y", "z", "rx",
            %     "ry", "rz", and "magnitude".
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
            % Example
            % -------
            %     nodeRespData = opsmat.post.getNodalResponse("MyODB");
            %     opsmat.vis.plotNodalResponse(nodeRespData);
            %     opsmat.vis.plotNodalResponse(nodeRespData, ...
            %         respType="disp", ...
            %         respComponent="magnitude", ...
            %         stepIdx="absMax");

            arguments
                obj (1,1) OpenSeesMatlabVis
                nodeRespData (1,1) struct
                options.respType (1,1) string = "disp"
                options.respComponent (1,1) string = "magnitude"
                options.stepIdx (1,1) = "absMax"
                options.opts (1,1) struct = struct()
                options.ax {OpenSeesMatlabVis.mustBeAxesOrEmpty} = []
            end

            odbTag = nodeRespData.odbTag;
            modelInfo = post.ODB.loadODB(odbTag, groups=post.resp.ModelInfoStepData.RESP_NAME);

            options.opts.field.type = options.respType;
            options.opts.field.component = options.respComponent;
            pr = plotter.PlotNodalResp(modelInfo, nodeRespData, options.ax, options.opts);
            pr.plotStep(options.stepIdx);
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
            %     vis.plotDeformation(nodeRespData, stepIdx=stepIdx)
            %     vis.plotDeformation(nodeRespData, color=color)
            %     vis.plotDeformation(nodeRespData, useInterpolation=tf)
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
                obj (1,1) OpenSeesMatlabVis
                nodeRespData (1,1) struct
                options.stepIdx (1,1) = "absMax"
                options.color (1,1) string = "blue"
                options.useInterpolation (1,1) logical = true
                options.scaleFactor (1,1) double = 1.0
                options.showUndeformed (1,1) logical = false
                options.ax {OpenSeesMatlabVis.mustBeAxesOrEmpty} = []
            end

            odbTag = nodeRespData.odbTag;
            modelInfo = post.ODB.loadODB(odbTag, groups=post.resp.ModelInfoStepData.RESP_NAME);
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
            %     vis.plotFrameResponse(respData)
            %     vis.plotFrameResponse(respData, respType=respType)
            %     vis.plotFrameResponse(respData, respComponent=component)
            %     vis.plotFrameResponse(respData, stepIdx=stepIdx)
            %     vis.plotFrameResponse(respData, opts=opts, ax=ax)
            %
            % Parameters
            % ----------
            % respData : struct
            %     Frame response data containing element response information,
            %     typically obtained from
            %     opsmat.post.getElementResponse(odbTag, eleType="Frame").
            % respType : string, optional. The type of response to visualize. Default is "sectionForces". Common options include
            %     - 'sectionForces'
            %     - 'sectionDeformations'
            %     - 'basicForces'
            %     - 'basicDeformations'
            %     - 'localForces'
            %     - 'plasticDeformation'
            % respComponent : string, optional. The component of the response to visualize. Default is "MZ". Common options include
            %     - For 'sectionForces' and 'sectionDeformations', components include 'N','MZ','VY','MY','VZ','T'.
            %     - For 'basicForces', 'basicDeformations' and 'plasticDeformation', components include 'N','MZ','MY','T'.
            %     - For 'localForces', components include 'FX','FY','FZ','MX','MY','MZ'.
            % stepIdx : integer or "absMax", optional
            %     - The index of the analysis step to visualize. Default is "absMax".
            %     - If "absMax", the step with the maximum absolute response will be visualized.
            %     - If "absMin", the step with the minimum absolute response will be visualized.
            %     - If "Max", the step with the maximum response will be visualized.
            %     - If "Min", the step with the minimum response will be visualized.
            %     - If an integer, the step with the specified index will be visualized.
            % opts : struct, optional
            %     Visualization options. Use ``vis.defaultPlotFrameResponseOptions`` to get default options.
            % ax : matlab.graphics.axis.Axes, optional
            %     Target axes. If omitted, a new figure/axes will be created.

            arguments
                obj (1,1) OpenSeesMatlabVis
                respData (1,1) struct
                options.respType (1,1) string = "sectionForces"
                options.respComponent (1,1) string = "MZ"
                options.stepIdx (1,1) = "absMax"
                options.opts (1,1) struct = struct()
                options.ax {OpenSeesMatlabVis.mustBeAxesOrEmpty} = []
            end
            odbTag = respData.odbTag;
            modelInfo = post.ODB.loadODB(odbTag, groups=post.resp.ModelInfoStepData.RESP_NAME);

            options.opts.respType = options.respType;
            options.opts.component = options.respComponent;

            pf = plotter.PlotFrameResp(modelInfo, respData, options.ax, options.opts);
            pf.plotStep(options.stepIdx);

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
            %
            % respComponent : string, optional  (default "mxx")
            %     - Section responses : "fxx" "fyy" "fxy" "mxx" "myy" "mxy" "vxz" "vyz"
            %     - Stress / Strain   : "sxx" "syy" "sxy" "syz" "sxz" | "exx" "eyy" "exy" "eyz" "exz"
            %
            % fiberPoint : string or integer, optional  (default "top")
            %     Through-thickness location for stress/strain responses.
            %     "top" | "bottom" | "middle"  or 1-based integer fiber index.
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

            arguments
                obj     (1,1) OpenSeesMatlabVis
                respData (1,1) struct

                options.respType      (1,1) string = "SecForceAtGP"
                options.respComponent (1,1) string = "mxx"
                options.fiberPoint                 = "top"
                options.stepIdx       (1,1)        = "absMax"
                options.opts          (1,1) struct = struct()
                options.ax            {OpenSeesMatlabVis.mustBeAxesOrEmpty} = []
            end

            odbTag = respData.odbTag;
            modelInfo = post.ODB.loadODB(odbTag, ...
                groups = post.resp.ModelInfoStepData.RESP_NAME);
            nodalResp = obj.parent.post.getNodalResponse(odbTag, respType="disp");

            pu = plotter.PlotUnstruResponse( ...
                modelInfo, nodalResp, respData, options.ax, options.opts);
            pu.setResponse('Shell', options.respType, options.respComponent, ...
                options.fiberPoint);
            pu.plotStep(options.stepIdx);
        end

        % -----------------------------------------------------------------

        function plotContinuumResponse(obj, respData, options)
            % Visualize Plane or Solid continuum element response for a step.
            %
            % Example
            % -------
            %     plotContinuumResponse(respData)
            %     plotContinuumResponse(respData, eleType="Solid", ...
            %         respType="StressAtGP", respComponent="sigmavm", ...
            %         stepIdx="absMax", ax=ax, opts=opts)
            %
            % Parameters
            % ----------
            % respData : struct
            %     Continuum element response data. Typically obtained from ``post.getElementResponse(odbTag, eleType="Plane")`` or ``post.getElementResponse(odbTag, eleType="Solid")``.
            % respType : string, optional  (default "StressAtGP")
            %     - "StressAtGP" | "StressAtNode" | "StrainAtGP" | "StrainAtNode"
            %     - "StressMeasureAtGP" | "StressMeasureAtNode"
            %
            % respComponent : string, optional  (default "sxx")
            %     - Plane tensor  : "sxx" "syy" "sxy" "szz"
            %     - Solid tensor  : "sxx" "syy" "szz" "sxy" "syz" "sxz"
            %     - Plane strain  : "exx" "eyy" "exy"
            %     - Solid strain  : "exx" "eyy" "ezz" "exy" "eyz" "exz"
            %     - Measures      : "p1" "p2" "p3" "sigmavm" "taumax" "sigmaoct" "tauoct"
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

            arguments
                obj     (1,1) OpenSeesMatlabVis
                respData (1,1) struct

                options.respType      (1,1) string = "StressAtGP"
                options.respComponent (1,1) string = "sxx"
                options.stepIdx       (1,1)        = "absMax"
                options.opts          (1,1) struct = struct()
                options.ax            {OpenSeesMatlabVis.mustBeAxesOrEmpty} = []
            end

            eleType = respData.eleType;

            switch lower(char(eleType))
                case 'plane'
                    eleType  = 'Plane';
                case {'solid', 'brick'}
                    eleType  = 'Solid';
                otherwise
                    error('plotContinuumResponse:BadEleType', ...
                        'eleType must be "Plane" or "Solid". Got "%s".', ...
                        eleType);
            end

            odbTag = respData.odbTag;
            modelInfo = post.ODB.loadODB(odbTag, ...
                groups = post.resp.ModelInfoStepData.RESP_NAME);
            nodalResp = obj.parent.post.getNodalResponse(odbTag, respType="disp");

            pu = plotter.PlotUnstruResponse( ...
                modelInfo, nodalResp, respData, options.ax, options.opts);
            pu.setResponse(eleType, options.respType, options.respComponent);
            pu.plotStep(options.stepIdx);
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
