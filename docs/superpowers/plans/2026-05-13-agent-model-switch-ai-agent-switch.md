# Agent Model Switch via AI Agent Switch 实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 让 Agent Hub 基于模板元数据渲染“读取/修改当前模型”能力，并通过容器内 `ai-agent-switch` CLI 读写真实 Agent 配置。

**架构：** 模板侧不新增 `model-switch.json`，而是在每个 agent 的 `index.json` 中加入小型 `model_switch` 能力声明。Agent 镜像构建时安装 `ai-agent-switch` CLI；Agent Hub 读取模板元数据后，使用 Kubernetes exec 在目标 Pod 内执行声明的 `current.argv` 和 `switch.argv`，不再依赖旧 `/opt/agent/config.sh`，也不做静默 fallback。

**技术栈：** Bash/Dockerfile、GitHub Actions、JSON 元数据、Go/Gin/Kubernetes client-go、React/TypeScript、Bun/npm `ai-agent-switch` CLI。

---

## 约束与决策

- 不创建 `model-switch.json`。
- 不新增 fallback 策略；读取或切换失败必须把明确错误返回给页面。
- 不把 API Key 放进命令参数；密钥只允许来自容器环境变量或后续明确确认的 Secret 注入方案。
- 不恢复旧 `config.sh/config.json` 契约。
- Agent Hub 的模型列表来源是 AI Proxy；模板仓库和 `index.json` 不维护模型清单。
- 开发镜像使用 Actions 生成的 `dev-<sha12>` 和 `dev` 标签；正式镜像使用对应 agent 的 `index.json.version`。
- 当前计划会同时描述 `Agent-Hub-Template` 与 `reference/agent-hub` 的改动；实际提交时可分成两个仓库 PR。

## 文件结构

### Agent-Hub-Template

- 修改：`agents/_template/index.json`
  - 增加 `model_switch` 示例能力声明，保持默认 disabled。
- 修改：`agents/hermes-agent/index.json`
  - 声明 Hermes 的 `ai-agent-switch` current/switch 命令和变量。
- 修改：`agents/openclaw/index.json`
  - 声明 OpenClaw 的 `ai-agent-switch` current/switch 命令和变量。
- 修改：`agents/cowagent/index.json`
  - 声明 CowAgent 的 `ai-agent-switch` current/switch 命令和变量。
- 修改：`agents/*/Dockerfile`
  - 对需要切模型的 agent 镜像安装 Node/npm 与 `ai-agent-switch` CLI。
- 修改：`agents/*/install.sh`
  - 抽出最小 `install_ai_agent_switch_cli` 安装步骤，避免每个 Dockerfile 重复长命令。
- 修改：`test/validate-agent-contract.sh`
  - 校验 `model_switch` 结构、禁止 shell 字符串命令、禁止 `config.sh/config.json`。
- 修改：`test/*smoke.sh`、`test/README.md`、`agents/hermes-agent/README.md`、`agents/openclaw/README.md`
  - 清理旧 `/opt/agent/config.sh` 描述，改成 `ai-agent-switch client show/use`。
- 修改：`.github/workflows/build.yml`
  - CI 构建时验证 CLI 存在。
- 修改：`README.md`、`docs/agent-contract.md`、`docs/adding-a-new-agent.md`
  - 记录 `model_switch` 字段和镜像安装契约。

### reference/agent-hub

- 修改：`backend/internal/agenttemplate/template.go`
  - 扩展 template definition，支持从模板元数据携带 `modelSwitch`。
- 修改：`backend/internal/dto/template.go`、`backend/internal/dto/agent_contract.go`
  - 新增模型切换能力 DTO。
- 修改：`backend/internal/handler/template.go`、`backend/internal/handler/agent_contract.go`
  - 把 `modelSwitch` 暴露给前端。
- 创建：`backend/internal/handler/agent_model_switch.go`
  - 新增读取当前模型与切换模型的 handler。
- 修改：`backend/internal/router/router.go`
  - 注册 `GET /api/v1/agents/:agentName/model` 与 `POST /api/v1/agents/:agentName/model`。
