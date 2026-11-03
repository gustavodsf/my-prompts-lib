# Windows installer (PowerShell 5.1 / pwsh 7); same options and behavior as scripts/install.sh.
# Re-running is uninstall + install. --track schedules Task Scheduler tasks instead of cron.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'apolo-common.ps1')

$sourceDir = Split-Path -Parent $PSScriptRoot
$claudeDir = Join-Path $HOME '.claude'
$codexDir = Join-Path $HOME '.codex'
if ($env:APOLO_SDLC_DATA) { $dataRoot = $env:APOLO_SDLC_DATA }
elseif ($env:LOCALAPPDATA) { $dataRoot = Join-Path $env:LOCALAPPDATA 'apolo-sdlc' }
elseif ($env:XDG_DATA_HOME) { $dataRoot = Join-Path $env:XDG_DATA_HOME 'apolo-sdlc' }
else { $dataRoot = Join-Path (Join-Path (Join-Path $HOME '.local') 'share') 'apolo-sdlc' }
$trackRoot = Join-Path $dataRoot 'projects'
$runnerRoot = Join-Path $dataRoot 'runners'
$taskFolder = '\apolo-sdlc\'
if ($env:APOLO_SDLC_TASK_FOLDER) { $taskFolder = $env:APOLO_SDLC_TASK_FOLDER }
$gitBin = 'git'; if ($env:GIT_BIN) { $gitBin = $env:GIT_BIN }
$ghBin = 'gh'; if ($env:GH_BIN) { $ghBin = $env:GH_BIN }
$replace = $false; $dryRun = $false; $uninstall = $false; $localMode = $false
$trackUrl = ''; $lanes = ''; $checkout = ''; $owner = ''
$laneNames = @()

function Say([string]$Text) { [Console]::Out.Write("$Text`n") }
function Fail([string]$Message) { Write-ErrorLine "Error: $Message"; exit 1 }

$usage = @'
Usage: scripts/install.ps1 [--local | --track GITHUB_URL] [--uninstall] [options]
       (scripts\install.bat passes its arguments here)

Re-running is safe: links from a previous install (any clone of this library) are
removed and recreated, so no --replace is needed for them.

Options:
  --local             Link sdlc and the skills only (default).
  --track URL         Also clone the GitHub repository and schedule the read-only monitor (Task Scheduler).
  --lanes LIST        With --track: issue, ci or issue,ci autonomous lanes.
  --checkout PATH     With --lanes: the project's working checkout.
  --owner LOGIN       With --lanes: GitHub owner whose issues the lane serves (default: gh api user).
  --source PATH       Library clone to link from (default: this clone).
  --claude-dir PATH   Claude configuration directory (default: ~/.claude).
  --codex-dir PATH    Codex configuration directory (default: ~/.codex).
  --track-root PATH   Where tracked repositories are cloned.
  --runner-root PATH  Where private runner copies are installed.
  --git-bin PATH      git executable.
  --gh-bin PATH       gh executable.
  --replace           Back up existing real files or directories at managed targets
                      (managed links never need it).
  --uninstall         Remove the managed sdlc and skill links; with --track URL also
                      that project's runner and its scheduled tasks (the clone stays).
  --dry-run           Print planned actions without changing files.
  --help              Show this help.
'@

for ($i = 0; $i -lt $args.Count; $i++) {
  $a = [string]$args[$i]
  $valued = @('--source', '--track', '--claude-dir', '--codex-dir', '--track-root', '--runner-root', '--git-bin', '--gh-bin', '--lanes', '--checkout', '--owner', '--cron-bin')
  $v = ''
  if ($valued -contains $a) {
    if ($i + 1 -ge $args.Count -or -not [string]$args[$i + 1]) { Fail "missing value for $a" }
    $v = [string]$args[$i + 1]; $i++
  }
  switch ($a) {
    '--source' { $sourceDir = $v }
    '--local' { if ($trackUrl) { Fail '--local cannot be combined with --track' }; $localMode = $true }
    '--track' { if ($localMode -or $trackUrl) { Fail '--track cannot be combined with another mode' }; $trackUrl = $v }
    '--claude-dir' { $claudeDir = $v }
    '--codex-dir' { $codexDir = $v }
    '--track-root' { $trackRoot = $v }
    '--runner-root' { $runnerRoot = $v }
    '--git-bin' { $gitBin = $v }
    '--gh-bin' { $ghBin = $v }
    '--cron-bin' { Fail '--cron-bin does not apply on Windows; tasks use Task Scheduler' }
    '--lanes' { $lanes = $v }
    '--checkout' { $checkout = $v }
    '--owner' { $owner = $v }
    '--replace' { $replace = $true }
    '--dry-run' { $dryRun = $true }
    '--uninstall' { $uninstall = $true }
    '--help' { Say $usage; exit 0 }
    default { Fail "unknown option: $a" }
  }
}

