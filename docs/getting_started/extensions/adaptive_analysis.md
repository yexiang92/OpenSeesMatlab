# Adaptive Analysis Recovery

!!! note

    `adaptiveAnalyze` is an OpenSeesMatlab extension, not a native OpenSees
    command. Configure the model and analysis in the usual way, then call
    [`adaptiveAnalyze`][ops.OpenSeesMatlabCmds.adaptiveAnalyze] instead of
    `analyze`.

`adaptiveAnalyze` runs one analysis attempt at a time. A converged step advances
the analysis normally. If a step fails, the command can increase the convergence
test iteration limit, switch algorithms or tests, and reduce only the failed
step. Each attempt starts from the last committed domain state.

## Quick start

Build the model and configure the OpenSees analysis as usual. Replace the final
`ops.analyze(...)` call with `ops.adaptiveAnalyze(...)`.

The simplest calls are:

```matlab
% Static analysis
ok = ops.adaptiveAnalyze(numSteps);

% Fixed-step transient analysis
ok = ops.adaptiveAnalyze(numSteps, dt);

% Variable transient analysis
ok = ops.adaptiveAnalyze(numSteps, dt, ...
    "-variableTransient", dtMin, dtMax, Jd);
```

With no optional recovery groups, all recovery strategies are off. The command
behaves like ordinary `analyze`, except that it advances one step at a time so
it can report the final result. It does not change the algorithm, convergence
test, or step size.

The return value is `0` when the full requested analysis completes. Always
check it in a script:

```matlab
ok = ops.adaptiveAnalyze(100);
if ok ~= 0
    error("Adaptive analysis failed with code %d.", ok);
end
```

For a nonlinear analysis, this is a practical starting configuration:

```matlab
ok = ops.adaptiveAnalyze(numSteps, ...
    "-iterations", 3, 100, ...
    "-algorithms", "KrylovNewton", "Newton", ...
    "-subdivision", 0.5, abs(initialStep) * 1e-6, 10);
```

This first allows more iterations, then tries the listed algorithms, and
finally divides only the failed step. The accepted substeps still complete the
original target; the command does not skip the unfinished part. Treat these
values as a starting point rather than a universal setting.

### Static example

For static analysis, configure the integrator as usual. `LoadControl` and
`DisplacementControl` increments can be recovered and subdivided when the
`"-subdivision"` group is present.

```matlab
ops.test("NormDispIncr", 1e-8, 20, 0);
ops.algorithm("Newton");
ops.integrator("DisplacementControl", controlNode, controlDof, 1e-3);
ops.analysis("Static");

ok = ops.adaptiveAnalyze(200);
```

### Fixed-step transient example

```matlab
ops.test("NormDispIncr", 1e-8, 20, 0);
ops.algorithm("Newton");
ops.integrator("Newmark", 0.5, 0.25);
ops.analysis("Transient");

ok = ops.adaptiveAnalyze(1000, 0.01);
```

This requests `1000` steps of `0.01`, just like `ops.analyze(1000, 0.01)`.
Add the `"-subdivision"` group if failed outer steps should be completed using
smaller internal substeps.

### Variable transient example

```matlab
ops.test("NormDispIncr", 1e-8, 20, 0);
ops.algorithm("Newton");
ops.integrator("Newmark", 0.5, 0.25);
ops.analysis("VariableTransient");

ok = ops.adaptiveAnalyze(1000, 0.01, ...
    "-variableTransient", 1e-5, 0.02, 8);
```

Here `0.01` is the initial outer time step, `1e-5` and `0.02` are its allowed
minimum and maximum values, and `8` is the desired iteration count used to
choose the next outer time step. The total requested model-time increment is
`1000 * 0.01 = 10.0`.

### Customizing recovery

Add named parameter groups after the required arguments:

```matlab
ok = ops.adaptiveAnalyze(200, ...
    "-iterations", 3, 200, ...
    "-algorithms", "KrylovNewton", "Newton", ...
    "-subdivision", 0.5, 1e-7, 10, ...
    "-debug");
```

Writing `"-iterations"`, `"-algorithms"`, `"-tests"`, `"-subdivision"`, or
`"-debug"` enables that feature. There is no Boolean switch. Omit the complete
group to leave the feature disabled.

