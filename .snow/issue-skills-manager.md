## 问题现象

设置面板（Settings modal）右上角的全屏/还原按钮（⤢）当前以 `position: absolute; top: 10px; right: 46px` 硬钉在面板上，位置尴尬：

1. **与「打开配置文件」按钮重叠**：官方 header 是 flex 布局（`settings.action` slot 内容 + 28px 关闭按钮），actions 区紧贴关闭按钮左侧。⤢ 的绝对定位区间（right 46–74px / top 10–38px）正好压在 actions 区上方，`z-index: 20` 直接遮挡「打开配置文件」按钮。action 按钮宽度随语言变化，冲突必然发生。
2. **与关闭按钮不对齐**：关闭按钮在 flex 流内（header padding-top 20px），⤢ 在 top:10px —— 两者垂直差 10px，视觉上错位。

## 修复

把 ⤢ 从绝对定位改为**嵌入 header 的 flex 流**（结构探测：`panel > nav + content > header > close`，`insertBefore(toggle, close)`）：

- 与关闭按钮共享几何（28×28 同高、`align-items: flex-start` 顶对齐、flex `gap: 8px` 自动间距）
- 永不遮挡 actions 区（flex 流内自然排列，内容再宽也只会把按钮整体左移）
- 结构探测失败时降级为原绝对定位（新增 `.sb-panel-maximize--floating` 修饰类），保持本插件「框架结构变化时静默降级」的设计哲学

改动文件：`src/client/settings-enhancer.ts`（插入逻辑）+ `src/client/styles.css`（定位样式）。

## 验证

本地 0809 基线（Windows 原生部署）实测：按钮与 × 关闭按钮同行对齐，「打开配置文件」按钮不再被遮挡，全屏/还原与右下角拖拽手柄功能不受影响。

> 备注：README 标注本仓库已归档、合并进 dsh-memory-evolve。若维护重心已迁移，此修复同样适用于 memory-evolve 继承的同款增强代码（其 `skills-browser/styles.css` 中也有 `.sb-panel-maximize` 规则）。

---

## 一键查看差异

https://github.com/ShiroEirin/dsh-skills-manager/compare/main...fix/settings-panel-maximize-seat

（上游组织禁用了 fork，无法直接开 PR；上方为本人的镜像仓库分支，可直接 cherry-pick。）

## 补丁（git apply 可直接应用）

```diff
diff --git a/src/client/settings-enhancer.ts b/src/client/settings-enhancer.ts
index 666a2b9..7b84300 100644
--- a/src/client/settings-enhancer.ts
+++ b/src/client/settings-enhancer.ts
@@ -114,7 +114,20 @@ function enhancePanel(panel: HTMLElement): () => void {
     applyStyle()
     saveSize(size)
   })
-  panel.appendChild(toggle)
+  // Seat the toggle inside the panel header's flex row, immediately left of
+  // the framework's close button: it shares the close button's geometry and
+  // can never overlap the header actions slot (the previous absolute pin at
+  // top:10/right:46 floated 10px above the close line and covered the action
+  // pill). Structure walk: panel > nav + content > header > actions + close.
+  // If the framework reshapes the panel, degrade to the absolute pin.
+  const header = panel.querySelector('nav')?.nextElementSibling?.firstElementChild ?? null
+  const closeButton = header?.querySelector(':scope > button') ?? null
+  if (header !== null && closeButton !== null) {
+    header.insertBefore(toggle, closeButton)
+  } else {
+    toggle.classList.add('sb-panel-maximize--floating')
+    panel.appendChild(toggle)
+  }
 
   // ── bottom-right drag handle (explicit grip icon) ─────────────────────
   const handle = document.createElement('div')
diff --git a/src/client/styles.css b/src/client/styles.css
index e6f8d5f..4a2d239 100644
--- a/src/client/styles.css
+++ b/src/client/styles.css
@@ -835,13 +835,12 @@
 
 /* ── settings panel enhancement (fullscreen / drag-resize) ─────────────── */
 
-/* Fullscreen toggle button: pinned to the panel's top-right, left of the
-   framework's close button (36px wide), above the content stack. */
+/* Fullscreen toggle button: seated in the panel header's flex row, left of
+   the framework's close button — it shares the close geometry and can never
+   overlap the header actions. The --floating modifier restores the legacy
+   absolute pin when the framework structure is not recognized. */
 .sb-panel-maximize {
-  position: absolute;
-  top: 10px;
-  right: 46px;
-  z-index: 20;
+  flex: none;
   display: flex;
   align-items: center;
   justify-content: center;
@@ -856,6 +855,13 @@
   transition: background-color 120ms ease, color 120ms ease;
 }
 
+.sb-panel-maximize--floating {
+  position: absolute;
+  top: 10px;
+  right: 46px;
+  z-index: 20;
+}
+
 .sb-panel-maximize:hover {
   background: var(--dsw-alias-interactive-bg-hover);
   color: var(--dsw-alias-label-primary);
```