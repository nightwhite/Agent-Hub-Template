# Agent Hub 自维护 AI Proxy 模型目录与初始化切换计划

> **面向 AI 代理的工作者：** 必需子技能：使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 在不修改 AI Proxy 的前提下，让 Agent Hub 自己维护可选模型目录、区域 AI Proxy 地址、请求格式和 model type，并通过 `ai-agent-switch` 为不同 Agent 初始化和切换当前模型。

**架构：** AI Proxy 只负责 workspace token 和 relay 请求；Agent Hub 是模型目录、region/cn/us、请求格式和模板能力过滤的控制面；`ai-agent-switch` 是写入各 Agent 原生配置的唯一入口。模板只声明当前 Agent 对应的 `ai-agent-switch` client 和支持的 model type，不新增 `model-switch.json`，不让 Agent Hub 按模型名猜协议。

**技术栈：** Go/Gin/client-go remotecommand、React/TypeScript、YAML 模型目录和模板元数据、Dockerfile/GitHub Actions、npm `ai-agent-switch` CLI、现有 AI Proxy token/relay API。

---

## 已确认约束

- 无法修改 AI Proxy。
- Agent Hub 自己维护模型列表，列表里包含模型、区域、请求格式、model type 等初始化所需信息。
- Agent Hub 负责决定请求哪个 region 的 AI Proxy，例如 cn/us；短期没有管理端，模型目录随 Agent Hub 配置版本发布。
- cn/us 不拆成两套 Agent Hub 代码；同一套代码通过 region 或 catalog path 加载不同模型配置。
- 不新增 `model-switch.json`。
- 不统一走 `openai-chat-compatible`；请求格式取决于模型和渠道本身。
- provider/channel/protocol 不能由 Agent Hub 靠模型名前缀猜，必须由 Agent Hub 维护的目录显式声明。
- Agent Hub 的定位是初始化器和辅助切换器，不替代 Agent 内部能力。
- Agent 镜像内置 `ai-agent-switch` CLI。
- 当前模型读取必须读 Agent 原生配置，使用 `ai-agent-switch client show <client>`。
- 不新增兜底逻辑；任何 CLI、token、Pod exec、配置校验失败都返回明确错误。
- 如果开发中认为需要兜底，必须先向用户确认。

## 当前源码事实

Agent Hub 现有能力：

- `POST /api/v1/aiproxy/token/ensure` 已经能确保 workspace AI Proxy token。
- `GET /api/v1/system/config` 已经返回 `aiProxyModelBaseURL`。
- 前端已能从集群地址推导 `https://aiproxy.<region>/v1`。
- 当前模板列表仍由 `regionModelPresets` 生成 `modelOptions`。
- 旧模型初始化逻辑还包含 Hermes 专用脚本和静默继续路径，例如 `continuing without model api key`、`runBootstrapFallback`、`agent_hermes_config.go`。

AI Proxy 现有能力：

- `/v1/models` 使用 workspace token 可返回用户可见模型 ID，但不返回 modelType/request format。
- `/api/models/*`、`/api/channels/*` 是管理接口，不作为本方案依赖。
- 本方案不改 AI Proxy，也不要求 AI Proxy 新增 catalog。

`ai-agent-switch` 当前能力：

- Hermes adapter 支持 `openai-responses`、`openai-chat-compatible`、`anthropic`、`gemini` 等，并把 model type 转成 Hermes transport。
- OpenClaw adapter 支持 `openai-responses`、`openai-chat-compatible`、`anthropic`、`gemini`、`ollama`，但拒绝 `custom`。
- CowAgent adapter 支持 `anthropic`、`gemini`、`deepseek`、`moonshot`、`dashscope`、`openai-chat-compatible`、`openrouter`、`siliconflow`、`lmstudio`、`custom`；明确拒绝 `openai-responses` 和 `ollama`。
- CowAgent 当前要求固定 env 名，例如 OpenAI Chat 兼容用 `OPEN_AI_API_KEY`、Anthropic 用 `CLAUDE_API_KEY`、Gemini 用 `GEMINI_API_KEY`。后续不强行要求它也直接读 `AIPROXY_API_KEY`，而是由 `ai-agent-switch` adapter 按 CowAgent 原生格式写入。

