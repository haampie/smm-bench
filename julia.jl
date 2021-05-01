using LoopVectorization
using LoopVectorization: StaticInt
using VectorizationBase: cache_size
using Libdl
using Plots
using Statistics: median
using Base: OneTo
using Statistics: quantile
using Printf: @sprintf
using HDF5
using Plots.PlotMeasures
using Random: shuffle

const lib = Libdl.dlopen("./libxsmm_bench_f64.so")
const sym = Libdl.dlsym(lib, :bench_f64)
const l3 = cache_size(Val(3))

bench_libxsmm!(C, A, B, repetitions) = ccall(sym, Cdouble, 
    (Ptr{Float64}, Ptr{Float64}, Ptr{Float64}, Cint, Cint, Cint, Cint, Cint),
    C, A, B, size(C, 1), size(C, 2), size(A, 2), size(A, 3), repetitions)

function bench_julia!(f!, C, A, B, repetitions, m::Val{ms}, n::Val{ns}, k::Val{ks}) where {ms,ns,ks}
    min_time = Inf
    for i = 1:repetitions
        fill!(C, 0)
        time = 1e3 * @elapsed f!(C, A, B, m, n, k)
        min_time = min(time, min_time)
    end
    return min_time
end

function lv!(C, A, B, ::Val{ms}, ::Val{ns}, ::Val{ks}) where {ms,ns,ks}
    for b ∈ OneTo(size(A, 3))
        @avx inline=true for m ∈ OneTo(StaticInt(ms)), n ∈ OneTo(StaticInt(ns))
            Cmn = zero(eltype(C))
            for k ∈ OneTo(StaticInt(ks))
                Cmn += A[m, k, b] * B[k, n, b]
            end
            C[m,n] += Cmn
        end
    end
    C
end

const not_measured = (-1.0, -1.0)

"""
Benchmark a bunch of triplets, restoring from a checkpoint if possible. Will
quit after `max_kernels`, so you have to restart this procedure a couple times.
The reason is explosion of function definitions where julia will give up at
some point :D.

The benchmark choses the batch size s.t. it fits in L3 cache. The best time of
`repetitions` runs is chosen. Most time is spent on compilation, so the number
of repetitions can be fixed at 25.
"""
function benchmark(;
    triplets::CartesianIndices = CartesianIndex(1,1,1):CartesianIndex(32,32,32),
    repetitions = 25,
    dir=joinpath(@__DIR__, "assets", Sys.CPU_NAME),
    max_kernels = 5000,
    save_after = 500,
    L3_cache::StaticInt{L3} = l3) where {L3}

    # Load results from checkpoint if possible
    h5_file = joinpath(dir, "data.h5")

    results = try
        h5open(joinpath(dir, "data.h5"), "r") do h5
            @assert all(triplets.indices[1] .== read(h5, "ms"))
            @assert all(triplets.indices[2] .== read(h5, "ns"))
            @assert all(triplets.indices[3] .== read(h5, "ks"))
            return reinterpret(reshape, Tuple{Float64,Float64}, read(h5, "results"))
        end
    catch err
        [not_measured for x in triplets]
    end

    i = 1

    for (I, triplet) in zip(CartesianIndices(triplets), triplets)
        # Skip benchmarks we've already run
        results[I] != not_measured && continue

        # Save results every so many triplets
        i % save_after == 0 && save_to_hdf5(results, triplets, dir)

        # Stop after max_kernel iterations
        i > max_kernels && break

        (m, n, k) = Tuple(triplet)
        @show (m, n, k)

        batchsize = L3 ÷ (sizeof(Float64) * (m * k + k * n + m * n))

        # Allocate the matrices
        A = rand(m, k, batchsize)
        B = rand(k, n, batchsize)
        C_libxsmm = zeros(m, n)
        C_lv      = zeros(m, n)

        # Validate results
        err = maximum(abs, C_lv - C_libxsmm)

        # Run the benchmark
        if err <= 200 * k * batchsize * eps(Float64)
            results[I] = (
                bench_libxsmm!(C_libxsmm, A, B, repetitions),
                bench_julia!(lv!, C_lv, A, B, repetitions, Val(m), Val(n), Val(k))
            )
        else
            println("Large error at for: (", m, ",", n, ",", k, ") = ", err)
        end

        i += 1
    end

    save_to_hdf5(results, triplets, dir)

    return results
end

function save_to_hdf5(results, triplets::CartesianIndices, dir=joinpath(@__DIR__, "assets", Sys.CPU_NAME))
    mkpath(dir)
    h5open(joinpath(dir, "data.h5"), "w") do h5
        write(h5, "results", reinterpret(reshape, Float64, results))
        write(h5, "ms", collect(triplets.indices[1]))
        write(h5, "ns", collect(triplets.indices[2]))
        write(h5, "ks", collect(triplets.indices[3]))
    end
end

function load_from_hdf5(path)
    return h5open(path, "r") do h5
        results = reinterpret(reshape, Tuple{Float64,Float64}, read(h5, "results"))
        ms = read(h5, "ms")
        ns = read(h5, "ns")
        ks = read(h5, "ks")

        results, ms, ns, ks
    end
end

function do_plot(results, ms, ns, ks, path=pwd())
    relative = [(x[2] - x[1]) / x[1] for x in results]

    for (mi, m) = enumerate(ms)
        data = relative[mi, :, :]
        max = maximum(abs, data)

        p = heatmap(ks, ns, data,
            title="m = $m. (lv - xsmm) / xsmm",
            aspectratio=:equal,
            width=800px,
            margin=0px,
            xlabel="k",
            ylabel="n",
            xlims=(first(ks)-.5, last(ks)+.5),
            ylims=(first(ns)-.5, last(ns)+.5),
            xticks=ks[2:2:end],
            yticks=ns[2:2:end],
            clims=(-max, max),
            c=cgrad(:balance, rev = true)
        )

        savefig(p, joinpath(path, "plot_$m.png"))
    end
end

function update_plots(root=joinpath(@__DIR__, "generate_page"))
    for dir in readdir(joinpath(root, "assets"), join=true)
        data = joinpath(dir, "data.h5")
        isfile(data) || continue
        arch = basename(dir)

        # Create new plots from the data
        results, ms, ns, ks = load_from_hdf5(data)
        do_plot(results, ms, ns, ks, dir)

        # Update the page
        open(joinpath(root, arch * ".md"), "w") do io
            println(io, "# ", arch)
            println(io)
            println(io, "The plots show the relative difference in runtime `(LoopVectorization.jl - libxsmm) / libxsmm` for every `(m, n, k)` triplet. Negative / red values are better for LoopVectorization.jl, positive / blue values are better for libxsmm.")
            println(io)
            
            for (mi, m) in enumerate(ms)
                relative = [(x[2] - x[1]) / x[1] for x in results[mi, :, :]][:]
                qs = map(q -> quantile(relative, q), (.25, .50, .75))
                println(io, "![", m , "](../assets/$arch/plot_$m.png)")
                println(io)
                println(io, "Q₁ = " * @sprintf("%2.3f", qs[1]),
                    ".  Q₂ = " * @sprintf("%2.3f", qs[2]),
                    ".  Q₃ = " * @sprintf("%2.3f", qs[3]))
                println(io)
            end
        end
    end
end
