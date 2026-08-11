---
title: "dsh-lazyfish 面板注入模式调研（面向 DSH WebUI 常驻音乐播放器面板）"
date: 2026-08-10
tags: [dsh, plugin, webui, slots, panel, research, decision-log]
status: partial
---

# dsh-lazyfish 面板注入模式 — 调研决策笔记

## 0. 读前必读：证据边界（决定本笔记能否直接照做）

- **本体证据缺失**：本次调研 **未能读取 `dsh-lazyfish` 源码**（`~/.dsh` 家目录被沙箱拦截，`danger-full-access` 升级被拒，工作区与历史会话中均未定位到它的 `lib/client.js` / `cordis.patch.yml`）。
- 因此本笔记对 **lazyfish 本体**的任何描述要么标 `?`（推断），要么标 **未确认**。
- **已验证部分**来自对 **DSH 源码 `packages/client/*`**（当前工作区即 DSH 源码 checkout）及参照插件 `dsh-better-sidebar` 的实际读取——这部分对做播放器面板是**可移植、可直接照做**的。

> **结论价值判断**：与其等 lazyfish 源码，不如直接采用下方「已验证」的 DSH 原生路径（`sidebar` 空槽 / `document.body` 自挂 + host `/api` 桥接 + 无 CSP 媒体）。lazyfish 只用于确认「这条路有人走过」的可行性佐证，不是必需依赖。

---

## 1. 决策摘要（一句话范式）

> **布局**：DSH 无右侧常驻槽 → 用空的 `sidebar`（root/单例/跨会话常驻）槽，或参照 `dsh-better-sidebar` 用 `document.body` 自挂 + `#root{margin-right:var(--...)}` 推挤。
> **桥接**：host 注入 `['httpServer','tools',...]` → 注册 `/api` 代理第三方音乐 API → client 同源 `fetch`；Agent 用 `defineTool` 触发、`slash` 命令做 UI 快捷入口。
> **媒体**：DSH WebUI **无 CSP** → Web Audio API、`<audio>/<video>`、B 站 iframe 均不受 CSP 拦截；B 站用 iframe（防盗链），网易云等非官方音源走 host `/api` 代理。

---

## 2. 已验证事实（来自 DSH 源码，可照做）

证据源：工作区即 DSH 源码 checkout，路径均为 `packages/client/*` 与 `apps/web/*`。

### 2.1 客户端 slots 清单（无全局右侧/顶部/底部常驻插槽）

| 包 | slots 声明文件 | 命名空间 |
|---|---|---|
| `ui-layout` | `packages/client/ui-layout/src/client/index.ts:80-96` | `root` → `sidebar`(single/root)、`conversation`(single/session-maybe)、`details`(single/session) |
| `ui-sidebar` | `ui-sidebar/src/client/contract/slots.ts` | `sidebar.workspaces`、`sidebar.settings` |
| `ui-conversation` | `ui-conversation/src/client/apply.ts:181-211` | `conversation.input.left/dock/overlay`、`composer.dock`、`hero.workspace`、`session.header` 等（session 作用域） |
| `ui-settings` | `ui-settings/src/client/index.ts:99-110` | `settings.section` 等（root 作用域） |

- 机制：Cordis（`@qiwen/cordis`）的 `slots.inject(key, fn)` + `slots.register(...)`。
- **关键 gap**：DSH **没有 `topbar`/`footer`/`Drawer`/`panel`/右侧常驻栏这类全局插槽**。AppFrame（`ui-layout`）是「左 sidebar / 中央 conversation / 右 details」三列，**无第三方右侧洞**。

### 2.2 `sidebar` 槽是唯一官方、当前**空置**的常驻布局位

- 前序会话核实：已装插件里 **无一人占用 `sidebar` 槽**（`dsh-better-sidebar` 用的是 `conversation`，不是 `sidebar`）。
- 渲染路径：`renderSlot('sidebar', { collapsed, width })`（AppFrame，`ui-layout/src/client/index.ts:39/83`），owner 提供 `SidebarOwnerProps`（`collapsed` + `width`）。
- `kind: single`，同时只有一个注册者——占用前需检查现有插件是否已用。

### 2.3 参照插件 `dsh-better-sidebar` 的做法（自挂方案）

- 因无右槽可挂，它用 **`ctx.effect` + `createRoot(document.body)` 自挂到 `document.body`**（绕过 slot，物理创建 React root）。
- 布局推挤：CSS `#root { margin-right: var(--dsh-sidebar-width) }`，用 margin 挤开主布局给面板腾位。
- 位置：`lib/client.js:468458-468505`。

### 2.4 host / 桥接与浏览器侧协议

