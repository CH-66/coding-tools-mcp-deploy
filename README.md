# coding-tools-mcp-deploy

`coding-tools-mcp-deploy` 是 `xyTom/coding-tools-mcp` 的离线部署、多项目实例管理和 Tunnel 编排层。

## 架构

一台 Linux 主机可以同时运行多个相互隔离的 MCP：

```text
project-a -> coding-tools-mcp-project-a -> 127.0.0.1:18765
project-b -> coding-tools-mcp-project-b -> 127.0.0.1:18766
project-c -> coding-tools-mcp-project-c -> 127.0.0.1:18767
```

每个实例独立拥有 workspace、端口、Bearer Token、权限模式、容器和 Tunnel 配置。所有实例共享同一个 MCP 镜像与 Compose 模板。

## Tunnel Provider

### OpenAI / ChatGPT Secure MCP Tunnel

使用官方 `openai/tunnel-client`。首次配置只保留 **2 个必要输入**：

1. **Tunnel ID**
   - 获取/创建：`https://platform.openai.com/settings/organization/tunnels`
   - 格式：`tunnel_` + 32 位小写十六进制字符。
2. **Runtime API Key（CONTROL_PLANE_API_KEY）**
   - 创建：`https://platform.openai.com/settings/organization/api-keys`
   - 建议使用 Restricted key，并授予目标 Tunnel 所需的 **Tunnels Read + Use**。

正常运行 **不需要 `OPENAI_ADMIN_KEY`**。Admin Key 只在使用
`tunnel-client admin tunnels create|list|update|delete` 管理 Tunnel 时需要。

最简交互式配置：

```bash
mcpctl tunnel openai ntip
```

命令只会在缺失时询问：

```text
OpenAI Tunnel ID:
OpenAI Runtime API Key:   # 隐藏输入
```

Runtime API Key 会保存到实例 `secrets/`，权限为 `0600`，后续重复执行会直接复用，不再次询问。

已有凭据时也支持非交互：

```bash
# Tunnel ID 可通过参数或环境变量提供；Runtime Key 推荐用文件提供
mcpctl tunnel openai ntip tunnel_xxx /root/secrets/openai-runtime-key

# 或
export OPENAI_TUNNEL_ID=tunnel_xxx
export CONTROL_PLANE_API_KEY='sk-...'
mcpctl tunnel openai ntip
unset CONTROL_PLANE_API_KEY
```

Tunnel 启动后还有 **1 个必须人工完成的 ChatGPT 操作**：

1. 打开 `https://chatgpt.com/#settings/Connectors`；
2. 创建/选择 Connector；
3. 选择 **Connection: Tunnel**；
4. 选择或粘贴与本机相同的 Tunnel ID。

本地 MCP 继续启用 Bearer 认证，`tunnel-client` 会给访问本地 MCP 的请求附加该实例的 Authorization Header。

### Cloudflare Tunnel

生产模式使用官方 `cloudflared` 的 remotely-managed named tunnel。首次配置只保留 **1 个必要输入**：

1. **Cloudflare Tunnel Token**
   - Cloudflare Dashboard：**Networking > Tunnels > 选择 Tunnel > Add a replica**；
   - 从显示的 `cloudflared` 命令中复制长的 `eyJ...` Token。

已经有 Tunnel Token 时，运行连接器 **不需要 Cloudflare API Token**。

最简交互式配置：

```bash
mcpctl tunnel cloudflare ntip
```

命令只会在本地没有已保存 Token 时询问：

```text
Cloudflare Tunnel Token:   # 隐藏输入
```

Token 会保存到实例 `secrets/`，权限为 `0600`，后续重复执行会直接复用。

已有 Token 文件时可完全非交互：

```bash
mcpctl tunnel cloudflare ntip /root/secrets/cloudflare-tunnel-token
```

或通过环境变量一次性提供：

```bash
export CLOUDFLARE_TUNNEL_TOKEN='eyJ...'
mcpctl tunnel cloudflare ntip
unset CLOUDFLARE_TUNNEL_TOKEN
```

Tunnel 启动后还有 **1 个必须人工完成的 Cloudflare 路由配置**：

1. Dashboard：**Networking > Tunnels > 选择 Tunnel > Routes > Add route > Published application**；
2. 自行选择公网 Hostname；
3. Service URL 填命令输出的：
   ```text
   http://127.0.0.1:<实例端口>
   ```

脚本不会询问 Hostname，因为它不是启动 `cloudflared` 的必要输入，且应由 Cloudflare 侧路由配置管理。

Cloudflare 只提供公网传输，因此外部 MCP 客户端还需要访问：

