<#
# dsh Windows installer — PowerShell counterpart to scripts/install.sh.
#
#   powershell -ExecutionPolicy Bypass -File scripts\install-windows.ps1
#
# Mirrors the POSIX installer's layout so Unix and Windows installs converge:
# a master clone (or an adopted checkout) at $DSH_SOURCE\master, one per-install
# staging git worktree at $DSH_SOURCE\staging-<timestamp>, a stable `current`
# junction pointing at the active staging worktree, and a `dsh.cmd` launcher on
# PATH that calls through `current\bin\dsh.cmd`. Windows has no symlinks for
# ordinary users, so `current` is a directory junction (no Developer Mode/admin
# needed) and the PATH entry is a small cmd shim rather than a link.
#
# Run from inside a checkout, the script ADOPTS that checkout (never clones,
# never touches its working tree; committed work only lands in staging via a
# worktree from HEAD). Otherwise it clones $DSH_REPO @ $DSH_REF into $DSH_MASTER.
#
# Overridable via environment (mirrors install.sh):
#   DSH_REF, DSH_REPO, DSH_SOURCE, DSH_MASTER, DSH_CURRENT, DSH_BIN_DIR, DSH_HOME
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

# --- paths -------------------------------------------------------------------
$homeDsh   = if ($env:DSH_HOME)    { $env:DSH_HOME }    else { Join-Path $HOME '.dsh' }
$DSH_SOURCE = if ($env:DSH_SOURCE)  { $env:DSH_SOURCE }  else { Join-Path $homeDsh 'source' }
$DSH_MASTER = if ($env:DSH_MASTER)  { $env:DSH_MASTER }  else { Join-Path $DSH_SOURCE 'master' }
$DSH_CURRENT = if ($env:DSH_CURRENT) { $env:DSH_CURRENT } else { Join-Path $DSH_SOURCE 'current' }
$DSH_BIN_DIR = if ($env:DSH_BIN_DIR) { $env:DSH_BIN_DIR } else { Join-Path $homeDsh 'bin' }
$DSH_REF   = if ($env:DSH_REF)      { $env:DSH_REF }     else { 'master' }
$DSH_REPO  = if ($env:DSH_REPO)     { $env:DSH_REPO }    else { 'https://github.com/deepseek-harness/deepseek-harness.git' }

# --- in-repo adoption --------------------------------------------------------
# Running from inside a checkout (this file's parent is a scripts/ dir with a
# bin/dsh.cmd at the repo root): never clone, adopt the checkout as master.
$repoRoot = Split-Path -Parent $PSScriptRoot
$inRepo = (Test-Path (Join-Path $repoRoot 'bin\dsh.cmd')) -and (Test-Path (Join-Path $repoRoot '.git'))
$checkout = if ($inRepo) { $repoRoot } else { $null }

# One UTC basic timestamp names this install's staging branch and worktree.
$DSH_STAMP = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ')
$DSH_STAGING_BRANCH = "dsh-staging/$DSH_STAMP"
$DSH_STAGING = Join-Path $DSH_SOURCE "staging-$DSH_STAMP"

function Write-Step([string]$title) { Write-Host "`n==> $title" -ForegroundColor Cyan }
function Write-Info([string]$msg)   { Write-Host "==> $msg" -ForegroundColor Green }
function Write-Warn([string]$msg)   { Write-Host " warn $msg" -ForegroundColor Yellow }
function Fail([string]$msg)         { Write-Host "error $msg" -ForegroundColor Red; exit 1 }

Write-Host "DeepSeek Harness - dsh installer (Windows)" -ForegroundColor Cyan

# --- 1. dependency check -----------------------------------------------------
Write-Step 'Checking dependencies'
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
  Fail 'git is required but not found. Install git (https://git-scm.com/download/win), then re-run.'
}
Write-Info 'git ... ok'

$nodeVersion = & node -v 2>$null
if ($LASTEXITCODE -eq 0 -and $nodeVersion) {
  # Node ^22.19.0 || >=24.0.0 (root package.json "engines").
  $parts = ($nodeVersion.TrimStart('v')).Split('.')
  $major = [int]$parts[0]
  $minor = if ($parts.Count -gt 1) { [int]$parts[1] } else { 0 }
  $nodeOk = ($major -ge 24) -or ($major -eq 22 -and $minor -ge 19)
  if ($nodeOk) { Write-Info "node $nodeVersion ... ok" }
  else { Fail "Node $nodeVersion is unsupported. dsh needs ^22.19.0 || >=24.0.0 - upgrade Node, then re-run." }
} else {
  Fail 'Node is required but not found. Install Node ^22.19.0 || >=24 (https://nodejs.org), then re-run.'
}

