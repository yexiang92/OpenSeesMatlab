# OpenSees command interface

`ops.OpenSeesMatlabCmds` is the MATLAB-facing command interface. Commands use
the same argument order as OpenSees and OpenSeesPy:

```matlab
opsMat = OpenSeesMatlab();
ops = opsMat.opensees;

ops.wipe();
ops.model("basic", "-ndm", 2, "-ndf", 3);
ops.node(1, 0.0, 0.0);
ops.node(2, 5.0, 0.0);
ops.fix(1, 1, 1, 1);
ops.element(...);
```

See the [OpenSeesPy documentation](https://openseespydoc.readthedocs.io/en/latest/index.html),
[OpenSees documentation](https://opensees.github.io/OpenSeesDocumentation/),
and [OpenSees command manual](https://opensees.berkeley.edu/wiki/index.php/OpenSees_User)
for command-specific arguments.

## Command coverage

This page lists all 245 methods currently exposed by `OpenSeesMatlabCmds`:

- 232 upstream OpenSees commands;
- 4 shared OpenSeesBindings commands: `adaptiveAnalyze`, `FEMDataRecorder`,
  `getDomainGeoTag`, and `updateMaterials`;
- 9 MATLAB-specific commands: `suppressPrint`, `matlabversion`, `readFEMData`,
  `writeFEMDataPVD`, `matlabSubstructure`, `registerMatlabSubstructure`,
  `unregisterMatlabSubstructure`, `clearMatlabSubstructures`, and
  `hasMatlabSubstructure`.

### Shared command methods

| Command | Command | Command | Command |
| --- | --- | --- | --- |
| `accelCPU` | `adaptiveAnalyze` | `addToParameter` | `algorithm` |
| `analysis` | `analyze` | `barrier` | `basicDeformation` |
| `basicForce` | `basicStiffness` | `Bcast` | `beamIntegration` |
| `block2D` | `block3D` | `build` | `cbdiDisplacement` |
| `classType` | `computeGradients` | `constraints` | `convertBinaryToText` |
| `convertTextToBinary` | `correlate` | `damping` | `database` |
| `defaultUnits` | `domainChange` | `domainCommitTag` | `eigen` |
| `eleDynamicalForce` | `eleForce` | `eleLoad` | `element` |
| `eleNodes` | `eleResponse` | `eleType` | `equalDOF` |
| `equalDOF_Mixed` | `equationConstraint` | `fiber` | `FEMDataRecorder` |
| `filter` | `findCurvatures` | `findDesignPoint` | `fix` |
| `fixX` | `fixY` | `fixZ` | `frictionModel` |
| `functionEvaluator` | `geomTransf` | `getCDF` | `getConstrainedDOFs` |
| `getConstrainedNodes` | `getCrdTransfTags` | `getDampTangent` | `getDomainGeoTag` |
| `getEleClassTags` | `getEleLoadClassTags` | `getEleLoadData` | `getEleLoadTags` |
| `getEleTags` | `getFixedDOFs` | `getFixedNodes` | `getInverseCDF` |
| `getLoadFactor` | `getLSFTags` | `getMean` | `getNDF` |
| `getNDM` | `getNodeLoadData` | `getNodeLoadTags` | `getNodeTags` |
| `getNodeTemperature` | `getNP` | `getNumElements` | `getNumThreads` |
| `getParamTags` | `getParamValue` | `getPatterns` | `getPDF` |
| `getPID` | `getRetainedDOFs` | `getRetainedNodes` | `getRVParamTag` |
| `getRVTags` | `getRVValue` | `getStdv` | `getStrain` |
| `getStress` | `getTangent` | `getTime` | `gradientEvaluator` |
| `gradPerformanceFunction` | `groundMotion` | `hystereticBackbone` | `IGA` |
| `imposedMotion` | `imposedSupportMotion` | `initialize` | `InitialStateAnalysis` |
| `integrator` | `layer` | `limitCurve` | `load` |
| `loadConst` | `logFile` | `mass` | `meritFunctionCheck` |
| `mesh` | `metaData` | `modalDamping` | `modalDampingQ` |
| `modalProperties` | `model` | `modulatingFunction` | `nDMaterial` |
| `NDTest` | `node` | `nodeAccel` | `nodeBounds` |
| `nodeCoord` | `nodeDisp` | `nodeDOFs` | `nodeEigenvector` |
| `nodeMass` | `nodePressure` | `nodeReaction` | `nodeResponse` |
| `nodeUnbalance` | `nodeVel` | `numberer` | `numFact` |
| `numIter` | `parameter` | `partition` | `patch` |
| `pattern` | `performanceFunction` | `pressureConstraint` | `printA` |
| `printB` | `printGID` | `printModel` | `printX` |
| `probabilityTransformation` | `randomNumberGenerator` | `randomVariable` | `rayleigh` |
| `reactions` | `record` | `recorder` | `recv` |
| `region` | `reliabilityConvergenceCheck` | `remesh` | `remove` |
| `reset` | `responseSpectrumAnalysis` | `restore` | `rigidDiaphragm` |
| `rigidLink` | `rootFinding` | `runFORMAnalysis` | `runFOSMAnalysis` |
| `runImportanceSamplingAnalysis` | `runSORMAnalysis` | `save` | `sdfResponse` |
| `searchDirection` | `searchPeerNGA` | `section` | `sectionDeformation` |
| `sectionDisplacement` | `sectionFlexibility` | `sectionForce` | `sectionLocation` |
| `sectionResponseType` | `sectionStiffness` | `sectionTag` | `sectionWeight` |
| `send` | `sensitivityAlgorithm` | `sensLambda` | `sensNodeAccel` |
| `sensNodeDisp` | `sensNodePressure` | `sensNodeVel` | `sensSectionForce` |
| `setCreep` | `setElementRayleighDampingFactors` | `setElementRayleighFactors` | `setMaxOpenFiles` |
| `setNodeAccel` | `setNodeCoord` | `setNodeDisp` | `setNodePressure` |
| `setNodeTemperature` | `setNodeVel` | `setNumThreads` | `setParameter` |
| `setPrecision` | `setStartNodeTag` | `setStrain` | `setTime` |
| `ShallowFoundationGen` | `solveCPU` | `sp` | `spectrum` |
| `start` | `startPoint` | `stepSizeRule` | `stiffnessDegradation` |
| `stop` | `strengthControl` | `strengthDegradation` | `stripXML` |
| `system` | `systemSize` | `test` | `testIter` |
| `testNorm` | `testNorms` | `testUniaxialMaterial` | `timeSeries` |
| `totalCPU` | `transformUtoX` | `uniaxialMaterial` | `updateMaterials` |
| `unloadingRule` | `updateElementDomain` | `updateMaterialStage` | `updateParameter` |
| `version` | `wipe` | `wipeAnalysis` | `wipeReliability` |

### MATLAB-specific command methods

| Command | Purpose |
| --- | --- |
| `suppressPrint` | Enable or suppress native OpenSees console output. |
| `matlabversion` | Return the MATLAB binding version. |
| `readFEMData` | Read HDF5 FEMData into MATLAB structures. |
| `writeFEMDataPVD` | Export FEMData visualization files. |
| `matlabSubstructure` | Create a MATLAB callback substructure element. |
| `registerMatlabSubstructure` | Register substructure callback state. |
| `unregisterMatlabSubstructure` | Remove one registered substructure callback. |
| `clearMatlabSubstructures` | Remove all registered substructure callbacks. |
| `hasMatlabSubstructure` | Test whether a substructure callback is registered. |

Solver and algorithm extensions use the normal command families rather than
additional top-level commands:

```matlab
ops.system("CuDSS");
ops.system("SUNDIALS", "-type", "dense");
ops.algorithm("TrustRegion");
ops.algorithm("KINSOL");

trustInfo = ops.algorithm("TrustRegion", "-info");
kinsolInfo = ops.algorithm("KINSOL", "-info");
```

Native and extension types are forwarded identically. The shared C++ layer
selects an extension factory when the type is registered locally and otherwise
delegates the call to upstream OpenSees.

## Argument and return conventions

- Both `char` and `string` inputs are supported.
- Commands without a return value return `[]`.
- Scalar arguments can always be passed individually.
- The following commands also accept numeric arrays and cell arrays, which are
  flattened automatically: `node`, `element`, `eleLoad`, `geomTransf`,
  `uniaxialMaterial`, `nDMaterial`, `equalDOF`, `equationConstraint`,
  `rigidDiaphragm`, `rigidLink`, `fix`, `fixX`, `fixY`, `fixZ`, `section`,
  `fiber`, `layer`, `patch`, `load`, `mass`, `rayleigh`,
  `ShallowFoundationGen`, `block2D`, `block3D`, `setNodeDisp`, `setNodeVel`,
  `setNodeAccel`, `frictionModel`, `region`,
  `setElementRayleighDampingFactors`, `setElementRayleighFactors`, `recorder`,
  and `timeSeries` (`Path` values and times).

## Complete command reference

::: ops.OpenSeesMatlabCmds
    handler: matlab
    options:
      parse_arguments: false
      show_root_toc_entry: true
      heading_level: 2
      separate_signature: true
      show_signature_types: true
      signature_crossrefs: true
      summary:
        properties: true
        functions: true
        namespaces: false
      docstring_section_style: list
      members:
        - accelCPU
        - adaptiveAnalyze
        - addToParameter
        - algorithm
        - analysis
        - analyze
        - barrier
        - basicDeformation
        - basicForce
        - basicStiffness
        - Bcast
        - beamIntegration
        - block2D
        - block3D
        - build
        - cbdiDisplacement
        - classType
        - computeGradients
        - constraints
        - convertBinaryToText
        - convertTextToBinary
        - correlate
        - damping
        - database
        - defaultUnits
        - domainChange
        - domainCommitTag
        - eigen
        - eleDynamicalForce
        - eleForce
        - eleLoad
        - element
        - eleNodes
        - eleResponse
        - eleType
        - equalDOF
        - equalDOF_Mixed
        - equationConstraint
        - fiber
        - FEMDataRecorder
        - filter
        - findCurvatures
        - findDesignPoint
        - fix
        - fixX
        - fixY
        - fixZ
        - frictionModel
        - functionEvaluator
        - geomTransf
        - getCDF
        - getConstrainedDOFs
        - getConstrainedNodes
        - getCrdTransfTags
        - getDampTangent
        - getDomainGeoTag
        - getEleClassTags
        - getEleLoadClassTags
        - getEleLoadData
        - getEleLoadTags
        - getEleTags
        - getFixedDOFs
        - getFixedNodes
        - getInverseCDF
        - getLoadFactor
        - getLSFTags
        - getMean
        - getNDF
        - getNDM
        - getNodeLoadData
        - getNodeLoadTags
        - getNodeTags
        - getNodeTemperature
        - getNP
        - getNumElements
        - getNumThreads
        - getParamTags
        - getParamValue
        - getPatterns
        - getPDF
        - getPID
        - getRetainedDOFs
        - getRetainedNodes
        - getRVParamTag
        - getRVTags
        - getRVValue
        - getStdv
        - getStrain
        - getStress
        - getTangent
        - getTime
        - gradientEvaluator
        - gradPerformanceFunction
        - groundMotion
        - hystereticBackbone
        - IGA
        - imposedMotion
        - imposedSupportMotion
        - initialize
        - InitialStateAnalysis
        - integrator
        - layer
        - limitCurve
        - load
        - loadConst
        - logFile
        - mass
        - meritFunctionCheck
        - mesh
        - metaData
        - modalDamping
        - modalDampingQ
        - modalProperties
        - model
        - modulatingFunction
        - nDMaterial
        - NDTest
        - node
        - nodeAccel
        - nodeBounds
        - nodeCoord
        - nodeDisp
        - nodeDOFs
        - nodeEigenvector
        - nodeMass
        - nodePressure
        - nodeReaction
        - nodeResponse
        - nodeUnbalance
        - nodeVel
        - numberer
        - numFact
        - numIter
        - parameter
        - partition
        - patch
        - pattern
        - performanceFunction
        - pressureConstraint
        - printA
        - printB
        - printGID
        - printModel
        - printX
        - probabilityTransformation
        - randomNumberGenerator
        - randomVariable
        - rayleigh
        - reactions
        - record
        - recorder
        - recv
        - region
        - reliabilityConvergenceCheck
        - remesh
        - remove
        - reset
        - responseSpectrumAnalysis
        - restore
        - rigidDiaphragm
        - rigidLink
        - rootFinding
        - runFORMAnalysis
        - runFOSMAnalysis
        - runImportanceSamplingAnalysis
        - runSORMAnalysis
        - save
        - sdfResponse
        - searchDirection
        - searchPeerNGA
        - section
        - sectionDeformation
        - sectionDisplacement
        - sectionFlexibility
        - sectionForce
        - sectionLocation
        - sectionResponseType
        - sectionStiffness
        - sectionTag
        - sectionWeight
        - send
        - sensitivityAlgorithm
        - sensLambda
        - sensNodeAccel
        - sensNodeDisp
        - sensNodePressure
        - sensNodeVel
        - sensSectionForce
        - setCreep
        - setElementRayleighDampingFactors
        - setElementRayleighFactors
        - setMaxOpenFiles
        - setNodeAccel
        - setNodeCoord
        - setNodeDisp
        - setNodePressure
        - setNodeTemperature
        - setNodeVel
        - setNumThreads
        - setParameter
        - setPrecision
        - setStartNodeTag
        - setStrain
        - setTime
        - ShallowFoundationGen
        - solveCPU
        - sp
        - spectrum
        - start
        - startPoint
        - stepSizeRule
        - stiffnessDegradation
        - stop
        - strengthControl
        - strengthDegradation
        - stripXML
        - system
        - systemSize
        - test
        - testIter
        - testNorm
        - testNorms
        - testUniaxialMaterial
        - timeSeries
        - totalCPU
        - transformUtoX
        - uniaxialMaterial
        - updateMaterials
        - unloadingRule
        - updateElementDomain
        - updateMaterialStage
        - updateParameter
        - version
        - wipe
        - wipeAnalysis
        - wipeReliability
        - suppressPrint
        - matlabversion
        - readFEMData
        - writeFEMDataPVD
        - matlabSubstructure
        - registerMatlabSubstructure
        - unregisterMatlabSubstructure
        - clearMatlabSubstructures
        - hasMatlabSubstructure
