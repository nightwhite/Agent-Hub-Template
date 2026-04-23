# Hermes 测试文档

这份文档用于说明当前仓库中 `agents/hermes` 的测试方式，分为两部分：

- 本地测试
- GitHub Actions 测试

文档目标是让任何维护者都能按同一套流程验证 Hermes 镜像是否可构建、可运行、可发布。

---

## 一、测试范围

当前 Hermes 目录的主要能力包括：

- 镜像构建
- 容器启动
- `gateway` 命令启动
- API Server 监听与响应
- `config.sh` 配置命令
- GHCR 发布

这份文档围绕这些能力给出可重复执行的测试步骤。

---

## 二、前置条件

执行本地测试前，建议确认以下条件：

- 已安装 Docker
- 当前机器可以访问：
  - `ghcr.io/gitlayzer/ubuntu:22.04-base`
  - `https://github.com/NousResearch/hermes-agent.git`
- 当前仓库目录为：

```bash
/Users/sealos/Agent-Hub-Template
```

- 当前使用的 Hermes Dockerfile 是：

```bash
agents/hermes/Dockerfile
```

---

## 三、本地测试

### 3.1 Shell 语法检查

先确认 Hermes 目录内脚本语法没有问题：

```bash
bash -n agents/hermes/install.sh
bash -n agents/hermes/config.sh
bash -n agents/hermes/entrypoint.sh
```

预期结果：

- 命令无输出
- 退出码为 `0`

如果失败：

- 先修正脚本语法
- 不要跳过这一步直接构建镜像

---

### 3.2 构建 Hermes 镜像

执行：

```bash
docker build -f agents/hermes/Dockerfile -t agent-hub/hermes:local-final .
```

预期结果：

- 镜像构建成功
- 本地生成镜像 `agent-hub/hermes:local-final`

可选检查：

```bash
docker image inspect agent-hub/hermes:local-final --format '{{.Id}} {{.Architecture}} {{.Os}}'
```

说明：

- 如果本机是 Apple Silicon，而基础镜像是 `amd64`，Docker 可能提示平台不一致
- 只要镜像能成功构建，不影响继续做功能验证

---

### 3.3 启动 Hermes Gateway

建议先启动一个带端口映射的测试容器：

```bash
docker rm -f hermes-final 2>/dev/null || true

docker run -d \
  -p 127.0.0.1:28642:8642 \
  --name hermes-final \
  agent-hub/hermes:local-final \
  gateway
```

检查容器状态：

```bash
docker ps --filter name=hermes-final --format '{{.ID}} {{.Image}} {{.Ports}} {{.Status}} {{.Names}}'
```

预期结果：

- 容器状态为 `Up`
- 端口映射为 `127.0.0.1:28642->8642/tcp`

---

### 3.4 查看启动日志

执行：

```bash
docker logs --tail 120 hermes-final
```

预期结果：

- 可以看到父镜像 `/init` 的 s6 初始化日志
- 可以看到 Hermes gateway 的启动日志

例如可能看到：

```text
WARNING gateway.run: No user allowlists configured.
```

注意：

- 如果看到的是普通 CLI 帮助页，说明启动参数没有按预期传递
- 如果看到 `/init` 没有执行，说明 `ENTRYPOINT` 被错误覆盖

---

### 3.5 测试 API Server

执行：

```bash
curl -sv --max-time 4 \
  http://127.0.0.1:28642/v1/models \
  -H 'Authorization: Bearer change-me-local-dev'
```

预期结果：

- 返回 `HTTP/1.1 200 OK`
- 返回 JSON，包含 `hermes-agent`

示例：

```json
{
  "object": "list",
  "data": [
    {
      "id": "hermes-agent"
    }
  ]
}
```

如果失败：

- `Connection refused`
  - 说明容器里 `8642` 没监听
  - 优先检查启动命令和 `API_SERVER_*` 配置

- `401` / `403`
  - 优先检查 `Authorization: Bearer change-me-local-dev`

