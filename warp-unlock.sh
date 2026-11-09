#!/usr/bin/env bash
# ==============================================================================
# v2rayN - Instagram / 流媒体纯净日本出口一键解锁工具 (Cloudflare WARP Socks5)
# 作用: 保持服务器千兆直连速度不变，仅将 Instagram/Meta 流量分流至纯正日本出口
# ==============================================================================
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
SKYBLUE='\033[0;36m'
PLAIN='\033[0m'

if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}[错误] 必须以 root 用户运行！${PLAIN}" 
   exit 1
fi

echo -e "${SKYBLUE}================================================================${PLAIN}"
echo -e "${GREEN}   正在为服务器注入 Cloudflare 日本官方纯净出口 (解锁 Ins 音乐库)...${PLAIN}"
echo -e "${SKYBLUE}================================================================${PLAIN}"

# 1. 安装 Cloudflare 官方客户端
export DEBIAN_FRONTEND=noninteractive
if ! command -v warp-cli >/dev/null 2>&1; then
    echo -e "${YELLOW}[1/4] 正在配置 Cloudflare 官方软件源...${PLAIN}"
    mkdir -p /usr/share/keyrings /etc/apt/sources.list.d
    curl -fsSL https://pkg.cloudflareclient.com/pubkey.gpg | gpg --yes --dearmor --output /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] https://pkg.cloudflareclient.com/ $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/cloudflare-client.list
    apt-get update -y >/dev/null 2>&1 || true
    apt-get install -y cloudflare-warp >/dev/null 2>&1 || true
fi

# 2. 配置为本地 Socks5 专用代理模式 (端口 40000，零影响系统网络和 SSH)
echo -e "${YELLOW}[2/4] 正在配置本地独立代理通道 (127.0.0.1:40000)...${PLAIN}"
warp-cli --accept-tos disconnect >/dev/null 2>&1 || true
warp-cli --accept-tos registration new >/dev/null 2>&1 || warp-cli --accept-tos register >/dev/null 2>&1 || true
warp-cli --accept-tos mode proxy >/dev/null 2>&1 || warp-cli --accept-tos set-mode proxy >/dev/null 2>&1 || true
warp-cli --accept-tos proxy port 40000 >/dev/null 2>&1 || warp-cli --accept-tos set-proxy-port 40000 >/dev/null 2>&1 || true
warp-cli --accept-tos connect >/dev/null 2>&1 || true

sleep 3

# 3. 校验出口状态
echo -e "${YELLOW}[3/4] 正在验证 Cloudflare 日本出口连通性...${PLAIN}"
TRACE=$(curl -s4m6 -x socks5h://127.0.0.1:40000 https://www.cloudflare.com/cdn-cgi/trace || true)
if echo "$TRACE" | grep -q "warp=on"; then
    COLO=$(echo "$TRACE" | awk -F= '/colo/{print $2}')
    LOC=$(echo "$TRACE" | awk -F= '/loc/{print $2}')
    echo -e "${GREEN}   -> Cloudflare 纯净通道已接通！地区: ${LOC} (${COLO})${PLAIN}"
else
    echo -e "${YELLOW}   -> 正在等待通道预热...${PLAIN}"
    sleep 2
fi

# 4. 注入 Hysteria 2 分流规则
HY2_CFG="/etc/hysteria/config.yaml"
if [ -f "$HY2_CFG" ]; then
    echo -e "${YELLOW}[4/4] 正在将 Instagram 流量精准挂载到纯净日本通道...${PLAIN}"
    # 清理历史可能重复的 outbounds 和 acl
    sed -i '/^outbounds:/,$d' "$HY2_CFG"
    
    cat << 'HY2_APPEND' >> "$HY2_CFG"

outbounds:
  - name: direct
    type: direct
  - name: warp
    type: socks5
    socks5:
      addr: 127.0.0.1:40000

acl:
  inline:
    - warp(suffix:instagram.com)
    - warp(suffix:cdninstagram.com)
    - warp(suffix:threads.net)
    - warp(suffix:facebook.com)
    - warp(suffix:fbcdn.net)
    - direct(all)
HY2_APPEND

    systemctl restart hysteria-server
    echo -e "${GREEN}   -> Hysteria 2 服务已完成智能分流重载！${PLAIN}"
fi

# 5. 现场验证 Instagram 国家识别码
echo "----------------------------------------------------------------"
echo -e "${SKYBLUE}【现场验证 Instagram 官方数据库国家识别码】${PLAIN}"
IG_CODE=$(curl -sL --compressed -x socks5h://127.0.0.1:40000 -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36" "https://www.instagram.com/" | grep -o '"country_code":"[^"]*"' || echo '"country_code":"未知"')
echo -e " 目标网站: Instagram"
echo -e " 识别结果: ${GREEN}${IG_CODE}${PLAIN}"
echo "----------------------------------------------------------------"
if echo "$IG_CODE" | grep -qi "JP"; then
    echo -e "${GREEN}🎉 恭喜！Instagram 官方识别已 100% 变更为纯正日本 (JP)！${PLAIN}"
    echo -e "${GREEN}👉 手机上彻底关闭 Instagram App 重新打开，音乐曲库立即满血解锁！${PLAIN}"
else
    echo -e "${YELLOW}识别码为: ${IG_CODE}，请在手机上重新打开 Instagram 查看音乐库！${PLAIN}"
fi
echo "================================================================"
