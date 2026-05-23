# N-body benchmark using JACC.jl
#
# Direct all-pairs (O(N^2)) gravitational force kernel, modeled on the 2nd-order
# leapfrog `calc_acc` of ymiki-repo/nbody (https://github.com/ymiki-repo/nbody).
# This benchmark measures the force (acceleration) kernel only, sweeping N.
#
# Usage:
#   julia --project -t auto nbody_jacc.jl [N_min] [N_max] [N_bins]
#   JACC_NBODY_FP=64 julia --project -t auto nbody_jacc.jl   # double precision
#
# Backend (CPU threads by default) is selected once via:
#   julia --project -e 'import JACC; JACC.set_backend("cuda")'

import JACC
JACC.@init_backend

using Printf
# using CUDA
# using Metal

# Floating-point type: Float32 (default) or Float64 via JACC_NBODY_FP=64
const FP = get(ENV, "JACC_NBODY_FP", "32") == "64" ? Float64 : Float32

# 22 floating-point operations per pairwise interaction (leapfrog, no potential),
# counting reciprocal-sqrt as 4 ops -- same convention as the reference repo.
const FLOPS_PER_INTERACTION = 22.0

# Reciprocal-sqrt via the NVVM approx.ftz intrinsic (flush-to-zero, ~22-bit
# accuracy). CUDA-only -- on other backends, swap in one of the alternatives
# commented out in the kernel below (`inv(sqrt)`, `Metal.rsqrt_fast`, ...).
@inline function rsqrt_ftz(x::Float32)
    Base.llvmcall(
        ("""
         declare float @llvm.nvvm.rsqrt.approx.ftz.f(float)
         define float @entry(float %0) #0 {
           %r = call float @llvm.nvvm.rsqrt.approx.ftz.f(float %0)
           ret float %r
         }
         attributes #0 = { alwaysinline }
         """, "entry"),
        Float32, Tuple{Float32}, x)
end

# --- Force kernel: direct all-pairs gravitational acceleration --------------
# a_i = sum_j  m_j * (r_j - r_i) / (r_ji^2 + eps^2)^(3/2),  with G = 1.
# The j == i term is kept (Plummer softening keeps it finite), matching the
# reference's N_pairs = N^2 accounting.
# The j loop is unrolled 8x via an `llvm.loop.unroll.count` loopinfo hint, so
# consecutive interactions become independent and expose the instruction-level
# parallelism the GPU needs to overlap reciprocal-sqrt latency. @fastmath
# enables FMA contraction and reassociation; the reciprocal-sqrt itself comes
# from the explicit `rsqrt_ftz` call below (NVVM intrinsic, CUDA-only).

@eval function calc_acc!(i, x, y, z, m, ax, ay, az, eps2, N)
    T = eltype(ax)
    @inbounds xi = x[i]
    @inbounds yi = y[i]
    @inbounds zi = z[i]
    axi = zero(T)
    ayi = zero(T)
    azi = zero(T)
    @inbounds @fastmath for j in 1:N
        $(Expr(:loopinfo, (Symbol("llvm.loop.unroll.count"), 8)))
        dx = x[j] - xi
        dy = y[j] - yi
        dz = z[j] - zi
        r2 = eps2 + dx * dx + dy * dy + dz * dz
        # r_inv = inv(sqrt(r2))
        # r_inv = Metal.rsqrt_fast(r2)
        # r_inv = CUDA.rsqrt(r2)
        r_inv = rsqrt_ftz(r2)
        alp = m[j] * r_inv * r_inv * r_inv
        axi += alp * dx
        ayi += alp * dy
        azi += alp * dz
    end
    @inbounds ax[i] = axi
    @inbounds ay[i] = ayi
    @inbounds az[i] = azi
    return nothing
end