- 修改：`backend/internal/handler/agent_settings_update.go`
  - 将模型字段从旧 settings resource update 中移除或禁用，只保留非模型设置。
- 修改：`backend/internal/handler/agent_bootstrap.go`
  - 移除 Hermes bootstrap fallback。
- 修改：`web/src/domains/agents/types.ts`
  - 新增 `ModelSwitchCapability`、`AgentModelState`、请求/响应类型。
- 创建：`web/src/api/agentModelSwitch.ts`
  - 封装读取与切换模型 API。
- 修改：`web/src/app/pages/agent-hub/components/AgentSettingsWorkspace.tsx`
  - 模型设置区改为读取真实 current 状态并提交 switch 命令。
- 测试：`backend/internal/handler/agent_model_switch_test.go`
  - 验证 argv 渲染、禁止未知变量、禁止 shell 字符串、失败无 fallback。
- 测试：`web/src/app/pages/agent-hub/components/AgentSettingsWorkspace.test.tsx`
  - 验证页面读取 current、提交 switch、展示失败。

---

## `model_switch` 元数据草案

放入每个 `agents/<agent>/index.json`，字段名用 snake_case 贴合现有 JSON 风格：

```json
{
  "model_switch": {
    "enabled": true,
    "client": "hermes",
    "variables": {
      "provider_id": {
        "source": "modelOption.provider",
        "required": true
      },
      "model": {
        "source": "input.model",
        "required": true
      }
    },
    "current": {
      "argv": ["ai-agent-switch", "client", "show", "hermes"]
    },
    "switch": {
      "argv": ["ai-agent-switch", "use", "hermes", "{{provider_id}}/{{model}}", "-y", "--json"]
    }
  }
}
```

模板仓库只声明命令和变量，不声明复杂 UI，也不声明模型列表。Agent Hub 的模型列表必须来自 AI Proxy。

---

### 任务 1：为模板仓库定义并校验 `model_switch` 契约

**文件：**
- 修改：`agents/_template/index.json`
- 修改：`agents/hermes-agent/index.json`
- 修改：`agents/openclaw/index.json`
- 修改：`agents/cowagent/index.json`
- 修改：`test/validate-agent-contract.sh`

- [ ] **步骤 1：编写失败的契约测试**

在 `test/validate-agent-contract.sh` 中追加校验函数：

```bash
validate_model_switch_contract() {
  local agent_dir="$1"
  local index_path="${agent_dir}/index.json"

  python3 - "$index_path" <<'PY'
import json
import sys

path = sys.argv[1]
data = json.load(open(path, encoding="utf-8"))
spec = data.get("model_switch")
if spec is None:
    return_code = 0
    raise SystemExit(return_code)
if not isinstance(spec, dict):
    raise SystemExit(f"{path}: model_switch must be an object")
if spec.get("enabled") is not True:
    raise SystemExit(0)
client = spec.get("client")
if not isinstance(client, str) or not client.strip():
    raise SystemExit(f"{path}: model_switch.client is required")
for section in ("current", "switch"):
    value = spec.get(section)
    if not isinstance(value, dict):
        raise SystemExit(f"{path}: model_switch.{section} must be an object")
    argv = value.get("argv")
    if not isinstance(argv, list) or not argv or not all(isinstance(item, str) and item for item in argv):
        raise SystemExit(f"{path}: model_switch.{section}.argv must be a non-empty string array")
    if any(item in {"sh", "bash", "-c"} for item in argv[:3]):
        raise SystemExit(f"{path}: model_switch.{section}.argv must not use shell wrappers")
switch_argv = spec["switch"]["argv"]
if not any("{{model}}" in item for item in switch_argv):
    raise SystemExit(f"{path}: model_switch.switch.argv must include {{model}}")
PY
}
```

并在遍历每个 agent 目录时调用：

```bash
validate_model_switch_contract "$agent_dir"
```

- [ ] **步骤 2：运行测试验证失败**

运行：

```bash
bash test/validate-agent-contract.sh
```

预期：如果还没有补 `model_switch`，测试通过；先临时给一个坏字段可确认失败信息。随后撤销临时坏字段。

