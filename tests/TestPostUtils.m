classdef TestPostUtils < matlab.unittest.TestCase
    % Tests for pure MATLAB post-processing helper utilities.

    methods (TestClassSetup)
        function addToolboxToPath(testCase)
            repoRoot = fileparts(fileparts(mfilename('fullpath')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(repoRoot, 'OpenSeesMatlab')));
        end
    end

    methods (Test)
        function finiteElementShapeLibraryReturnsKnownData(testCase)
            shapeFunc = post.utils.FEShapeLibrary.getShapeFunc("quad", 4, 4);
            gaussData = post.utils.FEShapeLibrary.getGaussData("quad", 4, 4);
            project = post.utils.FEShapeLibrary.getGP2NodeFunc("quad", 4, 4);

            testCase.verifyNotEmpty(shapeFunc);
            testCase.verifyEqual(gaussData.gp_w, ones(4, 1));

            gpResp = (1:4).';
            testCase.verifyEqual(project("copy", gpResp), gpResp);
            testCase.verifyEqual(project("average", gpResp), 2.5 * ones(4, 1), ...
                'AbsTol', 1.0e-12);

            testCase.verifyEmpty(post.utils.FEShapeLibrary.getShapeFunc("quad", 5, 4));
        end

        function openSeesTagMapsResolveNamesAndGroups(testCase)
            testCase.verifyEqual(post.utils.OpenSeesTagMaps.getClassName(3), ...
                "ElasticBeam2d");
            testCase.verifyEqual(post.utils.OpenSeesTagMaps.getClassName(999999), ...
                "ClassTag_999999");
            testCase.verifyTrue(post.utils.OpenSeesTagMaps.isInGroup(3, 'Beam'));
            testCase.verifyFalse(post.utils.OpenSeesTagMaps.isInGroup(3, 'Shell'));
            testCase.verifyError(@() post.utils.OpenSeesTagMaps.isInGroup(3, 'Nope'), ...
                'OpenSeesTagMaps:InvalidGroup');
        end

        function structMergerConcatenatesCompatibleNumericLeaves(testCase)
            p1 = struct('time', [0; 1], 'node', struct('disp', [1 2; 3 4]), ...
                'label', "segment");
            p2 = struct('time', 2, 'node', struct('disp', [5 6]), ...
                'label', "segment");

            out = post.utils.StructMerger.mergeParts({p1, p2}, 'Mode', 'concat');

            testCase.verifyEqual(out.time, [0; 1; 2]);
            testCase.verifyEqual(out.node.disp, [1 2; 3 4; 5 6]);
            testCase.verifyEqual(out.label, "segment");
        end

        function structMergerPrependsEqualShapedParts(testCase)
            p1 = struct('values', [1 2; 3 4]);
            p2 = struct('values', [5 6; 7 8]);

            out = post.utils.StructMerger.mergeParts({p1, p2}, 'Mode', 'prepend');

            testCase.verifySize(out.values, [2 2 2]);
            testCase.verifyEqual(squeeze(out.values(1, :, :)), p1.values);
            testCase.verifyEqual(squeeze(out.values(2, :, :)), p2.values);
        end

        function femModelAdapterConvertsNativeBeamLoads(testCase)
            raw = [ ...
                -2, 0.5, 0, 0, 0, 0, 0, 0; ...
                 1, 2, 3, 0, 0, 0, 0, 0; ...
                 4, 0.25, 5, 0, 0, 0, 0, 0; ...
                 4, 6, 0.25, 5, 0, 0, 0, 0; ...
                 1, 2, 3, 4, 0.1, 0.9, 0, 0; ...
                 1, 2, 3, 0.1, 0.9, 4, 5, 6];
            beam = struct('Values', raw, 'ClassTags', [3; 5; 4; 6; 12; 121]);
            loads = struct('Element', struct('Beam', beam));

            out = plotter.utils.FEMModelAdapter.loadsForPlotting(loads);
            expected = [ ...
                -2, -2, 0, 0, 0.5, 0.5, 0, 1, 3, 2; ...
                 1,  1, 2, 2, 3,   3,   0, 1, 5, 3; ...
                 4,  0, 0, 0, 5,   0, 0.25, -10000, 4, 3; ...
                 4,  0, 6, 0, 5,   0, 0.25, -10000, 6, 4; ...
                 1,  2, 0, 0, 3,   4, 0.1, 0.9, 12, 6; ...
                 1,  4, 2, 5, 3,   6, 0.1, 0.9, 121, 8];
            testCase.verifyEqual(out.Element.Beam.Values, expected);
        end

        function femModelAdapterRemapsCountPrefixedCells(testCase)
            cells = [ ...
                3, 2, 3, 4, NaN; ...
                4, 2, 4, 5, 6; ...
                3, 1, 3, 4, NaN];
            rawToClean = [0; 1; 2; 3; 0; 4];

            [actual, keepRows, usedRows] = ...
                plotter.utils.FEMModelAdapter.remapVTKCells(cells, rawToClean);

            testCase.verifyEqual(keepRows, [true; false; false]);
            testCase.verifyEqual(actual, [3, 1, 2, 3, NaN]);
            testCase.verifyEqual(usedRows, [1; 2; 3]);
        end

        function femModelAdapterDoesNotRemapCellPointCount(testCase)
            cells = [4, 4, 5, 6, 7];
            rawToClean = [0; 0; 0; 1; 2; 3; 4];

            actual = plotter.utils.FEMModelAdapter.remapVTKCells( ...
                cells, rawToClean);

            testCase.verifyEqual(actual, [4, 1, 2, 3, 4]);
        end

        function polyscopeAdapterExcludesUnusedNodesFromDisplayGeometry(testCase)
            modelInfo.Nodes = struct( ...
                'Coords', [100 100 0; 0 0 0; 2 0 0], ...
                'Tags', [99; 1; 2], ...
                'UnusedTags', 99);

            rows = plotter.polyscope.ModelAdapter.activeNodeRows(modelInfo);
            centered = plotter.polyscope.ModelAdapter.nodeCoords(modelInfo);
            modelLength = plotter.polyscope.ModelAdapter.modelLength(modelInfo);

            testCase.verifyEqual(rows, [2; 3]);
            testCase.verifyEqual(centered(2:3, :), [-1 0 0; 1 0 0]);
            testCase.verifyEqual(modelLength, 2);
        end

        function pvdWriterAcceptsDirectAndWrappedResponses(testCase)
            modelInfo.Nodes = struct( ...
                'Coords', [0 0 0; 1 0 0], ...
                'Tags', [1; 2], ...
                'UnusedTags', zeros(0, 1));
            modelInfo.Elements.Families.Line = struct( ...
                'Cells', [2 1 2], 'CellTypes', 3, 'Tags', 1);
            response = struct( ...
                'time', 0, ...
                'nodeTags', [1; 2], ...
                'disp', struct('data', zeros(1, 2, 3), ...
                    'dofs', {{'ux', 'uy', 'uz'}}));

            direct = post.utils.PVDWriter(modelInfo, nodalResp=response);
            wrapped = post.utils.PVDWriter(modelInfo, ...
                nodalResp=struct('NodalResponses', response));

            testCase.verifyEqual(direct.nSteps(), 1);
            testCase.verifyEqual(wrapped.nSteps(), 1);
        end

        function pvdWriterUsesUnusedTagsFromEachSegment(testCase)
            coords = [9 9 0; 0 0 0; 1 0 0; 8 8 0];
            line = struct('Cells', [2 2 3], 'CellTypes', 3, 'Tags', 10);
            nodes = struct( ...
                'Coords', coords, ...
                'Tags', [99; 1; 2; 100], ...
                'UnusedTags', 99, ...
                'Ndm', 2 * ones(4, 1));
            model1 = struct('Nodes', nodes, ...
                'Elements', struct('Families', struct('Line', line)));
            nodes.UnusedTags = 100;
            model2 = struct('Nodes', nodes, ...
                'Elements', struct('Families', struct('Line', line)));

            resp1 = TestPostUtils.nodalResponse(0, [1; 2; 100]);
            resp2 = TestPostUtils.nodalResponse(1, [99; 1; 2]);
            writer = post.utils.PVDWriter([model1, model2], ...
                nodalResp=[resp1, resp2]);

            outDir = tempname;
            mkdir(outDir);
            cleanup = onCleanup(@() rmdir(outDir, 's'));
            writer.write(outDir, 'stage');
            files = dir(fullfile(outDir, 'stage_nodal', 'vtu', '*.vtu'));
            testCase.verifyNumElements(files, 2);
            first = fileread(fullfile(files(1).folder, files(1).name));
            second = fileread(fullfile(files(2).folder, files(2).name));

            testCase.verifySubstring(first, '0 0 0 1 0 0 8 8 0');
            testCase.verifySubstring(second, '9 9 0 0 0 0 1 0 0');
            clear cleanup
        end
    end

    methods (Static, Access = private)
        function response = nodalResponse(time, nodeTags)
            response = struct( ...
                'time', time, ...
                'nodeTags', nodeTags, ...
                'disp', struct('data', zeros(1, numel(nodeTags), 3), ...
                    'dofs', {{'ux', 'uy', 'uz'}}));
        end
    end
end
