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

function benchmark(;
    triplets::CartesianIndices = CartesianIndex(1, 1, 1):CartesianIndex(32, 32, 32),
    dir=joinpath(@__DIR__, "assets", Sys.CPU_NAME),
    repetitions = 25,
    L3_cache::StaticInt{L3} = l3) where {L3}

    # Load results from checkpoint if possible
    h5_file = joinpath(dir, "data.h5")

    results, starting_triplet = try
        h5open(joinpath(dir, "data.h5"), "r") do h5
            data = reinterpret(reshape, Tuple{Float64,Float64}, read(h5, "results"))
            last = CartesianIndex(read(h5, "m"), read(h5, "n"), read(h5, "k"))
            @assert all(triplets.indices[1] .== read(h5, "ms"))
            @assert all(triplets.indices[2] .== read(h5, "ns"))
            @assert all(triplets.indices[3] .== read(h5, "ks"))
            @info "Resuming from" last
            return data, last
        end
    catch err
        data = [(0.0, 0.0) for x in triplets]
        last = first(triplets)
        data, last
    end

    @show starting_triplet

    i = 1

    for I in CartesianIndices(triplets)
        triplet = triplets[I]

        # Save results every so many triplets
        i % 10 == 0 && save_to_hdf5(results, triplet, triplets, dir)

        # Skip stuff we've already done
        starting_triplet > triplet && continue

        (m, n, k) = triplet.I

        @show (m, n, k)

        batchsize = L3 ÷ (sizeof(Float64) * (m * k + k * n + m * n))

        A = rand(m, k, batchsize)
        B = rand(k, n, batchsize)

        C_libxsmm    = zeros(m, n)
        C_lv         = zeros(m, n)

        time_libxsmm = bench_libxsmm!(C_libxsmm, A, B, repetitions)
        time_lv = bench_julia!(lv!, C_lv, A, B, repetitions, Val(m), Val(n), Val(k))

        results[I] = (time_libxsmm, time_lv)

        err = maximum(abs, C_lv - C_libxsmm)

        if err > 200 * k * batchsize * eps(Float64)
            println("Large error at for: (", m, ",", n, ",", k, ") = ", err)
        end

        i += 1
    end

    save_to_hdf5(results, last(triplets), triplets, dir)

    return results
end

function save_to_hdf5(results, triplet::CartesianIndex, triplets::CartesianIndices, dir=joinpath(@__DIR__, "assets", Sys.CPU_NAME))
    mkpath(dir)
    h5open(joinpath(dir, "data.h5"), "w") do h5
        write(h5, "results", reinterpret(reshape, Float64, results))
        write(h5, "ms", collect(triplets.indices[1]))
        write(h5, "ns", collect(triplets.indices[2]))
        write(h5, "ks", collect(triplets.indices[3]))
        write(h5, "m", collect(triplet.I[1]))
        write(h5, "n", collect(triplet.I[2]))
        write(h5, "k", collect(triplet.I[3]))
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
        any(isnan, data) && continue
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
                any(isnan, relative) && continue
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
