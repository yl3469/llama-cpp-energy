cmake -B build_en -DCMAKE_INSTALL_PREFIX=/home/yl3469/.local -DCMAKE_BUILD_TYPE=Debug
cmake --build build_en --config Release -j32 --target llama-batched-bench
