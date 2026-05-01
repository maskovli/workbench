$UpdateSession = New-Object -ComObject Microsoft.Update.Session

$UpdateInstaller = $UpdateSession.CreateUpdateInstaller()

$SearchResult = $UpdateSession.CreateUpdateSearcher().Search("IsInstalled=0")

$UpdatesToInstall = New-Object -ComObject Microsoft.Update.UpdateColl

foreach ($Update in $SearchResult.Updates) {
    if ($Update.InstallationBehavior.CanRequestUserInput -eq $false) {
        $UpdatesToInstall.Add($Update) | Out-Null
    }
}

if ($UpdatesToInstall.Count -gt 0) {
    .Updates = 
    $InstallResult = $UpdateInstaller.Install()

    if ($InstallResult.ResultCode -eq 2) {
        Write-Output "Installation completed successfully."
        exit 0
    }
    else {
        Write-Output "Installation failed with error code $($InstallResult.ResultCode)."
        exit 1
    }
}
else {
    Write-Output "No updates to install."
    exit 0
}
