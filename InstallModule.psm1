# SPDX-License-Identifier: Apache-2.0
# Licensed to the Ed-Fi Alliance under one or more agreements.
# The Ed-Fi Alliance licenses this file to you under the Apache License, Version 2.0.
# See the LICENSE and NOTICES files in the project root for more information.

############################################################
 
# Author: Douglas Loyo, Sr. Solutions Architect @ MSDF
 
# Description: Wrapper script that downloads the necesarry binaries and executes Ed-Fi installers.

############################################################

# 0) Helper Functions
Function Start-Message 
{  
    Param(
        [Int32]$Seconds = 10,
        [string]$Message = "Pausing for 10 seconds..."
    )
    ForEach ($Count in (1..$Seconds))
    {   Write-Progress -Id 1 -Activity $Message -Status "Waiting for $Seconds seconds, $($Seconds - $Count) left" -PercentComplete (($Count / $Seconds) * 100)
        Start-Sleep -Seconds 1
    }
    Write-Progress -Id 1 -Activity $Message -Status "Completed" -PercentComplete 100 -Completed
}

Function Write-HostInfo($message) { 
    $divider = "----"
    for($i=0;$i -lt $message.length;$i++){ $divider += "-" }
    Write-Host $divider -ForegroundColor Cyan
    Write-Host " " $message -ForegroundColor Cyan
    Write-Host $divider -ForegroundColor Cyan 
}

Function Write-HostStep($message) { 
    Write-Host "*** " $message " ***"-ForegroundColor Green
}

Function Find-SoftwareInstalled($software) {
    # To debug use this in your powershell
    # (Get-ItemProperty HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*).DisplayName
    return (Get-ItemProperty HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*).DisplayName -Contains $software
}

Function Install-Chrome {
    if(!(Find-SoftwareInstalled "Google Chrome"))
    {
        Write-Host "Installing: Google Chrome..."
        choco install googlechrome -y --ignore-checksums
    }else{Write-Host "Skipping: Google Chrome as it is already installed."}
}

Function Install-NotepadPlusPlus {
    if(!(Find-SoftwareInstalled "Notepad++ (64-bit x64)"))
    {
        Write-Host "Installing: Notepad Plus Plus..."
        choco install notepadplusplus -y
    }else{Write-Host "Skipping: Notepad Plus Plus as it is already installed."}
}

Function Install-MsSSMS {
    if(!(Find-SoftwareInstalled 'SQL Server Management Studio'))
    {
        Write-Host "Installing: SSMS  Sql Server Management Studio..."
        choco install sql-server-management-studio -y
    }else{Write-Host "Skipping: SSMS  Sql Server Management Studio as it is already installed."}
}

Function Install-Chocolatey(){
    if(!(Test-Path "$($env:ProgramData)\chocolatey\choco.exe"))
    {
        #Ensure we use the windows compression as we have had issues with 7zip
        $env:chocolateyUseWindowsCompression = 'true'
        Write-Host "Installing: Cocholatey..."
        Set-ExecutionPolicy Bypass -Scope Process -Force; Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))
    }else{Write-Host "Skipping: Cocholatey is already installed."}
}

Function Install-IISPrerequisites() {
    $allPreReqsInstalled = $true;
    # Throw this infront 'IIS-ASP', to make fail.
    $prereqs = @('IIS-WebServerRole', 'IIS-WebServer', 'IIS-CommonHttpFeatures', 'IIS-HttpErrors', 'IIS-ApplicationDevelopment', 'NetFx4Extended-ASPNET45', 'IIS-NetFxExtensibility45', 'IIS-HealthAndDiagnostics', 'IIS-HttpLogging', 'IIS-Security', 'IIS-RequestFiltering', 'IIS-Performance', 'IIS-WebServerManagementTools', 'IIS-ManagementConsole', 'IIS-BasicAuthentication', 'IIS-WindowsAuthentication', 'IIS-StaticContent', 'IIS-DefaultDocument', 'IIS-ISAPIExtensions', 'IIS-ISAPIFilter', 'IIS-HttpCompressionStatic', 'IIS-ASPNET45');
    # 'IIS-IIS6ManagementCompatibility','IIS-Metabase', 'IIS-HttpRedirect', 'IIS-LoggingLibraries','IIS-RequestMonitor''IIS-HttpTracing','IIS-WebSockets', 'IIS-ApplicationInit'?

    Write-Host "Ensuring all IIS prerequisites are already installed."
    foreach ($p in $prereqs) {
        if ((Get-WindowsOptionalFeature -Online -FeatureName $p).State -eq "Disabled") { $allPreReqsInstalled = $false; Write-Host "Prerequisite not installed: $p" }
    }

    if ($allPreReqsInstalled) { Write-Host "Skipping: All IIS prerequisites are already installed." }
    else { Enable-WindowsOptionalFeature -Online -FeatureName $prereqs }
}

