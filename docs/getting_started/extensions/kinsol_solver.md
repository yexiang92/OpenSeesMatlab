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
    "-method", "lineSearch", ...
    "-tol", 1.0e-8);

ops.integrator("LoadControl", 0.02);
ops.analysis("Static");
ok = ops.analyze(50);
```

The `ops.test` object supplies the default iteration limit. It is also retained
for compatibility if the analysis later switches back to a native OpenSees
algorithm. It does not create a second iteration loop around KINSOL.

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
KINSOL's own convergence test:

```matlab
ops.algorithm("KINSOL");
```

For most models, select one method and one tolerance:

```matlab
ops.algorithm("KINSOL", "-method", "newton",    "-tol", 1.0e-8);
ops.algorithm("KINSOL", "-method", "lineSearch", "-tol", 1.0e-8);
ops.algorithm("KINSOL", "-method", "modified",  "-tol", 1.0e-8);
ops.algorithm("KINSOL", "-method", "picard",    "-tol", 1.0e-8);
```

The presets mean exact-Jacobian Newton, adaptive-Jacobian Newton line search,
modified Newton, and damped Picard with Anderson acceleration respectively.
`-tol` sets the KINSOL function-norm tolerance. The maximum iteration count inherits the active
`ops.test`; specify `-maxIter` only when KINSOL needs a different limit.

The options below remain available for advanced tuning and override preset
values regardless of argument order.

Options are passed as ordinary OpenSees-style name/value arguments:

```matlab
ops.algorithm("KINSOL", ...
    "-strategy", "lineSearch", ...
    "-jacobian", "adaptive", ...
    "-funcNormTol", 1.0e-8, ...
    "-scaledStepTol", 1.0e-12, ...
    "-maxIter", 40);
```

### Parameter reference

| Option | Default | Meaning |
|---|---:|---|
| `-method newton\|lineSearch\|modified\|picard` | none | Recommended preset selecting a strategy and tangent policy |
| `-tol value` | none | Set the KINSOL function-norm tolerance |
| `-strategy none\|lineSearch\|picard` | `lineSearch` | Native KINSOL strategy; `KIN_NONE`, `KIN_LINESEARCH`, and `KIN_PICARD` are also accepted |
| `-jacobian exact\|modified\|adaptive` | `adaptive` | OpenSees tangent refresh policy |
| `-maxIter n` | active `test` limit | Maximum KINSOL nonlinear iterations per analysis step |
| `-testMode KINSOL\|OpenSees\|Hybrid` | `KINSOL` | KINSOL-only, final `NormUnbalance` test, or KINSOL plus final validation |
| `-funcNormTol value` | `1e-8` | KINSOL scaled function-norm tolerance; `-fnormTol` is an alias |
| `-scaledStepTol value` | `1e-12` | KINSOL scaled step-length tolerance; `-stepTol` is an alias |
| `-acceptStepTol on\|off` | `off` | Treat `KIN_STEP_LT_STPTOL` as an accepted approximate result |
| `-maxNewtonStep value` | KINSOL default | Maximum scaled Newton step; `0` leaves the KINSOL default |
| `-lineSearchRecovery on\|off` | `on` | Retry `KIN_LINESEARCH_NONCONV` once with full Newton from KINSOL's last retained iterate |
| `-maxBetaFailures n` | `10` | Maximum line-search beta-condition failures |
| `-validation residual\|step\|either\|both\|none` | handler-dependent | Final acceptance rule used only with `-testMode Hybrid` |
| `-validationResidualTol value` | `funcNormTol` | Hybrid tolerance for the re-formed, unscaled OpenSees residual |
| `-validationStepTol value` | `scaledStepTol` | Hybrid tolerance for final KINSOL scaled-step validation |
| `-maxSetupCalls n` | `10` | Maximum nonlinear iterations between full tangent setups in adaptive mode |
| `-maxSubSetupCalls n` | `5` | Maximum iterations between residual-monitoring sub-setups |
| `-adaptiveSizeThreshold n` | `256` | In adaptive mode, use the current tangent for systems no larger than this; `0` disables the size-based override |
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
| `-incrementConstraints vector` | none | KINSOL sign constraints on cumulative corrections; `-constraints` is a compatibility alias |
| `-verbosity 0\|1\|2` | `0` | Silent, final summary, or detailed residual/tangent output |
| `-collectStats` | off | Collect detailed counters for `algorithm("KINSOL", "-info")` without printing them |
| `-printStats` | off | Collect and print a final statistics summary |

`exact` overrides `-maxSetupCalls` to one. `modified` retains the tangent for
the current solve and disables residual-monitor-triggered refresh. When
`-maxIter` is omitted, KINSOL inherits
`ConvergenceTest::getMaxNumTests()`. Anderson depth must be smaller than an
explicit `maxIter`; KINSOL also validates its workspace when the equation size
is known.

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

KINSOL is always the only nonlinear iteration controller. By default, the
OpenSees `test` supplies only the maximum iteration count; its norm and
tolerance are not applied. KINSOL decides convergence from its own stopping
tests. `-testMode` optionally changes how the final result is accepted, but
never creates a second nonlinear iteration loop:

| Test mode | Behavior |
|---|---|
| `KINSOL` | Default; accept `KIN_SUCCESS` or `KIN_INITIAL_GUESS_OK` |
| `OpenSees` | After KINSOL stops, call the active `NormUnbalance` test once on the re-formed final residual |
| `Hybrid` | Require an admissible KINSOL termination and the selected final validation |

`Validated` remains accepted as a compatibility alias for `Hybrid`; use
`Hybrid` in new scripts.

For example, the tolerance in this test is unused by the default KINSOL mode,
while `40` becomes the default KINSOL iteration limit:

```matlab
ops.test("NormUnbalance", 1.0e-6, 40);
ops.algorithm("KINSOL", "-method", "lineSearch", ...
    "-funcNormTol", 1.0e-8);
