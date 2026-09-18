# OpenSeesNexus extensions API

OpenSeesMatlab exposes the OpenSeesNexus extensions through the same command
object used for upstream OpenSees commands:

```matlab
opsMAT = OpenSeesMatlab();
ops = opsMAT.opensees;
```

An extension is either a dedicated method, such as `linearBuckling`, or a type
selected by an existing OpenSees command family, such as
`system("CuDSS")`. The latter are not separate MATLAB methods.

!!! warning "Extension validation"

    These extensions are tested with targeted unit, regression, and example
    models, but they have not yet accumulated the broad independent usage of
    established upstream OpenSees features. Independently verify critical
    numerical results. Report reproducible problems through
    [GitHub Issues](https://github.com/yexiang92/OpenSeesMatlab/issues) with the
    version, platform, minimal model, expected result, and observed result.

## Dedicated extension commands

| Method | Purpose | Main return value |
| --- | --- | --- |
| [`adaptiveAnalyze`][ops.OpenSeesMatlabCmds.adaptiveAnalyze] | Retry failed static or transient steps with explicitly configured recovery strategies | OpenSees analysis status |
| [`linearBuckling`](#linear-buckling) | Capture the unloaded tangent and solve the sparse linearized buckling problem | Status for `capture`; load-factor vector for `solve` |
| [`FEMDataRecorder`](#femdata-and-model-state-utilities) | Create the native HDF5 FEMData recorder | Recorder status/tag |
| [`getFEMModel`](#femdata-and-model-state-utilities) | Return the active domain geometry and metadata | MATLAB structure |
| [`writeFEMModel`](#femdata-and-model-state-utilities) | Write the active domain model to an FEMData file | Status |
| [`readFEMData`](#femdata-and-model-state-utilities) | Read an FEMData HDF5 file | MATLAB structure |
| [`writeFEMDataPVD`](#femdata-and-model-state-utilities) | Write a ParaView collection for FEMData results | Status |
| [`getDomainGeoTag`](#femdata-and-model-state-utilities) | Return the domain topology revision | Integer revision |
| [`updateMaterials`](#femdata-and-model-state-utilities) | Apply supported material parameter updates without modifying upstream OpenSees | Number/status of updates |
| [`constraintGraphValidator`](#femdata-and-model-state-utilities) | Validate SP/MP constraint topology before analysis | Validation result |

### Adaptive analysis

```matlab
status = ops.adaptiveAnalyze(10, ...
    "-iterations", 2.0, 50, ...
    "-algorithms", "Newton", "KrylovNewton", ...
    "-subdivision", 0.5, 1.0e-6, 12);
```

`adaptiveAnalyze` uses the current OpenSees analysis objects. Recovery is
performed only after a step fails. See the
[adaptive-analysis guide](../getting_started/extensions/adaptive_analysis.md)
for static, transient, and variable-transient forms and all option groups.

### Linear buckling

```matlab
ops.constraints("Transformation");
ops.numberer("RCM");
ops.system("UmfPack");
ops.test("NormDispIncr", 1.0e-10, 30);
ops.algorithm("Newton");
ops.integrator("LoadControl", 1.0);
ops.analysis("Static");

if ops.linearBuckling("capture") ~= 0
    error("Could not capture the base tangent.");
end

if ops.analyze(1) ~= 0
    error("The reference-load analysis failed.");
end

bucklingFactors = ops.linearBuckling("solve", 6);
```

The topology, equation numbering, constraint handler, and analysis objects
must remain unchanged between `capture` and `solve`. The reference step must
converge, and the model must contain geometric stiffness. `UmfPack` is the CPU
baseline; `CuDSSSPD` can accelerate large compatible sparse problems.

Collect all returned modes in one operation:

```matlab
bucklingData = opsMAT.post.getLinearBucklingData( ...
    bucklingFactors, IncludeModelInfo=true);
opsMAT.vis.polyscope.plotEigen(bucklingData);
```

The stored `AnalysisType="buckling"` lets every mode-shape viewer distinguish
buckling data from ordinary modal data automatically.

[Read the complete linear buckling guide](../getting_started/extensions/linear_buckling.md).

## Extended system types

System extensions are selected with the ordinary
[`system`][ops.OpenSeesMatlabCmds.system] method.

| Type | Backend | Intended use |
| --- | --- | --- |
| `CuDSS` | NVIDIA cuDSS, general sparse | General sparse CPU/GPU factorization |
| `CuDSSSPD` | NVIDIA cuDSS, symmetric positive definite | Compatible structural, ARPACK, and linear-buckling systems |
| `SUNDIALS` | SUNDIALS CPU/CUDA/HIP | Iterative sparse Krylov solution |

```matlab
ops.system("CuDSS", "-device", "auto", "-reuseFactorization");
ops.system("CuDSSSPD", "-device", 0, "-reuseFactorization");
ops.system("SUNDIALS", "-backend", "cpu", ...
    "-type", "spgmr", "-relativeTolerance", 1.0e-8);
```

CUDA, cuDSS, and SUNDIALS GPU libraries are loaded only when their respective
runtime backend is selected. See the [cuDSS guide](../getting_started/extensions/cudss_solver.md)
for availability, options, reuse rules, and diagnostics.

## Extended nonlinear algorithms

Algorithm extensions are selected with the ordinary
[`algorithm`][ops.OpenSeesMatlabCmds.algorithm] method and
continue to use the active OpenSees integrator, convergence test, and system.

| Type | Main strategies |
| --- | --- |
| `TrustRegion` | Newton, Cauchy, and dogleg trust-region subproblems |
| `KINSOL` | Newton, line search, modified Jacobian, Picard, and Anderson acceleration |

```matlab
ops.algorithm("TrustRegion", "-subproblem", "dogleg");
trustInfo = ops.algorithm("TrustRegion", "-info");

ops.algorithm("KINSOL", "-method", "lineSearch", ...
    "-jacobian", "adaptive");
kinsolInfo = ops.algorithm("KINSOL", "-info");
```

See the [TrustRegion](../getting_started/extensions/trust_region_solver.md) and
[KINSOL](../getting_started/extensions/kinsol_solver.md) guides for accepted
options, convergence behavior, supported integrators, and statistics fields.

## Extended material types

### ConcreteDamagePlasticity

`ConcreteDamagePlasticity` is selected through the ordinary
[`nDMaterial`][ops.OpenSeesMatlabCmds.nDMaterial] method:

```matlab
tensionArgs = num2cell(reshape(tensionTable.', 1, []));
compressionArgs = num2cell(reshape(compressionTable.', 1, []));

ops.nDMaterial("ConcreteDamagePlasticity", tag, ...
    E, nu, dilation, eccentricity, fb0fc0, Kc, viscosity, wt, wc, ...
    "-tension", size(tensionTable, 1), tensionArgs{:}, ...
    "-compression", size(compressionTable, 1), compressionArgs{:}, ...
    "-rho", density);
```

`tensionTable` contains rows of cracking strain, tensile stress, and tensile
damage. `compressionTable` contains rows of inelastic strain, compressive
stress magnitude, and compressive damage. Available material responses include
`DAMAGET`, `DAMAGEC`, `PEEQT`, `PEEQ`, `SDEG`, and `PE`.

The finite-deformation material and element family is not listed here because
OpenSeesMatlab does not yet provide its dedicated MATLAB command wrappers.

## MATLAB callback extensions

| Method | Purpose |
| --- | --- |
| `callbackUniaxialMaterial` | Define a history-dependent uniaxial material with a MATLAB callback |
| [`callbackSubstructure`][ops.OpenSeesMatlabCmds.callbackSubstructure] | Define a condensed or component element evaluated by MATLAB |
| `callbackSparseSystem` | Solve the assembled sparse linear system in MATLAB |
| `callbackSparseEigen` | Solve a sparse eigenproblem in MATLAB |
| [`hasMatlabSubstructure`][ops.OpenSeesMatlabCmds.hasMatlabSubstructure] | Test whether a substructure callback is registered |
| [`unregisterMatlabSubstructure`][ops.OpenSeesMatlabCmds.unregisterMatlabSubstructure] | Remove one registered substructure callback |
| [`clearMatlabSubstructures`][ops.OpenSeesMatlabCmds.clearMatlabSubstructures] | Remove all registered substructure callbacks |

Callback objects participate in the normal OpenSees commit and revert
lifecycle. Their callback contracts and state rules are documented in the
[MATLAB material](../getting_started/extensions/matlab_uniaxialmaterial.md) and
[substructure](../getting_started/extensions/substructure_analysis.md) guides.

## FEMData and model-state utilities

`FEMDataRecorder`, `getFEMModel`, `writeFEMModel`, `readFEMData`, and
`writeFEMDataPVD` provide the native recording and exchange path used by the
post-processing layer. Prefer the higher-level `opsMAT.post` methods when an
equivalent method exists; call these commands directly when constructing a
custom recording workflow.

`getDomainGeoTag` is useful for invalidating cached geometry after the domain
topology changes. `constraintGraphValidator` can diagnose duplicate,
conflicting, cyclic, or unsupported constraint relationships before creating
the analysis.

## Related documentation

- [Extensions overview](../getting_started/extensions.md)
- [Complete OpenSees command API](OpenSeesMatlabCmds.md)
- [Post-processing API](OpenSeesMatlabPost.md)
- [MATLAB graphics API](OpenSeesMatlabVis.md)
- [Polyscope API](OpenSeesMatlabVisPolyscope.md)
- [Extension examples](../examples/extension/index.md)
