# Mirrors tests/install.sh for scripts/install.ps1 (Task Scheduler cmdlets mocked by mocks.ps1).
. (Join-Path $PSScriptRoot 'helpers.ps1')
$Launcher = Join-Path $PSScriptRoot 'with-mocks.ps1'
$Url = 'https://github.com/acme/widget'
$Skills = @(Get-ChildItem -LiteralPath (Join-Path $RepoRoot 'skills') -Directory | ForEach-Object { $_.Name })

function New-Env {
  $root = New-TestRoot 'install'
  $bin = Join-Path $root 'fake bin'
  $realGit = Get-RealGit
  New-Fake $bin 'git' @"
`$real = '$realGit'
if (`$args[0] -eq 'clone') {
  if (`$env:FAKE_CLONE_FAIL) { [Console]::Error.WriteLine('fatal: clone failed'); exit 128 }
  `$dir = `$args[`$args.Count - 1]; `$url = `$args[`$args.Count - 2]
  & `$real init -q `$dir; & `$real -C `$dir remote add origin `$url; exit `$LASTEXITCODE
}
& `$real @args; exit `$LASTEXITCODE
"@ | Out-Null
  New-Fake $bin 'gh' "if (`$args[0] -eq 'api') { 'botuser'; exit 0 }; exit 0" | Out-Null
  foreach ($a in 'claude', 'codex', 'grok') { New-Fake $bin $a 'exit 0' | Out-Null }
  $checkout = Join-Path $root 'work tree'
  & $realGit init -q $checkout; & $realGit -C $checkout remote add origin "$Url.git"
  return [pscustomobject]@{
    Root = $root; Bin = $bin; Claude = (Join-Path $root 'claude home'); Codex = (Join-Path $root 'codex home')
    Tracks = (Join-Path $root 'tracked repos'); Data = (Join-Path $root 'data dir'); Tasks = (Join-Path $root 'tasks.json'); Checkout = $checkout
  }
}

