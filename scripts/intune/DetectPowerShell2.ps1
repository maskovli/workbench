<#
    =================================================================================
    DISCLAIMER:
    This script is provided "as-is" with no warranties. Usage of this script is at
    your own risk. The author is not liable for any damages or losses arising from
    using this script. Please review the full legal disclaimer at:
    https://spirhed.com
    =================================================================================
#>
Get-WindowsOptionalFeature -FeatureName "MicrosoftWindowsPowerShellV2Root" -Online | Select-Object -ExpandProperty State