```

`OpenSees` mode is an advanced final acceptance option and intentionally
supports `NormUnbalance` only. OpenSees
`NormDispIncr` and `EnergyIncr` require the last accepted nonlinear increment,
which KINSOL does not expose. Selecting either test with
`-testMode OpenSees` therefore fails explicitly instead of evaluating a
different quantity under the OpenSees test name. Use `Hybrid` with `step`,
`residual`, `either`, or `both` validation instead.

KINSOL has two principal stopping measures, matching
`KINSetFuncNormTol` and `KINSetScaledStepTol`:

```matlab
"-funcNormTol", 1.0e-8, ...   % scaled function norm
"-scaledStepTol", 1.0e-12     % scaled step length
```

Meeting the function-norm tolerance returns `KIN_SUCCESS` and is accepted.
Meeting only the scaled-step tolerance returns `KIN_STEP_LT_STPTOL`: the
iteration can no longer make a significant move, but the nonlinear equations
may still have a material residual. It is rejected by default. Use
`-acceptStepTol on` only when an approximate or stagnated solution is acceptable
and verify the reported residual separately.

With `-testMode Hybrid`, OpenSeesMatlab can independently validate the final
state after KINSOL stops:

| Validation | Acceptance rule |
|---|---|
| `residual` | Re-form and check the unscaled OpenSees residual; default for ordinary handlers |
| `step` | Accept an explicit residual root or a sufficiently small KINSOL scaled step |
| `either` | Accept when the final residual or step check passes |
| `both` | Require both checks |
| `none` | Accept only `KIN_SUCCESS` or `KIN_INITIAL_GUESS_OK` |

```matlab
ops.algorithm("KINSOL", ...
    "-testMode", "Hybrid", ...
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
    "-method", "lineSearch", ...
    "-funcNormTol", 1.0e-8);
```

For strongly heterogeneous penalty equations, provide a problem-specific
equation-wise `-residualScale` vector. A single global scale generally cannot
distinguish physical equilibrium equations from penalty equations.

If Hybrid validation is explicitly enabled, an active `Penalty` handler selects
step validation when `-validation` is omitted. An explicit choice always wins:

```matlab
ops.algorithm("KINSOL", ...
    "-testMode", "Hybrid", ...
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

Statistics for the most recent KINSOL step are returned through the same
`algorithm` command used to configure the solver:

```matlab
stats = ops.algorithm("KINSOL", "-info");
reason = stats.returnReason;
```

Core termination information is always populated. Add `-collectStats` when
you need detailed residual, tangent, linear-solve, or line-search counters
without console output.

Important fields include:

| Field | Meaning |
|---|---|
| `nonlinearIterations` | KINSOL nonlinear iterations |
| `iterationLimit` | Effective explicit or inherited nonlinear iteration limit |
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
| `testMode` | `0=KINSOL`, `1=OpenSees`, `2=Hybrid` |
| `openSeesTestResult` | Final `NormUnbalance` result in OpenSees mode; otherwise `-1` |
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

## Performance guidance

Use native OpenSees Newton as the timing and response baseline. KINSOL adds
nonlinear-solver control and trial-state synchronization, so it is most useful
when it saves tangent formations, factorizations, failed steps, or manual retry
logic. It is not expected to outperform a reliably converging full Newton
method on every model.

Recommended tuning order:

1. Start with `-strategy lineSearch -jacobian adaptive`
2. Keep the selected OpenSees `system` appropriate for the matrix size and hardware
3. Inspect tangent, linear-solve, residual, and backtrack statistics
4. Add solution or residual scaling when equation magnitudes differ substantially
5. Try modified Jacobian only when tangent formation/factorization dominates
6. Use Picard and Anderson only when the OpenSees update defines a useful Picard map

Exact Jacobian refresh is the reference configuration:

```matlab
ops.algorithm("KINSOL", ...
    "-strategy", "newton", ...
    "-jacobian", "exact");
```

It provides the closest comparison with OpenSees Newton but may form and
factor the tangent more often than necessary. Adaptive refresh can reduce that
cost when the tangent remains useful for several iterations. Modified refresh
can save still more factorizations, but stale tangents may increase residual
evaluations or cause line-search failures.

Line search trades additional residual evaluations for a larger convergence
region. It is beneficial when full Newton steps overshoot; it is overhead when
full steps are consistently accepted. A high `lineSearchBacktracks` count
usually indicates a poor local model, an excessive analysis increment, or
inadequate scaling.

KINSOL always delegates linear solves to the active OpenSees `LinearSOE`.
Changing from UmfPack to Mumps or CuDSS therefore changes the dominant linear
algebra cost without changing KINSOL. The bridge reuses its right-hand-side
workspace, and KINSOL resources are retained until the equation count,
integrator, or linked system changes.

The default KINSOL mode avoids an additional final OpenSees acceptance test.
Enable `Hybrid` only when an independent final check is required, then select
the validation rule to match the constraint handler. Hybrid residual validation
may require one additional OpenSees residual formation.

For meaningful timings, warm up MATLAB and the linear solver, exclude model
construction, repeat runs, and compare median time together with
`tangentEvaluations`, `linearSolves`, `residualEvaluations`, backtracks,
validation status, and response error.
