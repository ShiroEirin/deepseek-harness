# DSH 配置迁移包使用手册

> **场景**：把当前机器（WSL2 Ubuntu 26.04，用户名 `aikun`）上已调好的 DSH（DeepSeek Harness）配置、插件、数据同步到**另一台电脑**。
> **本文档是给「目标机器上的 agent / 用户」看的操作手册**，逐条告诉 agent 迁移包里的配置**要改哪些地方、怎么改、怎么验证**。
> 生成时间：2026-08-07。源机器快照：`~/.dsh/`（10 插件已脱离 marisa，直接由 `cordis.patch.yml` 加载）。

---

## 0. 三句话结论

1. **主程序不用迁移**：新机器 `git clone` + `scripts/install.sh` 就有（见 §4）。
2. **必须迁移的是 `~/.dsh/` 下的配置与插件**：`cordis.patch.yml`（核心）、`plugins/`（10 个插件本体）、`profiles/web/`、`settings.yaml`、`.userid`、`storages/workspace.json`。
3. **迁移后必须改两处**：① `cordis.patch.yml` 里 6 条 `/home/aikun/...` 绝对路径 → 新用户名；② 重建 5 条 `@dsh-external` 软链。不改则插件全部加载失败。

---

## 1. 迁移包目录结构

```
dsh-config-migration/
├── README.md                 ← 本文档
├── cordis.patch.yml          ← ★核心配置：persona + 10 插件清单（必须改路径，见 §3.1）
├── config.yaml               ← persona 覆盖层（与 cordis.patch.yml 的 persona 相同，可留可删）
├── settings.yaml             ← UI 设置（直接放 ~/.dsh/ 即可）
├── .userid                   ← 用户身份 UUID（直接放 ~/.dsh/）
├── plugins/                  ← 10 个插件本体（约 2.5M），完整复制
│   ├── chat-width/           ├── dsh-message-edit/   ├── dsh-session-search/
│   ├── dsh-skills-manager/   ├── dsh-tool-calculator/├── dsh-tool-encoding/
│   ├── dsh-tool-json/        ├── dsh-tool-time/      ├── dsh-ui-progress/
│   └── dsh-web-ui-notify/
├── profiles/web/             ← 前端 profile（cordis.yml + package.json，不含 node_modules）
└── storages/workspace.json   ← workspace 注册表（★需按新机器路径适配，见 §3.3）
```

### 1.1 不打包清单（新机器重新生成/配置，别拷！）

| 不打包                          | 原因                                                                            |
| ------------------------------- | ------------------------------------------------------------------------------- |
| `.env`                          | **含 API 密钥**（如 `GEMINI_API_KEY`），新机器重新填写（见 §3.4）               |
| `source/`                       | 主程序源码，`git clone` + `install.sh` 安装（见 §4）                            |
| `marisa/`、`dshx.disabled/`     | dshx 插件管理器已停用（2026-08-07 关闭）                                        |
| `sessions/`                     | 74M 历史会话；**可选**——想保留历史对话就整体拷到 `~/.dsh/sessions/`，不要就跳过 |
| `*.bak-*`（config/cordis 备份） | 历史备份，新机器不需要                                                          |
| `web.log`                       | 运行日志                                                                        |

---

## 2. 新机器前置条件（按序执行）

```bash
# ① 系统包
sudo apt-get update && sudo apt-get install -y build-essential python3 xdg-utils
#   - build-essential：node-pty 编译必需（否则 pnpm install 报错）
#   - python3：构建脚本依赖
#   - xdg-utils：settings 面板「打开配置文件」按钮依赖（WSL 下桥接 explorer.exe）

# ② Node 22.x（用 nvm，避免 Ubuntu 源 node 的 unrun 坑）
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
export NVM_DIR="$HOME/.nvm"; . "$NVM_DIR/nvm.sh"
nvm install 22 && nvm alias default 22

# ③ pnpm（项目是 pnpm workspace）
corepack enable

# ④ 确认
node -v && pnpm -v
```

---

## 3. 迁移配置（核心操作，agent 逐条执行）

### 3.1 改 `cordis.patch.yml` 的绝对路径（★ 必改）

`cordis.patch.yml` 是 DSH 的**个人全局覆盖层**（`$DSH_HOME/cordis.patch.yml`），由 dsh web 的 HMR 监听。里面 6 条 server 插件是**硬编码绝对路径**：

