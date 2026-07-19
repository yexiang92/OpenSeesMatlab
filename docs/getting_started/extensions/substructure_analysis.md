# MATLAB Substructure Analysis

!!! note

    - This is an additional feature added to OpenSeesMatlab and is not a native OpenSees command.
    - Currently, it only supports numerical sub-models created within Matlab.
    - Any bugs or new request can be submitted as issues on GitHub.

[`matlabSubstructure`][ops.OpenSeesMatlabCmds.matlabSubstructure] lets an OpenSees model use a substructure calculated by a
MATLAB function. OpenSees treats it like an ordinary Element; when it needs the
Element force or tangent stiffness, it calls your MATLAB callback.

The MATLAB-side workflow is: write one callback, create the OpenSees interface
nodes, register the Element, and run the analysis. The complete example below
keeps those steps together so it can be copied directly.

## Decide what MATLAB and OpenSees each own

Treat `matlabSubstructure` as a condensed boundary Element:

| OpenSees | MATLAB callback |
| --- | --- |
| Owns the global nodes, constraints, loading and solution algorithm | Owns the internal substructure model behind the interface |
| Supplies trial interface displacement, velocity and acceleration | Converts that motion into interface force, tangent and optional mass/damping |
| Accepts or rejects Newton trials and time steps | Produces a candidate history state from the last accepted state |
| May own ground motion and support excitation | May instead own internal ground excitation, but must not duplicate it |

The command does not automatically condense a MATLAB model. Your callback must
already implement the map from interface motion to compatible interface force
and tangent. It must not start another OpenSees command from inside the callback.

## Complete example

First save this callback as `mySubstructure.m` somewhere on the MATLAB path:

```matlab
function [response, trialState, status] = ...
    mySubstructure(action, trial, committedState)
%MYSUBSTRUCTURE Two-boundary-DOF linear spring callback.
%
% OpenSees supplies the current interface motion in trial. The ordering of
% trial.disp is exactly the row ordering of interfacePairs used when the
% Element is created. This callback returns the resisting force in the same
% order and the derivative of that force with respect to trial.disp.
%
% committedState is the trialState returned for the last successfully
% committed step. It has the same callback-defined fields (K, disp, and time
% here); C++ stores and returns it without interpreting those fields. Never
% update persistent or global history on every "trial" call: Newton's method
% may call the callback several times before accepting one analysis step.

% A zero status tells the C++ Element that this action completed normally.
status = int32(0);

% Start each evaluation from accepted history. For this linear example the
% displacement and time fields are only diagnostic; K never changes.
trialState = committedState;

switch lower(string(action))
case {"init", "trial"}
    % "init" establishes the initial Element response. "trial" evaluates a
    % current OpenSees trial configuration. Both require force and tangent.
    K = committedState.K;

    % Internal resisting force: f = K*u. Do not add applied OpenSees nodal
    % loads here; OpenSees assembles external loads separately.
    response.force = K * trial.disp;

    % Consistent tangent: df/du = K. Its row and column ordering must match
    % interfacePairs. Returning the consistent tangent gives Newton's method
    % the linearization of response.force.
    response.tangent = K;

    if strcmpi(action, "init")
        % Optional initial matrix queried by getInitialStiff(). If omitted,
        % the K0 supplied to matlabSubstructure is used as the fallback.
        response.initialStiffness = K;
    end

    % This is candidate history only. C++ promotes it to committed history
    % after OpenSees calls the successful-step "commit" action.
    trialState.disp = trial.disp;
    trialState.time = trial.time;

case {"commit", "revert", "reverttostart", "shutdown"}
    % No response matrices are needed for lifecycle notifications in this
    % history-free model. The C++ layer owns commit/revert bookkeeping.
    response = struct();

otherwise
    % Reject an action that this callback does not understand.
    response = struct();
    status = int32(-1);
end
end
```

### How `committedState` is stored and advanced