if (Get-Command pnpm -ErrorAction SilentlyContinue) {
  Write-Info "pnpm $(& pnpm --version) ... ok"
} else {
  Write-Warn 'pnpm is not installed.'
  $answer = Read-Host 'Install pnpm now? [Y/n]'
  if ($answer -match '^[yY]') {
    if (Get-Command corepack -ErrorAction SilentlyContinue) {
      corepack enable pnpm | Out-Null
    } elseif (Get-Command npm -ErrorAction SilentlyContinue) {
      npm install -g pnpm | Out-Null
    } else {
      Fail 'could not install pnpm automatically. Install it (https://pnpm.io/installation), then re-run.'
    }
    if (-not (Get-Command pnpm -ErrorAction SilentlyContinue)) {
      Fail 'pnpm still not on PATH after install. Open a new shell, then re-run.'
    }
  } else {
    Fail 'pnpm is required. Install it (https://pnpm.io/installation), then re-run.'
  }
}

# --- 2. resolve the repository and lay out the staging worktree --------------
# Resolve the shared git dir and anchor it absolutely (git may report it
# relative, e.g. `.git` for a plain clone). --git-common-dir returns the SHARED
# dir, so a linked worktree resolves to the real clone rather than itself.
$repoCommon = $null
if ($inRepo) {
  Write-Step "Using existing checkout at $checkout"
  Write-Info 'running from inside the repo - never cloning, and DSH_REF is ignored'
  $repoRootAbs = (git -C $checkout rev-parse --show-toplevel 2>$null).Trim()
  if (-not $repoRootAbs) { Fail "$checkout is not a git repository - cannot adopt it." }
  $DSH_MASTER = $repoRootAbs
  $repoCommon = (git -C $checkout rev-parse --git-common-dir 2>$null).Trim()
  if (-not [System.IO.Path]::IsPathRooted($repoCommon)) { $repoCommon = Join-Path $DSH_MASTER $repoCommon }
  if (-not (Test-Path $repoCommon)) { Fail "$checkout is not a git repository - cannot adopt it." }
} else {
  Write-Step "Fetching source into $DSH_MASTER"
  if (Test-Path (Join-Path $DSH_MASTER '.git')) {
    Write-Info 'existing master clone found - updating'
    git -C $DSH_MASTER fetch origin $DSH_REF
    if ($LASTEXITCODE -ne 0) { Fail "git fetch failed." }
    git -C $DSH_MASTER checkout -q -B $DSH_REF FETCH_HEAD
    if ($LASTEXITCODE -ne 0) { Fail "git checkout failed." }
  } else {
    New-Item -ItemType Directory -Force -Path $DSH_SOURCE | Out-Null
    git clone --branch $DSH_REF $DSH_REPO $DSH_MASTER
    if ($LASTEXITCODE -ne 0) { Fail "git clone failed." }
  }
  $DSH_MASTER = (git -C $DSH_MASTER rev-parse --show-toplevel 2>$null).Trim()
  $repoCommon = (git -C $DSH_MASTER rev-parse --git-common-dir 2>$null).Trim()
  if (-not [System.IO.Path]::IsPathRooted($repoCommon)) { $repoCommon = Join-Path $DSH_MASTER $repoCommon }
}

Write-Step "Adding staging worktree at $DSH_STAGING"
if (Test-Path $DSH_STAGING) {
  Fail "staging path $DSH_STAGING already exists - remove it or set DSH_SOURCE elsewhere, then re-run."
}
New-Item -ItemType Directory -Force -Path $DSH_SOURCE | Out-Null
$gitBase = if ($inRepo) { $checkout } else { $DSH_MASTER }
if ($inRepo) {
  git -C $gitBase worktree add -b $DSH_STAGING_BRANCH $DSH_STAGING HEAD
} else {
  git -C $gitBase worktree add -b $DSH_STAGING_BRANCH $DSH_STAGING HEAD
}
if ($LASTEXITCODE -ne 0) { Fail "git worktree add failed." }

# Exclude the per-worktree merge lock, mirroring install.sh.
$exclude = Join-Path $repoCommon 'info\exclude'
if ((Test-Path $exclude) -and -not (Select-String -Path $exclude -SimpleMatch '.agents/merge.lock' -Quiet)) {
  Add-Content -Path $exclude -Value '.agents/merge.lock'
}
New-Item -ItemType Directory -Force -Path (Join-Path $DSH_STAGING '.agents') | Out-Null
New-Item -ItemType File -Force -Path (Join-Path $DSH_STAGING '.agents\merge.lock') | Out-Null

# --- 3. install dependencies (no build; the launcher runs from source) -------
Write-Step 'Installing dependencies with pnpm (this can take a while)'
Push-Location $DSH_STAGING
try { pnpm install }
finally { Pop-Location }
if ($LASTEXITCODE -ne 0) { Fail 'pnpm install failed.' }

