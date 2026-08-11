# DSH Windows 原生部署手册（0809 基线 + WSL bash 执行器）

> **场景**：Windows 本机运行 DSH 主程序（原生 node），bash 工具经 WSL 执行。
> 本手册基于 **20260809 快照基线**（`fix/webui-experience-20260809` 分支，含全部本地 fix）
> 与家机（`C:\Users\ShiroEirin\.dsh`，2026-08-10 实机验证）的部署经验编写。
> WSL 版部署手册见 `docs/dsh-config-migration.md`。

## 0. 三句话结论

1. **官方默认 compose 不支持 Windows**（bash 工具 `['bash','-c']` 无 bash 可跑、PTY 明说 "Windows fail at boot"、sandbox `PLATFORM_CHAINS.win32 = []` fail-closed）——但**不用改任何主程序代码**，纯配置 + 插件即可在 Windows 上完整运行。
2. **bash 工具裸 `bash -c` 就能跑**：Windows 的 `C:\Windows\System32\bash.exe`（WSL 启动器）天然在 PATH 里，DSH spawn 的 `bash` 自动落到 WSL bash（家机已验证）。**不需要** PowerShell lane、不需要 shell adapter、不需要 `resolveBashPath`。
3. **沙箱 confine 在 win32 不可用**：`sandbox-policy.mode` 必须在 Windows 上设为 `danger-full-access` + `approval.policy=never`（家机 cc-tui patch 原文做法），否则 bash 工具全部 `SANDBOX_UNAVAILABLE`。

## 1. 架构

```
┌─────────────────────────── Windows 侧 ───────────────────────────┐
│  dsh web（node.exe，tsx dev 或构建产物）                           │
│    ├─ ctx.bash        ← dsh-bash-encoding（替换 bash-sandbox）     │
│    │                    └─ 自管 spawn：bash -c <cmd>                │
│    │                       ├─ 裸 `bash` → System32\bash.exe         │
│    │                       └─ 原始字节 → UTF-16LE/UTF-8/GBK 检测解码 │
│    ├─ ctx.pty         ← 核心 pty-local（win32 fail at boot，禁用）  │
│    ├─ dsh-web-terminal 插件（node-pty 直连 WSL bash，持久终端）      │
│    └─ sandbox-policy  ← mode: danger-full-access（win32）           │
└──────────────────────────┬─────────────────────────────────────────┘
                           │  wsl.exe
┌──────────────────────────▼─────────────────────────────────────────┐
│  WSL 发行版（bash / 工具链 / 文件系统访问 /mnt/c /mnt/d）            │
└────────────────────────────────────────────────────────────────────┘
```

| 层        | 组件                                                    | 状态                            |
| --------- | ------------------------------------------------------- | ------------------------------- |
| 主程序    | 0809 快照 + 本地 fix（`fix/webui-experience-20260809`） | ✅ 已就绪                       |
| bash 执行 | 裸 `bash` → System32 WSL 启动器 → WSL bash              | ✅ 零修改                       |
| 中文乱码  | `dsh-bash-encoding` 插件替换 `ctx.bash`                 | ✅ 插件级                       |
| 沙箱      | `sandbox-policy` win32 → `danger-full-access`           | ✅ 配置级（安全降级）           |
| 持久终端  | `dsh-web-terminal` 插件（node-pty）                     | ✅ 插件级（绕过核心 pty-local） |

## 2. 为什么不用 win-port 补丁

`dsh-win-port-wip`（基于 0805 的 9 个补丁）走的是 **PowerShell 方言 lane**（`resolveShellPath`/`shellArgv`/`shell-windows` adapter 四件套），家机实战证明这是**走错方向**：

- 家机 `dsh-bash-encoding/src/executor.ts` 就是裸 `['bash','-c',cmd]`，靠 System32 bash.exe 解析到 WSL，**没有 wsl.exe 显式桥接、没有 PowerShell**；
- 0809 已删除 `apps/cli/config/base.cordis.yml`（配置体系重构为 `packages/bundle/base/cordis.patch.yml`），补丁的配置改动无法直接应用；
- 补丁对沙箱也只是 `console.warn`，真正解决沙箱的是**配置层** `danger-full-access`（家机 cc-tui patch 原文），补丁反而没做。

结论：**纯配置 + 插件方案（本手册）是家机验证过的最短路径**，主程序零改动。

## 3. 前置条件

| 项      | 要求                                        |
| ------- | ------------------------------------------- | --- | ----------------------- |
| OS      | Windows 10/11                               |
| Node.js | `^22.19                                     |     | >=24`（与官方要求一致） |
| pnpm    | `corepack enable` 或独立安装                |
| WSL     | 已安装发行版（Ubuntu 等），`wsl -l -v` 可见 |
| git     | 任意版本                                    |

