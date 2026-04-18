# 🚀 OpenSeesMatlab

**OpenSeesMatlab** is a MATLAB interface for the [OpenSees](https://opensees.github.io/OpenSeesDocumentation/) finite element framework. It is designed to provide a more natural MATLAB workflow for structural modeling, analysis, post-processing, and visualization, while preserving the full power of OpenSees.

✨ The project aims to make OpenSees easier to use in MATLAB by offering:

- a clearer and more consistent command interface  
- MATLAB-friendly data access  
- integrated visualization and documentation tools  

---

## ⚡ Quick Start

Using `OpenSeesMatlab` is straightforward:

- The **`opensees`** module provides wrappers for almost all OpenSees commands, keeping the same parameter parsing style as OpenSees/OpenSeesPy.
- Modules such as **`vis`**, **`post`**, and **`pre`** extend functionality with visualization, post-processing, and preprocessing tools, which can be used as needed.

```matlab
opsMat = OpenSeesMatlab();   % Get instance
ops = opsMat.opensees;       % Access OpenSees command interface

ops.wipe();
ops.model('basic', '-ndm', 2, '-ndf', 3);

ops.node(1, 0.0, 0.0);
ops.node(2, 5.0, 0.0);
ops.fix(1, 1, 1, 1);

A = 2.e-3;
Iz = 1.6e-5;
E = 200.e9;
ops.element('elasticBeamColumn', 1, 1, 2, A, E, Iz, 1)

...

opsMat.post.getModelData();  % Collect model data
opsMat.vis.plotModel();      % Visualize the model
```

## 🌟 Features
- 🧱 **`.opensees`** — MATLAB interface to all OpenSees commands (fully compatible syntax), implemented via MATLAB MEX wrapping of the OpenSees C++ library
- 📊 **`.post`** — post-processing module for extracting, organizing, and exporting analysis results
- 🏗️ **`.pre`** — preprocessing tools for model definition, units, and data preparation
- 🎨 **`.vis`** — visualization engine for models, responses, and mode shapes
- 📈 **`.anlys`** — high-level analysis workflows and utilities
- 🛠️ **`.utils`** — auxiliary helper functions and common utilities

---

## 📌 Notes

OpenSeesMatlab is intended for users who want to combine:

- the computational power of OpenSees ⚙️
- with the scripting, visualization, and data-processing capabilities of MATLAB 📊

📚 The project is actively evolving — more examples, utilities, and documentation will be added over time.

⚠️ This is a non-profit open-source project. Use at your own risk.

---

## 🔗 Related Links

- 📘 [OpenSees Official Documentation](https://opensees.github.io/OpenSeesDocumentation/)
- 🐍 [OpenSeesPy Documentation](https://openseespydoc.readthedocs.io/en/latest/index.html)
- 🧰 [opstool](https://github.com/yexiang92/opstool)
- 📐 [MATLAB](https://www.mathworks.com/)