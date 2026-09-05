classdef SparseFactorizationCache < handle
    %SPARSEFACTORIZATIONCACHE Reuse a MATLAB sparse decomposition by revision.

    properties (Access = private)
        Factorization
        MatrixRevision = uint64(0)
        HasFactorization = false
    end

    properties (SetAccess = private)
        FactorizationCount = 0
    end

    methods
        function solution = solve(cache, matrix, rightHandSide, matrixRevision)
            if nargin < 4
                matrixRevision = uint64(0);
            else
                matrixRevision = uint64(matrixRevision);
            end
            if ~cache.HasFactorization || cache.MatrixRevision ~= matrixRevision
                cache.Factorization = decomposition(matrix);
                cache.MatrixRevision = matrixRevision;
                cache.HasFactorization = true;
                cache.FactorizationCount = cache.FactorizationCount + 1;
            end
            solution = cache.Factorization \ rightHandSide;
        end

        function clear(cache)
            cache.Factorization = [];
            cache.MatrixRevision = uint64(0);
            cache.HasFactorization = false;
            cache.FactorizationCount = 0;
        end
    end
end
