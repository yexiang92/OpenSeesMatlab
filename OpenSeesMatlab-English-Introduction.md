# Introducing OpenSeesMatlab: OpenSees in a Native MATLAB Workflow

I am excited to share a project I have been developing: **OpenSeesMatlab**, which brings the OpenSees finite-element engine into a native MATLAB workflow.

I am also the author of [**opstool**](https://opstool.readthedocs.io/), a Python library for OpenSeesPy pre-processing, post-processing, and visualization. My experience developing opstool shaped many of the ideas behind OpenSeesMatlab, particularly its focus on practical modeling, result handling, and visualization.

I would like to thank my postdoctoral supervisor, **Prof. Yazhou Xie**, for his support, guidance, and encouragement throughout the development of this project.

Project links:

- GitHub: [yexiang92/OpenSeesMatlab](https://github.com/yexiang92/OpenSeesMatlab)
- Documentation: [openseesmatlab.readthedocs.io](https://openseesmatlab.readthedocs.io/en/latest/)

![OpenSeesMatlab model visualization](docs/static/images/demo-readme.png)

## Why OpenSeesMatlab?

OpenSees is widely used in structural and earthquake engineering for nonlinear finite-element analysis. MATLAB is equally familiar to many researchers for data processing, optimization, signal analysis, visualization, and application development.

OpenSeesMatlab connects the two. The OpenSees C++ core handles the model and analysis through a MATLAB MEX interface, while MATLAB provides the surrounding programming and data environment. It is not a reimplementation of OpenSees.

The command style remains close to OpenSees and OpenSeesPy:

```text
OpenSeesPy:     ops.node(2, 1.0, 0.0)
OpenSeesMatlab: ops.node(2, 1.0, 0.0);
```

Results are returned directly as MATLAB data, so an analysis can be connected naturally to parameter studies, optimization, uncertainty analysis, ground-motion processing, and custom plotting.

## A small example

```matlab
opsMat = OpenSeesMatlab();
ops = opsMat.opensees;

ops.wipe();
ops.model("basic", "-ndm", 2, "-ndf", 2);

ops.node(1, 0.0, 0.0);
ops.node(2, 1.0, 0.0);
ops.fix(1, 1, 1);
ops.fix(2, 0, 1);

ops.uniaxialMaterial("Elastic", 1, 200e9);
ops.element("Truss", 1, 1, 2, 2e-3, 1);

ops.timeSeries("Linear", 1);
ops.pattern("Plain", 1, 1);
ops.load(2, 10e3, 0.0);

ops.constraints("Plain");
ops.numberer("RCM");
ops.system("BandSPD");
ops.algorithm("Linear");
ops.integrator("LoadControl", 1.0);
ops.analysis("Static");
ops.analyze(1);

ux = ops.nodeDisp(2, 1);
opsMat.vis.plotModel();
```

The modeling sequence and engineering concepts remain those of OpenSees. MATLAB becomes the interface for building the model, managing the analysis, and working with the results.

## More than a command wrapper

OpenSeesMatlab includes several modules that share the same OpenSees domain:

- `.opensees` for modeling, analysis, recorders, and response queries;
- `.pre` for units, loads, Gmsh meshes, system matrices, and fiber sections;
- `.anlys` for robust nonlinear stepping and moment–curvature analysis;
- `.post` for model data, HDF5-based output databases, response retrieval, and ParaView export;
- `.vis` for MATLAB plotting and `.vis.polyscope` for interactive visualization.

Users can choose between direct OpenSees queries, standard recorders, and the structured OpenSeesMatlab output database. Model geometry, mode shapes, deformations, frame diagrams, and shell or continuum response fields can be viewed in MATLAB or through the Polyscope GUI.

![OpenSeesMatlab response visualization](docs/static/images/demo-readme2.png)

## MATLAB extensions to OpenSees

The project also adds three capabilities beyond conventional command wrapping.

### MATLAB-defined uniaxial materials

A MATLAB callback can provide stress, tangent, damping tangent, and history-dependent state. The material can then be used in an OpenSees model like a regular uniaxial material. This is useful for testing a new constitutive rule before moving to a C++ implementation.

### MATLAB numerical substructures

OpenSees can manage the global model while a MATLAB sub-model returns interface restoring forces, tangent stiffness, and optional mass and damping matrices. This makes it possible to couple an existing MATLAB model, reduced-order component, or specialized numerical element to an OpenSees analysis.

### NVIDIA cuDSS solver

An optional cuDSS backend is available for sparse linear systems on supported NVIDIA GPUs. GPU acceleration is model-dependent, so the repository includes a benchmark against a CPU solver. CUDA and cuDSS are optional; regular OpenSees CPU solvers remain available.

## Examples and availability

The repository includes examples for nonlinear truss and frame analysis, reinforced-concrete and steel-frame earthquake response, soil materials, excavation, soil–structure interaction, thermal and sensitivity analysis, fiber sections, Gmsh mesh import, moment–curvature analysis, parallel execution, MATLAB materials, numerical substructures, and GPU solving.

The current release targets **MATLAB R2023a or later on 64-bit Windows**. After downloading a release from GitHub or Gitee, installation is performed from MATLAB:

```matlab
installOpenSeesMatlab;
```

OpenSeesMatlab is still evolving. Models, units, convergence settings, and results should always be checked independently before they are used for engineering decisions.

I hope the project will be useful to researchers and engineers who work with OpenSees and prefer to keep their wider workflow in MATLAB. Feedback, issue reports, and technical discussions are welcome through the GitHub repository.
