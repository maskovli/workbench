#Config Variables
$AdminSiteURL = "https://spirhed.sharepoint.com/"
$CSVPath = "C:\Temp\GroupsMembersData.csv"
 
Try {
    #Connect to PnP Online
    Connect-PnPOnline -Url $AdminSiteURL -Interactive
 
    #Get all Office 365 Groups
    $Groups = Get-PnPMicrosoft365Group
     
    $GroupsData = @()
    #Loop through each group
    ForEach($Group in $Groups)
    {
        Write-host "Processing Group:"$Group.DisplayName
        #Get Members of the group
        $GroupMembers = (Get-PnPMicrosoft365GroupMembers -Identity $Group | Select -ExpandProperty UserPrincipalName) -join ";"
 
        #Get Group details
        $GroupsData += New-Object PSObject -property $([ordered]@{
            GroupName  = $Group.DisplayName
            Id = $Group.ID
            Visibility = $Group.Visibility
            Mail = $Group.Mail
            GroupMembers= $GroupMembers
        })
    }
    $GroupsData
    #Export Groups information to CSV
    $GroupsData | Export-Csv -Path $CSVPath -NoTypeInformation
}
Catch {
    write-host -f Red "Error:" $_.Exception.Message
}


#Install-Module PnP.PowerShell -Scope CurrentUser -verbose
