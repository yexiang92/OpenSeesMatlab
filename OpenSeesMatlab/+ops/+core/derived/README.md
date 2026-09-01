# Native runtime files

This directory stores the platform-specific OpenSees command-interface
runtime used by the installed MATLAB toolbox and `publish.m`.

Common MATLAB helpers live in the replaceable `+ops/+core` subpackage rather
than in this binary directory.

Place Windows x86-64 files under `windows-x86_64/`:

- `OpenSeesMATLAB.mexw64`
- `OpenSeesBindings.dll`
- required runtime `.dll` files such as `libiomp5md.dll`

Place macOS Apple-silicon files under `macos-aarch64/`:

- `OpenSeesMATLAB.mexmaca64`
- required runtime `.dylib` files

The publisher selects only the current platform's MEX module and dynamic
libraries. Import libraries, object files, debug symbols, and binaries for
other platforms are not included in the generated toolbox.

The separate Polyscope MEX module remains in
`+plotter/+polyscope/vendor/+polyscope/private`, where its MATLAB package
wrapper expects to find it.
