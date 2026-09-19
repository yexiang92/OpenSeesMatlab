%[text] # **Automatic Unit System Conversion**
%[text] The `unitSystem` object converts derived quantities from a chosen length-force-time basis. The same truss is solved in three unit systems to verify that frequencies are invariant and that displacements and reactions transform by the expected scale factors.
%[text] OpenSees does not impose a unit system; every numerical value must be consistent with the selected length, force, and time units. `unitSystem` derives area, stress, mass, and other conversion factors from that basis.

opsMAT = OpenSeesMatlab();
ops = opsMAT.opensees;

%[text] ### Basic usage
length_unit = "m";    % base unit
force_unit  = "kN";   % base unit

UNIT = opsMAT.pre.unitSystem;
UNIT.setBasicUnits(length_unit, force_unit, "sec");

fprintf("Length: %g %g %g %g %g %g\n", ... %[output:group:34a07f41] %[output:5da0212e]
    UNIT.mm, UNIT.mm2, UNIT.cm, UNIT.m, UNIT.inch, UNIT.ft); %[output:group:34a07f41] %[output:5da0212e]

fprintf("Force: %g %g %g %g %g\n", ... %[output:group:4bced0f0] %[output:432d8e75]
    UNIT.N, UNIT.kN, UNIT.lbf, UNIT.kip, UNIT("kN/mm")); %[output:group:4bced0f0] %[output:432d8e75]

fprintf("Stress: %g %g %g %g %g %g\n", ... %[output:group:95b7d3f5] %[output:5d31872a]
    UNIT.MPa, UNIT.kPa, UNIT.Pa, UNIT.psi, UNIT.ksi, UNIT("N/mm2")); %[output:group:95b7d3f5] %[output:5d31872a]

fprintf("Mass: %g %g %g %g\n", ... %[output:group:23e10a56] %[output:0ccff136]
    UNIT.g, UNIT.kg, UNIT.ton, UNIT.slug); %[output:group:23e10a56] %[output:0ccff136]
disp(UNIT) %[output:8b384e12]
%[text] These other units will be automatically converted to the base units you have set!
%[text] ### Truss example
%[text] Let’s look at a truss example. You can set the practical values of structural parameters in the model, and  unitSystem will help you automatically convert to the base unit system you specify.
length_unit1 = "m";
force_unit1 = "kN";
UNIT.setBasicUnits(length_unit1, force_unit1, "sec");
[u1, forces1, f1] = trussModel(opsMAT);

length_unit2 = "cm";
force_unit2 = "N";
UNIT.setBasicUnits(length_unit2, force_unit2, "sec");
[u2, forces2, f2] = trussModel(opsMAT);

length_unit3 = "ft";
force_unit3 = "lbf";
UNIT.setBasicUnits(length_unit3, force_unit3, "sec");
[u3, forces3, f3] = trussModel(opsMAT);
%[text] #### **Structure Frequency**
%[text] The structural frequencies are consistent, it really has nothing to do with the unit system!
freq = [f1; f2; f3];
% fprintf("structure frequency: ");
disp(freq); %[output:9b57efaf]
%[text] #### **Node Displacement**
%[text] 1 m = 100 cm
%[text] 1 ft = 0.3048 m
fprintf(['Displacement at node 4: ', ... %[output:group:300ada14] %[output:9dbf40b6]
         '%s/%s = %g, ', ... %[output:9dbf40b6]
         '%s/%s = %g\n'], ... %[output:9dbf40b6]
         char(length_unit2), char(length_unit1), u2(end) / u1(end), ... %[output:9dbf40b6]
         char(length_unit1), char(length_unit3), u1(end) / u3(end)); %[output:group:300ada14] %[output:9dbf40b6]
%[text] #### **Node Reactions**
fprintf('Reaction at node 2: %s/%s = %g, %s/%s = %g\n', ... %[output:group:469ca6ab] %[output:76742caf]
    char(force_unit2), char(force_unit1), forces2(end) / forces1(end), ... %[output:76742caf]
    char(force_unit3), char(force_unit1), forces3(end) / forces1(end)); %[output:group:469ca6ab] %[output:76742caf]
