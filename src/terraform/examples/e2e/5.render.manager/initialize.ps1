$ErrorActionPreference = "Stop"

$binDirectory = "C:\Users\Public\Downloads"
Set-Location -Path $binDirectory

$customDataInputFile = "C:\AzureData\CustomData.bin"
$customDataOutputFile = "C:\AzureData\scale.auto.ps1"
$fileStream = New-Object System.IO.FileStream($customDataInputFile, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read)
$streamReader = New-Object System.IO.StreamReader($fileStream)
Out-File -InputObject $streamReader.ReadToEnd() -FilePath $customDataOutputFile -Force

$taskName = "AAA Render Farm Auto Scale"
$taskStart = Get-Date
$taskInterval = New-TimeSpan -Seconds ${autoScale.detectionIntervalSeconds}
$taskAction = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-ExecutionPolicy Unrestricted -File $customDataOutputFile -resourceGroupName ${autoScale.resourceGroupName} -scaleSetName ${autoScale.scaleSetName} -jobWaitThresholdSeconds ${autoScale.jobWaitThresholdSeconds} -workerIdleDeleteSeconds ${autoScale.workerIdleDeleteSeconds}"
$taskTrigger = New-ScheduledTaskTrigger -RepetitionInterval $taskInterval -At $taskStart -Once
Register-ScheduledTask -TaskName $taskName -Action $taskAction -Trigger $taskTrigger -AsJob -User System -Force

while ($null -eq (Get-ScheduledTask $taskName -ErrorAction SilentlyContinue)) {
  Start-Sleep -Seconds 1
}
if ("${autoScale.enable}" -ne "true") {
  Disable-ScheduledTask -TaskName $taskName
}
