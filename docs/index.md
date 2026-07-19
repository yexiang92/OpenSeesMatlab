# OpenSeesMatlab

**OpenSeesMatlab** brings the OpenSees finite-element engine into MATLAB. You build and analyze a model with familiar OpenSees-style commands, then use MATLAB variables and the toolbox modules to prepare inputs, manage analyses, retrieve results, and visualize them.

<div class="grid cards" markdown>

- ![OpenSeesMatlab model visualization](static/images/demo-readme.png)

</div>

## Start here

Choose the path that matches what you want to do:

| Goal | Recommended page |
|---|---|
| Understand the toolbox and its modules | [OpenSeesMatlab at a glance](getting_started/overview.md) |
| Install and verify the toolbox | [Installation](getting_started/installation.md) |
| Build and analyze a first model | [Your first analysis](getting_started/quickstart.md) |
| Translate OpenSees or OpenSeesPy commands | [OpenSees command interface](getting_started/opensees.md) |
| Record, retrieve, and visualize results | [Pre/post-processing and visualization](getting_started/post.md) |
| Use OpenSeesMatlab-specific functionality | [Extensions](getting_started/extensions.md) |
| See complete engineering examples | [Examples](examples/index.md) |

!!! tip "New to both OpenSees and OpenSeesMatlab?"

    Read the [toolbox overview](getting_started/overview.md), complete the
    [first analysis](getting_started/quickstart.md), and then open an example
    closest to your own model type.

## The basic workflow

Most projects follow the same sequence:

1. Create one [`OpenSeesMatlab`][OpenSeesMatlab] object.
2. Use [`opsMat.opensees`][ops.OpenSeesMatlabCmds] to define and analyze the OpenSees domain.
3. Read values directly during analysis, use standard OpenSees recorders, or create an OpenSeesMatlab ODB for structured results.
4. Use MATLAB or [`opsMat.vis`][plotter.OpenSeesMatlabVis] to inspect and visualize the results.
5. Call `wipe` before building an unrelated model in the same MATLAB session.

```matlab
opsMat = OpenSeesMatlab();
ops = opsMat.opensees;

ops.wipe();
ops.model('basic', '-ndm', 2, '-ndf', 2);

ops.node(1, 0.0, 0.0);
ops.node(2, 1.0, 0.0);
ops.fix(1, 1, 1);

% Continue with materials, elements, loads, and analysis commands.

modelInfo = opsMat.post.getModelData(); %#ok<NASGU>
opsMat.vis.plotModel();
% Or open the interactive Polyscope viewer:
% opsMat.vis.polyscope.plotModel();
```

OpenSeesMatlab intentionally keeps the OpenSees command vocabulary. In most cases, an OpenSees or OpenSeesPy command can be translated by changing the call form rather than learning a new modelling language:

```text
OpenSeesPy:  ops.node(2, 1.0, 0.0)
MATLAB:      ops.node(2, 1.0, 0.0);
```

## How it differs from Tcl and OpenSeesPy

All three interfaces ultimately build and analyze a domain in the same
OpenSees C++ computational core. Tcl, OpenSeesPy, and OpenSeesMatlab each wrap
that core with a language-facing binding and data-conversion layer: the layer
translates host-language command arguments into values understood by OpenSees,
invokes the corresponding C++ command, and converts returned values back into
Tcl, Python, or MATLAB data. The wrappers are implemented differently, but the
element formulations, solution algorithms, and most command concepts come
from the shared OpenSees core. The main user-facing differences are therefore
the host-language syntax, data model, surrounding ecosystem, and additional
workflow tools.

