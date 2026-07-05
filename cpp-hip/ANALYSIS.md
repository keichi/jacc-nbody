# Why the FP32 force kernel is ~21 % slower in HIP than in JACC.jl (MI300A)

Peak FP32 at N = 2²⁰ on the MI300A (gfx942, ROCm 7.2.0):

| kernel | GFLOP/s | interactions/s |
|--------|--------:|---------------:|
| ymiki-repo HIP (`rsqrtf`, as-hipified) | 30456 | 1.384×10¹² |
| JACC.jl (`amdgcn.rsq.f32` intrinsic) | 36836 | 1.674×10¹² |

The entire gap has **a single root cause**, confirmed by ISA inspection and by
attribution experiments.

## Root cause: the `rsqrtf` subnormal guard

The kernel is **VALU-throughput bound**, not memory bound:

- `jpos[jj]` is the same address for every lane, so the compiler emits a
  **scalar broadcast load** (`s_load_dwordx4`), not vector global loads.
- The math is packed FP32 (`v_pk_add_f32` / `v_pk_mul_f32` / `v_pk_fma_f32`).
- Only **14 VGPRs** are used → occupancy is saturated, so thread-level
  parallelism already hides instruction latency.

In that regime every extra VALU instruction in the inner loop costs throughput.
ROCm's `rsqrtf()` does **not** compile to a bare `v_rsq_f32`; it wraps the
hardware instruction in a range-reduction guard for subnormal / extreme inputs
(`asm_baseline.s`):

```
v_mul_f32    v12, 0x4b800000, v7   ; scale input by 2^24 if it is subnormal
v_cmp_gt_f32 vcc, 0x800000, v7     ; r2 < FLT_MIN ?
v_cndmask_b32 v7, v7, v12, vcc
v_rsq_f32    v7, v7                ; <-- the only instruction JACC emits
v_mul_f32    v12, 0x45800000, v7   ; correct the result by 2^-12
v_cndmask_b32 v7, v7, v12, vcc
```

That is ~5 extra VALU ops out of ~16 in the loop body (~30 %). JACC.jl calls the
raw `amdgcn.rsq.f32` intrinsic (`@fastmath` + per-backend `rsqrt`), so it emits
just `v_rsq_f32` with no guard (`asm_bare_rsq.s`: `v_cndmask` count 2 → 0).

Crucially the guard is **dead code for this problem**: with Plummer softening
`eps = 1/64`, `r2 = eps² + dx²+dy²+dz² ≥ (1/64)² ≈ 2.4×10⁻⁴`, which is ~34 orders
of magnitude above `FLT_MIN ≈ 1.2×10⁻³⁸`. The subnormal branch is never taken, so
removing it changes nothing numerically.

## Attribution experiment (`nbody_exp.hip`)

`nbody_exp.hip` adds two compile-time switches to the hipified kernel:
`-DBARE_RSQ` (replace `rsqrtf` with `__builtin_amdgcn_rsqf`) and
`-DUNROLL_N=n` (`_Pragma("unroll n")` on the j-loop). FP32, N = 2²⁰:

| variant | GFLOP/s | vs baseline |
|---------|--------:|------------:|
| baseline (`rsqrtf`)            | 30456 | — |
| **bare rsq**                   | **37679** | **+23.7 %** |
| bare + unroll×4                | 36727 | +20.6 % |
| bare + unroll×8                | 36998 | +21.5 % |
| bare + unroll×16               | 37070 | +21.7 % |
| bare + unroll×128              | 36506 | +19.9 % |

Removing the guard **alone** recovers the full gap and slightly **beats** JACC.jl
(37679 vs 36836).

## What is *not* the cause

- **`-ffast-math`**: FP32 ISA is byte-identical with and without it (`fast_bench.out`,
  +0.2 %). The FP32 path already uses an explicit hardware `rsqrtf` and clang
  contracts FMAs by default (`-ffp-contract=fast`), so there is nothing for
  fast-math to change — and notably it does **not** strip the rsqrt guard.
- **Loop unrolling**: adding 4–128× unroll on top of `bare` does not help and
  slightly regresses (more VGPRs, lower occupancy; no latency benefit when
  occupancy is already saturated and loop control runs on the scalar unit).
  JACC.jl's tuned 128× unroll is near-neutral *for this kernel on this GPU* — its
  speed comes from the bare `rsq` intrinsic, not the unroll.

## Takeaway

To match/beat JACC.jl in FP32, change one line in the upstream kernel:

```cpp
// const auto r_inv = rsqrtf(type::cast2fp_l(r2));   // guarded, ~5 extra VALU ops
const auto r_inv = __builtin_amdgcn_rsqf(type::cast2fp_l(r2));  // bare v_rsq_f32
```

(Numerically safe here because `r2 ≥ eps²`; a general library would keep the guard.)

Reproduce: `asm_baseline.s`, `asm_bare_rsq.s` (ISA); `exp_bench.out`,
`exp2_bench.out`, `fast_bench.out` (raw measurements).
