# Unroll-factor tuning sweep for the N-body force kernel.
#
# `llvm.loop.unroll.count` loopinfo needs a literal unroll count, so this
# script metaprograms one `calc_acc_<U>` kernel + launcher per candidate U,
# then benchmarks each at a fixed N (default 32768) and reports the fastest.
# Mirrors the kernel of nbody_jacc.jl exactly apart from the parametric
# unroll factor.
#
# Usage:
#   julia --project tune_unroll.jl [N]
#   JACC_NBODY_FP=64 julia --project tune_unroll.jl

import JACC
JACC.@init_backend

using Printf

const FP = get(ENV, "JACC_NBODY_FP", "32") == "64" ? Float64 : Float32
const FLOPS_PER_INTERACTION = 22.0
const UNROLL_CANDIDATES = (1, 2, 4, 8, 16, 32)
const TG_CANDIDATES = (64, 128, 256, 512, 1024)

# Reciprocal-sqrt via the NVVM approx.ftz intrinsic (CUDA-only). Matches the
# kernel in nbody_jacc.jl; swap with `inv(sqrt)` / `Metal.rsqrt_fast` for
# other backends.
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

# --- Initial conditions: uniform sphere (cf. nbody_jacc.jl) ------------------
function uniform_sphere(::Type{T}, N; Mtot = one(T), rad = one(T)) where {T}
    x = Vector{T}(undef, N); y = Vector{T}(undef, N)
    z = Vector{T}(undef, N); m = Vector{T}(undef, N)
    mass = Mtot / T(N)
    for i in 1:N
        rr = rad * cbrt(rand(T))
        prj = T(2) * rand(T) - one(T)
        RR = rr * sqrt(max(zero(T), one(T) - prj * prj))
        theta = T(2) * T(pi) * rand(T)
        x[i] = RR * cos(theta); y[i] = RR * sin(theta)
        z[i] = rr * prj; m[i] = mass
    end
    return x, y, z, m
end

function ref_acc(x, y, z, m, eps2, N)
    T = eltype(x)
    ax = zeros(T, N); ay = zeros(T, N); az = zeros(T, N)
    for i in 1:N
        axi = zero(T); ayi = zero(T); azi = zero(T)
        for j in 1:N
            dx = x[j] - x[i]; dy = y[j] - y[i]; dz = z[j] - z[i]
            r2 = eps2 + dx * dx + dy * dy + dz * dz
            r_inv = inv(sqrt(r2))
            alp = m[j] * r_inv * r_inv * r_inv
            axi += alp * dx; ayi += alp * dy; azi += alp * dz
        end
        ax[i] = axi; ay[i] = ayi; az[i] = azi
    end
    return ax, ay, az
end

# --- Generate one kernel + launcher per candidate unroll factor --------------
const KERNELS   = Dict{Int,Function}()
const LAUNCHERS = Dict{Int,Function}()

for U in UNROLL_CANDIDATES
    kname = Symbol(:calc_acc_, U)
    lname = Symbol(:launch_, U)
    @eval begin
        function $kname(i, x, y, z, m, ax, ay, az, eps2, N)
            T = eltype(ax)
            @inbounds xi = x[i]
            @inbounds yi = y[i]
            @inbounds zi = z[i]
            axi = zero(T)
            ayi = zero(T)
            azi = zero(T)
            @inbounds @fastmath for j in 1:N
                $(Expr(:loopinfo, (Symbol("llvm.loop.unroll.count"), U)))
                dx = x[j] - xi
                dy = y[j] - yi
                dz = z[j] - zi
                r2 = eps2 + dx * dx + dy * dy + dz * dz
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

        function $lname(x, y, z, m, ax, ay, az, eps2, N, tg)
            if tg === nothing
                JACC.@parallel_for(range=N,
                    $kname(x, y, z, m, ax, ay, az, eps2, N))
            else
                JACC.@parallel_for(range=N, threads=tg, blocks=cld(N, tg),
                    $kname(x, y, z, m, ax, ay, az, eps2, N))
            end
        end

        KERNELS[$U]   = $kname
        LAUNCHERS[$U] = $lname
    end
end