Function Find-IfMsSQLServerInstalled($serverInstance) {
    If(Test-Path 'HKLM:\Software\Microsoft\Microsoft SQL Server\Instance Names\SQL') { return $true }
    try {
        $server = New-Object Microsoft.SqlServer.Management.Smo.Server $serverInstance
        $ver = $server.Version.Major
        Write-Host " MsSQL Server version detected :" $ver
        return ($ver -ne $null)
    }
    Catch {return $false}
    
    return $false
}

Function Install-MsSQLServerExpress {
    if(!(Find-IfMsSQLServerInstalled "."))
    {
        Write-Host "Installing: MsSQL Server Express..."
        choco install sql-server-express -o -ia "'/IACCEPTSQLSERVERLICENSETERMS /Q /ACTION=install /INSTANCEID=MSSQLSERVER /INSTANCENAME=MSSQLSERVER /SECURITYMODE=SQL /SAPWD=EdfiUs3r /TCPENABLED=1 /UPDATEENABLED=FALSE'" -f -y
        #Refres env and reload path in the Shell
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
        refreshenv

        # Test to see if we need to close PowerShell and reopen.
        # If .Net is already installed then we need to check to see if the MsSQL commands for SMO are avaialble.
        # We do this check because if .net is not installed we will reboot later.
        if((IsNetVersionInstalled 4 8)){
            If(-Not (Find-PowershellCommand Restore-SqlDatabase)) {
                # Will need to restart so lets give the user a message and exit here.
                Write-BigMessage "SQl Server Express Requires a PowerShell Session Restart" "Please close this PowerShell window and open a new one as an Administrator and run install again."
                Write-Error "Please restart this Powershell session/window and try again." -ErrorAction Stop
            }
        }
    } else {
        Write-Host "Skipping: MsSQL Express there is already a SQL Server installed."
    }
}

Function Invoke-SQLCmdOnDb($sqlQuery, $connStr) {    
    Invoke-Sqlcmd -Query $sqlQuery  -ConnectionString $connStr
}

Function IsNetCoreVersionInstalled($version) {
    $DotNetCoreItems = Get-Item -ErrorAction SilentlyContinue -Path 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\Microsoft\Updates\.NET Core'
    $DotNetCoreItems.GetSubKeyNames() | Where-Object { $_ -Match "Microsoft .NET Core $version.*Windows Server Hosting" } | ForEach-Object {
        Write-Host "The host has installed $_"
        return $True
    }
    
    return $False
}

Function Install-NetCoreHostingBundle() {
    $ver = "3.1.15"
    if (!(IsNetCoreVersionInstalled $ver)) {
        Write-Host "Installing: .Net Core Version $ver"
        choco install dotnetcore-windowshosting --version=$ver -y
        # Will need to restart so lets give the user a message and exit here.
        Write-Host ".Net Core Hosting Bundle May Require a Restart. Please restart this computer and re run the install."
        Write-Error "Please Restart" -ErrorAction Stop
    }
    else { Write-Host "Skiping: .Net Core Version $ver as it is already installed." }
}

Function Install-NetCoreRuntime() {
    $ver = "3.1.12"
    if (!(IsNetCoreVersionInstalled $ver)) {
        Write-Host "Installing: .Net Core Runtime Version $ver"
        choco install dotnetcore-runtime --version=$ver -y
        # Will need to restart so lets give the user a message and exit here.
    }
    else { Write-Host "Skiping: .Net Core Runtime Version $ver as it is already installed." }
}