- [ ] **步骤 3：补充最小 `model_switch` 元数据**

在 `agents/hermes-agent/index.json` 加入：

```json
"model_switch": {
  "enabled": true,
  "client": "hermes",
  "variables": {
    "provider_id": { "source": "modelOption.provider", "required": true },
    "model": { "source": "input.model", "required": true }
  },
  "current": {
    "argv": ["ai-agent-switch", "client", "show", "hermes"]
  },
  "switch": {
    "argv": ["ai-agent-switch", "use", "hermes", "{{provider_id}}/{{model}}", "-y", "--json"]
  }
}
```

OpenClaw 把 `client` 和 argv 里的 client 改成 `openclaw`；CowAgent 改成 `cowagent`。`agents/_template/index.json` 加入 disabled 示例：

```json
"model_switch": {
  "enabled": false
}
```

- [ ] **步骤 4：运行契约测试验证通过**

运行：

```bash
bash test/validate-agent-contract.sh
```

预期：PASS。

- [ ] **步骤 5：Commit**

```bash
git add agents/_template/index.json agents/hermes-agent/index.json agents/openclaw/index.json agents/cowagent/index.json test/validate-agent-contract.sh
git commit -m "feat: declare agent model switch contract"
```

---

### 任务 2：镜像构建时安装 `ai-agent-switch` CLI

**文件：**
- 修改：`agents/hermes-agent/install.sh`
- 修改：`agents/openclaw/install.sh`
- 修改：`agents/cowagent/install.sh`
- 修改：`agents/hermes-agent/Dockerfile`
- 修改：`agents/openclaw/Dockerfile`
- 修改：`agents/cowagent/Dockerfile`
- 修改：`.github/workflows/build.yml`

- [ ] **步骤 1：编写 CLI 存在性校验**

在每个 agent 的 `install_agent` 尾部加入：

```bash
if ! command -v ai-agent-switch >/dev/null 2>&1; then
  fail "ai-agent-switch CLI was not installed"
fi
ai-agent-switch --version >/dev/null 2>&1 || fail "ai-agent-switch CLI is not executable"
```

在 `.github/workflows/build.yml` 的 build 后加一步：

```yaml
- name: Verify ai-agent-switch CLI
  run: |
    docker run --rm "agent-hub/${{ matrix.name }}:ci-${{ github.run_id }}" ai-agent-switch --version
```

- [ ] **步骤 2：运行本地语法测试**

运行：

```bash
find agents -type f -name '*.sh' -print0 | xargs -0 -n1 bash -n
```

预期：PASS。

- [ ] **步骤 3：实现安装函数**

对没有 Node/npm 的镜像安装 Node 22 与 CLI。示例函数：

```bash
install_ai_agent_switch_cli() {
  if command -v ai-agent-switch >/dev/null 2>&1; then
    return
  fi

  if ! command -v npm >/dev/null 2>&1; then
    curl -fsSL "https://deb.nodesource.com/setup_22.x" | bash -
    apt-get install -y --no-install-recommends nodejs
  fi

  npm install -g ai-agent-switch@latest
}
```

在 `install_agent` 中调用：

```bash
install_ai_agent_switch_cli
```

OpenClaw 已安装 Node，可复用 npm；Hermes/CowAgent 需要 Node。

- [ ] **步骤 4：构建一个镜像验证**

先构建最轻的一个：

```bash
docker build -f agents/openclaw/Dockerfile -t agent-hub/openclaw:model-switch-local .
docker run --rm agent-hub/openclaw:model-switch-local ai-agent-switch --version
```

预期：输出 `ai-agent-switch/<version>`，退出码 0。

- [ ] **步骤 5：Commit**

```bash
git add agents/hermes-agent/install.sh agents/openclaw/install.sh agents/cowagent/install.sh .github/workflows/build.yml
git commit -m "feat: install ai-agent-switch in agent images"
```

---

### 任务 3：移除旧模型修改脚本文档与 smoke 测试残留