function Get-FullPath([string]$Path) {
  if (-not [System.IO.Path]::IsPathRooted($Path)) { $Path = Join-Path (Get-Location).ProviderPath $Path }
  return [System.IO.Path]::GetFullPath($Path).TrimEnd('\', '/')
}
function Test-SamePath([string]$A, [string]$B) {
  if (-not $A -or -not $B) { return $false }
  $x = (Get-FullPath $A); $y = (Get-FullPath $B)
  if ($script:ApoloIsWindows) { return $x.Equals($y, [System.StringComparison]::OrdinalIgnoreCase) }
  return $x -ceq $y
}
function Test-Dir([string]$Path) { return Test-Path -LiteralPath $Path -PathType Container }

function Resolve-ConfigDir([string]$Path) {
  if (-not $Path) { Fail 'unsafe configuration directory' }
  $full = Get-FullPath $Path
  if ($full -match '^[A-Za-z]:$' -or $full -eq '' -or $full.StartsWith('\\')) { Fail 'unsafe configuration directory' }
  if (Test-IsLink $full) { Fail "configuration directory must not be a symbolic link: $Path" }
  if ((Test-Path -LiteralPath $full) -and -not (Test-Dir $full)) { Fail "configuration directory is not a directory: $Path" }
  return $full
}

$sourceDir = Get-FullPath $sourceDir
$claudeDir = Resolve-ConfigDir $claudeDir
$codexDir = Resolve-ConfigDir $codexDir
$trackRoot = Get-FullPath $trackRoot
$runnerRoot = Get-FullPath $runnerRoot

$trackOwner = ''; $trackRepository = ''
function Get-GitHubRepository([string]$Url, [bool]$AllowSsh) {
  $prefix = 'https://github\.com/'
  if ($AllowSsh) { $prefix = '(?:https://github\.com/|git@github\.com:|ssh://git@github\.com/)' }
  if ($Url.EndsWith('.git')) { $Url = $Url.Substring(0, $Url.Length - 4) }
  if ($Url -cmatch "^$prefix([A-Za-z0-9][A-Za-z0-9._-]*)/([A-Za-z0-9][A-Za-z0-9._-]*)$") { return "$($Matches[1])/$($Matches[2])" }
  return $null
}
if ($trackUrl) {
  $repository = Get-GitHubRepository $trackUrl $false
  if (-not $repository) { Fail "track URL must be an HTTPS GitHub repository URL: $trackUrl" }
  $trackOwner, $trackRepository = $repository.Split('/')
}
if (($lanes -or $checkout -or $owner) -and -not $trackUrl) { Fail '--lanes, --checkout and --owner require --track' }

$gitPath = Resolve-Tool $gitBin
function Invoke-Git([string[]]$GitArgs) {
  if (-not $script:gitPath) { throw "git was not found: $gitBin" }
  return Invoke-Native $script:gitPath $GitArgs
}
function Test-Origin([string]$RepositoryDir) {
  $r = Invoke-Git @('-C', $RepositoryDir, 'config', '--get', 'remote.origin.url')
  if ($r.ExitCode -ne 0) { return "tracked repository has no origin remote: $RepositoryDir" }
  $remote = Get-GitHubRepository $r.Stdout.Trim() $true
  if (-not $remote) { return "tracked repository origin is not a GitHub repository: $RepositoryDir" }
  if ($remote -ne "$trackOwner/$trackRepository") { return "tracked repository origin does not match requested URL: $RepositoryDir" }
  return ''
}

# --- lanes options ---
$lane = @{ claude = ''; gh = ''; git = ''; codex = ''; grok = ''; gemini = ''; path = '' }
if ($trackUrl -and $lanes -and -not $uninstall) {
  if ($lanes -notmatch '^(issue|ci)(,(issue|ci))?$') { Fail "unknown lane list (use issue, ci or issue,ci): $lanes" }
  $laneNames = @($lanes.Split(','))
  if ($laneNames.Count -eq 2 -and $laneNames[0] -eq $laneNames[1]) { Fail "repeated lane: $($laneNames[0])" }
  if (-not $checkout) { Fail '--lanes requires --checkout' }
  if (-not (Test-Dir $checkout) -or (Test-IsLink $checkout)) { Fail "checkout is not a directory: $checkout" }
  $checkout = Get-FullPath $checkout
  if (-not $gitPath) { Fail "git is required by the lanes but was not found: $gitBin" }
  if ((Invoke-Git @('-C', $checkout, 'rev-parse', '--is-inside-work-tree')).ExitCode -ne 0) { Fail "checkout is not a Git worktree: $checkout" }
  if (Test-Origin $checkout) { Fail "checkout origin does not match requested URL: $checkout" }
  foreach ($f in @('scripts/lane.ps1', 'scripts/agent-run.ps1', 'scripts/resolve-agents.ps1', 'scripts/apolo-common.ps1', 'sdlc/agents.yml', 'lanes/issue.md', 'lanes/ci.md', 'lanes/deny.json')) {
    if (-not (Test-Path -LiteralPath (Join-Path $sourceDir $f) -PathType Leaf)) { Fail "lane source file is missing: $(Join-Path $sourceDir $f)" }
  }
  if ($env:CHECKPOINT_LINES -and $env:CHECKPOINT_LINES -notmatch '^[1-9][0-9]*$') { Fail "CHECKPOINT_LINES must be a positive integer: $env:CHECKPOINT_LINES" }
  $lane.gh = Resolve-Tool $ghBin; if (-not $lane.gh) { Fail "gh is required by the lanes but was not found: $ghBin" }
  if (-not $owner) {
    $r = Invoke-Native $lane.gh @('api', 'user', '--jq', '.login')
    if ($r.ExitCode -ne 0) { Fail 'could not resolve the GitHub owner with gh; pass --owner' }
    $owner = $r.Stdout.Trim()
  }
  if ($owner -notmatch '^[A-Za-z0-9][A-Za-z0-9-]{0,38}$') { Fail "unsafe GitHub owner: $owner" }
  $claudeName = 'claude'; if ($env:CLAUDE_BIN) { $claudeName = $env:CLAUDE_BIN }
  $lane.claude = Resolve-Tool $claudeName; if (-not $lane.claude) { Fail "claude is required by the lanes but was not found: $claudeName" }
  $lane.git = $gitPath
  foreach ($agent in @('codex', 'grok', 'gemini')) {
    $name = $agent; $override = [Environment]::GetEnvironmentVariable(($agent.ToUpperInvariant() + '_BIN'))
    if ($override) { $name = $override }
    $found = Resolve-Tool $name
    if ($found) { $lane[$agent] = $found }
  }
  if ($laneNames -contains 'issue' -and -not $lane.codex) { Fail "codex is required by the issue lane but was not found: $(if ($env:CODEX_BIN) { $env:CODEX_BIN } else { 'codex' })" }
  $nodeName = 'node'; if ($env:NODE_BIN) { $nodeName = $env:NODE_BIN }
  $node = Resolve-Tool $nodeName
  # Task Scheduler gives no per-task PATH; tool directories first (npm shims need node), then the install-time PATH.
  $dirs = New-Object System.Collections.Generic.List[string]
  foreach ($tool in @($lane.claude, $lane.gh, $lane.git, $lane.codex, $lane.grok, $lane.gemini, $node)) {
    if (-not $tool) { continue }
    $d = Split-Path -Parent $tool
    if (-not ($dirs | Where-Object { Test-SamePath $_ $d })) { $dirs.Add($d) }
  }
  $lane.path = ((@($dirs) + @($env:PATH -split [System.IO.Path]::PathSeparator | Where-Object { $_ })) -join [System.IO.Path]::PathSeparator)
  foreach ($k in @('claude', 'gh', 'git', 'codex', 'grok', 'gemini', 'path')) {
    if ($lane[$k] -and ($lane[$k].Contains('%') -or $lane[$k] -match '[^\x20-\x7E]')) { Fail "path cannot be scheduled safely: $($lane[$k])" }
  }
  if ($checkout.Contains('%') -or $checkout -match '[^\x20-\x7E]') { Fail "path cannot be scheduled safely: $checkout" }
}

# --- managed links ---
# A managed link points at <clone>\sdlc or <clone>\skills\<same name> of a library clone (a directory
# with sdlc and skills), or dangles there after the clone moved. Nothing else is touched.
function Test-ManagedLink([string]$Target) {
  $dest = Get-LinkTarget $Target
  if (-not $dest) { return $false }
  $name = Split-Path -Leaf $Target
  $parentLeaf = Split-Path -Leaf (Split-Path -Parent $Target)
  if ((Split-Path -Leaf $dest) -ne $name) { return $false }
  if ($parentLeaf -eq 'skills') {
    $skillsDir = Split-Path -Parent $dest
    if ((Split-Path -Leaf $skillsDir) -ne 'skills') { return $false }
    $root = Split-Path -Parent $skillsDir
  } else {
    if ($name -ne 'sdlc') { return $false }
    $root = Split-Path -Parent $dest
  }
  if (-not (Test-Path -LiteralPath $dest)) { return $true }
  return (Test-Dir (Join-Path $root 'sdlc')) -and (Test-Dir (Join-Path $root 'skills'))
}

$removedLinks = New-Object System.Collections.Generic.List[object]
$createdTargets = New-Object System.Collections.Generic.List[string]
$backups = New-Object System.Collections.Generic.List[object]
$createdDirs = New-Object System.Collections.Generic.List[string]

function Remove-ManagedLink([string]$Target) {
  $dest = Get-LinkTarget $Target
  if ($dryRun) { Say "Would remove managed link $Target"; return }
  Remove-Link $Target
  $removedLinks.Add([pscustomobject]@{ Target = $Target; Dest = $dest })
  Say "Removed managed link $Target"
}

function Get-ManagedLinks([string]$Directory) {
  $found = @()
  if (Test-ManagedLink (Join-Path $Directory 'sdlc')) { $found += (Join-Path $Directory 'sdlc') }
  $skills = Join-Path $Directory 'skills'
  if ((Test-Dir $skills) -and -not (Test-IsLink $skills)) {
    foreach ($item in @(Get-ChildItem -LiteralPath $skills -Force -ErrorAction SilentlyContinue)) {
      if (Test-ManagedLink $item.FullName) { $found += $item.FullName }
    }
  }
  return ,$found
}

function New-DirectoryTree([string]$Directory) {
  $missing = @()
  while ($Directory -and -not (Test-PathOrLink $Directory)) { $missing = @($Directory) + $missing; $Directory = Split-Path -Parent $Directory }
  foreach ($d in $missing) { New-Item -ItemType Directory -Path $d | Out-Null; $createdDirs.Add($d) }
}

function Undo-Installation {
  $ok = $true
  for ($i = $createdTargets.Count - 1; $i -ge 0; $i--) { try { Remove-Link $createdTargets[$i] } catch { $ok = $false } }
  for ($i = $backups.Count - 1; $i -ge 0; $i--) {
    $b = $backups[$i]
    if (Test-PathOrLink $b.Target) { $ok = $false; continue }
    try { Move-Item -LiteralPath $b.Backup -Destination $b.Target } catch { $ok = $false }
  }
  for ($i = $removedLinks.Count - 1; $i -ge 0; $i--) {
    $l = $removedLinks[$i]
    if (Test-PathOrLink $l.Target) { $ok = $false; continue }
    try { [void](New-DirectoryLink $l.Target $l.Dest) } catch { $ok = $false }
  }
  for ($i = $createdDirs.Count - 1; $i -ge 0; $i--) {
    try { [System.IO.Directory]::Delete($createdDirs[$i], $false) } catch { $ok = $false }
  }
  return $ok
}

# --- scheduled tasks ---
function Get-TaskMarkers {
  return @("apolo-sdlc-track:$trackOwner/$trackRepository", "apolo-sdlc-lane:issue:$trackOwner/$trackRepository", "apolo-sdlc-lane:ci:$trackOwner/$trackRepository")
}
function Get-ProjectTasks {
  $markers = Get-TaskMarkers
  return @(Get-ScheduledTask -TaskPath $taskFolder -ErrorAction SilentlyContinue | Where-Object { $markers -contains $_.Description })
}
function Get-TaskName([string]$Kind) { return "apolo-sdlc-$Kind-$trackOwner-$trackRepository" }

function Register-ApoloTask([string]$Kind, [string]$Marker, [string]$Script, [string]$Arguments, [int]$Minute, [string]$WorkDir, [int]$LimitMinutes) {
  $hostExe = Get-HostExecutable
  $argument = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $Script + '" ' + $Arguments
  $action = New-ScheduledTaskAction -Execute $hostExe -Argument $argument -WorkingDirectory $WorkDir
  $trigger = New-ScheduledTaskTrigger -Once -At ((Get-Date).Date.AddMinutes($Minute)) -RepetitionInterval (New-TimeSpan -Minutes 15)
  $settings = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -StartWhenAvailable -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes $LimitMinutes)
  if ($script:ApoloIsWindows) { $user = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name } else { $user = [Environment]::UserName }
  # Interactive logon: runs while the user is signed in, so no password is stored.
  $principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Limited
  Register-ScheduledTask -TaskName (Get-TaskName $Kind) -TaskPath $taskFolder -Action $action -Trigger $trigger -Settings $settings `
    -Principal $principal -Description $Marker -Force | Out-Null
}

# Previous tasks are exported first so a failed registration restores them as they were.
function Set-ProjectTasks([string]$RepositoryDir, [string]$RunnerDir) {
  $previous = @()
  foreach ($t in (Get-ProjectTasks)) {
    $previous += [pscustomobject]@{ Name = $t.TaskName; Xml = (Export-ScheduledTask -TaskName $t.TaskName -TaskPath $taskFolder) }
  }
  foreach ($t in $previous) { Unregister-ScheduledTask -TaskName $t.Name -TaskPath $taskFolder -Confirm:$false }
  $registered = @()
  try {
    $registered += (Get-TaskName 'track')
    Register-ApoloTask 'track' "apolo-sdlc-track:$trackOwner/$trackRepository" (Join-Path $RunnerDir 'monitor.ps1') `
      ('--scheduled --repo "' + $RepositoryDir + '" --error-log "' + (Join-Path $RunnerDir 'last-error.log') + '"') 0 $RunnerDir 10
    foreach ($name in $laneNames) {
      $minute = 0; if ($name -eq 'ci') { $minute = 7 }
      $registered += (Get-TaskName "lane-$name")
      Register-ApoloTask "lane-$name" "apolo-sdlc-lane:${name}:$trackOwner/$trackRepository" (Join-Path $RunnerDir 'lane.ps1') $name $minute $RunnerDir 120
    }
  } catch {
    $message = $_.Exception.Message
    foreach ($n in $registered) { Unregister-ScheduledTask -TaskName $n -TaskPath $taskFolder -Confirm:$false -ErrorAction SilentlyContinue }
    foreach ($t in $previous) { Register-ScheduledTask -TaskName $t.Name -TaskPath $taskFolder -Xml $t.Xml -Force | Out-Null }
    throw "could not register scheduled tasks: $message"
  }
}

