# Shared helpers for the Windows (PowerShell 5.1 / pwsh 7) scripts. Dot-sourced; keep this file ASCII.
Set-StrictMode -Version 2.0

$script:ApoloIsWindows = [Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT
$script:Utf8NoBom = New-Object System.Text.UTF8Encoding $false

function Write-Utf8File([string]$Path, [string]$Text) {
  [System.IO.File]::WriteAllText($Path, $Text, $script:Utf8NoBom)
}

function Add-Utf8File([string]$Path, [string]$Text) {
  [System.IO.File]::AppendAllText($Path, $Text, $script:Utf8NoBom)
}

function Write-ErrorLine([string]$Text) {
  [Console]::Error.WriteLine($Text)
}

# The host that runs these scripts (powershell.exe or pwsh.exe); scheduled tasks and the agent runner reuse it.
function Get-HostExecutable {
  return (Get-Process -Id $PID).Path
}

# Windows command-line quoting (CommandLineToArgvW rules); .NET applies the same rules on Linux.
function ConvertTo-WinArg([string]$Value) {
  if ($Value.Length -gt 0 -and $Value -notmatch '[\s"]') { return $Value }
  $builder = New-Object System.Text.StringBuilder
  [void]$builder.Append('"')
  $slashes = 0
  foreach ($c in $Value.ToCharArray()) {
    if ($c -eq '\') { $slashes++; continue }
    if ($c -eq '"') {
      [void]$builder.Append(('\' * ($slashes * 2 + 1)) + '"')
    } else {
      [void]$builder.Append(('\' * $slashes) + $c)
    }
    $slashes = 0
  }
  [void]$builder.Append(('\' * ($slashes * 2)) + '"')
  return $builder.ToString()
}

# Starts a native program without a shell. .cmd/.bat shims (npm installs claude.cmd, codex.cmd) go through
# cmd.exe /d /s /c. -StdinFile feeds a file as standard input; output is captured as UTF-8.
function Start-Native {
  param(
    [Parameter(Mandatory = $true)][string]$FilePath,
    [string[]]$Arguments = @(),
    [string]$StdinFile = '',
    [string]$WorkingDirectory = '',
    [hashtable]$Set = @{},
    [string[]]$Unset = @()
  )
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $argText = (@($Arguments) | ForEach-Object { ConvertTo-WinArg ([string]$_) }) -join ' '
  if ($script:ApoloIsWindows -and $FilePath -match '\.(cmd|bat)$') {
    $psi.FileName = $env:ComSpec
    $psi.Arguments = '/d /s /c "' + (ConvertTo-WinArg $FilePath) + ' ' + $argText + '"'
  } else {
    $psi.FileName = $FilePath
    $psi.Arguments = $argText
  }
  $psi.UseShellExecute = $false
  $psi.CreateNoWindow = $true
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $psi.RedirectStandardInput = $true
  $psi.StandardOutputEncoding = $script:Utf8NoBom
  $psi.StandardErrorEncoding = $script:Utf8NoBom
  if ($WorkingDirectory) { $psi.WorkingDirectory = $WorkingDirectory }
  foreach ($name in $Unset) {
    if ($psi.EnvironmentVariables.ContainsKey($name)) { $psi.EnvironmentVariables.Remove($name) }
  }
  foreach ($name in $Set.Keys) { $psi.EnvironmentVariables[$name] = [string]$Set[$name] }
  $process = [System.Diagnostics.Process]::Start($psi)
  $stdout = $process.StandardOutput.ReadToEndAsync()
  $stderr = $process.StandardError.ReadToEndAsync()
  try {
    if ($StdinFile) {
      $bytes = [System.IO.File]::ReadAllBytes($StdinFile)
      $process.StandardInput.BaseStream.Write($bytes, 0, $bytes.Length)
    }
    $process.StandardInput.Close()
  } catch {
    # The program may exit without reading its input; its exit code tells the story.
  }
  return [pscustomobject]@{ Process = $process; Out = $stdout; Err = $stderr }
}

function Stop-ProcessTree([System.Diagnostics.Process]$Process) {
  try {
    if ($script:ApoloIsWindows) {
      & "$env:SystemRoot\System32\taskkill.exe" /PID $Process.Id /T /F 2>$null | Out-Null
    } elseif ($PSVersionTable.PSVersion.Major -ge 7) {
      $Process.Kill($true)
    } else {
      $Process.Kill()
    }
  } catch { }
}

function Wait-Native($Handle, [int]$TimeoutSeconds = 0) {
  $timeoutMs = -1
  if ($TimeoutSeconds -gt 0) { $timeoutMs = $TimeoutSeconds * 1000 }
  $timedOut = -not $Handle.Process.WaitForExit($timeoutMs)
  if ($timedOut) {
    Stop-ProcessTree $Handle.Process
    [void]$Handle.Process.WaitForExit(15000)
  }
  $Handle.Process.WaitForExit()
  $code = $Handle.Process.ExitCode
  if ($timedOut) { $code = 124 }
  return [pscustomobject]@{ ExitCode = $code; Stdout = $Handle.Out.Result; Stderr = $Handle.Err.Result; TimedOut = $timedOut }
}

function Invoke-Native {
  param([string]$FilePath, [string[]]$Arguments = @(), [string]$StdinFile = '', [string]$WorkingDirectory = '',
    [hashtable]$Set = @{}, [string[]]$Unset = @(), [int]$TimeoutSeconds = 0)
  $handle = Start-Native -FilePath $FilePath -Arguments $Arguments -StdinFile $StdinFile -WorkingDirectory $WorkingDirectory -Set $Set -Unset $Unset
  return Wait-Native $handle $TimeoutSeconds
}

# Resolves a tool to an absolute program path: an existing file path as given, else PATH lookup that prefers
# .exe and .cmd (npm shims) over .ps1, so the result can be started without a PowerShell host.
function Resolve-Tool([string]$Name) {
  if (-not $Name) { return $null }
  if ([System.IO.Path]::IsPathRooted($Name) -or $Name.Contains('\') -or $Name.Contains('/')) {
    if (Test-Path -LiteralPath $Name -PathType Leaf) { return (Resolve-Path -LiteralPath $Name).ProviderPath }
    return $null
  }
  $found = @(Get-Command -Name $Name -CommandType Application -ErrorAction SilentlyContinue)
  if ($script:ApoloIsWindows) {
    foreach ($ext in @('.exe', '.cmd', '.bat', '.com')) {
      foreach ($item in $found) { if ($item.Source -like "*$ext") { return $item.Source } }
    }
  }
  foreach ($item in $found) { if ($item.Source -notlike '*.ps1') { return $item.Source } }
  return $null
}

function Get-LinkTarget([string]$Path) {
  $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
  if ($null -eq $item) { return $null }
  if (-not ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint)) { return $null }
  $target = $null
  if ($item.PSObject.Properties['LinkTarget'] -and $item.LinkTarget) { $target = $item.LinkTarget }
  elseif ($item.PSObject.Properties['Target'] -and $item.Target) { $target = @($item.Target)[0] }
  if (-not $target) { return '' }
  $target = [string]$target
  foreach ($prefix in @('\\?\', '\??\')) {
    if ($target.StartsWith($prefix)) { $target = $target.Substring($prefix.Length) }
  }
  return $target
}

function Test-IsLink([string]$Path) {
  return $null -ne (Get-LinkTarget $Path)
}

function Test-PathOrLink([string]$Path) {
  return (Test-Path -LiteralPath $Path) -or (Test-IsLink $Path)
}

# Directory links: a symbolic link when allowed (Developer Mode or admin), else a junction, which needs neither.
# APOLO_SDLC_NO_SYMLINK=1 forces the junction path (used by the Windows CI).
function New-DirectoryLink([string]$Link, [string]$Target) {
  if ($env:APOLO_SDLC_NO_SYMLINK -ne '1') {
    try {
      New-Item -ItemType SymbolicLink -Path $Link -Value $Target -ErrorAction Stop | Out-Null
      return 'symbolic link'
    } catch { }
  }
  if ($script:ApoloIsWindows) {
    New-Item -ItemType Junction -Path $Link -Value $Target -ErrorAction Stop | Out-Null
    return 'junction'
  }
  throw "could not create a link at $Link"
}

# Files: symbolic link, else hard link (same volume), else a copy.
function New-FileLink([string]$Link, [string]$Target) {
  if ($env:APOLO_SDLC_NO_SYMLINK -ne '1') {
    try { New-Item -ItemType SymbolicLink -Path $Link -Value $Target -ErrorAction Stop | Out-Null; return 'symbolic link' } catch { }
  }
  try { New-Item -ItemType HardLink -Path $Link -Value $Target -ErrorAction Stop | Out-Null; return 'hard link' } catch { }
  Copy-Item -LiteralPath $Target -Destination $Link -ErrorAction Stop
  return 'copy'
}

# Removes only the link, never what it points to (Remove-Item -Recurse on a junction can delete the target).
function Remove-Link([string]$Path) {
  try { [System.IO.Directory]::Delete($Path, $false) } catch { [System.IO.File]::Delete($Path) }
  if (Test-IsLink $Path) { throw "could not remove link $Path" }
}

function Get-Sha256Hex([string]$Text) {
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    $bytes = $sha.ComputeHash($script:Utf8NoBom.GetBytes($Text))
    return (($bytes | ForEach-Object { $_.ToString('x2') }) -join '')
  } finally { $sha.Dispose() }
}

# --- agents.yml (same subset of YAML the shell scripts read with sed) ---
function Get-YamlSection([string[]]$Lines, [string]$Name) {
  $inside = $false
  $result = New-Object System.Collections.Generic.List[string]
  foreach ($line in $Lines) {
    if ($line -match "^$([regex]::Escape($Name)):") { $inside = $true; continue }
    if ($inside -and $line -match '^[a-z]') { break }
    if ($inside) { $result.Add($line) }
  }
  return ,$result.ToArray()
}

function Get-YamlEntry([string[]]$Section, [string]$Key, [string]$Pattern) {
  foreach ($line in $Section) {
    if ($line -match "^  $([regex]::Escape($Key)): *$Pattern") { return $Matches[1] }
  }
  return ''
}

function Get-YamlScalar([string[]]$Lines, [string]$Key) {
  foreach ($line in $Lines) {
    if ($line -match "^$([regex]::Escape($Key)): *(.*)$") { return $Matches[1].Trim() }
  }
  return ''
}

function Read-Lines([string]$Path) {
  return ,([System.IO.File]::ReadAllLines($Path) | ForEach-Object { $_.TrimEnd("`r") })
}

function Get-ConfValue([string]$ConfPath, [string]$Key) {
  if (-not $ConfPath -or -not (Test-Path -LiteralPath $ConfPath -PathType Leaf)) { return '' }
  foreach ($line in (Read-Lines $ConfPath)) {
    if ($line.StartsWith("$Key=")) { return $line.Substring($Key.Length + 1) }
  }
  return ''
}

$script:KnownAgents = @('claude', 'codex', 'grok', 'gemini')

function Get-AgentCommand([string[]]$TableLines, [string]$Agent) {
  return Get-YamlEntry (Get-YamlSection $TableLines 'commands') $Agent "'(.*)'"
}

function Test-AgentAvailable([string[]]$TableLines, [string]$Conf, [string]$Agent) {
  if (-not (Get-AgentCommand $TableLines $Agent)) { return $false }
  if ($Conf) {
    $bin = Get-ConfValue $Conf "${Agent}_bin"
    return [bool]($bin -and (Test-Path -LiteralPath $bin -PathType Leaf))
  }
  return [bool](Resolve-Tool $Agent)
}

# Same rules as scripts/resolve-agents.sh; throws "agents.yml: ..." on an invalid table.
function Resolve-AgentTable([string]$Table, [string]$Conf = '', [string]$Implementer = '') {
  if (-not (Test-Path -LiteralPath $Table -PathType Leaf)) { throw "agents table not found: $Table" }
  $lines = Read-Lines $Table
  $phases = Get-YamlSection $lines 'phases'
  $writers = ' ' + (Get-YamlScalar $lines 'write_capable') + ' '
  $known = $script:KnownAgents
  foreach ($p in @('design', 'goldfish', 'implement', 'review', 'tiebreak')) {
    $a = Get-YamlEntry $phases $p '([a-z]+)'
    if (-not $a) { throw "agents.yml: phase $p is missing" }
    if ($known -notcontains $a) { throw "agents.yml: phase $p uses unknown agent '$a'" }
  }
  $design = Get-YamlEntry $phases 'design' '([a-z]+)'
  if (-not $writers.Contains(" $design ")) { throw "agents.yml: design agent $design is not write-capable" }
  if (-not (Test-AgentAvailable $lines $Conf $design)) { throw "agents.yml: design agent $design is not available (set ${design}_bin or its command)" }
  $impl = $Implementer
  if (-not $impl) { $impl = Get-YamlEntry $phases 'implement' '([a-z]+)' }
  if (-not $writers.Contains(" $impl ")) { throw "agents.yml: implement agent $impl is not write-capable" }
  if (-not (Test-AgentAvailable $lines $Conf $impl)) { throw "agents.yml: implement agent $impl is not available (set ${impl}_bin or its command)" }

  $pick = {
    param($want, $last, [string[]]$exclude)
    foreach ($candidate in @($want) + $known) {
      if ($exclude -contains $candidate) { continue }
      if (Test-AgentAvailable $lines $Conf $candidate) { return $candidate }
    }
    return $last
  }
  $goldfish = Get-YamlEntry $phases 'goldfish' '([a-z]+)'
  if (-not (Test-AgentAvailable $lines $Conf $goldfish)) { $goldfish = $design }
  $review = & $pick (Get-YamlEntry $phases 'review' '([a-z]+)') 'blocked' @($impl)
  $tiebreak = & $pick (Get-YamlEntry $phases 'tiebreak' '([a-z]+)') 'human' @($impl, $review)
  $pool = @()
  foreach ($a in ((Get-YamlScalar $lines 'goldfish_agents') -split '\s+' | Where-Object { $_ })) {
    if ($known -notcontains $a) { throw "agents.yml: goldfish_agents uses unknown agent '$a'" }
    if (Test-AgentAvailable $lines $Conf $a) { $pool += $a }
  }
  if ($pool.Count -eq 0) { $pool = @($design) }
  $result = New-Object System.Collections.Specialized.OrderedDictionary
  $result['design'] = $design
  $result['goldfish'] = $goldfish
  $result['implement'] = $impl
  $result['review'] = $review
  $result['tiebreak'] = $tiebreak
  $result['goldfish_pool'] = ($pool -join ',')
  return $result
}

function Format-AgentTable($Resolved) {
  return (($Resolved.Keys | ForEach-Object { "$_=$($Resolved[$_])" }) -join "`n")
}
