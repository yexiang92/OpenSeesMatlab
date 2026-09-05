classdef OpenSeesMatlab < handle
    % OpenSeesMatlab Main MATLAB interface for OpenSees.
    %
    %   OpenSeesMatlab is the top-level entry point of this toolbox. It creates
    %   and connects the OpenSees command interface, pre-processing utilities,
    %   analysis helpers, post-processing tools, visualization tools, and general
    %   utilities around an OpenSees MATLAB MEX module.
    %
    %   The OpenSees commands are accessed through the opensees property:
    %
    %       opsmat = OpenSeesMatlab();
    %       ops = opsmat.opensees;
    %
    %   Command syntax follows OpenSeesPy/OpenSees command conventions as closely
    %   as possible. For command-level details, refer to:
    %
    %   OpenSeesPy: https://openseespydoc.readthedocs.io/en/latest/index.html
    %
    %   OpenSees  : https://opensees.github.io/OpenSeesDocumentation/
    %
    % Syntax
    % ------
    %       opsmat = OpenSeesMatlab()
    %       opsmat = OpenSeesMatlab(backend=name)
    %       opsmat = OpenSeesMatlab(mexName=name)
    %       opsmat = OpenSeesMatlab(mexDir=dir)
    %       opsmat = OpenSeesMatlab(mexName=name, mexDir=dir)
    %
    % Properties
    % ----------
    % opensees : OpenSeesMatlabCmds
    %     OpenSees command wrapper. Use this object to call OpenSees commands
    %     such as wipe, model, node, element, system, numberer, constraints,
    %     integrator, algorithm, analysis, analyze, recorder, and related APIs.
    % pre : OpenSeesMatlabPre
    %     Pre-processing utilities, including section-geometry recording,
    %     unit-system utilities, mesh import helpers, mass/matrix utilities, and
    %     load transformation helpers.
    % anlys : OpenSeesMatlabAnalysis
    %     Analysis utilities. Includes smartAnalyze for robust transient/static
    %     analysis with retries, algorithm switching, step splitting, and progress
    %     reporting.
    % post : OpenSeesMatlabPost
    %     Post-processing utilities for collecting model information, eigen data,
    %     and response data, and for saving/loading output databases.
    % vis : OpenSeesMatlabVis
    %     Visualization utilities for model geometry, mode shapes, deformations,
    %     nodal responses, frame responses, shell responses, and continuum
    %     responses.
    % utils : OpenSeesMatlabTool
    %     General helper tools, including example-model loading.
    %
    % Example
    % -------
    %       opsmat = OpenSeesMatlab();
    %       ops = opsmat.opensees;
    %
    %       ops.wipe();
    %       ops.model('basic', '-ndm', 2, '-ndf', 3);
    %       ops.node(1, 0.0, 0.0);
    %       ops.node(2, 5.0, 0.0);
    %       ops.fix(1, 1, 1, 1);
    %       ops.fix(2, 0, 1, 0);
    %
    %       % Define materials, sections, elements, loads, and analysis commands.
    %       % The calls follow OpenSees/OpenSeesPy-style command arguments.
    %       % ops.uniaxialMaterial(...);
    %       % ops.element(...);
    %       % ops.timeSeries(...);
    %       % ops.pattern(...);
    %
    %       modelInfo = opsmat.post.getModelData();
    %       h = opsmat.vis.plotModel();
    %

    properties (SetAccess = private, GetAccess = public)
        opensees ops.OpenSeesMatlabCmds      % OpenSees command interface.
        post post.OpenSeesMatlabPost          % Post-processing interface.
        vis plotter.OpenSeesMatlabVis            % Visualization interface.
        pre pre.OpenSeesMatlabPre            % Pre-processing interface.
        anlys analysis.OpenSeesMatlabAnalysis     % Analysis management interface.
        utils utils.OpenSeesMatlabTool         % General utility interface.
    end

    properties (SetAccess = private, GetAccess = public)
        version = [];           % Compatibility alias for bindingVersion.
        bindingVersion = [];    % OpenSeesNexus MATLAB package version.
        openseesVersion = [];   % OpenSees engine version.
        backend = "serial";     % Active native backend: serial or sp.
    end

    methods
        function obj = OpenSeesMatlab(options)
            % Construct the main OpenSeesMatlab interface.
            %
            %   The constructor creates the OpenSees command wrapper first, then
            %   initializes visualization, post-processing, utility, analysis, and
            %   pre-processing helper objects that share the same parent interface.
            %
            % Syntax
            % ------
            %       opsmat = OpenSeesMatlab()
            %       opsmat = OpenSeesMatlab(backend=name)
            %       opsmat = OpenSeesMatlab(mexName=name)
            %       opsmat = OpenSeesMatlab(mexDir=dir)
            %       opsmat = OpenSeesMatlab(mexName=name, mexDir=dir)
            %
            % Parameters
            % ----------
            % backend : "serial" | "sp", optional
            %     Backend selected before native initialization. The default is
            %     the current OpenSeesNexus selection, initially "serial".
            % mexName : string or char, optional
            %     Explicit OpenSees MATLAB MEX module name. Leave empty to use
            %     OpenSeesMATLAB for serial or OpenSeesMATLABSP for SP.
            %
            % mexDir : string or char, optional
            %     Directory containing the OpenSees MATLAB MEX module. Relative
            %     paths are resolved by OpenSeesNexus relative to its embedded library
            %     location when supplied. By default the current platform is
            %     selected under +ops/OpenSeesNexus/derived.
            %
            % Example
            % -------
            %       opsmat = OpenSeesMatlab();
            %       ops = opsmat.opensees;
            %
            %       opsmatCustom = OpenSeesMatlab( ...
            %           mexName="OpenSeesMATLAB", ...
            %           mexDir="D:/custom/opensees");

            arguments
                options.backend {mustBeTextScalar} = ''
                options.mexName {mustBeTextScalar} = ''
                options.mexDir {mustBeTextScalar} = ''
            end

            ops.connectOpenSeesNexus();
            if strlength(string(options.backend)) > 0
                OpenSeesNexus.setBackend(options.backend);
            end

            obj.opensees = ops.OpenSeesMatlabCmds(obj, options.mexName, options.mexDir);

            % Initialize the bookkeeping data manager
            obj.vis = plotter.OpenSeesMatlabVis(obj);
            obj.post = post.OpenSeesMatlabPost(obj);
            obj.utils = utils.OpenSeesMatlabTool(obj);
            obj.anlys = analysis.OpenSeesMatlabAnalysis(obj);
            obj.pre = pre.OpenSeesMatlabPre(obj);

            obj.backend = OpenSeesNexus.getBackend();
            obj.bindingVersion = obj.opensees.matlabversion();
            obj.openseesVersion = obj.opensees.openseesVersion();
            obj.version = obj.bindingVersion;
        end
    end

    % Additional methods for OpenSeesMatlab can be added here, such as high-level
    methods

    end
end
