<#
.SYNOPSIS
  DSH Windows 部署辅助脚本：配置落位 + junction 全量重建 + 就绪验证。

.DESCRIPTION
  面向「Windows 原生 DSH 主程序 + WSL bash 执行器」形态（0809 基线，
  见 docs/windows-deploy-0809.md）。基于家机 dsh-plugins-config-20260810
  部署包（56 插件 / 65 skills / 双 profile）一键恢复。

  用法：
    1) 从部署包恢复（推荐，一键）：
       .\setup-windows-dsh.ps1 -PackageDir D:\dsh-plugins-config-20260810 `
                               -Checkout D:\dsh\source\current -Apply
       - 复制 cordis.patch.yml / settings.yaml / client-links.manifest /
         plugins / skills / profiles 到 ~/.dsh
       - 用户名路径替换（ShiroEirin → 本机用户）
       - 按 client-links.manifest 全量重建 junction（56 插件全部覆盖）
       - 就绪验证

    2) 仅重建 junction（配置已就位，manifest 已在 ~/.dsh）：
       .\setup-windows-dsh.ps1 -Checkout D:\dsh\source\current -Apply

  注意：
  - junction 由 client-links.manifest 全量驱动；找不到 manifest 时报错，
    绝不静默降级（56 个插件一个都不能少）。
  - [checkout] 前缀的依赖 junction（cordis / node-pty / ws /
    dsh-client-ui-workflow）需要 -Checkout 指向主程序 checkout 目录。
  - profiles/node_modules（@deepseek-ai 147 包 + 单包）由主程序 pnpm
    install 生成，脚本只负责建 junction；target 不存在时跳过并提示。
  - 默认 DRY-RUN，加 -Apply 才写盘。

.EXAMPLE
  .\setup-windows-dsh.ps1 -PackageDir D:\dsh-plugins-config-20260810 -Checkout D:\dsh\source\current -Apply
#>
[CmdletBinding()]
param(
  [string]$PackageDir = '',
  [string]$DshHome = '',
  [string]$Checkout = '',
  [switch]$RebuildJunctionsOnly,
  [switch]$Apply
)

$ErrorActionPreference = 'Stop'

function Write-Step([string]$msg) { Write-Host "==> $msg" -ForegroundColor Cyan }
function Write-Ok([string]$msg)   { Write-Host "    [ok] $msg" -ForegroundColor Green }
function Write-Skip([string]$msg) { Write-Host "    [--] $msg" -ForegroundColor DarkGray }
function Write-Warn([string]$msg) { Write-Host "    [!] $msg" -ForegroundColor Yellow }

if (-not $DshHome) { $DshHome = Join-Path $env:USERPROFILE '.dsh' }
$profilesWeb = Join-Path $DshHome 'profiles\web'
$pluginsDir  = Join-Path $DshHome 'plugins'

Write-Step "DSH home: $DshHome"
Write-Step "Apply 模式: $(if ($Apply) {'写入'} else {'DRY-RUN（仅打印）'})"
if ($Checkout) { Write-Step "主程序 checkout: $Checkout" }

# ── 0. 环境检查 ──────────────────────────────────────────────────────
Write-Step '环境检查'
if (-not (Test-Path "$env:SystemRoot\System32\bash.exe")) {
  Write-Warn '未找到 C:\Windows\System32\bash.exe —— WSL 可能未启用；先 wsl --install'
} else { Write-Ok 'System32\bash.exe 存在（裸 bash 可解析到 WSL）' }
if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
  Write-Warn 'node 不在 PATH'
} else { Write-Ok "node: $(& node -v)" }

# ── 1. 从部署包恢复（可选） ───────────────────────────────────────────
if ($PackageDir -and -not $RebuildJunctionsOnly) {
  if (-not (Test-Path $PackageDir)) { throw "PackageDir 不存在: $PackageDir" }
  Write-Step "从部署包恢复: $PackageDir"

  $pkgHome = Join-Path $PackageDir 'cordis.patch.yml'
  if (-not (Test-Path $pkgHome)) { throw '包内缺少 cordis.patch.yml' }

  if ($Apply) { New-Item -ItemType Directory -Force -Path $DshHome | Out-Null }

  # ① 复制根级配置（含 manifest！junction 重建全靠它）
  foreach ($f in @('cordis.patch.yml', 'settings.yaml', 'client-links.manifest')) {
    $src = Join-Path $PackageDir $f
    if (-not (Test-Path $src)) { Write-Skip "$f 不存在，跳过"; continue }
    if ($Apply) { Copy-Item $src (Join-Path $DshHome $f) -Force }
    Write-Ok "复制 $f"
  }

  # ② 复制 plugins / skills / profiles（56 插件 / 65 skills / 双 profile 全量）
  foreach ($d in @('plugins', 'skills', 'profiles')) {
    $src = Join-Path $PackageDir $d
    if (-not (Test-Path $src)) { Write-Skip "$d/ 不存在，跳过"; continue }
    if ($Apply) { Copy-Item $src (Join-Path $DshHome $d) -Recurse -Force }
    Write-Ok "复制 $d/ (递归)"
  }

  # ③ 用户名路径替换（cordis.patch.yml 内 server 插件是 file:///C:/Users/ShiroEirin/... 绝对路径）
  $oldUser = 'ShiroEirin'
  $newUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name.Split('\')[-1]
  if ($newUser -ne $oldUser) {
    foreach ($f in @('cordis.patch.yml')) {
      $path = Join-Path $DshHome $f
      if (-not (Test-Path $path)) { continue }
      if ($Apply) {
        $text = Get-Content $path -Raw
        if ($text -match [regex]::Escape($oldUser)) {
          $text = $text.Replace("C:/Users/$oldUser", "C:/Users/$newUser")
          [System.IO.File]::WriteAllText($path, $text, (New-Object System.Text.UTF8Encoding $false))
          Write-Ok "${f}: C:/Users/$oldUser → C:/Users/$newUser"
        } else { Write-Skip "$f 无旧用户名，跳过" }
      } else { Write-Ok "$f 将替换用户名 $oldUser → $newUser" }
    }
  }
} elseif ($RebuildJunctionsOnly) {
  Write-Step '仅重建 junction 模式'
} else {
  Write-Step '未指定 PackageDir，跳过配置恢复（仅打印指引）'
  Write-Host "  用法: $($MyInvocation.MyCommand.Path) -PackageDir <部署包目录> -Checkout <主程序checkout> -Apply"
}

# ── 2. junction 全量重建（client-links.manifest 驱动） ───────────────
Write-Step 'junction 重建（client-links.manifest 全量）'
$manifestPath = Join-Path $DshHome 'client-links.manifest'
if (-not (Test-Path $manifestPath) -and $PackageDir) {
  $fromPkg = Join-Path $PackageDir 'client-links.manifest'
  if (Test-Path $fromPkg) { $manifestPath = $fromPkg }
}
if (-not (Test-Path $manifestPath)) {
  throw "未找到 client-links.manifest（$manifestPath 或包内）—— junction 重建必须按清单逐条执行，拒绝降级"
}
Write-Ok "解析 manifest: $manifestPath"

# 目标前缀 → 路径解析
function Resolve-ManifestTarget([string]$desc) {
  if ($desc.StartsWith('[plugins]'))    { return Join-Path $DshHome 'plugins' $desc.Substring(9) }
  if ($desc.StartsWith('[monorepo]'))   { return Join-Path $DshHome 'plugins' $desc.Substring(10) }
  if ($desc.StartsWith('[profiles]'))   { return Join-Path $DshHome $desc.Substring(10) }
  if ($desc.StartsWith('[plugins-deps]')) { return Join-Path $DshHome $desc.Substring(14) }
  if ($desc.StartsWith('[checkout]')) {
    if (-not $Checkout) { throw "[checkout] 前缀需要 -Checkout 参数: $desc" }
    return Join-Path $Checkout $desc.Substring(10)
  }
  throw "未知目标前缀: $desc"
}

# profile → junction 落点
function Resolve-LinkPath([string]$profile, [string]$name) {
  switch ($profile) {
    'web' {
      $base = Join-Path $DshHome 'profiles\web\node_modules'
      if ($name.StartsWith('@') -and $name.Contains('/')) {
        $scope, $pkg = $name.Split('/')
        return (Join-Path (Join-Path $base $scope) $pkg)
      }
      return Join-Path $base $name
    }
    'cc-tui' {
      # junction 挂在全局 profiles/node_modules/@deepseek-ai 下
      $base = Join-Path $DshHome 'profiles\node_modules\@deepseek-ai'
      if ($name.StartsWith('@') -and $name.Contains('/')) { $pkg = $name.Split('/')[1] } else { $pkg = $name }
      return Join-Path $base $pkg
    }
    'global' {
      $base = Join-Path $DshHome 'plugins\node_modules'
      if ($name.StartsWith('@') -and $name.Contains('/')) {
        $scope, $pkg = $name.Split('/')
        return (Join-Path (Join-Path $base $scope) $pkg)
      }
      return Join-Path $base $name   # 含 scope 目录本身（@deepseek-ai）与裸包名
    }
    default { throw "未知 profile: $profile" }
  }
}

$junctions = @()
foreach ($line in Get-Content $manifestPath) {
  $t = $line.Trim()
  if (-not $t -or $t.StartsWith('#')) { continue }
  $parts = $t.Split('|')
  if ($parts.Count -lt 3) { continue }
  $junctions += @{ Profile = $parts[0]; Name = $parts[1]; Desc = $parts[2] }
}
Write-Ok "manifest 共 $($junctions.Count) 条 junction 记录（web client + 依赖 + cc-tui + global src 依赖）"

if ($Apply) {
  $created = 0; $skipped = 0; $missing = 0
  foreach ($j in $junctions) {
    $link = Resolve-LinkPath $j.Profile $j.Name
    $target = Resolve-ManifestTarget $j.Desc
    if (-not (Test-Path $target)) {
      Write-Warn "目标不存在，跳过 $link → $target（profiles/node_modules 需先由主程序 pnpm install 生成）"
      $missing++; continue
    }
    if (Test-Path $link) { Write-Ok "$link 已存在，跳过"; $skipped++; continue }
    New-Item -ItemType Directory -Force -Path (Split-Path $link) | Out-Null
    New-Item -ItemType Junction -Path $link -Target $target | Out-Null
    Write-Ok "junction: $link → $target"
    $created++
  }
  Write-Ok "junction 重建完成：新建 $created / 已存在 $skipped / 目标缺失 $missing"
} else {
  foreach ($j in $junctions) {
    $link = Resolve-LinkPath $j.Profile $j.Name
    $target = Resolve-ManifestTarget $j.Desc
    Write-Ok "将创建 junction: $link → $target"
  }
}

# ── 3. 验证清单 ─────────────────────────────────────────────────────
Write-Step '就绪验证（运行前请先启动 dsh web）'
Write-Ok "配置: $(Join-Path $DshHome 'cordis.patch.yml')"
$pluginCount = if (Test-Path $pluginsDir) { (Get-ChildItem $pluginsDir -Directory).Count } else { 0 }
Write-Ok "插件目录: $pluginsDir（$pluginCount 个，家机包应为 56）"
$skillCount = if (Test-Path (Join-Path $DshHome 'skills')) { (Get-ChildItem (Join-Path $DshHome 'skills') -Directory).Count } else { 0 }
Write-Ok "skills: $(Join-Path $DshHome 'skills')（$skillCount 个，家机包应为 65）"
$port = netstat -ano 2>$null | Select-String ':3080'
if ($port) { Write-Ok '端口 3080 在监听' } else { Write-Warn '端口 3080 未监听（dsh web 未启动？）' }

Write-Step '完成。若为 DRY-RUN，请加 -Apply 实际执行。'
