# Define the output CSV file
set -ex
OUTPUT_CSV="llama_bench_output.csv"
INPUT_LOG=$1
# Add the header to the CSV file
echo "Config,n_kv_max,n_batch,n_ubatch,flash_attn,is_pp_shared,n_gpu_layers,n_threads,n_threads_batch,PP,TG,B,N_KV,T_PP s,S_PP t/s,P_PP W,T_TG s,S_TG t/s,P_TG W,T s,S t/s,P W" > $OUTPUT_CSV

# Read the log file line by line
while read -r line; do
    # If the line contains configuration details, store it
    if [[ $line == main:* ]]; then
        config_line="$line"
        
        # Extract the parameters from the config line
# Extract only the numeric values from the config line
        n_kv_max=$(echo $line | awk -F'n_kv_max = ' '{print $2}' | awk '{print $1}' | grep -o '[0-9]\+')
        n_batch=$(echo $line | awk -F'n_batch = ' '{print $2}' | awk '{print $1}' | grep -o '[0-9]\+')
        n_ubatch=$(echo $line | awk -F'n_ubatch = ' '{print $2}' | awk '{print $1}' | grep -o '[0-9]\+')
        flash_attn=$(echo $line | awk -F'flash_attn = ' '{print $2}' | awk '{print $1}' | grep -o '[0-9]\+')
        is_pp_shared=$(echo $line | awk -F'is_pp_shared = ' '{print $2}' | awk '{print $1}' | grep -o '[0-9]\+')
        n_gpu_layers=$(echo $line | awk -F'n_gpu_layers = ' '{print $2}' | awk '{print $1}' | grep -o '[0-9]\+')
        n_threads=$(echo $line | awk -F'n_threads = ' '{print $2}' | awk '{print $1}' | grep -o '[0-9]\+')
        n_threads_batch=$(echo $line | awk -F'n_threads_batch = ' '{print $2}' | awk '{print $1}' | grep -o '[0-9]\+')
        echo "$config_line,$n_kv_max,$n_batch,$n_ubatch,$flash_attn,$is_pp_shared,$n_gpu_layers,$n_threads,$n_threads_batch" >> $OUTPUT_CSV
    fi

    # If the line is a table row (contains '|'), process it into CSV
    if [[ $line == *'|'* && $line != *'-----'* ]]; then
        # Convert the table row to CSV format
        csv_row=$(echo "$line" | sed 's/|/,/g' | sed 's/^,//; s/,$//')
        echo $csv_row >> $OUTPUT_CSV
        # Append the configuration and the table row to the CSV file
        
    fi
done < $INPUT_LOG

echo "CSV file created: $OUTPUT_CSV"

