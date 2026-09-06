<!-- matlab-script-download -->
[:material-download: Download MATLAB script](./post_unitsystem.m){ .md-button .md-button--primary }

# <span style="color:var(--md-accent-fg-color)">**Automatic Unit System Conversion**</span>

The `unitSystem` object converts derived quantities from a chosen length\-force\-time basis. The same truss is solved in three unit systems to verify that frequencies are invariant and that displacements and reactions transform by the expected scale factors.

OpenSees does not impose a unit system; every numerical value must be consistent with the selected length, force, and time units. `unitSystem` derives area, stress, mass, and other conversion factors from that basis.

```matlab

opsMAT = OpenSeesMatlab();
ops = opsMAT.opensees;

```

## Basic usage
```matlab
length_unit = "m";    % base unit
force_unit  = "kN";   % base unit

UNIT = opsMAT.pre.unitSystem;
UNIT.setBasicUnits(length_unit, force_unit, "sec");

fprintf("Length: %g %g %g %g %g %g\n", ...
    UNIT.mm, UNIT.mm2, UNIT.cm, UNIT.m, UNIT.inch, UNIT.ft);
```

<div class="example-output">
<div class="example-output__header"><img class="example-component__logo" src="../../../static/images/matlab.svg" alt=""><span>Run output</span><span class="example-output__count">1 line</span></div>
<pre>Length: 0.001 1e-06 0.01 1 0.0254 0.3048</pre>
</div>

```matlab

fprintf("Force: %g %g %g %g %g\n", ...
    UNIT.N, UNIT.kN, UNIT.lbf, UNIT.kip, UNIT("kN/mm"));
```

<div class="example-output">
<div class="example-output__header"><img class="example-component__logo" src="../../../static/images/matlab.svg" alt=""><span>Run output</span><span class="example-output__count">1 line</span></div>
<pre>Force: 0.001 1 0.00444822 4.44822 1000</pre>
</div>

```matlab

fprintf("Stress: %g %g %g %g %g %g\n", ...
    UNIT.MPa, UNIT.kPa, UNIT.Pa, UNIT.psi, UNIT.ksi, UNIT("N/mm2"));
```

<div class="example-output">
<div class="example-output__header"><img class="example-component__logo" src="../../../static/images/matlab.svg" alt=""><span>Run output</span><span class="example-output__count">1 line</span></div>
<pre>Stress: 1000 1 0.001 6.89476 6894.76 1000</pre>
</div>

```matlab

fprintf("Mass: %g %g %g %g\n", ...
    UNIT.g, UNIT.kg, UNIT.ton, UNIT.slug);
```

<div class="example-output">
<div class="example-output__header"><img class="example-component__logo" src="../../../static/images/matlab.svg" alt=""><span>Run output</span><span class="example-output__count">1 line</span></div>
<pre>Mass: 1e-06 0.001 1 0.0145939</pre>
</div>

```matlab
disp(UNIT)
```

<div class="example-output">
<div class="example-output__header"><img class="example-component__logo" src="../../../static/images/matlab.svg" alt=""><span>Run output</span><span class="example-output__count">1 line</span></div>
<pre>&lt;UnitSystem: length=&quot;m&quot;, force=&quot;kn&quot;, time=&quot;sec&quot;&gt;</pre>
</div>

These other units will be automatically converted to the base units you have set!

## Truss example

Let’s look at a truss example. You can set the practical values of structural parameters in the model, and  unitSystem will help you automatically convert to the base unit system you specify.

```matlab
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
```

### **Structure Frequency**

The structural frequencies are consistent, it really has nothing to do with the unit system!

```matlab
freq = [f1; f2; f3];
% fprintf("structure frequency: ");
disp(freq);
```

<div class="example-output">
<div class="example-output__header"><img class="example-component__logo" src="../../../static/images/matlab.svg" alt=""><span>Run output</span><span class="example-output__count">3 lines</span></div>
<pre>    7.0536    8.2893
    7.0536    8.2893
    7.0536    8.2893</pre>
</div>

### **Node Displacement**

1 m = 100 cm

1 ft = 0.3048 m

```matlab
fprintf(['Displacement at node 4: ', ...
         '%s/%s = %g, ', ...
         '%s/%s = %g\n'], ...
         char(length_unit2), char(length_unit1), u2(end) / u1(end), ...
         char(length_unit1), char(length_unit3), u1(end) / u3(end));
```

<div class="example-output">
<div class="example-output__header"><img class="example-component__logo" src="../../../static/images/matlab.svg" alt=""><span>Run output</span><span class="example-output__count">1 line</span></div>
<pre>Displacement at node 4: cm/m = 100, m/ft = 0.3048</pre>
</div>

### **Node Reactions**

```matlab
fprintf('Reaction at node 2: %s/%s = %g, %s/%s = %g\n', ...
    char(force_unit2), char(force_unit1), forces2(end) / forces1(end), ...
    char(force_unit3), char(force_unit1), forces3(end) / forces1(end));
```

<div class="example-output">
<div class="example-output__header"><img class="example-component__logo" src="../../../static/images/matlab.svg" alt=""><span>Run output</span><span class="example-output__count">1 line</span></div>
<pre>Reaction at node 2: N/kN = 1000, lbf/kN = 224.809</pre>
</div>

The numerical values change with the chosen units, while the physical response does not. The printed ratios should reproduce the known conversion factors for displacement and force.

## Truss Model Code
```matlab
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

```

## Verification

Frequencies from the three models should coincide. Displacement and reaction ratios should equal the corresponding length and force conversion factors, demonstrating physical rather than numerical equivalence.