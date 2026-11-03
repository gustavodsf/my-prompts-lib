# Run one SDLC phase with the agent resolved from agents.yml, under lane guardrails (Windows port of agent-run.sh).
# Usage: agent-run.ps1 <phase> <prompt-file> <cwd> [metrics.md]
#        agent-run.ps1 goldfish-panel <prompt-file> <cwd> [metrics.md] [bug|feature]
#        agent-run.ps1 diff-lines <cwd> <since-ref>   -> "<added+removed> <checkpoint threshold>"
#        agent-run.ps1 pseudo-check <cwd>             -> lists leftover SDLC-PSEUDO markers, exit 1 if any
# Lives in the lane runner directory beside project.conf and lanes\agents.yml.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'apolo-common.ps1')
$here = $PSScriptRoot
$conf = Join-Path $here 'project.conf'
$table = Join-Path (Join-Path $here 'lanes') 'agents.yml'

function Get-GitBin {
  $bin = Get-ConfValue $conf 'git_bin'
  if ($bin -and (Test-Path -LiteralPath $bin -PathType Leaf)) { return $bin }
  $bin = Resolve-Tool 'git'
  if (-not $bin) { Write-ErrorLine 'agent-run: git not found'; exit 2 }
  return $bin
}

$mode = ''
if ($args.Count -gt 0) { $mode = [string]$args[0] }
if ($mode -eq 'diff-lines') {
  if ($args.Count -lt 3) { Write-ErrorLine 'usage: agent-run.ps1 diff-lines <cwd> <since-ref>'; exit 2 }
  $limit = Get-ConfValue $conf 'checkpoint_lines'
  if ($limit -notmatch '^[0-9]+$') {
    $limit = ''
    if (Test-Path -LiteralPath $table) {
      foreach ($line in (Read-Lines $table)) { if ($line -match '^checkpoint_lines: *([0-9]+)') { $limit = $Matches[1]; break } }
    }
  }
  if (-not $limit) { $limit = '250' }
  # Committed since the ref plus uncommitted work, Markdown excluded (never committed).
  $r = Invoke-Native (Get-GitBin) @('-C', [string]$args[1], 'diff', '--numstat', [string]$args[2], '--', '.', ':(exclude)*.md')
  if ($r.ExitCode -ne 0) { Write-ErrorLine $r.Stderr; exit $r.ExitCode }
  $sum = 0
  foreach ($line in ($r.Stdout -split "`n")) {
    $parts = $line.Trim() -split '\s+'
    if ($parts.Count -ge 2 -and $parts[0] -match '^[0-9]+$' -and $parts[1] -match '^[0-9]+$') { $sum += [int]$parts[0] + [int]$parts[1] }
  }
  [Console]::Out.Write("$sum $limit`n")
  exit 0
}
if ($mode -eq 'pseudo-check') {
  if ($args.Count -lt 2) { Write-ErrorLine 'usage: agent-run.ps1 pseudo-check <cwd>'; exit 2 }
  $r = Invoke-Native (Get-GitBin) @('-C', [string]$args[1], 'grep', '-n', '-I', '--untracked', 'SDLC-PSEUDO', '--', '.', ':(exclude)*.md')
  if ($r.ExitCode -eq 0) {
    [Console]::Out.Write($r.Stdout)
    Write-ErrorLine 'pseudocode markers remain: implement or remove them before the PR'
    exit 1
  }
  exit 0
}

if ($args.Count -lt 3) { Write-ErrorLine 'usage: agent-run.ps1 <phase> <prompt-file> <cwd> [metrics.md] [bug|feature]'; exit 2 }
$phase = [string]$args[0]; $promptFile = [string]$args[1]; $cwd = [string]$args[2]
$metrics = ''; if ($args.Count -gt 3) { $metrics = [string]$args[3] }
if (-not (Test-Path -LiteralPath $promptFile -PathType Leaf) -or -not (Test-Path -LiteralPath $cwd -PathType Container)) {
  Write-ErrorLine 'agent-run: prompt file or cwd missing'; exit 2
}
if (@('design', 'goldfish', 'goldfish-panel', 'implement', 'review', 'tiebreak') -notcontains $phase) {
  Write-ErrorLine "agent-run: unknown phase $phase"; exit 2
}
try {
  $resolved = Resolve-AgentTable $table $conf ([string]$env:APOLO_SDLC_IMPLEMENTER)
} catch { Write-ErrorLine $_.Exception.Message; exit 1 }
$tableLines = Read-Lines $table

