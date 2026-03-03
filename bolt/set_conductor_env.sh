#!/bin/bash

# 使用 notarycli 动态获取凭证
curl --proto '=https' --tlsv1.2 -sSf https://pages.github.pie.apple.com/storage-orchestration/conductor/docs/setup-conductor.sh | bash
NOTARY_OUTPUT=$(notarycli issue -o conductor --audience=aprn:apple:turi::notary:application:conductor)

# 提取凭证并设置环境变量
export AWS_ACCESS_KEY_ID=$(echo "$NOTARY_OUTPUT" | jq -r '.AccessKeyId')
export AWS_SECRET_ACCESS_KEY=$(echo "$NOTARY_OUTPUT" | jq -r '.SecretAccessKey')
export AWS_SESSION_TOKEN=$(echo "$NOTARY_OUTPUT" | jq -r '.SessionToken // empty')

# 清除其他配置
unset AWS_PROFILE
unset AWS_SHARED_CREDENTIALS_FILE

echo "✓ Conductor credentials refreshed"
echo "Expires: $(echo "$NOTARY_OUTPUT" | jq -r '.Expiration')"

# 然后运行 conductor 命令
conductor s3 ls