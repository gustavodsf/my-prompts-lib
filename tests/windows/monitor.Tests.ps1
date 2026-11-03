# Mirrors tests/monitor.sh for scripts/monitor.ps1.
. (Join-Path $PSScriptRoot 'helpers.ps1')
$Monitor = Join-Path (Join-Path $RepoRoot 'scripts') 'monitor.ps1'

function New-Mon {
  $root = New-TestRoot 'monitor'
  $bin = Join-Path $root 'fake bin'; $calls = Join-Path $root 'gh calls.txt'
  New-Fake $bin 'gh' @"
Add-Content -LiteralPath '$calls' -Value (`$args -join ' ')
if (`$args[0] -eq 'issue' -and `$args[1] -eq 'view') { [string]`$env:FAKE_ISSUE_STATE; exit 0 }
if (`$env:FAKE_GH_FAIL) { [Console]::Error.WriteLine('boom'); exit 1 }
'[]'
"@ | Out-Null
  $repo = Join-Path $root 'my repo'
  $git = Get-RealGit; & $git init -q $repo; & $git -C $repo remote add origin 'https://github.com/acme/widget.git'
  return [pscustomobject]@{ Root = $root; Bin = $bin; Calls = $calls; Repo = $repo; State = (Join-Path $root 'state root') }
}
function Mon($M, [string[]]$Arguments, [hashtable]$Extra = @{}) {
  $set = @{ PATH = ($M.Bin + $Sep + (Get-BasePath)); XDG_STATE_HOME = $M.State; FAKE_ISSUE_STATE = 'OPEN' }
  foreach ($k in $Extra.Keys) { $set[$k] = $Extra[$k] }
  return Invoke-Script $Monitor (@('--repo', $M.Repo) + $Arguments) -Set $set
}
function Get-GhCalls($M) { if (Test-Path -LiteralPath $M.Calls) { return [IO.File]::ReadAllText($M.Calls) } return '' }

Invoke-TestBlock 'no authorization: reads issues and PRs, scheduled run is silent' {
  $m = New-Mon
  $r = Mon $m @(); Assert-True ($r.ExitCode -eq 0) "monitor failed: $($r.Output)"
  Assert-Contains $r.Stdout 'No authorized issue' 'message'
  Assert-Contains (Get-GhCalls $m) 'pr list --state open --limit 30' 'pr list'
  Remove-Item -LiteralPath $m.Calls
  $r = Mon $m @('--scheduled'); Assert-True ($r.ExitCode -eq 0 -and -not $r.Stdout -and -not (Get-GhCalls $m)) 'scheduled must be silent and offline'
  $r = Mon $m @() @{ FAKE_GH_FAIL = '1' }; Assert-True ($r.ExitCode -ne 0) 'gh failure must fail'
}

Invoke-TestBlock 'authorize, track, complete and clear' {
  $m = New-Mon
  $r = Mon $m @('--authorize', '12'); Assert-Contains $r.Stdout 'Authorized issue #12' 'authorize'
  $r = Mon $m @('--authorize', '13'); Assert-True ($r.ExitCode -ne 0) 'a second issue must be refused'
  $r = Mon $m @('--dry-run'); Assert-Contains $r.Stdout 'ready for interactive execution' 'dry-run'
  $r = Mon $m @(); Assert-Contains $r.Stdout 'requires interactive execution' 'open issue'
  $r = Mon $m @() @{ FAKE_ISSUE_STATE = 'CLOSED' }; Assert-Contains $r.Stdout 'marked completed' 'closed issue'
  $r = Mon $m @(); Assert-Contains $r.Stdout 'already completed' 'completed state'
  $r = Mon $m @('--clear-authorization'); Assert-Contains $r.Stdout 'Cleared' 'clear'
  Assert-True (@(Get-ChildItem -LiteralPath (Join-Path $m.State 'apolo-sdlc') -Filter '*.state').Count -eq 0) 'state removed'
}

Invoke-TestBlock 'invalid input and foreign state are refused; errors reach --error-log' {
  $m = New-Mon
  foreach ($a in @(@('--limit', '0'), @('--limit', '51'), @('--authorize', 'x'), @('--bogus'))) {
    $r = Mon $m $a; Assert-True ($r.ExitCode -ne 0) "should reject $($a -join ' ')"
  }
  $state = Join-Path $m.Root 'shared.state'
  Mon $m @('--state-file', $state, '--authorize', '3') | Out-Null
  $other = Join-Path $m.Root 'other repo'; & (Get-RealGit) init -q $other; & (Get-RealGit) -C $other remote add origin 'https://github.com/acme/other.git'
  $log = Join-Path $m.Root 'err.log'
  $r = Invoke-Script $Monitor @('--repo', $other, '--state-file', $state, '--error-log', $log) -Set @{ PATH = ($m.Bin + $Sep + (Get-BasePath)) }
  Assert-True ($r.ExitCode -ne 0) 'state of another repository must be refused'
  Assert-Contains ([IO.File]::ReadAllText($log)) 'different repository' 'error log'
}

Complete-Tests 'windows monitor'
