$NewTeams = $null
$OldTeams = $null
$OldTeamsMachineWide = $null

$windowsAppsPath = "C:\Program Files\WindowsApps"
$NewTeamsSearch = "MSTeams_*_x64__*"
$NewTeams = Get-ChildItem -Path $windowsAppsPath -Directory -Filter $NewTeamsSearch  -ErrorAction SilentlyContinue

$OldTeams = Get-AppxPackage "Teams*" -AllUsers
ForEach ( $Architecture in "SOFTWARE", "SOFTWARE\Wow6432Node" ) {
    $UninstallKey = "HKLM:$Architecture\Microsoft\Windows\CurrentVersion\Uninstall" 
    if (Test-path $UninstallKey) {
        $OldTeamsMachineWide = Get-ChildItem -Path $UninstallKey | Get-ItemProperty | Where-Object {$_.DisplayName -match "Teams Machine-Wide Installer" } |Select-Object PSChildName -ExpandProperty PSChildName
    }
}
If ($OldTeamsMachineWide) {Write-Host "Old Teams Machine wide installer found";exit 1} #teams machine wide installer is installed will be uninstalled
elseif ($OldTeams) {Write-Host "Old Teams found";exit 1} #old teams is installed will be uninstalled
elseif ($NewTeams) {Write-Host "New Teams found";exit 0} #new teams is installed all is good
else {Write-Host "Failed detection of Teams";exit 1}