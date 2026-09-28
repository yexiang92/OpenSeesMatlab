%[text] # Two-dimensional liquefiable-soil analysis
%[text] Build and analyze a saturated soil column with `quadUP` elements and a
%[text] pressure-dependent material. Recorder files contain the response histories.
%%
function results = liquefiableSoil2D(ops, outdir, gmPath)
%LIQUEFIABLESOIL2D Analyze a saturated plane-strain soil column.
%
%   results = liquefiableSoil2D(ops)
%   results = liquefiableSoil2D(ops, outdir)
%   results = liquefiableSoil2D(ops, outdir, gmPath)
%
%   Input
%   -----
%   ops    : OpenSeesMatlab OpenSees command object.
%   outdir : Output directory for recorder files.
%            Default: "openseesmatlab.output"
%   gmPath : Ground-motion acceleration file.
%            Default: "acc_value.txt"
%
%   Output
%   ------
%   results.ok                  : Final OpenSees analyze return code.
%   results.outdir              : Recorder output directory.
%   results.gmPath              : Ground-motion file path.
%   results.finalTime           : Final analysis time.
%   results.dynamicTimeStep     : Final dynamic time step used.
%   results.initialDynamicSteps : Initial requested dynamic steps.
%   results.elapsedTime         : Wall-clock time of the function.
%   results.a0                  : Rayleigh mass-proportional coefficient.
%   results.a1                  : Rayleigh stiffness-proportional coefficient.

exampleFolder = fileparts(mfilename("fullpath"));
if nargin < 2 || isempty(outdir)
    outdir = fullfile(exampleFolder, "openseesmatlab.output");
end

if nargin < 3 || isempty(gmPath)
    gmPath = fullfile(exampleFolder, "acc_value.txt");
end

outdir = string(outdir);
gmPath = string(gmPath);

if ~isfolder(outdir)
    mkdir(outdir);
end

tStart = tic;

% -------------------------------------------------------------------------
% 1. User-defined variables
% -------------------------------------------------------------------------

numXele = 20;             % Number of elements in the horizontal direction
numYele = 10;             % Number of elements in the vertical direction
xSize = 1.0;              % Element size in x direction, m
ySize = 1.0;              % Element size in y direction, m

numTotEle = numXele * numYele;
numXnode = numXele + 1;
numYnode = numYele + 1;

% Soil material parameters
nod = 2.0;
satDensity = 1.9;
H2ODensity = 1.0; %#ok<NASGU>
shear = 10.0e4;
bulk1 = 23.3e4;
fricAngle = 33.5;
peakShear = 0.1;
refPress = 101.0;
pressDependCoef = 0.5;
ptAngle = 25.5;

cont1 = 0.045;
cont2 = 5.0;
cont3 = 0.15;

dilat1 = 0.06;
dilat2 = 3.0;
dilat3 = 0.25;

numSurf = 20;
liquefac1 = 1.0;
liquefac2 = 0.0;

voidRatio = 0.7;
cs1 = 0.9;
cs2 = 0.02;
cs3 = 0.7;
pa = 101.0;

% Element parameters
bulk = 2.2e6 / voidRatio;
fmass = 1.0;
initHperm = 100.0;
initVperm = 100.0;
hPerm = 2.0e-3;
vPerm = 2.0e-3;
accGravity = 9.81;
thick = 1.0;
recDT = 0.1;

% -------------------------------------------------------------------------
% 2. Model, nodes, material, and elements
% -------------------------------------------------------------------------

ops.wipe();
ops.model('BasicBuilder', '-ndm', 2, '-ndf', 3);

% Create regular grid nodes.
for i = 1:numXnode
    for j = 1:numYnode
        xCoord = (i - 1) * xSize;
        yCoord = (j - 1) * ySize;
        nodeTag = i + (j - 1) * numXnode;
        ops.node(nodeTag, xCoord, yCoord);
    end
end