**文件：**
- 修改：`agents/hermes-agent/README.md`
- 修改：`agents/openclaw/README.md`
- 修改：`test/hermes-smoke.sh`
- 修改：`test/openclaw-smoke.sh`
- 修改：`test/ccswitch-smoke.sh`
- 修改：`test/README.md`
- 修改：`README.md`
- 修改：`docs/agent-contract.md`

- [ ] **步骤 1：定位旧契约残留**

运行：

```bash
rg -n "config\\.sh|/opt/agent/config|devbox-agent-config|ccswitch" README.md docs agents test
```

预期：列出旧文档和旧 smoke 测试引用。

- [ ] **步骤 2：更新 README 命令示例**

把 Hermes 示例替换为：

```bash
docker exec hermes-local ai-agent-switch client show hermes
docker exec hermes-local ai-agent-switch provider add \
  --id sealos-aiproxy \
  --name "Sealos AIProxy" \
  --type openai-responses \
  --base-url "${AGENT_MODEL_BASEURL}" \
  --api-key-env AIPROXY_API_KEY \
  --model gpt-5.4 \
  --default-model gpt-5.4
docker exec hermes-local ai-agent-switch use hermes sealos-aiproxy/gpt-5.4 -y --json
```

OpenClaw 和 CowAgent 用对应 client 名称。

- [ ] **步骤 3：收敛 smoke 测试**

将旧 `run_config_json` 调用删除，替换为只验证：

```bash
docker exec "$CONTAINER" ai-agent-switch --version >/dev/null
docker exec "$CONTAINER" ai-agent-switch client show hermes --json >/tmp/hermes-current.json
```

如果当前 CLI 的 `client show` 不支持 `--json`，使用无 `--json` 命令并解析 stdout JSON。

- [ ] **步骤 4：运行文本扫描确认清理**

运行：

```bash
rg -n "config\\.sh|/opt/agent/config|devbox-agent-config" README.md docs agents test
```

预期：只允许出现“禁止新增 config.sh/config.json”的契约描述。

- [ ] **步骤 5：运行契约测试**

运行：

```bash
bash test/validate-agent-contract.sh
```

预期：PASS。

- [ ] **步骤 6：Commit**

```bash
git add README.md docs/agent-contract.md agents/hermes-agent/README.md agents/openclaw/README.md test
git commit -m "docs: replace legacy config script model flow"
```

---

### 任务 4：Agent Hub 后端读取并暴露 `model_switch` 能力

**文件：**
- 修改：`reference/agent-hub/backend/internal/agenttemplate/template.go`
- 修改：`reference/agent-hub/backend/internal/dto/template.go`
- 修改：`reference/agent-hub/backend/internal/dto/agent_contract.go`
- 修改：`reference/agent-hub/backend/internal/handler/template.go`
- 修改：`reference/agent-hub/backend/internal/handler/agent_contract.go`
- 测试：`reference/agent-hub/backend/internal/handler/agent_contract_test.go`

- [ ] **步骤 1：编写失败的 contract 测试**

在 `agent_contract_test.go` 增加测试，构造 template definition：

```go
func TestBuildAgentContractIncludesModelSwitch(t *testing.T) {
	t.Parallel()

	templateDef := agenttemplate.Definition{
		ID: "hermes-agent",
		ModelSwitch: agenttemplate.ModelSwitchDefinition{
			Enabled: true,
			Client: "hermes",
			Current: agenttemplate.CommandSpec{Argv: []string{"ai-agent-switch", "client", "show", "hermes"}},
			Switch: agenttemplate.CommandSpec{Argv: []string{"ai-agent-switch", "use", "hermes", "{{provider_id}}/{{model}}", "-y", "--json"}},
		},
	}
	view := kube.AgentView{Agent: agent.Agent{Name: "demo", TemplateID: "hermes-agent", Namespace: "ns", Ready: true}}

	contract := buildAgentContract(view, templateDef, config.Config{Region: "us"})
	if !contract.ModelSwitch.Enabled {
		t.Fatal("expected model switch capability")
	}
	if contract.ModelSwitch.Client != "hermes" {
		t.Fatalf("client = %q, want hermes", contract.ModelSwitch.Client)
	}
}
```

