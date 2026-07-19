classdef TestSlicePlanes < matlab.unittest.TestCase
    %TESTSLICEPLANES Regression tests for multi-slice-plane support.

    methods (TestClassSetup)
        function addToolboxToPath(testCase)
            repoRoot = fileparts(fileparts(mfilename('fullpath')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(repoRoot, 'OpenSeesMatlab')));
        end

        function assumeMexAvailable(testCase)
            repoRoot = fileparts(fileparts(mfilename('fullpath')));
            mexDir = fullfile(repoRoot, 'OpenSeesMatlab', '+plotter', '+polyscope', ...
                              'vendor', '+polyscope', 'private');
            files = dir(fullfile(mexDir, 'polyscope_mex.mex*'));
            testCase.assumeTrue(~isempty(files), ...
                'polyscope MEX not available; skipping Polyscope tests.');
        end
    end

    methods (Test)
        function legacyScalarSliceOptionsAreNormalized(testCase)
            opts = plotter.polyscope.Options.defaultModelOptions();
            opts.slice.show = true;
            opts.slice.normal = [1, 0, 0];
            opts.polyscope.headless = true;
            opts.polyscope.autoShow = false;

            v = plotter.polyscope.plotModel(testCase.simpleModel_(), opts);
            cleanup = onCleanup(@() v.App.shutdown());
            v.frameTick();

            testCase.verifyTrue(isfield(v.Opts.slice, 'planes'));
            testCase.verifyEqual(numel(v.Opts.slice.planes), 1);
            testCase.verifyEqual(v.Opts.slice.planes(1).normal, [1, 0, 0]);
            testCase.verifyTrue(v.App.polyscopeHandle().has_slice_plane('Slice plane'));
        end

        function canRegisterMultipleSlicePlanes(testCase)
            opts = plotter.polyscope.Options.defaultModelOptions();
            opts.slice.planes = struct( ...
                'name',       {'Plane A'; 'Plane B'}, ...
                'show',       {true; true}, ...
                'normal',     {[1, 0, 0]; [0, 1, 0]}, ...
                'center',     {[0.5, 0.5, 0]; [0.5, 0.5, 0]}, ...
                'drawPlane',  {true; true}, ...
                'drawWidget', {false; false}, ...
                'widgetSize', {0.75; 0.75}, ...
                'color',      {[0.90, 0.35, 0.55]; [0.35, 0.90, 0.55]}, ...
                'gridColor',  {[1, 1, 1]; [1, 1, 1]}, ...
                'transparency', {0.45; 0.45}, ...
                'cullWholeElements', {false; false});
            opts.polyscope.headless = true;
            opts.polyscope.autoShow = false;

            v = plotter.polyscope.plotModel(testCase.simpleModel_(), opts);
            cleanup = onCleanup(@() v.App.shutdown());
            v.frameTick();

            ps = v.App.polyscopeHandle();
            testCase.verifyTrue(ps.has_slice_plane('Plane A'));
            testCase.verifyTrue(ps.has_slice_plane('Plane B'));
        end

        function addAndRemovePlaneApi(testCase)
            opts = plotter.polyscope.Options.defaultModelOptions();
            opts.slice.show = true;
            opts.polyscope.headless = true;
            opts.polyscope.autoShow = false;

            v = plotter.polyscope.plotModel(testCase.simpleModel_(), opts);
            cleanup = onCleanup(@() v.App.shutdown());
            v.frameTick();

            v.addSlicePlane();
            v.addSlicePlane();
            testCase.verifyEqual(numel(v.Opts.slice.planes), 3);

            v.removeSlicePlane(2);
            testCase.verifyEqual(numel(v.Opts.slice.planes), 2);

            v.applySlicePlanes();
            ps = v.App.polyscopeHandle();
            testCase.verifyTrue(ps.has_slice_plane('Slice plane'));
            testCase.verifyTrue(ps.has_slice_plane('Slice plane 2'));
            testCase.verifyFalse(ps.has_slice_plane('Slice plane 1'));
        end

        function removeAllPlanesThenAddBack(testCase)
            opts = plotter.polyscope.Options.defaultModelOptions();
            opts.slice.show = true;
            opts.polyscope.headless = true;
            opts.polyscope.autoShow = false;

            v = plotter.polyscope.plotModel(testCase.simpleModel_(), opts);
            cleanup = onCleanup(@() v.App.shutdown());
            v.frameTick();
            v.enableGui();

            v.removeSlicePlane(1);
            v.applySlicePlanes();
            testCase.verifyEqual(numel(v.Opts.slice.planes), 0);

            v.addSlicePlane();
            v.applySlicePlanes();
            ps = v.App.polyscopeHandle();
            testCase.verifyTrue(ps.has_slice_plane('Slice plane 1'));
        end
    end

    methods (Access = private)
        function model = simpleModel_(~)
            model = struct();
            model.Nodes = struct('Coords', [0, 0, 0; 1, 0, 0; 1, 1, 0], ...
                                 'Tags', [1; 2; 3]);
        end
    end
end
