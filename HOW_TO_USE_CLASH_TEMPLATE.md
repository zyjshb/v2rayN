# 📘 Hysteria 2 节点一键转换 Clash Verge 配置文件教程

> 很多小伙伴部署完 Hysteria 2 之后，手里只有一串类似 `hy2://...` 的链接，但在电脑端使用 **Clash Verge** 时，发现无法直接将原生 `hy2://` 链接一键粘贴导入，也不知道 Clash 的 YAML 文件怎么手写。  
> 本教程带你 **30 秒** 看懂转换规则，并利用通用模板极速生成属于你自己的高速配置文件！

---

## 一、速查对照表（拆解 `hy2://` 链接）

假设你的脚本或服务商给你的链接长这样：

```text
hy2://mypassword123@45.76.120.88:38421?insecure=1&sni=turn.live.com#MyTokyoNode
```

将其逐段拆解，与 Clash 配置文件的对应关系如下：

| `hy2://` 链接中的片段 | 代表含义 | 对应 Clash 配置文件中的字段 | 填写示例 |
| :--- | :--- | :--- | :--- |
| `mypassword123` | 连接认证密码 | `password:` | `"mypassword123"` （加英文双引号） |
| `45.76.120.88` | 服务器 IP 或解析域名 | `server:` | `45.76.120.88` |
| `38421` | 服务器端口号 | `port:` | `38421` |
| `sni=turn.live.com` | TLS 伪装域名 | `sni:` | `turn.live.com` |
| `insecure=1` | 跳过证书校验 | `skip-cert-verify:` | `true` （若为 0 则填 `false`） |
| `#MyTokyoNode` | 节点备注名 | `name:` | `"⚡ 东京-Hysteria2"` （可任意取名） |

---

## 二、修改模板操作步骤（只需 3 步）

### 第一步：获取通用模板文件
在仓库根目录下找到：  
👉 **`clash_hysteria2_template.yaml`**  
*(建议复制一份并重命名为例如 `my_clash_profile.yaml`)*

### 第二步：用记事本编辑替换
用 Windows 自带的 **记事本**（或 VSCode、Notepad++）打开该文件，找到第 37 行开始的 `proxies` 区域：

```yaml
proxies:
  - name: "⚡ 我的Hysteria2节点"      # 取一个你喜欢的名字
    type: hysteria2                 # 保持不变
    server: 1.2.3.4                 # 改成你的服务器真实 IP
    port: 25000                     # 改成你的端口
    password: "YourPasswordHere"    # 改成你的真实密码（注意双引号）
    sni: turn.live.com              # 保持或改成你的 SNI 伪装域名
    skip-cert-verify: true          # 自签证书保持 true
    alpn:
      - h3                          # 保持不变
    up: "100 Mbps"                  # 建议保留（提供充足上行缓存）
    down: "1000 Mbps"               # 建议保留（激活 1Gbps 满血 Brutal 油门）
```

> ⚠️ **新手必看注意事项**：
> 1. YAML 文件**对缩进极其严格**，修改时请不要多打空格或删除行首的空格。
> 2. 下方的 `proxy-groups` 里的节点名称，必须和上面 `name:` 的文字一模一样。

---

## 三、导入 Clash Verge 客户端

1. 打开 **Clash Verge** 软件。
2. 点击左侧菜单栏的 **【订阅】（Profiles）**。
3. 点击页面顶部的 **【新建】（New）** 按钮：
   * **类型（Type）**：选择 **`Local`**（本地文件）。
   * **名称（Name）**：随便填，比如 `我的海外节点`。
   * 点击 **【浏览】（Browse）**，选中你刚刚保存的 `.yaml` 配置文件。
   * 点击 **【保存】（Save）**。
4. 在订阅列表里，**右键**点击该配置，选择 **【选择 / Select】**（高亮激活）。
5. 点击左侧菜单栏的 **【代理】（Proxies）**，确认看到你的节点并勾选它。
6. 打开系统代理，立刻尽享千兆极速！
