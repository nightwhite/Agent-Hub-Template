# Agent Hub Template

面向 Sealos Devbox 的 Agent 镜像接入仓库。

这个仓库维护的是 **Devbox Agent Adapter Standard**，不是通用 agent 应用模板。第一阶段标准的目标只有三个：

- 所有 agent 镜像都基于 Devbox base，并遵守统一目录与入口契约
- 容器统一通过 `entrypoint.sh start` 启动
- 前端统一读取 `/opt/agent/config.json` 并通过 `/opt/agent/config.sh` 调配置，但配置内容必须尊重各 agent 的原生方式

第一阶段明确不做两件事：

- 不把不同 agent 的配置内容统一成同一个 schema
- 不把“部署时透传任意上游 CLI 启动参数”作为平台标准能力

## 仓库布局

```text
agents/
  _template/
  hermes-agent/
  openclaw/
registry/
  agents.yaml
docs/
test/
```

## Agent 目录契约

每个 agent 目录必须提供：

- `Dockerfile`
- `install.sh`
- `entrypoint.sh`
- `config.sh`
- `config.json`
- `index.json`
- `deploy.yaml`
- `README.md`

可以保留额外实现文件，例如 `build.env`，但它们不属于平台对外契约。

## 启动契约

统一要求：

- 镜像 `ENTRYPOINT` 固定为 `"/init", "/opt/agent/entrypoint.sh"`
- 默认 `CMD` 固定为 `"start"`
- Kubernetes 模板默认固定 `args: ["start"]`
- `start` 是标准启动入口
- `config` 是标准配置入口
- `shell` 是标准调试入口
- `run` 只作为维护者调试或兼容性执行入口，不是平台默认启动方式

运行模型允许两类：

- `service`: `start` 直接拉起前台长驻主进程
- `tool`: `start` 完成 bootstrap 后保持容器可被 `exec`

对应信息写在 `index.json` 的 `runtime.kind` 中。

## 前端配置契约

统一要求：

- Dockerfile 必须把 `config.json` 复制到 `/opt/agent/config.json`
- `config.json` 必须声明 `schemaVersion: "devbox-agent-config.v1"`
- `config.json` 只描述该 agent 暴露给前端的原生配置能力，不存真实配置值或密钥
- `config.sh` 是前端调用的唯一配置脚本入口
- `config.sh` stdout 必须只输出统一 JSON envelope，stderr 才能输出日志
- 配置修改后必须尽快作用到当前运行中的 agent

前端调用模型：

```bash
cat /opt/agent/config.json
/opt/agent/config.sh <resource> <action> [args...]
```

成功输出：

```json
{
  "ok": true,
  "resource": "model",
  "action": "set-main",
  "applied": true,
  "data": {}
}
```

失败输出：

```json
{
  "ok": false,
  "resource": "model",
  "action": "set-main",
  "error": {
    "code": "invalid_config",
    "message": "human readable error"
  }
}
```

统一边界：

- 平台只统一“调用方式”和“返回 envelope”，不统一“字段名”
- Hermes、OpenClaw 等 agent 可以各自维护自己的原生配置文件、目录、鉴权方式和生效机制
- secret 类字段读取时不能回传明文，只能返回 `configured`、`masked` 或空值
- 如果某个 agent 需要 reload 或内部 restart，由该 agent 自己在封装里处理，不把容器外部参数透传当成第一阶段方案

## 当前样板

- `agents/_template`: 新 agent 的最小模板
- `agents/hermes-agent`: 基于 Hermes 原生 `config.yaml + .env + hermes gateway run`
- `agents/openclaw`: 基于 OpenClaw 原生 `openclaw.json + .env + openclaw gateway run`

## 本地验证

```bash
bash test/validate-agent-contract.sh
bash test/hermes-smoke.sh
bash test/openclaw-smoke.sh
```

参考：

- `docs/adding-a-new-agent.md`
- `docs/testing-hermes.md`
- `test/README.md`