# --- uninstall ---
if ($uninstall) {
  foreach ($link in @((Get-ManagedLinks $claudeDir) + (Get-ManagedLinks $codexDir))) {
    try { Remove-ManagedLink $link } catch { Fail "could not remove managed link: $link" }
  }
  if ($trackUrl) {
    $projectRunner = Join-Path (Join-Path $runnerRoot $trackOwner) $trackRepository
    if ($dryRun) {
      Say "Would remove runner $projectRunner and its scheduled tasks"
    } else {
      if ((Test-Dir $projectRunner) -and -not (Test-IsLink $projectRunner)) {
        Remove-Item -LiteralPath $projectRunner -Recurse -Force
        Say "Removed runner $projectRunner"
      }
      foreach ($t in (Get-ProjectTasks)) { Unregister-ScheduledTask -TaskName $t.TaskName -TaskPath $taskFolder -Confirm:$false }
      Say "Removed scheduled tasks for $trackOwner/$trackRepository (clone kept)"
    }
  }
  Say 'Uninstall complete'
  exit 0
}

# --- local install ---
if (-not (Test-Dir (Join-Path $sourceDir 'sdlc'))) { Fail "managed source does not exist: $(Join-Path $sourceDir 'sdlc')" }
$skillNames = @(Get-ChildItem -LiteralPath (Join-Path $sourceDir 'skills') -Directory | Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'SKILL.md') } | ForEach-Object { $_.Name } | Sort-Object)
if ($skillNames.Count -eq 0) { Fail "no skills found in $(Join-Path $sourceDir 'skills')" }

