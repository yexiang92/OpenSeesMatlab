::: OpenSeesMatlabPre
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
        - unitSystem
        - setSectionGeometryRecorder
        - plotSection
        - getNodeMass
        - getMCK
        - createGravityLoad
        - beamGlobalUniformLoad
        - beamGlobalPointLoad
        - surfaceGlobalPressureLoad
        - fiberSectionMesh


::: pre.UnitSystem
    handler: matlab
    options:
      parse_arguments: true
      show_root_toc_entry: true
      heading_level: 1
      separate_signature: true
      show_signature_types: true
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
      show_signature_types: true
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

::: pre.FiberSectionMesh
    handler: matlab
    options:
      parse_arguments: true
      show_root_toc_entry: true
      heading_level: 1
      separate_signature: true
      show_signature_types: true
      signature_crossrefs: true
      summary:
        properties: true
        functions: true
        namespaces: false
      docstring_section_style: list
      members:
        - new
        - mesh
        - computeProps
        - printProps
        - build
        - plot
        - polygonShape
        - rectShape
        - hollowRectShape
        - circleShape
        - annulusShape
        - IShape
        - TShape
        - LShape
        - lineRebars
        - rectRebars
        - circRebars
        - arcRebars
        - polygonRebars
