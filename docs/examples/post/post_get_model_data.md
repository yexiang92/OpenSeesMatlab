
# <span style="color:rgb(213,80,0)">**Retrieval Model and Eigenvalue Analysis Data**</span>

## Model Data

First, instantiate the OpenSeesMatlab interface class. This class provides native OpenSees commands, as well as additional visualization, pre/post\-processing, and utility methods.

```matlab
opsMAT = OpenSeesMatlab();
ops = opsMAT.opensees;
```

For example, the `tool` property provides a function `loadExamples` to run some built\-in models. Of course, you can run your own model; the built\-in model is used here for demonstration purposes only.

```matlab
opsMAT.utils.loadExamples("Frame3D");
% or your model here
```

We can visualize the model using the `plotModel` function in the `vis` attribute.

```matlab
figure;
h = opsMAT.vis.plotModel();
```

We can retrieve data from the current model, which returns a nested `struct`. You can view the data using MATLAB's workspace variables.

```matlab
modelData = opsMAT.post.getModelData();
disp(modelData)
```

<div style="font-size:0.85em; color:#87ae73;">
  <div style="font-weight:600;">Output</div>
  <div style="white-space:pre-wrap; font-family:Consolas;">
Nodes: [1x1 struct]
           Fixed: [1x1 struct]
    MPConstraint: [1x1 struct]
           Loads: [1x1 struct]
        Elements: [1x1 struct]
         NumNode: 384
      NumElement: 930
  </div>
</div>


Finally, we can print the information for each field.

```matlab
S = modelData;

stack = {{'S', S}};

while ~isempty(stack)
    item = stack{end};
    stack(end) = [];

    name = item{1};
    val  = item{2};

    if isstruct(val)
        fns = fieldnames(val);
        for i = numel(fns):-1:1
            f = fns{i};
            stack{end+1} = {sprintf('%s.%s', name, f), val.(f)};
        end
    else
        sz = strjoin(string(size(val)), 'x');
        fprintf('%s : %s\n', name, sz);
    end
end
```

<div style="font-size:0.85em; color:#87ae73;">
  <div style="font-weight:600;">Output</div>
  <div style="white-space:pre-wrap; font-family:Consolas;">
S.Nodes.Tags : 384x1
S.Nodes.Coords : 384x3
S.Nodes.Ndm : 384x1
S.Nodes.Ndf : 384x1
S.Nodes.UnusedTags : 0x1
S.Nodes.Bounds : 1x6
S.Nodes.MinBoundSize : 1x1
S.Nodes.MaxBoundSize : 1x1
S.Fixed.NodeTags : 24x1
S.Fixed.NodeIndex : 24x1
S.Fixed.Coords : 24x3
S.Fixed.Dofs : 24x6
S.MPConstraint.PairNodeTags : 0x2
S.MPConstraint.Cells : 0x3
S.MPConstraint.MidCoords : 0x3
S.MPConstraint.Dofs : 0x6
S.Loads.PatternTags : 0x1
S.Loads.Node.PatternNodeTags : 0x2
S.Loads.Node.Values : 0x3
S.Loads.Element.Beam.PatternElementTags : 0x2
S.Loads.Element.Beam.Values : 0x10
S.Loads.Element.Surface.PatternElementTags : 0x2
S.Loads.Element.Surface.Values : 0x0
S.Elements.Summary.Tags : 930x1
S.Elements.Summary.ClassTags : 930x1
S.Elements.Summary.CenterCoords : 930x3
S.Elements.Families.Truss.Tags : 0x1
S.Elements.Families.Truss.Cells : 0x3
S.Elements.Families.Beam.Tags : 930x1
S.Elements.Families.Beam.Cells : 930x3
S.Elements.Families.Beam.Midpoints : 930x3
S.Elements.Families.Beam.Lengths : 930x1
S.Elements.Families.Beam.XAxis : 930x3
S.Elements.Families.Beam.YAxis : 930x3
S.Elements.Families.Beam.ZAxis : 930x3
S.Elements.Families.Link.Tags : 0x1
S.Elements.Families.Link.Cells : 0x3
S.Elements.Families.Link.Midpoints : 0x3
S.Elements.Families.Link.Lengths : 0x1
S.Elements.Families.Link.XAxis : 0x3
S.Elements.Families.Link.YAxis : 0x3
S.Elements.Families.Link.ZAxis : 0x3
S.Elements.Families.Line.Tags : 930x1
S.Elements.Families.Line.Cells : 930x3
S.Elements.Families.Plane.Tags : 0x1
S.Elements.Families.Plane.Cells : 0x0
S.Elements.Families.Plane.CellTypes : 0x1
S.Elements.Families.Shell.Tags : 0x1
S.Elements.Families.Shell.Cells : 0x0
S.Elements.Families.Shell.CellTypes : 0x1
S.Elements.Families.Solid.Tags : 0x1
S.Elements.Families.Solid.Cells : 0x0
S.Elements.Families.Solid.CellTypes : 0x1
S.Elements.Families.Joint.Tags : 0x1
S.Elements.Families.Contact.Tags : 0x1
S.Elements.Families.Contact.Cells : 0x3
S.Elements.Families.Unstructured.Tags : 0x1
S.Elements.Families.Unstructured.Cells : 0x0
S.Elements.Families.Unstructured.CellTypes : 0x1
S.Elements.Classes.ElasticBeam3d.Cells : 930x3
S.Elements.Classes.ElasticBeam3d.CellTypes : 930x1
S.Elements.Classes.ElasticBeam3d.ElementTags : 930x1
S.NumNode : 1x1
S.NumElement : 1x1
  </div>