The rest of this guide explains the stepping behavior and every parameter in
detail.

### Which command should I use?

Use `ops.analyze` when the chosen step size and algorithm already converge
reliably. It has the least control overhead. Use `ops.adaptiveAnalyze` when a
long nonlinear run occasionally encounters a difficult step and you want a
repeatable recovery sequence. Adaptive recovery cannot repair an unstable
model, missing constraint, unsuitable material parameters, or inconsistent
units; repeated failure at the minimum step is a reason to inspect the model.

## Detailed analysis modes

The command follows the analysis type selected by `ops.analysis`:

| Analysis type | Call | Step source |
| --- | --- | --- |
| `Static` | `ops.adaptiveAnalyze(numSteps, groups...)` | The configured `LoadControl` or `DisplacementControl` integrator |
| `Transient` | `ops.adaptiveAnalyze(numSteps, dt, groups...)` | The fixed outer step `dt` |
| `VariableTransient` | `ops.adaptiveAnalyze(numSteps, dt, "-variableTransient", dtMin, dtMax, Jd, groups...)` | A variable outer step initially equal to `dt` |

For `VariableTransient`, `numSteps * dt` is the requested total model-time
increment. The actual number of accepted outer steps can differ because the
outer time step varies.

The `"-variableTransient"` group is required for `VariableTransient` and is
rejected for other analysis types. It has no enable switch because
`ops.analysis("VariableTransient")` already selects the mode.

## Outer steps and failed-step subdivision

Outer step selection and inner recovery operate at different levels:

1. The command selects one outer target step.
2. It attempts that step using the current user configuration.
3. If necessary, recovery strategies retry or subdivide that target.
4. The next outer step is selected only after the entire current target has
   been completed.

Consequently, subdivision does not discard the remainder of a step. For
example, if a static increment of `0.1` is reduced to `0.05`, both accepted
substeps must add up to the original `0.1` target. If the remaining `0.05`
fails, it is recovered and subdivided in the same way.

For static analysis, outer step adaptation follows the optional
`numIter`, `minIncr`, and `maxIncr` values of the configured integrator:

```matlab
ops.integrator("LoadControl", lambda, numIter, minLambda, maxLambda);
ops.integrator("DisplacementControl", nodeTag, dof, increment, ...
    numIter, minIncrement, maxIncrement);
```

Static analysis without subdivision can use the same integrators as ordinary
`analyze`. Static failed-step subdivision currently supports only
`LoadControl` and `DisplacementControl`. When subdivision is enabled, the
command temporarily recreates the selected integrator with a smaller recovery
step, then restores the user's outer integrator configuration after the
attempt.

For `VariableTransient`, `dtMin`, `dtMax`, and `Jd` control the next outer time
step using the iteration demand of the last accepted outer step. Inner
subdivision remains independent and only helps complete the current outer
target.

## Recovery groups

Options use named groups followed by positional values:

| Group | Values | Default | Purpose |
| --- | --- | --- | --- |
| `"-iterations"` | `multiplier, maxIterations` | Disabled | Retry with a larger convergence-test iteration limit |
| `"-algorithms"` | `algorithmSpec...` | Disabled | Try fallback solution algorithms in order |
| `"-tests"` | `testSpecs` | Disabled | Try alternate convergence tests |
| `"-subdivision"` | `reduction, minStep, maxSubdivisions` | Disabled | Reduce the current failed target |
| `"-variableTransient"` | `dtMin, dtMax, Jd` | Required for `VariableTransient` | Control variable outer time stepping |
| `"-limits"` | `maxRecoveryAttempts` | `1000` | Limit real analysis attempts for one outer target |
| `"-debug"` | No following value | Disabled | Print every recovery attempt |
| `"-log"` | `filePath` | Disabled | Write attempt records to a CSV file |

The presence of a group enables it. To disable a strategy, omit that complete
group. Suggested values are `"-iterations", 3, 200` and
`"-subdivision", 0.5, abs(initialStep)*1e-6, 10`. A commonly useful algorithm
order is `"-algorithms", "KrylovNewton", "Newton"`.

