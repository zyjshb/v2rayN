<div align="center">

# ⚡ v2rayN / Xray & Hysteria 2 极速并发安装脚本 (v3.1 旗舰版)

> 单端口四层协议栈并发黑科技：TCP (VLESS-Reality) + UDP (Hysteria 2) 零冲突共存  
> **全自动随机安全端口 • 老用户无感热更新 (保留原端口/链接) • 全局 `v2rayn` 快捷管理 • 抗指纹 X509v3 证书**

[![License](https://img.shields.io/badge/license-MIT-blue.svg?style=flat-square)](LICENSE)
[![Release](https://img.shields.io/badge/release-v3.1%20Flagship-brightgreen.svg?style=flat-square)](https://github.com/zyjshb/v2rayN)
[![Platform](https://img.shields.io/badge/platform-Ubuntu%2020.04%2B%20%7C%20Debian%2011%2B-orange.svg?style=flat-square)](https://github.com/zyjshb/v2rayN)
[![Protocol](https://img.shields.io/badge/protocols-VLESS--Reality%20%7C%20Hy2-success.svg?style=flat-square)](https://github.com/zyjshb/v2rayN)
[![Network](https://img.shields.io/badge/Bandwidth-200M%2B%20Uncapped-red.svg?style=flat-square)](https://github.com/zyjshb/v2rayN)

[一键安装与无感更新](#-一键安装与无感更新) • [v3.1 旗舰特性](#-v31-旗舰级特性升级) • [快捷管理命令](#-v2rayn-全局快捷管理命令) • [客户端支持](#-客户端导入说明)

</div>

---

## 💡 为什么选择本项目？

传统脚本要么操作繁琐，要么**写死默认端口与固定 3650 天自签名证书**，极易被防火墙批量嗅探封锁。

本项目利用 Linux 底层传输层 TCP 与 UDP 独立命名空间原理，实现**同一个端口同时并发运行两大王牌协议**，并在 **v3.1 旗舰版**中实现了**「新装零交互自动给随机端口」+「老用户一行指令无损热更新」**：

```
                                   ┌──► TCP (随机端口) ──► Xray VLESS + XTLS-Vision + REALITY (动态大厂证书隐身)
客户端数据请求 ───► [同一高安全随机端口]
                                   └──► UDP (随机端口) ──► Hysteria 2 + Salamander + SHA256 指纹锁 (暴力跑满 200M)
```

---

## 🚀 一键安装与无感更新

以 `root` 用户登录服务器，复制对应命令直接运行：

### 1️⃣ 全新安装（零交互全自动生成随机安全端口，装完去安全组放行即可）
```bash
bash <(curl -fsSL https://raw.githubusercontent.com/zyjshb/v2rayN/main/install.sh)
```
> 💡 **极简体验**：新机器运行无需任何键盘输入，脚本会自动避开已占用端口，为你随机分配一个 `20000~60000` 之间的干净高位端口，并在最后醒目提示你需要去云控制台安全组放行该端口！

### 2️⃣ 老用户一键「无感热更新」（保留原有端口、密钥和客户端链接 100% 不变！）
```bash
bash <(curl -fsSL https://raw.githubusercontent.com/zyjshb/v2rayN/main/install.sh) update
```
> 🔄 **无缝升级**：如果你之前已经安装过旧版本，运行此命令会**自动提取并保留你现有的端口号、UUID、密码和节点链接**，在后台无缝升级最新内核、BBR+TFO 调优、BT 防投诉拦截与进程崩溃自愈，**手机和电脑客户端无需重新导入节点！**

---

## 🛡️ v3.1 旗舰级特性升级

| 模块维度 | 传统脚本痛点 | 本项目 v3.1 旗舰解决方案 |
| :--- | :--- | :--- |
| **零打扰随机端口** | 安装时反复追问配置，或者所有人共用死端口 | 全新安装**零交互自动生成 `20000~60000` 未占用高位端口**，结尾高亮提醒安全组放行 |
| **老用户无感热更新** | 每次更新脚本都会重置端口和密钥，需重新配客户端 | 内置逆向配置提取引擎，支持 `update` **原位无损升级**，原端口与客户端链接完全不变 |
| **全局 `v2rayn` 命令** | 装完找不到管理入口，记不住复杂 systemctl 命令 | 自动注册系统级 **`v2rayn` 快捷指令**，支持可视化菜单、查链接、扫码、改端口、重启、卸载 |
| **REALITY 动态优选池** | 写死单一域名，容易特征聚集或路由阻断 | 内置 **Apple / Microsoft / AMD 等 TLS 1.3 大厂域名池**，安装时自动测速握手并随机分配浏览器指纹 |
| **Hy2 证书抗指纹** | 固定 `3650` 天有效期、单一 CN、无扩展，一探即露馅 | **随机证书有效期 (`365~1095` 天)** + **随机跨国企业组织 (`O`)** + **完整 X509v3 SAN 扩展** + **`pinSHA256` 指纹锁** |
| **高并发防崩自愈** | 200M 跑满时默认 `1024` 句柄耗尽导致进程假死断流 | 自动注入 Systemd `LimitNOFILE=1048576` 百万级并发句柄与 `Restart=always` 3秒自动复活保护 |
| **云监控深度切除** | 仅清理简单进程，残留云助手探针 | 全自动卸载 **阿里云 (Aegis/云助手)、腾讯云 (Tat/Barad/云镜)、华为云 (HostGuard)** 监控全家桶 |

---

## 🛠️ `v2rayn` 全局快捷管理命令

安装或更新完成后，在服务器终端随时输入 **`v2rayn`** 即可调出管理面板或执行快捷操作：

| 快捷命令 | 功能说明 |
| :--- | :--- |
| `v2rayn` | 打开交互式可视化管理面板（默认回车即为无感热更新） |
| `v2rayn update` | **无感热更新**：保留原端口与原链接不变，升级最新内核与安全配置 |
| `v2rayn info` | 查看当前双协议纯文本节点链接及需放行的端口号 |
| `v2rayn qr` | **按需显示二维码**：在终端打印双节点二维码供手机扫码导入 |
| `v2rayn port` | **仅更换端口**：保留原有密钥，一键切换为新随机端口 |
| `v2rayn restart` | 一键重启 Xray 与 Hysteria 2 双栈服务 |
| `v2rayn status` | 查看双栈服务实时运行状态与日志 |
| `v2rayn uninstall` | 彻底卸载服务并清理所有残留文件 |

---

## 🖥️ 终端部署效果预览

```text
========================================================================
🎉 单端口 [54321] 双协议并发部署完成 (v3.1 旗舰安全版)
========================================================================
• TCP 54321 状态 (Xray VLESS-Reality-Vision): active (running)
• UDP 54321 状态 (Hysteria 2 + Salamander) : active (running)
• REALITY 伪装目标 : www.microsoft.com (指纹: firefox)
• Hy2 媒体伪装目标 : stun.teams.microsoft.com
• BT 迅雷流量拦截  : 已开启 (防止版权投诉封机)
------------------------------------------------------------------------
1. 【Hysteria 2 满血暴力节点】（UDP 54321 | 200M 提速 | Salamander 混淆）：
hy2://Pass@203.0.113.10:54321/?insecure=1&pinSHA256=E9:3B:...&sni=stun.teams.microsoft.com&obfs=salamander...

2. 【VLESS-Reality 隐身防封节点】（TCP 54321 | Vision 流控 | 大厂证书伪装）：
vless://uuid@203.0.113.10:54321?encryption=none&flow=xtls-rprx-vision&security=reality&sni=www.microsoft.com&fp=firefox...
========================================================================
⚠️ 【重要一步】请前往您的云服务商控制台 ->「安全组 / 防火墙」放行以下端口：
👉 协议: TCP + UDP   |   端口范围: 54321
------------------------------------------------------------------------
💡 快捷管理命令：
   • 输入 v2rayn       打开管理面板 / 无感更新
   • 输入 v2rayn info  查看纯文本节点链接
   • 输入 v2rayn qr    按需生成手机扫码二维码
========================================================================
```

---

## 📱 客户端导入说明

本脚本输出的标准链接与二维码支持市面上所有主流客户端：

- **Windows**: [v2rayN](https://github.com/233boy/v2rayN) / [Clash Verge Rev](https://github.com/clash-verge-rev/clash-verge-rev) / [Sing-box](https://github.com/SagerNet/sing-box)
- **Android**: [v2rayNG](https://github.com/233boy/v2rayNG) / [NekoBox](https://github.com/MatsuriDayo/NekoBoxForAndroid)
- **iOS / macOS**: [Sing-box](https://sing-box.sagernet.org/) / [Shadowrocket](https://apps.apple.com/app/shadowrocket/id932747118) / [Loon](https://nsloon.com/) / [Surge](https://nssurge.com/)

---

## ⚠️ 免责声明
本项目仅供网络技术研究、传输层安全测试与合法运维使用，请严格遵守您所在地区的法律法规。
