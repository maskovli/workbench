<#
.SYNOPSIS
  Intune PR Remediate: install specific Windows key and activate.

.NOTES
  - Uses slmgr.vbs via cscript to avoid popups.
  - Logs to %ProgramData%\Microsoft\IntuneManagementExtension\Logs\PR-Activation.log
  - Exit 0 = success, non-zero = failure
#>

param(
    # Provide your 25-character product key (with or without dashes)
    [string]$ProductKey = 'GXJYB-NBKBP-H4C24-8PBR9-C7P48',

    # Force uninstall current product key before install (slmgr /upk)
    [bool]$ForceUpk = $false
)

$logPath = Join-Path $env:ProgramData 'Microsoft\IntuneManagementExtension\Logs\PR-Activation.log'
$logDir  = Split-Path $logPath -Parent
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Force -Path $logDir | Out-Null }

function Write-Log {
    param([Parameter(Mandatory)][string]$Message)
    $ts = (Get-Date).ToString('s')
    "$ts`t$Message" | Out-File -FilePath $logPath -Encoding UTF8 -Append
    Write-Output $Message
}

function Get-Last5 {
    param([Parameter(Mandatory)][string]$Key)
    $clean = ($Key -replace '[^A-Za-z0-9]', '').ToUpper()
    if ($clean.Length -lt 5) { throw "Provided key appears invalid or too short." }
    -join $clean.Substring($clean.Length - 5, 5).ToCharArray()
}

# Paths
$slmgr  = Join-Path $env:WINDIR 'System32\slmgr.vbs'
$cscript = Join-Path $env:WINDIR 'System32\cscript.exe'

if (-not (Test-Path $slmgr))  { Write-Log "ERROR: $slmgr not found.";  exit 1 }
if (-not (Test-Path $cscript)){ Write-Log "ERROR: $cscript not found."; exit 1 }

try {
    $last5 = Get-Last5 -Key $ProductKey
    Write-Log "Starting remediation. Target key last5=$last5. ForceUpk=$ForceUpk"

    if ($ForceUpk) {
        Write-Log "Running: slmgr.vbs /upk"
        & $cscript //nologo $slmgr /upk | ForEach-Object { Write-Log $_ }
        Start-Sleep -Seconds 3
        # Optional: also clear product key from registry (for security hygiene)
        # Write-Log "Running: slmgr.vbs /cpky"
        # & $cscript //nologo $slmgr /cpky | ForEach-Object { Write-Log $_ }
    }

    Write-Log "Running: slmgr.vbs /ipk *****-*****-*****-*****-$last5"
    & $cscript //nologo $slmgr /ipk $ProductKey | ForEach-Object { Write-Log $_ }
    Start-Sleep -Seconds 5

    Write-Log "Running: slmgr.vbs /ato"
    & $cscript //nologo $slmgr /ato | ForEach-Object { Write-Log $_ }
    Start-Sleep -Seconds 8

    # Re-check status and ensure the installed key matches the requested one
    $WindowsAppId = '55c92734-d682-4d71-983e-d6ec3f16059f'
    $products = Get-CimInstance -ClassName SoftwareLicensingProduct -ErrorAction Stop |
        Where-Object { $_.ApplicationID -eq $WindowsAppId -and $_.PartialProductKey }

    if (-not $products) {
        Write-Log "FAILURE: No Windows SoftwareLicensingProduct entries found after activation."
        exit 1
    }

    $matches = $products | Where-Object { $_.PartialProductKey.ToUpper() -eq $last5 }
    if (-not $matches) {
        Write-Log "FAILURE: After activation, desired key last5=$last5 not present."
        exit 1
    }

    $candidate = $matches | Where-Object { $_.LicenseStatus -eq 1 } | Select-Object -First 1
    if (-not $candidate) { $candidate = $matches | Select-Object -First 1 }

    $currentLast5 = $candidate.PartialProductKey.ToUpper()
    $status       = [int]$candidate.LicenseStatus

    Write-Log "Post-check: Name='$($candidate.Name)' PartialProductKey=$currentLast5 LicenseStatus=$status"

    if ($status -eq 1 -and $currentLast5 -eq $last5) {
        Write-Log "SUCCESS: Device activated with desired key (last5=$last5)."
        exit 0
    } else {
        Write-Log "FAILURE: Activation state or key mismatch after remediation."
        exit 1
    }

} catch {
    Write-Log "ERROR during remediation: $($_.Exception.Message)"
    exit 1
}
