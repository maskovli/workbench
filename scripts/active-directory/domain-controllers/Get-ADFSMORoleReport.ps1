# Import Active Directory module
Import-Module ActiveDirectory

# Get forest and domain information
$forest = Get-ADForest
$domain = Get-ADDomain

# Initialize a PSObject for the FSMO role holders
$fsmoRoles = New-Object PSObject -Property @{
    'SchemaMaster' = $forest.SchemaMaster
    'DomainNamingMaster' = $forest.DomainNamingMaster
    'PDCEmulator' = $domain.PDCEmulator
    'RIDMaster' = $domain.RIDMaster
    'InfrastructureMaster' = $domain.InfrastructureMaster
}

# Output the FSMO role holders in markdown table format
"|Role|Domain Controller|" 
"|----|-----------------|" 
"|Schema Master|$($fsmoRoles.SchemaMaster)|"
"|Domain Naming Master|$($fsmoRoles.DomainNamingMaster)|"
"|PDC Emulator|$($fsmoRoles.PDCEmulator)|"
"|RID Master|$($fsmoRoles.RIDMaster)|"
"|Infrastructure Master|$($fsmoRoles.InfrastructureMaster)|"
