classdef TestOpenSeesMexIntegration < matlab.unittest.TestCase
    % Integration tests that exercise the OpenSees MEX backend.
    %
    % These tests are skipped automatically when the bundled MEX module is not
    % available for the current platform.

    methods (TestClassSetup)
        function addToolboxToPath(testCase)
            repoRoot = fileparts(fileparts(mfilename('fullpath')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(repoRoot, 'OpenSeesMatlab')));
        end
    end

    methods (Test)
        function mexModuleLoadsAndReportsVersion(testCase)
            opsmat = TestOpenSeesMexIntegration.makeOpsMat(testCase);
            cleanup = onCleanup(@() opsmat.opensees.wipe());

            testCase.verifyTrue(opsmat.opensees.hasMex());
            testCase.verifyNotEmpty(opsmat.opensees.mexPath());
            testCase.verifyClass(opsmat.version, 'char');
            testCase.verifyMatches(opsmat.version, '^\d+\.\d+\.\d+');
            testCase.verifyEqual(opsmat.version, opsmat.bindingVersion);
            testCase.verifyClass(opsmat.openseesVersion, 'char');
            testCase.verifyMatches(opsmat.openseesVersion, '^\d+\.\d+\.\d+');
            testCase.verifyEqual(opsmat.backend, "serial");
            testCase.verifyEqual(opsmat.opensees.openseesVersion(), ...
                opsmat.openseesVersion);

            clear cleanup
        end

        function canBuildAndQueryBasicDomain(testCase)
            opsmat = TestOpenSeesMexIntegration.makeOpsMat(testCase);
            cleanup = onCleanup(@() opsmat.opensees.wipe());
            ops = opsmat.opensees;

            TestOpenSeesMexIntegration.buildTrussModel(ops);

            testCase.verifyEqual(double(ops.getNodeTags()), [1 2]);
            testCase.verifyEqual(double(ops.getEleTags()), 1);
            testCase.verifyEqual(double(ops.nodeCoord(2)), [1 0], 'AbsTol', 1.0e-12);
            testCase.verifyEqual(double(ops.eleNodes(1)), [1 2]);
            testCase.verifyEqual(double(ops.getNDM(2)), 2);
            testCase.verifyEqual(double(ops.getNDF(2)), 2);

            clear cleanup
        end

        function linearStaticTrussAnalysisMatchesClosedForm(testCase)
            opsmat = TestOpenSeesMexIntegration.makeOpsMat(testCase);
            cleanup = onCleanup(@() opsmat.opensees.wipe());
            ops = opsmat.opensees;

            TestOpenSeesMexIntegration.buildStaticTrussModel(ops);
            ok = ops.analyze(1);

            testCase.verifyEqual(double(ok), 0);
            testCase.verifyEqual(double(ops.nodeDisp(2)), [0.01 0], ...
                'AbsTol', 1.0e-10);
            testCase.verifyEqual(double(ops.eleForce(1)), [-10 0 10 0], ...
                'AbsTol', 1.0e-8);

            clear cleanup
        end

        function femDataSchemaFeedsNamedPostDataset(testCase)
            opsmat = TestOpenSeesMexIntegration.makeOpsMat(testCase);
            cleanup = onCleanup(@() opsmat.opensees.wipe());
            outputFile = [tempname '.h5'];
            fileCleanup = onCleanup(@() TestOpenSeesMexIntegration.deleteIfPresent(outputFile));
            ops = opsmat.opensees;

            TestOpenSeesMexIntegration.buildStaticTrussModel(ops);
            recorderTag = ops.FEMDataRecorder(outputFile, '-saveNodalResp');
            testCase.assertEqual(double(ops.analyze(1)), 0);
            ops.remove('recorder', recorderTag);

            recorded = ops.readFEMData(outputFile, 'nodal');
            testCase.verifyTrue(isfield(recorded, 'responseSchema'));
            schemaIndex = find(strcmp(recorded.responseSchema.paths, 'disp.ux'), 1);
            testCase.verifyNotEmpty(schemaIndex);
            testCase.verifyEqual(recorded.responseSchema.dimensions{schemaIndex}, ...
                {'time', 'node'});

            dataset = post.toResponseDataset(recorded);
            displacement = dataset('disp.ux');
            testCase.verifyEqual(displacement.Dimensions, ["time", "node"]);

            clear fileCleanup cleanup
        end

        function postProcessorCollectsMexModelData(testCase)
            opsmat = TestOpenSeesMexIntegration.makeOpsMat(testCase);
            cleanup = onCleanup(@() opsmat.opensees.wipe());

            TestOpenSeesMexIntegration.buildTrussModel(opsmat.opensees);
            modelInfo = opsmat.post.getModelData();

            testCase.verifyEqual(double(modelInfo.NumNode), 2);
            testCase.verifyEqual(double(modelInfo.NumElement), 1);
            testCase.verifyEqual(double(modelInfo.Nodes.Tags(:).'), [1 2]);
            testCase.verifyEqual(double(modelInfo.Nodes.Coords(1:2, 1:2)), ...
                [0 0; 1 0], 'AbsTol', 1.0e-12);
            testCase.verifyTrue(isfield(modelInfo.Elements.Families, 'Truss'));
            testCase.verifyEqual(double(modelInfo.Elements.Families.Truss.Cells), [2 1 2]);

            clear cleanup
        end

        function postModelDataMatchesNativeSnapshot(testCase)
            opsmat = TestOpenSeesMexIntegration.makeOpsMat(testCase);
            cleanup = onCleanup(@() opsmat.opensees.wipe());
            outputFile = [tempname '.h5'];
            fileCleanup = onCleanup(@() TestOpenSeesMexIntegration.deleteIfPresent(outputFile));
            ops = opsmat.opensees;

            TestOpenSeesMexIntegration.buildTrussModel(ops);
            ops.equalDOF(1, 2, 1);
            ops.timeSeries('Linear', 1);
            ops.pattern('Plain', 1, 1);
            ops.load(2, 2.0, 0.0);

            fromPost = opsmat.post.getModelData();
            testCase.assertEqual(double(ops.writeFEMModel(outputFile)), 0);
            fromNative = ops.readFEMData(outputFile, 'model');

            testCase.verifyEqual(fromPost, fromNative);
            testCase.verifyEqual(double(fromPost.MPConstraint.PairNodeTags), [1 2]);
            testCase.verifyTrue(isfield(fromPost.MPConstraint, 'RetainedDofs'));
            testCase.verifyTrue(isfield(fromPost.MPConstraint, 'ConstrainedDofs'));

            clear fileCleanup cleanup
        end

        function preProcessorAssemblesStiffnessMatrixFromMexModel(testCase)
            opsmat = TestOpenSeesMexIntegration.makeOpsMat(testCase);
            cleanup = onCleanup(@() opsmat.opensees.wipe());

            TestOpenSeesMexIntegration.buildTrussModel(opsmat.opensees);
            K = opsmat.pre.getMCK('k');

            testCase.verifyEqual(K.Type, 'k');
            testCase.verifySize(K.Data, [4 4]);
            expectedK = [1.0e12 + 1000 0 -1000 0; ...
                         0 1.0e12 0 0; ...
                         -1000 0 1000 0; ...
                         0 0 0 1.0e12];
            testCase.verifyEqual(K.Data, expectedK, 'AbsTol', 1.0e-8);
            testCase.verifyNumElements(K.Labels, 4);

            clear cleanup
        end
    end

    methods (Static, Access = private)
        function deleteIfPresent(path)
            if isfile(path)
                delete(path);
            end
        end

        function opsmat = makeOpsMat(testCase)
            mexDir = TestOpenSeesMexIntegration.findMexDir();
            testCase.assumeTrue(isfolder(mexDir), ...
                'OpenSees MEX directory is not available on this platform.');

            try
                opsmat = OpenSeesMatlab(mexDir=mexDir);
            catch ME
                testCase.assumeTrue(false, ...
                    sprintf('OpenSees MEX could not be loaded: %s', ME.message));
            end
        end

        function mexDir = findMexDir()
            repoRoot = fileparts(fileparts(mfilename('fullpath')));
            ops.connectOpenSeesNexus();
            candidate = fullfile(repoRoot, 'OpenSeesMatlab', '+ops', ...
                'OpenSeesNexus', 'derived', ...
                OpenSeesNexus.platformKey());

            ext = mexext();
            mexFile = fullfile(candidate, ['OpenSeesMATLAB.' ext]);
            if isfile(mexFile)
                mexDir = candidate;
            else
                mexDir = '';
            end
        end

        function buildTrussModel(ops)
            ops.wipe();
            ops.model('basic', '-ndm', 2, '-ndf', 2);
            ops.node(1, 0.0, 0.0);
            ops.node(2, 1.0, 0.0);
            ops.fix(1, 1, 1);
            ops.fix(2, 0, 1);
            ops.uniaxialMaterial('Elastic', 1, 1000.0);
            ops.element('truss', 1, 1, 2, 1.0, 1);
        end

        function buildStaticTrussModel(ops)
            TestOpenSeesMexIntegration.buildTrussModel(ops);
            ops.timeSeries('Linear', 1);
            ops.pattern('Plain', 1, 1);
            ops.load(2, 10.0, 0.0);
            ops.system('BandGeneral');
            ops.numberer('Plain');
            ops.constraints('Plain');
            ops.integrator('LoadControl', 1.0);
            ops.algorithm('Linear');
            ops.analysis('Static');
        end
    end
end
