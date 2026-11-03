# Shared test helpers: plain PowerShell (no Pester), runs on Windows PowerShell 5.1 and pwsh 7, Windows or Linux.
$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path (Join-Path $RepoRoot 'scripts') 'apolo-common.ps1')
$HostExe = Get-HostExecutable
$Sep = [System.IO.Path]::PathSeparator
$script:Failures = 0

function New-TestRoot([string]$Name) {
  # A space in every test path: paths with spaces must work everywhere.
  $root = Join-Path ([System.IO.Path]::GetTempPath()) ("apolo test $Name " + [guid]::NewGuid().ToString('N').Substring(0, 8))
  New-Item -ItemType Directory -Path $root | Out-Null
  return (Resolve-Path -LiteralPath $root).ProviderPath
}

function Fail-Test([string]$Message) { throw "FAIL: $Message" }
function Assert-True($Condition, [string]$Message) { if (-not $Condition) { Fail-Test $Message } }
function Assert-Contains([string]$Text, [string]$Needle, [string]$Message) {
  if (-not $Text.Contains($Needle)) { Fail-Test "$Message`n--- expected to contain: $Needle`n--- got:`n$Text" }
}
function Assert-NotContains([string]$Text, [string]$Needle, [string]$Message) {
  if ($Text.Contains($Needle)) { Fail-Test "$Message`n--- did not expect: $Needle`n--- got:`n$Text" }
}

function Get-RealGit {
  $git = Resolve-Tool 'git'
  if (-not $git) { throw 'git is required to run the tests' }
  return $git
}

function Get-BasePath {
  $dirs = @((Split-Path -Parent (Get-RealGit)))
  if ($ApoloIsWindows) { $dirs += @("$env:SystemRoot\System32", $env:SystemRoot) } else { $dirs += @('/usr/bin', '/bin') }
  return ($dirs -join $Sep)
}

# A fake CLI: <Name>.ps1 holds the logic; a shim (<Name>.cmd on Windows, <Name> on Linux) runs it with this host.
function New-Fake([string]$Dir, [string]$Name, [string]$Body) {
  New-Item -ItemType Directory -Force -Path $Dir | Out-Null
  $logic = Join-Path $Dir "$Name.ps1"
  Write-Utf8File $logic ("`$ErrorActionPreference = 'Stop'`n" + $Body + "`n")
  if ($ApoloIsWindows) {
    $shim = Join-Path $Dir "$Name.cmd"
    Write-Utf8File $shim ("@`"$HostExe`" -NoProfile -ExecutionPolicy Bypass -File `"%~dp0$Name.ps1`" %*`r`nexit /b %ERRORLEVEL%`r`n")
  } else {
    $shim = Join-Path $Dir $Name
    Write-Utf8File $shim ("#!/bin/sh`nexec '$HostExe' -NoProfile -File `"`$(dirname `"`$0`")/$Name.ps1`" `"`$@`"`n")
    & chmod +x $shim
  }
  return $shim
}

# Runs a script in a fresh host process and returns ExitCode, Stdout, Stderr and Output (both).
function Invoke-Script([string]$Script, [string[]]$Arguments = @(), [hashtable]$Set = @{}, [string[]]$Unset = @(), [string]$WorkingDirectory = '') {
  $all = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $Script) + $Arguments
  $r = Invoke-Native $HostExe $all -Set $Set -Unset $Unset -WorkingDirectory $WorkingDirectory
  $r | Add-Member -NotePropertyName Output -NotePropertyValue ($r.Stdout + $r.Stderr)
  return $r
}

function Invoke-TestBlock([string]$Name, [scriptblock]$Block) {
  try { & $Block; [Console]::Out.Write("ok   $Name`n") }
  catch { $script:Failures++; [Console]::Out.Write("FAIL $Name`n$($_.Exception.Message)`n$($_.ScriptStackTrace)`n") }
}

function Complete-Tests([string]$Suite) {
  if ($script:Failures -gt 0) { [Console]::Out.Write("FAIL: $Suite ($($script:Failures) failing)`n"); exit 1 }
  [Console]::Out.Write("PASS: $Suite`n"); exit 0
}
