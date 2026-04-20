# Intune PR - Detect Windows activation by specific key (last 5)
# Exit 0 = compliant, 1 = not compliant

# >>> SET YOUR KEY HERE (full key) <<<
$DesiredKey = 'GXJYB-NBKBP-H4C24-8PBR9-C7P48'

# Windows ApplicationID (SoftwareLicensingProduct.ApplicationID) 
# This GUID matches Windows family products
$WindowsAppId = '55c92734-d682-4d71-983e-d6ec3f16059f'

function Get-Last5 {
    param([Parameter(Mandatory)][string]$Key)
    $clean = ($Key -replace '[^A-Za-z0-9]', '').ToUpper()
    if ($clean.Length -lt 5) { throw "Provided key appears invalid or too short." }
    # Return last 5 characters
    -join $clean.Substring($clean.Length - 5, 5).ToCharArray()
}

try {
    $target5 = Get-Last5 -Key $DesiredKey

    $products = Get-CimInstance -ClassName SoftwareLicensingProduct -ErrorAction Stop |
        Where-Object { $_.ApplicationID -eq $WindowsAppId -and $_.PartialProductKey }

    if (-not $products) {
        Write-Output "No Windows SoftwareLicensingProduct entries with partial keys found."
        exit 1
    }

    # Find the product that has our last5
    $matches = $products | Where-Object { $_.PartialProductKey.ToUpper() -eq $target5 }
    if (-not $matches) {
        Write-Output "Desired key last5=$target5 not present on this device."
        exit 1
    }

    # Prefer a licensed match; otherwise first match
    $match = $matches | Where-Object { $_.LicenseStatus -eq 1 } | Select-Object -First 1
    if (-not $match) { $match = $matches | Select-Object -First 1 }

    Write-Output ("Found: Name='{0}' last5={1} LicenseStatus={2}" -f $match.Name, $match.PartialProductKey, $match.LicenseStatus)

    if ($match.LicenseStatus -eq 1) { exit 0 } else { exit 1 }
}
catch {
    Write-Output "Detection error: $($_.Exception.Message)"
    exit 1
}
