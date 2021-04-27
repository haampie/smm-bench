Instructions:

```console
git clone --recursive https://github.com/haampie/smm-bench.git
cd smm-bench

# Use AVX={1,2,3} for AVX, AVX2, AVX-512 resp
# benchmarks in the readme are done on zen2 using AVX=2
make AVX=2 -j
```

color scale is (lv - xsmm) / xsmm

## zen2 (gcc 9.3)

`make AVX=2 INTRINSICS=1 STATIC=0 -j`

![assets/zen2/plot_1.png](assets/zen2/plot_1.png)
![assets/zen2/plot_2.png](assets/zen2/plot_2.png)
![assets/zen2/plot_4.png](assets/zen2/plot_4.png)
![assets/zen2/plot_8.png](assets/zen2/plot_8.png)
![assets/zen2/plot_16.png](assets/zen2/plot_16.png)
## broadwell (gcc 10.1, piz daint)

`make AVX=2 INTRINSICS=1 STATIC=0 CXX=CC CC=cc FC=ftn -j`

![assets/zen2/plot_1.png](assets/zen2/plot_1.png)
![assets/zen2/plot_2.png](assets/zen2/plot_2.png)
![assets/zen2/plot_4.png](assets/zen2/plot_4.png)
![assets/zen2/plot_8.png](assets/zen2/plot_8.png)
![assets/zen2/plot_16.png](assets/zen2/plot_16.png)