# Guardrails: only the lane's own claude session pushes. Every agent run here gets no GitHub
# token, no credential prompts, and a push URL that cannot work.
$lane = $env:APOLO_SDLC_LANE; if (-not $lane) { $lane = 'issue' }
$guardSet = @{
  APOLO_SDLC_LANE = $lane
  GIT_TERMINAL_PROMPT = '0'
  GCM_INTERACTIVE = 'never'
  GIT_CONFIG_COUNT = '2'
  GIT_CONFIG_KEY_0 = 'remote.origin.pushurl'; GIT_CONFIG_VALUE_0 = 'no-push://agent-run.disabled'
  GIT_CONFIG_KEY_1 = 'remote.pushDefault'; GIT_CONFIG_VALUE_1 = 'no-push-disabled'
}
$guardUnset = @('GH_TOKEN', 'GITHUB_TOKEN', 'GH_ENTERPRISE_TOKEN')
$path = Get-ConfValue $conf 'path'
if ($path) { $guardSet['PATH'] = $path }

function Add-Metric([string]$Phase, [string]$Agent, [string]$Status, [int]$Seconds) {
  if (-not $metrics) { return }
  if (-not (Test-Path -LiteralPath $metrics)) {
    Write-Utf8File $metrics "| Phase | Agent | Tokens (if known) | Attempt | Result |`n| --- | --- | --- | --- | --- |`n"
  }
  $attempt = 1 + @((Read-Lines $metrics) | Where-Object { $_.StartsWith("| $Phase | ") }).Count
  $dash = [string][char]0x2014
  Add-Utf8File $metrics "| $Phase | $Agent | $dash | $attempt | $Status, ${Seconds}s |`n"
}

# The command template is split on spaces before substitution, so paths with spaces stay one argument;
# `< {prompt_file}` becomes standard input. No shell is involved.
function Start-Agent([string]$Agent, [string]$Phase, [string]$Prompt) {
  $bin = Get-ConfValue $conf "${Agent}_bin"
  $template = Get-AgentCommand $tableLines $Agent
  $sandbox = 'read-only'
  if ($Phase -eq 'implement' -or $Phase -eq 'design') { $sandbox = 'workspace-write' }
  $values = @{ '{bin}' = $bin; '{prompt_file}' = $Prompt; '{cwd}' = $cwd; '{sandbox}' = $sandbox
    '{deny_file}' = (Join-Path (Join-Path $here 'lanes') 'deny.json') }
  $tokens = @($template -split ' +' | Where-Object { $_ })
  $argv = New-Object System.Collections.Generic.List[string]
  $stdin = ''
  for ($i = 0; $i -lt $tokens.Count; $i++) {
    $token = $tokens[$i]
    if ($token -eq '<') { $i++; $token = $tokens[$i]; foreach ($k in $values.Keys) { $token = $token.Replace($k, $values[$k]) }; $stdin = $token; continue }
    foreach ($k in $values.Keys) { $token = $token.Replace($k, $values[$k]) }
    $argv.Add($token)
  }
  $program = $argv[0]
  $rest = @(); if ($argv.Count -gt 1) { $rest = $argv.GetRange(1, $argv.Count - 1).ToArray() }
  $set = $guardSet.Clone(); $set['APOLO_SDLC_PHASE'] = $Phase; $set['APOLO_SDLC_AGENT'] = $Agent
  return Start-Native -FilePath $program -Arguments $rest -StdinFile $stdin -WorkingDirectory $cwd -Set $set -Unset $guardUnset
}

