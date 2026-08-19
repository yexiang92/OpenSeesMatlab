# Native Trust-Region Nonlinear Algorithm

!!! summary
    `TrustRegion` replaces only the OpenSees nonlinear `algorithm`. The active
    constraints, numberer, integrator, linear system, analysis object, Domain,
    elements, and materials remain under normal OpenSees control.

The trust-region extension globalizes Newton iteration by accepting a trial
step only when the measured residual reduction is consistent with the local
linear model. Its algorithmic structure references the BSD-licensed Trilinos
`NOX::Solver::TrustRegionBased` implementation, particularly its Cauchy point,
dogleg path, actual-to-predicted reduction ratio, and radius-update rules. The
algorithm has been reimplemented against OpenSees interfaces; it neither links
to NOX nor requires Trilinos or SUNDIALS KINSOL, and it does not claim complete
behavioral identity with NOX.

## Basic use

```matlab
ops.constraints("Transformation");
ops.numberer("RCM");
ops.system("UmfPack");
ops.test("NormDispIncr", 1.0e-8, 50);

ops.algorithm("TrustRegion", ...
    "-subproblem", "dogleg", ...
    "-ratio", "quadratic", ...
    "-initialRadius", 1.0, ...
    "-maxIter", 50);

ops.integrator("LoadControl", 0.01);
ops.analysis("Static");
code = ops.analyze(100);
```

`TrustRegionNewton` is accepted as an alias, although the selected subproblem
is still controlled by `-subproblem`.

Changing only the linear system changes the solver used for every Newton
equation:

```matlab
ops.system("CuDSS");       % or UmfPack, Mumps, BandGeneral, ...
```

The trust-region implementation never factors its tangent snapshot. It always
calls the active OpenSees `LinearSOE::solve()` for the Newton direction.

## Residual and Newton sign convention

OpenSees forms the unbalanced load

\[
B = R_{\mathrm{external}}-R_{\mathrm{internal}}=-F
\]

Its Newton equation is therefore

\[
Jp_N=B=-F
\]

which is the usual nonlinear-solver equation \(Jp_N=-F\). The trust-region
linear residual is evaluated as

\[
r_{\mathrm{linear}}(p)=Jp-B
\]

No sign conversion is required when the Newton solution is obtained from the
OpenSees linear system.

## Subproblem methods

### Newton

```matlab
ops.algorithm("TrustRegion", "-subproblem", "newton");
```

The OpenSees Newton direction is truncated to the current radius when it is
too long. It uses \(Jp=\alpha B\) for a scaled Newton step, so it needs neither
a transpose Jacobian product nor a tangent snapshot.

### Cauchy

```matlab
ops.algorithm("TrustRegion", "-subproblem", "cauchy");
```

For the residual merit function

\[
\phi(u)=\frac{1}{2}\lVert F(u)\rVert_2^2
\]

the descent direction is \(-J^TF=J^TB\). The unbounded Cauchy point is

\[
p_C=\frac{\lVert J^TB\rVert_2^2}
          {\lVert JJ^TB\rVert_2^2}J^TB
\]

and is truncated when it lies outside the trust region. Pure Cauchy iteration
is robust as a descent mechanism but can be very slow for ill-conditioned or
poorly scaled structural equations. It is mainly useful as a diagnostic or as
the first segment of dogleg.

### Dogleg

```matlab
ops.algorithm("TrustRegion", "-subproblem", "dogleg");
```

Dogleg uses the Cauchy point near the origin and then follows the segment from
the Cauchy point to the full Newton point. It selects the intersection with
the trust-region boundary when the Newton point lies outside the radius.
`dogleg` is the default because it combines residual descent away from the
solution with fast Newton convergence near the solution.

## Acceptance ratio and radius updates

The default `quadratic` ratio compares the actual reduction of the residual
merit function with the reduction predicted by \(F+Jp\):

\[
\rho=
\frac{\frac12\lVert F\rVert^2-\frac12\lVert F(u+p)\rVert^2}
     {\frac12\lVert F\rVert^2-\frac12\lVert F+Jp\rVert^2}
\]

The alternative `aredPred` form compares reductions in the residual norm
rather than its square:

```matlab
ops.algorithm("TrustRegion", "-ratio", "aredPred");
```

A step is accepted when `rho >= minRatio`. Poor ratios contract the radius;
good boundary steps expand it. Rejected trial points are restored to the last
accepted OpenSees trial state and are never committed.

## Options

