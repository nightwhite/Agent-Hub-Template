# Agent Hub Init Contract 修复计划

> **面向 AI 代理的工作者：** 必需子技能：使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 修复 Agent Hub 模型初始化改造中的 CLI 契约不一致、dry-run 写入副作用和模板 smoke 脚本权限问题。

**架构：** 当前开发阶段按三个仓库同步本地改推进，不把 npm 已发布版本作为 blocker。先在 `ai-agent-switch` 中把 `agent-hub init` 做成无副作用预检、确认后写入的 CLI；再让 Agent-Hub-Template 的 install、smoke、GitHub Actions 全部只调用新命令；最后用 Agent Hub 后端和前端测试锁定 `providerId=aiproxy`、`modelType` 跟随模型、`requestFormat` 只作为目录/UI 元数据的契约。旧 `init-model` 契约完全删除，不做 alias，不做兼容，不新增 fallback。

**技术栈：** Bun/TypeScript、cac CLI、Go/Gin、Kubernetes exec、React/Vitest、Bash、Dockerfile、GitHub Actions。

---

## 约束与已确认事实

- 用户明确禁止未经确认新增 fallback；本计划不增加旧命令兼容、不静默降级、不吞掉 CLI 或 Pod exec 错误。
- `agent-hub init -y` 是 Agent Hub 在 Pod 内非交互执行的正常写入路径；如果写入失败，命令直接失败并把错误返回给 Agent Hub，不设计自动回滚或补偿流程。
- 当前本地开发按 `reference/ai-agent-switch`、`Agent-Hub-Template`、`reference/agent-hub` 同步修改推进，不把 npm latest 作为本轮开发 blocker。
- npm latest 是否包含 `agent-hub init` 只作为发布/合并前检查项；进入真实 Actions 镜像构建前必须确认对应版本已发布。
- 当前主模板 `.github/workflows/build.yml` 仍调用旧 `agent-hub init-model`、`--provider-type`、`--request-format`。
- 当前 `reference/ai-agent-switch/src/core/app.ts` 的 `initAgentHub` 在 `yes=false` 时已经写入 `.ai-agent-switch/config.jsonc`，实测 `--dry-run` 会污染配置。
- `test/hermes-smoke.sh` 和 `test/openclaw-smoke.sh` 从 `100755` 变成 `100644`，建议恢复 executable bit。

## 文件结构

### `reference/ai-agent-switch`

- 修改：`src/core/app.ts`
  - 让 `initAgentHub` 在 `yes=false` 时只生成 plan，不写 `ConfigStore` 和 `StateStore`。
  - 让 `yes=true` 时先生成 plan，再写 provider/route，再 apply client config，再写 lastSwitch。
- 修改：`src/cli/main.ts`
  - 保持唯一命令 `agent-hub init`；确认路径复用第一次生成的参数，不调用旧命令。
- 修改：`tests/agent-hub-init-model.test.ts`
  - 增加 dry-run 不创建 `.ai-agent-switch/config.jsonc` 的测试。
  - 增加 interactive cancel 不写配置的核心层测试。
- 修改：`tests/cli-agent-hub.test.ts`
  - 增加 CLI dry-run 不写 ai-agent-switch store 的集成测试。
- 不在本轮开发任务中修改：`package.json` / `bun.lock`
  - 版本 bump 与 npm 发布作为合并/发布前独立步骤处理。

### `Agent-Hub-Template`

- 修改：`.github/workflows/build.yml`
  - 把旧 `agent-hub init-model` verify 改为 `agent-hub init --model-type ...`。
  - 明确 verify 使用 Actions 解析出的 `AI_AGENT_SWITCH_VERSION`。
- 修改：`test/hermes-smoke.sh`
  - 恢复 executable bit。
- 修改：`test/openclaw-smoke.sh`
  - 恢复 executable bit。
- 修改：`test/validate-agent-contract.sh`
  - 增加校验：workflow 和脚本中不得出现 `agent-hub init-model`、`--provider-type`、`--request-format`。

### `reference/agent-hub`

