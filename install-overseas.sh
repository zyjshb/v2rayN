#!/usr/bin/env bash
# ==============================================================================
# v2rayN - 海外主流 VPS 厂商特调版 (RackNerd / DMIT / 搬瓦工 / Claw / Akile / Vultr 等)
# Specialized Flagship Edition for Overseas VPS Providers
# 
# 核心特调优化：
# 1. 狂暴满血 Brutal 拥塞控制：满血支持 1Gbps~2.5Gbps 大端口，暴力发包直接碾碎晚高峰跨洋丢包
# 2. 高 BDP 跨洋长肥管道调优：内核 TCP/UDP 缓冲区放宽至 32M~64M，开启 TCP Fast Open 与 FQ+BBR
# 3. 极速纯净出站：完全解除连接并发限制 (LimitNOFILE=1048576, somaxconn=65535)，从容应对海量并发
# 4. 原生流媒体与 AI 支持：保留原生 IPv4/IPv6 双栈优化与全球公共权威 DNS，完美直达 ChatGPT/Grok
# 5. 秒级极速构建：系统干净无流氓组件，30 秒全自动化部署就绪
# 
# Repository: https://github.com/zyjshb/v2rayN
# ==============================================================================
set -euo pipefail

EDITION="海外主流 VPS 特调版 (千兆狂暴·高吞吐·无视晚高峰跨洋丢包版)"
EDITION_TAG="OVERSEAS_GIGA"
VERSION="v3.2"
REPO_BASE="https://raw.githubusercontent.com/zyjshb/v2rayN/main"
ENV_FILE="/etc/v2rayn_dualstack.env"
LINKS_FILE="/root/node_links.txt"
XRAY_CFG="/usr/local/etc/xray/config.json"
HY2_CFG="/etc/hysteria/config.yaml"

# 终端色彩
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
SKYBLUE='\033[0;36m'
PURPLE='\033[0;35m'
PLAIN='\033[0m'

# 权限校验
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}[错误] 此脚本必须以 root 用户运行！${PLAIN}" 
   exit 1
fi

# 随机高位可用端口 (20000 - 60000)
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

# 提取已有配置（老用户热更新无感保留）
extract_existing_config() {
    local target_tag="$EDITION_TAG"
    if [ -f "$ENV_FILE" ]; then
        # shellcheck disable=SC1090
        source "$ENV_FILE"
        EDITION_TAG="$target_tag"
        SNI_DOMAIN="www.microsoft.com"
        CLIENT_FP="chrome"
        HY2_SNI=${HY2_SNI:-turn.live.com}
        if [ -n "${PORT:-}" ] && [ -n "${UUID:-}" ] && [ -n "${PRIVATE_KEY:-}" ] && [ -n "${PUBLIC_KEY:-}" ] && [ -n "${HY2_PASS:-}" ]; then
            return 0
        fi
    fi

    if [ -f "$XRAY_CFG" ] && [ -f "$HY2_CFG" ]; then
        PORT=$(jq -r '.inbounds[0].port // empty' "$XRAY_CFG" 2>/dev/null || true)
        UUID=$(jq -r '.inbounds[0].settings.clients[0].id // empty' "$XRAY_CFG" 2>/dev/null || true)
        PRIVATE_KEY=$(jq -r '.inbounds[0].streamSettings.realitySettings.privateKey // empty' "$XRAY_CFG" 2>/dev/null || true)
        SHORT_ID=$(jq -r '.inbounds[0].streamSettings.realitySettings.shortIds[0] // empty' "$XRAY_CFG" 2>/dev/null || true)
        SNI_DOMAIN="www.microsoft.com"
        HY2_PASS=$(awk '/auth:/,0 {if ($1 == "password:") {print $2; exit}}' "$HY2_CFG" | tr -d ' "\r\n' || true)

        if [ -f "$LINKS_FILE" ]; then
            PUBLIC_KEY=$(grep -oP 'pbk=\K[^&]+' "$LINKS_FILE" | head -n1 | tr -d '\r\n' || true)
            HY2_SNI=$(grep -oP 'hy2://[^\n]+sni=\K[^&#]+' "$LINKS_FILE" | head -n1 | tr -d '\r\n' || true)
        fi
        if [ -z "${PUBLIC_KEY:-}" ] && [ -n "${PRIVATE_KEY:-}" ] && [ -x /usr/local/bin/xray ]; then
            X25519_DERIVE=$(/usr/local/bin/xray x25519 -i "$PRIVATE_KEY" 2>/dev/null || true)
            PUBLIC_KEY=$(echo "$X25519_DERIVE" | awk -F': ' '/Public|Password/{print $2}' | tr -d ' \r\n')
        fi
        EDITION_TAG="$target_tag"
        CLIENT_FP="chrome"
        HY2_SNI=${HY2_SNI:-turn.live.com}

        if [ -n "${PORT:-}" ] && [ -n "${UUID:-}" ] && [ -n "${PRIVATE_KEY:-}" ] && [ -n "${PUBLIC_KEY:-}" ] && [ -n "${HY2_PASS:-}" ]; then
            return 0
        fi
    fi
    return 1
}

