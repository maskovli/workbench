 # Get the status of the WinDefend service
 $service = Get-Service -Name WinDefend

 # Check if the service is running
 if ($service.Status -eq 'Running') {
     Write-Output "Microsoft Defender Antivirus service is running."
 } else {
     Write-Output "Microsoft Defender Antivirus service is not running."
 }
 
 # Get the status of Real-Time protection
 $realTimeProtectionEnabled = (Get-MpPreference).DisableRealtimeMonitoring
 
 # Check if Real-Time protection is enabled
 if (-not $realTimeProtectionEnabled) {
     Write-Output "Real-Time protection is enabled."
 } else {
     Write-Output "Real-Time protection is not enabled."
 } 