function Install([object]$E, [string[]]$Arguments, [hashtable]$Extra = @{}) {
  $set = @{ PATH = ($E.Bin + $Sep + (Get-BasePath)); APOLO_TEST_TASKS = $E.Tasks; APOLO_SDLC_DATA = $E.Data; APOLO_SDLC_TASK_FOLDER = '\apolo-sdlc-test\' }
  foreach ($k in $Extra.Keys) { $set[$k] = $Extra[$k] }
  $all = @('--claude-dir', $E.Claude, '--codex-dir', $E.Codex, '--track-root', $E.Tracks) + $Arguments
  return Invoke-Script $Launcher $all -Set $set -Unset @('GH_TOKEN', 'GITHUB_TOKEN', 'CHECKPOINT_LINES')
}

function Get-Tasks([object]$E) {
  if (-not (Test-Path -LiteralPath $E.Tasks)) { return @() }
  $text = [IO.File]::ReadAllText($E.Tasks); if (-not $text.Trim()) { return @() }
  return @($text | ConvertFrom-Json)
}

function Assert-Linked([object]$E) {
  foreach ($base in $E.Claude, $E.Codex) {
    $sdlc = Join-Path $base 'sdlc'
    Assert-True (Test-IsLink $sdlc) "$sdlc is not a link"
    Assert-True (Test-SameTarget (Get-LinkTarget $sdlc) (Join-Path $RepoRoot 'sdlc')) "$sdlc points elsewhere"
    foreach ($s in $Skills) {
      $p = Join-Path (Join-Path $base 'skills') $s
      Assert-True (Test-IsLink $p) "$p is not a link"
      Assert-True (Test-Path -LiteralPath (Join-Path $p 'SKILL.md')) "$p does not resolve to the skill"
    }
  }
}
function Test-SameTarget($a, $b) { return ([IO.Path]::GetFullPath($a).TrimEnd('\', '/')) -eq ([IO.Path]::GetFullPath($b).TrimEnd('\', '/')) }

Invoke-TestBlock 'local install links sdlc and every skill (paths with spaces)' {
  $e = New-Env; $r = Install $e @()
  Assert-True ($r.ExitCode -eq 0) "install failed: $($r.Output)"
  Assert-Linked $e
  if ($env:APOLO_SDLC_NO_SYMLINK -eq '1' -and $ApoloIsWindows) {
    Assert-True ((Get-Item -LiteralPath (Join-Path $e.Claude 'sdlc')).LinkType -eq 'Junction') 'expected a junction'
  }
}

Invoke-TestBlock 'reinstall twice is idempotent and keeps unmanaged skills' {
  $e = New-Env
  $own = Join-Path (Join-Path $e.Claude 'skills') 'my-own-skill'
  New-Item -ItemType Directory -Force -Path $own | Out-Null; Write-Utf8File (Join-Path $own 'SKILL.md') 'mine'
  foreach ($i in 1..3) { $r = Install $e @(); Assert-True ($r.ExitCode -eq 0) "run $i failed: $($r.Output)" }
  Assert-Contains $r.Output 'Reusing link' 'second run should reuse links'
  Assert-Linked $e
  Assert-True ([IO.File]::ReadAllText((Join-Path $own 'SKILL.md')) -eq 'mine') 'unmanaged skill changed'
}

Invoke-TestBlock 'links from another library clone and dangling ones are replaced; foreign links refused' {
  $e = New-Env
  $other = Join-Path $e.Root 'other clone'
  New-Item -ItemType Directory -Force -Path (Join-Path $other 'sdlc'), (Join-Path (Join-Path $other 'skills') 'sdlc-qa') | Out-Null
  New-Item -ItemType Directory -Force -Path (Join-Path $e.Claude 'skills') | Out-Null
  New-DirectoryLink (Join-Path $e.Claude 'sdlc') (Join-Path $other 'sdlc') | Out-Null
  New-DirectoryLink (Join-Path (Join-Path $e.Claude 'skills') 'sdlc-qa') (Join-Path (Join-Path $other 'skills') 'sdlc-qa') | Out-Null
  $gone = Join-Path $e.Root 'gone clone'
  New-Item -ItemType Directory -Force -Path (Join-Path $gone 'sdlc'), (Join-Path (Join-Path $gone 'skills') 'sdlc-pr') | Out-Null
  New-DirectoryLink (Join-Path (Join-Path $e.Claude 'skills') 'sdlc-pr') (Join-Path (Join-Path $gone 'skills') 'sdlc-pr') | Out-Null
  [IO.Directory]::Delete($gone, $true)
  $r = Install $e @(); Assert-True ($r.ExitCode -eq 0) "install failed: $($r.Output)"
  Assert-Linked $e
  Assert-True (Test-Path -LiteralPath (Join-Path (Join-Path $other 'skills') 'sdlc-qa')) 'other clone content was deleted'

  $foreign = Join-Path $e.Root 'foreign'; New-Item -ItemType Directory -Force -Path $foreign | Out-Null
  $t = Join-Path $e.Codex 'sdlc'; Remove-Link $t; New-DirectoryLink $t $foreign | Out-Null
  $r = Install $e @('--replace')
  Assert-True ($r.ExitCode -ne 0) 'a foreign link must be refused even with --replace'
  Assert-True (Test-SameTarget (Get-LinkTarget $t) $foreign) 'foreign link was changed'
}

Invoke-TestBlock 'real directories need --replace and are backed up' {
  $e = New-Env
  $real = Join-Path (Join-Path $e.Codex 'skills') 'sdlc-plan'
  New-Item -ItemType Directory -Force -Path $real | Out-Null; Write-Utf8File (Join-Path $real 'note.txt') 'keep'
  $r = Install $e @(); Assert-True ($r.ExitCode -ne 0) 'install without --replace should fail'
  Assert-True (-not (Test-IsLink (Join-Path $e.Claude 'sdlc'))) 'failed preflight must not link anything'
  $r = Install $e @('--replace'); Assert-True ($r.ExitCode -eq 0) "replace failed: $($r.Output)"
  Assert-Contains $r.Output 'Backed up' 'backup message'
  Assert-Linked $e
  $backup = @(Get-ChildItem -LiteralPath $e.Codex -Recurse -Filter 'note.txt' | Where-Object { $_.FullName -notlike "*$([IO.Path]::DirectorySeparatorChar)skills$([IO.Path]::DirectorySeparatorChar)sdlc-plan*" })
  Assert-True ($backup.Count -eq 1) 'backup copy not found'
}

Invoke-TestBlock 'dry-run changes nothing; uninstall removes only managed links' {
  $e = New-Env
  $r = Install $e @('--dry-run'); Assert-True ($r.ExitCode -eq 0) "dry-run failed: $($r.Output)"
  Assert-Contains $r.Output 'Would link' 'dry-run plan'
  Assert-True (-not (Test-PathOrLink (Join-Path $e.Claude 'sdlc'))) 'dry-run created a link'
  Install $e @() | Out-Null
  $own = Join-Path (Join-Path $e.Claude 'skills') 'mine'; New-Item -ItemType Directory -Force -Path $own | Out-Null
  $r = Install $e @('--uninstall', '--dry-run'); Assert-Contains $r.Output 'Would remove managed link' 'uninstall dry-run'
  Assert-True (Test-IsLink (Join-Path $e.Claude 'sdlc')) 'uninstall dry-run removed a link'
  $r = Install $e @('--uninstall'); Assert-True ($r.ExitCode -eq 0) "uninstall failed: $($r.Output)"
  Assert-True (-not (Test-PathOrLink (Join-Path $e.Claude 'sdlc'))) 'sdlc link left behind'
  Assert-True (Test-Path -LiteralPath $own) 'unmanaged skill removed'
  Assert-True (Test-Path -LiteralPath (Join-Path (Join-Path $RepoRoot 'skills') 'sdlc-qa')) 'uninstall touched the library'
}

Invoke-TestBlock 'track installs the monitor task once; re-runs keep one task' {
  $e = New-Env
  foreach ($i in 1..2) { $r = Install $e @('--track', $Url); Assert-True ($r.ExitCode -eq 0) "track run $i failed: $($r.Output)" }
  $tasks = @(Get-Tasks $e)
  Assert-True ($tasks.Count -eq 1) "expected 1 task, got $($tasks.Count)"
  Assert-True ($tasks[0].Description -eq 'apolo-sdlc-track:acme/widget') "marker: $($tasks[0].Description)"
  Assert-True ($tasks[0].IntervalMinutes -eq 15) 'monitor interval'
  Assert-Contains $tasks[0].Arguments 'monitor.ps1' 'monitor task runs monitor.ps1'
  Assert-True (Test-Path -LiteralPath (Join-Path (Join-Path $e.Tracks 'acme') 'widget')) 'clone missing'
}

Invoke-TestBlock 'lanes schedule issue at :00 and ci at :07 every 15 minutes, idempotently' {
  $e = New-Env
  $seed = '[{"TaskName":"other","TaskPath":"\\apolo-sdlc-test\\","Description":"apolo-sdlc-track:acme/other"}]'
  [IO.File]::WriteAllText($e.Tasks, $seed)
  foreach ($i in 1..2) {
    $r = Install $e @('--track', $Url, '--lanes', 'issue,ci', '--checkout', $e.Checkout) @{ CHECKPOINT_LINES = '400' }
    Assert-True ($r.ExitCode -eq 0) "lanes run $i failed: $($r.Output)"
  }
  $tasks = @(Get-Tasks $e)
  Assert-True ($tasks.Count -eq 4) "expected 3 project tasks + 1 foreign, got $($tasks.Count)"
  $issue = @($tasks | Where-Object { $_.Description -eq 'apolo-sdlc-lane:issue:acme/widget' })
  $ci = @($tasks | Where-Object { $_.Description -eq 'apolo-sdlc-lane:ci:acme/widget' })
  Assert-True ($issue.Count -eq 1 -and $issue[0].Minute -eq 0 -and $issue[0].IntervalMinutes -eq 15) 'issue lane schedule'
  Assert-True ($ci.Count -eq 1 -and $ci[0].Minute -eq 7 -and $ci[0].IntervalMinutes -eq 15) 'ci lane schedule'
  Assert-True ($issue[0].LogonType -eq 'Interactive') 'tasks must not store a password'
  $runner = Split-Path -Parent ([regex]::Match($issue[0].Arguments, '-File "([^"]+)"').Groups[1].Value)
  $conf = [IO.File]::ReadAllText((Join-Path $runner 'project.conf'))
  Assert-Contains $conf 'checkpoint_lines=400' 'CHECKPOINT_LINES persisted'
  Assert-Contains $conf 'owner=botuser' 'owner from gh api user'
  Assert-Contains $conf ('codex_bin=' + (Resolve-Tool (Join-Path $e.Bin 'codex'))) 'codex resolved to the shim'
  $deny = [IO.File]::ReadAllText((Join-Path (Join-Path $runner 'lanes') 'deny.json')) | ConvertFrom-Json
  Assert-True (@($deny.permissions.deny | Where-Object { $_ -like 'Edit(*project.conf)' }).Count -ge 1) 'runner deny rules'
  foreach ($f in 'lane.ps1', 'agent-run.ps1', 'resolve-agents.ps1', 'apolo-common.ps1', 'monitor.ps1', 'lanes\agents.yml', 'lanes\issue.md', 'lanes\ci.md') {
    Assert-True (Test-Path -LiteralPath (Join-Path $runner $f)) "runner file missing: $f"
  }

  $r = Install $e @('--track', $Url, '--lanes', 'ci', '--checkout', $e.Checkout)
  Assert-True ($r.ExitCode -eq 0) "ci-only failed: $($r.Output)"
  $tasks = @(Get-Tasks $e)
  Assert-True (@($tasks | Where-Object { $_.Description -like '*:issue:acme/widget' }).Count -eq 0) 'issue lane should be gone'
  Assert-True ($tasks.Count -eq 3) "expected monitor+ci+foreign, got $($tasks.Count)"

  $r = Install $e @('--track', $Url, '--uninstall'); Assert-True ($r.ExitCode -eq 0) "track uninstall failed: $($r.Output)"
  $tasks = @(Get-Tasks $e)
  Assert-True ($tasks.Count -eq 1 -and $tasks[0].TaskName -eq 'other') 'only the foreign task may remain'
  Assert-True (-not (Test-Path -LiteralPath $runner)) 'runner left behind'
  Assert-True (Test-Path -LiteralPath (Join-Path (Join-Path $e.Tracks 'acme') 'widget')) 'clone must be kept'
}

Invoke-TestBlock 'invalid options are rejected before any change' {
  $e = New-Env
  foreach ($case in @(
      @(@('--track', 'http://github.com/a/b'), @{}),
      @(@('--track', $Url, '--lanes', 'nope', '--checkout', $e.Checkout), @{}),
      @(@('--track', $Url, '--lanes', 'issue'), @{}),
      @(@('--track', $Url, '--lanes', 'issue', '--checkout', $e.Checkout), @{ CHECKPOINT_LINES = 'abc' }),
      @(@('--cron-bin', 'x'), @{}),
      @(@('--bogus'), @{}))) {
    $r = Install $e $case[0] $case[1]
    Assert-True ($r.ExitCode -ne 0) "should fail: $($case[0] -join ' ')"
  }
  Assert-True (-not (Test-PathOrLink (Join-Path $e.Claude 'sdlc'))) 'a rejected run changed files'
}

Invoke-TestBlock 'task registration failure rolls back tasks, runner files and links' {
  $e = New-Env
  $r = Install $e @('--track', $Url, '--lanes', 'issue', '--checkout', $e.Checkout) @{ CHECKPOINT_LINES = '111' }
  Assert-True ($r.ExitCode -eq 0) "first install failed: $($r.Output)"
  $before = @(Get-Tasks $e | ForEach-Object { $_.TaskName } | Sort-Object) -join ','
  $runner = Join-Path (Join-Path (Join-Path $e.Data 'runners') 'acme') 'widget'
  Assert-True (Test-Path -LiteralPath (Join-Path $runner 'project.conf')) 'runner config missing'
  Remove-Link (Join-Path $e.Codex 'sdlc')
  $r = Install $e @('--track', $Url, '--lanes', 'issue,ci', '--checkout', $e.Checkout) @{ CHECKPOINT_LINES = '222'; APOLO_TEST_TASKS_FAIL = 'lane-ci' }
  Assert-True ($r.ExitCode -ne 0) 'injected failure should fail the install'
  $after = @(Get-Tasks $e | ForEach-Object { $_.TaskName } | Sort-Object) -join ','
  Assert-True ($before -eq $after) "tasks not restored: $before vs $after"
  Assert-Contains ([IO.File]::ReadAllText((Join-Path $runner 'project.conf'))) 'checkpoint_lines=111' 'runner config not restored'
  Assert-True (-not (Test-PathOrLink (Join-Path $e.Codex 'sdlc'))) 'new link not rolled back'
  Assert-True (@(Get-ChildItem -LiteralPath (Join-Path $e.Data 'runners') -Recurse -Force | Where-Object { $_.Name -like '*.previous-*' -or $_.Name -like '.staging*' }).Count -eq 0) 'staging left behind'
}

Invoke-TestBlock 'clone failure rolls back the local links' {
  $e = New-Env
  $r = Install $e @('--track', $Url) @{ FAKE_CLONE_FAIL = '1' }
  Assert-True ($r.ExitCode -ne 0) 'clone failure should fail'
  Assert-True (-not (Test-PathOrLink (Join-Path $e.Claude 'sdlc'))) 'links not rolled back'
  Assert-True (@(Get-Tasks $e).Count -eq 0) 'no task may be registered'
}

Complete-Tests 'windows install'
