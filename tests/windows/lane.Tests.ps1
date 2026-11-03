# Mirrors tests/lane.sh and tests/lane-mode.sh for lane.ps1, agent-run.ps1 and resolve-agents.ps1.
. (Join-Path $PSScriptRoot 'helpers.ps1')

$Recorder = @'
$rec = [ordered]@{ name = '__NAME__'; args = @($args); stdin = ''; gh = [string]$env:GH_TOKEN; github = [string]$env:GITHUB_TOKEN
  pushurl = [string]$env:GIT_CONFIG_VALUE_0; prompt = [string]$env:GIT_TERMINAL_PROMPT; implementer = [string]$env:APOLO_SDLC_IMPLEMENTER
  lane = [string]$env:APOLO_SDLC_LANE; agents = [string]$env:APOLO_SDLC_AGENTS; phase = [string]$env:APOLO_SDLC_PHASE; cwd = (Get-Location).Path }
if ('__STDIN__' -eq '1') { $rec.stdin = [Console]::In.ReadToEnd() }
$file = Join-Path $env:FAKE_LOG_DIR ('__NAME__-' + [guid]::NewGuid().ToString('N') + '.json')
[IO.File]::WriteAllText($file, (ConvertTo-Json -InputObject $rec -Depth 4))
if ($env:FAKE_SLEEP -and '__NAME__' -eq 'claude') { Start-Sleep -Seconds ([int]$env:FAKE_SLEEP) }
'@

