#!/usr/bin/env bash
# ==============================================================================
# v2rayN - 海外主流 VPS 厂商特调版 (RackNerd / DMIT / 搬瓦工 / Claw / Akile / Vultr 等)
# Specialized Flagship Edition for Overseas VPS Providers
# 
# 核心特调优化：
# 1. 狂暴满血 Brutal 拥塞控制 + QUIC 大流控窗口：满血支持 1Gbps~2.5Gbps 大端口，秒开 4K/8K
# 2. 动态 UDP 端口跳跃 (Port Hopping 20000-50000)：彻底粉碎运营商对单 UDP 端口的 QoS 限速与封锁
# 3. 高 BDP 跨洋长肥管道调优：内核 TCP/UDP 缓冲区自适应放宽、开启 MTU 探测、TCP Fast Open 与 FQ+BBR
# 4. 真实 UFW 防火墙加固 + 重启持久化守护：默认拒绝非法入站扫描，仅放行 SSH 与代理端口
# 5. 自动生成开箱即用 Clash Verge 配置文件 (/root/clash_verge.yaml)，内置 HY2+VLESS 自动故障回退
# 
# Repository: https://github.com/zyjshb/v2rayN
# ==============================================================================
set -euo pipefail
trap '' HUP

EDITION="海外主流 VPS 特调版 (千兆狂暴·端口跳跃·无视晚高峰跨洋丢包版)"
EDITION_TAG="OVERSEAS_GIGA"
VERSION="v3.3"
REPO_BASE="https://raw.githubusercontent.com/zyjshb/v2rayN/main"
ENV_FILE="/etc/v2rayn_dualstack.env"
LINKS_FILE="/root/node_links.txt"
CLASH_FILE="/root/clash_verge.yaml"
XRAY_CFG="/usr/local/etc/xray/config.json"
HY2_CFG="/etc/hysteria/config.yaml"
HOP_START=20000
HOP_END=50000

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

