#!/bin/bash
# Ego-Exo4D inference. Override resolution: NUM_FRAMES=25 HEIGHT=256 WIDTH=704 bash scripts/infer_ego4d.sh
GPU_IDS=0
SEED=42

NUM_FRAMES=${NUM_FRAMES:-49}
HEIGHT=${HEIGHT:-448}
WIDTH=${WIDTH:-1232}
NUM_INFERENCE_STEPS=${NUM_INFERENCE_STEPS:-50}

export CUDA_VISIBLE_DEVICES=$GPU_IDS
echo "Using GPUs: $GPU_IDS | resolution: ${NUM_FRAMES}x${HEIGHT}x${WIDTH} | steps: ${NUM_INFERENCE_STEPS}"

python3 infer.py \
    --num_inference_steps $NUM_INFERENCE_STEPS \
    --meta_data_file ./example/egoexo4D/meta.json \
    --model_path ./checkpoints/pretrained_model/Wan2.1-I2V-14B-480P-Diffusers \
    --lora_path ./checkpoints/EgoX/pytorch_lora_weights.safetensors \
    --lora_rank 256 \
    --out ./results \
    --seed $SEED \
    --use_GGA \
    --cos_sim_scaling_factor 3.0 \
    --num_frames $NUM_FRAMES \
    --height $HEIGHT \
    --width $WIDTH \

