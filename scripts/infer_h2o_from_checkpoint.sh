#!/bin/bash
# H2O inference using a finetune checkpoint (e.g. results/EgoX_h2o_test/checkpoint-3).
# Usage: bash scripts/infer_h2o_from_checkpoint.sh [checkpoint_dir]
#   checkpoint_dir defaults to ./results/EgoX_h2o_test/checkpoint-3
#   测 EgoX 官方（Wan2.1 + EgoX LoRA）: bash scripts/infer_h2o_from_checkpoint.sh official
#   测 128x352: NUM_FRAMES=25 HEIGHT=128 WIDTH=352 bash scripts/infer_h2o_from_checkpoint.sh official
# Optional env: NUM_FRAMES, HEIGHT, WIDTH, NUM_INFERENCE_STEPS, GPU_IDS, IDX, COS_SIM_SCALING_FACTOR

set -e
source "$(conda info --base)/etc/profile.d/conda.sh"
conda activate egox

GPU_IDS=${GPU_IDS:-0}
SEED=42
CHECKPOINT_DIR=${1:-./results/EgoX_h2o_test/checkpoint-3}
NUM_FRAMES=${NUM_FRAMES:-25}
HEIGHT=${HEIGHT:-256}
WIDTH=${WIDTH:-704}
NUM_INFERENCE_STEPS=${NUM_INFERENCE_STEPS:-15}
IDX=${IDX:-0}
# 与 finetune 一致用 1.0；官方权重用 3.0
COS_SIM_SCALING_FACTOR_OFFICIAL=3.0
COS_SIM_SCALING_FACTOR_FINETUNE=${COS_SIM_SCALING_FACTOR:-1.0}

# official = EgoX 官方权重（Wan2.1 + EgoX LoRA，即 checkpoints/EgoX）
USE_OFFICIAL=false
if [ -z "$CHECKPOINT_DIR" ] || [ "$CHECKPOINT_DIR" = "official" ]; then
    USE_OFFICIAL=true
    CHECKPOINT_DIR="./checkpoints/EgoX"
    OUT_DIR="./results/EgoX_h2o_test/infer_official_${HEIGHT}x${WIDTH}"
else
    OUT_DIR="./results/EgoX_h2o_test/infer"
fi

export CUDA_VISIBLE_DEVICES=$GPU_IDS
echo "Checkpoint: $CHECKPOINT_DIR | resolution: ${NUM_FRAMES}x${HEIGHT}x${WIDTH} | steps: $NUM_INFERENCE_STEPS | idx: $IDX | out: $OUT_DIR"

if [ "$USE_OFFICIAL" = "true" ]; then
    # EgoX official = Wan2.1 base + EgoX LoRA (same as infer_ego4d.sh / infer_h2o.sh)
    python3 infer.py \
        --num_inference_steps $NUM_INFERENCE_STEPS \
        --meta_data_file ./EgoX-EgoPriorRenderer/processed/h2o/meta.json \
        --model_path ./checkpoints/pretrained_model/Wan2.1-I2V-14B-480P-Diffusers \
        --lora_path "$CHECKPOINT_DIR" \
        --out "$OUT_DIR" \
        --seed $SEED \
        --use_GGA \
        --cos_sim_scaling_factor $COS_SIM_SCALING_FACTOR_OFFICIAL \
        --num_frames $NUM_FRAMES \
        --height $HEIGHT \
        --width $WIDTH \
        --idx $IDX
else
    python3 infer.py \
        --num_inference_steps $NUM_INFERENCE_STEPS \
        --meta_data_file ./EgoX-EgoPriorRenderer/processed/h2o/meta.json \
        --model_path ./checkpoints/pretrained_model/Wan2.1-I2V-14B-480P-Diffusers \
        --lora_path "$CHECKPOINT_DIR" \
        --out "$OUT_DIR" \
        --seed $SEED \
        --use_GGA \
        --cos_sim_scaling_factor $COS_SIM_SCALING_FACTOR_FINETUNE \
        --num_frames $NUM_FRAMES \
        --height $HEIGHT \
        --width $WIDTH \
        --idx $IDX
fi

echo "Done. Outputs: $OUT_DIR"
