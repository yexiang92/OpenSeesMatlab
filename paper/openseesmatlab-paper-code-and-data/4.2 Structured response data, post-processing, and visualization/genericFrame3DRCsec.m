%[text] # Three-dimensional reinforced-concrete frame
%[text] Build a parameterized RC frame with fiber sections, rigid diaphragms,
%[text] gravity loading, modal analysis, recorders, and optional bidirectional
%[text] earthquake excitation. This is a MATLAB translation of the OpenSees
%[text] Example 8 workflow.
%%
function results = genericFrame3DRCsec(opsMAT, params)
%GENERICFRAME3DRCSEC Build and analyze a three-dimensional RC frame.
%
% Notes:
%   1) STKO/display-only commands are removed.
%   2) The model remains parameterized through the params structure.
%   3) The original Tcl nonlinearBeamColumn elements are converted to
%      forceBeamColumn elements with explicit Lobatto beamIntegration objects,
%      which is the safer OpenSeesMatlab form.
%
% Basic usage:
%   opsMat = OpenSeesMatlab();
%   ops = opsMat.opensees;
%   results = genericFrame3DRCsec(ops);
%
% Parameterized usage:
%   params = struct();
%   params.NStory = 2;
%   params.NBay = 2;
%   params.NBayZ = 2;
%   params.dataDir = "Data";
%   params.GMdir = "../GMfiles";
%   params.GMfiles = ["H-E01140", "H-E12140"];
%   params.GMdirections = [1, 2];
%   params.GMfactors = [1.5, 0.75];
%   results = genericFrame3DRCsec(ops, params);

if nargin < 2 || isempty(params)
    params = struct();
end

ops = opsMAT.opensees;
exampleFolder = fileparts(mfilename("fullpath"));

ticTotal = tic;

% -------------------------------------------------------------------------
% Units
% -------------------------------------------------------------------------
u = defineUnits();

% -------------------------------------------------------------------------
% Default parameters
% -------------------------------------------------------------------------
params = setDefault(params, "dataDir", fullfile(exampleFolder, "Data"));
params = setDefault(params, "GMdir", fullfile(exampleFolder, "GMfiles"));

params = setDefault(params, "NStory", 2);
params = setDefault(params, "NBay", 2);
params = setDefault(params, "NBayZ", 2);

params = setDefault(params, "LCol", 14 * u.ft);
params = setDefault(params, "LBeam", 24 * u.ft);
params = setDefault(params, "LGird", 24 * u.ft);

params = setDefault(params, "Dlevel", 10000);
params = setDefault(params, "Dframe", 100);

params = setDefault(params, "RigidDiaphragm", "ON");
params = setDefault(params, "SectionType", "FiberSection");

params = setDefault(params, "runDynamic", true);
params = setDefault(params, "GMfiles", ["H-E01140", "H-E12140"]);
params = setDefault(params, "GMdirections", [1, 2]);
params = setDefault(params, "GMfactors", [1.5, 0.75]);
params = setDefault(params, "DtAnalysis", 0.01 * u.sec);
params = setDefault(params, "TmaxAnalysis", 10.0 * u.sec);

params = setDefault(params, "xDamp", 0.02);
params = setDefault(params, "MpropSwitch", 1.0);
params = setDefault(params, "KcurrSwitch", 0.0);
params = setDefault(params, "KcommSwitch", 1.0);
params = setDefault(params, "KinitSwitch", 0.0);
params = setDefault(params, "nEigenI", 1);
params = setDefault(params, "nEigenJ", 3);

params = setDefault(params, "numIntgrPts", 5);

dataDir = string(params.dataDir);
GMdir = string(params.GMdir);
if ~isfolder(dataDir)
    mkdir(dataDir);
end
if ~isfolder(GMdir)
    % Do not error here because the user may only want to build the model.
    % The dynamic analysis will error later if the requested records are absent.
end

% -------------------------------------------------------------------------
% SET UP
% -------------------------------------------------------------------------
ops.wipe();
ops.model('basic', '-ndm', 3, '-ndf', 6);

NStory = params.NStory;
NBay = params.NBay;
NBayZ = params.NBayZ;
NFrame = NBayZ + 1;

LCol = params.LCol;
LBeam = params.LBeam;
LGird = params.LGird;
Dlevel = params.Dlevel;
Dframe = params.Dframe;

% -------------------------------------------------------------------------
% Nodal coordinates
% -------------------------------------------------------------------------
for frame = 1:NFrame
    % Z-up convention used in this converted model:
    %   X = beam/span direction, Y = transverse frame/girder direction, Z = height.
    Y = (frame - 1) * LGird;
    for level = 1:(NStory + 1)
        Z = (level - 1) * LCol;
        for pier = 1:(NBay + 1)
            X = (pier - 1) * LBeam;
            nodeID = level * Dlevel + frame * Dframe + pier;
            ops.node(nodeID, X, Y, Z);
        end
    end
