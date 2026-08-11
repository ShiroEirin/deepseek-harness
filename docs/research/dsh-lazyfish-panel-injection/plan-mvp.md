---
title: "DSH WebUI 音乐播放器插件 — MVP 落地方案（审查修正版）"
date: 2026-08-10
tags: [dsh, plugin, webui, music, player, plan, mvp]
status: approved-for-build
前身: README.md（注入模式调研决策笔记，已 commit bf67759e）
审查依据: ① checkup 对抗式审查（第 1 轮，修正 sidebar 槽被占/逆向高估）；② review 收敛审查（第 2 轮，修正 kind/trust-fence/inject/验证脚本/行号/布局消费规则）；③ 反例 dsh-better-sidebar 源码级逐条核实
---

# DSH WebUI 音乐播放器插件 — MVP 落地方案（审查修正版）

> 本方案是上一次调研决策笔记（`README.md`，已纳入 git）的**落地修正版**。审查发现并修正了两处会对构建造成硬失败的错误假设：① `sidebar` 槽**不是空置的**；② "复用本地逆向管道"被高估。本版按真实约束重写，每个关键决策都标注验证来源。

## 0. 审查修正要点（先读）

| # | 原方案假设 | 审查结论 | 本版修正 |
|---|---|---|---|
| 0.1 | `sidebar` 槽空置、可注入面板 | **证伪**：`ui-sidebar` 已 `register({name:'sidebar'})`，`kind:'single'`，重复注册在浏览器 boot 抛异常（`ui-slots:724-726`） | 弃用 slots 注入，改 **`document.body` 自挂 + `--dsh-sidebar-width` CSS 变量推挤**（照 dsh-better-sidebar） |
| 0.2 | "复用本地 NeteaseMusic-Plugin 逆向管道" | **高估**：该项目只是 require 公开 npm 库 `NeteaseCloudMusicApi`，本身无逆向代码，且该库原版已停维护 | 诚实对待：host 端 **Node 直接集成** `NeteaseCloudMusicApi`（选仍维护的 fork），调用它的 action 协议；不再说"复用本地插件" |
| 0.3 | 布局注入走 slots 生态 | dsh-better-sidebar 反例证明 registry + document.body 自挂是生产可用形态 | 采纳反例形态 |
| 0.4 | 验证用 `dump-config\|grep` | registry 插件**不进** dump-config（skill gotcha），会假阴性 | 改用 **`dsh registry list` + web boot log 清洁 + headless-Chrome smoke**（见 §6） |
| 0.5 | "DSH preference API" | DSH 无面向第三方插件的 preference 写 API，各 feature 自用 localStorage | 自建 **`localStorage`**（照 `dsh-sidebar:v1` 模式） |
| 0.6 | 播放失败无降级 | song_url 空/VIP/403 分支无处理 | Error Boundary + 诊断条 + 换歌引导（照反例 `SidebarBoundary` + `fail()`） |
| 0.7 | `/api/music/*` 无鉴权自证 | serveStatic 无 policy，httpServer 无内置鉴权，但反例用 `isTrustedApiRequest`（Host-loopback/trusted + sec-fetch-site + origin）做 fence，明言「非 auth 层」 | 照反例 **`isTrustedApiRequest` Host-header fence**（需 `inject:['loader']` 读 `trustedHostsOf`），不自造 token |

## 1. 形态选型（registry + client 半边）

参照：`dsh-better-sidebar`（`~/.dsh/plugins/dsh-better-sidebar/`，registry 完整反例）。

- 插件 id：`publisher/name`（如 `dsh-external/dsh-music-player`），目录名 = name。
- 脚手架：`dsh registry create <publisher>/<name>`，生成 `dsh.plugin.json` + `index.mjs` + `README.md`（skill 脚手架入口；实际反例是 tsdown 构建型，见 §6）。
- 文件树（照反例，host 与 client 指向 `lib/` 编译产物）：
  ```
  dsh-music-player/
    dsh.plugin.json          # id/version/main/engines.dsh/contributes + client.main
    src/                     # TS 源码（host half index.ts + client half client.tsx）
      index.ts
      client.tsx
      index.css
    lib/                     # 构建产物（main / client.main 指向这里）
      index.js
      client.js
    tsconfig.json|tsdown.config.ts|package.json|README.md
  ```
