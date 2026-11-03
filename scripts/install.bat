@echo off
setlocal EnableExtensions EnableDelayedExpansion

set "SOURCE=%~dp0.."
for %%I in ("%SOURCE%") do set "SOURCE=%%~fI"
set "CLAUDE_DIR=%USERPROFILE%\.claude"
set "CODEX_DIR=%USERPROFILE%\.codex"
set "REPLACE=0"
set "DRY_RUN=0"
set "UNINSTALL=0"

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
if /I "%~1"=="--uninstall" (
  set "UNINSTALL=1"
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
if not exist "%SOURCE%\sdlc\NUL" goto missing_source
if not exist "%SOURCE%\skills\NUL" goto missing_source

for %%I in ("%CLAUDE_DIR%") do set "CLAUDE_DIR=%%~fI"
for %%I in ("%CODEX_DIR%") do set "CODEX_DIR=%%~fI"
call :validate_root "%CLAUDE_DIR%" || exit /b 1
call :validate_root "%CODEX_DIR%" || exit /b 1

if "%UNINSTALL%"=="1" goto uninstall

call :validate_root "%CLAUDE_DIR%\skills" || exit /b 1
call :validate_root "%CODEX_DIR%\skills" || exit /b 1
call :validate_root "%CLAUDE_DIR%\skills-backup" || exit /b 1
call :validate_root "%CODEX_DIR%\skills-backup" || exit /b 1
for %%R in ("%CLAUDE_DIR%" "%CODEX_DIR%") do (
  call :preflight "%%~R\sdlc" || exit /b 1
  for /d %%S in ("%SOURCE%\skills\*") do (
    if exist "%%~S\SKILL.md" call :preflight "%%~R\skills\%%~nxS" || exit /b 1
  )
)

call :ensure_root "%CLAUDE_DIR%\skills" || exit /b 1
call :ensure_root "%CODEX_DIR%\skills" || exit /b 1

set /a STEP=0
rem Uninstall the previous install first: stale managed skill links (renamed or removed skills) go too.
for %%R in ("%CLAUDE_DIR%" "%CODEX_DIR%") do (
  if exist "%%~R\skills\NUL" for /f "delims=" %%L in ('dir /b /AL "%%~R\skills" 2^>nul') do (
    if not exist "%SOURCE%\skills\%%L\SKILL.md" call :remove_if_managed "%%~R\skills\%%L" || goto rollback
  )
)
for %%R in ("%CLAUDE_DIR%" "%CODEX_DIR%") do (
  call :install_dir "%SOURCE%\sdlc" "%%~R\sdlc" || goto rollback
  for /d %%S in ("%SOURCE%\skills\*") do (
    if exist "%%~S\SKILL.md" call :install_dir "%%~S" "%%~R\skills\%%~nxS" "%%~R\skills-backup\%%~nxS" || goto rollback
  )
)
exit /b 0

:uninstall
for %%R in ("%CLAUDE_DIR%" "%CODEX_DIR%") do (
  call :remove_if_managed "%%~R\sdlc" || exit /b 1
  if exist "%%~R\skills\NUL" for /f "delims=" %%L in ('dir /b /AL "%%~R\skills" 2^>nul') do (
    call :remove_if_managed "%%~R\skills\%%L" || exit /b 1
  )
)
echo Uninstall complete
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
  call :is_managed "%~1"
  if "!MANAGED!"=="1" exit /b 0
  echo Error: refusing to replace unmanaged symbolic link: %~1 >&2
  exit /b 1
)
if "%REPLACE%"=="1" exit /b 0
echo Error: managed target exists; rerun with --replace: %~1 >&2
exit /b 1

:is_managed
rem A managed link points at <clone>\sdlc or <clone>\skills\<same name> of a library clone
rem (a directory with sdlc and skills), or dangles there after the clone moved.
set "MANAGED=0"
set "LINK_TARGET="
fsutil reparsepoint query "%~1" >nul 2>&1 || exit /b 0
set "LINK_PATH=%~1"
for /f "usebackq delims=" %%T in (`powershell -NoProfile -Command "(Get-Item -LiteralPath $env:LINK_PATH -Force).Target" 2^>nul`) do set "LINK_TARGET=%%T"
if not defined LINK_TARGET exit /b 0
call :is_managed_check "%~1"
exit /b 0

