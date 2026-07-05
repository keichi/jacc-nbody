#!/bin/bash
#
# Build the ymiki-repo/nbody force kernel (cpp/cuda/11_memcpy_rsqrt/nbody_leapfrog2.cu)
# for AMD GPUs (MI300A, gfx942) by hipifying the CUDA source and compiling with hipcc.
#
# The upstream project is CUDA-only and its CMake build has no HIP target, so we
# hipify the single translation unit and compile it directly. BENCHMARK_MODE is
# the project's own built-in benchmark harness (self-adjusting iteration count),
# so we do NOT reimplement any measurement logic -- we just enable that flag.
#
# Produces three executables that differ only in precision:
#   nbody_bench_fp32   FP_L=32 FP_M=32   full single precision
#   nbody_bench_mixed  FP_L=32 FP_M=64   the actual default of 11_memcpy_rsqrt
#                                        (FP64 storage/accumulation, FP32 rsqrt)
#   nbody_bench_fp64   FP_L=64 FP_M=64   full double precision
#
set -euo pipefail

REPO_URL="https://github.com/ymiki-repo/nbody.git"
PINNED_COMMIT="1834c7df30b9a6098caa8f8363e4a7108c9ba70a"
GPU_ARCH="${GPU_ARCH:-gfx942}"        # MI300A
NTHREADS="${NTHREADS:-1024U}"         # threads per block (matches JACC.jl tuned value)

# HDF5 header is only needed so that util/hdf5.hpp parses; in BENCHMARK_MODE none
# of its functions are called, so libhdf5 is never linked. Point this at any
# hdf5.h on the system.
HDF5_INC="${HDF5_INC:-/work/RTRHD/kohji/hdf5-1.14/include}"

HERE="$(cd "$(dirname "$0")" && pwd)"
WORK="${HERE}/build"
SRC="${WORK}/nbody"

module load rocm/7.2.0 2>/dev/null || true

rm -rf "${WORK}" && mkdir -p "${WORK}"
git clone "${REPO_URL}" "${SRC}"
git -C "${SRC}" checkout --quiet "${PINNED_COMMIT}"

KDIR="${SRC}/cpp/cuda/11_memcpy_rsqrt"
hipify-perl "${KDIR}/nbody_leapfrog2.cu" > "${KDIR}/nbody_leapfrog2.hip"

build() { # $1=output name  $2=extra -D flags
  hipcc -x hip "${KDIR}/nbody_leapfrog2.hip" -o "${WORK}/$1" \
    -std=c++17 -O3 --offload-arch="${GPU_ARCH}" \
    -DBENCHMARK_MODE $2 -DNTHREADS="${NTHREADS}" -DNDEBUG -DSIMD_BITS=512 \
    -I "${SRC}/cpp" -I "${HDF5_INC}" \
    -lboost_program_options -lboost_filesystem -lboost_system -lboost_timer \
    2>/dev/null
  echo "built ${WORK}/$1"
}

# NOTE: no CALCULATE_POTENTIAL/USE_POTENTIAL -> the kernel skips the potential
# term and write_log uses FLOPS_PER_INTERACTION=22, matching the JACC.jl benchmark.
build nbody_bench_fp32  "-DFP_L=32 -DFP_M=32"
build nbody_bench_mixed "-DFP_L=32 -DFP_M=64"
build nbody_bench_fp64  "-DFP_L=64 -DFP_M=64"

echo "done. binaries in ${WORK}/"
