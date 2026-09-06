%% *Nonlinear frame pushover with OpenSeesSP*
% This example performs a displacement-controlled pushover of a scalable, one-bay
% steel moment frame. A gravity analysis establishes the initial state; a triangular
% lateral load pattern then pushes the roof into the nonlinear range. The resulting
% base-shear–roof-drift curve shows the reduction in tangent stiffness as yielding
% spreads through displacement-based beam-column elements.
% *Before running: install MPI on Windows*
% This Windows package uses *Intel MPI*. Install the current x64 Intel MPI Library
% runtime from the <https://www.intel.com/content/www/us/en/developer/tools/oneapi/mpi-library-download.html
% official Intel MPI download page>, keep its standard installation directory,
% and restart MATLAB. Verify it from PowerShell with:
%%
%
%  & "C:\Program Files (x86)\Intel\oneAPI\mpi\latest\bin\mpiexec.exe" -n 2 hostname
%
%%
% |runOpenSeesSP| normally discovers this installation without changing the
% persistent environment. With multiple MPI versions, pass the compatible executable
% explicitly using |MpiExecutable="C:\...\mpiexec.exe"|. Do not mix an Intel-MPI
% package with Microsoft MPI or another MPI implementation.
% *Run from the MATLAB Command Window*
% Open this file in the Live Editor to read it, then launch the MPI job from
% the Command Window. The response figure is transferred back from the batch child
% process and opened automatically.
%%
%
%  runOpenSeesSP(8, "parallel_openseessp_nonlinear_pushover.m")
%
%%
%

clear;
clc;
close all;

% *Create the distributed OpenSees model*
% MATLAB runs only on MPI rank zero. The remaining ranks are native OpenSeesSP
% workers. Increase the storey or member-subdivision parameters below to give
% a machine with many CPU cores enough elements to partition. A P-Delta transformation
% includes the principal second-order column effect.


ops = OpenSeesNexus();
processCount = ops.getNP();
processRank = ops.getPID();

assert(processCount >= 2, ...
    "OpenSeesSPExample:NotParallel", ...
    "Run this example with runOpenSeesSP and at least two processes.");
assert(processRank == 0, ...
    "OpenSeesSPExample:UnexpectedRank", ...
    "The MATLAB host must be MPI rank zero.");

numberOfStoreys = 15;          % Number of frame levels above the base.
columnElementsPerStorey = 4;   % Finite elements along each column member.
beamElementsPerBay = 4;        % Finite elements along each floor beam.
bayWidth = 6.0;                % Horizontal bay width [m].
storeyHeight = 3.2;            % Height of each storey [m].
youngsModulus = 200.0e9;       % Steel elastic modulus [Pa].
yieldStress = 345.0e6;         % Steel yield stress [Pa].
hardeningRatio = 0.01;         % Post-yield tangent divided by elastic tangent.

assert(columnElementsPerStorey >= 1 && beamElementsPerBay >= 1, ...
    "OpenSeesSPExample:InvalidMesh", ...
    "Each physical member needs at least one finite element.");

ops.wipe();
ops.model("basic", "-ndm", 2, "-ndf", 3);

% Node tags are 2*level+1 on the left and 2*level+2 on the right.
for level = 0:numberOfStoreys
    elevation = level * storeyHeight;
    ops.node(2 * level + 1, 0.0, elevation);
    ops.node(2 * level + 2, bayWidth, elevation);
end
leftBaseNode = 1;
rightBaseNode = 2;
ops.fix(leftBaseNode, 1, 1, 1);
ops.fix(rightBaseNode, 1, 1, 1);

steelTag = 1;
columnSectionTag = 1;
beamSectionTag = 2;
ops.uniaxialMaterial("Steel01", steelTag, yieldStress, ...
    youngsModulus, hardeningRatio);

% Incremental patch calls are collected into each Fiber section by the SP
% adapter, matching the serial MATLAB, Python, and Julia command syntax.
ops.section("Fiber", columnSectionTag);
ops.patch("rect", steelTag, 12, 12, -0.20, -0.20, 0.20, 0.20);
ops.section("Fiber", beamSectionTag);
ops.patch("rect", steelTag, 14, 10, -0.25, -0.15, 0.25, 0.15);

columnTransformationTag = 1;
beamTransformationTag = 2;
columnIntegrationTag = 1;
beamIntegrationTag = 2;
ops.geomTransf("PDelta", columnTransformationTag);
ops.geomTransf("Linear", beamTransformationTag);
ops.beamIntegration("Lobatto", columnIntegrationTag, columnSectionTag, 5);
ops.beamIntegration("Lobatto", beamIntegrationTag, beamSectionTag, 5);

