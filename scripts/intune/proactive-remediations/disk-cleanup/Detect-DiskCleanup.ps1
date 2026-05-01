$Threshold = 10GB

$FreeSpace = (Get-PSDrive -PSProvider FileSystem C).Free

if ($FreeSpace -lt $Threshold) {
    Write-Output "Disk space is critically low. Available space: $FreeSpace"
    exit 1
}
else {
    Write-Output "Disk space is sufficient. Available space: $FreeSpace"
    exit 0
}
