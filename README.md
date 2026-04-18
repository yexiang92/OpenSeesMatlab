# OpenSeesMatlab

[![Documentation Status](https://readthedocs.org/projects/OpenSeesMatlab/badge/?version=latest)](https://openseesmatlab.readthedocs.io/en/latest/)
<!-- [![github stars](https://img.shields.io/github/stars/yexiang92/OpenSeesMatlab?style=social)](https://github.com/yexiang92/OpenSeesMatlab) -->
[![GitHub License](https://img.shields.io/github/license/yexiang92/OpenSeesMatlab?style=flat)](https://img.shields.io/github/license/yexiang92/OpenSeesMatlab?style=flat)

OpenSeesMatlab is a MATLAB-based platform for structural analysis and simulation. It aims to provide powerful modeling, analysis, post-processing, and visualization tools for research and engineering applications in structural, earthquake, and geotechnical engineering.

## OpenSees Integration
OpenSeesMatlab leverages MATLAB's C++ mex interface to encapsulate the [OpenSees engine](https://opensees.github.io/OpenSeesDocumentation/), enabling seamless and interactive use of OpenSees directly within MATLAB. This allows users to:
- Run OpenSees commands and analyses natively in MATLAB scripts and functions
- Benefit from MATLAB's interactive environment for pre/post-processing and visualization
- Integrate OpenSees with MATLAB toolboxes and workflows


## 🌟 Features
- 🧱 **`.opensees`** — MATLAB interface to OpenSees commands (fully compatible syntax), implemented via MATLAB MEX wrapping of the OpenSees C++ library
- 📊 **`.post`** — post-processing module for extracting, organizing, and exporting analysis results
- 🏗️ **`.pre`** — preprocessing tools for model definition, units, and data preparation
- 🎨 **`.vis`** — visualization engine for models, responses, and mode shapes
- 📈 **`.anlys`** — high-level analysis workflows and utilities
- 🛠️ **`.utils`** — auxiliary helper functions and common utilities


## Quick Start
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

For more detailed installation and usage instructions, see the documentation.

## Documentation
[https://openseesmatlab.readthedocs.io/en/latest/](https://openseesmatlab.readthedocs.io/en/latest/)


## License
This project is licensed for academic research and personal use only. Commercial and closed-source use is prohibited. See the [LICENSE](LICENSE) file for details.