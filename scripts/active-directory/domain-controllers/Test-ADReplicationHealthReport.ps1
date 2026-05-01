# Import Active Directory module
Import-Module ActiveDirectory

# Perform replication test
$replicationResult = Test-ReplicationHealth -ShowAll | Select-Object SourceServer, DestinationServer, Result, Error, LastReplicationResult

# Output the replication result in markdown table format
"|Source Server|Destination Server|Result|Error|Last Replication Result|"
"|-------------|-----------------|------|-----|----------------------|"
foreach ($result in $replicationResult) {
    "|$($result.SourceServer)|$($result.DestinationServer)|$($result.Result)|$($result.Error)|$($result.LastReplicationResult)|"
}
