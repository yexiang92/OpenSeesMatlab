# Installation

OpenSeesMatlab can be installed either as a MATLAB toolbox or from GitHub source code.

---


## Option 1: Install from GitHub
1. Go to the [OpenSeesMatlab GitHub Repository](https://github.com/yexiang92/OpenSeesMatlab).
2. Go to the [release directory](https://github.com/yexiang92/OpenSeesMatlab/releases) and choose the version you want, for example `release/3.8.0.0/`. Download it.
3. Open this release directory in MATLAB, then install the toolbox package by running:
   ```matlab
   installOpenSeesMatlab
   ```


## Option 2: Install from MATLAB File Exchange

Coming soon

---

After installation, explore and run example models in the `examples/` directory (You need to use it as your working directory):

   - Open any `.mlx` file in `examples/` with MATLAB Live Editor, e.g.:
   - `examples/earthquake_frame3D_transient.mlx`
   - `examples/structural_nonlinear_truss.mlx`
   - `examples/geotechnical_PM4Sand.mlx`
   - `examples/post_2d_Portal_Frame.mlx`
   - Click "Run" in MATLAB to execute and interact with the example.

## Versioning

OpenSeesMatlab uses a four-part version number in the format `MAJOR.MINOR.PATCH.BUILD`. The `MAJOR.MINOR.PATCH` portion matches the official OpenSees release version, while `BUILD` identifies the incremental OpenSeesMatlab revision built for that specific OpenSees release. For example, in version `3.8.0.1`, `3.8.0` refers to the corresponding official OpenSees version, and `1` indicates the OpenSeesMatlab release built on top of it.

## Requirements

MATLAB R2023a or later

Windows operating system (currently only supported on Windows)

## Changes Log
[Changes Log](changelog.md)