% Pressure-dependent multi-yield material.
matTag = 1;
ops.nDMaterial('PressureDependMultiYield02', matTag, nod, satDensity, ...
    shear, bulk1, fricAngle, peakShear, refPress, pressDependCoef, ...
    ptAngle, cont1, cont3, dilat1, dilat3, numSurf, cont2, dilat2, ...
    liquefac1, liquefac2, cs3, cs1, cs2, voidRatio, pa);

% Create quadUP elements.
for i = 1:numXele
    for j = 1:numYele
        eleTag = i + (j - 1) * numXele;

        n1 = i + (j - 1) * numXnode;
        n2 = i + (j - 1) * numXnode + 1;
        n4 = i + j * numXnode + 1;
        n3 = i + j * numXnode;

        ops.element('quadUP', eleTag, n1, n2, n4, n3, ...
            thick, matTag, bulk, fmass, ...
            initHperm / accGravity / fmass, ...
            initVperm / accGravity / fmass, ...
            0.0, -accGravity, 0.0);
    end
end

% Elastic material stage for gravity initialization.
ops.updateMaterialStage('-material', matTag, '-stage', 0);

% -------------------------------------------------------------------------
% 3. Boundary conditions and equalDOF constraints
% -------------------------------------------------------------------------

for i = 1:numXnode
    % Base nodes: fix x and y displacements, leave pore pressure free.
    ops.fix(i, 1, 1, 0);

    % Surface nodes: fix pore-pressure DOF for drainage.
    surfaceNode = (numYnode - 1) * numXnode + i;
    ops.fix(surfaceNode, 0, 0, 1);
end

% Tie displacement DOFs at the same elevation between two side nodes.
for i = 1:(numYnode - 1)
    nodeLeft = i * numXnode + 1;
    nodeRight = i * numXnode + numXnode;
    ops.equalDOF(nodeLeft, nodeRight, 1, 2);
end

% -------------------------------------------------------------------------
% 4. Gravity analysis
% -------------------------------------------------------------------------

ops.numberer('RCM');
ops.system('ProfileSPD');
ops.test('NormDispIncr', 1.0e-6, 50, 0);
ops.algorithm('KrylovNewton');
ops.constraints('Penalty', 1.0e18, 1.0e18);

gamma = 1.5;
beta = (gamma + 0.5)^2 / 4.0;
ops.integrator('Newmark', gamma, beta);
ops.analysis('Transient');

okElasticGravity = ops.analyze(10, 5.0e3);

% Switch to elastoplastic stage and finish gravity analysis.
ops.updateMaterialStage('-material', matTag, '-stage', 1);
okPlasticGravity = ops.analyze(10, 1.0e1);

ops.wipeAnalysis();
ops.setTime(0.0);

% -------------------------------------------------------------------------
% 5. Update permeability parameters for dynamic analysis
% -------------------------------------------------------------------------

parameterTag = 10000;

for eleTag = 1:numTotEle
    ops.parameter(parameterTag + 1, 'element', eleTag, 'vPerm');
    ops.parameter(parameterTag + 2, 'element', eleTag, 'hPerm');
    parameterTag = parameterTag + 2;
end

parameterTag = 10000;

for eleTag = 1:numTotEle
    ops.updateParameter(parameterTag + 1, vPerm / accGravity / fmass);
    ops.updateParameter(parameterTag + 2, hPerm / accGravity / fmass);
    parameterTag = parameterTag + 2;
end

% -------------------------------------------------------------------------
% 6. Recorders
% -------------------------------------------------------------------------

nodeList1 = [53, 95, 137, 158, 179, 221];

ops.recorder('Node', '-file', char(fullfile(outdir, 'disp2.txt')), ...
    '-node', nodeList1, '-time', '-dT', recDT, '-dof', 1, 2, 'disp');

ops.recorder('Node', '-file', char(fullfile(outdir, 'Ydisp2.txt')), ...
    '-node', nodeList1, '-time', '-dT', recDT, '-dof', 2, 'disp');

ops.recorder('Node', '-file', char(fullfile(outdir, 'pwp1.txt')), ...
    '-node', nodeList1, '-time', '-dT', recDT, '-dof', 3, 'vel');

