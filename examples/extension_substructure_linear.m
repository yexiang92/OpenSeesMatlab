%[text] # **Linear MATLAB Substructure: Static Analysis and Verification**
%[text] A two-node spring is deliberately used so that every callback quantity can be checked by hand. The example establishes the interface ordering, resisting-force sign convention, and tangent matrix before nonlinear substructures are attempted.
%[text] Responsibility is divided explicitly between OpenSees and the MATLAB callback:
%[text] **OpenSees owns:**
%[text]   1\. Global nodes and constraints
%[text]   2\. External loads
%[text]   3\. Equation assembly
%[text]   4\. The analysis algorithm
%[text] **The MATLAB callback owns:**
%[text]   1\. The condensed substructure model
%[text]   2\. Interface resisting forces
%[text]   3\. Interface tangent stiffness
%[text]   4\. Optional history variables
%[text] The example uses a linear spring and verifies the OpenSees results against the analytical solution.
%[text] **Problem definition**
%[text] Two one-dimensional interface nodes are connected by a spring:
%[text]  **fixed node 1 ---- MATLAB spring (k) ---- node 2 ---\> P**
%[text] Node 1 is fixed.
%[text] A force P is applied to node 2.
%[text] The analytical solution is:
%[text] \\$\\$
%[text]   u2 = \\frac{P}{k}
%[text] \\$\\$
%[text] Using the interface order
%[text]   \[node 1   DOF 1;
%[text]    node 2   DOF 1\]
%[text] the expected internal resisting force is:
%[text]   \[-P;  P\]
%[text] ### Define the spring and callback state
%[text] `K0` follows the interface order stated above. `initialState` is passed to every trial evaluation through the committed-state mechanism, even though this linear spring does not need evolving history variables.
clc; clear; close all;
k = 1000.0;
P = 1.0;

K0 = k * [
     1 -1
    -1  1
];

% initialState can contain any data required by the MATLAB substructure.
% Every trial evaluation receives the last state committed by OpenSees.
initialState = struct("K", K0);

%[text] ### Create the OpenSees model and interface
%[text] Both interface nodes must exist before `callbackSubstructure` is created. Each row of `interfacePairs` fixes the ordering used by trial vectors, resisting force, and all callback matrices.
%% Create the OpenSees command interface

opsMAT = OpenSeesMatlab();
ops = opsMAT.opensees;

% Remove any model left from an earlier run.
ops.wipe();

% If an error stops the script, this guard removes the active Element before
% clearing its MATLAB callback record.
cleanupGuard = onCleanup(@() cleanupLinearSubstructure(ops));
%% Create the OpenSees model and interface nodes
% The model and every node referenced by interfacePairs must exist before
% callbackSubstructure is called.

ops.model("basic", "-ndm", 1, "-ndf", 1);

ops.node(1, 0.0);
ops.node(2, 1.0);

% Fix the only DOF of node 1.
ops.fix(1, 1);
%% Define the interface DOFs
% Every row of interfacePairs is:
%
%   [nodeTag, oneBasedDOF]
%
% The row order defines the order of:
%
%   trial.disp
%   trial.vel
%   trial.accel
%   response.force
%   rows and columns of response.tangent
%
% There are two interface DOFs, so K0 and response.tangent must be 2-by-2,
% while response.force must contain two values.

interfacePairs = [
    1 1
    2 1
];

%[text] ### Register the MATLAB substructure
%[text] With `tangentMode="matlab"`, OpenSees uses the tangent returned by the callback. `tangentMode="initial"` would keep `K0` throughout the analysis.
%% Create the MATLAB-backed substructure Element

eleTag = 1001;

ops.callbackSubstructure( ...
    eleTag, ...
    @linearSubstructureCallback, ...
    initialState, ...
    K0, ...
    interfacePairs, ...
    "tangentMode", "matlab");
% The final argument controls which tangent OpenSees uses:
%
%   "matlab"  - use response.tangent returned by the callback
%   "initial" - always use the initial stiffness K0
%
% "matlab" is appropriate when the callback supplies the current tangent.
%% Apply the external load

ops.timeSeries("Linear", 1);
ops.pattern("Plain", 1, 1);

% Apply P to the only DOF of node 2.
ops.load(2, P);

%[text] ### Solve one static load step
%[text] The callback element participates in the ordinary OpenSees equation assembly. Newton may evaluate it several times during the step, so callback trials must not modify committed history.
%% Configure the static analysis
% callbackSubstructure behaves as an OpenSees Element. It does not select the
% constraint handler, equation numberer, solver, algorithm, or integrator.

ops.constraints("Plain");
ops.numberer("Plain");
ops.system("BandGeneral");

ops.test("NormUnbalance", 1.0e-12, 10);
ops.algorithm("Newton");

