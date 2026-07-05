# JACC.jl N-body Benchmark

A force-kernel benchmark for the N-body problem (direct all-pairs method)
using [JACC.jl](https://github.com/JuliaGPU/JACC.jl).
The kernel is based on the `calc_acc` acceleration computation of the
2nd-order leapfrog, direct all-pairs (O(N²)) scheme from
[ymiki-repo/nbody](https://github.com/ymiki-repo/nbody). Following that
repository's `BENCHMARK_MODE`, this benchmark measures the **performance of
the force (acceleration) kernel alone** while varying N.

## Algorithm

- Acceleration: `a_i = Σ_j m_j (r_j - r_i) / (r_ji² + ε²)^{3/2}`, gravitational constant `G = 1`
- Plummer softening: `ε = 1/64`
- Initial conditions: uniform sphere (radius 1, total mass 1, equal-mass particles)
- **22 FLOP** per interaction (the reciprocal-sqrt is counted as 4 FLOP)
- Data layout: SoA (positions `x,y,z`, mass `m`, accelerations `ax,ay,az` in separate arrays)

## Requirements

- Julia 1.11 or later

## Setup

```sh
julia --project -e 'using Pkg; Pkg.instantiate()'
```

## Running

CPU threads backend (default; no extra installation required):

```sh
# Default sweep: N = 1024 .. 2^20, 11 points
julia --project -t auto nbody_jacc.jl

# Specify N_min N_max N_bins via arguments
julia --project -t auto nbody_jacc.jl 1024 2097152 12
```

Switch to double precision (`Float64`; the default is `Float32`):

```sh
JACC_NBODY_FP=64 julia --project -t auto nbody_jacc.jl
```

## Running on GPU backends

Setting the backend once generates a `LocalPreferences.toml`.
After that, the script can be run unchanged.

```sh
# Example: CUDA. "amdgpu" / "metal" / "oneapi" work the same way
julia --project -e 'import JACC; JACC.set_backend("cuda")'
julia --project nbody_jacc.jl
```

To switch back to CPU threads:

```sh
julia --project -e 'import JACC; JACC.set_backend("threads")'
```

## Output

- At runtime, a small-scale (N=256) correctness check is performed,
  comparing against a naive sequential host-side implementation by
  relative L2 error.
- On GPU backends, the threadgroup size (`{64,128,256,512,1024}`) is
  lightly auto-tuned at startup, and the fastest value is used for the
  entire sweep (shown in the `threadgroup size` line of the header). On
  the CPU threads backend, auto-tuning is skipped and JACC's default
  launch configuration is used (shown as `auto (JACC default)`).
- At each point of the N sweep, the iteration count is automatically
  adjusted until the minimum measurement time (0.5 s) is reached, and
  `interactions/s` and `GFLOP/s` are printed in tabular form.

Example output on an **AMD Instinct MI300A** (`gfx942`, ROCm 7.2.0,
AMDGPU.jl 2.5.1; loop unrolled 128x, tuned with `tune_unroll.jl` at N=524288):

```
JACC.jl N-body benchmark - direct all-pairs leapfrog force kernel
  backend array type : AMDGPU.ROCArray
  CPU threads        : 1
  precision          : Float32
  threadgroup size   : 1024
  N sweep            : 1024 .. 1048576 (11 log-spaced points)

correctness check: N=256, relative L2 error = 1.102e-07 (tol 1e-03)

           N    iters      time[s]     interactions/s      GFLOP/s
        1024     4096       0.5084         8.4474e+09      185.842
       32768      256       0.9356         2.9379e+11     6463.320
      131072       64       0.9499         1.1575e+12    25464.078
      524288        4       0.7715         1.4251e+12    31352.894
     1048576        1       0.6567         1.6744e+12    36835.766

peak performance: 36835.766 GFLOP/s  (22 FLOP per interaction)
```

Peak throughput on the MI300A (11-point sweep, N up to 2^20):

| precision | peak GFLOP/s | at N     |
|-----------|-------------:|---------:|
| Float32   |     36835.8  | 1048576  |
| Float64   |     20824.6  | 1048576  |