## 核心设计

### 1. Agent Hub 维护一份全局 AI Proxy 模型目录

不放到每个 Agent template 里重复维护；推荐在 Agent Hub 主项目新增一份全局 YAML，例如：

```text
reference/agent-hub/config/aiproxy-models.yaml
```

示例：

```yaml
version: 1
regions:
  us:
    baseURL: https://aiproxy.usw-1.sealos.io/v1
    defaultModel: claude-sonnet-4.6
    models:
      - id: gpt-5.4
        label: GPT-5.4
        providerId: aiproxy
        providerName: AI Proxy
        modelType: openai-responses
        requestFormat: openai-responses
      - id: claude-sonnet-4.6
        label: Claude Sonnet 4.6
        providerId: aiproxy
        providerName: AI Proxy
        modelType: anthropic
        requestFormat: anthropic-messages
      - id: deepseek-chat
        label: DeepSeek Chat
        providerId: aiproxy-deepseek
        providerName: AI Proxy · DeepSeek
        modelType: deepseek
        requestFormat: openai-chat-completions
  cn:
    baseURL: https://aiproxy.hzh.sealos.run/v1
    defaultModel: glm-4.6
    models:
      - id: glm-4.6
        label: GLM-4.6
        providerId: aiproxy
        providerName: AI Proxy
        modelType: openai-chat-compatible
        requestFormat: openai-chat-completions
```

字段含义：

- `baseURL`：这个 region 的 AI Proxy relay 地址，由 Agent Hub 管，不从 AI Proxy 查询。
- `id`：传给 Agent 的模型名。
- `providerId`：写进 `ai-agent-switch` provider 配置的稳定 ID。
- `modelType`：`ai-agent-switch` adapter 用来判断怎么写 Agent 原生配置。
- `requestFormat`：这个模型经过 AI Proxy 时使用的请求格式，用于 UI 展示、校验和后端审计。
- `defaultModel`：这个 region 的明确默认模型；没有默认时创建页必须要求用户选择，不静默选第一个。

### 2. `modelType` 和 `requestFormat` 分开

这两个字段很容易混在一起，需要明确：

- `requestFormat` 表示请求长什么样，例如 OpenAI Responses、OpenAI Chat Completions、Anthropic Messages、Gemini。
- `modelType` 表示 `ai-agent-switch` 应该按哪个 provider/client 规则写配置。

例如 DeepSeek：

```yaml
modelType: deepseek
requestFormat: openai-chat-completions
```

这表示请求形态是 Chat Completions，但不要把它强行压成普通 `openai-chat-compatible`，因为有些 Agent adapter 可以识别 `deepseek` 并写出更贴近 CowAgent/OpenClaw 的原生配置。

### 3. API key 逻辑使用“统一来源，按 Agent 原生格式写入”

Agent Hub 给模型目录和 CLI 传的 logical key source 可以统一是：

```text
AIPROXY_API_KEY
```

但如果某个 Agent 有固定格式，不强迫它直接读这个 env 名。

例如 CowAgent 当前更像是：

- OpenAI 类：写 `open_ai_api_key` 或要求 `OPEN_AI_API_KEY`
- Anthropic：写 `claude_api_key` 或要求 `CLAUDE_API_KEY`
- Gemini：写 `gemini_api_key` 或要求 `GEMINI_API_KEY`

推荐做法：`ai-agent-switch` 的 CowAgent adapter 在 `agent-hub init` 时把 `AIPROXY_API_KEY` 这个来源转换成 CowAgent 原生配置需要的 env 引用，例如 `CLAUDE_API_KEY`、`OPEN_AI_API_KEY`、`GEMINI_API_KEY`。这个逻辑属于 client adapter，不放在 Agent Hub 页面或模板里硬编码；默认不把 token 明文写进 CowAgent 配置文件。

