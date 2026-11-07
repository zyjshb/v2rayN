#!/usr/bin/env bash
# ==============================================================================
# v2rayN v3.2 (智能全自适应多厂商旗舰版)
# Multi-Cloud Intelligent Adaptive Dual-Stack (VLESS-Reality + Hysteria 2) Installer
# 
# 智能多模式矩阵：
# 1. 国内主流云厂商特调模式 (阿里云/腾讯云/华为云/移动云等海外区域)
#    - 深度外科手术式切除流氓监控探针 (Aegis/YunJing/Tat/HostGuard)
#    - 内存防爆机制 (智能紧凑 Swap + GOMEMLIMIT 限制，杜绝 1G 内存 OOM)
#    - 规避机房 QoS 封杀机制 (强制平滑 QUIC-BBR，杜绝触发 1Mbps 惩罚锁)
#    - 白名单拟态 Apple CDN，消除主动探测特征
# 
# 2. 海外主流 VPS 厂商特调模式 (RackNerd/DMIT/搬瓦工/Claw/Akile/V.PS/Vultr等)
#    - 狂暴满血 Brutal 算法，千兆极速发包无视晚高峰跨洋骨干网丢包
#    - 内核长管道高 BDP 调优 (TCP/UDP 缓冲放宽至 32M~64M，TCP Fast Open，FQ+BBR)
#    - 解除并发与连接限制 (LimitNOFILE=1048576, somaxconn=65535)
#    - 全球权威 DNS 与原生 IPv4/IPv6 双栈优化
# 
# Repository: https://github.com/zyjshb/v2rayN
# ==============================================================================
set -euo pipefail

VERSION="v3.2"
REPO_BASE="https://raw.githubusercontent.com/zyjshb/v2rayN/main"
ENV_FILE="/etc/v2rayn_dualstack.env"

# 终端色彩
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
SKYBLUE='\033[0;36m'
PURPLE='\033[0;35m'
PLAIN='\033[0m'

if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}[错误] 此脚本必须以 root 用户运行！${PLAIN}" 
   exit 1
fi

# 智能厂商与硬件环境检测引擎
detect_cloud_environment() {
    IS_CN_CLOUD="false"
    DETECTED_VENDOR="海外常规 VPS 宿主机"
    REASON="标准 KVM 虚拟化与干净宿主系统"

    # 1. 检测元数据服务器 (阿里云 / 腾讯云)
    if curl -s -m 1 http://100.100.100.200/latest/meta-data/ >/dev/null 2>&1; then
        IS_CN_CLOUD="true"
        DETECTED_VENDOR="阿里云 (Alibaba Cloud)"
        REASON="命中阿里云专属元数据通道，具有云盾常驻与动态令牌桶 QoS 机制"
    elif curl -s -m 1 http://metadata.tencentyun.com/latest/meta-data/ >/dev/null 2>&1; then
        IS_CN_CLOUD="true"
        DETECTED_VENDOR="腾讯云 (Tencent Cloud)"
        REASON="命中腾讯云专属元数据通道，具有云镜与组件监控风控机制"
    fi

    # 2. 检测 DMI 硬件厂商与虚拟化特征
    local sys_vendor product_name
    sys_vendor=$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null || true)
    product_name=$(cat /sys/class/dmi/id/product_name 2>/dev/null || true)
    if echo "${sys_vendor}${product_name}" | grep -qiE "Alibaba|Aliyun"; then
        IS_CN_CLOUD="true"
        DETECTED_VENDOR="阿里云 (Alibaba Cloud)"
        REASON="DMI 识别为阿里云定制宿主机"
    elif echo "${sys_vendor}${product_name}" | grep -qiE "Tencent"; then
        IS_CN_CLOUD="true"
        DETECTED_VENDOR="腾讯云 (Tencent Cloud)"
        REASON="DMI 识别为腾讯云定制宿主机"
    elif echo "${sys_vendor}${product_name}" | grep -qiE "Huawei"; then
        IS_CN_CLOUD="true"
        DETECTED_VENDOR="华为云 (Huawei Cloud)"
        REASON="DMI 识别为华为云定制宿主机"
    fi

    # 3. 检测系统内常驻流氓监控进程
    if pgrep -f "AliYunDun|aegis|YunJing|barad_agent|hostguard|tat_agent" >/dev/null 2>&1; then
        IS_CN_CLOUD="true"
        if [ "$DETECTED_VENDOR" = "海外常规 VPS 宿主机" ]; then
            DETECTED_VENDOR="国内云出海机型 (检测到活跃云监控进程)"
            REASON="发现常驻主机监控探针，必须深度切除并应用防QoS锁速"
        fi
    fi

    TOTAL_RAM=$(free -m | awk '/Mem:/{print $2}')
}

