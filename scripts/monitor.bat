@echo off
setlocal EnableExtensions EnableDelayedExpansion

set "REPO=%CD%"
set "STATE_FILE=%LOCALAPPDATA%\apolo-sdlc\authorized-issue"
set "CLAUDE_BIN=claude"
set "ALLOWED_TOOLS=Read,Glob,Grep,Edit,Write,Bash(git status *),Bash(git diff *),Bash(git branch *),Bash(git switch *),Bash(git add *),Bash(git commit *),Bash(git fetch *),Bash(git merge --ff-only *),Bash(git log *),Bash(git show *),Bash(git rev-parse *),Bash(git remote *),Bash(git ls-files *),Bash(gh issue list *),Bash(gh issue view *),Bash(gh pr list *),Bash(gh pr view *),Bash(gh pr checks *),Bash(npm *),Bash(pnpm *),Bash(yarn *),Bash(bun *),Bash(mvn *),Bash(gradle *),Bash(dotnet *),Bash(go *),Bash(pytest *)"
set "LIMIT=30"
set "MAX_LIMIT=50"
set "LOCK_TTL=3600"
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
if /I "%~1"=="--claude-bin" (
  if "%~2"=="" goto missing_value
  set "CLAUDE_BIN=%~2"
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
if /I "%~1"=="--lock-ttl" (
  if "%~2"=="" goto missing_value
  set "LOCK_TTL=%~2"
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
set "APOLO_NUMBER=!LOCK_TTL!"
powershell -NoProfile -Command "if ($env:APOLO_NUMBER -notmatch '^[1-9][0-9]*$') { exit 1 }" || goto invalid_lock_ttl
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
  echo Would invoke Claude for authorized issue #!STATE_ISSUE! in !REPO!
  exit /b 0
)

where "!CLAUDE_BIN!" >nul 2>&1 || (
  echo Error: Claude CLI is required: !CLAUDE_BIN! >&2
  exit /b 1
)
set "LOCK_DIR=!STATE_FILE!.lock"
if exist "!LOCK_DIR!" call :recover_lock || (
  echo Authorized issue #!STATE_ISSUE! is already running.
  exit /b 0
)
mkdir "!LOCK_DIR!" >nul 2>&1 || exit /b 1
for /f "usebackq delims=" %%I in (`powershell -NoProfile -Command "$PID"`) do set "LOCK_PID=%%I"
for /f "usebackq delims=" %%I in (`powershell -NoProfile -Command "[DateTimeOffset]::UtcNow.ToUnixTimeSeconds()"`) do set "LOCK_STARTED=%%I"
> "!LOCK_DIR!\owner" echo !LOCK_PID! !LOCK_STARTED!
pushd "!REPO!" || (
  rmdir "!LOCK_DIR!" >nul 2>&1
  exit /b 1
)
"!CLAUDE_BIN!" -p --permission-mode dontAsk --allowedTools "!ALLOWED_TOOLS!" "Run the authorized GitHub issue lifecycle for issue #!STATE_ISSUE! in this repository. Follow the installed sdlc-github-issue skill. Work only on this issue; do not advance another issue. Direct external writes and AWS access are unavailable in automatic mode."
set "RESULT=!ERRORLEVEL!"
popd
del "!LOCK_DIR!\owner" >nul 2>&1
rmdir "!LOCK_DIR!" >nul 2>&1
if not "!RESULT!"=="0" exit /b !RESULT!
call :write_state "!STATE_ISSUE!" completed || exit /b 1
echo Authorized issue #!STATE_ISSUE! completed.
exit /b 0

:invalid_issue
echo Error: issue must be a positive integer >&2
exit /b 1

:invalid_limit
echo Error: limit must be an integer from 1 to 50 >&2
exit /b 1

:invalid_lock_ttl
echo Error: lock TTL must be a positive integer >&2
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

:recover_lock
fsutil reparsepoint query "!LOCK_DIR!" >nul 2>&1 && exit /b 1
set "APOLO_LOCK_DIR=!LOCK_DIR!"
set "APOLO_LOCK_TTL=!LOCK_TTL!"
powershell -NoProfile -Command "$owner=Get-Content -LiteralPath (Join-Path $env:APOLO_LOCK_DIR 'owner') -ErrorAction SilentlyContinue; $parts=$owner -split ' '; $stale=$parts.Count -ne 2 -or -not ($parts[0] -as [int]) -or -not ($parts[1] -as [long]) -or ([DateTimeOffset]::UtcNow.ToUnixTimeSeconds()-[long]$parts[1] -gt [long]$env:APOLO_LOCK_TTL); $alive=if($stale){$false}else{Get-Process -Id ([int]$parts[0]) -ErrorAction SilentlyContinue}; if($stale -or -not $alive){Remove-Item -LiteralPath $env:APOLO_LOCK_DIR -Force; exit 0}; exit 1"
exit /b !ERRORLEVEL!

:usage
echo Usage: scripts\monitor.bat [--authorize ISSUE] [--clear-authorization] [--repo PATH] [--state-file PATH] [--claude-bin PATH] [--limit NUMBER] [--dry-run]
exit /b 0
