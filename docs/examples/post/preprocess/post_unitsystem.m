%% *Automatic Unit System Conversion*
% This live script is written as a guided walkthrough for a post-processing 
% workflow. It focuses on retrieving, organizing, and visualizing model or response 
% data after an OpenSees analysis. Read the text cells first, then run each code 
% cell in order so that the variables, model state, and recorded results are available 
% for the later sections.
% 
% As we all know, the units should be unified in the finite element analysis. 
% Common basic units include |length|, |force|, and |time|. The units of the base 
% system can be combined in any combination, but other units including |pressure|, 
% |stress|, |mass|, etc. should be unified with base system. In order to facilitate 
% unit processing in the model, ``OpenSeesMatlab`` has developed a class that 
% can automatically perform unit conversion based on the basic units you set.


opsMAT = OpenSeesMatlab();
ops = opsMAT.opensees;

% Basic usage
% The following commands carry out this step of the workflow. Run this cell 
% after the previous sections so the required variables and model state already 
% exist.

length_unit = "m";    % base unit
force_unit  = "kN";   % base unit

UNIT = opsMAT.pre.unitSystem;
UNIT.setBasicUnits(length_unit, force_unit, "sec");

fprintf("Length: %g %g %g %g %g %g\n", ...
    UNIT.mm, UNIT.mm2, UNIT.cm, UNIT.m, UNIT.inch, UNIT.ft);

fprintf("Force: %g %g %g %g %g\n", ...
    UNIT.N, UNIT.kN, UNIT.lbf, UNIT.kip, UNIT("kN/mm"));

fprintf("Stress: %g %g %g %g %g %g\n", ...
    UNIT.MPa, UNIT.kPa, UNIT.Pa, UNIT.psi, UNIT.ksi, UNIT("N/mm2"));

fprintf("Mass: %g %g %g %g\n", ...
    UNIT.g, UNIT.kg, UNIT.ton, UNIT.slug);
disp(UNIT)
%% 
% These other units will be automatically converted to the base units you have 
% set!
% 
% 
% Truss example
% Let’s look at a truss example. You can set the practical values of structural 
% parameters in the model, and  unitSystem will help you automatically convert 
% to the base unit system you specify.

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
% *Structure Frequency*
% The structural frequencies are consistent, it really has nothing to do with 
% the unit system!

freq = [f1; f2; f3];
% fprintf("structure frequency: ");
disp(freq);
% *Node Displacement*
% 1 m = 100 cm
% 
% 1 ft = 0.3048 m

fprintf(['Displacement at node 4: ', ...
         '%s/%s = %g, ', ...
         '%s/%s = %g\n'], ...
         char(length_unit2), char(length_unit1), u2(end) / u1(end), ...
         char(length_unit1), char(length_unit3), u1(end) / u3(end));
% *Node Reactions*

fprintf('Reaction at node 2: %s/%s = %g, %s/%s = %g\n', ...
    char(force_unit2), char(force_unit1), forces2(end) / forces1(end), ...
    char(force_unit3), char(force_unit1), forces3(end) / forces1(end));
%% 
% The displacement and force values depend on the base unit system you set up, 
% but they are proportional to each other. Well, the rest is left to you to verify.
% Truss Model Code
% This section creates the finite-element idealization used by the rest of the 
% example. Check the dimensions, tags, and connectivity here before moving on.

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