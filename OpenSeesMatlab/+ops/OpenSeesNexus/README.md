# OpenSeesNexus for MATLAB

OpenSeesNexus is the standalone MATLAB command interface to OpenSeesBindings.
It includes the public `OpenSeesNexus` class, the private implementation
package, launchers, and native binaries. Plotting and post-processing remain in
the higher-level OpenSeesMatlab toolbox.

## Install and use

Add the extracted directory itself to the MATLAB path:

```matlab
addpath("OpenSeesNexus");
ops = OpenSeesNexus();

ops.wipe();
ops.model("basic", "-ndm", 2, "-ndf", 2);
ops.node(1, 0.0, 0.0);
```

The compatible raw entry point `OpenSeesMATLAB("command", ...)` uses the same
native model state. For normal code, prefer the class because its named methods
support MATLAB IDE completion.

## Directory layout

```text
OpenSeesNexus/
├── OpenSeesNexus.m
├── OpenSeesSPMatlab.cmd/.ps1/.sh
├── +nexus/                         internal MATLAB implementation
└── derived/
    ├── windows-x86_64/             Windows native bundle
    └── macos-aarch64/              Apple-silicon native bundle
```

`OpenSeesNexus` is the only normal command entry point. The `nexus` package is
an implementation detail rather than another installation layer. The runtime
selects the current platform automatically. `OPENSEES_MATLAB_DIR` may override
the native directory for development.

The higher-level OpenSeesMatlab project copies this complete directory to
`OpenSeesMatlab/+ops/OpenSeesNexus`. Bridge files beside it connect the
toolbox command class to this sublibrary. Its publisher retains only the host
platform's native directory in each generated toolbox.

## OpenSeesSP

Serial OpenSees is selected by default. Start a four-rank SP model with:

```powershell
.\OpenSeesSPMatlab.cmd 4 model.m
```

On macOS:

```bash
./OpenSeesSPMatlab.sh 4 model.m
```

The launcher locates MATLAB and MPI, selects the SP backend for the child job,
and does not persistently change the user's environment. When multiple
installations exist, Windows users can pass `-MatlabExecutable` and
`-MpiExecutable`; both platforms also recognize
`OPENSEES_MATLAB_EXECUTABLE` and `OPENSEES_MPIEXEC`.

For manual startup, select SP before constructing the interface:

```matlab
OpenSeesNexus.setBackend("sp");
ops = OpenSeesNexus();
```

Only rank zero starts MATLAB; worker ranks use `OpenSeesSPWorker`.

## Output

`writeFEMDataPVD` defaults to `.openseesmatlab.output`. A higher-level package
may supply another output directory. Set `OPENSEES_MATLAB_QUIET=1` before
startup to hide the one-time package banner; `suppressPrint(true)` controls
ordinary OpenSees output.
