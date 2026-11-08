#!/usr/bin/env bash
# ==============================================================================
# v2rayN - 国内主流云厂商特调版 (阿里云/腾讯云/华为云/百度云等海外VPS)
# Specialized Edition for Chinese Cloud Providers (Aliyun, Tencent, Huawei, etc.)
# 
# 核心特调优化：
# 1. 深度外科手术式切除大厂流氓监控探针 (Aegis/YunJing/Tat/HostGuard)，释放 150-250MB 内存
# 2. 内存防爆机制：智能创建紧凑 Swap + 限制 Go 运行时内存 (GOMEMLIMIT) + Journald 日志限额
# 3. 规避机房 QoS 封杀机制：强制平滑 QUIC-BBR，彻底杜绝 Brutal 暴力发包触发 1Mbps 惩罚锁
# 4. 真实 UFW 防火墙加固 + 抗探测白名单伪装 (Apple CDN + Safari TLS 1.3)
# 5. 自动生成开箱即用 Clash Verge 配置文件 (/root/clash_verge.yaml)，内置 HY2+VLESS 自动故障回退
# 
# Repository: https://github.com/zyjshb/v2rayN
# ==============================================================================
set -euo pipefail

EDITION="国内主流云特调版 (轻量隐匿·防QoS锁速·极速内存版)"
EDITION_TAG="CN_CLOUD"
VERSION="v3.3"
REPO_BASE="https://raw.githubusercontent.com/zyjshb/v2rayN/main"
ENV_FILE="/etc/v2rayn_dualstack.env"
LINKS_FILE="/root/node_links.txt"
CLASH_FILE="/root/clash_verge.yaml"
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
        SNI_DOMAIN="www.apple.com"
        CLIENT_FP="safari"
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
        SNI_DOMAIN="www.apple.com"
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
        CLIENT_FP="safari"
        HY2_SNI=${HY2_SNI:-turn.live.com}

        if [ -n "${PORT:-}" ] && [ -n "${UUID:-}" ] && [ -n "${PRIVATE_KEY:-}" ] && [ -n "${PUBLIC_KEY:-}" ] && [ -n "${HY2_PASS:-}" ]; then
            return 0
        fi
    fi
    return 1
}

# 深度彻底切除国内大厂所有流氓监控与内网劫持
clean_cloud_monitors() {
    echo -e "${SKYBLUE}[1/7] 正在对国内云厂商进行深度瘦身：彻底拔除云盾、云镜与监控进程...${PLAIN}"
    
    # 限制 systemd-journald 日志体积上限为 50MB，防止小硬盘爆满
    mkdir -p /etc/systemd/journald.conf.d
    cat << 'JRNL_EOF' > /etc/systemd/journald.conf.d/99-limit.conf
[Journal]
SystemMaxUse=50M
RuntimeMaxUse=30M
JRNL_EOF
    systemctl restart systemd-journald 2>/dev/null || true

    # 清理历史可能残留的 WARP 网卡与服务
    if command -v warp-cli >/dev/null 2>&1 || dpkg -l 2>/dev/null | grep -q cloudflare-warp; then
        warp-cli --accept-tos disconnect >/dev/null 2>&1 || true
        systemctl stop warp-svc >/dev/null 2>&1 || true
        systemctl disable warp-svc >/dev/null 2>&1 || true
        apt-get purge -y cloudflare-warp >/dev/null 2>&1 || true
        rm -f /etc/apt/sources.list.d/cloudflare-client.list
    fi
    ip link delete CloudflareWARP 2>/dev/null || true
    ip link delete warp 2>/dev/null || true

    # 修复并锁定纯净公共 DNS (清理大厂内网劫持 DNS，防 DHCP 覆盖)
    chattr -i /etc/resolv.conf 2>/dev/null || true
    rm -f /etc/resolv.conf 2>/dev/null || true
    cat << 'DNS_EOF' > /etc/resolv.conf
nameserver 1.1.1.1
nameserver 8.8.8.8
nameserver 223.5.5.5
DNS_EOF
    chattr +i /etc/resolv.conf 2>/dev/null || true

    # 停止并永久屏蔽大厂监控服务
    systemctl stop aegis hostguard aliyun-service tat_agent barad_agent sgagent 2>/dev/null || true
    systemctl disable aegis hostguard aliyun-service tat_agent barad_agent sgagent 2>/dev/null || true
    systemctl mask aegis hostguard aliyun-service tat_agent barad_agent sgagent 2>/dev/null || true

    # 运行大厂自带的卸载程序
    [ -f /usr/local/aegis/aegis_update/uninstall.sh ] && bash /usr/local/aegis/aegis_update/uninstall.sh >/dev/null 2>&1 || true
    [ -f /usr/local/aegis/aegis_client/uninstall.sh ] && bash /usr/local/aegis/aegis_client/uninstall.sh >/dev/null 2>&1 || true
    [ -f /usr/local/qcloud/stargate/admin/uninstall.sh ] && bash /usr/local/qcloud/stargate/admin/uninstall.sh >/dev/null 2>&1 || true
    [ -f /usr/local/qcloud/YunJing/uninst.sh ] && bash /usr/local/qcloud/YunJing/uninst.sh >/dev/null 2>&1 || true
    [ -f /usr/local/qcloud/monitor/barad/admin/uninstall.sh ] && bash /usr/local/qcloud/monitor/barad/admin/uninstall.sh >/dev/null 2>&1 || true

    # 暴力杀死残留监控进程
    pkill -9 -f "AliYunDun|AliYunDunUpdate|AliYunDunMonitor|YunJing|barad_agent|sgagent|hostguard|tat_agent" 2>/dev/null || true
    rm -rf /usr/local/aegis /usr/local/qcloud /etc/init.d/aegis /etc/init.d/barad_agent 2>/dev/null || true
    systemctl daemon-reload
    echo -e "${GREEN}   -> 监控探针已全部彻底切除，已释放约 180MB 系统内存！${PLAIN}"
}

