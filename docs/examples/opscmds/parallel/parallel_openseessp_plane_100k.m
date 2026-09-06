%% *100,000-element plane-stress model with OpenSeesSP*
% This example verifies distributed domain partitioning and the parallel MUMPS
% system with a genuinely large finite-element mesh. A rectangular elastic plate
% is represented by exactly 100,000 four-node quadrilateral elements and loaded
% along its free edge.
% *Before running: install MPI on Windows*
% This Windows package uses *Intel MPI*. Download the current x64 Intel MPI
% Library installer from the <https://www.intel.com/content/www/us/en/developer/tools/oneapi/mpi-library-download.html
% official Intel MPI download page>, run the installer, and keep its standard
% installation directory. The standalone runtime is sufficient for running this
% prebuilt example; the development component is needed only when compiling OpenSeesBindings.
%
% Restart MATLAB after installation, then verify the launcher from PowerShell:
%%
%
%  & "C:\Program Files (x86)\Intel\oneAPI\mpi\latest\bin\mpiexec.exe" -n 2 hostname
%
%%
% Two host-name lines indicate that the local MPI launcher works. |runOpenSeesSP|
% searches the standard Intel oneAPI directories automatically, so it does not
% permanently modify |PATH| and normally does not require |setvars.bat|. If several
% MPI versions are installed, select the compatible executable explicitly:
%%
%
%  mpi = "C:\Program Files (x86)\Intel\oneAPI\mpi\latest\bin\mpiexec.exe";
%  runOpenSeesSP(8, "parallel_openseessp_plane_100k.m", MpiExecutable=mpi)
%
%%
% Do not launch an Intel-MPI build with Microsoft MPI or another incompatible
% |mpiexec|; use the MPI implementation identified by the OpenSeesNexus release
% package.
% *Run from the MATLAB Command Window*
% Open the file in the Live Editor to read it, then launch a separate MPI job.
% Eight processes are a practical starting point; a machine with more CPU cores
% can request more because this mesh contains far more elements than typical workstation
% process counts.
%%
%
%  runOpenSeesSP(20, "parallel_openseessp_plane_100k.m")
%
%%
% *Resource note:* this model has about 200,000 unconstrained translational
% degrees of freedom. MUMPS factorization requires substantially more memory than
% the nodal and element data alone, so increase the process count gradually while
% watching available RAM.
%
%


clear;
clc;
close all;

% *Define the structured finite-element mesh*
% The two mesh counts are deliberately exposed as parameters. Their product
% is the element count. Node and element tags are generated analytically, so no
% external meshing package or data file is required.


ops = OpenSeesNexus();
processCount = ops.getNP();
processRank = ops.getPID();

assert(processCount >= 2, ...
    "OpenSeesSPExample:NotParallel", ...
    "Run this example with runOpenSeesSP and at least two processes.");
assert(processRank == 0, ...
    "OpenSeesSPExample:UnexpectedRank", ...
    "The MATLAB host must be MPI rank zero.");

elementsAlongLength = 500;     % Number of quad columns.
elementsAlongHeight = 200;     % Number of quad rows.
plateLength = 50.0;            % Plate length [m].
plateHeight = 20.0;            % Plate height [m].
plateThickness = 0.10;         % Out-of-plane thickness [m].
youngsModulus = 30.0e9;        % Elastic modulus [Pa].
poissonsRatio = 0.20;          % Isotropic Poisson ratio.
totalVerticalLoad = 1.0e6;     % Downward free-edge resultant [N].

numberOfElements = elementsAlongLength * elementsAlongHeight;
numberOfNodes = (elementsAlongLength + 1) * ...
    (elementsAlongHeight + 1);

assert(numberOfElements == 100000, ...
    "OpenSeesSPExample:UnexpectedElementCount", ...
    "The verification mesh must contain exactly 100,000 elements.");
assert(numberOfElements >= processCount, ...
    "OpenSeesSPExample:TooFewElements", ...
    "Use no more than %d MPI processes for this mesh.", numberOfElements);

ops.wipe();
ops.model("basic", "-ndm", 2, "-ndf", 2);

nodeSpacingX = plateLength / elementsAlongLength;
nodeSpacingY = plateHeight / elementsAlongHeight;
modelTimer = tic;

% Tags increase first in the horizontal direction and then by mesh row.
for row = 0:elementsAlongHeight
    nodeY = row * nodeSpacingY;
    rowStartTag = row * (elementsAlongLength + 1) + 1;
    for column = 0:elementsAlongLength
        nodeTag = rowStartTag + column;
        ops.node(nodeTag, column * nodeSpacingX, nodeY);
    end
    % Clamp every node on the left edge in both in-plane directions.
    ops.fix(rowStartTag, 1, 1);