- [ ] **步骤 2：运行测试验证失败**

运行：

```bash
cd reference/agent-hub/backend
go test ./internal/handler -run TestBuildAgentContractIncludesModelSwitch -count=1
```

预期：FAIL，缺少类型或字段。

- [ ] **步骤 3：增加 Go 类型与 DTO**

在 `agenttemplate/template.go` 增加：

```go
type ModelSwitchDefinition struct {
	Enabled   bool                         `yaml:"enabled"`
	Client    string                       `yaml:"client"`
	Variables map[string]ModelSwitchVar    `yaml:"variables"`
	Current   CommandSpec                  `yaml:"current"`
	Switch    CommandSpec                  `yaml:"switch"`
}

type ModelSwitchVar struct {
	Source   string `yaml:"source"`
	Required bool   `yaml:"required"`
}

type CommandSpec struct {
	Argv []string `yaml:"argv"`
}
```

在 `Definition` 加字段：

```go
ModelSwitch ModelSwitchDefinition `yaml:"modelSwitch"`
```

如果 Agent Hub 的模板源最终来自 JSON，需要读取模板生成流程时把 snake_case `model_switch` 映射成 camelCase `modelSwitch`。

- [ ] **步骤 4：暴露到 contract**

在 DTO 中增加：

```go
type ModelSwitchContract struct {
	Enabled bool `json:"enabled"`
	Client string `json:"client,omitempty"`
}
```

在 `AgentContract` 增加：

```go
ModelSwitch ModelSwitchContract `json:"modelSwitch"`
```

在 `buildAgentContract` 中设置：

```go
ModelSwitch: dto.ModelSwitchContract{
	Enabled: templateDef.ModelSwitch.Enabled,
	Client: strings.TrimSpace(templateDef.ModelSwitch.Client),
},
```

不要把完整 argv 暴露给前端；命令执行在后端。

- [ ] **步骤 5：运行测试验证通过**

运行：

```bash
cd reference/agent-hub/backend
go test ./internal/handler -run TestBuildAgentContractIncludesModelSwitch -count=1
```

预期：PASS。

- [ ] **步骤 6：Commit**

```bash
cd reference/agent-hub
git add backend/internal/agenttemplate/template.go backend/internal/dto/template.go backend/internal/dto/agent_contract.go backend/internal/handler/template.go backend/internal/handler/agent_contract.go backend/internal/handler/agent_contract_test.go
git commit -m "feat: expose model switch capability"
```

---

### 任务 5：Agent Hub 后端实现 current/switch exec API

**文件：**
- 创建：`reference/agent-hub/backend/internal/handler/agent_model_switch.go`
- 创建：`reference/agent-hub/backend/internal/handler/agent_model_switch_test.go`
- 修改：`reference/agent-hub/backend/internal/router/router.go`

- [ ] **步骤 1：编写 argv 渲染单元测试**

测试内容：

```go
func TestRenderModelSwitchArgv(t *testing.T) {
	t.Parallel()

	argv, err := renderModelSwitchArgv(
		[]string{"ai-agent-switch", "use", "hermes", "{{provider_id}}/{{model}}", "-y", "--json"},
		map[string]string{"provider_id": "sealos-aiproxy", "model": "gpt-5.4"},
	)
	if err != nil {
		t.Fatalf("renderModelSwitchArgv() error = %v", err)
	}
	want := []string{"ai-agent-switch", "use", "hermes", "sealos-aiproxy/gpt-5.4", "-y", "--json"}
	if !reflect.DeepEqual(argv, want) {
		t.Fatalf("argv = %#v, want %#v", argv, want)
	}
}
```

再加未知变量失败：

```go
func TestRenderModelSwitchArgvRejectsUnknownVariable(t *testing.T) {
	t.Parallel()

	_, err := renderModelSwitchArgv([]string{"{{unknown}}"}, map[string]string{"model": "gpt-5.4"})
	if err == nil {
		t.Fatal("expected unknown variable error")
	}
}
```

- [ ] **步骤 2：运行测试验证失败**

运行：