`minStep` and `maxSubdivisions` are independent safeguards and both apply.
Recovery stops when another reduction would violate `minStep`, when the
subdivision depth reaches `maxSubdivisions`, or when the attempt limit is
reached.

### Algorithm specifications

Algorithms without arguments can be supplied as consecutive strings:

```matlab
ok = ops.adaptiveAnalyze(100, ...
    "-algorithms", "KrylovNewton", "Newton");
```

Use an outer cell array when an algorithm has arguments. Each inner cell is one
complete `algorithm` command:

```matlab
fallbackAlgorithms = { ...
    {"KrylovNewton", "-maxDim", 20}, ...
    {"Newton"}};

ok = ops.adaptiveAnalyze(100, ...
    "-algorithms", fallbackAlgorithms);
```

This cell form prevents an algorithm option from being mistaken for another
adaptive-analysis group.

### Convergence-test specifications

Each fallback test is one cell containing the test name, tolerance, maximum
iterations, and print flag:

```matlab
fallbackTests = { ...
    {"NormDispIncr", 1e-8, 100, 0}, ...
    {"EnergyIncr",   1e-10, 100, 0}};

ok = ops.adaptiveAnalyze(100, "-tests", fallbackTests);
```

## Detailed examples

### Displacement-controlled static analysis

```matlab
ops.test("NormDispIncr", 1e-8, 20, 0);
ops.algorithm("Newton");
ops.integrator("DisplacementControl", controlNode, controlDof, 1e-3, ...
    8, 1e-5, 2e-3);
ops.analysis("Static");

ok = ops.adaptiveAnalyze(200, ...
    "-iterations", 3, 200, ...
    "-algorithms", "KrylovNewton", "Newton", ...
    "-subdivision", 0.5, 1e-7, 10);
```

The displacement increment is the outer target. If it fails, the command
completes that same displacement target through smaller increments before
moving to the next one.

### Fixed-step transient analysis

```matlab
ops.test("NormDispIncr", 1e-8, 20, 0);
ops.algorithm("Newton");
ops.integrator("Newmark", 0.5, 0.25);
ops.analysis("Transient");

ok = ops.adaptiveAnalyze(1000, 0.01, ...
    "-algorithms", "KrylovNewton", "Newton", ...
    "-subdivision", 0.5, 1e-6, 10);
```

The requested outer step remains `0.01`. A failed step may be completed using
smaller inner substeps without changing the next fixed outer target.

### Variable transient analysis

```matlab
ops.test("NormDispIncr", 1e-8, 20, 0);
ops.algorithm("Newton");
ops.integrator("Newmark", 0.5, 0.25);
ops.analysis("VariableTransient");

ok = ops.adaptiveAnalyze(1000, 0.01, ...
    "-variableTransient", 1e-5, 0.02, 8, ...
    "-algorithms", "KrylovNewton", "Newton", ...
    "-subdivision", 0.5, 1e-6, 10, ...
    "-limits", 1000);
```

Here the requested total model-time increment is `10.0`. `dtMin`, `dtMax`, and
`Jd` control future outer steps; failed-step subdivision still operates only
inside the current outer target.

## Configuration restoration and output

After every successful or failed attempt, the command restores the user's
algorithm, convergence test, and static integrator configuration. Recovery
settings therefore do not leak into the next normal attempt or a later
analysis command.

With `"-debug"`, each algorithm switch, iteration-limit change, test
change, and subdivision is printed with the `adaptiveAnalyze::` prefix. A final
success or failure summary is always printed, even when debug output is off.
The summary includes wall-clock analysis time and the available convergence
norm information.

CSV logging records each attempt, including `timeStart`, `timeEnd`,
`targetTime`, `remainingTime`, `stageID`, and `successFlag`. These are OpenSees
Domain values and are different from the summary's wall-clock duration.

Use logging while tuning a model:

```matlab
ok = ops.adaptiveAnalyze(numSteps, ...
    "-subdivision", 0.5, minStep, 10, ...
    "-log", "adaptive_attempts.csv", ...
    "-debug");
```

After the settings are stable, remove `"-debug"` to keep the command window
readable. The CSV file can remain enabled when an attempt history is useful.

Check the return value in scripts:

```matlab
if ok ~= 0
    error("Adaptive analysis failed with code %d.", ok);
end
```
