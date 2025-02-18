param (
  [string] $buildConfigEncoded
)

$ErrorActionPreference = "Stop"

$binPaths = ""
$binDirectory = "C:\Users\Public\Downloads"
Set-Location -Path $binDirectory

function StartProcess ($filePath, $argumentList, $logFile) {
  if ($logFile -eq $null) {
    if ($argumentList -eq $null) {
      Start-Process -FilePath $filePath -Wait
    } else {
      Start-Process -FilePath $filePath -ArgumentList $argumentList -Wait
    }
  } else {
    if ($argumentList -eq $null) {
      Start-Process -FilePath $filePath -Wait -RedirectStandardError $logFile-err.log -RedirectStandardOutput $logFile-out.log
    } else {
      Start-Process -FilePath $filePath -ArgumentList $argumentList -Wait -RedirectStandardError $logFile-err.log -RedirectStandardOutput $logFile-out.log
    }
    Get-Content -Path $logFile-err.log | Tee-Object -FilePath "$logFile.log" -Append
    Get-Content -Path $logFile-out.log | Tee-Object -FilePath "$logFile.log" -Append
    Remove-Item -Path $logFile-err.log, $logFile-out.log
  }
}

Write-Host "Customize (Start): Resize OS Disk"
$osDriveLetter = "C"
$partitionSizeActive = (Get-Partition -DriveLetter $osDriveLetter).Size
$partitionSizeRange = Get-PartitionSupportedSize -DriveLetter $osDriveLetter
if ($partitionSizeActive -lt $partitionSizeRange.SizeMax) {
  Resize-Partition -DriveLetter $osDriveLetter -Size $partitionSizeRange.SizeMax
}
Write-Host "Customize (End): Resize OS Disk"

Write-Host "Customize (Start): Image Build Parameters"
$buildConfigBytes = [System.Convert]::FromBase64String($buildConfigEncoded)
$buildConfig = [System.Text.Encoding]::UTF8.GetString($buildConfigBytes) | ConvertFrom-Json
$machineType = $buildConfig.machineType
$gpuProvider = $buildConfig.gpuProvider
$renderManager = $buildConfig.renderManager
$renderEngines = $buildConfig.renderEngines
$binStorageHost = $buildConfig.binStorageHost
$binStorageAuth = $buildConfig.binStorageAuth
$servicePassword = $buildConfig.servicePassword
Write-Host "Machine Type: $machineType"
Write-Host "GPU Provider: $gpuProvider"
Write-Host "Render Manager: $renderManager"
Write-Host "Render Engines: $renderEngines"
Write-Host "Customize (End): Image Build Parameters"

Write-Host "Customize (Start): Chocolatey"
$installType = "chocolatey"
$installFile = "$installType.ps1"
$downloadUrl = "https://community.chocolatey.org/install.ps1"
(New-Object System.Net.WebClient).DownloadFile($downloadUrl, (Join-Path -Path $pwd.Path -ChildPath $installFile))
StartProcess PowerShell.exe "-ExecutionPolicy Unrestricted -File .\$installFile" $installType
$binPathChoco = "C:\ProgramData\chocolatey"
$binPaths += ";$binPathChoco"
Write-Host "Customize (End): Chocolatey"

Write-Host "Customize (Start): Python"
$installType = "python"
StartProcess $binPathChoco\choco.exe "install $installType --confirm --no-progress" $installType
Write-Host "Customize (End): Python"

if ($machineType -eq "Workstation") {
  Write-Host "Customize (Start): Node.js"
  $installType = "nodejs"
  StartProcess $binPathChoco\choco.exe "install $installType --confirm --no-progress" $installType
  Write-Host "Customize (End): Node.js"
}

Write-Host "Customize (Start): Git"
$installType = "git"
StartProcess $binPathChoco\choco.exe "install $installType --confirm --no-progress" $installType
$binPathGit = "C:\Program Files\Git\bin"
$binPaths += ";$binPathGit"
Write-Host "Customize (End): Git"

