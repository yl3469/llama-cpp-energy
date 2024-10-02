#include <chrono>
#include <stdio.h>
#include <unordered_map>

thread_local std::unordered_map<void*, std::chrono::high_resolution_clock::time_point> start_times;

extern "C" void __cyg_profile_func_enter(void* func, void* caller) __attribute__((no_instrument_function));
extern "C" void __cyg_profile_func_exit(void* func, void* caller) __attribute__((no_instrument_function));

extern "C" void __cyg_profile_func_enter(void* func, void* caller) {
    start_times[func] = std::chrono::high_resolution_clock::now();
}

extern "C" void __cyg_profile_func_exit(void* func, void* caller) {
    auto end = std::chrono::high_resolution_clock::now();
    auto start = start_times[func];
    std::chrono::duration<double> diff = end - start;
    printf("Execution time: %f s\n", diff.count());
}