- 修改：`backend/internal/handler/agent_model_switch_test.go`
  - 锁定 Agent Hub 生成 `ai-agent-switch agent-hub init --model-type ... -y --json`。
  - 确认不传 `requestFormat`、不传 provider-level request format。
- 修改：`backend/internal/handler/aiproxy_models_test.go`
  - 锁定模型列表按 template `supportedModelTypes` 过滤。
- 修改：`web/src/domains/agents/templates.test.ts`
  - 锁定 `requestFormat` 只映射到 UI `apiMode/helper`，不影响 providerId。

---

## 任务 1：修复 `ai-agent-switch agent-hub init` 的 dry-run 副作用

**文件：**
- 修改：`reference/ai-agent-switch/tests/agent-hub-init-model.test.ts`
- 修改：`reference/ai-agent-switch/src/core/app.ts`

- [ ] **步骤 1：编写失败测试：`yes=false` 不写 ai-agent-switch store**

在 `reference/ai-agent-switch/tests/agent-hub-init-model.test.ts` 追加：

```ts
import { existsSync } from "node:fs";

test("dry-run plans Agent Hub init without writing ai-agent-switch store", async () => {
  const home = await mkdtemp(join(tmpdir(), "ai-agent-switch-agent-hub-dry-run-"));
  try {
    const app = new AiAgentSwitchApp({ homeDir: home, cwd: home });
    const result = await app.initAgentHub({
      clientId: "hermes",
      providerId: "aiproxy",
      providerName: "AI Proxy",
      baseUrl: "https://aiproxy.usw-1.sealos.io/v1",
      apiKeyEnv: "AIPROXY_API_KEY",
      modelId: "glm-4.6",
      modelType: "openai-chat-compatible",
      availableModels: [{ id: "glm-4.6", type: "openai-chat-compatible" }],
      yes: false,
    });

    expect(result).toMatchObject({ applied: false, requiresConfirmation: true });
    expect(existsSync(join(home, ".ai-agent-switch/config.jsonc"))).toBe(false);
    expect(existsSync(join(home, ".hermes/config.yaml"))).toBe(false);
  } finally {
    await rm(home, { recursive: true, force: true });
  }
});
```

- [ ] **步骤 2：运行测试确认失败**

运行：

```bash
cd /Users/night/Documents/code/sealos/Agent-Hub-Template/reference/ai-agent-switch
bun test tests/agent-hub-init-model.test.ts
```

预期：新增测试 FAIL，失败原因是 `.ai-agent-switch/config.jsonc` 已存在。

- [ ] **步骤 3：修改 `initAgentHub`，只在 apply 路径写 store**

将 `src/core/app.ts` 中 `initAgentHub` 的核心结构改成：

```ts
const plan = await adapter.planApply({ provider, modelId: input.modelId });
if (!input.yes) {
  return {
    clientId: input.clientId,
    providerId: provider.id,
    modelId: input.modelId,
    modelType: input.modelType,
    configPath: adapter.configPath,
    applied: false,
    requiresConfirmation: true,
    plan,
  };
}

await this.store.update((config) => {
  config.providers[provider.id] = provider;
  config.routes.default = { candidates: [{ providerId: provider.id, modelId: input.modelId }] };
  return config;
});
await adapter.apply(plan);
await this.stateStore.update((state) => {
  state.lastSwitch = {
    clientId: input.clientId,
    providerId: provider.id,
    modelId: input.modelId,
    at: new Date().toISOString(),
  };
  return state;
});
```

注意：这里不做自动回滚或补偿流程。`-y` 写入失败时直接返回错误；本次只修复 `dry-run/取消确认` 不应写入配置的问题。

- [ ] **步骤 4：运行目标测试确认通过**

运行：

```bash
cd /Users/night/Documents/code/sealos/Agent-Hub-Template/reference/ai-agent-switch
bun test tests/agent-hub-init-model.test.ts
```

预期：PASS。

- [ ] **步骤 5：Commit**

```bash
cd /Users/night/Documents/code/sealos/Agent-Hub-Template/reference/ai-agent-switch
git add src/core/app.ts tests/agent-hub-init-model.test.ts
git commit -m "fix: make agent hub init dry-run side-effect free"
```

