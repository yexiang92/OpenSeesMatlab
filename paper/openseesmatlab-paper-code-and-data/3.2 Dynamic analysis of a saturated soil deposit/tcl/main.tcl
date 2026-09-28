# Created by Eng. MohammadReza Jalali Farahani, MS.c., Sharif University of Technology, 2024
# Converted to OpenSees Tcl from the provided OpenSeesPy script.
# 2D liquefiable soil model using quadUP elements.
# Units: kN, ton, sec, m.

wipe

set startTime [clock milliseconds]
# ------------------------------------------------------------------------------
# User-defined variables
# ------------------------------------------------------------------------------
set numXele 20
set numYele 10
set xSize 1.0
set ySize 1.0

set NumToTEle [expr {$numXele * $numYele}]
set numXnode  [expr {$numXele + 1}]
set numYnode  [expr {$numYele + 1}]

# ------------------------------------------------------------------------------
# Soil material parameters: loose sand, Dr = 50
# ------------------------------------------------------------------------------
set nod 2.0
set satDensity 1.9
set H2ODensity 1.0

set shear 10.0e4
set bulk1 23.3e4
set FricAngel 33.5
set PeakShear 0.1
set refPress 101.0
set pressDependCoef 0.5
set PTAngel 25.5

set Cont1 0.045
set Cont2 5.0
set Cont3 0.15

set dilat1 0.06
set dilat2 3.0
set dilat3 0.25

set numSurf 20
set Liquefac1 1.0
set Liquefac2 0.0

set e 0.7
set Cs1 0.9
set Cs2 0.02
set Cs3 0.7
set Pa 101.0

# ------------------------------------------------------------------------------
# Element parameters
# ------------------------------------------------------------------------------
set bulk [expr {2.2e6 / $e}]
set fmass 1.0

set INhperm 100.0
set INvperm 100.0

set hPerm 2.0e-3
set vPerm 2.0e-3

set accGravity 9.81
set loadBias 0.0
set pressure 0.0
set thick 1.0
set deltaT 0.1

# ------------------------------------------------------------------------------
# Nodes
# ------------------------------------------------------------------------------
model BasicBuilder -ndm 2 -ndf 3

for {set i 1} {$i <= $numXnode} {incr i} {
    for {set j 1} {$j <= $numYnode} {incr j} {
        set xdim [expr {($i - 1) * $xSize}]
        set ydim [expr {($j - 1) * $ySize}]
        set nodeNum [expr {$i + ($j - 1) * $numXnode}]
        node $nodeNum $xdim $ydim
    }
}

# ------------------------------------------------------------------------------
# Soil material
# ------------------------------------------------------------------------------
set matTag 1

nDMaterial PressureDependMultiYield02 $matTag $nod $satDensity $shear $bulk1 \
    $FricAngel $PeakShear $refPress $pressDependCoef $PTAngel \
    $Cont1 $Cont3 $dilat1 $dilat3 $numSurf $Cont2 $dilat2 \
    $Liquefac1 $Liquefac2 $Cs3 $Cs1 $Cs2 $e $Pa

# ------------------------------------------------------------------------------
# Elements
# ------------------------------------------------------------------------------
for {set i 1} {$i <= $numXele} {incr i} {
    for {set j 1} {$j <= $numYele} {incr j} {
        set eleTag [expr {$i + ($j - 1) * $numXele}]

        set n1 [expr {$i + ($j - 1) * $numXnode}]
        set n2 [expr {$i + ($j - 1) * $numXnode + 1}]
        set n4 [expr {$i + $j * $numXnode + 1}]
        set n3 [expr {$i + $j * $numXnode}]

        element quadUP $eleTag $n1 $n2 $n4 $n3 $thick $matTag $bulk $fmass \
            [expr {$INhperm / $accGravity / $fmass}] \
            [expr {$INvperm / $accGravity / $fmass}] \
            0.0 [expr {-$accGravity}] 0.0
    }
}

# Elastic material stage for gravity initialization.
updateMaterialStage -material $matTag -stage 0

# ------------------------------------------------------------------------------
# Boundary conditions
# ------------------------------------------------------------------------------
for {set i 1} {$i <= $numXnode} {incr i} {
    fix $i 1 1 0

    set surfNode [expr {($numYnode - 1) * $numXnode + $i}]
    fix $surfNode 0 0 1
}

for {set i 1} {$i < $numYnode} {incr i} {
    set nodeNum1 [expr {$i * $numXnode + 1}]
    set nodeNum2 [expr {$i * $numXnode + $numXnode}]
    equalDOF $nodeNum1 $nodeNum2 1 2
}

# ------------------------------------------------------------------------------
# Gravity analysis
# ------------------------------------------------------------------------------
numberer RCM
system ProfileSPD
test NormDispIncr 1.0e-6 50 0
algorithm KrylovNewton
constraints Penalty 1.0e18 1.0e18

