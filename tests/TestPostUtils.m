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
    end
end