> ⚠️ **System32 bash.exe 检查**：`Test-Path C:\Windows\System32\bash.exe` 必须为 `True`（WSL 功能启用即有）。若为 False，说明 WSL 未启用或未安装发行版，先 `wsl --install`。

## 4. 主程序部署

```powershell
# ① 拉取仓库（0809 基线 + 本地 fix）
git clone -b fix/webui-experience-20260809 https://github.com/dsh2026/test-ShiroEirin.git D:\dsh\source\current
cd D:\dsh\source\current
pnpm install

# ② dev 模式启动（家机当前用法；构建产物方式见 §8）
Start-Process node -ArgumentList "--import","./node_modules/tsx/dist/esm/index.mjs","./apps/cli/src/bin.ts","web" `
  -WorkingDirectory (Get-Location) `
  -RedirectStandardOutput "$env:USERPROFILE\.dsh\web.log" `
  -RedirectStandardError "$env:USERPROFILE\.dsh\web.err.log" `
  -WindowStyle Hidden
```

浏览器打开 `http://127.0.0.1:3080`。

## 5. 配置落位（~/.dsh）

```
%USERPROFILE%\.dsh\
├── cordis.patch.yml        ← ★ home 级 patch（bash 替换 + 插件 insert + 沙箱降级）
├── settings.yaml           ← UI 设置（可选）
├── plugins\                ← 插件本体（见 §6）
├── profiles\web\           ← web profile（cordis.yml + package.json + pnpm-workspace.yaml）
└── skills\                 ← skills 目录（可选，按需）
```

### 5.1 `cordis.patch.yml` 关键段（0809 格式）

0809 的 web profile = `dsh-base` bundle（`packages/bundle/base/cordis.patch.yml`）+ `dsh-web-app` bundle + home 级 patch。home 级 patch 是顶层 YAML 数组：

```yaml
# --- ① 沙箱降级（Windows 无 confinement runner，必须 full-access + 免审批）---
- id: sandbox-policy
  config:
    mode: !!js "process.platform === 'win32' ? 'danger-full-access' : (process.env.DSH_PERMISSION_MODE ?? 'workspace-write')"
    workspaceRoot: !!js process.cwd()

- id: approval
  config:
    policy: !!js "process.platform === 'win32' ? 'never' : ((process.env.DSH_PERMISSION_MODE ?? 'workspace-write') === 'danger-full-access' ? 'never' : 'ask')"

# --- ② bash 工具替换（同一 context 只能有一个 ctx.bash）---
- id: bash-sandbox
  disabled: true

- insert:
    - id: bash
      name: "file:///C:/Users/<USER>/.dsh/plugins/dsh-bash-encoding/lib/index.js"
      config:
        timeoutMs: 120000
        maxTimeoutMs: 600000
        maxOutputBytes: 65536
        graceMs: 3000

    # --- ③ 可选：核心 client 插件（junction 见 §7）---
    - id: dsh-skills-manager
      name: "@dsh-external/dsh-skills-manager"
```

> ⚠️ 0809 差异说明：
>
> - 0806 的 `apps/cli/config/base.cordis.yml` 已删除，bash/sandbox/approval 条目现在由 `packages/bundle/base/cordis.patch.yml` 提供，**home 级 patch 直接按 id 覆盖即可**（id 不变：`sandbox-policy`/`approval`/`bash-sandbox`）。
> - 若后续上游改 id，先 `dsh --profile web --dump-config | Select-String "id:"` 核对。

### 5.2 profiles/web

`cordis.yml` = `[]`（空根，patch 组合），`package.json` 的 bundles 保持：

```json
{
  "dsh": {
    "profile": {
      "bundles": ["@deepseek-ai/dsh-base", "@deepseek-ai/dsh-web-app"]
    }
  }
}
```

## 6. 插件（全量 56 个，随部署包一次到位）

**插件本体全部随部署包拷贝**（`dsh-plugins-config-20260810/plugins/`，56 个仓库，已剔除 node_modules/.git），**不需要逐个 clone/install**。加载配置由 `cordis.patch.yml` 全文驱动（五批 insert + bash-sandbox disable，38 个插件挂载点），junction 由 `client-links.manifest`（36 条记录）全量重建——两者都由 `scripts/setup-windows-dsh.ps1` 自动处理。

> ⚠️ **为什么脚本/文档里看不到 56 个插件的逐个配置？** 因为插件加载是**声明式**的：包内 `cordis.patch.yml` 已经写好了全部 insert（client 走包名 + junction，server 走 `file:///` 绝对路径），恢复时**复制配置 + 重建 junction** 就等于把 56 个插件全部挂上。手工逐条配置反而是错的做法（还容易漏 junction）。

### 6.1 已挂载（cordis.patch.yml 五批 insert，38 个）

