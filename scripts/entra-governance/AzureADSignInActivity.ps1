
$tenantID=""
$contentType = "application/json"

$outList = @()

$Body = @{    
    Grant_Type    = "client_credentials"
    Scope         = "https://graph.microsoft.com/.default"
    Client_Id     = ""
    Client_Secret = ""
}
$ConnectGraph = Invoke-RestMethod -Uri "https://login.microsoftonline.com/$tenantID/oauth2/v2.0/token" -Method POST -Body $Body

$token = $ConnectGraph.access_token
$headers = @{ 'Authorization' = "Bearer $token" }


#$queryURL = "https://graph.microsoft.com/beta/users?`$filter=startswith(displayName,'paul')&`$select=displayName,userprincipalname,signInActivity"

$queryURL = 'https://graph.microsoft.com/beta/users?$select=displayName,createddatetime,userprincipalname,mail,usertype,signInActivity'

$SignInData = Invoke-RestMethod -Method GET -Uri $queryUrl -Headers $headers -contentType $contentType

ForEach ($User in $SignInData.Value) {  
    If ($Null -ne $User.SignInActivity)     {
       $LastSignIn = Get-Date($User.SignInActivity.LastSignInDateTime)
       $DaysSinceSignIn = (New-TimeSpan $LastSignIn).Days }
    Else { #No sign in data for user
       $LastSignIn = "Never or > 180 days" 
       $DaysSinceSignIn = "N/A" }
      
    $Values  = [PSCustomObject] @{          
      UPN                = $User.UserPrincipalName
      DisplayName        = $User.DisplayName
      Email              = $User.Mail
      Created            = Get-Date($User.CreatedDateTime)   
      LastSignIn         = $LastSignIn
      DaysSinceSignIn    = $DaysSinceSignIn
      UserType           = $User.UserType }
    $outList += $Values
    
 } 
 
 $NextLink = $SignInData.'@Odata.NextLink'
 While ($NextLink -ne $Null) {
    $SignInData = Invoke-RestMethod -Method GET -Uri $NextLink -Headers $headers -contentType $contentType
    ForEach ($User in $SignInData.Value) {  
        If ($Null -ne $User.SignInActivity)     {
           $LastSignIn = Get-Date($User.SignInActivity.LastSignInDateTime)
           $DaysSinceSignIn = (New-TimeSpan $LastSignIn).Days }
        Else { #No sign in data for user
           $LastSignIn = "Never or > 180 days" 
           $DaysSinceSignIn = "N/A" }
          
        $Values  = [PSCustomObject] @{          
          UPN                = $User.UserPrincipalName
          DisplayName        = $User.DisplayName
          Email              = $User.Mail
          Created            = Get-Date($User.CreatedDateTime)   
          LastSignIn         = $LastSignIn
          DaysSinceSignIn    = $DaysSinceSignIn
          UserType           = $User.UserType }
        $outList += $Values
      
     } 

    $NextLink = $SignInDate.'@odata.NextLink' }

 $outList | Export-Csv -Path 'C:\Temp\User_Signin_Activity.csv' -NoTypeInformation