- `dsh.plugin.json` 结构（照反例 `dsh.plugin.json`，`main`/`client.main` 指向 `lib/` 产物）：
  ```json
  {
    "id": "dsh-external/dsh-music-player",
    "version": "0.1.0",
    "main": "./lib/index.js",
    "description": "...",
    "engines": { "dsh": ">=0.0.1" },
    "contributes": { "tools": ["music_search","music_play","music_queue"], "skills": [] },
    "client": { "main": "./lib/client.js" }
  }
  ```
- **contributes.tools 仅是 registry 展示清单，不是生效通道**：工具真正生效只来自 §2 的 `ctx.tools.register`。两份名单必须逐字一致（enable 校验：声明未注册或注册未声明都会失败回滚），后续加工具需同步两处。

## 2. host 半边（Node）

> 反例 source of truth：`dsh-better-sidebar/src/index.ts` —— `inject:['httpServer','sessions','loader']`（:41）、`ctx.httpServer.register({ kind:'prefix', path, handler })`（:320/352）、可选 `ctx.inject(['settings'],cb)`（:300）、handler 先 `fence(req)` 再 `req.method` 校验（:324/328）。
> 我方 `inject` 用 `['httpServer','tools','loader']`：`tools` 注册 Agent 工具；`loader` 读部署真实 trustedHosts 供 fence（照反例 `trustedHostsOf(ctx)`）。`settings` 不作为顶层硬依赖——如需要 NETEASE_COOKIE 配置，用 `ctx.inject(['settings'], cb)` 可选子注入，避免未挂 settings 的 composition 加载失败。

```ts
import { defineTool } from '@deepseek-ai/dsh-tools'
import { isTrustedApiRequest } from './trust-fence.ts' // 照反例 trust-fence.ts
// 依赖：NeteaseCloudMusicApi（选仍维护的 fork）

export const name = 'dsh-music-player'
export const inject = ['httpServer', 'tools', 'loader']

export function apply(ctx: Context) {
  // 部署的真实可信主机（来自 loader 的 connection 行，供 fence）
  const trustedHosts = trustedHostsOf(ctx)                        // 照反例 :63
  const fence = (req: IncomingMessage) => isTrustedApiRequest(req, trustedHosts)

  // 3) 音乐工具（Agent 联动，运行时唯一生效通道）
  ctx.effect(() => ctx.tools.register(defineTool({
    name: 'music_search', description: '搜网易云歌曲',
    parameters: { type: 'object', properties: { keyword: { type: 'string' }, type: { type: 'integer' }, limit: { type: 'integer' } }, required: ['keyword'] },
    output: { schema: { type: 'string' }, render: (_a, v) => [{ type: 'text', text: v }] },
    execute: async ({ keyword, type = 1, limit = 30 }) => JSON.stringify(await api.cloudsearch({ keywords: keyword, type, limit })),
  })))
  // music_play / music_queue 同理 ...

  // 1) 数据源路由（同源 fetch 代理，供 client 面板）
  ctx.effect(() => ctx.httpServer.register({
    kind: 'prefix',
    path: '/api/music/v1',
    handler: async (req, res) => {
      if (!fence(req)) { res.statusCode = 403; res.end('forbidden'); return }   // 照反例 :324
      if (req.method !== 'POST') { res.statusCode = 405; res.end('method not allowed'); return } // 照反例 :328
      const { action, ...args } = await readJsonBody(req)
      const result = await route(action, args)   // search/song_url/lyric/queue
      res.statusCode = 200
      res.end(JSON.stringify(result))
    },
  }))
}
```

- `song_url` 支持 level：standard/higher/exhigh/lossless。
- `ctx.effect()` 返回 disposer，卸载时注销路由/工具，避免 disable 后残留。

## 3. client 半边（浏览器面板）

> 反例 source of truth：`dsh-better-sidebar/src/client/index.tsx` + `state.ts` + `layout.css`。(反例 client `inject:['slots','sessions','connection']` 是因为它注册 `settings.section` 槽；**我方不注册任何 slot**，故不声明 `slots`。)

