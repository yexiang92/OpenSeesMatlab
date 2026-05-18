All OpenSees commands use the same input format as ``OpenSees`` and ``OpenSeesPy``. 
For example:

```matlab
opsMat = OpenSeesMatlab();  % Get Instance
ops = opsmat.opensees;  % Get the OpenSees command interface

ops.wipe();
ops.model('basic', '-ndm', 2, '-ndf', 3);
...
ops.node(1, 0.0, 0.0);
ops.node(2, 5.0, 0.0);
ops.fix(1, 1, 1, 1);
ops.element(...);
```

For details, please refer to their official documentation, You can call it in the same way.

[OpenSeesPy](https://openseespydoc.readthedocs.io/en/latest/index.html)

[OpenSees](https://opensees.github.io/OpenSeesDocumentation/)

[OpenSees Command Manual](https://opensees.berkeley.edu/wiki/index.php/OpenSees_User)

📌 A few notes:

- ✨ Both ``char`` and ``string`` inputs are supported. However, using ``char`` is recommended.
- ✨ Most commands accept **scalar arguments only** and do not support passing
    a `numeric array` directly. Please pass scalar arguments one by one.
  
    To unpack a `cell` array, use `{:}` expansion:
    
        ops.node(1, coords{:});         % coords is a cell array
    
    To unpack a numeric array, convert to cell first:

        coords = num2cell(coords);
        ops.node(1, coords{:});
    
    The following commands are exceptions and **do support** `numeric array`
    and `cell` array inputs, which are flattened automatically (Since OpenSeesMatlab v3.8.0.1):

    `node`, `element`, `eleLoad`, `geomTransf`, `uniaxialMaterial`,
    `nDMaterial`, `equalDOF`, `equationConstraint`, `rigidDiaphragm`,
    `rigidLink`, `fix`, `fixX`, `fixY`, `fixZ`, `section`, `fiber`,
    `layer`, `patch`, `load`, `mass`, `rayleigh`, `ShallowFoundationGen`,
    `block2D`, `block3D`, `setNodeDisp`, `setNodeVel`, `setNodeAccel`,
    `frictionModel`, `region`, `setElementRayleighDampingFactors`,
    `setElementRayleighFactors`, `recorder` , and `timeSeries` (`Path` type only: numeric array accepted for `-values` and `-time` )

- ✨ Commands with return values will return MATLAB data. If a command has no return value, an empty array ``[]`` will be returned.
- ✨ The additional post-processing provided by OpenSeesMatlab may be slow or buggy. If you think so, you can use only the OpenSees command interface and use ``recorder`` or other output commands to post-process the analysis results.

::: ops.OpenSeesMatlabCmds
    handler: matlab
    options:
      parse_arguments: true
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
        - wipe
        - model
        - node
        - element
        - fix
        - fixX
        - fixY
        - fixZ
        - equalDOF
        - equalDOF_Mixed
        - rigidLink
        - rigidDiaphragm
        - timeSeries
        - pattern
        - load
        - eleLoad
        - loadConst
        - sp
        - groundMotion
        - imposedMotion
        - mass
        - region
        - rayleigh
        - modalDamping
        - damping
        - block2D
        - block3D
        - beamIntegration
        - uniaxialMaterial
        - nDMaterial
        - section
        - fiber
        - patch
        - layer
        - frictionModel
        - geomTransf
        - remove
        - setCreep
        - constraints
        - numberer
        - system
        - test
        - algorithm
        - integrator
        - analysis
        - analyze
        - eigen
        - modalProperties
        - responseSpectrumAnalysis
        - wipeAnalysis
        - record
        - recorder
        - nodeDisp
        - nodeVel
        - nodeAccel
        - nodeCoord
        - nodeBounds
        - nodeEigenvector
        - nodeDOFs
        - nodeMass
        - nodePressure
        - nodeReaction
        - reactions
        - nodeResponse
        - nodeUnbalance
        - basicDeformation
        - basicForce
        - basicStiffness
        - eleDynamicalForce
        - eleForce
        - eleNodes
        - eleResponse
        - getEleTags
        - getNodeTags
        - getLoadFactor
        - getTime
        - setTime
        - sectionForce
        - sectionDeformation
        - sectionStiffness
        - sectionFlexibility
        - sectionLocation
        - sectionWeight
        - systemSize
        - numIter
        - testIter
        - testNorm
        - testUniaxialMaterial
        - setStrain
        - getStrain
        - getStress
        - getTangent
        - getDampTangent
        - reset
