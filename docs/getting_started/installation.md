# Installation

OpenSeesMatlab can be installed either as a MATLAB toolbox or from GitHub source code.

---

## Option 1: Install from MATLAB File Exchange

1. Download the `.mltbx` file.
2. Double-click it in MATLAB.
3. Follow the installation prompts.


## Option 2: Install from GitHub
1. Go to the [OpenSeesMatlab GitHub Repository](https://github.com/yexiang92/OpenSeesMatlab).
1. Go to the `release/` directory and choose the version you want, for example `release/v3.8.0.0/`. Download it.
2. Install the MATLAB toolbox package (`.mltbx`), for example:
   - `release/v3.8.0.0/OpenSeesMatlab_v3.8.0.0.mltbx`
   - You can install it by double-clicking the file in MATLAB, or by using the Add-On installer.
3. After installation, explore and run example models in the `examples/` directory:
   - Open any `.mlx` file in `examples/` with MATLAB Live Editor, e.g.:
     - `examples/earthquake_frame3D_transient.mlx`
     - `examples/structural_nonlinear_truss.mlx`
     - `examples/geotechnical_PM4Sand.mlx`
     - `examples/post_2d_Portal_Frame.mlx`
   - Click "Run" in MATLAB to execute and interact with the example.

## Versioning

OpenSeesMatlab follows a four-part versioning scheme:

``MAJOR.MINOR.PATCH.BUILD``


- **MAJOR.MINOR.PATCH**: Correspond to the official release version of OpenSees.
- **BUILD**: Indicates the incremental OpenSeesMatlab revision built on top of that specific OpenSees version.

For example:

``3.8.0.1``

- `3.8.0`: The OpenSees official release version.
- `1`: The OpenSeesMatlab release for this OpenSees version.

## Requirements

MATLAB R2023a or later

Windows operating system (currently only supported on Windows)