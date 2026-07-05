# ymiki-repo/nbody force kernel on MI300A (HIP port)

Benchmark of the direct all-pairs force kernel from
[ymiki-repo/nbody](https://github.com/ymiki-repo/nbody),
`cpp/cuda/11_memcpy_rsqrt/nbody_leapfrog2.cu` (the `cudaMemcpy` + `rsqrtf`
variant of the 2nd-order leapfrog scheme), ported to AMD GPUs and measured on
an **AMD Instinct MI300A** (`gfx942`, ROCm 7.2.0). This is the CUDA counterpart
of the JACC.jl benchmark in the repository root, for a direct comparison.

## Approach

The upstream project is CUDA-only and its CMake build has **no HIP target**, so
setting `BENCHMARK_MODE=ON` alone does not build on an AMD GPU. Instead:

1. Hipify the single translation unit with `hipify-perl` (only the CUDA runtime
   calls change: `cudaMalloc`→`hipMalloc`, etc.; the kernel, `<<<>>>` launch,
   and `rsqrtf` are unchanged).
2. Compile it directly with `hipcc --offload-arch=gfx942`, enabling the
   project's own `BENCHMARK_MODE`. **The measurement logic is upstream's, not
   ours** — `BENCHMARK_MODE` is the built-in benchmark harness that
   auto-adjusts the iteration count until the minimum wall time is reached and
   writes `interactions/s` and `Flop/s` to `log/collapse_run.csv`.

`boost` 1.75 and an `hdf5.h` header are available system-side. In
`BENCHMARK_MODE` no HDF5 function is called (`util/hdf5.hpp` only needs to
parse), so `libhdf5` is never linked.

`nbody_leapfrog2.hip` in this directory is a committed reference copy of the
hipify output; `build.sh` regenerates it from a pinned upstream commit
(`1834c7d`) and is the source of truth for building.

### Precision variants

The FLOP count matches the JACC.jl benchmark (leapfrog, no potential term →
`FLOPS_PER_INTERACTION = 22`, `rsqrt` counted as 4 FLOP), so `interactions/s`
is directly comparable across all rows.

| binary | `FP_L` | `FP_M` | meaning |
|--------|:------:|:------:|---------|
| `nbody_bench_fp32`  | 32 | 32 | full single precision |
| `nbody_bench_mixed` | 32 | 64 | **the actual default of `11_memcpy_rsqrt`**: FP64 storage/accumulation, FP32 `rsqrtf` |
| `nbody_bench_fp64`  | 64 | 64 | full double precision (Newton–Raphson refined `rsqrt`) |

## Build & run

```sh
module load rocm/7.2.0
cd cpp-hip
./build.sh                 # clones pinned upstream, hipifies, builds 3 binaries into build/
qsub run_bench.pbs         # runs on one MI300A via the debug queue
```

## Results (MI300A, gfx942, ROCm 7.2.0)

Peak at N = 2²⁰ = 1,048,576 (sweep N = 1024 .. 2²⁰, 11 points, min 0.5 s).
Full sweep in [`hip_bench.out`](hip_bench.out).

| precision | interactions/s | GFLOP/s |
|-----------|---------------:|--------:|
| FP32  | 1.384×10¹² | 30446 |
| mixed (default) | 1.208×10¹² | 26582 |
| FP64  | 0.996×10¹² | 21905 |

### Comparison with JACC.jl (same MI300A, same 22-FLOP kernel)

`interactions/s` is the fair metric (precision-independent):

| precision | ymiki-repo (HIP) | JACC.jl | JACC.jl / ymiki |
|-----------|-----------------:|--------:|:---------------:|
| FP32 GFLOP/s | 30446 | 36836 | **1.21× (JACC faster)** |
| FP64 GFLOP/s | 21905 | 20825 | **0.95× (ymiki faster)** |

So on the MI300A the JACC.jl kernel is ~21 % faster in FP32, while the hand-written
CUDA/HIP kernel is ~5 % faster in FP64. (The `mixed` variant is the honest
default of this upstream directory but has no JACC.jl counterpart.)

Note: at large N the iteration count drops to a few, so mid-sweep points carry
more timing noise; the N = 2²⁰ peak (a clean single-launch measurement) is the
most reliable comparison point.
