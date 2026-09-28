classdef TestPlotTopology < matlab.unittest.TestCase
    % Regression tests for compacted-node connectivity in MATLAB plotters.

    methods (TestClassSetup)
        function addToolboxToPath(testCase)
            repoRoot = fileparts(fileparts(mfilename('fullpath')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(repoRoot, 'OpenSeesMatlab')));
        end
    end

    methods (Test)
        function nodalPlotRemapsMixedVTKCells(testCase)
            [modelInfo, nodalResp] = TestPlotTopology.fixtureData();
            fig = figure('Visible', 'off');
            cleanup = onCleanup(@() close(fig));
            ax = axes(fig);

            viewer = plotter.PlotNodalResp(modelInfo, nodalResp, ax);
            viewer.plotStep(0);

            TestPlotTopology.verifyPatchConnectivity(testCase, ax);
        end

        function unstructuredPlotRemapsMixedVTKCells(testCase)
            [modelInfo, nodalResp, eleResp] = TestPlotTopology.fixtureData();
            fig = figure('Visible', 'off');
            cleanup = onCleanup(@() close(fig));
            ax = axes(fig);

            viewer = plotter.PlotUnstruResponse( ...
                modelInfo, nodalResp, eleResp, ax);
            viewer.setResponse('Plane', 'CustomAtNode', 'c1');
            viewer.plotStep(0);

            TestPlotTopology.verifyPatchConnectivity(testCase, ax);
        end

        function framePlotPreservesSingleBeamShapeAndRemapsWireframe(testCase)
            [modelInfo, ~, ~] = TestPlotTopology.fixtureData();
            modelInfo.Elements.Families.Beam = struct( ...
                'Cells', [2 2 3], 'CellTypes', 3, 'Tags', 10);
            frameResp = struct( ...
                'time', 0, ...
                'eleTags', 10, ...
                'MyVector', struct('data', zeros(1, 1, 1), ...
                    'dofs', {{'c1'}}));
            opts = plotter.PlotFrameResp.defaultOptions();
            opts.respType = 'MyVector';
            opts.component = 'c1';
            opts.responseLocation = 'element';
            opts.showMaxMinLabel = 'none';
            opts.cbar.show = false;

            fig = figure('Visible', 'off');
            cleanup = onCleanup(@() close(fig));
            ax = axes(fig);
            viewer = plotter.PlotFrameResp(modelInfo, frameResp, ax, opts);
            viewer.plotStep(0);

            testCase.verifyTrue(~isempty(findobj(ax, 'Type', 'line')) || ...
                ~isempty(findobj(ax, 'Type', 'patch')));
            testCase.verifyTrue(isfield(viewer.Handles, ...
                'UnstructuredWireframe'));
        end
    end

    methods (Static, Access = private)
        function [modelInfo, nodalResp, eleResp] = fixtureData()
            nodes = struct( ...
                'Coords', [99 99 99; 0 0 0; 1 0 0; 0 1 0; 1 1 0], ...
                'Tags', [99; 1; 2; 3; 4], ...
                'UnusedTags', 99, ...
                'Ndm', 3 * ones(5, 1), ...
                'Bounds', [0 1 0 1 0 0]);
            line = struct( ...
                'Cells', [2 2 3; 2 3 5; 2 5 4], ...
                'CellTypes', [3; 3; 3]);
            plane = struct( ...
                'Cells', [3 2 3 4 NaN; 4 2 3 5 4], ...
                'CellTypes', [5; 9], ...
                'Tags', [10; 11]);
            families = struct('Line', line, 'Plane', plane, ...
                'Unstructured', plane);
            modelInfo = struct('Nodes', nodes, ...
                'Elements', struct('Families', families));

            nodalResp = struct( ...
                'time', 0, ...
                'nodeTags', [1; 2; 3; 4], ...
                'disp', struct('data', zeros(1, 4, 3), ...
                    'dofs', {{'ux', 'uy', 'uz'}}));
            eleResp = struct( ...
                'time', 0, ...
                'nodeTags', [1; 2; 3; 4], ...
                'eleTags', [10; 11], ...
                'CustomAtNode', struct('c1', zeros(1, 4)));
        end

        function verifyPatchConnectivity(testCase, ax)
            patches = findobj(ax, 'Type', 'patch');
            testCase.verifyNotEmpty(patches);
            for i = 1:numel(patches)
                faces = patches(i).Faces;
                vertices = patches(i).Vertices;
                if ~isempty(faces)
                    testCase.verifyLessThanOrEqual( ...
                        max(faces(:), [], 'omitnan'), size(vertices, 1));
                end
            end
        end
    end
end
