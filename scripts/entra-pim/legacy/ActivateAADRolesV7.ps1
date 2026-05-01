# Install required modules (if you are local admin) (only needed first time).
Install-Module -Name DCToolbox -Force
Install-Module -Name AzureADPreview -Force
Install-Package msal.ps -Force

# Install required modules as curren user (if you're not local admin) (only needed first time).
Install-Module -Name DCToolbox -Scope CurrentUser -Force
Install-Module -Name AzureADPreview -Scope CurrentUser -Force
Install-Package msal.ps -AcceptLicense -Force

Get-Module
Remove-Module azureAD -Force -Verbose
Install-Module AzureADPreview -Force -Verbose

Enable-DCAzureADPIMRole -RolesToActivate 'Intune Administrator','Security Administrator','User Administrator','Groups Administrator','Conditional Access Administrator','Privileged Role Administrator','Identity Governance Administrator' -Reason 'Performing some management security coniguration.' -UseMaximumTimeAllowed