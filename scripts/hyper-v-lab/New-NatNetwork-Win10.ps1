<#	
	.NOTES
	===========================================================================
	 Created on:   	20.08.2019 00.05
	 Created by:   	Marius A. Skovli
	 Filename:     	
	===========================================================================
	.DESCRIPTION
        Run script line by line.
        This script create a NAT-network for your lab environment. Ment for inspiration. 
        for more information go to: https://docs.microsoft.com/en-us/virtualization/hyper-v-on-windows/user-guide/setup-nat-network
        Redd0g is a fictive company ment to illustrate and be inspirational. 
#>


Get-NetAdapter
Get-NetNat | Remove-NetNat
Get-NetIPAddress
Remove-NetNat -Name "redd0g"




#Redd0g.com (Example 1)
New-VMSwitch -SwitchName "Redd0g" -SwitchType Internal
$Redd0gComIfIndex = Get-NetAdapter "*redd0g*" | select ifIndex
New-NetIPAddress -IPAddress 192.168.11.1 -PrefixLength 24 -InterfaceIndex 53
New-NetNat -Name Redd0g -InternalIPInterfaceAddressPrefix 192.168.11.0/24


#Redd0g.local (Example 2)
New-VMSwitch -SwitchName "Redd0g.local" -SwitchType Internal
$Redd0gLocalIfIndex = Get-NetAdapter "*redd0g.local*" | select ifIndex
New-NetIPAddress -IPAddress 192.168.12.1 -PrefixLength 24 -InterfaceIndex 71
New-NetNat -Name Reddog.local -InternalIPInterfaceAddressPrefix 192.168.12.0/24