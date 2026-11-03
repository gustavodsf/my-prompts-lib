# Runs one scheduled autonomous lane using project.conf beside this runner (Windows port of lane.sh).
# Usage: lane.ps1 issue|ci
# Task Scheduler starts it; errors also go to logs\<lane>-last-error.log (overwritten each run).
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'apolo-common.ps1')

$runnerDir = $PSScriptRoot
$configFile = Join-Path $runnerDir 'project.conf'
$promptKeys = @('repo', 'owner', 'checkout', 'worktrees', 'docs', 'state', 'evidence_branch')
$requiredKeys = $promptKeys + @('claude_bin', 'gh_bin', 'git_bin')
# `path` is Windows-only: Task Scheduler has no per-task PATH, so the installer records it here.
$optionalKeys = @('codex_bin', 'grok_bin', 'gemini_bin', 'timeout_seconds', 'max_turns', 'checkpoint_lines', 'path')
$script:errorLog = ''

function Fail([string]$Message) {
  Write-ErrorLine "Error: $Message"
  if ($script:errorLog) { try { Add-Utf8File $script:errorLog "Error: $Message`n" } catch { } }
  exit 1
}

if ($args.Count -ne 1) { Write-ErrorLine "Usage: lane.ps1 issue|ci`n`nRuns one scheduled autonomous lane using project.conf beside this runner."; exit 1 }
$lane = [string]$args[0]
if ($lane -ne 'issue' -and $lane -ne 'ci') { Fail "unknown lane: $lane" }
$logDir = Join-Path $runnerDir 'logs'
if (Test-Path -LiteralPath $logDir -PathType Container) {
  $script:errorLog = Join-Path $logDir "$lane-last-error.log"
  Write-Utf8File $script:errorLog ''
}

$conf = @{}
if (-not (Test-Path -LiteralPath $configFile -PathType Leaf) -or (Test-IsLink $configFile)) { Fail "missing or unsafe project.conf: $configFile" }
foreach ($line in (Read-Lines $configFile)) {
  if ($line -eq '') { continue }
  if (-not $line.Contains('=')) { Fail "malformed project.conf line: $line" }
  $key = $line.Substring(0, $line.IndexOf('='))
  $value = $line.Substring($line.IndexOf('=') + 1)
  if (($requiredKeys + $optionalKeys) -notcontains $key) { Fail "unsupported project.conf key: $key" }
  if ($conf.ContainsKey($key)) { Fail "duplicate project.conf key: $key" }
  # Values reach the prompt and process arguments, so reject anything a terminal could reinterpret.
  if (-not $value -or $value.Contains('%') -or $value -match '[^\x20-\x7E]') { Fail "unsafe project.conf value for $key" }
  $conf[$key] = $value
}
foreach ($key in $requiredKeys) { if (-not $conf.ContainsKey($key)) { Fail "project.conf is missing $key" } }
if (-not $conf.ContainsKey('timeout_seconds')) { $conf['timeout_seconds'] = '3600' }
if (-not $conf.ContainsKey('max_turns')) { $conf['max_turns'] = '150' }
if ($conf['timeout_seconds'] -notmatch '^[1-9][0-9]*$') { Fail "timeout_seconds must be a positive integer: $($conf['timeout_seconds'])" }
if ($conf['max_turns'] -notmatch '^[1-9][0-9]*$') { Fail "max_turns must be a positive integer: $($conf['max_turns'])" }
if ($conf.ContainsKey('checkpoint_lines') -and $conf['checkpoint_lines'] -notmatch '^[1-9][0-9]*$') { Fail "checkpoint_lines must be a positive integer: $($conf['checkpoint_lines'])" }

function Require-Tool([string]$Name) {
  $key = "${Name}_bin"
  if (-not $conf.ContainsKey($key)) { Fail "$Name is required but project.conf has no $key" }
  if (-not [System.IO.Path]::IsPathRooted($conf[$key])) { Fail "$key must be an absolute path: $($conf[$key])" }
  if (-not (Test-Path -LiteralPath $conf[$key] -PathType Leaf)) { Fail "$Name is required but was not found: $($conf[$key])" }
}
Require-Tool 'claude'; Require-Tool 'gh'; Require-Tool 'git'
foreach ($agent in @('grok', 'gemini')) { if ($conf.ContainsKey("${agent}_bin")) { Require-Tool $agent } }

