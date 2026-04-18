::: OpenSeesMatlabAnalysis
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
        - smartAnalyze


::: analysis.SmartAnalyze
    handler: matlab
    options:
      parse_arguments: true
      show_root_toc_entry: true
      show_submodules: true
      heading_level: 2
      separate_signature: true
      show_signature_annotations: true
      signature_crossrefs: true
      docstring_section_style: list
      members:
        - configure
        - reset
        - staticStepSplit
        - staticAnalyze
        - transientStepSplit
        - transientAnalyze
        - setSensitivityAlgorithm
        - getState