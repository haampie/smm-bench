using LoopVectorization
using Libdl
using ProgressMeter

const lib = Libdl.dlopen("./libxsmm_bench_f64.so") # Open the library explicitly.
const sym = Libdl.dlsym(lib, :bench_f64)

# g++ -shared -fPIC -march=native -I libxsmm/include main.cc -L libxsmm/lib '-Wl,-rpath=$ORIGIN/libxsmm/lib' -lxsmm -lblas -o libxsmm_bench_f64.so

bench_libxsmm!(C, A, B, repetitions=10) = ccall(sym, Cint, 
    (Ptr{Float64}, Ptr{Float64}, Ptr{Float64}, Cint, Cint, Cint, Cint, Cint),
    C, A, B, size(C, 1), size(C, 2), size(A, 2), size(A, 3), repetitions)

function bench_julia!(f!, C, A, B, repetitions=10)
    min_time = Inf
    for i = 1:repetitions
        C .= 0
        time = 1e9 * @elapsed f!(C, A, B)
        min_time = min(time, min_time)
    end
    return round(Int, min_time)
end

function vanilla_julia!(C, A, B)
    for b ∈ axes(A, 3)
        for m ∈ axes(A, 1), n ∈ axes(B, 2)
            Cmn = zero(eltype(C))
            @simd for k ∈ axes(A, 2)
                @inbounds Cmn += A[m, k, b] * B[k, n, b]
            end
            C[m,n] += Cmn
        end
    end
    C
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
    results = [(0, 0) for m in ms, n in ns, k in ks]

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