# --- Correctness check for one kernel ----------------------------------------
function check(U; N = 256)
    T = FP
    eps2 = (T(1) / T(64))^2
    hx, hy, hz, hm = uniform_sphere(T, N)
    rax, ray, raz = ref_acc(hx, hy, hz, hm, eps2, N)
    x = JACC.array(hx); y = JACC.array(hy); z = JACC.array(hz); m = JACC.array(hm)
    ax = JACC.zeros(T, N); ay = JACC.zeros(T, N); az = JACC.zeros(T, N)
    LAUNCHERS[U](x, y, z, m, ax, ay, az, eps2, N, nothing)
    JACC.synchronize()
    gax = Array(ax); gay = Array(ay); gaz = Array(az)
    num = 0.0; den = 0.0
    for i in 1:N
        num += (gax[i]-rax[i])^2 + (gay[i]-ray[i])^2 + (gaz[i]-raz[i])^2
        den += rax[i]^2 + ray[i]^2 + raz[i]^2
    end
    relerr = sqrt(num / den)
    tol = T === Float32 ? 1e-3 : 1e-10
    relerr <= tol || error("UNROLL=$U correctness FAILED: relerr=$relerr > $tol")
    return relerr
end

# --- Benchmark one launcher at fixed N ---------------------------------------
function bench(launch, N, tg; min_elapsed = 0.5)
    T = FP
    eps2 = (T(1) / T(64))^2
    hx, hy, hz, hm = uniform_sphere(T, N)
    x = JACC.array(hx); y = JACC.array(hy); z = JACC.array(hz); m = JACC.array(hm)
    ax = JACC.zeros(T, N); ay = JACC.zeros(T, N); az = JACC.zeros(T, N)
    launch(x, y, z, m, ax, ay, az, eps2, N, tg)   # warm-up / JIT
    JACC.synchronize()
    iter = 1
    elapsed = 0.0
    while true
        JACC.synchronize()
        t0 = time_ns()
        for _ in 1:iter
            launch(x, y, z, m, ax, ay, az, eps2, N, tg)
        end
        JACC.synchronize()
        elapsed = (time_ns() - t0) / 1e9
        elapsed >= min_elapsed && break
        iter = nextpow(2, ceil(Int, iter * 1.25 * min_elapsed / max(elapsed, 1e-9)))
    end
    gflops = Float64(N) * Float64(N) * iter / elapsed * FLOPS_PER_INTERACTION / 1e9
    return gflops
end

# Pick the fastest threadgroup size for a launcher at this N.
function autotune_tg(launch, N; iters = 16)
    JACC.array_type() === Base.Array && return nothing
    T = FP
    eps2 = (T(1) / T(64))^2
    hx, hy, hz, hm = uniform_sphere(T, N)
    x = JACC.array(hx); y = JACC.array(hy); z = JACC.array(hz); m = JACC.array(hm)
    ax = JACC.zeros(T, N); ay = JACC.zeros(T, N); az = JACC.zeros(T, N)
    best_tg = TG_CANDIDATES[1]; best_t = Inf
    for tg in TG_CANDIDATES
        tg > N && continue
        launch(x, y, z, m, ax, ay, az, eps2, N, tg)
        JACC.synchronize()
        t0 = time_ns()
        for _ in 1:iters
            launch(x, y, z, m, ax, ay, az, eps2, N, tg)
        end
        JACC.synchronize()
        t = (time_ns() - t0) / 1e9
        if t < best_t
            best_t = t; best_tg = tg
        end
    end
    return best_tg
end

function main()
    N = length(ARGS) >= 1 ? parse(Int, ARGS[1]) : 1 << 15
    println("JACC.jl N-body - unroll-factor tuning")
    println("  backend array type : ", JACC.array_type())
    println("  precision          : ", FP)
    @printf("  N                  : %d\n\n", N)

    @printf("%8s %8s %12s %12s\n", "UNROLL", "best tg", "GFLOP/s", "relerr")
    best_u = 0; best_g = 0.0
    for U in UNROLL_CANDIDATES
        relerr = check(U)
        launch = LAUNCHERS[U]
        tg = autotune_tg(launch, N)
        g = bench(launch, N, tg)
        tgs = tg === nothing ? "auto" : string(tg)
        marker = g > best_g ? "  <--" : ""
        @printf("%8d %8s %12.3f %12.2e%s\n", U, tgs, g, relerr, marker)
        if g > best_g
            best_g = g; best_u = U
        end
    end
    println()
    @printf("optimal UNROLL = %d  (%.3f GFLOP/s at N=%d)\n", best_u, best_g, N)
end

main()
