# #####################################################################################
#
# Modelling of Single Story Shear Frame equipped with Nonlinear Viscous Damper
#
# Modified version:
#   - Nonlinear steel columns
#   - Steel4 material with a finite ultimate-strength surface
#   - Fiber sections
#   - forceBeamColumn column elements
#   - Elastic roof beam
#   - Nonlinear viscous damper
#
# Units: mm, kN, sec
#
# #####################################################################################

wipe all

set startTime [clock milliseconds]

# ------------------------------------------------------------------------------
# 1. Define model
# ------------------------------------------------------------------------------

model BasicBuilder -ndm 2 -ndf 3

# Create output directory
set Output Output
file mkdir $Output

# ------------------------------------------------------------------------------
# 2. Geometry
# ------------------------------------------------------------------------------

set L 5000.0
set h 3000.0

node 1 0.0 0.0
node 2 $L  0.0
node 3 0.0 $h
node 4 $L  $h

# ------------------------------------------------------------------------------
# 3. Boundary conditions and floor constraint
# ------------------------------------------------------------------------------

fix 1 1 1 1
fix 2 1 1 1

# equalDOF retainedNode constrainedNode dofs
equalDOF 3 4 2 3

# ------------------------------------------------------------------------------
# 4. Mass
# ------------------------------------------------------------------------------

set W 1000.0
set g 9810.0
set m [expr $W / $g]

mass 3 [expr 0.5 * $m] 0.0 0.0
mass 4 [expr 0.5 * $m] 0.0 0.0

set pi [expr acos(-1.0)]

# ------------------------------------------------------------------------------
# 5. Nonlinear steel material for columns
# ------------------------------------------------------------------------------

# Steel4 material
# uniaxialMaterial Steel4 matTag Fy E0 -kin b R0 r1 r2 -ult Fu Ru

set FyCol 0.345
set E0    200.0
set b     0.01

set R0    18.0
set cR1   0.925
set cR2   0.15
set FuCol [expr 1.20 * $FyCol]
set RuCol 20.0

set matColSteel 1

uniaxialMaterial Steel4 $matColSteel $FyCol $E0 \
    -kin $b $R0 $cR1 $cR2 \
    -ult $FuCol $RuCol

# ------------------------------------------------------------------------------
# 6. Fiber section for nonlinear steel columns
# ------------------------------------------------------------------------------

# Column H-section dimensions, mm
set dCol  300.0
set twCol 8.0
set bfCol 220.0
set tfCol 14.0

set secCol 1

# Fiber discretization
set nfdw 16
set nftw 2
set nfbf 12
set nftf 2

set yTop    [expr  0.5 * $dCol]
set yBot    [expr -0.5 * $dCol]
set zLeft   [expr -0.5 * $bfCol]
set zRight  [expr  0.5 * $bfCol]
set zWebL   [expr -0.5 * $twCol]
set zWebR   [expr  0.5 * $twCol]

set yTopFlangeBot [expr  0.5 * $dCol - $tfCol]
set yBotFlangeTop [expr -0.5 * $dCol + $tfCol]

section Fiber $secCol {

    # Top flange
    patch rect $matColSteel $nftf $nfbf \
        $yTopFlangeBot $zLeft \
        $yTop          $zRight

    # Web
    patch rect $matColSteel $nfdw $nftw \
        $yBotFlangeTop $zWebL \
        $yTopFlangeBot $zWebR

    # Bottom flange
    patch rect $matColSteel $nftf $nfbf \
        $yBot          $zLeft \
        $yBotFlangeTop $zRight
}

# ------------------------------------------------------------------------------
# 7. Elastic roof beam properties
# ------------------------------------------------------------------------------

# Elastic beam H-section dimensions, mm
set dBeam  500.0
set twBeam 12.0
set bfBeam 300.0
set tfBeam 20.0

set EBeam 200.0

set ABeam [expr 2.0 * $bfBeam * $tfBeam + $twBeam * ($dBeam - 2.0 * $tfBeam)]

set IBeam [expr \
    ($twBeam * pow($dBeam - 2.0 * $tfBeam, 3)) / 12.0 + \
    2.0 * ( \
        ($bfBeam * pow($tfBeam, 3)) / 12.0 + \
        $bfBeam * $tfBeam * pow(($dBeam - $tfBeam) / 2.0, 2) \
    )]

# Stiffness amplification for a relatively stiff elastic roof beam
set beamStiffnessFactor 10.0

set ABeamEff [expr $beamStiffnessFactor * $ABeam]
set IBeamEff [expr $beamStiffnessFactor * $IBeam]

# ------------------------------------------------------------------------------
# 8. Nonlinear viscous damper
# ------------------------------------------------------------------------------