ops.integrator("LoadControl", 1.0);
ops.analysis("Static");

%% Run one load step
% OpenSees may call the MATLAB callback several times during a single
% analysis step. Each trial must start from committedState rather than from
% an earlier uncommitted trial.

ok = ops.analyze(1);

if ok ~= 0
    error("Linear substructure analysis failed with code %d.", ok);
end
%% Read the numerical response
% eleResponse reads data already stored by the C++ Element. These queries do
% not invoke the MATLAB callback again.

u2 = ops.nodeDisp(2, 1);

interfaceDisp = ops.eleResponse( ...
    eleTag, "interfaceDisp");

interfaceForce = ops.eleResponse( ...
    eleTag, "interfaceForce");

tangentFlat = ops.eleResponse( ...
    eleTag, "tangent");

initialStiffnessFlat = ops.eleResponse( ...
    eleTag, "initialStiffness");

interfaceDefinition = ops.eleResponse( ...
    eleTag, "interfacePairs");

%% Convert flattened matrices
% The current MATLAB wrapper can return an OpenSees matrix as a flattened
% row vector. Convert it back to an N-by-N MATLAB matrix.

nInterface = size(interfacePairs, 1);

tangent = reshape( ...
    tangentFlat, nInterface, nInterface).';

initialStiffness = reshape( ...
    initialStiffnessFlat, nInterface, nInterface).';
%[text] ### Verify displacement, force, and tangent
%[text] The numerical checks compare all interface quantities, not only the free-node displacement. This catches reversed interface ordering and incorrect force signs that a displacement-only check can miss.
%% Calculate the analytical solution

uExpected = P / k;

dispExpected = [
    0
    uExpected
];

forceExpected = [
    -P
     P
];

tangentExpected = K0;
%% Verify displacement, force, and tangent stiffness

displacementError = abs(u2 - uExpected);

interfaceDispError = norm( ...
    interfaceDisp(:) - dispExpected, inf);

forceError = norm( ...
    interfaceForce(:) - forceExpected, inf);

tangentError = norm( ...
    tangent - tangentExpected, inf);

initialStiffnessError = norm( ...
    initialStiffness - K0, inf);

tolerance = 1.0e-10;

assert(displacementError < tolerance, ...
    "Node displacement verification failed.");

assert(interfaceDispError < tolerance, ...
    "Interface displacement verification failed.");

assert(forceError < tolerance, ...
    "Interface force verification failed.");

assert(tangentError < tolerance, ...
    "Current tangent verification failed.");

assert(initialStiffnessError < tolerance, ...
    "Initial stiffness verification failed.");
%% Display the verification results

verification = table( ... %[output:group:33d01bcb] %[output:257ad8e8]
    u2, ... %[output:257ad8e8]
    uExpected, ... %[output:257ad8e8]
    displacementError, ... %[output:257ad8e8]
    interfaceDispError, ... %[output:257ad8e8]
    forceError, ... %[output:257ad8e8]
    tangentError, ... %[output:257ad8e8]
    initialStiffnessError) %[output:group:33d01bcb] %[output:257ad8e8]
disp("Interface definition returned by the Element:"); %[output:54a5fb5f]
disp(interfaceDefinition); %[output:4252429b]
disp("Interface displacement:"); %[output:175d7daf]
disp(interfaceDisp(:)); %[output:3956393d]
disp("Interface resisting force:"); %[output:9903249a]
disp(interfaceForce(:)); %[output:4a716ec0]
disp("Current tangent stiffness:"); %[output:0aa474b7]
disp(tangent); %[output:6b7349b4]
%% Inspect callback activity
% trialCallCount can be greater than one because Newton can evaluate the
% Element repeatedly during a single load step.

trialCalls = ops.eleResponse( ...
    eleTag, "trialCallCount");

totalCalls = ops.eleResponse( ...
    eleTag, "callCount");

meanCallbackTime = ops.eleResponse( ...
    eleTag, "meanCallbackTime");

fprintf("Verification passed.\n"); %[output:4aaaac6f]
fprintf("Trial callback calls: %g\n", trialCalls); %[output:882bf31c]
fprintf("Total callback calls: %g\n", totalCalls); %[output:0e288534]
fprintf("Mean callback time: %.6g seconds\n", meanCallbackTime); %[output:45944c81]
%% Important interpretation
% response.force is the internal resisting force, not an externally applied
% nodal load.
%
% For this example:
%
%   response.force = K * trial.disp
%
% At the converged solution:
%
%   trial.disp = [0; P/k]
%
% and therefore:
%
%   response.force = [-P; P]
%
% OpenSees assembles this internal force into the global equilibrium
% equations and balances it against the applied external load.

%%
%[text] ### Clean up
%[text]
% Always remove the active Element before removing its callback record.
%
% Recommended order:
%
%   1. ops.wipe()
%   2. ops.clearCallbackSubstructures()
%
% Query all required results before cleanup.

