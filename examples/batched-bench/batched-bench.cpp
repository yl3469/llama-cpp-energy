#include "arg.h"
#include "common.h"
#include "log.h"
#include "llama.h"
#include <fstream>
#include <string>

#include <algorithm>
#include <cstdio>
#include <string>
#include <vector>
#include "energymon-rapl.h"


static void print_usage(int, char ** argv) {
    LOG("\nexample usage:\n");
    LOG("\n    %s -m model.gguf -c 2048 -b 2048 -ub 512 -npp 128,256,512 -ntg 128,256 -npl 1,2,4,8,16,32 [-pps]\n", argv[0]);
    LOG("\n");
}

static long get_memory_available (void) {
    std::ifstream file("/proc/meminfo");
    std::string key;
    long value;
    std::string unit;
    
    while (file >> key >> value >> unit) {
        if (key == "MemAvailable:") {
            LOG("Memory available: %ld %s\n", value, unit.c_str());

            if (unit == "kB") {
                return value / 1024;
            } else if (unit == "mB") {
                return value;
            } else if (unit == "gB") {
                return value * 1024;
            } else {
                return -1;
            }
            return value;  // The value is in MB
        }
    }

    return -1;  // Error, couldn't find the value
}

int main(int argc, char ** argv) {
    energymon em;
    uint64_t start_uj, end_uj;

    // get the energymon instance and initialize
    energymon_get_rapl(&em);
    em.finit(&em);
    start_uj = em.fread(&em);
    gpt_params params;

    if (!gpt_params_parse(argc, argv, params, LLAMA_EXAMPLE_BENCH, print_usage)) {
        return 1;
    }

    gpt_init();

    int is_pp_shared = params.is_pp_shared;

    std::vector<int> n_pp = params.n_pp;
    std::vector<int> n_tg = params.n_tg;
    std::vector<int> n_pl = params.n_pl;

    // init LLM

    llama_backend_init();
    llama_numa_init(params.numa);

    // initialize the model

    llama_model_params model_params = llama_model_params_from_gpt_params(params);

    llama_model * model = llama_load_model_from_file(params.model.c_str(), model_params);
    end_uj = em.fread(&em);
    printf("~~~~~Total energy for llama_load_model_from_file() in microjoules: %"PRIu64"\n", end_uj - start_uj);

    long int mem = get_memory_available();
    printf("Memory available: %ld\n", mem);
    long int max_mem_watermark = 120 * 1024; // 120 GB TODO - currently hardcoded

    auto model_size = llama_model_size(model); // in bytes
    // auto max_kv_memory = static_cast<long int>(mem * 0.8) - static_cast<long int>(model_size / 1024.0 / 1024); // in MB
    auto max_kv_memory = static_cast<long int>(100*1024)- static_cast<long int>(model_size / 1024.0 / 1024); // in MB
    printf("Model size: %ld\n", model_size / 1024 / 1024);
    printf("Max memory watermark: %ld\n", max_mem_watermark);
    printf("MAX KV memory: %ld\n", max_kv_memory);

    if (model == NULL) {
        fprintf(stderr , "%s: error: unable to load model\n" , __func__);
        return 1;
    }

    llama_context_params ctx_params = llama_context_params_from_gpt_params(params);

    // ensure enough sequences are available
    ctx_params.n_seq_max = n_pl.empty() ? 1 : *std::max_element(n_pl.begin(), n_pl.end());

    llama_context * ctx = llama_new_context_with_model(model, ctx_params);

    if (ctx == NULL) {
        fprintf(stderr , "%s: error: failed to create the llama_context\n" , __func__);
        return 1;
    }

    // const int32_t n_kv_max = llama_n_ctx(ctx);
    // max is actually the max (npp+ntg) * npl
    const int32_t max_npp = *std::max_element(n_pp.begin(), n_pp.end());
    const int32_t max_ntg = *std::max_element(n_tg.begin(), n_tg.end());
    const int32_t max_npl = *std::max_element(n_pl.begin(), n_pl.end());
    const int32_t n_kv_max = (max_npp+max_ntg) * (n_pl.empty() ? 1 : max_npl);
    float kv_size = llama_get_kv_cache_size(ctx);
    LOG("KV size: %f\n", kv_size);
    LOG("n_kv_max size: %d\n", n_kv_max);
    llama_batch batch = llama_batch_init(n_kv_max, 0, 1);

    // decode in batches of ctx_params.n_batch tokens
    auto decode_helper = [](llama_context * ctx, llama_batch & batch, int32_t n_batch) {
        for (int32_t i = 0; i < (int32_t) batch.n_tokens; i += n_batch) {
            const int32_t n_tokens = std::min(n_batch, (int32_t) (batch.n_tokens - i));

            llama_batch batch_view = {
                n_tokens,
                batch.token    + i,
                nullptr,
                batch.pos      + i,
                batch.n_seq_id + i,
                batch.seq_id   + i,
                batch.logits   + i,
                0, 0, 0, // unused
            };

            const int ret = llama_decode(ctx, batch_view);
            if (ret != 0) {
                LOG_ERR("failed to decode the batch, n_batch = %d, ret = %d\n", n_batch, ret);
                return false;
            }

            llama_synchronize(ctx);
        }

        return true;
    };

    // warm up
    {
        for (int i = 0; i < 16; ++i) {
            llama_batch_add(batch, 0, i, { 0 }, false);
        }

        if (!decode_helper(ctx, batch, ctx_params.n_batch)) {
            LOG_ERR("%s: llama_decode() failed\n", __func__);
            return 1;
        }
    }

    if (!params.batched_bench_output_jsonl) {
        LOG("\n");
        LOG("%s: n_kv_max = %d, n_batch = %d, n_ubatch = %d, flash_attn = %d, is_pp_shared = %d, n_gpu_layers = %d, n_threads = %u, n_threads_batch = %u\n", __func__, n_kv_max, params.n_batch, params.n_ubatch, params.flash_attn, params.is_pp_shared, params.n_gpu_layers, ctx_params.n_threads, ctx_params.n_threads_batch);
        LOG("\n");
        LOG("|%6s | %6s | %4s | %6s | %8s | %8s | %8s | %8s | %8s | %8s | %8s | %8s | %8s |\n", "PP", "TG", "B", "N_KV", "T_PP s", "S_PP t/s", "P_PP W", "T_TG s", "S_TG t/s", "P_TG W", "T s", "S t/s", "P W");
        LOG("|%6s-|-%6s-|-%4s-|-%6s-|-%8s-|-%8s-|-%8s-|-%8s-|-%8s-|-%8s-|-%8s-|-%8s-|-%8s-|\n", "------", "------", "----", "------", "--------", "--------", "--------", "--------", "--------", "--------", "--------", "--------", "--------");
    }

    for (        int i_pp = 0; i_pp < (int) n_pp.size(); ++i_pp) {
        for (    int i_tg = 0; i_tg < (int) n_tg.size(); ++i_tg) {
            for (int i_pl = 0; i_pl < (int) n_pl.size(); ++i_pl) {
                const int pp = n_pp[i_pp];
                const int tg = n_tg[i_tg];
                const int pl = n_pl[i_pl];

                const int n_ctx_req = is_pp_shared ? pp + pl*tg : pl*(pp + tg);

                

                // if (n_ctx_req > n_kv_max) {
                //     continue;
                // }

                // calculate the max KV cache CPU memory can hold. This can be 4* nlayers * nheads * dheads for each token, and the rest of memory can be profiled by util function
                // const
                
                if (kv_size * n_ctx_req > float(max_kv_memory)) {
                    LOG("KV size exceeds the available memory %f \n", float(max_kv_memory));
                    continue;
                }

                

                llama_batch_clear(batch);

                for (int i = 0; i < pp; ++i) {
                    for (int j = 0; j < (is_pp_shared ? 1 : pl); ++j) {
                        llama_batch_add(batch, 0, i, { j }, false);
                    }
                }
                batch.logits[batch.n_tokens - 1] = true;

                const auto t_pp_start = ggml_time_us();
                const auto e_pp_start = em.fread(&em);

                llama_kv_cache_clear(ctx);

                if (!decode_helper(ctx, batch, ctx_params.n_batch)) {
                    LOG_ERR("%s: llama_decode() failed\n", __func__);
                    return 1;
                }

                if (is_pp_shared) {
                    for (int32_t i = 1; i < pl; ++i) {
                        llama_kv_cache_seq_cp(ctx, 0, i, -1, -1);
                    }
                }

                const auto t_pp_end = ggml_time_us();
                const auto e_pp_end = em.fread(&em);

                const auto t_tg_start = ggml_time_us();
                const auto e_tg_start = em.fread(&em);

                for (int i = 0; i < tg; ++i) {
                    llama_batch_clear(batch);

                    for (int j = 0; j < pl; ++j) {
                        llama_batch_add(batch, 0, pp + i, { j }, true);
                    }

                    if (!decode_helper(ctx, batch, ctx_params.n_batch)) {
                        LOG_ERR("%s: llama_decode() failed\n", __func__);
                        return 1;
                    }
                }

                const auto t_tg_end = ggml_time_us();
                const auto e_tg_end = em.fread(&em);

                const int32_t n_kv = n_ctx_req;

                const float t_pp = (t_pp_end - t_pp_start) / 1000000.0f;
                const float t_tg = (t_tg_end - t_tg_start) / 1000000.0f;
                const float e_pp = (e_pp_end - e_pp_start) / 1000.0f; // in mJ
                const float e_tg = (e_tg_end - e_tg_start) / 1000.0f;
                
                // Measure average power
                const float p_pp = e_pp / t_pp / 1000.0f; // in W
                const float p_tg = e_tg / t_tg / 1000.0f;
                const float t    = t_pp + t_tg;
                const float e = e_pp + e_tg;
                const float p = e / t / 1000.0f; // in W

                const float speed_pp = is_pp_shared ? pp / t_pp : pl*pp / t_pp;
                const float speed_tg = pl*tg / t_tg;
                const float speed    = n_kv / t;

                if(params.batched_bench_output_jsonl) {
                    LOG(
                        "{\"n_kv_max\": %d, \"n_batch\": %d, \"n_ubatch\": %d, \"flash_attn\": %d, \"is_pp_shared\": %d, \"n_gpu_layers\": %d, \"n_threads\": %u, \"n_threads_batch\": %u, "
                        "\"pp\": %d, \"tg\": %d, \"pl\": %d, \"n_kv\": %d, \"t_pp\": %f, \"speed_pp\": %f, \"t_tg\": %f, \"speed_tg\": %f, \"t\": %f, \"speed\": %f}\n",
                        n_kv_max, params.n_batch, params.n_ubatch, params.flash_attn, params.is_pp_shared, params.n_gpu_layers, ctx_params.n_threads, ctx_params.n_threads_batch,
                        pp, tg, pl, n_kv, t_pp, speed_pp, t_tg, speed_tg, t, speed
                    );
                } else {
                    LOG("|%6d | %6d | %4d | %6d | %8.3f | %8.2f | %8.4f | %8.3f | %8.2f | %8.4f | %8.3f | %8.2f | %8.4f | \n", pp, tg, pl, n_kv, t_pp, speed_pp, p_pp, t_tg, speed_tg, p_tg, t, speed, p);
                }
            }
        }
    }
// destroy the instance
    em.ffinish(&em);
    LOG("\n");
    llama_perf_context_print(ctx);

    llama_batch_free(batch);

    llama_free(ctx);
    llama_free_model(model);

    llama_backend_free();

    LOG("\n\n");

    return 0;
}
