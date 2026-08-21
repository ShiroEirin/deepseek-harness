## 问题现象

启用本仓库任一皮肤（nord / aurora / paper / dream）后，DSH Web 头部 deepseek 文字标右侧的 **HARNESS 徽章完全不可读**，只剩一个纯色块。

## 根因

官方 `BrandWordmark`（`@deepseek-ai/dsh-client-ui-primitives`）的徽章结构：

- 徽章底板：`<rect fill="currentColor">` → 取 `--dsw-alias-label-primary`
- HARNESS 字母：`fill="var(--dsw-alias-label-primary-inverted)"` → **反色镂空**

官方主题的语义是「inverted = primary 的反色」：浅色主题 primary 深、inverted 近白；深色主题 primary 浅、inverted 近深，因此徽章始终可读。

而四个皮肤把 `--dsw-alias-label-primary-inverted` 填成了与 primary **几乎相同的颜色**，文字与底板撞色：

| 皮肤 | primary（底板） | inverted（文字） | 效果 |
|---|---|---|---|
| nord | `#eceff4` | `#d8dee9` | 浅撞浅 |
| aurora | `#f0eeff` | `#e8e6ff` | 浅撞浅 |
| paper | `#3e3226` | `#4a3a28` | 深撞深 |
| dream | `#fdf6e3` | `#fdf6e3` | **完全相同，彻底隐形** |

## 修复

将各皮肤的 inverted 改为各自的底色（正好等于各皮肤自己定义的 `--dsw-alias-brand-primary-invert`，语义一致）：

- nord → `#2e3440`
- aurora → `#0d101e`
- paper → `#fbf8f2`
- dream → `#1b2140`

改动共 4 行（每皮肤 1 行），不影响其他任何 token。

## 验证

本地 0809 基线（Windows 原生部署）实测：四个皮肤下 HARNESS 徽章均恢复可读，浅色/深色官方主题不受影响（未改动官方 token）。
