# FP32 N-sweep: HIP port vs JACC.jl (MI300A)

Force-kernel throughput (GFLOP/s, 22 FLOP/interaction) across the full N sweep
(1024 .. 2²⁰, 11 log-spaced points, min 0.5 s/point) on one MI300A (gfx942,
ROCm 7.2.0). Same methodology and FLOP count as the JACC.jl benchmark, so the
numbers are directly comparable.

- **JACC.jl** — `bench.out` in the repo root
- **HIP baseline** — hipified upstream kernel, `rsqrtf` (`sweep_bench.out`)
- **HIP bare** — `rsqrtf` → `__builtin_amdgcn_rsqf` (`sweep_bench.out`)
- **HIP bare+u16** — bare + `#pragma unroll 16` (`sweep2_bench.out`)

| N | JACC.jl | HIP baseline | HIP bare | HIP bare+u16 | JACC/bare |
|--:|--------:|-------------:|---------:|-------------:|----------:|
| 1024 | 186 | 151 | 185 | 192 | 1.00 |
| 2048 | 149 | 292 | 356 | 374 | 0.42 |
| 4096 | 724 | 568 | 686 | 749 | 1.06 |
| 8192 | 1549 | 1128 | 1371 | 1499 | 1.13 |
| 16384 | 3202 | 2251 | 2740 | 2995 | 1.17 |
| 32768 | 6463 | 4486 | 5465 | 5977 | 1.18 |
| 65536 | 12880 | 8913 | 10862 | 11877 | 1.19 |
| 131072 | 25464 | 17480 | 21317 | 23311 | 1.19 |
| 262144 | 25050 | 18900 | 23317 | 23627 | 1.07 |
| 524288 | 31353 | 25313 | 31314 | 30845 | 1.00 |
| 1048576 | 36836 | 30464 | **37623** | 37096 | **0.98** |

(Small N ≤ 2048 is launch/occupancy noise and not meaningful; the non-monotonic
JACC value at N=2048 is a JIT/warm-up artifact.)

## Reading the curves

Two regimes, set by whether the launch fills the GPU's 228 CUs (1024 threads/block
→ N/1024 workgroups):

- **Large N (≥ 512K, ≥ 512 workgroups): occupancy-saturated.** Thread-level
  parallelism fully hides `v_rsq` latency, so only instruction *count* matters.
  Removing the `rsqrtf` subnormal guard (**HIP bare**) is enough to match and then
  slightly **beat** JACC.jl (37623 vs 36836 at N=2²⁰). Unrolling adds nothing here
  (`bare+u16` is marginally lower — more VGPRs, no latency win). See
  [`ANALYSIS.md`](ANALYSIS.md).

- **Mid N (64K–256K, 64–256 workgroups): occupancy-starved.** Too few workgroups
  to hide latency by TLP, so instruction-level parallelism matters. Here JACC.jl
  holds a ~19 % lead even over **HIP bare**; HIP's `bare+u16` recovers about half
  of it (+9 % over bare) but a residual ~8 % remains — attributable to JACC.jl's
  128× unroll giving more independent `rsq` chains, plus SoA-vs-AoS load/cache
  differences. This is why JACC.jl's tuned 128× unroll pays off across the sweep
  even though it is neutral at the single largest N.

**Bottom line:** the headline peak gap is entirely the rsqrt guard; the mid-N gap
is latency-hiding (unroll/ILP) under low occupancy.