| 批次           | 类型      | 插件（id）                                                                                                                          |
| -------------- | --------- | ----------------------------------------------------------------------------------------------------------------------------------- |
| 批 1 (0806)    | client    | `dsh-skills-manager` `dsh-web-ui-notify` `chat-width` `dsh-ui-progress`                                                             |
| 批 1           | server    | `dsh-message-edit`(双形态 index.mjs) `dsh-session-search` `dsh-tool-calculator` `dsh-tool-json` `dsh-tool-time` `dsh-tool-encoding` |
| 批 2 (0809)    | client    | `dsh-stickers` `dsh-paste-input` `dsh-ui-whale` `dsh-web-terminal`(双形态) `dsh-memory-evolve`(裸名)                                |
| 批 2           | server    | `dsh-tool-regex` `dsh-tool-csv`                                                                                                     |
| 批 3 (0809)    | client    | `dsh-input-history` `dsh-web-archive`(裸名) `dsh-sidechain` `dsh-multimedia-webui-input` `ui-workflow`(@deepseek-ai monorepo)       |
| 批 3           | server    | `dsh-tool-markdown` `dsh-git-identity`(index.mjs) `dsh-auto-approval` `dsh-session-health` `dsh-deep-research` `dsh-inspect`        |
| 批 4 (0809)    | client    | `activity`(裸名) `dsh-skill-stats`                                                                                                  |
| 批 5 (0810)    | bash 替换 | `bash-sandbox` **disabled** → `bash`(dsh-bash-encoding)                                                                             |
| 批 5           | client    | `drag-and-drop` `skins`(@dsh-external/dsh-web-skins monorepo) `client-ui-plan-execute`                                              |
| 批 5           | server    | `plan-execute`(lib) `tool-checkpoint` `tool-rewind` `session-cluster`(后 3 个 **src 直出**，tsx dev 模式)                           |
| cc-tui profile | client    | `dsh-cc-tui`（junction 挂全局 `profiles/node_modules/@deepseek-ai`）                                                                |

### 6.2 未挂载（20 个，属正常设计）

| 插件                                                                                                                                                | 状态                                                                                             |
| --------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------ |
| `dsh-visualize` `dsh-live-stats` `dsh-subagent-tree` `official-plugins-port`                                                                        | 与 0808 基线不兼容（schema/类型/tsconfig），**其 35 个技能已单独挂载可用**；升级主程序基线后重试 |
| `dsh-genui` `dsh-github-integration` `dsh-humanize` `dsh-issue-like-skill` `dsh-plugin-dev` `dsh-skill-session-recovery` `plugin-registry` `Recall` | 纯技能提供者（skills 已展开进 `~/.dsh/skills/`，65 个，无需插件加载）                            |
| `dsh-advisor` `dsh-llm-fallbacks` `dsh-plugin-check` `dsh-session-hub` `dsh-working-activity`                                                       | 家机未启用（不在 patch 中），按需自行加 insert                                                   |

### 6.3 dsh-bash-encoding 与 0809 兼容性（已实测核对）

- 继承 `BashExecutor`（`sandboxMode`/`resolve`/`run`/`start` 0809 全部保留）
- 依赖 `cordis ^4.0.0-rc.7`（0809 vendor 仍 4.0.0-rc.7 ✓）、`schemastery ^3.18.0`（0809 vendor = 3.18.0 ✓）、`@deepseek-ai/dsh-sandbox` 类型（0809 导出齐全 ✓）
- 插件 `devDependencies` 用 `link:../.dsh/source/current/...` 相对路径 → 主程序 checkout 必须放在 `~/.dsh/source/current`（或按插件 package.json 调整）

## 7. junction 全量重建（client-links.manifest 驱动，36 条）

**一键**（推荐，见 §5 脚本）：

```powershell
.\scripts\setup-windows-dsh.ps1 -PackageDir D:\dsh-plugins-config-20260810 `
  -Checkout D:\dsh\source\current -Apply