# 基础环境与 DNS 优化
setup_network_env() {
    echo -e "${SKYBLUE}[1/7] 正在初始化海外纯净网络环境与全球权威 DNS 解析...${PLAIN}"
    # 强制启用 Google + Cloudflare 原生双栈权威解析
    rm -f /etc/resolv.conf 2>/dev/null || true
    cat << 'DNS_EOF' > /etc/resolv.conf
nameserver 1.1.1.1
nameserver 8.8.8.8
nameserver 2606:4700:4700::1111
nameserver 2001:4860:4860::8888
DNS_EOF
}

# 高 BDP 跨洋长管道内核与极端并发网络栈优化（支持小内存海外 VPS 动态自适应）
optimize_overseas_kernel() {
    echo -e "${SKYBLUE}[2/7] 正在应用千兆满血高吞吐内核参数 (BBR + FQ + 智能分级缓冲 + TCP FastOpen)...${PLAIN}"
    export DEBIAN_FRONTEND=noninteractive

    # 安装基础依赖
    if ! command -v jq >/dev/null 2>&1 || ! command -v qrencode >/dev/null 2>&1 || ! command -v ufw >/dev/null 2>&1; then
        systemctl stop unattended-upgrades apt-daily.timer apt-daily-upgrade.timer 2>/dev/null || true
        pkill -9 -f unattended-upgr 2>/dev/null || true
        rm -f /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock /var/cache/apt/archives/lock 2>/dev/null || true
        dpkg --configure -a >/dev/null 2>&1 || true
        apt-get -o DPkg::Lock::Timeout=30 update -y >/dev/null 2>&1 || true
        apt-get -o DPkg::Lock::Timeout=30 install -y curl wget openssl ufw jq unzip ca-certificates qrencode >/dev/null 2>&1 || true
    fi

    # 针对海外小内存 VPS (如 512M/1G RackNerd/Claw/Akile) 自动补充 Swap 并动态调整内核缓冲，严防 TCP 内存压力锁死
    local total_ram total_swap rmem_max tcp_max
    total_ram=$(free -m | awk '/Mem:/{print $2}')
    total_swap=$(free -m | awk '/Swap:/{print $2}')
    if [ "$total_ram" -le 1200 ]; then
        rmem_max=16777216
        tcp_max=16777216
        if [ "$total_swap" -lt 512 ]; then
            echo -e "${YELLOW}   -> 检测到海外 VPS 物理内存为 ${total_ram}MB，自动挂载 1GB Swap 防止高并发 OOM...${PLAIN}"
            swapoff /swapfile 2>/dev/null || true
            dd if=/dev/zero of=/swapfile bs=1M count=1024 status=none 2>/dev/null || true
            chmod 600 /swapfile
            mkswap /swapfile >/dev/null 2>&1 || true
            swapon /swapfile 2>/dev/null || true
            if ! grep -q '/swapfile' /etc/fstab 2>/dev/null; then
                echo '/swapfile none swap sw 0 0' >> /etc/fstab
            fi
        fi
    else
        rmem_max=67108864
        tcp_max=33554432
    fi

    rm -f /etc/sysctl.d/99-*.conf 2>/dev/null || true
    cat << SYSCTL > /etc/sysctl.d/99-overseas-giga-optimize.conf
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.core.rmem_max = ${rmem_max}
net.core.wmem_max = ${rmem_max}
net.core.rmem_default = 4194304
net.core.wmem_default = 4194304
net.ipv4.tcp_rmem = 4096 87380 ${tcp_max}
net.ipv4.tcp_wmem = 4096 65536 ${tcp_max}
net.core.netdev_max_backlog = 100000
net.core.somaxconn = 65535
net.ipv4.tcp_max_syn_backlog = 3240000
net.ipv4.tcp_max_tw_buckets = 1440000
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_slow_start_after_idle = 0
fs.file-max = 2097152
vm.swappiness = 10
SYSCTL
    sysctl --system >/dev/null 2>&1 || true
    echo -e "${GREEN}   -> 千兆内核网络栈优化完毕，TCP 窗口与 UDP 缓冲区已按物理内存 (${total_ram}MB) 最优放开！${PLAIN}"
}

