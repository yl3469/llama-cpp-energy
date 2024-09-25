#!/bin/bash
set -ex
# Path to save the benchmark log
LOGFILE="benchmark_log-$(date +'%Y-%m-%d-%H-%M-%S').txt"
> $LOGFILE  # Clear the log file if it exists

# Threshold for saturation (1.1 means 10% performance gain)
SATURATION_THRESHOLD=1.1

# Initialize variables to store the last successful performance numbers
last_S_TG=0.1
last_S_PP=0.1

current_S_TG=0
current_S_PP=0

# Configurations to test (you can modify as needed)
# batch_sizes=(16 32 64 128)  # Values for -ngl, the batch size
pp_configs="128,256,512"    # Values for -npp
tg_configs="16,64"   # Values for -ntg
num_threads=(2 4 8 16 32 64 90 128 224)         # Number of threads to test
echo $pp_configs > /dev/null
# Function to compare current and last performance
saturation_check() {

  tg_ratio=$(echo "scale=2; $current_S_TG / $last_S_TG" | bc)
  pp_ratio=$(echo "scale=2; $current_S_PP / $last_S_PP" | bc)

  # If both metrics are saturated, return false
  if (( $(echo "$tg_ratio > 1" | bc -l) && $(echo "$pp_ratio > 1" | bc -l) && $(echo "$tg_ratio < $SATURATION_THRESHOLD" | bc -l) && $(echo "$pp_ratio < $SATURATION_THRESHOLD" | bc -l) )); then
  # and it should > 1
#   if (( $(echo "$tg_ratio > 1" | bc -l) && $(echo "$pp_ratio > 1" | bc -l) )); then
    return 1  # Saturation detected, skip
  fi
  return 0  # Continue testing
}

check_logs() {
    # This function checks the logs and returns S_TG and S_PP
    # Poll the results from the log file once the file is written in the background 
    # When the logfile is updated, read the last line and extract S_TG and S_PP
    # Return the values

    # Create a lock file to check if the log file is updated
    touch lockfile
    # write 1 to lockfile
    echo 1 > lockfile

    # Check if the length of log is updated
    past_length=$(wc -l < $LOGFILE)
    while [ $(wc -l < $LOGFILE) -le $past_length ]; do
        sleep 1
    done

    result_line=$(tail -n 1 $LOGFILE)
    # if result_line starts with main: n_kv_max = then start 
    # if [[ $result_line == main:* ]]; then
    current_S_TG=$(echo "$result_line" | awk -F "|" '{print $8}' | xargs)
    current_S_PP=$(echo "$result_line" | awk -F "|" '{print $6}' | xargs)
    # fi
    # wait until the aboves are real umbers
    if ! [[ $current_S_TG =~ ^[0-9]+([.][0-9]+)?$ ]] || ! [[ $current_S_PP =~ ^[0-9]+([.][0-9]+)?$ ]]; 
    then
        current_S_TG=0 
        current_S_PP=0
    fi
    echo $current_S_TG $current_S_PP

    check_logs &
}

# Loop through configurations
for models in codegemma-7b-it-Q4_K_M.gguf Meta-Llama-3.1-8B-Instruct-Q4_K_M.gguf; do
  for threads in "${num_threads[@]}"; do
# for tg in "${tg_configs[@]}"; do
#   for pp in "${pp_configs[@]}"; do

    # check_logs &
    # Extract S_TG and S_PP by calling check_logs function
    # read current_S_TG current_S_PP < <(check_logs)

    # put the above line in the background
    
    # read the values from the function

    # Run the benchmark and append the output to the log file
    llama-batched-bench -m ./models/$models -c 8192 -b 512 -ub 512 -ngl 0 -npp $pp_configs -ntg $tg_configs -npl 1,2,4,8,16,32,64 -t $threads >> $LOGFILE

    # check_logs &
    # Extract S_TG and S_PP by calling check_logs function
    # read current_S_TG current_S_PP < <(check_logs)

    # put the above line in the background
    
    # read the values from the function

    # Run the benchmark and append the output to the log file
    # llama-batched-bench -m ./models/Meta-Llama-3.1-8B-Instruct-Q4_K_M.gguf -c 8192 -b 512 -ub 512 -ngl 0 -npp $pp -ntg $tg -npl 1,2,4,8,16,32,64 -t $threads >> $LOGFILE 


    # Update last performance values
    last_S_TG=$current_S_TG
    last_S_PP=$current_S_PP

    # Log successful configuration
    echo "Configuration completed: tg=$tg pp=$pp threads=$threads with S_TG=$current_S_TG, S_PP=$current_S_PP" >> $LOGFILE
  done
done