```

**手动等价物**（README §4.2 原文，三组）：

① web profile client 插件（`profiles/web/node_modules` 下）：

- `@dsh-external` scope 14 个：`chat-width` `dsh-drag-and-drop` `dsh-input-history` `dsh-message-edit` `dsh-sidechain` `dsh-skill-stats` `dsh-skills-manager` `dsh-stickers` `dsh-ui-progress` `dsh-ui-whale` `dsh-visualize` `dsh-web-terminal` `dsh-web-ui-notify` + 特殊 `dsh-web-skins` → `plugins/dsh-skins/packages/dsh-web-skins`（monorepo）
- `@dsh-community` 2 个：`dsh-paste-input` `multimedia-webui-input`
- `@deepseek-ai` 2 个：`dsh-client-ui-plan-execute` + 特殊 `dsh-client-ui-workflow` → `plugins/dsh-web-workflow-visualizer/packages/client/ui-workflow`（monorepo）
- 根级裸名 3 个：`dsh-activity-plugin` `dsh-memory-evolve` `dsh-web-archive`
- 依赖 junction（指向 checkout）：`cordis` → `<checkout>/vendor/cordis`；`node-pty`/`ws` → `<checkout>/node_modules/.pnpm/<ver>/node_modules/<pkg>`

② 全局 src 直出依赖（`plugins/node_modules` 下，checkpoint/rewind/session-cluster 必需）：

- `@deepseek-ai` 整个 scope → `profiles/node_modules/@deepseek-ai`（147 包，由主程序 pnpm install 生成）
- 单包兜底：`cordis` `schemastery` `react` `react-dom` `zod` `clsx` `immer` `yaml` `js-yaml` `commander` → `profiles/node_modules/<pkg>`

③ cc-tui profile：`profiles/node_modules/@deepseek-ai/dsh-cc-tui` → `plugins/dsh-cc-tui`

> 脚本解析 `client-links.manifest` 全部 36 条记录（web 24 + cc-tui 1 + global 11，含 `[plugins]`/`[monorepo]`/`[checkout]`/`[profiles]`/`[plugins-deps]` 五种前缀与 web/cc-tui/global 三组落点），找不到 manifest 时**报错拒绝降级**——56 个插件一个都不能少。

## 8. 启动与验证

```powershell
# ① 端口
netstat -ano | Select-String ":3080"

# ② 插件层叠（应含 bash-sandbox disabled + insert 的 bash / client 插件）
node "$env:USERPROFILE\.dsh\source\current\apps\cli\src\bin.ts" --profile web --dump-config 2>$null | Select-String "id:"

# ③ 日志无 ERROR
Get-Content "$env:USERPROFILE\.dsh\web.log" -Tail 50
Get-Content "$env:USERPROFILE\.dsh\web.err.log" -Tail 10

# ④ bash 工具实测（web 里发一条 bash 命令，如 echo 你好）
# 应输出正常中文（无乱码）；WSL 代理警告也应可读（dsh-bash-encoding 修复）
```

## 9. 中文乱码根因与治本选项

**根因**：WSL **NAT 模式**（`.wslconfig` 无 `networkingMode=mirrored`）+ `HTTP_PROXY/HTTPS_PROXY` 指向 `localhost` → 每次 `wsl.exe` 执行命令都向 stderr 输出一条 **UTF-16LE** 代理警告；DSH 核心 subprocess 层 `Buffer.toString('utf8')` 有损解码 → 必现乱码。`dsh-bash-encoding` 自管 spawn 收集原始字节 + 流式编码检测修复。

**治本（可选，与插件互补）**：

- `.wslconfig` 设 `networkingMode=mirrored`（`%UserProfile%\.wslconfig`）
- 或设环境变量 `WSL_UTF8=1`（消除 wsl.exe 警告输出）

## 10. 已知坑

1. **改插件后必须重启 dsh web**：client bundle / server lib 有内存缓存；`cordis.patch.yml` 由 HMR 热应用，但 `plugins/` 代码要重启才生效。
2. **插件 `name` 必须写显式文件路径**：目录名会解析成 `<dir>/index.json` 失败（家机实战踩过）。
3. **junction 名称必须与 `cordis.patch.yml` 的 `name` 一一对应**：`@dsh-external/xxx` 需挂 scoped junction；裸名挂根级 junction；server 插件走 `file:///` 绝对路径不需要 junction；`src` 直出插件（checkpoint/rewind/session-cluster 等）必须依赖全局依赖 junction。
4. **`.env` 含密钥不打包**：恢复后手动创建（`DEEPSEEK_API_KEY` / `DEEPSEEK_BASE_URL`）。
5. **安全降级**：Windows 上 `workspace-write`/`read-only` 的 confine 边界不存在（`PLATFORM_CHAINS.win32 = []` fail-closed）。`danger-full-access` + `approval=never` 是**终端信任模型**（与其他终端编码代理一致），工具层策略仍生效；若需更强边界，等 sandbox 官方补 win32 runner（注释中预留 AppContainer/restricted-token 槽位）。
6. **核心 pty-local 在 win32 fail at boot**：0809 注释明说；持久终端用 `dsh-web-terminal` 插件（node-pty）替代，不依赖核心 PTY。
7. **不要 `git add -A`**：仓库很大，按需 add。

## 11. 相关产物

- 家机完整配置包（56 插件 / 65 skills / 双 profile / junction 清单）：`D:\github\DeepSeek\dsh-plugins-config-20260810\`（不在本仓库，靠拷贝携带）
- 部署辅助脚本：`scripts/setup-windows-dsh.ps1`（配置落位 + junction 重建 + 验证）
- WSL 版迁移手册：`docs/dsh-config-migration.md`