Write-Host "Customize (Start): Visual Studio Build Tools"
$versionInfo = "2022"
$installType = "vs-build-tools"
$installFile = "vs_BuildTools.exe"
$downloadUrl = "$binStorageHost/VS/$versionInfo/$installFile$binStorageAuth"
(New-Object System.Net.WebClient).DownloadFile($downloadUrl, (Join-Path -Path $pwd.Path -ChildPath $installFile))
$componentIds = "--add Microsoft.VisualStudio.Component.Windows11SDK.22621"
$componentIds += " --add Microsoft.VisualStudio.Component.VC.CMake.Project"
$componentIds += " --add Microsoft.Component.MSBuild"
StartProcess .\$installFile "$componentIds --quiet --norestart" $installType
$binPathCMake = "C:\Program Files (x86)\Microsoft Visual Studio\$versionInfo\BuildTools\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin"
$binPathMSBuild = "C:\Program Files (x86)\Microsoft Visual Studio\$versionInfo\BuildTools\MSBuild\Current\Bin\amd64"
$binPaths += ";$binPathCMake;$binPathMSBuild"
Write-Host "Customize (End): Visual Studio Build Tools"

if ($gpuProvider -eq "AMD") {
  $installType = "amd-gpu"
  if ($machineType -like "*NG*" -and $machineType -like "*v1*") {
    Write-Host "Customize (Start): AMD GPU (NG v1)"
    $installFile = "$installType.zip"
    $downloadUrl = "https://go.microsoft.com/fwlink/?linkid=2234555"
    (New-Object System.Net.WebClient).DownloadFile($downloadUrl, (Join-Path -Path $pwd.Path -ChildPath $installFile))
    Expand-Archive -Path $installFile
    $certStore = Get-Item -Path "cert:LocalMachine\TrustedPublisher"
    $certStore.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadWrite)
    $filePath = ".\$installType\Packages\Drivers\Display\WT6A_INF\U0388197.cat"
    $signature = Get-AuthenticodeSignature -FilePath $filePath
    $certStore.Add($signature.SignerCertificate)
    $filePath = ".\$installType\Packages\Drivers\Display\WT6A_INF\amdfdans\AMDFDANS.cat"
    $signature = Get-AuthenticodeSignature -FilePath $filePath
    $certStore.Add($signature.SignerCertificate)
    $certStore.Close()
    StartProcess .\$installType\Setup.exe "-install -log $binDirectory\$installType.log" $null
    Write-Host "Customize (End): AMD GPU (NG v1)"
  } elseif ($machineType -like "*NV*" -and $machineType -like "*v4*") {
    Write-Host "Customize (Start): AMD GPU (NV v4)"
    $installFile = "$installType.exe"
    $downloadUrl = "https://go.microsoft.com/fwlink/?linkid=2175154"
    (New-Object System.Net.WebClient).DownloadFile($downloadUrl, (Join-Path -Path $pwd.Path -ChildPath $installFile))
    StartProcess .\$installFile /S $null
    StartProcess C:\AMD\AMD*\Setup.exe "-install -log $binDirectory\$installType.log" $null
    Write-Host "Customize (End): AMD GPU (NV v4)"
  }
} elseif ($gpuProvider -eq "NVIDIA") {
  Write-Host "Customize (Start): NVIDIA GPU (GRID)"
  $installType = "nvidia-gpu-grid"
  $installFile = "$installType.exe"
  $downloadUrl = "https://go.microsoft.com/fwlink/?linkid=874181"
  (New-Object System.Net.WebClient).DownloadFile($downloadUrl, (Join-Path -Path $pwd.Path -ChildPath $installFile))
  StartProcess .\$installFile "-s -n -log:$binDirectory\$installType" $null
  Write-Host "Customize (End): NVIDIA GPU (GRID)"

  Write-Host "Customize (Start): NVIDIA GPU (CUDA)"
  $versionInfo = "12.1.1"
  $installType = "nvidia-gpu-cuda"
  $installFile = "cuda_${versionInfo}_531.14_windows.exe"
  $downloadUrl = "$binStorageHost/NVIDIA/CUDA/$versionInfo/$installFile$binStorageAuth"
  (New-Object System.Net.WebClient).DownloadFile($downloadUrl, (Join-Path -Path $pwd.Path -ChildPath $installFile))
  StartProcess .\$installFile "-s -n -log:$binDirectory\$installType" $null
  Write-Host "Customize (End): NVIDIA GPU (CUDA)"

  Write-Host "Customize (Start): NVIDIA OptiX"
  $versionInfo = "7.7.0"
  $installType = "nvidia-optix"
  $installFile = "NVIDIA-OptiX-SDK-$versionInfo-win64-32649046.exe"
  $downloadUrl = "$binStorageHost/NVIDIA/OptiX/$versionInfo/$installFile$binStorageAuth"
  (New-Object System.Net.WebClient).DownloadFile($downloadUrl, (Join-Path -Path $pwd.Path -ChildPath $installFile))
  StartProcess .\$installFile "/S /O $binDirectory\$installType.log" $null
  $versionInfo = "v12.0"
  $sdkDirectory = "C:\ProgramData\NVIDIA Corporation\OptiX SDK $versionInfo\SDK"
  $buildDirectory = "$sdkDirectory\build"
  New-Item -ItemType Directory $buildDirectory
  StartProcess $binPathCMake\cmake.exe "-B ""$buildDirectory"" -S ""$sdkDirectory"" -D CUDA_TOOLKIT_ROOT_DIR=""C:\\Program Files\\NVIDIA GPU Computing Toolkit\\CUDA\\$versionInfo""" $installType-cmake
  StartProcess $binPathMSBuild\MSBuild.exe """$buildDirectory\OptiX-Samples.sln"" -p:Configuration=Release" $installType-msbuild
  $binPaths += ";$buildDirectory\bin\Release"
  Write-Host "Customize (End): NVIDIA OptiX"
}

if ($renderEngines -contains "Maya") {
  Write-Host "Customize (Start): Maya"
  $versionInfo = "2024_0_1"
  $installFile = "Autodesk_Maya_${versionInfo}_Update_Windows_64bit_dlm.zip"
  $downloadUrl = "$binStorageHost/Maya/$versionInfo/$installFile$binStorageAuth"
  (New-Object System.Net.WebClient).DownloadFile($downloadUrl, (Join-Path -Path $pwd.Path -ChildPath $installFile))
  Expand-Archive -Path $installFile
  Start-Process -FilePath .\Autodesk_Maya*\Autodesk_Maya*\Setup.exe -ArgumentList "--silent"
  Start-Sleep -Seconds 600
  $binPaths += ";C:\Program Files\Autodesk\Maya2024\bin"
  Write-Host "Customize (End): Maya"
}

if ($renderEngines -contains "PBRT") {
  Write-Host "Customize (Start): PBRT v3"
  $versionInfo = "v3"
  $installType = "pbrt-$versionInfo"
  $installPath = "C:\Program Files\PBRT"
  $installPathV3 = "$installPath\$versionInfo"
  StartProcess $binPathGit\git.exe "clone --recursive https://github.com/mmp/$installType.git" $installType-git
  New-Item -ItemType Directory -Path $installPathV3 -Force
  StartProcess $binPathCMake\cmake.exe "-B ""$installPathV3"" -S $binDirectory\$installType" $installType-cmake
  StartProcess $binPathMSBuild\MSBuild.exe """$installPathV3\PBRT-$versionInfo.sln"" -p:Configuration=Release" $installType-msbuild
  New-Item -ItemType SymbolicLink -Target $installPathV3\Release\pbrt.exe -Path $installPath\pbrt3.exe
  Write-Host "Customize (End): PBRT v3"

  Write-Host "Customize (Start): PBRT v4"
  $versionInfo = "v4"
  $installType = "pbrt-$versionInfo"
  $installPathV4 = "$installPath\$versionInfo"
  StartProcess $binPathGit\git.exe "clone --recursive https://github.com/mmp/$installType.git" $installType-git
  New-Item -ItemType Directory -Path $installPathV4 -Force
  StartProcess $binPathCMake\cmake.exe "-B ""$installPathV4"" -S $binDirectory\$installType" $installType-cmake
  StartProcess $binPathMSBuild\MSBuild.exe """$installPathV4\PBRT-$versionInfo.sln"" -p:Configuration=Release" $installType-msbuild
  New-Item -ItemType SymbolicLink -Target $installPathV4\Release\pbrt.exe -Path $installPath\pbrt4.exe
  Write-Host "Customize (End): PBRT v4"

  $binPaths += ";$installPath"
}

if ($renderEngines -contains "Houdini") {
  Write-Host "Customize (Start): Houdini"
  $versionInfo = "19.5.569"
  $versionEULA = "2021-10-13"
  $installType = "houdini"
  $installFile = "$installType-$versionInfo-win64-vc142.exe"
  $downloadUrl = "$binStorageHost/Houdini/$versionInfo/$installFile$binStorageAuth"
  (New-Object System.Net.WebClient).DownloadFile($downloadUrl, (Join-Path -Path $pwd.Path -ChildPath $installFile))
  if ($machineType -eq "Workstation") {
    $installArgs = "/MainApp=Yes"
  } else {
    $installArgs = "/HoudiniEngineOnly=Yes"
  }
  if ($renderEngines -contains "Maya") {
    $installArgs += " /EngineMaya=Yes"
  }
  if ($renderEngines -contains "Unreal") {
    $installArgs += " /EngineUnreal=Yes"
  }
  StartProcess .\$installFile "/S /AcceptEULA=$versionEULA $installArgs" $installType
  $binPaths += ";C:\Program Files\Side Effects Software\Houdini $versionInfo\bin"
  Write-Host "Customize (End): Houdini"
}

if ($renderEngines -contains "Blender") {
  Write-Host "Customize (Start): Blender"
  $versionInfo = "3.6.0"
  $installType = "blender"
  $installFile = "$installType-$versionInfo-windows-x64.msi"
  $downloadUrl = "$binStorageHost/Blender/$versionInfo/$installFile$binStorageAuth"
  (New-Object System.Net.WebClient).DownloadFile($downloadUrl, (Join-Path -Path $pwd.Path -ChildPath $installFile))
  StartProcess $installFile "/quiet /norestart /log $installType.log" $null
  $binPaths += ";C:\Program Files\Blender Foundation\Blender 3.6"
  Write-Host "Customize (End): Blender"
}

if ($renderEngines -contains "Unreal" -or $renderEngines -contains "Unreal+PixelStream") {
  Write-Host "Customize (Start): Visual Studio Workloads"
  $versionInfo = "2022"
  $installType = "unreal-visual-studio"
  $installFile = "VisualStudioSetup.exe"
  $downloadUrl = "$binStorageHost/VS/$versionInfo/$installFile$binStorageAuth"
  (New-Object System.Net.WebClient).DownloadFile($downloadUrl, (Join-Path -Path $pwd.Path -ChildPath $installFile))
  $componentIds = "--add Microsoft.Net.Component.4.8.SDK"
  $componentIds += " --add Microsoft.Net.Component.4.6.2.TargetingPack"
  $componentIds += " --add Microsoft.VisualStudio.Component.VC.Tools.x86.x64"
  $componentIds += " --add Microsoft.VisualStudio.Component.VSSDK"
  $componentIds += " --add Microsoft.VisualStudio.Workload.NativeGame"
  $componentIds += " --add Microsoft.VisualStudio.Workload.NativeDesktop"
  $componentIds += " --add Microsoft.VisualStudio.Workload.NativeCrossPlat"
  $componentIds += " --add Microsoft.VisualStudio.Workload.ManagedDesktop"
  $componentIds += " --add Microsoft.VisualStudio.Workload.Universal"
  StartProcess .\$installFile "$componentIds --quiet --norestart" $installType
  Write-Host "Customize (End): Visual Studio Workloads"

  Write-Host "Customize (Start): Unreal Engine Setup"
  $installType = "dotnet-fx3"
  StartProcess dism.exe "/Enable-Feature /FeatureName:NetFX3 /Online /All /NoRestart" $installType
  Set-Location -Path C:\
  $versionInfo = "5.2.1"
  $installType = "unreal-engine"
  $installFile = "UnrealEngine-$versionInfo-release.zip"
  $downloadUrl = "$binStorageHost/Unreal/$versionInfo/$installFile$binStorageAuth"
  (New-Object System.Net.WebClient).DownloadFile($downloadUrl, (Join-Path -Path $pwd.Path -ChildPath $installFile))
  Expand-Archive -Path $installFile

  $installPath = "C:\Program Files\Unreal"
  New-Item -ItemType Directory -Path $installPath
  Move-Item -Path "Unreal*\Unreal*\*" -Destination $installPath
  Remove-Item -Path "Unreal*" -Exclude "*.zip" -Recurse
  Set-Location -Path $binDirectory

  $buildPath = $installPath.Replace("\", "\\")
  $buildPath = "$buildPath\\Engine\\Binaries\\ThirdParty\\Windows\\DirectX\\x64\"
  $scriptFilePath = "$installPath\Engine\Source\Programs\ShaderCompileWorker\ShaderCompileWorker.Build.cs"
  $scriptFileText = Get-Content -Path $scriptFilePath
  $scriptFileText = $scriptFileText.Replace("DirectX.GetDllDir(Target) + ", "")
  $scriptFileText = $scriptFileText.Replace("d3dcompiler_47.dll", "$buildPath\d3dcompiler_47.dll")
  Set-Content -Path $scriptFilePath -Value $scriptFileText

  $installFile = "$installPath\Setup.bat"
  $scriptFilePath = $installFile
  $scriptFileText = Get-Content -Path $scriptFilePath
  $scriptFileText = $scriptFileText.Replace("/register", "/register /unattended")
  $scriptFileText = $scriptFileText.Replace("pause", "rem pause")
  Set-Content -Path $scriptFilePath -Value $scriptFileText

  StartProcess $installFile $null $installType-setup
  Write-Host "Customize (End): Unreal Engine Setup"

  Write-Host "Customize (Start): Unreal Project Files Generate"
  $installFile = "$installPath\GenerateProjectFiles.bat"
  $scriptFilePath = $installFile
  $scriptFileText = Get-Content -Path $scriptFilePath
  $scriptFileText = $scriptFileText.Replace("pause", "rem pause")
  Set-Content -Path $scriptFilePath -Value $scriptFileText
  $scriptFilePath = "$installPath\Engine\Build\BatchFiles\GenerateProjectFiles.bat"
  $scriptFileText = Get-Content -Path $scriptFilePath
  $scriptFileText = $scriptFileText.Replace("pause", "rem pause")
  Set-Content -Path $scriptFilePath -Value $scriptFileText
  StartProcess $installFile $null unreal-project-files-generate
  Write-Host "Customize (End): Unreal Project Files Generate"

  Write-Host "Customize (Start): Unreal Engine Build"
  [System.Environment]::SetEnvironmentVariable("MSBuildEnableWorkloadResolver", "false")
  [System.Environment]::SetEnvironmentVariable("MSBuildSDKsPath", "$installPath\Engine\Binaries\ThirdParty\DotNet\6.0.302\windows\sdk\6.0.302\Sdks")
  StartProcess $binPathMSBuild\MSBuild.exe """$installPath\UE5.sln"" -p:Configuration=""Development Editor"" -p:Platform=Win64 -restore" $installType-msbuild
  Write-Host "Customize (End): Unreal Engine Build"

  if ($renderEngines -contains "Unreal+PixelStream") {
    Write-Host "Customize (Start): Unreal Pixel Streaming"
    $versionInfo = "5.2-0.6.5"
    $installType = "unreal-stream"
    $installFile = "UE$versionInfo.zip"
    $downloadUrl = "$binStorageHost/Unreal/PixelStream/$versionInfo/$installFile$binStorageAuth"
    (New-Object System.Net.WebClient).DownloadFile($downloadUrl, (Join-Path -Path $pwd.Path -ChildPath $installFile))
    Expand-Archive -Path $installFile
    $installFile = "UE$versionInfo\PixelStreamingInfrastructure-$versionInfo\SignallingWebServer\platform_scripts\cmd\setup.bat"
    StartProcess .\$installFile $null $installType-signalling
    $installFile = "UE$versionInfo\PixelStreamingInfrastructure-$versionInfo\Matchmaker\platform_scripts\cmd\setup.bat"
    StartProcess .\$installFile $null $installType-matchmaker
    $installFile = "UE$versionInfo\PixelStreamingInfrastructure-$versionInfo\SFU\platform_scripts\cmd\setup.bat"
    StartProcess .\$installFile $null $installType-sfu
    Write-Host "Customize (End): Unreal Pixel Streaming"
  }

  $binPathUnreal = "$installPath\Engine\Binaries\Win64"
  $binPaths += ";$binPathUnreal"

  if ($machineType -eq "Workstation") {
    Write-Host "Customize (Start): Unreal Editor"
    netsh advfirewall firewall add rule name="Allow Unreal Editor" dir=in action=allow program="$binPathUnreal\UnrealEditor.exe"
    $shortcutPath = "$env:AllUsersProfile\Desktop\Unreal Editor.lnk"
    $scriptShell = New-Object -ComObject WScript.Shell
    $shortcut = $scriptShell.CreateShortcut($shortcutPath)
    $shortcut.WorkingDirectory = "$binPathUnreal"
    $shortcut.TargetPath = "$binPathUnreal\UnrealEditor.exe"
    $shortcut.Save()
    Write-Host "Customize (End): Unreal Editor"
  }
}

