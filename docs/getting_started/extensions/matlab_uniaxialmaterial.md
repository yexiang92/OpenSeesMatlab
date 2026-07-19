# MATLAB-Defined Uniaxial Material

!!! note

    `MatlabUniaxialMaterial` is an OpenSeesMatlab extension. It is not a native
    OpenSees material type and requires the OpenSeesMATLAB MEX module.

`MatlabUniaxialMaterial` lets a MATLAB function implement the stress, tangent,
and history evolution of an ordinary OpenSees `UniaxialMaterial`. Once created,
it can be assigned to `zeroLength`, truss, section, bearing, and other OpenSees
objects that accept a uniaxial material.

## Create a material

Use the normal [`ops.uniaxialMaterial`][ops.OpenSeesMatlabCmds.uniaxialMaterial]
command:

```matlab
initialState = struct(...);

ops.uniaxialMaterial( ...
    "MatlabUniaxialMaterial", ...
    materialTag, ...
    @materialCallback, ...
    initialState, ...
    initialTangent);
```

The MATLAB wrapper recognizes `MatlabUniaxialMaterial` and routes it to the
internal MEX `extensionMaterial` dispatcher. Native material types such as
`Elastic` and `Steel01` continue to use the upstream OpenSees material factory.

## Callback contract

```matlab
function [response, trialState, status] = ...
    materialCallback(action, trial, committedState)
```

The MEX calls MATLAB only for `init` and `trial`:

| Action | Purpose |
| --- | --- |
| `init` | Establish the initial stress, tangent, and MATLAB state |
| `trial` | Evaluate a candidate response from the last committed state |

`response` must contain finite scalar doubles:

```matlab
response.stress = stress;
response.tangent = tangent;
```

An optional viscous tangent can also be returned:

```matlab
response.dampTangent = dampTangent;
```

A zero `status` accepts the callback evaluation. A nonzero value makes the
material evaluation fail.

The `trial` struct provides:

| Field | Meaning |
| --- | --- |
| `strain` | Current trial strain or element deformation |
| `strainRate` | Current trial strain rate |
| `committedStrain` | Strain at the last accepted step |
| `committedStrainRate` | Strain rate at the last accepted step |
| `committedStress` | Stress at the last accepted step |
| `committedTangent` | Tangent at the last accepted step |
| `materialTag` | OpenSees material tag |
| `callId` | MATLAB callback evaluation counter |
| `committedRevision` | Committed-state revision counter |
| `action` | `init` or `trial` |

## Complete linear example

The following example creates a linear callback material, assigns it to a
`zeroLength` element, and solves one static load step. Notice that
`initialState`, `committedState`, and `trialState` always use the same fields.

```matlab
clc; clear;

opsMAT = OpenSeesMatlab();
ops = opsMAT.opensees;
ops.wipe();
cleanup = onCleanup(@() ops.wipe()); %#ok<NASGU>

%% Material state
% Define the complete state schema before creating the material. The callback
% updates field values, but it does not add or remove fields.
K = 1000.0;
initialState = struct( ...
    "K", K, ...
    "lastStrain", 0.0, ...
    "trialEvaluationCount", 0);

%% Model and callback material
ops.model("basic", "-ndm", 1, "-ndf", 1);
ops.node(1, 0.0);
ops.node(2, 0.0);
ops.fix(1, 1);

ops.uniaxialMaterial( ...
    "MatlabUniaxialMaterial", ...
    1, ...                       % material tag
    @linearCallback, ...         % MATLAB constitutive callback
    initialState, ...            % complete initial history state
    K);                          % initial tangent

% zeroLength creates and owns a copy of material 1.
ops.element("zeroLength", 1, 1, 2, ...
    "-mat", 1, "-dir", 1);

%% Unit static load
ops.timeSeries("Linear", 1);
ops.pattern("Plain", 1, 1);
ops.load(2, 1.0);

ops.constraints("Plain");
ops.numberer("Plain");
ops.system("BandGeneral");
ops.test("NormDispIncr", 1.0e-12, 10);
ops.algorithm("Newton");
ops.integrator("LoadControl", 1.0);
ops.analysis("Static");

status = ops.analyze(1);
assert(status == 0);

% For K=1000 and P=1, the exact displacement is P/K=0.001.
displacement = ops.nodeDisp(2, 1);
force = ops.eleResponse(1, "material", 1, "stress");
assert(abs(displacement - 0.001) < 1.0e-12);
assert(abs(force - 1.0) < 1.0e-12);

ops.wipe();

%% Constitutive callback
function [response, trialState, status] = ...
    linearCallback(action, trial, committedState)

% Start from a copy of accepted history on every call. Never start from a
% previous trial evaluation because Newton may abandon that trial.
trialState = committedState;
status = 0;

switch action
    case "init"
        % initialState already contains every required field. Keep the schema
        % unchanged and return the zero-strain initial response.
        trialState.lastStrain = trial.strain;
        trialState.trialEvaluationCount = 0;

    case "trial"
        % This is candidate history. C++ commits it only after OpenSees accepts
        % the analysis step.
        trialState.lastStrain = trial.strain;
        trialState.trialEvaluationCount = ...
            committedState.trialEvaluationCount + 1;

    otherwise
        % Current versions call MATLAB only for init and trial.
        status = -1;
end

% A linear law has no path dependence, but response is still evaluated from
% the supplied trial strain and the state-owned stiffness.
response = struct( ...
    "stress", committedState.K * trial.strain, ...
    "tangent", committedState.K);
end
```