% Split every physical member into a configurable chain of displacement-
% based elements. Floor-joint tags remain predictable; intermediate mesh
% nodes receive tags after all floor joints.
nextNodeTag = 2 * (numberOfStoreys + 1) + 1;
elementTag = 1;
for level = 1:numberOfStoreys
    lowerLeft = 2 * (level - 1) + 1;
    lowerRight = lowerLeft + 1;
    upperLeft = 2 * level + 1;
    upperRight = upperLeft + 1;

    lowerColumnNodes = [lowerLeft, lowerRight];
    upperColumnNodes = [upperLeft, upperRight];
    columnCoordinates = [0.0, bayWidth];
    for column = 1:2
        previousNode = lowerColumnNodes(column);
        for subdivision = 1:(columnElementsPerStorey - 1)
            nodeY = ((level - 1) + ...
                subdivision / columnElementsPerStorey) * storeyHeight;
            ops.node(nextNodeTag, columnCoordinates(column), nodeY);
            ops.element("dispBeamColumn", elementTag, previousNode, ...
                nextNodeTag, columnTransformationTag, columnIntegrationTag);
            previousNode = nextNodeTag;
            nextNodeTag = nextNodeTag + 1;
            elementTag = elementTag + 1;
        end
        ops.element("dispBeamColumn", elementTag, previousNode, ...
            upperColumnNodes(column), columnTransformationTag, ...
            columnIntegrationTag);
        elementTag = elementTag + 1;
    end

    previousNode = upperLeft;
    for subdivision = 1:(beamElementsPerBay - 1)
        nodeX = subdivision * bayWidth / beamElementsPerBay;
        ops.node(nextNodeTag, nodeX, level * storeyHeight);
        ops.element("dispBeamColumn", elementTag, previousNode, ...
            nextNodeTag, beamTransformationTag, beamIntegrationTag);
        previousNode = nextNodeTag;
        nextNodeTag = nextNodeTag + 1;
        elementTag = elementTag + 1;
    end
    ops.element("dispBeamColumn", elementTag, previousNode, upperRight, ...
        beamTransformationTag, beamIntegrationTag);
    elementTag = elementTag + 1;
end

numberOfElements = elementTag - 1;
assert(numberOfElements >= processCount, ...
    "OpenSeesSPExample:TooFewElements", ...
    ["The model has %d elements for %d MPI processes. Increase " ...
     "numberOfStoreys or the member subdivisions."], ...
    numberOfElements, processCount);

% *Establish the gravity state*
% The vertical floor loads introduce column axial forces before the lateral
% pushover. |loadConst| then preserves that converged state while resetting pseudo-time
% for the lateral pattern.


gravitySeriesTag = 1;
gravityPatternTag = 1;
floorGravityLoad = 6.0e5;      % Downward load at each frame joint [N].
ops.timeSeries("Linear", gravitySeriesTag);
ops.pattern("Plain", gravityPatternTag, gravitySeriesTag);
for level = 1:numberOfStoreys
    ops.load(2 * level + 1, 0.0, -floorGravityLoad, 0.0);
    ops.load(2 * level + 2, 0.0, -floorGravityLoad, 0.0);
end

ops.constraints("Transformation");
ops.numberer("RCM");
ops.system("Mumps");
ops.test("NormUnbalance", 1.0e-3, 30);
ops.algorithm("Linear");
ops.integrator("LoadControl", 0.1);
ops.analysis("Static");
gravityCode = ops.analyze(10);
assert(gravityCode == 0, ...
    "OpenSeesSPExample:GravityFailed", ...
    "The distributed gravity analysis returned code %d.", gravityCode);
ops.loadConst("-time", 0.0);

% *Run the displacement-controlled pushover*
% A triangular load pattern gives larger lateral force to upper floors. |DisplacementControl|
% advances the roof displacement by a fixed increment; the required load factor
% and support reactions define the pushover curve.


lateralSeriesTag = 2;
lateralPatternTag = 2;
referenceBaseShear = 1.0e6;    % Scale used for the unit triangular pattern [N].
levelWeights = (1:numberOfStoreys) / sum(1:numberOfStoreys);
ops.timeSeries("Linear", lateralSeriesTag);
ops.pattern("Plain", lateralPatternTag, lateralSeriesTag);
for level = 1:numberOfStoreys
    floorForce = 0.5 * referenceBaseShear * levelWeights(level);
    ops.load(2 * level + 1, floorForce, 0.0, 0.0);
    ops.load(2 * level + 2, floorForce, 0.0, 0.0);
