# Read-only GitHub monitor (Windows port of monitor.sh). Never starts Claude, never writes to GitHub.
# Usage: monitor.ps1 [--authorize ISSUE] [--clear-authorization] [--repo PATH] [--state-file PATH]
#                    [--limit N] [--scheduled] [--dry-run] [--error-log PATH] [--help]
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'apolo-common.ps1')

$repoDir = (Get-Location).ProviderPath
$stateFile = ''
$stateRoot = $env:XDG_STATE_HOME
if ($stateRoot) { $stateRoot = Join-Path $stateRoot 'apolo-sdlc' }
elseif ($env:LOCALAPPDATA) { $stateRoot = Join-Path (Join-Path $env:LOCALAPPDATA 'apolo-sdlc') 'state' }
else { $stateRoot = Join-Path (Join-Path (Join-Path $HOME '.local') 'state') 'apolo-sdlc' }
$limit = '30'; $maxLimit = 50; $dryRun = $false; $scheduled = $false
$authorizeIssue = ''; $clearAuthorization = $false; $script:errorLog = ''

function Fail([string]$Message) {
  Write-ErrorLine "Error: $Message"
  if ($script:errorLog) { try { Add-Utf8File $script:errorLog "Error: $Message`n" } catch { } }
  exit 1
}
function Say([string]$Text) { [Console]::Out.Write("$Text`n") }

$usage = @'
Usage: scripts/monitor.ps1 [options]

Options:
  --authorize ISSUE          Persist one explicitly authorized GitHub issue for this repository.
  --clear-authorization      Remove this repository's persisted authorized issue.
  --repo PATH                Repository to track.
  --state-file PATH          Authorization state file; it remains bound to --repo.
  --limit NUMBER             Read limit when no issue is authorized. Range: 1-50. Default: 30.
  --scheduled                Run the silent read-only scheduled check.
  --dry-run                  Inspect GitHub work without changing state.
  --error-log PATH           Also write errors to PATH (overwritten each run; used by the scheduled task).
  --help                     Show this help.
'@

for ($i = 0; $i -lt $args.Count; $i++) {
  $a = [string]$args[$i]
  $needsValue = @('--authorize', '--repo', '--state-file', '--limit', '--error-log') -contains $a
  if ($needsValue) {
    if ($i + 1 -ge $args.Count -or -not [string]$args[$i + 1]) { Fail "missing value for $a" }
    $v = [string]$args[$i + 1]; $i++
  }
  switch ($a) {
    '--authorize' { $authorizeIssue = $v }
    '--clear-authorization' { $clearAuthorization = $true }
    '--repo' { $repoDir = $v }
    '--state-file' { $stateFile = $v }
    '--limit' { $limit = $v }
    '--error-log' { $script:errorLog = $v; Write-Utf8File $v '' }
    '--dry-run' { $dryRun = $true }
    '--scheduled' { $scheduled = $true }
    '--help' { Say $usage; exit 0 }
    default { Fail "unknown option: $a" }
  }
}

if ($limit -notmatch '^[1-9][0-9]*$' -or [int]$limit -gt $maxLimit) { Fail "limit must be an integer from 1 to $maxLimit" }
if ($authorizeIssue -and $authorizeIssue -notmatch '^[1-9][0-9]*$') { Fail 'issue must be a positive integer' }
if ($authorizeIssue -and $clearAuthorization) { Fail 'authorize and clear cannot be used together' }
if (-not (Test-Path -LiteralPath (Join-Path $repoDir '.git'))) { Fail "repository is not a Git checkout: $repoDir" }
$git = Resolve-Tool 'git'; if (-not $git) { Fail 'git is required' }
$r = Invoke-Native $git @('-C', $repoDir, 'rev-parse', '--show-toplevel')
if ($r.ExitCode -ne 0) { Fail "repository is not a Git checkout: $repoDir" }
$repoDir = $r.Stdout.Trim()
$repoRemote = (Invoke-Native $git @('-C', $repoDir, 'config', '--get', 'remote.origin.url')).Stdout.Trim()
if (-not $repoRemote -or $repoRemote.Contains("`n") -or $repoRemote.Contains("`r")) { Fail 'repository must have a safe origin remote' }

