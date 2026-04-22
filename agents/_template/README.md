# change-me Agent 模板

先阅读：`docs/adding-a-new-agent.md`

这个目录是新增 agent 时使用的标准脚手架。

## 目录内文件说明

- `Dockerfile`
  - 负责构建最终 agent 镜像
  - 基于 `ghcr.io/gitlayzer/ubuntu:22.04-base`
  - 在构建时会先加载 `build.env`，再执行 `install.sh`
  - 运行时要保留父镜像 `/init` 的启动链路

- `build.env`
  - 构建期环境变量文件
  - 会在 `docker build` 时导出给 `install.sh`
  - 适合放源码地址、版本号、安装路径、非敏感默认值

- `install.sh`
  - 镜像构建阶段执行的安装脚本
  - 应提供安装相关函数和最终安装入口
  - 负责把真实 agent 运行时安装进镜像

- `config.sh`
  - 运行期配置命令入口
  - 负责处理 `set config ...`、`get config`、`delete config`、`list config`
  - 具体配置逻辑由每个 agent 自己实现

- `config.json`
  - 给前端渲染配置表单和操作按钮用
  - 描述 `config.sh` 支持哪些动作、每个动作需要哪些参数
  - 模板里提供的是能力模型，具体配置项和字段名称由实际 agent 自己收敛

- `entrypoint.sh`
  - 容器运行入口脚本
  - 接收容器参数并转发给真实 agent CLI
  - 需要和父镜像 `/init` 一起工作，而不是覆盖它

- `index.json`
  - 给前端展示 agent 信息使用
  - 用于描述名称、说明、图标、标签、镜像名等展示数据

- `_template/index.yaml`
  - 这个 agent 的 Kubernetes 部署模板
  - 用来描述镜像、环境变量、工作目录、运行参数等

- `README.md`
  - 当前模板目录自己的说明文件
  - 用来告诉后续维护者每个文件是做什么的

## 使用时至少要修改这些文件

- `Dockerfile`
- `build.env`
- `install.sh`
- `config.sh`
- `config.json`
- `entrypoint.sh`
- `index.json`
- `_template/index.yaml`
- `README.md`

## 快速检查清单

- 替换掉模板中的占位内容，例如 `change-me`、`replace-me`
- 所有 agent 自己的逻辑都应留在当前目录内
- 在 agent 真正构建通过之前，`registry/agents.yaml` 里保持 `enabled: false`

## 约束说明

- `Dockerfile` 必须使用 `FROM ghcr.io/gitlayzer/ubuntu:22.04-base`
- `build.env` 会在构建时加载，并导出给 `install.sh`
- `config.sh` 负责配置命令分发，例如 `set config ...`、`get config`
- `config.json` 用于让前端知道如何渲染配置操作界面
- 前端如果要基于模板渲染页面，应该以 `config.json` 的资源和动作定义为准，而不是假设所有 agent 都用同一组字段
- `index.json` 用于前端展示 agent 基本信息
- `_template/index.yaml` 用于 Kubernetes 部署这个 agent
- 模板只定义命令分发结构，具体 agent 需要自己实现 `set_config`、`get_config`、`delete_config`、`list_config`
- `entrypoint.sh` 负责启动命令分发和参数转发
- 镜像必须保留父镜像 `/init`，不要把它覆盖掉
- `install.sh` 负责安装命令分发，例如 `install agent`
- 模板只定义安装阶段结构，具体 agent 需要自己实现真正的安装逻辑
- 必须把模板中的占位安装逻辑替换成真实 upstream agent 的安装过程
- 在 agent 真正构建通过并验证可运行之前，不要把它开启进构建流程