```text
https://<你的公网 Hostname>/mcp
```

并携带该实例现有的：

```text
Authorization: Bearer <MCP_AUTH_TOKEN>
```

`MCP_AUTH_TOKEN` 在 `mcpctl add` 时已经自动生成，保存在该实例的
`instance.env` 中，**无需再让用户创建或输入一个新 Token**。

临时测试仍支持：

```bash
mcpctl tunnel cloudflare-quick ntip
```

Quick Tunnel 不作为生产方案。Cloudflare 只负责公网传输；外部 MCP 客户端仍需按 MCP 服务认证方式提供认证信息。

### 交互原则

`mcpctl tunnel` 遵循“只问必要信息”：

- 已存在实例配置：不问；
- 已保存 Secret：不问；
- 能从实例自动得到的 MCP 端口、目标 URL、Bearer Token：不问；
- OpenAI Admin Key：正常运行不问；
- Cloudflare API Token：已有 Tunnel Token 时不问；
- Cloudflare 公网 Hostname：不问，只提示到 Dashboard 配置；
- 所有交互式 Secret 均隐藏输入。

可随时查看提示：

```bash
mcpctl tunnel help
```

## 离线定义

这里的“离线”指 **安装离线**：

- 现场不访问 GitHub；
- 不执行 apt/pip/npm/go 在线安装；
- MCP Docker image 已包含在交付包；
- OpenAI `tunnel-client` 已包含在交付包；
- Cloudflare `cloudflared` 已包含在交付包；
- 安装阶段不下载任何运行组件。

Tunnel 运行时仍然必须能够出站访问对应厂商公网服务。机器完全断网时，公网 Tunnel 不可能建立。

## 安装后目录

```text
/opt/coding-tools-mcp/
├── bin/
│   ├── mcpctl
│   ├── tunnel-client
│   └── cloudflared
├── compose/
│   └── docker-compose.yml
├── config/
│   └── versions.env
├── instances/
│   ├── ntip/
│   │   ├── instance.env
│   │   └── secrets/
│   └── agent/
│       ├── instance.env
│       └── secrets/
└── tunnel/
    ├── run.sh
    └── providers/
        ├── openai.sh
        └── cloudflare.sh
```

`instances/` 只保存实例配置和 Secret，不复制代码项目。

## 使用

安装离线包：

```bash
tar -zxf coding-tools-mcp-deploy-0.1.1-linux-amd64.tgz
cd coding-tools-mcp-deploy-0.1.1
sudo bash scripts/install.sh
```

添加多个项目：

```bash
mcpctl add ntip /opt/projects/ntip
mcpctl add agent /opt/projects/agent
mcpctl add frontend /opt/projects/frontend
```

端口从 18765 开始自动分配。

常用管理：

```bash
mcpctl list
mcpctl start ntip
mcpctl stop ntip
mcpctl restart ntip
mcpctl logs ntip
mcpctl doctor ntip
mcpctl doctor
```

Tunnel 状态：

```bash
mcpctl tunnel status ntip
journalctl -u coding-tools-tunnel@ntip -f
```

关闭 Tunnel：

```bash
mcpctl tunnel off ntip
```

## 构建完整离线包

在有互联网的构建机：

```bash
make offline-pkg
```

构建机会固定版本完成以下动作：

1. 拉取并构建 `coding-tools-mcp`；
2. `docker save` MCP 镜像；
3. 下载 OpenAI `tunnel-client` 对应架构 release；
4. 下载 Cloudflare `cloudflared` 对应架构 release；
5. 生成 `SHA256SUMS`；
6. 输出完整 tgz。

当前锁定：

```text
coding-tools-mcp      0.3.0
openai tunnel-client  v0.0.14
cloudflared           2026.9.1
```

支持 Linux amd64 和 arm64。V0.1 采用原生架构构建：amd64 构建机生成 amd64 包，arm64 构建机生成 arm64 包，避免 Docker 镜像架构与 Tunnel 二进制架构不一致。

输出：

```text
dist/coding-tools-mcp-deploy-0.1.1-linux-amd64.tgz
```

## 安全默认值

- MCP 仅绑定宿主机 `127.0.0.1`；
- 每个实例独立 Bearer Token；
- Secret 文件权限 0600；
- 实例目录权限 0700；
- Cloudflare 使用 token file，避免把 token 放进进程参数；
- `cloudflared --no-autoupdate`；
- MCP telemetry 默认关闭；
- 默认 `trusted`，可按实例调整为 `safe`。

## 上游

- https://github.com/xyTom/coding-tools-mcp
- https://github.com/openai/tunnel-client
- https://github.com/cloudflare/cloudflared