end

% -------------------------------------------------------------------------
% Rigid diaphragm nodes
% -------------------------------------------------------------------------
iMasterNode = [];
if strcmpi(string(params.RigidDiaphragm), "ON")
    Xa = (NBay * LBeam) / 2.0;
    Ya = (NFrame - 1) * LGird / 2.0;

    for level = 2:(NStory + 1)
        Z = (level - 1) * LCol;
        masterNodeID = 9900 + level;
        ops.node(masterNodeID, Xa, Ya, Z);

        % Z-up rigid diaphragm master node. The diaphragm lies in the X-Y
        % plane; therefore UZ, RX, and RY are restrained, while UX, UY,
        % and RZ remain active as floor rigid-body DOFs.
        ops.fix(masterNodeID, 0, 0, 1, 1, 1, 0);
        iMasterNode(end + 1) = masterNodeID; %#ok<AGROW>

        perpDirn = 3;
        for frame = 1:NFrame
            for pier = 1:(NBay + 1)
                nodeID = level * Dlevel + frame * Dframe + pier;
                ops.rigidDiaphragm(perpDirn, masterNodeID, nodeID);
            end
        end
    end
end

% -------------------------------------------------------------------------
% Support nodes and boundary conditions
% -------------------------------------------------------------------------
iSupportNode = [];
level = 1;
for frame = 1:NFrame
    for pier = 1:(NBay + 1)
        nodeID = level * Dlevel + frame * Dframe + pier;
        iSupportNode(end + 1) = nodeID; %#ok<AGROW>

        % Z-up form of the original base restraint. The translational DOFs
        % are fixed; the rotational restraint about the original vertical
        % axis is mapped from RY to RZ.
        ops.fix(nodeID, 1, 1, 1, 0, 0, 1);
    end
end

IDctrlNode = int32((NStory + 1) * Dlevel + 1 * Dframe + 1);
IDctrlDOF = 1;
LBuilding = NStory * LCol;

% -------------------------------------------------------------------------
% Sections and materials
% -------------------------------------------------------------------------
sec = defineSectionsAndMaterials(ops, u, params);

ColSecTag = sec.ColSecTag;
BeamSecTag = sec.BeamSecTag;
GirdSecTag = sec.GirdSecTag;
IDconcCore = sec.IDconcCore;
IDSteel = sec.IDSteel;
HCol = sec.HCol;
BCol = sec.BCol;
cover = sec.cover;
QdlCol = sec.QdlCol;
QBeam = sec.QBeam;
QGird = sec.QGird;

% -------------------------------------------------------------------------
% Geometric transformations
% -------------------------------------------------------------------------
IDColTransf = 1;
IDBeamTransf = 2;
IDGirdTransf = 3;

ColTransfType = 'Linear';
% Z-up transformation of the original local-axis definitions.
% Original Tcl was Y-up: columns/beams used vecxz = [0 0 1].
% After mapping old Z -> new Y and old Y -> new Z, this becomes [0 1 0].
ops.geomTransf(ColTransfType, IDColTransf, 0, 1, 0);
ops.geomTransf('Linear', IDBeamTransf, 0, 1, 0);
ops.geomTransf('Linear', IDGirdTransf, 1, 0, 0);

% -------------------------------------------------------------------------
% Beam integrations and frame elements
% -------------------------------------------------------------------------
numIntgrPts = params.numIntgrPts;

% Explicit beamIntegration objects. Integration tags are set equal to
% section tags to keep the model compact and parameterized.
ops.beamIntegration('Lobatto', ColSecTag,  ColSecTag,  numIntgrPts);
ops.beamIntegration('Lobatto', BeamSecTag, BeamSecTag, numIntgrPts);
ops.beamIntegration('Lobatto', GirdSecTag, GirdSecTag, numIntgrPts);

N0col = 10000 - 1;
for frame = 1:NFrame
    for level = 1:NStory
        for pier = 1:(NBay + 1)
            elemID = N0col + level * Dlevel + frame * Dframe + pier;
            nodeI = level * Dlevel + frame * Dframe + pier;
            nodeJ = (level + 1) * Dlevel + frame * Dframe + pier;

            % Tcl original:
            % element nonlinearBeamColumn elemID nodeI nodeJ numIntgrPts ColSecTag IDColTransf
            % OpenSeesMatlab-safe form:
            ops.element('forceBeamColumn', elemID, nodeI, nodeJ, IDColTransf, ColSecTag);
        end
    end
end