# 随机高位可用主端口 (50001 - 60000，与 20000-50000 跳跃端口段严格隔离零冲突)
generate_free_port() {
    local port
    while true; do
        port=$(shuf -i 50001-60000 -n 1)
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
            PUBLIC_KEY=$(echo "$X25519_DERIVE" | awk -F':' '/Public|Password/{print $2}' | tr -d ' \r\n')
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

# 基础环境与持久化防重置 DNS 优化
setup_network_env() {
    echo -e "${SKYBLUE}[1/7] 正在初始化海外纯净网络环境、日志防爆盘与全球权威 DNS 解析...${PLAIN}"
    # 限制 systemd-journald 日志体积上限为 50MB，防止长期高并发运行撑爆硬盘
    mkdir -p /etc/systemd/journald.conf.d
    cat << 'JRNL_EOF' > /etc/systemd/journald.conf.d/99-limit.conf
[Journal]
SystemMaxUse=50M
RuntimeMaxUse=30M
JRNL_EOF
    systemctl restart systemd-journald 2>/dev/null || true

    # 配置 systemd-resolved 与 resolv.conf 双重锁定，防止重启被 DHCP 覆盖
    mkdir -p /etc/systemd/resolved.conf.d
    cat << 'RESOLVED_EOF' > /etc/systemd/resolved.conf.d/99-global-dns.conf
[Resolve]
DNS=1.1.1.1 8.8.8.8 2606:4700:4700::1111 2001:4860:4860::8888
FallbackDNS=1.0.0.1 8.8.4.4
RESOLVED_EOF
    systemctl restart systemd-resolved 2>/dev/null || true

    chattr -i /etc/resolv.conf 2>/dev/null || true
    rm -f /etc/resolv.conf 2>/dev/null || true
    cat << 'DNS_EOF' > /etc/resolv.conf
nameserver 1.1.1.1
nameserver 8.8.8.8
nameserver 2606:4700:4700::1111
nameserver 2001:4860:4860::8888
DNS_EOF
    chattr +i /etc/resolv.conf 2>/dev/null || true
}

# 高 BDP 跨洋长管道内核与极端并发网络栈优化（支持小内存海外 VPS 动态自适应）
optimize_overseas_kernel() {
    echo -e "${SKYBLUE}[2/7] 正在应用千兆满血高吞吐内核参数 (BBR + FQ + UDP加速 + MTU探测 + TCP FastOpen)...${PLAIN}"
    export DEBIAN_FRONTEND=noninteractive

    # 安装基础依赖
    if ! command -v jq >/dev/null 2>&1 || ! command -v qrencode >/dev/null 2>&1 || ! command -v ufw >/dev/null 2>&1; then
        systemctl stop unattended-upgrades apt-daily.timer apt-daily-upgrade.timer 2>/dev/null || true
        pkill -9 -f unattended-upgr 2>/dev/null || true
        rm -f /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock /var/cache/apt/archives/lock 2>/dev/null || true
        dpkg --configure -a >/dev/null 2>&1 || true
        apt-get -o DPkg::Lock::Timeout=30 update -y >/dev/null 2>&1 || true
        apt-get -o DPkg::Lock::Timeout=30 install -y curl wget openssl ufw iptables jq unzip ca-certificates qrencode >/dev/null 2>&1 || true
    fi

    # 针对海外小内存 VPS (如 512M/1G RackNerd/Claw/Akile/Vultr) 自动补充 Swap 并动态调整内核缓冲
    local total_ram total_swap rmem_max tcp_max
    total_ram=$(free -m | awk '/Mem:/{print $2}')
    total_swap=$(free -m | awk '/Swap:/{print $2}')
    if [ "$total_ram" -le 1200 ]; then
        rmem_max=33554432
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
net.ipv4.udp_rmem_min = 16384
net.ipv4.udp_wmem_min = 16384
net.core.netdev_max_backlog = 100000
net.core.somaxconn = 65535
net.ipv4.tcp_max_syn_backlog = 3240000
net.ipv4.tcp_max_tw_buckets = 1440000
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_mtu_probing = 1
fs.file-max = 2097152
vm.swappiness = 10
SYSCTL
    sysctl --system >/dev/null 2>&1 || true
    echo -e "${GREEN}   -> 千兆内核网络栈优化完毕，UDP 与 TCP 缓冲区已按物理内存 (${total_ram}MB) 最优放开！${PLAIN}"
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

# 配置持久化端口跳跃与安全防火墙
apply_firewall_and_porthop() {
    local listen_port="$1"
    echo -e "${SKYBLUE}[6/7] 正在启用 UFW 真实安全防火墙与 UDP 端口跳跃 (${HOP_START}:${HOP_END} -> ${listen_port})...${PLAIN}"
    ACTIVE_SSH_PORT=$(echo "${SSH_CONNECTION:-}" | awk '{print $4}')
    SSH_PORT=$(ss -tlnp 2>/dev/null | awk '/sshd/{split($4,a,":"); print a[length(a)]; exit}' || true)
    ACTIVE_SSH_PORT=${ACTIVE_SSH_PORT:-${SSH_PORT:-22}}

    if command -v ufw >/dev/null 2>&1; then
        ufw default deny incoming >/dev/null 2>&1 || true
        ufw default allow outgoing >/dev/null 2>&1 || true
        ufw allow "${ACTIVE_SSH_PORT}/tcp" >/dev/null 2>&1 || true
        ufw allow "${listen_port}/tcp" >/dev/null 2>&1 || true
        ufw allow "${listen_port}/udp" >/dev/null 2>&1 || true
        ufw allow "${HOP_START}:${HOP_END}/udp" >/dev/null 2>&1 || true
        ufw --force enable >/dev/null 2>&1 || true
    fi

    # 创建端口跳跃脚本与 systemd 开机自启守护，重启永不丢失
    cat << HOP_EOF > /usr/local/bin/v2rayn-porthop-apply
#!/usr/bin/env bash
iptables -C INPUT -p tcp --dport "${listen_port}" -j ACCEPT 2>/dev/null || iptables -I INPUT -p tcp --dport "${listen_port}" -j ACCEPT 2>/dev/null || true
iptables -C INPUT -p udp --dport "${listen_port}" -j ACCEPT 2>/dev/null || iptables -I INPUT -p udp --dport "${listen_port}" -j ACCEPT 2>/dev/null || true
iptables -C INPUT -p udp --dport "${HOP_START}:${HOP_END}" -j ACCEPT 2>/dev/null || iptables -I INPUT -p udp --dport "${HOP_START}:${HOP_END}" -j ACCEPT 2>/dev/null || true
while iptables -t nat -D PREROUTING -p udp --dport "${HOP_START}:${HOP_END}" -j REDIRECT --to-ports "${listen_port}" 2>/dev/null; do :; done
iptables -t nat -A PREROUTING -p udp --dport "${HOP_START}:${HOP_END}" -j REDIRECT --to-ports "${listen_port}" 2>/dev/null || true
if command -v ip6tables >/dev/null 2>&1; then
    while ip6tables -t nat -D PREROUTING -p udp --dport "${HOP_START}:${HOP_END}" -j REDIRECT --to-ports "${listen_port}" 2>/dev/null; do :; done
    ip6tables -t nat -A PREROUTING -p udp --dport "${HOP_START}:${HOP_END}" -j REDIRECT --to-ports "${listen_port}" 2>/dev/null || true
fi
HOP_EOF
    chmod +x /usr/local/bin/v2rayn-porthop-apply
    /usr/local/bin/v2rayn-porthop-apply

    cat << 'SVC_EOF' > /etc/systemd/system/v2rayn-porthop.service
[Unit]
Description=v2rayN UDP Port Hopping NAT Redirect Persistence
After=network-online.target ufw.service
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/v2rayn-porthop-apply
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
SVC_EOF
    systemctl daemon-reload
    systemctl enable v2rayn-porthop.service >/dev/null 2>&1 || true
}

# 写入配置并应用狂暴性能守护策略
write_configs_and_start() {
    SERVER_IP=$(curl -s4m6 https://api.ipify.org || curl -s4m6 https://ip.sb || curl -s4m6 https://icanhazip.com || echo "127.0.0.1")

    echo -e "${SKYBLUE}[5/7] 正在生成海外高吞吐专属配置 (激活 Brutal 暴力发包 + QUIC 大流控窗口)...${PLAIN}"
    
    local total_ram conn_win mem_limit_line=""
    total_ram=$(free -m | awk '/Mem:/{print $2}')
    if [ "$total_ram" -le 1200 ]; then
        conn_win=33554432
        mem_limit_line="Environment=GOMEMLIMIT=256MiB"
    else
        conn_win=67108864
    fi

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

    # 2. 写入 Hysteria 2 狂暴满血配置 (千兆带宽 + Brutal 算法 + QUIC 大流控窗口)
    cat << HY2_EOF > "$HY2_CFG"
listen: :${PORT}

tls:
  cert: /etc/hysteria/server.crt
  key: /etc/hysteria/server.key

bandwidth:
  up: 1 gbps
  down: 1 gbps

ignoreClientBandwidth: false
speedTest: true

quic:
  initStreamReceiveWindow: 16777216
  maxStreamReceiveWindow: 16777216
  initConnReceiveWindow: ${conn_win}
  maxConnReceiveWindow: ${conn_win}
  maxIdleTimeout: 30s
  keepAlivePeriod: 10s

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
HOP_START="${HOP_START}"
HOP_END="${HOP_END}"
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

    apply_firewall_and_porthop "${PORT}"

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

# 生成客户端链接与开箱即用 Clash Verge YAML 文件
generate_client_output() {
    local vless_link="vless://${UUID}@${SERVER_IP}:${PORT}?security=reality&encryption=none&pbk=${PUBLIC_KEY}&headerType=none&fp=${CLIENT_FP}&spx=%2F&type=tcp&flow=xtls-rprx-vision&sni=${SNI_DOMAIN}&sid=${SHORT_ID}#VLESS-Reality-Global"
    local hy2_link="hy2://${HY2_PASS}@${SERVER_IP}:${PORT}?insecure=1&sni=${HY2_SNI}&mport=${HOP_START}-${HOP_END}#Hysteria2-Brutal-1Gbps"

    # 自动生成开箱即用的 Clash Verge 完整配置文件 (/root/clash_verge.yaml)
    cat << CLASH_EOF > "$CLASH_FILE"
port: 7890
socks-port: 7891
mixed-port: 7892
allow-lan: false
mode: rule
log-level: warning
ipv6: false
unified-delay: true
tcp-concurrent: true
find-process-mode: strict
external-controller: 127.0.0.1:9097
geodata-mode: true

sniffer:
  enable: true
  parse-pure-ip: true
  override-destination: false
  sniff:
    HTTP:
      ports: [80, 8080-8880]
    TLS:
      ports: [443, 8443]
    QUIC:
      ports: [443, 8443]
  skip-domain:
    - "+.push.apple.com"
    - "+.challenges.cloudflare.com"

dns:
  enable: true
  listen: 127.0.0.1:1053
  ipv6: false
  prefer-h3: true
  enhanced-mode: fake-ip
  fake-ip-range: 198.18.0.1/16
  fake-ip-filter:
    - "*.lan"
    - "*.local"
    - "+.msftconnecttest.com"
    - "+.msftncsi.com"
    - "localhost.ptlogin2.qq.com"
    - "+.stun.*"
    - "time.*.com"
    - "ntp.*.com"
  default-nameserver:
    - 223.5.5.5
    - 119.29.29.29
  nameserver:
    - https://dns.alidns.com/dns-query
    - https://doh.pub/dns-query

proxies:
  - name: "⚡ Hysteria2-千兆狂暴(端口跳跃)"
    type: hysteria2
    server: ${SERVER_IP}
    port: ${PORT}
    ports: ${HOP_START}-${HOP_END}
    hop-interval: 30
    password: "${HY2_PASS}"
    sni: ${HY2_SNI}
    skip-cert-verify: true
    alpn:
      - h3
    up: "100 Mbps"
    down: "1000 Mbps"

  - name: "🛡️ VLESS-Reality-TCP防封备用"
    type: vless
    server: ${SERVER_IP}
    port: ${PORT}
    uuid: ${UUID}
    network: tcp
    tls: true
    udp: true
    flow: xtls-rprx-vision
    servername: ${SNI_DOMAIN}
    client-fingerprint: ${CLIENT_FP}
    reality-opts:
      public-key: ${PUBLIC_KEY}
      short-id: ${SHORT_ID}

proxy-groups:
  - name: "PROXY"
    type: select
    proxies:
      - "🔄 智能故障回退(HY2优先)"
      - "⚡ Hysteria2-千兆狂暴(端口跳跃)"
      - "🛡️ VLESS-Reality-TCP防封备用"
      - DIRECT

  - name: "🔄 智能故障回退(HY2优先)"
    type: fallback
    url: "https://www.gstatic.com/generate_204"
    interval: 180
    lazy: true
    proxies:
      - "⚡ Hysteria2-千兆狂暴(端口跳跃)"
      - "🛡️ VLESS-Reality-TCP防封备用"

  - name: "AI"
    type: select
    proxies:
      - "⚡ Hysteria2-千兆狂暴(端口跳跃)"
      - "🛡️ VLESS-Reality-TCP防封备用"

rules:
  - IP-CIDR,${SERVER_IP}/32,DIRECT,no-resolve
  - DOMAIN-SUFFIX,grok.com,AI
  - DOMAIN-SUFFIX,x.ai,AI
  - DOMAIN-SUFFIX,openai.com,AI
  - DOMAIN-SUFFIX,chatgpt.com,AI
  - DOMAIN-SUFFIX,claude.ai,AI
  - DOMAIN-SUFFIX,anthropic.com,AI
  - DOMAIN-SUFFIX,gemini.google.com,AI
  - DOMAIN-SUFFIX,perplexity.ai,AI
  - DOMAIN-SUFFIX,google.com,PROXY
  - DOMAIN-SUFFIX,youtube.com,PROXY
  - DOMAIN-SUFFIX,googlevideo.com,PROXY
  - DOMAIN-SUFFIX,ytimg.com,PROXY
  - DOMAIN-SUFFIX,github.com,PROXY
  - DOMAIN-KEYWORD,google,PROXY
  - GEOIP,LAN,DIRECT,no-resolve
  - GEOIP,CN,DIRECT
  - MATCH,PROXY
CLASH_EOF
    chmod 600 "$CLASH_FILE"

    cat << OUT_EOF > "$LINKS_FILE"
================================================================================
v2rayN ${VERSION} - ${EDITION}
服务器 IP  : ${SERVER_IP}
主监听端口 : ${PORT} (TCP: VLESS-Reality | UDP: Hysteria 2 Brutal 1Gbps)
端口跳跃段 : ${HOP_START}-${HOP_END} (UDP 动态端口跳跃已激活，防运营商单端口限速)
伪装域名   : ${SNI_DOMAIN} (Microsoft 官方权威安全域)
Clash 配置 : ${CLASH_FILE} (已自动生成，输入 v2rayn clash 即可查看复制)
================================================================================

【节点链接 1: Hysteria 2 (千兆狂暴 + 动态端口跳跃 · 主力极速推荐)】
${hy2_link}

【节点链接 2: VLESS-Reality (纯 TCP 隐匿防封 · 禁 UDP 网络应急备用)】
${vless_link}

================================================================================
快捷管理命令:
  v2rayn          - 打开交互式管理菜单
  v2rayn clash    - 直接输出开箱即用的 Clash Verge YAML 完整配置
  v2rayn port     - 随机更换主端口 (同步更新防火墙、端口跳跃与 Clash 配置)
  v2rayn status   - 查看双栈服务运行状态
================================================================================
OUT_EOF

    # 安装全局管理命令 CLI
    cat << 'CLI_EOF' > /usr/local/bin/v2rayn
#!/usr/bin/env bash
ENV_FILE="/etc/v2rayn_dualstack.env"
LINKS_FILE="/root/node_links.txt"
CLASH_FILE="/root/clash_verge.yaml"

show_menu() {
    clear
    cat << 'BANNER'
  _    _ ___  _ __ __ _ _   _ _ __  
 | |  | |_  )| '__/ _` | | | | '_ \ 
 | |/\| |/ / | | | (_| | |_| | | | |
  \_/\_/ /___|_|  \__,_|\__, |_| |_|  (海外千兆狂暴·端口跳跃版)
                        |___/       
BANNER
    echo -e "\033[0;36m=== 海外主流 VPS 专属特调双栈管理工具 (v3.3) ===\033[0m"
    echo -e " 1. 查看当前节点链接与概览"
    echo -e " 2. 导出 Clash Verge 完整 YAML 配置 (直接复制保存即可用)"
    echo -e " 3. 一键更换随机新主端口 (保留密钥，同步更新端口跳跃与配置)"
    echo -e " 4. 重启服务 (Xray + Hysteria 2)"
    echo -e " 5. 查看运行状态与防火墙"
    echo -e " 6. 退出"
    echo "------------------------------------------------"
    read -rp "请输入选项 [1-6]: " choice
    case "$choice" in
        1) cat "$LINKS_FILE" ;;
        2) cat "$CLASH_FILE" ;;
        3) change_port ;;
        4) 
           systemctl restart xray hysteria-server
           echo -e "\033[0;32m[成功] 服务已平滑重启！\033[0m"
           ;;
        5)
           echo "--- Xray (VLESS-Reality) ---"
           systemctl status xray --no-pager -l | head -n 10
           echo "--- Hysteria 2 (Brutal 1Gbps) ---"
           systemctl status hysteria-server --no-pager -l | head -n 10
           ;;
        6) exit 0 ;;
        *) echo "无效选项" ;;
    esac
}

