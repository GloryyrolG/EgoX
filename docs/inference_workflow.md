# EgoX Inference 流程说明

流程参照 [EgoX-EgoPriorRenderer/README.md](../EgoX-EgoPriorRenderer/README.md)：先完成 ViPE 推理与 Ego Prior 渲染（及深度图转换），再运行 EgoX 主仓的 `infer.py`。

## 前置条件（参见 EgoX-EgoPriorRenderer README）

1. **ViPE 推理**（生成深度与位姿）
   ```bash
   cd EgoX-EgoPriorRenderer
   ./scripts/infer_vipe.sh   # 默认用 ironman: example/in_the_wild/videos/ironman/exo.mp4
   ```

2. **Ego Prior 渲染**（生成 ego_Prior.mp4）
   ```bash
   ./scripts/render_vipe.sh  # 需根据视频改 INPUT_DIR、META_JSON_PATH、OUT_DIR
   ```
   In-the-wild 需在 `vipe visualize ... --ego_manual` 中标注 ego 轨迹并更新 `meta.json` 中的 `ego_extrinsics`。

3. **深度图转 .npy**（GGA 推理需要）
   ```bash
   # in-the-wild 示例（按需改路径）
   python scripts/convert_depth_zip_to_npy.py \
     --depth_path vipe_results/YOUR_VIDEO/depth \
     --egox_depthmaps_path ../example/in_the_wild/depth_maps

   # H2O
   python scripts/convert_depth_zip_to_npy.py \
     --depth_path ./vipe_results/subject1_h1_0_cam0/depth \
     --egox_depthmaps_path ./processed/h2o/depth_maps
   ```

## EgoX 主仓推理

在 **EgoX 项目根目录** 执行 `infer.py`。

### 1. Ironman（in-the-wild）

- meta：`./example/in_the_wild/meta.json`，ironman 为第 2 条（idx=1）。
- 需有：`exo.mp4`、`ego_Prior.mp4`、以及 GGA 时对应的 depth_maps（见上）。

```bash
# 单条：Ironman（idx=1；idx=0 为 joker）
python infer.py \
  --meta_data_file ./example/in_the_wild/meta.json \
  --model_path ./checkpoints/pretrained_model/Wan2.1-I2V-14B-480P-Diffusers \
  --lora_path ./checkpoints/EgoX/pytorch_lora_weights.safetensors \
  --lora_rank 256 \
  --out ./results \
  --seed 846514 \
  --use_GGA \
  --cos_sim_scaling_factor 3.0 \
  --in_the_wild \
  --idx 1
```

### 2. H2O

- meta：`./EgoX-EgoPriorRenderer/processed/h2o/meta.json`。
- 需已跑完 H2O 的 ViPE + 渲染 + 深度转 npy（见 README 中 H2O 部分）。

```bash
python infer.py \
  --meta_data_file ./EgoX-EgoPriorRenderer/processed/h2o/meta.json \
  --model_path ./checkpoints/pretrained_model/Wan2.1-I2V-14B-480P-Diffusers \
  --lora_path ./checkpoints/EgoX/pytorch_lora_weights.safetensors \
  --lora_rank 256 \
  --out ./results/h2o \
  --use_GGA \
  --cos_sim_scaling_factor 3.0 \
  --idx 0
```

### 分辨率（num_frames × height × width）

脚本支持通过环境变量覆盖分辨率，便于快速测不同尺寸（如 25×256×704）：

```bash
# 快速小分辨率测试（25 帧，高 256，总宽 704）
NUM_FRAMES=25 HEIGHT=256 WIDTH=704 bash scripts/infer_itw.sh
NUM_FRAMES=25 HEIGHT=256 WIDTH=704 bash scripts/infer_h2o.sh

# 其他分辨率示例
NUM_FRAMES=49 HEIGHT=384 WIDTH=896 bash scripts/infer_itw.sh
```

默认：`num_frames=49`，`height=448`，`width=1232`（总宽 = exo + ego）。

### 常用参数

- `--idx`：跑 meta 中第几条（-1 表示全部）。
- `--use_GGA`：使用几何引导注意力（需 depth_maps 已转换好）。
- `--width` / `--height` / `--num_frames`：见上。

现有脚本对应关系：
- `scripts/infer_itw.sh`：in-the-wild，当前为 `--idx 0`（joker）；改 `--idx 1` 即跑 Ironman。
- H2O 可仿照上面命令写 `scripts/infer_h2o.sh`。
