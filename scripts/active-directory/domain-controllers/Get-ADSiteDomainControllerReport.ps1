# Import Active Directory module
Import-Module ActiveDirectory

# Get all sites
$sites = Get-ADReplicationSite -Filter *

# Initialize an array to hold the results
$siteResults = @()

foreach($site in $sites) {
    # Get the servers in this site
    $servers = Get-ADDomainController -Filter * | Where-Object { $_.Site -eq $site.Name }

    # Create a PSObject for this server
    $properties = @{
        'SiteName' = $site.Name
        'Servers' = ($servers | ForEach-Object { $_.HostName }) -join ', '
    }

    $siteResults += New-Object PSObject -Property $properties
}

# Output the site results in markdown table format
"|Site Name|Servers|"
"|---------|-------|"
foreach($result in $siteResults) {
    "|$($result.SiteName)|$($result.Servers)|"
}
