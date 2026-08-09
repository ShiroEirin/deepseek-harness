# DSH 插件与配置打包说明（Windows 部署）

> **场景**：把本机（Windows，`C:\Users\ShiroEirin\.dsh`）已调好的 DSH（DeepSeek Harness）配置、插件打包，用于备份或在另一台 Windows 机器上恢复。
> **生成时间**：2026-08-09。源：`C:\Users\ShiroEirin\.dsh`（cordis 4.0.0-rc.7，web profile，34 个插件仓库）。

---

## 0. 三句话结论

1. **主程序不用打包**：`git clone` 仓库后 `scripts/install-windows.ps1` 或 tsx dev 模式启动即可（见 §4）。
2. **必须迁移的是 `.dsh` 下的配置与插件**：`cordis.patch.yml`（核心）、`plugins/`（34 个插件本体）、`profiles/web/`（4 个配置文件）、`settings.yaml`。
3. **恢复后必须重建 junction**（打包不携带 junction 目标）：client 插件全部走 `profiles/web/node_modules` 下的 junction，不重建则插件加载失败（见 §3.2）。

---

## 1. 包目录结构

```
dsh-pack-20260809/
├── README.md                 ← 本文档
├── cordis.patch.yml          ← ★核心：home 级插件清单（17+ 条 insert 声明）
├── settings.yaml             ← UI 设置（直接放 ~/.dsh/）
├── plugins/                  ← 34 个插件本体（约 100M，已剔除 node_modules/.git）
└── profiles/web/             ← web profile 配置（cordis.patch.yml + cordis.yml + package.json + pnpm-workspace.yaml，不含 node_modules）
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

## 2. 恢复前置条件

- Windows 10/11 + Node.js 22.x（fnm/nvm 均可）
- pnpm（`corepack enable` 或独立安装）
- DSH 仓库 checkout（`fix/webui-experience-20260806` 分支）

---

## 3. 恢复步骤（agent 逐条执行）

### 3.1 放置配置与插件

```powershell
# 假设新机器用户为 <USER>
$dsh = "C:\Users\<USER>\.dsh"
New-Item -ItemType Directory -Force -Path "$dsh" | Out-Null
Copy-Item cordis.patch.yml settings.yaml $dsh\
Copy-Item plugins $dsh\ -Recurse
New-Item -ItemType Directory -Force -Path "$dsh\profiles\web" | Out-Null
Copy-Item profiles\web\* $dsh\profiles\web\ -Recurse
```

> ⚠️ `cordis.patch.yml` 里 server 插件是 `file:///C:/Users/ShiroEirin/.dsh/plugins/...` 绝对路径，新机器用户名不是 `ShiroEirin` 时**必须全局替换**：
> `(Get-Content $dsh\cordis.patch.yml -Raw).Replace('C:/Users/ShiroEirin', 'C:/Users/<USER>') | Set-Content $dsh\cordis.patch.yml`

### 3.2 重建 junction（★ 必做，打包不携带）

以下 junction 全部指向 `plugins/` 插件本体，恢复后重建（`New-Item -ItemType Junction`）：

| 挂载点 | 目标 |
| --- | --- |
| `profiles\web\node_modules\@dsh-external\chat-width` | `plugins\chat-width` |
| `...\@dsh-external\dsh-input-history` | `plugins\dsh-input-history` |
| `...\@dsh-external\dsh-message-edit` | `plugins\dsh-message-edit` |
| `...\@dsh-external\dsh-sidechain` | `plugins\dsh-sidechain` |
| `...\@dsh-external\dsh-skill-stats` | `plugins\dsh-skill-stats` |
| `...\@dsh-external\dsh-skills-manager` | `plugins\dsh-skills-manager` |
| `...\@dsh-external\dsh-stickers` | `plugins\dsh-stickers` |
| `...\@dsh-external\dsh-ui-progress` | `plugins\dsh-ui-progress` |
| `...\@dsh-external\dsh-ui-whale` | `plugins\dsh-ui-whale` |
| `...\@dsh-external\dsh-web-terminal` | `plugins\dsh-web-terminal` |
| `...\@dsh-external\dsh-web-ui-notify` | `plugins\dsh-web-ui-notify` |
| `...\@dsh-community\dsh-paste-input` | `plugins\dsh-paste-input` |
| `...\@dsh-community\dsh-multimedia-webui-input` | `plugins\dsh-multimedia-webui-input` |
| `profiles\web\node_modules\dsh-activity-plugin` | `plugins\dsh-activity-plugin` |
| `profiles\web\node_modules\dsh-memory-evolve` | `plugins\dsh-memory-evolve` |
| `profiles\web\node_modules\dsh-web-archive` | `plugins\dsh-web-archive` |

