%% *Static analysis and visualization of 2D Portal Frame*
% This portal frame is small enough to inspect node tags, element axes, reactions, 
% and section forces directly. It serves as a practical introduction to the plotting 
% and response-query tools after a static analysis.
% 
% *See the original example in [opsvis](https://opsvis.readthedocs.io/en/latest/ex_2d_portal_frame.html).*

clc; clear; close all;
opsMAT = OpenSeesMatlab();
ops = opsMAT.opensees;
% Model construction and load application

ops.wipe();
ops.model('basic', '-ndm', 2, '-ndf', 3);

colL = 4.0;
girL = 6.0;

Acol  = 2.0e-3;
Agir  = 6.0e-3;
IzCol = 1.6e-5;
IzGir = 5.4e-5;

E = 200.0e9;

ops.node(1, 0.0,   0.0);
ops.node(2, 0.0,   colL);
ops.node(3, girL,  0.0);
ops.node(4, girL,  colL);

ops.fix(1, 1, 1, 1);
ops.fix(3, 1, 1, 0);

ops.geomTransf('Linear', 1);

% columns
ops.element('elasticBeamColumn', 1, 1, 2, Acol, E, IzCol, 1);
ops.element('elasticBeamColumn', 2, 3, 4, Acol, E, IzCol, 1);

% girder
ops.element('elasticBeamColumn', 3, 2, 4, Agir, E, IzGir, 1);

% ops.section('Elastic', 1, E, Agir, IzGir, E/2, 0.75)
% ops.beamIntegration('Lobatto', 1, 1, 5)
% ops.element('forceBeamColumn', 3, 2, 4, 1, 1)

Px =  2.0e3;
Wy = -10.0e3;
Wx =  0.0;
ops.timeSeries('Linear', 1);
ops.pattern('Plain', 1, 1);
ops.load(2, Px, 0.0, 0.0);
ops.eleLoad('-ele', 3, '-type', '-beamUniform', Wy, Wx);
modelData = opsMAT.post.getModelData();
opts = opsMAT.vis.defaultPlotModelOptions;
opts.loads.showNodal = true;
opts.loads.showElement = true;
opts.loads.scale = 1.2;
opsMAT.vis.plotModel(opts=opts);
opsMAT.vis.plotModelGUI();
% Static analysis

ODB = opsMAT.post.createODB("myODB", interpolateBeamDisp=11);
Nsteps = 10;
ops.constraints('Transformation');
ops.numberer('RCM');
ops.system('BandGeneral');
ops.test('NormDispIncr', 1.0e-6, 6, 2);
ops.algorithm('Linear');
ops.integrator('LoadControl', 1 / Nsteps);
ops.analysis('Static');
ops.analyze(Nsteps);
% Results visualization

nodeResp = opsMAT.post.getNodalResponse("myODB");

opsMAT.vis.plotNodalResponse(nodeResp, stepIdx="absMax");
grid off
eleResp = opsMAT.post.getElementResponse("myODB", eleType="Frame");

opsMAT.vis.plotFrameResponse(eleResp, ...
    stepIdx="absMax", respType="sectionForces", respComponent="MZ");
grid off
opts = opsMAT.vis.defaultPlotFrameResponseOptions;
opts.style = "wireframe";
opsMAT.vis.plotFrameResponse(eleResp, ...
    stepIdx="absMax", respType="sectionForces", respComponent="Mz",...
    opts=opts);
grid off
opts.color.useColormap = false;
opsMAT.vis.plotFrameResponse(eleResp, ...
    stepIdx="absMax", respType="sectionForces", respComponent="N",...
    opts=opts);
grid off
opsMAT.vis.plotFrameResponse(eleResp, ...
    stepIdx="absMax", respType="sectionForces", respComponent="VY",...
    opts=opts);
grid off
opsMAT.vis.plotFrameResponse(eleResp, ...
    stepIdx="absMax", respType="basicForces", respComponent="MZ",...
    opts=opts);
grid off
opsMAT.vis.plotFrameResponse(eleResp, ...
    stepIdx="absMax", respType="localForces", respComponent="FY",...
    opts=opts);
grid off
% Visualization based on Matlab GUI

opsMAT.vis.plotModelGUI();
%% 
% 

opsMAT.vis.plotNodalResponseGUI(nodeResp);
%% 
% 

opsMAT.vis.plotFrameResponseGUI(eleResp);
%% 
% 
% Visualization based on Polyscope GUI

opsMAT.vis.polyscope.plotModel();
%% 
% 

opsMAT.vis.polyscope.plotNodalResponse(nodeResp);
%% 
% 

opsMAT.vis.polyscope.plotFrameResponse(eleResp);
%% 
% 


% Checks after analysis
% Reaction sums should balance the applied loads. Deformed shape, local axes, 
% and section-force diagrams should be inspected together so component signs are 
% interpreted in the correct element coordinate system.