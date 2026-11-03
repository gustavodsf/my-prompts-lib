# Resolve sdlc/agents.yml into the effective agent per phase (Windows port of resolve-agents.sh).
# Usage: resolve-agents.ps1 <agents.yml> [project.conf] [--implementer AGENT]
# Prints `phase=agent` lines; exits 1 when the table is invalid or a write phase has no agent.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'apolo-common.ps1')
if ($args.Count -lt 1) { Write-ErrorLine 'usage: resolve-agents.ps1 <agents.yml> [project.conf] [--implementer AGENT]'; exit 1 }
$table = [string]$args[0]; $conf = ''; $implementer = ''
for ($i = 1; $i -lt $args.Count; $i++) {
  if ($args[$i] -eq '--implementer') { $implementer = [string]$args[$i + 1]; $i++ } else { $conf = [string]$args[$i] }
}
try {
  [Console]::Out.Write((Format-AgentTable (Resolve-AgentTable $table $conf $implementer)) + "`n")
} catch {
  Write-ErrorLine $_.Exception.Message
  exit 1
}
exit 0
