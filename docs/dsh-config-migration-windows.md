# DSH 插件与配置打包说明（Windows 部署）

> **场景**：把本机（Windows，`C:\Users\ShiroEirin\.dsh`）已调好的 DSH（DeepSeek Harness）配置、插件、skills 打包，用于备份或在另一台 Windows 机器上恢复。
> **生成时间**：2026-08-10。源：`C:\Users\ShiroEirin\.dsh`（cordis 4.0.0-rc.7，web profile + cc-tui profile，49 个插件仓库、38 个挂载插件、8 个 skills）。

---

## 0. 三句话结论

1. **主程序不用打包**：`git clone` 仓库后 `scripts/install-windows.ps1` 或 tsx dev 模式启动即可（见 §4）。
2. **必须迁移的是 `.dsh` 下的配置、插件与 skills**：`cordis.patch.yml`（核心）、`plugins/`（49 个插件仓库）、`profiles/web/` + `profiles/cc-tui/`（2 个 profile 配置）、`skills/`（8 个技能）、`settings.yaml`。
3. **恢复后必须重建 junction**（打包不携带 junction 目标）：client 插件全部走 `profiles/web/node_modules` 下的 junction，`src` 直出插件依赖 `plugins/node_modules/@deepseek-ai` 全局 junction，不重建则插件加载失败（见 §3.2）。

---

## 1. 包目录结构

```
dsh-pack-20260809/
├── README.md                 ← 本文档
├── cordis.patch.yml          ← ★核心：home 级插件清单（含第五批 insert + bash-sandbox disable）
├── settings.yaml             ← UI 设置（直接放 ~/.dsh/）
├── plugins/                  ← 49 个插件仓库（约 130M，已剔除 node_modules/.git；空仓库 dsh-session-hub 不携带）
├── skills/                   ← 8 个已装技能（见 §2 skills 清单）
└── profiles/
    ├── web/                  ← web profile 配置（cordis.patch.yml + cordis.yml + package.json + pnpm-workspace.yaml，不含 node_modules）
    └── cc-tui/               ← cc-tui profile（package.json + cordis.yml + cordis.patch.yml，bundles=dsh-base+dsh-cc-tui）
```

### 1.1 不打包清单（恢复时重新生成/配置，别拷！）

| 不打包 | 原因 |
| --- | --- |
| `.env` | **含 API 密钥**，恢复后手动重填 |
| `profiles/node_modules/`、`profiles/web/node_modules/` | 由主程序安装/链接生成，恢复后重建 junction（§3.2） |
| `sessions/`、`storages/`、`memories/` | 会话/存储数据，按需手动拷贝 |
| `logs/`、`web.log`、`web.err.log` | 运行日志 |
| `source/` | 主程序源码，`git clone` + 安装脚本 |

---

## 2. Skills 清单（8 个，均已装）

