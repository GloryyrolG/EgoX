#!/bin/bash
# 用 screen 后台跑 overfit finetune，断 SSH 不掉；日志 tee 到 logs/。无 screen 时退化为 nohup。
# Usage: cd repo_root && bash scripts/run_finetune_overfit_background.sh
#  可选: TRAIN_STEPS=500 CHECKPOINTING_STEPS=500 bash scripts/run_finetune_overfit_background.sh
#  TB: 脚本里 --report_to tensorboard，需先 pip install tensorboard；logdir 为 OUTPUT_DIR（默认 results/EgoX_h2o_overfit）

set -e
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"
mkdir -p logs

LOG="logs/finetune_h2o_overfit_$(date +%Y%m%d_%H%M%S).log"
SESSION_NAME="egox_overfit"

# 显式传入环境变量，避免 screen 子 shell 未继承
RUN_CMD="cd $REPO_ROOT && FAST_OVERFIT='$FAST_OVERFIT' RESUME_FROM_CHECKPOINT='$RESUME_FROM_CHECKPOINT' TRAIN_STEPS='$TRAIN_STEPS' CHECKPOINTING_STEPS='$CHECKPOINTING_STEPS' OUTPUT_DIR='$OUTPUT_DIR' bash scripts/finetune_h2o_overfit.sh 2>&1 | tee $LOG"

if command -v screen &>/dev/null; then
    if screen -ls 2>/dev/null | grep -q "\.$SESSION_NAME "; then
        echo "screen session $SESSION_NAME already exists. Attach: screen -r $SESSION_NAME"
        echo "Or kill: screen -S $SESSION_NAME -X quit"
        exit 1
    fi
    echo "Starting screen session: $SESSION_NAME | log: $LOG"
    echo "Attach: screen -r $SESSION_NAME   Detach: Ctrl+A then D"
    screen -S "$SESSION_NAME" -dm bash -c "$RUN_CMD"
else
    echo "screen not found, using nohup. Log: $LOG"
    nohup bash -c "$RUN_CMD" </dev/null &>/dev/null &
    echo "PID: $!  |  tail -f $LOG  # follow log"
fi
echo "Done."