| Option | Default | Meaning |
|---|---:|---|
| `-subproblem newton\|cauchy\|dogleg` | `dogleg` | Trust-region subproblem |
| `-ratio quadratic\|aredPred` | `quadratic` | Actual/predicted reduction definition |
| `-initialRadius value` | `1.0` | Initial radius |
| `-minRadius value` | `1e-12` | Minimum radius before failure |
| `-maxRadius value` | `1e10` | Maximum radius |
| `-minRatio value` | `1e-4` | Minimum ratio for accepting a trial step |
| `-contractRatio value` | `0.1` | Ratio below which the radius contracts |
| `-expandRatio value` | `0.75` | Ratio above which a boundary step may expand the radius |
| `-contractFactor value` | `0.25` | Radius contraction multiplier |
| `-expandFactor value` | `4.0` | Radius expansion multiplier |
| `-maxIter n` | inherited from `test` | Maximum accepted nonlinear iterations per analysis step |
| `-maxReject n` | `20` | Maximum rejected trials for one tangent/model |
| `-recoveryStep value` | `0` | Fraction of the Newton step used after rejection exhaustion; zero fails safely |
| `-verbosity 0\|1\|2` | `0` | Diagnostic output level |
| `-printStats` | off | Print final statistics |

The consistency rules require
`minRadius <= initialRadius <= maxRadius`, ordered ratio thresholds, a
contraction factor below one, and an expansion factor above one.

When `-maxIter` is omitted, the algorithm reads
`ConvergenceTest::getMaxNumTests()` at the start of every analysis step. The
iteration count specified by `test` is therefore the single default limit.
Providing `-maxIter` remains available as an explicit algorithm-level override.

## Interaction with OpenSees convergence tests

Unlike KINSOL, `TrustRegion` uses the selected OpenSees `test` as its
convergence test. It does not create a second nonlinear loop around another
solver. The test is called only after a trust-region trial has been accepted,
and `LinearSOE::X` is set to the accepted increment before the test is called.
Consequently `NormDispIncr` and `EnergyIncr` observe the accepted step rather
than a rejected candidate.

```matlab
ops.test("NormDispIncr", 1.0e-8, 50);
ops.algorithm("TrustRegion", "-subproblem", "dogleg");
```

`NormUnbalance` is often suitable with Transformation constraints. Very large
Penalty factors can make the force norm poorly scaled or dominated by penalty
forces; prefer `NormDispIncr`, an explicitly assessed `EnergyIncr`, or a
combined engineering acceptance check for such models.

## Tangent snapshot and transient analysis

For static integrators, OpenSees assembles its tangent from `FE_Element`
contributions. The trust-region snapshot follows the same equation IDs and
assembly operation.

For transient integrators such as Newmark, OpenSees assembles both:

1. `DOF_Group` contributions, including nodal mass and nodal damping; and
2. `FE_Element` contributions, including effective stiffness, damping, and
   element mass.

The trust-region snapshot follows this order and reads the local tangents just
formed by OpenSees without forming them a second time. Snapshot construction
is lazy: Newton does not require it, and dogleg avoids it whenever the full
Newton step is accepted inside the current radius. Therefore ordinary Newmark
models with nodal mass, element mass, and Rayleigh damping are supported by
Cauchy and dogleg. The effective tangent has the familiar form

\[
J_{\mathrm{eff}}=c_1K+c_2C+c_3M
\]

!!! warning "Modal damping matrix limitation"
    OpenSees adds its modal damping matrix directly to `LinearSOE` inside
    `TransientIntegrator::formTangent()`. That contribution is not exposed as
    a `DOF_Group` or `FE_Element` tangent and is therefore not present in the
    trust-region sparse snapshot.

    Trust-region Newton remains complete because its direction is solved using
    the OpenSees `LinearSOE` and its predicted linear residual follows directly
    from \(Jp_N=B\). With modal damping enabled, Cauchy and dogleg still have
    incomplete snapshot `J*v` and `J^T*v` operations. Until a portable access
    path is implemented, use `TrustRegion -subproblem newton` or a native
    OpenSees Newton-family algorithm for modal-damping analyses, or use Rayleigh
    damping when Cauchy/dogleg behavior is required.

## Scaling and method selection

The current radius and residual merit use unscaled Euclidean norms. Models
mixing translations, rotations, forces, moments, or widely different stiffness
scales can make pure Cauchy iteration converge very slowly. This is not usually
a useful default for nonlinear frame analysis.

Recommended starting points:

| Situation | Suggested method |
|---|---|
| Ordinary problem with reliable Newton steps | OpenSees `Newton` |
| Full Newton steps leave the local convergence region | `TrustRegion -subproblem dogleg` |
| Modal damping matrix is enabled | `TrustRegion -subproblem newton` or native Newton |
| Diagnose merit-function descent or scaling | `TrustRegion -subproblem cauchy` |
| Need line search, scaling vectors, inequalities, or Anderson-Picard | `KINSOL` |

## Usage and performance guidance

Start with the native OpenSees `Newton` result as both an accuracy and timing
baseline. If Newton already converges reliably in a few iterations,
trust-region globalization is unlikely to reduce total work. Use dogleg when
full Newton steps are rejected, cross sharp stiffness transitions, or leave a
small local convergence region.

A practical initial configuration is:

```matlab
maxIterations = 50;
ops.test("NormDispIncr", 1.0e-8, maxIterations);
ops.algorithm("TrustRegion", ...
    "-subproblem", "dogleg", ...
    "-ratio", "quadratic", ...
    "-initialRadius", 1.0, ...
    "-minRadius", 1.0e-12, ...
    "-maxRadius", 1.0e6, ...
    "-maxReject", 20);
```