### 4. 模板只声明 Agent 支持能力

模板不维护模型列表，只声明这个 Agent 能支持哪些 model type。

示例：

```yaml
modelSwitch:
  enabled: true
  client: hermes
  apiKeyEnv: AIPROXY_API_KEY
  supportedProviderTypes:
    - openai-responses
    - openai-chat-compatible
    - anthropic
    - gemini
```

CowAgent：

```yaml
modelSwitch:
  enabled: true
  client: cowagent
  apiKeyEnv: AIPROXY_API_KEY
  supportedProviderTypes:
    - openai-chat-compatible
    - anthropic
    - gemini
    - deepseek
    - moonshot
    - dashscope
    - openrouter
    - siliconflow
    - lmstudio
```

真正的硬校验仍由 `ai-agent-switch` adapter 执行；模板只是让 Agent Hub 渲染和过滤更早发生。

### 5. Agent Hub 调一个原子命令

推荐新增 `ai-agent-switch` 自动化命令：

```bash
ai-agent-switch agent-hub init \
  --client hermes \
  --provider-id aiproxy \
  --provider-name "AI Proxy" \
  --model-type anthropic \
  --base-url https://aiproxy.usw-1.sealos.io/v1 \
  --api-key-env AIPROXY_API_KEY \
  --model claude-sonnet-4.6 \
  --available-model claude-sonnet-4.6 \
  --available-model claude-sonnet-4.5 \
  -y \
  --json
```

原子语义：

1. 校验 client 是否存在。
2. 校验 model type 是否已知。
3. 校验 request format 是否已知。
4. 校验目标 client adapter 是否支持该 model type/request format。
5. upsert provider。
6. upsert provider models。
7. 设置 provider default model。
8. apply 到 client 原生配置。
9. 返回 `client show` 风格的 current state JSON。

失败语义：任一步失败直接退出非 0，输出结构化错误，不继续执行后续步骤。

### 6. 版本策略跟随 Actions，但不能用漂移 latest

镜像构建时可以安装“当次 Actions 解析出的 `ai-agent-switch` 版本”，但必须把解析结果固化到构建参数、镜像 label 和模板元数据里，不能让同一个镜像 tag 因为 npm latest 变化而不可复现。

建议：

- dev 镜像 tag 跟随合并后的 commit/run 版本。
- 正式镜像 tag 跟随对应 Agent 的版本。
- 镜像 label 记录 `org.opencontainers.image.version`、`org.sealos.agent.version`、`org.sealos.ai-agent-switch.version`。
- `agents/<agent>/index.json` 同步记录 agent image tag 和内置 CLI version。

## 方案选项

### 方案 1：Agent Hub 全局 YAML 模型目录（已确认）

Agent Hub 维护一份 `aiproxy-models.yaml`，里面按 region 管理 baseURL、默认模型、模型列表、model type 和 request format。各 Agent template 只声明支持能力。

实际部署可以是一个文件包含 `cn/us` 两个 region，也可以是 cn/us 各自部署时通过 `AIPROXY_MODEL_CATALOG_PATH` 指向不同文件。两种方式都使用同一套 Agent Hub 代码。

优点：

- 不改 AI Proxy。
- 不重复维护每个 Agent 的模型列表。
- cn/us 和请求哪个 AI Proxy 都由 Agent Hub 管。
- 和“不新增 model-switch.json”的要求一致。

缺点：

- 新模型上线需要更新 Agent Hub 模型目录并发布。
- 目录内容需要测试校验，避免 modelType/requestFormat 写错。

### 方案 2：沿用并增强 `regionModelPresets`

直接扩展现有 `template/<agent>/template.yaml` 里的 `regionModelPresets`，新增 `modelType`、`requestFormat`、`providerId` 等字段。

优点：

- 改动小，贴近现有代码。
- 不需要新增全局配置加载器。

缺点：

- 每个 Agent template 都要重复维护同一批模型。
- 新模型或 region 调整时容易漏改某个 Agent。
- 模型事实分散在多个 template 里，不适合 Agent Hub 统一控制 cn/us。

