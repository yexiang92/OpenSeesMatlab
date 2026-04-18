classdef OpenSeesMatlabVis < handle
    % Visualization interface for OpenSeesMatlab.
    %   OpenSeesMatlabVis provides methods for visualizing OpenSees models and results.

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
            if nargin < 1 || isempty(parentObj)
                error('OpenSeesMatlabVis:InvalidInput', ...
                    'A parent OpenSeesMatlab object is required.');
            end
            obj.parent = parentObj;
        end

        function h = plotModel(obj, options)
            % Visualize the OpenSees model.
            %
            % Example
            % --------
            %     h = plotModel();
            %     h = plotModel(opts=opts, ax=ax);
            %
            % Parameters
            % -----------
            % opts : struct, optional
            %     Visualization options. Use ``vis.defaultPlotModelOptions`` to get default options.
            % ax : matlab.graphics.axis.Axes, optional
            %     Target axes. If omitted, a new figure/axes will be created by
            %     PatchPlotter.
            %
            % Returns
            % --------
            % h : array of graphics objects
            %     Handles to the created graphics objects.

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
            % Visualize a specific mode shape from eigenvalue analysis results.
            %
            % Example
            % ---------
            %     h = plotEigen(modeTag, eigenData)
            %     h = plotEigen(modeTag, eigenData, opts=opts, ax=ax)
            %
            % Parameters
            % -----------
            % modeTag : integer
            %     The mode number to visualize (e.g., 1 for the first mode).
            % eigenData : struct
            %     Eigenvalue analysis results, typically obtained from ``post.getEigenData()``.
            % opts : struct, optional
            %     Visualization options. Use ``vis.defaultPlotEigenOptions`` to get default options.
            % ax : matlab.graphics.axis.Axes, optional
            %     Target axes. If omitted, a new figure/axes will be created.
            %
            % Returns
            % --------
            % h : array of graphics objects
            %     Handles to the created graphics objects.

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
            % Visualize nodal response data for a specific analysis step.
            %
            % Example
            % ---------
            %     plotNodalResponse(nodeRespData)
            %     plotNodalResponse(nodeRespData, stepIdx="absMax", opts=opts, ax=ax)
            %
            % Parameters
            % -----------
            % nodeRespData : struct
            %     Nodal response data, typically obtained from ``post.getNodalResponse(odbTag)``.
            % respType : string, optional
            %     The type of response to visualize. Default is "disp" (displacement).
            %     Common options include 'disp','vel','accel','reaction','reactionIncInertia', 'rayleighForces','pressure'.
            % respComponent : string, optional
            %     The component of the response to visualize. Default is "magnitude".
            %     For vector responses, options include "x", "y", "z", "rx", "ry", "rz", "magnitude", etc.
            % stepIdx : integer or "absMax", optional
            %     - The index of the analysis step to visualize. Default is "absMax".
            %     - If "absMax", the step with the maximum absolute response will be visualized.
            %     - If "absMin", the step with the minimum absolute response will be visualized.
            %     - If "Max", the step with the maximum response will be visualized.
            %     - If "Min", the step with the minimum response will be visualized.
            %     - If ``Integer``, the step with the specified index will be visualized.
            % opts : struct, optional
            %     Visualization options. Use ``vis.defaultPlotNodalResponseOptions`` to get default options.
            % ax : matlab.graphics.axis.Axes, optional
            %     Target axes. If omitted, a new figure/axes will be created.
            
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
            % Visualize deformation for a specific analysis step.
            %
            % Example
            % ---------
            %     plotDeformation(nodeRespData)
            %     plotDeformation(nodeRespData, stepIdx="absMax", opts=opts, ax=ax)
            %
            % Parameters
            % -----------
            % nodeRespData : struct
            %     Nodal response data containing displacement information, typically obtained from ``post.getNodalResponse(odbTag)``.
            % stepIdx : integer or "absMax", optional
            %     - The index of the analysis step to visualize. Default is "absMax".
            %     - If "absMax", the step with the maximum absolute response will be visualized.
            %     - If "absMin", the step with the minimum absolute response will be visualized.
            %     - If "Max", the step with the maximum response will be visualized.
            %     - If "Min", the step with the minimum response will be visualized.
            %     - If ``Integer``, the step with the specified index will be visualized.
            % color : char | string, optional
            %     Color for the deformed shape. Default is "blue".
            % useInterpolation : logical, optional
            %     Whether to use interpolation for smoother visualization. Default is true.
            % scaleFactor : double, optional
            %     Scale factor for deformation. Default is 1.0 (no scaling).
            % showUndeformed : logical, optional
            %     Whether to show the undeformed shape as well. Default is false.
            % ax : matlab.graphics.axis.Axes, optional
            %     Target axes. If omitted, a new figure/axes will be created.
            
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
            % Visualize frame element response for a specific analysis step.
            %
            % Example
            % ---------
            %     plotFrameResponse(respData)
            %     plotFrameResponse(respData, stepIdx="absMax", opts=opts, ax=ax)
            %
            % Parameters
            % -----------
            % respData : struct
            %     Frame response data containing element response information, typically obtained from ``post.getElementResponse(odbTag, eleType="Frame")``.
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
            %     (Measure components auto-redirect respType to StressMeasureAtGP/Node)
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