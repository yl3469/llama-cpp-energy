set(TARGET llama-batched-bench)

find_package(PkgConfig REQUIRED)
pkg_check_modules(EnergyMonRapl REQUIRED IMPORTED_TARGET energymon-rapl)

add_executable(${TARGET} batched-bench.cpp)
install(TARGETS ${TARGET} RUNTIME)
target_link_libraries(${TARGET} PRIVATE common llama PkgConfig::EnergyMonRapl Timing ${CMAKE_THREAD_LIBS_INIT})
target_compile_features(${TARGET} PRIVATE cxx_std_11)
