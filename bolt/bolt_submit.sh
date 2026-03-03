#!/usr/bin/env bash
# bolt_submit.sh - 在 Apple VPN + Clash TUN 共存时安全提交 bolt task
# 原理：临时向 /etc/hosts 注入 Apple 内网域名的真实 IP（通过 Apple VPN DNS 查询）
#       bolt 运行结束后自动清理 /etc/hosts 条目

set -euo pipefail

HOSTS_FILE="/etc/hosts"
MARKER="# bolt-apple-vpn-temp"
APPLE_VPN_DNS="17.7.7.7"

# 需要解析的 Apple 内网域名（bolt submit 会用到）
APPLE_DOMAINS=(
    "bolt.apple.com"
    "conductor.data.apple.com"
)

cleanup() {
    echo "[bolt_submit] 清理 /etc/hosts 临时条目..."
    sudo sed -i '' "/$MARKER/d" "$HOSTS_FILE" 2>/dev/null || true
    echo "[bolt_submit] 清理完成"
}

inject_hosts() {
    echo "[bolt_submit] 查询 Apple VPN DNS (${APPLE_VPN_DNS}) 获取内网 IP..."
    local injected=0
    for domain in "${APPLE_DOMAINS[@]}"; do
        # 取第一个 IP（优先 17.x.x.x 范围，走 Apple VPN 路由）
        local ip
        ip=$(dig "$domain" "@${APPLE_VPN_DNS}" +short +time=5 2>/dev/null \
            | grep -E "^(10|17|100\.)\." | head -1)
        if [[ -n "$ip" ]]; then
            echo "[bolt_submit]   $domain -> $ip"
            echo "${ip}  ${domain}  ${MARKER}" | sudo tee -a "$HOSTS_FILE" > /dev/null
            ((injected++))
        else
            echo "[bolt_submit]   WARNING: 无法解析 $domain，Apple VPN 可能未连接"
        fi
    done

    if [[ $injected -eq 0 ]]; then
        echo "[bolt_submit] ERROR: 没有解析到任何 Apple 内网 IP"
        echo "[bolt_submit] 请确认 Apple Corporate VPN 已连接"
        exit 1
    fi
}

# 检查 Apple VPN 是否连接（utun4 上有 17.7.7.7 路由）
check_vpn() {
    if ! netstat -rn 2>/dev/null | grep -q "utun4"; then
        echo "[bolt_submit] WARNING: 未检测到 Apple VPN (utun4)，内网域名可能无法访问"
    else
        echo "[bolt_submit] Apple VPN (utun4) 已检测到 ✓"
    fi
}

# 主流程
trap cleanup EXIT INT TERM

check_vpn
inject_hosts

echo "[bolt_submit] 启动 bolt task submit..."
echo ""
conda run -n bolt bolt task submit "$@"
