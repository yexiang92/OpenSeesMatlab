classdef ModelDataUtils
    % ModelDataUtils
    % Utility methods for extracting nodal coordinates, nodal mass, and
    % M/C/K/Ki matrices from an OpenSees MATLAB wrapper.
    %
    % Notes
    % -----
    % 1. This class assumes you have an OpenSees wrapper object `ops`
    %    that provides methods analogous to:
    %       ops.getNodeTags()
    %       ops.getNDF(tag)
    %       ops.getNDM(tag)
    %       ops.nodeCoord(tag)
    %       ops.nodeDOFs(tag)
    %       ops.wipeAnalysis()
    %       ops.numberer(...)
    %       ops.constraints(...)
    %       ops.system(...)
    %       ops.algorithm(...)
    %       ops.test(...)
    %       ops.analysis(...)
    %       ops.integrator(...)
    %       ops.analyze(...)
    %       ops.printA('-ret')
    %       ops.systemSize()
    %
    % 2. Outputs are MATLAB structs instead of xarray objects.
    %
    % Example
    % -------
    %   nodeCoord = ModelDataUtils.getNodeCoord(ops);
    %   M = ModelDataUtils.getMCK(ops, 'm', {'Penalty', 0.0, 0.0}, ...
    %       {'Diagonal', 'lumped'}, {'Plain'});
    %   nodeMass = ModelDataUtils.getNodeMass(ops);

    methods (Static)
        function nodeMass = getNodeMass(ops)
            % Get nodal mass data from the OpenSees model, including the
            % mass assembled from the model.
            %
            % Output
            % ------
            % nodeMass : containers.Map
            %   Key   : node tag
            %   Value : row vector of nodal masses for each DOF

            M = pre.ModelDataUtils.getMCK( ...
                ops, ...
                'm', ...
                {'Penalty', 0.0, 0.0}, ...
                {'Diagonal', 'lumped'}, ...
                {'Plain'});

            vec = M.Data;
            if ~isvector(vec)
                vec = vec(:);
            end

            nodeMass = containers.Map('KeyType', 'double', 'ValueType', 'any');

            nodeTags = double(ops.getNodeTags());
            idx = 1;
            for i = 1:numel(nodeTags)
                ntag = nodeTags(i);
                ndofs = double(ops.getNDF(ntag));
                if numel(ndofs) > 1
                    ndofs = ndofs(1);
                end

                mass = zeros(1, ndofs);
                for j = 1:ndofs
                    mass(j) = double(vec(idx));
                    idx = idx + 1;
                end
                nodeMass(ntag) = mass;
            end
        end

        function matrix = getMCK(ops, matrixType, constraintsArgs, systemArgs, numbererArgs)
            % Get the mass, damping, stiffness, or initial stiffness matrix.
            %
            % Inputs
            % ------
            % matrixType      : 'm', 'c', 'k', or 'ki'
            % constraintsArgs : cell array, e.g. {'Penalty', 1e10, 1e10}
            % systemArgs      : cell array, default {'FullGeneral'}
            % numbererArgs    : cell array, default {'Plain'}
            %
            % Output
            % ------
            % matrix : struct
            %   .Type
            %   .Data
            %   .Labels

            arguments
                ops
                matrixType {mustBeTextScalar}
                constraintsArgs cell
                systemArgs cell = {'FullGeneral'}
                numbererArgs cell = {'Plain'}
            end

            ops.suppressPrint(true);
            matrix = pre.ModelDataUtils.getMCKImpl( ...
                ops, ...
                char(string(matrixType)), ...
                constraintsArgs, ...
                systemArgs, ...
                numbererArgs);
            ops.suppressPrint(false);
        end
    end

    methods (Static, Access = private)
        function matrix = getMCKImpl(ops, matrixType, constraintsArgs, systemArgs, numbererArgs)
            ops.wipeAnalysis();
            ops.numberer(numbererArgs{:});
            ops.constraints(constraintsArgs{:});
            ops.system(systemArgs{:});
            ops.algorithm('Linear');
            ops.test('NormDispIncr', 1, 10, 0);
            ops.analysis('Transient', '-noWarnings');

            switch lower(string(matrixType))
                case "m"
                    ops.integrator('GimmeMCK', 1.0, 0.0, 0.0, 0.0);
                case "c"
                    ops.integrator('GimmeMCK', 0.0, 1.0, 0.0, 0.0);
                case "k"
                    ops.integrator('GimmeMCK', 0.0, 0.0, 1.0, 0.0);
                case "ki"
                    ops.integrator('GimmeMCK', 0.0, 0.0, 0.0, 1.0);
                otherwise
                    error('ModelDataUtils:InvalidInput', ...
                        'matrixType must be ''m'', ''c'', ''k'', or ''ki''.');
            end

            ops.analyze(1, 0.0);

            A = double(ops.printA('-ret'));
            n = double(ops.systemSize());

            if numel(A) == n^2
                A = reshape(A, n, n);
            else
                A = A(:);
            end

            labels = strings(n, 1);
            nodeTags = double(ops.getNodeTags());

            for i = 1:numel(nodeTags)
                ntag = nodeTags(i);
                dofs = double(ops.nodeDOFs(ntag));
                dofs = dofs(:);

                for j = 1:numel(dofs)
                    dof = dofs(j);
                    if dof >= 0
                        idx = dof + 1;  % OpenSees DOF numbering may be zero-based here
                        if idx >= 1 && idx <= n
                            labels(idx) = sprintf('%d-%d', ntag, dof);
                        end
                    end
                end
            end

            matrix = struct();
            matrix.Type = char(lower(string(matrixType)));
            matrix.Data = A;
            matrix.Labels = cellstr(labels);

            ops.wipeAnalysis();
        end
    end
end