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

Download and install matching CUDA and cuDSS versions, and note their
installation directories for the configuration below.

## Configure the cuDSS runtime

If cuDSS is installed in its standard directory, try the shortest form first:

```matlab
ops.system("CuDSS");
```

If the runtime is not found, or if several CUDA versions are installed, pass
the two DLL locations explicitly with `-cudaPath` and `-cudssPath`.

For custom or Conda layouts, specify the two DLL directories independently.
Each value may be either the directory that directly contains the DLLs or an
installation root containing `bin` or `Library\bin`:

```matlab
% for cuda v12.6, for example
cudssPath = "C:\Program Files\NVIDIA cuDSS\v0.8\bin\12";
cudaPath = "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v12.6\bin";

% for cuda 13.1, for example
cudssPath = "C:\Program Files\NVIDIA cuDSS\v0.8\bin\13";
cudaPath = "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v13.1\bin";

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

Once the solver loads correctly, remove `-verbose` for normal runs:

```matlab
CuDSSOptions = {"-cudaPath", cudaPath, "-cudssPath", cudssPath};
ops.system("CuDSS", CuDSSOptions{:});
```

Keeping the options in a cell array is convenient when several scripts use the
same runtime. The `{:}` expands the cell contents into separate arguments. Add
`"-verbose"` only when checking which DLLs and GPU were selected.

## Options

All options below are passed through `ops.system` to the cuDSS extension.

| Option | Default | Description |
| --- | --- | --- |
| `-cudaMajor auto\|12\|13` | `auto` | Select the CUDA runtime major family. |
| `-cudaPath directory` | automatic | CUDA DLL directory or installation root. |
| `-cudssPath directory` | automatic | cuDSS DLL directory or installation root. |
| `-device auto\|index` | `auto` | Select one zero-based GPU index. |
| `-devices "i,j,..."` | disabled | Enable single-node multi-GPU execution on at least two GPUs. |
| `-cpuThreshold equations` | `0` | Use Eigen SparseLU at or below this equation count; zero disables CPU crossover. |
| `-reuseFactorization` | on | Reuse an existing numerical factorization when the newly assembled matrix is exactly unchanged. |
| `-noReuseFactorization` | off | Force numerical refactorization after OpenSees forms the tangent; useful for controlled benchmarks. |
| `-indexBits auto\|32\|64` | `auto` | Select CSR index width. Automatic mode uses 32-bit indices when the matrix fits and otherwise uses 64-bit indices. |
| `-reorder default\|btf\|colamd\|amd\|nd\|none` | `default` | Select the symbolic reordering algorithm. |
| `-factorization default\|multiblock\|general` | `default` | Select the numerical factorization algorithm. |
| `-pivot auto\|none\|globalCol\|globalRow\|diagonal\|local` | `auto` | Select numerical pivoting. Valid combinations depend on matrix type and reordering. |
| `-pivotThreshold value` | cuDSS default | Set the pivot acceptance threshold. |
| `-pivotEpsilon value` | cuDSS default | Set the static-pivot replacement epsilon. |
| `-refinement count` | `0` | Maximum iterative-refinement steps. |
| `-tolerance value` | `1e-12` | Iterative-refinement relative tolerance. |
| `-deterministic` | off | Request reproducible execution; it may reduce performance. |
| `-estimates` | off | Print factorization memory and FLOP estimates after analysis. |
| `-hybridMemory` | off | Allow factor data to use host and device memory. |
| `-hybridMemoryLimit bytes` | unset | Enable hybrid memory and set the per-device GPU memory limit. |
| `-hybridExecute` | off | Enable hybrid host/device execution. |
| `-hostThreads count` | cuDSS default | Set the host thread count for hybrid or MT execution. |
| `-threadingLayer library` | unset | Load a cuDSS-compatible threading backend, such as VCOMP on Windows. |
| `-schurSize equations` | disabled | Use the final N equations as a Schur set; currently requires `CuDSSSymmetric` or `CuDSSSPD`. |
| `-diagnostics` | off | Synchronize and query errors after each phase; debugging only. |
| `-verbose` | off | Print runtime, device, and transfer details. |

For example, a performance-oriented symmetric-indefinite configuration is:

```matlab
ops.system("CuDSSSymmetric", ...
    "-cpuThreshold", 1000, ...
    "-reorder", "amd", ...
    "-pivot", "diagonal");