### 方案 3：模型目录写成 Go 常量

把模型列表写在 Agent Hub 后端 Go 代码里。

优点：

- 类型安全，测试直接。
- 不需要 YAML parser 边界。

缺点：

- 每次改模型都必须发后端代码。
- 运维和产品同学不容易审查目录内容。

## 推荐执行顺序

### 任务 0：Agent Hub 模型目录 schema 和加载器

**文件：**
- 创建：`reference/agent-hub/config/aiproxy-models.yaml`
- 创建：`reference/agent-hub/backend/internal/aiproxycatalog/catalog.go`
- 创建：`reference/agent-hub/backend/internal/aiproxycatalog/catalog_test.go`
- 修改：`reference/agent-hub/backend/internal/config/config.go`

- [ ] **步骤 1：写目录 schema 测试**

测试覆盖：

```text
cn/us region 必须存在
每个 region 必须有 baseURL
每个 model 必须有 id/providerId/providerName/modelType/requestFormat
defaultModel 如果存在，必须出现在当前 region models 中
modelType 必须属于 ai-agent-switch 支持集合
requestFormat 必须属于 Agent Hub 支持集合
```

- [ ] **步骤 2：实现加载器**

新增 `LoadCatalog(path string)`，读取 YAML 并做严格校验。配置缺失或非法直接返回错误，不自动补默认模型、不自动猜 model type。

- [ ] **步骤 3：接入后端配置**

新增环境变量：

```text
AIPROXY_MODEL_CATALOG_PATH
```

为空时使用仓库内默认路径。这里是“默认配置路径”，不是运行失败后的兜底逻辑。

部署层可以为 cn/us 指定不同 catalog path，但不要 fork 两套 Agent Hub 代码。

### 任务 1：模板声明 Agent 模型切换能力

**文件：**
- 修改：`reference/agent-hub/backend/internal/agenttemplate/template.go`
- 修改：`reference/agent-hub/backend/internal/dto/template.go`
- 修改：`reference/agent-hub/template/hermes-agent/template.yaml`
- 修改：`reference/agent-hub/template/openclaw/template.yaml`
- 修改或新增：`reference/agent-hub/template/cowagent/template.yaml`

- [ ] **步骤 1：扩展模板 schema**

新增 `ModelSwitch` 结构：

```go
type ModelSwitch struct {
	Enabled                bool     `yaml:"enabled" json:"enabled"`
	Client                 string   `yaml:"client" json:"client"`
	APIKeyEnv              string   `yaml:"apiKeyEnv" json:"apiKeyEnv"`
	SupportedProviderTypes []string `yaml:"supportedProviderTypes" json:"supportedProviderTypes"`
}
```

- [ ] **步骤 2：模板校验**

`client` 必须是已支持 client；`supportedProviderTypes` 必须是已知 model type；`apiKeyEnv` 为空时直接校验失败。

- [ ] **步骤 3：声明支持矩阵**

Hermes：`openai-responses/openai-chat-compatible/anthropic/gemini`。

OpenClaw：`openai-responses/openai-chat-compatible/anthropic/gemini/ollama`。

CowAgent：按当前 adapter 能力声明，不包含 `openai-responses/ollama`。

### 任务 2：Agent Hub 后端按 catalog 返回模型选项

**文件：**
- 创建：`reference/agent-hub/backend/internal/handler/aiproxy_models.go`
- 创建：`reference/agent-hub/backend/internal/handler/aiproxy_models_test.go`
- 修改：`reference/agent-hub/backend/internal/router/router.go`
- 修改：`reference/agent-hub/backend/internal/handler/template.go`

- [ ] **步骤 1：写失败测试，证明模型列表来自 catalog**

新增测试要求：

```text
GET /api/v1/aiproxy/models?templateId=hermes-agent
```

返回当前 region 的 catalog models，并按 template `modelSwitch.supportedProviderTypes` 过滤。

- [ ] **步骤 2：实现模型 API**

接口返回：

