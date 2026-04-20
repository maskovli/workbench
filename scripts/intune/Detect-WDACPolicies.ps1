    # Check if WDAC policies are enforced
    $WDACStatus = Get-CimInstance -Namespace root\Microsoft\Windows\DeviceGuard -ClassName Win32_DeviceGuard

    $hash = @{
        WDACEnforced = $WDACStatus.SecurityPolicyEnforcementRequired
        WDACUserModeCodeIntegrity = $WDACStatus.UserModeCodeIntegrityPolicyEnforcementStatus
    }

    # Return the results as JSON
    return $hash | ConvertTo-Json -Compress
