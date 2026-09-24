# CPA OpenAI Basis Points 插件

这是一个 CLIProxyAPI（CPA）原生插件，用 CPA 已有的 ChatGPT/Codex OAuth 凭据直接请求：

`https://bps.openai.com/basispoints/api/responses`

插件不会执行 OfficeJS。客户端传入的 `tools` 会被从上游请求体移除，并在 developer 消息中改写为自然语言工具目录。模型请求工具时，插件只接受 Basis Points 原生的 `run_officejs`，从其 `code` 字段二次解码出真实客户端工具，再把调用转回客户端。客户端回传工具结果后，插件会把之前完整的原生 `run_officejs` item（包括 `id`、`summary`、`references` 等模型字段）和标准 `function_call_output` 一起回放给上游。

## 安装和配置

1. 将 `build/linux/amd64/oai-basispoints.so` 复制到 CPA 的 Linux amd64 插件目录。
2. 启用插件并按需合并 `config.example.yaml`。默认暴露模型 `gpt-6-astra-basispoints`。
3. CPA 的 `auth-dir` 中已有的 `type: codex` OAuth 文件会被插件识别；插件只在内存中读取 token，不生成另一份 token 文件。
4. 客户端使用 Responses 协议调用 `gpt-6-astra-basispoints`。`reasoning.effort` 支持 `low`、`medium`、`high`、`xhigh`；`max`/`ultra` 会安全降为 `medium`，因为 Basis Points 当前没有 `max` 挡位。

插件的 `auth.parse` 会接管 CPA 中 `type: codex` 的 OAuth 文件，并为同一个文件展开两条内存认证：一条保留原生 `codex`，另一条是 `oai-basispoints` 虚拟认证。这样现有 Codex 模型继续使用 CPA 原生执行器，`gpt-6-astra-basispoints` 则使用本插件；不会生成或改写 OAuth 文件。Basis Points 虚拟认证沿用源文件中的 JWT，过期后需要 CPA 重新加载该源文件。流式响应遵循 Responses SSE 格式，但为保证工具调用可在完整 item 上做安全转换，当前会先读完上游 SSE 再回放给客户端，不是 token 级实时转发。

## 构建

```bash
make test
make build
```

本机是 macOS/ARM 时，可使用 Zig 提供 Linux AMD64 C 编译器：

```bash
mkdir -p build/linux/amd64
CGO_ENABLED=1 GOOS=linux GOARCH=amd64 \
  CC='zig cc -target x86_64-linux-gnu' \
  go build -trimpath -buildmode=c-shared \
  -o build/linux/amd64/oai-basispoints.so ./cmd/basispoints
```

## 协议边界

- 上游请求始终带 `Authorization: Bearer <access_token>`、`chatgpt-account-id`、`x-openai-account-id` 和 `x-basispoints-auth-mode: chatgpt`。
- `turn_id` 按会话和当前用户 turn 稳定生成；工具结果回合只递增 `agent_iteration`，不会把同一 turn 重新当成新计划。
- 工具 `code` 是嵌套 JSON 字符串，不是 JavaScript。插件只解析它，不执行其中内容。
- 未能从 OAuth JWT 或凭据字段得到账号 ID、token 过期、上游返回非 2xx、工具名不在客户端目录中时，插件会报告明确错误，不伪造成功。
