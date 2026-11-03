# Task Scheduler stand-ins backed by a JSON file ($env:APOLO_TEST_TASKS). Functions win over cmdlets, so these
# replace the real ones on Windows too. APOLO_TEST_TASKS_FAIL=<substring> makes Register-ScheduledTask fail.
function Read-MockTasks {
  if (-not (Test-Path -LiteralPath $env:APOLO_TEST_TASKS)) { return @() }
  $text = [System.IO.File]::ReadAllText($env:APOLO_TEST_TASKS)
  if (-not $text.Trim()) { return @() }
  return @($text | ConvertFrom-Json)
}
function Write-MockTasks($Tasks) {
  $json = ConvertTo-Json -InputObject @($Tasks) -Depth 5
  [System.IO.File]::WriteAllText($env:APOLO_TEST_TASKS, $json)
}
function New-ScheduledTaskAction { param($Execute, $Argument, $WorkingDirectory) [pscustomobject]@{ Execute = $Execute; Arguments = $Argument; WorkingDirectory = $WorkingDirectory } }
function New-ScheduledTaskTrigger { param([switch]$Once, $At, $RepetitionInterval) [pscustomobject]@{ Minute = ([datetime]$At).Minute; IntervalMinutes = ([timespan]$RepetitionInterval).TotalMinutes } }
function New-ScheduledTaskSettingsSet { [pscustomobject]@{} }
function New-ScheduledTaskPrincipal { param($UserId, $LogonType, $RunLevel) [pscustomobject]@{ UserId = $UserId; LogonType = $LogonType } }
function Get-ScheduledTask { param($TaskPath, $TaskName, $ErrorAction)
  @(Read-MockTasks | Where-Object { $_.TaskPath -eq $TaskPath -and (-not $TaskName -or $_.TaskName -eq $TaskName) }) }
function Export-ScheduledTask { param($TaskName, $TaskPath)
  ConvertTo-Json -Depth 5 -InputObject (@(Read-MockTasks | Where-Object { $_.TaskPath -eq $TaskPath -and $_.TaskName -eq $TaskName })[0]) }
function Unregister-ScheduledTask { param($TaskName, $TaskPath, [switch]$Confirm, $ErrorAction)
  Write-MockTasks @(Read-MockTasks | Where-Object { -not ($_.TaskPath -eq $TaskPath -and $_.TaskName -eq $TaskName) }) }
function Register-ScheduledTask {
  param($TaskName, $TaskPath, $Action, $Trigger, $Settings, $Principal, $Description, $Xml, [switch]$Force)
  if ($env:APOLO_TEST_TASKS_FAIL -and $TaskName -like "*$($env:APOLO_TEST_TASKS_FAIL)*") { throw "mock registration failure for $TaskName" }
  if ($Xml) { $task = $Xml | ConvertFrom-Json }
  else {
    $task = [pscustomobject]@{ TaskName = $TaskName; TaskPath = $TaskPath; Description = $Description; Execute = $Action.Execute
      Arguments = $Action.Arguments; Minute = $Trigger.Minute; IntervalMinutes = $Trigger.IntervalMinutes; LogonType = [string]$Principal.LogonType }
  }
  $others = @(Read-MockTasks | Where-Object { -not ($_.TaskPath -eq $TaskPath -and $_.TaskName -eq $TaskName) })
  Write-MockTasks (@($others) + @($task))
  return $task
}
