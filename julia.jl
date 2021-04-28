using LoopVectorization
using LoopVectorization: StaticInt
using Libdl
using Plots
using Statistics: median
using Base: OneTo
using Statistics: quantile
using Printf: @sprintf
using HDF5
using Plots.PlotMeasures

const lib = Libdl.dlopen("./libxsmm_bench_f64.so")
const sym = Libdl.dlsym(lib, :bench_f64)

bench_libxsmm!(C, A, B, repetitions=10) = ccall(sym, Cdouble, 
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

function example(ms=1:2:17, ns=1:2:17, ks=1:2:17, b=100_000, repetitions=20)
    results = [(0.0, 0.0) for m in ms, n in ns, k in ks]

    for (mi, m) in enumerate(ms), (ni, n) in enumerate(ns), (ki, k) in enumerate(ks)
        @show (m, n, k)

        A = rand(m, k, b)
        B = rand(k, n, b)

        C_libxsmm    = zeros(m, n)
        C_lv         = zeros(m, n)

        time_libxsmm = bench_libxsmm!(C_libxsmm, A, B, repetitions)
        time_lv      = bench_julia!(lv!, C_lv, A, B, repetitions, Val(m), Val(n), Val(k))

        results[mi, ni, ki] = (time_libxsmm, time_lv)

        err = maximum(abs, C_lv - C_libxsmm)

        if err > 200 * k * b * eps(Float64)
            println("Large error at for: (", m, ",", n, ",", k, ") = ", err)
        end
    end

    return results
end

function save_to_hdf5(results, ms, ns, ks, dir=joinpath(@__DIR__, "assets", Sys.CPU_NAME))
    mkpath(dir)
    h5open(joinpath(dir, "data.h5"), "w") do h5
        write(h5, "results", reinterpret(reshape, Float64, results))
        write(h5, "ms", collect(ms))
        write(h5, "ns", collect(ns))
        write(h5, "ks", collect(ks))
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

function update_plots()
    buffer = IOBuffer()

    for dir in readdir(joinpath(@__DIR__, "assets"), join=true)
        data = joinpath(dir, "data.h5")
        isfile(data) || continue

        # Create new plots from the data
        results, ms, ns, ks = load_from_hdf5(data)
        do_plot(results, ms, ns, ks, dir)

        # Update the readme
        println(buffer, "## ", basename(dir))
        println(buffer)
        
        for (mi, m) in enumerate(ms)
            relative = [(x[2] - x[1]) / x[1] for x in results[mi, :, :]][:]
            qs = map(q -> quantile(relative, q), (.25, .50, .75))
            
            image_path = relpath(joinpath(dir, "plot_$m.png"), @__DIR__)
            println(buffer, "![", image_path, "](", image_path, ")")
            println(buffer)
            println(buffer, "Q₁ = " * @sprintf("%2.3f", qs[1]),
                ".  Q₂ = " * @sprintf("%2.3f", qs[2]),
                ".  Q₃ = " * @sprintf("%2.3f", qs[3]))
            println(buffer)
        end

        println(buffer)
    end

    return String(take!(buffer))
end