### Keep one state schema

Use the same field names and compatible MATLAB types in all three states:

| State | Example fields |
| --- | --- |
| `initialState` | `K`, `lastStrain`, `trialEvaluationCount` |
| `committedState` | `K`, `lastStrain`, `trialEvaluationCount` |
| `trialState` | `K`, `lastStrain`, `trialEvaluationCount` |

This is especially important for `revertToStart()`: C++ restores the original
`initialState` supplied when the material was created. If the callback adds a
required field only during `init`, that field will be absent after a reset.
Define the complete state schema in `initialState`, then update values without
changing its structure.

### State progression

Suppose the committed state is `S0`. Newton may evaluate several trial strains:

```text
trial strain e1 + S0 -> candidate S1  (rejected)
trial strain e2 + S0 -> candidate S2  (rejected)
trial strain e3 + S0 -> candidate S3  (accepted)
```

Every candidate starts from `S0`; `S1` must not be used to calculate `S2`.
After convergence, C++ executes:

```text
committedState = S3
```

If the step fails, C++ discards the candidate and restores `S0` without calling
MATLAB.

## History-dependent callback rule

Always derive candidate history from `committedState`:

```matlab
trialState = committedState;
trialState.plasticStrain = committedState.plasticStrain + deltaPlasticStrain;
```

Do not accumulate history in `persistent` or global variables during trial
evaluations. Newton's method may evaluate several candidates before accepting a
step. Only the state returned by the accepted trial is committed.

The C++ material follows the standard OpenSees trial/commit model:

```text
setTrialStrain        MATLAB evaluates response and candidate state
commitState           C++ copies trial response/state to committed storage
revertToLastCommit    C++ restores the last committed response/state
revertToStart         C++ restores the initial response/state
destructor            C++ releases data without calling MATLAB
```

Commit, rollback, reset, and destruction do not enter MATLAB. This prevents
script-cleanup re-entry and reduces callback overhead.

## Use the material in a zero-length element

```matlab
ops.model("basic", "-ndm", 1, "-ndf", 1);
ops.node(1, 0.0);
ops.node(2, 0.0);
ops.fix(1, 1);

ops.uniaxialMaterial( ...
    "MatlabUniaxialMaterial", 1, ...
    @materialCallback, initialState, initialTangent);

ops.element("zeroLength", 1, 1, 2, ...
    "-mat", 1, "-dir", 1);
```

For a cyclic pushover, define a unit reference load and control the node with
`DisplacementControl`:

```matlab
ops.timeSeries("Linear", 1);
ops.pattern("Plain", 1, 1);
ops.load(2, 1.0);

increment = targetDisp(step + 1) - targetDisp(step);
ops.integrator("DisplacementControl", ...
    2, 1, increment, 1, increment, increment);
```

Passing the same value as the requested, minimum, and maximum increment prevents
OpenSees from adaptively changing the prescribed cyclic path.

## Query responses

`MatlabUniaxialMaterial` inherits `UniaxialMaterial::setResponse` and
`UniaxialMaterial::getResponse`. Standard element material queries therefore
work without a custom recorder implementation:

```matlab
stress = ops.eleResponse(1, "material", 1, "stress");
tangent = ops.eleResponse(1, "material", 1, "tangent");
strain = ops.eleResponse(1, "material", 1, "strain");
stressStrain = ops.eleResponse(1, "material", 1, "stressStrain");
```

These functions return the current trial response. Immediately after a
successful `ops.analyze(1)`, trial and committed responses are identical. After
an analysis failure, OpenSees reverts the trial response to the preceding
committed response.

## Performance

Crossing from C++ into MATLAB is much more expensive than evaluating a native
OpenSees material. The implementation reduces this cost by:

- calling MATLAB only for `init` and `trial`;
- caching repeated requests with the same strain, strain rate, and committed
  revision;
- performing commit and rollback entirely in C++.

For good performance, keep callbacks small, return scalar numeric response
fields, avoid graphics or file access inside callbacks, and use only as many
cyclic increments as needed to resolve the response.

## Limitations

- MATLAB function handles and arbitrary MATLAB states cannot be serialized
  through an OpenSees `Channel`; distributed-process material transfer is not
  supported.
- Do not call `ops.analyze`, change the model, or replace the solution algorithm
  from inside a material callback. Handle failed steps in the outer MATLAB
  analysis loop.
- The inherited `plasticStrain` response is the OpenSees approximation
  `strain - stress/initialTangent`; it is not a direct view of a callback state
  field. Store and post-process specialized history variables separately when
  their exact values are required.

## Complete tutorials

[Extensions Examples](../../examples/extension/index.md){ .md-button .md-button--primary }