%[text] The numerical values change with the chosen units, while the physical response does not. The printed ratios should reproduce the known conversion factors for displacement and force.
%[text] ### Truss Model Code
function [u, forces, freq] = trussModel(opsMAT)
%TRUSSMODEL  Simple 2D truss example in OpenSeesMatlab.
%
% Outputs
% -------
% u      : nodal displacement history of node 4, size = [10, 2]
% forces : reaction history of node 2, size = [10, 2]
% freq   : first two natural frequencies, size = [2, 1]

    ops  = opsMAT.opensees;
    UNIT = opsMAT.pre.unitSystem;

    % Clear model
    ops.wipe();
    ops.model("basic", "-ndm", 2, "-ndf", 2);

    % Create nodes
    ops.node(1, 0.0, 0.0);
    ops.node(2, 144.0 * UNIT.cm, 0.0);
    ops.node(3, 2.0 * UNIT.m, 0.0);
    ops.node(4, 80.0 * UNIT.cm, 96.0 * UNIT.cm);

    % Mass
    ops.mass(4, 100 * UNIT.kg, 100 * UNIT.kg);

    % Boundary conditions
    ops.fix(1, 1, 1);
    ops.fix(2, 1, 1);
    ops.fix(3, 1, 1);

    % Material
    ops.uniaxialMaterial("Elastic", 1, 3000.0 * UNIT.N / UNIT.cm2);

    % Elements
    ops.element("Truss", 1, 1, 4, 100.0 * UNIT.cm2, 1);
    ops.element("Truss", 2, 2, 4,  50.0 * UNIT.cm2, 1);
    ops.element("Truss", 3, 3, 4,  50.0 * UNIT.cm^2, 1);

    % Eigen analysis
    lambda = ops.eigen("-fullGenLapack", 2);
    omega  = sqrt(lambda);
    freq   = omega / (2 * pi);

    % Load pattern
    ops.timeSeries("Linear", 1);
    ops.pattern("Plain", 1, 1);
    ops.load(4, 10.0 * UNIT.kN, -5.0 * UNIT.kN);

    % Analysis options
    ops.system("BandSPD");
    ops.numberer("RCM");
    ops.constraints("Plain");
    ops.integrator("LoadControl", 1.0 / 10.0);
    ops.algorithm("Linear");
    ops.analysis("Static");

    % Preallocate
    nSteps = 10;
    u      = zeros(nSteps, 2);
    forces = zeros(nSteps, 2);

    % Analysis loop
    for i = 1:nSteps
        ok = ops.analyze(1);
        if ok ~= 0
            error("OpenSees analysis failed at step %d.", i);
        end

        u(i, :) = reshape(ops.nodeDisp(4), 1, []);
        ops.reactions();
        forces(i, :) = reshape(ops.nodeReaction(2), 1, []);
    end
end

%[text] ### Verification
%[text] Frequencies from the three models should coincide. Displacement and reaction ratios should equal the corresponding length and force conversion factors, demonstrating physical rather than numerical equivalence.

%[appendix]{"version":"1.0"}
%---
%[metadata:view]
%   data: {"layout":"inline","rightPanelPercent":40}
%---
%[output:5da0212e]
%   data: {"dataType":"text","outputData":{"text":"Length: 0.001 1e-06 0.01 1 0.0254 0.3048\n","truncated":false}}
%---
%[output:432d8e75]
%   data: {"dataType":"text","outputData":{"text":"Force: 0.001 1 0.00444822 4.44822 1000\n","truncated":false}}
%---
%[output:5d31872a]
%   data: {"dataType":"text","outputData":{"text":"Stress: 1000 1 0.001 6.89476 6894.76 1000\n","truncated":false}}
%---
%[output:0ccff136]
%   data: {"dataType":"text","outputData":{"text":"Mass: 1e-06 0.001 1 0.0145939\n","truncated":false}}
%---
%[output:8b384e12]
%   data: {"dataType":"text","outputData":{"text":"<UnitSystem: length=\"m\", force=\"kn\", time=\"sec\">\n","truncated":false}}
%---
%[output:9b57efaf]
%   data: {"dataType":"text","outputData":{"text":"    7.0536    8.2893\n    7.0536    8.2893\n    7.0536    8.2893\n\n","truncated":false}}
%---
%[output:9dbf40b6]
%   data: {"dataType":"text","outputData":{"text":"Displacement at node 4: cm\/m = 100, m\/ft = 0.3048\n","truncated":false}}
%---
%[output:76742caf]
%   data: {"dataType":"text","outputData":{"text":"Reaction at node 2: N\/kN = 1000, lbf\/kN = 224.809\n","truncated":false}}
%---