- `Empty reply from server`
  - 说明端口可能开了，但请求方式不正确
  - 继续查容器日志和 Hermes 配置

---

## 四、`config.sh` 本地测试

### 4.1 启动独立配置测试容器

为了验证配置写入和挂载行为，建议使用单独的挂载目录：

```bash
docker rm -f hermes-final-config 2>/dev/null || true

tmpdir="$(mktemp -d)"
echo "$tmpdir"

docker run -d \
  -v "$tmpdir:/home/agent/.hermes" \
  --name hermes-final-config \
  agent-hub/hermes:local-final \
  gateway
```

后续可以用这个 `$tmpdir` 观察宿主机上的配置文件变化。

---

### 4.2 写入运行时配置

执行：

```bash
docker exec hermes-final-config \
  /opt/agent/config.sh \
  set config \
  http://example.test/v1 \
  sk-test-123 \
  gpt-5.4
```

预期结果：

- 输出：

```text
[INFO] updated Hermes runtime config
```

- 宿主机挂载目录中出现：
  - `.env`
  - `config.values.env`
  - `config.yaml`

---

### 4.3 写入 YAML 配置

执行：

```bash
docker exec hermes-final-config /opt/agent/config.sh set yaml provider custom
docker exec hermes-final-config /opt/agent/config.sh set yaml display.skin default
docker exec hermes-final-config /opt/agent/config.sh set yaml terminal.backend local
docker exec hermes-final-config /opt/agent/config.sh add yaml fallback_providers openai
docker exec hermes-final-config /opt/agent/config.sh add yaml fallback_providers anthropic
docker exec hermes-final-config /opt/agent/config.sh add yaml provider custom http://example.test/v1 OPENAI_API_KEY
```

然后查看：

```bash
docker exec hermes-final-config /opt/agent/config.sh get config
docker exec hermes-final-config /opt/agent/config.sh list yaml
docker exec hermes-final-config /opt/agent/config.sh get yaml model
docker exec hermes-final-config /opt/agent/config.sh get yaml fallback_providers
```

预期结果：

- `.env` 被写入
- `config.values.env` 被写入
- `providers.list` 被写入
- `config.yaml` 被重新渲染

示例 `config.yaml`：

```yaml
model: 'gpt-5.4'
provider: 'custom'
display:
  skin: 'default'
terminal:
  backend: 'local'
fallback_providers:
  - 'openai'
  - 'anthropic'
providers:
  - name: 'custom'
    base_url: 'http://example.test/v1'
    api_key_env: 'OPENAI_API_KEY'
```

---

### 4.4 删除 YAML 字段

执行：

```bash
docker exec hermes-final-config /opt/agent/config.sh delete yaml provider
docker exec hermes-final-config /opt/agent/config.sh delete yaml display.skin
docker exec hermes-final-config /opt/agent/config.sh delete yaml terminal.backend
docker exec hermes-final-config /opt/agent/config.sh list yaml
```

预期结果：

- `provider` 从 `config.yaml` 中消失
- `display` 从 `config.yaml` 中消失
- `terminal` 从 `config.yaml` 中消失

示例结果：

```yaml
model: 'gpt-5.4'
fallback_providers:
  - 'openai'
  - 'anthropic'
providers:
  - name: 'custom'
    base_url: 'http://example.test/v1'
    api_key_env: 'OPENAI_API_KEY'
```

如果删除后字段仍然存在：

- 说明 `config.sh` 删除语义有问题
- 优先检查：
  - 状态文件是否正确保存
  - 渲染逻辑是否还在回填默认值

---

### 4.5 删除所有配置

执行：

```bash
docker exec hermes-final-config /opt/agent/config.sh delete config
```

然后查看宿主机挂载目录：

```bash
ls -la "$tmpdir"
```

预期结果：

- `.env`
- `config.values.env`
- `providers.list`
- `config.yaml`

这些文件都被删除

---

## 五、Actions 测试

当前仓库有两层 workflow：

- `build-enabled-agents`
- `release-enabled-agents`

它们都只构建 `registry/agents.yaml` 里 `enabled: true` 的 agent。

