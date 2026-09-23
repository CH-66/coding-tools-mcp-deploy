# coding-tools-mcp-deploy 2.0 操作手册

适用于现场安装、实例接入、Tunnel 配置和日常运维。

## 1. 部署前检查

先检查 Docker：

```bash
command -v docker && docker --version
```

处理原则：

- 有 Docker：安装程序直接使用现场 Docker，不覆盖、不升级；
- 没有 Docker：安装程序自动使用离线包内置 Docker Engine；
- 有 Docker 命令但 daemon 异常：安装程序直接报错，不会自动替换现场 Docker。

确认本机端口未被占用：

```bash
ss -lntp | grep -E ':(9080|9180|2379)\b'
```

无输出表示端口未被占用。

确认服务器架构：

```bash
uname -m
```

对应安装包：

| `uname -m` | 安装包 |
|---|---|
| `x86_64` | `coding-tools-mcp-deploy-2.0.1-linux-amd64.tgz` |
| `aarch64` / `arm64` | `coding-tools-mcp-deploy-2.0.1-linux-arm64.tgz` |

## 2. 安装

解压对应架构的离线包：

```bash
tar -zxf coding-tools-mcp-deploy-2.0.1-linux-amd64.tgz
cd coding-tools-mcp-deploy-2.0.1
```

执行安装：

```bash
sudo bash scripts/install.sh
```

安装完成后检查：

```bash
mcpctl version
mcpctl gateway status
mcpctl gateway doctor
```

`gateway doctor` 最终显示：

```text
Gateway: HEALTHY
```

即表示 APISIX Gateway 正常。

安装目录固定为：

```text
/opt/coding-tools-mcp
```

## 3. 添加 MCP 实例

假设代码项目目录为：

```text
/opt/projects/ntip
```

添加实例：

```bash
mcpctl add ntip /opt/projects/ntip
```

查看实例：

```bash
mcpctl list
```

查看 APISIX Route：

```bash
mcpctl gateway list
```

检查实例：

```bash
mcpctl doctor ntip
```

正常情况下各检查项应为 `PASS`。

实例创建后会自动分配 MCP 端口，并自动注册 APISIX Route。

例如：

```text
MCP 原始地址：
http://127.0.0.1:18765/mcp

APISIX 内部转发地址：
http://127.0.0.1:9080/mcp/ntip
```

以上两个地址都属于服务器内部地址，**不是最终对外访问入口**。

最终访问入口由 Tunnel 提供。

## 4. 配置 OpenAI / ChatGPT Tunnel

执行：

```bash
mcpctl tunnel openai ntip
```

首次配置只需要输入：

```text
OpenAI Tunnel ID:
OpenAI Runtime API Key:
```

Runtime API Key 输入时不会回显。

配置完成后检查：

```bash
mcpctl tunnel status ntip
```

查看实时日志：

```bash
journalctl -u coding-tools-tunnel@ntip -f
```

然后在 ChatGPT 中配置 Connector：

```text
Settings
  -> Connectors
  -> 创建或选择 Connector
  -> Connection 选择 Tunnel
  -> 选择或填写同一个 Tunnel ID
```

OpenAI Tunnel 场景下：

```text
最终访问入口：
ChatGPT Connector + Tunnel ID

Tunnel 内部目标：
http://127.0.0.1:9080/mcp/ntip
```

不需要把 `127.0.0.1:9080` 配置给最终用户。

## 5. 配置 Cloudflare Tunnel

执行：

```bash
mcpctl tunnel cloudflare ntip
```

首次配置只需要输入 Cloudflare Tunnel Token：

```text
Cloudflare Tunnel Token:
```

Token 输入时不会回显。

然后在 Cloudflare Dashboard 中给该 Tunnel 增加 Published application：

```text
Service URL:
http://127.0.0.1:9080
```

假设配置的公网域名为：

```text
mcp.example.com
```

实例名为：

```text
ntip
```

则最终 MCP 访问地址为：

```text
https://mcp.example.com/mcp/ntip
```

另一个实例 `agent` 的访问地址为：

```text
https://mcp.example.com/mcp/agent
```

Cloudflare Tunnel 场景下：

```text
最终访问入口：
https://<公网域名>/mcp/<实例名>

Tunnel 内部目标：
http://127.0.0.1:9080
```

外部 MCP Client 还需要携带对应实例的 Bearer Token。

需要配置客户端时，可在服务器上查看该实例 Token：

```bash
sudo awk -F= '$1=="MCP_AUTH_TOKEN"{print $2}' \
  /opt/coding-tools-mcp/instances/ntip/instance.env
```

## 6. 验证 Cloudflare 最终入口

先设置实例 Token：

```bash
TOKEN='实际的 MCP_AUTH_TOKEN'
```

测试最终 Tunnel 地址：