```json
{
  "region": "us",
  "baseURL": "https://aiproxy.usw-1.sealos.io/v1",
  "defaultModel": "claude-sonnet-4.6",
  "models": [
    {
      "id": "claude-sonnet-4.6",
      "label": "Claude Sonnet 4.6",
      "providerId": "aiproxy",
      "providerName": "AI Proxy · Anthropic",
      "modelType": "anthropic",
      "requestFormat": "anthropic-messages"
    }
  ]
}
```

- [ ] **步骤 3：移除 `regionModelPresets` 主路径**

`regionModelPresets` 暂时可以保留为旧字段兼容，但创建、设置和模型切换主路径不再使用它。

### 任务 3：为 `ai-agent-switch` 增加 Agent Hub 原子命令

**文件：**
- 修改：`reference/ai-agent-switch/src/cli/main.ts`
- 修改：`reference/ai-agent-switch/src/core/app.ts`
- 修改：`reference/ai-agent-switch/src/config/schema.ts`
- 测试：`reference/ai-agent-switch/tests/*`

- [ ] **步骤 1：新增 request format 类型**

新增允许值：

```ts
type RequestFormat =
  | "openai-responses"
  | "openai-chat-completions"
  | "anthropic-messages"
  | "gemini-native";
```

- [ ] **步骤 2：新增 core 方法**

新增 `initAgentHub(input)`，输入包含 client、provider、modelType、available models、target model、yes/json。

- [ ] **步骤 3：复用现有 provider schema 和 adapter**

内部复用现有 provider 校验、provider upsert、adapter `planApply` 和 `apply`，不新增第二套 Agent 配置写入逻辑。

- [ ] **步骤 4：处理固定 Agent 格式**

CowAgent 这类 client 不强制直接读 `AIPROXY_API_KEY`。adapter 把 logical key source 转成 CowAgent 原生 env 引用，默认不把 token 值直接写入 CowAgent 配置文件。

- [ ] **步骤 5：新增 CLI 命令**

命令：

```bash
ai-agent-switch agent-hub init ... --json
```

成功输出：

```json
{
  "clientId": "hermes",
  "providerId": "aiproxy",
  "modelType": "anthropic",
  "requestFormat": "anthropic-messages",
  "modelId": "claude-sonnet-4.6",
  "configPath": "/home/agent/.hermes/config.yaml"
}
```

### 任务 4：Agent Hub 前端渲染 catalog 模型选项

**文件：**
- 修改：`reference/agent-hub/web/src/api/backend.ts`
- 修改：`reference/agent-hub/web/src/domains/agents/types.ts`
- 修改：`reference/agent-hub/web/src/components/business/agents/AgentConfigForm.tsx`
- 修改：`reference/agent-hub/web/src/app/pages/agent-hub/components/AgentSettingsWorkspace.tsx`
- 测试：`reference/agent-hub/web/src/components/business/agents/AgentConfigForm.test.tsx`

- [ ] **步骤 1：新增前端 API 类型**

新增 `AIProxyModelOption`，字段和后端返回保持一致。

- [ ] **步骤 2：创建页和设置页改读 catalog API**

创建页、设置页都从 `GET /api/v1/aiproxy/models?templateId=<id>` 读取模型列表，不再读取 `template.modelOptions` 作为主来源。

- [ ] **步骤 3：展示请求格式**

模型选项展示模型名、provider name、request format。创建页和设置页都只展示当前 Agent 支持的 model type；不支持的模型不进入列表。

- [ ] **步骤 4：默认模型策略**

如果当前 region catalog 没有 `defaultModel`，前端不静默选择第一项。创建时要求用户选择。

### 任务 5：创建与切换时执行原子 CLI

**文件：**
- 创建：`reference/agent-hub/backend/internal/handler/agent_model_switch.go`
- 创建：`reference/agent-hub/backend/internal/handler/agent_model_switch_test.go`
- 修改：`reference/agent-hub/backend/internal/handler/agent.go`
- 修改：`reference/agent-hub/backend/internal/handler/agent_settings_update.go`

