# CPA OpenAI Basis Points 插件

这是一个 CLIProxyAPI（CPA）原生插件，用 CPA 已有的 ChatGPT/Codex OAuth 凭据直接请求。

## 通过 CPA 插件商店安装（推荐）

在管理界面的「第三方插件源 → 插件源 registry URL (plugins.store-sources)」中添加以下地址并保存，然后刷新插件商店，搜索 **CPA OpenAI Basis Points**：

```text
https://raw.githubusercontent.com/JaxsonWang/cpa-plugin-oai-basispoints/main/registry.json
```

也可合并到 CPA **宿主配置**（`config.yaml`，与下方插件配置共用同一个 `plugins` 节点）：

```yaml
plugins:
  enabled: true
  store-sources:
    - https://raw.githubusercontent.com/JaxsonWang/cpa-plugin-oai-basispoints/main/registry.json
```

保留已有插件源，不要整体覆盖原有 `plugins` 配置；内置官方源由 CPA 自动保留。本源使用宿主原生的 `github-release` 安装方式，最新版本以本仓库已发布的 GitHub Release 为准，不在 registry 中另行维护版本号。CPA 会按运行平台下载 `oai-basispoints_<version>_<goos>_<goarch>.zip`，并使用同一 Release 的 `checksums.txt` 校验。

发行包覆盖 Linux、macOS、Windows 的 AMD64/ARM64。插件商店负责下载、校验和安装；更新已加载的动态库后仍需重启 CPA，使新代码及 OAuth 认证解析生效。

## 安装和配置

1. 将 `build/linux/amd64/oai-basispoints.so` 复制到 CPA 的 Linux amd64 插件目录。
2. 将 `config.example.yaml` 按需合并到 CPA 的 `config.yaml`；它是完整的宿主配置示例，不会由插件自动读取。插件内置默认暴露 `gpt-6-astra-basispoints`，示例同时配置 Astra 和 Sol，可继续增删模型。
3. CPA 的 `auth-dir` 中已有的 `type: codex` OAuth 文件会被插件识别；插件只在内存中读取 token，不生成另一份 token 文件。
4. 客户端使用 Responses 协议调用 `gpt-6-astra-basispoints`。模型目录声明图像输入，以及 `low`、`medium`、`high`、`xhigh`、`max`、`ultra` 思考等级；`max` 映射为 `xhigh`，`ultra` 原样传递，未指定时默认 `medium`。

插件的 `auth.parse` 会接管 CPA 中 `type: codex` 的 OAuth 文件，并为同一个文件展开两条内存认证：一条保留原生 `codex`，另一条是 `oai-basispoints` 虚拟认证。这样现有 Codex 模型继续使用 CPA 原生执行器，`gpt-6-astra-basispoints` 则使用本插件；不会生成或改写 OAuth 文件。原生 Codex 记录保留源 OAuth 元数据，供原生执行器读取访问令牌和刷新令牌。注意：当前 CPA 会把这两条记录都标记为虚拟认证，不持久化原生记录的刷新结果；Basis Points 记录也不会自动同步原生记录在内存中刷新的 JWT。源 JWT 过期时，需要先通过 CPA 更新或重新导入源 OAuth 凭据，再重新加载，单纯重载过期文件无效。流式响应遵循 Responses SSE 格式，但为保证工具调用可在完整 item 上做安全转换，当前会先读完上游 SSE 再回放给客户端，不是 token 级实时转发。

### 配置多个模型

在 `plugins.configs.oai-basispoints` 下使用 `models` 声明启用的客户端别名，使用 `model_mappings` 指定每个别名实际调用的上游模型。**条目数量不固定，不限于两个模型，也不需要复制插件实例。**

```yaml
plugins:
  enabled: true
  configs:
    oai-basispoints:
      enabled: true
      responses_url: https://bps.openai.com/basispoints/api/responses
      # 未单独映射的别名使用的默认上游模型。
      upstream_model: gpt-6-astra
      # 客户端请求时使用这些别名；未指定模型时选第一项。
      models:
        - gpt-6-astra-basispoints
        - gpt-5.6-sol-basispoints
      # 可以继续添加更多映射，数量不写死。
      model_mappings:
        gpt-6-astra-basispoints: gpt-6-astra
        gpt-5.6-sol-basispoints: gpt-5.6-sol
      timeout_seconds: 300
      max_response_bytes: 67108864
      auth_mode: chatgpt
      # 仅由 YAML 管理，避免旧 settings.json 覆盖模型配置。
      data_dir: ""
```

- **添加模型**：在 `models` 增加别名，并在 `model_mappings` 增加同名键及其上游模型名；重复此操作即可添加第三个、第四个或更多模型。
- **移除模型**：同时移除别名及对应映射。映射引用未启用的别名、空的键或值、去除首尾空白后重复的映射键都会被拒绝。
- **原有配置不变**：不填写 `model_mappings` 时，所有别名仍调用 `upstream_model`；有映射时优先使用对应映射，未单独映射的别名仍调用全局上游。
- **统一路由**：模型注册、普通请求、流式请求及 Codex 模型目录元数据均按同一份映射处理。不同上游的上下文元数据从各自的规范模型读取，不复用 Astra 的容量。

逐项中文注释见 `config.example.yaml`。已有 `plugins` / `configs` 时合并子项，不要覆盖其他插件或重复声明同名 YAML 节点。**需要使用包含此功能的新插件构建；仅修改配置不会让旧版本获得多模型支持。** 替换插件动态库并修改配置后重启 CPA。示例不代表已对 Basis Points 的所有模型完成真实联调，实际可用模型及支持参数以服务和当前账号权限为准。

当前配置优先级为：默认值 → CPA 传入的 YAML → `data_dir/settings.json` 中已有字段。示例显式设置 `data_dir: ""`，不读取或写入该持久化文件，也不会删除旧文件或影响 OAuth 凭据读取。若保留默认目录 `plugins/oai-basispoints-data`，修改 YAML 可能被旧设置覆盖；应先停止 CPA、备份 `settings.json`，再同步修改对应字段后启动。

## 构建

```bash
make test
make build
```

## 协议边界

- 上游请求始终带 `Authorization: Bearer <access_token>`、`chatgpt-account-id`、`x-openai-account-id` 和 `x-basispoints-auth-mode: chatgpt`。
- `turn_id` 按会话和当前用户 turn 稳定生成；工具结果回合只递增 `agent_iteration`，不会把同一 turn 重新当成新计划。
- 工具 `code` 是嵌套 JSON 字符串，不是 JavaScript。插件只解析它，不执行其中内容。
- 未能从 OAuth JWT 或凭据字段得到账号 ID、token 过期、上游返回非 2xx、工具名不在客户端目录中时，插件会报告明确错误，不伪造成功。

---

## 版权与社区支持

本项目基于 [MIT License](LICENSE) 开源

感谢 [LINUX DO 社区](https://linux.do/) 的支持

<a href="https://linux.do/">
  <img src="docs/assets/linuxdo.png" alt="LINUX DO 社区" width="360" />
</a>