N0beam = 1000000;
for frame = 1:NFrame
    for level = 2:(NStory + 1)
        for bay = 1:NBay
            elemID = N0beam + level * Dlevel + frame * Dframe + bay;
            nodeI = level * Dlevel + frame * Dframe + bay;
            nodeJ = level * Dlevel + frame * Dframe + bay + 1;

            ops.element('forceBeamColumn', elemID, nodeI, nodeJ, IDBeamTransf, BeamSecTag);
        end
    end
end

N0gird = 2000000;
for frame = 1:(NFrame - 1)
    for level = 2:(NStory + 1)
        for bay = 1:(NBay + 1)
            elemID = N0gird + level * Dlevel + frame * Dframe + bay;
            nodeI = level * Dlevel + frame * Dframe + bay;
            nodeJ = level * Dlevel + (frame + 1) * Dframe + bay;

            ops.element('forceBeamColumn', elemID, nodeI, nodeJ, IDGirdTransf, GirdSecTag);
        end
    end
end

% -------------------------------------------------------------------------
% Gravity loads, weights, and masses
% -------------------------------------------------------------------------
GammaConcrete = 150 * u.pcf;
Tslab = 6 * u.in;
Lslab = LGird / 2.0;
DLfactor = 1.0;

Qslab = GammaConcrete * Tslab * Lslab * DLfactor;
QdlBeam = Qslab + QBeam;
QdlGird = QGird;

WeightCol = QdlCol * LCol;
WeightBeam = QdlBeam * LBeam;
WeightGird = QdlGird * LGird;

iFloorWeight = [];
WeightTotal = 0.0;
sumWiHi = 0.0;

for frame = 1:NFrame
    if frame == 1 || frame == NFrame
        GirdWeightFact = 1;
    else
        GirdWeightFact = 2;
    end

    for level = 2:(NStory + 1)
        FloorWeight = 0.0;

        if level == (NStory + 1)
            ColWeightFact = 1;
        else
            ColWeightFact = 2;
        end

        for pier = 1:(NBay + 1)
            if pier == 1 || pier == (NBay + 1)
                BeamWeightFact = 1;
            else
                BeamWeightFact = 2;
            end

            WeightNode = ColWeightFact * WeightCol / 2.0 + ...
                         BeamWeightFact * WeightBeam / 2.0 + ...
                         GirdWeightFact * WeightGird / 2.0;

            MassNode = WeightNode / u.g;
            nodeID = level * Dlevel + frame * Dframe + pier;

            % Z-up form of original horizontal floor mass. The original
            % Tcl used mass in X and old-Z; after mapping old-Z -> new-Y,
            % the horizontal mass is assigned to DOF 1 and DOF 2.
            ops.mass(nodeID, MassNode, MassNode, 0.0, 0.0, 0.0, 0.0);

            FloorWeight = FloorWeight + WeightNode;
        end

        iFloorWeight(end + 1) = FloorWeight; %#ok<AGROW>
        WeightTotal = WeightTotal + FloorWeight;
        sumWiHi = sumWiHi + FloorWeight * (level - 1) * LCol;
    end
end

MassTotal = WeightTotal / u.g;

% -------------------------------------------------------------------------
% Eigenvalue analysis
% -------------------------------------------------------------------------
numModes = 3;
lambda = ops.eigen(numModes);
lambda = double(lambda(:));
omega = sqrt(lambda);
f = omega / (2 * pi);
T = (2 * pi) ./ omega;

% -------------------------------------------------------------------------
% Lateral-load distribution for static pushover
% -------------------------------------------------------------------------
iFj = zeros(1, NStory);
for level = 2:(NStory + 1)
    FloorWeight = iFloorWeight(level - 1);
    FloorHeight = (level - 1) * LCol;
    iFj(level - 1) = FloorWeight * FloorHeight / sumWiHi * WeightTotal;
end

iNodePush = iMasterNode;
iFPush = iFj;

% -------------------------------------------------------------------------
% Recorders
% -------------------------------------------------------------------------
FreeNodeID = NFrame * Dframe + (NStory + 1) * Dlevel + (NBay + 1);
SupportNodeFirst = iSupportNode(1);
SupportNodeLast = iSupportNode(end);
FirstColumn = N0col + 1 * Dframe + 1 * Dlevel + 1;

ops.recorder('Node', '-file', fullfile(dataDir, 'DFree.out'), ...
    '-time', '-node', FreeNodeID, '-dof', 1, 2, 3, 'disp');

ops.recorder('Node', '-file', fullfile(dataDir, 'DBase.out'), ...
    '-time', '-nodeRange', SupportNodeFirst, SupportNodeLast, ...
    '-dof', 1, 2, 3, 'disp');

ops.recorder('Node', '-file', fullfile(dataDir, 'RBase.out'), ...
    '-time', '-nodeRange', SupportNodeFirst, SupportNodeLast, ...
    '-dof', 1, 2, 3, 'reaction');

