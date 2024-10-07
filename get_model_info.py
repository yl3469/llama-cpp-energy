from huggingface_hub import HfApi, hf_hub_download
from tabulate import tabulate
import json
import requests
from bs4 import BeautifulSoup
import re
# Instantiate Huggingface API
api = HfApi()

# List of models
models = [
    # Llama 2 models
    "meta-llama/Llama-2-7b-hf",
    "meta-llama/Llama-2-13b-hf",
    "meta-llama/Llama-2-70b-hf",
    "meta-llama/Meta-Llama-3-8B",
    "meta-llama/Meta-Llama-3-70B-Instruct",
    # "meta-llama/Llama-3.2-90B-Vision-Instruct",
    # OPT models
    "facebook/opt-125m",
    "facebook/opt-350m",
    "facebook/opt-1.3b",
    "facebook/opt-2.7b",
    "facebook/opt-6.7b",
    "facebook/opt-13b",
    "facebook/opt-30b",
    "facebook/opt-66b",
    # Mixtral models
    "mistralai/Mixtral-8x7B-v0.1",
    "mistralai/Mixtral-8x7B-Instruct-v0.1",
    "mistralai/Mixtral-8x22B-Instruct-v0.1",
    # QWen models
    "Qwen/Qwen-7B",
    "Qwen/Qwen1.5-MoE-A2.7B",
    "Qwen/Qwen-14B",
    "Qwen/Qwen-72B",
    "Qwen/Qwen-1_8B",
    "Qwen/Qwen-VL",
    "Qwen/Qwen-Audio",
    # # Other models
    # "THUDM/chatglm2-6b",
    # "EleutherAI/gpt-neo-1.3B",
    # "EleutherAI/gpt-j-6B",
    # "gpt2",
    # "bigscience/bloom-560m",
    # "bigscience/bloom-1b7",
    # "bert-base-uncased"
]

# Function to extract model details
def calculate_kv_cache_size(hidden_size, num_heads, num_layers):
    # Formula: 4 * n * d * h_kv * L
    # where n is sequence length (we'll use 1 for per-token calculation)
    # d is hidden_size // num_heads (assuming d_k = d_v = d // num_heads)
    # h_kv is num_heads (assuming num_kv_heads = num_heads if not specified)
    # L is num_layers
    d_head = hidden_size // num_heads
    return 4 * 1 * d_head * num_heads * num_layers

def calculate_model_size(hidden_size, num_heads, num_layers, vocab_size):
    # This is inaccurate! DEPRECATED
    # This is a rough estimate and may vary based on model architecture
    # Formula: 4 * (V * d + L * d * d + L * d * d_ff)
    # where V is vocab_size, d is hidden_size, L is num_layers
    # and d_ff is typically 4 * hidden_size for most transformer models
    d_ff = 4 * hidden_size
    return 4 * (vocab_size * hidden_size + num_layers * hidden_size * hidden_size + num_layers * hidden_size * d_ff)



def get_config(model_id):
    try:
        config_file = hf_hub_download(repo_id=model_id, filename="config.json")
        with open(config_file, 'r') as f:
            return json.load(f)
    except Exception as e:
        print(f"Error fetching config for {model_id}: {str(e)}")
        return None

def get_model_size(model_id):
    url = f"https://huggingface.co/{model_id}/tree/main"
    response = requests.get(url)
    if response.status_code == 200:
        soup = BeautifulSoup(response.text, 'html.parser')

        # Step 2: Find all download links and file size information
        # 
        download_links = soup.find_all('a', href=re.compile(r'.*\.safetensors\?download=true'))
        
        total_size = 0

        # Step 3: Loop through each download link to extract the file size and sum it
        for link in download_links:
            file_name = link['href'].split('/')[-1]
            if re.match(r'model.*\.safetensors', file_name):
                # Get the size from the text next to the download link
                size_text = link.text.strip()

                # Extract the size and convert to bytes
                size_value, unit = re.match(r'([0-9.]+)\s*([KMG]?B)', size_text).groups()
                size_value = float(size_value)
                
                # Convert to bytes based on the unit
                if unit == 'KB':
                    size_value *= 1024
                elif unit == 'MB':
                    size_value *= 1024 ** 2
                elif unit == 'GB':
                    size_value *= 1024 ** 3

                total_size += size_value

            # Step 4: Print the total size in GB
        if total_size == 0:
            download_links = soup.find_all('a', href=re.compile(r'.*\.bin\?download=true'))
            # print(download_links)
            for link in download_links:
                file_name = link['href'].split('/')[-1]
                if re.match(r'pytorch_model.*\.bin', file_name):
                    # Get the size from the text next to the download link
                    size_text = link.text.strip()

                    # Extract the size and convert to bytes
                    size_value, unit = re.match(r'([0-9.]+)\s*([KMG]?B)', size_text).groups()
                    size_value = float(size_value)
                    
                    # Convert to bytes based on the unit
                    if unit == 'KB':
                        size_value *= 1024
                    elif unit == 'MB':
                        size_value *= 1024 ** 2
                    elif unit == 'GB':
                        size_value *= 1024 ** 3

                    total_size += size_value
        print(f"Total size of model*.safetensors files: {total_size / (1024 ** 3):.2f} GB")

        return total_size
    else:
        print(f"Failed to fetch the webpage, status code: {response.status_code}")
        return -1
    
    
    
# Function to extract model details
def get_model_details(model_id):
    try:
        config = get_config(model_id)
        
        if config:
            hidden_size = config.get('hidden_size', config.get('n_embd', 'N/A'))
            num_kv_heads = config.get('num_key_value_heads', config.get('n_head', config.get('num_attention_heads', 'N/A')))
            num_layers = config.get('num_hidden_layers', config.get('n_layer', 'N/A'))
            vocab_size = config.get('vocab_size', 0)
            num_heads = config.get('num_attention_heads', config.get('n_head', 'N/A'))
            
            kv_cache_size = calculate_kv_cache_size(hidden_size, num_kv_heads, num_layers)
            model_size = get_model_size(model_id)
            print(f"kv_cache_size: {kv_cache_size}")
            return {
                "Model": model_id.split("/")[-1],
                "Dimension": hidden_size,
                "Heads": num_heads,
                "KV Heads": num_kv_heads,
                "Layers": num_layers,
                "Context Length": config.get('max_position_embeddings', 'N/A'),
                # "Num Expert": config.get('num_experts', 'N/A'), # or just num_local_experts if it is NA --
                "Num Expert": config.get('num_local_experts', 'N/A') if config.get('num_experts', 'N/A') == 'N/A' else config.get('num_experts', 'N/A'),
                "Top K": config.get('num_experts_per_tok', 'N/A'),
                "KV Cache Size (MB)": kv_cache_size / 1024.0 / 1024.0,
                "Model Size (GB)": model_size / 1024.0 / 1024.0 / 1024.0,   
            }
        else:
            return {"Model": model_id.split("/")[-1], "Error": "Config not found"}
    except Exception as e:
        return {"Model": model_id.split("/")[-1], "Error": str(e)}

# Get details for each model
model_details = [get_model_details(model_id) for model_id in models]

# Print the results in a formatted table
print(tabulate(model_details, headers="keys"))