**`committedState` is the previously committed `trialState`.** It therefore has
the same MATLAB type, structure, and user-defined fields as the `trialState`
returned by the callback. MATLAB determines all of those fields; C++ only
stores the returned value, passes it back on later calls, commits it after a
successful step, or restores it on revert. C++ neither adds fields nor
interprets their contents.

The first value comes from `initialState`: the successful `trialState` returned
by `init` becomes the first `committedState`. After that, each successful
analysis step promotes its accepted `trialState` to the next
`committedState`. A useful mental model is that the Element owns three MATLAB
values:

```text
initialState     original value passed to matlabSubstructure
committedState   MATLAB history at the last accepted OpenSees step
trialState       candidate MATLAB history for the current Newton trial
```

For example, suppose the last accepted state is `S0`. OpenSees may try several
displacements while solving the next step:

```text
trial call 1: callback("trial", trial1, S0) returns candidate S1a
trial call 2: callback("trial", trial2, S0) returns candidate S1b
trial call 3: callback("trial", trial3, S0) returns candidate S1c
commit:       accepted candidate S1c becomes the new committed state S1
next step:    every new trial receives S1, not S0
```

Notice that calls 2 and 3 receive `S0`, not `S1a` or `S1b`. A Newton trial is
only a proposal; accumulating history from one proposal into the next would
make the result depend on the number of solver iterations. The callback should
therefore calculate each candidate from its third input and return the result
as `trialState`:

```matlab
% Correct pattern for a history variable:
trialState = committedState;
trialState.plasticDisp = updatePlasticDisp( ...
    committedState.plasticDisp, trial.disp);
```

Do not increment a persistent variable or modify shared state on every trial:

```matlab
% Incorrect: Newton retries would permanently advance the history.
persistent plasticDisp
plasticDisp = updatePlasticDisp(plasticDisp, trial.disp);
```

The complete state transitions implemented by the Element are:

| Action | Third callback input | What C++ does with returned `trialState` |
| --- | --- | --- |
| `init` | Original `initialState` | Stores the returned value as both the initial working candidate and the first committed state. |
| `trial` | Current `committedState` | Stores the returned value as the latest candidate only. Repeated trials replace this candidate. |
| `commit` | Latest accepted candidate | If supported successfully, lets the callback finalize the candidate; C++ then copies that candidate to `committedState`. If unsupported, C++ commits the candidate unchanged. |
| `revert` | Current `committedState` | Ignores the returned state and replaces the candidate with `committedState`. |
| `revertToStart` | Original command `initialState` | Ignores the returned state and resets both stored states to the original command value. |
| `shutdown` | Last stored `committedState` | Uses the call only as a best-effort cleanup notification; returned state is ignored. |

The name `committedState` is exact during a `trial` call. During `commit`, the
same third argument position contains the accepted candidate so the callback
can optionally finalize it. This action-dependent meaning is why callback code
should normally branch on `action` before using the third input.

Use MATLAB value data such as structs, numeric arrays, cells, and tables for
rollback-safe history. Be careful with handle objects stored inside the state:
mutating a handle object in place can also change an earlier stored state,
because the states then refer to the same object. If a handle class is needed,
implement and use an explicit deep-copy operation before changing it.

Then run this script. It creates the package interface, builds a two-DOF
spring, applies a unit load, performs one static step, and reads the result:

