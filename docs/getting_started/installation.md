# Installation

OpenSeesMatlab is currently distributed as a MATLAB toolbox for Windows. MATLAB R2023a or later is required.

## Install a released version

1. Download a release from [GitHub](https://github.com/yexiang92/OpenSeesMatlab/releases) or [Gitee (China)](https://gitee.com/yexiang-yan/opensees-interface-for-matlab/releases).
2. Extract the release to a directory where you have write permission.
3. In MATLAB, change to that directory and run:
   ```matlab
   cd('path_to_openseesmatlab_directory');
   installOpenSeesMatlab;
   ```
4. Restart MATLAB if the installer requests it.

The MATLAB File Exchange package is not yet available.

## Verify the installation

Run this in a new MATLAB session:

```matlab
opsMat = OpenSeesMatlab();
opsMat.version
opsMat.opensees.wipe();
```

A returned version and no constructor error indicate that MATLAB can find both the toolbox and its OpenSees MEX module.

You can also check which installation MATLAB resolves:

```matlab
which OpenSeesMatlab -all
```

If more than one copy is listed, remove old copies from the MATLAB path so that scripts do not load a different release than expected.

## Run an example

The `examples` directory contains Live Scripts grouped by engineering topic. Open a `.mlx` file in MATLAB Live Editor and run its sections in order. A good first choice is a small structural example; response and visualization examples are useful after you understand the basic command workflow.

Next, follow [Your first analysis](quickstart.md) for a complete model–analysis–result cycle, or browse the [examples](../examples/index.md).

## Requirements and limitations

| Item | Requirement |
|---|---|
| MATLAB | R2023a or later |
| Operating system | Windows |
| OpenSees engine | Included through the OpenSeesMatlab MEX interface |
| Interactive Polyscope viewer | Requires the packaged Polyscope MEX binary |

!!! note "Polyscope is optional for core analysis"

    The OpenSees command interface and regular MATLAB visualization do not
    depend on opening a Polyscope window. Use `opsMat.vis.polyscope` only when
    you want the interactive Polyscope GUI.

## Troubleshooting

### `OpenSeesMatlab` is not found

- Confirm that installation completed without an error.
- Run `which OpenSeesMatlab -all`.
- Re-run `installOpenSeesMatlab` from the extracted release directory.

### The MEX file cannot be loaded

- Confirm that you are using supported 64-bit Windows and MATLAB R2023a or later.
- Do not mix files from different OpenSeesMatlab releases.
- Check whether endpoint security software quarantined a packaged binary.

### A Polyscope viewer cannot start

- Confirm that the release contains the packaged Polyscope MEX binary.
- Update the graphics driver and try a regular MATLAB plot with `opsMat.vis.plotModel()` to distinguish a graphics-backend issue from a model issue.
- Core OpenSees analyses can still run without the interactive viewer.

## Performance guidance

For the lowest overhead, use `opsMat.opensees` with standard OpenSees recorders or direct query commands. The `.pre`, `.post`, and `.vis` modules trade some overhead for MATLAB-friendly workflows, structured data, and interactive exploration.

## Version numbers

OpenSeesMatlab uses `MAJOR.MINOR.PATCH.BUILD`. The first three fields identify the corresponding OpenSees release; `BUILD` identifies an OpenSeesMatlab revision built on it. For example, `3.8.0.2` is the second OpenSeesMatlab build based on OpenSees 3.8.0.

See the [changelog](changelog.md) for release-specific changes.