> skills 装在 `C:\Users\ShiroEirin\.dsh\skills\` 下，恢复时整目录拷过去即可（skill-local 自动发现）。来源标注便于后续单独重装。

| Skill 目录 | 来源 | 用途 |
| --- | --- | --- |
| `deep-standard` | 手动安装（dsh-external/deep-standard-skill） | 可执行工程标准体系：六法则 + 三档采纳阶梯 + 模板，把约定硬化成会拒绝违规的门禁程序 |
| `dsh-issue-filer` | 手动安装（dsh-external/dsh-issue-filer） | 向 dsh-external/issues 提 issue：自动查重、按仓库规范格式化、本地台账记录 |
| `dsh-session-repair` | 手动安装（dsh-external/dsh-session-repair-skill） | 修复损坏的 DSH 会话历史（多客户端并发写 seq 损坏）：扫描 ~/.dsh/sessions、自动修复 stale-tail/stale-counter、GUI 验证 |
| `dsh-reuse-first` | 手动安装（来自 DSH checkout skills 目录） | 实现任何新功能/插件/工具前，先检查当前 dsh checkout 是否已提供 |
| `codex-cli-calling` | **dsh-memory-evolve 自动生成**（x-provider: dsh-memory-evolve） | 从命令行直接调用 Codex（不进交互式 TUI），含参数透传 |
| `grok-cli-calling` | **dsh-memory-evolve 自动生成** | 从命令行调用 Grok CLI |
| `hermes-cli-calling` | **dsh-memory-evolve 自动生成** | 从命令行调用 Hermes Agent |
| `kimi-cli-calling` | **dsh-memory-evolve 自动生成** | 从命令行调用 Kimi Code CLI |

> ⚠️ 4 个 `*-cli-calling` 是 dsh-memory-evolve 插件在运行中自动生成的（memory-evolve 的「技能自我进化」能力），恢复后若 memory-evolve 重新生成同名技能会覆盖/共存，属正常现象。

---

## 3. 恢复前置条件

- Windows 10/11 + Node.js 22.x（fnm/nvm 均可）
- pnpm（`corepack enable` 或独立安装）
- DSH 仓库 checkout（`fix/webui-experience-20260806` 分支）

---

## 4. 恢复步骤（agent 逐条执行）

### 4.1 放置配置、插件与 skills

```powershell
# 假设新机器用户为 <USER>
$dsh = "C:\Users\<USER>\.dsh"
New-Item -ItemType Directory -Force -Path "$dsh" | Out-Null
Copy-Item cordis.patch.yml settings.yaml $dsh\
Copy-Item plugins $dsh\ -Recurse
Copy-Item skills $dsh\ -Recurse
New-Item -ItemType Directory -Force -Path "$dsh\profiles\web","$dsh\profiles\cc-tui" | Out-Null
Copy-Item profiles\web\* $dsh\profiles\web\ -Recurse
Copy-Item profiles\cc-tui\* $dsh\profiles\cc-tui\ -Recurse
```

> ⚠️ `cordis.patch.yml` 里 server 插件是 `file:///C:/Users/ShiroEirin/.dsh/plugins/...` 绝对路径，新机器用户名不是 `ShiroEirin` 时**必须全局替换**：
> `(Get-Content $dsh\cordis.patch.yml -Raw).Replace('C:/Users/ShiroEirin', 'C:/Users/<USER>') | Set-Content $dsh\cordis.patch.yml`

### 4.2 重建 junction（★ 必做，打包不携带）

**① web profile client 插件 junction**（`profiles/web/node_modules` 下，指向 `plugins/`）：

```powershell
$nm = "$dsh\profiles\web\node_modules"
New-Item -ItemType Directory -Force -Path "$nm\@dsh-external","$nm\@dsh-community","$nm\@deepseek-ai" | Out-Null
# @dsh-external scope
$ext = 'chat-width','dsh-drag-and-drop','dsh-input-history','dsh-message-edit','dsh-sidechain','dsh-skill-stats','dsh-skills-manager','dsh-stickers','dsh-ui-progress','dsh-ui-whale','dsh-visualize','dsh-web-skins','dsh-web-terminal','dsh-web-ui-notify'
foreach ($p in $ext) { New-Item -ItemType Junction -Path "$nm\@dsh-external\$p" -Target "$dsh\plugins\$p" | Out-Null }
# @dsh-community scope
New-Item -ItemType Junction -Path "$nm\@dsh-community\dsh-paste-input" -Target "$dsh\plugins\dsh-paste-input" | Out-Null
New-Item -ItemType Junction -Path "$nm\@dsh-community\multimedia-webui-input" -Target "$dsh\plugins\dsh-multimedia-webui-input" | Out-Null
# @deepseek-ai scope（client-ui-* 系）
New-Item -ItemType Junction -Path "$nm\@deepseek-ai\dsh-client-ui-plan-execute" -Target "$dsh\plugins\dsh-client-ui-plan-execute" | Out-Null
# 根级裸名
foreach ($p in 'dsh-activity-plugin','dsh-memory-evolve','dsh-web-archive') { New-Item -ItemType Junction -Path "$nm\$p" -Target "$dsh\plugins\$p" | Out-Null }
```

> ⚠️ `@dsh-external/dsh-web-skins` 的目标是 monorepo 子包：`plugins\dsh-skins\packages\dsh-web-skins`。visualize junction 可保留（声明已从 cordis.patch.yml 移除，挂载无害）。

