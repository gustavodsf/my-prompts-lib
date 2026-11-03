# Runs scripts/install.ps1 with the Task Scheduler mocks loaded: with-mocks.ps1 <installer args...>
. (Join-Path $PSScriptRoot 'mocks.ps1')
& (Join-Path (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'scripts') 'install.ps1') @args
exit $LASTEXITCODE