end

materialTag = 1;
ops.nDMaterial("ElasticIsotropic", materialTag, ...
    youngsModulus, poissonsRatio);

% Counter-clockwise connectivity: lower-left, lower-right, upper-right,
% upper-left. The PlaneStress option selects the two-dimensional material
% reduction used by each constant-thickness quad.
elementTag = 1;
nodesPerRow = elementsAlongLength + 1;
for row = 0:(elementsAlongHeight - 1)
    lowerRowStart = row * nodesPerRow + 1;
    upperRowStart = lowerRowStart + nodesPerRow;
    for column = 0:(elementsAlongLength - 1)
        lowerLeft = lowerRowStart + column;
        lowerRight = lowerLeft + 1;
        upperLeft = upperRowStart + column;
        upperRight = upperLeft + 1;
        ops.element("quad", elementTag, lowerLeft, lowerRight, ...
            upperRight, upperLeft, plateThickness, ...
            "PlaneStress", materialTag);
        elementTag = elementTag + 1;
    end
end
modelSeconds = toc(modelTimer);

assert(elementTag - 1 == numberOfElements, ...
    "OpenSeesSPExample:MeshGenerationFailed", ...
    "The generated element count does not match the requested mesh.");

% *Apply the free-edge load*
% Trapezoidal nodal weights represent a uniform vertical traction. The first
% and last edge nodes receive half weight, making the assembled nodal forces sum
% exactly to the requested resultant.


loadSeriesTag = 1;
loadPatternTag = 1;
ops.timeSeries("Linear", loadSeriesTag);
ops.pattern("Plain", loadPatternTag, loadSeriesTag);

edgeDiscretizationWeight = totalVerticalLoad / elementsAlongHeight;
assembledVerticalLoad = 0.0;
for row = 0:elementsAlongHeight
    edgeNodeTag = row * nodesPerRow + nodesPerRow;
    nodalWeight = 1.0;
    if row == 0 || row == elementsAlongHeight
        nodalWeight = 0.5;
    end
    nodalVerticalLoad = -nodalWeight * edgeDiscretizationWeight;
    ops.load(edgeNodeTag, 0.0, nodalVerticalLoad);
    assembledVerticalLoad = assembledVerticalLoad + nodalVerticalLoad;
end

assert(abs(assembledVerticalLoad + totalVerticalLoad) <= ...
    100.0 * eps(totalVerticalLoad), ...
    "OpenSeesSPExample:LoadAssemblyFailed", ...
    "The assembled edge load does not equal the requested resultant.");

% *Partition and solve*
% The first |analyze| call triggers METIS domain partitioning. |Mumps| then
% performs the distributed sparse direct factorization across the MPI ranks. The
% model is linear, so one load step is sufficient.


ops.constraints("Plain");
ops.numberer("RCM");
ops.system("Mumps");
ops.test("NormUnbalance", 1.0e-4, 20);
ops.algorithm("Linear");
ops.integrator("LoadControl", 1.0);
ops.analysis("Static");

analysisTimer = tic;
analysisCode = ops.analyze(1);
analysisSeconds = toc(analysisTimer);

assert(analysisCode == 0, ...
    "OpenSeesSPExample:AnalysisFailed", ...
    "The distributed analysis returned code %d.", analysisCode);

% *Validate against a reference solution*
% Only the 201 loaded-edge nodes are queried. Their mean vertical displacement
% is compared with the Timoshenko cantilever result, which contains both bending
% and shear deformation:
%
%
%
% $$$$\delta=\frac{PL^3}{3EI}+\frac{PL}{\kappa GA},\qquad I=\frac{tH^3}{12},\quad
% A=tH,\quad G=\frac{E}{2(1+\nu)},\quad \kappa=\frac{5}{6}$$
%
% $$$$
%
% Timoshenko theory predicts the cross-section-average displacement, not the
% value at every point on the free edge. The two-dimensional continuum solution
% also contains a small, symmetric edge-warping component. The mean response should
% match the beam reference within the stated engineering tolerance, while the
% edge variation is checked separately.


edgeElevation = zeros(elementsAlongHeight + 1, 1);
edgeVerticalDisplacement = zeros(elementsAlongHeight + 1, 1);
for row = 0:elementsAlongHeight
    resultIndex = row + 1;
    edgeNodeTag = row * nodesPerRow + nodesPerRow;
    edgeElevation(resultIndex) = row * nodeSpacingY;
    edgeVerticalDisplacement(resultIndex) = ops.nodeDisp(edgeNodeTag, 2);