ops.recorder('Drift', '-file', fullfile(dataDir, 'DrNode.out'), ...
    '-time', '-iNode', SupportNodeFirst, '-jNode', FreeNodeID, ...
    '-dof', 1, '-perpDirn', 3);

ops.recorder('Element', '-file', fullfile(dataDir, 'Fel1.out'), ...
    '-time', '-ele', FirstColumn, 'localForce');

ops.recorder('Element', '-file', fullfile(dataDir, 'ForceEle1sec1.out'), ...
    '-time', '-ele', FirstColumn, 'section', 1, 'force');

ops.recorder('Element', '-file', fullfile(dataDir, 'DefoEle1sec1.out'), ...
    '-time', '-ele', FirstColumn, 'section', 1, 'deformation');

ops.recorder('Element', '-file', fullfile(dataDir, sprintf('ForceEle1sec%d.out', numIntgrPts)), ...
    '-time', '-ele', FirstColumn, 'section', numIntgrPts, 'force');

ops.recorder('Element', '-file', fullfile(dataDir, sprintf('DefoEle1sec%d.out', numIntgrPts)), ...
    '-time', '-ele', FirstColumn, 'section', numIntgrPts, 'deformation');

yFiber = HCol / 2.0 - cover;
zFiber = BCol / 2.0 - cover;

ops.recorder('Element', '-file', fullfile(dataDir, 'SSconcEle1sec1.out'), ...
    '-time', '-ele', FirstColumn, 'section', numIntgrPts, ...
    'fiber', yFiber, zFiber, IDconcCore, 'stressStrain');

ops.recorder('Element', '-file', fullfile(dataDir, 'SSreinfEle1sec1.out'), ...
    '-time', '-ele', FirstColumn, 'section', numIntgrPts, ...
    'fiber', yFiber, zFiber, IDSteel, 'stressStrain');

% -------------------------------------------------------------------------
% Gravity loading
% -------------------------------------------------------------------------
ops.timeSeries('Linear', 101);
ops.pattern('Plain', 101, 101);

for frame = 1:NFrame
    for level = 1:NStory
        for pier = 1:(NBay + 1)
            elemID = N0col + level * Dlevel + frame * Dframe + pier;
            ops.eleLoad('-ele', elemID, '-type', '-beamUniform', 0.0, 0.0, -QdlCol);
        end
    end
end

for frame = 1:NFrame
    for level = 2:(NStory + 1)
        for bay = 1:NBay
            elemID = N0beam + level * Dlevel + frame * Dframe + bay;
            ops.eleLoad('-ele', elemID, '-type', '-beamUniform', -QdlBeam, 0.0);
        end
    end
end

for frame = 1:(NFrame - 1)
    for level = 2:(NStory + 1)
        for bay = 1:(NBay + 1)
            elemID = N0gird + level * Dlevel + frame * Dframe + bay;
            ops.eleLoad('-ele', elemID, '-type', '-beamUniform', -QdlGird, 0.0);
        end
    end
end

% Gravity-analysis parameters
Tol = 1.0e-8;
constraintsTypeGravity = 'Plain';
if strcmpi(string(params.RigidDiaphragm), "ON")
    constraintsTypeGravity = 'Lagrange';
end

ops.constraints(constraintsTypeGravity);
ops.numberer('RCM');
ops.system('BandGeneral');
ops.test('EnergyIncr', Tol, 6);
ops.algorithm('Newton');

NstepGravity = 10;
DGravity = 1.0 / NstepGravity;

ops.integrator('LoadControl', DGravity);
ops.analysis('Static');

okGravity = ops.analyze(NstepGravity);
ops.loadConst('-time', 0.0);
ops.wipeAnalysis();

% -------------------------------------------------------------------------
% Dynamic bidirectional earthquake analysis
% -------------------------------------------------------------------------
%
odb = opsMAT.post.createODB("MyODB", floatPrecision="float");


okDynamic = NaN;
rayleighCoefficients = struct();

if params.runDynamic
    dyn = runBidirectionalDynamicAnalysis(ops, params, u, dataDir, GMdir);
    okDynamic = dyn.okDynamic;
    rayleighCoefficients = dyn.rayleighCoefficients;
end

odb.close();

% -------------------------------------------------------------------------
% Return results
% -------------------------------------------------------------------------
results = struct();
results.params = params;
results.units = u;
results.dataDir = dataDir;
results.GMdir = GMdir;
results.NFrame = NFrame;
results.iSupportNode = iSupportNode;
results.iMasterNode = iMasterNode;
results.IDctrlNode = IDctrlNode;
results.IDctrlDOF = IDctrlDOF;
results.LBuilding = LBuilding;
results.MassTotal = MassTotal;
results.WeightTotal = WeightTotal;
results.iFloorWeight = iFloorWeight;
results.iFj = iFj;
results.iNodePush = iNodePush;
results.iFPush = iFPush;
results.lambda = lambda;
results.omega = omega;
results.frequency = f;
results.period = T;
results.okGravity = okGravity;
results.okDynamic = okDynamic;
results.finalTime = ops.getTime();
results.rayleighCoefficients = rayleighCoefficients;
results.elapsedTime = toc(ticTotal);

