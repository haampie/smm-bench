#!/bin/bash
#
#SBATCH --job-name=julia-smm-lv-bench
#SBATCH --ntasks=1
#SBATCH --hint=nomultithread
#SBATCH --time=1:00:00

echo "Number of cores = $SLURM_CPUS_ON_NODE"

module unload xalt
module swap PrgEnv-cray PrgEnv-gnu

cd /dev/shm
wget -q https://julialang-s3.julialang.org/bin/linux/x64/1.6/julia-1.6.1-linux-x86_64.tar.gz
tar -xf julia-1.6.1-linux-x86_64.tar.gz
rm *.tar.gz
export PATH="$PWD/julia-1.6.1/bin/:$PATH"
git clone --recursive https://github.com/haampie/smm-bench.git
cd smm-bench

srun -n1 -c $SLURM_CPUS_ON_NODE make AVX=2 INTRINSICS=1 STATIC=0 CC=cc CXX=CC FC=ftn -j

export JULIA_DEPOT_PATH="/dev/shm/depot"

# install packages
echo "installing julia packages"
srun -n1 -c $SLURM_CPUS_ON_NODE julia -O0 --project -e 'using Pkg; pkg"instantiate";'

# run the benchmark
echo "running the benchmark"
srun -n1 -c1 --unbuffered julia -O3 --project -e 'include("julia.jl"); ms=(2,4,8,16); ns=1:32; ks=1:32; results=example(ms,ns,ks,10_000,10); save_to_hdf5(results,ms,ns,ks,joinpath(ENV["SCRATCH"],Sys.CPU_NAME))'