```bash
cd reference/agent-hub/backend
go test ./internal/handler -run 'TestRenderModelSwitchArgv' -count=1
```

预期：FAIL，函数不存在。

- [ ] **步骤 3：实现 DTO 与渲染函数**

在新文件中定义：

```go
type AgentModelStateResponse struct {
	ClientID   string `json:"clientId"`
	ProviderID string `json:"providerId,omitempty"`
	ModelID    string `json:"modelId,omitempty"`
	ConfigPath string `json:"configPath,omitempty"`
}

type SwitchAgentModelRequest struct {
	ProviderID string `json:"providerId"`
	Model      string `json:"model"`
}
```

实现：

```go
func renderModelSwitchArgv(argv []string, values map[string]string) ([]string, error) {
	result := make([]string, 0, len(argv))
	for _, item := range argv {
		next := item
		for {
			start := strings.Index(next, "{{")
			if start < 0 {
				break
			}
			end := strings.Index(next[start+2:], "}}")
			if end < 0 {
				return nil, fmt.Errorf("unclosed model switch variable in %q", item)
			}
			name := strings.TrimSpace(next[start+2 : start+2+end])
			value, ok := values[name]
			if !ok {
				return nil, fmt.Errorf("unknown model switch variable: %s", name)
			}
			next = next[:start] + value + next[start+2+end+2:]
		}
		result = append(result, next)
	}
	return result, nil
}
```

- [ ] **步骤 4：实现 GET current**

Handler 流程：

1. 读取 kube factory。
2. 校验 agentName。
3. 获取 AgentView。
4. resolve template definition。
5. 校验 `modelSwitch.enabled`。
6. 执行 `execInAgentPodWithRetry(ctx, clientset, factory, agentName, current.argv, nil, false, nil)`。
7. 解析 stdout JSON。
8. 返回 `AgentModelStateResponse`。

失败时返回 502 或 400，不读取 annotation 作为 fallback。

- [ ] **步骤 5：实现 POST switch**

Handler 流程：

1. 解析 `providerId` 和 `model`。
2. 根据 template 的 `switch.argv` 替换 `provider_id` 和 `model`。
3. exec 命令。
4. 解析 CLI JSON 输出。
5. 成功后更新 Devbox/Service/Ingress annotation 中的 `agent.sealos.io/model-provider` 与 `agent.sealos.io/model`，仅作为展示缓存。
6. 再执行 current 读取真实值并返回。

- [ ] **步骤 6：注册路由**

在 router 中添加：

```go
agents.GET("/:agentName/model", handler.GetAgentModel)
agents.POST("/:agentName/model", handler.SwitchAgentModel)
```

实际路由变量名按当前 router 文件风格调整。

- [ ] **步骤 7：运行后端测试**

运行：

```bash
cd reference/agent-hub/backend
go test ./internal/handler ./internal/router -count=1
```

预期：PASS。

- [ ] **步骤 8：Commit**

```bash
cd reference/agent-hub
git add backend/internal/handler/agent_model_switch.go backend/internal/handler/agent_model_switch_test.go backend/internal/router/router.go
git commit -m "feat: switch agent model via pod exec"
```

---

### 任务 6：移除 Agent Hub 的 Hermes bootstrap fallback

**文件：**
- 修改：`reference/agent-hub/backend/internal/handler/agent_bootstrap.go`
- 测试：`reference/agent-hub/backend/internal/handler/agent_bootstrap_test.go`

- [ ] **步骤 1：编写失败测试**

测试目标：模板 bootstrap 失败时应直接失败并标记 failed，不调用 `configureHermesModel`。

新增测试名：

```go
func TestRunAgentBootstrapLifecycleDoesNotFallbackToHermesConfig(t *testing.T) {
	t.Parallel()
	// 使用 fake exec 或拆出 runBootstrapFailureHandler 后验证：
	// 输入 hermes-agent + bootstrapErr，返回错误必须包含 "template bootstrap failed"，
	// 不包含 "recovered"。
}
```

如果现有代码难以直接测试 goroutine 生命周期，先把 fallback 决策拆为纯函数：

