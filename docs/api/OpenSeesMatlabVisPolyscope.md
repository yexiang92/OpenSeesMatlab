# OpenSeesMatlabVisPolyscope

Interactive Polyscope visualization interface available as `opsMAT.vis.polyscope`. It provides consistent in-window controls for model inspection, mode-shape animation, and nodal, frame, shell, plane, and solid response histories.

```matlab
opsMAT = OpenSeesMatlab();

% Interactive model viewer
opsMAT.vis.polyscope.plotModel();

% Interactive response viewer
nodeResp = opsMAT.post.getNodalResponse("myODB");
opsMAT.vis.polyscope.plotNodalResponse(nodeResp);
```

!!! tip "Recommended interactive backend"

    Use Polyscope for new interactive visualization workflows that require
    static exploration or animation. Use [OpenSeesMatlabVis](OpenSeesMatlabVis.md)
    when you need a regular MATLAB figure or a single-step MATLAB GUI plot.

::: plotter.OpenSeesMatlabVisPolyscope
    handler: matlab
    options:
      heading_level: 2
      signature_crossrefs: true
      summary:
        properties: true
        functions: true
        namespaces: false
      members:
        - plotModel
        - plotEigen
        - plotNodalResponse
        - plotFrameResponse
        - plotShellResponse
        - plotContinuumResponse