$targets = @()
foreach ($directory in @($claudeDir, $codexDir)) {
  $skills = Join-Path $directory 'skills'; $backupDir = Join-Path $directory 'skills-backup'
  # A whole-directory link from older installs would place per-skill links inside the source clone.
  if (Test-IsLink $skills) { Fail "skills directory is a symbolic link from an older install; remove it and rerun: $skills" }
  if ((Test-Path -LiteralPath $skills) -and -not (Test-Dir $skills)) { Fail "skills path is not a directory: $skills" }
  if (Test-IsLink $backupDir) { Fail "skills-backup directory must not be a symbolic link: $backupDir" }
  if ((Test-Path -LiteralPath $backupDir) -and -not (Test-Dir $backupDir)) { Fail "skills-backup path is not a directory: $backupDir" }
  $targets += [pscustomobject]@{ Target = (Join-Path $directory 'sdlc'); Source = (Join-Path $sourceDir 'sdlc') }
  foreach ($name in $skillNames) {
    $targets += [pscustomobject]@{ Target = (Join-Path $skills $name); Source = (Join-Path (Join-Path $sourceDir 'skills') $name) }
  }
}
foreach ($t in $targets) {
  if (Test-IsLink $t.Target) {
    if (-not (Test-ManagedLink $t.Target)) { Fail "refusing to replace unmanaged symbolic link: $($t.Target)" }
    continue
  }
  if ((Test-Path -LiteralPath $t.Target) -and -not $replace) { Fail "managed target exists; rerun with --replace: $($t.Target)" }
}

