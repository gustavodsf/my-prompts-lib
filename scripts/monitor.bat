@echo off
setlocal EnableExtensions EnableDelayedExpansion

set "REPO=%CD%"
set "STATE_FILE=%LOCALAPPDATA%\apolo-sdlc\authorized-issue"
set "LIMIT=30"
set "MAX_LIMIT=50"
set "DRY_RUN=0"
set "AUTHORIZE_ISSUE="
set "CLEAR_AUTHORIZATION=0"
set "REPO_REMOTE="
set "STATE_ISSUE="
set "STATE_STATUS="
set "STATE_REPO="
set "STATE_REMOTE="

:parse
if "%~1"=="" goto parsed
if /I "%~1"=="--authorize" (
  if "%~2"=="" goto missing_value
  set "AUTHORIZE_ISSUE=%~2"
  shift
  shift
  goto parse
)
if /I "%~1"=="--clear-authorization" (
  set "CLEAR_AUTHORIZATION=1"
  shift
  goto parse
)
if /I "%~1"=="--repo" (
  if "%~2"=="" goto missing_value
  set "REPO=%~2"
  shift
  shift
  goto parse
)
if /I "%~1"=="--state-file" (
  if "%~2"=="" goto missing_value
  set "STATE_FILE=%~2"
  shift
  shift
  goto parse
)
if /I "%~1"=="--limit" (
  if "%~2"=="" goto missing_value
  set "LIMIT=%~2"
  shift
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
if not "!AUTHORIZE_ISSUE!"=="" if "!CLEAR_AUTHORIZATION!"=="1" goto incompatible_flags
set "APOLO_NUMBER=!LIMIT!"
powershell -NoProfile -Command "if ($env:APOLO_NUMBER -notmatch '^[1-9][0-9]*$') { exit 1 }" || goto invalid_limit
if !LIMIT! GTR !MAX_LIMIT! goto invalid_limit
if not "!AUTHORIZE_ISSUE!"=="" (
  set "APOLO_NUMBER=!AUTHORIZE_ISSUE!"
  powershell -NoProfile -Command "if ($env:APOLO_NUMBER -notmatch '^[1-9][0-9]*$') { exit 1 }" || goto invalid_issue
)
set "APOLO_PATH=!REPO!"
powershell -NoProfile -Command "if ([string]::IsNullOrWhiteSpace($env:APOLO_PATH) -or $env:APOLO_PATH -match '[&|<>^!]') { exit 1 }" || goto unsafe_path
set "APOLO_PATH=!STATE_FILE!"
powershell -NoProfile -Command "if ([string]::IsNullOrWhiteSpace($env:APOLO_PATH) -or $env:APOLO_PATH -match '[&|<>^!]') { exit 1 }" || goto unsafe_path

if not exist "!REPO!\.git" if not exist "!REPO!\.git\NUL" (
  echo Error: repository is not a Git checkout: !REPO! >&2
  exit /b 1
)
for %%I in ("!REPO!") do set "REPO=%%~fI"
for /f "usebackq delims=" %%I in (`git -C "!REPO!" rev-parse --show-toplevel 2^>nul`) do set "REPO=%%I"
for /f "usebackq delims=" %%I in (`git -C "!REPO!" config --get remote.origin.url 2^>nul`) do set "REPO_REMOTE=%%I"
if "!REPO_REMOTE!"=="" (
  echo Error: repository must have an origin remote >&2
  exit /b 1
)
for %%I in ("!STATE_FILE!") do set "STATE_FILE=%%~fI"
if exist "!STATE_FILE!\NUL" (
  echo Error: state path is not a regular file: !STATE_FILE! >&2
  exit /b 1
)
if exist "!STATE_FILE!" (
  fsutil reparsepoint query "!STATE_FILE!" >nul 2>&1 && (
    echo Error: refusing symbolic-link state file: !STATE_FILE! >&2
    exit /b 1
  )
)

if not "!AUTHORIZE_ISSUE!"=="" (
  if exist "!STATE_FILE!" (
    call :read_state || exit /b 1
    if not "!STATE_ISSUE!"=="!AUTHORIZE_ISSUE!" goto existing_authorization
    if not "!STATE_STATUS!"=="authorized" goto existing_authorization
  ) else (
    call :write_state "!AUTHORIZE_ISSUE!" authorized || exit /b 1
  )
  echo Authorized issue #!AUTHORIZE_ISSUE! for !REPO_REMOTE!
  exit /b 0
)

if "!CLEAR_AUTHORIZATION!"=="1" (
  if exist "!STATE_FILE!" (
    call :read_state || exit /b 1
    del "!STATE_FILE!" || (
      echo Error: could not clear authorization state >&2
      exit /b 1
    )
  )
  echo Cleared authorization state for !REPO_REMOTE!
  exit /b 0
)

where gh >nul 2>&1 || (
  echo Error: gh CLI is required >&2
  exit /b 1
)
if not exist "!STATE_FILE!" (
  pushd "!REPO!" || exit /b 1
  gh issue list --state open --limit !LIMIT! --json number,title,url >nul || (popd & exit /b 1)
  gh pr list --state open --limit !LIMIT! --json number,title,url >nul || (popd & exit /b 1)
  popd
  echo No authorized issue. Monitoring completed without starting Claude.
  exit /b 0
)

call :read_state || exit /b 1
if "!STATE_STATUS!"=="completed" (
  echo Authorized issue #!STATE_ISSUE! has already completed.
  exit /b 0
)
pushd "!REPO!" || exit /b 1
for /f "usebackq delims=" %%I in (`gh issue view !STATE_ISSUE! --json state --jq .state`) do set "ISSUE_STATE=%%I"
set "GH_RESULT=!ERRORLEVEL!"
popd
if not "!GH_RESULT!"=="0" exit /b 1
if /I not "!ISSUE_STATE!"=="OPEN" (
  call :write_state "!STATE_ISSUE!" completed || exit /b 1
  echo Authorized issue #!STATE_ISSUE! is no longer open; marked completed.
  exit /b 0
)
if "!DRY_RUN!"=="1" (
  echo Authorized issue #!STATE_ISSUE! is ready for interactive execution in !REPO!
  exit /b 0
)
echo Authorized issue #!STATE_ISSUE! is tracked and requires interactive execution.
exit /b 0

:invalid_issue
echo Error: issue must be a positive integer >&2
exit /b 1

:invalid_limit
echo Error: limit must be an integer from 1 to 50 >&2
exit /b 1

:incompatible_flags
echo Error: authorize and clear cannot be used together >&2
exit /b 1

:unsafe_path
echo Error: unsafe path option >&2
exit /b 1

:existing_authorization
echo Error: an authorization is already recorded; clear it before authorizing another issue >&2
exit /b 1

:write_state
for %%I in ("!STATE_FILE!") do mkdir "%%~dpI" >nul 2>&1
> "!STATE_FILE!" (
  echo version=1
  echo repo=!REPO!
  echo remote=!REPO_REMOTE!
  echo issue=%~1
  echo status=%~2
)
exit /b !ERRORLEVEL!

:read_state
set "STATE_VERSION="
set "STATE_REPO="
set "STATE_REMOTE="
set "STATE_ISSUE="
set "STATE_STATUS="
for /f "usebackq tokens=1,* delims==" %%A in ("!STATE_FILE!") do (
  if /I "%%A"=="version" set "STATE_VERSION=%%B"
  if /I "%%A"=="repo" set "STATE_REPO=%%B"
  if /I "%%A"=="remote" set "STATE_REMOTE=%%B"
  if /I "%%A"=="issue" set "STATE_ISSUE=%%B"
  if /I "%%A"=="status" set "STATE_STATUS=%%B"
)
if not "!STATE_VERSION!"=="1" exit /b 1
set "APOLO_NUMBER=!STATE_ISSUE!"
powershell -NoProfile -Command "if ($env:APOLO_NUMBER -notmatch '^[1-9][0-9]*$') { exit 1 }" || exit /b 1
if /I not "!STATE_STATUS!"=="authorized" if /I not "!STATE_STATUS!"=="completed" exit /b 1
if not "!STATE_REPO!"=="!REPO!" exit /b 1
if not "!STATE_REMOTE!"=="!REPO_REMOTE!" exit /b 1
exit /b 0

:usage
echo Usage: scripts\monitor.bat [--authorize ISSUE] [--clear-authorization] [--repo PATH] [--state-file PATH] [--limit NUMBER] [--dry-run]
exit /b 0
