#!/bin/bash

# Prevent tokenizer parallelism issues
export TOKENIZERS_PARALLELISM=false

export MASTER_ADDR=localhost
export MASTER_PORT=29501
export NNODES=1
export NUM_PROCESSES=1  # 4

export LAUNCHER="accelerate launch \
    --config_file configs_acc/1gpu.yaml \
    --main_process_ip $MASTER_ADDR \
    --main_process_port $MASTER_PORT \
    --machine_rank 0 \
    --num_processes $NUM_PROCESSES \
    --num_machines $NNODES \
    "

export PROGRAM="\
finetune.py \
    --model_path ./checkpoints/pretrained_model/Wan2.1-I2V-14B-480P-Diffusers \
    --model_name wan-i2v \
    --model_type wan-i2v \
    --training_type lora \
    --rank 128 \
    --lora_alpha 256 \
    --output_dir ./results/EgoX \
    --report_to tensorboard \
    --data_root ./EgoX-EgoPriorRenderer/processed \
    --meta_data_file ./EgoX-EgoPriorRenderer/processed/h2o/meta.json \
    --train_resolution 25x256x704 \
    --train_epochs 150 \
    --seed 42 \
    --batch_size 1 \
    --gradient_accumulation_steps 1 \
    --mixed_precision bf16 \
    --num_workers 16 \
    --pin_memory True \
    --nccl_timeout 1800 \
    --checkpointing_steps 250 \
    --checkpointing_limit 54 \
    --gen_fps 30 \
    --cos_sim_scaling_factor 1.0 \
"
# --resume_from_checkpoint ./results/EgoX/checkpoint-10000 \
# --rank 256 \
# --data_root ./dataset/train \
# --meta_data_file ./dataset/train/meta_with_uid.json \
# --train_resolution 49x448x1232 \

export CMD="$LAUNCHER $PROGRAM"

# Use eval so the composed string is parsed into words/args correctly
eval "$CMD"

echo "END TIME: $(date)"
