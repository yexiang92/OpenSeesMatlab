classdef TestResponseDataset < matlab.unittest.TestCase
    methods (TestClassSetup)
        function addProjectPath(~)
            repoRoot=fileparts(fileparts(mfilename('fullpath')));
            addpath(fullfile(repoRoot,'OpenSeesMatlab'));
        end
    end
    methods (Test)
        function convertsAndSelectsNodalResponse(testCase)
            r=struct('odbTag',"demo",'time',[0;1;2], ...
                'nodeTags',[10;20],'disp',struct('ux',[1 2;3 4;5 6]));
            original=r;
            ds=post.toResponseDataset(r);
            testCase.verifyTrue(ds.has("disp.ux"));
            a=ds("disp.ux");
            testCase.verifyEqual(a.Dimensions,["time","node"]);
            testCase.verifyEqual(a.sel("node",20).Data,[2;4;6]);
            testCase.verifyEqual(a.sel("time",1.2,"Method","nearest").Data,[3 4]);
            testCase.verifyEqual(r,original);
        end
        function supportsDotVariableAndCoordinateAccess(testCase)
            r=struct('time',[0;0.5;1],'nodeTags',[10;20], ...
                'disp',struct('ux',[1 2;3 4;5 6]));
            ds=post.toResponseDataset(r);
            a=ds.disp.ux;
            testCase.verifyClass(a,'post.ResponseArray');
            testCase.verifyEqual(ds.disp.ux.time,[0;0.5;1]);
            testCase.verifyEqual(ds.disp.ux.time(2),0.5);
            testCase.verifyEqual(ds.disp.ux.node,[10;20]);
            testCase.verifyEqual(ds.disp.ux.Data,r.disp.ux);
        end
        function convertsElementComponents(testCase)
            r=struct('time',[0;1],'eleTags',[101;205], ...
                'force',reshape(1:12,[2 2 3]));
            ds=post.ResponseDataset.fromStruct(r);
            a=ds("force");
            testCase.verifyEqual(a.Dimensions,["time","element","component"]);
            testCase.verifyEqual(size(a.sel("element",205).Data),[2 1 3]);
        end
        function preservesImplicitSingletonDimensionsAfterSelection(testCase)
            r=struct('time',(0:3).','eleTags',[1;2], ...
                'eleType',"Frame",'sectionDeformations', ...
                struct('Mz',zeros(4,2,5)));
            ds=post.toResponseDataset(r);
            a=ds.sectionDeformations.Mz;
            selected=a.sel("element",1,"section",1);
            testCase.verifyEqual(selected.Dimensions, ...
                ["time","element","section"]);
            testCase.verifyEqual(size(selected.Data),[4,1]);
            testCase.verifyEqual(selected.element,1);
            testCase.verifyEqual(selected.section,1);
        end
        function recognizesFEMDataGaussPointAndNodeLayouts(testCase)
            r=struct('time',(0:2).','eleTags',[11;12],'nodeTags',[1;2;3;4]);
            r.SolidResponses.StressAtGP.sxx=zeros(3,2,8);
            r.SolidResponses.StressAtNode.sxx=zeros(3,4);
            ds=post.toResponseDataset(r);
            gp=ds("SolidResponses.StressAtGP.sxx");
            nd=ds("SolidResponses.StressAtNode.sxx");
            testCase.verifyEqual(gp.Dimensions, ...
                ["time","element","gaussPoint"]);
            testCase.verifyEqual(nd.Dimensions, ...
                ["time","node"]);
        end
        function recognizesShellFiberAndFrameSectionLayouts(testCase)
            r=struct('time',[0;1],'eleTags',[21;22;23],'nodeTags',(1:5).');
            r.ShellResponses.StressAtGP.sxx=zeros(2,3,4,7);
            r.ShellResponses.StressAtNode.sxx=zeros(2,5,7);
            r.FrameResponses.sectionForces.N=zeros(2,3,6);
            r.FrameResponses.Fibers.Stress=zeros(2,3,6,20);
            r.FrameResponses.Fibers.ElementSectionMap=zeros(3,6);
            r.FrameResponses.Fibers.Geometry.Area=zeros(4,20);
            ds=post.toResponseDataset(r);
            gp=ds("ShellResponses.StressAtGP.sxx");
            nd=ds("ShellResponses.StressAtNode.sxx");
            sec=ds("FrameResponses.sectionForces.N");
            fib=ds("FrameResponses.Fibers.Stress");
            fibMap=ds("FrameResponses.Fibers.ElementSectionMap");
            fibArea=ds("FrameResponses.Fibers.Geometry.Area");
            testCase.verifyEqual(gp.Dimensions, ...
                ["time","element","gaussPoint","fiber"]);
            testCase.verifyEqual(nd.Dimensions, ...
                ["time","node","fiber"]);
            testCase.verifyEqual(sec.Dimensions, ...
                ["time","element","section"]);
            testCase.verifyEqual(fib.Dimensions, ...
                ["time","element","section","fiber"]);
            testCase.verifyEqual(fibMap.Dimensions,["element","section"]);
            testCase.verifyEqual(fibArea.Dimensions,["sectionGeometry","fiber"]);
        end
        function usesEleTypeForSelectedShellGroup(testCase)
            r=struct('time',[0;1],'eleTags',[1;2],'eleType',"Shell", ...
                'StressAtGP',struct('sxx',zeros(2,2,4,3)));
            ds=post.toResponseDataset(r); a=ds("StressAtGP.sxx");
            testCase.verifyEqual(a.Dimensions, ...
                ["time","element","gaussPoint","fiber"]);
        end
        function prefersReaderSchema(testCase)
            schema=struct('version',1,'paths',{{'custom.values'}}, ...
                'dimensions',{{{'time','element','integrationPoint'}}});
            r=struct('time',[0;1],'eleTags',[7;8], ...
                'responseSchema',schema,'custom',struct('values',zeros(2,2,3)));
            ds=post.toResponseDataset(r); a=ds("custom.values");
            testCase.verifyEqual(a.Dimensions, ...
                ["time","element","integrationPoint"]);
            testCase.verifyFalse(ds.has("responseSchema.version"));
        end
        function keepsSchemaTrailingSingletonDimension(testCase)
            schema=struct('version',1,'paths',{{'section.Mz'}}, ...
                'dimensions',{{{'time','element','section'}}});
            r=struct('time',[0;1],'eleTags',[7;8], ...
                'responseSchema',schema,'section',struct('Mz',zeros(2,2,1)));
            ds=post.toResponseDataset(r); a=ds.section.Mz;
            testCase.verifyEqual(a.Dimensions,["time","element","section"]);
            testCase.verifyEqual(a.section,1);
        end
        function recognizesInterpolationStaticAndTransientLayouts(testCase)
            r=struct('time',[0;1],'nodeTags',[1;2], ...
                'interpolateCoords',zeros(5,3),'interpolateCells',zeros(4,3), ...
                'interpolateDisp',zeros(2,5,3));
            ds=post.toResponseDataset(r);
            testCase.verifyEqual(ds.interpolateCoords.Dimensions, ...
                ["interpolationPoint","component"]);
            testCase.verifyEqual(ds.interpolateCells.Dimensions, ...
                ["interpolationCell","cellEntry"]);
            testCase.verifyEqual(ds.interpolateDisp.Dimensions, ...
                ["time","interpolationPoint","component"]);
        end
    end
end