# Launch the force kernel. `tg === nothing` uses JACC's automatic launch
# configuration (unchanged behaviour, all backends). A concrete `tg` pins the
# threadgroup/block size via JACC's LaunchSpec path -- used by the GPU
# autotune below to pick the size that maximises occupancy.
launch!(x, y, z, m, ax, ay, az, eps2, N, tg) =
    tg === nothing ?
    JACC.@parallel_for(range=N, calc_acc!(x, y, z, m, ax, ay, az, eps2, N)) :
    JACC.@parallel_for(range=N, threads=tg, blocks=cld(N, tg),
        calc_acc!(x, y, z, m, ax, ay, az, eps2, N))

# --- Initial conditions: uniform sphere (cf. nbody/cpp/common/init.hpp) ------
function uniform_sphere(::Type{T}, N; Mtot = one(T), rad = one(T)) where {T}
    x = Vector{T}(undef, N)
    y = Vector{T}(undef, N)
    z = Vector{T}(undef, N)
    m = Vector{T}(undef, N)
    mass = Mtot / T(N)
    for i in 1:N
        rr = rad * cbrt(rand(T))
        prj = T(2) * rand(T) - one(T)
        RR = rr * sqrt(max(zero(T), one(T) - prj * prj))
        theta = T(2) * T(pi) * rand(T)
        x[i] = RR * cos(theta)
        y[i] = RR * sin(theta)
        z[i] = rr * prj
        m[i] = mass
    end
    return x, y, z, m
end

# --- Host-side naive reference (for correctness check) ----------------------
function ref_acc(x, y, z, m, eps2, N)
    T = eltype(x)
    ax = zeros(T, N)
    ay = zeros(T, N)
    az = zeros(T, N)
    for i in 1:N
        axi = zero(T); ayi = zero(T); azi = zero(T)
        for j in 1:N
            dx = x[j] - x[i]
            dy = y[j] - y[i]
            dz = z[j] - z[i]
            r2 = eps2 + dx * dx + dy * dy + dz * dz
            r_inv = inv(sqrt(r2))
            alp = m[j] * r_inv * r_inv * r_inv
            axi += alp * dx; ayi += alp * dy; azi += alp * dz
        end
        ax[i] = axi; ay[i] = ayi; az[i] = azi
    end
    return ax, ay, az
end

function check_correctness(::Type{T}; N = 256) where {T}
    eps2 = (T(1) / T(64))^2
    hx, hy, hz, hm = uniform_sphere(T, N)
    rax, ray, raz = ref_acc(hx, hy, hz, hm, eps2, N)

    x = JACC.array(hx); y = JACC.array(hy); z = JACC.array(hz); m = JACC.array(hm)
    ax = JACC.zeros(T, N); ay = JACC.zeros(T, N); az = JACC.zeros(T, N)
    launch!(x, y, z, m, ax, ay, az, eps2, N, nothing)
    JACC.synchronize()

    gax = Array(ax); gay = Array(ay); gaz = Array(az)
    num = 0.0; den = 0.0
    for i in 1:N
        num += (gax[i] - rax[i])^2 + (gay[i] - ray[i])^2 + (gaz[i] - raz[i])^2
        den += rax[i]^2 + ray[i]^2 + raz[i]^2
    end
    relerr = sqrt(num / den)
    tol = T === Float32 ? 1e-3 : 1e-10
    @printf("correctness check: N=%d, relative L2 error = %.3e (tol %.0e)\n",
        N, relerr, tol)
    relerr <= tol || error("correctness check FAILED: relerr=$relerr > tol=$tol")
    return nothing
end