# The agents table is validated before any agent runs; the ci lane's fixer is this claude session.
$agentsTable = Join-Path (Join-Path $runnerDir 'lanes') 'agents.yml'
foreach ($file in @($agentsTable, (Join-Path $runnerDir 'resolve-agents.ps1'), (Join-Path $runnerDir 'agent-run.ps1'))) {
  if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { Fail 'agents table or agent runner is missing beside lane.ps1 (reinstall the lanes)' }
}
$implementer = ''; if ($lane -eq 'ci') { $implementer = 'claude' }
try { $agents = Format-AgentTable (Resolve-AgentTable $agentsTable $configFile $implementer) } catch { Fail "invalid agents table: $($_.Exception.Message)" }

# The runner passes the token through the environment so the model never reads or types it.
$botToken = ''
$tokenFile = Join-Path $conf['state'] 'bot-token'
if (Test-PathOrLink $tokenFile) {
  if (-not (Test-Path -LiteralPath $tokenFile -PathType Leaf) -or (Test-IsLink $tokenFile)) { Fail "bot-token must be a regular file you own: $tokenFile" }
  if ($script:ApoloIsWindows) {
    $acl = Get-Acl -LiteralPath $tokenFile
    $me = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    foreach ($rule in $acl.Access) {
      if ($rule.AccessControlType -ne 'Allow') { continue }
      try { $sid = $rule.IdentityReference.Translate([System.Security.Principal.SecurityIdentifier]).Value } catch { $sid = '' }
      # The owner, SYSTEM and Administrators may read it; anyone else (Users, Everyone, ...) may not.
      if (@($me, 'S-1-5-18', 'S-1-5-32-544') -notcontains $sid) { Fail "bot-token must not be accessible by other users: $tokenFile" }
    }
  }
  $botToken = ([System.IO.File]::ReadAllText($tokenFile) -split "`r?`n")[0]
  if ($botToken -notmatch '^[A-Za-z0-9_]+$') { Fail "bot-token is malformed: $tokenFile" }
}

$promptFile = Join-Path (Join-Path $runnerDir 'lanes') "$lane.md"
$denyFile = Join-Path (Join-Path $runnerDir 'lanes') 'deny.json'
if (-not (Test-Path -LiteralPath $promptFile -PathType Leaf)) { Fail "lane prompt is missing: $promptFile" }
if (-not (Test-Path -LiteralPath $denyFile -PathType Leaf)) { Fail "deny rules are missing: $denyFile" }
if (-not (Test-Path -LiteralPath $conf['checkout'] -PathType Container)) { Fail "checkout is not a directory: $($conf['checkout'])" }

function Stamp { return (Get-Date).ToString('yyyy-MM-ddTHH:mm:sszzz') }
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$script:errorLog = Join-Path $logDir "$lane-last-error.log"
$laneLog = Join-Path $logDir "$lane.log"