Function Install-EdFiPackageSource() {
    $isPackageSourceInstalled = (Get-PackageSource).Name -Contains 'EdFi@Release';
    if($isPackageSourceInstalled){
        Write-Host "Skipping registration of Ed-Fi Pacakge Source as it is already installed"
    }else{
        Write-Host "Installing Ed-Fi Pacakge Source..."
        Register-PackageSource -Name EdFi@Release -Location https://pkgs.dev.azure.com/ed-fi-alliance/Ed-Fi-Alliance-OSS/_packaging/EdFi%40Release/nuget/v2/ -ProviderName NuGet -Force
    }
}

Function Install-EdFiDatabases($dbBinaryPath, $mode, $plugins) {
    $configurationJsonFilePath = $dbBinaryPath + "configuration.json"
    # Load the JSON file and update config settings.
    $configJson = (Get-Content $configurationJsonFilePath | Out-String | ConvertFrom-Json)

    $connStrings = @{
        EdFi_Ods= "server=(local);trusted_connection=True;database=EdFi_{0};Application Name=EdFi.Ods.WebApi";
        EdFi_Admin = "server=(local);trusted_connection=True;database=EdFi_Admin;persist security info=True;Application Name=EdFi.Ods.WebApi";
        EdFi_Security= "server=(local);trusted_connection=True;database=EdFi_Security;Application Name=EdFi.Ods.WebApi";
        EdFi_Master= "server=(local);trusted_connection=True;database=master;Application Name=EdFi.Ods.WebApi";
    }

    $configJson.ApiSettings.Mode = $mode;
    $configJson.ApiSettings.Engine = "SQLServer";
    $configJson.ApiSettings.MinimalTemplateScript = "EdFiMinimalTemplate";
    $configJson.ApiSettings.PopulatedTemplateScript = "GrandBend";

    $configJson.ConnectionStrings = $connStrings;

    if($plugins) {
        $configJson.Plugin.Folder = "../../Plugin";
        $configJson.Plugin.Scripts = $plugins;
    }

    # Update File
    $configJson | ConvertTo-Json -depth 100 | Out-File $configurationJsonFilePath

    $pathDbInstallScript = $dbBinaryPath + "PostDeploy.ps1"

    Invoke-Expression -Command $pathDbInstallScript
}

Function Install-EdFiAPI($dbBinaryPath, $mode, $plugins) {

    $parameters = @{
        PackageVersion = "5.2.14406"
        DbConnectionInfo = @{
            Engine="SqlServer"
            Server="localhost"
            UseIntegratedSecurity=$true
        }
        InstallType = $mode   
    }

    $path = "$dbBinaryPath"+"Install-EdFiOdsWebApi.psm1"
    Write-Host $path;

    Import-Module $path

    Install-EdFiOdsWebApi @parameters

    #Lets check if they are installing TPMD or other plugins
    if($plugins) {
        $configurationJsonFilePath ="C:\inetpub\Ed-Fi\WebApi\appsettings.json"
        $configJson = (Get-Content $configurationJsonFilePath | Out-String | ConvertFrom-Json)
        $configJson.Plugin.Folder = "./Plugin";
        $configJson.Plugin.Scripts = $plugins;

        # Update File
        $configJson | ConvertTo-Json -depth 100 | Out-File $configurationJsonFilePath
    }

}

Function Install-EdFiDocs($dbBinaryPath) {

    $computerName = [System.Net.Dns]::GetHostName()

    $parameters = @{
        PackageVersion = "5.2.14406"
        WebApiVersionUrl = "https://$computerName/WebApi"
    }

    $path = "$dbBinaryPath"+"Install-EdFiOdsSwaggerUI.psm1"

    Import-Module $path

    Install-EdFiOdsSwaggerUI @parameters
}

Function Get-EdFiApiUrl() {
    $computerName = [System.Net.Dns]::GetHostName()
    return "https://$computerName/WebApi"
}