ops.recorder('Node', '-file', char(fullfile(outdir, 'acc1.txt')), ...
    '-node', nodeList1, '-time', '-dT', recDT, '-dof', 1, 'accel');

recEleTags = [10, 70, 130, 190];

for eleTag = recEleTags
    ops.recorder('Element', '-file', char(fullfile(outdir, sprintf('stress%d.txt', eleTag))), ...
        '-time', '-dT', recDT, '-ele', eleTag, 'material', '1', 'stress');

    ops.recorder('Element', '-file', char(fullfile(outdir, sprintf('strain%d.txt', eleTag))), ...
        '-time', '-dT', recDT, '-ele', eleTag, 'material', '1', 'strain');
end

% -------------------------------------------------------------------------
% 7. Dynamic analysis setup
% -------------------------------------------------------------------------

patternTag = 10;
accelSeriesTag = 1;
direction = 1;

ops.timeSeries('Path', accelSeriesTag, ...
    '-dt', 0.01, '-filePath', char(gmPath), '-factor', accGravity);

ops.pattern('UniformExcitation', patternTag, direction, '-accel', accelSeriesTag);

ops.constraints('Transformation');
ops.numberer('RCM');



ops.system('UmfPack');
% cudssPath = "C:\Program Files\NVIDIA cuDSS\v0.8\bin\12";
% cudaPath = "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v12.6\bin";
% CuDSSOptions = {"-cudaPath", cudaPath, "-cudssPath", cudssPath, "-verbose"};
% ops.system("CuDSS", CuDSSOptions{:});

tol = 1.0e-4;
maxNumIter = 100;
printFlag = 0;
testType = 'NormDispIncr';
ops.test(testType, tol, maxNumIter, printFlag);

ops.algorithm('KrylovNewton');

newmarkGamma = 0.5;
newmarkBeta = 0.25;
ops.integrator('Newmark', newmarkGamma, newmarkBeta);
ops.analysis('Transient');

% Rayleigh damping.
damp = 0.02;
omega1 = 2.0 * pi * 1.0;
omega2 = 2.0 * pi * 20.0;
a0 = 2.0 * damp * omega1 * omega2 / (omega1 + omega2);
a1 = 2.0 * damp / (omega1 + omega2);

ops.rayleigh(a0, a1, 0.0, 0.0);

% -------------------------------------------------------------------------
% 8. Dynamic analysis with two-level time-step reduction
% -------------------------------------------------------------------------

dT = 0.005;
nSteps = 6500;

okDynamic = ops.analyze(nSteps, dT);
dynamicTimeStep = dT;

if okDynamic ~= 0
    currentTime = ops.getTime();
    markedTime = currentTime;
    currentStep = currentTime / dT;

    remainingStepsReal = (nSteps - currentStep) * 2.0;
    remainingSteps = int32(remainingStepsReal);

    dT = dT / 2.0;
    dynamicTimeStep = dT;

    okDynamic = ops.analyze(remainingSteps, dT);

    if okDynamic ~= 0
        currentTime = ops.getTime();
        currentStep = (currentTime - markedTime) / dT;

        remainingSteps = int32((remainingStepsReal - currentStep) * 2.0);

        dT = dT / 2.0;
        dynamicTimeStep = dT;

        okDynamic = ops.analyze(remainingSteps, dT);
    end
end

% -------------------------------------------------------------------------
% 9. Return results and clean up
% -------------------------------------------------------------------------

results = struct();
results.ok = okDynamic;
results.okElasticGravity = okElasticGravity;
results.okPlasticGravity = okPlasticGravity;
results.outdir = outdir;
results.gmPath = gmPath;
results.finalTime = ops.getTime();
results.dynamicTimeStep = dynamicTimeStep;
results.initialDynamicSteps = nSteps;
results.a0 = a0;
results.a1 = a1;
results.elapsedTime = toc(tStart);

% ops.wipe();

end

%[appendix]{"version":"1.0"}
%---
%[metadata:view]
%   data: {"layout":"onright"}
%---