</div>

## Eigen Data

First, we need to save the eigenvalue analysis results data for future reuse.

```matlab
tag = 1;
opsMAT.post.saveEigenData(tag, 10, solver='-genBandArpack');
```

Then, data is retrieved from the file, returning a nested `structure` that stores the various results of the eigenvalue analysis.

```matlab
eigenData = opsMAT.post.getEigenData(odbTag=tag);
disp(eigenData)
```

<div style="font-size:0.85em; color:#87ae73;">
  <div style="font-weight:600;">Output</div>
  <div style="white-space:pre-wrap; font-family:Consolas;">
EigenVectors: [1x1 struct]
    InterpolatedEigenVectors: [1x1 struct]
                  ModalProps: [1x1 struct]
                   ModelInfo: [1x1 struct]
                    ModeTags: [10x1 double]
  </div>
</div>


Using this data, we can visualize the first modal shapes.

```matlab
figure;
opsMAT.vis.plotEigen(6, eigenData);
axis off
S = eigenData;

stack = {{'S', S}};

while ~isempty(stack)
    item = stack{end};
    stack(end) = [];

    name = item{1};
    val  = item{2};

    if isstruct(val)
        fns = fieldnames(val);
        for i = numel(fns):-1:1
            f = fns{i};
            stack{end+1} = {sprintf('%s.%s', name, f), val.(f)};
        end
    else
        sz = strjoin(string(size(val)), 'x');
        fprintf('%s : %s\n', name, sz);
    end
end
```

<div style="font-size:0.85em; color:#87ae73;">
  <div style="font-weight:600;">Output</div>
  <div style="white-space:pre-wrap; font-family:Consolas;">
S.EigenVectors.data : 10x384x6
S.EigenVectors.nodeCoords : 384x3
S.EigenVectors.nodeNdf : 384x1
S.EigenVectors.nodeNdm : 384x1
S.EigenVectors.nodeTags : 384x1
S.InterpolatedEigenVectors.cellNodeTags : 930x2
S.InterpolatedEigenVectors.cells : 4650x3
S.InterpolatedEigenVectors.data : 10x5580x3
S.InterpolatedEigenVectors.eleTags : 930x1
S.InterpolatedEigenVectors.modeTags : 10x1
S.InterpolatedEigenVectors.nodeTags : 384x1
S.InterpolatedEigenVectors.nptsPerElement : 1x1
S.InterpolatedEigenVectors.pointID : 5580x1
S.InterpolatedEigenVectors.points : 5580x3
S.ModalProps.attrs.centerOfMass : 1x3
S.ModalProps.attrs.domainSize : 1x1
S.ModalProps.attrs.totalFreeMass : 1x6
S.ModalProps.attrs.totalMass : 1x6
S.ModalProps.raw.centerOfMass : 1x3
S.ModalProps.raw.domainSize : 1x1
S.ModalProps.raw.eigenFrequency : 1x10
S.ModalProps.raw.eigenLambda : 1x10
S.ModalProps.raw.eigenOmega : 1x10
S.ModalProps.raw.eigenPeriod : 1x10
S.ModalProps.raw.partiFactorMX : 1x10
S.ModalProps.raw.partiFactorMY : 1x10
S.ModalProps.raw.partiFactorMZ : 1x10
S.ModalProps.raw.partiFactorRMX : 1x10
S.ModalProps.raw.partiFactorRMY : 1x10
S.ModalProps.raw.partiFactorRMZ : 1x10
S.ModalProps.raw.partiMassMX : 1x10
S.ModalProps.raw.partiMassMY : 1x10
S.ModalProps.raw.partiMassMZ : 1x10
S.ModalProps.raw.partiMassRMX : 1x10
S.ModalProps.raw.partiMassRMY : 1x10
S.ModalProps.raw.partiMassRMZ : 1x10
S.ModalProps.raw.partiMassRatiosCumuMX : 1x10
S.ModalProps.raw.partiMassRatiosCumuMY : 1x10
S.ModalProps.raw.partiMassRatiosCumuMZ : 1x10
S.ModalProps.raw.partiMassRatiosCumuRMX : 1x10
S.ModalProps.raw.partiMassRatiosCumuRMY : 1x10
S.ModalProps.raw.partiMassRatiosCumuRMZ : 1x10
S.ModalProps.raw.partiMassRatiosMX : 1x10
S.ModalProps.raw.partiMassRatiosMY : 1x10
S.ModalProps.raw.partiMassRatiosMZ : 1x10
S.ModalProps.raw.partiMassRatiosRMX : 1x10
S.ModalProps.raw.partiMassRatiosRMY : 1x10
S.ModalProps.raw.partiMassRatiosRMZ : 1x10
S.ModalProps.raw.partiMassesCumuMX : 1x10
S.ModalProps.raw.partiMassesCumuMY : 1x10
S.ModalProps.raw.partiMassesCumuMZ : 1x10
S.ModalProps.raw.partiMassesCumuRMX : 1x10
S.ModalProps.raw.partiMassesCumuRMY : 1x10
S.ModalProps.raw.partiMassesCumuRMZ : 1x10
S.ModalProps.raw.totalFreeMass : 1x6
S.ModalProps.raw.totalMass : 1x6
S.ModalProps.data : 10x34
S.ModeTags : 10x1
  </div>