# 针对 1GB/2GB 小内存主机的内核与内存防爆优化
optimize_system_and_memory() {
    echo -e "${SKYBLUE}[2/7] 正在应用小内存防爆保护与稳健型网络栈 (防QoS与内存溢出)...${PLAIN}"
    export DEBIAN_FRONTEND=noninteractive

    # 自动释放 apt 锁并安装必要工具
    if ! command -v jq >/dev/null 2>&1 || ! command -v qrencode >/dev/null 2>&1 || ! command -v ufw >/dev/null 2>&1; then
        systemctl stop unattended-upgrades apt-daily.timer apt-daily-upgrade.timer 2>/dev/null || true
        pkill -9 -f unattended-upgr 2>/dev/null || true
        rm -f /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock /var/cache/apt/archives/lock 2>/dev/null || true
        dpkg --configure -a >/dev/null 2>&1 || true
        apt-get -o DPkg::Lock::Timeout=30 update -y >/dev/null 2>&1 || true
        apt-get -o DPkg::Lock::Timeout=30 install -y curl wget openssl ufw iptables jq unzip ca-certificates qrencode >/dev/null 2>&1 || true
    fi

    # 小内存 VPS 自动开启 1GB 智能 Swap 缓冲区
    local total_ram
    total_ram=$(free -m | awk '/Mem:/{print $2}')
    local total_swap
    total_swap=$(free -m | awk '/Swap:/{print $2}')
    if [ "$total_ram" -le 1200 ] && [ "$total_swap" -lt 512 ]; then
        echo -e "${YELLOW}   -> 检测到当前物理内存仅 ${total_ram}MB，自动挂载 1GB 紧凑 Swap 防爆缓冲...${PLAIN}"
        swapoff /swapfile 2>/dev/null || true
        dd if=/dev/zero of=/swapfile bs=1M count=1024 status=none 2>/dev/null || true
        chmod 600 /swapfile
        mkswap /swapfile >/dev/null 2>&1 || true
        swapon /swapfile 2>/dev/null || true
        if ! grep -q '/swapfile' /etc/fstab 2>/dev/null; then
            echo '/swapfile none swap sw 0 0' >> /etc/fstab
        fi
    fi

    # 内核参数调优：
    # 严格保持 16MB 缓冲区，绝不设为 32MB+，彻底杜绝 1GB 小内存触发 Linux 内核 TCP Memory Pressure 降速锁
    rm -f /etc/sysctl.d/99-*.conf 2>/dev/null || true
    cat << 'SYSCTL' > /etc/sysctl.d/99-cn-cloud-optimize.conf
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.core.rmem_default = 2621440
net.core.wmem_default = 2621440
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216
net.ipv4.udp_rmem_min = 16384
net.ipv4.udp_wmem_min = 16384
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_mtu_probing = 1
vm.swappiness = 10
SYSCTL
    sysctl --system >/dev/null 2>&1 || true
}

