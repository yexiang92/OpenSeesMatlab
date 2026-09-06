%% *Run independent OpenSees models with* |*parfor*|
% Use |parfor| when many OpenSees models are *independent*: parameter studies,
% Monte Carlo simulations, calibration trials, or separate load cases. Each worker
% creates its own OpenSees interface and model, so the analyses do not share state.
%
% This differs from OpenSeesSP: |parfor| runs many separate models concurrently,
% whereas OpenSeesSP partitions one large model across MPI processes.


clear; clc; close all;

% Define a small parameter study
% The same nonlinear three-bar truss is solved for several steel yield stresses.
% The example deliberately keeps the input to each case to one number.


yieldStress = linspace(24.0, 48.0, 100)'; % ksi
hardeningRatio = 0.02;
numberOfSteps = 400;

% Establish a serial reference
% Serial and parallel loops call the same function. The serial result makes
% the parallel calculation easy to verify.


numberOfCases = numel(yieldStress);
serialCapacity = zeros(numberOfCases, 1);

serialTimer = tic;
for caseIndex = 1:numberOfCases
    serialCapacity(caseIndex) = solveTrussCase( ...
        yieldStress(caseIndex), hardeningRatio, numberOfSteps);
end
serialSeconds = toc(serialTimer);

% Run the independent models with |parfor|
% MATLAB uses the current process pool, or starts its default local process
% pool. To choose a worker count, start one before running the example, for example
% |parpool("Processes", 4)|. A process pool is used because each worker needs
% an isolated native OpenSees engine.


parallelAvailable = license("test", "Distrib_Computing_Toolbox");
parallelCapacity = nan(numberOfCases, 1);
parallelSeconds = NaN;
workerCount = 0;

if parallelAvailable
    pool = gcp("nocreate");
    if isempty(pool)
        pool = parpool("Processes");
    end
    workerCount = pool.NumWorkers;

    parallelTimer = tic;
    parfor caseIndex = 1:numberOfCases
        parallelCapacity(caseIndex) = solveTrussCase( ...
            yieldStress(caseIndex), hardeningRatio, numberOfSteps);
    end
    parallelSeconds = toc(parallelTimer);

    maximumDifference = max(abs(parallelCapacity - serialCapacity));
    comparisonTolerance = 1.0e-9 * max(1.0, max(abs(serialCapacity)));
    assert(maximumDifference <= comparisonTolerance, ...
        "Serial and parallel results do not agree within tolerance.");
else
    maximumDifference = NaN;
    warning("Parallel Computing Toolbox is unavailable; only the serial reference was run.");
end
% Review the results
% Pool startup is excluded from the parallel timer. Small studies may still
% be faster serially because dispatching work has a cost; |parfor| becomes useful
% when there are enough independent, sufficiently expensive analyses.


summary = table(numberOfCases, workerCount, serialSeconds, ...
    parallelSeconds, serialSeconds / parallelSeconds, maximumDifference, ...
    'VariableNames', ["Cases", "Workers", "SerialSeconds", ...
    "ParallelSeconds", "Speedup", "MaximumDifference"]);
disp(summary);

figure("Color", "white");
plot(yieldStress, serialCapacity, "-", "LineWidth", 1.5, ...
    "DisplayName", "Serial reference");
hold on;
if parallelAvailable
    plot(yieldStress, parallelCapacity, "o", "MarkerSize", 5, ...
        "DisplayName", "parfor");
end
grid on;
xlabel("Yield stress, F_y [ksi]");
ylabel("Final horizontal load [kip]");
title("Independent nonlinear truss analyses");
legend("Location", "northwest");
% Practical use
% Replace |solveTrussCase| with your own model function and pass every case-specific
% input through its arguments. If a model writes recorder or result files, give
% each case a different output directory to prevent workers from writing to the
% same file.



function finalLoad = solveTrussCase(yieldStress, hardeningRatio, numberOfSteps)

    toolbox = OpenSeesMatlab();
    ops = toolbox.opensees;

    elasticModulus = 29000.0; % ksi
    memberArea = 4.0;         % in^2
    referenceLoad = 160.0;    % kip
    targetDisplacement = 2.0; % in

    ops.wipe();
    ops.model("basic", "-ndm", 2, "-ndf", 2);


    ops.node(1,   0.0,   0.0);
    ops.node(2,  72.0,   0.0);
    ops.node(3, 168.0,   0.0);
    ops.node(4,  48.0, 144.0);
    ops.fix(1, 1, 1);
    ops.fix(2, 1, 1);
    ops.fix(3, 1, 1);


    ops.uniaxialMaterial("Steel01", 1, yieldStress, ...
    elasticModulus, hardeningRatio);
    ops.element("CorotTruss", 1, 1, 4, memberArea, 1);
    ops.element("CorotTruss", 2, 2, 4, memberArea, 1);
    ops.element("CorotTruss", 3, 3, 4, memberArea, 1);

    ops.timeSeries("Linear", 1);
    ops.pattern("Plain", 1, 1);
    ops.load(4, referenceLoad, 0.0);

    ops.constraints("Plain");
    ops.numberer("RCM");
    ops.system("BandGeneral");
    ops.test("NormUnbalance", 1.0e-8, 30, 0);
    ops.algorithm("Newton");
    ops.integrator("DisplacementControl", 4, 1, ...
    targetDisplacement / numberOfSteps);
    ops.analysis("Static");

    for step = 1:numberOfSteps
        returnCode = ops.analyze(1);
        if returnCode ~= 0
        error("OpenSees:AnalysisFailed", ...
            "Truss analysis failed at step %d for Fy = %.3g ksi.", ...
            step, yieldStress);
        end
    end

    finalLoad = ops.getLoadFactor(1) * referenceLoad;
    ops.wipe();
end