ops.wipe();
ops.clearCallbackSubstructures();

% The explicit cleanup succeeded, so remove the automatic cleanup guard.
clear cleanupGuard
%[text]
%%
%[text] ### MATLAB callback used by the Element
%[text]
% The callback signature is:
%
%   [response, trialState, status] = ...
%       callback(action, trial, committedState)
%
% For "init" and "trial", the required outputs are:
%
%   response.force
%   response.tangent
%
% status == 0 indicates success.

function [response, trialState, status] = ...
        linearSubstructureCallback(action, trial, committedState)

    % Start every evaluation from the last state accepted by OpenSees.
    status = int32(0);
    trialState = committedState;

    switch lower(string(action))

        case {"init", "trial"}

            K = committedState.K;

            % Internal interface resisting force.
            response.force = K * trial.disp;

            % Derivative of response.force with respect to trial.disp.
            response.tangent = K;

            % K0 passed to callbackSubstructure is already the fallback initial
            % stiffness. Returning it explicitly during init demonstrates the
            % optional callback field.
            if strcmpi(action, "init")
                response.initialStiffness = K;
            end

            % These state fields are not required by a linear spring. They are
            % included to demonstrate how a candidate trial state is returned.
            %
            % OpenSees accepts trialState only after the analysis step commits.
            trialState.disp = trial.disp;
            trialState.time = trial.time;

        case "commit"

            % The trial state has been accepted by OpenSees.
            % This linear example requires no additional action.
            response = struct();

        case "revert"

            % OpenSees restores its committed snapshot after a failed or
            % restarted trial. No additional MATLAB action is required here.
            response = struct();

        case "reverttostart"

            % OpenSees restores the initial state.
            response = struct();

        case "shutdown"

            % Release MATLAB-side files, sockets, or other resources here if
            % the real substructure owns any.
            response = struct();

        otherwise

            response = struct();
            status = int32(-1);
    end
end

%% Cleanup helper

function cleanupLinearSubstructure(ops)
% Remove active Elements before clearing their callback records.

    try
        ops.wipe();
    catch
    end

    try
        ops.clearCallbackSubstructures();
    catch
    end
end

%[text] ### Verification summary
%[text] Free-node displacement, interface force, tangent, initial stiffness, and interface definition are all checked against closed-form values. Passing only the displacement check is not sufficient to validate a substructure interface.

%[appendix]{"version":"1.0"}
%---
%[metadata:view]
%   data: {"layout":"inline","rightPanelPercent":40}
%---
%[output:257ad8e8]
%   data: {"dataType":"tabular","outputData":{"columnNames":["u2","uExpected","displacementError","interfaceDispError","forceError","tangentError","initialStiffnessError"],"columns":7,"dataTypes":["double","double","double","double","double","double","double"],"header":"1×7 table","name":"verification","rows":1,"type":"table","value":[["1.0000e-03","1.0000e-03","0","0","0","0","0"]]}}
%---
%[output:54a5fb5f]
%   data: {"dataType":"text","outputData":{"text":"Interface definition returned by the Element:\n","truncated":false}}
%---
%[output:4252429b]
%   data: {"dataType":"text","outputData":{"text":"     1     1     2     1\n\n","truncated":false}}
%---
%[output:175d7daf]
%   data: {"dataType":"text","outputData":{"text":"Interface displacement:\n","truncated":false}}
%---
%[output:3956393d]
%   data: {"dataType":"text","outputData":{"text":"   1.0e-03 *\n\n         0\n    1.0000\n\n","truncated":false}}
%---
%[output:9903249a]
%   data: {"dataType":"text","outputData":{"text":"Interface resisting force:\n","truncated":false}}
%---
%[output:4a716ec0]
%   data: {"dataType":"text","outputData":{"text":"    -1\n     1\n\n","truncated":false}}
%---
%[output:0aa474b7]
%   data: {"dataType":"text","outputData":{"text":"Current tangent stiffness:\n","truncated":false}}
%---
%[output:6b7349b4]
%   data: {"dataType":"text","outputData":{"text":"        1000       -1000\n       -1000        1000\n\n","truncated":false}}
%---
%[output:4aaaac6f]
%   data: {"dataType":"text","outputData":{"text":"Verification passed.\n","truncated":false}}
%---
%[output:882bf31c]
%   data: {"dataType":"text","outputData":{"text":"Trial callback calls: 2\n","truncated":false}}
%---
%[output:0e288534]
%   data: {"dataType":"text","outputData":{"text":"Total callback calls: 4\n","truncated":false}}
%---
%[output:45944c81]
%   data: {"dataType":"text","outputData":{"text":"Mean callback time: 0.0009162 seconds\n","truncated":false}}
%---