set gamma 1.5
set beta [expr {pow($gamma + 0.5, 2) / 4.0}]

integrator Newmark $gamma $beta
analysis Transient

set okElasticGravity [analyze 10 5.0e3]

updateMaterialStage -material $matTag -stage 1
set okPlasticGravity [analyze 10 1.0e1]

wipeAnalysis
setTime 0.0

# ------------------------------------------------------------------------------
# Permeability parameters for dynamic analysis
# ------------------------------------------------------------------------------
set ctr 10000

for {set i 1} {$i <= $NumToTEle} {incr i} {
    parameter [expr {$ctr + 1}] element $i vPerm
    parameter [expr {$ctr + 2}] element $i hPerm
    set ctr [expr {$ctr + 2}]
}

set ctr 10000

for {set j 1} {$j <= $NumToTEle} {incr j} {
    updateParameter [expr {$ctr + 1}] [expr {$vPerm / $accGravity / $fmass}]
    updateParameter [expr {$ctr + 2}] [expr {$hPerm / $accGravity / $fmass}]
    set ctr [expr {$ctr + 2}]
}

# ------------------------------------------------------------------------------
# Recorders
# ------------------------------------------------------------------------------
set nodeList1 {53 95 137 158 179 221}

set DataDir "OutPuts"
file mkdir $DataDir

recorder Node -file "$DataDir/disp2.txt"  -node {*}$nodeList1 -time -dT $deltaT -dof 1 2 disp
recorder Node -file "$DataDir/Ydisp2.txt" -node {*}$nodeList1 -time -dT $deltaT -dof 2 disp
recorder Node -file "$DataDir/pwp1.txt"   -node {*}$nodeList1 -time -dT $deltaT -dof 3 vel
recorder Node -file "$DataDir/acc1.txt"   -node {*}$nodeList1 -time -dT $deltaT -dof 1 accel

recorder Element -file "$DataDir/stress10.txt"  -time -dT $deltaT -ele 10  material 1 stress
recorder Element -file "$DataDir/strain10.txt"  -time -dT $deltaT -ele 10  material 1 strain
recorder Element -file "$DataDir/stress70.txt"  -time -dT $deltaT -ele 70  material 1 stress
recorder Element -file "$DataDir/strain70.txt"  -time -dT $deltaT -ele 70  material 1 strain
recorder Element -file "$DataDir/stress130.txt" -time -dT $deltaT -ele 130 material 1 stress
recorder Element -file "$DataDir/strain130.txt" -time -dT $deltaT -ele 130 material 1 strain
recorder Element -file "$DataDir/stress190.txt" -time -dT $deltaT -ele 190 material 1 stress
recorder Element -file "$DataDir/strain190.txt" -time -dT $deltaT -ele 190 material 1 strain

# ------------------------------------------------------------------------------
# Dynamic analysis
# ------------------------------------------------------------------------------
set patternTag 10
set accelSeriesTag 1
set direction 1
set GMPath "acc_value.txt"

timeSeries Path $accelSeriesTag -dt 0.01 -filePath $GMPath -factor $accGravity
pattern UniformExcitation $patternTag $direction -accel $accelSeriesTag

constraints Transformation
numberer RCM
system UmfPack

set Tol 1.0e-4
set maxNumIter 100
set printFlag 0
set TestType NormDispIncr
test $TestType $Tol $maxNumIter $printFlag

set algorithmType KrylovNewton
algorithm $algorithmType

set NewmarkGamma 0.5
set NewmarkBeta 0.25
integrator Newmark $NewmarkGamma $NewmarkBeta
analysis Transient

set pi 3.141592654
set damp 0.02
set omega1 [expr {2.0 * $pi * 1.0}]
set omega2 [expr {2.0 * $pi * 20.0}]

set a0 [expr {2.0 * $damp * $omega1 * $omega2 / ($omega1 + $omega2)}]
set a1 [expr {2.0 * $damp / ($omega1 + $omega2)}]

rayleigh $a0 $a1 0.0 0.0

set dT 0.005
set nSteps 6500
set ok [analyze $nSteps $dT]

if {$ok != 0} {
    set curTime [getTime]
    set mTime $curTime
    set curStep [expr {$curTime / $dT}]
    set rStep [expr {($nSteps - $curStep) * 2.0}]
    set remStep [expr {int(($nSteps - $curStep) * 2.0)}]
    set dT [expr {$dT / 2.0}]

    set ok [analyze $remStep $dT]

    if {$ok != 0} {
        set curTime [getTime]
        set curStep [expr {($curTime - $mTime) / $dT}]
        set remStep [expr {int(($rStep - $curStep) * 2.0)}]
        set dT [expr {$dT / 2.0}]

        set ok [analyze $remStep $dT]
    }
}

set endTime [clock milliseconds]
set elapsedTime [expr {($endTime - $startTime) / 1000.0}]

puts "Total runtime = $elapsedTime seconds"

wipe
