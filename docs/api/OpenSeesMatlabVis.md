# OpenSeesMatlabVis

MATLAB-graphics visualization interface available as `opsMAT.vis`. These methods create regular MATLAB figures or MATLAB GUI wrappers. For interactive static and animated visualization, see [OpenSeesMatlabVisPolyscope](OpenSeesMatlabVisPolyscope.md).

```matlab
opsMAT = OpenSeesMatlab();
opsMAT.vis.plotModel();
```

::: plotter.OpenSeesMatlabVis
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
        - polyscope
        - plotModelGUI
        - plotEigenGUI
        - plotNodalResponseGUI
        - plotFrameResponseGUI
        - plotShellResponseGUI
        - plotContinuumResponseGUI
        - plotModel
        - plotEigen
        - plotNodalResponse
        - plotDeformation
        - plotFrameResponse
        - plotShellResponse
        - plotContinuumResponse
        - defaultPlotModelOptions
        - defaultPlotEigenOptions
        - defaultPlotNodalResponseOptions
        - defaultPlotFrameResponseOptions
        - defaultPlotShellResponseOptions
        - defaultPlotContinuumResponseOptions