if (-not (Test-Path (Join-Path $DSH_STAGING 'bin\dsh.cmd'))) {
  Fail "launcher $DSH_STAGING\bin\dsh.cmd missing after install - is DSH_REF a branch that ships apps/cli?"
}

# --- 4. put `dsh` on PATH ----------------------------------------------------
# Windows cannot `ln -sfn`, so `current` is a junction and the PATH entry is a
# small cmd shim that calls through it. An upgrade repoints `current` at a new
# staging worktree; the shim never moves.
Write-Step "Linking dsh into $DSH_BIN_DIR"
New-Item -ItemType Directory -Force -Path $DSH_BIN_DIR | Out-Null

# rmdir removes a junction without ever following into its target (PS
# Remove-Item -Recurse can recurse into a junction target on older versions).
if (Test-Path $DSH_CURRENT) { cmd /c rmdir "$DSH_CURRENT" 2>$null; if ($LASTEXITCODE -ne 0) { Fail "could not remove existing $DSH_CURRENT" } }
New-Item -ItemType Junction -Path $DSH_CURRENT -Target $DSH_STAGING | Out-Null
Write-Info "pointed $DSH_CURRENT -> $DSH_STAGING"

$shim = "@echo off`r`n" +
  "rem dsh launcher shim - calls through the current junction so upgrades repoint it in place.`r`n" +
  "call `"$DSH_CURRENT\bin\dsh.cmd`" %*`r`n" +
  "exit /b %ERRORLEVEL%`r`n"
Set-Content -Path (Join-Path $DSH_BIN_DIR 'dsh.cmd') -Value $shim -Encoding Ascii
Write-Info "wrote $DSH_BIN_DIR\dsh.cmd -> $DSH_CURRENT\bin\dsh.cmd"

$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
if ($userPath -and (($userPath -split ';') -contains $DSH_BIN_DIR)) {
  Write-Info "$DSH_BIN_DIR already on user PATH"
} else {
  $newPath = if ($userPath) { $userPath.TrimEnd(';') + ';' + $DSH_BIN_DIR } else { $DSH_BIN_DIR }
  [Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
  Write-Warn "added $DSH_BIN_DIR to user PATH - open a new shell to pick it up"
}

# --- 5. credentials ----------------------------------------------------------
Write-Step 'Configuring credentials'
$envFile = Join-Path $homeDsh '.env'
# The installer owns exactly the two DEEPSEEK_* lines; any other lines the user
# keeps in this .env are preserved on rewrite (mirrors install.sh).
$keep = @()
if (Test-Path $envFile) {
  $keep = @(Get-Content $envFile | Where-Object { $_ -notmatch '^DEEPSEEK_API_KEY=' -and $_ -notmatch '^DEEPSEEK_BASE_URL=' })
}
$hasExistingKey = (Test-Path $envFile) -and (Get-Content $envFile | Select-String -SimpleMatch 'DEEPSEEK_API_KEY=' -Quiet)
if ($hasExistingKey) {
  Write-Info "DEEPSEEK_API_KEY already set in $envFile"
  $replace = Read-Host 'Replace it? [y/N]'
  if ($replace -notmatch '^[yY]') { $skipCreds = $true }
}
if (-not $skipCreds) {
  $secure = Read-Host 'DeepSeek API key (input hidden):' -AsSecureString
  $key = if ($secure) { [System.Net.NetworkCredential]::new('', $secure).Password } else { '' }
  if ([string]::IsNullOrEmpty($key)) {
    Write-Warn "no key entered - skipping. Set DEEPSEEK_API_KEY in $envFile before using dsh."
  } else {
    $baseUrl = Read-Host 'DeepSeek base URL (optional, Enter to skip):'
    New-Item -ItemType Directory -Force -Path $homeDsh | Out-Null
    $lines = @($keep) + "DEEPSEEK_API_KEY=$key"
    if (-not [string]::IsNullOrEmpty($baseUrl)) { $lines += "DEEPSEEK_BASE_URL=$baseUrl" }
    Set-Content -Path $envFile -Value $lines -Encoding Ascii
    # Windows analog of `chmod 600`: restrict to the current user only.
    icacls $envFile /inheritance:r /grant:r "$env:USERDOMAIN\$env:USERNAME:(R,W)" | Out-Null
    Write-Info "wrote $envFile"
  }
}

# --- 6. next steps -----------------------------------------------------------
Write-Step 'Done'
Write-Host '   1) Web UI (recommended):  dsh web   (builds the repository first)'
Write-Host '   2) TUI:                   dsh'
Write-Host ''
Write-Info 'install complete. Open a new shell, then run:'
Write-Host '   dsh'
Write-Host 'or build and start the Web UI with:'
Write-Host "   (cd $DSH_STAGING; pnpm run build)"
Write-Host '   dsh web'