# 安装或更新官方双核
install_cores() {
    local mode=${1:-fresh}
    echo -e "${SKYBLUE}[3/7] 正在同步官方最新 Xray-core 与 Hysteria 2 内核...${PLAIN}"
    if [ "$mode" = "update" ] && [ -x /usr/local/bin/xray ] && [ -x /usr/local/bin/hysteria ]; then
        echo -e "${GREEN}   -> 双核组件就绪，执行配置级平滑更新...${PLAIN}"
    else
        bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install >/dev/null
        bash <(curl -fsSL https://get.hy2.sh/) >/dev/null
    fi
}

# 生成 Hysteria 2 证书
generate_hy2_cert() {
    local force_regen=${1:-false}
    echo -e "${SKYBLUE}[4/7] 正在校验与签发 Hysteria 2 TLS 证书...${PLAIN}"
    mkdir -p /etc/hysteria
    if [ "$force_regen" = "true" ] || [ ! -f /etc/hysteria/server.crt ] || [ ! -f /etc/hysteria/server.key ]; then
        CERT_DAYS=$(shuf -i 365-1095 -n 1)
        openssl req -x509 -nodes -newkey ec:<(openssl ecparam -name prime256v1) \
            -keyout /etc/hysteria/server.key \
            -out /etc/hysteria/server.crt \
            -subj "/C=US/ST=California/L=San Francisco/O=Microsoft Corporation/CN=${HY2_SNI}" \
            -addext "subjectAltName=DNS:${HY2_SNI},DNS:*.${HY2_SNI#*.}" \
            -addext "keyUsage=digitalSignature,keyEncipherment" \
            -addext "extendedKeyUsage=serverAuth" \
            -days "${CERT_DAYS}" 2>/dev/null
    fi
    chown -R hysteria:hysteria /etc/hysteria 2>/dev/null || true
    chmod 755 /etc/hysteria 2>/dev/null || true
    chmod 644 /etc/hysteria/server.crt 2>/dev/null || true
    chmod 600 /etc/hysteria/server.key 2>/dev/null || true
}

# 写入配置并应用狂暴性能守护策略
write_configs_and_start() {
    SERVER_IP=$(curl -s4m6 https://api.ipify.org || curl -s4m6 https://ip.sb || curl -s4m6 https://icanhazip.com || echo "127.0.0.1")

    echo -e "${SKYBLUE}[5/7] 正在生成海外高吞吐专属配置 (激活 Brutal 暴力发包，无视晚高峰跨洋丢包)...${PLAIN}"
    
    # 1. 写入 Xray 满血出站配置 (serverNames 严格对齐 dest 目标证书 SAN)
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
            "${SNI_DOMAIN}"
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

    # 2. 写入 Hysteria 2 狂暴满血配置 (千兆带宽 + Brutal 算法)
    cat << HY2_EOF > "$HY2_CFG"
listen: :${PORT}

tls:
  cert: /etc/hysteria/server.crt
  key: /etc/hysteria/server.key

bandwidth:
  up: 1 gbps
  down: 1 gbps

auth:
  type: password
  password: ${HY2_PASS}

masquerade:
  type: proxy
  proxy:
    url: https://${SNI_DOMAIN}/
    rewriteHost: true
HY2_EOF

    # 环境变量持久化
    cat << ENV_EOF > "$ENV_FILE"
EDITION_TAG="${EDITION_TAG}"
PORT="${PORT}"
SERVER_IP="${SERVER_IP}"
UUID="${UUID}"
PRIVATE_KEY="${PRIVATE_KEY}"
PUBLIC_KEY="${PUBLIC_KEY}"
SHORT_ID="${SHORT_ID}"
SNI_DOMAIN="${SNI_DOMAIN}"
CLIENT_FP="${CLIENT_FP}"
HY2_PASS="${HY2_PASS}"
HY2_SNI="${HY2_SNI}"
ENV_EOF
    chmod 600 "$ENV_FILE"

    # 服务守护进程解除限制：支持百万级并发文件句柄，小内存机器自动注入 GOMEMLIMIT 防 OOM
    local total_ram mem_limit_line=""
    total_ram=$(free -m | awk '/Mem:/{print $2}')
    if [ "$total_ram" -le 1200 ]; then
        mem_limit_line="Environment=GOMEMLIMIT=256MiB"
    fi
    mkdir -p /etc/systemd/system/xray.service.d /etc/systemd/system/hysteria-server.service.d
    cat << OVERRIDE > /etc/systemd/system/xray.service.d/override.conf
[Service]
${mem_limit_line}
LimitNOFILE=1048576
LimitNPROC=512000
Restart=always
RestartSec=3
OVERRIDE

    cat << OVERRIDE > /etc/systemd/system/hysteria-server.service.d/override.conf
[Service]
${mem_limit_line}
LimitNOFILE=1048576
LimitNPROC=512000
Restart=always
RestartSec=3
OVERRIDE

    echo -e "${SKYBLUE}[6/7] 正在同步系统安全防火墙规则 (${PORT}/tcp & ${PORT}/udp)...${PLAIN}"
    ACTIVE_SSH_PORT=$(echo "${SSH_CONNECTION:-}" | awk '{print $4}')
    SSH_PORT=$(ss -tlnp 2>/dev/null | awk '/sshd/{split($4,a,":"); print a[length(a)]; exit}' || true)
    ACTIVE_SSH_PORT=${ACTIVE_SSH_PORT:-${SSH_PORT:-22}}
    if command -v ufw >/dev/null 2>&1; then
        ufw allow "${ACTIVE_SSH_PORT}/tcp" >/dev/null 2>&1 || true
        ufw allow "${PORT}/tcp" >/dev/null 2>&1 || true
        ufw allow "${PORT}/udp" >/dev/null 2>&1 || true
        ufw disable >/dev/null 2>&1 || true
    fi
    iptables -C INPUT -p tcp --dport "${PORT}" -j ACCEPT 2>/dev/null || iptables -I INPUT -p tcp --dport "${PORT}" -j ACCEPT 2>/dev/null || true
    iptables -C INPUT -p udp --dport "${PORT}" -j ACCEPT 2>/dev/null || iptables -I INPUT -p udp --dport "${PORT}" -j ACCEPT 2>/dev/null || true

    echo -e "${SKYBLUE}[7/7] 正在启动并校验双栈服务运行状态...${PLAIN}"
    systemctl daemon-reload
    systemctl enable xray hysteria-server >/dev/null 2>&1 || true
    systemctl restart xray hysteria-server >/dev/null 2>&1 || true
    sleep 1
    if ! systemctl is-active --quiet xray || ! systemctl is-active --quiet hysteria-server; then
        echo -e "${YELLOW}[提示] 检测到服务首次启动较慢，正在重试拉起...${PLAIN}"
        chown -R hysteria:hysteria /etc/hysteria 2>/dev/null || true
        systemctl restart xray hysteria-server || true
    fi
}

# 输出双节点链接与本地配置
generate_client_output() {
    local vless_link="vless://${UUID}@${SERVER_IP}:${PORT}?security=reality&encryption=none&pbk=${PUBLIC_KEY}&headerType=none&fp=${CLIENT_FP}&spx=%2F&type=tcp&flow=xtls-rprx-vision&sni=${SNI_DOMAIN}&sid=${SHORT_ID}#VLESS-Reality-Global"
    local hy2_link="hy2://${HY2_PASS}@${SERVER_IP}:${PORT}?insecure=1&sni=${HY2_SNI}#Hysteria2-Brutal-1Gbps"

    cat << OUT_EOF > "$LINKS_FILE"
================================================================================
v2rayN ${VERSION} - ${EDITION}
服务器 IP  : ${SERVER_IP}
单端口双栈 : ${PORT} (TCP: VLESS-Reality | UDP: Hysteria 2 Brutal 1Gbps)
伪装域名   : ${SNI_DOMAIN} (Microsoft 官方权威安全域)
吞吐性能   : 满血 Brutal 暴力抗丢包 + 1000M 极限发包 (专治晚高峰跨洋拥堵)
================================================================================

【节点链接 1: VLESS-Reality (日常主力/最高安全级别/绝不封IP)】
${vless_link}

【节点链接 2: Hysteria 2 (千兆狂暴·晚高峰 10% 跨洋丢包秒杀版)】
${hy2_link}

================================================================================
管理命令:
  v2rayn          - 显示节点链接与快速管理菜单
  v2rayn port     - 随机更换端口 (保留密钥，一键恢复满血)
  v2rayn status   - 查看服务运行状态
================================================================================
OUT_EOF

    # 安装全局管理命令 CLI
    cat << 'CLI_EOF' > /usr/local/bin/v2rayn
#!/usr/bin/env bash
ENV_FILE="/etc/v2rayn_dualstack.env"
LINKS_FILE="/root/node_links.txt"

show_menu() {
    clear
    cat << 'BANNER'
  _    _ ___  _ __ __ _ _   _ _ __  
 | |  | |_  )| '__/ _` | | | | '_ \ 
 | |/\| |/ / | | | (_| | |_| | | | |
  \_/\_/ /___|_|  \__,_|\__, |_| |_|  (海外千兆狂暴版)
                        |___/       
BANNER
    echo -e "\033[0;36m=== 海外主流 VPS 专属特调双栈管理工具 (v3.2) ===\033[0m"
    echo -e " 1. 查看当前节点配置与连接"
    echo -e " 2. 一键更换随机新端口 (保留密钥，无缝切换)"
    echo -e " 3. 重启服务 (Xray + Hysteria 2)"
    echo -e " 4. 查看运行状态"
    echo -e " 5. 退出"
    echo "------------------------------------------------"
    read -rp "请输入选项 [1-5]: " choice
    case "$choice" in
        1) cat "$LINKS_FILE" ;;
        2) change_port ;;
        3) 
           systemctl restart xray hysteria-server
           echo -e "\033[0;32m[成功] 服务已平滑重启！\033[0m"
           ;;
        4)
           echo "--- Xray (VLESS-Reality) ---"
           systemctl status xray --no-pager -l | head -n 10
           echo "--- Hysteria 2 (Brutal 1Gbps) ---"
           systemctl status hysteria-server --no-pager -l | head -n 10
           ;;
        5) exit 0 ;;
        *) echo "无效选项" ;;
    esac
}

