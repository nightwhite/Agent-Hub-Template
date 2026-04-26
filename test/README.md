# 本地 Smoke 测试

先跑静态契约校验：

```bash
bash test/validate-agent-contract.sh
```

再按需跑真实镜像 smoke：

```bash
bash test/hermes-smoke.sh
bash test/openclaw-smoke.sh
```

如果本机有 ccswitch 监听 `127.0.0.1:15721`，可以跑完整模型链路：

```bash
bash test/ccswitch-smoke.sh
```

这些脚本会：

- 构建镜像
- 按默认 `start` 启动容器
- 读取运行态 `/opt/agent/config.json`
- 通过 `/opt/agent/config.sh` 修改原生配置
- 校验 `config.sh` stdout 是统一 JSON envelope
- 校验 secret 读取不返回明文
- 校验配置文件已经被写入
- 校验运行中的 gateway 仍然健康
- `ccswitch-smoke.sh` 会额外验证 direct ccswitch、Hermes gateway、OpenClaw gateway 三条真实模型调用链路