end

% =========================================================================
% Local functions
% =========================================================================

function params = setDefault(params, name, value)
if ~isfield(params, name) || isempty(params.(name))
    params.(name) = value;
end
end

function u = defineUnits()
u = struct();

u.in = 1.0;
u.kip = 1.0;
u.sec = 1.0;

u.LunitTXT = "inch";
u.FunitTXT = "kip";
u.TunitTXT = "sec";

u.ft = 12.0 * u.in;
u.ksi = u.kip / (u.in^2);
u.psi = u.ksi / 1000.0;
u.lbf = u.psi * u.in * u.in;
u.pcf = u.lbf / (u.ft^3);
u.psf = u.lbf / (u.ft^3);

u.in2 = u.in * u.in;
u.in4 = u.in^4;
u.cm = u.in / 2.54;

u.PI = 2 * asin(1.0);
u.g = 32.2 * u.ft / (u.sec^2);

u.Ubig = 1.0e10;
u.Usmall = 1.0 / u.Ubig;
end

function sec = defineSectionsAndMaterials(ops, u, params)
% Define RC materials and rectangular RC fiber sections.

ColSecTag = 1;
BeamSecTag = 2;
GirdSecTag = 3;

ColSecTagFiber = 4;
BeamSecTagFiber = 5;
GirdSecTagFiber = 6;

SecTagTorsion = 70;

HCol = 18 * u.in;
BCol = HCol;

HBeam = 24 * u.in;
BBeam = 18 * u.in;

HGird = 24 * u.in;
BGird = 18 * u.in;

SectionType = string(params.SectionType);

if strcmpi(SectionType, "Elastic")
    fc = 4000 * u.psi;
    Ec = 57 * u.ksi * sqrt(fc / u.psi);
    nu = 0.2;
    Gc = Ec / 2.0 / (1.0 + nu);
    J = u.Ubig;

    AgCol = HCol * BCol;
    IzCol = 0.5 * 1.0 / 12.0 * BCol * HCol^3;
    IyCol = 0.5 * 1.0 / 12.0 * HCol * BCol^3;

    AgBeam = HBeam * BBeam;
    IzBeam = 0.5 * 1.0 / 12.0 * BBeam * HBeam^3;
    IyBeam = 0.5 * 1.0 / 12.0 * HBeam * BBeam^3;

    AgGird = HGird * BGird;
    IzGird = 0.5 * 1.0 / 12.0 * BGird * HGird^3;
    IyGird = 0.5 * 1.0 / 12.0 * HGird * BGird^3;

    ops.section('Elastic', ColSecTag, Ec, AgCol, IzCol, IyCol, Gc, J);
    ops.section('Elastic', BeamSecTag, Ec, AgBeam, IzBeam, IyBeam, Gc, J);
    ops.section('Elastic', GirdSecTag, Ec, AgGird, IzGird, IyGird, Gc, J);

    IDconcCore = 1;
    IDSteel = 2;
    cover = 2.5 * u.in;