# --- Benchmark one value of N ------------------------------------------------
function bench_N(::Type{T}, N, tg; min_elapsed = 0.5) where {T}
    eps2 = (T(1) / T(64))^2
    hx, hy, hz, hm = uniform_sphere(T, N)
    x = JACC.array(hx); y = JACC.array(hy); z = JACC.array(hz); m = JACC.array(hm)
    ax = JACC.zeros(T, N); ay = JACC.zeros(T, N); az = JACC.zeros(T, N)

    # Warm-up (triggers JIT compilation of the kernel).
    launch!(x, y, z, m, ax, ay, az, eps2, N, tg)
    JACC.synchronize()

    iter = 1
    elapsed = 0.0
    while true
        JACC.synchronize()
        t0 = time_ns()
        for _ in 1:iter
            launch!(x, y, z, m, ax, ay, az, eps2, N, tg)
        end
        JACC.synchronize()
        elapsed = (time_ns() - t0) / 1e9
        elapsed >= min_elapsed && break
        # Predict iteration count to reach min_elapsed (booster 1.25 as in ref).
        iter = nextpow(2, ceil(Int, iter * 1.25 * min_elapsed / max(elapsed, 1e-9)))
    end

    pairs = Float64(N) * Float64(N) * iter
    pairs_per_s = pairs / elapsed
    gflops = pairs_per_s * FLOPS_PER_INTERACTION / 1e9
    return iter, elapsed, pairs_per_s, gflops
end

# --- GPU launch-config autotune ---------------------------------------------
# JACC's default threadgroup size on Metal is the kernel maximum (1024), which
# can limit occupancy for register-heavy kernels. Try a few sizes once and keep
# the fastest. Returns `nothing` (= JACC's automatic config, unchanged
# behaviour) on CPU backends, so portability is preserved.
const TG_CANDIDATES = (64, 128, 256, 512, 1024)

function autotune_tg(::Type{T}; N = 1 << 17, iters = 16) where {T}
    JACC.array_type() === Base.Array && return nothing  # CPU: keep defaults
    eps2 = (T(1) / T(64))^2
    hx, hy, hz, hm = uniform_sphere(T, N)
    x = JACC.array(hx); y = JACC.array(hy); z = JACC.array(hz); m = JACC.array(hm)
    ax = JACC.zeros(T, N); ay = JACC.zeros(T, N); az = JACC.zeros(T, N)
    best_tg = TG_CANDIDATES[1]
    best_t = Inf
    for tg in TG_CANDIDATES
        tg > N && continue
        launch!(x, y, z, m, ax, ay, az, eps2, N, tg)  # warm-up
        JACC.synchronize()
        t0 = time_ns()
        for _ in 1:iters
            launch!(x, y, z, m, ax, ay, az, eps2, N, tg)
        end
        JACC.synchronize()
        t = (time_ns() - t0) / 1e9
        if t < best_t
            best_t = t
            best_tg = tg
        end
    end
    return best_tg
end

# --- Main --------------------------------------------------------------------
function main()
    T = FP
    N_min  = length(ARGS) >= 1 ? parse(Int, ARGS[1]) : 1024
    N_max  = length(ARGS) >= 2 ? parse(Int, ARGS[2]) : 1 << 20
    N_bins = length(ARGS) >= 3 ? parse(Int, ARGS[3]) : 11

    tg = autotune_tg(T)

    println("JACC.jl N-body benchmark - direct all-pairs leapfrog force kernel")
    println("  backend array type : ", JACC.array_type())
    println("  CPU threads        : ", Threads.nthreads())
    println("  precision          : ", T)
    println("  threadgroup size   : ", tg === nothing ? "auto (JACC default)" : tg)
    @printf("  N sweep            : %d .. %d (%d log-spaced points)\n",
        N_min, N_max, N_bins)
    println()

    check_correctness(T)
    println()

    # Log-spaced, deduplicated N values.
    ratio = N_bins > 1 ? (N_max / N_min)^(1 / (N_bins - 1)) : 1.0
    Ns = sort(unique(round(Int, N_min * ratio^k) for k in 0:(N_bins - 1)))

    @printf("%12s %8s %12s %18s %12s\n",
        "N", "iters", "time[s]", "interactions/s", "GFLOP/s")
    peak = 0.0
    for N in Ns
        iter, elapsed, pairs_per_s, gflops = bench_N(T, N, tg)
        peak = max(peak, gflops)
        @printf("%12d %8d %12.4f %18.4e %12.3f\n",
            N, iter, elapsed, pairs_per_s, gflops)
    end
    println()
    @printf("peak performance: %.3f GFLOP/s  (%.0f FLOP per interaction)\n",
        peak, FLOPS_PER_INTERACTION)
end

main()
