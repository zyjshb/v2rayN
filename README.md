<div align="center">

# ⚡ v2rayN 多厂商智能自适应双栈脚本 (v3.2 旗舰版)

> **首创区分国内主流云厂商与海外常规 VPS 的智能分类优化架构**  
> 单端口四层协议栈并发黑科技：**TCP (VLESS-Reality) + UDP (Hysteria 2) 零冲突共存**  
> **AI 宿主机环境自动侦测 • 深度切除大厂流氓监控 • 内存防爆机制 • 规避机房 1Mbps 惩罚限速 • 海外千兆 Brutal 满血抗丢包**

[![License](https://img.shields.io/badge/license-MIT-blue.svg?style=flat-square)](LICENSE)
[![Release](https://img.shields.io/badge/release-v3.2%20Adaptive-brightgreen.svg?style=flat-square)](https://github.com/zyjshb/v2rayN)
[![Platform](https://img.shields.io/badge/platform-Ubuntu%2020.04%2B%20%7C%20Debian%2011%2B-orange.svg?style=flat-square)](https://github.com/zyjshb/v2rayN)
[![Protocols](https://img.shields.io/badge/protocols-VLESS--Reality%20%7C%20Hysteria%202-success.svg?style=flat-square)](https://github.com/zyjshb/v2rayN)
[![Adaptive](https://img.shields.io/badge/QoS--Bypass-Smart%20Dynamic-red.svg?style=flat-square)](https://github.com/zyjshb/v2rayN)

[⚡ 快速开始](#-快速开始一键运行) • [🎯 两大版本核心对比](#-两大版本核心调优对比) • [🛠️ 快捷管理命令](#️-v2rayn-快捷管理命令) • [📱 客户端配置指南](#-客户端配置指引)

</div>

---

## 💡 为什么需要区分国内大厂云与海外 VPS？

不同厂商的机房环境和风控机制存在巨大差异，**用同一套粗放的参数去跑所有服务器必然踩坑**：

1. **国内主流云厂商（阿里云 / 腾讯云 / 华为云等海外轻量与 ECS）**：
   * **痛点**：预装大厂监控探针（Aegis、云镜、Tat、HostGuard）常驻吃掉 150MB~250MB 内存；宿主机拥有极其严苛的 **“动态令牌桶 QoS”**，一旦 Hysteria 2 启用 Brutal 暴力发包冲高 PPS，机房云盾立刻将其标记为“异常 UDP 洪流”，**直接把虚拟机总带宽掐死在 1Mbps（128 KB/s）小黑屋**；加上 1GB 小内存如果乱开 32MB+ 缓冲区，会立刻触发 Linux 内核 TCP 内存压力降速。
   * **对策**：必须深度外科手术式切除大厂监控；启用平滑 **QUIC-BBR** 拥塞控制；将内核缓冲控制在 16MB 黄金安全线；自动补充 1GB 紧凑 Swap，限制 Go 运行时内存防 OOM。

2. **海外主流 VPS 厂商（RackNerd / DMIT / 搬瓦工 / ClawCloud / Akile / V.PS 等）**：
   * **特点**：纯净无监控，网络端口普遍给足 **1Gbps ~ 2.5Gbps** 且不限速；痛点在于**中美跨洋等长距离骨干网在晚高峰时存在 5%~15% 的高丢包率**。
   * **对策**：彻底解除发包封印！激活满血 **Hysteria 2 Brutal 暴力算法**，配合 32M~64M 高 BDP 跨洋长肥管道调优、TCP Fast Open 与百万并发句柄，以暴力多发包直接碾碎跨洋网络抖动。

---

## 🚀 快速开始：一键运行

### 🤖 方式 A：全智能全自适应总入口（推荐，自动判断宿主机）
脚本会自动通过云元数据、DMI 硬件特征及网络 ASN 研判宿主机身份，并智能匹配最优调优方案：
```bash
bash <(curl -fsSL https://raw.githubusercontent.com/zyjshb/v2rayN/main/install.sh)
```
> 💡 支持参数快速直达：  
> - 强制国内大厂模式：`bash <(curl -fsSL https://raw.githubusercontent.com/zyjshb/v2rayN/main/install.sh) --cn`  
> - 强制海外狂暴模式：`bash <(curl -fsSL https://raw.githubusercontent.com/zyjshb/v2rayN/main/install.sh) --overseas`  
> - 原有老用户无感热更新：`bash <(curl -fsSL https://raw.githubusercontent.com/zyjshb/v2rayN/main/install.sh) update`

---

### 🇨🇳 方式 B：国内主流云厂商特调直装版
专门针对 **阿里云 (Aliyun)、腾讯云 (Tencent Cloud)、华为云 (Huawei Cloud)、百度云、移动云** 海外轻量服务器及 ECS 定制：
```bash
bash <(curl -fsSL https://raw.githubusercontent.com/zyjshb/v2rayN/main/install-cn.sh)
```
* **彻底拔除云监控**：自动切除 `Aegis(安骑士)`、`YunJing(云镜)`、`tat_agent`、`hostguard` 等常驻监控，释放 180MB 内存并屏蔽内网嗅探。
* **规避机房 1Mbps 锁死**：强制采用平滑 **QUIC-BBR** 发包模式（`ignoreClientBandwidth: true`），发包节奏如同正常网页浏览，绝不触发机房防 DDoS 惩罚限速。
* **小内存自愈保护**：物理内存 $\le 1\text{GB}$ 时自动配置 1GB 紧凑 Swap，注入 `GOMEMLIMIT=256MiB`，杜绝突发并发导致内核 OOM 崩溃。
* **拟态白名单 SNI**：选用 Apple CDN 官方权威域名与 Safari 伪装指纹，彻底消除主动探测特征。

---

### 🌍 方式 C：海外主流 VPS 厂商特调直装版
专门针对 **RackNerd、DMIT、搬瓦工 (BandwagonHost)、ClawCloud、AkileCloud、V.PS、Vultr、Linode、Hetzner** 等海外主机商定制：
```bash
bash <(curl -fsSL https://raw.githubusercontent.com/zyjshb/v2rayN/main/install-overseas.sh)
```
* **满血千兆 Brutal 暴力抗丢包**：服务端与客户端放开 1Gbps 发包能力，晚高峰遇 10% 跨洋丢包也能瞬间秒开 4K/8K 视频。
* **高 BDP 长管道内核重构**：TCP/UDP 缓冲区放大至 32MB~64MB，开启 `tcp_fastopen = 3` 与 FQ 队列，使跨洋长距离 TCP 单连接迅速跑满。
* **解除并发连接限制**：自动注入 Systemd `LimitNOFILE=1048576` 百万级并发句柄，支持海量连接无阻断。
* **原生全球 DNS 与 IPv4/IPv6 双栈优化**：权威双栈解析，原生支持 ChatGPT、Claude、Grok 等 AI 工具及全球流媒体。

---

## 🎯 两大版本核心调优对比

| 调优维度 | 🇨🇳 国内主流云特调版 (`install-cn.sh`) | 🌍 海外主流 VPS 特调版 (`install-overseas.sh`) |
| :--- | :--- | :--- |
| **适配厂商** | 阿里云、腾讯云、华为云、百度云等出海机型 | RackNerd、DMIT、搬瓦工、Claw、Akile、Vultr 等 |
| **内存与监控策略** | **深度切除大厂监控**，释放 180M 内存；1G Swap 防爆 | 原生极简纯净系统，30 秒秒速就绪 |
| **Hysteria 2 算法** | **平滑 QUIC-BBR**（`ignoreClientBandwidth: true`） | **满血 Brutal 暴力发包**（最高达 1Gbps~2.5Gbps） |
| **机房风控防范** | **规避令牌桶 QoS**，杜绝触发机房 1Mbps 限速小黑屋 | 海外机房不限速，专注抗击晚高峰国际骨干网高丢包 |
| **内核网络缓冲** | 严格限制在 16MB 内（防止 1G 内存触发 TCP 内存压力降速） | 大管道放宽至 32MB~64MB，开启 TCP FastOpen |
| **SNI 伪装优选** | Apple CDN 官方真实白名单 + Safari 指纹 | Microsoft 官方权威域 + Chrome 指纹 |
| **单端口双栈共存** | 支持 (TCP: VLESS-Reality + UDP: Hy2) | 支持 (TCP: VLESS-Reality + UDP: Hy2) |

---

## 🛠️ `v2rayn` 快捷管理命令

安装完成后，在服务器终端随时输入 **`v2rayn`** 即可打开可视化管理面板：

```bash
v2rayn          # 打开图形交互管理面板
v2rayn port     # 一键更换全新随机端口 (保留原密钥与配置，防单端口被封)
v2rayn status   # 查看双栈服务实时运行状态
v2rayn restart  # 平滑重启 Xray 与 Hysteria 2 服务
```

---

## 📱 客户端配置指引

### 1. v2rayN (Windows)
* 建议配合 v2rayN 最新版（内含 `sing_box` 或 `Xray` 双核心）。
* **VLESS-Reality 节点**：直接复制导入即用，日常主力推荐（最隐蔽、最安全）。
* **Hysteria 2 节点**：导入后右键“编辑服务器”，确保跳过证书验证已勾选；测试延时请使用 **“测试真实延时 (Ctrl+O)”**（因为 Hy2 是纯 UDP，普通 Tcping 会显示 `-1`）。

### 2. Clash Verge / Mihomo (Windows / Mac)
* 客户端自带的 Mihomo 内核原生完美支持两大协议，可在配置文件的 `proxies` 中直接填入：
  - Hysteria 2：`type: hysteria2`, `alpn: [h3]`, `skip-cert-verify: true`, `down: "1000 Mbps"`
  - VLESS-Reality：`type: vless`, `flow: xtls-rprx-vision`, `reality-opts: { public-key: ..., short-id: ... }`

### 3. 🎯 Hysteria 2 转 Clash Verge 专属模板与教程
针对 `hy2://` 链接无法直接导入 Clash 的问题，本项目提供了开箱即用的通用模板与 30 秒转换教程（**完全保护隐私，无任何个人信息**）：
* 📄 **通用配置文件模板**：[`clash_hysteria2_template.yaml`](clash_hysteria2_template.yaml)
* 📘 **图文转换与导入教程**：[`HOW_TO_USE_CLASH_TEMPLATE.md`](HOW_TO_USE_CLASH_TEMPLATE.md)
* 用户只需复制模板，将自己的 IP、端口、密码填入，即可导入 Clash Verge 享受 1000M 狂暴加速！

---

## 📄 开源许可证

本项目基于 [MIT License](LICENSE) 协议完全开源，纯净直接，安全无后门。
