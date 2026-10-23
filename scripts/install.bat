@echo off
setlocal EnableExtensions EnableDelayedExpansion

set "SOURCE=%~dp0.."
for %%I in ("%SOURCE%") do set "SOURCE=%%~fI"
set "CLAUDE_DIR=%USERPROFILE%\.claude"
set "CODEX_DIR=%USERPROFILE%\.codex"
set "REPLACE=0"
set "DRY_RUN=0"

:parse
if "%~1"=="" goto parsed
if /I "%~1"=="--source" (
  if "%~2"=="" goto missing_value
  set "SOURCE=%~2"
  shift
  shift
  goto parse
)
if /I "%~1"=="--local" (
  shift
  goto parse
)
if /I "%~1"=="--track" (
  echo Error: --track is currently supported on macOS/Linux only >&2
  exit /b 1
)
if /I "%~1"=="--claude-dir" (
  if "%~2"=="" goto missing_value
  set "CLAUDE_DIR=%~2"
  shift
  shift
  goto parse
)
if /I "%~1"=="--codex-dir" (
  if "%~2"=="" goto missing_value
  set "CODEX_DIR=%~2"
  shift
  shift
  goto parse
)
if /I "%~1"=="--replace" (
  set "REPLACE=1"
  shift
  goto parse
)
if /I "%~1"=="--dry-run" (
  set "DRY_RUN=1"
  shift
  goto parse
)
if /I "%~1"=="--help" goto usage
echo Error: unknown option %~1 >&2
exit /b 1

:missing_value
echo Error: missing option value >&2
exit /b 1

:parsed
for %%I in ("%SOURCE%") do set "SOURCE=%%~fI"
if not exist "%SOURCE%\CLAUDE.md" goto missing_source
if not exist "%SOURCE%\AGENTS.md" goto missing_source
if not exist "%SOURCE%\sdlc\NUL" goto missing_source
if not exist "%SOURCE%\commands\NUL" goto missing_source
if not exist "%SOURCE%\skills\NUL" goto missing_source

for %%I in ("%CLAUDE_DIR%") do set "CLAUDE_DIR=%%~fI"
for %%I in ("%CODEX_DIR%") do set "CODEX_DIR=%%~fI"
call :validate_root "%CLAUDE_DIR%" || exit /b 1
call :validate_root "%CODEX_DIR%" || exit /b 1

call :preflight "%CLAUDE_DIR%\CLAUDE.md" || exit /b 1
call :preflight "%CLAUDE_DIR%\sdlc" || exit /b 1
call :preflight "%CLAUDE_DIR%\commands" || exit /b 1
call :preflight "%CLAUDE_DIR%\skills" || exit /b 1
call :preflight "%CODEX_DIR%\AGENTS.md" || exit /b 1
call :preflight "%CODEX_DIR%\sdlc" || exit /b 1
call :preflight "%CODEX_DIR%\commands" || exit /b 1
call :preflight "%CODEX_DIR%\skills" || exit /b 1

call :ensure_root "%CLAUDE_DIR%" || exit /b 1
call :ensure_root "%CODEX_DIR%" || exit /b 1

set /a STEP=0
call :install_file "%SOURCE%\CLAUDE.md" "%CLAUDE_DIR%\CLAUDE.md" || goto rollback
call :install_dir "%SOURCE%\sdlc" "%CLAUDE_DIR%\sdlc" || goto rollback
call :install_dir "%SOURCE%\commands" "%CLAUDE_DIR%\commands" || goto rollback
call :install_dir "%SOURCE%\skills" "%CLAUDE_DIR%\skills" || goto rollback
call :install_file "%SOURCE%\AGENTS.md" "%CODEX_DIR%\AGENTS.md" || goto rollback
call :install_dir "%SOURCE%\sdlc" "%CODEX_DIR%\sdlc" || goto rollback
call :install_dir "%SOURCE%\commands" "%CODEX_DIR%\commands" || goto rollback
call :install_dir "%SOURCE%\skills" "%CODEX_DIR%\skills" || goto rollback
exit /b 0

