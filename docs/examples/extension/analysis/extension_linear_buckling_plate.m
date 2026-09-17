%% *Linear buckling modes of a rectangular plate*
% This example reproduces the rectangular steel plate from the <https://openseesdigital.com/2025/05/24/minimal-plate-buckling-example/ 
% OpenSees Digital minimal plate buckling example>. The model uses |ShellNLDKGT| 
% elements so the tangent stiffness contains the geometric contribution required 
% by |linearBuckling|. See the OpenSeesMatlab linear buckling guide in the
% documentation for the formulation, requirements, and validation checks.
% 
% The plate is 50 in long, 8 in wide, and 1 in thick. A unit axial reference 
% load is distributed over the loaded edge, so each returned load factor is also 
% the corresponding critical load in kip.

clear;
clc;
close all;

opsMAT = OpenSeesMatlab();
ops = opsMAT.opensees;
%% *Model parameters*

plateLength = 50.0;
plateWidth = 8.0;
thickness = 1.0;
elasticModulus = 29000.0;
poissonRatio = 0.3;
referenceLoad = 1.0;

meshSize = plateWidth / 4;
numWidthElements = round(plateWidth / meshSize);
numLengthElements = round(plateLength / meshSize);
numModes = 6;
sectionTag = 1;

widthCoordinates = linspace( ...
    -plateWidth / 2, plateWidth / 2, numWidthElements + 1);
lengthCoordinates = linspace( ...
    0.0, plateLength, numLengthElements + 1);

%% *Structured triangular shell mesh*
% The plate lies in the y-z plane. Its normal displacement is therefore the 
% global x translation, while the global z axis remains vertical in the mode-shape 
% plots.

ops.wipe();
ops.model("basic", "-ndm", 3, "-ndf", 6);

for lengthIndex = 0:numLengthElements
    z = lengthCoordinates(lengthIndex + 1);
    for widthIndex = 0:numWidthElements
        y = widthCoordinates(widthIndex + 1);
        tag = plateNodeTag( ...
            widthIndex, lengthIndex, numWidthElements);
        ops.node(tag, 0.0, y, z);
    end
end

ops.section( ...
    "ElasticMembranePlateSection", sectionTag, ...
    elasticModulus, poissonRatio, thickness);

for lengthIndex = 0:(numLengthElements - 1)
    for widthIndex = 0:(numWidthElements - 1)
        firstElement = ...
            2 * (lengthIndex * numWidthElements + widthIndex) + 1;

        lowerLeft = plateNodeTag( ...
            widthIndex, lengthIndex, numWidthElements);
        lowerRight = plateNodeTag( ...
            widthIndex + 1, lengthIndex, numWidthElements);
        upperRight = plateNodeTag( ...
            widthIndex + 1, lengthIndex + 1, numWidthElements);
        upperLeft = plateNodeTag( ...
            widthIndex, lengthIndex + 1, numWidthElements);

        % Use the same clockwise orientation and diagonal for every cell.
        ops.element( ...
            "ShellNLDKGT", firstElement, ...
            upperLeft, upperRight, lowerRight, sectionTag);
        ops.element( ...
            "ShellNLDKGT", firstElement + 1, ...
            upperLeft, lowerRight, lowerLeft, sectionTag);
    end
end
%% *Boundary conditions and reference load*
% Both end edges are restrained against transverse translation. Axial motion 
% is fixed at z=0 and remains free at z=L. One drilling rotation is restrained 
% to remove the remaining rigid mode.

for widthIndex = 0:numWidthElements
    bottomNode = plateNodeTag(widthIndex, 0, numWidthElements);
    topNode = plateNodeTag( ...
        widthIndex, numLengthElements, numWidthElements);

    if widthIndex == 0
        ops.fix(bottomNode, 1, 1, 1, 1, 0, 0);
    else
        ops.fix(bottomNode, 1, 1, 1, 0, 0, 0);
    end
    ops.fix(topNode, 1, 1, 0, 0, 0, 0);
end
%% 
% 

opsMAT.vis.plotModelGUI();
%% 
% 


% The linear time series is zero at capture and reaches the unit reference
% load after one load-controlled step.
ops.timeSeries("Linear", 1);
ops.pattern("Plain", 1, 1);

numTopNodes = numWidthElements + 1;
for widthIndex = 0:numWidthElements
    topNode = plateNodeTag( ...
        widthIndex, numLengthElements, numWidthElements);
    ops.load( ...
        topNode, 0.0, 0.0, -referenceLoad / numTopNodes, ...
        0.0, 0.0, 0.0);
end

