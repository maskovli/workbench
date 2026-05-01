<#
.SYNOPSIS
This script configures power settings on Windows 11 endpoints.

.DESCRIPTION
This script sets specific power plan settings for Windows 11 machines, including display and sleep configurations, and power button actions. It is designed to be deployed via Intune across an organization.

.PARAMETER activeScheme
The GUID of the currently active power scheme. The script retrieves this automatically.

.EXAMPLE
PS> .\SetPowerPlan.ps1
Executes the script to set power configurations.

.NOTES
Author: Marius A. Skovli
Company: Spirhed AS
Web: http://www.spirhed.com
Version: 1.0
Date: February 24, 2024
Documentation MSFT: https://learn.microsoft.com/en-us/windows-hardware/design/device-experiences/powercfg-command-line-options
Documentation Additional: https://www.tenforums.com/tutorials/69741-change-default-action-power-button-windows-10-a.html
#>

# First, we need the GUID of the active power scheme
$activeScheme = (powercfg -getactivescheme).split()[3]

# Set the display for both 'On battery' and 'Plugged in'
powercfg -change monitor-timeout-dc 4
powercfg -change monitor-timeout-ac 10

# Set the computer to never sleep for both 'On battery' and 'Plugged in'
powercfg -change standby-timeout-dc 20
powercfg -change standby-timeout-ac 180

# Set the power button to sleep (index 2) for both 'On battery' and 'Plugged in'
powercfg -setacvalueindex $activeScheme SUB_BUTTONS PBUTTONACTION 1
powercfg -setdcvalueindex $activeScheme SUB_BUTTONS PBUTTONACTION 1

# Set the sleep button to sleep (index 2) for both 'On battery' and 'Plugged in'
powercfg -setacvalueindex $activeScheme SUB_BUTTONS SBUTTONACTION 1
powercfg -setdcvalueindex $activeScheme SUB_BUTTONS SBUTTONACTION 1

# Set the lid close action to sleep (index 1) on battery and do nothing (index 0) when plugged in
powercfg -setdcvalueindex $activeScheme SUB_BUTTONS LIDACTION 0
powercfg -setacvalueindex $activeScheme SUB_BUTTONS LIDACTION 0