# 2.0 架构方案：APISIX MCP Gateway

## 目标

2.0 将 `coding-tools-mcp-deploy` 从“多 MCP 实例 + Tunnel 编排”升级为“多 MCP 实例 + APISIX Gateway + Tunnel 编排”。

职责保持清晰：

- `mcpctl`：实例创建、Docker 生命周期、端口、workspace、Tunnel、APISIX Route 同步。
- APISIX：统一 HTTP 路由、流式转发、网关入口与后续流量治理扩展。
- etcd：保存 APISIX 动态配置。
- MCP 实例：仍保留各自 Bearer Token，APISIX 不保存业务 Token。
- Tunnel：OpenAI Tunnel 可指向 APISIX 的实例路由；Cloudflare 可把 Hostname 指向 APISIX，并用路径区分实例。

## 数据面

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
 127.0.0.1:18765  :18766      :18767
       |          |           |
      /mcp       /mcp        /mcp
```

APISIX Route 使用 `proxy-rewrite` 将 `/mcp/<instance>` 重写为后端的 `/mcp`，并启用 `proxy-buffering.disable_proxy_buffering=true`，保证 MCP Streamable HTTP / SSE 不被代理缓冲。

## 管理面

```text
mcpctl gateway up
        |
        +--> etcd (127.0.0.1:2379)
        |
        +--> APISIX (127.0.0.1:9080)
                 |
                 +--> Admin API (127.0.0.1:9180)
```

Admin API Key 在安装时随机生成，保存为：

```text
/opt/coding-tools-mcp/gateway/admin.key
```

权限为 `0600`。Admin API 与 etcd 都只监听回环地址，不暴露到外部网络。

## 路由生命周期

### add

```text
mcpctl add ntip /opt/projects/ntip
  -> 分配 MCP_PORT
  -> 启动 MCP
  -> PUT APISIX route mcp-ntip
```

### start / restart

实例启动后重新确保 Route 存在，允许 APISIX 配置被重建后自动恢复。

### stop

停止实例前删除 Route，避免外部流量命中已停止 upstream。

### remove

删除 Route、Tunnel 和容器，然后删除实例目录。

### sync

`mcpctl gateway sync` 以本地 `instances/*/instance.env` 为事实来源，重新创建全部 APISIX Route，并把旧版实例迁移到 `MCP_GATEWAY=apisix`。

## 路由模型

实例 `ntip`：

```text
Route ID: mcp-ntip
URI:      /mcp/ntip
Upstream: 127.0.0.1:18765
Rewrite:  /mcp
Timeout:  connect=5, send=300, read=300
Buffer:   disabled
```

客户端 Bearer Token 原样透传到 MCP，不在 APISIX 中复制一份认证信息。

## Tunnel

### OpenAI / ChatGPT Secure MCP Tunnel

2.0 中 OpenAI Tunnel 的 MCP target 为：

```text
http://127.0.0.1:9080/mcp/<instance>
```

`tunnel-client` 继续注入该实例的 Bearer Token。

### Cloudflare Tunnel

生产 Tunnel 的 Published application Service URL 指向：

```text
http://127.0.0.1:9080
```

外部 MCP URL：

```text
https://<hostname>/mcp/<instance>
```

Quick Tunnel 为避免不同 cloudflared 版本对 origin path 的处理差异，仍直接指向实例原始 `/mcp` 地址。

## 离线交付

2.0 离线包新增：

- `apache/apisix:3.18.0-debian`
- amd64：`bitnamilegacy/etcd:3.5.11`；arm64：`rancher/coreos-etcd:v3.4.15-arm64`，构建时统一 retag 为 `coding-tools-etcd:2.0.0`
- `compose/gateway-compose.yml`
- `gateway/config.yaml.tpl`

所有镜像在联网构建机按目标原生架构拉取并执行 `docker save`。etcd 会按架构选择 APISIX 官方 Docker 示例使用的兼容镜像，再统一 retag 为运行时固定镜像名。现场安装阶段只执行 `docker load`，不访问 Docker Hub、GitHub 或软件源。

## 兼容策略

- 保留原 `compose/docker-compose.yml` 和独立 MCP 容器模型。
- 保留旧实例 `WORKSPACE_DIR` 的读取兼容。
- 旧实例缺少 `MCP_GATEWAY` 时按 `direct` 处理；执行 `mcpctl gateway sync` 后迁移为 `apisix`。
- Docker Compose 继续使用离线包内 standalone 二进制，适配 Docker 18.09 现场环境。
- APISIX 与 etcd 使用 host network，使 APISIX 能直接访问 MCP 的 `127.0.0.1:<port>`，不依赖 Linux 上较新的 `host.docker.internal` 能力。