| | OpenSees Tcl | OpenSeesPy | OpenSeesMatlab |
|---|---|---|---|
| Host environment | Tcl interpreter and command-line scripts | Python and its scientific ecosystem | MATLAB, Live Scripts, and MATLAB toolboxes |
| Typical command | `node 2 1.0 0.0` | `ops.node(2, 1.0, 0.0)` | `ops.node(2, 1.0, 0.0);` |
| Returned data | Commonly written with recorders or handled as Tcl values | Python scalars, lists, NumPy arrays, and user-defined workflows | MATLAB scalars, arrays, structs, tables, and toolbox workflows |
| Model automation | Tcl loops and procedures | Python functions, classes, packages, and notebooks | MATLAB functions, classes, scripts, Live Scripts, and apps |
| Built-in workflow in this project | Standard OpenSees commands and recorders | Provided by the separate OpenSeesPy ecosystem | [Preprocessing][pre.OpenSeesMatlabPre], [analysis helpers][analysis.OpenSeesMatlabAnalysis], [ODB post-processing][post.OpenSeesMatlabPost], and [visualization][plotter.OpenSeesMatlabVis] |
| Interactive visualization | Normally external or script-based | Python plotting/viewer packages | MATLAB figures plus the recommended [Polyscope GUI][plotter.OpenSeesMatlabVisPolyscope] |
| Current OpenSeesMatlab platform scope | OpenSees itself is available on multiple platforms | Available on multiple platforms | The distributed OpenSeesMatlab toolbox currently targets Windows and requires MATLAB |

Choose **Tcl** when you want the traditional OpenSees scripting environment
and maximum compatibility with established Tcl examples. Choose
**OpenSeesPy** when the surrounding workflow is primarily Python-based.
Choose **OpenSeesMatlab** when model generation, calibration, signal
processing, optimization, plotting, or application development already takes
place in MATLAB.

!!! note "Equivalent commands do not imply identical scripts"

    Command names and argument order are usually close, but Tcl list
    expansion, Python containers, and MATLAB arrays/cell arrays follow their
    respective language rules. When translating a model, check the
    [MATLAB calling conventions](getting_started/opensees.md) and verify the
    resulting model and analysis independently.

## What the main object provides

| Property | Use it for |
|---|---|
| [`opsMat.opensees`][ops.OpenSeesMatlabCmds] | OpenSees model, loading, analysis, recorder, and query commands |
| [`opsMat.pre`][pre.OpenSeesMatlabPre] | Units, sections, meshes, matrices, and other preprocessing helpers |
| [`opsMat.anlys`][analysis.OpenSeesMatlabAnalysis] | Higher-level analysis workflows such as robust step handling |
| [`opsMat.post`][post.OpenSeesMatlabPost] | Model data, eigen data, ODB recording, response retrieval, and export |
| [`opsMat.vis`][plotter.OpenSeesMatlabVis] | MATLAB model, mode-shape, deformation, and response plots |
| [`opsMat.vis.polyscope`][plotter.OpenSeesMatlabVisPolyscope] | Interactive Polyscope GUI viewers |
| [`opsMat.utils`][utils.OpenSeesMatlabTool] | General toolbox helpers and example utilities |

The modules share the same OpenSees domain through `opsMat`; do not create a separate top-level object for every module.

## Choosing a result workflow

| Need | Use |
|---|---|
| A few values during or after an analysis | OpenSees query commands such as `nodeDisp`, `nodeReaction`, `eleForce`, and `eleResponse` |
| Maximum performance or OpenSees-compatible text output | Standard OpenSees `recorder` commands |
| Structured time histories for toolbox plotting and export | [`opsMat.post.createODB`][post.OpenSeesMatlabPost.createODB] and the response retrieval functions |

For large transient models, record only the data you need. Convenience layers make exploration easier, while direct OpenSees queries and recorders minimize overhead.

## Scope and requirements

- MATLAB R2023a or later
- Windows (the currently supported platform)
- Command syntax aligned as closely as possible with OpenSees and OpenSeesPy
- MATLAB-native access to returned numeric and structured data

<div class="grid cards" markdown>

- OpenSeesMatlab is an open-source engineering tool under active development. Validate models, units, convergence settings, and results independently before using them for engineering decisions.

</div>

## Related resources

- **OpenSees**: [:fontawesome-brands-readme: Documentation](https://opensees.github.io/OpenSeesDocumentation/) | [:fontawesome-brands-readme: Command manual](https://opensees.berkeley.edu/wiki/index.php/OpenSees_User) | [:fontawesome-brands-github: Github](https://github.com/OpenSees/OpenSees)
- **OpenSeesPy**: [:fontawesome-brands-readme: Documentation](https://openseespydoc.readthedocs.io/) | [:fontawesome-brands-github: Github](https://github.com/zhuminjie/OpenSeesPy)
- **opstool**: [:fontawesome-brands-readme: Documentation](https://opstool.readthedocs.io/en/latest/index.html)  | [:fontawesome-brands-github: Github](https://github.com/yexiang92/opstool)
