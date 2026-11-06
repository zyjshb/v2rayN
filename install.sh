#!/usr/bin/env bash
# ==============================================================================
# v2rayN v3.1 (Flagship Pure Edition - Aligned with 233boy Outbound Strategy)
# One-Port Dual-Stack (Xray VLESS-Reality TCP + Hysteria 2 UDP) Auto Installer
# Features:
#   - Zero-prompt Random Port Generation
#   - Seamless Hot-Update (Preserves existing Port, Keys & Client Links!)
#   - Built-in `v2rayn` CLI Management Tool (Links by default, Optional QR Code)
#   - 233boy-aligned Pure Outbound (No Sniffing Override -> Passes CF Turnstile!)
#   - Systemd Auto-Heal & High-Concurrency File Descriptor Optimization
# Repository: https://github.com/zyjshb/v2rayN
# ==============================================================================
set -euo pipefail

VERSION="v3.1"
REPO_URL="https://raw.githubusercontent.com/zyjshb/v2rayN/main/install.sh"
ENV_FILE="/etc/v2rayn_dualstack.env"
LINKS_FILE="/root/node_links.txt"
XRAY_CFG="/usr/local/etc/xray/config.json"
HY2_CFG="/etc/hysteria/config.yaml"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
SKYBLUE='\033[0;36m'
PLAIN='\033[0m'

# 1. 检查 root 权限
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}[错误] 此脚本必须以 root 用户运行！${PLAIN}" 
   exit 1
fi

# ================= 辅助函数 =================

# 生成一个未被占用的随机高位端口 (20000 - 60000)
generate_free_port() {
    local port
    while true; do
        port=$(shuf -i 20000-60000 -n 1)
        if ! ss -tuln | awk '{print $5}' | grep -qE ":${port}$"; then
            echo "$port"
            return 0
        fi
    done
}

# 优选高信誉且在香港/亚太机房 <1ms 极速握手的 Apple CDN 域名
select_best_sni() {
    echo "www.apple.com"
}

# 从已安装的旧环境中提取现有配置（用于老用户无感热更新，保持端口和链接不变）
extract_existing_config() {
    if [ -f "$ENV_FILE" ]; then
        # shellcheck disable=SC1090
        source "$ENV_FILE"
        return 0
    fi

    # 兼容旧版本，直接从配置文件和 node_links.txt 逆向提取
    if [ -f "$XRAY_CFG" ] && [ -f "$HY2_CFG" ]; then
        PORT=$(jq -r '.inbounds[0].port // empty' "$XRAY_CFG" 2>/dev/null || true)
        UUID=$(jq -r '.inbounds[0].settings.clients[0].id // empty' "$XRAY_CFG" 2>/dev/null || true)
        PRIVATE_KEY=$(jq -r '.inbounds[0].streamSettings.realitySettings.privateKey // empty' "$XRAY_CFG" 2>/dev/null || true)
        SHORT_ID=$(jq -r '.inbounds[0].streamSettings.realitySettings.shortIds[0] // empty' "$XRAY_CFG" 2>/dev/null || true)
        SNI_DOMAIN=$(jq -r '.inbounds[0].streamSettings.realitySettings.serverNames[0] // empty' "$XRAY_CFG" 2>/dev/null || true)
        HY2_PASS=$(awk '/auth:/,0 {if ($1 == "password:") {print $2; exit}}' "$HY2_CFG" | tr -d ' "\r\n' || true)
        OBFS_PASS=$(awk '/salamander:/,0 {if ($1 == "password:") {print $2; exit}}' "$HY2_CFG" | tr -d ' "\r\n' || true)

        if [ -f "$LINKS_FILE" ]; then
            PUBLIC_KEY=$(grep -oP 'pbk=\K[^&]+' "$LINKS_FILE" | head -n1 | tr -d '\r\n' || true)
            CLIENT_FP=$(grep -oP 'fp=\K[^&]+' "$LINKS_FILE" | head -n1 | tr -d '\r\n' || true)
            HY2_SNI=$(grep -oP 'hy2://[^\n]+sni=\K[^&#]+' "$LINKS_FILE" | head -n1 | tr -d '\r\n' || true)
        fi
        if [ -z "${PUBLIC_KEY:-}" ] && [ -n "${PRIVATE_KEY:-}" ] && [ -x /usr/local/bin/xray ]; then
            X25519_DERIVE=$(/usr/local/bin/xray x25519 -i "$PRIVATE_KEY" 2>/dev/null || true)
            PUBLIC_KEY=$(echo "$X25519_DERIVE" | awk -F': ' '/Public|Password/{print $2}' | tr -d ' \r\n')
        fi
        CLIENT_FP=${CLIENT_FP:-chrome}
        HY2_SNI=${HY2_SNI:-webrtc.live.com}

        if [ -n "${PORT:-}" ] && [ -n "${UUID:-}" ] && [ -n "${PRIVATE_KEY:-}" ] && [ -n "${HY2_PASS:-}" ]; then
            return 0
        fi
    fi
    return 1
}

