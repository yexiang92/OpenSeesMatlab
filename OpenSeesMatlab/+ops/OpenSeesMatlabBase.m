classdef (Abstract) OpenSeesMatlabBase < handle
    % OpenSeesMatlabBase Base class for OpenSees MATLAB MEX command wrappers.
    %
    %   OpenSeesMatlabBase provides the shared infrastructure used by the
    %   OpenSeesMatlab command interface. It resolves the OpenSees MEX module,
    %   adds the configured MEX directory to the MATLAB path, stores a function
    %   handle to the MEX entry point, and exposes lightweight helper methods for
    %   dispatching OpenSees commands.
    %
    %   This class is abstract and is not intended to be used directly by end
    %   users. User-facing command access is provided through OpenSeesMatlabCmds,
    %   which derives from this class and defines explicit wrappers for OpenSees
    %   commands such as model, node, element, analysis, analyze, and recorder.
    %
    % Typical use through OpenSeesMatlab
    % ----------------------------------
    %     opsmat = OpenSeesMatlab();
    %     ops = opsmat.opensees;
    %
    %     ops.wipe();
    %     ops.model('basic', '-ndm', 2, '-ndf', 3);
    %     ops.node(1, 0.0, 0.0);
    %
    % Notes
    % -----
    %     The command argument style follows the OpenSees/OpenSeesPy command
    %     style. String and character inputs are passed through to the MEX module,
    %     so command arguments should match the OpenSees command documentation.

    properties
        mexName {mustBeTextScalar} = "OpenSeesMATLAB"
        mexDir  {mustBeTextScalar} = "derived/"
    end

    properties (Hidden, Access = protected)
        mexHandle = []
    end

    methods
        function obj = OpenSeesMatlabBase(mexName, mexDir)
            % Construct an OpenSeesMatlabBase wrapper around an OpenSees MEX module.
            %
            % Syntax
            % ------
            %     obj = OpenSeesMatlabBase()
            %     obj = OpenSeesMatlabBase(mexName)
            %     obj = OpenSeesMatlabBase(mexName, mexDir)
            %
            % Parameters
            % ----------
            % mexName : string or char, optional
            %     Name of the OpenSees MATLAB MEX function. The default is
            %     'OpenSeesMATLAB'.
            % mexDir : string or char, optional
            %     Directory containing the OpenSees MATLAB MEX function. Relative
            %     paths are resolved relative to the directory containing this
            %     class when possible. If the resolved directory exists, it is
            %     added to the MATLAB path.
            %
            % Errors
            % ------
            % OpenSeesMatlab:MexNotFound
            %     Thrown when the configured MEX function cannot be located on the
            %     MATLAB path after resolving mexDir.
            %
            % Example
            % -------
            %     baseObj = SomeConcreteOpenSeesWrapper('OpenSeesMATLAB', 'derived/');

            if nargin >= 1 && ~isempty(mexName)
                obj.mexName = char(mexName);
            end
            if nargin >= 2 && ~isempty(mexDir)
                obj.mexDir = obj.resolveMexDir(char(mexDir));
                if isfolder(obj.mexDir)
                    addpath(obj.mexDir);
                end
            end

            obj.mexHandle = str2func(obj.mexName);

            if isempty(which(obj.mexName))
                error('OpenSeesMatlab:MexNotFound', ...
                    ['Cannot locate the OpenSees MEX module "%s". ', ...
                    'Resolved mexDir: %s'], ...
                    obj.mexName, obj.mexDir);
            end
        end

        function varargout = call(obj, cmd, varargin)
            % Call an OpenSees command through the configured MEX function.
            %
            % Syntax
            % ------
            %     obj.call(cmd, arg1, arg2, ...)
            %     [out1, out2, ...] = obj.call(cmd, arg1, arg2, ...)
            %
            % Parameters
            % ----------
            % cmd : char or string
            %     OpenSees command name, for example 'model', 'node', 'element',
            %     'analysis', or 'analyze'.
            % arg1, arg2, ... : any
            %     Command arguments passed directly to the OpenSees MEX module.
            %
            % Returns
            % -------
            % varargout
            %     Outputs returned by the OpenSees MEX module for the requested
            %     command.
            %
            % Example
            % -------
            %     obj.call('model', 'basic', '-ndm', 2, '-ndf', 3);
            %     obj.call('node', 1, 0.0, 0.0);

            if isstring(cmd)
                cmd = char(cmd);
            end
            [varargout{1:nargout}] = obj.mexHandle(cmd, varargin{:});
        end

        function tf = hasMex(obj)
            % Check whether this wrapper has a MEX function handle.
            %
            % Syntax
            % ------
            %     tf = obj.hasMex()
            %
            % Returns
            % -------
            % tf : logical
            %     True when the wrapper stores a nonempty MEX function handle.
            %
            % Notes
            % -----
            %     This method checks the stored function handle. Use mexPath to
            %     inspect the resolved path returned by MATLAB's which function.

            tf = ~isempty(obj.mexHandle);
        end

        function fn = getMexHandle(obj)
            % Get the raw MEX function handle for direct low-overhead calls.
            %
            %   The returned handle bypasses MATLAB method dispatch entirely.
            %   Use it in performance-critical loops where the same MEX commands
            %   are called repeatedly (e.g. nodeDisp, eleForce, nodeVel).
            %
            %   The handle remains valid as long as the OpenSeesMatlabBase object
            %   exists and the MEX module stays on the MATLAB path.
            %
            % Returns
            % -------
            % fn : function_handle
            %     Direct handle to the OpenSees MEX entry point.
            %     Call as: fn('command', arg1, arg2, ...)
            %
            % Example
            % -------
            %     % Slow: goes through method dispatch every call
            %     for i = 1:npts
            %         d = ops.nodeDisp(nodeTag, dof);
            %     end
            %
            %     % Fast: direct MEX call, no dispatch overhead
            %     ops_ = ops.getMexHandle();
            %     for i = 1:npts
            %         d = ops_('nodeDisp', nodeTag, dof);
            %     end
            %
            %     % Batch: fetch all DOFs in one call instead of N calls
            %     d = ops_('nodeDisp', nodeTag);   % returns full DOF vector
            %     f = ops_('eleForce', eleTag);    % returns all force components
            fn = obj.mexHandle;
        end

        function p = mexPath(obj)
            % Get the path of the configured OpenSees MEX function.
            %
            % Syntax
            % ------
            %     p = obj.mexPath()
            %
            % Returns
            % -------
            % p : char
            %     Full path returned by which(obj.mexName). If the MEX function is
            %     not on the MATLAB path, p is empty.
            %
            % Example
            % -------
            %     p = obj.mexPath();
            %     if isempty(p)
            %         error("OpenSees MEX module is not on the MATLAB path.");
            %     end

            p = which(obj.mexName);
        end

        function ensureMexOnPath(obj)
            % Add the configured MEX directory to the MATLAB path.
            %
            %   This method is useful if the MATLAB path was changed after object
            %   construction. It does not rebuild the MEX handle; it only calls
            %   addpath for the stored mexDir when mexDir is nonempty.
            if ~isempty(obj.mexDir)
                addpath(obj.mexDir);
            end
        end

        function disp(obj)
            fprintf('%s object\n', class(obj));
            fprintf('  mexName : %s\n', obj.mexName);
            if ~isempty(obj.mexDir)
                fprintf('  mexDir  : %s\n', obj.mexDir);
            end
            p = which(obj.mexName);
            if isempty(p)
                fprintf('  status  : MEX not found on MATLAB path\n');
            else
                fprintf('  status  : ready\n');
                fprintf('  mexPath : %s\n', p);
            end
        end

        function mexDir = resolveMexDir(obj, mexDir)
            % Resolve a user-provided MEX directory.
            %
            % Parameters
            % ----------
            % mexDir : char or string
            %     Directory supplied by the caller. Absolute paths and existing
            %     relative paths are returned unchanged. Nonexisting relative paths
            %     are also checked relative to the directory containing this class.
            %
            % Returns
            % -------
            % mexDir : char
            %     Resolved directory candidate.
            if isempty(mexDir)
                return;
            end

            mexDir = char(mexDir);
            if isfolder(mexDir)
                return;
            end

            if obj.isAbsolutePath(mexDir)
                return;
            end

            classDir = fileparts(mfilename('fullpath'));
            candidateDir = fullfile(classDir, mexDir);
            if isfolder(candidateDir)
                mexDir = candidateDir;
            end
        end
    end

    methods (Access = protected)
        function tf = isAbsolutePath(~, pathStr)
            tf = ~isempty(regexp(pathStr, '^[A-Za-z]:[\\/]|^\\\\', 'once'));
        end

        function varargout = dispatchCommand(obj, cmd, varargin)
            % Dispatch an OpenSees command through the MEX function.
            %
            %   Subclasses can call this protected method when they need a single
            %   internal dispatch point for command wrappers.
            [varargout{1:nargout}] = obj.mexHandle(cmd, varargin{:});
        end

        % Kept only for compatibility with existing subclasses.
        function out = validateTextScalar(~, value, ~)
            % Convert a string scalar to char for compatibility with older callers.
            %
            %   This helper is kept for compatibility with existing subclasses.
            if isstring(value)
                out = char(value);
            else
                out = value;
            end
        end

        function args = preprocessCommandArgs(~, ~, args)
            % Preprocess command arguments before dispatching.
            %
            %   The default implementation leaves args unchanged. Subclasses may
            %   override this hook to normalize or record command arguments before
            %   they are sent to the OpenSees MEX module.
        end

        function beforeCommand(~, varargin)
            % Hook for actions to perform before dispatching a command.
            %
            %   The default implementation is empty. Subclasses may override this
            %   hook to implement logging, bookkeeping, validation, or recording.
        end

        function afterCommand(~, varargin)
            % Hook for actions to perform after dispatching a command.
            %
            %   The default implementation is empty. Subclasses may override this
            %   hook to update caches, collect metadata, or synchronize auxiliary
            %   data after a command has been sent to OpenSees.
        end
    end

    % methods
    %     function varargout = subsref(obj, S)
    %         % Fast path only intercepts obj.command(...)
    %         nS = numel(S);
    %         if nS >= 2 && strcmp(S(1).type, '.') && strcmp(S(2).type, '()')
    %             name = S(1).subs;

    %             % Fast hard exclusions: avoid dynamic dispatch for real public APIs.
    %             % Keep this list short and hot.
    %             switch name
    %                 case {'mexName','mexDir','call','hasMex','mexPath','ensureMexOnPath','disp'}
    %                     [varargout{1:nargout}] = builtin('subsref', obj, S);
    %                     return;
    %             end

    %             % Dynamic OpenSees command.
    %             [varargout{1:nargout}] = obj.mexHandle(name, S(2).subs{:});

    %             % Optional chained indexing on single output only.
    %             if nS > 2
    %                 if nargout <= 1
    %                     varargout{1} = builtin('subsref', varargout{1}, S(3:end));
    %                 else
    %                     error('OpenSeesMatlab:InvalidChainedIndexing', ...
    %                         'Chained indexing after dynamic command dispatch supports only a single output.');
    %                 end
    %             end
    %             return;
    %         end

    %         [varargout{1:nargout}] = builtin('subsref', obj, S);
    %     end
    % end

    %----------------------------------------------------------------------
    % Explicit OpenSees command wrappers
    %
    % Query commands  — return a single 'result' variable (read-only).
    % Action commands — use varargout; modify domain state or run analysis.
    %----------------------------------------------------------------------

    % =====================================================================
    % Query commands
    % =====================================================================
    methods

        % --- Nodal response -----------------------------------------------
        function result = nodeDisp(obj, varargin),           result = obj.mexHandle('nodeDisp', varargin{:}); end
        function result = nodeVel(obj, varargin),            result = obj.mexHandle('nodeVel', varargin{:}); end
        function result = nodeAccel(obj, varargin),          result = obj.mexHandle('nodeAccel', varargin{:}); end
        function result = nodeReaction(obj, varargin),       result = obj.mexHandle('nodeReaction', varargin{:}); end
        function result = nodeUnbalance(obj, varargin),      result = obj.mexHandle('nodeUnbalance', varargin{:}); end
        function result = nodeCoord(obj, varargin),          result = obj.mexHandle('nodeCoord', varargin{:}); end
        function result = nodeResponse(obj, varargin),       result = obj.mexHandle('nodeResponse', varargin{:}); end
        function result = nodeMass(obj, varargin),           result = obj.mexHandle('nodeMass', varargin{:}); end
        function result = nodePressure(obj, varargin),       result = obj.mexHandle('nodePressure', varargin{:}); end
        function result = nodeDOFs(obj, varargin),           result = obj.mexHandle('nodeDOFs', varargin{:}); end
        function result = nodeBounds(obj, varargin),         result = obj.mexHandle('nodeBounds', varargin{:}); end
        function result = nodeEigenvector(obj, varargin),    result = obj.mexHandle('nodeEigenvector', varargin{:}); end
        function result = getNodeTemperature(obj, varargin), result = obj.mexHandle('getNodeTemperature', varargin{:}); end

        % --- Element response ---------------------------------------------
        function result = eleForce(obj, varargin),           result = obj.mexHandle('eleForce', varargin{:}); end
        function result = eleDynamicalForce(obj, varargin),  result = obj.mexHandle('eleDynamicalForce', varargin{:}); end
        function result = eleResponse(obj, varargin),        result = obj.mexHandle('eleResponse', varargin{:}); end
        function result = eleNodes(obj, varargin),           result = obj.mexHandle('eleNodes', varargin{:}); end
        function result = eleType(obj, varargin),            result = obj.mexHandle('eleType', varargin{:}); end
        function result = classType(obj, varargin),          result = obj.mexHandle('classType', varargin{:}); end

        % --- Section response ---------------------------------------------
        function result = sectionForce(obj, varargin),       result = obj.mexHandle('sectionForce', varargin{:}); end
        function result = sectionDeformation(obj, varargin), result = obj.mexHandle('sectionDeformation', varargin{:}); end
        function result = sectionStiffness(obj, varargin),   result = obj.mexHandle('sectionStiffness', varargin{:}); end
        function result = sectionFlexibility(obj, varargin), result = obj.mexHandle('sectionFlexibility', varargin{:}); end
        function result = sectionLocation(obj, varargin),    result = obj.mexHandle('sectionLocation', varargin{:}); end
        function result = sectionWeight(obj, varargin),      result = obj.mexHandle('sectionWeight', varargin{:}); end
        function result = sectionTag(obj, varargin),         result = obj.mexHandle('sectionTag', varargin{:}); end
        function result = sectionResponseType(obj, varargin),result = obj.mexHandle('sectionResponseType', varargin{:}); end
        function result = sectionDisplacement(obj, varargin),result = obj.mexHandle('sectionDisplacement', varargin{:}); end
        function result = cbdiDisplacement(obj, varargin),   result = obj.mexHandle('cbdiDisplacement', varargin{:}); end
        function result = basicDeformation(obj, varargin),   result = obj.mexHandle('basicDeformation', varargin{:}); end
        function result = basicForce(obj, varargin),         result = obj.mexHandle('basicForce', varargin{:}); end
        function result = basicStiffness(obj, varargin),     result = obj.mexHandle('basicStiffness', varargin{:}); end

        % --- Domain information -------------------------------------------
        function result = getNodeTags(obj, varargin),        result = obj.mexHandle('getNodeTags', varargin{:}); end
        function result = getEleTags(obj, varargin),         result = obj.mexHandle('getEleTags', varargin{:}); end
        function result = getEleClassTags(obj, varargin),    result = obj.mexHandle('getEleClassTags', varargin{:}); end
        function result = getEleLoadClassTags(obj, varargin),result = obj.mexHandle('getEleLoadClassTags', varargin{:}); end
        function result = getEleLoadTags(obj, varargin),     result = obj.mexHandle('getEleLoadTags', varargin{:}); end
        function result = getEleLoadData(obj, varargin),     result = obj.mexHandle('getEleLoadData', varargin{:}); end
        function result = getNodeLoadTags(obj, varargin),    result = obj.mexHandle('getNodeLoadTags', varargin{:}); end
        function result = getNodeLoadData(obj, varargin),    result = obj.mexHandle('getNodeLoadData', varargin{:}); end
        function result = getCrdTransfTags(obj, varargin),   result = obj.mexHandle('getCrdTransfTags', varargin{:}); end
        function result = getNumElements(obj, varargin),     result = obj.mexHandle('getNumElements', varargin{:}); end
        function result = getNDM(obj, varargin),             result = obj.mexHandle('getNDM', varargin{:}); end
        function result = getNDF(obj, varargin),             result = obj.mexHandle('getNDF', varargin{:}); end
        function result = getPatterns(obj, varargin),        result = obj.mexHandle('getPatterns', varargin{:}); end
        function result = getFixedNodes(obj, varargin),      result = obj.mexHandle('getFixedNodes', varargin{:}); end
        function result = getFixedDOFs(obj, varargin),       result = obj.mexHandle('getFixedDOFs', varargin{:}); end
        function result = getConstrainedNodes(obj, varargin),result = obj.mexHandle('getConstrainedNodes', varargin{:}); end
        function result = getConstrainedDOFs(obj, varargin), result = obj.mexHandle('getConstrainedDOFs', varargin{:}); end
        function result = getRetainedNodes(obj, varargin),   result = obj.mexHandle('getRetainedNodes', varargin{:}); end
        function result = getRetainedDOFs(obj, varargin),    result = obj.mexHandle('getRetainedDOFs', varargin{:}); end
        function result = getParamTags(obj, varargin),       result = obj.mexHandle('getParamTags', varargin{:}); end
        function result = getParamValue(obj, varargin),      result = obj.mexHandle('getParamValue', varargin{:}); end
        function result = getLoadFactor(obj, varargin),      result = obj.mexHandle('getLoadFactor', varargin{:}); end
        function result = getTime(obj, varargin),            result = obj.mexHandle('getTime', varargin{:}); end
        function result = getPID(obj, varargin),             result = obj.mexHandle('getPID', varargin{:}); end
        function result = getNP(obj, varargin),              result = obj.mexHandle('getNP', varargin{:}); end
        function result = getNumThreads(obj, varargin),      result = obj.mexHandle('getNumThreads', varargin{:}); end
        function result = domainCommitTag(obj, varargin),    result = obj.mexHandle('domainCommitTag', varargin{:}); end

        % --- Material state -----------------------------------------------
        function result = getStrain(obj, varargin),          result = obj.mexHandle('getStrain', varargin{:}); end
        function result = getStress(obj, varargin),          result = obj.mexHandle('getStress', varargin{:}); end
        function result = getTangent(obj, varargin),         result = obj.mexHandle('getTangent', varargin{:}); end
        function result = getDampTangent(obj, varargin),     result = obj.mexHandle('getDampTangent', varargin{:}); end

        % --- Analysis state -----------------------------------------------
        function result = testNorm(obj, varargin),           result = obj.mexHandle('testNorm', varargin{:}); end
        function result = testNorms(obj, varargin),          result = obj.mexHandle('testNorms', varargin{:}); end
        function result = testIter(obj, varargin),           result = obj.mexHandle('testIter', varargin{:}); end
        function result = analyze(obj, varargin),            result = obj.mexHandle('analyze', varargin{:}); end
        function result = eigen(obj, varargin),              result = obj.mexHandle('eigen', varargin{:}); end
        function result = modalProperties(obj, varargin),    result = obj.mexHandle('modalProperties', varargin{:}); end

        % --- Performance timing -------------------------------------------
        function result = totalCPU(obj, varargin),           result = obj.mexHandle('totalCPU', varargin{:}); end
        function result = solveCPU(obj, varargin),           result = obj.mexHandle('solveCPU', varargin{:}); end
        function result = accelCPU(obj, varargin),           result = obj.mexHandle('accelCPU', varargin{:}); end
        function result = numFact(obj, varargin),            result = obj.mexHandle('numFact', varargin{:}); end
        function result = numIter(obj, varargin),            result = obj.mexHandle('numIter', varargin{:}); end
        function result = systemSize(obj, varargin),         result = obj.mexHandle('systemSize', varargin{:}); end
        function result = version(obj, varargin),            result = obj.mexHandle('version', varargin{:}); end

        % --- Sensitivity / reliability ------------------------------------
        function result = sensNodeDisp(obj, varargin),       result = obj.mexHandle('sensNodeDisp', varargin{:}); end
        function result = sensNodeVel(obj, varargin),        result = obj.mexHandle('sensNodeVel', varargin{:}); end
        function result = sensNodeAccel(obj, varargin),      result = obj.mexHandle('sensNodeAccel', varargin{:}); end
        function result = sensLambda(obj, varargin),         result = obj.mexHandle('sensLambda', varargin{:}); end
        function result = sensSectionForce(obj, varargin),   result = obj.mexHandle('sensSectionForce', varargin{:}); end
        function result = sensNodePressure(obj, varargin),   result = obj.mexHandle('sensNodePressure', varargin{:}); end
        function result = sdfResponse(obj, varargin),        result = obj.mexHandle('sdfResponse', varargin{:}); end
        function result = transformUtoX(obj, varargin),      result = obj.mexHandle('transformUtoX', varargin{:}); end
        function result = getRVTags(obj, varargin),          result = obj.mexHandle('getRVTags', varargin{:}); end
        function result = getRVParamTag(obj, varargin),      result = obj.mexHandle('getRVParamTag', varargin{:}); end
        function result = getRVValue(obj, varargin),         result = obj.mexHandle('getRVValue', varargin{:}); end
        function result = getMean(obj, varargin),            result = obj.mexHandle('getMean', varargin{:}); end
        function result = getStdv(obj, varargin),            result = obj.mexHandle('getStdv', varargin{:}); end
        function result = getPDF(obj, varargin),             result = obj.mexHandle('getPDF', varargin{:}); end
        function result = getCDF(obj, varargin),             result = obj.mexHandle('getCDF', varargin{:}); end
        function result = getInverseCDF(obj, varargin),      result = obj.mexHandle('getInverseCDF', varargin{:}); end
        function result = getLSFTags(obj, varargin),         result = obj.mexHandle('getLSFTags', varargin{:}); end

    end % query methods

    % =====================================================================
    % Action commands
    % =====================================================================
    methods

        % --- Model initialisation -----------------------------------------
        function varargout = wipe(obj, varargin),              [varargout{1:nargout}] = obj.mexHandle('wipe', varargin{:}); end
        function varargout = wipeReliability(obj, varargin),   [varargout{1:nargout}] = obj.mexHandle('wipeReliability', varargin{:}); end
        function varargout = model(obj, varargin),             [varargout{1:nargout}] = obj.mexHandle('model', varargin{:}); end

        % --- Node / DOF definition ----------------------------------------
        function varargout = node(obj, varargin),              [varargout{1:nargout}] = obj.mexHandle('node', varargin{:}); end
        function varargout = fix(obj, varargin),               [varargout{1:nargout}] = obj.mexHandle('fix', varargin{:}); end
        function varargout = fixX(obj, varargin),              [varargout{1:nargout}] = obj.mexHandle('fixX', varargin{:}); end
        function varargout = fixY(obj, varargin),              [varargout{1:nargout}] = obj.mexHandle('fixY', varargin{:}); end
        function varargout = fixZ(obj, varargin),              [varargout{1:nargout}] = obj.mexHandle('fixZ', varargin{:}); end
        function varargout = mass(obj, varargin),              [varargout{1:nargout}] = obj.mexHandle('mass', varargin{:}); end
        function varargout = equalDOF(obj, varargin),          [varargout{1:nargout}] = obj.mexHandle('equalDOF', varargin{:}); end
        function varargout = equalDOF_Mixed(obj, varargin),    [varargout{1:nargout}] = obj.mexHandle('equalDOF_Mixed', varargin{:}); end
        function varargout = equationConstraint(obj, varargin),[varargout{1:nargout}] = obj.mexHandle('equationConstraint', varargin{:}); end
        function varargout = rigidLink(obj, varargin),         [varargout{1:nargout}] = obj.mexHandle('rigidLink', varargin{:}); end
        function varargout = rigidDiaphragm(obj, varargin),    [varargout{1:nargout}] = obj.mexHandle('rigidDiaphragm', varargin{:}); end
        function varargout = sp(obj, varargin),                [varargout{1:nargout}] = obj.mexHandle('sp', varargin{:}); end
        function varargout = pressureConstraint(obj, varargin),[varargout{1:nargout}] = obj.mexHandle('pressureConstraint', varargin{:}); end

        % --- Element / material / section definition ----------------------
        function varargout = element(obj, varargin),           [varargout{1:nargout}] = obj.mexHandle('element', varargin{:}); end
        function varargout = uniaxialMaterial(obj, varargin),  [varargout{1:nargout}] = obj.mexHandle('uniaxialMaterial', varargin{:}); end
        function varargout = nDMaterial(obj, varargin),        [varargout{1:nargout}] = obj.mexHandle('nDMaterial', varargin{:}); end
        function varargout = testUniaxialMaterial(obj, varargin),[varargout{1:nargout}] = obj.mexHandle('testUniaxialMaterial', varargin{:}); end
        function varargout = section(obj, varargin),           [varargout{1:nargout}] = obj.mexHandle('section', varargin{:}); end
        function varargout = fiber(obj, varargin),             [varargout{1:nargout}] = obj.mexHandle('fiber', varargin{:}); end
        function varargout = patch(obj, varargin),             [varargout{1:nargout}] = obj.mexHandle('patch', varargin{:}); end
        function varargout = layer(obj, varargin),             [varargout{1:nargout}] = obj.mexHandle('layer', varargin{:}); end
        function varargout = geomTransf(obj, varargin),        [varargout{1:nargout}] = obj.mexHandle('geomTransf', varargin{:}); end
        function varargout = damping(obj, varargin),           [varargout{1:nargout}] = obj.mexHandle('damping', varargin{:}); end
        function varargout = beamIntegration(obj, varargin),   [varargout{1:nargout}] = obj.mexHandle('beamIntegration', varargin{:}); end
        function varargout = frictionModel(obj, varargin),     [varargout{1:nargout}] = obj.mexHandle('frictionModel', varargin{:}); end
        function varargout = limitCurve(obj, varargin),        [varargout{1:nargout}] = obj.mexHandle('limitCurve', varargin{:}); end
        function varargout = hystereticBackbone(obj, varargin),[varargout{1:nargout}] = obj.mexHandle('hystereticBackbone', varargin{:}); end
        function varargout = stiffnessDegradation(obj, varargin),[varargout{1:nargout}] = obj.mexHandle('stiffnessDegradation', varargin{:}); end
        function varargout = strengthDegradation(obj, varargin),[varargout{1:nargout}] = obj.mexHandle('strengthDegradation', varargin{:}); end
        function varargout = strengthControl(obj, varargin),   [varargout{1:nargout}] = obj.mexHandle('strengthControl', varargin{:}); end
        function varargout = unloadingRule(obj, varargin),     [varargout{1:nargout}] = obj.mexHandle('unloadingRule', varargin{:}); end

        % --- Load / pattern definition ------------------------------------
        function varargout = timeSeries(obj, varargin),        [varargout{1:nargout}] = obj.mexHandle('timeSeries', varargin{:}); end
        function varargout = pattern(obj, varargin),           [varargout{1:nargout}] = obj.mexHandle('pattern', varargin{:}); end
        function varargout = load(obj, varargin),              [varargout{1:nargout}] = obj.mexHandle('load', varargin{:}); end
        function varargout = eleLoad(obj, varargin),           [varargout{1:nargout}] = obj.mexHandle('eleLoad', varargin{:}); end
        function varargout = loadConst(obj, varargin),         [varargout{1:nargout}] = obj.mexHandle('loadConst', varargin{:}); end
        function varargout = groundMotion(obj, varargin),      [varargout{1:nargout}] = obj.mexHandle('groundMotion', varargin{:}); end
        function varargout = imposedMotion(obj, varargin),     [varargout{1:nargout}] = obj.mexHandle('imposedMotion', varargin{:}); end
        function varargout = imposedSupportMotion(obj, varargin),[varargout{1:nargout}] = obj.mexHandle('imposedSupportMotion', varargin{:}); end

        % --- Analysis object definition -----------------------------------
        function varargout = system(obj, varargin),            [varargout{1:nargout}] = obj.mexHandle('system', varargin{:}); end
        function varargout = numberer(obj, varargin),          [varargout{1:nargout}] = obj.mexHandle('numberer', varargin{:}); end
        function varargout = constraints(obj, varargin),       [varargout{1:nargout}] = obj.mexHandle('constraints', varargin{:}); end
        function varargout = integrator(obj, varargin),        [varargout{1:nargout}] = obj.mexHandle('integrator', varargin{:}); end
        function varargout = algorithm(obj, varargin),         [varargout{1:nargout}] = obj.mexHandle('algorithm', varargin{:}); end
        function varargout = analysis(obj, varargin),          [varargout{1:nargout}] = obj.mexHandle('analysis', varargin{:}); end
        function varargout = test(obj, varargin),              [varargout{1:nargout}] = obj.mexHandle('test', varargin{:}); end
        function varargout = rayleigh(obj, varargin),          [varargout{1:nargout}] = obj.mexHandle('rayleigh', varargin{:}); end
        function varargout = modalDamping(obj, varargin),      [varargout{1:nargout}] = obj.mexHandle('modalDamping', varargin{:}); end
        function varargout = modalDampingQ(obj, varargin),     [varargout{1:nargout}] = obj.mexHandle('modalDampingQ', varargin{:}); end
        function varargout = setElementRayleighDampingFactors(obj, varargin),[varargout{1:nargout}] = obj.mexHandle('setElementRayleighDampingFactors', varargin{:}); end
        function varargout = setElementRayleighFactors(obj, varargin),[varargout{1:nargout}] = obj.mexHandle('setElementRayleighFactors', varargin{:}); end

        % --- Analysis control ---------------------------------------------
        function varargout = wipeAnalysis(obj, varargin),      [varargout{1:nargout}] = obj.mexHandle('wipeAnalysis', varargin{:}); end
        function varargout = reset(obj, varargin),             [varargout{1:nargout}] = obj.mexHandle('reset', varargin{:}); end
        function varargout = initialize(obj, varargin),        [varargout{1:nargout}] = obj.mexHandle('initialize', varargin{:}); end
        function varargout = reactions(obj, varargin),         [varargout{1:nargout}] = obj.mexHandle('reactions', varargin{:}); end
        function varargout = responseSpectrumAnalysis(obj, varargin),[varargout{1:nargout}] = obj.mexHandle('responseSpectrumAnalysis', varargin{:}); end
        function varargout = InitialStateAnalysis(obj, varargin),[varargout{1:nargout}] = obj.mexHandle('InitialStateAnalysis', varargin{:}); end
        function varargout = domainChange(obj, varargin),      [varargout{1:nargout}] = obj.mexHandle('domainChange', varargin{:}); end
        function varargout = updateElementDomain(obj, varargin),[varargout{1:nargout}] = obj.mexHandle('updateElementDomain', varargin{:}); end
        function varargout = updateMaterialStage(obj, varargin),[varargout{1:nargout}] = obj.mexHandle('updateMaterialStage', varargin{:}); end

        % --- State setters ------------------------------------------------
        function varargout = setTime(obj, varargin),           [varargout{1:nargout}] = obj.mexHandle('setTime', varargin{:}); end
        function varargout = setStrain(obj, varargin),         [varargout{1:nargout}] = obj.mexHandle('setStrain', varargin{:}); end
        function varargout = setNodeDisp(obj, varargin),       [varargout{1:nargout}] = obj.mexHandle('setNodeDisp', varargin{:}); end
        function varargout = setNodeVel(obj, varargin),        [varargout{1:nargout}] = obj.mexHandle('setNodeVel', varargin{:}); end
        function varargout = setNodeAccel(obj, varargin),      [varargout{1:nargout}] = obj.mexHandle('setNodeAccel', varargin{:}); end
        function varargout = setNodeCoord(obj, varargin),      [varargout{1:nargout}] = obj.mexHandle('setNodeCoord', varargin{:}); end
        function varargout = setNodePressure(obj, varargin),   [varargout{1:nargout}] = obj.mexHandle('setNodePressure', varargin{:}); end
        function varargout = setNodeTemperature(obj, varargin),[varargout{1:nargout}] = obj.mexHandle('setNodeTemperature', varargin{:}); end
        function varargout = setCreep(obj, varargin),          [varargout{1:nargout}] = obj.mexHandle('setCreep', varargin{:}); end
        function varargout = setNumThreads(obj, varargin),     [varargout{1:nargout}] = obj.mexHandle('setNumThreads', varargin{:}); end
        function varargout = setMaxOpenFiles(obj, varargin),   [varargout{1:nargout}] = obj.mexHandle('setMaxOpenFiles', varargin{:}); end
        function varargout = setStartNodeTag(obj, varargin),   [varargout{1:nargout}] = obj.mexHandle('setStartNodeTag', varargin{:}); end
        function varargout = setPrecision(obj, varargin),      [varargout{1:nargout}] = obj.mexHandle('setPrecision', varargin{:}); end
        function varargout = setParameter(obj, varargin),      [varargout{1:nargout}] = obj.mexHandle('setParameter', varargin{:}); end

        % --- Parameter / region -------------------------------------------
        function varargout = parameter(obj, varargin),         [varargout{1:nargout}] = obj.mexHandle('parameter', varargin{:}); end
        function varargout = addToParameter(obj, varargin),    [varargout{1:nargout}] = obj.mexHandle('addToParameter', varargin{:}); end
        function varargout = updateParameter(obj, varargin),   [varargout{1:nargout}] = obj.mexHandle('updateParameter', varargin{:}); end
        function varargout = region(obj, varargin),            [varargout{1:nargout}] = obj.mexHandle('region', varargin{:}); end
        function varargout = remove(obj, varargin),            [varargout{1:nargout}] = obj.mexHandle('remove', varargin{:}); end

        % --- Output / recording -------------------------------------------
        function varargout = recorder(obj, varargin),          [varargout{1:nargout}] = obj.mexHandle('recorder', varargin{:}); end
        function varargout = record(obj, varargin),            [varargout{1:nargout}] = obj.mexHandle('record', varargin{:}); end
        function varargout = database(obj, varargin),          [varargout{1:nargout}] = obj.mexHandle('database', varargin{:}); end
        function varargout = save(obj, varargin),              [varargout{1:nargout}] = obj.mexHandle('save', varargin{:}); end
        function varargout = restore(obj, varargin),           [varargout{1:nargout}] = obj.mexHandle('restore', varargin{:}); end
        function varargout = printModel(obj, varargin),        [varargout{1:nargout}] = obj.mexHandle('printModel', varargin{:}); end
        function varargout = printA(obj, varargin),            [varargout{1:nargout}] = obj.mexHandle('printA', varargin{:}); end
        function varargout = printB(obj, varargin),            [varargout{1:nargout}] = obj.mexHandle('printB', varargin{:}); end
        function varargout = printX(obj, varargin),            [varargout{1:nargout}] = obj.mexHandle('printX', varargin{:}); end
        function varargout = printGID(obj, varargin),          [varargout{1:nargout}] = obj.mexHandle('printGID', varargin{:}); end
        function varargout = logFile(obj, varargin),           [varargout{1:nargout}] = obj.mexHandle('logFile', varargin{:}); end

        % --- Mesh generation ----------------------------------------------
        function varargout = block2D(obj, varargin),           [varargout{1:nargout}] = obj.mexHandle('block2D', varargin{:}); end
        function varargout = block3D(obj, varargin),           [varargout{1:nargout}] = obj.mexHandle('block3D', varargin{:}); end
        function varargout = mesh(obj, varargin),              [varargout{1:nargout}] = obj.mexHandle('mesh', varargin{:}); end
        function varargout = remesh(obj, varargin),            [varargout{1:nargout}] = obj.mexHandle('remesh', varargin{:}); end
        function varargout = ShallowFoundationGen(obj, varargin),[varargout{1:nargout}] = obj.mexHandle('ShallowFoundationGen', varargin{:}); end

        % --- Parallel / MPI -----------------------------------------------
        function varargout = partition(obj, varargin),         [varargout{1:nargout}] = obj.mexHandle('partition', varargin{:}); end
        function varargout = barrier(obj, varargin),           [varargout{1:nargout}] = obj.mexHandle('barrier', varargin{:}); end
        function varargout = send(obj, varargin),              [varargout{1:nargout}] = obj.mexHandle('send', varargin{:}); end
        function varargout = recv(obj, varargin),              [varargout{1:nargout}] = obj.mexHandle('recv', varargin{:}); end
        function varargout = Bcast(obj, varargin),             [varargout{1:nargout}] = obj.mexHandle('Bcast', varargin{:}); end

        % --- Timing -------------------------------------------------------
        function varargout = start(obj, varargin),             [varargout{1:nargout}] = obj.mexHandle('start', varargin{:}); end
        function varargout = stop(obj, varargin),              [varargout{1:nargout}] = obj.mexHandle('stop', varargin{:}); end

        % --- Sensitivity / reliability ------------------------------------
        function varargout = sensitivityAlgorithm(obj, varargin),[varargout{1:nargout}] = obj.mexHandle('sensitivityAlgorithm', varargin{:}); end
        function varargout = computeGradients(obj, varargin),  [varargout{1:nargout}] = obj.mexHandle('computeGradients', varargin{:}); end
        function varargout = randomVariable(obj, varargin),    [varargout{1:nargout}] = obj.mexHandle('randomVariable', varargin{:}); end
        function varargout = filter(obj, varargin),            [varargout{1:nargout}] = obj.mexHandle('filter', varargin{:}); end
        function varargout = modulatingFunction(obj, varargin),[varargout{1:nargout}] = obj.mexHandle('modulatingFunction', varargin{:}); end
        function varargout = spectrum(obj, varargin),          [varargout{1:nargout}] = obj.mexHandle('spectrum', varargin{:}); end
        function varargout = correlate(obj, varargin),         [varargout{1:nargout}] = obj.mexHandle('correlate', varargin{:}); end
        function varargout = performanceFunction(obj, varargin),[varargout{1:nargout}] = obj.mexHandle('performanceFunction', varargin{:}); end
        function varargout = gradPerformanceFunction(obj, varargin),[varargout{1:nargout}] = obj.mexHandle('gradPerformanceFunction', varargin{:}); end
        function varargout = probabilityTransformation(obj, varargin),[varargout{1:nargout}] = obj.mexHandle('probabilityTransformation', varargin{:}); end
        function varargout = startPoint(obj, varargin),        [varargout{1:nargout}] = obj.mexHandle('startPoint', varargin{:}); end
        function varargout = randomNumberGenerator(obj, varargin),[varargout{1:nargout}] = obj.mexHandle('randomNumberGenerator', varargin{:}); end
        function varargout = reliabilityConvergenceCheck(obj, varargin),[varargout{1:nargout}] = obj.mexHandle('reliabilityConvergenceCheck', varargin{:}); end
        function varargout = searchDirection(obj, varargin),   [varargout{1:nargout}] = obj.mexHandle('searchDirection', varargin{:}); end
        function varargout = meritFunctionCheck(obj, varargin),[varargout{1:nargout}] = obj.mexHandle('meritFunctionCheck', varargin{:}); end
        function varargout = stepSizeRule(obj, varargin),      [varargout{1:nargout}] = obj.mexHandle('stepSizeRule', varargin{:}); end
        function varargout = rootFinding(obj, varargin),       [varargout{1:nargout}] = obj.mexHandle('rootFinding', varargin{:}); end
        function varargout = functionEvaluator(obj, varargin), [varargout{1:nargout}] = obj.mexHandle('functionEvaluator', varargin{:}); end
        function varargout = gradientEvaluator(obj, varargin), [varargout{1:nargout}] = obj.mexHandle('gradientEvaluator', varargin{:}); end
        function varargout = runFOSMAnalysis(obj, varargin),   [varargout{1:nargout}] = obj.mexHandle('runFOSMAnalysis', varargin{:}); end
        function varargout = findDesignPoint(obj, varargin),   [varargout{1:nargout}] = obj.mexHandle('findDesignPoint', varargin{:}); end
        function varargout = findCurvatures(obj, varargin),    [varargout{1:nargout}] = obj.mexHandle('findCurvatures', varargin{:}); end
        function varargout = runFORMAnalysis(obj, varargin),   [varargout{1:nargout}] = obj.mexHandle('runFORMAnalysis', varargin{:}); end
        function varargout = runSORMAnalysis(obj, varargin),   [varargout{1:nargout}] = obj.mexHandle('runSORMAnalysis', varargin{:}); end
        function varargout = runImportanceSamplingAnalysis(obj, varargin),[varargout{1:nargout}] = obj.mexHandle('runImportanceSamplingAnalysis', varargin{:}); end

        % --- Miscellaneous ------------------------------------------------
        function varargout = build(obj, varargin),             [varargout{1:nargout}] = obj.mexHandle('build', varargin{:}); end
        function varargout = searchPeerNGA(obj, varargin),     [varargout{1:nargout}] = obj.mexHandle('searchPeerNGA', varargin{:}); end
        function varargout = metaData(obj, varargin),          [varargout{1:nargout}] = obj.mexHandle('metaData', varargin{:}); end
        function varargout = defaultUnits(obj, varargin),      [varargout{1:nargout}] = obj.mexHandle('defaultUnits', varargin{:}); end
        function varargout = stripXML(obj, varargin),          [varargout{1:nargout}] = obj.mexHandle('stripXML', varargin{:}); end
        function varargout = convertBinaryToText(obj, varargin),[varargout{1:nargout}] = obj.mexHandle('convertBinaryToText', varargin{:}); end
        function varargout = convertTextToBinary(obj, varargin),[varargout{1:nargout}] = obj.mexHandle('convertTextToBinary', varargin{:}); end
        function varargout = IGA(obj, varargin),               [varargout{1:nargout}] = obj.mexHandle('IGA', varargin{:}); end
        function varargout = NDTest(obj, varargin),            [varargout{1:nargout}] = obj.mexHandle('NDTest', varargin{:}); end

    end % action methods
    %-------------------------------------------------------------------------
    % Added by OpenSeesMatlab
    %-------------------------------------------------------------------------
    methods
        function varargout = suppressPrint(obj, varargin), [varargout{1:nargout}] = obj.mexHandle('suppressPrint', varargin{:}); end

        function result = FEMDataRecorder(obj, varargin), result = obj.mexHandle('FEMDataRecorder', varargin{:}); end

        function result = readFEMData(obj, varargin), result = obj.mexHandle('readFEMData', varargin{:}); end

        function result = writeFEMDataPVD(obj, varargin), result = obj.mexHandle('writeFEMDataPVD', varargin{:}); end

        function result = getDomainGeoTag(obj, varargin), result = obj.mexHandle('getDomainGeoTag', varargin{:}); end

        function result = matlabversion(obj, varargin), result = obj.mexHandle('matlabversion', varargin{:}); end
    end
end
