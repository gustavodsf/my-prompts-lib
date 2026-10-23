@echo off
setlocal EnableExtensions EnableDelayedExpansion

set "REPO=%CD%"
set "STATE_FILE=%LOCALAPPDATA%\apolo-sdlc\authorized-issue"
set "CLAUDE_BIN=claude"
set "ALLOWED_TOOLS=Read,Glob,Grep,Edit,Write,Bash(git status *),Bash(git diff *),Bash(git branch *),Bash(git switch *),Bash(git add *),Bash(git commit *),Bash(git push *),Bash(git fetch *),Bash(git merge --ff-only *),Bash(git log *),Bash(git show *),Bash(git rev-parse *),Bash(git remote *),Bash(git ls-files *),Bash(gh issue list *),Bash(gh issue view *),Bash(gh issue comment *),Bash(gh pr list *),Bash(gh pr view *),Bash(gh pr checks *),Bash(gh pr create *),Bash(curl *),Bash(npm *),Bash(pnpm *),Bash(yarn *),Bash(bun *),Bash(mvn *),Bash(gradle *),Bash(dotnet *),Bash(go *),Bash(pytest *)"
set "LIMIT=30"
set "DRY_RUN=0"
set "AUTHORIZE_ISSUE="
set "CLEAR_AUTHORIZATION=0"

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
if exist "%STATE_FILE%" (
  fsutil reparsepoint query "%STATE_FILE%" >nul 2>&1 && (
    echo Error: refusing symbolic-link state file: %STATE_FILE% >&2
    exit /b 1
  )
)
if not "%AUTHORIZE_ISSUE%"=="" (
  echo %AUTHORIZE_ISSUE%| findstr /r "^[1-9][0-9]*$" >nul || goto invalid_issue
  if exist "%STATE_FILE%" (
    set /p CURRENT_ISSUE=<"%STATE_FILE%"
    if not "!CURRENT_ISSUE!"=="%AUTHORIZE_ISSUE%" (
      echo Error: issue !CURRENT_ISSUE! is already authorized; clear it before authorizing another issue >&2
      exit /b 1
    )
  ) else (
    for %%I in ("%STATE_FILE%") do mkdir "%%~dpI" >nul 2>&1
    > "%STATE_FILE%" echo %AUTHORIZE_ISSUE%
  )
  echo Authorized issue #%AUTHORIZE_ISSUE%
  exit /b 0
)

if "%CLEAR_AUTHORIZATION%"=="1" (
  if exist "%STATE_FILE%" del "%STATE_FILE%"
  echo Cleared authorization state
  exit /b 0
)

if not exist "%REPO%\.git" if not exist "%REPO%\.git\NUL" (
  echo Error: repository is not a Git checkout: %REPO% >&2
  exit /b 1
)
where gh >nul 2>&1 || (
  echo Error: gh CLI is required >&2
  exit /b 1
)
pushd "%REPO%" || exit /b 1

gh issue list --state open --limit %LIMIT% --json number,title,url >nul || (popd & exit /b 1)
gh pr list --state open --limit %LIMIT% --json number,title,url >nul || (popd & exit /b 1)

if not exist "%STATE_FILE%" (
  popd
  echo No authorized issue. Monitoring completed without starting Claude.
  exit /b 0
)
set /p ISSUE=<"%STATE_FILE%"
echo %ISSUE%| findstr /r "^[1-9][0-9]*$" >nul || (popd & goto invalid_state)
gh issue view %ISSUE% --json number,title,url >nul || (popd & exit /b 1)
popd

if "%DRY_RUN%"=="1" (
  echo Would invoke Claude for authorized issue #%ISSUE% in %REPO%
  exit /b 0
)

where "%CLAUDE_BIN%" >nul 2>&1 || (
  echo Error: Claude CLI is required: %CLAUDE_BIN% >&2
  exit /b 1
)
set "LOCK_DIR=%STATE_FILE%.lock"
mkdir "%LOCK_DIR%" >nul 2>&1 || (
  echo Authorized issue #%ISSUE% is already running.
  exit /b 0
)
pushd "%REPO%" || (
  rmdir "%LOCK_DIR%" >nul 2>&1
  exit /b 1
)
"%CLAUDE_BIN%" -p --permission-mode dontAsk --allowedTools "%ALLOWED_TOOLS%" "Run the authorized GitHub issue lifecycle for issue #%ISSUE% in this repository. Follow the installed sdlc-github-issue skill. Work only on this issue; do not advance another issue. GitHub writes are allowed only for this authorized issue and must be concise and sanitized. Do not access AWS unless necessary, and never create, update, delete, or mutate AWS resources."
set "RESULT=%ERRORLEVEL%"
popd
rmdir "%LOCK_DIR%" >nul 2>&1
exit /b %RESULT%

:invalid_issue
echo Error: issue must be a positive integer >&2
exit /b 1

:invalid_state
echo Error: authorization state must contain one positive issue number >&2
exit /b 1

:usage
echo Usage: scripts\monitor.bat [--authorize ISSUE] [--clear-authorization] [--repo PATH] [--state-file PATH] [--claude-bin PATH] [--limit NUMBER] [--dry-run]
exit /b 0
