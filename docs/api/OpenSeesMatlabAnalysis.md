# OpenSeesMatlabAnalysis

Higher-level analysis workflows available as `opsMAT.anlys`. Native analysis
extensions invoked directly through `opsMAT.opensees`, such as
`adaptiveAnalyze` and `linearBuckling`, are documented in the
[OpenSeesNexus extensions API](OpenSeesNexusExtensions.md).

::: analysis.OpenSeesMatlabAnalysis
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
        - smartAnalyze
        - MomentCurvature


::: analysis.SmartAnalyze
    handler: matlab
    options:
      parse_arguments: false
      show_root_toc_entry: true
      heading_level: 2
      separate_signature: true
      show_signature_types: true
      signature_crossrefs: true
      docstring_section_style: list
      members:
        - initialize
        - configure
        - reset
        - setTotalSteps
        - staticStepSplit
        - staticAnalyze
        - transientStepSplit
        - transientAnalyze
        - setSensitivityAlgorithm
        - getState
        - getNormHistory
        - getDiagnostics
        - printLastFailure

::: analysis.MomentCurvature
    handler: matlab
    options:
      parse_arguments: false
      show_root_toc_entry: true
      heading_level: 2
      separate_signature: true
      show_signature_types: true
      signature_crossrefs: true
      docstring_section_style: list
      members:
        - new
        - analyze
        - setCyclePath
        - getMPhi
        - getCurvature
        - getMoment
        - getLimitState
        - bilinearize
        - plotMPhi
        - plotFiberResponses
        - buildNMM
        - plotNMM

## Related documentation

- [Extensions overview](../getting_started/extensions.md)
- [Adaptive analysis guide](../getting_started/extensions/adaptive_analysis.md)
- [Linear buckling guide](../getting_started/extensions/linear_buckling.md)
- [OpenSeesNexus extensions API](OpenSeesNexusExtensions.md)