**② 全局依赖 junction**（`src` 直出 server 插件解析 @deepseek-ai/* 依赖的关键，★ 必做）：

```powershell
# 全量 @deepseek-ai 作用域（147 包）→ checkpoint/rewind/session-cluster 等 src 直出插件运行时解析
New-Item -ItemType Directory -Force -Path "$dsh\plugins\node_modules" | Out-Null
New-Item -ItemType Junction -Path "$dsh\plugins\node_modules\@deepseek-ai" -Target "$dsh\profiles\node_modules\@deepseek-ai" | Out-Null
# 兜底单包（cordis/schemastery/react/zod 等，Node 从 file:// 插件 realpath 向上找 plugins/node_modules 命中）
foreach ($pkg in 'cordis','schemastery','react','react-dom','zod','clsx','immer','yaml','js-yaml','commander') {
  if (Test-Path "$dsh\profiles\node_modules\$pkg") { New-Item -ItemType Junction -Path "$dsh\plugins\node_modules\$pkg" -Target "$dsh\profiles\node_modules\$pkg" | Out-Null }
}
```

**③ cc-tui profile junction**：

```powershell
New-Item -ItemType Junction -Path "$dsh\profiles\node_modules\@deepseek-ai\dsh-cc-tui" -Target "$dsh\plugins\dsh-cc-tui" | Out-Null
```

> ⚠️ 特殊 junction 指向 **checkout 内**（非 plugins/），需按新机器 checkout 实际路径重建：
> - `profiles/web/node_modules/@deepseek-ai/dsh-client-ui-workflow` → `<checkout>\packages\client\ui-workflow`
> - 根级 `cordis`、`node-pty`、`ws` → `<checkout>\vendor\cordis` / `<checkout>\node_modules\.pnpm\...`

### 4.3 安装主程序并启动

```powershell
# 方式 A：dev 模式（本机当前用法）
cd <checkout>
Start-Process node -ArgumentList "--import","./node_modules/tsx/dist/esm/index.mjs","./apps/cli/src/bin.ts","web" -WorkingDirectory <checkout> -RedirectStandardOutput "$dsh\web.log" -RedirectStandardError "$dsh\web.err.log" -WindowStyle Hidden

# 方式 B：已构建产物
node C:\Users\<USER>\.dsh\profiles\node_modules\@deepseek-ai\dsh\lib\bin.js --profile web
```

浏览器打开 `http://127.0.0.1:3080`。cc-tui 用 `node .../bin.ts --profile cc-tui`（需 TTY）。

---

## 5. 验证清单

```powershell
# ① 端口
netstat -ano | Select-String ":3080"          # LISTENING

# ② 插件层叠（含第五批：bash/drag-and-drop/skins/client-ui-plan-execute/plan-execute/tool-checkpoint/tool-rewind/session-cluster）
node C:\Users\<USER>\.dsh\profiles\node_modules\@deepseek-ai\dsh\lib\bin.js --profile web --dump-config | Select-String "id:"

# ③ 无加载错误
Get-Content $dsh\web.log -Tail 50             # 无 ERROR
Get-Content $dsh\web.err.log -Tail 10         # 空

# ④ client bundle 可达（抽查）
Invoke-WebRequest -UseBasicParsing http://127.0.0.1:3080 | Select-Object StatusCode

# ⑤ skills 已发现（8 个）
Get-ChildItem $dsh\skills | Select-Object Name   # 应为 8 个目录
```

---

## 6. 已知坑

1. **改插件后必须重启 dsh web**：client bundle / server lib 有内存缓存；`cordis.patch.yml` 由 HMR 热应用，但 `plugins/` 里代码要重启才生效。
2. **插件 `name` 必须写显式文件路径**：目录名会解析成 `<dir>/index.json` 失败。
3. **junction 名称必须与 `cordis.patch.yml` 的 `name` 一一对应**：`@dsh-external/xxx` 需挂 scoped junction；裸名（如 `dsh-web-archive`）挂根级 junction；server 插件走 `file:///` 绝对路径不需要 junction；**`src` 直出插件（tool-checkpoint/tool-rewind/session-cluster）必须依赖 §4.2 ② 的全局 junction**。
4. **`.env` 含密钥不打包**：恢复后手动创建。
5. **不要 `git add -A`**：仓库很大，按需 add。
6. **基线兼容性**：visualize（BUNDLED_SKILL_RANK 缺失）、official-plugins-port（schema 旧格式）、live-stats（类型不符）、subagent-tree（tsconfig 布局依赖）与本 0808 基线不兼容，未挂载——升级主程序基线后需重试。

---

_打包由本机生成（2026-08-10）。WSL 版迁移手册见 `docs/dsh-config-migration.md`。_