批量重建脚本：

```powershell
$nm = "$dsh\profiles\web\node_modules"
New-Item -ItemType Directory -Force -Path "$nm\@dsh-external","$nm\@dsh-community" | Out-Null
$ext = 'chat-width','dsh-input-history','dsh-message-edit','dsh-sidechain','dsh-skill-stats','dsh-skills-manager','dsh-stickers','dsh-ui-progress','dsh-ui-whale','dsh-web-terminal','dsh-web-ui-notify'
foreach ($p in $ext) { New-Item -ItemType Junction -Path "$nm\@dsh-external\$p" -Target "$dsh\plugins\$p" | Out-Null }
$com = @{ 'dsh-paste-input' = 'dsh-paste-input'; 'dsh-multimedia-webui-input' = 'dsh-multimedia-webui-input' }
foreach ($k in $com.Keys) { New-Item -ItemType Junction -Path "$nm\@dsh-community\$k" -Target "$dsh\plugins\$($com[$k])" | Out-Null }
foreach ($p in 'dsh-activity-plugin','dsh-memory-evolve','dsh-web-archive') { New-Item -ItemType Junction -Path "$nm\$p" -Target "$dsh\plugins\$p" | Out-Null }
```

> ⚠️ 两个特殊 junction 指向 **checkout 内**（非 plugins/），需按新机器 checkout 实际路径重建：
> - `@deepseek-ai\dsh-client-ui-workflow` → `<checkout>\packages\client\ui-workflow`
> - 根级 `cordis` → `<checkout>\vendor\cordis`；`node-pty`、`ws` → `<checkout>\node_modules\.pnpm\...`
>
> 若新机器用 `dsh plugin add` / 官方安装流程，这些由安装器生成，可跳过手动重建。

### 3.3 安装主程序并启动

```powershell
# 方式 A：dev 模式（本机当前用法）
cd <checkout>
Start-Process node -ArgumentList "--import","./node_modules/tsx/dist/esm/index.mjs","./apps/cli/src/bin.ts","web" -WorkingDirectory <checkout> -RedirectStandardOutput "$dsh\web.log" -RedirectStandardError "$dsh\web.err.log" -WindowStyle Hidden

# 方式 B：已构建产物
node C:\Users\<USER>\.dsh\profiles\node_modules\@deepseek-ai\dsh\lib\bin.js --profile web
```

浏览器打开 `http://127.0.0.1:3080`。

---

## 4. 验证清单

```powershell
# ① 端口
netstat -ano | Select-String ":3080"          # LISTENING

# ② 插件层叠（17+ 条声明全在）
node C:\Users\<USER>\.dsh\profiles\node_modules\@deepseek-ai\dsh\lib\bin.js --profile web --dump-config | Select-String "id:"

# ③ 无加载错误
Get-Content $dsh\web.log -Tail 50             # 无 ERROR
Get-Content $dsh\web.err.log -Tail 10         # 空

# ④ client bundle 可达（抽查）
Invoke-WebRequest -UseBasicParsing http://127.0.0.1:3080 | Select-Object StatusCode
```

---

## 5. 已知坑

1. **改插件后必须重启 dsh web**：client bundle / server lib 有内存缓存；`cordis.patch.yml` 由 HMR 热应用，但 `plugins/` 里代码要重启才生效。
2. **插件 `name` 必须写显式文件路径**：目录名会解析成 `<dir>/index.json` 失败。
3. **junction 名称必须与 `cordis.patch.yml` 的 `name` 一一对应**：`@dsh-external/xxx` 需挂 scoped junction；裸名（如 `dsh-web-archive`）挂根级 junction；server 插件走 `file:///` 绝对路径不需要 junction。
4. **`.env` 含密钥不打包**：恢复后手动创建。
5. **不要 `git add -A`**：仓库很大，按需 add。

---

_打包由本机生成（2026-08-09）。WSL 版迁移手册见 `docs/dsh-config-migration.md`。_
