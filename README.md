# coding-tools-mcp-deploy

`coding-tools-mcp-deploy` 是 `xyTom/coding-tools-mcp` 的离线部署、多项目实例、APISIX Gateway 与 Tunnel 编排层。

## 2.0 架构

2.0 引入 Apache APISIX 作为统一 MCP HTTP Gateway：

```text
OpenAI Tunnel / Cloudflare / Local Client
                  |
                  v
          127.0.0.1:9080
               APISIX
                  |
       +----------+-----------+
       |          |           |
 /mcp/ntip  /mcp/agent  /mcp/frontend
       |          |           |
       v          v           v
    :18765      :18766      :18767
       |          |           |
      /mcp       /mcp        /mcp
```

职责边界：

- `mcpctl`：MCP 实例生命周期、workspace、端口、Tunnel、APISIX Route 同步。
- APISIX：统一 HTTP 路由、URI 重写、流式转发与后续流量治理。
- etcd：保存 APISIX 动态配置。
- MCP：继续使用每实例独立 Bearer Token，认证信息不会复制到 APISIX。
- Tunnel：负责公网/ChatGPT 到本机 Gateway 或 MCP 的安全传输。

详细设计见 `docs/v2-design.md`。

## MCP 多实例

一台 Linux 主机可以同时运行多个互相隔离的 MCP：

```text
project-a -> coding-tools-mcp-project-a -> 127.0.0.1:18765
project-b -> coding-tools-mcp-project-b -> 127.0.0.1:18766
project-c -> coding-tools-mcp-project-c -> 127.0.0.1:18767
```

每个实例独立拥有：

- workspace
- MCP 端口
- Bearer Token
- permission mode
- Docker container
- APISIX Route
- Tunnel 配置

所有实例共享 MCP 镜像、Compose 模板和 APISIX Gateway。

## 安装

现场只需要 Docker daemon 已安装并运行。

```bash
tar -zxf coding-tools-mcp-deploy-2.0.0-linux-amd64.tgz
cd coding-tools-mcp-deploy-2.0.0
sudo bash scripts/install.sh
```

安装程序会：

1. 安装包内固定版本的 Docker Compose standalone；
2. `docker load` MCP、APISIX、etcd 离线镜像；
3. 安装 OpenAI `tunnel-client` 和 Cloudflare `cloudflared`；
4. 生成随机 APISIX Admin API Key；
5. 启动 APISIX + etcd；
6. 将已有实例同步到 APISIX。

如明确不希望安装后自动启动 Gateway：

```bash
sudo MCP_GATEWAY_AUTO_START=off bash scripts/install.sh
```

## APISIX Gateway

常用管理：

```bash
mcpctl gateway up
mcpctl gateway down
mcpctl gateway restart
mcpctl gateway status
mcpctl gateway logs
mcpctl gateway doctor
```

查看实例 Route：

```bash
mcpctl gateway list
```

把所有本地实例同步到 APISIX：

```bash
mcpctl gateway sync
```

单实例切换：

```bash
mcpctl gateway route ntip
mcpctl gateway unroute ntip
```

`route` 会把实例设置为 `MCP_GATEWAY=apisix`；`unroute` 会删除 APISIX Route 并恢复 direct 模式。

### Route 规则

例如实例 `ntip`：

```text
http://127.0.0.1:9080/mcp/ntip
                    |
                    | APISIX proxy-rewrite
                    v
http://127.0.0.1:18765/mcp
```

Route 会启用：

- `proxy-rewrite`：`/mcp/<instance>` -> `/mcp`
- `proxy-buffering.disable_proxy_buffering=true`：适配 MCP Streamable HTTP / SSE
- connect timeout：5s
- send/read timeout：300s

## 实例管理

添加多个项目：

```bash
mcpctl add ntip /opt/projects/ntip
mcpctl add agent /opt/projects/agent
mcpctl add frontend /opt/projects/frontend
```

端口从 18765 开始自动分配。

APISIX 正常运行时，`mcpctl add` 会自动创建 Route。

常用命令：

```bash
mcpctl list
mcpctl start ntip
mcpctl stop ntip
mcpctl restart ntip
mcpctl logs ntip
mcpctl doctor ntip
mcpctl doctor
mcpctl remove ntip
```

实例停止或删除时，APISIX Route 会同步删除；再次启动时 Route 会自动恢复。

## OpenAI / ChatGPT Secure MCP Tunnel

使用官方 `openai/tunnel-client`。

首次配置只保留两个必要输入：

1. Tunnel ID
2. Runtime API Key（`CONTROL_PLANE_API_KEY`）

```bash
mcpctl tunnel openai ntip
```

APISIX 模式下，Tunnel 的本地 MCP target 自动变为：

```text
http://127.0.0.1:9080/mcp/ntip
```