```matlab
% Create the high-level OpenSeesMatlab object and obtain its OpenSees command
% interface. wipe() makes the example independent of any earlier model.
opsMAT = OpenSeesMatlab();
ops = opsMAT.opensees;
ops.wipe();

% 1. Data owned by the MATLAB substructure
% ------------------------------------------------------------
% This is the stiffness of one spring connecting two boundary DOFs:
%
%     f = K0*u = k*[u1-u2; u2-u1].
%
% K0 is singular before constraints are applied because rigid translation
% produces no spring deformation. Fixing node 1 below removes that mode.
k = 1000.0;
K0 = k * [1 -1; -1 1];

% initialState is owned by the MATLAB callback. Store model data and internal
% history here rather than in persistent/global variables. The callback will
% receive this value during initialization and the last committed value later.
state0 = struct("K", K0);

% 2. OpenSees model and interface nodes
% ------------------------------------------------------------
% A one-dimensional model with one translational DOF per node is sufficient
% for this two-ended axial spring. Both interface nodes must already exist
% when matlabSubstructure is called.
ops.model("basic", "-ndm", 1, "-ndf", 1);
ops.node(1, 0.0);
ops.node(2, 1.0);

% Node 1 represents the fixed end. Node 2 remains the only unknown DOF.
ops.fix(1, 1);

% Each row is [nodeTag, oneBasedDOF]. Row order defines the order of
% trial.disp, response.force, and the rows/columns of K0 and response.tangent.
% Thus the vectors used here are [u1; u2] and [f1; f2]. OpenSees DOF numbers
% are one-based, so DOF 1 is the axial translation in this model.
interfacePairs = [
    1 1
    2 1
];

% 3. Register the callback and create the OpenSees Element
% ------------------------------------------------------------
% The first five inputs are required positional arguments. tangentMode is an
% optional name-value setting. "matlab" tells OpenSees to use the current
% response.tangent returned by the callback during Newton iterations.
eleTag = 1001;
ops.matlabSubstructure(eleTag, ...
    @mySubstructure, state0, K0, interfacePairs, ...
    "tangentMode", "matlab");

% 4. Load and analysis
% ------------------------------------------------------------
% A Linear time series multiplied by a Plain pattern has factor 1.0 at the
% end of this LoadControl step. Therefore the final force at node 2 is 1.0.
ops.timeSeries("Linear", 1);
ops.pattern("Plain", 1, 1);
ops.load(2, 1.0);

% matlabSubstructure is an Element only; the usual OpenSees analysis objects
% must still be selected. This problem is linear, but Newton also verifies
% that the callback-provided tangent is usable by the nonlinear solution loop.
ops.constraints("Plain");
ops.numberer("Plain");
ops.system("BandGeneral");
ops.test("NormUnbalance", 1e-10, 10);
ops.algorithm("Newton");
ops.integrator("LoadControl", 1.0);
ops.analysis("Static");

% Always check the analyze return code before using response results. Zero
% means that OpenSees accepted and committed the requested step.
ok = ops.analyze(1);
if ok ~= 0
    error("OpenSees analysis failed with code %d.", ok);
end

% 5. Query and independently verify the response
% ------------------------------------------------------------
% With node 1 fixed, equilibrium gives u2 = P/k = 1/1000 = 0.001.
% The expected ordered interface resisting force is [-1; +1].
u2 = ops.nodeDisp(2, 1);
fInterface = ops.eleResponse(eleTag, "interfaceForce");
expectedU2 = 1.0 / k;
expectedForce = [-1.0; 1.0];

displacementError = abs(u2 - expectedU2);
forceError = norm(fInterface(:) - expectedForce, inf);
tolerance = 1e-10;
assert(displacementError < tolerance, ...
    "Unexpected node displacement; check the interface ordering and K0.");
assert(forceError < tolerance, ...
    "Unexpected interface force; check the callback force convention.");

% Print the compact verification summary in one call.
fprintf(['Linear substructure verification\n' ...
         '  u2:       %.12g (expected %.12g)\n' ...
         '  force:   [%.12g, %.12g]^T\n' ...
         '  max err: %.3e\n'], ...
    u2, expectedU2, fInterface(1), fInterface(2), ...
    max(displacementError, forceError));

% 6. Cleanup
% ------------------------------------------------------------
% Query all results before cleanup. wipe() removes the Element and lets it send
% its shutdown notification while the callback record still exists. Clear the
% callback registry only afterward.
ops.wipe();
ops.clearMatlabSubstructures();
```