elseif strcmpi(SectionType, "FiberSection")
    mat = defineRCMaterials(ops, u);

    IDconcCore = mat.IDconcCore;
    IDconcCover = mat.IDconcCover;
    IDSteel = mat.IDSteel;

    cover = 2.5 * u.in;

    numBarsTopCol = 8;
    numBarsBotCol = 8;
    numBarsIntCol = 6;

    barAreaTopCol = 1.0 * u.in * u.in;
    barAreaBotCol = 1.0 * u.in * u.in;
    barAreaIntCol = 1.0 * u.in * u.in;

    numBarsTopBeam = 6;
    numBarsBotBeam = 6;
    numBarsIntBeam = 2;

    barAreaTopBeam = 1.0 * u.in * u.in;
    barAreaBotBeam = 1.0 * u.in * u.in;
    barAreaIntBeam = 1.0 * u.in * u.in;

    numBarsTopGird = 6;
    numBarsBotGird = 6;
    numBarsIntGird = 2;

    barAreaTopGird = 1.0 * u.in * u.in;
    barAreaBotGird = 1.0 * u.in * u.in;
    barAreaIntGird = 1.0 * u.in * u.in;

    nfCoreY = 12;
    nfCoreZ = 12;
    nfCoverY = 8;
    nfCoverZ = 8;

    BuildRCrectSection(ops, ColSecTagFiber, HCol, BCol, cover, cover, ...
        IDconcCore, IDconcCover, IDSteel, ...
        numBarsTopCol, barAreaTopCol, ...
        numBarsBotCol, barAreaBotCol, ...
        numBarsIntCol, barAreaIntCol, ...
        nfCoreY, nfCoreZ, nfCoverY, nfCoverZ);

    BuildRCrectSection(ops, BeamSecTagFiber, HBeam, BBeam, cover, cover, ...
        IDconcCore, IDconcCover, IDSteel, ...
        numBarsTopBeam, barAreaTopBeam, ...
        numBarsBotBeam, barAreaBotBeam, ...
        numBarsIntBeam, barAreaIntBeam, ...
        nfCoreY, nfCoreZ, nfCoverY, nfCoverZ);

    BuildRCrectSection(ops, GirdSecTagFiber, HGird, BGird, cover, cover, ...
        IDconcCore, IDconcCover, IDSteel, ...
        numBarsTopGird, barAreaTopGird, ...
        numBarsBotGird, barAreaBotGird, ...
        numBarsIntGird, barAreaIntGird, ...
        nfCoreY, nfCoreZ, nfCoverY, nfCoverZ);

    ops.uniaxialMaterial('Elastic', SecTagTorsion, u.Ubig);

    ops.section('Aggregator', ColSecTag, SecTagTorsion, 'T', ...
        '-section', ColSecTagFiber);

    ops.section('Aggregator', BeamSecTag, SecTagTorsion, 'T', ...
        '-section', BeamSecTagFiber);

    ops.section('Aggregator', GirdSecTag, SecTagTorsion, 'T', ...
        '-section', GirdSecTagFiber);

else
    error("Unsupported SectionType: %s", SectionType);
end

GammaConcrete = 150 * u.pcf;

QdlCol = GammaConcrete * HCol * BCol;
QBeam = GammaConcrete * HBeam * BBeam;
QGird = GammaConcrete * HGird * BGird;

sec = struct();
sec.ColSecTag = ColSecTag;
sec.BeamSecTag = BeamSecTag;
sec.GirdSecTag = GirdSecTag;
sec.ColSecTagFiber = ColSecTagFiber;
sec.BeamSecTagFiber = BeamSecTagFiber;
sec.GirdSecTagFiber = GirdSecTagFiber;
sec.SecTagTorsion = SecTagTorsion;
sec.HCol = HCol;
sec.BCol = BCol;
sec.HBeam = HBeam;
sec.BBeam = BBeam;
sec.HGird = HGird;
sec.BGird = BGird;
sec.cover = cover;
sec.IDconcCore = IDconcCore;
sec.IDSteel = IDSteel;
sec.QdlCol = QdlCol;
sec.QBeam = QBeam;
sec.QGird = QGird;
end

function mat = defineRCMaterials(ops, u)
% OpenSeesMatlab version of LibMaterialsRC.tcl.

fc = -4.0 * u.ksi;
Ec = 57 * u.ksi * sqrt(-fc / u.psi);
nu = 0.2;
Gc = Ec / 2.0 / (1.0 + nu); %#ok<NASGU>

Kfc = 1.3;
Kres = 0.2;

fc1C = Kfc * fc;
eps1C = 2.0 * fc1C / Ec;
fc2C = Kres * fc1C;
eps2C = 20 * eps1C;

lambda = 0.1;

fc1U = fc;
eps1U = -0.003;
fc2U = Kres * fc1U;
eps2U = -0.01;

ftC = -0.14 * fc1C;
ftU = -0.14 * fc1U;
Ets = ftU / 0.002;

IDconcCore = 1;
IDconcCover = 2;

ops.uniaxialMaterial('Concrete02', IDconcCore, ...
    fc1C, eps1C, fc2C, eps2C, lambda, ftC, Ets);

ops.uniaxialMaterial('Concrete02', IDconcCover, ...
    fc1U, eps1U, fc2U, eps2U, lambda, ftU, Ets);

Fy = 66.8 * u.ksi;
Es = 29000.0 * u.ksi;
Bs = 0.01;
R0 = 18;
cR1 = 0.925;
cR2 = 0.15;

IDSteel = 3;
ops.uniaxialMaterial('Steel02', IDSteel, Fy, Es, Bs, R0, cR1, cR2);

mat = struct();
mat.IDconcCore = IDconcCore;
mat.IDconcCover = IDconcCover;
mat.IDSteel = IDSteel;
end

function BuildRCrectSection(ops, id, HSec, BSec, coverH, coverB, ...
    coreID, coverID, steelID, ...
    numBarsTop, barAreaTop, ...
    numBarsBot, barAreaBot, ...
    numBarsIntTot, barAreaInt, ...
    nfCoreY, nfCoreZ, nfCoverY, nfCoverZ)

% OpenSeesMatlab version of BuildRCrectSection.tcl.

