classdef TestPolyscopeSSAA < matlab.unittest.TestCase
    %TESTPOLYSCOPESSAA Regression tests for Polyscope SSAA initialization.

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
        function defaultSsaaFactorIsTwoAfterInit(testCase)
            app = plotter.polyscope.PolyscopeApp();
            cleanup = onCleanup(@() app.shutdown());

            opts = plotter.polyscope.Options.defaultModelOptions();
            opts.polyscope.headless = true;
            app.init('openGL_mock', opts, false);

            testCase.verifyEqual(double(app.getSSAAFactor()), 2);
        end

        function ssaaFactorCanBeChangedAfterInit(testCase)
            app = plotter.polyscope.PolyscopeApp();
            cleanup = onCleanup(@() app.shutdown());

            opts = plotter.polyscope.Options.defaultModelOptions();
            opts.polyscope.headless = true;
            opts.polyscope.ssaaFactor = 3;
            app.init('openGL_mock', opts, false);

            testCase.verifyEqual(double(app.getSSAAFactor()), 3);

            app.setSSAAFactor(1);
            testCase.verifyEqual(double(app.getSSAAFactor()), 1);
        end

        function defaultScalarColorMapIsCoolwarm(testCase)
            opts = plotter.polyscope.Options.defaultModelOptions();
            testCase.verifyEqual(char(string(opts.polyscope.scalarColorMap)), 'coolwarm');
            opts = plotter.polyscope.Options.defaultFrameResponseOptions();
            testCase.verifyEqual(char(string(opts.polyscope.scalarColorMap)), 'coolwarm');
            opts = plotter.polyscope.Options.defaultNodalResponseOptions();
            testCase.verifyEqual(char(string(opts.polyscope.scalarColorMap)), 'coolwarm');
            opts = plotter.polyscope.Options.defaultUnstructuredResponseOptions();
            testCase.verifyEqual(char(string(opts.polyscope.scalarColorMap)), 'coolwarm');
            opts = plotter.polyscope.Options.defaultEigenOptions();
            testCase.verifyEqual(char(string(opts.polyscope.scalarColorMap)), 'coolwarm');
        end
    end
end