end

controlNode = 2 * numberOfStoreys + 2; % Right roof joint.
controlDegreeOfFreedom = 1;            % Global horizontal translation.
roofHeight = numberOfStoreys * storeyHeight;
targetRoofDrift = 0.025;               % Target roof displacement / roof height.
numberOfPushoverSteps = 240;           % Resolution of the response curve.
displacementIncrement = targetRoofDrift * roofHeight / ...
    numberOfPushoverSteps;
maximumSteps = numberOfPushoverSteps;

ops.test("NormDispIncr", 1.0e-8, 40);
ops.algorithm("Newton");
ops.integrator("DisplacementControl", controlNode, ...
    controlDegreeOfFreedom, displacementIncrement);
ops.analysis("Static");

roofDrift = zeros(maximumSteps + 1, 1);
baseShear = zeros(maximumSteps + 1, 1);
completedSteps = 0;
analysisTimer = tic;

for step = 1:maximumSteps
    analysisCode = ops.analyze(1);
    if analysisCode ~= 0
        fprintf("Pushover stopped at step %d with code %d.\n", ...
            step, analysisCode);
        break
    end

    completedSteps = step;
    roofDisplacement = ops.nodeDisp(controlNode, ...
        controlDegreeOfFreedom);
    roofDrift(step + 1) = roofDisplacement / roofHeight;
    % The triangular reference forces sum to referenceBaseShear. Using the
    % converged pattern factor remains valid when support nodes reside on
    % remote SP subdomains, where rank-zero nodeReaction may not own them.
    baseShear(step + 1) = ops.getLoadFactor(lateralPatternTag) * ...
        referenceBaseShear;
end
analysisSeconds = toc(analysisTimer);

roofDrift = roofDrift(1:completedSteps + 1);
baseShear = baseShear(1:completedSteps + 1);

assert(completedSteps >= round(0.8 * maximumSteps), ...
    "OpenSeesSPExample:PushoverFailed", ...
    "Only %d of %d requested pushover steps converged.", ...
    completedSteps, maximumSteps);
assert(max(baseShear) > 0.0, ...
    "OpenSeesSPExample:InvalidResponse", ...
    "The computed base shear is not positive.");

% Compare early and late secant slopes to confirm nonlinear softening.
earlyIndex = max(2, round(0.20 * numel(roofDrift)));
lateIndex = max(earlyIndex + 1, round(0.90 * numel(roofDrift)));
earlyStiffness = baseShear(earlyIndex) / ...
    (roofDrift(earlyIndex) * roofHeight);
lateStiffness = baseShear(lateIndex) / ...
    (roofDrift(lateIndex) * roofHeight);
stiffnessRatio = lateStiffness / earlyStiffness;

assert(stiffnessRatio < 0.90, ...
    "OpenSeesSPExample:ResponseStayedElastic", ...
    "The late-to-early secant stiffness ratio %.3f does not show yielding.", ...
    stiffnessRatio);

summary = table(processCount, numberOfStoreys, numberOfElements, ...
    completedSteps, analysisSeconds, ...
    100.0 * roofDrift(end), max(baseShear) / 1.0e6, stiffnessRatio, ...
    'VariableNames', ["MPIProcesses", "Storeys", "Elements", ...
    "ConvergedSteps", "AnalysisSeconds", "FinalRoofDriftPercent", ...
    "PeakBaseShearMN", "LateToEarlyStiffness"]);
disp(summary);

% *Inspect the nonlinear response*
% The initial branch is nearly linear. Yielding spreads through the column and
% beam fibres as drift increases, reducing the curve's slope. A nonzero post-yield
% slope remains because |Steel01| uses a 1% hardening ratio, while the column
% P-Delta transformation captures the principal geometric effect.


figure("Color", "white");
plot(100.0 * roofDrift, baseShear / 1.0e6, ...
    "-o", "LineWidth", 1.6, "MarkerSize", 3.5);
grid on;
xlabel("Roof drift [%]");
ylabel("Base shear [MN]");
title(sprintf("OpenSeesSP nonlinear pushover on %d MPI processes", ...
    processCount));
%%
%


fprintf("OpenSeesSP pushover passed: %d steps, late/early stiffness = %.3f.\n", ...
    completedSteps, stiffnessRatio);
ops.wipe();