```

Start with the default algorithms and benchmark alternatives on a representative
model. `amd` is often a useful symmetric baseline, while `btf` or `colamd` may
benefit general matrices. An incompatible reordering/pivot combination is
rejected by cuDSS rather than silently changed.

## Performance behavior

The implementation automatically selects 32-bit or 64-bit CSR indices, caches
the element-equation to CSR assembly mapping, uses asynchronous transfers on a
dedicated stream, reuses symbolic analysis, and uses refactorization when the
sparsity pattern is unchanged. If refactorization fails, it retries a complete
numerical factorization. When the assembled matrix is exactly unchanged, the
default `-reuseFactorization` behavior skips its upload and numerical
factorization and performs only the new right-hand-side solve.

Small systems can be faster on the CPU because GPU launch and transfer overhead
dominates. Tune `-cpuThreshold` with the actual model and hardware; values around
500--3000 equations are reasonable starting experiments, not universal defaults.
Single-node multi-GPU is intended for sufficiently large factorizations and may
be slower for modest systems. Hybrid memory primarily extends capacity when the
factorization does not fit in GPU memory and is not normally a speed optimization.

Do not enable `-diagnostics`, `-verbose`, or `-estimates` in production timing.
Deterministic execution can also reduce throughput. Schur mode performs the
reduced dense solve on the CPU and is beneficial only when the selected Schur
set is relatively small.

### A sensible tuning order

1. Run the model with a trusted CPU solver and keep its result and elapsed time
   as a reference.
2. Select `CuDSS` with default settings and confirm that the response agrees.
3. Remove `-verbose`, `-diagnostics`, and `-estimates` before measuring time.
4. If the analysis contains many small systems, test `-cpuThreshold` values
   such as `500`, `1000`, and `3000`.
5. Only then benchmark reordering or matrix-type variants on the full model.

Measure the complete analysis, not a single solve. GPU initialization can make
the first run slower, while symbolic-analysis reuse becomes useful over many
steps. Compare runs with the same model, recorder, and convergence settings.

A straightforward production setup is:

```matlab
CuDSSOptions = { ...
    "-cudaPath", cudaPath, ...
    "-cudssPath", cudssPath, ...
    "-cpuThreshold", 1000, ...
    "-refinement", 0};

ops.system("CuDSS", CuDSSOptions{:});
```

Do not copy `-cpuThreshold`, reordering, or pivot values blindly. The best
choice depends on equation count, sparsity pattern, GPU, and how often the
tangent matrix changes.

## Improving nonlinear analysis performance

Start with the general solver and the standard Newton algorithm. This is the
safest choice for nonlinear static and dynamic analysis:

```matlab
ops.system("CuDSS");
ops.test("NormDispIncr", 1.0e-8, 30);
ops.algorithm("Newton");
```

For static analysis, add the required load-control integrator. For dynamic
analysis, use the selected transient integrator as usual:

```matlab
% Static
ops.integrator("LoadControl", 0.01);
ops.analysis("Static");

% Dynamic
ops.integrator("Newmark", 0.5, 0.25);
ops.analysis("Transient");
```

Newton updates and refactorizes the tangent during nonlinear iteration. For a
large model, try `ModifiedNewton` or `KrylovNewton` if the tangent can remain
useful for several iterations:

```matlab
ops.algorithm("ModifiedNewton");
% or
ops.algorithm("KrylovNewton", "-maxDim", 10);
```

These methods may reduce factorization time, but they can require more
iterations. Use Newton again if convergence becomes slow or unreliable. Strong
plasticity, stiffness degradation, contact, snap-through, and changing time
steps generally reduce the opportunity to reuse a factorization.

CuDSS automatically reuses an unchanged matrix. This is especially effective
for linear dynamics and for repeated solves with a fixed tangent. Nonlinear
materials and geometric nonlinearity remain fully active; when the tangent
changes, CuDSS refactorizes it automatically.

Measure the complete analysis rather than a single solve. The first solve is
normally slower because it initializes the GPU and performs symbolic analysis
and factorization. Compare total time, convergence, and final response with a
trusted CPU solver such as UmfPack. Disable reuse only when measuring raw
factorization performance:

```matlab
ops.system("CuDSS", "-noReuseFactorization");
```

The C++ extension additionally supports multiple dense right-hand sides through
`SOE::solveMultiple`. The standard OpenSees `LinearSOE` analysis path continues
to submit one right-hand side. Cross-node MGMN and batching independent OpenSees
domains require an external communicator or analysis scheduler and are not
created automatically by `ops.system`.

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
