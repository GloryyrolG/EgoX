#!/bin/bash
# Quick test: H2O EgoX (exo2ego) fine-tune — run a few steps and verify checkpoint save.
# Uses EgoX-EgoPriorRenderer/processed (meta + videos + vipe_results). data_root=processed so cache goes under processed/cache.
# 通测设置: train_steps=3, checkpointing_steps=1, checkpointing_limit=2（无 eval 阶段）
# Usage: 在 repo root 执行: bash scripts/finetune_h2o_test.sh（会激活 conda 环境 egox）

set -e
# 使用 conda 环境 egox
source "$(conda info --base)/etc/profile.d/conda.sh"
conda activate egox
export TOKENIZERS_PARALLELISM=false
export MASTER_ADDR=localhost
export MASTER_PORT=29502
export NNODES=1
export NUM_PROCESSES=1

LAUNCHER="accelerate launch \
    --config_file configs_acc/1gpu.yaml \
    --main_process_ip $MASTER_ADDR \
    --main_process_port $MASTER_PORT \
    --machine_rank 0 \
    --num_processes $NUM_PROCESSES \
    --num_machines $NNODES"

# 通测：只跑 3 步，每步都 save，不跑 eval（本代码没有 eval 阶段）
PROGRAM="finetune.py \
    --model_path ./checkpoints/pretrained_model/Wan2.1-I2V-14B-480P-Diffusers \
    --model_name wan-i2v \
    --model_type wan-i2v \
    --training_type lora \
    --rank 128 \
    --lora_alpha 256 \
    --output_dir ./results/EgoX_h2o_test \
    --report_to tensorboard \
    --data_root ./EgoX-EgoPriorRenderer/processed \
    --meta_data_file ./EgoX-EgoPriorRenderer/processed/h2o/meta.json \
    --train_resolution 25x256x704 \
    --train_epochs 1 \
    --train_steps 3 \
    --seed 42 \
    --batch_size 1 \
    --gradient_accumulation_steps 1 \
    --mixed_precision bf16 \
    --num_workers 4 \
    --pin_memory True \
    --checkpointing_steps 1 \
    --checkpointing_limit 2 \
    --gen_fps 30 \
    --cos_sim_scaling_factor 1.0 \
"

CMD="$LAUNCHER $PROGRAM"
echo "Running H2O EgoX fine-tune 通测 (3 steps, save every step, no eval)..."
eval "$CMD"
echo "END TIME: $(date)"
echo "Checkpoints: ls -la ./results/EgoX_h2o_test/"