change_port() {
    if [ ! -f "$ENV_FILE" ]; then
        echo "未找到环境配置文件！"
        exit 1
    fi
    source "$ENV_FILE"
    local NEW_PORT
    while true; do
        NEW_PORT=$(shuf -i 20000-60000 -n 1)
        if [ "$NEW_PORT" != "$PORT" ] && ! ss -tuln | awk '{print $5}' | grep -qE ":${NEW_PORT}$"; then
            break
        fi
    done
    echo -e "\033[0;33m正在将节点端口从 ${PORT} 切换为全新随机端口: ${NEW_PORT}...\033[0m"
    sed -i "s/\"port\": ${PORT}/\"port\": ${NEW_PORT}/g" /usr/local/etc/xray/config.json
    sed -i "s/listen: :${PORT}/listen: :${NEW_PORT}/g" /etc/hysteria/config.yaml
    sed -i "s/PORT=\"${PORT}\"/PORT=\"${NEW_PORT}\"/g" "$ENV_FILE"
    
    iptables -I INPUT -p tcp --dport "${NEW_PORT}" -j ACCEPT 2>/dev/null || true
    iptables -I INPUT -p udp --dport "${NEW_PORT}" -j ACCEPT 2>/dev/null || true
    iptables -D INPUT -p tcp --dport "${PORT}" -j ACCEPT 2>/dev/null || true
    iptables -D INPUT -p udp --dport "${PORT}" -j ACCEPT 2>/dev/null || true
    systemctl restart xray hysteria-server
    
    sed -i "s/: ${PORT}/: ${NEW_PORT}/g" "$LINKS_FILE"
    sed -i "s/:${PORT}/:${NEW_PORT}/g" "$LINKS_FILE"
    echo -e "\033[0;32m[成功] 端口已切换为 ${NEW_PORT}！\033[0m"
    cat "$LINKS_FILE"
}

