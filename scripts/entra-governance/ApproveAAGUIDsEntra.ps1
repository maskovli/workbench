# Define the Microsoft Graph API Endpoint for FIDO2 Key Approval
$GraphApiEndpoint = "https://graph.microsoft.com/beta/identity/authenticationMethodsPolicy/authenticationMethodConfigurations/Fido2SecurityKeys/allowedAAGUIDs"

# Function to detect OS
function Get-OS {
    if ($IsWindows) { return "Windows" }
    elseif ($IsMacOS) { return "macOS" }
    elseif ($IsLinux) { return "Linux" }
    else { return "Unknown" }
}

$OS = Get-OS
Write-Host "Detected OS: $OS"

# Function to fetch FIDO2 security keys and AAGUIDs from Microsoft Docs
function Get-Fido2Keys {
    $url = "https://learn.microsoft.com/en-us/entra/identity/authentication/concept-fido2-hardware-vendor"
    $response = Invoke-WebRequest -Uri $url -UseBasicParsing
    $htmlContent = $response.Content

    # Extract AAGUIDs using regex
    $matches = [regex]::Matches($htmlContent, '<td>([^<]+)</td>\s*<td>([0-9A-Fa-f-]{36})</td>')

    $fido2Keys = @()
    foreach ($match in $matches) {
        $fido2Keys += [PSCustomObject]@{
            "Security Key Name" = $match.Groups[1].Value.Trim()
            "AAGUID" = $match.Groups[2].Value.Trim()
        }
    }

    return $fido2Keys
}

# Function to authenticate with Microsoft Graph API
function Get-GraphToken {
    try {
        # Check if user is logged in
        $context = Get-MgContext
        if (-not $context) {
            Write-Host "⚠️ Not logged into Microsoft Graph. Attempting to connect..." -ForegroundColor Yellow
            Connect-MgGraph -Scopes "Policy.ReadWrite.AuthenticationMethod"
            $context = Get-MgContext
            if (-not $context) {
                throw "Graph authentication failed. Please sign in using Connect-MgGraph."
            }
        }

        # Retrieve token
        $token = Get-MgAccessToken
        return $token
    } catch {
        Write-Host "❌ Failed to retrieve Graph API token. Ensure you are logged in using Connect-MgGraph." -ForegroundColor Red
        exit 1
    }
}

# Function to select FIDO2 keys based on OS
function Select-Fido2Keys {
    param ([array]$fido2Keys)

    if ($OS -eq "Windows") {
        # Windows: Use Out-GridView
        return $fido2Keys | Out-GridView -Title "Select FIDO2 Security Keys to Approve" -PassThru
    } else {
        # macOS/Linux: Use text-based selection
        Write-Host "Select FIDO2 Security Keys to Approve (comma-separated):"
        $fido2Keys | ForEach-Object {
            $i = [array]::IndexOf($fido2Keys, $_) + 1
            Write-Host "$i: $($_.'Security Key Name') (AAGUID: $($_.AAGUID))"
        }

        $selection = Read-Host "Enter the numbers of the keys you want to approve (comma-separated)"
        $selectedIndexes = $selection -split ',' | ForEach-Object { $_.Trim() -as [int] }

        $selectedKeys = @()
        foreach ($index in $selectedIndexes) {
            if ($index -gt 0 -and $index -le $fido2Keys.Count) {
                $selectedKeys += $fido2Keys[$index - 1]
            }
        }

        return $selectedKeys
    }
}

# Function to add selected keys to Microsoft Entra ID
function Add-ApprovedFido2Keys {
    param ([array]$SelectedKeys)

    $token = Get-GraphToken
    $headers = @{
        "Authorization" = "Bearer $token"
        "Content-Type"  = "application/json"
    }

    foreach ($key in $SelectedKeys) {
        $aaguid = $key.AAGUID

        # Define the JSON payload
        $body = @{ "value" = $aaguid } | ConvertTo-Json -Depth 3

        try {
            # Make the API request
            $response = Invoke-RestMethod -Uri $GraphApiEndpoint -Headers $headers -Method POST -Body $body
            Write-Host "✅ Successfully added FIDO2 Key: $($key.'Security Key Name') (AAGUID: $aaguid)" -ForegroundColor Green
        } catch {
            Write-Host "❌ Failed to add FIDO2 Key: $($key.'Security Key Name') (AAGUID: $aaguid). Error: $_" -ForegroundColor Red
        }
    }
}

# Get the list of FIDO2 keys
$fido2Keys = Get-Fido2Keys

if ($fido2Keys.Count -eq 0) {
    Write-Host "⚠️ No FIDO2 keys were retrieved. Exiting script." -ForegroundColor Yellow
    exit 1
}

# Select keys based on OS
$selectedKeys = Select-Fido2Keys -fido2Keys $fido2Keys

# Add selected keys to Entra ID if any were selected
if ($selectedKeys.Count -gt 0) {
    Add-ApprovedFido2Keys -SelectedKeys $selectedKeys
} else {
    Write-Host "ℹ️ No keys were selected. Exiting script." -ForegroundColor Yellow
}



$url = "https://learn.microsoft.com/en-us/entra/identity/authentication/concept-fido2-hardware-vendor"
$response = Invoke-WebRequest -Uri $url -UseBasicParsing
$response.Content | Out-File -FilePath "$env:TEMP/FIDO2Page.html"
Start-Process "$env:TEMP/FIDO2Page.html"