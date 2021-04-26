using LoopVectorization
using Libdl
using Plots

const lib = Libdl.dlopen("./libxsmm_bench_f64.so") # Open the library explicitly.
const sym = Libdl.dlsym(lib, :bench_f64)

bench_libxsmm!(C, A, B, repetitions=10) = ccall(sym, Cdouble, 
    (Ptr{Float64}, Ptr{Float64}, Ptr{Float64}, Cint, Cint, Cint, Cint, Cint),
    C, A, B, size(C, 1), size(C, 2), size(A, 2), size(A, 3), repetitions)


function bench_julia!(f!, C, A, B, repetitions=10)
    min_time = Inf
    for i = 1:repetitions
        fill!(C, 0)
        time = 1e3 * @elapsed f!(C, A, B)
        min_time = min(time, min_time)
    end
    return min_time
end

function lv!(C, A, B)
    @avx for b ∈ axes(A, 3)
        for m ∈ axes(A, 1), n ∈ axes(B, 2)
            Cmn = zero(eltype(C))
            for k ∈ axes(A, 2)
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
        time_lv      = bench_julia!(lv!, C_lv, A, B, repetitions)

        results[mi, ni, ki] = (time_libxsmm, time_lv)

        err = maximum(abs, C_lv - C_libxsmm)
        if err > 10 b * eps(Float64)
            println("Large error at for: (", m, ",", n, ",", k, ") = ", err)
        end
    end

    return results
end

function do_plot(results, ms, ns, ks)
    relative = [(x[1] - x[2]) / (abs(x[1]) + abs(x[2])) for x in results]

    for (mi, m) = enumerate(ms)

        p = heatmap(ns, ks, faster[mi, :, :],
            title="m = $m. positive = lv faster. normalized (lv-xsmm)/(|lv|+|xsmm|)",
            aspectratio=:equal,
            xlabel="n",
            ylabel="k",
            xlims=(first(ns)-.5, last(ns)+.5),
            ylims=(first(ks)-.5, last(ks)+.5),
            xticks=ns, yticks=ks, clims=extrema(faster))
        contour!(p, ns, ks, faster[mi, :, :], levels=[1.0], line=(4, :white))
        savefig(p, "plot_$m.png")
    end
end