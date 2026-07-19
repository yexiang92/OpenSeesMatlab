# NVIDIA cuDSS GPU Solver

!!! note

    - [cuDSS](https://developer.nvidia.com/cudss) is an optional OpenSeesMatlab extension for solving sparse linear systems on an NVIDIA GPU.
    - CPU solvers continue to work without an NVIDIA GPU, CUDA, or cuDSS.
    - The current binary supports the cuDSS 0.8 API. CUDA 12 is validated; CUDA 13 runtime discovery is available but has not yet been validated on a CUDA 13 test machine.

The cuDSS backend can accelerate repeated sparse factorizations in large models.
For small systems, CPU solvers may remain faster because GPU initialization,
data transfer, and kernel-launch overhead are comparable with the solve itself.

## User requirements

To use cuDSS, the user computer needs:

!!! info

    - a CUDA-capable NVIDIA GPU;
    - an NVIDIA driver compatible with the selected CUDA version;
    - [CUDA](https://developer.nvidia.com/cuda-toolkit-archive) 12 or CUDA 13 runtime and cuBLAS libraries;
    - NVIDIA [cuDSS](https://developer.nvidia.com/cudss) **0.8** built for the same CUDA major version; and

Users do not need Visual Studio, CMake, `nvcc`, or MATLAB Parallel Computing
Toolbox. A newer supported NVIDIA GPU is allowed; the MEX is not tied to the GPU
used when it was compiled.

## Configure the cuDSS runtime

If cuDSS is installed in its standard directory, automatic discovery is usually
enough. Otherwise, set the installation directory before creating the solver:

The paths may also be supplied directly to `ops.system` with `-cudaPath` and
`-cudssPath`. This is useful when several CUDA or cuDSS versions are installed.

For custom or Conda layouts, specify the two DLL directories independently.
Each value may be either the directory that directly contains the DLLs or an
installation root containing `bin` or `Library\bin`:

```matlab
% for cuda v12.6, for example
cudssPath = "C:\Program Files\NVIDIA cuDSS\v0.8\bin\12";
cudaPath = "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v12.6\bin"

% for cuda 13.1, for example
cudssPath = "C:\Program Files\NVIDIA cuDSS\v0.8\bin\13";
cudaPath = "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v13.1\bin"

ops.system("CuDSS", ...
    "-cudaPath", cudaPath, ...   % cudart64_*.dll, cublas64_*.dll, cublasLt64_*.dll
    "-cudssPath", cudssPath, ...  % cudss64_0.dll
    "-verbose");
```

If neither path is supplied, the loader searches the CUDA environment variables,
the cuDSS environment variables, standard installation directories, and the
normal Windows DLL search path automatically. A supplied path may be either an
installation root or the DLL directory itself; the loader also checks `bin`,
`Library\bin`, and the cuDSS version-specific `bin\12` or `bin\13` directory.

!!! warning

    The cuDSS package must match the selected CUDA major version. Do not mix a CUDA 12 cuDSS DLL with CUDA 13 runtime DLLs. cuDSS 0.9 and 1.x are not accepted by the current MEX until those APIs have been explicitly supported and validated.

## Basic usage

Create the OpenSeesMatlab interface as usual:

```matlab
opsMat = OpenSeesMatlab();
ops = opsMat.opensees;

ops.wipe();
% Define the model, materials, nodes, elements, constraints, and loads.
```

Select the general cuDSS solver before creating the analysis:

```matlab
ops.constraints("Transformation");
ops.numberer("RCM");

ops.system("CuDSS", ...
    "-cudaPath", cudaPath, ...
    "-cudssPath", cudssPath, ...
    "-verbose");

ops.test("NormDispIncr", 1.0e-8, 20);
ops.algorithm("Newton");
ops.integrator("Newmark", 0.5, 0.25);
ops.analysis("Transient");
```

With `-cudaMajor "auto"`, the loader tries CUDA 13 and then CUDA 12. With
`-device "auto"`, it selects an available GPU. The `-verbose` option prints the
loaded runtime and selected device, for example:

```text
CuDSS: loaded CUDA 12 and cuDSS 0.8 at runtime
CuDSS: selected GPU 0 (compute capability 8.6)
```

The default `-refinement` value is `0`. OpenSeesMatlab reuses the cuDSS
reordering and symbolic analysis while the equation graph is unchanged, uses
refactorization for later changed tangent matrices, and skips the matrix upload
and factorization when only the right-hand side changes.

For troubleshooting, add `-diagnostics`:

```matlab
ops.system("CuDSS", "-diagnostics", "-verbose");
```

Diagnostic mode synchronizes and queries device-side information after every
cuDSS phase. It is useful for locating asynchronous GPU errors but adds overhead,
so do not enable it for normal timing or production analysis.

To select a specific installation and GPU:

```matlab
ops.system("CuDSS", ...
    "-cudaMajor", 12, ...
    "-cudaPath", "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v12.6", ...
    "-cudssPath", "C:\Program Files\NVIDIA cuDSS\v0.8", ...
    "-device", 0, ...
    "-refinement", 0);
```

The CUDA and cuDSS DLLs may also be kept in different directories:

```matlab
ops.system("CuDSS", ...
    "-cudaMajor", 12, ...
    "-cudaPath", "D:\runtimes\cuda12", ...
    "-cudssPath", "D:\runtimes\cudss08", ...
    "-device", 0);
```

## Choosing the matrix type

The following variants are available:

| Command | Matrix assumption | Recommended use |
| --- | --- | --- |
| `CuDSS` or `CuDSSGeneral` | General sparse matrix | Safest choice for nonlinear analysis |
| `CuDSSSymmetric` | Symmetric indefinite | Use only when symmetry is guaranteed |
| `CuDSSSPD` | Symmetric positive definite | Use only when positive definiteness is guaranteed |

For strongly nonlinear earthquake analysis, start with `CuDSS`. A tangent
matrix may become indefinite even if the initial elastic stiffness is positive
definite.

## CPU fallback

OpenSeesMatlab does not automatically replace cuDSS with a CPU solver when GPU
configuration fails. Select the desired CPU solver explicitly:

```matlab
ops.system("UmfPack");
```

CPU solvers do not load CUDA or cuDSS and are unaffected when the GPU runtime is
not installed.

## Troubleshooting

If cuDSS cannot be selected:

1. Run `nvidia-smi` and confirm that Windows can see the GPU.
2. Confirm that CUDA, cuBLAS, and cuDSS use the same CUDA major version.
3. Pass `-cudaPath`, `-cudssPath`, and `-cudaMajor` explicitly.
4. Use `-verbose` to display the selected runtime and GPU.
5. Add `-diagnostics` to report asynchronous device-side phase errors.
6. Confirm that MATLAB is loading the GPU-enabled MEX with:

```matlab
which OpenSeesMATLAB -all
```

If an analysis fails only with an SPD or symmetric variant, retry with the
general `CuDSS` solver and check the model constraints, conditioning, and
nonlinear convergence settings.

## Examples

[Extensions Examples](../../examples/extension/index.md)
