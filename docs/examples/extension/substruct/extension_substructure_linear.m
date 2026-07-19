%% *Linear MATLAB Substructure: Static Analysis and Verification*
% This example demonstrates the complete workflow for a MATLAB-backed OpenSees 
% substructure.
% 
% *OpenSees owns:*
% 
% 1. Global nodes and constraints
% 
% 2. External loads
% 
% 3. Equation assembly
% 
% 4. The analysis algorithm
% 
% *The MATLAB callback owns:*
% 
% 1. The condensed substructure model
% 
% 2. Interface resisting forces
% 
% 3. Interface tangent stiffness
% 
% 4. Optional history variables
% 
% 
% 
% The example uses a linear spring and verifies the OpenSees results against 
% the analytical solution.
% 
% 
% 
% *Problem definition*
% 
% Two one-dimensional interface nodes are connected by a spring:
% 
% 
% 
% *fixed node 1 ---- MATLAB spring (k) ---- node 2 ---> P*
% 
% 
% 
% Node 1 is fixed. 
% 
% A force P is applied to node 2.
% 
% 
% 
% The analytical solution is:
% 
% $$
% 
% u2 = \frac{P}{k}
% 
% $$
% 
% 
% 
% Using the interface order
% 
% [node 1   DOF 1;
% 
% node 2   DOF 1]
% 
% 
% 
% the expected internal resisting force is:
% 
% 
% 
% [-P;  P]
% 
% 

clc; clear; close all;
%% 
% 

k = 1000.0;
P = 1.0;

K0 = k * [
     1 -1
    -1  1
];

% initialState can contain any data required by the MATLAB substructure.
% Every trial evaluation receives the last state committed by OpenSees.
initialState = struct("K", K0);

%% Create the OpenSees command interface

opsMAT = OpenSeesMatlab();
ops = opsMAT.opensees;

% Remove any model left from an earlier run.
ops.wipe();

% If an error stops the script, this guard removes the active Element before
% clearing its MATLAB callback record.
cleanupGuard = onCleanup(@() cleanupLinearSubstructure(ops));
%% 
% 

%% Create the OpenSees model and interface nodes
% The model and every node referenced by interfacePairs must exist before
% matlabSubstructure is called.

ops.model("basic", "-ndm", 1, "-ndf", 1);

ops.node(1, 0.0);
ops.node(2, 1.0);

% Fix the only DOF of node 1.
ops.fix(1, 1);
%% 
% 

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

%% Create the MATLAB-backed substructure Element

eleTag = 1001;

ops.matlabSubstructure( ...
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
%% 
% 

%% Apply the external load

ops.timeSeries("Linear", 1);
ops.pattern("Plain", 1, 1);

% Apply P to the only DOF of node 2.
ops.load(2, P);

%% Configure the static analysis
% matlabSubstructure behaves as an OpenSees Element. It does not select the
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
%% 
% 

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
%% 
% 

%% Convert flattened matrices
% The current MATLAB wrapper can return an OpenSees matrix as a flattened
% row vector. Convert it back to an N-by-N MATLAB matrix.

nInterface = size(interfacePairs, 1);

tangent = reshape( ...
    tangentFlat, nInterface, nInterface).';

initialStiffness = reshape( ...
    initialStiffnessFlat, nInterface, nInterface).';
%% 
% 

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
%% 
% 

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
%% 
% 

%% Display the verification results

verification = table( ...
    u2, ...
    uExpected, ...
    displacementError, ...
    interfaceDispError, ...
    forceError, ...
    tangentError, ...
    initialStiffnessError)
disp("Interface definition returned by the Element:");
disp(interfaceDefinition);
disp("Interface displacement:");
disp(interfaceDisp(:));
disp("Interface resisting force:");
disp(interfaceForce(:));
disp("Current tangent stiffness:");
disp(tangent);
%% Inspect callback activity
% trialCallCount can be greater than one because Newton can evaluate the
% Element repeatedly during a single load step.

trialCalls = ops.eleResponse( ...
    eleTag, "trialCallCount");

totalCalls = ops.eleResponse( ...
    eleTag, "callCount");

meanCallbackTime = ops.eleResponse( ...
    eleTag, "meanCallbackTime");

fprintf("Verification passed.\n");
fprintf("Trial callback calls: %g\n", trialCalls);
fprintf("Total callback calls: %g\n", totalCalls);
fprintf("Mean callback time: %.6g seconds\n", meanCallbackTime);
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

%% Clean up
% Always remove the active Element before removing its callback record.
%
% Recommended order:
%
%   1. ops.wipe()
%   2. ops.clearMatlabSubstructures()
%
% Query all required results before cleanup.

ops.wipe();
ops.clearMatlabSubstructures();

% The explicit cleanup succeeded, so remove the automatic cleanup guard.
clear cleanupGuard
%% 
% 

%% MATLAB callback used by the Element
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

            % K0 passed to matlabSubstructure is already the fallback initial
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
        ops.clearMatlabSubstructures();
    catch
    end
end