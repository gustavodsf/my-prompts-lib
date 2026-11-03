# Runs every Windows test suite in its own host process: tests\windows\run.ps1 [-Real]
param([switch]$Real)
$suites = @('install.Tests.ps1', 'lane.Tests.ps1', 'monitor.Tests.ps1')
if ($Real) { $suites += 'tasks-real.Tests.ps1' }
$exe = (Get-Process -Id $PID).Path
$failed = @()
foreach ($s in $suites) {
  & $exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot $s)
  if ($LASTEXITCODE -ne 0) { $failed += $s }
}
if ($failed.Count) { Write-Host "FAILED: $($failed -join ', ')"; exit 1 }
Write-Host 'All Windows suites passed.'