case "${1:-}" in
    port) change_port ;;
    status) systemctl status xray hysteria-server --no-pager ;;
    restart) systemctl restart xray hysteria-server ;;
    *) show_menu ;;
esac
CLI_EOF
    chmod +x /usr/local/bin/v2rayn

    clear
    cat "$LINKS_FILE"
}

# 主执行流程
main() {
    local mode="fresh"
    if [ "${1:-}" = "update" ] || extract_existing_config; then
        mode="update"
        echo -e "${GREEN}>> 锁定已有配置 -> 端口: ${PORT} | 伪装站: ${SNI_DOMAIN}${PLAIN}"
    else
        PORT=$(generate_free_port)
        UUID=$(cat /proc/sys/kernel/random/uuid)
        SNI_DOMAIN="www.microsoft.com"
        HY2_SNI="turn.live.com"
        CLIENT_FP="chrome"
        SHORT_ID=$(openssl rand -hex 5)
        HY2_PASS=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | head -c 24)
        
        # 预先生成 REALITY X25519 密钥（兼容新旧版 Xray-core 输出格式）
        if ! command -v xray >/dev/null 2>&1; then
            bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install >/dev/null
        fi
        X25519_KEYPAIR=$(/usr/local/bin/xray x25519)
        PRIVATE_KEY=$(echo "$X25519_KEYPAIR" | awk -F': ' '/Private/{print $2}' | tr -d ' \r\n')
        PUBLIC_KEY=$(echo "$X25519_KEYPAIR" | awk -F': ' '/Public|Password/{print $2}' | tr -d ' \r\n')
    fi

    setup_network_env
    optimize_overseas_kernel
    install_cores "$mode"
    generate_hy2_cert false
    write_configs_and_start
    generate_client_output
}

main "$@"
