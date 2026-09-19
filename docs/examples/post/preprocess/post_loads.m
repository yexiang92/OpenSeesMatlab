%% *Loads Processing*
% The goal is to inspect loads already stored in an OpenSees domain. Nodal loads, 
% elemental loads, and load-pattern factors are retrieved separately so their 
% contributions are not confused.
% Build a frame with known local axes
% The diagonal member makes local and global load directions visibly different. 
% Displaying the beam axes beside the loads is the quickest way to verify the 
% conversion.

clc; clear;

opsMAT = OpenSeesMatlab();
ops = opsMAT.opensees;
ops.wipe();
ops.model("basic", "-ndm", 3, "-ndf", 6);
ops.node(1, 0, 0, 1);
ops.node(2, 0, 2, 1);
ops.node(3, 2, 2, 1);
ops.node(4, 2, 0, 1);

ops.geomTransf("Linear", 1, 0, 0, 1);
ops.element("elasticBeamColumn", 1, 1, 2, 1000, 1000, 1000, 1000, 1000, 1000, 1);
ops.element("elasticBeamColumn", 2, 2, 3, 1000, 1000, 1000, 1000, 1000, 1000, 1);
ops.element("elasticBeamColumn", 3, 3, 4, 1000, 1000, 1000, 1000, 1000, 1000, 1);
ops.element("elasticBeamColumn", 4, 4, 1, 1000, 1000, 1000, 1000, 1000, 1000, 1);
ops.element("elasticBeamColumn", 5, 1, 3, 1000, 1000, 1000, 1000, 1000, 1000, 1);
ops.timeSeries("Linear", 1);
ops.pattern("Plain", 1, 1);
% Create global beam loads
% The preprocessing helpers convert global uniform and point loads into the 
% local components required by each beam element. Separate load patterns make 
% the two load types easy to inspect.

opsMAT.pre.beamGlobalUniformLoad([1, 2, 3, 4, 5], wy=2, wz=-2);

ops.pattern("Plain", 2, 1);
opsMAT.pre.beamGlobalPointLoad([1, 2, 3, 4, 5], py=2, pz=-3, xl=0.5);
% Inspect the generated loads
% |getModelData| returns the load definitions stored in the domain. The final 
% plot shows element labels, local axes, and both applied load sets together.

a= opsMAT.post.getModelData();
figure;
opts = opsMAT.vis.defaultPlotModelOptions;
opts.loads.showNodal = true;
opts.loads.showElement = true;
opts.loads.scale = 2;
opts.localAxes.showBeam = true;
opts.elements.showLabels = true;

opsMAT.vis.plotModel(opts=opts);
zlim([0,2]);

% Checking load conversion
% Global load arrows should retain their intended direction on members with 
% different local axes. Element labels and local-axis glyphs make an incorrect 
% sign or component conversion visible.