coverY = HSec / 2.0;
coverZ = BSec / 2.0;

coreY = coverY - coverH;
coreZ = coverZ - coverB;

numBarsInt = numBarsIntTot / 2;

ops.section('fiberSec', id, '-GJ', 100000);

% Core patch
ops.patch('quad', coreID, nfCoreZ, nfCoreY, ...
    -coreY,  coreZ, ...
    -coreY, -coreZ, ...
     coreY, -coreZ, ...
     coreY,  coreZ);

% Cover patches
ops.patch('quad', coverID, 2, nfCoverY, ...
    -coverY,  coverZ, ...
    -coreY,   coreZ, ...
     coreY,   coreZ, ...
     coverY,  coverZ);

ops.patch('quad', coverID, 2, nfCoverY, ...
    -coreY,  -coreZ, ...
    -coverY, -coverZ, ...
     coverY, -coverZ, ...
     coreY,  -coreZ);

ops.patch('quad', coverID, nfCoverZ, 2, ...
    -coverY,  coverZ, ...
    -coverY, -coverZ, ...
    -coreY,  -coreZ, ...
    -coreY,   coreZ);

ops.patch('quad', coverID, nfCoverZ, 2, ...
     coreY,  coreZ, ...
     coreY, -coreZ, ...
     coverY, -coverZ, ...
     coverY,  coverZ);

% Reinforcement layers
ops.layer('straight', steelID, numBarsInt, barAreaInt, ...
    -coreY,  coreZ, ...
     coreY,  coreZ);

ops.layer('straight', steelID, numBarsInt, barAreaInt, ...
    -coreY, -coreZ, ...
     coreY, -coreZ);

ops.layer('straight', steelID, numBarsTop, barAreaTop, ...
     coreY,  coreZ, ...
     coreY, -coreZ);

ops.layer('straight', steelID, numBarsBot, barAreaBot, ...
    -coreY,  coreZ, ...
    -coreY, -coreZ);
end

function dyn = runBidirectionalDynamicAnalysis(ops, params, u, ~, GMdir)
% OpenSeesMatlab version of Ex8.genericFrame3D.analyze.Dynamic.EQ.bidirect.tcl.

DtAnalysis = params.DtAnalysis;
TmaxAnalysis = params.TmaxAnalysis;

% Dynamic-analysis parameters from LibAnalysisDynamicParameters.tcl
constraintsTypeDynamic = 'Transformation';
numbererTypeDynamic = 'RCM';
systemTypeDynamic = 'UmfPack';

TolDynamic = 1.0e-4;
maxNumIterDynamic = 100;
printFlagDynamic = 0;
testTypeDynamic = 'NormDispIncr';

algorithmTypeDynamic = 'KrylovNewton';

NewmarkGamma = 0.5;
NewmarkBeta = 0.25;
integratorTypeDynamic = 'Newmark';

analysisTypeDynamic = 'Transient';

ops.constraints(constraintsTypeDynamic);
ops.numberer(numbererTypeDynamic);
ops.system(systemTypeDynamic);
ops.test(testTypeDynamic, TolDynamic, maxNumIterDynamic, printFlagDynamic);
ops.algorithm(algorithmTypeDynamic);
ops.integrator(integratorTypeDynamic, NewmarkGamma, NewmarkBeta);
ops.analysis(analysisTypeDynamic);

% Rayleigh damping
xDamp = params.xDamp;
MpropSwitch = params.MpropSwitch;
KcurrSwitch = params.KcurrSwitch;
KcommSwitch = params.KcommSwitch;
KinitSwitch = params.KinitSwitch;

nEigenI = params.nEigenI;
nEigenJ = params.nEigenJ;

lambdaN = ops.eigen(nEigenJ);
lambdaN = double(lambdaN(:));

lambdaI = lambdaN(nEigenI);
lambdaJ = lambdaN(nEigenJ);

omegaI = sqrt(lambdaI);
omegaJ = sqrt(lambdaJ);

alphaM = MpropSwitch * xDamp * (2.0 * omegaI * omegaJ) / (omegaI + omegaJ);
betaKcurr = KcurrSwitch * 2.0 * xDamp / (omegaI + omegaJ);
betaKcomm = KcommSwitch * 2.0 * xDamp / (omegaI + omegaJ);
betaKinit = KinitSwitch * 2.0 * xDamp / (omegaI + omegaJ);

ops.rayleigh(alphaM, betaKcurr, betaKinit, betaKcomm);

% Uniform excitation
GMfiles = string(params.GMfiles);
GMdirections = params.GMdirections;
GMfactors = params.GMfactors;

if numel(GMfiles) ~= numel(GMdirections) || numel(GMfiles) ~= numel(GMfactors)
    error("GMfiles, GMdirections, and GMfactors must have the same length.");
end