set Kd 25.0
set Cd 20.7452
set ad 0.35

set matDamper 10

# uniaxialMaterial ViscousDamper matTag Kd Cd alpha
uniaxialMaterial ViscousDamper $matDamper $Kd $Cd $ad

# ------------------------------------------------------------------------------
# 9. Geometric transformation and beam integration
# ------------------------------------------------------------------------------

set TransfTag 1
geomTransf Linear $TransfTag

set numIntPts 5
set beamIntCol 1

beamIntegration Lobatto $beamIntCol $secCol $numIntPts

# ------------------------------------------------------------------------------
# 10. Elements
# ------------------------------------------------------------------------------

# Nonlinear steel columns
element forceBeamColumn 1 1 3 $TransfTag $beamIntCol
element forceBeamColumn 2 2 4 $TransfTag $beamIntCol

# Elastic roof beam
element elasticBeamColumn 3 3 4 $ABeamEff $EBeam $IBeamEff $TransfTag

# Nonlinear viscous damper
# element twoNodeLink eleTag iNode jNode -mat matTags -dir dirs
element twoNodeLink 4 1 4 -mat $matDamper -dir 1

puts "Model Built"

# ------------------------------------------------------------------------------
# 11. Ground motion
# ------------------------------------------------------------------------------

# timeSeries Path tag -dt dt -filePath filePath -factor cFactor
# The record peak is 0.617; normalize its peak acceleration to 1.0g.
set recordPeak 0.617
timeSeries Path 1 -dt 0.01 -filePath TAKY.th \
    -factor [expr 1.00 * $g / $recordPeak]

# ------------------------------------------------------------------------------
# 12. Recorders
# ------------------------------------------------------------------------------

recorder Node -file $Output/Disp.out -time -node 4 -dof 1 disp
recorder Node -file $Output/Acc.out -timeSeries 1 -time -node 4 -dof 1 accel

# Reactions at both fixed nodes; their sum gives the total horizontal base
# reaction used for the roof-displacement--base-shear hysteresis plot.
recorder Node -file $Output/Base.out  -time -node 1 2 -dof 1 reaction
recorder Node -file $Output/NBase.out -time -node 1 2 -dof 2 reaction

recorder Element -file $Output/Damperdisp.out    -time -ele 4 deformations
recorder Element -file $Output/Damperforce.out   -time -ele 4 localForce
recorder Element -file $Output/Dampergbforce.out -time -ele 4 -dof 1 force

# Column basic/global force output
recorder Element -file $Output/Frameforce.out -time -ele 1 2 force

# Optional section response recorders for nonlinear columns
recorder Element -file $Output/Col1_sec1_force.out -time -ele 1 section 1 force
recorder Element -file $Output/Col1_sec1_defo.out  -time -ele 1 section 1 deformation

recorder Element -file $Output/Col2_sec1_force.out -time -ele 2 section 1 force
recorder Element -file $Output/Col2_sec1_defo.out  -time -ele 2 section 1 deformation

# ------------------------------------------------------------------------------
# 13. Eigenvalue analysis and damping
# ------------------------------------------------------------------------------

set lambda1 [eigen 1]
set freq [expr sqrt($lambda1)]
set period [expr 2.0 * $pi / $freq]

puts "First period = $period sec"

set damp 0.02
rayleigh [expr 2.0 * $damp * $freq] 0.0 0.0 0.0

# ------------------------------------------------------------------------------
# 14. Uniform excitation
# ------------------------------------------------------------------------------

# pattern UniformExcitation patternTag dir -accel tsTag
pattern UniformExcitation 1 1 -accel 1

# ------------------------------------------------------------------------------
# 15. Display
# ------------------------------------------------------------------------------

# The display recorder may be disabled if OpenSees is run in batch/headless mode.
recorder display "Displaced shape" 10 10 500 500 -wipe
prp 200.0 50.0 1.0
vup 0 1 0
vpn 0 0 1
display 1 5 40

# ------------------------------------------------------------------------------
# 16. Analysis
# ------------------------------------------------------------------------------

wipeAnalysis

constraints Transformation
numberer RCM
system UmfPack

test EnergyIncr 1.0e-10 100
algorithm KrylovNewton

integrator Newmark 0.5 0.25
analysis Transient

set ok [analyze [expr 10 * 4096] 0.001]

if {$ok == 0} {
    puts "Analysis completed successfully."
} else {
    puts "Analysis failed with return code $ok."
}

# ------------------------------------------------------------------------------
# 17. Runtime
# ------------------------------------------------------------------------------

set endTime [clock milliseconds]
set elapsedTime [expr {($endTime - $startTime) / 1000.0}]

puts "Total runtime = $elapsedTime seconds"

wipe