---

## 任务 2：补 CLI dry-run 集成测试，锁定用户可见行为

**文件：**
- 修改：`reference/ai-agent-switch/tests/cli-agent-hub.test.ts`

- [ ] **步骤 1：编写失败测试：CLI `--dry-run --json` 不写 store**

在 `reference/ai-agent-switch/tests/cli-agent-hub.test.ts` 追加：

```ts
import { existsSync } from "node:fs";

test("init dry-run returns JSON without writing config files", async () => {
  const home = await mkdtemp(join(tmpdir(), "ai-agent-switch-cli-agent-hub-dry-run-"));
  try {
    const output = await run(
      home,
      "agent-hub",
      "init",
      "--client",
      "hermes",
      "--provider-id",
      "aiproxy",
      "--provider-name",
      "AI Proxy",
      "--model-type",
      "openai-chat-compatible",
      "--base-url",
      "https://aiproxy.hzh.sealos.run/v1",
      "--api-key-env",
      "AIPROXY_API_KEY",
      "--model",
      "glm-4.6",
      "--available-model",
      "glm-4.6",
      "--dry-run",
      "--json",
    );

    const parsed = JSON.parse(output) as { applied: boolean; requiresConfirmation: boolean };
    expect(parsed).toMatchObject({ applied: false, requiresConfirmation: true });
    expect(existsSync(join(home, ".ai-agent-switch/config.jsonc"))).toBe(false);
    expect(existsSync(join(home, ".hermes/config.yaml"))).toBe(false);
  } finally {
    await rm(home, { recursive: true, force: true });
  }
});
```

- [ ] **步骤 2：运行 CLI 测试确认通过**

运行：

```bash
cd /Users/night/Documents/code/sealos/Agent-Hub-Template/reference/ai-agent-switch
bun test tests/cli-agent-hub.test.ts
```

预期：PASS。

- [ ] **步骤 3：运行类型检查**

运行：

```bash
cd /Users/night/Documents/code/sealos/Agent-Hub-Template/reference/ai-agent-switch
bun run typecheck
```

预期：PASS。

- [ ] **步骤 4：Commit**

```bash
cd /Users/night/Documents/code/sealos/Agent-Hub-Template/reference/ai-agent-switch
git add tests/cli-agent-hub.test.ts
git commit -m "test: cover agent hub init cli dry run"
```

---

## 任务 3：本地同步验证 `ai-agent-switch` 新命令

**文件：**
- 不修改文件；只运行本地验证命令。

- [ ] **步骤 1：确认本地源码命令存在**

运行：

```bash
cd /Users/night/Documents/code/sealos/Agent-Hub-Template/reference/ai-agent-switch
bun src/cli/main.ts agent-hub init --help
```

预期：help 输出中存在 `agent-hub <action>`，且 action 支持 `init`。

- [ ] **步骤 2：确认本地 dry-run 不写配置**

运行：

```
cd /Users/night/Documents/code/sealos/Agent-Hub-Template/reference/ai-agent-switch
tmp="$(mktemp -d)"
HOME="$tmp" AI_AGENT_SWITCH_HOME="$tmp/.ai-agent-switch" bun src/cli/main.ts agent-hub init \
  --client hermes \
  --provider-id aiproxy \
  --provider-name "AI Proxy" \
  --model-type openai-chat-compatible \
  --base-url https://aiproxy.hzh.sealos.run/v1 \
  --api-key-env AIPROXY_API_KEY \
  --model glm-4.6 \
  --available-model glm-4.6 \
  --dry-run \
  --json
test ! -e "$tmp/.ai-agent-switch/config.jsonc"
test ! -e "$tmp/.hermes/config.yaml"
rm -rf "$tmp"
```

预期：命令输出 JSON 且两个 `test ! -e` 都成功。

- [ ] **步骤 3：完整验证**

运行：

```bash
cd /Users/night/Documents/code/sealos/Agent-Hub-Template/reference/ai-agent-switch
bun test
bun run typecheck
bun run build
```

预期：全部 PASS。

- [ ] **步骤 4：Commit**

