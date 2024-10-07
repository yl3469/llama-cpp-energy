# For CPU only build (with energymon)
set -ex
cmake -B build_en -DCMAKE_INSTALL_PREFIX=/home/yl3469/.local -DCMAKE_BUILD_TYPE=Debug
cmake --build build_en --config Release -j32 --target llama-batched-bench

#For GPU build - first modify makefile
```
LDFLAGS += -L/home/yl3469/.local/lib -lenergymon-rapl
CXXFLAGS += -I/home/yl3469/.local/include/energymon
```
make GGML_CUDA_MMV_Y=128 GGML_CUDA=1 GGML_CUDA_FORCE_CUBLAS=1 LLAMA_OPENBLAS=1

# Make sure that energymon is set up correctly
export :pkg-config --modversion energymon-rapl

