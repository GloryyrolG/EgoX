#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_ROOT="${1:-/mnt/shared/envs}"

EGOX_ENV="$ENV_ROOT/egox"
EGO_PRIOR_ENV="$ENV_ROOT/egox-egoprior"
EGO_PRIOR_DIR="$ROOT_DIR/EgoX-EgoPriorRenderer"

if ! command -v conda >/dev/null 2>&1; then
  echo "Error: conda not found in PATH."
  exit 1
fi

mkdir -p "$ENV_ROOT"

echo "[1/6] Create EgoX env: $EGOX_ENV"
if [ ! -d "$EGOX_ENV" ]; then
  conda create -y -p "$EGOX_ENV" python=3.10
else
  echo "  - exists, skip create"
fi

echo "[2/6] Install EgoX deps"
"$EGOX_ENV/bin/pip" install torch torchvision --index-url https://download.pytorch.org/whl/cu121
"$EGOX_ENV/bin/pip" install -r "$ROOT_DIR/requirements.txt"
"$EGOX_ENV/bin/pip" install tensorboard

echo "[3/6] Create EgoPrior env: $EGO_PRIOR_ENV"
if [ ! -d "$EGO_PRIOR_ENV" ]; then
  conda env create -p "$EGO_PRIOR_ENV" -f "$EGO_PRIOR_DIR/envs/base.yml"
else
  echo "  - exists, skip create"
fi

echo "[4/6] Install EgoPrior base deps"
"$EGO_PRIOR_ENV/bin/pip" install -r "$EGO_PRIOR_DIR/envs/requirements.txt"

echo "[5/6] Install EgoPrior extras (pytorch3d, MoGe, editable package)"
CUDA_INCLUDE_DIR="$EGO_PRIOR_ENV/targets/x86_64-linux/include"
export CUDA_HOME="$EGO_PRIOR_ENV"
export CUDACXX="$EGO_PRIOR_ENV/bin/nvcc"
export CUB_HOME="$CUDA_INCLUDE_DIR"
export CPATH="$CUDA_INCLUDE_DIR:${CPATH:-}"

"$EGO_PRIOR_ENV/bin/pip" install "git+https://github.com/facebookresearch/pytorch3d.git@v0.7.9" --no-build-isolation
"$EGO_PRIOR_ENV/bin/pip" install "git+https://github.com/microsoft/MoGe.git"
"$EGO_PRIOR_ENV/bin/pip" install --no-build-isolation -e "$EGO_PRIOR_DIR"

echo "[6/6] Verify imports"
"$EGOX_ENV/bin/python" - <<'PY'
import torch, torchvision, diffusers, transformers, deepspeed
from torch.utils.tensorboard import SummaryWriter
print("EgoX OK:", torch.__version__, torchvision.__version__, "tensorboard", SummaryWriter.__name__)
PY

"$EGO_PRIOR_ENV/bin/python" - <<'PY'
import torch, torchvision, pytorch3d, vipe, moge
print("EgoPrior OK:", torch.__version__, torchvision.__version__, pytorch3d.__version__)
PY

cat <<EOF
Done.
Activate with:
  conda activate $EGOX_ENV
  conda activate $EGO_PRIOR_ENV
EOF