`-maxIter` can normally be omitted because it inherits the limit from `test`.
Specify it only when a separate algorithm safety limit is intentional.

### Choose the radius from the expected correction scale

The radius is measured in the unscaled Euclidean norm of the equation-space
increment. Set `-initialRadius` near a plausible correction magnitude rather
than copying one value between models with different units. A radius that is
too small causes many expansions and artificially truncated steps. A radius
that is too large provides little protection from a poor full Newton step.

Use the statistics to diagnose the choice:

| Observed statistics | Likely interpretation | Adjustment |
|---|---|---|
| Many `radiusExpansions`, few rejections | Initial radius is conservative | Increase `-initialRadius` |
| Many `rejectedSteps` and contractions | Local model is inaccurate or radius is too large | Reduce `-initialRadius`; consider smaller analysis increments |
| `finalRadius` reaches `minRadius` | The current step or model is not producing useful reduction | Reduce the load/time step or change integrator/algorithm |
| Mostly `newtonSteps`, zero snapshot size | Newton fast path is active | Overhead should be close to Newton |
| Frequent `cauchySteps` or `doglegSteps` | Globalization is active | Expect extra sparse products and possibly extra residual evaluations |

### Understand the fast paths

Trust-region Newton does not create a sparse tangent snapshot. A dogleg step
also skips the snapshot whenever the full Newton point lies inside the radius
and is accepted. Consequently dogleg can approach Newton cost near the
solution. Snapshot allocation and `J*v`/`J^T*v` costs occur only when the
Cauchy or dogleg construction is actually required.

Pure Cauchy is generally not a performance method for structural systems. It
can require many iterations when translations, rotations, forces, moments, or
stiffnesses have different scales. Use it mainly to examine residual-merit
descent or scaling. Dogleg is the normal production choice when trust-region
globalization is needed.

### Keep the OpenSees linear system appropriate

Every Newton equation is solved by the selected OpenSees `system`. For large
models, tangent factorization normally dominates trust-region bookkeeping.
Compare suitable systems such as UmfPack, Mumps, or CuDSS using the same model
and nonlinear settings. Switching `system` does not require TrustRegion code
changes.

### Match the convergence test to the constraint handler

With Transformation constraints, `NormUnbalance` is often a useful force
criterion. Large Penalty factors can dominate or distort that norm. For
Penalty models, prefer `NormDispIncr`, carefully assessed `EnergyIncr`, or an
independent engineering response check. Loosening a force tolerance solely to
hide penalty forces can accept an inaccurate physical equilibrium state.

### Treat timing as a benchmark, not a property of the method

Exclude model construction and gravity initialization when comparing nonlinear
solution time. Warm up MATLAB and the selected linear solver, repeat each case,
and report a median rather than one run. Compare time together with
`tangentEvaluations`, `linearSolves`, `residualEvaluations`, accepted/rejected
steps, and response error. A faster result is not useful if it follows a
different equilibrium path or stops at a looser effective criterion.

For snap-through or snap-back, changing only the nonlinear algorithm is often
insufficient. Use an appropriate OpenSees continuation integrator or smaller
adaptive increments; TrustRegion globalizes the equilibrium iteration but does
not replace the analysis path parameterization.

## Statistics and return reason

```matlab
statistics = ops.call("trustRegionStats");
reason = ops.call("trustRegionReturnReason");
```

The statistics structure contains:

| Field | Meaning |
|---|---|
| `nonlinearIterations` | Accepted nonlinear iterations |
| `iterationLimit` | Effective limit after inheritance or explicit override |
| `residualEvaluations` | Residual formations |
| `tangentEvaluations` | OpenSees tangent formations |
| `linearSolves` | Calls to the active OpenSees linear system |
| `acceptedSteps`, `rejectedSteps` | Accepted and rejected trial counts |
| `radiusContractions`, `radiusExpansions` | Radius changes |
| `newtonSteps`, `cauchySteps`, `doglegSteps` | Attempted subproblem steps |
| `jacobianProducts` | Snapshot `J*v` products |
| `transposeJacobianProducts` | Snapshot `J^T*v` products |
| `snapshotNonzeros`, `snapshotBytes` | Sparse snapshot size estimate |
| `finalResidualNorm`, `finalStepNorm` | Final norms |
| `finalRadius`, `finalImprovementRatio` | Final trust-region state |
| `returnCode` | Numeric result code |

On failure, the surrounding OpenSees analysis performs its normal failed-step
revert. Replacing the algorithm and retrying the step therefore starts from
the last committed Domain state.

## Complete comparison example

The notebook-style script `examples/extension_TrustRegion_steel_frame_benchmark.m`
compares OpenSees Newton and KrylovNewton with trust-region Newton, Cauchy, and
dogleg for nonlinear pushover and Newmark transient analyses. It reports
accuracy, timing, iteration histories, residual histories, completion, and
return reasons with publication-style figures.