</div>


Let's look at the period of each mode.

```matlab
S.ModalProps.raw.eigenPeriod
```

<div style="font-size:0.85em; color:#87ae73;">
  <div style="font-weight:600;">Output</div>
  <div style="white-space:pre-wrap; font-family:Consolas;">
ans = 1x10
    2.2607    2.1196    1.9810    0.7388    0.6988    0.6564    0.4202    0.4051    0.3870    0.2951
  </div>
</div>


Let's look at the **cumulative participation mass ratio (%)** in each direction.

```matlab
S.ModalProps.raw.partiMassRatiosCumuMX
```

<div style="font-size:0.85em; color:#87ae73;">
  <div style="font-weight:600;">Output</div>
  <div style="white-space:pre-wrap; font-family:Consolas;">
ans = 1x10
    0.0000   80.7272   80.7272   80.7272   91.1228   91.1228   91.1228   94.5874   94.5874   94.5874
  </div>
</div>

```matlab
S.ModalProps.raw.partiMassRatiosCumuMY
```

<div style="font-size:0.85em; color:#87ae73;">
  <div style="font-weight:600;">Output</div>
  <div style="white-space:pre-wrap; font-family:Consolas;">
ans = 1x10
   79.6341   79.6341   79.6341   90.9131   90.9131   90.9131   94.4481   94.4481   94.4481   96.2749
  </div>
</div>

```matlab
S.ModalProps.raw.partiMassRatiosCumuMZ
```

<div style="font-size:0.85em; color:#87ae73;">
  <div style="font-weight:600;">Output</div>
  <div style="white-space:pre-wrap; font-family:Consolas;">
ans = 1x10
1.0e-29 *

    0.0085    0.0104    0.0115    0.0932    0.1655    0.2187    0.3673    0.4689    0.5151    0.6397
  </div>
</div>

```matlab
S.ModalProps.raw.partiMassRatiosCumuRMX
```

<div style="font-size:0.85em; color:#87ae73;">
  <div style="font-weight:600;">Output</div>
  <div style="white-space:pre-wrap; font-family:Consolas;">
ans = 1x10
   19.1567   19.1567   19.1567   71.8213   71.8213   71.8213   78.3219   78.3219   78.3219   85.4282
  </div>
</div>

```matlab
S.ModalProps.raw.partiMassRatiosCumuRMY
```

<div style="font-size:0.85em; color:#87ae73;">
  <div style="font-weight:600;">Output</div>
  <div style="white-space:pre-wrap; font-family:Consolas;">
ans = 1x10
    0.0000   16.7152   16.7152   16.7152   67.3875   67.3875   67.3875   72.9309   72.9309   72.9309
  </div>
</div>

```matlab
S.ModalProps.raw.partiMassRatiosCumuRMZ
```

<div style="font-size:0.85em; color:#87ae73;">
  <div style="font-weight:600;">Output</div>
  <div style="white-space:pre-wrap; font-family:Consolas;">
ans = 1x10
    0.0000    0.0000   81.5449   81.5449   81.5449   91.1897   91.1897   91.1897   94.6036   94.6036
  </div>
</div>