```bash
curl -i \
  -H "Authorization: Bearer $TOKEN" \
  -H 'Accept: application/json, text/event-stream' \
  -H 'Content-Type: application/json' \
  --data '{
    "jsonrpc":"2.0",
    "id":1,
    "method":"initialize",
    "params":{
      "protocolVersion":"2025-11-25",
      "capabilities":{},
      "clientInfo":{
        "name":"mcp-test",
        "version":"1.0"
      }
    }
  }' \
  https://mcp.example.com/mcp/ntip
```

能收到 MCP initialize 响应，说明链路正常：

```text
MCP Client
  -> Tunnel
  -> APISIX
  -> MCP 实例
```

## 7. 日常运维

| 操作 | 命令 |
|---|---|
| 查看所有实例 | `mcpctl list` |
| 查看 Gateway Route | `mcpctl gateway list` |
| 启动实例 | `mcpctl start ntip` |
| 停止实例 | `mcpctl stop ntip` |
| 重启实例 | `mcpctl restart ntip` |
| 查看实例日志 | `mcpctl logs ntip` |
| 检查实例 | `mcpctl doctor ntip` |
| 检查全部实例 | `mcpctl doctor` |
| 检查 APISIX | `mcpctl gateway doctor` |
| 查看 APISIX 状态 | `mcpctl gateway status` |
| 查看 APISIX 日志 | `mcpctl gateway logs` |
| 重新同步全部 Route | `mcpctl gateway sync` |
| 检查 Tunnel | `mcpctl tunnel status ntip` |
| 查看 Tunnel 日志 | `journalctl -u coding-tools-tunnel@ntip -f` |
| 关闭实例 Tunnel | `mcpctl tunnel off ntip` |

## 8. 新增第二个项目

例如新增：

```text
/opt/projects/agent
```

执行：

```bash
mcpctl add agent /opt/projects/agent
mcpctl doctor agent
mcpctl gateway list
```

如果使用 OpenAI Tunnel：

```bash
mcpctl tunnel openai agent
```

如果多个实例共用**同一个 Cloudflare Tunnel 和同一个公网域名**，不用为 `agent` 再启动一条 Tunnel。原有 Cloudflare Tunnel 已经指向 APISIX，新实例注册 Route 后即可直接访问：

```text
https://mcp.example.com/mcp/ntip
https://mcp.example.com/mcp/agent
```

如果 `agent` 要使用**独立 Cloudflare Tunnel / 独立公网域名**，再执行：

```bash
mcpctl tunnel cloudflare agent
```

并在 Cloudflare 中为该 Tunnel 单独配置 Published application。

## 9. 从 0.1.x 升级到 2.0

升级前备份实例配置：

```bash
sudo cp -a /opt/coding-tools-mcp/instances \
  /opt/coding-tools-mcp/instances.backup
```

解压 2.0 安装包后重新安装：

```bash
sudo bash scripts/install.sh
```

然后执行：

```bash
mcpctl gateway up
mcpctl gateway sync
mcpctl gateway doctor
mcpctl doctor
```

确认所有实例和 Route 正常后，再配置或恢复 Tunnel。

## 10. 常见问题

| 现象 | 处理 |
|---|---|
| `mcpctl gateway doctor` 失败 | 执行 `mcpctl gateway logs`，并检查 9080、9180、2379 是否被占用 |
| 实例显示 `stopped` | 执行 `mcpctl start <实例名>` |
| APISIX Route 不存在 | 执行 `mcpctl gateway route <实例名>`；多个实例可执行 `mcpctl gateway sync` |
| Tunnel 未启动 | 执行 `mcpctl tunnel status <实例名>` 和 `journalctl -u coding-tools-tunnel@<实例名> -f` |
| Cloudflare 返回 404 | 检查访问路径是否为 `/mcp/<实例名>`，并确认 Published application 指向 `http://127.0.0.1:9080` |
| 返回 401 | 检查客户端是否携带正确实例的 `Authorization: Bearer <token>` |
| ChatGPT 无法连接 | 检查本机 Tunnel 状态，并确认 ChatGPT Connector 绑定的是同一个 Tunnel ID |

## 11. 交付验收

| 检查项 | 命令/方式 | 通过标准 |
|---|---|---|
| Docker | `systemctl is-active docker` | `active` |
| Docker 开机启动 | `systemctl is-enabled docker` | `enabled` |
| 版本 | `mcpctl version` | 显示 `deploy=2.0.1` |
| APISIX | `mcpctl gateway doctor` | `Gateway: HEALTHY` |
| MCP 实例 | `mcpctl doctor <实例名>` | 检查项全部通过 |
| APISIX Route | `mcpctl gateway list` | 对应实例 Route 为 `active` |
| Tunnel | `mcpctl tunnel status <实例名>` | Tunnel 正常运行 |
| 最终访问 | ChatGPT Connector 或 Cloudflare 公网 URL | MCP initialize 调用成功 |