如果任务 1、2 已经各自 commit，本任务不需要 commit。若本地验证时补了测试或文档，只提交对应文件。

---

## 任务 4：修复 Agent-Hub-Template build workflow 的旧命令

**文件：**
- 修改：`/Users/night/Documents/code/sealos/Agent-Hub-Template/.github/workflows/build.yml`
- 修改：`/Users/night/Documents/code/sealos/Agent-Hub-Template/test/validate-agent-contract.sh`

- [ ] **步骤 1：给契约测试增加旧命令禁用检查**

在 `test/validate-agent-contract.sh` 末尾验证成功前加入：

```bash
if grep -R --line-number -E 'agent-hub[[:space:]]+init-model|--provider-type|--request-format' \
  .github agents test README.md docs \
  --exclude-dir=superpowers >/tmp/agent-hub-old-cli-refs.txt; then
  cat /tmp/agent-hub-old-cli-refs.txt >&2
  fail "old ai-agent-switch agent-hub init-model contract must not be used"
fi
rm -f /tmp/agent-hub-old-cli-refs.txt
```

- [ ] **步骤 2：运行测试确认失败**

运行：

```bash
cd /Users/night/Documents/code/sealos/Agent-Hub-Template
bash test/validate-agent-contract.sh
```

预期：FAIL，指向 `.github/workflows/build.yml` 中旧命令。

- [ ] **步骤 3：修改 workflow verify 命令**

把 `.github/workflows/build.yml` 中：

```bash
HOME="$verify_home" ai-agent-switch agent-hub init-model \
  --client "$VERIFY_CLIENT" \
  --provider-id verify-aiproxy \
  --provider-name Verify \
  --provider-type openai-chat-compatible \
  --request-format openai-chat-completions \
  --base-url http://127.0.0.1:1/v1 \
  --api-key-env AIPROXY_API_KEY \
  --model verify-model \
  --available-model verify-model \
  --json
```

改成：

```bash
HOME="$verify_home" ai-agent-switch agent-hub init \
  --client "$VERIFY_CLIENT" \
  --provider-id verify-aiproxy \
  --provider-name Verify \
  --model-type openai-chat-compatible \
  --base-url http://127.0.0.1:1/v1 \
  --api-key-env AIPROXY_API_KEY \
  --model verify-model \
  --available-model verify-model \
  --json
```

- [ ] **步骤 4：运行契约测试确认通过**

运行：

```bash
cd /Users/night/Documents/code/sealos/Agent-Hub-Template
bash test/validate-agent-contract.sh
```

预期：PASS。

- [ ] **步骤 5：Commit**

```bash
cd /Users/night/Documents/code/sealos/Agent-Hub-Template
git add .github/workflows/build.yml test/validate-agent-contract.sh
git commit -m "fix: align build verification with agent hub init"
```

---

## 任务 5：恢复 smoke 脚本可执行权限

**文件：**
- 修改权限：`/Users/night/Documents/code/sealos/Agent-Hub-Template/test/hermes-smoke.sh`
- 修改权限：`/Users/night/Documents/code/sealos/Agent-Hub-Template/test/openclaw-smoke.sh`

- [ ] **步骤 1：恢复 executable bit**

运行：

```bash
cd /Users/night/Documents/code/sealos/Agent-Hub-Template
chmod +x test/hermes-smoke.sh test/openclaw-smoke.sh
```

- [ ] **步骤 2：验证权限**

运行：

```bash
cd /Users/night/Documents/code/sealos/Agent-Hub-Template
git diff --summary -- test/hermes-smoke.sh test/openclaw-smoke.sh
test -x test/hermes-smoke.sh
test -x test/openclaw-smoke.sh
```

预期：`git diff --summary` 不再显示 `100755 => 100644`，两个 `test -x` 都成功。

- [ ] **步骤 3：Commit**

```bash
cd /Users/night/Documents/code/sealos/Agent-Hub-Template
git add test/hermes-smoke.sh test/openclaw-smoke.sh
git commit -m "chore: keep smoke scripts executable"
```

---

## 任务 6：补 Agent Hub 后端契约测试，锁定 `modelType` 跟随模型

