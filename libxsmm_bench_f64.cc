#include <libxsmm.h>
#include <chrono>
#include <limits>

extern "C" {

/* compute C = sum(A_i * B_i) where C_i is m x n, A_i is m x k and B_i is
   k x n, for i = 1:bs, repetitions times, and return the min runtime in ms.*/
double bench_f64(double * c, double * a, double * b, int ms, int ns, int ks, int bs, int repetitions) {
  typedef double T;

  /* generates and dispatches a matrix multiplication kernel (C++ functor) */
  libxsmm_mmfunction<T> kernel(LIBXSMM_GEMM_FLAG_NONE, ms, ns, ks, 1.0 /*alpha*/, 1.0 /*beta*/);
  assert(kernel);

  double min = std::numeric_limits<double>::max();

  for (int i = 0; i < repetitions; ++i)
  {
    /* reset C to zero */
    for (int i = 0; i < ms * ns; ++i)
      c[i] = 0;

    /* do one batched matmul */
    auto t1 = std::chrono::high_resolution_clock::now(); 
    for (int i = 0; i < bs; ++i) kernel(&a[i * ms * ks], &b[i * ks * ns], &c[0]);
    auto t2 = std::chrono::high_resolution_clock::now();

    /* store min runtime */
    auto result = std::chrono::duration<double, std::milli>(t2 - t1).count();
    if (result < min) min = result;
  }

  return min;
}

}
