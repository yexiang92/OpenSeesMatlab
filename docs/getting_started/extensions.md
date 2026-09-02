# OpenSeesMatlab Extensions

OpenSeesMatlab includes optional features that extend the standard OpenSees
command workflow. These extensions use the same `ops` interface as native
commands, but they are implemented and maintained by OpenSeesMatlab.

| If you need to... | Start with |
|---|---|
| Retry a difficult nonlinear step without losing its remainder | `adaptiveAnalyze` |
| Run a component or condensed model in a MATLAB function | `matlabSubstructure` |
| Define a path-dependent uniaxial material in MATLAB | MATLAB uniaxial material |
| Solve a large sparse system on an NVIDIA GPU | `CuDSS` |
| Add line-search Newton, adaptive tangent refresh, or Anderson-Picard iteration | `KINSOL` |
| Globalize Newton steps with a native Cauchy or dogleg trust region | `TrustRegion` |

Use an extension only where it solves a specific problem. An ordinary OpenSees
command is still the clearest choice for the rest of the model.

## Canonical names and compatibility aliases

The documentation uses one canonical spelling for each public feature. A few
older spellings remain accepted so existing models continue to run:

| Canonical form | Compatibility form | Note |
|---|---|---|
| `algorithm("TrustRegion", ...)` | `TrustRegionNewton` | The alias does not select the Newton subproblem; use `-subproblem`. |
| `algorithm("KINSOL", "-testMode", "Hybrid")` | `Validated` | Both select hybrid final validation. |
| `-funcNormTol` | `-fnormTol` | KINSOL function-norm tolerance. |
| `-scaledStepTol` | `-stepTol` | KINSOL scaled-step tolerance. |
| `-incrementConstraints` | `-constraints` | KINSOL correction constraints. |
| `system("CuDSS", ...)` | `CuDSSGeneral` | Both select the general sparse cuDSS system. |

The raw MEX dispatcher also recognizes internal callback command names used by
older builds. They are implementation details, not additional MATLAB APIs.
Use `ops.matlabSubstructure(...)` and
`ops.uniaxialMaterial("MatlabUniaxialMaterial", ...)` in user code.

## Adaptive analysis recovery

[`adaptiveAnalyze`][ops.OpenSeesMatlabCmds.adaptiveAnalyze] is a replacement
for `analyze` that advances the model one step at a time and applies recovery
strategies only after a step fails. It supports static, fixed-step transient,
and `VariableTransient` analyses without requiring changes to OpenSees.

[Read the adaptive analysis guide](extensions/adaptive_analysis.md){ .md-button .md-button--primary }

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
The wrapper exposes CPU/GPU crossover, reordering, factorization and pivoting
controls, hybrid memory/execution, host threading, single-node multi-GPU and
Schur-complement options. Symbolic analysis and numerical factors are reused
when the OpenSees equation graph permits it.

[Read the cuDSS configuration and usage guide](extensions/cudss_solver.md){ .md-button .md-button--primary }

CPU solvers remain available without CUDA or cuDSS. The GPU runtime is loaded
only when a cuDSS system is explicitly selected.

## SUNDIALS KINSOL nonlinear solver

The optional KINSOL backend replaces the nonlinear `algorithm` while retaining
the current OpenSees integrator, Domain state handling, and `LinearSOE`. Newton,
Newton line search, adaptive or modified tangent refresh, and
Anderson-accelerated Picard iteration are available. Penalty constraint
handlers automatically use step-based final validation because penalty forces
can make the total residual norm unsuitable as a convergence measure.

[Read the KINSOL configuration and convergence guide](extensions/kinsol_solver.md){ .md-button .md-button--primary }

## Native trust-region nonlinear algorithm

`TrustRegion` is an OpenSeesMatlab algorithm extension with Newton, Cauchy,
and dogleg subproblems. Its algorithmic structure references Trilinos NOX's
BSD-licensed trust-region implementation but does not link to or depend on
NOX. Newton equations continue to use the selected OpenSees `system`; a sparse
tangent snapshot is used only for the Jacobian-vector products required by
Cauchy and dogleg. Accepted steps use the normal OpenSees convergence test and
Domain commit/revert lifecycle.

[Read the trust-region algorithm guide](extensions/trust_region_solver.md){ .md-button .md-button--primary }

## Extension examples

Complete runnable examples are collected under
[Extended functionality by OpenSeesMatlab](../examples/extension/index.md),
including linear and nonlinear MATLAB substructures and a cuDSS plane-element
solver comparison.
