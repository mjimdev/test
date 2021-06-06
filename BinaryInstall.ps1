############################################################
 
# Author: Douglas Loyo, Sr. Solutions Architect @ MSDF
 
# Description: Downloads Ed-Fi binaries from the published MyGet feed and installs them.
#              After install it does appropriate configuration to have applications running.

# Note: This powershell has to be ran with Elevated Permissions (As Administrator) and in a x64 environment.
# Know issues and future todo's: (look at the .PSM1 file)
 
############################################################
#Requires -Version 5
#Requires -RunAsAdministrator

#Clear all errors before starting.
$error.clear()

# Base path to download files and store Logs and so.
$global:tempPathForBinaries = "C:\Ed-Fi\BinaryInstaller\"

Import-Module "$PSScriptRoot\InstallModule" -Force #-Verbose #-Force
# 1) Ensure the working directory exists
$global:pathToWorkingDir = "C:\Ed-Fi\BinaryInstaller\"
Write-Host "Step: Ensuring working path is accessible. ($global:pathToWorkingDir)"
New-Item -ItemType Directory -Force -Path $pathToWorkingDir


Write-HostInfo "Wrapper for the Ed-Fi binary installers."
Write-Host "To install Ed-Fi run any of the following commands:" 
Write-HostStep " Ed-Fi ODS/APi & Tools 5.2.0"
Write-Host " Install-EdFi520Sandbox"
Write-Host " Install-EdFi520SharedInstance"
Write-Host " Install-EdFi520SandboxTPDM"
Write-Host " Install-EdFi520SharedInstanceTPDM"
Write-HostStep " Other Tools:"
Write-Host "    Install-TPDMDescriptors 'apiURL' 'key' 'secret'"
Write-Host "    Install-Chocolatey" 
Write-Host "    Install-Chrome" 
Write-Host "    Install-MsSSMS"
Write-Host "    Install-NotepadPlusPlus"
Write-Host "" 