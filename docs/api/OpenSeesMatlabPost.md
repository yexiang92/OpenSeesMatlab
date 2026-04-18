::: OpenSeesMatlabPost
    handler: matlab
    options:
      parse_arguments: true
      show_root_toc_entry: true
      show_submodules: true
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
        - setOutputDir
        - saveModelData
        - getModelData
        - saveEigenData
        - getEigenData
        - createODB
        - getODBData
        - getNodalResponse
        - getElementResponse
        - writeResponsePVD


::: post.ODB
    handler: matlab
    options:
      parse_arguments: true
      show_root_toc_entry: true
      show_submodules: true
      heading_level: 1
      separate_signature: true
      show_signature_annotations: true
      signature_crossrefs: true
      docstring_section_style: list
      members:
        - fetchResponseStep
        - saveResponse
        - reset