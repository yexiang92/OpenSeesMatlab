# Getting Started with OpenSeesMatlab

This tutorial is for readers using OpenSeesMatlab for the first time. It begins with installation, follows the usual OpenSees modelling workflow, and then works through a complete two-node truss example. The last sections introduce response recording, plotting, and a practical way to organize larger models.

All values in the example use a consistent SI unit system. You can paste the code directly into a MATLAB script.

## Install and verify OpenSeesMatlab

OpenSeesMatlab currently supports Windows with MATLAB R2023a or later. Download a release from either location:

- [GitHub Releases](https://github.com/yexiang92/OpenSeesMatlab/releases)
- [Gitee Releases](https://gitee.com/yexiang-yan/opensees-interface-for-matlab/releases)

Extract the package to a directory where you have write permission. In MATLAB, change to that directory and run the installer:

```matlab
cd('D:\path\to\OpenSeesMatlab');
installOpenSeesMatlab;
```

Replace the example path with the directory you extracted. Restart MATLAB if the installer asks you to do so. In a new MATLAB session, verify the installation:

```matlab
opsMat = OpenSeesMatlab();
opsMat.version
which OpenSeesMatlab -all
```

If a version is returned and `which` points to the current installation, the toolbox is ready. If MATLAB lists more than one copy, remove older copies from the MATLAB path. Mixing files from different releases is a common cause of MEX loading errors.

The main features are available through the `opsMat` object:

| Object | Purpose |
| --- | --- |
| `opsMat.opensees` | OpenSees-compatible modelling and analysis commands |
| `opsMat.pre` | Preprocessing helpers |
| `opsMat.anlys` | Higher-level analysis helpers |
| `opsMat.post` | ODB creation, response retrieval, and export |
| `opsMat.vis` | MATLAB and interactive visualization |

Most scripts give the command interface a shorter name:

```matlab
opsMat = OpenSeesMatlab();
ops = opsMat.opensees;
```

After that, `ops.node(...)` calls the OpenSees `node` command.

## The usual OpenSees workflow

Most OpenSees models follow the same overall sequence, whether the model is a small truss, a building frame, or a soil domain:

```text
Clear the previous domain
    ↓
Declare the model dimensions and nodal degrees of freedom
    ↓
Create nodes, constraints, materials, sections, and elements
    ↓
Define time series, load patterns, and loads
    ↓
Choose constraint handling, numbering, equation solver,
convergence test, algorithm, and integrator
    ↓
Run a static or transient analysis
    ↓
Check the return code, then read, save, and plot the results
```

In command form, the outline looks like this:

```matlab
ops.wipe();
ops.model(...);

ops.node(...);
ops.fix(...);
ops.uniaxialMaterial(...);  % or nDMaterial
ops.section(...);           % only when required by the element
ops.element(...);

ops.timeSeries(...);
ops.pattern(...);
ops.load(...);              % or eleLoad, groundMotion, and so on

ops.constraints(...);
ops.numberer(...);
ops.system(...);
ops.test(...);              % normally needed for nonlinear analysis
ops.algorithm(...);
ops.integrator(...);
ops.analysis(...);

ok = ops.analyze(...);
```

The first half describes the physical model. The second half tells OpenSees how to solve it. A valid model still needs suitable analysis settings, but changing algorithms cannot repair incorrect connectivity, missing supports, or inconsistent material data.

In a static analysis, OpenSees “time” commonly represents a load factor or pseudo-time. In a transient analysis, it represents physical time. A `timeSeries` defines how a load varies, a `pattern` associates that series with a group of loads, and an `integrator` controls how the analysis advances.

After an analysis, commands such as `nodeDisp` and `eleResponse` query the current state. For a complete history over many steps, create an ODB before calling `analyze`.

## First example: an elastic truss in tension

The model is a horizontal bar 1 m long. Its left end is fixed and a 100 kN horizontal force is applied at the right end. The cross-sectional area is 0.002 m² and the elastic modulus is 200 GPa. The theoretical displacement is

\[
u=\frac{PL}{AE}=2.5\times10^{-4}\ \mathrm{m}.
\]

### Clear the previous model

```matlab
ops.wipe();
```

Starting every self-contained script with `wipe` prevents nodes, materials, and loads from an earlier run from remaining in the OpenSees domain.

### Declare the model space

```matlab
ops.model('basic', '-ndm', 2, '-ndf', 2);
```

- `-ndm 2` selects a two-dimensional model.
- `-ndf 2` gives each node two degrees of freedom: X and Y translation.

A two-dimensional frame model normally uses three nodal degrees of freedom—`ux`, `uy`, and `rz`—and therefore uses `-ndf 3`. The degrees of freedom must be compatible with the chosen elements.

### Define parameters, nodes, and supports

```matlab
L = 1.0;       % length, m
A = 2.0e-3;    % area, m^2
E = 200.0e9;   % elastic modulus, Pa
P = 100.0e3;   % force, N

ops.node(1, 0.0, 0.0);
ops.node(2, L,   0.0);

ops.fix(1, 1, 1);
ops.fix(2, 0, 1);
```

The first argument to `node` is its integer tag; the remaining arguments are coordinates. Tags do not have to be consecutive, but they must be unique.

For `fix`, `1` means restrained and `0` means free. Node 1 is restrained in both directions. Node 2 is free in X and restrained in Y. The Y restraint is necessary because a single horizontal truss has no vertical stiffness; leaving that degree of freedom free would produce a singular stiffness matrix.

### Define the material and element

```matlab
ops.uniaxialMaterial('Elastic', 1, E);
ops.element('Truss', 1, 1, 2, A, 1);
```

The first command creates an elastic uniaxial material with tag 1. The second creates truss element 1 between nodes 1 and 2. Its final argument refers to material tag 1.

OpenSees connects nodes, materials, sections, and elements through integer tags. In a larger model, define tag ranges in one place rather than scattering unexplained numbers throughout the script.

### Inspect the model

```matlab
opsMat.vis.plotModel();
```

Plotting is not required for the solution, but it is a quick way to find incorrect coordinates, connectivity, and restraints before running the analysis.

For an interactive viewer with display controls, use:

```matlab
opsMat.vis.polyscope.plotModel();
```

### Apply the load

```matlab
ops.timeSeries('Linear', 1);
ops.pattern('Plain', 1, 1);
ops.load(2, P, 0.0);
```

These commands create a linear time series, associate it with a plain load pattern, and apply X and Y forces to node 2. The number of components passed to `load` must match the number of nodal degrees of freedom.

### Configure a static analysis

```matlab
ops.system('BandSPD');
ops.numberer('RCM');
ops.constraints('Plain');
ops.integrator('LoadControl', 1.0);
ops.algorithm('Linear');
ops.analysis('Static');
```

These commands select the equation solver, degree-of-freedom numbering, constraint handling, load increment, solution algorithm, and analysis driver.

A nonlinear model also needs a convergence test and a nonlinear algorithm, for example:

```matlab
ops.test('NormDispIncr', 1.0e-8, 30);
ops.algorithm('Newton');
```

If an analysis fails, first check supports, connectivity, units, and material parameters. Change the step size or solution algorithm one item at a time so the cause remains visible.

### Solve and check the return code

```matlab
ok = ops.analyze(1);
assert(ok == 0, 'OpenSees analysis failed with return code %d.', ok);
```

OpenSees returns `0` when the requested analysis succeeds and a nonzero value when it fails. Always check this value in scripts that run unattended.

### Read and verify the displacement

```matlab
ux = ops.nodeDisp(2, 1);
uxExpected = P * L / (A * E);

fprintf('OpenSees displacement: %.6e m\n', ux);
fprintf('Analytical value:      %.6e m\n', uxExpected);
fprintf('Relative error:        %.3e\n', abs(ux - uxExpected) / uxExpected);
```

`nodeDisp(2, 1)` reads degree of freedom 1 at node 2, which is the X displacement in this model.

## Complete script

```matlab
opsMat = OpenSeesMatlab();
ops = opsMat.opensees;
ops.wipe();

% Model
ops.model('basic', '-ndm', 2, '-ndf', 2);
L = 1.0;
A = 2.0e-3;
E = 200.0e9;
P = 100.0e3;

ops.node(1, 0.0, 0.0);
ops.node(2, L,   0.0);
ops.fix(1, 1, 1);
ops.fix(2, 0, 1);
ops.uniaxialMaterial('Elastic', 1, E);
ops.element('Truss', 1, 1, 2, A, 1);

% Load
ops.timeSeries('Linear', 1);
ops.pattern('Plain', 1, 1);
ops.load(2, P, 0.0);

% Analysis
ops.system('BandSPD');
ops.numberer('RCM');
ops.constraints('Plain');
ops.integrator('LoadControl', 1.0);
ops.algorithm('Linear');
ops.analysis('Static');

ok = ops.analyze(1);
assert(ok == 0, 'OpenSees analysis failed with return code %d.', ok);

% Results
ux = ops.nodeDisp(2, 1);
uxExpected = P * L / (A * E);
fprintf('ux = %.6e m; expected = %.6e m\n', ux, uxExpected);

opsMat.vis.plotModel();
ops.wipe();
```

Run the complete script once before changing it. When the expected result is reproduced, run it section by section and experiment with the parameters.

## Record a multi-step response

`nodeDisp` is convenient for the current state. To retain every step of a static or transient analysis, create an ODB before the analysis begins. The ODB records subsequent calls to `analyze` automatically.

The following setup applies the load in ten increments:

```matlab
% Build the model and apply its load as above.

ops.system('BandSPD');
ops.numberer('RCM');
ops.constraints('Plain');
ops.integrator('LoadControl', 0.1);
ops.algorithm('Linear');
ops.analysis('Static');

odbTag = "truss_demo";
ODB = opsMat.post.createODB(odbTag);

ok = ops.analyze(10);
assert(ok == 0, 'The analysis did not complete.');

ODB.close();
ops.wipe();
```

By default, the data are stored in:

```text
.openseesmatlab.output/Responses-truss_demo.odb/output.h5
```

Read and plot the nodal history after recording has finished:

```matlab
nodeResp = opsMat.post.getNodalResponse("truss_demo");

idx = nodeResp.nodeTags == 2;
uxHistory = nodeResp.disp.ux(:, idx);

figure;
plot(nodeResp.time, uxHistory, 'LineWidth', 1.5);
xlabel('Load factor');
ylabel('Node 2 X displacement / m');
grid on;
```

Do not call `getNodalResponse` while the same ODB is still being recorded. Reading the response closes recording for that ODB.

## Select response data by label

ODB readers return ordinary MATLAB structs, which remain the input expected by the existing visualization functions. For selection by node, element, section, or time label, create a `ResponseDataset` view:

```matlab
ds = opsMat.post.toResponseDataset(nodeResp);

ds.names()           % list available variable paths
ux = ds.get("disp.ux");

node2 = ux.sel("node", 2);       % select by coordinate label
first10 = ux.isel("time", 1:10); % select by MATLAB array position
```

Common response paths also support dot access, so `ds.disp.ux` returns the X displacement array. `sel` uses coordinate labels, whereas `isel` uses MATLAB's one-based array indices.

The conversion does not alter `nodeResp`. Continue to pass the original response struct to the plotting functions:

```matlab
opsMat.vis.plotNodalResponse( ...
    nodeResp, stepIdx="absMax", ...
    respType="disp", respComponent="ux");

opsMat.vis.polyscope.plotNodalResponse(nodeResp);
```

## Organize a larger model

Once a model grows beyond a short example, separating responsibilities makes it easier to inspect and reuse:

```text
my_model/
├─ main.m               % parameters, cases, and execution order
├─ buildModel.m         % nodes, supports, materials, sections, elements
├─ applyLoads.m         % time series, patterns, and loads
├─ configureAnalysis.m  % solver, algorithm, test, and integrator
└─ plotResults.m        % response processing and figures
```

State the base units near the beginning of `main.m`, and include units in parameter comments. OpenSees does not enforce a unit system. A model that mixes millimetres with pascals may still run and return plausible-looking but incorrect values.

## Common problems

### Singular stiffness matrix

Check the following before changing the equation solver:

- missing supports or unconstrained rigid-body motion;
- elements connected to the wrong node tags;
- nodal degrees of freedom incompatible with the element type;
- a free degree of freedom to which no element contributes stiffness;
- zero or incorrectly scaled material and section properties.

In the tutorial model, leaving node 2 free in the Y direction produces this problem.

### A nonzero return from `analyze`

Keep the return code and identify the last successful step. A smaller step may help a nonlinear analysis, but it is not a substitute for checking the model. Change one analysis setting at a time.

### MATLAB cannot find the toolbox or MEX file

```matlab
which OpenSeesMatlab -all
which OpenSeesMex -all
```

Make sure MATLAB is not resolving files from different releases. Restart MATLAB after reinstalling or changing the path.

### The Polyscope window does not open

First verify the model with the regular MATLAB plot:

```matlab
opsMat.vis.plotModel();
```

Core modelling and analysis do not depend on Polyscope, so an interactive-viewer problem does not prevent the model from being solved or its responses from being read.

### Results have the wrong order of magnitude

OpenSees has no built-in unit system. N-m-Pa and N-mm-MPa are both valid when used consistently. Frequent mistakes include defining geometry in millimetres while using an elastic modulus in pascals, and confusing mass with weight.

## Where to go next

- Read the [OpenSees command interface](opensees.md) for MATLAB argument conventions and command usage.
- Continue with [Pre/post-processing and visualization](post.md) for ODB data, element responses, export, and GUI tools.
- See [Extensions](extensions.md) for adaptive analysis, solvers, and other additions.
- Browse the [examples](../examples/index.md) for structural, geotechnical, transient, and parallel models.

When learning a new element, start from the closest working example. Keep its material, degree-of-freedom, and analysis settings unchanged at first; modify geometry and parameters before introducing additional nonlinear behaviour or advanced post-processing.
