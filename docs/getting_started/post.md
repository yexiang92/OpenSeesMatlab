# Pre, Post-Processing and Visualization

OpenSeesMatlab provides a comprehensive set of pre- and post-processing tools that work seamlessly with OpenSees. This guide covers the essential workflows for model visualization, response retrieval, and result export.

This is a topic guide rather than a first tutorial. New users should begin with [OpenSeesMatlab at a glance](overview.md) and [Your first analysis](quickstart.md). For command syntax and model construction, see the [OpenSees command interface](opensees.md).

---

## Table of Contents

1. [Initialization](#initialization)
2. [Model Visualization](#model-visualization)
3. [Eigenvalue Analysis Visualization](#eigenvalue-analysis-visualization)
4. [Response Data Recording (ODB)](#response-data-recording-odb)
5. [Retrieving Responses](#retrieving-responses)
6. [Visualization of Analysis Results](#visualization-of-analysis-results)
7. [Interactive GUI Plotters](#interactive-gui-plotters)
8. [Export to ParaView (PVD)](#export-to-paraview-pvd)
9. [Preprocessing Utilities](#preprocessing-utilities)

---

## Initialization

All pre/post-processing features are accessed through the [`OpenSeesMatlab`][OpenSeesMatlab] interface. Create an instance and obtain the OpenSees command handle:

```matlab
opsMAT = OpenSeesMatlab();
ops = opsMAT.opensees;
```

The `opsMAT` object provides the following main namespaces:

| Namespace | Purpose |
|-----------|---------|
| [`opsMAT.opensees`][ops.OpenSeesMatlabCmds] | OpenSees-compatible modelling and analysis commands |
| [`opsMAT.pre`][pre.OpenSeesMatlabPre] | Preprocessing helpers (sections, loads, units, etc.) |
| [`opsMAT.anlys`][analysis.OpenSeesMatlabAnalysis] | Higher-level analysis workflows and helpers |
| [`opsMAT.post`][post.OpenSeesMatlabPost] | Post-processing (ODB creation, saved model/eigen data, response retrieval) |
| [`opsMAT.vis`][plotter.OpenSeesMatlabVis] | Visualization (model, eigen modes, deformation, response plots, GUIs) |

---

## Model Visualization

At any point during model creation, visualize the current geometry:

```matlab
% Your model code

% Basic model plot
opsMAT.vis.plotModel();

% Customized plot
opts = opsMAT.vis.defaultPlotModelOptions;
opts.nodes.show = true;
opts.nodes.showLabels = true;
disp(opts.help);
opsMAT.vis.plotModel(opts=opts);

% Interactive Polyscope model window with in-window ImGui controls
opsMAT.vis.polyscope.plotModel();
```

---

## Eigenvalue Analysis Visualization

Save eigen data during analysis, then visualize mode shapes:

```matlab
% Save eigen analysis results
tag = 1;
opsMAT.post.saveEigenData(tag, 10, solver='-genBandArpack');

% Retrieve eigen data
eigenData = opsMAT.post.getEigenData(odbTag=tag);

% Plot first mode shape
opsMAT.vis.plotEigen(1, eigenData);

% Plot with colormap
opts = opsMAT.vis.defaultPlotEigenOptions;
opts.color.useColormap = true;
opsMAT.vis.plotEigen(3, eigenData, opts=opts);

% Interactive Polyscope eigen-mode window with in-window ImGui controls
opsMAT.vis.polyscope.plotEigen(1, eigenData);
```

---

## Response Data Recording (ODB)

OpenSeesMatlab uses an **ODB (Output Database)** system to record analysis results in HDF5 format.
For optimal performance, OpenSeesMatlab implements a custom `recorder` object in C++ internally.
Note that `odbTag` is important — it is used to distinguish between different analysis cases.

Create an [`ODB`][post.ODB] before analysis with [`createODB`][post.OpenSeesMatlabPost.createODB]:

```matlab
% Create ODB with optional beam interpolation
ODB = opsMAT.post.createODB("myODB");
```

Once created, all subsequent `ops.analyze()` calls automatically write data to the ODB:

```matlab
% Run analysis — data is recorded automatically
ops.analyze(npts, dt);

% Clean up
ops.wipe();

% If you only want to stop recording, use
ODB.close();
```

ODB files are stored in `.openseesmatlab.output/Responses-myODB.odb/output.h5`.

---

## Retrieving Responses

Once the analysis is complete and the ODB has saved the data properly, a series of functions can be used to retrieve the analysis results.
Typically, they return a nested struct (or a struct array if the model data changes).

!!! note

    Once these functions are called, the ODB corresponding to `odbTag` will stop recording. Therefore, it is recommended to read the results only after the analysis is complete.

### [Nodal Responses][post.OpenSeesMatlabPost.getNodalResponse]

```matlab
nodeResp = opsMAT.post.getNodalResponse("myODB");
nodeTags = nodeResp.nodeTags;

% Time-history of a specific node
idx = nodeTags == 18;
plot(nodeResp.time, nodeResp.disp.ux(:, idx));

% Available fields (Layout C):
%   nodeResp.disp.ux, .uy, .uz, .rx, .ry, .rz
%   nodeResp.vel, nodeResp.accel, nodeResp.reaction
```

### [Element Responses][post.OpenSeesMatlabPost.getElementResponse]

```matlab
% Frame element responses
frameResp = opsMAT.post.getElementResponse("myODB", eleType="Frame");
sectionForces = frameResp.sectionForces;   % Layout C: .Mz, .My, .N, .Vy, .Vz, .T
sectionDefos  = frameResp.sectionDeformations;

% Shell/Plane/Solid element responses
eleResp = opsMAT.post.getElementResponse("myODB", eleType="Shell");
```

---

## Visualization of Analysis Results

### [Nodal Response Visualization][plotter.OpenSeesMatlabVis.plotNodalResponse]

```matlab
nodeResp = opsMAT.post.getNodalResponse("myODB");

% Deformation at peak step
opsMAT.vis.plotDeformation(nodeResp, stepIdx="absMax", scaleFactor=1.0);

% Specific displacement component, or any other response component
opsMAT.vis.plotNodalResponse(nodeResp, stepIdx="absMax", respType="disp", respComponent="ux");

% Interactive Polyscope nodal-response window (with ImPlot history)
opsMAT.vis.polyscope.plotNodalResponse(nodeResp);
```

### [Frame Response Diagrams][plotter.OpenSeesMatlabVis.plotFrameResponse]

```matlab
frameResp = opsMAT.post.getElementResponse("myODB", eleType="Frame");

% Section force diagram
opsMAT.vis.plotFrameResponse(frameResp, stepIdx="absMax", ...
    respType="sectionForces", respComponent="MZ");

% Section deformation diagram
opsMAT.vis.plotFrameResponse(frameResp, stepIdx="absMax", ...
    respType="sectionDeformations", respComponent="MZ");

% Interactive frame response GUI
app = opsMAT.vis.plotFrameResponseGUI(frameResp);
```

### Shell Response Visualization

```matlab
shellResp = opsMAT.post.getElementResponse("myODB", eleType="Shell");

opsMAT.vis.plotShellResponse(shellResp);

% Interactive shell response GUI
app = opsMAT.vis.plotShellResponseGUI(shellResp);
```

### Plane/Solid Response Visualization

```matlab
% For continuum elements
planeResp = opsMAT.post.getElementResponse("myODB", eleType="Plane");

opsMAT.vis.plotContinuumResponse(planeResp, ...
    respType="StressAtGP", respComponent="sxx");

% Interactive continuum response GUI
app = opsMAT.vis.plotContinuumResponseGUI(planeResp);
```

### Custom Response Fields and Components

The response plotters and response GUIs can also read user-defined fields
directly from the response data struct. The field name becomes the available
`respType`, and the component list is inferred from the data layout:

```matlab
% Nodal scalar field: component shown as "value" in the GUI
nodeResp.MyScalar = rand(nStep, nNode);

% Nodal vector field: components come from .dofs
nodeResp.MyVector.data = rand(nStep, nNode, nComp);
nodeResp.MyVector.dofs = {'c1','c2','c3'};

% Nodal Layout-C field: components come from numeric subfield names
nodeResp.MyLayoutC.c1 = rand(nStep, nNode);
nodeResp.MyLayoutC.c2 = rand(nStep, nNode);

opsMAT.vis.plotNodalResponse(nodeResp, respType="MyVector", respComponent="c2");
opsMAT.vis.polyscope.plotNodalResponse(nodeResp);
```

Frame response custom fields follow the same idea, with `responseLocation`
used to state whether values are element-level or section/sample-point values:

```matlab
% Element scalar diagram
frameResp.MyScalar = rand(nStep, nEle);
opsMAT.vis.plotFrameResponse(frameResp, ...
    respType="MyScalar", respComponent="value", responseLocation="element");

% Vector field with named components
frameResp.MyVector.data = rand(nStep, nEle, nComp);
frameResp.MyVector.dofs = {'c1','c2','c3'};

% Section-style Layout-C field
frameResp.MySection.c1 = rand(nStep, nEle, nSec);
opsMAT.vis.plotFrameResponse(frameResp, ...
    respType="MySection", respComponent="c1", responseLocation="section");
```

For shell, plane, and solid element responses, custom fields can be stored as
element, Gauss-point, or node data. Names containing `AtNode` are treated as
node fields by default; names containing `AtGP` are treated as Gauss-point
fields; other custom fields are treated as element fields unless
`responseLocation` is set explicitly.

```matlab
% Element/Gauss-point vector field
eleResp.MyStress.data = rand(nStep, nEle, nGP, nComp);
eleResp.MyStress.dofs = {'s11','s22','s12'};
opsMAT.vis.plotContinuumResponse(eleResp, ...
    respType="MyStress", respComponent="s11", responseLocation="gp");

% Node-based Layout-C field
eleResp.MyFieldAtNode.c1 = rand(nStep, nNode);
opsMAT.vis.plotContinuumResponse(eleResp, ...
    respType="MyFieldAtNode", respComponent="c1");
```

For all response GUIs, custom fields and components are populated from the
first response struct entry, for example `nodeResp(1)`, `frameResp(1)`, or
`eleResp(1)`. If a multi-stage response uses struct arrays, put the custom
field names and component metadata in the first entry as well.

### Step Index Options

All `stepIdx` parameters accept:

| Value | Meaning |
|-------|---------|
| Integer (0-based) | Specific step index |
| `"absMax"` / `"absMin"` | Maximum / minimum absolute value step |
| `"Max"` / `"Min"` | Maximum / minimum signed value step |

Selectors are case-insensitive in the plotters, but the examples use the canonical mixed-case spelling.

---

## Interactive GUI Plotters

OpenSeesMatlab provides two GUI visualization families. They use the same model and response data but target different workflows.

| GUI family | Best suited to | Result display |
|---|---|---|
| MATLAB GUI (`opsMAT.vis.*GUI`) | Inspecting and configuring a publication-style MATLAB plot at one selected step | Static MATLAB figure; one step is displayed at a time |
| Polyscope (`opsMAT.vis.polyscope.*`) | Interactive model inspection, static result exploration, mode-shape animation, and response-history animation | Interactive 3-D viewer with in-window controls |

!!! tip "Recommended GUI"

    Use the **Polyscope GUI** for new interactive visualization workflows. It
    supports both static display and animation and provides a consistent viewer
    for models, eigenmodes, nodal responses, frame responses, shells, planes,
    and solids. Use the MATLAB GUI when you specifically need a MATLAB figure or
    want to tune a single-step static plot.

### MATLAB GUI: Single-Step Static Plots

The MATLAB GUI functions wrap the regular `.vis` plotters. A response GUI can select a step or an envelope step such as `absMax`, but the axes show one static state at a time. Each function returns an `app` struct with the figure, axes, controls, and callbacks such as `app.getOptions()`, `app.refresh()`, and `app.reset()`.

| Function | Input | Use |
|---|---|---|
| [`opsMAT.vis.plotModelGUI()`][plotter.OpenSeesMatlabVis.plotModelGUI] | Current OpenSees model | Inspect model geometry, labels, supports, loads, and display styles |
| [`opsMAT.vis.plotEigenGUI(eigenData)`][plotter.OpenSeesMatlabVis.plotEigenGUI] | Eigen data | Select a mode and configure a static mode-shape plot |
| [`opsMAT.vis.plotNodalResponseGUI(nodeResp)`][plotter.OpenSeesMatlabVis.plotNodalResponseGUI] | Nodal response | Select a step, response field/component, deformation, vectors, and colors |
| [`opsMAT.vis.plotFrameResponseGUI(frameResp)`][plotter.OpenSeesMatlabVis.plotFrameResponseGUI] | Frame response | Select a step and inspect section, basic, or local frame diagrams |
| [`opsMAT.vis.plotShellResponseGUI(shellResp)`][plotter.OpenSeesMatlabVis.plotShellResponseGUI] | Shell response | Inspect shell force, deformation, stress, or strain fields |
| [`opsMAT.vis.plotContinuumResponseGUI(respData)`][plotter.OpenSeesMatlabVis.plotContinuumResponseGUI] | Plane or solid response | Inspect continuum stress, strain, and related scalar fields |

```matlab
modelApp = opsMAT.vis.plotModelGUI();
eigenApp = opsMAT.vis.plotEigenGUI(eigenData);
nodalApp = opsMAT.vis.plotNodalResponseGUI(nodeResp);
frameApp = opsMAT.vis.plotFrameResponseGUI(frameResp);
shellApp = opsMAT.vis.plotShellResponseGUI(shellResp);
solidApp = opsMAT.vis.plotContinuumResponseGUI(solidResp);
```

Common MATLAB GUI controls include step and view selectors, colormap selection, axes visibility, plot-specific color editors, and option help. Some control panels are scrollable; use the mouse wheel or panel scrollbar to reach controls below the visible area.

### Polyscope GUI: Static and Animated Visualization

The Polyscope functions open a dedicated interactive viewer with ImGui controls. Response viewers can browse individual steps and animate the response history; the eigen viewer can animate mode shapes. Viewer options include visibility and style controls, deformation scale, colormaps and scalar ranges, camera views, axes overlays, SSAA, and slice planes where applicable.
See [`OpenSeesMatlabVisPolyscope`][plotter.OpenSeesMatlabVisPolyscope] for more details.

[:fontawesome-brands-github: Polyscope Github](https://github.com/nmwsharp/polyscope)

[:fontawesome-brands-readme: Polyscope Document](https://polyscope.run/py/)

| Function | Input | Use |
|---|---|---|
| [`opsMAT.vis.polyscope.plotModel()`][plotter.OpenSeesMatlabVisPolyscope.plotModel] | Current OpenSees model | Interactive model geometry and display inspection |
| [`opsMAT.vis.polyscope.plotEigen()`][plotter.OpenSeesMatlabVisPolyscope.plotEigen] | Current model | Collect and display the first mode |
| [`opsMAT.vis.polyscope.plotEigen(eigenData)`][plotter.OpenSeesMatlabVisPolyscope.plotEigen] | Eigen data | Select, inspect, and animate mode shapes |
| [`opsMAT.vis.polyscope.plotNodalResponse(nodeResp)`][plotter.OpenSeesMatlabVisPolyscope.plotNodalResponse] | Nodal response | Display and animate nodal fields, deformation, vectors, and histories |
| [`opsMAT.vis.polyscope.plotFrameResponse(frameResp)`][plotter.OpenSeesMatlabVisPolyscope.plotFrameResponse] | Frame response | Display and animate frame response diagrams |
| [`opsMAT.vis.polyscope.plotShellResponse(shellResp)`][plotter.OpenSeesMatlabVisPolyscope.plotShellResponse] | Shell response | Display and animate shell response fields |
| [`opsMAT.vis.polyscope.plotContinuumResponse(respData)`][plotter.OpenSeesMatlabVisPolyscope.plotContinuumResponse] | Plane or solid response | Display and animate continuum response fields |

`plotFrameResp` is retained as an alias of `plotFrameResponse`; use the full `plotFrameResponse` name in new scripts.

```matlab
% Geometry and modes
opsMAT.vis.polyscope.plotModel();
opsMAT.vis.polyscope.plotEigen(eigenData);

% Response histories
opsMAT.vis.polyscope.plotNodalResponse(nodeResp);
opsMAT.vis.polyscope.plotFrameResponse(frameResp);
opsMAT.vis.polyscope.plotShellResponse(shellResp);
opsMAT.vis.polyscope.plotContinuumResponse(solidResp);
```

### Response Data Requirements

Response GUI functions read model information using the ODB tag stored in the response struct. Shell and continuum viewers also retrieve nodal displacement (`respType="disp"`) from the same ODB so that deformed geometry and interpolated response fields can be displayed. Create and complete the ODB recording before retrieving the response structs and opening a viewer.

---

## Export to ParaView (PVD)

For high-performance visualization of large models or animations, export ODB data to ParaView-compatible PVD/VTU files:

```matlab
% Export all recorded datasets
opsMAT.post.writeResponsePVD("myODB");
```

Output structure:

```
paraview_output/
├── nodal/
│   ├── vtu/
│   │   ├── model_nodal_000001.vtu
│   │   └── ...
│   └── model_nodal.pvd
├── shell/
│   └── ...
└── solid/
    └── ...
```

Open the `.pvd` file in **ParaView**. For deformation visualization, apply the **"Warp By Vector"** filter to the `disp` field.

---

## Preprocessing Utilities

OpenSeesMatlab provides a variety of preprocessing utilities for model setup, including fiber section generation, gravity loads, MCK matrices, unit system conversion, and GMSH model import.
Details can be found in the [Detailed Examples](../examples/post/index.md).

---

## Complete Example

```matlab
% 1. Setup
opsMAT = OpenSeesMatlab();
ops = opsMAT.opensees;

% 2. Build your model
ops.wipe();
ops.model("BasicBuilder", "-ndm", 3, "-ndf", 6);
% ... nodes, elements, materials, loads ...

% 3. Create ODB (before analysis)
odbTag = "myODB";
ODB = opsMAT.post.createODB(odbTag);

% 4. Run analysis
ops.analyze(100, 0.01);  % run analysis and record results
ODB.close();
ops.wipe();

% 5. Retrieve and visualize
nodeResp = opsMAT.post.getNodalResponse("myODB");
opsMAT.vis.plotDeformation(nodeResp, stepIdx="absMax");

```

---

## Performance Note

!!! tip "Maximum Runtime Efficiency"

    If your top priority is **analysis speed** (matching native OpenSees performance),
    use only the **`opensees`** module (`opsMAT.opensees`) and avoid the
    post-processing wrappers.

    - Use OpenSees `recorder` commands to write `.out` or `.h5` result files.
    - Use query commands (`nodeDisp`, `nodeReaction`, `eleForce`, `eleResponse`,
      `nodeVel`, `nodeAccel`, etc.) to pull data directly into MATLAB variables
      during or after the analysis loop.

    The `post` and `vis` layers add convenience (automatic tag mapping, unified
    data structures, plotting), but they introduce overhead. For large models or
    long transient analyses, the core `opensees` command interface is the fastest
    path.

## Further Reading

- [Detailed Examples](../examples/post/index.md)
- [API Reference](../api/index.md)