:rollback
call :rollback_installation
if errorlevel 1 (
  echo Error: installation failed and rollback was incomplete >&2
  exit /b 2
)
echo Error: installation failed and was rolled back >&2
exit /b 1

:missing_source
echo Error: managed source is missing from "%SOURCE%" >&2
exit /b 1

:validate_root
if "%~1"=="" (
  echo Error: unsafe configuration directory >&2
  exit /b 1
)
if /I "%~1"=="%~d1\" (
  echo Error: unsafe configuration directory >&2
  exit /b 1
)
if "%~1:~0,2%"=="\\" (
  echo Error: unsafe configuration directory >&2
  exit /b 1
)
if exist "%~1" (
  fsutil reparsepoint query "%~1" >nul 2>&1 && (
    echo Error: configuration directory must not be a symbolic link: %~1 >&2
    exit /b 1
  )
  if not exist "%~1\NUL" (
    echo Error: configuration directory is not a directory: %~1 >&2
    exit /b 1
  )
)
exit /b 0

:preflight
if not exist "%~1" exit /b 0
fsutil reparsepoint query "%~1" >nul 2>&1 && (
  echo Error: refusing to replace existing symbolic link: %~1 >&2
  exit /b 1
)
if "%REPLACE%"=="1" exit /b 0
echo Error: managed target exists; rerun with --replace: %~1 >&2
exit /b 1

:ensure_root
if exist "%~1\NUL" exit /b 0
if "%DRY_RUN%"=="1" (
  echo Would create directory %~1
  exit /b 0
)
mkdir "%~1" >nul || exit /b 1
exit /b 0

:backup
for /f %%I in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd-HHmmss"') do set "STAMP=%%I"
set "BACKUP=%~1-old-%STAMP%"
set /a SUFFIX=0
:backup_name
if not exist "!BACKUP!" goto backup_ready
set /a SUFFIX+=1
set "BACKUP=%~1-old-%STAMP%-!SUFFIX!"
goto backup_name
:backup_ready
if "%DRY_RUN%"=="1" (
  echo Would back up %~1 to !BACKUP!
  exit /b 0
)
move "%~1" "!BACKUP!" >nul || exit /b 1
set "BACKUP_%STEP%=!BACKUP!"
echo Backed up %~1 to !BACKUP!
exit /b 0

:install_file
set /a STEP+=1
set "TARGET_%STEP%=%~2"
set "KIND_%STEP%=file"
if exist "%~2" call :backup "%~2" || exit /b 1
if "%DRY_RUN%"=="1" (
  echo Would link %~2 to %~1
  exit /b 0
)
mklink "%~2" "%~1" >nul || exit /b 1
set "CREATED_%STEP%=1"
echo Linked %~2 to %~1
exit /b 0

:install_dir
set /a STEP+=1
set "TARGET_%STEP%=%~2"
set "KIND_%STEP%=dir"
if exist "%~2" call :backup "%~2" || exit /b 1
if "%DRY_RUN%"=="1" (
  echo Would link %~2 to %~1
  exit /b 0
)
mklink /D "%~2" "%~1" >nul || exit /b 1
set "CREATED_%STEP%=1"
echo Linked %~2 to %~1
exit /b 0

:rollback_installation
set "ROLLBACK_FAILED=0"
for /l %%I in (%STEP%,-1,1) do (
  if defined CREATED_%%I (
    if "!KIND_%%I!"=="dir" (
      rmdir "!TARGET_%%I!" >nul 2>&1 || set "ROLLBACK_FAILED=1"
    ) else (
      del "!TARGET_%%I!" >nul 2>&1 || set "ROLLBACK_FAILED=1"
    )
  )
  if defined BACKUP_%%I (
    if not exist "!TARGET_%%I!" (
      move "!BACKUP_%%I!" "!TARGET_%%I!" >nul || set "ROLLBACK_FAILED=1"
    ) else (
      set "ROLLBACK_FAILED=1"
    )
  )
)
if "!ROLLBACK_FAILED!"=="1" exit /b 1
exit /b 0

:usage
echo Usage: scripts\install.bat [--local] [--source PATH] [--claude-dir PATH] [--codex-dir PATH] [--replace] [--dry-run]
exit /b 0
