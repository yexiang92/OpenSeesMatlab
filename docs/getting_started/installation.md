# Installation

OpenSeesMatlab can be installed either as a MATLAB toolbox or from GitHub source code.

---

## Option 1: Install via MATLAB Toolbox

1. Download the `.mltbx` file.
2. Double-click it in MATLAB.
3. Follow the installation prompts.


## Option 2: Install from GitHub
1. Download or clone the repository:
```bash
git clone https://github.com/your-username/OpenSeesMatlab.git
```

2. Add to MATLAB path:
```MATLAB
addpath(genpath('path_to_OpenSeesMatlab'));
savepath;
```

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