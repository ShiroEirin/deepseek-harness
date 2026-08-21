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
