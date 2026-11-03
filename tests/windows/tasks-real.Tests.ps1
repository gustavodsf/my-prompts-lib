# Windows only (CI): registers real Task Scheduler tasks in a dedicated folder, checks them, and removes them.
. (Join-Path $PSScriptRoot 'helpers.ps1')
if (-not $ApoloIsWindows) { [Console]::Out.Write("SKIP: real Task Scheduler test needs Windows`n"); exit 0 }
$folder = '\apolo-sdlc-ci\'
$root = New-TestRoot 'tasks'
$bin = Join-Path $root 'fake bin'
$realGit = Get-RealGit
New-Fake $bin 'git' @"
`$real = '$realGit'
if (`$args[0] -eq 'clone') { `$dir = `$args[`$args.Count - 1]; & `$real init -q `$dir; & `$real -C `$dir remote add origin `$args[`$args.Count - 2]; exit `$LASTEXITCODE }
& `$real @args; exit `$LASTEXITCODE
"@ | Out-Null
New-Fake $bin 'gh' "'botuser'" | Out-Null
foreach ($a in 'claude', 'codex') { New-Fake $bin $a 'exit 0' | Out-Null }
$checkout = Join-Path $root 'work tree'; & $realGit init -q $checkout; & $realGit -C $checkout remote add origin 'https://github.com/acme/widget'
$common = @('--claude-dir', (Join-Path $root 'c'), '--codex-dir', (Join-Path $root 'x'), '--track-root', (Join-Path $root 't'), '--track', 'https://github.com/acme/widget')
$set = @{ PATH = ($bin + $Sep + (Get-BasePath)); APOLO_SDLC_DATA = (Join-Path $root 'data'); APOLO_SDLC_TASK_FOLDER = $folder }
$installer = Join-Path (Join-Path $RepoRoot 'scripts') 'install.ps1'
try {
  Invoke-TestBlock 'real tasks: register twice, inspect, uninstall' {
    foreach ($i in 1..2) {
      $r = Invoke-Script $installer ($common + @('--lanes', 'issue,ci', '--checkout', $checkout)) -Set $set
      Assert-True ($r.ExitCode -eq 0) "install $i failed: $($r.Output)"
    }
    $tasks = @(Get-ScheduledTask -TaskPath $folder)
    Assert-True ($tasks.Count -eq 3) "expected 3 tasks, got $($tasks.Count)"
    $ci = $tasks | Where-Object { $_.Description -eq 'apolo-sdlc-lane:ci:acme/widget' }
    Assert-True ($ci.Triggers[0].Repetition.Interval -eq 'PT15M') "interval $($ci.Triggers[0].Repetition.Interval)"
    Assert-True (([datetime]$ci.Triggers[0].StartBoundary).Minute -eq 7) 'ci at :07'
    Assert-True ($ci.Principal.LogonType -eq 'Interactive') 'interactive logon, no stored password'
    Assert-Contains $ci.Actions[0].Arguments 'lane.ps1' 'lane action'
    # Run the monitor task once: with no authorization it exits 0 quickly.
    $mon = $tasks | Where-Object { $_.Description -eq 'apolo-sdlc-track:acme/widget' }
    Start-ScheduledTask -TaskPath $folder -TaskName $mon.TaskName
    $deadline = (Get-Date).AddSeconds(60)
    do { Start-Sleep -Seconds 2; $info = Get-ScheduledTaskInfo -TaskPath $folder -TaskName $mon.TaskName } while ($info.LastTaskResult -eq 267009 -or $info.LastTaskResult -eq 267011 -and (Get-Date) -lt $deadline)
    [Console]::Out.Write("monitor task last result: $($info.LastTaskResult)`n")
    $r = Invoke-Script $installer ($common + @('--uninstall')) -Set $set
    Assert-True ($r.ExitCode -eq 0) "uninstall failed: $($r.Output)"
    Assert-True (@(Get-ScheduledTask -TaskPath $folder -ErrorAction SilentlyContinue).Count -eq 0) 'tasks left behind'
  }
} finally {
  Get-ScheduledTask -TaskPath $folder -ErrorAction SilentlyContinue | Unregister-ScheduledTask -Confirm:$false
}
Complete-Tests 'windows real tasks'
