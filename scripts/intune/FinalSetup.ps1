## Install Rigel app
######################

# In the event that the app is already provisioned, DO NOT provision it again.
if ((get-appxprovisionedpackage -online |? {$_.DisplayName -eq "Microsoft.SkypeRoomSystem"}) -eq $null) {

    # Check if we are using store or dev package
    $licensePath = Get-Item $Env:SystemDrive\Rigel\x64\Ship\AppPackages\*\*.xml
    $isDevPackage = $false
    if ($licensePath -eq $null){
        $isDevPackage = $true
    }

    # Install certs and allow sideload if this is a dev package
    if ($isDevPackage)
    {
        # Allow apps to be sideloaded.
        reg.exe add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock" /f /v "AllowAllTrustedApps" /t REG_DWORD /d 1

        # Install the cert
        powershell.exe -executionpolicy unrestricted "$Env:SystemDrive\Rigel\x64\Scripts\Provisioning\cert.ps1"
    }

    # Install Rigel App for Future users
    $packagePath = Get-Item $Env:SystemDrive\Rigel\x64\Ship\AppPackages\*\*.appx
    $dependencyPath = Get-ChildItem $Env:SystemDrive\Rigel\x64\Ship\AppPackages\*\Dependencies\x64\*.appx | Foreach-Object {$_.FullName}
    $ProvisioningArguments = @{ "online" = $true; "PackagePath" = $packagePath; "DependencyPackagePath" = $dependencyPath }
    if ($isDevPackage){
        #Install test package without license file
        $ProvisioningArguments.add("SkipLicense", $true)
    }
    else {
        #Install store package with license file
        $ProvisioningArguments.add("LicensePath", $licensePath)
    }
    Add-AppxProvisionedPackage @ProvisioningArguments

}

# Register EventLog for ScriptLaunch
New-EventLog -LogName "ScriptLaunch" -Source "ScriptLaunch"
Limit-EventLog -LogName "ScriptLaunch" -MaximumSize 15168KB

# Let the app configure the OS
powershell -executionpolicy unrestricted "c:\Rigel\x64\Scripts\Provisioning\ScriptLaunch.ps1" Initialize.ps1