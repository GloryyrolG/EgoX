#!/bin/bash
# Overfit on current H2O subset to verify finetune→infer pipeline.
# 当前 meta 只有 1 条样本，1 epoch = 1 step；约 3k 步可望有初步 overfit 效果（经验上 video LoRA 小数据常需 1k–5k 步）。
#
# 快速验证（仅验证方案可行/模型能力，后面再扩展大数据）:
#   FAST_OVERFIT=1  bash scripts/finetune_h2o_overfit.sh
#   会使用: 小分辨率 25x128x352（256x704 严格一半，exo=224+ego=128）、rank 64、1500 步。
#   用该 ckpt 推理时需一致分辨率: NUM_FRAMES=25 HEIGHT=128 WIDTH=352 bash scripts/infer_h2o_from_checkpoint.sh <ckpt_dir>
#
# 从 official EgoX 开始 overfit（推荐：验证 loss 尺度 + 推理更稳）:
#   INITIAL_LORA_PATH=./checkpoints/EgoX FAST_OVERFIT=1 bash scripts/finetune_h2o_overfit.sh
#   会加载官方 LoRA 并在此基础上继续训；rank/alpha 自动用 256/512 以匹配官方。
#
# 环境变量: TRAIN_STEPS CHECKPOINTING_STEPS OUTPUT_DIR
#  或 FAST_OVERFIT=1 使用上述快速预设（可再覆盖 TRAIN_STEPS 等）。
# 续训: RESUME_FROM_CHECKPOINT=./results/EgoX_h2o_overfit_fast/checkpoint-500 bash scripts/finetune_h2o_overfit.sh

set -e
export TOKENIZERS_PARALLELISM=false
source "$(conda info --base)/etc/profile.d/conda.sh"
conda activate egox

export MASTER_ADDR=localhost
export MASTER_PORT=29501
export NNODES=1
export NUM_PROCESSES=1

# Optional one-shot upstream: untar + process H2O before finetune.
RUN_PREPROCESS="${RUN_PREPROCESS:-1}"
PREPROCESS_SCRIPT="${PREPROCESS_SCRIPT:-./EgoX-EgoPriorRenderer/data_preprocess/scripts/process_h2o_batch.sh}"
H2O_SCENE="${H2O_SCENE:-h1}"
H2O_SEQUENCE="${H2O_SEQUENCE:-0}"
H2O_EXO_CAM="${H2O_EXO_CAM:-cam0}"
H2O_STRATEGY="${H2O_STRATEGY:-single}"
H2O_SUBJECT="${H2O_SUBJECT:-subject1}"
H2O_ROOT="${H2O_ROOT:-/mnt/shared/dses/h2o}"
TEXT_ROOT="${TEXT_ROOT:-/mnt/shared/dses/egoworld/h2o/text}"
OUTPUT_ROOT="${OUTPUT_ROOT:-/mnt/shared/dses/egox/h2o_batch}"
EXTRACT_FROM_TAR="${EXTRACT_FROM_TAR:-1}"
TAR_EXTRACT_MODE="${TAR_EXTRACT_MODE:-partial}"
TAR_SOURCE_DIR="${TAR_SOURCE_DIR:-$H2O_ROOT}"
RUN_POST="${RUN_POST:-1}"
EGOX_ENV="${EGOX_ENV:-egox-egopriorrenderer}"

# Data/model path defaults (can override via env).
MODEL_PATH="${MODEL_PATH:-/mnt/shared/ckpts/egox/pretrained_model/Wan2.1-I2V-14B-480P-Diffusers}"
DATA_ROOT="${DATA_ROOT:-$OUTPUT_ROOT}"
META_DATA_FILE="${META_DATA_FILE:-$OUTPUT_ROOT/meta.json}"
CLEAR_CACHE_BEFORE_TRAIN="${CLEAR_CACHE_BEFORE_TRAIN:-1}"
PIN_MEMORY="${PIN_MEMORY:-True}"
MIXED_PRECISION="${MIXED_PRECISION:-bf16}"

if [[ "$RUN_PREPROCESS" == "1" ]]; then
    echo "Running preprocess: subject=$H2O_SUBJECT scene=$H2O_SCENE seq=$H2O_SEQUENCE cam=$H2O_EXO_CAM strategy=$H2O_STRATEGY"
    H2O_ROOT="$H2O_ROOT" \
    TEXT_ROOT="$TEXT_ROOT" \
    OUTPUT_ROOT="$OUTPUT_ROOT" \
    EXTRACT_FROM_TAR="$EXTRACT_FROM_TAR" \
    TAR_EXTRACT_MODE="$TAR_EXTRACT_MODE" \
    TAR_SOURCE_DIR="$TAR_SOURCE_DIR" \
    RUN_POST="$RUN_POST" \
    EGOX_ENV="$EGOX_ENV" \
    bash "$PREPROCESS_SCRIPT" "$H2O_SCENE" "$H2O_SEQUENCE" "$H2O_EXO_CAM" "$H2O_STRATEGY" "$H2O_SUBJECT"
