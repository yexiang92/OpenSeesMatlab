# Linear Buckling Analysis

`linearBuckling` calculates
linearized bifurcation load factors and mode shapes while retaining the normal
OpenSees model-building and static-analysis workflow. OpenSeesMatlab does not
construct or modify the model for this command; the user controls the unloaded
state, reference load, analysis configuration, and validation.

!!! warning "Validation status"

    This extension has not yet received broad independent use. Validate load
    factors and mode shapes against analytical solutions, mesh refinement, and
    another solver before relying on them. Report reproducible problems through
    [GitHub Issues](https://github.com/yexiang92/OpenSeesMatlab/issues).

## Problem definition

The command forms the tangent-difference problem

\[
K_g = K_0-K_1,
\qquad
K_0\phi = \lambda K_g\phi,
\]

where (K_0) is the tangent captured before applying the reference load and
(K_1) is the tangent at the converged reference state. A returned positive
factor \(\lambda_i\) multiplies the complete reference load pattern.

This is not the vibration problem solved by
[`eigen`][ops.OpenSeesMatlabCmds.eigen]. Buckling factors are dimensionless
unless the reference pattern has been normalized to one unit of load.

## Required command sequence

```text
build model and reference load pattern
configure the complete Static analysis
linearBuckling("capture")
analyze the reference-load step
linearBuckling("solve", numberOfModes)
```

```matlab
ops.constraints("Transformation");
ops.numberer("RCM");
ops.system("UmfPack");
ops.test("NormDispIncr", 1.0e-10, 30);
ops.algorithm("Newton");
ops.integrator("LoadControl", 1.0);
ops.analysis("Static");

captureCode = ops.linearBuckling("capture");
assert(captureCode == 0, "Could not capture the base tangent.");

analysisCode = ops.analyze(1);
assert(analysisCode == 0, "The reference-load analysis failed.");

bucklingFactors = double(ops.linearBuckling("solve", 6));
```

Do not call `wipeAnalysis`, replace an analysis component, or change the domain
between `capture` and `solve`.

## Model and matrix requirements

| Requirement | Reason |
| --- | --- |
| Configured `Static` analysis | Both tangents are formed through the active static integrator |
| Geometrically nonlinear formulation | The reference step must produce a nonzero geometric stiffness |
| Converged reference state | `K1` must describe the intended prestress rather than a failed trial state |
| Symmetric `K0` and `Kg` | The sparse ARPACK formulation solves a symmetric generalized eigenproblem |
| Positive-definite constrained `K0` | `K0` defines the inner product and must be factorable |
| Unchanged topology and numbering | Stored element blocks must remain in the captured equation space |
| `1 <= numberOfModes < numberOfEquations` | ARPACK needs a Krylov space larger than the requested mode set |

`Transformation` is the recommended general constraint handler. `Plain` is
also suitable when all constraints are homogeneous and compatible with it.
Penalty constraints can introduce extreme stiffness scales, while Lagrange
multipliers make the base matrix indefinite; neither is a good default for the
symmetric positive-definite buckling formulation.

## Reference load and returned factors

All loads active during the reference step are scaled together. If a unit
compressive pattern is used, the factor is numerically equal to the critical
load. Otherwise,

\[
P_{cr,i}=\lambda_i P_{ref}.
\]

The analysis is a linearization about the selected reference state. It does
not trace a nonlinear equilibrium path, introduce imperfections, calculate a
post-buckling response, or determine a collapse load.

## Sparse system selection

| System | Recommended use |
| --- | --- |
| `UmfPack` | Portable CPU baseline and routine sparse analysis |
| `CuDSSSPD` | Large compatible symmetric positive-definite base systems on NVIDIA GPUs |
| `CuDSS` | General sparse diagnostic path when SPD factorization is unsuitable |
| `BandGeneral` | Small or narrow-band verification models |

The active system factors (K_0). ARPACK then reuses that solve while applying
(K_g) from stored element blocks. See the
[cuDSS guide](cudss_solver.md#eigenvalue-and-linear-buckling-analysis) for GPU
requirements and limitations.

## Collect and visualize all modes

[`getLinearBucklingData`][post.OpenSeesMatlabPost.getLinearBucklingData]
collects the node eigenvectors already stored by `solve`; it does not repeat
the analysis:

```matlab
bucklingData = opsMAT.post.getLinearBucklingData( ...
    bucklingFactors, IncludeModelInfo=true);
```

All mode-shape viewers read `bucklingData.AnalysisType` and automatically use
buckling labels:

```matlab
opsMAT.vis.plotEigen(1, bucklingData);
opsMAT.vis.plotEigenGUI(bucklingData);
opsMAT.vis.polyscope.plotEigen(bucklingData);
```

When `IncludeModelInfo=true`, the stored geometry is preferred over the live
domain, so the modes remain viewable after `ops.wipe()`.

Use [`saveLinearBucklingData`][post.OpenSeesMatlabPost.saveLinearBucklingData]
to store the complete mode set in an OpenSeesMatlab result file.

## Validation

- Compare the first factor with an analytical solution for a simple column or
  plate before using the workflow on a large model.
- Refine the mesh and verify that the factors and mode shapes stabilize.
- Reverse or rescale the reference load to confirm the sign and scaling
  convention.
- Check that every requested mode has a small residual and a physically
  interpretable shape.
- Compare `UmfPack` with `CuDSSSPD` before relying on GPU results.

## Related API and examples

- [OpenSeesNexus extensions API](../../api/OpenSeesNexusExtensions.md)
- [`linearBuckling` extension API](../../api/OpenSeesNexusExtensions.md#linear-buckling)
- [`getLinearBucklingData` API][post.OpenSeesMatlabPost.getLinearBucklingData]
- [`plotEigen` MATLAB graphics API][plotter.OpenSeesMatlabVis.plotEigen]
- [`plotEigen` Polyscope API][plotter.OpenSeesMatlabVisPolyscope.plotEigen]
- [Rectangular plate buckling example](../../examples/extension/analysis/extension_linear_buckling_plate.md)
