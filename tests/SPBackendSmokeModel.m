%SPBACKENDSMOKEMODEL Exercise the high-level toolbox inside an OpenSeesSP job.

opsmat = OpenSeesMatlab();
assert(opsmat.backend == "sp");
assert(strcmp(opsmat.opensees.mexName, "OpenSeesMATLABSP"));
assert(strcmp(opsmat.openseesVersion, "3.8.0"));

ops = opsmat.opensees;
ops.wipe();
ops.model("basic", "-ndm", 1, "-ndf", 1);
numberOfElements = 20;
for tag = 1:(numberOfElements + 1)
    ops.node(tag, tag - 1.0);
end
ops.fix(1, 1);
ops.uniaxialMaterial("Elastic", 1, 1000.0);
for tag = 1:numberOfElements
    ops.element("Truss", tag, tag, tag + 1, 1.0, 1);
end
ops.timeSeries("Linear", 1);
ops.pattern("Plain", 1, 1);
ops.load(numberOfElements + 1, 1.0);
ops.constraints("Plain");
ops.numberer("Plain");
ops.system("BandGeneral");
ops.algorithm("Linear");
ops.integrator("LoadControl", 1.0);
ops.analysis("Static");
assert(ops.analyze(1) == 0);
assert(abs(ops.nodeDisp(numberOfElements + 1, 1) - 2.0e-2) < 1.0e-12);
ops.wipe();

fprintf("OpenSeesMatlab SP smoke test passed.\n");