if ($machineType -eq "Scheduler") {
  Write-Host "Customize (Start): Azure CLI"
  $installType = "azure-cli"
  $installFile = "$installType.msi"
  $downloadUrl = "https://aka.ms/installazurecliwindows"
  (New-Object System.Net.WebClient).DownloadFile($downloadUrl, (Join-Path -Path $pwd.Path -ChildPath $installFile))
  StartProcess $installFile "/quiet /norestart /log $installType.log" $null
  Write-Host "Customize (End): Azure CLI"

  if ("$renderManager" -like "*Deadline*" -or "$renderManager" -like "*RoyalRender*") {
    Write-Host "Customize (Start): NFS Server"
    Install-WindowsFeature -Name "FS-NFS-Service"
    Write-Host "Customize (End): NFS Server"
  }
} else {
  Write-Host "Customize (Start): NFS Client"
  $installType = "nfs-client"
  StartProcess dism.exe "/Enable-Feature /FeatureName:ClientForNFS-Infrastructure /Online /All /NoRestart" $installType
  Write-Host "Customize (End): NFS Client"
}

if ("$renderManager" -like "*Deadline*") {
  $versionInfo = "10.2.1.0"
  $installRoot = "C:\Deadline"
  $databaseHost = $(hostname)
  $databasePort = 27100
  $databasePath = "C:\DeadlineDatabase"
  $certificateFile = "Deadline10Client.pfx"
  $binPathScheduler = "$installRoot\bin"

  Write-Host "Customize (Start): Deadline Download"
  $installFile = "Deadline-$versionInfo-windows-installers.zip"
  $downloadUrl = "$binStorageHost/Deadline/$versionInfo/$installFile$binStorageAuth"
  (New-Object System.Net.WebClient).DownloadFile($downloadUrl, (Join-Path -Path $pwd.Path -ChildPath $installFile))
  Expand-Archive -Path $installFile
  Write-Host "Customize (End): Deadline Download"

  Set-Location -Path Deadline*
  if ($machineType -eq "Scheduler") {
    Write-Host "Customize (Start): Deadline Server"
    netsh advfirewall firewall add rule name="Allow Deadline Database" dir=in action=allow protocol=TCP localport=$databasePort
    $installType = "deadline-repository"
    $installFile = "DeadlineRepository-$versionInfo-windows-installer.exe"
    StartProcess .\$installFile "--mode unattended --dbLicenseAcceptance accept --prefix $installRoot --dbhost $databaseHost --mongodir $databasePath --installmongodb true" $null
    Move-Item -Path $env:TMP\installbuilder_installer.log -Destination $binDirectory\deadline-repository.log
    Copy-Item -Path $databasePath\certs\$certificateFile -Destination $installRoot\$certificateFile
    New-NfsShare -Name "Deadline" -Path $installRoot -Permission ReadWrite
    Write-Host "Customize (End): Deadline Server"
  }

  Write-Host "Customize (Start): Deadline Client"
  netsh advfirewall firewall add rule name="Allow Deadline Worker" dir=in action=allow program="$binPathScheduler\deadlineworker.exe"
  netsh advfirewall firewall add rule name="Allow Deadline Monitor" dir=in action=allow program="$binPathScheduler\deadlinemonitor.exe"
  netsh advfirewall firewall add rule name="Allow Deadline Launcher" dir=in action=allow program="$binPathScheduler\deadlinelauncher.exe"
  $installFile = "DeadlineClient-$versionInfo-windows-installer.exe"
  $installArgs = "--mode unattended --prefix $installRoot"
  if ($machineType -eq "Scheduler") {
    $installArgs = "$installArgs --slavestartup false --launcherservice false"
  } else {
    if ($machineType -eq "Farm") {
      $workerStartup = "true"
    } else {
      $workerStartup = "false"
    }
    $installArgs = "$installArgs --slavestartup $workerStartup --launcherservice true"
  }
  StartProcess .\$installFile $installArgs $null
  Copy-Item -Path $env:TMP\installbuilder_installer.log -Destination $binDirectory\deadline-client.log
  Set-Location -Path $binDirectory
  Write-Host "Customize (End): Deadline Client"

  Write-Host "Customize (Start): Deadline Monitor"
  $shortcutPath = "$env:AllUsersProfile\Desktop\Deadline Monitor.lnk"
  $scriptShell = New-Object -ComObject WScript.Shell
  $shortcut = $scriptShell.CreateShortcut($shortcutPath)
  $shortcut.WorkingDirectory = $binPathScheduler
  $shortcut.TargetPath = "$binPathScheduler\deadlinemonitor.exe"
  $shortcut.Save()
  Write-Host "Customize (End): Deadline Monitor"

  $binPaths += ";$binPathScheduler"
}