- client 插件以 bundle 形式经 `window.__ModuleLoader__.load({id, factory})` 加载；`factory(require)` 返回 `{ apply, inject }`；`inject` 声明依赖的**服务种子**。
- 服务种子包：`slots`、`sessions`、`conversation`、`workspaces`、`connection`、`slash`、`typert`、`sessionHistory` 等（完整种子表在 `packages/client/web/src/seed.ts`）。
- host 端静态服务：`packages/host/frontend-static/src/index.ts` 的 `serveStatic` 只写 `content-type` + `cache-control: no-cache`，不设安全策略。

### 2.5 CSP（确定结论）

- DSH WebUI **无任何 CSP**：`apps/web/index.html` 无 CSP `<meta>`（仅 charset/viewport/manifest/favicon/title/root div/module script）；`vite.config.ts` 无 CSP/headers 配置；全源码 grep `script-src`/`connect-src`/`frame-ancestors` 零命中。
- ⇒ **Web Audio API、`<audio>/<video>` 播放远程音源、B 站 iframe 均不受 CSP 拦截**（本地 `dsh web` 服务 127.0.0.1）。

---

## 3. 未确认 / 推断项（lazyfish 本体与桥接细节）

| 项 | 状态 | 说明 |
|---|---|---|
| lazyfish 右侧面板具体挂法 / slot | 推断 `?` | 大概率同 better-sidebar 走 `document.body` 自挂 + fixed/margin 推挤（因无右槽），未读源码确认 |
| lazyfish host 端 HTTP 路由路径前缀 / 协议 | 未确认 | 未读到 `lib/index.js` |
| host→client 桥接的安全校验（CSRF / trusted-host token） | 未确认 | 未验证；`serveStatic` 无 policy，需看具体桥接实现 |
| lazyfish 是否用 `defineTool` 或 `slash` 让 Agent 联动 | 未确认 | DSH 两种通道（`ctx.tools` 的 defineTool / `inject:['slash']`）均平台已验证，但 lazyfish 具体用哪个无证据 |
| lazyfish B 站嵌入具体方式（iframe 参数、防盗链处理） | 推断 `?` | iframe 官方播放器最可能是答案（B 站流带签名/防盗链），未确认 |
| lazyfish 的 `cordis.patch.yml` / install.mjs 内容 | 未确认 | DSH 插件经 `~/.dsh/cordis.patch.yml` 挂载（profile/patch 层），@dsh-external scope 本地约 14 个 client 插件 |

> **若要补齐未确认项**：需放行对 `~/.dsh/plugins/@dsh-external/dsh-web-panel/`（host 桥接范式）与 `~/.dsh/plugins/@dsh-external/dsh-lazyfish/`（本体）的只读访问，或授权 `danger-full-access` 做一次只读遍历。

---

## 4. 对「音乐播放器面板」的可执行落地清单

1. **布局选型**：优先试 `sidebar` 空槽（root/单例/官方/无冲突）；若需要真正自由的浮层，改用 `document.body` 自挂 + margin 推挤（照 2.3）。
2. **host 端**：注入 `['httpServer','tools',...]`，注册 `/api/*` 做网易云等第三方 API 代理（browser 同源不能直连非官方 API）。
3. **客户端**：同 origin `fetch('/api/...')` 绕 CORS；bundle 经 `__ModuleLoader__.load`，`apply` + `inject: ['slots', 'sessions', 'conversation']`（如需要 `slash` 加 `['slash']`）。
4. **Agent 联动**：host 用 `ctx.tools` + `defineTool` 定义点歌/切歌工具；UI 快捷命令用 `slash`。
5. **媒体**：B 站走 iframe 官方播放器（防盗链友好）；网易云走 host `/api` 代理；无 CSP 限制 Web Audio。
6. **安全**：既然 `serveStatic` 无 policy，桥接接口需**自证安全**——建议加 session-origin 校验/CSRF token，别依赖平台兜底。

---

## 5. 附：文件证据路径索引

- 客户端 slot 声明：`packages/client/ui-layout/src/client/index.ts`、`ui-conversation/src/client/apply.ts`、`ui-settings/src/client/index.ts`、`ui-sidebar/src/client/contract/slots.ts`
- 平台模块种子：`packages/client/web/src/seed.ts`
- 静态服务实现：`packages/host/frontend-static/src/index.ts`
- WebUI 入口（无 CSP）：`apps/web/index.html`、`apps/web/vite.config.ts`
- 参照插件自挂：`dsh-better-sidebar` 的 `lib/client.js`（约 468458-468505 行）
- 参照插件（host 桥接范式）：`~/.dsh/plugins/@dsh-external/dsh-web-panel/`（本会话读不到）
