# Label-Aware Response Arrays and Datasets

`post.xarray.ResponseDataset` organizes response variables by dotted paths,
while `post.xarray.ResponseArray` associates one numeric array with named
dimensions and coordinates. Create both objects from an existing response
struct through the public post-processing entry point:

```matlab
resp = opsMAT.post.getNodalResponse("myODB");
ds = opsMAT.post.toResponseDataset(resp);

ux = ds.disp.ux;
u18 = ux.sel("node", 18);
timeMean = ds.mean("time");
```

The wrapper does not modify the original response struct. Existing plotting and
GUI functions should continue to receive that original struct.

## ResponseDataset

::: post.xarray.ResponseDataset
    handler: matlab
    options:
      parse_arguments: false
      show_root_toc_entry: true
      heading_level: 3
      separate_signature: true
      show_signature_types: true
      signature_crossrefs: true
      summary:
        properties: true
        functions: true
        namespaces: false
      docstring_section_style: list
      members:
        - names
        - has
        - get
        - sel
        - isel
        - mean
        - sum
        - min
        - max
        - std
        - median
        - squeeze
        - rename
        - renameDimension
        - assignCoords
        - assignCoordinates
        - fromStruct

## ResponseArray

::: post.xarray.ResponseArray
    handler: matlab
    options:
      parse_arguments: false
      show_root_toc_entry: true
      heading_level: 3
      separate_signature: true
      show_signature_types: true
      signature_crossrefs: true
      summary:
        properties: true
        functions: true
        namespaces: false
      docstring_section_style: list
      members:
        - sel
        - isel
        - sizes
        - coordinate
        - mean
        - sum
        - min
        - max
        - std
        - median
        - any
        - all
        - transpose
        - squeeze
        - rename
        - renameDimension
        - assignCoords
        - assignCoordinates
        - where
        - toArray
        - toStruct
        - toTable

