# Install required modules (if you are local admin) (only needed first time).
Install-Module -Name DCToolbox -Force
Install-Module -Name AzureADPreview -Force
Install-Package msal.ps -Force



Enable-DCAzureADPIMRole -RolesToActivate 'Intune Administrator',
'Security Administrator',
'User Administrator',
'Groups Administrator',
'Conditional Access Administrator',
'Privileged Role Administrator',
'Identity Governance Administrator' -Reason 'Performing some management security coniguration.' -UseMaximumTimeAllowed