`ok == 0` means the step succeeded. Check it before trusting the queried
results; `u2` should be about `0.001`. `"tangentMode"` is optional:
`"matlab"` uses the current tangent returned by MATLAB (the default), whereas
`"initial"` returns the Element's fixed initial stiffness whenever OpenSees
asks for its current tangent. That initial stiffness is
`response.initialStiffness` returned during `init`, or command `K0` when the
field is omitted. The wrapper validates the
tag, callback, dimensions, interface rows, and tangent mode before forwarding
the command to the MEX interface.

### `matlabSubstructure` inputs

The five inputs through `interfacePairs` are required positional arguments.
Optional settings follow as name-value pairs. Optional names are
case-insensitive but must be complete; an unknown or duplicate name, or a name
without a value, is an error.

| Input | Form | Value |
| --- | --- | --- |
| `eleTag` | required positional | Element and callback-registry tag. |
| `callback` | required positional | Callback function handle. |
| `initialState` | required positional | Initial MATLAB-owned history; any MATLAB value, including `[]`. |
| `initialStiffness` | required positional | Finite real N-by-N double matrix `K0`. |
| `interfacePairs` | required positional | N-by-2 double matrix of unique `[nodeTag, oneBasedDOF]` rows. |
| `"tangentMode"` | optional name-value | `"matlab"` (default) or `"initial"`. |

For compatibility, a bare trailing `"matlab"` or `"initial"` is still accepted.
Prefer `"tangentMode", value` in new code.

### Algorithms, integrators, and `tangentMode`

`matlabSubstructure` does not contain an algorithm or integrator whitelist. It
implements the normal OpenSees Element interfaces for resisting force, current
and initial stiffness, mass, and damping. The selected OpenSees algorithm and
integrator decide when and how those quantities are requested and assembled.
Consequently, the Element does not prevent a particular serial algorithm or
static/transient integrator from being selected, but this is not a guarantee
that every possible combination is numerically appropriate for a particular
callback model.

| Setting | Responsibility |
| --- | --- |
| `ops.algorithm(...)` | Controls equilibrium iterations and whether OpenSees requests a current or initial stiffness. |
| `ops.integrator(...)` | Controls the static increment or transient time integration and forms the effective system from stiffness and, when applicable, damping and mass. |
| `"tangentMode"` | Controls only what this Element's `getTangentStiff()` returns when OpenSees requests the current tangent. It does not select or restrict an algorithm/integrator. |

| Mode | Element current-tangent return | Typical effect |
| --- | --- | --- |
| `"matlab"` | Latest `response.tangent` from the callback | A Newton-type algorithm can use the callback's state-dependent consistent tangent. This is normally preferred for nonlinear response. |
| `"initial"` | Fixed Element initial stiffness | The callback force remains nonlinear, but iterations use a fixed stiffness for this Element, giving modified-Newton-like behavior that may require more iterations. |

`getInitialStiff()` always returns the Element initial stiffness independently
of `tangentMode`. Therefore, if the OpenSees algorithm itself explicitly asks
for an initial tangent, that algorithm choice takes precedence: selecting
`tangentMode="matlab"` cannot force such an algorithm to use the current MATLAB
tangent. Conversely, `tangentMode="initial"` makes even a normal current-tangent
request return the fixed initial matrix for this Element.

The callback must currently return a valid `response.tangent` for every
successful `init`/`trial` evaluation even when `tangentMode="initial"`; the
Element validates and stores the complete response before OpenSees requests a
matrix. For transient analysis, the effective matrix generally also contains
the callback's `response.mass` and `response.damping` (plus assigned Rayleigh
damping) with coefficients chosen by the integrator. `tangentMode` changes only
the stiffness contribution; it does not change mass, damping, force, state
commit/revert behavior, or time integration.

The implementation has automated coverage for `Linear`, `Newton`,
`ModifiedNewton`, `KrylovNewton`, and `NewtonLineSearch` in static examples and
for `Newmark` and `HHT` in transient examples. Other standard serial OpenSees
methods use the same Element interfaces, but should be verified for the target
model. Distributed `sendSelf/recvSelf` and concurrent MATLAB callbacks are not
supported.

