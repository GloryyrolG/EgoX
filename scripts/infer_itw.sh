#!/bin/bash
# In-the-wild inference (idx: 0=joker, 1=ironman, 2=hulk_blackwidow, 3=tabletennis)
# Resolution: set NUM_FRAMES, HEIGHT, WIDTH or use preset (e.g. 25x256x704 for quick test)
GPU_IDS=0
SEED=846514

# Resolution (num_frames x height x total_width). Override via env, e.g.:
#   NUM_FRAMES=25 HEIGHT=256 WIDTH=704 bash scripts/infer_itw.sh   # quick test
#   NUM_FRAMES=49 HEIGHT=448 WIDTH=1232 ...                        # default
NUM_FRAMES=${NUM_FRAMES:-49}
HEIGHT=${HEIGHT:-448}
WIDTH=${WIDTH:-1232}
NUM_INFERENCE_STEPS=${NUM_INFERENCE_STEPS:-50}

export CUDA_VISIBLE_DEVICES=$GPU_IDS
echo "Using GPUs: $GPU_IDS | resolution: ${NUM_FRAMES}x${HEIGHT}x${WIDTH} | steps: ${NUM_INFERENCE_STEPS}"

python3 infer.py \
    --num_inference_steps $NUM_INFERENCE_STEPS \
    --meta_data_file ./example/in_the_wild/meta.json \
    --model_path ./checkpoints/pretrained_model/Wan2.1-I2V-14B-480P-Diffusers \
    --lora_path ./checkpoints/EgoX/pytorch_lora_weights.safetensors \
    --lora_rank 256 \
    --out ./results \
    --seed $SEED \
    --use_GGA \
    --cos_sim_scaling_factor 3.0 \
    --in_the_wild \
    --num_frames $NUM_FRAMES \
    --height $HEIGHT \
    --width $WIDTH \
    --idx 1