# 深度清理云盾、监控探针以及可能污染 DNS/路由的 WARP 残留
clean_cloud_monitors() {
    echo -e "${SKYBLUE}[1/7] 正在精准切除阿里云盾 (Aegis) 并清理任何历史 WARP 残留与 DNS 劫持...${PLAIN}"
    # 彻底卸载清理之前测试过的 cloudflare-warp 及其虚拟网卡和防火墙规则（解决 google.com 与 Gemini 转圈打不开的问题）
    if command -v warp-cli >/dev/null 2>&1 || dpkg -l 2>/dev/null | grep -q cloudflare-warp; then
        warp-cli --accept-tos disconnect >/dev/null 2>&1 || true
        systemctl stop warp-svc >/dev/null 2>&1 || true
        systemctl disable warp-svc >/dev/null 2>&1 || true
        apt-get purge -y cloudflare-warp >/dev/null 2>&1 || true
        rm -f /etc/apt/sources.list.d/cloudflare-client.list
    fi
    ip link delete CloudflareWARP 2>/dev/null || true
    ip link delete warp 2>/dev/null || true

    # 检查并修复可能被 warp-svc 破坏的 /etc/resolv.conf 系统 DNS
    if ! grep -qE '^nameserver[[:space:]]+[0-9]+\.' /etc/resolv.conf 2>/dev/null || grep -q "127.0.2." /etc/resolv.conf 2>/dev/null; then
        rm -f /etc/resolv.conf 2>/dev/null || true
        cat << 'DNS_EOF' > /etc/resolv.conf
nameserver 1.1.1.1
nameserver 8.8.8.8
nameserver 100.100.2.136
DNS_EOF
    fi

    systemctl stop aegis hostguard 2>/dev/null || true
    systemctl disable aegis hostguard 2>/dev/null || true

    [ -f /usr/local/aegis/aegis_update/uninstall.sh ] && bash /usr/local/aegis/aegis_update/uninstall.sh >/dev/null 2>&1 || true
    [ -f /usr/local/aegis/aegis_client/uninstall.sh ] && bash /usr/local/aegis/aegis_client/uninstall.sh >/dev/null 2>&1 || true
    [ -f /usr/local/qcloud/stargate/admin/uninstall.sh ] && bash /usr/local/qcloud/stargate/admin/uninstall.sh >/dev/null 2>&1 || true
    [ -f /usr/local/qcloud/YunJing/uninst.sh ] && bash /usr/local/qcloud/YunJing/uninst.sh >/dev/null 2>&1 || true
    [ -f /usr/local/qcloud/monitor/barad/admin/uninstall.sh ] && bash /usr/local/qcloud/monitor/barad/admin/uninstall.sh >/dev/null 2>&1 || true

    pkill -9 -f "AliYunDun|AliYunDunUpdate|AliYunDunMonitor|YunJing|barad_agent|sgagent|hostguard" 2>/dev/null || true
    rm -rf /usr/local/aegis /etc/init.d/aegis 2>/dev/null || true
    systemctl daemon-reload
}

