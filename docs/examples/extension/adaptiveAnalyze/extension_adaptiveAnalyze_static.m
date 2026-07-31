%% *Strongly nonlinear snap-through example for adaptiveAnalyze*
% 
% 
% Model:
% 
% An asymmetric shallow two-bar truss with corotational geometry.
% 
% 
% 
% Comparison:
% 
% 1. Fine-step Newton analysis used as the numerical reference.
% 
% 2. Coarse-step ModifiedNewton analysis using adaptiveAnalyze.
% 
% 3. Independently stored reference values at selected displacements.
% 
% 
% 
% Expected adaptive behavior:
% 
% - ModifiedNewton attempts fail near the limit points.
% 
% - KrylovNewton and Newton are attempted.
% 
% - Some failed displacement increments are subdivided.
% 
% 

clear;
clc;
close all;

opsMAT = OpenSeesMatlab();
ops = opsMAT.opensees;
%% 
% 
% Analysis parameters

referenceIncrement = -5.0e-4;
referenceSteps = 400;

adaptiveIncrement = -2.5e-2;
adaptiveSteps = 8;

controlNode = 3;
controlDOF = 2;
loadPatternTag = 1;

% Fine-step reference analysis

buildShallowTrussModel(ops);

ops.constraints("Plain");
ops.numberer("Plain");
ops.system("BandGeneral");

ops.test("NormDispIncr", 1.0e-12, 50, 0);
ops.algorithm("Newton");
ops.integrator( ...
    "DisplacementControl", ...
    controlNode, controlDOF, referenceIncrement);
ops.analysis("Static");

reference = zeros(referenceSteps + 1, 4);
% Columns:
%   1: horizontal displacement of node 3
%   2: vertical displacement of node 3
%   3: vertical load magnitude
%   4: OpenSees load factor

reference(1, :) = [
    ops.nodeDisp(controlNode, 1), ...
    ops.nodeDisp(controlNode, 2), ...
    ops.getLoadFactor(loadPatternTag), ...
    ops.getLoadFactor(loadPatternTag)];

for step = 1:referenceSteps
    ok = ops.analyze(1);

    if ok ~= 0
        error( ...
            "Reference analysis failed at step %d with code %d.", ...
            step, ok);
    end

    loadFactor = ops.getLoadFactor(loadPatternTag);

    reference(step + 1, :) = [
        ops.nodeDisp(controlNode, 1), ...
        ops.nodeDisp(controlNode, 2), ...
        loadFactor, ...
        loadFactor];
end

% Coarse-step adaptive analysis

buildShallowTrussModel(ops);

ops.constraints("Plain");
ops.numberer("Plain");
ops.system("BandGeneral");

% Intentionally restrictive settings make the original ModifiedNewton
% configuration fail near strongly nonlinear portions of the path.
ops.test("NormDispIncr", 1.0e-12, 2, 0);
ops.algorithm("ModifiedNewton");
ops.integrator( ...
    "DisplacementControl", ...
    controlNode, controlDOF, adaptiveIncrement);
ops.analysis("Static");

adaptive = zeros(adaptiveSteps + 1, 4);
% Columns:
%   1: horizontal displacement of node 3
%   2: vertical displacement of node 3
%   3: vertical load magnitude
%   4: adaptiveAnalyze return code

adaptive(1, :) = [
    ops.nodeDisp(controlNode, 1), ...
    ops.nodeDisp(controlNode, 2), ...
    ops.getLoadFactor(loadPatternTag), ...
    0];

fprintf("\n");
fprintf("============================================================\n");
fprintf(" Adaptive coarse-step analysis\n");
fprintf(" Watch for adaptiveAnalyze:: algorithm and subdivision output\n");
fprintf("============================================================\n\n");

for step = 1:adaptiveSteps
    fprintf( ...
        "\n--- Requested outer displacement step %d of %d ---\n", ...
        step, adaptiveSteps);

    ok = ops.adaptiveAnalyze(1, ...
        "-algorithms", "KrylovNewton", "Newton", ...
        "-subdivision", 0.5, 1.0e-6, 10, ...
        "-limits", 1000, ...
        "-debug");

    if ok ~= 0
        error( ...
            "Adaptive analysis failed at outer step %d with code %d.", ...
            step, ok);
    end

    adaptive(step + 1, :) = [
        ops.nodeDisp(controlNode, 1), ...
        ops.nodeDisp(controlNode, 2), ...
        ops.getLoadFactor(loadPatternTag), ...
        ok];