fi

if [[ "$CLEAR_CACHE_BEFORE_TRAIN" == "1" ]]; then
    echo "Clearing cache: $DATA_ROOT/cache"
    rm -rf "$DATA_ROOT/cache"
fi

# 快速 overfit 验证预设：小 resolution + 小 rank + 少步数，省时间
if [ "${FAST_OVERFIT}" = "1" ]; then
    export TRAIN_RESOLUTION="${TRAIN_RESOLUTION:-25x128x352}"
    if [ -n "${INITIAL_LORA_PATH}" ]; then
        export LORA_RANK="${LORA_RANK:-256}"
        export LORA_ALPHA="${LORA_ALPHA:-512}"
    else
        export LORA_RANK="${LORA_RANK:-64}"
        export LORA_ALPHA="${LORA_ALPHA:-128}"
    fi
    export TRAIN_STEPS="${TRAIN_STEPS:-1500}"
    export CHECKPOINTING_STEPS="${CHECKPOINTING_STEPS:-250}"
    export OUTPUT_DIR="${OUTPUT_DIR:-./results/EgoX_h2o_overfit_fast}"
    export NUM_WORKERS="${NUM_WORKERS:-4}"
    echo "FAST_OVERFIT=1: resolution=$TRAIN_RESOLUTION rank=$LORA_RANK steps=$TRAIN_STEPS out=$OUTPUT_DIR initial_lora=${INITIAL_LORA_PATH:-none}"
else
    TRAIN_RESOLUTION=${TRAIN_RESOLUTION:-25x256x704}
    if [ -n "${INITIAL_LORA_PATH}" ]; then
        LORA_RANK=${LORA_RANK:-256}
        LORA_ALPHA=${LORA_ALPHA:-512}
    else
        LORA_RANK=${LORA_RANK:-128}
        LORA_ALPHA=${LORA_ALPHA:-256}
    fi
    TRAIN_STEPS=${TRAIN_STEPS:-3000}
    CHECKPOINTING_STEPS=${CHECKPOINTING_STEPS:-500}
    OUTPUT_DIR=${OUTPUT_DIR:-./results/EgoX_h2o_overfit}
    NUM_WORKERS=${NUM_WORKERS:-16}
fi

# 续训：传入 checkpoint 目录（如 ./results/EgoX_h2o_overfit_fast/checkpoint-500）
RESUME_ARG=""
if [ -n "${RESUME_FROM_CHECKPOINT}" ]; then
    RESUME_ARG="--resume_from_checkpoint \"${RESUME_FROM_CHECKPOINT}\""
    echo "Resuming from: $RESUME_FROM_CHECKPOINT"
fi

# 从 official EgoX LoRA 开始：传入目录（如 ./checkpoints/EgoX）或 .safetensors 路径；rank/alpha 需与官方一致（256/512）
INITIAL_LORA_ARG=""
if [ -n "${INITIAL_LORA_PATH}" ]; then
    INITIAL_LORA_ARG="--initial_lora_path \"${INITIAL_LORA_PATH}\""
    echo "Initial LoRA from: $INITIAL_LORA_PATH (rank=$LORA_RANK alpha=$LORA_ALPHA)"
fi

LAUNCHER="accelerate launch \
    --config_file configs_acc/1gpu.yaml \
    --main_process_ip $MASTER_ADDR \
    --main_process_port $MASTER_PORT \
    --machine_rank 0 \
    --num_processes $NUM_PROCESSES \
    --num_machines $NNODES"

PROGRAM="finetune.py \
    --model_path $MODEL_PATH \
    --model_name wan-i2v \
    --model_type wan-i2v \
    --training_type lora \
    --rank $LORA_RANK \
    --lora_alpha $LORA_ALPHA \
    --output_dir $OUTPUT_DIR \
    --report_to tensorboard \
    --data_root $DATA_ROOT \
    --meta_data_file $META_DATA_FILE \
    --train_resolution $TRAIN_RESOLUTION \
    --train_epochs 1 \
    --train_steps $TRAIN_STEPS \
    --seed 42 \
    --batch_size 1 \
    --gradient_accumulation_steps 1 \
    --mixed_precision $MIXED_PRECISION \
    --num_workers $NUM_WORKERS \
    --pin_memory $PIN_MEMORY \
    --nccl_timeout 1800 \
    --checkpointing_steps $CHECKPOINTING_STEPS \
    --checkpointing_limit 10 \
    --gen_fps 30 \
    --cos_sim_scaling_factor 1.0 \
    $INITIAL_LORA_ARG \
    $RESUME_ARG \
"

echo "H2O overfit finetune: resolution=$TRAIN_RESOLUTION rank=$LORA_RANK steps=$TRAIN_STEPS checkpoint_every=$CHECKPOINTING_STEPS out=$OUTPUT_DIR"
eval "$LAUNCHER $PROGRAM"
echo "END TIME: $(date)"