`tunnel-client` 仍会注入该实例自己的：

```text
Authorization: Bearer <MCP_AUTH_TOKEN>
```

已有凭据也支持非交互：

```bash
mcpctl tunnel openai ntip tunnel_xxx /root/secrets/openai-runtime-key
```

Tunnel 启动后，在 ChatGPT Connector 中选择相同 Tunnel ID。

## Cloudflare Tunnel

生产模式：

```bash
mcpctl tunnel cloudflare ntip
```

APISIX 模式下，Cloudflare Published application 的 Service URL 配置为：

```text
http://127.0.0.1:9080
```

外部 MCP URL：

```text
https://<your-hostname>/mcp/ntip
```

客户端继续携带该实例的 Bearer Token。

Quick Tunnel：

```bash
mcpctl tunnel cloudflare-quick ntip
```

Quick Tunnel 仍直连实例原始 `/mcp` 地址，避免依赖 cloudflared 对 origin path 的版本差异。

## Tunnel 状态

```bash
mcpctl tunnel status ntip
journalctl -u coding-tools-tunnel@ntip -f
```

关闭 Tunnel：

```bash
mcpctl tunnel off ntip
```

## 离线定义

这里的“离线”指安装离线：

- 现场不访问 GitHub；
- 不执行 apt/pip/npm/go 在线安装；
- MCP Docker image 已包含；
- APISIX Docker image 已包含；
- etcd Docker image 已包含；
- Docker Compose standalone 已包含；
- OpenAI `tunnel-client` 已包含；
- Cloudflare `cloudflared` 已包含；
- 安装阶段不下载任何运行组件。

Tunnel 运行时仍需要出站访问相应厂商公网服务。

## 构建离线包

联网构建机：

```bash
make offline-pkg
```

构建过程：

1. 拉取并构建 `coding-tools-mcp`；
2. 保存 MCP 镜像；
3. 拉取并保存 APISIX 3.18.0；
4. 按目标架构选择并保存 etcd；
5. 下载并校验 Docker Compose standalone；
6. 下载 OpenAI `tunnel-client`；
7. 下载 Cloudflare `cloudflared`；
8. 生成 SHA256SUMS；
9. 输出 tgz。

当前固定版本：

```text
coding-tools-mcp      0.3.0
Docker Compose        v2.20.3
Apache APISIX         3.18.0
etcd amd64            3.5.11 (bitnamilegacy)
etcd arm64            3.4.15 (rancher/coreos-etcd)
openai tunnel-client  v0.0.14
cloudflared           2026.9.1
```

支持 Linux amd64 和 arm64。离线包采用原生架构构建。

输出：

```text
dist/coding-tools-mcp-deploy-2.0.0-linux-amd64.tgz
dist/coding-tools-mcp-deploy-2.0.0-linux-arm64.tgz
```

## 安装后目录

```text
/opt/coding-tools-mcp/
├── bin/
│   ├── mcpctl
│   ├── docker-compose
│   ├── tunnel-client
│   └── cloudflared
├── compose/
│   ├── docker-compose.yml
│   └── gateway-compose.yml
├── config/
│   └── versions.env
├── gateway/
│   ├── admin.key
│   ├── config.yaml
│   ├── config.yaml.tpl
│   └── data/
│       └── etcd/
├── instances/
│   └── <instance>/
│       ├── instance.env
│       └── secrets/
└── tunnel/
    ├── run.sh
    └── providers/
```

## 安全默认值

- MCP 实例仅绑定宿主机 `127.0.0.1`；
- APISIX Gateway 仅绑定 `127.0.0.1:9080`；
- APISIX Admin API 仅绑定 `127.0.0.1:9180`；
- etcd 仅监听 `127.0.0.1:2379`；
- APISIX Admin Key 安装时随机生成，文件权限 `0600`；
- 每个 MCP 实例使用独立 Bearer Token；
- Secret 文件权限 `0600`；
- 实例目录权限 `0700`；
- `instance.env` 不通过 shell `source` 执行，字段按白名单读取；
- workspace 路径使用 Base64 保存；
- Cloudflare Token 使用 token file；
- `cloudflared --no-autoupdate`；
- MCP telemetry 默认关闭。

## 2.0 升级

从 0.1.x 覆盖安装 2.0 后执行：

```bash
mcpctl gateway up
mcpctl gateway sync
mcpctl gateway doctor
mcpctl doctor
```

旧实例缺少 `MCP_GATEWAY` 时默认保持 direct；`gateway sync` 会将其迁移到 APISIX 并创建对应 Route。

## 上游

- https://github.com/xyTom/coding-tools-mcp
- https://github.com/apache/apisix
- https://github.com/apache/apisix-docker
- https://github.com/docker/compose
- https://github.com/openai/tunnel-client
- https://github.com/cloudflare/cloudflared