end
% Independently stored reference values

% These values were obtained from the fine-step Newton solution using:
%
%   displacement increment = -5.0e-4
%   test tolerance         = 1.0e-12
%   maximum iterations     = 50
%
% Columns:
%   [horizontal displacement, vertical displacement, load factor]

publishedReference = [
     3.60712752838123e-4, -0.025,  2.48201205553051e-1
     6.19158366863243e-4, -0.050,  2.84192774311654e-1
     7.74542441814802e-4, -0.075,  1.77821500993599e-1
     8.26389841308204e-4, -0.100, -6.10622663543834e-16
     7.74542441814889e-4, -0.125, -1.77821500993605e-1
     6.19158366863171e-4, -0.150, -2.84192774311655e-1
     3.60712752838085e-4, -0.175, -2.48201205553024e-1
    -5.96848531392942e-17, -0.200,  0.0
];

% Compare the computed reference with the stored values

referenceAtCheckPoints = zeros(adaptiveSteps, 3);

for i = 1:adaptiveSteps
    targetDisplacement = publishedReference(i, 2);

    [~, index] = min(abs(reference(:, 2) - targetDisplacement));

    referenceAtCheckPoints(i, :) = [
        reference(index, 1), ...
        reference(index, 2), ...
        reference(index, 3)];
end

publishedHorizontalError = ...
    referenceAtCheckPoints(:, 1) - publishedReference(:, 1);

publishedLoadError = ...
    referenceAtCheckPoints(:, 3) - publishedReference(:, 3);

maxPublishedHorizontalError = max(abs(publishedHorizontalError));
maxPublishedLoadError = max(abs(publishedLoadError));

% Compare adaptive results with the fine-step reference

adaptiveReferenceLoad = interp1( ...
    -reference(:, 2), ...
    reference(:, 3), ...
    -adaptive(:, 2), ...
    "linear");

adaptiveLoadError = adaptive(:, 3) - adaptiveReferenceLoad;

adaptiveReferenceHorizontalDisp = interp1( ...
    -reference(:, 2), ...
    reference(:, 1), ...
    -adaptive(:, 2), ...
    "linear");

adaptiveHorizontalError = ...
    adaptive(:, 1) - adaptiveReferenceHorizontalDisp;

maxAdaptiveLoadError = max(abs(adaptiveLoadError));
maxAdaptiveHorizontalError = max(abs(adaptiveHorizontalError));

% Print comparison table


comparisonTable = table( ...
    (0:adaptiveSteps)', ...
    adaptive(:, 2), ...
    adaptive(:, 1), ...
    adaptive(:, 3), ...
    adaptiveReferenceLoad, ...
    adaptiveLoadError, ...
    adaptiveHorizontalError, ...
    'VariableNames', { ...
        'OuterStep', ...
        'VerticalDisplacement', ...
        'HorizontalDisplacement', ...
        'AdaptiveLoad', ...
        'ReferenceLoad', ...
        'LoadError', ...
        'HorizontalDisplacementError'});

fprintf("\n");
fprintf("============================================================\n");
fprintf(" Adaptive versus fine-step reference\n");
fprintf("============================================================\n\n");
comparisonTable

fprintf("Maximum adaptive load error:              %.6e\n", ...
    maxAdaptiveLoadError);
fprintf("Maximum adaptive horizontal error:        %.6e\n", ...
    maxAdaptiveHorizontalError);
fprintf("Maximum stored-reference load error:      %.6e\n", ...
    maxPublishedLoadError);
fprintf("Maximum stored-reference horizontal error: %.6e\n", ...
    maxPublishedHorizontalError);

% Numerical checks

assert(all(adaptive(:, 4) == 0), ...
    "At least one adaptive outer step did not complete.");

assert(abs(adaptive(end, 2) + 0.2) < 1.0e-10, ...
    "The adaptive analysis did not reach the target displacement.");

assert(maxPublishedLoadError < 1.0e-8, ...
    "The fine-step solution does not match the stored load references.");

assert(maxPublishedHorizontalError < 1.0e-8, ...
    "The fine-step solution does not match the stored displacement references.");

assert(maxAdaptiveLoadError < 1.0e-7, ...
    "The adaptive load response differs excessively from the reference.");

assert(maxAdaptiveHorizontalError < 1.0e-7, ...
    "The adaptive horizontal response differs excessively from the reference.");

% Plot comparison

