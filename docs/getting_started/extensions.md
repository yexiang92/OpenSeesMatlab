# OpenSeesMatlab Extensions

OpenSeesMatlab includes optional features that extend the standard OpenSees
command workflow. These extensions use the same `ops` interface as native
commands, but they are implemented and maintained by OpenSeesMatlab.

## MATLAB numerical substructure analysis

[`matlabSubstructure`][ops.OpenSeesMatlabCmds.matlabSubstructure] connects an
OpenSees domain to a numerical sub-model evaluated by a MATLAB callback.
OpenSees owns the global model and analysis, while MATLAB returns the interface
force, tangent stiffness, and optional mass and damping matrices.

[Read the MATLAB substructure guide](extensions/substructure_analysis.md){ .md-button .md-button--primary }

## MATLAB-defined uniaxial material

Implement stress, tangent, damping tangent, and path-dependent history in a
MATLAB callback, then use the result as an ordinary OpenSees uniaxial material.

[Read the MATLAB material guide](extensions/matlab_uniaxialmaterial.md){ .md-button .md-button--primary }

Use this extension when a component or condensed sub-model is easier to
implement in MATLAB but must participate in an ordinary OpenSees static or
transient analysis.

## NVIDIA cuDSS GPU solver

The optional cuDSS backend solves sparse linear systems on a supported NVIDIA
GPU. It is selected through `ops.system("CuDSS", ...)` and is most useful for
large systems or analyses that repeatedly factorize tangent matrices.

[Read the cuDSS configuration and usage guide](extensions/cudss_solver.md){ .md-button .md-button--primary }

CPU solvers remain available without CUDA or cuDSS. The GPU runtime is loaded
only when a cuDSS system is explicitly selected.

## Extension examples

Complete runnable examples are collected under
[Extended functionality by OpenSeesMatlab](../examples/extension/index.md),
including linear and nonlinear MATLAB substructures and a cuDSS plane-element
solver comparison.
