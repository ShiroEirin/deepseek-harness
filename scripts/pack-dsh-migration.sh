#!/usr/bin/env bash
# ============================================================
# DSH 配置迁移包生成脚本（在源机器 WSL 上执行）
# 用法：bash scripts/pack-dsh-migration.sh [目标目录]
# 默认目标：/mnt/d/github/DeepSeek/dsh-config-migration/
# ============================================================
set -euo pipefail

DEST="${1:-/mnt/d/github/DeepSeek/dsh-config-migration}"
SRC_HOME="${HOME}/.dsh"

echo "==> 目标目录：${DEST}"
mkdir -p "${DEST}"

# ---------- 1. 配置文件（含 persona，无密钥） ----------
echo "==> 复制配置文件"
install -m 0644 "${SRC_HOME}/cordis.patch.yml" "${DEST}/cordis.patch.yml"
install -m 0644 "${SRC_HOME}/config.yaml"       "${DEST}/config.yaml"
install -m 0644 "${SRC_HOME}/settings.yaml"     "${DEST}/settings.yaml"
install -m 0600 "${SRC_HOME}/.userid"           "${DEST}/.userid"

# ---------- 2. 插件本体（10 个） ----------
echo "==> 复制插件本体"
mkdir -p "${DEST}/plugins"
for p in chat-width dsh-message-edit dsh-session-search dsh-skills-manager \
         dsh-tool-calculator dsh-tool-encoding dsh-tool-json dsh-tool-time \
         dsh-ui-progress dsh-web-ui-notify; do
  if [ -d "${SRC_HOME}/plugins/${p}" ]; then
    cp -a "${SRC_HOME}/plugins/${p}" "${DEST}/plugins/"
    echo "  - ${p}"
  else
    echo "  !! 缺失：${p}"
  fi
done
# 清理插件内的 node_modules（开发期 pnpm 软链，指向源机器绝对路径，运行时用已构建 lib/，不需要）
find "${DEST}/plugins" -type d -name node_modules -prune -exec rm -rf {} + 2>/dev/null || true
echo "  （已清理插件内 node_modules 开发软链）"

# ---------- 3. profiles/web（cordis.yml + package.json，不含 node_modules） ----------
echo "==> 复制 profiles/web"
mkdir -p "${DEST}/profiles/web"
install -m 0644 "${SRC_HOME}/profiles/web/cordis.yml"    "${DEST}/profiles/web/cordis.yml"
install -m 0644 "${SRC_HOME}/profiles/web/package.json"  "${DEST}/profiles/web/package.json"

# ---------- 4. storages/workspace.json ----------
echo "==> 复制 storages/workspace.json"
mkdir -p "${DEST}/storages"
install -m 0600 "${SRC_HOME}/storages/workspace.json" "${DEST}/storages/workspace.json"

# ---------- 5. README ----------
# 从脚本自身位置推导仓库根（scripts/..），不硬编码机器路径
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
echo "==> 复制 README（仓库 docs/ 已有则用）"
if [ -f "${REPO_ROOT}/docs/dsh-config-migration.md" ]; then
  install -m 0644 "${REPO_ROOT}/docs/dsh-config-migration.md" "${DEST}/README.md"
fi

# ---------- 6. 生成安装适配脚本 ----------
cat > "${DEST}/install-on-new-machine.sh" << 'SCRIPT'
#!/usr/bin/env bash
# DSH 迁移包安装脚本（在【新机器】WSL 上执行）
# 用法：bash install-on-new-machine.sh <新机器用户名>
set -euo pipefail
NEWUSER="${1:?用法: bash install-on-new-machine.sh <新机器用户名>}"
SRC="$(cd "$(dirname "$0")" && pwd)"
DEST_HOME="${HOME}/.dsh"

echo "==> 目标：${DEST_HOME}（用户名 ${NEWUSER}）"

# 1. 放置配置文件（cordis.patch.yml 先做路径适配）
echo "==> 安装配置文件"
mkdir -p "${DEST_HOME}"
sed "s|/home/aikun|/home/${NEWUSER}|g" "${SRC}/cordis.patch.yml" > "${DEST_HOME}/cordis.patch.yml"
cp "${SRC}/config.yaml"   "${DEST_HOME}/config.yaml"
cp "${SRC}/settings.yaml" "${DEST_HOME}/settings.yaml"
cp "${SRC}/.userid"       "${DEST_HOME}/.userid"

# 2. 放置插件本体
echo "==> 安装插件"
mkdir -p "${DEST_HOME}/plugins"
cp -a "${SRC}/plugins/." "${DEST_HOME}/plugins/"

# 3. profiles/web
echo "==> 安装 profiles/web"
mkdir -p "${DEST_HOME}/profiles/web"
cp "${SRC}/profiles/web/cordis.yml"   "${DEST_HOME}/profiles/web/cordis.yml"
cp "${SRC}/profiles/web/package.json" "${DEST_HOME}/profiles/web/package.json"

# 4. 重建 5 条 @dsh-external 软链（★关键，tar 不携带软链）
echo "==> 重建 @dsh-external 软链"
mkdir -p "${DEST_HOME}/profiles/web/node_modules/@dsh-external"
for p in chat-width dsh-message-edit dsh-skills-manager dsh-ui-progress dsh-web-ui-notify; do
  ln -sfn "${DEST_HOME}/plugins/${p}" "${DEST_HOME}/profiles/web/node_modules/@dsh-external/${p}"
done
ls -la "${DEST_HOME}/profiles/web/node_modules/@dsh-external/"

# 5. workspace.json（备份原文件，提示手动适配）
if [ -f "${DEST_HOME}/storages/workspace.json" ]; then
  cp "${DEST_HOME}/storages/workspace.json" "${DEST_HOME}/storages/workspace.json.bak-pre-migration"
fi
mkdir -p "${DEST_HOME}/storages"
cp "${SRC}/storages/workspace.json" "${DEST_HOME}/storages/workspace.json"
echo "!! 注意：workspace.json 里的 /mnt/d/... 路径是源机器的，请按新机器实际路径编辑（或删除不存在的条目）"

# 6. 校验
echo "==> 校验"
if grep -q "aikun" "${DEST_HOME}/cordis.patch.yml"; then
  echo "!! 警告：cordis.patch.yml 仍有 aikun 残留，请检查"
else
  echo "OK：cordis.patch.yml 无 aikun 残留"
fi
echo "完成！下一步："
echo "  1) 配置 ~/.dsh/.env（API 密钥）"
echo "  2) 安装主程序并启动 dsh web"
echo "  3) 按 README.md §5 验证清单逐项检查"
SCRIPT
chmod +x "${DEST}/install-on-new-machine.sh"

echo
echo "==> 迁移包已生成：${DEST}"
du -sh "${DEST}"
echo "提示：sessions/（历史会话 74M）按需手动拷贝；.env 密钥不打包。"