### Callback sequence during an analysis

OpenSees may evaluate one step as follows:

```text
first update               -> init, then trial
each Newton iteration      -> trial
successful step            -> commit
failed/restarted iteration -> revert
Element removal/wipe       -> shutdown
```

Several `trial` calls can occur at the same analysis time. Thus a callback call
is not a time step. `trial.dt` is measured from the last committed time, and
`trial.isNewTime` only says that the current time differs from that committed
time; neither means the current trial will be accepted.

## Choosing the interface DOFs

`interfacePairs` is an N-by-2 matrix. Each row contains
`[OpenSees node tag, MATLAB-style one-based DOF]`. N must equal the number of
components in `response.force` and both dimensions of `K0` and
`response.tangent`.

```matlab
interfacePairs = [1 1; 1 2; 4 1; 4 2];
```

This maps `trial.disp(1:4)` to node 1 DOFs 1 and 2, followed by node 4 DOFs 1
and 2. All interface vectors use that same order.

The substructure is not restricted to two OpenSees nodes:

- If MATLAB already contains the pile, soil, far-field boundary, and ground
  reference, expose only the pile-head DOFs.
- If MATLAB describes relative behavior between two physical ends, expose
  both ends. The second end may be active or fixed in OpenSees.

For a MATLAB pile-soil model with its own ground reference, a single six-DOF
pile-head node is enough:

```matlab
ops.model("basic", "-ndm", 3, "-ndf", 6);
ops.node(100, 0.0, 0.0, 0.0);
interfacePairs = [(100 * ones(6,1)), (1:6)'];
ops.matlabSubstructure(5001, ...
    @pileSoilSubstructure, state0, K0, interfacePairs);
```

Do not add a fixed OpenSees ground node if the same reference is already inside
MATLAB. Conversely, do not omit the second end if neither side otherwise
defines a reference, or the model may have a rigid-body mechanism. Apply a
given earthquake excitation in either MATLAB or OpenSees unless the formulation
explicitly requires both, so it is not counted twice.

## Callback contract

```matlab
[response, trialState, status] = callback(action, trial, committedState)
```

Keep the ownership boundary clear:

| Object | Owner and purpose |
| --- | --- |
| `action` | C++ lifecycle request. |
| `trial` | Read-only OpenSees current kinematics and analysis context, including explicitly named committed OpenSees quantities. |
| `committedState` | The previously committed `trialState`, with the same MATLAB type and user-defined fields. MATLAB defines the fields; C++ only stores, passes, commits, and restores the value without interpreting it. |
| `response` | Current Element force/tangent and optional matrices returned to OpenSees. |
| `trialState` | Candidate MATLAB history; it is not accepted merely because the callback returned it. |
| `status` | Scalar; zero is success and nonzero is failure/unsupported action. |

In particular, `committedState` does not automatically contain OpenSees force,
displacement, or load factor. Put MATLAB-owned history such as plastic strain,
damage, or internal DOFs in `committedState`; read authoritative OpenSees values
from `trial`.

### Trial input fields

N is the number of interface rows.

| Field | Type/shape | Meaning |
| --- | --- | --- |
| `disp`, `vel`, `accel` | N-by-1 double | Current trial interface kinematics in `interfacePairs` order. |
| `committedDisp` | N-by-1 or empty | Displacement at the last successful Element commit; empty during `init`. |
| `committedForce` | N-by-1 or empty | Internal resisting force at the last successful Element commit; empty during `init` and excludes separately assembled inertia/damping. |
| `time` | scalar double | Current OpenSees Domain time. |
| `dt` | scalar double | Current time minus last committed time; repeated Newton calls can have the same value. |
| `previousCommittedTime` | scalar double | Domain time at the last successful Element commit. |
| `loadFactor` | scalar or empty | Factor of the only load pattern; empty with zero/multiple patterns. A transient pattern value is not a static multiplier. |
| `elementTag` | scalar double | Element tag. |
| `action` | char | Copy of the first callback argument. |
| `isInitial` | logical | True for `init` and `reverttostart`. |
| `isNewTime` | logical | Whether time differs from committed time, not whether the trial will commit. |
| `activeDofCount` | scalar double | N. |
| `interfacePairs` | N-by-2 double | Interface node/DOF definition. |
| `callId` | scalar double | Trial-call counter. |
| `committedRevision` | scalar double | Successful Element commit count. |

