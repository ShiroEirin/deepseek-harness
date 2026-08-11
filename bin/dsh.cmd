@echo off
rem dsh Windows launcher: runs the apps/cli `dsh` bin FROM SOURCE through the tsx
rem ESM hook, mirroring bin/dsh, so a launcher copied or shimmed anywhere (e.g.
rem %USERPROFILE%\.dsh\bin\dsh.cmd -> current\bin\dsh.cmd) always executes the
rem current working tree without a build step. Cmd.exe cannot express the Unix
rem exec-chain, so each invocation resolves paths from its own location; the
rem installer's stable shim calls through `current`, and file access follows the
rem junction transparently.
rem
rem Node's --import parses its argument as a URL; a Windows drive path (C:\...)
rem is read as the scheme `c:` and rejected, so the tsx hook is passed as a
rem file:// URL with backslashes normalised to forward slashes.
setlocal
set "DSH_ROOT=%~dp0.."
set "TSX_HOOK=file:///%DSH_ROOT:\=/%/node_modules/tsx/dist/esm/index.mjs"
set "NODE_USE_ENV_PROXY=1"
set "TSX_TSCONFIG_PATH=%DSH_ROOT%\tsconfig.json"
node --import "%TSX_HOOK%" "%DSH_ROOT%\apps\cli\src\bin.ts" %*
exit /b %ERRORLEVEL%
