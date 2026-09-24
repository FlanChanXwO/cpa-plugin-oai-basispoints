# CPA OpenAI Basis Points 插件

这是一个 CLIProxyAPI（CPA）原生插件，用 CPA 已有的 ChatGPT/Codex OAuth 凭据直接请求：

`https://bps.openai.com/basispoints/api/responses`

插件不会执行 OfficeJS。客户端传入的 `tools` 会被从上游请求体移除，并在 developer 消息中改写为自然语言工具目录。模型请求工具时，插件只接受 Basis Points 原生的 `run_officejs`，从其 `code` 字段二次解码出真实客户端工具，再把调用转回客户端。客户端回传工具结果后，插件会把之前完整的原生 `run_officejs` item（包括 `id`、`summary`、`references` 等模型字段）和标准 `function_call_output` 一起回放给上游。

## 通过 CPA 插件商店安装（推荐）

在管理界面的「第三方插件源 → 插件源 registry URL (plugins.store-sources)」中添加以下地址并保存，然后刷新插件商店，搜索 **CPA OpenAI Basis Points**：

```text
https://raw.githubusercontent.com/JaxsonWang/cpa-plugin-oai-basispoints/main/registry.json
```

也可合并到 CPA **宿主配置**（不是本仓库的插件参数 `config.example.yaml`）：

```yaml
plugins:
  enabled: true
  store-sources:
    - https://raw.githubusercontent.com/JaxsonWang/cpa-plugin-oai-basispoints/main/registry.json
```

保留已有插件源，不要整体覆盖原有 `plugins` 配置；内置官方源由 CPA 自动保留。本源使用宿主原生的 `github-release` 安装方式，最新版本以本仓库已发布的 GitHub Release 为准，不在 registry 中另行维护版本号。CPA 会按运行平台下载 `oai-basispoints_<version>_<goos>_<goarch>.zip`，并使用同一 Release 的 `checksums.txt` 校验。

发行包覆盖 Linux、macOS、Windows 的 AMD64/ARM64。插件商店负责下载、校验和安装；更新已加载的动态库后仍需重启 CPA，使新代码及 OAuth 认证解析生效。

## 已知问题：Fast 暂不可用

