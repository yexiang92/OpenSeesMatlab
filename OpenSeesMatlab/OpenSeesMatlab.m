classdef OpenSeesMatlab < handle
    % MATLAB interface for OpenSees commands.
    %
    %   ``OpenSeesMatlab`` provides a user-facing MATLAB interface for executing
    %   OpenSees commands through the OpenSees MATLAB MEX module.
    %   ``OpenSeesMatlab`` implements all OpenSees commands, and the command calls have the same format as ``OpenSeesPy``. Please refer to the following for various commands:
    %
    % [OpenSeesPy](https://openseespydoc.readthedocs.io/en/latest/index.html)
    %
    % [OpenSees](https://opensees.github.io/OpenSeesDocumentation/)
    %
    %   Example
    %   -------
    %       opsmat = OpenSeesMatlab();
    %       ops = opsmat.opensees;  % Get the OpenSees command interface
    %
    %       ops.wipe();
    %       ops.model('basic', '-ndm', 2, '-ndf', 3);
    %       ...
    %       ops.node(1, 0.0, 0.0);
    %       ops.node(2, 5.0, 0.0);
    %       ops.fix(1, 1, 1, 1);
    %       ops.element(...);
    %       ...
    %       opsmat.post.getModelData();  % Collect model data for post-processing
    %       opsmat.vis.plotModel();  % Visualize the model
    % 

    properties (SetAccess = private, GetAccess = public)
        opensees OpenSeesMatlabCmds  % The main OpenSees command interface. An instance of ``OpenSeesMatlabCmds``
        post OpenSeesMatlabPost    % Post-processing interface. An instance of ``OpenSeesMatlabPost``
        vis OpenSeesMatlabVis      % Visualization interface. An instance of ``OpenSeesMatlabVis``
        pre OpenSeesMatlabPre      % Pre-processing interface. An instance of ``OpenSeesMatlabPre``
        anlys OpenSeesMatlabAnalysis  % Analysis management interface. An instance of ``OpenSeesMatlabAnalysis``
        utils OpenSeesMatlabTool    % Utility tools interface. An instance of ``OpenSeesMatlabTool``
    end

    methods
        function obj = OpenSeesMatlab(options)
            % Construct an OpenSees MATLAB interface object.
            %
            %   ``ops = OpenSeesMatlab()`` creates an object using the default
            %   MEX module name.
            %
            %   ``ops = OpenSeesMatlab(mexName=<name>, mexDir=<dir>)`` creates 
            %   an object with specified options.
            %
            % Parameters
            % ----------
            % mexName : string or char, optional
            %       Name of the OpenSees MATLAB MEX module.
            %
            % mexDir : string or char, optional
            %       Directory containing the MEX module.
            %       Default values are 'OpenSeesMATLAB' for mexName and 'derived/' for mexDir.

            arguments
                options.mexName  {mustBeTextScalar} = 'OpenSeesMATLAB'
                options.mexDir {mustBeTextScalar} = 'derived/'
            end

            obj.opensees = OpenSeesMatlabCmds(obj, options.mexName, options.mexDir);

            % Initialize the bookkeeping data manager
            obj.vis = OpenSeesMatlabVis(obj);
            obj.post = OpenSeesMatlabPost(obj);
            obj.utils = OpenSeesMatlabTool(obj);
            obj.anlys = OpenSeesMatlabAnalysis(obj);
            obj.pre = OpenSeesMatlabPre(obj);
        end
    end

    % Additional methods for OpenSeesMatlab can be added here, such as high-level
    methods
    
    end
end