function Exit-RolledBack([string]$Message) {
  if (-not (Undo-Installation)) { Fail "$Message and rollback was incomplete" }
  Fail $Message
}

foreach ($directory in @((Join-Path $claudeDir 'skills'), (Join-Path $codexDir 'skills'))) {
  if ($dryRun) { if (-not (Test-Dir $directory)) { Say "Would create directory $directory" } }
  else { try { New-DirectoryTree $directory } catch { Exit-RolledBack "could not create configuration directory: $directory" } }
}

# Uninstall the previous install first: stale managed skill links (renamed or removed skills) go too.
foreach ($directory in @($claudeDir, $codexDir)) {
  foreach ($link in (Get-ManagedLinks $directory)) {
    $relative = $link.Substring($directory.Length).TrimStart('\', '/')
    if (Test-SamePath (Get-LinkTarget $link) (Join-Path $sourceDir $relative)) { continue }
    try { Remove-ManagedLink $link } catch { Exit-RolledBack "could not remove previous managed link: $link" }
  }
}

foreach ($t in $targets) {
  if ((Test-IsLink $t.Target) -and (Test-SamePath (Get-LinkTarget $t.Target) $t.Source)) { Say "Reusing link $($t.Target)"; continue }
  if (Test-Path -LiteralPath $t.Target) {
    # Skill backups go to a sibling skills-backup directory because a copy left in skills loads as a duplicate skill.
    $parent = Split-Path -Parent $t.Target
    $base = $t.Target
    if ((Split-Path -Leaf $parent) -eq 'skills') { $base = Join-Path (Join-Path (Split-Path -Parent $parent) 'skills-backup') (Split-Path -Leaf $t.Target) }
    $stamp = (Get-Date).ToString('yyyyMMdd-HHmmss')
    $backup = "$base-old-$stamp"; $suffix = 0
    while (Test-PathOrLink $backup) { $suffix++; $backup = "$base-old-$stamp-$suffix" }
    if ($dryRun) { Say "Would back up $($t.Target) to $backup" }
    else {
      try {
        New-DirectoryTree (Split-Path -Parent $backup)
        Move-Item -LiteralPath $t.Target -Destination $backup
      } catch { Exit-RolledBack "could not back up managed target: $($t.Target)" }
      $backups.Add([pscustomobject]@{ Target = $t.Target; Backup = $backup })
      Say "Backed up $($t.Target) to $backup"
    }
  }
  if ($dryRun) { Say "Would link $($t.Target) to $($t.Source)"; continue }
  try { $kind = New-DirectoryLink $t.Target $t.Source } catch { Exit-RolledBack "could not link managed target: $($t.Target)" }
  $createdTargets.Add($t.Target)
  Say "Linked $($t.Target) to $($t.Source) ($kind)"
}

if (-not $trackUrl) { exit 0 }

# --- tracking ---
$trackCreated = New-Object System.Collections.Generic.List[string]   # removed on rollback (deepest last)
$runnerBackup = ''
$runnerEntries = @('monitor.ps1', 'apolo-common.ps1', 'lane.ps1', 'agent-run.ps1', 'resolve-agents.ps1', 'lanes', 'project.conf')
$repositoryDir = Join-Path (Join-Path $trackRoot $trackOwner) $trackRepository
$runnerDir = Join-Path (Join-Path $runnerRoot $trackOwner) $trackRepository

function New-TrackTree([string]$Directory) {
  $missing = @()
  while ($Directory -and -not (Test-PathOrLink $Directory)) { $missing = @($Directory) + $missing; $Directory = Split-Path -Parent $Directory }
  foreach ($d in $missing) { New-Item -ItemType Directory -Path $d | Out-Null; $trackCreated.Add($d) }
}

function Undo-Tracking {
  $ok = $true
  if ($script:runnerBackup) {
    foreach ($entry in $runnerEntries) {
      $saved = Join-Path $script:runnerBackup $entry
      $live = Join-Path $runnerDir $entry
      try {
        if (Test-PathOrLink $live) { Remove-Item -LiteralPath $live -Recurse -Force }
        if (Test-Path -LiteralPath $saved) { Move-Item -LiteralPath $saved -Destination $live }
      } catch { $ok = $false }
    }
    Remove-Item -LiteralPath $script:runnerBackup -Recurse -Force -ErrorAction SilentlyContinue
  }
  for ($i = $trackCreated.Count - 1; $i -ge 0; $i--) {
    try { if (Test-PathOrLink $trackCreated[$i]) { Remove-Item -LiteralPath $trackCreated[$i] -Recurse -Force } } catch { $ok = $false }
  }
  return $ok
}

function ConvertTo-ClaudePath([string]$Path) {
  # Claude Code matches Windows paths in POSIX form: C:\Users\me -> /c/Users/me ("//" prefix = absolute).
  if ($Path -match '^([A-Za-z]):[\\/](.*)$') { return '/' + $Matches[1].ToLowerInvariant() + '/' + ($Matches[2] -replace '\\', '/') }
  return ($Path -replace '\\', '/')
}

function Get-RunnerDenies([string]$Dir) {
  $posix = ConvertTo-ClaudePath $Dir
  $rules = @()
  foreach ($f in @('lane.ps1', 'lanes/**', 'project.conf', 'agent-run.ps1', 'resolve-agents.ps1', 'apolo-common.ps1', 'monitor.ps1')) {
    $rules += "Edit(/$posix/$f)"; $rules += "Write(/$posix/$f)"
  }
  foreach ($form in (@($Dir, ($Dir -replace '\\', '/'), $posix) | Select-Object -Unique)) {
    $sep = '/'; if ($form.Contains('\')) { $sep = '\' }
    foreach ($f in @('lanes', 'lane.ps1', 'project.conf')) { $rules += "Bash(*$form$sep$f*)" }
  }
  $escaped = (@($rules | Select-Object -Unique) | ForEach-Object { '"' + ($_ -replace '\\', '\\' -replace '"', '\"') + '",' }) -join ''
  $json = [System.IO.File]::ReadAllText((Join-Path (Join-Path $sourceDir 'lanes') 'deny.json'))
  $m = [regex]::Match($json, '"deny"\s*:\s*\[')
  if (-not $m.Success) { throw 'lanes/deny.json has no deny list' }
  return $json.Insert($m.Index + $m.Length, $escaped)
}

function Get-LaneConfig {
  $projectDir = Split-Path -Parent $checkout
  $lines = @("repo=$trackOwner/$trackRepository", "owner=$owner", "checkout=$checkout", "worktrees=$(Join-Path $projectDir 'worktrees')",
    "docs=$(Join-Path $projectDir 'docs')", "state=$(Join-Path $runnerDir 'state')", 'evidence_branch=qa-evidence',
    "claude_bin=$($lane.claude)", "gh_bin=$($lane.gh)", "git_bin=$($lane.git)")
  foreach ($agent in @('codex', 'grok', 'gemini')) { if ($lane[$agent]) { $lines += "${agent}_bin=$($lane[$agent])" } }
  if ($env:CHECKPOINT_LINES) { $lines += "checkpoint_lines=$env:CHECKPOINT_LINES" }
  $lines += "path=$($lane.path)"
  return ($lines -join "`n") + "`n"
}

function Install-Tracking {
  # Clone or verify the tracked repository.
  if (Test-PathOrLink $repositoryDir) {
    if (-not (Test-Dir $repositoryDir) -or (Test-IsLink $repositoryDir)) { throw "tracked repository path is not a directory: $repositoryDir" }
    if ((Invoke-Git @('-C', $repositoryDir, 'rev-parse', '--is-inside-work-tree')).ExitCode -ne 0) { throw "tracked repository is not a Git worktree: $repositoryDir" }
    $problem = Test-Origin $repositoryDir; if ($problem) { throw $problem }
  } elseif ($dryRun) {
    Say "Would clone $trackUrl to $repositoryDir"
  } else {
    New-TrackTree (Split-Path -Parent $repositoryDir)
    $trackCreated.Add($repositoryDir)
    $r = Invoke-Git @('clone', '--depth', '1', $trackUrl, $repositoryDir)
    if ($r.ExitCode -ne 0) { throw "could not clone tracked repository: $trackUrl" }
    Say "Cloned $trackUrl to $repositoryDir"
    $problem = Test-Origin $repositoryDir; if ($problem) { throw $problem }
  }

  if ($dryRun) {
    Say "Would install managed monitor runner at $(Join-Path $runnerDir 'monitor.ps1')"
    Say "Would add or update 15-minute read-only monitor task for $trackOwner/$trackRepository"
    if ($laneNames.Count -gt 0) {
      Say "Would install lane runner at $(Join-Path $runnerDir 'lane.ps1')"
      Say "Would write lane configuration $(Join-Path $runnerDir 'project.conf') for owner $owner and checkout $checkout"
      foreach ($name in $laneNames) { Say "Would schedule $name lane for $trackOwner/$trackRepository" }
    }
    return
  }

  # Private runner copies: later changes to the library clone need a supervised reinstall.
  if ((Test-IsLink $runnerDir) -or ((Test-Path -LiteralPath $runnerDir) -and -not (Test-Dir $runnerDir))) { throw "runner directory must be a real directory: $runnerDir" }
  New-TrackTree $runnerDir
  foreach ($entry in $runnerEntries + @('state', 'logs')) {
    if (Test-IsLink (Join-Path $runnerDir $entry)) { throw "runner path must not be a symbolic link: $(Join-Path $runnerDir $entry)" }
  }
  $monitorPath = Join-Path $runnerDir 'monitor.ps1'
  if ((Test-Path -LiteralPath $monitorPath) -and -not (Test-Path -LiteralPath $monitorPath -PathType Leaf)) { throw "runner path is not a regular file: $monitorPath" }
  $script:runnerBackup = Join-Path $runnerDir ('.previous-' + [guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Path $script:runnerBackup | Out-Null
  $staging = Join-Path $runnerDir ('.staged-' + [guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Path $staging | Out-Null
  try {
    $stagedEntries = @('monitor.ps1', 'apolo-common.ps1')
    Copy-Item -LiteralPath (Join-Path $sourceDir 'scripts/monitor.ps1') -Destination (Join-Path $staging 'monitor.ps1')
    Copy-Item -LiteralPath (Join-Path $sourceDir 'scripts/apolo-common.ps1') -Destination (Join-Path $staging 'apolo-common.ps1')
    if ($laneNames.Count -gt 0) {
      foreach ($f in @('lane.ps1', 'agent-run.ps1', 'resolve-agents.ps1')) { Copy-Item -LiteralPath (Join-Path (Join-Path $sourceDir 'scripts') $f) -Destination (Join-Path $staging $f) }
      $stagedLanes = Join-Path $staging 'lanes'
      New-Item -ItemType Directory -Path $stagedLanes | Out-Null
      Copy-Item -LiteralPath (Join-Path (Join-Path $sourceDir 'lanes') 'issue.md') -Destination $stagedLanes
      Copy-Item -LiteralPath (Join-Path (Join-Path $sourceDir 'lanes') 'ci.md') -Destination $stagedLanes
      Copy-Item -LiteralPath (Join-Path (Join-Path $sourceDir 'sdlc') 'agents.yml') -Destination $stagedLanes
      $deny = Get-RunnerDenies $runnerDir
      if (-not $deny.Contains("Edit(/$(ConvertTo-ClaudePath $runnerDir)/lane.ps1)")) { throw "could not render lane deny rules for $runnerDir" }
      Write-Utf8File (Join-Path $stagedLanes 'deny.json') $deny
      Write-Utf8File (Join-Path $staging 'project.conf') (Get-LaneConfig)
      # A ci-only install has no implement phase; its fixer is the lane's claude session.
      $impl = ''; if ($laneNames -notcontains 'issue') { $impl = 'claude' }
      try { [void](Resolve-AgentTable (Join-Path $stagedLanes 'agents.yml') (Join-Path $staging 'project.conf') $impl) }
      catch { throw "agents table is not runnable with the detected tools (see sdlc/agents.yml): $($_.Exception.Message)" }
      $stagedEntries += @('lane.ps1', 'agent-run.ps1', 'resolve-agents.ps1', 'lanes', 'project.conf')
    }
    foreach ($entry in $stagedEntries) {
      $live = Join-Path $runnerDir $entry
      if (Test-Path -LiteralPath $live) { Move-Item -LiteralPath $live -Destination (Join-Path $script:runnerBackup $entry) }
      Move-Item -LiteralPath (Join-Path $staging $entry) -Destination $live
    }
  } finally {
    Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue
  }
  Say "Installed managed monitor runner at $monitorPath"
  if ($laneNames.Count -gt 0) {
    foreach ($d in @((Join-Path $runnerDir 'state'), (Join-Path $runnerDir 'logs'), (Join-Path (Split-Path -Parent $checkout) 'worktrees'), (Join-Path (Split-Path -Parent $checkout) 'docs'))) {
      if (-not (Test-PathOrLink $d)) { New-Item -ItemType Directory -Path $d | Out-Null; $trackCreated.Add($d) }
    }
    Say "Installed lane runner, prompts and configuration in $runnerDir"
  }

  Set-ProjectTasks $repositoryDir $runnerDir
  Remove-Item -LiteralPath $script:runnerBackup -Recurse -Force -ErrorAction SilentlyContinue
  $script:runnerBackup = ''
  Say "Scheduled 15-minute read-only monitor for $trackOwner/$trackRepository"
  foreach ($name in $laneNames) { Say "Scheduled $name lane for $trackOwner/$trackRepository" }
}

try {
  Install-Tracking
} catch {
  $message = $_.Exception.Message
  $ok = Undo-Tracking
  if (-not (Undo-Installation)) { $ok = $false }
  if (-not $ok) { Fail "tracking setup failed and rollback was incomplete: $message" }
  Fail "tracking setup failed and local configuration was rolled back: $message"
}
exit 0