---

### 5.1 构建验证：`build-enabled-agents`

文件：

```text
.github/workflows/build.yml
```

职责：

- 读取 `registry/agents.yaml`
- 只对 `enabled: true` 的 agent 生成 matrix
- 对每个 agent：
  - checkout
  - `bash -n` 校验 shell 脚本
  - `docker build`

不负责：

- 容器运行测试
- API Server 测试
- `config.sh` 测试
- GHCR 推送

触发方式：

- push 到 `master` / `main`
- PR
- `workflow_dispatch`

检查方式：

```bash
gh run list --workflow build.yml --limit 5
gh run watch <run-id> --exit-status
```

通过标准：

- `prepare` 成功
- `build (...)` 成功

---

### 5.2 发布验证：`release-enabled-agents`

文件：

```text
.github/workflows/release.yml
```

职责：

- 读取 `registry/agents.yaml`
- 只对 `enabled: true` 的 agent 生成 matrix
- 登录 GHCR
- build 镜像
- push 到 GHCR

不负责：

- 运行期冒烟测试

触发方式：

- 手动 `workflow_dispatch`
- 或 push tag `v*`

手动触发示例：

```bash
gh workflow run release.yml -f image_tag=test-20260422-1
```

查看状态：

```bash
gh run list --workflow release.yml --limit 5
gh run watch <run-id> --exit-status
```

通过标准：

- `prepare` 成功
- `release (...)` 成功
- GHCR 中出现新 tag，例如：

```text
ghcr.io/gitlayzer/hermes:test-20260422-1
```

---

## 六、`registry/agents.yaml` 的作用

文件：

```text
registry/agents.yaml
```

示例：

```yaml
agents:
  - name: hermes
    path: agents/hermes
    enabled: false
```

说明：

- `enabled: true`
  - build workflow 会真正构建这个 agent
  - release workflow 会真正发布这个 agent

- `enabled: false`
  - workflow 仍然会触发
  - 但 matrix 为空
  - 不会真正进入构建 / 发布 job

所以在进入 CI / 发布前，先确认这个开关是否符合当前目标。

---

## 七、推荐测试顺序

建议严格按这个顺序执行：

1. 本地 shell 语法检查
2. 本地构建镜像
3. 本地启动 gateway
4. 本地验证 API server
5. 本地验证 `config.sh`
6. 打开 `registry/agents.yaml` 的 `enabled`
7. 推代码，跑 `build-enabled-agents`
8. 手动触发 `release-enabled-agents`
9. 从 GHCR 拉镜像再做一次本地验证

---

## 八、常见问题

### 8.1 `8642` 没监听

优先检查：

- 是否正确启动了 `gateway`
- 是否配置了：
  - `API_SERVER_ENABLED`
  - `API_SERVER_HOST`
  - `API_SERVER_PORT`
  - `API_SERVER_KEY`

### 8.2 挂载空目录后 API server 不工作

如果把空目录挂到：

```text
/home/agent/.hermes
```

会覆盖镜像内默认配置文件。  
需要确保挂载目录里有正确的 `.env` / `config.yaml`，或者先通过 `config.sh` 补齐。

### 8.3 Actions 没有真正构建

优先检查：

```yaml
enabled: true
```

是否已经在 `registry/agents.yaml` 中打开。

### 8.4 `docker run` 可以启动，但请求接口失败

先确认：

```bash
curl http://127.0.0.1:<mapped-port>/v1/models \
  -H 'Authorization: Bearer change-me-local-dev'
```

而不是只请求根路径 `/`。

---

## 九、当前测试结论模板

建议每次测试完成后按下面格式记录：

```text
本地 shell 校验：通过 / 失败
本地构建镜像：通过 / 失败
本地 gateway 启动：通过 / 失败
本地 API server：通过 / 失败
本地 config.sh：通过 / 失败
build-enabled-agents：通过 / 失败
release-enabled-agents：通过 / 失败
GHCR 回拉测试：通过 / 失败
```

这样后续排查会更快。
