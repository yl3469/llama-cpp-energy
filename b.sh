#!/bin/bash
set -x
# Path to save the benchmark log
LOGFILE="benchmark_log_fa-$(date +'%Y-%m-%d-%H-%M-%S').txt"
> $LOGFILE  # Clear the log file if it exists

# Threshold for saturation (1.1 means 10% performance gain)
SATURATION_THRESHOLD=1.1

# Initialize variables to store the last successful performance numbers
last_S_TG=0.1
last_S_PP=0.1

current_S_TG=0
current_S_PP=0

EXE=/home/lisa/llama.cpp/build_en_oct3/bin/llama-batched-bench
# Configurations to test (you can modify as needed)
# batch_sizes=(16 32 64 128)  # Values for -ngl, the batch size
pp_configs="8192"    # Values for -npp
tg_configs="8"   # Values for -ntg
pl_configs="2,4,8,16" #  batch size for the model
# (Note, this can be calculated as KVMem / ) TODO
num_threads=(16 32 64)         # Number of threads to test
max_batchs=(1024 2048 512)  # Values for -b, the maximum batch size
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

check_time() {
    # This function checks the logs and returns S_TG and S_PP
    # Poll the results from the log file once the file is written in the background 
    # When the logfile is updated, read the last line and extract S_TG and S_PP
    # Return the values

    # Create a lock file to check if the log file is updated
    touch lockfile
    # write 1 to lockfile
    echo 1 > lockfile

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

}
# Loop through configurations Meta-Llama-3-70B-Instruct-Q4_K_M.gguf
for models in Meta-Llama-3.1-8B-Instruct-Q4_K_M.gguf; do
  for max_batch in "${max_batchs[@]}"; do
    for threads in "${num_threads[@]}"; do
# for tg in "${tg_configs[@]}"; do
#   for pp in "${pp_configs[@]}"; do
      echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~" >> $LOGFILE
    # check_logs &
    # Extract S_TG and S_PP by calling check_logs function
    # read current_S_TG current_S_PP < <(check_logs)

    # put the above line in the background
    
    # read the values from the function

    # Run the benchmark and append the output to the log file
      (
        # taskset on the #threads CPUs
        taskset -c 0-$(($threads-1)) $EXE -m ./models/$models -c 0 -b $max_batch -ub $max_batch -ngl 0 -npp $pp_configs -ntg $tg_configs -npl $pl_configs -t $threads -fa >> $LOGFILE
      ) &  # Redirect both stdout and stderr to the log file
      PID=$!
      
      # Wait and periodically check if the process exceeds the time limit
      SECONDS=0
      # Get the maximum time for the logfile in the column as the time limit
      TIME_LIMIT=12000
      while kill -0 $PID 2> /dev/null; do
          if [ $SECONDS -ge $TIME_LIMIT ]; then
              echo "llama-batched-bench with PID $PID has exceeded the time limit of $((TIME_LIMIT / 60)) minutes. Killing the process." >> $LOGFILE
              kill -9 $PID
              break
          fi
          sleep 2m  # Check every 10 seconds
      done
    # Extract S_TG and S_PP by calling check_logs function
    # read current_S_TG current_S_PP < <(check_logs)

    # put the above line in the background
    
    # read the values from the function

    # Run the benchmark and append the output to the log file
    # llama-batched-bench -m ./models/Meta-Llama-3.1-8B-Instruct-Q4_K_M.gguf -c 8192 -b 512 -ub 512 -ngl 0 -npp $pp -ntg $tg -npl 1,2,4,8,16,32,64 -t $threads >> $LOGFILE 


    # # Update last performance values
    # last_S_TG=$current_S_TG
    # last_S_PP=$current_S_PP

    # Log successful configuration
      echo "Configuration completed: HW = SPR threads=$threads max_batch=$max_batch model=$models" >> $LOGFILE
    done
  done
done