# 打印横幅与智能检测报告
print_banner() {
    clear
    cat << 'BANNER'
  _    _ ___  _ __ __ _ _   _ _ __  
 | |  | |_  )| '__/ _` | | | | '_ \ 
 | |/\| |/ / | | | (_| | |_| | | | |
  \_/\_/ /___|_|  \__,_|\__, |_| |_|  (v3.2 智能多厂商自适应版)
                        |___/       
BANNER
    echo -e "${SKYBLUE}================================================================${PLAIN}"
    echo -e "${GREEN}【AI 智能环境深度侦测结果】${PLAIN}"
    echo -e " 宿主机识别 : ${PURPLE}${DETECTED_VENDOR}${PLAIN}"
    echo -e " 物理内存   : ${YELLOW}${TOTAL_RAM} MB${PLAIN}"
    echo -e " 研判特征   : ${REASON}"
    if [ "$IS_CN_CLOUD" = "true" ]; then
        echo -e " 智能推荐   : ${GREEN}[选项 1] 国内主流云特调版 (轻量隐匿·防QoS锁速·极速内存版)${PLAIN}"
    else
        echo -e " 智能推荐   : ${GREEN}[选项 2] 海外主流 VPS 特调版 (千兆狂暴·高吞吐·晚高峰抗丢包版)${PLAIN}"
    fi
    echo -e "${SKYBLUE}================================================================${PLAIN}"
}

# 调度分发
dispatch_install() {
    local target_edition="$1"
    local script_name=""
    local local_script=""

    if [ "$target_edition" = "1" ] || [ "$target_edition" = "cn" ]; then
        script_name="install-cn.sh"
    else
        script_name="install-overseas.sh"
    fi

    local_script="/tmp/${script_name}"
    
    # 优先使用本地同级目录下的脚本，若不存在则从 GitHub 动态拉取
    local script_dir
    script_dir=$(dirname "$(readlink -f "$0")" 2>/dev/null || pwd)
    if [ -f "${script_dir}/${script_name}" ]; then
        echo -e "${GREEN}>> 正在加载本地专属特调方案: ${script_name}...${PLAIN}"
        bash "${script_dir}/${script_name}" "$@"
    else
        echo -e "${GREEN}>> 正在从 GitHub 官方仓库载入专属特调方案: ${script_name}...${PLAIN}"
        curl -fsSL "${REPO_BASE}/${script_name}" -o "$local_script"
        chmod +x "$local_script"
        bash "$local_script" "$@"
    fi
}

main() {
    detect_cloud_environment

    # 处理命令行参数快速启动
    for arg in "$@"; do
        case "$arg" in
            --cn|-cn)
                dispatch_install "1" "$@"
                exit 0
                ;;
            --overseas|--global|-g|-o)
                dispatch_install "2" "$@"
                exit 0
                ;;
        esac
    done

    # 若检测到老环境存在 EDITION_TAG，自动继承原有模式更新
    if [ -f "$ENV_FILE" ]; then
        # shellcheck disable=SC1090
        source "$ENV_FILE"
        if [ "${EDITION_TAG:-}" = "CN_CLOUD" ]; then
            echo -e "${GREEN}>> 检测到已安装 [国内主流云特调版]，正在执行无缝平滑热更新...${PLAIN}"
            dispatch_install "1" "$@"
            exit 0
        elif [ "${EDITION_TAG:-}" = "OVERSEAS_GIGA" ]; then
            echo -e "${GREEN}>> 检测到已安装 [海外主流 VPS 特调版]，正在执行无缝平滑热更新...${PLAIN}"
            dispatch_install "2" "$@"
            exit 0
        fi
    fi

    print_banner

    echo -e "请选择想要应用的调优方案:"
    echo -e " ${GREEN}1.${PLAIN} 国内主流云特调版 (${YELLOW}阿里云/腾讯云/华为云/百度云${PLAIN} - 切除云监控 + 内存防爆 + 防QoS锁速)"
    echo -e " ${GREEN}2.${PLAIN} 海外主流 VPS 特调版 (${YELLOW}RackNerd/DMIT/搬瓦工/Claw/Akile/V.PS${PLAIN} - 千兆狂暴Brutal + 晚高峰抗丢包)"
    echo -e " ${GREEN}3.${PLAIN} 退出"
    echo "----------------------------------------------------------------"
    
    local default_choice="1"
    if [ "$IS_CN_CLOUD" = "false" ]; then
        default_choice="2"
    fi

    read -rp "请输入选项 [默认回车使用推荐选项 $default_choice]: " user_choice
    user_choice=${user_choice:-$default_choice}

    case "$user_choice" in
        1) dispatch_install "1" "$@" ;;
        2) dispatch_install "2" "$@" ;;
        3) echo "已取消安装。"; exit 0 ;;
        *) echo -e "${RED}输入无效，默认采用智能推荐方案...${PLAIN}"; dispatch_install "$default_choice" "$@" ;;
    esac
}

main "$@"
