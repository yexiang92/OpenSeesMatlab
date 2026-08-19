# SUNDIALS KINSOL Nonlinear Solver

!!! note

    KINSOL is an optional nonlinear-algorithm extension. It replaces only the
    OpenSees `algorithm`; the Domain, constraint handler, numberer, integrator,
    analysis object, and linear system remain under OpenSees control.

[KINSOL](https://computing.llnl.gov/projects/sundials/kinsol) solves nonlinear
systems of the form

\[
F(u)=0
\]

In OpenSeesMatlab, the KINSOL unknown is the cumulative correction from the
predictor produced by the current `IncrementalIntegrator`. The residual and
Jacobian are supplied by the same OpenSees integrator used by native nonlinear
algorithms.

```text
OpenSees Integrator
    -> formUnbalance / formTangent
    -> KINSOL nonlinear iteration
    -> SUNLinearSolver_OpenSees
    -> LinearSOE::solve
    -> active OpenSees system
```

No SUNDIALS sparse matrix or native KLU, SuperLU, or Krylov linear solver is
used. Changing only the OpenSees system changes the linear solver used by
KINSOL:

```matlab
ops.system("UmfPack");
ops.algorithm("KINSOL", "-strategy", "lineSearch");
```

The same algorithm can instead use cuDSS:

```matlab
ops.system("CuDSS");
ops.algorithm("KINSOL", "-strategy", "lineSearch");
```

## Basic usage

Configure the model and the ordinary OpenSees analysis components first:

```matlab
ops.constraints("Transformation");
ops.numberer("RCM");
ops.system("UmfPack");
ops.test("NormUnbalance", 1.0e-8, 40, 0);

ops.algorithm("KINSOL", ...
    "-strategy", "lineSearch", ...
    "-jacobian", "adaptive", ...
    "-fnormTol", 1.0e-8, ...
    "-maxIter", 40);

ops.integrator("LoadControl", 0.02);
ops.analysis("Static");
ok = ops.analyze(50);
```

The `ops.test` object is retained for compatibility if the analysis later
switches back to a native OpenSees algorithm. **It does not drive KINSOL's
nonlinear iterations.**

For transient analysis, only the integrator and analysis type change:

```matlab
ops.integrator("Newmark", 0.5, 0.25);
ops.analysis("Transient");
ok = ops.analyze(1000, 0.01);
```

KINSOL callbacks never commit the Domain. Successful commit and failed-step
revert remain the responsibility of the surrounding OpenSees analysis.

## Command syntax

The shortest form selects Newton line search, adaptive tangent refresh, and
automatic final validation:

```matlab
ops.algorithm("KINSOL");
```

Options are passed as ordinary OpenSees-style name/value arguments:

```matlab
ops.algorithm("KINSOL", ...
    "-strategy", "lineSearch", ...
    "-jacobian", "adaptive", ...
    "-fnormTol", 1.0e-8, ...
    "-stepTol", 1.0e-12, ...
    "-maxIter", 40);
```

### Parameter reference

| Option | Default | Meaning |
|---|---:|---|
| `-strategy newton\|lineSearch\|picard` | `lineSearch` | Nonlinear iteration strategy |
| `-jacobian exact\|modified\|adaptive` | `adaptive` | OpenSees tangent refresh policy |
| `-maxIter n` | `30` | Maximum KINSOL nonlinear iterations per analysis step |
| `-fnormTol value` | `1e-8` | KINSOL scaled function-norm tolerance |
| `-stepTol value` | `1e-12` | KINSOL scaled step-length tolerance |
| `-maxNewtonStep value` | KINSOL default | Maximum scaled Newton step; `0` leaves the KINSOL default |
| `-maxBetaFailures n` | `10` | Maximum line-search beta-condition failures |
| `-validation residual\|step\|either\|both\|none` | automatic | Final OpenSees acceptance rule; `Penalty` selects `step`, other handlers select `residual` |
| `-validationResidualTol value` | `fnormTol` | Tolerance for the re-formed, unscaled OpenSees residual |
| `-validationStepTol value` | `stepTol` | Tolerance for final KINSOL scaled step validation |
| `-maxSetupCalls n` | `10` | Maximum nonlinear iterations between full tangent setups in adaptive mode |
| `-maxSubSetupCalls n` | `5` | Maximum iterations between residual-monitoring sub-setups |
| `-residualMonitor on\|off` | `on` | Enable KINSOL residual monitoring for tangent refresh |
| `-resMonMin value` | KINSOL default | Minimum residual-monitoring parameter |
| `-resMonMax value` | KINSOL default | Maximum residual-monitoring parameter |
| `-resMonConstant value` | KINSOL default | Constant residual-monitoring parameter |
| `-anderson depth` | `0` | Anderson history depth; only valid with Picard |
| `-andersonDelay n` | `0` | Picard iterations before Anderson acceleration begins |
| `-andersonOrth mgs\|icwy\|cgs2\|dcgs2` | `mgs` | Anderson QR orthogonalization method |
| `-damping value` | `1.0` | Picard damping, with `0 < value <= 1` |
| `-andersonDamping value` | `1.0` | Anderson-accelerated update damping |
| `-returnNewest on\|off` | `on` | Return the newest KINSOL iterate on termination |
| `-solutionScale vector` | all ones | Equation-wise solution scaling |
| `-solutionScaleValue value` | `1.0` | Broadcast solution scaling value |
| `-residualScale vector` | all ones | Equation-wise residual scaling |
| `-residualScaleValue value` | `1.0` | Broadcast residual scaling value |
| `-incrementConstraints vector` | none | KINSOL sign constraints on cumulative corrections |
| `-verbosity 0\|1\|2` | `0` | Silent, final summary, or detailed residual/tangent output |
| `-printStats` | off | Print a final statistics summary |

`exact` overrides `-maxSetupCalls` to one. `modified` retains the tangent for
the current solve and disables residual-monitor-triggered refresh. Anderson
depth must be smaller than `maxIter`.

## Nonlinear strategies

| Command | KINSOL strategy | Description |
|---|---|---|
| `-strategy newton` | `KIN_NONE` | Basic Newton iteration |
| `-strategy lineSearch` | `KIN_LINESEARCH` | Newton with globalization; default |
| `-strategy picard` | `KIN_PICARD` | Picard iteration using the OpenSees tangent and linear system |

Fixed-point mode is not available. `KIN_FP` requires an explicit fixed-point
map \(G(u)\), while the OpenSees incremental-integrator interface defines a
residual, tangent, and update operation rather than a general \(G(u)\).

### Newton

Use exact Newton as a direct comparison with the native OpenSees algorithm:

```matlab
ops.algorithm("KINSOL", ...
    "-strategy", "newton", ...
    "-jacobian", "exact");
```

### Newton line search

Line search is the recommended starting point for a model in which a full
Newton step crosses a sharp stiffness transition:

```matlab
ops.algorithm("KINSOL", ...
    "-strategy", "lineSearch", ...
    "-jacobian", "adaptive");
```

Rejected line-search points remain OpenSees trial states. The callback moves
the Domain between arbitrary KINSOL points with incremental updates and never
commits rejected material or element history.

### Picard and Anderson acceleration

```matlab
ops.algorithm("KINSOL", ...
    "-strategy", "picard", ...
    "-jacobian", "modified", ...
    "-anderson", 4, ...
    "-andersonDelay", 1, ...
    "-andersonOrth", "mgs", ...
    "-damping", 0.8, ...
    "-andersonDamping", 1.0);
```

Picard can reduce tangent factorizations when the nonlinearity is moderate,
but usually converges more slowly than Newton when stiffness changes sharply.
Anderson acceleration combines recent Picard updates. Inequality constraints
are not supported by KINSOL in Picard mode.

## Jacobian refresh

| Value | Behavior |
|---|---|
| `-jacobian exact` | Form the current OpenSees tangent every nonlinear iteration |
| `-jacobian modified` | Reuse the tangent during the current analysis step |
| `-jacobian adaptive` | Allow KINSOL residual monitoring to request a new tangent |

Additional refresh controls are available:

```matlab
"-maxSetupCalls", 10, ...
"-maxSubSetupCalls", 5, ...
"-residualMonitor", "on", ...
"-resMonMin", 1.0e-5, ...
"-resMonMax", 0.9, ...
"-resMonConstant", 0.9
```

Every tangent setup calls `IncrementalIntegrator::formTangent()`. Every linear
solve calls the currently linked `LinearSOE::solve()`.

## Convergence and final validation

KINSOL is the only nonlinear iteration controller. OpenSeesMatlab does not run
an OpenSees `ConvergenceTest` loop around KINSOL and does not call
`ConvergenceTest::test()` once after KINSOL returns. OpenSees displacement and
energy tests depend on iteration state that is not equivalent to KINSOL's
line-search state.

KINSOL has two principal stopping measures:

```matlab
"-fnormTol", 1.0e-8, ...  % scaled function norm
"-stepTol", 1.0e-12       % scaled step length
```

After KINSOL stops, OpenSeesMatlab can independently validate the final state:

| Validation | Acceptance rule |
|---|---|
| `residual` | Re-form and check the unscaled OpenSees residual; default for ordinary handlers |
| `step` | Accept an explicit residual root or a sufficiently small KINSOL scaled step |
| `either` | Accept when the final residual or step check passes |
| `both` | Require both checks |
| `none` | Accept only `KIN_SUCCESS` or `KIN_INITIAL_GUESS_OK` |

```matlab
ops.algorithm("KINSOL", ...
    "-validation", "residual", ...
    "-validationResidualTol", 1.0e-8, ...
    "-validationStepTol", 1.0e-12);
```

This validation is one final calculation, not a second nonlinear iteration
loop. In particular, it prevents a stalled `KIN_STEP_LT_STPTOL` result from
being committed merely because the KINSOL return code is nonnegative.

### Penalty constraints

Penalty constraints add terms proportional to a large penalty number. The
resulting equation residual can be dominated by penalty forces and may no
longer provide a useful physical force norm.

```matlab
ops.constraints("Penalty", 1.0e16, 1.0e16);
ops.algorithm("KINSOL", ...
    "-strategy", "lineSearch", ...
    "-stepTol", 1.0e-10);
```

When the active handler is `Penalty` and `-validation` is omitted,
OpenSeesMatlab automatically selects step validation. An explicit choice always
wins:

```matlab
ops.algorithm("KINSOL", ...
    "-validation", "step", ...
    "-validationStepTol", 1.0e-10);
```

Step validation accepts an exact KINSOL residual root because KINSOL stops
immediately at such a point and cannot be asked to perform an additional zero
increment without introducing a second nonlinear loop. Otherwise, a
`KIN_STEP_LT_STPTOL` result must satisfy the requested step tolerance.

For `Lagrange` or another formulation with an unsuitable residual scale, select
step validation explicitly and verify the constraint error separately.

### Energy convergence

`-validation energy` is intentionally rejected. A correct energy increment
requires

\[
\frac{1}{2}\left|\Delta u_{accepted}^{T}R\right|.
\]

KINSOL does not expose the complete accepted line-search or Anderson step
vector. `LinearSOE::getX()` contains a linear correction direction and is not
generally the accepted step. Using it would give an incorrect EnergyIncr value.

## Scaling

Solution and residual scaling can be supplied by equation:

```matlab
ops.algorithm("KINSOL", ...
    "-solutionScale", solutionScale, ...
    "-residualScale", residualScale);
```

The vectors must have the current OpenSees equation count. Broadcast scalars
are also available:

```matlab
"-solutionScaleValue", 1.0, ...
"-residualScaleValue", 0.01
```

Use solution scaling when translational and rotational corrections have
substantially different magnitudes. Scaling changes KINSOL's internal norms;
the reported `finalOpenSeesResidualNorm` remains unscaled.

## Inequality constraints

KINSOL constraint values apply to the cumulative correction from the OpenSees
integrator predictor, not to absolute nodal displacement:

| Value | Correction constraint |
|---:|---|
| `0` | none |
| `1` | nonnegative |
| `-1` | nonpositive |
| `2` | strictly positive |
| `-2` | strictly negative |

```matlab
ops.algorithm("KINSOL", ...
    "-incrementConstraints", constraintVector);
```

The vector follows the OpenSees equation-numbering order and is unrelated to
Penalty SP/MP constraint handling.

## Other controls

```matlab
ops.algorithm("KINSOL", ...
    "-maxIter", 50, ...
    "-maxNewtonStep", 1.0, ...
    "-maxBetaFailures", 10, ...
    "-returnNewest", "on", ...
    "-verbosity", 1);
```

`-verbosity 0` is silent, `1` prints a final summary, and `2` also prints
residual evaluations and tangent setups. `-printStats` retains the final-summary
behavior for compatibility.

## Solver statistics

Statistics for the most recent KINSOL step are returned as a MATLAB structure:

```matlab
stats = ops.call("kinsolStats");
reason = ops.call("kinsolReturnReason");
```

Important fields include:

| Field | Meaning |
|---|---|
| `nonlinearIterations` | KINSOL nonlinear iterations |
| `residualEvaluations` | residual callback evaluations |
| `tangentEvaluations` | OpenSees tangent formations |
| `linearSetupCalls` | SUNLinearSolver setup calls |
| `linearSolves` | OpenSees `LinearSOE::solve()` calls |
| `lineSearchBacktracks` | line-search backtracks |
| `betaConditionFailures` | beta-condition failures |
| `finalResidualNorm` | KINSOL function norm |
| `finalOpenSeesResidualNorm` | re-formed, unscaled OpenSees residual norm |
| `finalStepNorm` | KINSOL scaled step length |
| `validationPassed` | final acceptance status |
| `validationMode` | `0=residual`, `1=step`, `2=either`, `3=both`, `4=none` |
| `returnCode` | numeric KINSOL return code |

## Domain changes and failed steps

KINSOL resources are recreated when the equation count, integrator, or linked
`LinearSOE` changes. Replacing the system on an existing analysis is supported:

```matlab
ops.system("UmfPack");
ok = ops.analyze(1);

ops.system("CuDSS");
ok = ops.analyze(1);
```

OpenSees does not permit the constraint handler or numberer to be replaced
while an analysis object exists. Preserve the Domain and rebuild the analysis:

```matlab
ops.wipeAnalysis();
ops.constraints("Transformation");
ops.numberer("RCM");
ops.system("UmfPack");
ops.test("NormUnbalance", 1.0e-8, 40);
ops.algorithm("KINSOL");
ops.integrator("LoadControl", 0.02);
ops.analysis("Static");
```

If KINSOL fails, the surrounding OpenSees analysis reverts the Domain to its
last committed state. The failed step can be retried after changing algorithm
options or replacing the algorithm.

## Choosing a strategy

| Situation | Starting point |
|---|---|
| Native Newton already converges in a few iterations | Keep native `Newton` as the baseline |
| Full Newton steps cross stiffness transitions | KINSOL line search with adaptive Jacobian |
| Tangent factorization dominates and nonlinearity is moderate | Picard with Anderson |
| Penalty constraints distort the force norm | Step validation and solution scaling |
| Snap-through or snap-back | Change the OpenSees integrator or continuation method; algorithm replacement alone is insufficient |
