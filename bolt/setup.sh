### Code
# mkdir -p tmp/code
# cd tmp/code
# git clone --recurse-submodules https://github.com/GloryyrolG/EgoX.git
# cd EgoX


### Env
# Install PyTorch with CUDA 12.1
pip3 install torch torchvision --index-url https://download.pytorch.org/whl/cu121

# Install other dependencies
pip install -r requirements.txt

pip install huggingface_hub


### Data
# mkdir -p tmp/data
# 首次运行：下载数据（重试时跳过）
# if [ ! -f "/mnt/shared/.data_ready" ]; then
#   echo "📥 首次运行：下载训练数据到 ScratchFS..."

#   # 从 Conductor 下载数据
#   conductor s3 cp s3://your-conductor-bucket/egox-dataset $DATA_DIR \
#     --recursive \
#     --endpoint-url https://conductor.data.apple.com

#   # 下载预训练模型
#   conductor s3 cp s3://your-conductor-bucket/models/pretrained.pt $PRETRAINED_DIR/ \
#     --endpoint-url https://conductor.data.apple.com

#   touch /mnt/shared/.data_ready
#   echo "✅ 数据下载完成"
# else
#   echo "✅ ScratchFS 中已有数据，跳过下载（节省时间）"
# fi


### Weights
# mkdir -p tmp/ckpts

# ln -s /mnt/task_runtime/tmp/ckpts/Wan2.1-I2V-14B-480P-Diffusers /mnt/task_runtime/tmp/code/checkpoints/pretrained_model/Wan2.1-I2V-14B-480P-Diffusers

