STATIC ?= 0
INTRINSICS ?= 1

all: libxsmm libxsmm_bench_f64.cc
	$(CXX) -shared -fPIC -march=native -I libxsmm/include libxsmm_bench_f64.cc -L libxsmm/lib '-Wl,-rpath=$ORIGIN/libxsmm/lib' -lxsmm -lblas -o libxsmm_bench_f64.so

.PHONY: libxsmm

libxsmm: # edit this for your own arch
	$(MAKE) -C libxsmm

clean:
	rm -f libxsmm_bench_f64.so
	$(MAKE) -C libxsmm clean