$ErrorActionPreference = "Stop"

$binDirectory = "C:\Users\Public\Downloads"
Set-Location -Path $binDirectory

$taskCount = 60 / ${terminationNotificationDetectionIntervalSeconds}
$nextMinute = (Get-Date).Minute + 1
for ($i = 0; $i -lt $taskCount; $i++) {
  $taskName = "AAA Event Handler $i"
  $taskInterval = New-TimeSpan -Minutes 1
  $taskStart = Get-Date -Minute $nextMinute -Second ($i * ${terminationNotificationDetectionIntervalSeconds})
  $taskAction = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-ExecutionPolicy Unrestricted -File $binDirectory\onTerminate.ps1"
  $taskTrigger = New-ScheduledTaskTrigger -RepetitionInterval $taskInterval -At $taskStart -Once
  Register-ScheduledTask -TaskName $taskName -Action $taskAction -Trigger $taskTrigger -AsJob -User System -Force
}

$fsMountsFile = "$binDirectory\fs-mounts.bat"
New-Item -ItemType File -Path $fsMountsFile
%{ for fsMount in fileSystemMountsStorage }
  Add-Content -Path $fsMountsFile -Value "${fsMount}"
%{ endfor }
%{ for fsMount in fileSystemMountsStorageCache }
  Add-Content -Path $fsMountsFile -Value "${fsMount}"
%{ endfor }
%{ for fsMount in fileSystemMountsQube }
  Add-Content -Path $fsMountsFile -Value "${fsMount}"
%{ endfor }
%{ for fsMount in fileSystemMountsDeadline }
  Add-Content -Path $fsMountsFile -Value "${fsMount}"
%{ endfor }

$fsMountsFileSize = (Get-Item -Path $fsMountsFile).Length
if ($fsMountsFileSize -gt 0) {
  $taskName = "AAA File System Mounts"
  $taskAction = New-ScheduledTaskAction -Execute $fsMountsFile
  $taskTrigger = New-ScheduledTaskTrigger -AtStartup
  Register-ScheduledTask -TaskName $taskName -Action $taskAction -Trigger $taskTrigger -AsJob -User System -Force
  Start-Process -FilePath $fsMountsFile -Wait -RedirectStandardOutput "fs-mounts.output.txt" -RedirectStandardError "fs-mounts.error.txt"
}

%{ for fsPermission in fileSystemPermissions }
  ${fsPermission}
%{ endfor }