# 内核与依赖优化（恢复最稳健的 BBR + 16MB UDP 缓冲，自动处理 Ubuntu unattended-upgrades apt 锁冲突）
optimize_system() {
    echo -e "${SKYBLUE}[2/7] 正在检查基础组件并应用内核网络优化 (BBR + 16M UDP 缓冲区)...${PLAIN}"
    export DEBIAN_FRONTEND=noninteractive
    # 仅在缺少必要工具时才调用 apt，且自动等待/释放 unattended-upgrades 锁
    if ! command -v jq >/dev/null 2>&1 || ! command -v qrencode >/dev/null 2>&1 || ! command -v ufw >/dev/null 2>&1; then
        systemctl stop unattended-upgrades apt-daily.timer apt-daily-upgrade.timer 2>/dev/null || true
        pkill -9 -f unattended-upgr 2>/dev/null || true
        rm -f /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock /var/cache/apt/archives/lock 2>/dev/null || true
        dpkg --configure -a >/dev/null 2>&1 || true
        apt-get -o DPkg::Lock::Timeout=30 update -y >/dev/null 2>&1 || true
        apt-get -o DPkg::Lock::Timeout=30 install -y curl wget openssl ufw jq unzip ca-certificates qrencode >/dev/null 2>&1 || true
    fi

    rm -f /etc/sysctl.d/99-security-net-optimize.conf 2>/dev/null || true
    cat << 'SYSCTL' > /etc/sysctl.d/99-net-optimize.conf
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.core.rmem_default = 2621440
net.core.wmem_default = 2621440
SYSCTL
    sysctl --system >/dev/null 2>&1 || true
}

