# 添加一个新的 Agent

这份文档面向仓库使用者，说明如何在当前仓库中新增一个可构建、可测试、可纳入 CI 的 agent。

目标很简单：

1. 创建一个新的 agent 目录（推荐直接用脚手架）
2. 补齐这个 agent 需要的文件
3. 在 `registry/agents.yaml` 中注册一次路径（脚手架会自动做）
4. 用仓库已有脚本完成校验、构建和测试

整个过程不需要改共享脚本，也不需要改 GitHub Actions。

---

## 零、先看 30 秒最短路径

如果你只想立刻开始，按下面做：

```bash
make new-agent AGENT=my-agent
```

然后只做这几件事：

1. 修改 `agents/my-agent/agent.yaml`
2. 实现 `agents/my-agent/install.sh`
3. 改好 `agents/my-agent/Dockerfile`
4. 检查 `entrypoint.sh`、`healthcheck.sh`、`tests/smoke.sh`
5. 运行：

```bash
make validate
make build-agent AGENT=my-agent
make test-agent AGENT=my-agent
```

6. 通过后再把 `registry/agents.yaml` 里的 `enabled: false` 改成 `enabled: true`

也可以直接用：

```bash
make enable-agent AGENT=my-agent
make disable-agent AGENT=my-agent
```

你只需要关心两处：
- `agents/<name>/`：实现 agent 自己的一切
- `registry/agents.yaml`：声明仓库是否识别/启用这个 agent

---

## 一、先理解这个仓库的接入规则

这个仓库采用固定约定接入新 agent：

- 每个 agent 都放在 `agents/<agent-name>/`
- 每个 agent 都有自己的元数据、Dockerfile、安装脚本、入口脚本和 smoke test
- 仓库根目录下的 `scripts/` 负责统一的 build / test / validate
- `registry/agents.yaml` 只负责声明“这个仓库支持哪些 agent，以及是否启用自动化”

也就是说，新增一个 agent 的核心原则只有一句话：

> 只在 `agents/<agent-name>/` 里实现这个 agent，并在 `registry/agents.yaml` 注册它。

---

## 二、目录结构要求

每个 agent 至少应包含这些文件：

```text
agents/<name>/
  agent.yaml
  Dockerfile
  install.sh
  entrypoint.sh
  healthcheck.sh
  tests/smoke.sh
  README.md
```

这些文件的职责如下：

- `agent.yaml`
  - 描述 agent 名称、版本、基础镜像、镜像名、来源等元数据
- `Dockerfile`
  - 定义最终镜像如何组装
- `install.sh`
  - 写这个 agent 的真实安装过程
- `entrypoint.sh`
  - 定义容器启动后默认如何运行 agent
- `healthcheck.sh`
  - 提供最小健康检查
- `tests/smoke.sh`
  - 提供最小可用性验证
- `README.md`
  - 记录这个 agent 的说明和用法

---

## 三、推荐的新增方式：先用模板生成

最简单的方式是直接使用仓库自带脚手架：

```bash
make new-agent AGENT=my-agent
```

这条命令会做两件事：

1. 把 `agents/_template` 复制为 `agents/my-agent`
2. 自动在 `registry/agents.yaml` 末尾追加一个新条目

生成后，你会得到：

```text
agents/my-agent/
  agent.yaml
  Dockerfile
  install.sh
  entrypoint.sh
  healthcheck.sh
  tests/smoke.sh
  README.md
```

同时在 `registry/agents.yaml` 里会新增类似内容：

```yaml
- name: my-agent
  path: agents/my-agent
  enabled: false
```

这里故意只保留“名字、路径、是否启用”。
真正的 base、image、build.args、runtime 等元数据都应集中写在 `agents/my-agent/agent.yaml` 中。

注意：

新生成的 agent 默认是 `enabled: false`，这是故意的。
这样可以避免半成品直接进入 `build-all` / `test-all` / CI。

---

## 四、逐步修改新 agent 的文件

下面建议按这个顺序修改。

### 第 1 步：修改 `agent.yaml`

先把元数据补完整。

一个最小可用示例：