Function Install-EdFiSandboxAdmin($dbBinaryPath) {

    $parameters = @{
        PackageVersion = "5.2.14406"
        OAuthUrl = Get-EdFiApiUrl
    }

    $path = "$dbBinaryPath"+"Install-EdFiOdsSandboxAdmin.psm1"

    Import-Module $path

    Install-EdFiOdsSandboxAdmin @parameters
}

Function Install-EdFiAdminApp($pathToWorkingDir) {

    if($pathToWorkingDir -eq $null) {
        $pathToWorkingDir = "C:\Ed-Fi\BinWrapper\"
    }

    Write-Host "    Downloading Ed-Fi Admin App"
    $url = "https://odsassets.blob.core.windows.net/public/adminapp/AdminAppInstaller.2.2.0.zip"
    $outputpath = "$pathToWorkingDir\AdminAppInstaller.2.2.0.zip"
    Invoke-WebRequest -Uri $url -OutFile $outputpath

    # UnZip them to the destination folders.
    $installPath = "$pathToWorkingDir\AdminAppInstaller"
    Expand-Archive -LiteralPath $outputpath -DestinationPath $installPath -Force

    # Update the install.ps1
    $apiUrl = Get-EdFiApiUrl    
    $installPSFilePath = $installPath + "\install.ps1"
    Write-Host "    Updating the APIUrl to $apiUrl"
    $find = 'OdsApiUrl = ""'
    $replacementText = 'OdsApiUrl = "' + $apiUrl + '"'

    (Get-Content $installPSFilePath | Out-String) -replace $find, $replacementText | Out-File $installPSFilePath

    Invoke-Expression -Command $installPSFilePath
}

Function Install-EdFiCommonAssets($mode, $plugins) {
    # 1) Ensure the working directories exists
    $pathToWorkingDir = "C:\Ed-Fi\BinWrapper\"

    Write-Host "Step: Ensuring working path is accessible. (pathToWorkingDir)"
    New-Item -ItemType Directory -Force -Path $pathToWorkingDir

    Write-Host "Step: Ensure Prerequisits are installed."

    ## Install Prerequisits ##
    # Ensure the EdFi PackageSource is installed:
    Install-EdFiPackageSource
    Install-Chocolatey
    Install-IISPrerequisites
    Install-NetCoreHostingBundle
    Install-MsSQLServerExpress

    Write-Host "Step: Downloading all binaries."

    $binaries = @(  
            @{  name = "EdFi.Suite3.Installer.WebApi"; version = "5.2.59"; }
		    @{  name = "EdFi.Suite3.Installer.SwaggerUI"; version = "5.2.42"; }
		    @{  name = "EdFi.Suite3.Installer.SandboxAdmin"; version = "5.2.62"; }
		    @{  name = "EdFi.Suite3.RestApi.Databases"; version = "5.2.14406"; }
    )

    foreach ($b in $binaries) {
        Write-Host "Downloading " $b.name
        # Download
        Save-Package -Name $b.name -ProviderName NuGet -Source EdFi@Release -Path $pathToWorkingDir -RequiredVersion $b.version

        # Rename to .Zip
        $nupkgFileName = $b.name + "." + $b.version + ".nupkg"
        $srcPath = "$pathToWorkingDir\" + $nupkgFileName
        $zipFileName = $b.name + ".zip"
        $zipPath = "$pathToWorkingDir\" + $zipFileName

        if(Test-Path $zipPath){ Remove-Item $zipPath }
        Rename-Item -Path $srcPath -NewName $zipFileName -Force

        # UnZip them to the destination fodlers.
    
        $installPath = "$pathToWorkingDir\" + $b.name
    
        Expand-Archive -LiteralPath $zipPath -DestinationPath $installPath -Force
    }

    # Install EdFi Databases
    $dbBinaryPath = "$pathToWorkingDir" + $binaries[3].name + "\"
    Install-EdFiDatabases $dbBinaryPath $mode $plugins

    # Install EdFi API
    $apiBinaryPath = "$pathToWorkingDir" + $binaries[0].name + "\"
    Install-EdFiAPI $apiBinaryPath $mode $plugins

    # Install EdFi Docs / Swagger
    $docsBinaryPath = "$pathToWorkingDir" + $binaries[1].name + "\"
    Install-EdFiDocs $docsBinaryPath

    if($mode -eq "Sandbox") {
       Write-Host "Installing EdFi Sandbox Admin"
       $sandboxAdminBinaryPath = "$pathToWorkingDir" + $binaries[2].name + "\"
       Install-EdFiSandboxAdmin $sandboxAdminBinaryPath
    } else { 
        Write-Host "Installing EdFi Admin App"
        Install-EdFiAdminApp $pathToWorkingDir 
    }
    
}

