@echo off
rem Thin wrapper: the Windows monitor is scripts\monitor.ps1 (same options as monitor.sh).
rem Uses PowerShell 7 (pwsh) when installed, else Windows PowerShell 5.1.
setlocal
set "APOLO_PS=powershell.exe"
where pwsh.exe >nul 2>&1 && set "APOLO_PS=pwsh.exe"
"%APOLO_PS%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0monitor.ps1" %*
exit /b %ERRORLEVEL%