if (-not $stateFile) { $stateFile = Join-Path $stateRoot ((Get-Sha256Hex "$repoDir`n$repoRemote") + '.state') }
if ($stateFile -eq '/' -or $stateFile -eq '.') { Fail 'unsafe state file' }
if (Test-IsLink $stateFile) { Fail "refusing symbolic-link state file: $stateFile" }
if ((Test-Path -LiteralPath $stateFile) -and -not (Test-Path -LiteralPath $stateFile -PathType Leaf)) { Fail "state path is not a regular file: $stateFile" }
$stateDir = Split-Path -Parent $stateFile

function Write-State([string]$Issue, [string]$Status) {
  New-Item -ItemType Directory -Force -Path $stateDir | Out-Null
  $tmp = "$stateFile.tmp.$PID"
  Write-Utf8File $tmp "version=1`nrepo=$repoDir`nremote=$repoRemote`nissue=$Issue`nstatus=$Status`n"
  Move-Item -LiteralPath $tmp -Destination $stateFile -Force
}

$state = @{}
function Read-State {
  if ((Test-IsLink $stateFile) -or -not (Test-Path -LiteralPath $stateFile -PathType Leaf)) { Fail "refusing unsafe authorization state: $stateFile" }
  $script:state = @{}
  foreach ($line in (Read-Lines $stateFile)) {
    if ($line -eq '') { continue }
    $key = $line.Split('=')[0]; $value = $line.Substring($key.Length + 1)
    if (@('version', 'repo', 'remote', 'issue', 'status') -notcontains $key) { Fail 'authorization state has an unsupported field' }
    if ($script:state.ContainsKey($key)) { Fail "authorization state has duplicate $key" }
    $script:state[$key] = $value
  }
  if ($script:state['version'] -ne '1' -or [string]$script:state['issue'] -notmatch '^[1-9][0-9]*$') { Fail 'authorization state is invalid' }
  if (@('authorized', 'completed') -notcontains $script:state['status']) { Fail 'authorization state has an invalid status' }
  if ($script:state['repo'] -ne $repoDir -or $script:state['remote'] -ne $repoRemote) { Fail 'authorization belongs to a different repository' }
}

function Get-Gh { $gh = Resolve-Tool 'gh'; if (-not $gh) { Fail 'gh CLI is required' }; return $gh }

if ($authorizeIssue) {
  if (Test-Path -LiteralPath $stateFile) {
    Read-State
    if ($state['issue'] -ne $authorizeIssue -or $state['status'] -ne 'authorized') { Fail "issue #$($state['issue']) is already recorded; clear it before authorizing another issue" }
  } else { Write-State $authorizeIssue 'authorized' }
  Say "Authorized issue #$authorizeIssue for $repoRemote"; exit 0
}
if ($clearAuthorization) {
  if (Test-Path -LiteralPath $stateFile) { Read-State; Remove-Item -LiteralPath $stateFile -Force }
  Say "Cleared authorization state for $repoRemote"; exit 0
}
if (-not (Test-Path -LiteralPath $stateFile)) {
  if ($scheduled) { exit 0 }
  $gh = Get-Gh
  foreach ($kind in @('issue', 'pr')) {
    $r = Invoke-Native $gh @($kind, 'list', '--state', 'open', '--limit', $limit, '--json', 'number,title,url') -WorkingDirectory $repoDir
    if ($r.ExitCode -ne 0) { Fail "gh $kind list failed: $($r.Stderr.Trim())" }
  }
  Say 'No authorized issue. Monitoring completed without starting Claude.'; exit 0
}
Read-State
if ($state['status'] -eq 'completed') { Say "Authorized issue #$($state['issue']) has already completed."; exit 0 }
$r = Invoke-Native (Get-Gh) @('issue', 'view', $state['issue'], '--json', 'state', '--jq', '.state') -WorkingDirectory $repoDir
if ($r.ExitCode -ne 0) { Fail "gh issue view failed: $($r.Stderr.Trim())" }
if ($r.Stdout.Trim() -ne 'OPEN') {
  Write-State $state['issue'] 'completed'
  Say "Authorized issue #$($state['issue']) is no longer open; marked completed."; exit 0
}
if ($dryRun) { Say "Authorized issue #$($state['issue']) is ready for interactive execution in $repoDir"; exit 0 }
Say "Authorized issue #$($state['issue']) is tracked and requires interactive execution."
exit 0