- `client.js`（build 产物）：`window.__ModuleLoader__.load({ id: 'dsh-external/dsh-music-player', factory })`，`factory(require)` 返回 `{ name, inject, apply }`。
- `inject = []`（纯自挂全局面板不需要宿主服务种子；若要做会话感知再加 `'sessions'`，按需声明，不为未用服务埋伏笔）。
- `apply(ctx)`：
  1. `ctx.effect(...)` → `document.createElement('div')` → `setAttribute('data-dsh-music-player','')` → `document.body.appendChild(host)` → `createRoot(host).render(<ErrorBoundary><Player/></ErrorBoundary>)` → 卸载时 `root.unmount(); host.remove()`（照反例 index.tsx:89-120）。
  2. 布局推挤：**成对使用**——CSS `#root { margin-right: var(--dsh-player-width, 0px) }`（消费方）+ JS `documentElement.style.setProperty('--dsh-player-width', String(width))`（提供方），缺一不生效（照反例 layout.css:15-16）。或选固定右下角浮层（不推挤，更简单）。
  3. 数据：同源 `POST fetch('/api/music/v1', ...)` 访问 host 路由（与 host 的 method 校验对齐）。
  4. ErrorBoundary + `fail()` 诊断条：任何渲染/请求失败显示左下角红条，不静默（照反例 index.tsx:75-87）。
- 面板内容：
  - `<audio>` 播放器（无 CSP，远程音源放行）。
  - WebAudio `AnalyserNode.getByteFrequencyData()` → canvas 律动条（rAF 驱动）。
  - LRC 解析（`[mm:ss.xx]`）→ `requestAnimationFrame` 高亮行滚动。
  - 歌单/搜索/播放/队列按钮。
- 持久化：`localStorage`（key `dsh-music-player:v1:<songId>` 记录播放进度/音量/收藏/队列）。

## 4. Agent 联动

3 个 `defineTool`：
| 工具 | 作用 | 关键参数 |
|---|---|---|
| `music_search` | 按关键词搜网易云 | `keyword`, `type`(默认1单曲), `limit` |
| `music_play` | 播放指定曲 | `id`, `level` |
| `music_queue` | 加队列/下一首/看队列 | `action`, `id?` |

agent 通过对 model 说「来点轻快的歌」→ 调 `music_search` → `music_play`。UI 侧可选 `inject:['slash']` 加 `/play` 快捷命令。

## 5. 安全边界（MVP 必须落实）

- `/api/music/v1` 无内置鉴权 → **照反例用 `isTrustedApiRequest(req, trustedHosts)` Host-header fence**（fence.ts:63-73）：Host 为 loopback 或 `trustedHostsOf(ctx)`（loader 的 connection 行）之一，且 `sec-fetch-site` 非 `cross-site`、origin 与 Host 同源。**这是 DSH 金标准，不是 auth 层**——本插件也用它，不自造 session token。
- `trustedHostsOf(ctx)` 从 `ctx.loader` 读部署真实列表（反例 src/index.ts:63）；因此 host `inject` 必须含 `loader`，否则 fence 无可用名单。
- Cookie（`NETEASE_COOKIE`）经可选 settings 子注入传入，仅存 host 端，不下发到浏览器。
- 不要把可播放 URL 无保护地暴露给非站点进程（fence 兜底，外加 Cookie 不出 host）。

## 6. 构建与验证（registry 口径）

> 注意与 dsh-plugin-dev 的 bundle 验证流程区分：registry 插件**不**进 dump-config。
> 反例为 tsdown 构建型 registry 插件（`src/` TS → `lib/` 产物），验证落在「构建产物 + web 装配」两层。

