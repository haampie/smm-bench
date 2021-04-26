Compiled and run libxsmm like this:

```console
mkdir libxmm_env
// put hello.cc here 
cd libxmm_env
git clone https://github.com/hfp/libxsmm
(
  cd libxsmm
  make -j AVX=2 STATIC=0
)
g++ --std=c++11 -march=native -I libxsmm/include main.cc -L libxsmm/lib '-Wl,-rpath=$ORIGIN/libxsmm/lib' -lxsmm -lblas -o hello
./hello
```