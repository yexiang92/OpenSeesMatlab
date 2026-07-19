# API Reference Overview

This section provides comprehensive API documentation for all classes and functions in OpenSeesMatlab. The documentation is auto-generated from MATLAB docstrings using `mkdocstrings`.

---

## Architecture Overview

OpenSeesMatlab is organized into six main namespaces, each exposed as a property of the root `OpenSeesMatlab` class:

```matlab
opsMAT = OpenSeesMatlab();
ops    = opsMAT.opensees;   % Native OpenSees commands
pre    = opsMAT.pre;        % Preprocessing utilities
post   = opsMAT.post;       % Post-processing & ODB
vis    = opsMAT.vis;        % Visualization
anlys  = opsMAT.anlys;      % Higher-level analysis workflows
utils  = opsMAT.utils;      % General utilities
```

!!! tip "Performance Tip"

    If you want **maximum runtime efficiency** — identical to using OpenSees directly —
    use only the **`opensees`** module (`opsMAT.opensees`).

    Use standard OpenSees `recorder` commands to write result files, or use query
    commands such as `nodeDisp`, `nodeReaction`, `eleForce`, `eleResponse`, etc.
    to return data directly into MATLAB variables during or after analysis.

    The additional pre/post-processing layers (`pre`, `post`, `vis`) provide
    convenience but add overhead. For large models or long transient analyses,
    sticking to the core `opensees` command interface gives the best performance.

---

## API Modules

### [OpenSeesMatlab](OpenSeesMatlab.md)

The root interface class. Instantiates the MEX bridge to OpenSees and provides access to all subsystems.

| Property | Type | Description |
|----------|------|-------------|
| `opensees` | `OpenSeesMatlabCmds` | Native OpenSees Tcl command interface |
| `pre` | `OpenSeesMatlabPre` | Preprocessing helpers |
| `post` | `OpenSeesMatlabPost` | Post-processing and ODB management |
| `vis` | `OpenSeesMatlabVis` | Visualization functions |
| `anlys` | `OpenSeesMatlabAnalysis` | Higher-level analysis workflows |
| `utils` | `OpenSeesMatlabTool` | General utility functions |

---

### [OpenSees Commands (OpenSeesMatlabCmds)](OpenSeesMatlabCmds.md)

Native OpenSees command interface. All standard OpenSees Tcl commands are available as MATLAB methods.

**Key features:**
- Both `char` and `string` inputs supported (char recommended)
- Most commands accept scalar arguments; use `num2cell` + `{:}` expansion for arrays
- Selected commands (`node`, `element`, `fix`, `load`, `mass`, etc.) accept numeric arrays directly since v3.8.0.1
- Commands with return values return MATLAB data; others return `[]`

**Common commands:**
- Model building: `wipe`, `model`, `node`, `element`, `fix`, `mass`
- Materials: `uniaxialMaterial`, `nDMaterial`, `section`, `fiber`, `patch`, `layer`
- Analysis: `constraints`, `numberer`, `system`, `test`, `algorithm`, `integrator`, `analysis`, `analyze`
- Results: `nodeDisp`, `nodeReaction`, `eleForce`, `eleResponse`, `sectionForce`

---

### [Preprocessing (OpenSeesMatlabPre)](OpenSeesMatlabPre.md)

Helper functions for model preprocessing.

| Category | Functions |
|----------|-----------|
| **Unit System** | `unitSystem`, `setUnitSystem` |
| **Fiber Sections** | `setSectionGeometryRecorder`, `plotSection`, `fiberSectionMesh` |
| **Loads** | `createGravityLoad`, `beamGlobalUniformLoad`, `beamGlobalPointLoad`, `surfaceGlobalPressureLoad` |
| **System Matrices** | `getMCK`, `getNodeMass` |
| **GMSH Import** | `Gmsh2OPS` |

**Sub-classes:**
- `UnitSystem` — Unit conversion management
- `Gmsh2OPS` — GMSH mesh file reader and OpenSees command generator
- `FiberSectionMesh` — Programmatic fiber section mesh generation

---

### [Post-processing (OpenSeesMatlabPost)](OpenSeesMatlabPost.md)

Data recording, retrieval, and export.

| Category | Functions |
|----------|-----------|
| **Model Data** | `saveModelData`, `getModelData`, `getModelDataFromODB` |
| **Eigen Data** | `saveEigenData`, `getEigenData` |
| **ODB Management** | `createODB`, `getODBData`, `close` |
| **Response Retrieval** | `getNodalResponse`, `getElementResponse` |
| **Export** | `writeResponsePVD` |

