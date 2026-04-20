# Connect to Microsoft Entra
Connect-Entra

# ==== DRY RUN MODE ====
$DryRun = $false  # Change to $true to test without creating anything

# ==== PROMPTS ====

# Core user details
$FirstName     = Read-Host "Enter the user's first name (e.g., Jane)"
$MiddleName    = Read-Host "Enter the user's middle name (if any, or leave blank)"
$LastName      = Read-Host "Enter the user's last name (e.g., Dhoe)"
$Initials      = Read-Host "Enter the user's initials (e.g., JD)"

# Username validation
do {
    $Username = Read-Host "Enter username WITHOUT domain (e.g., jane.dhoe)"
    if (-not ($Username -match "^[a-zA-Z0-9._-]+$")) {
        Write-Warning "⚠️ Username contains invalid characters. Only letters, numbers, dot, underscore and hyphen are allowed."
    }
} while (-not ($Username -match "^[a-zA-Z0-9._-]+$"))

$DisplayName   = Read-Host "Enter full display name (e.g., Jane Dhoe)"
$Address       = Read-Host "Enter street address (e.g., Road 1, 1526 Moss)"
$PhoneNumber   = Read-Host "Enter mobile number (e.g., +4799988777)"
$PrivateEmail  = Read-Host "Enter a personal email address (optional)"
$JobTitle      = Read-Host "Enter job title (e.g., Finance Manager)"
$ManagerUPN    = Read-Host "Enter the UPN (email) of the user's manager (e.g., manager@yourdomain.com)"
$Domain        = Read-Host "Enter your Entra domain (e.g., yourdomain.com or tenant.onmicrosoft.com)"

# Additional attributes
$CompanyName     = Read-Host "Enter company name (e.g., Company AS)"
$Department      = Read-Host "Enter department (e.g., Finance)"
$OfficeLocation  = Read-Host "Enter office location (e.g., Oslo HQ)"

# UsageLocation validation
do {
    $UsageLocation = Read-Host "Enter usage location (2-letter country code, e.g., NO)"
    if ($UsageLocation.Length -ne 2) {
        Write-Warning "⚠️ Usage location must be exactly 2 characters (e.g., NO, SE, US)."
    }
} while ($UsageLocation.Length -ne 2)

# ==== DEFAULT FALLBACKS ====
if (-not $CompanyName) { $CompanyName = "Default Company AS" }
if (-not $Department)  { $Department = "General" }

# ==== BUILD UPN ====
$UserPrincipalName = "$Username@$Domain"

# Check for duplicates
$ExistingUser = Get-EntraUser -Filter "UserPrincipalName eq '$UserPrincipalName'" -ErrorAction SilentlyContinue
if ($ExistingUser) {
    $timestamp = Get-Date -Format "yyyyMMddHHmmss"
    $Username = "$Username$timestamp"
    $UserPrincipalName = "$Username@$Domain"
    Write-Warning "⚠️ UPN already exists. Adjusted username to: $Username"
}

# ==== PASSWORD SETUP ====
$Password = ([char[]](65..90 + 97..122 + 48..57 + 33..47) | Get-Random -Count 12) -join ''
Write-Host "`nGenerated Password: $Password"

$PasswordProfile = New-Object Microsoft.Open.AzureAD.Model.PasswordProfile
$PasswordProfile.Password = $Password
$PasswordProfile.ForceChangePasswordNextLogin = $true

# ==== SHOW SUMMARY ====
Write-Host "`n📋 Please review:"
Write-Host "Display Name     : $DisplayName"
Write-Host "UPN              : $UserPrincipalName"
Write-Host "Title            : $JobTitle"
Write-Host "Department       : $Department"
Write-Host "Company          : $CompanyName"
Write-Host "Office Location  : $OfficeLocation"
Write-Host "Manager UPN      : $ManagerUPN"
Write-Host "Usage Location   : $UsageLocation"
Write-Host "Groups to assign : Will prompt next"
Write-Host "Dry Run Mode     : $DryRun"
$confirm = Read-Host "Proceed with user creation? (Y/N)"
if ($confirm -ne "Y") {
    Write-Host "❌ Cancelled."
    return
}

# ==== USER CREATION ====
if (-not $DryRun) {
    $NewUserParams = @{
        AccountEnabled                 = $true
        DisplayName                    = $DisplayName
        GivenName                      = $FirstName
        Surname                        = $LastName
        MailNickname                   = $Username
        UserPrincipalName              = $UserPrincipalName
        JobTitle                       = $JobTitle
        StreetAddress                  = $Address
        OtherMails                     = if ($PrivateEmail) { @($PrivateEmail) } else { @() }
        PasswordProfile                = $PasswordProfile
        CompanyName                    = $CompanyName
        Department                     = $Department
        PhysicalDeliveryOfficeName     = $OfficeLocation
        UsageLocation                  = $UsageLocation
    }

    try {
        $User = New-EntraUser @NewUserParams
        Write-Host "✅ User created successfully!"
        Write-Host "UPN: $($User.UserPrincipalName)"
        Write-Host "Temporary Password: $Password`n"
    } catch {
        Write-Error "❌ Failed to create user: $_"
        return
    }
} else {
    Write-Host "🧪 Dry run enabled — no user was created."
    return
}

# ==== MANAGER ASSIGNMENT ====
if ($ManagerUPN) {
    $Manager = Get-EntraUser -Filter "UserPrincipalName eq '$ManagerUPN'" -ErrorAction SilentlyContinue
    if ($Manager -and $User) {
        try {
            Set-EntraUserManager -UserId $User.Id -ManagerId $Manager.Id
            Write-Host "✅ Manager assigned"
        } catch {
            Write-Warning "⚠️ Failed to assign manager: $_"
        }
    } else {
        Write-Warning "⚠️ Manager not found or user object invalid"
    }
}

# ==== GROUP ASSIGNMENT ====
$GroupNames = Read-Host "Enter comma-separated group names to assign the user to"
$GroupNames = $GroupNames -split "," | ForEach-Object { $_.Trim() }

foreach ($GroupName in $GroupNames) {
    $Group = Get-EntraGroup -Filter "DisplayName eq '$GroupName'" -ErrorAction SilentlyContinue
    if ($Group) {
        try {
            Add-EntraGroupMember -GroupId $Group.Id -DirectoryObjectId $User.Id
            Write-Host "✅ Added to group '$GroupName'"
        } catch {
            Write-Warning "⚠️ Failed to add to group '$GroupName': $_"
        }
    } else {
        Write-Warning "⚠️ Group '$GroupName' not found"
    }
}

Write-Host "`n🎉 All done!"