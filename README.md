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

使用官方 `openai/tunnel-client`：

```bash
mcpctl tunnel openai ntip tunnel_xxx /root/secrets/openai-runtime-key
```

OpenAI Tunnel 通过出站 HTTPS 与控制面通信。本地 MCP 继续启用 Bearer 认证，`tunnel-client` 会为访问本地 MCP 的请求附加该实例的 Authorization Header。

### Cloudflare Tunnel

生产模式使用官方 `cloudflared` 的 remotely-managed named tunnel：

```bash
mcpctl tunnel cloudflare ntip /root/secrets/cloudflare-tunnel-token
```

然后在 Cloudflare Public Hostname / Published Application 中把 Service URL 配为命令输出的：

```text
http://127.0.0.1:<实例端口>
```

临时测试也支持：

```bash
mcpctl tunnel cloudflare-quick ntip
```

Quick Tunnel 不作为生产方案。Cloudflare 只负责公网传输；外部 MCP 客户端仍需按 MCP 服务认证方式提供认证信息。

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
tar -zxf coding-tools-mcp-deploy-0.1.0-linux-amd64.tgz
cd coding-tools-mcp-deploy-0.1.0
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

支持 Linux amd64 和 arm64。

输出：

```text
dist/coding-tools-mcp-deploy-0.1.0-linux-amd64.tgz
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
