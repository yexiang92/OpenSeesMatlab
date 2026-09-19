classdef TestSliceContourBuilder < matlab.unittest.TestCase
    methods (TestClassSetup)
        function addProjectPath(~)
            repoRoot = fileparts(fileparts(mfilename('fullpath')));
            addpath(fullfile(repoRoot, 'OpenSeesMatlab'));
        end
    end

    methods (Test)
        function cutsLinearTetraAndInterpolatesValues(testCase)
            P = [0 0 0; 1 0 0; 0 1 0; 0 0 1];
            [V, F, S, ~, E] = plotter.polyscope.SliceContourBuilder.build( ...
                P, 10, [4 1 2 3 4], P(:, 3), [0 0 0.25], [0 0 1]);
            testCase.verifySize(V, [3 3]);
            testCase.verifySize(F, [1 3]);
            testCase.verifyEqual(S, 0.25 * ones(3, 1), 'AbsTol', 1e-12);
            testCase.verifySize(E, [3 2]);
        end

        function cutsLinearHexAndTriangulatesQuad(testCase)
            P = [0 0 0; 1 0 0; 1 1 0; 0 1 0; ...
                 0 0 1; 1 0 1; 1 1 1; 0 1 1];
            [V, F, S] = plotter.polyscope.SliceContourBuilder.build( ...
                P, 12, [8 1:8], P(:, 3), [0 0 0.5], [0 0 1]);
            testCase.verifySize(V, [4 3]);
            testCase.verifySize(F, [2 3]);
            testCase.verifyEqual(S, 0.5 * ones(4, 1), 'AbsTol', 1e-12);
        end

        function ignoresCellsOutsidePlane(testCase)
            P = [0 0 0; 1 0 0; 0 1 0; 0 0 1];
            [V, F, S] = plotter.polyscope.SliceContourBuilder.build( ...
                P, 10, [4 1 2 3 4], P(:, 3), [0 0 2], [0 0 1]);
            testCase.verifyEmpty(V);
            testCase.verifyEmpty(F);
            testCase.verifyEmpty(S);
        end
    end
end