```yaml
name: my-agent
version: "0.1.0"
base: ubuntu
image:
  repository: agent-hub/my-agent
  tag: dev
source:
  type: git
  repository: https://github.com/example/my-agent
  ref: main
runtime:
  entrypoint: /opt/agent/entrypoint.sh
  healthcheck: /opt/agent/healthcheck.sh
  user: agent
metadata:
  description: Real MyAgent runtime image.
  category: custom-agent
```

至少要确认这些字段正确：

- `name`
- `version`
- `base`
- `image.repository`
- `image.tag`
- `source.*`
- `metadata.description`

如果你的 Dockerfile 需要额外构建参数，也建议统一写到 `agent.yaml` 中，例如：

```yaml
build:
  args:
    MY_AGENT_VERSION: 1.2.3
    NODE_VERSION: 24.14.1
```

这样版本和构建参数就集中在元数据里，由 `scripts/build-agent.sh` 自动传给 Docker build，而不是分散写死在 Dockerfile 默认值里。

---

### 第 2 步：实现 `install.sh`

这是最关键的文件。

仓库级脚本不会自动知道你的 agent 怎么安装，因此安装逻辑必须写在 agent 自己的 `install.sh` 里。

这里应当完成的事情通常包括：

- 安装系统依赖
- 下载或克隆上游 agent
- 安装真实运行时或 CLI
- 准备运行目录
- 确保最终有一个真实可执行入口

重要原则：

- 要安装真实 agent 运行时，不要用假进程代替
- 不要留下仅用于演示的占位逻辑
- 如果 agent 的真实分发方式是 git / npm / pip / 二进制包，就按真实方式安装

你可以把它理解成：

- 仓库脚本负责“调用”安装
- `install.sh` 负责“定义”安装

---

### 第 3 步：修改 `Dockerfile`

`Dockerfile` 负责把这个 agent 组装成镜像。

通常要做这些事情：

1. 选择基础镜像
2. 复制 `install.sh`
3. 执行安装
4. 复制 `entrypoint.sh` 和 `healthcheck.sh`
5. 配置用户、工作目录、卷和 healthcheck

你应确保：

- `COPY` 路径已经从模板占位符替换成真实 agent 目录
- Dockerfile 最终引用的是 `agents/<name>/...`，不是 `agents/_template/...`
- 镜像里真正安装了可用的 agent，而不是测试占位文件

---

### 第 4 步：修改 `entrypoint.sh`

这个脚本决定容器启动后怎么运行。

推荐保留两类能力：

1. `shell`
   - 方便进入容器调试
2. 默认执行真实 agent 命令
   - 用户直接运行镜像时可以正常使用 agent

一个常见模式是：

```bash
mode="${1:-shell}"
case "$mode" in
  shell)
    shift || true
    exec /bin/bash "$@"
    ;;
  my-agent)
    shift || true
    exec my-agent "$@"
    ;;
  *)
    exec my-agent "$@"
    ;;
esac
```

重点不是照抄，而是：

- 默认行为要符合用户直觉
- 不要把测试参数硬编码成默认运行参数
- 入口要执行真实 agent 程序

---

### 第 5 步：修改 `healthcheck.sh`

这里建议只做最小健康验证。

例如：

- `my-agent --version`
- `my-agent help`
- 一个轻量、不依赖外部服务的状态检查

健康检查应满足：

- 快
- 稳定
- 不依赖交互
- 不依赖外部 token 或复杂环境

---

### 第 6 步：修改 `tests/smoke.sh`

这个脚本用于最小可用性验证。

建议只验证“真实运行时已经安装且命令可用”，例如：

```bash
#!/usr/bin/env bash
set -euo pipefail

IMAGE="${1:-agent-hub/my-agent:dev}"

docker run --rm "$IMAGE" --version >/dev/null
```

如果你的 agent 需要更强校验，也可以加入第二条最小命令。
但建议避免把一堆仅测试用参数、临时调试参数硬塞进默认 smoke test。

原则是：

- 足够证明镜像不是空壳
- 但不要把测试过程复杂化
- 不要要求用户提供额外配置才能通过最小测试

