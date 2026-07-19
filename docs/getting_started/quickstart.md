# Your First Analysis

This tutorial builds a two-dimensional elastic truss, applies a static load, solves it in one step, and reads the displacement into MATLAB. It is intentionally small so that the complete OpenSeesMatlab workflow is visible in one place.

## Create the interface

```matlab
opsMat = OpenSeesMatlab();
ops = opsMat.opensees;

ops.wipe();
```

[`opsMat`][OpenSeesMatlab] owns the toolbox modules. `ops` is only a shorter reference to its [`.opensees` command interface][ops.OpenSeesMatlabCmds].

## Define the model

The model has two translational degrees of freedom per node. SI units are used consistently in this tutorial.

```matlab
ops.model('basic', '-ndm', 2, '-ndf', 2);

L = 1.0;       % m
A = 2.0e-3;    % m^2
E = 200.0e9;   % Pa
P = 100.0e3;   % N

ops.node(1, 0.0, 0.0);
ops.node(2, L,   0.0);

ops.fix(1, 1, 1);
ops.fix(2, 0, 1);

ops.uniaxialMaterial('Elastic', 1, E);
ops.element('Truss', 1, 1, 2, A, 1);
```

The vertical degree of freedom at node 2 is restrained because a horizontal truss alone provides no vertical stiffness.

## Inspect the model

```matlab
opsMat.vis.plotModel();
```

For the interactive Polyscope backend, use:

```matlab
opsMat.vis.polyscope.plotModel();
```

The regular [`plotModel`][plotter.OpenSeesMatlabVis.plotModel] plot is the simplest verification path. The Polyscope [`plotModel`][plotter.OpenSeesMatlabVisPolyscope.plotModel] viewer is useful when you want an interactive GUI with visibility, display, slicing, and other viewer controls.

## Apply the load

```matlab
ops.timeSeries('Linear', 1);
ops.pattern('Plain', 1, 1);
ops.load(2, P, 0.0);
```

## Configure and run a static analysis

```matlab
ops.system('BandSPD');
ops.numberer('RCM');
ops.constraints('Plain');
ops.integrator('LoadControl', 1.0);
ops.algorithm('Linear');
ops.analysis('Static');

ok = ops.analyze(1);
assert(ok == 0, 'OpenSees analysis did not converge.');
```

OpenSees returns `0` when the requested analysis completes successfully. Always check the return code in scripts that will run unattended.

## Read and verify the result

```matlab
ux = ops.nodeDisp(2, 1);
uxExpected = P * L / (A * E);

fprintf('OpenSees displacement: %.6e m\n', ux);
fprintf('Analytical value:      %.6e m\n', uxExpected);
fprintf('Relative error:        %.3e\n', abs(ux - uxExpected) / uxExpected);
```

[`nodeDisp`][ops.OpenSeesMatlabCmds.nodeDisp] returns a MATLAB scalar here. Larger workflows can store values in arrays, tables, structs, or files using normal MATLAB tools.

## Clean up

```matlab
ops.wipe();
```

This clears the OpenSees domain. It is good practice at both the beginning and end of self-contained scripts.

## Complete script

```matlab
opsMat = OpenSeesMatlab();
ops = opsMat.opensees;
ops.wipe();

ops.model('basic', '-ndm', 2, '-ndf', 2);
L = 1.0; A = 2.0e-3; E = 200.0e9; P = 100.0e3;

ops.node(1, 0.0, 0.0);
ops.node(2, L,   0.0);
ops.fix(1, 1, 1);
ops.fix(2, 0, 1);
ops.uniaxialMaterial('Elastic', 1, E);
ops.element('Truss', 1, 1, 2, A, 1);

ops.timeSeries('Linear', 1);
ops.pattern('Plain', 1, 1);
ops.load(2, P, 0.0);

ops.system('BandSPD');
ops.numberer('RCM');
ops.constraints('Plain');
ops.integrator('LoadControl', 1.0);
ops.algorithm('Linear');
ops.analysis('Static');

ok = ops.analyze(1);
assert(ok == 0, 'OpenSees analysis did not converge.');

ux = ops.nodeDisp(2, 1);
uxExpected = P * L / (A * E);
fprintf('ux = %.6e m; expected = %.6e m\n', ux, uxExpected);

opsMat.vis.plotModel();
ops.wipe();
```

## Next steps

- Learn MATLAB argument conventions in the [OpenSees command interface](opensees.md).
- Use an ODB for time histories and response visualization in [Pre/post-processing and visualization](post.md).
- Browse the [examples](../examples/index.md) for nonlinear, dynamic, structural, and geotechnical models.