:is_managed_check
set "LINK_ROOT="
for %%P in ("!LINK_TARGET!") do (
  set "LINK_LEAF=%%~nxP"
  set "LINK_PARENT=%%~dpP"
)
if /I not "!LINK_LEAF!"=="%~nx1" exit /b 0
for %%Q in ("!LINK_PARENT:~0,-1!") do (
  set "LINK_PARENT_LEAF=%%~nxQ"
  set "LINK_GRANDPARENT=%%~dpQ"
)
for %%Q in ("%~dp1.") do set "TARGET_PARENT_LEAF=%%~nxQ"
if /I "!TARGET_PARENT_LEAF!"=="skills" (
  if /I not "!LINK_PARENT_LEAF!"=="skills" exit /b 0
  set "LINK_ROOT=!LINK_GRANDPARENT!"
) else (
  if /I not "!LINK_LEAF!"=="sdlc" exit /b 0
  set "LINK_ROOT=!LINK_PARENT!"
)
if not exist "!LINK_TARGET!" (
  set "MANAGED=1"
  exit /b 0
)
if exist "!LINK_ROOT!sdlc\NUL" if exist "!LINK_ROOT!skills\NUL" set "MANAGED=1"
exit /b 0

:remove_if_managed
call :is_managed "%~1"
if not "!MANAGED!"=="1" exit /b 0
if "%DRY_RUN%"=="1" (
  echo Would remove managed link %~1
  exit /b 0
)
set /a STEP+=1
set "TARGET_%STEP%=%~1"
rmdir "%~1" >nul 2>&1 || exit /b 1
set "OLDLINK_%STEP%=!LINK_TARGET!"
echo Removed managed link %~1
exit /b 0

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
rem Skill backups go to skills-backup because a copy left in skills loads as a duplicate skill.
set "BACKUP_BASE=%~1"
if not "%~2"=="" set "BACKUP_BASE=%~2"
set "BACKUP=!BACKUP_BASE!-old-%STAMP%"
set /a SUFFIX=0
:backup_name
if not exist "!BACKUP!" goto backup_ready
set /a SUFFIX+=1
set "BACKUP=!BACKUP_BASE!-old-%STAMP%-!SUFFIX!"
goto backup_name
:backup_ready
if "%DRY_RUN%"=="1" (
  echo Would back up %~1 to !BACKUP!
  exit /b 0
)
for %%D in ("!BACKUP!") do if not exist "%%~dpD" mkdir "%%~dpD" >nul || exit /b 1
move "%~1" "!BACKUP!" >nul || exit /b 1
set "BACKUP_%STEP%=!BACKUP!"
echo Backed up %~1 to !BACKUP!
exit /b 0

:install_dir
set /a STEP+=1
set "TARGET_%STEP%=%~2"
set "KIND_%STEP%=dir"
fsutil reparsepoint query "%~2" >nul 2>&1 && (
  call :is_managed "%~2"
  if /I "!LINK_TARGET!"=="%~1" (
    echo Reusing link %~2
    exit /b 0
  )
  call :remove_if_managed "%~2" || exit /b 1
  if "%DRY_RUN%"=="1" (
    echo Would link %~2 to %~1
    exit /b 0
  )
  set /a STEP+=1
  set "TARGET_!STEP!=%~2"
  set "KIND_!STEP!=dir"
)
if exist "%~2" call :backup "%~2" "%~3" || exit /b 1
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
  if defined OLDLINK_%%I (
    if not exist "!TARGET_%%I!" (
      mklink /D "!TARGET_%%I!" "!OLDLINK_%%I!" >nul || set "ROLLBACK_FAILED=1"
    ) else (
      set "ROLLBACK_FAILED=1"
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
echo Usage: scripts\install.bat [--local] [--source PATH] [--claude-dir PATH] [--codex-dir PATH] [--replace] [--dry-run] [--uninstall]
echo Re-running is safe: managed links from a previous install are removed and recreated.
exit /b 0