ops.constraints("Transformation");
ops.numberer("RCM");
ops.system("UmfPack");
ops.test("NormUnbalance", 1.0e-10, 30);
ops.algorithm("Newton");
ops.integrator("LoadControl", 1.0);
ops.analysis("Static");

%% *Sparse linear buckling solution*
% |capture| stores the unloaded tangent. The static step establishes the reference 
% geometric stiffness, and |solve| returns the first six positive buckling factors. 
% Analysis and solution remain explicit user operations; post-processing only 
% collects the resulting factors and node mode vectors.

captureCode = ops.linearBuckling("capture");
assert(captureCode == 0, "The base tangent could not be captured.");

analysisCode = ops.analyze(1);
assert(analysisCode == 0, ...
    "The unit reference-load analysis did not converge.");

bucklingFactors = double(ops.linearBuckling("solve", numModes));
bucklingFactors = bucklingFactors(:);

assert(issorted(bucklingFactors), ...
    "The buckling factors are not ordered.");
assert(all(bucklingFactors > 0.0), ...
    "A non-positive buckling factor was returned.");

%% *Independent first-mode check*
% The lowest mode is the weak-axis flexural mode of the plate strip. Euler's 
% pinned-column result provides an independent check of the finite-element solution.

weakAxisInertia = plateWidth * thickness^3 / 12;
eulerLoad = pi^2 * elasticModulus * weakAxisInertia / plateLength^2;
relativeError = abs(bucklingFactors(1) - eulerLoad) / eulerLoad;

assert(relativeError < 0.02, ...
    "The first buckling load differs from Euler theory by more than 2%%.");

results = table( ...
    (1:numModes).', bucklingFactors, ...
    VariableNames=["Mode", "CriticalLoad_kip"]);
disp(results);
fprintf("Euler weak-axis load: %.6f kip\n", eulerLoad);
fprintf("First-mode difference: %.3f %%n", 100 * relativeError);
%% *Collect all buckling modes for post-processing*
% |getLinearBucklingData| does not repeat the analysis. It reads all six node 
% mode vectors already stored by |linearBuckling("solve", 6)| and packages them 
% for the normal OpenSeesMatlab visualization functions.

bucklingData = opsMAT.post.getLinearBucklingData( ...
    bucklingFactors, ...
    IncludeModelInfo=true, ...
    InterpolateBeam=false);
%% *First six buckling modes*
% The plots use the built-in |plotEigen| geometry engine in buckling mode. Displacements 
% are automatically enlarged for visibility and colored by signed global x amplitude. 
% They are eigenvectors, not physical displacements at the critical load. Equal 
% data aspect ratios preserve the actual 50:8 plate proportions.

figure( ...
    Name="First six linear buckling modes", ...
    Color="white", ...
    Position=[80, 80, 1500, 940]);
layout = tiledlayout(2, 3, ...
    TileSpacing="compact", Padding="compact");

plotOptions = opsMAT.vis.defaultPlotEigenOptions;
plotOptions.mode.type = "buckling";
plotOptions.mode.component = "ux";
plotOptions.mode.autoScale = true;
plotOptions.mode.scale = 1.0;
plotOptions.mode.showUndeformed = false;
plotOptions.color.useColormap = true;
plotOptions.color.colormap = turbo(256);
plotOptions.color.clim = [-1.0, 1.0];
plotOptions.unstructured.showEdges = true;
plotOptions.unstructured.edgeColor = [0.15, 0.15, 0.15];
plotOptions.unstructured.edgeWidth = 0.5;
plotOptions.scalar.useAbsoluteForComponent = false;
plotOptions.scalar.showColorbar = false;
plotOptions.fixed.show = true;
plotOptions.general.grid = false;
plotOptions.general.box = true;

for mode = 1:numModes
    ax = nexttile(layout);
    opsMAT.vis.plotEigen( ...
        mode, bucklingData, opts=plotOptions, ax=ax);
    view(ax, -32, 14);
    axis(ax, "equal");
    axis(ax, "off");
end

title(layout, "Linear buckling modes of the rectangular plate");
opsMAT.vis.polyscope.plotEigen(bucklingData);
%% 
% 
%% 
% The same data can also be explored interactively with |opsMAT.vis.plotEigenGUI(bucklingData)| 
% or |opsMAT.vis.polyscope.plotEigen(bucklingData)|.

ops.wipe();
%% 
% 

function tag = plateNodeTag(widthIndex, lengthIndex, numWidthElements)
%PLATENODETAG Return the one-based node tag for the structured plate mesh.
tag = lengthIndex * (numWidthElements + 1) + widthIndex + 1;
end
