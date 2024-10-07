import torch
import time
import numpy as np
from torch import mps, cuda
from time import (
    process_time,
    perf_counter,
    sleep,
)

num_trails = 500
is_FP16 = True
low_res = False
def flops_benchmark(device):
    # test_range = 2 ** np.arange(13, 15, 0.25)
    test_range = 2 ** np.arange(8, 13, 0.25)
    print('size, elapsed_time, flops')
    for n in test_range:
        total = 0
        if total > 0.1 and total < 1:
            num_trails = 20
        elif total > 1:
            num_trails = 5
        else:
            num_trails = 100
        for _ in range(num_trails):
            n = int(n)
            if is_FP16:
                a = torch.rand(n, n, device=device).half()
            else:
                a = torch.rand(n, n, device=device)

            synchronize(device)
            
            # if low_res:
            #     now = time.time()
            # else:
            now = perf_counter()
            b = torch.matmul(a, a)
            synchronize(device)

            # total += time.time() - now
            total += perf_counter() - now

        total = total / num_trails

        tflops = 2 * n**3 / total / 1e12

        print(n, total, tflops, sep=", ")


def synchronize(device):
    if device.type == "cuda":
        cuda.synchronize()
    elif device.type == "mps":
        mps.synchronize()
    elif device.type == "cpu":
        pass


def memory_bandwidth_benchmark(device, size=1024 * 1024 * 256):  # 256MB
    # test_range = 2 ** (np.arange(28, 30, 0.5))
    test_range = 2 ** (np.arange(20, 28, 0.5))
    
    

    print('size (GB), elapsed_time, bandwidth')
    num_trails = 100
    for size in test_range:
        elapsed_time = 0
        if elapsed_time > 0.1 and elapsed_time < 1:
            num_trails = 20
        elif elapsed_time > 1:
            num_trails = 5
            
        for _ in range(num_trails):
            size = int(size)

            # Create random tensors
            if is_FP16:
                a = torch.rand(size, device=device).half()
                b = torch.rand(size, device=device).half()
            else:
                a = torch.rand(size, device=device)
                b = torch.rand(size, device=device)

            # Warm-up to ensure CUDA kernel is initialized if using GPU
            synchronize(device)
            a.copy_(b)
            synchronize(device)

            # Record the start time
            # start_time = time.time()
            start_time = perf_counter()
            # Perform the copy operation
            a.copy_(b)

            # Synchronize if using CUDA to make sure operation is finished
            synchronize(device)

            # Record the end time
            # end_time = time.time()
            end_time = perf_counter()

            # Compute elapsed time
            elapsed_time += end_time - start_time

        elapsed_time = elapsed_time / num_trails
        # Calculate Bandwidth in GB/s
        bytes_copied = a.nelement() * a.element_size()  # bytes
        bandwidth = 2 * bytes_copied / elapsed_time / 1e9  # GB/s

        print(bytes_copied / 1e9, elapsed_time, bandwidth, sep=', ')

    return bandwidth


if __name__ == "__main__":
    device = torch.device('cpu')
    flops_benchmark(device)
    memory_bandwidth_benchmark(device)