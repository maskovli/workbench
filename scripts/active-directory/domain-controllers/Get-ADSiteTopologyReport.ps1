# Import Active Directory module
Import-Module ActiveDirectory

# Get all sites
$sites = Get-ADReplicationSite -Filter *

# Initialize an array to hold the results
$siteResults = @()

foreach($site in $sites) {
    # Create a PSObject for this site
    $properties = @{
        'Name' = $site.Name
        'Description' = $site.Description
    }

    $siteResults += New-Object PSObject -Property $properties
}

# Output the site results in markdown table format
"|Site Name|Description|"
"|---------|-----------|"
foreach($result in $siteResults) {
    "|$($result.Name)|$($result.Description)|"
}

# Get all site links
$siteLinks = Get-ADReplicationSiteLink -Filter *

# Initialize an array to hold the results
$siteLinkResults = @()

foreach($siteLink in $siteLinks) {
    # Create a PSObject for this site link
    $properties = @{
        'Name' = $siteLink.Name
        'Sites' = $siteLink.Sites -join ', '
    }

    $siteLinkResults += New-Object PSObject -Property $properties
}

# Output the site link results in markdown table format
"|Site Link Name|Linked Sites|"
"|--------------|------------|"
foreach($result in $siteLinkResults) {
    "|$($result.Name)|$($result.Sites)|"
}

# Get all subnets
$subnets = Get-ADReplicationSubnet -Filter *

# Initialize an array to hold the results
$subnetResults = @()

foreach($subnet in $subnets) {
    # Create a PSObject for this subnet
    $properties = @{
        'Subnet' = $subnet.Name
        'Site' = $subnet.Site
    }

    $subnetResults += New-Object PSObject -Property $properties
}

# Output the subnet results in markdown table format
"|Subnet|Site|"
"|------|----|"
foreach($result in $subnetResults) {
    "|$($result.Subnet)|$($result.Site)|"
}
