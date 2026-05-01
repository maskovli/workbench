# Import Active Directory module
Import-Module ActiveDirectory

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