**Response data layouts:**
- **Nodal responses** (`getNodalResponse`): Layout C with fields `disp.ux/uy/uz/rx/ry/rz`, `vel`, `accel`, `reaction`
- **Element responses** (`getElementResponse`): Layout C with component fields (e.g., `sectionForces.Mz/My/N/Vy/Vz/T`)
- **Custom response fields**: response plotters and GUIs accept numeric fields, `.data` plus `.dofs`, or Layout-C numeric subfields; custom field names become `respType` entries and `.dofs` or subfield names become selectable components.

**Data structures:**
- Scalar struct: single stage, fixed topology
- Struct array: multi-stage, each element covers a contiguous time block

---

### [Visualization (OpenSeesMatlabVis)](OpenSeesMatlabVis.md)

High-level plotting functions for models, eigen modes, and analysis results.

| Function | Purpose |
|----------|---------|
| `plotModel` | Visualize model geometry (nodes, elements, constraints, loads) |
| `plotEigen` | Visualize eigen mode shapes |
| `plotDeformation` | Plot deformed shape from nodal response |
| `plotNodalResponse` | Plot nodal response scalar fields |
| `plotFrameResponse` | Plot frame element response diagrams (forces, deformations) |
| `plotShellResponse` | Plot shell element response fields |
| `plotContinuumResponse` | Plot plane/solid element response fields |

**Default options functions:**
- `defaultPlotModelOptions`
- `defaultPlotEigenOptions`
- `defaultPlotNodalResponseOptions`
- `defaultPlotFrameResponseOptions`
- `defaultPlotShellResponseOptions`
- `defaultPlotContinuumResponseOptions`

---

### [Interactive Polyscope Visualization (OpenSeesMatlabVisPolyscope)](OpenSeesMatlabVisPolyscope.md)

Recommended interactive backend for static exploration and animation.

| Function | Purpose |
|----------|---------|
| `plotModel` | Inspect model geometry and display options |
| `plotEigen` | Select and animate eigen mode shapes |
| `plotNodalResponse` | Explore and animate nodal response fields and histories |
| `plotFrameResponse` | Explore and animate frame response diagrams |
| `plotShellResponse` | Explore shell response fields |
| `plotContinuumResponse` | Explore plane and solid response fields |
| `plotUnstruResponse` | General low-level unstructured-response viewer |

---

### [Analysis (OpenSeesMatlabAnalysis)](OpenSeesMatlabAnalysis.md)

Advanced analysis utilities.

| Function / Class | Purpose |
|------------------|---------|
| `smartAnalyze` | Automatic step-size control with convergence diagnostics |
| `SmartAnalyze` | Configurable smart analysis controller |
| `MomentCurvature` | Section moment-curvature analysis with cyclic loading |

---

### [Utilities (OpenSeesMatlabTool)](OpenSeesMatlabTool.md)

General helper functions.

| Function | Purpose |
|----------|---------|
| `loadExamples` | Load and run built-in example models |

---

## Data Flow Diagram

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│   OpenSees C++  │────▶│   HDF5 ODB      │────▶│   MATLAB        │
│   (Analysis)    │     │   (Recorder)    │     │   (Post/Vis)    │
└─────────────────┘     └─────────────────┘     └─────────────────┘
         │                                            │
         │         ┌─────────────────┐               │
         └────────▶│   PVD/VTU       │◀──────────────┘
                   │   (ParaView)    │   writeResponsePVD()
                   └─────────────────┘
```

---

## Quick Links

- [OpenSeesMatlab](OpenSeesMatlab.md) — Root interface
- [OpenSeesMatlabCmds](OpenSeesMatlabCmds.md) — Native commands
- [OpenSeesMatlabPre](OpenSeesMatlabPre.md) — Preprocessing
- [OpenSeesMatlabPost](OpenSeesMatlabPost.md) — Post-processing
- [OpenSeesMatlabVis](OpenSeesMatlabVis.md) — Visualization
- [OpenSeesMatlabVisPolyscope](OpenSeesMatlabVisPolyscope.md) — Interactive Polyscope visualization
- [OpenSeesMatlabAnalysis](OpenSeesMatlabAnalysis.md) — Analysis utilities
- [OpenSeesMatlabTool](OpenSeesMatlabTool.md) — Utilities