end

assert(all(isfinite(edgeVerticalDisplacement)), ...
    "OpenSeesSPExample:NonfiniteResponse", ...
    "The loaded-edge displacement contains a nonfinite value.");
assert(mean(edgeVerticalDisplacement) < 0.0, ...
    "OpenSeesSPExample:UnexpectedDirection", ...
    "The loaded edge did not move in the applied-load direction.");

computedEdgeDisplacement = mean(edgeVerticalDisplacement);
edgeDisplacementRange = max(edgeVerticalDisplacement) - ...
    min(edgeVerticalDisplacement);
sectionArea = plateThickness * plateHeight;
sectionMomentOfInertia = plateThickness * plateHeight^3 / 12.0;
shearModulus = youngsModulus / (2.0 * (1.0 + poissonsRatio));
shearCorrectionFactor = 5.0 / 6.0;
bendingDisplacement = totalVerticalLoad * plateLength^3 / ...
    (3.0 * youngsModulus * sectionMomentOfInertia);
shearDisplacement = totalVerticalLoad * plateLength / ...
    (shearCorrectionFactor * shearModulus * sectionArea);
referenceEdgeDisplacement = -(bendingDisplacement + shearDisplacement);
relativeDisplacementError = abs(computedEdgeDisplacement - ...
    referenceEdgeDisplacement) / abs(referenceEdgeDisplacement);

assert(relativeDisplacementError <= 0.02, ...
    "OpenSeesSPExample:ReferenceMismatch", ...
    "The mean loaded-edge displacement differs from the Timoshenko " + ...
    "reference by %.3f%%, exceeding the 2%% tolerance.", ...
    100.0 * relativeDisplacementError);
assert(edgeDisplacementRange / abs(computedEdgeDisplacement) <= 0.02, ...
    "OpenSeesSPExample:ExcessiveEdgeWarping", ...
    "The free-edge displacement range exceeds 2%% of its mean magnitude.");

summary = table(processCount, numberOfNodes, numberOfElements, ...
    modelSeconds, analysisSeconds, computedEdgeDisplacement, ...
    referenceEdgeDisplacement, 100.0 * relativeDisplacementError, ...
    1000.0 * edgeDisplacementRange, ...
    'VariableNames', ["MPIProcesses", "Nodes", "Elements", ...
    "ModelSeconds", "AnalysisSeconds", "ComputedDisplacementM", ...
    "ReferenceDisplacementM", "RelativeErrorPercent", ...
    "EdgeWarpingRangeMM"]);
disp(summary);

figure("Color", "white");
responseLayout = tiledlayout(1, 2, "TileSpacing", "compact", ...
    "Padding", "compact");

nexttile;
plot(1000.0 * edgeVerticalDisplacement, edgeElevation, ...
    "-", "LineWidth", 1.8, "DisplayName", "OpenSeesSP");
hold on;
xline(1000.0 * referenceEdgeDisplacement, "--", ...
    "Timoshenko reference", "LineWidth", 1.5, ...
    "DisplayName", "Timoshenko reference");
xline(1000.0 * computedEdgeDisplacement, ":", ...
    "OpenSeesSP mean", "LineWidth", 1.5, ...
    "DisplayName", "OpenSeesSP mean");
hold off;
grid on;
legend("Location", "best");
xlabel("Vertical displacement [mm]");
ylabel("Edge elevation [m]");
absoluteLowerLimit = 1.05 * min([edgeVerticalDisplacement; ...
    referenceEdgeDisplacement]) * 1000.0;
xlim([absoluteLowerLimit, 0.0]);
title("Absolute response");

nexttile;
plot(1.0e6 * (edgeVerticalDisplacement - computedEdgeDisplacement), ...
    edgeElevation, "-", "LineWidth", 1.8);
xline(0.0, ":", "Section mean", "LineWidth", 1.3);
grid on;
xlabel("Local deviation from section mean [\mum]");
ylabel("Edge elevation [m]");
title("Magnified two-dimensional edge warping");

title(responseLayout, sprintf( ...
    "100,000 quads on %d MPI processes: mean error %.3f%%", ...
    processCount, 100.0 * relativeDisplacementError));

fprintf("OpenSeesSP plane-stress verification passed: " + ...
    "%d elements on %d MPI processes, reference error %.3f%%.\n", ...
    numberOfElements, processCount, 100.0 * relativeDisplacementError);
ops.wipe();
%%
%