```yaml
- insert:
    # client 插件（5 个，走 @dsh-external 包名，见 §3.2）
    - id: dsh-skills-manager
      name: "@dsh-external/dsh-skills-manager"
    - id: dsh-web-ui-notify
      name: "@dsh-external/dsh-web-ui-notify"
    - id: chat-width
      name: "@dsh-external/chat-width"
    - id: dsh-ui-progress
      name: "@dsh-external/dsh-ui-progress"
    # server 插件（6 条，绝对路径 → ★必须改成新用户名）
    - id: dsh-message-edit
      name: /home/aikun/.dsh/plugins/dsh-message-edit/index.mjs
    - id: dsh-session-search
      name: /home/aikun/.dsh/plugins/dsh-session-search/lib/index.js
    - id: dsh-tool-calculator
      name: /home/aikun/.dsh/plugins/dsh-tool-calculator/lib/index.js
    - id: dsh-tool-json
      name: /home/aikun/.dsh/plugins/dsh-tool-json/lib/index.js
    - id: dsh-tool-time
      name: /home/aikun/.dsh/plugins/dsh-tool-time/lib/index.js
    - id: dsh-tool-encoding
      name: /home/aikun/.dsh/plugins/dsh-tool-encoding/lib/index.js
```

**agent 执行**（假设新机器用户名为 `NEWUSER`，替换成实际值）：

```bash
# 一次性替换全部 /home/aikun → /home/NEWUSER
sed -i 's|/home/aikun|/home/NEWUSER|g' ~/.dsh/cordis.patch.yml
grep -n "aikun" ~/.dsh/cordis.patch.yml   # 必须 0 命中！
```

> ⚠️ **注意**：不要偷懒改成 `~/` 或 `$HOME/`——loader 对插件 `name` 不做 shell 展开，必须写**显式文件路径**（`lib/index.js` 或 `index.mjs`，不能只写目录名，否则重启时解析成 `<dir>/index.json` 失败——2026-08-07 实测踩坑）。

### 3.2 重建 `@dsh-external` 软链（★ 必做）

5 个 client 插件通过 `profiles/web/node_modules/@dsh-external/<name>` 软链指向插件本体。**tar 包不带软链**（软链目标带绝对路径，拷过去必失效），新机器重建：

```bash
mkdir -p ~/.dsh/profiles/web/node_modules/@dsh-external
for p in chat-width dsh-message-edit dsh-skills-manager dsh-ui-progress dsh-web-ui-notify; do
  ln -sfn ~/.dsh/plugins/$p ~/.dsh/profiles/web/node_modules/@dsh-external/$p
done
ls -la ~/.dsh/profiles/web/node_modules/@dsh-external/   # 5 条软链，目标都指向 ~/.dsh/plugins/
```

> 这 5 个名字必须与 `cordis.patch.yml` 中 `name: "@dsh-external/xxx"` 一一对应（dsh-message-edit 同时出现在 client 软链和 server 绝对路径，双形态，两处都要）。

### 3.3 适配 `storages/workspace.json`（★ 按需改）

源机器注册了 3 个 workspace，全部是 Windows 侧路径：

```json
{ "workspaceIds": ["6d46164f-...", "6011383d-...", "d6c10496-..."], ... }
```

- 若新机器没有对应的 `/mnt/d/github/...` 目录 → **删掉对应条目**（否则 skills 管理器的 `cwd` fallback 会指向失效目录，重演 vcp-smoke 事故）。
- 若新机器目录路径不同 → 改成实际路径。
- agent 修改后重启 dsh web 生效。

### 3.4 填写 `.env`（API 密钥，★ 必做）

迁移包**故意不含** `.env`。新机器手动创建：

```bash
cat > ~/.dsh/.env << 'EOF'
# 按源机器 ~/.dsh/.env 的内容重新填（各 provider 的 API Key）
# 例：GEMINI_API_KEY=xxx  （vcp-memory embedding 用）
# 例：其他 DSH 需要读取的密钥
EOF
chmod 600 ~/.dsh/.env
```

> 找不到源 `.env`？在源机器执行 `cat ~/.dsh/.env` 抄一份（注意别外泄）。

### 3.5 插件本体内的残留路径（检查过，运行时无害，可选处理）

迁移包内的插件本体是**已构建产物**，grep 会发现少量 `aikun` 残留，但都**不影响运行**：

| 位置                                                          | 性质                                                      | 影响                                                                            |
| ------------------------------------------------------------- | --------------------------------------------------------- | ------------------------------------------------------------------------------- |
| `chat-width/lib/client.js`、`dsh-web-ui-notify/lib/client.js` | esbuild 构建注释 `//#region \0dsh-css:/home/aikun/...`    | 运行时注释，无影响                                                              |
| `dsh-skills-manager/tsconfig.json`                            | 开发期 TS 配置，指向 `~/.dsh/source/current/...` 类型定义 | 运行时用 `lib/index.js`（已构建），无影响；仅在新机器**重新构建插件**时才需要改 |