function New-Lane {
  $root = New-TestRoot 'lane'
  $bin = Join-Path $root 'fake bin'; $logs = Join-Path $root 'calls'
  New-Item -ItemType Directory -Force -Path $logs | Out-Null
  $claude = New-Fake $bin 'claude' (($Recorder -replace '__NAME__', 'claude' -replace '__STDIN__', '1') + "`n" + @'
$i = [array]::IndexOf(@($args), '--max-turns')
if ($args -contains '--settings' -and $i -ge 0 -and $args[$i + 1] -eq '60') { 'Verdict: Pass'; '- fine' }
'@)
  $codex = New-Fake $bin 'codex' (($Recorder -replace '__NAME__', 'codex' -replace '__STDIN__', '1') + "`n'codex done'")
  $grok = New-Fake $bin 'grok' (($Recorder -replace '__NAME__', 'grok' -replace '__STDIN__', '0') + "`n" + @'
$p = [IO.File]::ReadAllText($args[[array]::IndexOf(@($args), '--prompt-file') + 1])
if ($p.Contains('Lens: security')) { 'Verdict: **Fail**'; '- leaks a token' } elseif ($p.Contains('Lens: adversarial')) { 'Verdict: Partial' } else { 'Verdict: Pass' }
'@)
  $gh = New-Fake $bin 'gh' "if (`$env:FAKE_GH_FAIL) { exit 1 }; if (`$args[0] -eq 'run') { '9 completed success' } else { [string]`$env:FAKE_GH_OUT }"
  $runner = Join-Path $root 'runner dir'
  New-Item -ItemType Directory -Force -Path (Join-Path $runner 'lanes') | Out-Null
  foreach ($f in 'lane.ps1', 'agent-run.ps1', 'resolve-agents.ps1', 'apolo-common.ps1') { Copy-Item -LiteralPath (Join-Path (Join-Path $RepoRoot 'scripts') $f) -Destination $runner }
  foreach ($f in 'issue.md', 'ci.md', 'deny.json') { Copy-Item -LiteralPath (Join-Path (Join-Path $RepoRoot 'lanes') $f) -Destination (Join-Path $runner 'lanes') }
  Copy-Item -LiteralPath (Join-Path (Join-Path $RepoRoot 'sdlc') 'agents.yml') -Destination (Join-Path $runner 'lanes')
  $checkout = Join-Path $root 'work tree'
  $git = Get-RealGit
  & $git init -q $checkout
  & $git -C $checkout -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
  $state = Join-Path $root 'state dir'
  $conf = [ordered]@{ repo = 'acme/widget'; owner = 'botuser'; checkout = $checkout; worktrees = (Join-Path $root 'wt'); docs = (Join-Path $root 'docs')
    state = $state; evidence_branch = 'sdlc-evidence'; claude_bin = (Resolve-Tool $claude); gh_bin = (Resolve-Tool $gh); git_bin = $git
    codex_bin = (Resolve-Tool $codex); grok_bin = (Resolve-Tool $grok); path = ($bin + $Sep + (Get-BasePath)) }
  $e = [pscustomobject]@{ Root = $root; Runner = $runner; Logs = $logs; Checkout = $checkout; State = $state; Conf = $conf; Bin = $bin }
  Write-Conf $e
  return $e
}
function Write-Conf($E) { Write-Utf8File (Join-Path $E.Runner 'project.conf') ((@($E.Conf.Keys | ForEach-Object { "$_=$($E.Conf[$_])" }) -join "`n") + "`n") }
function Get-Calls($E, [string]$Name) {
  @(Get-ChildItem -LiteralPath $E.Logs -Filter "$Name-*.json" | Sort-Object LastWriteTime | ForEach-Object { [IO.File]::ReadAllText($_.FullName) | ConvertFrom-Json })
}
function Clear-Calls($E) { Get-ChildItem -LiteralPath $E.Logs | Remove-Item -Force }
function Run-Lane($E, [string]$Lane, [hashtable]$Extra = @{}) {
  $set = @{ FAKE_LOG_DIR = $E.Logs; PATH = ($E.Bin + $Sep + (Get-BasePath)); FAKE_GH_OUT = '1 2026-11-01T00:00:00Z' }
  foreach ($k in $Extra.Keys) { $set[$k] = $Extra[$k] }
  return Invoke-Script (Join-Path $E.Runner 'lane.ps1') @($Lane) -Set $set -Unset @('GH_TOKEN', 'GITHUB_TOKEN')
}
function Run-Agent($E, [string[]]$Arguments, [hashtable]$Extra = @{}) {
  $set = @{ FAKE_LOG_DIR = $E.Logs; GH_TOKEN = 'ghp_leak'; GITHUB_TOKEN = 'ghp_leak2'; APOLO_SDLC_LANE = 'issue' }
  foreach ($k in $Extra.Keys) { $set[$k] = $Extra[$k] }
  return Invoke-Script (Join-Path $E.Runner 'agent-run.ps1') $Arguments -Set $set
}
function Read-LaneLog($E, [string]$Lane) { [IO.File]::ReadAllText((Join-Path (Join-Path $E.Runner 'logs') "$Lane.log")) }

Invoke-TestBlock 'issue lane runs claude with the prompt on stdin, deny settings and the bot token' {
  $e = New-Lane
  New-Item -ItemType Directory -Force -Path $e.State | Out-Null
  Write-Utf8File (Join-Path $e.State 'bot-token') "ghs_bot123`n"
  $r = Run-Lane $e 'issue'
  Assert-True ($r.ExitCode -eq 0) "lane failed: $($r.Output)"
  $c = @(Get-Calls $e 'claude'); Assert-True ($c.Count -eq 1) 'claude should run once'
  $a = @($c[0].args)
  Assert-True (($a -join ' ') -eq ('-p --dangerously-skip-permissions --settings ' + (Join-Path (Join-Path $e.Runner 'lanes') 'deny.json') + ' --max-turns 150')) "claude args: $($a -join ' ')"
  Assert-Contains $c[0].stdin 'Lane mode: active' 'prompt header'
  Assert-Contains $c[0].stdin "checkout: $($e.Checkout)" 'checkout in prompt (with spaces)'
  Assert-Contains $c[0].stdin 'agent-run.ps1' 'agent_runner line'
  Assert-Contains $c[0].stdin 'agents: design=claude' 'agents line'
  Assert-True ($c[0].gh -eq 'ghs_bot123') 'the lane claude gets the bot token'
  Assert-True ($c[0].lane -eq 'issue' -and -not $c[0].implementer) 'issue lane env'
  Assert-True ((Get-Item -LiteralPath $c[0].cwd).FullName.TrimEnd('\', '/') -eq (Get-Item -LiteralPath $e.Checkout).FullName.TrimEnd('\', '/')) 'claude runs in the checkout'
  Assert-True (-not (Test-Path -LiteralPath (Join-Path $e.Runner 'lanes.lock'))) 'lock released'

  Clear-Calls $e
  $r = Run-Lane $e 'issue'
  Assert-True ($r.ExitCode -eq 0 -and @(Get-Calls $e 'claude').Count -eq 0) 'unchanged GitHub state must skip claude'
  Assert-Contains (Read-LaneLog $e 'issue') 'no changes (pre-check)' 'pre-check logged'
  $r = Run-Lane $e 'issue' @{ FAKE_GH_OUT = '1 2026-11-02T00:00:00Z' }
  Assert-True (@(Get-Calls $e 'claude').Count -eq 1) 'a GitHub change must run claude'
}

Invoke-TestBlock 'ci lane: claude is the implementer, so codex reviews' {
  $e = New-Lane
  $r = Run-Lane $e 'ci'; Assert-True ($r.ExitCode -eq 0) "ci lane failed: $($r.Output)"
  $c = @(Get-Calls $e 'claude')[0]
  Assert-True ($c.implementer -eq 'claude' -and $c.lane -eq 'ci') 'ci env'
  Assert-Contains $c.agents 'implement=claude' 'implementer in agents'
  Assert-NotContains $c.agents 'review=claude' 'claude may not review itself'
  Assert-True (-not $c.gh) 'no token file, no GH_TOKEN'
}

Invoke-TestBlock 'project.conf validation' {
  foreach ($case in @(@{ bogus = 'x' }, @{ max_turns = 'abc' }, @{ checkpoint_lines = '0' }, @{ claude_bin = 'claude' }, @{ owner = "bad%PATH%" })) {
    $e = New-Lane
    foreach ($k in $case.Keys) { $e.Conf[$k] = $case[$k] }
    Write-Conf $e
    $r = Run-Lane $e 'issue'
    Assert-True ($r.ExitCode -ne 0) "should reject $(@($case.Keys) -join ',')"
    Assert-True (@(Get-Calls $e 'claude').Count -eq 0) 'claude must not run on a bad config'
    Assert-Contains $r.Stderr 'Error:' 'error reported'
  }
  $e = New-Lane; $r = Run-Lane $e 'nope'; Assert-True ($r.ExitCode -ne 0) 'unknown lane'
  $e = New-Lane; $e.Conf.Remove('grok_bin'); $e.Conf.Remove('codex_bin'); Write-Conf $e
  $r = Run-Lane $e 'issue'; Assert-True ($r.ExitCode -ne 0) 'issue lane without an implementer must fail'
  Assert-Contains $r.Output 'invalid agents table' 'agents table error'
}

Invoke-TestBlock 'lock held by a live process skips; a stale lock is recovered' {
  $e = New-Lane
  $lock = Join-Path $e.Runner 'lanes.lock'
  New-Item -ItemType Directory -Force -Path $lock | Out-Null; Write-Utf8File (Join-Path $lock 'pid') "$PID`n"
  $r = Run-Lane $e 'issue'
  Assert-True ($r.ExitCode -eq 0 -and @(Get-Calls $e 'claude').Count -eq 0) 'held lock must skip'
  Assert-Contains (Read-LaneLog $e 'issue') "lock held by pid $PID" 'skip logged'
  Write-Utf8File (Join-Path $lock 'pid') "999999`n"
  $r = Run-Lane $e 'issue'
  Assert-True ($r.ExitCode -eq 0 -and @(Get-Calls $e 'claude').Count -eq 1) 'stale lock must be taken over'
}

Invoke-TestBlock 'a hung claude is killed at timeout_seconds and the run is retried next time' {
  $e = New-Lane; $e.Conf['timeout_seconds'] = '3'; Write-Conf $e
  $start = Get-Date
  $r = Run-Lane $e 'issue' @{ FAKE_SLEEP = '60' }
  Assert-True (((Get-Date) - $start).TotalSeconds -lt 40) 'timeout did not stop the run'
  Assert-True ($r.ExitCode -ne 0) 'timed-out run must fail'
  Assert-Contains (Read-LaneLog $e 'issue') 'timed out after 3s' 'timeout logged'
  Assert-True (-not (Test-Path -LiteralPath (Join-Path $e.State 'issue-fingerprint'))) 'failed run must not record the fingerprint'
}

Invoke-TestBlock 'agent-run implement: codex template, prompt on stdin, no tokens, push disabled, metrics' {
  $e = New-Lane
  $prompt = Join-Path $e.Root 'the prompt.md'; Write-Utf8File $prompt 'implement AC1'
  $metrics = Join-Path $e.Root 'metrics file.md'
  $r = Run-Agent $e @('implement', $prompt, $e.Checkout, $metrics)
  Assert-True ($r.ExitCode -eq 0) "agent-run failed: $($r.Output)"
  Assert-Contains $r.Stdout 'codex done' 'agent output relayed'
  $c = @(Get-Calls $e 'codex')[0]
  Assert-True ((@($c.args) -join '|') -eq ("--ask-for-approval|never|exec|--sandbox|workspace-write|-C|$($e.Checkout)|-")) "codex args: $(@($c.args) -join '|')"
  Assert-True ($c.stdin -eq 'implement AC1') 'prompt on stdin'
  Assert-True (-not $c.gh -and -not $c.github) 'tokens must be stripped'
  Assert-True ($c.pushurl -eq 'no-push://agent-run.disabled' -and $c.prompt -eq '0') 'push guardrail'
  Assert-Contains ([IO.File]::ReadAllText($metrics)) '| implement | codex |' 'metrics row'
  $r = Run-Agent $e @('review', $prompt, $e.Checkout)
  Assert-True (@(Get-Calls $e 'claude').Count -eq 1) 'review runs claude'
  $r = Run-Agent $e @('bogus', $prompt, $e.Checkout); Assert-True ($r.ExitCode -eq 2) 'unknown phase'
}

Invoke-TestBlock 'goldfish panel: lenses alternate grok/claude, worst verdict wins' {
  $e = New-Lane
  $prompt = Join-Path $e.Root 'design.md'; Write-Utf8File $prompt 'design'
  $r = Run-Agent $e @('goldfish-panel', $prompt, $e.Checkout, '', 'feature')
  Assert-True ($r.ExitCode -eq 1) "security Fail must fail the panel: $($r.Output)"
  Assert-Contains $r.Stdout '### comprehension (grok): Pass' 'lens 1 on grok'
  Assert-Contains $r.Stdout '### adversarial (claude): Pass' 'lens 2 on claude'
  Assert-Contains $r.Stdout '### security (grok): Fail' 'lens 3 on grok'
  Assert-Contains $r.Stdout 'PANEL: FAIL' 'panel verdict'
  Assert-True (@(Get-Calls $e 'grok' | Where-Object { $_.gh }).Count -eq 0) 'panel agents get no token'
  $r = Run-Agent $e @('goldfish-panel', $prompt, $e.Checkout, '', 'bug')
  Assert-True ($r.ExitCode -eq 0) 'bug panel passes'
  Assert-Contains $r.Stdout 'PANEL: PASS' 'bug panel verdict'
  Assert-True (@(Get-ChildItem -LiteralPath ([IO.Path]::GetTempPath()) -Filter 'apolo-panel-*' -ErrorAction SilentlyContinue).Count -eq 0) 'panel temp dir removed'
  $e.Conf.Remove('grok_bin'); Write-Conf $e
  $r = Run-Agent $e @('goldfish-panel', $prompt, $e.Checkout, '', 'feature')
  Assert-Contains $r.Stdout '### adversarial (claude): Pass' 'without grok the pool is claude only'
}

Invoke-TestBlock 'diff-lines and pseudo-check' {
  $e = New-Lane
  $git = Get-RealGit
  $base = (& $git -C $e.Checkout rev-parse HEAD).Trim()
  Write-Utf8File (Join-Path $e.Checkout 'a.txt') ((1..10 | ForEach-Object { "line $_" }) -join "`n")
  Write-Utf8File (Join-Path $e.Checkout 'notes.md') ((1..50 | ForEach-Object { "md $_" }) -join "`n")
  & $git -C $e.Checkout add . ; & $git -C $e.Checkout -c user.name=t -c user.email=t@t commit -q -m two
  $r = Run-Agent $e @('diff-lines', $e.Checkout, $base)
  Assert-True ($r.Stdout.Trim() -eq '10 250') "diff-lines: $($r.Stdout)"
  $e.Conf['checkpoint_lines'] = '7'; Write-Conf $e
  $r = Run-Agent $e @('diff-lines', $e.Checkout, $base); Assert-True ($r.Stdout.Trim() -eq '10 7') "override: $($r.Stdout)"
  $r = Run-Agent $e @('pseudo-check', $e.Checkout); Assert-True ($r.ExitCode -eq 0) 'clean tree'
  Write-Utf8File (Join-Path $e.Checkout 'b.txt') '// SDLC-PSEUDO: todo'
  $r = Run-Agent $e @('pseudo-check', $e.Checkout); Assert-True ($r.ExitCode -eq 1) 'untracked marker found'
  Assert-Contains $r.Stdout 'b.txt' 'marker location'
}

Invoke-TestBlock 'resolve-agents fallbacks match the shell version' {
  $e = New-Lane
  $script = Join-Path $e.Runner 'resolve-agents.ps1'
  $r = Invoke-Script $script @((Join-Path (Join-Path $e.Runner 'lanes') 'agents.yml'), (Join-Path $e.Runner 'project.conf'))
  Assert-True ($r.ExitCode -eq 0) "resolve failed: $($r.Output)"
  $e.Conf.Remove('grok_bin'); Write-Conf $e
  $r = Invoke-Script $script @((Join-Path (Join-Path $e.Runner 'lanes') 'agents.yml'), (Join-Path $e.Runner 'project.conf'))
  Assert-Contains $r.Stdout 'goldfish=claude' 'goldfish falls back to a fresh claude'
  Assert-Contains $r.Stdout 'tiebreak=human' 'no third agent'
  if (-not $ApoloIsWindows) {
    $sh = & bash (Join-Path $RepoRoot 'scripts/resolve-agents.sh') (Join-Path (Join-Path $e.Runner 'lanes') 'agents.yml') (Join-Path $e.Runner 'project.conf') 2>&1
    Assert-True ((($sh -join "`n").Trim()) -eq $r.Stdout.Trim()) "parity with resolve-agents.sh:`n$($sh -join "`n")`nvs`n$($r.Stdout)"
  }
}

Complete-Tests 'windows lanes'