All fields exist for normal `init`/`trial` calls. Use `isempty` for optional
context. Additional fields do not break callbacks that ignore them.

### Callback outputs

For `init` and `trial`, `response` must be a scalar struct of finite real
doubles:

| Field | Requirement and meaning |
| --- | --- |
| `force` | Required N-value internal resisting force. |
| `tangent` | Required N-by-N tangent consistent with `force`. |
| `mass` | Optional current N-by-N mass; omission means zero for this call. |
| `damping` | Optional current N-by-N damping; omission means zero for this call. |
| `initialStiffness` | Optional during `init`; defaults to command `K0`. |
| `initialMass` | Optional during `init`; defaults to `init` response mass. |
| `initialDamping` | Optional during `init`; defaults to `init` response damping. |

`trialState` may be any MATLAB value and should contain only the candidate
MATLAB model history. Its type and fields define the type and fields of the
future `committedState`: after a successful commit, C++ stores that
`trialState`, and a later `trial` call receives it as `committedState`. `status`
must be scalar zero on success. For notification actions whose response is
unused, return `response = struct()`.

### Action lifecycle

| Action | Third callback argument | State outcome |
| --- | --- | --- |
| `init` | Command `initialState` | Successful returned `trialState` becomes the initial committed MATLAB snapshot. |
| `trial` | Last committed MATLAB snapshot | Returned `trialState` remains a candidate until commit. |
| `commit` | Accepted candidate from the last successful trial | Returned state may finalize the candidate and is then committed. |
| `revert` | Last committed MATLAB snapshot | Returned state is ignored; C++ restores its committed snapshots. |
| `reverttostart` | Original `initialState` | Returned state is ignored; initial snapshots are restored. |
| `shutdown` | Last stored committed MATLAB snapshot | Optional cleanup; returned state is ignored and `trial` may be empty after Domain removal. |

This action-dependent table is why the conventional argument name
`committedState` is exact for `trial` but should not be interpreted literally
for every notification. Callbacks implementing only `init` and `trial` remain
supported through C++ fallback behavior.

When mass or damping is returned, OpenSees forms

```text
R_total = response.force + response.damping * trial.vel
                         + response.mass * trial.accel
```

Do not include the same `C*v` or `M*a` contribution in `response.force`. A
constitutive force that inherently depends on velocity may stay in
`response.force`; normally do not return it again as a damping matrix.

The returned mass and damping are OpenSees Element matrices. Transient analysis
therefore assembles `M*a` and `C*v` from the current nodal kinematics.
`UniformExcitation` is handled by the normal OpenSees
`-M*R*groundAcceleration` element-load convention. If Rayleigh damping is also
assigned to this Element, OpenSees adds the Rayleigh matrix to
`response.damping`; do not duplicate it in the callback.

Under `UniformExcitation`, `trial.accel` is the nodal relative acceleration
used by the transient integrator, not a request to add the ground acceleration
again. If the MATLAB substructure applies ground motion internally, do not also
apply the same excitation to it through OpenSees.

During `trial`, calculate only from `committedState` and return a candidate
`trialState`. Do not retain or reuse uncommitted history in persistent/global
MATLAB storage.

For a path-dependent model, always calculate history this way:

```matlab
[force, tangent, historyTrial] = evaluateModel( ...
    trial.disp, trial.vel, trial.time, committedState.history);
response.force = force;
response.tangent = tangent;
trialState = committedState;
trialState.history = historyTrial;
```