if ($phase -ne 'goldfish-panel') {
  $agent = $resolved[$phase]
  if ($agent -eq 'blocked' -or $agent -eq 'human') { [Console]::Out.Write("agent-run: no independent agent for $phase ($agent)`n"); exit 3 }
  $start = Get-Date
  $r = Wait-Native (Start-Agent $agent $phase $promptFile)
  [Console]::Out.Write($r.Stdout); [Console]::Error.Write($r.Stderr)
  Add-Metric $phase $agent "exit $($r.ExitCode)" ([int]((Get-Date) - $start).TotalSeconds)
  exit $r.ExitCode
}

# Goldfish panel.
$type = 'feature'; if ($args.Count -gt 4 -and $args[4] -eq 'bug') { $type = 'bug' }
$lenses = @((Get-YamlEntry (Get-YamlSection $tableLines 'goldfish_lenses') $type '(.*)') -split '\s+' | Where-Object { $_ })
$pool = @($resolved['goldfish_pool'] -split ',' | Where-Object { $_ })
if ($lenses.Count -eq 0 -or $pool.Count -eq 0) { Write-ErrorLine 'agent-run: no goldfish lenses or agents'; exit 2 }
$focus = @{
  comprehension = 'Explain the plan back in at most 10 lines; list every path#symbol not in codemap.md and not marked (new).'
  adversarial = 'Find edge cases, races, bad inputs and failure modes the design misses; say how it could break.'
  security = 'Check secrets, permissions, AWS use (read-only at most), personal data and privacy.'
  testability = 'Check every AC names a concrete, automatable test and every task has a file and a failing test first.'
  simplicity = 'Find over-scope and a simpler option that meets the same ACs.'
}
foreach ($lens in $lenses) { if (-not $focus.ContainsKey($lens)) { Write-ErrorLine "agent-run: unknown goldfish lens $lens"; exit 2 } }
$work = Join-Path ([System.IO.Path]::GetTempPath()) ('apolo-panel-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work | Out-Null
try {
  $base = [System.IO.File]::ReadAllText($promptFile)
  $runs = @()
  $i = 0
  foreach ($lens in $lenses) {
    $agent = $pool[$i % $pool.Count]
    $lensPrompt = Join-Path $work "$lens.prompt"
    Write-Utf8File $lensPrompt ($base + "`n`nLens: $lens. $($focus[$lens])`nReply with a first line ``Verdict: Pass|Partial|Fail``, then at most 5 bullets. Do not write files.`n")
    $runs += [pscustomobject]@{ Lens = $lens; Agent = $agent; Start = (Get-Date); Handle = (Start-Agent $agent 'goldfish' $lensPrompt) }
    $i++
  }
  $panel = 'PASS'
  foreach ($run in $runs) {
    $r = Wait-Native $run.Handle
    $secs = [int]((Get-Date) - $run.Start).TotalSeconds
    $text = $r.Stdout + $r.Stderr
    $verdict = ''
    $m = [regex]::Match($text, 'Verdict:\s*\**(Pass|Partial|Fail)', 'IgnoreCase')
    if ($m.Success) { $verdict = $m.Groups[1].Value.ToLowerInvariant() }
    if ($r.ExitCode -ne 0 -or -not $verdict) { $verdict = 'fail' } # no readable verdict blocks
    if ($verdict -eq 'fail') { $panel = 'FAIL' }
    if ($verdict -eq 'partial' -and $panel -eq 'PASS') { $panel = 'PARTIAL' }
    $title = $verdict.Substring(0, 1).ToUpperInvariant() + $verdict.Substring(1)
    $head = (@($text -split "`r?`n") | Select-Object -First 12) -join "`n"
    [Console]::Out.Write("### $($run.Lens) ($($run.Agent)): $title`n$head`n`n")
    Add-Metric "goldfish:$($run.Lens)" $run.Agent $title $secs
  }
  [Console]::Out.Write("PANEL: $panel`n")
} finally {
  Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
if ($panel -eq 'FAIL') { exit 1 }
exit 0