---

### 第 7 步：补充 `README.md`

建议至少写清楚：

- 这个 agent 来自哪里
- 如何构建
- 如何运行
- 如何进入 shell
- 如何做最小验证

例如：

~~~md
# MyAgent image

This image packages the real MyAgent runtime.

Build:

```bash
make build-agent AGENT=my-agent
```

Run:

```bash
docker run --rm my-agent:dev --version
```
~~~

---

## 五、校验新增的 agent

完成文件修改后，按这个顺序检查。

### 第 1 步：校验仓库结构

```bash
make validate
```

这一步会检查：

- registry 文件是否存在
- registry 中 name/path 是否重复
- agent/base 路径是否存在
- agent 必需文件是否齐全
- 关键脚本是否带可执行权限
- registry 与 agent.yaml/base.yaml 的名称和路径是否一致
- agent 引用的 base 是否存在
- `change-me` / `replace-me` 这类模板占位符是否残留

---

### 第 2 步：单独构建 agent

```bash
make build-agent AGENT=my-agent
```

如果失败，优先检查：

- `agent.yaml` 是否完整
- Dockerfile 中路径是否正确
- `install.sh` 是否能在镜像里顺利执行

---

### 第 3 步：执行 smoke test

```bash
make test-agent AGENT=my-agent
```

如果这一步通过，说明你的镜像至少满足“最小可用”。

---

## 六、什么时候把 agent 设为 enabled

只有在下面都通过后，才建议把 `registry/agents.yaml` 中对应条目改成：

```yaml
enabled: true
```

或者直接执行：

```bash
make enable-agent AGENT=<name>
```

推荐条件：

1. `make validate` 通过
2. `make build-agent AGENT=<name>` 通过
3. `make test-agent AGENT=<name>` 通过
4. 你确认它安装的是“真实 agent”，不是占位实现

完成后，这个 agent 才会被纳入：

- `make build-all`
- `make test-all`
- GitHub Actions 的统一流程

如果之后不想让它继续参与批量构建，也可以直接执行：

```bash
make disable-agent AGENT=<name>
```

---

## 七、最常见的几个坑

### 1. 模板占位符没有替换干净

比如 Dockerfile 里仍然引用：

```text
agents/change-me/...
```

这说明你还没把模板内容全部改成真实 agent 名称。

### 2. 只改了 README，没有装真实 runtime

新增 agent 的核心不是写说明，而是：

- `install.sh` 真的装了 agent
- `entrypoint.sh` 真的能启动 agent
- `tests/smoke.sh` 真的能验证 agent

### 3. 把测试参数写成默认行为

例如：

- 仅为了测试而加的 `--verbose`
- 临时调试用的 `--allow-*`
- 只适合 CI 的参数

这类参数不应当变成镜像默认行为。

### 4. 太早启用 `enabled: true`

如果 agent 还没验证通过，就把它启用，会让：

- `build-all` 失败
- `test-all` 失败
- CI 失败

建议始终先本地单独构建和测试，再启用。

---

## 八、最短路径总结

如果你只想看最短操作路径，就按下面做：

### 1. 生成模板

```bash
make new-agent AGENT=my-agent
```

### 2. 修改这些文件

- `agents/my-agent/agent.yaml`
- `agents/my-agent/Dockerfile`
- `agents/my-agent/install.sh`
- `agents/my-agent/entrypoint.sh`
- `agents/my-agent/healthcheck.sh`
- `agents/my-agent/tests/smoke.sh`
- `agents/my-agent/README.md`

### 3. 校验

```bash
make validate
```

### 4. 构建

```bash
make build-agent AGENT=my-agent
```

### 5. 测试

```bash
make test-agent AGENT=my-agent
```

### 6. 通过后启用

把 `registry/agents.yaml` 里的对应项改成：

```yaml
enabled: true
```

---

## 九、一句话原则

新增 agent 时，只需要记住一句话：

> 在 `agents/<name>/` 中实现真实 agent，在 `registry/agents.yaml` 中注册它，然后用统一脚本构建和测试。
