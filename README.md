# CPA OpenAI Basis Points 插件

这是一个 CLIProxyAPI（CPA）原生插件，用 CPA 已有的 ChatGPT/Codex OAuth 凭据直接请求：

`https://bps.openai.com/basispoints/api/responses`

插件不会执行 OfficeJS。客户端传入的 `tools` 会被从上游请求体移除，并在 developer 消息中改写为自然语言工具目录。模型请求工具时，插件只接受 Basis Points 原生的 `run_officejs`，从其 `code` 字段二次解码出真实客户端工具，再把调用转回客户端。客户端回传工具结果后，插件会把之前完整的原生 `run_officejs` item（包括 `id`、`summary`、`references` 等模型字段）和标准 `function_call_output` 一起回放给上游。

## 安装和配置

1. 将 `build/linux/amd64/oai-basispoints.so` 复制到 CPA 的 Linux amd64 插件目录。
2. 启用插件并按需合并 `config.example.yaml`。默认暴露模型 `gpt-6-astra-basispoints`。
3. CPA 的 `auth-dir` 中已有的 `type: codex` OAuth 文件会被插件识别；插件只在内存中读取 token，不生成另一份 token 文件。
4. 客户端使用 Responses 协议调用 `gpt-6-astra-basispoints`。模型目录声明图像输入，以及 `low`、`medium`、`high`、`xhigh`、`max`、`ultra` 思考等级；`max` 映射为 `xhigh`，`ultra` 原样传递，未指定时默认 `medium`。

插件的 `auth.parse` 会接管 CPA 中 `type: codex` 的 OAuth 文件，并为同一个文件展开两条内存认证：一条保留原生 `codex`，另一条是 `oai-basispoints` 虚拟认证。这样现有 Codex 模型继续使用 CPA 原生执行器，`gpt-6-astra-basispoints` 则使用本插件；不会生成或改写 OAuth 文件。原生 Codex 记录保留源 OAuth 元数据，供原生执行器读取访问令牌和刷新令牌。注意：当前 CPA 会把这两条记录都标记为虚拟认证，不持久化原生记录的刷新结果；Basis Points 记录也不会自动同步原生记录在内存中刷新的 JWT。源 JWT 过期时，需要先通过 CPA 更新或重新导入源 OAuth 凭据，再重新加载，单纯重载过期文件无效。流式响应遵循 Responses SSE 格式，但为保证工具调用可在完整 item 上做安全转换，当前会先读完上游 SSE 再回放给客户端，不是 token 级实时转发。

## 更新后自测

- 替换插件后重启 CPA，确保既有 `codex` OAuth 文件重新解析成两条认证；仅替换磁盘文件不会改变已加载的插件。
- 刷新客户端模型列表，必要时重启客户端；确认图片附件不再被本地能力检查拒绝，且思考等级不再只有 `medium`。较旧 Codex 客户端可能由 CPA 过滤 `max`，仍可使用 `xhigh`。
- 图片内容使用 Responses `input_image`（URL 或 data URL）原样转发；没有额外图片上传服务，也不做图片内容改写。
- 本地回归只验证能力声明、认证字段和请求转发，不代表已完成线上识图或客户端界面验收。

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

## v0.1.3 错误诊断

- 修复上游非 2xx 流式响应直接丢弃错误正文、未关闭流的问题；现在读取并关闭错误流，保留 HTTP 状态及校验原因。
- 错误提示附带实际 `reasoning_effort`、直接消息中的图片数量，以及 `detail=original` 图片数量；不输出图片地址或内容，隐藏凭据，并移除校验错误中的 `input`/`ctx`。
- 此版本保持 `max → xhigh`、`ultra` 原样传递；不自动重试、不降级、不丢图、不切换其他上游。
- 2026-09-25 用户实测上传图片触发 422：上一版能力声明及本地转发测试不能证明上游支持图像。诊断版仍允许复现图片请求，以获取服务端实际校验错误；图像支持尚未完成真实验收。
