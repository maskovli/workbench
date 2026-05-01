Connect-AzureAD
$UserId = (Get-AzureADUser -Top 1).ObjectId
Get-AzureADUserExtension -ObjectId $UserId


$User = Get-AzureADUser –ObjectId peter.griffin@redd0g.com
$User | Select –ExpandProperty ExtensionProperty



Get-AzureADUser –ObjectId peter.griffin@redd0g.com | Select –ExpandProperty ExtensionProperty