downwardReferenceDisp = -reference(:, 2);
downwardAdaptiveDisp = -adaptive(:, 2);

figure( ...
    "Color", "white", ...
    "Name", "adaptiveAnalyze strong nonlinear demonstration", ...
    "Position",[100 100 1500 600]);

layout = tiledlayout(2, 2, ...
    "TileSpacing", "compact", ...
    "Padding", "compact");

title(layout, ...
    "Asymmetric shallow-truss snap-through response", ...
    "FontWeight", "bold");

% Load-displacement response
nexttile([1, 2]);

plot( ...
    downwardReferenceDisp, reference(:, 3), ...
    "-", ...
    "Color", [0.10, 0.35, 0.75], ...
    "LineWidth", 2.0, ...
    "DisplayName", "Fine-step Newton reference");

hold on;

plot( ...
    downwardAdaptiveDisp, adaptive(:, 3), ...
    "o--", ...
    "Color", [0.85, 0.20, 0.15], ...
    "MarkerFaceColor", [1.00, 0.75, 0.20], ...
    "MarkerSize", 7, ...
    "LineWidth", 1.5, ...
    "DisplayName", "Coarse adaptiveAnalyze");

plot( ...
    -publishedReference(:, 2), publishedReference(:, 3), ...
    "ks", ...
    "MarkerSize", 6, ...
    "LineWidth", 1.0, ...
    "DisplayName", "Stored reference values");

yline(0.0, ":", "Color", [0.35, 0.35, 0.35]);
grid on;
box on;

xlabel("Downward displacement, -u_y");
ylabel("Load factor");
legend("Location", "bestoutside");

% Horizontal equilibrium response
nexttile;

plot( ...
    downwardReferenceDisp, reference(:, 1), ...
    "-", ...
    "Color", [0.10, 0.35, 0.75], ...
    "LineWidth", 2.0, ...
    "DisplayName", "Reference");

hold on;

plot( ...
    downwardAdaptiveDisp, adaptive(:, 1), ...
    "o", ...
    "Color", [0.85, 0.20, 0.15], ...
    "MarkerFaceColor", [1.00, 0.75, 0.20], ...
    "MarkerSize", 6, ...
    "DisplayName", "Adaptive");

grid on;
box on;

xlabel("Downward displacement, -u_y");
ylabel("Horizontal displacement, u_x");
legend("Location", "bestoutside");

% Adaptive error
nexttile;

semilogy( ...
    downwardAdaptiveDisp, ...
    max(abs(adaptiveLoadError), eps), ...
    "o-", ...
    "Color", [0.55, 0.15, 0.70], ...
    "MarkerFaceColor", [0.75, 0.55, 0.90], ...
    "LineWidth", 1.5, ...
    "DisplayName", "|load error|");

hold on;

semilogy( ...
    downwardAdaptiveDisp, ...
    max(abs(adaptiveHorizontalError), eps), ...
    "s-", ...
    "Color", [0.10, 0.55, 0.30], ...
    "MarkerFaceColor", [0.45, 0.80, 0.55], ...
    "LineWidth", 1.5, ...
    "DisplayName", "|horizontal displacement error|");

grid on;
box on;

xlabel("Downward displacement, -u_y");
ylabel("Absolute error");
legend("Location", "bestoutside");

fprintf("\nAll reference and adaptive comparison checks passed.\n");
ops.wipe();
% Local function

function buildShallowTrussModel(ops)
%BUILDSHALLOWTRUSSMODEL Create an asymmetric two-bar snap-through model.

ops.wipe();

ops.model("basic", "-ndm", 2, "-ndf", 2);

% Support nodes and shallow apex.
ops.node(1, -1.0, 0.0);
ops.node(2,  1.2, 0.0);
ops.node(3,  0.0, 0.1);

ops.fix(1, 1, 1);
ops.fix(2, 1, 1);
ops.fix(3, 0, 0);

% The material is elastic. Strong nonlinearity is produced by the
% corotational geometry and shallow snap-through configuration.
ops.uniaxialMaterial("Elastic", 1, 1000.0);

ops.element("corotTruss", 1, 1, 3, 1.0, 1);
ops.element("corotTruss", 2, 2, 3, 1.0, 1);

ops.timeSeries("Linear", 1);
ops.pattern("Plain", 1, 1);

% Unit downward reference load. Therefore, the load factor is also the
% magnitude of the applied vertical load.
ops.load(3, 0.0, -1.0);
end