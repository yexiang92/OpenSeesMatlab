%% *KINSOL Methods for a Strongly Nonlinear Truss*
% This example compares OpenSees Newton with the KINSOL Newton and line-search 
% methods. The three-bar truss has material yielding and large-displacement geometric 
% nonlinearity.
% 
% Four large load steps are used. The full Newton updates fail at the third 
% step; the KINSOL line search shortens the update and completes the loading path.


clear; clc; close all;

toolbox = OpenSeesMatlab();
ops = toolbox.opensees;

solverNames = ["OpenSees Newton", "KINSOL Newton", "KINSOL Line Search"];
solverTypes = ["newton", "kinsol-newton", "kinsol-linesearch"];
numSteps = 10;
loadStep = 0.5;
referenceLoad = 160.0;

displacement = nan(numSteps + 1, numel(solverNames));
force = nan(numSteps + 1, numel(solverNames));
completedSteps = zeros(numel(solverNames), 1);
returnCode = zeros(numel(solverNames), 1);
displacement(1, :) = 0.0;
force(1, :) = 0.0;

% Run the same truss with each algorithm

for i = 1:numel(solverNames)
    ops.wipe();
    ops.model("basic", "-ndm", 2, "-ndf", 2);

    % Geometry in inches
    ops.node(1,   0.0,   0.0);
    ops.node(2,  72.0,   0.0);
    ops.node(3, 168.0,   0.0);
    ops.node(4,  48.0, 144.0);
    ops.fix(1, 1, 1);
    ops.fix(2, 1, 1);
    ops.fix(3, 1, 1);

    % Steel02: yield stress = 36 ksi, E = 29000 ksi
    ops.uniaxialMaterial("Steel02", 1, 36.0, 29000.0, 0.02, ...
        18.0, 0.925, 0.15);
    ops.element("CorotTruss", 1, 1, 4, 4.0, 1);
    ops.element("CorotTruss", 2, 2, 4, 4.0, 1);
    ops.element("CorotTruss", 3, 3, 4, 4.0, 1);

    ops.timeSeries("Linear", 1);
    ops.pattern("Plain", 1, 1);
    ops.load(4, referenceLoad, 0.0);

    ops.constraints("Plain");
    ops.numberer("Plain");
    ops.system("BandGeneral");
    ops.test("NormUnbalance", 1.0e-8, 40, 0);

    switch solverTypes(i)
        case "newton"
            ops.algorithm("Newton");
        case "kinsol-newton"
            ops.algorithm("KINSOL", "-method", "newton", ...
                "-testMode", "KINSOL", "-tol", 1.0e-8, ...
                "-maxIter", 40, "-maxNewtonStep", 100.0);
        case "kinsol-linesearch"
            ops.algorithm("KINSOL", "-method", "lineSearch", ...
                "-testMode", "KINSOL", "-tol", 1.0e-8, ...
                "-maxIter", 40, "-maxNewtonStep", 100.0);
    end

    ops.integrator("LoadControl", loadStep);
    ops.analysis("Static");

    fprintf('\n%s\n', solverNames(i));
    for step = 1:numSteps
        returnCode(i) = ops.analyze(1);
        if returnCode(i) ~= 0
            fprintf('Stopped at step %d.\n', step);
            break;
        end

        completedSteps(i) = step;
        displacement(step + 1, i) = ops.nodeDisp(4, 1);
        force(step + 1, i) = ops.getLoadFactor(1) * referenceLoad;
    end
end
% Results

summary = table(solverNames.', completedSteps == numSteps, completedSteps, ...
    returnCode, 'VariableNames', ...
    {'Algorithm', 'Completed', 'Steps', 'ReturnCode'});
summary

figure('Color', 'w');
hold on; grid on; box on;
for i = 1:numel(solverNames)
    plot(displacement(:, i), force(:, i), '-o', 'LineWidth', 1.5, ...
        'DisplayName', solverNames(i));
end
xlabel('Horizontal displacement of node 4 (in)');
ylabel('Horizontal load (kip)');
title('Strongly nonlinear truss');
legend('Location', 'northwest');
set(gca, 'FontName', 'Arial', 'FontSize', 12);

ops.wipe();

% Reading the result
% The truncated Newton curves contain only converged states and stop after step 
% 2. The line-search curve reaches the full load in four steps; overlapping early 
% points confirm that the algorithms solve the same equilibrium problem.