# 安装或更新官方双核
install_cores() {
    local mode=${1:-fresh}
    echo -e "${SKYBLUE}[3/7] 正在同步官方最新 Xray-core 与 Hysteria 2 内核...${PLAIN}"
    if [ "$mode" = "update" ] && [ -x /usr/local/bin/xray ] && [ -x /usr/local/bin/hysteria ]; then
        echo -e "${GREEN}   -> 双核组件就绪，执行配置级无缝更新...${PLAIN}"
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
            -subj "/C=US/ST=California/L=San Francisco/O=Apple Inc./CN=${HY2_SNI}" \
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

# 写入配置并应用高并发守护策略
write_configs_and_start() {
    SERVER_IP=$(curl -s4m6 https://api.ipify.org || curl -s4m6 https://ip.sb || curl -s4m6 https://icanhazip.com || echo "127.0.0.1")

    echo -e "${SKYBLUE}[5/7] 正在生成国内大厂专属配置文件 (开启 QUIC-BBR 防QoS锁速机制)...${PLAIN}"
    
    # 1. 写入 Xray 纯净出站配置 (Apple 白名单拟态)
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
            "itunes.apple.com"
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

    # 2. 写入 Hysteria 2 特调配置
    # 核心：ignoreClientBandwidth: true 强制启用 QUIC-BBR 拥塞控制，不使用暴力发包，彻底杜绝被云厂商交换机扣上 1Mbps 限速帽
    cat << HY2_EOF > "$HY2_CFG"
listen: :${PORT}

tls:
  cert: /etc/hysteria/server.crt
  key: /etc/hysteria/server.key

ignoreClientBandwidth: true
speedTest: true

quic:
  initStreamReceiveWindow: 8388608
  maxStreamReceiveWindow: 16777216
  initConnReceiveWindow: 16777216
  maxConnReceiveWindow: 33554432
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

    # 服务守护进程限制与防内存无节制膨胀 (GOMEMLIMIT=256MiB)
    mkdir -p /etc/systemd/system/xray.service.d /etc/systemd/system/hysteria-server.service.d
    cat << 'OVERRIDE' > /etc/systemd/system/xray.service.d/override.conf
[Service]
Environment=GOMEMLIMIT=256MiB
LimitNOFILE=524288
Restart=always
RestartSec=3
OVERRIDE

    cat << 'OVERRIDE' > /etc/systemd/system/hysteria-server.service.d/override.conf
[Service]
Environment=GOMEMLIMIT=256MiB
LimitNOFILE=524288
Restart=always
RestartSec=3
OVERRIDE

    echo -e "${SKYBLUE}[6/7] 正在启用 UFW 真实安全防火墙 (${PORT}/tcp & ${PORT}/udp)...${PLAIN}"
    # 放行当前 SSH 端口与节点服务端口
    ACTIVE_SSH_PORT=$(echo "${SSH_CONNECTION:-}" | awk '{print $4}')
    SSH_PORT=$(ss -tlnp 2>/dev/null | awk '/sshd/{split($4,a,":"); print a[length(a)]; exit}' || true)
    ACTIVE_SSH_PORT=${ACTIVE_SSH_PORT:-${SSH_PORT:-22}}
    if command -v ufw >/dev/null 2>&1; then
        ufw default deny incoming >/dev/null 2>&1 || true
        ufw default allow outgoing >/dev/null 2>&1 || true
        ufw allow "${ACTIVE_SSH_PORT}/tcp" >/dev/null 2>&1 || true
        ufw allow "${PORT}/tcp" >/dev/null 2>&1 || true
        ufw allow "${PORT}/udp" >/dev/null 2>&1 || true
        ufw --force enable >/dev/null 2>&1 || true
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

# 输出双节点链接与开箱即用 Clash Verge YAML 配置
generate_client_output() {
    local vless_link="vless://${UUID}@${SERVER_IP}:${PORT}?security=reality&encryption=none&pbk=${PUBLIC_KEY}&headerType=none&fp=${CLIENT_FP}&spx=%2F&type=tcp&flow=xtls-rprx-vision&sni=${SNI_DOMAIN}&sid=${SHORT_ID}#VLESS-Reality-CN"
    local hy2_link="hy2://${HY2_PASS}@${SERVER_IP}:${PORT}?insecure=1&sni=${HY2_SNI}#Hysteria2-BBR-CN"

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
  - name: "⚡ Hysteria2-QUIC-BBR(防限速)"
    type: hysteria2
    server: ${SERVER_IP}
    port: ${PORT}
    password: "${HY2_PASS}"
    sni: ${HY2_SNI}
    skip-cert-verify: true
    alpn:
      - h3

  - name: "🛡️ VLESS-Reality-TCP防封主力"
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
      - "⚡ Hysteria2-QUIC-BBR(防限速)"
      - "🛡️ VLESS-Reality-TCP防封主力"
      - DIRECT

  - name: "🔄 智能故障回退(HY2优先)"
    type: fallback
    url: "https://www.gstatic.com/generate_204"
    interval: 180
    lazy: true
    proxies:
      - "⚡ Hysteria2-QUIC-BBR(防限速)"
      - "🛡️ VLESS-Reality-TCP防封主力"

  - name: "AI"
    type: select
    proxies:
      - "⚡ Hysteria2-QUIC-BBR(防限速)"
      - "🛡️ VLESS-Reality-TCP防封主力"

rules:
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
单端口双栈 : ${PORT} (TCP: VLESS-Reality | UDP: Hysteria 2 QUIC-BBR)
伪装域名   : ${SNI_DOMAIN} (Apple CDN 官方真实白名单)
QoS策略    : 强制平滑 QUIC-BBR 拥塞控制 (严防机房 1Mbps 惩罚限速)
Clash 配置 : ${CLASH_FILE} (已自动生成，输入 v2rayn clash 即可查看复制)
================================================================================

【节点链接 1: VLESS-Reality (日常主力/最高安全级别/绝不封IP)】
${vless_link}

【节点链接 2: Hysteria 2 (晚高峰平滑抗丢包/防QoS锁死版)】
${hy2_link}

================================================================================
快捷管理命令:
  v2rayn          - 显示节点链接与快速管理菜单
  v2rayn clash    - 直接输出开箱即用的 Clash Verge YAML 完整配置
  v2rayn port     - 随机更换端口 (保留密钥，一键恢复满血)
  v2rayn status   - 查看服务运行状态
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
  \_/\_/ /___|_|  \__,_|\__, |_| |_|  (国内云特调·防QoS版)
                        |___/       
BANNER
    echo -e "\033[0;36m=== 国内主流云专属特调双栈管理工具 (v3.3) ===\033[0m"
    echo -e " 1. 查看当前节点配置与连接"
    echo -e " 2. 导出 Clash Verge 完整 YAML 配置 (直接复制保存即可用)"
    echo -e " 3. 一键更换随机新端口 (保留密钥，规避云厂商单端口限速)"
    echo -e " 4. 重启服务 (Xray + Hysteria 2)"
    echo -e " 5. 查看运行状态"
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
           echo "--- Hysteria 2 (QUIC-BBR) ---"
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
        NEW_PORT=$(shuf -i 20000-60000 -n 1)
        if [ "$NEW_PORT" != "$OLD_PORT" ] && ! ss -tuln | awk '{print $5}' | grep -qE ":${NEW_PORT}$"; then
            break
        fi
    done
    echo -e "\033[0;33m正在将节点端口从 ${OLD_PORT} 切换为全新随机端口: ${NEW_PORT}...\033[0m"
    sed -i "s/\"port\": ${OLD_PORT}/\"port\": ${NEW_PORT}/g" /usr/local/etc/xray/config.json
    sed -i "s/listen: :${OLD_PORT}/listen: :${NEW_PORT}/g" /etc/hysteria/config.yaml
    sed -i "s/^PORT=\"${OLD_PORT}\"/PORT=\"${NEW_PORT}\"/g" "$ENV_FILE"
    
    if command -v ufw >/dev/null 2>&1; then
        ufw allow "${NEW_PORT}/tcp" >/dev/null 2>&1 || true
        ufw allow "${NEW_PORT}/udp" >/dev/null 2>&1 || true
        ufw delete allow "${OLD_PORT}/tcp" >/dev/null 2>&1 || true
        ufw delete allow "${OLD_PORT}/udp" >/dev/null 2>&1 || true
    fi
    iptables -I INPUT -p tcp --dport "${NEW_PORT}" -j ACCEPT 2>/dev/null || true
    iptables -I INPUT -p udp --dport "${NEW_PORT}" -j ACCEPT 2>/dev/null || true
    iptables -D INPUT -p tcp --dport "${OLD_PORT}" -j ACCEPT 2>/dev/null || true
    iptables -D INPUT -p udp --dport "${OLD_PORT}" -j ACCEPT 2>/dev/null || true
    systemctl restart xray hysteria-server
    
    sed -i "s/单端口双栈 : ${OLD_PORT}/单端口双栈 : ${NEW_PORT}/g" "$LINKS_FILE"
    sed -i "s/@${SERVER_IP}:${OLD_PORT}/@${SERVER_IP}:${NEW_PORT}/g" "$LINKS_FILE"
    sed -i "s/port: ${OLD_PORT}/port: ${NEW_PORT}/g" "$CLASH_FILE"
    echo -e "\033[0;32m[成功] 端口已切换为 ${NEW_PORT}！\033[0m"
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
        SNI_DOMAIN="www.apple.com"
        HY2_SNI="turn.live.com"
        CLIENT_FP="safari"
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

    clean_cloud_monitors
    optimize_system_and_memory
    install_cores "$mode"
    generate_hy2_cert false
    write_configs_and_start
    generate_client_output
}

main "$@"