IDloadTag = 400;

for i = 1:numel(GMfiles)
    IDloadTag = IDloadTag + 1;
    GMfile = GMfiles(i);
    GMdirection = GMdirections(i);
    GMfact = GMfactors(i);

    inFile = fullfile(GMdir, GMfile + ".at2");
    outFile = fullfile(GMdir, GMfile + ".g3");

    dt = ReadSMDFile(inFile, outFile);

    GMfatt = u.g * GMfact;

    accelSeriesTag = IDloadTag;
    ops.timeSeries('Path', accelSeriesTag, ...
        '-dt', dt, ...
        '-filePath', outFile, ...
        '-factor', GMfatt);

    ops.pattern('UniformExcitation', IDloadTag, GMdirection, ...
        '-accel', accelSeriesTag);
end


Nsteps = floor(TmaxAnalysis / DtAnalysis);
ok = ops.analyze(Nsteps, DtAnalysis);

if ok ~= 0
    ok = 0;
    controlTime = ops.getTime();

    while controlTime < TmaxAnalysis && ok == 0
        controlTime = ops.getTime();
        ok = ops.analyze(1, DtAnalysis);

        if ok ~= 0
            ops.test('NormDispIncr', TolDynamic, 1000, 0);
            ops.algorithm('Newton', '-initial');
            ok = ops.analyze(1, DtAnalysis);

            ops.test(testTypeDynamic, TolDynamic, maxNumIterDynamic, 0);
            ops.algorithm(algorithmTypeDynamic);
        end

        if ok ~= 0
            ops.algorithm('Broyden', 8);
            ok = ops.analyze(1, DtAnalysis);
            ops.algorithm(algorithmTypeDynamic);
        end

        if ok ~= 0
            ops.algorithm('NewtonLineSearch', 0.8);
            ok = ops.analyze(1, DtAnalysis);
            ops.algorithm(algorithmTypeDynamic);
        end
    end
end

dyn = struct();
dyn.okDynamic = ok;
dyn.rayleighCoefficients = struct( ...
    'alphaM', alphaM, ...
    'betaKcurr', betaKcurr, ...
    'betaKinit', betaKinit, ...
    'betaKcomm', betaKcomm);
end

function dt = ReadSMDFile(inFilename, outFilename)
%READSMDFILE Read PEER/SMD ground-motion file and write one value per line.
%
% This function:
%   1) reads the time step DT from the PEER/SMD header;
%   2) reads all acceleration values after the header;
%   3) expands the values row by row;
%   4) writes one acceleration value per line to outFilename.
%
% The row-wise expansion is important. For example, if the original file is:
%
%   a11 a12 a13 a14 a15
%   a21 a22 a23 a24 a25
%
% the output will be:
%
%   a11
%   a12
%   a13
%   a14
%   a15
%   a21
%   a22
%   ...
%
% Do not use data(:) here, because MATLAB expands matrices column by column.

inFilename = string(inFilename);
outFilename = string(outFilename);

if ~isfile(inFilename)
    error("Ground-motion file not found: %s", inFilename);
end

txt = fileread(inFilename);
lines = regexp(txt, '\r\n|\n|\r', 'split');

dt = NaN;
dataStarted = false;
accValues = [];

for i = 1:numel(lines)
    line = strtrim(lines{i});

    if strlength(line) == 0
        continue;
    end

    if ~dataStarted
        % Search DT from the header line, e.g.:
        % NPTS=  2000, DT= .00500 SEC
        lineUpper = upper(string(line));

        token = regexp(lineUpper, 'DT\s*=\s*([0-9EeDd+\-\.]+)', ...
            'tokens', 'once');

        if ~isempty(token)
            dtText = string(token{1});
            dtText = replace(dtText, "D", "E");
            dt = str2double(dtText);

            dataStarted = true;
        end

    else
        % Row-wise parsing:
        % read numeric values from the current line from left to right.
        lineClean = replace(string(line), "D", "E");
        rowValues = sscanf(lineClean, "%f").';

        if ~isempty(rowValues)
            accValues = [accValues, rowValues]; %#ok<AGROW>
        end
    end
end

if isnan(dt)
    error("Could not read DT from PEER/SMD file header: %s", inFilename);
end

if isempty(accValues)
    error("No acceleration data were found in file: %s", inFilename);
end

outFolder = fileparts(outFilename);
if strlength(outFolder) > 0 && ~isfolder(outFolder)
    mkdir(outFolder);
end

fid = fopen(outFilename, "w");
if fid < 0
    error("Cannot open file for writing: %s", outFilename);
end

cleanupObj = onCleanup(@() fclose(fid));

% Write one data point per line
for i = 1:numel(accValues)
    fprintf(fid, "%.10e\n", accValues(i));
end

end

%[appendix]{"version":"1.0"}
%---
