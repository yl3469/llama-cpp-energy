#include <chrono>
#include <iostream>
#include <unordered_map>

// A map to store function start times
std::unordered_map<void*, std::chrono::high_resolution_clock::time_point> start_times;

extern "C" void __cyg_profile_func_enter(void* func, void* caller) {
    start_times[func] = std::chrono::high_resolution_clock::now();
}

extern "C" void __cyg_profile_func_exit(void* func, void* caller) {
    auto end = std::chrono::high_resolution_clock::now();
    auto start = start_times[func];
    std::chrono::duration<double> diff = end - start;
    std::cout << "Execution time: " << diff.count() << " s\n";
}
