# OpenSeesMatlabPost

Post-processing and ODB interface available as `opsMAT.post`. The
[post-processing guide](../getting_started/post.md) explains the model,
response, modal, and linear-buckling data flows used by these methods.

::: post.OpenSeesMatlabPost
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
        - setOutputDir
        - getOutputDir
        - saveModelData
        - getModelData
        - saveEigenData
        - getEigenData
        - saveLinearBucklingData
        - getLinearBucklingData
        - createODB
        - getODBData
        - getModelDataFromODB
        - getNodalResponse
        - getElementResponse
        - transformResponseStruct
        - writeResponsePVD
        - toResponseDataset


::: post.ODB
    handler: matlab
    options:
      parse_arguments: false
      show_root_toc_entry: true
      heading_level: 1
      separate_signature: true
      show_signature_types: true
      signature_crossrefs: true
      docstring_section_style: list
      members:
        - close

## Related documentation

- [Pre/post-processing and visualization guide](../getting_started/post.md)
- [Linear buckling guide](../getting_started/extensions/linear_buckling.md)
- [MATLAB graphics API](OpenSeesMatlabVis.md)
- [Polyscope API](OpenSeesMatlabVisPolyscope.md)
- [ResponseArray and ResponseDataset](ResponseArrayDataset.md)