```go
func handleTemplateBootstrapError(templateID string, bootstrapErr error) error {
	return fmt.Errorf("template bootstrap failed: %w", bootstrapErr)
}
```

- [ ] **步骤 2：运行测试验证失败**

运行：

```bash
cd reference/agent-hub/backend
go test ./internal/handler -run 'TestRunAgentBootstrapLifecycleDoesNotFallback|TestHandleTemplateBootstrapError' -count=1
```

预期：FAIL，当前仍有 fallback。

- [ ] **步骤 3：删除 fallback**

把：

```go
if err := executeTemplateScript(...); err != nil {
	if fallbackErr := runBootstrapFallback(...); fallbackErr != nil {
		...
	}
}
```

改为：

```go
if err := executeTemplateScript(...); err != nil {
	message := truncateBootstrapMessage(err.Error())
	_ = persistBootstrapStatus(context.Background(), repo, spec.Name, kube.BootstrapPhaseFailed, message)
	return err
}
```

删除 `runBootstrapFallback` 函数和不再使用的 import。

- [ ] **步骤 4：运行测试验证通过**

运行：

```bash
cd reference/agent-hub/backend
go test ./internal/handler -count=1
```

预期：PASS。

- [ ] **步骤 5：Commit**

```bash
cd reference/agent-hub
git add backend/internal/handler/agent_bootstrap.go backend/internal/handler/agent_bootstrap_test.go
git commit -m "fix: remove silent hermes bootstrap fallback"
```

---

### 任务 7：Agent Hub 前端接入 current/switch API

**文件：**
- 修改：`reference/agent-hub/web/src/domains/agents/types.ts`
- 创建：`reference/agent-hub/web/src/api/agentModelSwitch.ts`
- 修改：`reference/agent-hub/web/src/app/pages/agent-hub/components/AgentSettingsWorkspace.tsx`
- 测试：`reference/agent-hub/web/src/app/pages/agent-hub/components/AgentSettingsWorkspace.test.tsx`

- [ ] **步骤 1：编写前端测试**

测试目标：

```tsx
it("loads current model from model switch API before editing", async () => {
  // mock GET /api/v1/agents/demo/model
  // render settings workspace with modelSwitch.enabled=true
  // expect selected model to become response.modelId
});

it("shows model switch errors without falling back to cached runtime model", async () => {
  // mock GET failure
  // expect visible error state
  // expect cached runtime.model not to be shown as current truth
});
```

- [ ] **步骤 2：运行测试验证失败**

运行：

```bash
cd reference/agent-hub/web
npm test -- AgentSettingsWorkspace.test.tsx --runInBand
```

如果项目使用 Vitest：

```bash
cd reference/agent-hub/web
npx vitest run src/app/pages/agent-hub/components/AgentSettingsWorkspace.test.tsx
```

预期：FAIL。

- [ ] **步骤 3：增加 API 封装**

创建 `web/src/api/agentModelSwitch.ts`：

```ts
import { backendFetch } from "./backend";

export interface AgentModelState {
  clientId: string;
  providerId?: string;
  modelId?: string;
  configPath?: string;
}

export async function getAgentModel(agentName: string) {
  return backendFetch<AgentModelState>(`/api/v1/agents/${encodeURIComponent(agentName)}/model`);
}

export async function switchAgentModel(agentName: string, payload: { providerId: string; model: string }) {
  return backendFetch<AgentModelState>(`/api/v1/agents/${encodeURIComponent(agentName)}/model`, {
    method: "POST",
    body: JSON.stringify(payload),
  });
}
```

函数名和 `backendFetch` 签名按现有 API 文件调整。

- [ ] **步骤 4：设置页接入真实 current**

在 `AgentSettingsWorkspace.tsx` 中：

1. 如果 `item.modelSwitch.enabled` 为 true，加载 current。
2. current 成功后显示 `providerId/modelId`。
3. 提交模型变更时调用 `switchAgentModel`。
4. 失败时显示错误，不使用 runtime cached model 伪装为当前真实值。

- [ ] **步骤 5：运行前端测试**

运行：