- [ ] **步骤 1：封装 argv 构造**

只构造 argv 数组，不拼 shell 字符串。

- [ ] **步骤 2：创建后初始化**

Agent 创建成功并 Pod 可 exec 后调用：

```bash
ai-agent-switch agent-hub init ... --json
```

参数来自 catalog 和用户选择，不从模型名猜。

- [ ] **步骤 3：设置页切换复用同一路径**

设置页提交模型后调用同一个后端逻辑，最终由同一个 CLI 原子命令切换。

- [ ] **步骤 4：当前模型读取**

当前模型读取使用：

```bash
ai-agent-switch client show <client> --json
```

返回 Agent 原生配置的真实状态，不以 annotation/env 作为真实来源。

### 任务 6：镜像内置指定版本 `ai-agent-switch`

**文件：**
- 修改：`agents/hermes-agent/install.sh`
- 修改：`agents/openclaw/install.sh`
- 修改：`agents/cowagent/install.sh`
- 修改：`agents/*/Dockerfile`
- 修改：`.github/workflows/build.yml`
- 修改：`test/validate-agent-contract.sh`
- 修改：`agents/*/index.json`

- [ ] **步骤 1：Actions 解析 CLI 版本并传入构建**

Actions 生成 `AI_AGENT_SWITCH_VERSION`，Docker build 使用 build arg 安装该版本。

- [ ] **步骤 2：镜像记录版本**

镜像 label 和 `agents/<agent>/index.json` 记录 agent version、image tag、`ai-agent-switch` version。

- [ ] **步骤 3：构建校验**

CI 运行：

```bash
ai-agent-switch --version
ai-agent-switch client list --json
ai-agent-switch agent-hub init --help
```

### 任务 7：移除旧模型脚本和兜底路径

**文件：**
- 修改：`reference/agent-hub/backend/internal/handler/agent_bootstrap.go`
- 修改或删除：`reference/agent-hub/backend/internal/handler/agent_hermes_config.go`
- 修改：`agents/hermes-agent/README.md`
- 修改：`agents/openclaw/README.md`
- 修改：`test/*smoke*.sh`
- 修改：`docs/*`

- [ ] **步骤 1：删除 `/opt/agent/config.sh` 模型切换契约**

Smoke test 不再检查旧脚本；改为检查 `ai-agent-switch` CLI。

- [ ] **步骤 2：删除模型初始化兜底路径**

删除 `runBootstrapFallback` 中模型相关路径，以及 “continuing without model api key” 类静默继续逻辑。

- [ ] **步骤 3：回归搜索**

运行：

```bash
rg -n "continuing without model api key|config.sh|hermes fallback|runBootstrapFallback" reference/agent-hub/backend agents test docs
```

任何残留都要逐项解释；如果确实需要兜底，先问用户。

## 已确认决策

1. Agent Hub 目前没有模型管理端；模型目录随配置版本发布。
2. cn/us 分模型配置或部署配置，不分两套 Agent Hub 代码。
3. 模型目录放在 Agent Hub 全局 YAML，推荐 `config/aiproxy-models.yaml`。
4. CowAgent 等固定格式 Agent 尊重自身原生格式，优先由 `ai-agent-switch` adapter 写 env 引用，不默认写明文 token。
5. 设置页模型列表由 Agent Hub 维护目录过滤，只显示当前 Agent 支持 model type 的模型。

## 自检

- 已删除“修改 AI Proxy / 新增 AI Proxy catalog”的路线。
- 已把 cn/us 和 AI Proxy baseURL 控制权放回 Agent Hub。
- 已明确 cn/us 是配置版本差异，不是代码分叉。
- 已把模型列表、modelType、requestFormat 放到 Agent Hub 显式目录中。
- 已明确设置页只展示当前 Agent 支持类型的模型。
- 已保留“不新增 model-switch.json”的约束。
- 已避免模型名前缀猜测。
- 已避免把所有模型统一压成 `openai-chat-compatible`。
- 已保留“不新增兜底，需先确认”的约束。