**文件：**
- 修改：`reference/agent-hub/backend/internal/handler/agent_model_switch_test.go`
- 修改：`reference/agent-hub/backend/internal/handler/aiproxy_models_test.go`

- [ ] **步骤 1：增加 argv 断言测试**

在 `agent_model_switch_test.go` 中增加测试，确保命令形态只包含 `--model-type`：

```go
func TestBuildAgentHubModelInitArgvUsesModelTypeOnly(t *testing.T) {
	t.Parallel()

	argv := buildAgentHubModelInitArgv(
		agenttemplate.ModelSwitch{
			Client:    "hermes",
			APIKeyEnv: "AIPROXY_API_KEY",
		},
		aiproxycatalog.Region{
			BaseURL: "https://aiproxy.usw-1.sealos.io/v1",
			Models: []aiproxycatalog.Model{
				{ID: "gpt-5.4", ProviderID: "aiproxy", ProviderName: "AI Proxy", ModelType: "openai-responses", RequestFormat: "openai-responses"},
				{ID: "glm-4.6", ProviderID: "aiproxy", ProviderName: "AI Proxy", ModelType: "openai-chat-compatible", RequestFormat: "openai-chat-completions"},
			},
		},
		aiproxycatalog.Model{ID: "gpt-5.4", ProviderID: "aiproxy", ProviderName: "AI Proxy", ModelType: "openai-responses", RequestFormat: "openai-responses"},
	)

	joined := strings.Join(argv, " ")
	if !strings.Contains(joined, "agent-hub init") {
		t.Fatalf("argv = %v, want agent-hub init", argv)
	}
	if !containsArgPair(argv, "--model-type", "openai-responses") {
		t.Fatalf("argv = %v, want --model-type openai-responses", argv)
	}
	if containsArg(argv, "--request-format") || containsArg(argv, "--provider-type") || containsArg(argv, "init-model") {
		t.Fatalf("argv = %v, must not use old request/provider type contract", argv)
	}
}
```

如果测试文件没有 helper，则添加：

```go
func containsArg(argv []string, value string) bool {
	for _, item := range argv {
		if item == value {
			return true
		}
	}
	return false
}

func containsArgPair(argv []string, key string, value string) bool {
	for index := 0; index+1 < len(argv); index++ {
		if argv[index] == key && argv[index+1] == value {
			return true
		}
	}
	return false
}
```

- [ ] **步骤 2：运行后端目标测试**

运行：

```bash
cd /Users/night/Documents/code/sealos/Agent-Hub-Template/reference/agent-hub/backend
go test ./internal/handler -run 'TestBuildAgentHubModelInitArgv|TestListAIProxyModels|TestResolveCatalogModel'
```

预期：PASS。

- [ ] **步骤 3：Commit**

```bash
cd /Users/night/Documents/code/sealos/Agent-Hub-Template/reference/agent-hub
git add backend/internal/handler/agent_model_switch_test.go backend/internal/handler/aiproxy_models_test.go
git commit -m "test: lock agent hub model init argv contract"
```

---

## 任务 7：补 Agent Hub 前端模型目录映射测试

**文件：**
- 修改：`reference/agent-hub/web/src/domains/agents/templates.test.ts`

- [ ] **步骤 1：增加 `requestFormat` 仅作为 UI 元数据的测试**

在 `templates.test.ts` 中增加：

```ts
it("maps AI Proxy request format into UI metadata without changing provider id", () => {
  const options = mapAIProxyCatalogToModelOptions({
    region: "us",
    baseURL: "https://aiproxy.usw-1.sealos.io/v1",
    defaultModel: "gpt-5.4",
    models: [
      {
        id: "gpt-5.4",
        label: "GPT-5.4",
        providerId: "aiproxy",
        providerName: "AI Proxy",
        modelType: "openai-responses",
        requestFormat: "openai-responses",
      },
    ],
  });

  expect(options).toEqual([
    {
      value: "gpt-5.4",
      label: "GPT-5.4",
      helper: "AI Proxy · openai-responses",
      provider: "aiproxy",
      apiMode: "openai-responses",
    },
  ]);
});
```