change_port() {
    if [ ! -f "$ENV_FILE" ]; then
        echo "未找到环境配置文件！"
        exit 1
    fi
    # shellcheck disable=SC1090
    source "$ENV_FILE"
    local OLD_PORT="$PORT"
    local NEW_PORT
    while true; do
        NEW_PORT=$(shuf -i 50001-60000 -n 1)
        if [ "$NEW_PORT" != "$OLD_PORT" ] && ! ss -tuln | awk '{print $5}' | grep -qE ":${NEW_PORT}$"; then
            break
        fi
    done
    echo -e "\033[0;33m正在将节点主端口从 ${OLD_PORT} 切换为全新随机端口: ${NEW_PORT}...\033[0m"
    sed -i "s/\"port\": ${OLD_PORT}/\"port\": ${NEW_PORT}/g" /usr/local/etc/xray/config.json
    sed -i "s/listen: :${OLD_PORT}/listen: :${NEW_PORT}/g" /etc/hysteria/config.yaml
    sed -i "s/^PORT=\"${OLD_PORT}\"/PORT=\"${NEW_PORT}\"/g" "$ENV_FILE"

    if command -v ufw >/dev/null 2>&1; then
        ufw allow "${NEW_PORT}/tcp" >/dev/null 2>&1 || true
        ufw allow "${NEW_PORT}/udp" >/dev/null 2>&1 || true
        ufw delete allow "${OLD_PORT}/tcp" >/dev/null 2>&1 || true
        ufw delete allow "${OLD_PORT}/udp" >/dev/null 2>&1 || true
    fi
    if [ -f /usr/local/bin/v2rayn-porthop-apply ]; then
        sed -i "s/${OLD_PORT}/${NEW_PORT}/g" /usr/local/bin/v2rayn-porthop-apply
        /usr/local/bin/v2rayn-porthop-apply
    fi
    systemctl restart xray hysteria-server

    sed -i "s/主监听端口 : ${OLD_PORT}/主监听端口 : ${NEW_PORT}/g" "$LINKS_FILE"
    sed -i "s/@${SERVER_IP}:${OLD_PORT}/@${SERVER_IP}:${NEW_PORT}/g" "$LINKS_FILE"
    sed -i "s/port: ${OLD_PORT}/port: ${NEW_PORT}/g" "$CLASH_FILE"
    echo -e "\033[0;32m[成功] 主端口已平滑切换为 ${NEW_PORT}！\033[0m"
    cat "$LINKS_FILE"
}

case "${1:-}" in
    clash) cat "$CLASH_FILE" ;;
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
    if extract_existing_config; then
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
        PRIVATE_KEY=$(echo "$X25519_KEYPAIR" | awk -F':' '/Private/{print $2}' | tr -d ' \r\n')
        PUBLIC_KEY=$(echo "$X25519_KEYPAIR" | awk -F':' '/Public|Password/{print $2}' | tr -d ' \r\n')
    fi

    setup_network_env
    optimize_overseas_kernel
    install_cores "$mode"
    generate_hy2_cert false
    write_configs_and_start
    generate_client_output
}

main "$@"