- 构建：按反例 `tsconfig.json` + `tsdown.config.ts` 从 `src/` 产出 `lib/`（`main`/`client.main` 指向 `lib/` 产物）。客户端 bundle 的 `__ModuleLoader__.load` id 必须 = 插件 id。
- 安装/启用：`dsh registry install ./dsh-music-player` → `dsh registry enable dsh-external/dsh-music-player` → `dsh registry list`。
- Node half 挂载验证：**web 侧**确认——`dsh registry list` 显示 enabled + 重启 web 后 boot log 无 `plugin tree failed to load`。不依赖 `dsh run`（它 boots headless profile，无 HTTP/browser 层，registry Node half 在 headless 是否装配未证实）。
- client 半边挂载验证：headless Chrome `--headless=new --virtual-time-budget=12000 --dump-dom <dsh web url>`，断言 `data-dsh-music-player` marker 存在且无 "Failed to load plugins"。反例对应的浏览器 smoke 在其 `tests/smoke.spec.ts`；`verify-client-smoke.mjs` 属 dsh-pet 项目（plugin-registry-create skill 引用的），不是本反例——实现时参考 dsh-pet 该脚本但标注来源。
- host 工具验证：web 装配后，向 agent 下「用 music_search 搜 Star Sky」指令，确认返回结果；或直接 `curl -X POST`（带 Host fence 允许的来源）打 `/api/music/v1` 验证路由。

## 7. 依赖与风险

| 风险 | 等级 | 缓解 |
|---|---|---|
| `NeteaseCloudMusicApi` 原版停维护 | 中 | 用仍维护的 fork；调用动作收敛到 search/song_url/lyric 三个稳定借口 |
| 逆向接口风控/403 | 中 | 播放 URL 为空的降级：提示换歌、切 level、必要时提示登录 |
| 版权/VIP 曲目无法播放 | 中 | 面板对空 URL 优雅降级，引导搜可听版本 |
| `#root margin-right` 推挤与反例 rule 竞争 | 低 | 若同时启用 dsh-better-sidebar 且都用 `#root { margin-right }`，两规则按 CSS 层叠互相覆盖（与变量名无关）。缓解：我方优先用右下角浮层（不推挤），或在自身 CSS 用更高优先级/`!important` 明确声明 |
| registry/bundle 双通道互斥 | 中 | 只走 registry，不经 Loader tree（反例即此） |

## 8. 未纳入 MVP（后续）

- QQ 音乐兜底源：等网易云链路验证稳定后再讨论，避免逆向双源维护成本。
- 完整歌单管理/收藏/封面/AQ 视觉级律动。
- 多语歌词切换。
- 全局快捷键。

## 9. 证据索引
（均为**源码**路径；反例 `src/` 与 `lib/` 是同文件不同形态，以下用 `src/` 源文件行号）
- 反例 manifest：`~/.dsh/plugins/dsh-better-sidebar/dsh.plugin.json`（`main:./lib/index.js`、`client.main:./lib/client-registry.js`、无 client.inject）
- 反例 host half（src）：`~/.dsh/plugins/dsh-better-sidebar/src/index.ts`（`inject:['httpServer','sessions','loader']` @41；`ctx.httpServer.register({kind:'prefix', ...})` @320/352；`registerUpgrade` @402；可选 `ctx.inject(['settings'],cb)` @300；handler `fence()`→`method!=='POST'`→405 @324-329）
- 反例 fence：`~/.dsh/plugins/dsh-better-sidebar/src/trust-fence.ts`（`isTrustedApiRequest` @63-73：loopback/trustedHosts + sec-fetch-site + origin；明言非 auth 层）；`trustedHostsOf(ctx)` 从 loader connection 行读取 @index.ts:63
- 反例 client half（src）：`~/.dsh/plugins/dsh-better-sidebar/src/client/index.tsx`（`:89-120` 自挂 + ErrorBoundary + `fail()` 诊断条）；`src/client/state.ts`（`:4` localStorage `dsh-sidebar:v1`）；`src/client/Sidebar.tsx:199`（`--dsh-sidebar-width`）
- 反例布局（消费方）：`~/.dsh/plugins/dsh-better-sidebar/src/client/layout.css:15-16`（`#root { margin-right: var(--dsh-sidebar-width, 0px) }`）
- registry 机制：`plugin-registry-create` skill（Stage 3/5/6）
- sidebar 槽冲突证据：`packages/client/ui-sidebar/src/client/index.ts:38`、`packages/client/ui-layout/src/client/index.ts:39`、`packages/client/ui-slots/src/index.ts:724-726`
- 浏览器 smoke 参考：dsh-pet 项目 `scripts/verify-client-smoke.mjs`（plugin-registry-create Stage 6 引用；非本反例）；反例自身 smoke 在 `tests/smoke.spec.ts`