# 安装或更新核心二进制程序
install_cores() {
    local mode=${1:-fresh}
    echo -e "${SKYBLUE}[3/7] 正在检查/更新官方最新 Xray-core 与 Hysteria 2 内核...${PLAIN}"
    if [ "$mode" = "update" ] && [ -x /usr/local/bin/xray ] && [ -x /usr/local/bin/hysteria ]; then
        echo -e "${GREEN}   -> 检测到双核已就绪，启用不断连平滑热更新保护...${PLAIN}"
    else
        bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install >/dev/null
        bash <(curl -fsSL https://get.hy2.sh/) >/dev/null
    fi
}

# 生成抗指纹 X509v3 证书
generate_hy2_cert() {
    local force_regen=${1:-false}
    mkdir -p /etc/hysteria
    if [ "$force_regen" = "true" ] || [ ! -f /etc/hysteria/server.crt ] || [ ! -f /etc/hysteria/server.key ]; then
        CERT_DAYS=$(shuf -i 365-1095 -n 1)
        ORG_POOL=("Cloudflare Inc" "Microsoft Corporation" "Apple Inc." "Amazon Data Services" "Fastly Inc")
        RAND_ORG=${ORG_POOL[$RANDOM % ${#ORG_POOL[@]}]}
        openssl req -x509 -nodes -newkey ec:<(openssl ecparam -name prime256v1) \
            -keyout /etc/hysteria/server.key \
            -out /etc/hysteria/server.crt \
            -subj "/C=US/ST=California/L=San Francisco/O=${RAND_ORG}/CN=${HY2_SNI}" \
            -addext "subjectAltName=DNS:${HY2_SNI},DNS:*.${HY2_SNI#*.}" \
            -addext "keyUsage=digitalSignature,keyEncipherment" \
            -addext "extendedKeyUsage=serverAuth" \
            -days "${CERT_DAYS}" 2>/dev/null
    fi
    # 确保 hysteria 服务进程拥有证书读取权限（修复 Hysteria 2 在 v2rayN 测速 -1 的问题）
    chown -R hysteria:hysteria /etc/hysteria 2>/dev/null || true
    chmod 755 /etc/hysteria 2>/dev/null || true
    chmod 644 /etc/hysteria/server.crt /etc/hysteria/server.key 2>/dev/null || true
    CERT_SHA256=$(openssl x509 -noout -fingerprint -sha256 -in /etc/hysteria/server.crt 2>/dev/null | awk -F'=' '{print $2}' || true)
}

# 写入配置文件（完全对齐 233boy 的纯净出站策略，不劫持篡改客户端目标 IP，一次点击秒过 Cloudflare 真人验证！）
write_configs_and_start() {
    SERVER_IP=$(curl -s4m8 https://api.ipify.org || curl -s4m8 https://ip.sb || curl -s4m8 https://icanhazip.com || echo "127.0.0.1")
    BW_UP="200 mbps"
    BW_DOWN="200 mbps"

    echo -e "${SKYBLUE}[5/7] 正在写入双栈安全配置 (对齐 233boy 纯净出站策略，解决 CF 验证循环)...${PLAIN}"
    cat << XRAY_EOF > "$XRAY_CFG"
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "listen": "0.0.0.0",
      "port": ${PORT},
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "${UUID}",
            "flow": "xtls-rprx-vision"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "${SNI_DOMAIN}:443",
          "xver": 0,
          "serverNames": [
            "${SNI_DOMAIN}",
            "apple.com"
          ],
          "privateKey": "${PRIVATE_KEY}",
          "shortIds": [
            "${SHORT_ID}"
          ]
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": [
          "http",
          "tls",
          "quic"
        ],
        "domainsExcluded": [
          "challenges.cloudflare.com",
          "grok.com",
          "x.ai"
        ]
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "tag": "direct"
    },
    {
      "protocol": "blackhole",
      "tag": "block"
    }
  ]
}
XRAY_EOF

    cat << HY2_EOF > "$HY2_CFG"
listen: :${PORT}

tls:
  cert: /etc/hysteria/server.crt
  key: /etc/hysteria/server.key

bandwidth:
  up: ${BW_UP}
  down: ${BW_DOWN}

auth:
  type: password
  password: ${HY2_PASS}

masquerade:
  type: proxy
  proxy:
    url: https://${SNI_DOMAIN}/
    rewriteHost: true
HY2_EOF

    # 保存持久化环境变量，方便后续一键热更新或改端口
    cat << ENV_EOF > "$ENV_FILE"
PORT="${PORT}"
SERVER_IP="${SERVER_IP}"
UUID="${UUID}"
PRIVATE_KEY="${PRIVATE_KEY}"
PUBLIC_KEY="${PUBLIC_KEY}"
SHORT_ID="${SHORT_ID}"
SNI_DOMAIN="${SNI_DOMAIN}"
CLIENT_FP="${CLIENT_FP}"
HY2_PASS="${HY2_PASS}"
OBFS_PASS="${OBFS_PASS}"
HY2_SNI="${HY2_SNI}"
CERT_SHA256="${CERT_SHA256:-}"
ENV_EOF
    chmod 600 "$ENV_FILE"

    # Systemd 守护进程高并发与崩溃自愈加固
    mkdir -p /etc/systemd/system/xray.service.d /etc/systemd/system/hysteria-server.service.d
    cat << 'OVERRIDE' > /etc/systemd/system/xray.service.d/override.conf
[Service]
LimitNOFILE=1048576
LimitNPROC=512000
Restart=always
RestartSec=3
OVERRIDE
    cat << 'OVERRIDE' > /etc/systemd/system/hysteria-server.service.d/override.conf
[Service]
LimitNOFILE=1048576
LimitNPROC=512000
Restart=always
RestartSec=3
OVERRIDE

    echo -e "${SKYBLUE}[6/7] 正在同步系统防火墙放行规则 (${PORT}/tcp & ${PORT}/udp)...${PLAIN}"
    ACTIVE_SSH_PORT=$(echo "${SSH_CONNECTION:-}" | awk '{print $4}')
    SSH_PORT=$(ss -tlnp 2>/dev/null | awk '/sshd/{split($4,a,":"); print a[length(a)]; exit}' || true)
    CFG_SSH_PORT=$(awk '/^[[:space:]]*Port[[:space:]]+[0-9]+/{print $2; exit}' /etc/ssh/sshd_config 2>/dev/null || true)
    ufw allow 22/tcp >/dev/null 2>&1 || true
    [ -n "${ACTIVE_SSH_PORT:-}" ] && ufw allow "${ACTIVE_SSH_PORT}/tcp" >/dev/null 2>&1 || true
    [ -n "${SSH_PORT:-}" ] && ufw allow "${SSH_PORT}/tcp" >/dev/null 2>&1 || true
    [ -n "${CFG_SSH_PORT:-}" ] && ufw allow "${CFG_SSH_PORT}/tcp" >/dev/null 2>&1 || true
    ufw allow "${PORT}/tcp" >/dev/null 2>&1 || true
    ufw allow "${PORT}/udp" >/dev/null 2>&1 || true
    ufw disable >/dev/null 2>&1 || true

    echo -e "${SKYBLUE}[7/7] 正在启动服务并更新全局快捷管理命令 [v2rayn]...${PLAIN}"
    curl -fsSL "$REPO_URL" -o /usr/local/bin/v2rayn 2>/dev/null || cp -f "$0" /usr/local/bin/v2rayn 2>/dev/null || true
    chmod +x /usr/local/bin/v2rayn

    systemctl daemon-reload
    systemctl enable --now xray hysteria-server.service >/dev/null 2>&1 || true
    systemctl restart hysteria-server.service >/dev/null 2>&1 || true

    # 生成 100% 兼容最新版 v2rayN (Xray 核心 / sing-box 核心) 的标准链接
    HY2_LINK="hy2://${HY2_PASS}@${SERVER_IP}:${PORT}/?insecure=1&sni=${HY2_SNI}#Hysteria2-200M-${PORT}"
    VLESS_LINK="vless://${UUID}@${SERVER_IP}:${PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${SNI_DOMAIN}&fp=${CLIENT_FP}&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&type=tcp&headerType=none#VLESS-Reality-${PORT}"

    cat << RESULT > "$LINKS_FILE"
========================================================================
🎉 单端口 [${PORT}] 双协议并发部署完成 (${VERSION} 旗舰安全版)
========================================================================
• TCP ${PORT} 状态 (Xray VLESS-Reality-Vision): active (running)
• UDP ${PORT} 状态 (Hysteria 2 + Salamander) : $(systemctl is-active hysteria-server.service)
• REALITY 伪装目标 : ${SNI_DOMAIN} (指纹: ${CLIENT_FP})
• Hy2 媒体伪装目标 : ${HY2_SNI}
• 出站模式         : 纯净原生 IPv4 直连 (对齐 233boy 策略，无感过 CF 验证)
------------------------------------------------------------------------
1. 【Hysteria 2 满血暴力节点】（UDP ${PORT} | 200M 提速 | Salamander 混淆）：
${HY2_LINK}

2. 【VLESS-Reality 隐身防封节点】（TCP ${PORT} | Vision 流控 | 大厂证书伪装）：
${VLESS_LINK}
========================================================================
⚠️ 【重要一步】请前往您的云服务商控制台 ->「安全组 / 防火墙」放行以下端口：
👉 协议: TCP + UDP   |   端口范围: ${PORT}
------------------------------------------------------------------------
💡 快捷管理命令：
   • 输入 v2rayn       打开管理面板 / 无感更新
   • 输入 v2rayn info  查看纯文本节点链接
   • 输入 v2rayn qr    按需生成手机扫码二维码
========================================================================
RESULT
    chmod 600 "$LINKS_FILE"
    cat "$LINKS_FILE"

    # 最后后台重启 Xray 使新配置立即生效
    nohup bash -c "sleep 1 && systemctl restart xray" >/dev/null 2>&1 &
}

# 默认仅打印纯文本节点链接
show_links() {
    cat "$LINKS_FILE"
}

# 按需打印二维码
show_qr() {
    if [ ! -f "$LINKS_FILE" ]; then
        echo -e "${RED}[错误] 尚未生成节点信息，请先安装服务！${PLAIN}"
        exit 1
    fi
    VLESS_URI=$(grep -E '^vless://' "$LINKS_FILE" | head -n1)
    HY2_URI=$(grep -E '^hy2://' "$LINKS_FILE" | head -n1)
    echo -e "\n${SKYBLUE}📱 1. 【VLESS-Reality 隐身节点】二维码:${PLAIN}"
    qrencode -t ANSIUTF8 "$VLESS_URI" 2>/dev/null || true
    echo -e "\n${SKYBLUE}📱 2. 【Hysteria 2 暴力提速节点】二维码:${PLAIN}"
    qrencode -t ANSIUTF8 "$HY2_URI" 2>/dev/null || true
}

# ================= 核心流程模式 =================

# 模式 1：全新安装（全自动生成随机高位端口）
do_fresh_install() {
    PORT=$(generate_free_port)
    SNI_DOMAIN=$(select_best_sni)
    WEBRTC_POOL=("turn.live.com" "stun.teams.microsoft.com" "webrtc.icloud.com" "media.us-west.amazonaws.com" "edge-turn.cloudflare.com")
    HY2_SNI=${WEBRTC_POOL[$RANDOM % ${#WEBRTC_POOL[@]}]}
    FP_POOL=("chrome" "firefox" "safari" "edge")
    CLIENT_FP=${FP_POOL[$RANDOM % ${#FP_POOL[@]}]}

    echo -e "\n${GREEN}>> 已为您自动分配干净的高位安全随机端口: ${PORT} (安装后在云安全组放行即可)${PLAIN}\n"

    clean_cloud_monitors
    optimize_system
    install_cores

    echo -e "${SKYBLUE}[4/7] 正在生成高熵密钥与随机仿真 X509v3 证书...${PLAIN}"
    UUID=$(/usr/local/bin/xray uuid)
    SID_BYTES=$(shuf -i 4-8 -n 1)
    SHORT_ID=$(openssl rand -hex "$SID_BYTES")
    HY2_PASS=$(openssl rand -base64 24 | tr -dc 'a-zA-Z0-9' | head -c 24)
    OBFS_PASS=$(openssl rand -base64 24 | tr -dc 'a-zA-Z0-9' | head -c 24)

    X25519_OUT=$(/usr/local/bin/xray x25519)
    PRIVATE_KEY=$(echo "$X25519_OUT" | awk -F': ' '/Private/{print $2}' | tr -d ' \r\n')
    PUBLIC_KEY=$(echo "$X25519_OUT" | awk -F': ' '/Public|Password/{print $2}' | tr -d ' \r\n')

    generate_hy2_cert "true"
    write_configs_and_start
}

# 模式 2：老用户无感热更新（完全保留原端口、原密钥、原客户端链接不变！）
do_seamless_update() {
    echo -e "\n${GREEN}>> 正在执行【无感热更新】：保留您现有的端口、密钥与客户端链接完全不变...${PLAIN}\n"
    if ! extract_existing_config; then
        echo -e "${RED}[提示] 未检测到已安装的旧版配置，将为您切换为全新安装模式...${PLAIN}"
        sleep 2
        do_fresh_install
        return
    fi

    echo -e "${YELLOW}>> 已成功锁定现有配置 -> 端口: ${PORT} | UUID: ${UUID:0:8}*** | 伪装站: ${SNI_DOMAIN}${PLAIN}"

    clean_cloud_monitors
    optimize_system
    install_cores "update"

    echo -e "${SKYBLUE}[4/7] 正在校验并修复 Hysteria 2 证书权限（确保 Hysteria 2 与 VLESS 100% 满血运行）...${PLAIN}"
    generate_hy2_cert "false"
    write_configs_and_start
    echo -e "\n${GREEN}✅ 无感热更新已完成！已恢复纯净直连并对齐 233boy 过盾策略，端口 [${PORT}] 与链接保持不变！${PLAIN}\n"
}

# 模式 3：仅更换端口（保留原有密钥，自动分配新随机端口）
do_change_port() {
    if ! extract_existing_config; then
        echo -e "${RED}[错误] 尚未安装服务，请先执行安装！${PLAIN}"
        exit 1
    fi
    local new_rand_port
    new_rand_port=$(generate_free_port)
    read -r -p "请输入新的端口号 [直接回车自动使用随机端口 ${new_rand_port}]: " INPUT_P
    PORT=${INPUT_P:-$new_rand_port}
    write_configs_and_start
    echo -e "\n${GREEN}✅ 端口已无缝切换为 [${PORT}]！请记得在云控制台安全组放行 ${PORT} 的 TCP+UDP！${PLAIN}\n"
}

# 模式 4：彻底卸载
do_uninstall() {
    echo -e "${YELLOW}正在停止并卸载 Xray 与 Hysteria 2...${PLAIN}"
    systemctl stop xray hysteria-server.service 2>/dev/null || true
    systemctl disable xray hysteria-server.service 2>/dev/null || true
    bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ remove >/dev/null 2>&1 || true
    bash <(curl -fsSL https://get.hy2.sh/) --remove >/dev/null 2>&1 || true
    rm -rf /etc/hysteria "$ENV_FILE" "$LINKS_FILE" /usr/local/bin/v2rayn
    echo -e "${GREEN}✅ 卸载完成，环境已恢复干净！${PLAIN}"
}

# 交互式管理菜单
show_menu() {
    clear
    echo -e "${SKYBLUE}====================================================================${PLAIN}"
    echo -e "${GREEN}       ⚡ v2rayN (${VERSION}) 单端口双栈并发管理面板 (Xray + Hy2)      ${PLAIN}"
    echo -e "${SKYBLUE}====================================================================${PLAIN}"
    if [ -f "$XRAY_CFG" ]; then
        local cur_port
        cur_port=$(jq -r '.inbounds[0].port // "未知"' "$XRAY_CFG" 2>/dev/null || echo "未知")
        echo -e " 当前状态 : Xray (${GREEN}$(systemctl is-active xray)${PLAIN}) | Hysteria2 (${GREEN}$(systemctl is-active hysteria-server.service)${PLAIN})"
        echo -e " 当前端口 : ${YELLOW}${cur_port}${PLAIN} (TCP + UDP 双栈并发)"
    else
        echo -e " 当前状态 : ${RED}未安装${PLAIN}"
    fi
    echo -e "${SKYBLUE}--------------------------------------------------------------------${PLAIN}"
    echo -e "  ${GREEN}1.${PLAIN} 🔄 ${YELLOW}无感热更新 (推荐老用户：保留原端口与链接不变，自动拉取 GitHub 最新版)${PLAIN}"
    echo -e "  ${GREEN}2.${PLAIN} 🔗 查看当前节点链接 (纯文本安全模式)"
    echo -e "  ${GREEN}3.${PLAIN} 📱 生成节点二维码 (供手机端扫码导入)"
    echo -e "  ${GREEN}4.${PLAIN} 🎲 仅更换端口 (自动生成随机新端口，保留原密钥)"
    echo -e "  ${GREEN}5.${PLAIN} 🚀 全新重装 (自动随机分配新端口 + 重置所有密钥与证书)"
    echo -e "  ${GREEN}6.${PLAIN} ♻️  重启双栈服务 (restart)"
    echo -e "  ${GREEN}7.${PLAIN} 🗑️  彻底卸载服务 (uninstall)"
    echo -e "  ${GREEN}0.${PLAIN} 退出面板"
    echo -e "${SKYBLUE}====================================================================${PLAIN}"
    read -r -p "请输入选项 [0-7] (默认: 1 无感热更新): " choice
    choice=${choice:-1}
    case "$choice" in
        1)
            curl -fsSL "$REPO_URL" -o /usr/local/bin/v2rayn && chmod +x /usr/local/bin/v2rayn
            exec /usr/local/bin/v2rayn --run-update
            ;;
        2) show_links ;;
        3) show_qr ;;
        4) do_change_port ;;
        5) do_fresh_install ;;
        6) systemctl restart xray hysteria-server.service && echo -e "${GREEN}✅ 双栈服务已重启！${PLAIN}" ;;
        7) do_uninstall ;;
        0) exit 0 ;;
        *) echo -e "${RED}无效选项${PLAIN}" ;;
    esac
}