if ("$renderManager" -like "*RoyalRender*") {
  $versionInfo = "9.0.06"
  $installRoot = "\RoyalRender"
  $binPathScheduler = "C:$installRoot\bin\win64"

  Write-Host "Customize (Start): Royal Render Download"
  $installFile = "RoyalRender__${versionInfo}__installer.zip"
  $downloadUrl = "$binStorageHost/RoyalRender/$versionInfo/$installFile$binStorageAuth"
  (New-Object System.Net.WebClient).DownloadFile($downloadUrl, (Join-Path -Path $pwd.Path -ChildPath $installFile))
  Expand-Archive -Path $installFile
  Write-Host "Customize (End): Royal Render Download"

  if ($machineType -eq "Scheduler") {
    Write-Host "Customize (Start): Royal Render Server"
    netsh advfirewall set public state off
    $installType = "royal-render"
    $installPath = "RoyalRender*"
    $installFile = "rrSetup_win.exe"
    $rrShareName = $installRoot.TrimStart("\")
    $rrRootShare = "\\$(hostname)$installRoot"
    New-Item -ItemType Directory -Path $installRoot
    New-SmbShare -Name $rrShareName -Path "C:$installRoot" -FullAccess "Everyone"
    StartProcess .\$installPath\$installPath\$installFile "-console -rrRoot $rrRootShare" $installType
    Remove-SmbShare -Name $rrShareName -Force
    New-NfsShare -Name "RoyalRender" -Path C:$installRoot -Permission ReadWrite
    Write-Host "Customize (End): Royal Render Server"
  } else {
    $binPathScheduler = "T:\bin\win64"
  }

  $binPaths += ";$binPathScheduler"

  Write-Host "Customize (Start): Royal Render Submitter"
  $shortcutPath = "$env:AllUsersProfile\Desktop\Royal Render Submitter.lnk"
  $scriptShell = New-Object -ComObject WScript.Shell
  $shortcut = $scriptShell.CreateShortcut($shortcutPath)
  $shortcut.WorkingDirectory = $binPathScheduler
  $shortcut.TargetPath = "$binPathScheduler\rrSubmitter.exe"
  $shortcut.Save()
  Write-Host "Customize (End): Royal Render Submitter"
}

if ("$renderManager" -like "*Qube*") {
  $versionInfo = "8.0-0"
  $installRoot = "C:\Program Files\pfx\qube"
  $binPathScheduler = "$installRoot\bin"

  Write-Host "Customize (Start): Strawberry Perl"
  $installType = "strawberryperl"
  StartProcess $binPathChoco\choco.exe "install $installType --confirm --no-progress" $installType
  Write-Host "Customize (End): Strawberry Perl"

  Write-Host "Customize (Start): Qube Core"
  $installType = "qube-core"
  $installFile = "$installType-$versionInfo-WIN32-6.3-x64.msi"
  $downloadUrl = "$binStorageHost/Qube/$versionInfo/$installFile$binStorageAuth"
  (New-Object System.Net.WebClient).DownloadFile($downloadUrl, (Join-Path -Path $pwd.Path -ChildPath $installFile))
  StartProcess $installFile "/quiet /norestart /log $installType.log" $null
  Write-Host "Customize (End): Qube Core"

  if ($machineType -eq "Scheduler") {
    Write-Host "Customize (Start): Qube Supervisor"
    netsh advfirewall firewall add rule name="Allow Qube Database" dir=in action=allow protocol=TCP localport=50055
    netsh advfirewall firewall add rule name="Allow Qube Supervisor (TCP)" dir=in action=allow protocol=TCP localport=50001,50002
    netsh advfirewall firewall add rule name="Allow Qube Supervisor (UDP)" dir=in action=allow protocol=UDP localport=50001,50002
    netsh advfirewall firewall add rule name="Allow Qube Supervisor Proxy" dir=in action=allow protocol=TCP localport=50555,50556
    $installType = "qube-supervisor"
    $installFile = "$installType-${versionInfo}-WIN32-6.3-x64.msi"
    $downloadUrl = "$binStorageHost/Qube/$versionInfo/$installFile$binStorageAuth"
    (New-Object System.Net.WebClient).DownloadFile($downloadUrl, (Join-Path -Path $pwd.Path -ChildPath $installFile))
    StartProcess $installFile "/quiet /norestart /log $installType.log" $null
    $binPaths += ";C:\Program Files\pfx\pgsql\bin"
    Write-Host "Customize (End): Qube Supervisor"

    Write-Host "Customize (Start): Qube Data Relay Agent (DRA)"
    netsh advfirewall firewall add rule name="Allow Qube Data Relay Agent (DRA)" dir=in action=allow protocol=TCP localport=5001
    $installType = "qube-dra"
    $installFile = "$installType-$versionInfo-WIN32-6.3-x64.msi"
    $downloadUrl = "$binStorageHost/Qube/$versionInfo/$installFile$binStorageAuth"
    (New-Object System.Net.WebClient).DownloadFile($downloadUrl, (Join-Path -Path $pwd.Path -ChildPath $installFile))
    StartProcess $installFile "/quiet /norestart /log $installType.log" $null
    Write-Host "Customize (End): Qube Data Relay Agent (DRA)"
  } else {
    Write-Host "Customize (Start): Qube Worker"
    netsh advfirewall firewall add rule name="Allow Qube Worker (TCP)" dir=in action=allow protocol=TCP localport=50011
    netsh advfirewall firewall add rule name="Allow Qube Worker (UDP)" dir=in action=allow protocol=UDP localport=50011
    $installType = "qube-worker"
    $installFile = "$installType-$versionInfo-WIN32-6.3-x64.msi"
    $downloadUrl = "$binStorageHost/Qube/$versionInfo/$installFile$binStorageAuth"
    (New-Object System.Net.WebClient).DownloadFile($downloadUrl, (Join-Path -Path $pwd.Path -ChildPath $installFile))
    StartProcess $installFile "/quiet /norestart /log $installType.log" $null
    Write-Host "Customize (End): Qube Worker"

    Write-Host "Customize (Start): Qube Client"
    $installType = "qube-client"
    $installFile = "$installType-$versionInfo-WIN32-6.3-x64.msi"
    $downloadUrl = "$binStorageHost/Qube/$versionInfo/$installFile$binStorageAuth"
    (New-Object System.Net.WebClient).DownloadFile($downloadUrl, (Join-Path -Path $pwd.Path -ChildPath $installFile))
    StartProcess $installFile "/quiet /norestart /log $installType.log" $null
    $shortcutPath = "$env:AllUsersProfile\Desktop\Qube Client.lnk"
    $scriptShell = New-Object -ComObject WScript.Shell
    $shortcut = $scriptShell.CreateShortcut($shortcutPath)
    $shortcut.WorkingDirectory = "$installRoot\QubeUI"
    $shortcut.TargetPath = "$installRoot\QubeUI\QubeUI.bat"
    $shortcut.IconLocation = "$installRoot\lib\install\qube_icon.ico"
    $shortcut.Save()
    Write-Host "Customize (End): Qube Client"

    $configFile = "C:\ProgramData\pfx\qube\qb.conf"
    $configFileText = Get-Content -Path $configFile
    $configFileText = $configFileText.Replace("#qb_supervisor =", "qb_supervisor = scheduler.artist.studio")
    $configFileText = $configFileText.Replace("#worker_cpus = 0", "worker_cpus = 1")
    Set-Content -Path $configFile -Value $configFileText
  }

  $binPaths += ";$binPathScheduler;$installRoot\sbin"
}

if ($machineType -eq "Farm") {
  Write-Host "Customize (Start): Privacy Experience"
  $registryKeyPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\OOBE"
  New-Item -ItemType Directory -Path $registryKeyPath -Force
  New-ItemProperty -Path $registryKeyPath -PropertyType DWORD -Name "DisablePrivacyExperience" -Value 1 -Force
  Write-Host "Customize (End): Privacy Experience"
}

if ($machineType -eq "Workstation") {
  Write-Host "Customize (Start): Teradici PCoIP"
  $versionInfo = "23.04.1"
  $installType = if ([string]::IsNullOrEmpty($gpuProvider)) {"pcoip-agent-standard"} else {"pcoip-agent-graphics"}
  $installFile = "${installType}_$versionInfo.exe"
  $downloadUrl = "$binStorageHost/Teradici/$versionInfo/$installFile$binStorageAuth"
  (New-Object System.Net.WebClient).DownloadFile($downloadUrl, (Join-Path -Path $pwd.Path -ChildPath $installFile))
  StartProcess .\$installFile "/S /NoPostReboot /Force" $installType
  Write-Host "Customize (End): Teradici PCoIP"
}

setx PATH "$env:PATH$binPaths" /m