Function Install-TPDMDescriptors($apiURL, $key, $secret, $pathToWorkingDir)
{

    Start-Message -Seconds 5 -Message "Install-TPDMDescriptors"

	if($pathToWorkingDir -eq $null) {
        $pathToWorkingDir = "C:\Ed-Fi\BinWrapper\"
    }
	
    # Download the lastest Zip 
    # TODO: Replace $url with official Ed-Fi URL when its made public in Tech Docs.
    Write-Host "    Downloading Ed-Fi-TPDMDataLoad.zip"
    $url = "http://toolwise.net/Ed-Fi-TPDMDataLoad.zip"
    $outputpath = "$pathToWorkingDir\Ed-Fi-TPDMDataLoad.zip"
    Invoke-WebRequest -Uri $url -OutFile $outputpath

    # UnZip them to the destination folders.
    $unzipPath = "$pathToWorkingDir\" # the Zip already contains destiantion folder. No need to do "$pathToWorkingDir\Ed-Fi-TPDMDataLoad"
    Expand-Archive -LiteralPath $outputpath -DestinationPath $unzipPath -Force

    $installPath = "$pathToWorkingDir\Ed-Fi-TPDMDataLoad"

    # Update the install.ps1
    #$apiUrl = Get-EdFiApiUrl    
    $installPSFilePath = $installPath + "\LoadBootstrapData.ps1"
    Write-Host "    Updating:"
    Write-Host "       - APIUrl to $apiUrl"
    Write-Host "       - Key to $key"
    Write-Host "       - Secret to $secret"
	
    $findApiUrl = '"-b", "http://localhost:54746/",'
    $replacementTextApiUrl = '"-b", "' + $apiUrl + '",'
    $findKey = '"-k", "minimalSandbox",'
    $replacementTextKey = '"-k", "'+$key+'",'
    $findSecret = '"-s", "minimumSandboxSecret",'
    $replacementTextSecret = '"-s", "'+$secret+'",'

    (Get-Content $installPSFilePath | Out-String) -replace $findApiUrl, $replacementTextApiUrl -replace $findKey, $replacementTextKey -replace $findSecret, $replacementTextSecret | Out-File $installPSFilePath
	Write-Host "    Done updating LoadBootstrapData.ps1 configuration parameters"
	
	#TODO: 
	# We need to ensure that vendor has the correct Namespaces: ('uri://ed-fi.org/','uri://tpdm.ed-fi.org', 'http://ed-fi.org') 
	# Then we need to ensure we have the "" claimset so that we can add the Descriptors;
	#    1) Get the current claimset for the application where the Key=$key, we have to restore it later.
	#    2) Set the application's claimset to "Bootstrap Descriptors and EdOrgs"
    # Add TPDM Namespace to the EdFi_Admin Db
	
	$EdFiAdminConn = "server=(local);trusted_connection=True;database=EdFi_Admin;persist security info=True;Application Name=EdFi.Ods.WebApi";						 
						 
	$sQLServer = "localhost"
	$dbEdFi_Admin = "EdFi_Admin"
    $dbEdFi_Ods = "EdFi_Ods"
    				 
	$sqlCurrentClaimsetAndVendor="SELECT Applications.ApplicationId, Applications.ClaimSetName, Vendor_VendorId
						 FROM dbo.Applications
						 INNER JOIN dbo.ApiClients on Applications.ApplicationId = ApiClients.Application_ApplicationId
						 WHERE ApiClients.[Key] = '"+$key+"';"
	
	$sqlResult =  Invoke-Sqlcmd  -ServerInstance $sQLServer -Database $dbEdFi_Admin -Query $sqlCurrentClaimsetAndVendor
    $applicationId = $sqlResult.Item(0)
	$claimSet = $sqlResult.Item(1)
    $vendorId = $sqlResult.Item(2)
    #Checking the Current Tpdm Descriptors
    $sqlCurrentTpdmDescriptors="SELECT COUNT(*) as TPDMDescriptorCount from edfi.Descriptor where Namespace like '%tpdm%';"
    $sqlDescriptorsResult =  Invoke-Sqlcmd  -ServerInstance $sQLServer -Database $dbEdFi_Ods -Query $sqlCurrentTpdmDescriptors
    $descriptorsCount = $sqlDescriptorsResult.Item(0)

	# cheking if the required namespaces exists
	$ensureNamespacePrefix = "
		IF NOT EXISTS ( SELECT * FROM VendorNamespacePrefixes WHERE Vendor_VendorId =  $vendorId AND NamespacePrefix = 'http://ed-fi.org')
		   BEGIN
			  INSERT INTO [dbo].[VendorNamespacePrefixes] ([NamespacePrefix],[Vendor_VendorId]) VALUES ('http://ed-fi.org' ,$vendorId)
		   END

		IF NOT EXISTS ( SELECT * FROM VendorNamespacePrefixes WHERE Vendor_VendorId = $vendorId AND NamespacePrefix = 'uri://tpdm.ed-fi.org')
			BEGIN
			  INSERT INTO [dbo].[VendorNamespacePrefixes] ([NamespacePrefix], [Vendor_VendorId]) VALUES ('uri://tpdm.ed-fi.org', $vendorId)
			END

		IF NOT EXISTS ( SELECT * FROM VendorNamespacePrefixes WHERE Vendor_VendorId = $vendorId AND NamespacePrefix = 'uri://ed-fi.org')
			BEGIN
			  INSERT INTO [dbo].[VendorNamespacePrefixes] ([NamespacePrefix], [Vendor_VendorId]) VALUES ('uri://ed-fi.org', $vendorId)
			END"
	
	Invoke-Sqlcmd -ServerInstance $sQLServer -Database $dbEdFi_Admin -Query  $ensureNamespacePrefix

	
    $sqlUpdApplicationClaimset="UPDATE [dbo].[Applications] SET [ClaimSetName] = 'Bootstrap Descriptors and EdOrgs' WHERE [ApplicationId] = $applicationId"
	
	Invoke-Sqlcmd  -ServerInstance $sQLServer -Database $dbEdFi_Admin -Query $sqlUpdApplicationClaimset

    # Run the LoadBootstrapData command on PowerShell
	Write-Host "    Executing the LoadBootstrapData.ps1 process..."

    Invoke-Expression -Command $installPSFilePath
	
	#TODO: Once everything ran we need to put the claimset back to what it was.
    $sqlRevertClaimset="UPDATE [dbo].[Applications] SET [ClaimSetName] = '" + $claimSet +"' WHERE [ApplicationId] = $applicationId"
								
	Invoke-Sqlcmd  -ServerInstance $sQLServer -Database $dbEdFi_Admin -Query $sqlRevertClaimset
	
	# Verify everything good...
    $sqlNewTpdmDescriptors="SELECT COUNT(*) as TPDMDescriptorCount from edfi.Descriptor where Namespace like '%tpdm%';"
    $sqlNewDescriptorsResult =  Invoke-Sqlcmd  -ServerInstance $sQLServer -Database $dbEdFi_Ods -Query $sqlNewTpdmDescriptors
    $newDescriptorsCount = $sqlNewDescriptorsResult.Item(0)
    $descriptorsAdded= $newDescriptorsCount-$descriptorsCount

    Write-Host "$descriptorsAdded TPDM Descriptors were added."
}

Function Install-EdFi520Sandbox { Install-EdFiCommonAssets "Sandbox" }
Function Install-EdFi520SharedInstance { Install-EdFiCommonAssets "SharedInstance" }

Function Install-EdFi520SandboxTPDM { 
    $plugins = @("tpdm")
    Install-EdFiCommonAssets "Sandbox" $plugins
}
Function Install-EdFi520SharedInstanceTPDM { 
    $plugins = @("tpdm")
    Install-EdFiCommonAssets "SharedInstance" $plugins 
}