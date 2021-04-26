#include <libxsmm.h>
#include <vector>
#include <chrono>
#include <iostream>
#include <limits>

extern "C" {

int bench_f64(double * c, double * a, double * b, int ms, int ns, int ks, int bs, int repetitions) {
  std::cerr.precision(std::numeric_limits<double>::max_digits10);

  /* compute C = sum(A_i * B_i) where C_i is m x n, A_i is m x k and B_i is k x n. */
  typedef double T;

  /* C/C++ and Fortran interfaces are available */
  typedef libxsmm_mmfunction<T> kernel_type;

  /* generates and dispatches a matrix multiplication kernel (C++ functor) */
  kernel_type kernel(LIBXSMM_GEMM_FLAG_NONE, ms, ns, ks, 1.0 /*alpha*/, 1.0 /*beta*/);
  assert(kernel);

  /* initialize */
  for (int i = 0; i < ms * ks * bs; ++i)
    a[i] = static_cast<T>(1) / (1 + i % 13);

  for (int i = 0; i < ks * ns * bs; ++i)
    b[i] = static_cast<T>(1) / (1 + i % 13);

  /* get the min runtime of 10 runs */
  int max = std::numeric_limits<int>::max();

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
    auto result = std::chrono::duration_cast<std::chrono::nanoseconds>(t2 - t1).count();
    if (result < max) max = result;
  }

  return max;
}

}
