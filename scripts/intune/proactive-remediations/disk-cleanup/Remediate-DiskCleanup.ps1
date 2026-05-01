$TempFolders = @(
    "$env:TEMP"
    "$env:LOCALAPPDATA\Temp"
    "$env:LOCALAPPDATA\Microsoft\Windows\INetCache\"
    "$env:windir\Temp"
    "$env:windir\Prefetch"
)
foreach ($TempFolder in $TempFolders) {
    Get-ChildItem -Path $TempFolder -Recurse | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-7) } | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
}