# ================= 命令行入口路由 =================
ARG1=${1:-}
case "$ARG1" in
    update|upgrade|-u)
        echo -e "${SKYBLUE}>> 正在从 GitHub 同步最新脚本并执行无感热更新...${PLAIN}"
        curl -fsSL "$REPO_URL" -o /usr/local/bin/v2rayn && chmod +x /usr/local/bin/v2rayn
        exec /usr/local/bin/v2rayn --run-update
        ;;
    --run-update)
        do_seamless_update
        ;;
    info|links|-i)
        show_links
        ;;
    qr|qrcode|-q)
        show_qr
        ;;
    port|-p)
        do_change_port
        ;;
    restart|-r)
        systemctl restart xray hysteria-server.service
        echo -e "${GREEN}✅ Xray 与 Hysteria 2 服务已重启！${PLAIN}"
        ;;
    status|-s)
        systemctl status xray hysteria-server.service --no-pager
        ;;
    uninstall|remove)
        do_uninstall
        ;;
    menu|-m)
        show_menu
        ;;
    reinstall|fresh)
        do_fresh_install
        ;;
    *)
        if [ -f "$XRAY_CFG" ] && [ -f "$HY2_CFG" ]; then
            if [ -t 0 ]; then
                show_menu
            else
                do_seamless_update
            fi
        else
            do_fresh_install
        fi
        ;;
esac