**结论：不处理也能跑。** 若要在新机器上重新编译插件，再按新路径改 tsconfig 即可。

### 3.6 放置其余文件

```bash
cp -r settings.yaml .userid ~/.dsh/
mkdir -p ~/.dsh/profiles/web ~/.dsh/storages
cp profiles/web/cordis.yml profiles/web/package.json ~/.dsh/profiles/web/
cp storages/workspace.json ~/.dsh/storages/
cp -r plugins/ ~/.dsh/   # 10 个插件本体
cp cordis.patch.yml ~/.dsh/   # 注意：先做 §3.1 的 sed 替换再拷，或拷完再 sed
```

> `config.yaml` 可拷可不拷：它的 persona 与 `cordis.patch.yml` 相同（源机器已双写），留着只是冗余。

---

## 4. 安装主程序（dsh web）

```bash
# ① clone 仓库（用安装脚本支持的分支/快照）
git clone <DSH_REPO> deepseek-harness
cd deepseek-harness

# ② 安装（install.sh 会创建 staging、构建、把 current 符号链接指到最新构建）
DSH_REPO=<仓库地址> DSH_REF=<分支或快照> ./scripts/install.sh

# ③ 启动 web（注意：不是 `pnpm run dsh web`，package.json 没有 dsh script！）
cd ~/.dsh/source/current
./bin/dsh web        # 前台
# 或后台：
setsid nohup ./bin/dsh web > ~/.dsh/web.log 2>&1 < /dev/null &
```

**访问**：浏览器打开 `http://localhost:3080`（默认端口 3080）。

> ⚠️ 常见错误：`dsh --config xxx` / `dsh web --config xxx` **参数不存在**。覆盖配置请用 `--patch <path>`（在 profile 层之后追加覆盖，可重复）。`cordis.patch.yml` 是主配置层，一般不需要 `--patch`。

---

## 5. 验证清单（agent 逐项确认）

```bash
# ① 进程与端口
ss -tlnp | grep 3080                       # 3080 监听中

# ② 插件加载（10 个全在 = 成功）
tail -50 ~/.dsh/web.log                    # 无 ERROR
# 浏览器 F12 → window.__DSH_BOOT__ 或 console 看 boot 摘要
# 应包含：5 个 @dsh-external/xxx + 6 条 ~/.dsh/plugins/ 绝对路径（dsh-message-edit 双形态）

# ③ client bundle 可达（5 个全 200）
for p in dsh-skills-manager dsh-web-ui-notify chat-width dsh-ui-progress dsh-message-edit; do
  curl -s -o /dev/null -w "%{http_code} $p\n" "http://localhost:3080/...$p..."
done

# ④ skills 管理器 API（验证 workspace cwd fallback 正常）
curl -s "http://localhost:3080/api/skills" | head -c 200

# ⑤ persona 生效：新建会话，确认系统提示词是「YAGNI/PDCA」版本

# ⑥ settings 面板「打开配置文件」按钮：能弹出编辑器（依赖 xdg-utils）
```

---

## 6. 已知坑（agent 必读，避免重踩）

1. **改插件后必须重启 dsh web**：client bundle / server lib 有内存缓存，HMR 只热应用 `cordis.patch.yml`，改 `plugins/` 里代码要重启才生效。
2. **插件 `name` 必须写显式文件路径**：目录名会解析成 `<dir>/index.json` 失败（2026-08-07 实测）。
3. **`cordis.patch.yml` 由 dsh web 监听**：保存后事务性热应用，改完它不用重启。
4. **WSL 下 `settings.openDocument` 依赖 xdg-utils**：没装则按钮报 ENOENT；装了 xdg-open 会自动桥接 `explorer.exe` 弹 Windows 关联程序。
5. **CRLF/LF**：从 Windows 复制 yaml/js 到 WSL 注意行尾；`git add` 前确认（仓库有 lefthook lint，长行 ≤120 字符）。
6. **sudo 非交互**：`echo "密码" | sudo -S apt-get ...`，apt 卡密码提示会超时。
7. **不要 `git add -A`**：仓库很大，按需 add。

---

## 7. 回滚

- 迁移失败想还原：删 `~/.dsh` 里新增的配置，重新 `install.sh`（`current` 符号链接由 install.sh 管理，重跑安全）。
- `cordis.patch.yml` 改坏了：用 `cordis.patch.yml.bak-close-dshx-20260807T172322Z`（源机器备份，迁移包外）恢复。

---

_迁移包由源机器 `scripts/pack-dsh-migration.sh` 生成（见仓库 scripts/ 目录）。有问题找哈雷酱！_