# Creating a directory is atomic; a stale lock (dead pid) is taken over.
$lockDir = Join-Path $runnerDir 'lanes.lock'
function Get-Lock {
  try { New-Item -ItemType Directory -Path $lockDir -ErrorAction Stop | Out-Null; return $true } catch { }
  $holder = ''
  try { $holder = ([System.IO.File]::ReadAllText((Join-Path $lockDir 'pid'))).Trim() } catch { }
  if ($holder -match '^[0-9]+$' -and (Get-Process -Id ([int]$holder) -ErrorAction SilentlyContinue)) { return $false }
  Remove-Item -LiteralPath $lockDir -Recurse -Force -ErrorAction SilentlyContinue
  try { New-Item -ItemType Directory -Path $lockDir -ErrorAction Stop | Out-Null; return $true } catch { return $false }
}
if (-not (Get-Lock)) {
  $holder = 'unknown'; try { $holder = ([System.IO.File]::ReadAllText((Join-Path $lockDir 'pid'))).Trim() } catch { }
  Add-Utf8File $laneLog "=== $(Stamp) $lane lane skipped: lock held by pid $holder ===`n"
  exit 0
}
$status = 0
try {
  Write-Utf8File (Join-Path $lockDir 'pid') "$PID`n"
  New-Item -ItemType Directory -Force -Path $conf['state'] | Out-Null

  $childEnv = @{ APOLO_SDLC_LANE = $lane; APOLO_SDLC_AGENTS = $agents }
  if ($conf.ContainsKey('path')) { $childEnv['PATH'] = $conf['path'] }
  if ($botToken) { $childEnv['GH_TOKEN'] = $botToken }

  # A cheap summary of what the lane reacts to; an unchanged summary means Claude would only report "no changes".
  $fingerprint = $null
  if ($lane -eq 'issue') {
    $r = Invoke-Native $conf['gh_bin'] @('issue', 'list', '-R', $conf['repo'], '--author', $conf['owner'], '--state', 'open', '--limit', '100',
      '--json', 'number,updatedAt', '--jq', '.[] | "\(.number) \(.updatedAt)"') -Set $childEnv
    if ($r.ExitCode -eq 0) { $fingerprint = $r.Stdout }
  } else {
    $r = Invoke-Native $conf['gh_bin'] @('pr', 'list', '-R', $conf['repo'], '--state', 'open', '--limit', '100',
      '--json', 'number,updatedAt,headRefOid', '--jq', '.[] | "\(.number) \(.updatedAt) \(.headRefOid)"') -Set $childEnv
    if ($r.ExitCode -eq 0) {
      $r2 = Invoke-Native $conf['gh_bin'] @('run', 'list', '-R', $conf['repo'], '--limit', '20',
        '--json', 'databaseId,status,conclusion', '--jq', '.[] | "\(.databaseId) \(.status) \(.conclusion)"') -Set $childEnv
      if ($r2.ExitCode -eq 0) { $fingerprint = $r.Stdout + $r2.Stdout }
    }
  }
  $fingerprintFile = Join-Path $conf['state'] "$lane-fingerprint"
  if ($null -ne $fingerprint -and -not (Test-Path -LiteralPath (Join-Path $conf['state'] "$lane-busy")) -and
      (Test-Path -LiteralPath $fingerprintFile -PathType Leaf) -and ([System.IO.File]::ReadAllText($fingerprintFile) -eq $fingerprint)) {
    Add-Utf8File $laneLog "=== $(Stamp) $lane lane no changes (pre-check) ===`n"
    exit 0
  }

  $hostExe = Get-HostExecutable
  $runner = '"' + $hostExe + '" -NoProfile -ExecutionPolicy Bypass -File "' + (Join-Path $runnerDir 'agent-run.ps1') + '"'
  $prompt = "Lane mode: active`nlane: $lane`n"
  foreach ($key in $promptKeys) { $prompt += "${key}: $($conf[$key])`n" }
  $prompt += "agents: $(($agents -split "`n") -join ' ')`nagent_runner: $runner`n`n"
  $prompt += [System.IO.File]::ReadAllText($promptFile)
  $promptCopy = Join-Path $lockDir 'prompt'
  Write-Utf8File $promptCopy $prompt

  if ($lane -eq 'ci') { $childEnv['APOLO_SDLC_IMPLEMENTER'] = 'claude' }
  Add-Utf8File $laneLog "=== $(Stamp) $lane lane start ===`n"
  $r = Invoke-Native $conf['claude_bin'] @('-p', '--dangerously-skip-permissions', '--settings', $denyFile, '--max-turns', $conf['max_turns']) `
    -StdinFile $promptCopy -WorkingDirectory $conf['checkout'] -Set $childEnv -TimeoutSeconds ([int]$conf['timeout_seconds'])
  Add-Utf8File $laneLog ($r.Stdout + $r.Stderr)
  $status = $r.ExitCode
  if ($r.TimedOut) { Add-Utf8File $laneLog "=== $(Stamp) $lane lane timed out after $($conf['timeout_seconds'])s ===`n" }
  Add-Utf8File $laneLog "=== $(Stamp) $lane lane exit $status ===`n"
  # Recorded only after success, so a failed or interrupted run is retried even if GitHub did not change.
  if ($status -eq 0 -and $null -ne $fingerprint) { Write-Utf8File $fingerprintFile $fingerprint }
} finally {
  Remove-Item -LiteralPath $lockDir -Recurse -Force -ErrorAction SilentlyContinue
}
exit $status