Never advance a persistent/global history on every `trial` call. Newton can
retry the same step, so that would accumulate unaccepted history. The tangent
should be consistent with the returned force; otherwise Newton convergence may
be slow or fail. Selecting `"initial"` tangent mode merely makes OpenSees use a
fixed initial tangent (modified Newton); the callback must still return the
correct nonlinear force.

### Static and transient models

For static stiffness-only behavior, return only `force` and `tangent`. For a
transient model, return mass and damping only if they physically belong to the
MATLAB substructure. Do not also put the same mass on OpenSees interface nodes.
Mass and damping must be full N-by-N matrices; use zero rows and columns for
DOFs that have none.

Omitting mass or damping in a trial means zero for that trial, not “reuse the
last value.” During `init`, `K0` is the fallback `initialStiffness`, and
`initialMass`/`initialDamping` default to the mass/damping returned by `init`.
These initial matrices remain fixed after initialization.

## Querying and recording results

Queries read stored C++ results and do not invoke the callback:

```matlab
f  = ops.eleResponse(eleTag, "interfaceForce");
u  = ops.eleResponse(eleTag, "interfaceDisp");
K  = ops.eleResponse(eleTag, "tangent");
K0 = ops.eleResponse(eleTag, "initialStiffness");
M  = ops.eleResponse(eleTag, "mass");
C  = ops.eleResponse(eleTag, "damping");
rt = ops.eleResponse(eleTag, "forceIncInertia");

ops.recorder("Element", "-file", "interfaceForce.out", ...
    "-ele", eleTag, "interfaceForce");
```

The wrapper may return a matrix as a flattened row vector, although the
underlying OpenSees value remains N-by-N. Aliases include `force`, `forces`,
`globalForce`, `activeForce`, `localForce`, `disp`, `vel`, `accel`, `stiffness`,
`initialMass`, `initialDamping`, and `interfacePairs`. Here `localForce` means
interface force; this Element has no separate geometric local axes.

Performance queries include `callCount`, `trialCallCount`, `commitCount`,
`callbackTime`, `lastCallbackTime`, `maxCallbackTime`, and `meanCallbackTime`:

```matlab
nTrial = ops.eleResponse(eleTag, "trialCallCount");
tMean = ops.eleResponse(eleTag, "meanCallbackTime");
```

They count actual MATLAB calls and reset on `revertToStart()`.

## Restrictions and cleanup

- Do not call `ops`, `opsMAT`, or the underlying MEX interface inside the
  callback; re-entering the MEX call is unsupported.
- Callbacks run only in the local MEX process and are not thread-safe.
- Distributed `sendSelf/recvSelf` is not supported.
- Remove active Elements first (normally with `ops.wipe()`), then use
  `ops.unregisterMatlabSubstructure(eleTag)` for one callback or
  `ops.clearMatlabSubstructures()` for all callbacks.
- Use `ops.hasMatlabSubstructure(eleTag)` to test whether a tag is registered.

The Element does not select the analysis algorithm or integrator. Configure
`Linear`, `Newton`, `ModifiedNewton`, `KrylovNewton`, `NewtonLineSearch`,
`Newmark`, `HHT`, and other methods through the usual OpenSees commands.

## Checklist before a full analysis

- All interface nodes already exist; each `[nodeTag, DOF]` is valid and unique.
- N equals the force length and every dimension of `K0` and the returned
  tangent, mass and damping matrices.
- Every response value is a finite real `double` and uses internal
  resisting-force signs.
- Ground reference, mass, damping and earthquake excitation each exist only
  once across MATLAB and OpenSees.
- The returned tangent has been compared with a small finite-difference change
  in force.
- The script checks `ok == 0` before using results.
- Cleanup is performed with `ops.wipe()` before unregistering or clearing
  callback records.

## Examples

[Extensions Examples](../../examples/extension/index.md)