```bash
cd reference/agent-hub/web
npx vitest run src/app/pages/agent-hub/components/AgentSettingsWorkspace.test.tsx
```

预期：PASS。

- [ ] **步骤 6：Commit**

```bash
cd reference/agent-hub
git add web/src/domains/agents/types.ts web/src/api/agentModelSwitch.ts web/src/app/pages/agent-hub/components/AgentSettingsWorkspace.tsx web/src/app/pages/agent-hub/components/AgentSettingsWorkspace.test.tsx
git commit -m "feat: edit agent model through switch API"
```

---

### 任务 8：端到端验证与文档收口

**文件：**
- 修改：`docs/agent-contract.md`
- 修改：`docs/adding-a-new-agent.md`
- 修改：`README.md`
- 修改：`reference/agent-hub/docs/AgentHub-Product-Spec.md`
- 修改：`reference/agent-hub/backend/api/openapi.yaml`

- [ ] **步骤 1：更新 API 文档**

在 Agent Hub OpenAPI 中加入：

```yaml
/api/v1/agents/{agentName}/model:
  get:
    summary: Get current agent model from runtime
  post:
    summary: Switch agent model through runtime CLI
```

请求：

```json
{
  "providerId": "sealos-aiproxy",
  "model": "gpt-5.4"
}
```

响应：

```json
{
  "clientId": "hermes",
  "providerId": "sealos-aiproxy",
  "modelId": "gpt-5.4",
  "configPath": "/home/agent/.hermes/config.yaml"
}
```

- [ ] **步骤 2：更新模板契约文档**

在 `docs/agent-contract.md` 写明：

```markdown
`model_switch` is optional. When enabled, the image must contain `ai-agent-switch`, and command specs must be argv arrays. Shell command strings are not allowed.
```

- [ ] **步骤 3：运行全量验证**

模板仓库：

```bash
bash test/validate-agent-contract.sh
find agents -type f -name '*.sh' -print0 | xargs -0 -n1 bash -n
```

Agent Hub 后端：

```bash
cd reference/agent-hub/backend
go test ./...
```

Agent Hub 前端：

```bash
cd reference/agent-hub/web
npx vitest run
```

- [ ] **步骤 4：镜像冒烟验证**

至少验证一个镜像：

```bash
docker build -f agents/openclaw/Dockerfile -t agent-hub/openclaw:model-switch-local .
docker run --rm agent-hub/openclaw:model-switch-local ai-agent-switch --version
docker run --rm agent-hub/openclaw:model-switch-local ai-agent-switch client show openclaw
```

预期：CLI 可执行；`client show` 输出 JSON 或明确的配置缺失错误，不能出现 command not found。

- [ ] **步骤 5：Commit**

```bash
git add README.md docs/agent-contract.md docs/adding-a-new-agent.md
git commit -m "docs: document ai-agent-switch model switching"

cd reference/agent-hub
git add docs/AgentHub-Product-Spec.md backend/api/openapi.yaml
git commit -m "docs: document runtime model switch API"
```

---

## 自检清单

- 规格覆盖：读取当前模型、切换模型、镜像安装 CLI、旧脚本移除、版本规则、失败无 fallback 都有任务覆盖。
- 占位符扫描：计划中没有未完成标记或模糊步骤。
- 类型一致性：模板字段使用 `model_switch`，Agent Hub API 对外使用 `modelSwitch`。
- YAGNI：没有引入单独 JSON 文件，没有设计复杂 UI schema，没有把 argv 暴露给前端。
- 风险：`ai-agent-switch@latest` 会降低镜像可复现性；这是用户明确希望“跟随最新 CLI”带来的权衡。若后续要锁定版本，应改为 build arg 或 registry 字段。

---

## 执行建议

推荐拆成两个 PR：

1. `Agent-Hub-Template` PR：元数据、镜像安装、文档和测试。
2. `agent-hub` PR：后端 exec API、前端页面、去掉 fallback。

两个 PR 合并顺序建议先模板后 Agent Hub；Agent Hub 可以先兼容没有 `modelSwitch` 的模板，但不能在执行失败时 fallback 到旧 annotation。
