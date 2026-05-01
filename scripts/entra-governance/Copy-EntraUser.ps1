# Requires: Install-Module Microsoft.Graph -Scope CurrentUser

param(
    [Parameter(Mandatory=$true)]
    [string]$SourceUserUpn,      # User to copy, e.g. "john.doe@domain.com"

    [string]$Prefix = "COPY_",
    [switch]$CopyGroupMemberships,
    [switch]$CopyLicenses
)

# Generate a random password (cross-platform)
function New-RandomPassword {
    param([int]$Length = 16)
    $upper   = [char[]]'ABCDEFGHJKLMNPQRSTUVWXYZ'
    $lower   = [char[]]'abcdefghijkmnpqrstuvwxyz'
    $digits  = [char[]]'23456789'
    $special = [char[]]'!@#$%^&*-_=+'
    $all     = $upper + $lower + $digits + $special

    $chars = @(
        $upper   | Get-Random
        $lower   | Get-Random
        $digits  | Get-Random
        $special | Get-Random
    )
    $chars += 1..($Length - 4) | ForEach-Object { $all | Get-Random }
    -join ($chars | Sort-Object { Get-Random })
}

# Connect to Graph
Connect-MgGraph -Scopes "User.ReadWrite.All","Group.ReadWrite.All","Directory.ReadWrite.All"

# Fetch the source user with all relevant properties
Write-Host "Fetching source user: $SourceUserUpn" -ForegroundColor Cyan
$source = Get-MgUser -UserId $SourceUserUpn -Property `
    DisplayName,GivenName,Surname,JobTitle,Department,CompanyName, `
    OfficeLocation,StreetAddress,City,State,PostalCode,Country, `
    UsageLocation,PreferredLanguage,BusinessPhones,MobilePhone, `
    EmployeeType,AccountEnabled,MailNickname,UserPrincipalName

if (-not $source) {
    Write-Error "Could not find source user $SourceUserUpn"
    return
}

# Build new UPN with prefix
$upnParts  = $SourceUserUpn -split '@'
$newUpn    = "$Prefix$($upnParts[0])@$($upnParts[1])"

# Sanitize mailNickname (no dots or special chars)
$baseNick          = ($upnParts[0] -replace '[^a-zA-Z0-9_-]', '')
$newMailNickname   = "$Prefix$baseNick" -replace '[^a-zA-Z0-9_-]', ''
$newDisplayName    = "$Prefix$($source.DisplayName)"

$tempPassword = New-RandomPassword -Length 16
$passwordProfile = @{
    Password                      = $tempPassword
    ForceChangePasswordNextSignIn = $true
}

# Clone all properties from source, override identity fields
$newUserParams = @{
    AccountEnabled    = $true
    DisplayName       = $newDisplayName
    GivenName         = $source.GivenName
    Surname           = $source.Surname
    UserPrincipalName = $newUpn
    MailNickname      = $newMailNickname
    PasswordProfile   = $passwordProfile
    JobTitle          = $source.JobTitle
    Department        = $source.Department
    CompanyName       = $source.CompanyName
    OfficeLocation    = $source.OfficeLocation
    StreetAddress     = $source.StreetAddress
    City              = $source.City
    State             = $source.State
    PostalCode        = $source.PostalCode
    Country           = $source.Country
    UsageLocation     = $source.UsageLocation
    PreferredLanguage = $source.PreferredLanguage
    EmployeeType      = $source.EmployeeType
    # Mobile and business phones intentionally omitted - set manually after
}

# Remove empty values
$newUserParams = $newUserParams.GetEnumerator() |
    Where-Object { $null -ne $_.Value -and $_.Value -ne "" } |
    ForEach-Object -Begin { $h = @{} } -Process { $h[$_.Key] = $_.Value } -End { $h }

Write-Host "Creating copy: $newUpn" -ForegroundColor Cyan
$newUser = New-MgUser -BodyParameter $newUserParams

Write-Host "User created. ObjectId: $($newUser.Id)" -ForegroundColor Green
Write-Host "Temporary password: $tempPassword" -ForegroundColor Yellow

# Copy manager
try {
    $mgr = Get-MgUserManager -UserId $source.Id -ErrorAction Stop
    if ($mgr) {
        $ref = @{ "@odata.id" = "https://graph.microsoft.com/v1.0/users/$($mgr.Id)" }
        Set-MgUserManagerByRef -UserId $newUser.Id -BodyParameter $ref
        Write-Host "Manager copied." -ForegroundColor Green
    }
} catch {
    Write-Host "No manager to copy." -ForegroundColor DarkGray
}

# Copy group memberships
if ($CopyGroupMemberships) {
    Write-Host "Copying group memberships..." -ForegroundColor Cyan
    $groups = Get-MgUserMemberOf -UserId $source.Id -All |
              Where-Object { $_.AdditionalProperties["@odata.type"] -eq "#microsoft.graph.group" }

    foreach ($g in $groups) {
        try {
            New-MgGroupMember -GroupId $g.Id -DirectoryObjectId $newUser.Id -ErrorAction Stop
            Write-Host "  + $($g.AdditionalProperties.displayName)" -ForegroundColor Green
        } catch {
            Write-Host "  - Skipped $($g.AdditionalProperties.displayName): $($_.Exception.Message)" -ForegroundColor DarkYellow
        }
    }
}

# Copy licenses
if ($CopyLicenses) {
    Write-Host "Copying licenses..." -ForegroundColor Cyan
    $srcLic = Get-MgUserLicenseDetail -UserId $source.Id
    if ($srcLic) {
        $addLicenses = $srcLic | ForEach-Object { @{ SkuId = $_.SkuId } }
        Set-MgUserLicense -UserId $newUser.Id -AddLicenses $addLicenses -RemoveLicenses @()
        Write-Host "Licenses copied." -ForegroundColor Green
    }
}

Write-Host "`nDone! Edit the new user in Entra portal to set final name, UPN, email, mobile, etc." -ForegroundColor Green