跟踪 [issue #3](https://github.com/JaxsonWang/cpa-plugin-oai-basispoints/issues/3)。2026-09-25 真实对照确认：同一模型、相同纯文本和 `xhigh`，不发送 `service_tier` 返回 200 和 `OK`；显式发送 `default` 或 `priority` 均返回 422。当前目录中的 Fast 选项是插件声明，不等于 Basis Points 已支持优先处理。

使用该通道时请不要开启 Fast，并确保请求**省略 `service_tier`**；仅改成 `default` 也不能解决。本次发布不修改该问题的处理逻辑、不静默降级，也不宣称 Fast 已修复。

## 安装和配置

1. 将 `build/linux/amd64/oai-basispoints.so` 复制到 CPA 的 Linux amd64 插件目录。
2. 启用插件并按需合并 `config.example.yaml`。默认暴露模型 `gpt-6-astra-basispoints`。
3. CPA 的 `auth-dir` 中已有的 `type: codex` OAuth 文件会被插件识别；插件只在内存中读取 token，不生成另一份 token 文件。
4. 客户端使用 Responses 协议调用 `gpt-6-astra-basispoints`。模型目录声明图像输入，以及 `low`、`medium`、`high`、`xhigh`、`max`、`ultra` 思考等级；`max` 映射为 `xhigh`，`ultra` 原样传递，未指定时默认 `medium`。

插件的 `auth.parse` 会接管 CPA 中 `type: codex` 的 OAuth 文件，并为同一个文件展开两条内存认证：一条保留原生 `codex`，另一条是 `oai-basispoints` 虚拟认证。这样现有 Codex 模型继续使用 CPA 原生执行器，`gpt-6-astra-basispoints` 则使用本插件；不会生成或改写 OAuth 文件。原生 Codex 记录保留源 OAuth 元数据，供原生执行器读取访问令牌和刷新令牌。注意：当前 CPA 会把这两条记录都标记为虚拟认证，不持久化原生记录的刷新结果；Basis Points 记录也不会自动同步原生记录在内存中刷新的 JWT。源 JWT 过期时，需要先通过 CPA 更新或重新导入源 OAuth 凭据，再重新加载，单纯重载过期文件无效。流式响应遵循 Responses SSE 格式，但为保证工具调用可在完整 item 上做安全转换，当前会先读完上游 SSE 再回放给客户端，不是 token 级实时转发。

## 更新后自测

- 替换插件后重启 CPA，确保既有 `codex` OAuth 文件重新解析成两条认证；仅替换磁盘文件不会改变已加载的插件。
- 刷新客户端模型列表，必要时重启客户端；确认图片附件不再被本地能力检查拒绝，且思考等级不再只有 `medium`。较旧 Codex 客户端可能由 CPA 过滤 `max`，仍可使用 `xhigh`。
- 用户消息中的 data URL 图片先通过 Basis Points 附件接口上传，再以 `input_image.file_id` 发送；HTTP(S) 图片 URL 和已有 `file_id` 保持原样，详见 v0.1.6 说明。
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

## GitHub Actions 打包与发布

工作流参考 `haowang02/cpa-plugin-key-billing`，适配本项目的 C ABI 入口和版本常量，使用仓库自带的 `GITHUB_TOKEN` 发布。

- `Check`：分支推送、Pull Request 或手动触发时，检查 Go 格式、依赖文件和工作流语法，并运行 `go test -race ./...`、`go vet ./...`。Go 版本从 `go.mod` 读取。
- `Release`：推送 `v*` 标签时自动执行，也可在 Actions 页面手动填写已有标签重新打包。标签必须与 `internal/basispoints/types.go` 中的 `Version` 一致，例如版本 `0.1.8` 对应 `v0.1.8`。
- 检查通过后构建 Linux AMD64/ARM64、macOS Intel/Apple Silicon、Windows AMD64/ARM64。Linux 沿用 manylinux2014 构建环境，避免直接依赖新版 Ubuntu 的 glibc。
- 每个平台上传独立的 Actions artifact（保留 7 天）；全部构建成功后，发布到对应 GitHub Release，并附带 `checksums.txt`。构建和检查只读仓库，只有发布任务具有 `contents: write` 权限。

Linux 和 macOS 同时提供 `.tar.gz` 与 `.zip`，Windows 提供 `.zip`。每个归档根目录只包含一个插件动态库，不包含 CGO 头文件。以 Linux AMD64 为例：

```text
oai-basispoints_0.1.8_linux_amd64.tar.gz
oai-basispoints_0.1.8_linux_amd64.zip
  └── oai-basispoints.so
```

发布时先更新版本常量并提交，再推送对应标签；仅推送分支会运行检查，不会创建 Release。手动发布要求标签已经存在，且 Actions 已启用并允许工作流申请写入权限。

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

## 速度与上下文目录修复（无需升级 CPA 宿主）

当前方案兼容 **`eceasy/cli-proxy-api:v7.3.16`**，不要求替换 CPA 主程序或 Docker 镜像。该版本已有模型目录响应钩子 `response.intercept_after`；插件通过此钩子修正自己配置的模型别名。此前 v0.1.4/v0.1.5 使用新增 `MetadataModelID`、`SupportedServiceTiers` 字段的方案依赖宿主修改，现已改为使用既有扩展接口，不再依赖这些新增字段。

- 插件在同一份 Codex 模型目录中找到 `upstream_model` 对应的规范模型，只将 `context_window`、`max_context_window`、`effective_context_window_percent` 同步到自己的别名。不复制系统指令或其他模型能力，不把窗口写死为 500000，也不宣称无限上下文。
- Codex 会把 `model_context_window` 与目录中的 `max_context_window` 取较小值，再按有效窗口比例显示。此前 `min(500000, 272000) × 95% = 258400`；改用当前 Astra 元数据后，本地 500000 配置不再被 272000 压低，按 95% 预计显示约 475000。实际大上下文请求仍受 Basis Points 服务端约束，尚未进行 500k 真实验收。
- 不修改用户的 `~/.codex/config.toml`，也不让远端 CPA 读取客户端机器的配置。移除插件未收到客户端策略时擅自添加的 `compact_threshold = 200000`；未指定、`null` 或空数组时省略 `context_management`，有明确非空策略则原样保留（v0.1.5 修正；v0.1.4 发送空数组会触发 HTTP 400）。
- 在插件专用别名上同时输出 `service_tiers: [{id: priority, name: Fast, ...}]` 和 `additional_speed_tiers: [fast]`，避免两个速度字段不一致。不沿用原生模型的倍速或计费承诺，也不修改其他模型的档位。请保留独立的 Basis Points 别名，不与其他提供方共用同一模型 ID。
- 客户端的 `service_tier` 原样传到 Basis Points；客户端没传时插件不主动启用。**后续真实对照已确认 `default` 和 `priority` 均触发 422，见顶部已知问题及 issue #3；该入口目前不可视为可用 Fast。**
- 只需替换本插件动态库并重启现有 CPA，再刷新 Codex 模型目录；不需要更新宿主镜像，不改模型名或客户端配置，也不手工修改 `models_cache.json`。先检查实时 `/v1/models?client_version=...`，再验收客户端界面。
- 目录必须同时包含配置的规范模型及其真实窗口字段；带 CPA 路由前缀的别名使用相同前缀的规范模型。若规范模型被隐藏或缺少窗口元数据，插件会报告 `model_metadata_missing`，不编造容量；宿主拦截器失败时仍会返回原始目录，可在 CPA 日志中查看原因。

### 仍保留的限制与协议边界

| 项目 | 当前行为 | 是否可配置 / 说明 |
| --- | --- | --- |
| 思考等级 | `low / medium / high / xhigh / ultra`；`max → xhigh`；未指定或未知值变为 `medium` | `max` 映射和 `ultra` 透传保留用户既定要求；未知值回退是已有行为 |
| 响应读取超时 | 默认 300 秒 | `timeout_seconds` 可设 10–1800 秒；不是上下文 token 上限 |
| 响应缓冲 | 默认 64 MiB | `max_response_bytes` 可设 64 KiB–128 MiB；全量缓冲的内存保护，不是图片输入或上下文 token 上限 |
| 工具调用回放缓存 | 全局保留最近 512 个原生调用 | 固定值；更旧调用依赖已有的回放重建逻辑 |
| Metadata | 键最多 64 字节、字符串值最多 512 字节 | 固定裁剪；`task_id / turn_id / agent_iteration` 由插件生成 |
| 流式输出 | 上游读完后回放 SSE | 不是逐 token 实时输出；Fast 不会消除这一等待行为 |
| Token 统计 | `executor.count_tokens` 目前返回 0 | 不是准确计数；不能据此判断剩余上下文 |
| 输入与参数 | 仅 Responses；上游请求体按明确字段构建 | 不保证透传任意参数；如 `temperature / top_p / max_output_tokens` 当前不转发 |
| 图像 | 用户消息中的 data URL 先上传附件，再发送 `file_id`（v0.1.6） | 保留明确的 `detail`；HTTP(S) URL 交给上游下载，工具截图不改写；远端识图待部署验收 |
| 图片引用缓存 | 进程内最近 512 个成功上传的文件 ID | 仅缓存摘要和 ID；按端点、账号与访问令牌隔离，不是请求图片数或上下文上限；重启后重新上传 |
| 认证 | 使用源 Codex OAuth JWT | 仍无跨虚拟认证的刷新同步；过期需更新源凭据 |

### 参考项目核对

2026-09-25 核对 `Nonary/ghcp_proxy` 的 `main` 提交 `ad23ce2db3b5212c0355762d981c3877322fb160`：`excel_upstream.py` 与本地参考副本相同，Excel 通道仍声明 `input_modalities: [text]`、`vision: False`，没有图片转换、上传或速度档位传递实现。因此它可作该项目实现的参考，但不能据此推断 Basis Points 网关不支持图片。v0.1.6 改以官方 Excel 前端的附件协议为依据。

本次使用本地已配置的 CPA 认证真实发送了两组新请求：相同模型、`reasoning.effort=medium`、相同短提示；纯文本返回 HTTP 200、`response.completed` 和 `OK`，加一张程序生成的有效 32×32 红色 PNG（`detail=auto`）返回 HTTP 422，仍为 `Invalid request body`。这确认当前已部署链路拒绝此最小图片输入，不是只有原截图或旧会话才触发。当时尚未找到官方附件契约；随后在 v0.1.6 排查中确认了官方前端的上传流程。当前仍未取得可直接联调该网关的 OAuth，也未验证优先调度及 500k 实际承载能力。新错误摘要增加安全的 `service_tier`，便于区分速度字段与图片字段的拒绝；不输出未识别字段内容。

## v0.1.5 空压缩策略修复

修复 v0.1.4 移除默认 200k 压缩阈值时引入的回归：插件曾发送 `context_management: []`，而上游要求该字段出现时至少包含一项，导致纯文本也返回 HTTP 400。现在未指定、`null` 或空数组均不发送该字段；非空策略和明确阈值原样保留，不重新加回 200k 限制。不隐藏错误类型，由上游继续报告不合法的策略。

新增请求实际序列化边界测试，覆盖流式/非流式、`OriginalRequest`/`Payload`、缺省/空/显式策略；v0.1.4 的错误“应发送空数组”断言已移除。此修复只需替换插件并重启 CPA；当前速度与上下文目录方案同样不再要求升级宿主，见前述响应钩子说明。

## v0.1.6 内嵌图片上传修复

2026-09-25 对同一已部署 CPA 链路复测：`reasoning_effort=xhigh` 的纯文本返回 200 和 `OK`；相同公开 PNG 用 Base64 data URL 发送返回 422，用 HTTPS URL 发送则返回 400 `Failed to download file`。这说明两种载荷走了不同处理路径，不能简单归因于思考等级，也不能认为模型没有视觉能力。

官方 Excel 前端提供了缺失的上传契约：

1. `POST /basispoints/api/attachments`，上传 `multipart/form-data`，只有一个 `file` 字段，不使用公共 OpenAI Files API 的 `purpose` 参数。
2. 读取响应的 `openai_file_id`；没有有效 ID 必须报错，不能伪造成功。
3. 用户图片作为 `input_image` 发送，使用 `file_id` 而不是内嵌 `image_url`。插件保留客户端明确的 `detail`，仅缺省时补官方客户端使用的 `auto`，不自行降低精度。不支持的值仍由服务端校验。

仅转换直接用户消息中的 data URL。已有 `file_id` 和 HTTP(S) URL 原样保留，不自行下载任意 URL，避免新增 SSRF 或凭据泄漏路径。工具输出图片保持原协议。会话标识先按原始输入计算，再替换附件 ID，避免改变 `task_id / turn_id`。

上传端点与 `responses_url` 同源、同目录，使用现有宿主 HTTP 回调和当前 OAuth。原始图片字节、MIME 类型、明确精度保持不变。历史回放和并发复用成功上传的 ID；缓存按端点、账号、令牌和图片摘要隔离，内存最多 512 项，不持久化图片或令牌。淘汰、重启、令牌改变后重新上传，不限制请求包含更多图片。

上传失败保留 HTTP 状态，错误前缀为 `Basis Points attachment upload`，隐藏凭据和图片字节；不继续提交缺图对话、不自动重试或降级。大小和格式由真实附件服务校验，没有新增固定像素、图片数量或上下文 token 限制。

保留 v0.1.5 的空 `context_management` 修复。图片适配只需替换插件；当前模型目录已使用 CPA v7.3.16 既有响应钩子，不再要求修改宿主。Fast 的实际请求仍有顶部所述已知问题。

协议来源（2026-09-25 读取的官方公开资源）：

- Manifest：`https://bps.openai.com/basispoints/api/office/manifest.xml`。
- 前端：`https://bps.openai.com/basispoints/extension/360590d7-f8f9-4d88-bf75-0edfe0a4b9f3/assets/x-square-CTaa3pDu.js`。
- `hMt` 使用 FormData 的 file 字段调用 attachments，`pMt` 读取 openai_file_id，`Lme` 生成用户 input_image/file_id，`Nee` 与 `zL` 确定 `/basispoints/api` 基址。

新增测试覆盖 multipart 原字节、上传与 Responses 调用、流式/非流式、OriginalRequest/Payload、重复图片、并发、账号/令牌/端点隔离、缓存淘汰、错误状态与响应、脱敏和同源地址；另用真实本地 HTTP 服务器贯通执行器。这些测试验证代理实现和协议，不等于真实 Basis Points 已成功识图：新 `.so` 仍需上传到目标 CPA、重启后用原图复测。

## v0.1.7 非流式宿主回调状态修复

2026-09-25 的日志出现 16 次 `Basis Points attachment upload HTTP 0`，每次正文均已返回 `openai_file_id`。图片实际上传成功，插件却误判为失败，CPA 因此反复换认证重试，客户端表现为持续思考；请求尚未进入正常识图响应阶段。

根因是两种宿主回调的 JSON 契约不同：`callHostHTTPDo` 直接序列化 `pluginapi.HTTPResponse`，使用 `StatusCode / Headers / Body`；`callHostHTTPDoStream` 使用独立 RPC 结构，字段为 `status_code / headers / stream_id`。插件错误地把非流式返回也标记为 `status_code`，JSON 解码没有匹配到 `StatusCode`，状态遂保留为 Go 默认值 0。

本次仅将非流式 DTO 对齐实际宿主字段；流式 RPC 保持原样。附件上传和非流式 Responses 共用此修复，不把 0 硬改为 200、不隐藏真正的 4xx/5xx，也不调整 CPA 的账号重试策略。

此前附件测试直接给 Go 结构体赋值，漏过了宿主 JSON 反序列化边界。现已补齐独立宿主字段夹具、200/201/204 与错误状态、本地 HTTP 往返和流式完成事件测试。旧代码可稳定复现 HTTP 0，修复后通过。另使用实际加载的本机 c-shared 动态库验证 C ABI：multipart 上传、PascalCase 返回解码、缓存复用、snake_case 流式读取、完成事件和 422 状态传递均通过。这里的响应为测试夹具，不等同于真实 NAS 上的识图验收。

为避开共享工作区另一项工具命名空间改动及其未完成的备份包，本次发布使用修改前快照叠加 HTTP 状态修复独立构建；该构建通过 `go test -race ./...` 和 `go vet ./...`。工具命名空间工作保留在原工作区，没有覆盖或删除，也没有混入这份修复包。

## 客户端原生工具协议兼容

修复命名空间工具被降为短名的问题：客户端声明 `mcp__node_repl.js` 时，返回的 Responses 调用同时携带 `name: js` 和 `namespace: mcp__node_repl`，不再把它错误派发成无命名空间的 `js`。平铺工具名保持原样，不按点号或双下划线猜测命名空间。

- 支持客户端 `function`、`custom` 及 `namespace` 分组；函数完整参数 schema 和自定义工具的 format/grammar 写入模型工具目录，不再只描述顶层参数名。
- 保留函数参数内的大整数、自定义工具输入的空白和换行；custom 输入必须是原始字符串，不把对象伪装成文本。
- 保留 `call_id`、原生调用和结果关联；缓存未命中时按完整工具名重建既有中转。当前回合的 `tool_choice` 不影响历史调用回放。
- 工具结果中的图片、多模态内容和空输出原样保留，不再替换为“成功但无输出”。
- JSON 响应支持多个调用；SSE 输出补齐 function arguments 和 custom input 的 delta/done、item 生命周期及递增序号。added 事件不再提前带上完整输入，避免客户端重复拼接。
- 对客户端函数/自定义工具执行 `tool_choice` 的 `none`、`auto`、`required`、指定工具及 `allowed_tools` 约束；`parallel_tool_calls: false` 禁止一个响应返回多个调用。
- 非目录工具、损坏的中转载荷、尾随 JSON、重复调用 ID 等返回明确协议错误，不把 `run_officejs` 或服务器注入工具泄漏给客户端执行，也不自动重试或伪造成功。

**边界：这是客户端 Responses 工具协议兼容，不是上游任意原生工具透传。** Basis Points 侧仍使用既有 `run_officejs` 中转，插件不执行工具；真正的执行继续由 Codex 客户端完成。没有新增或声称支持服务器托管的 `web_search`、`computer`、`code_interpreter` 等工具，也不承诺完整 JSON Schema/grammar 的服务端约束生成。流式响应仍为先缓冲上游再输出事件，不是逐 token 实时转发。

本地回归覆盖 function/custom、平铺/命名空间身份、同名隔离、完整 schema、数字精度、空白与图片保留、缓存命中/缺失、调用限制、错误拒绝，以及流式/非流式执行器和下一轮回放。协议字段核对自官方 Responses create 与 streaming-events 文档。测试使用本地宿主回调和受控上游响应，不代表真实微信或远端工具已完成联调；部署新插件、重启 CPA 后仍需实测。

本次独立 Linux AMD64 验证产物位于 `build/tool-protocol/linux/amd64/oai-basispoints.so`，不覆盖既有构建目录，不自动安装或重启 CPA。
