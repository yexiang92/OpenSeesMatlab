# OpenSeesMatlab at a Glance

This page explains how OpenSeesMatlab is organized and where each part fits. If you already know OpenSees or OpenSeesPy, the central idea is simple: **OpenSeesMatlab preserves the OpenSees modelling workflow and adds MATLAB-oriented tools around it.**

## One object, several modules

Start every workflow by creating one top-level [`OpenSeesMatlab`][OpenSeesMatlab] object:

```matlab
opsMat = OpenSeesMatlab();
ops = opsMat.opensees;
```

`ops` is a convenient short name for command calls. The other modules remain available from `opsMat`:

| Module | Responsibility | Typical calls |
|---|---|---|
| [`.opensees`][ops.OpenSeesMatlabCmds] | Build and query the OpenSees domain | `model`, `node`, `element`, `analyze`, `nodeDisp` |
| [`.pre`][pre.OpenSeesMatlabPre] | Prepare data before analysis | units, fiber sections, meshes, mass and load helpers |
| [`.anlys`][analysis.OpenSeesMatlabAnalysis] | Coordinate higher-level analyses | robust analysis stepping and reusable analysis workflows |
| [`.post`][post.OpenSeesMatlabPost] | Collect and organize model/results data | `getModelData`, `createODB`, `getNodalResponse` |
| [`.vis`][plotter.OpenSeesMatlabVis] | Plot with MATLAB graphics | `plotModel`, `plotEigen`, `plotDeformation` |
| [`.vis.polyscope`][plotter.OpenSeesMatlabVisPolyscope] | Explore models/results in an interactive GUI | `plotModel`, `plotEigen`, response viewers |
| [`.utils`][utils.OpenSeesMatlabTool] | General utilities | example and toolbox helper functions |

All modules refer to the same underlying OpenSees domain. For example, nodes created with `ops.node` are immediately available to `opsMat.post.getModelData()` and `opsMat.vis.plotModel()`.

## What stays the same as OpenSees

The analysis concepts and command sequence remain those of OpenSees:

```text
wipe → model → nodes/constraints → materials/elements
     → time series/patterns → analysis configuration → analyze
```

Command arguments generally follow OpenSees/OpenSeesPy ordering. Strings identify command types and flags; numeric values remain numeric MATLAB arguments.

```matlab
ops.uniaxialMaterial('Elastic', 1, 200.0e9);
ops.element('Truss', 1, 1, 2, 2.0e-3, 1);
ops.integrator('LoadControl', 0.1);
```

Use the official OpenSees documentation for the engineering meaning and valid arguments of individual commands. Use the [OpenSees command interface](opensees.md) page for MATLAB calling conventions and supported argument forms.

## What OpenSeesMatlab adds

### MATLAB data access

Commands that return values produce MATLAB data, so results can be inspected, transformed, plotted, or passed to optimization and signal-processing workflows without parsing a Tcl file.

```matlab
ux = ops.nodeDisp(2, 1);
lambda = ops.getLoadFactor(1);
```

### Structured output databases

An OpenSeesMatlab ODB records model and response data in HDF5 for later retrieval and visualization. It is useful when you need many time steps, multiple response types, or consistent data structures across plotting/export functions.

### Two visualization styles

- `opsMat.vis` uses MATLAB graphics and works well with figures, axes, Live Scripts, and publication workflows.
- `opsMat.vis.polyscope` opens an interactive Polyscope GUI for model, eigenmode, nodal, frame, shell, and continuum exploration.

These are alternative front ends over the same model/result data; Polyscope is a backend name, not a replacement for the whole `.vis` module.

### Higher-level helpers

Preprocessing and analysis utilities reduce repetitive MATLAB code, but they do not change the underlying OpenSees model. You can adopt them incrementally and continue to use direct OpenSees commands whenever that is clearer or faster.

## Choose the simplest workflow that fits

### Direct queries

Use query commands when you need a small number of values or want to make decisions inside an analysis loop:

```matlab
ops.analyze(1);
ux = ops.nodeDisp(2, 1);
```

### Standard OpenSees recorders

Use `ops.recorder(...)` when compatibility with established OpenSees workflows and low recording overhead matter most.

### OpenSeesMatlab ODB

Use [`opsMat.post.createODB(...)`][post.OpenSeesMatlabPost.createODB] when you want structured response retrieval, GUI exploration, or PVD export. Avoid retrieving ODB responses before recording is complete because retrieval closes the corresponding recording workflow.

## Object lifetime and model state

OpenSees commands operate on persistent domain state held by the MEX interface. Keep these rules in mind:

- Call `ops.wipe()` before starting an unrelated model.
- Keep the `opsMat` object alive while its modules are in use.
- Do not assume that clearing a MATLAB plotting variable clears the OpenSees domain.
- Use distinct ODB tags for distinct analysis cases.
- Keep units consistent; OpenSees and OpenSeesMatlab do not impose a unit system on the model.

## Where to go next

1. [Install and verify OpenSeesMatlab](installation.md).
2. Complete [Your first analysis](quickstart.md).
3. Read the [command interface guide](opensees.md) when translating an OpenSees model.
4. Read [Pre/post-processing and visualization](post.md) when you need ODBs or response viewers.
5. Move to the [examples](../examples/index.md) for larger structural, earthquake, and geotechnical workflows.