- [ ] **步骤 2：运行前端目标测试**

运行：

```bash
cd /Users/night/Documents/code/sealos/Agent-Hub-Template/reference/agent-hub/web
npm test -- src/domains/agents/templates.test.ts
```

预期：PASS。

- [ ] **步骤 3：Commit**

```bash
cd /Users/night/Documents/code/sealos/Agent-Hub-Template/reference/agent-hub
git add web/src/domains/agents/templates.test.ts
git commit -m "test: keep aiproxy request format as catalog metadata"
```

---

## 任务 8：最终验证顺序

**文件：**
- 不新增文件；运行验证命令。

- [ ] **步骤 1：验证 `ai-agent-switch`**

运行：

```bash
cd /Users/night/Documents/code/sealos/Agent-Hub-Template/reference/ai-agent-switch
bun test
bun run typecheck
bun run build
```

预期：全部 PASS。

- [ ] **步骤 2：验证主模板**

运行：

```bash
cd /Users/night/Documents/code/sealos/Agent-Hub-Template
git diff --check
bash test/validate-agent-contract.sh
bash -n agents/cowagent/install.sh agents/hermes-agent/install.sh agents/openclaw/install.sh
bash -n test/ccswitch-smoke.sh test/hermes-smoke.sh test/openclaw-smoke.sh
```

预期：全部 PASS。

- [ ] **步骤 3：验证 Agent Hub 后端和前端**

运行：

```bash
cd /Users/night/Documents/code/sealos/Agent-Hub-Template/reference/agent-hub/backend
go test ./internal/aiproxycatalog ./internal/agenttemplate ./internal/kube ./internal/handler ./internal/router

cd /Users/night/Documents/code/sealos/Agent-Hub-Template/reference/agent-hub/web
npm test -- src/domains/agents/templates.test.ts src/components/business/agents/AgentConfigForm.test.tsx
npm run build
```

预期：全部 PASS。

- [ ] **步骤 4：发布/合并前检查 npm 已发布版本**

当前本地开发可以跳过此步骤。准备合并到会触发真实镜像构建的分支前运行：

```bash
npm view ai-agent-switch version
npx --yes ai-agent-switch@<published-version> agent-hub init --help
```

预期：已发布版本包含 `agent-hub init`。如果还没有发布，不能把会触发 Actions 镜像构建的模板改动合进去。

- [ ] **步骤 5：验证模板构建可拿到新 CLI**

本地开发阶段如果没有可安装的新 npm 包，可以暂不跑镜像 smoke。准备合并前至少覆盖 Hermes：

```bash
cd /Users/night/Documents/code/sealos/Agent-Hub-Template
AI_AGENT_SWITCH_VERSION=<published-version> bash test/hermes-smoke.sh
```

预期：镜像内 `ai-agent-switch --version` 匹配 `<published-version>`，`agent-hub init` dry-run JSON 返回 `"requiresConfirmation": true`。

---

## 自检

- 规格覆盖度：
  - 旧 workflow 命令：任务 4 覆盖。
  - dry-run 污染配置：任务 1、任务 2 覆盖。
  - npm 发布顺序：降级为任务 8 的发布/合并前检查，不作为当前本地开发 blocker。
  - 脚本权限：任务 5 覆盖。
  - Agent Hub `modelType`/`requestFormat` 契约：任务 6、任务 7 覆盖。
- 占位符扫描：
  - 本计划不使用“待定”“后续实现”作为任务内容。
  - 每个代码变更步骤包含具体代码或具体替换片段。
- 类型一致性：
  - CLI 命令统一为 `agent-hub init`。
  - CLI 参数统一为 `--model-type`，不再使用 `--provider-type`、`--request-format`。
  - `requestFormat` 只在 Agent Hub catalog/UI 中使用，不传给 CLI。

## 推荐执行方式

推荐使用 **内联执行**。原因是三个仓库之间存在本地契约依赖：先修 `reference/ai-agent-switch` 的 dry-run 和 CLI 语义，再修主模板 workflow/契约测试，最后补 Agent Hub 的后端和前端契约测试。npm 发布只在准备合并到真实 Actions 构建前处理。
