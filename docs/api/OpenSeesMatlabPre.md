::: OpenSeesMatlabPre
    handler: matlab
    options:
      parse_arguments: true
      show_root_toc_entry: true
      heading_level: 2
      separate_signature: true
      show_signature_annotations: true
      signature_crossrefs: true
      summary:
        properties: true
        functions: true
        namespaces: false
      docstring_section_style: list
      members:
        - unitSystem
        - setSectionGeometryRecorder
        - plotSection
        - getNodeMass
        - getMCK
        - createGravityLoad
        - beamGlobalUniformLoad
        - beamGlobalPointLoad
        - surfaceGlobalPressureLoad


::: pre.UnitSystem
    handler: matlab
    options:
      parse_arguments: true
      show_root_toc_entry: true
      heading_level: 1
      separate_signature: true
      show_signature_annotations: true
      signature_crossrefs: true
      summary:
        properties: false
        functions: false
        namespaces: false
      docstring_section_style: list
      members:
        - setBasicUnits

::: pre.Gmsh2OPS
    handler: matlab
    options:
      parse_arguments: true
      show_root_toc_entry: true
      heading_level: 1
      separate_signature: true
      show_signature_annotations: true
      signature_crossrefs: true
      summary:
        properties: false
        functions: false
        namespaces: false
      docstring_section_style: list
      members:
        - reset
        - readGmshFile
        - printInfo
        - getDimEntityTags
        - getBoundaryDimTags
        - getNodeTags
        - getElementTags
        - createNodeCmds
        - createElementCmds
        - createFixCmds
        - setOutputFile
        - writeNodeFile
        - writeElementFile
        - writeFixFile


