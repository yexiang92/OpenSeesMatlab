# Native runtime files

This directory stores the platform-native part of the self-contained
OpenSeesNexus MATLAB package:

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

`OpenSeesNexus` selects only the directory matching the current host and uses
the serial MEX by default. Call `OpenSeesNexus.setBackend("sp")` before
creating the command object to select the SP MEX. The legacy
`OPENSEES_BACKEND` environment variable remains a compatibility fallback.
