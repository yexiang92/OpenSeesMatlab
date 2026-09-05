# Native runtime files

This directory makes `+ops/+core` a self-contained, replaceable MATLAB
binding package. Store each native bundle in its platform directory:

```text
derived/
├── windows-x86_64/
│   ├── OpenSeesMATLAB.mexw64
│   ├── OpenSeesBindings.dll
│   ├── OpenSeesMATLABSP.mexw64
│   ├── OpenSeesBindingsSP.dll
│   ├── OpenSeesSPWorker.exe
│   └── required runtime DLLs
└── macos-aarch64/
    ├── OpenSeesMATLAB.mexmaca64
    ├── OpenSeesMATLABSP.mexmaca64
    ├── libOpenSeesBindingsSP.dylib
    ├── OpenSeesSPWorker
    └── required runtime dylibs
```

`ops.core.Runtime` selects only the directory matching the current host.
It selects the serial MEX by default. Call `ops.core.setBackend("sp")` before
creating a runtime or top-level `ops` object to select the SP MEX. The legacy
`OPENSEES_BACKEND` environment variable remains a compatibility fallback.
