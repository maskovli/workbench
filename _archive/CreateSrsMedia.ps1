<#
.SYNOPSIS

    Create SRSv2 media appropriate for setting up an SRSv2 device.


.DESCRIPTION

    This script automates some sanity checks and copying operations that are
    necessary to create bootable SRSv2 media. Booting an SRSv2 device using the
    media created from this process will result in the SRSv2 shutting down. The
    SRSv2 can then either be put into service, or booted with separate WinPE
    media for image capture.

    To use this script, you will need:

    1. An Internet connection
    2. A USB drive with sufficient space (16GB+), inserted into this computer
    3. Windows 10 Enterprise or Windows 10 Enterprise IoT media, which must be
       accessible from this computer (you will be prompted for a path). The
       Windows media build number must match the build required by the SRSv2
       deployment kit.

.EXAMPLE
    .\CreateSrsMedia

    Prompt for required information, validate provided inputs, and (if all
    validations pass) create media on the specified USB device.

.NOTES

    This script requires that you provide Windows media targeted for the x64
    architecture.

    Only one driver pack can be used at a time. Each unique supported SKU of
    SRSv2 computer hardware must have its own, separate image.

    The build number of the Windows media being used *must* match the build
    required by the SRSv2 deployment kit.

#>

<#
Revision history
    1.0.0  - Initial release
    1.0.1  - Support source media with WIM >4GB
    1.1.0  - Switch Out-Null to Write-Debug for troubleshooting
             Record transcripts for troubleshooting
             Require the script be run from a path without spaces
             Require the script be run from an NTFS filesystem
             Soft check for sufficient scratch space
             Warn that the target USB drive will be wiped
             Rethrow exceptions after cleanup on main path
    1.2.0  - Indicate where to get Enterprise media
             Improve error handling for non-Enterprise media
             Report and exit on copy errors
             Work with spaces in the script's path
             Explicitly reject Windows 10 Media Creation Tool media
             Fix OEM media regression caused by splitting WIMs
    1.3.1  - Read config information from MSI
             Added infrastructure for downloading files
             Support for automatically downloading Windows updates
             Support for automatically downloading the deployment kit MSI
             Support for self-updating
             Added menu-driven driver selection/downloading
    1.3.2  - Fix OEM media regression caused by splitting WIMs
    1.4.0  - Support BIOS booting
    1.4.1  - BIOS booting controlled by metadata
    1.4.2  - Fix driver pack informative output
             Add 64-bit check to prevent 32-bit accidents
             Add debugging cross-check
             Add checks to prevent the script being run in weird ways
             Add warning about image cleanup taking a long time
             Fix space handling in self-update
    1.4.3  - Add non-terminating disk initialization logic
             Delete "system volume information" to prevent Windows Setup issues
             Add return code checking for native commands
    1.4.4  - Improve rejection of non-LP CABs
    1.4.5  - Add host OS check to prevent older DISM etc. mangling newer images
    1.5.0  - Add support for mismatched OS build number vs. feature build number
    1.5.1  - Change OEM default key.
    1.6.0  - Add support for mismatched OS build number vs. language build number
    1.6.1  - Use default credentials with the default proxy
    1.7.0  - Add metadata for clearer "human readable" Windows version information
             Change required input from Windows install media path to Windows ISO path
             Add size and hash check for input Windows ISO
    1.7.1  - Remove ePKEA references
             Improve ISO path input handling to allow quoted paths
             Fix directory left behind when script runs successfully
             Improve diagnostic output so it's less obtrusive
    1.8.0  - Add support for deployment kits that require Windows 11
             Improve ISO requirements messaging, so it's always stated
             Change names, add comments to reduce cases of mistaken code divers
    1.8.1  - Fix image mounting stage to work for both Windows 10 and 11

#>
[CmdletBinding()]
param(
    [Switch]$ShowVersion, <# If set, output the script version number and exit. #>
    [Switch]$Manufacturing <# Internal use. #>
)

$ErrorActionPreference = "Stop"
$DebugPreference = if($PSCmdlet.MyInvocation.BoundParameters["Debug"]) { "Continue" } else { "SilentlyContinue" }
Set-StrictMode -Version Latest

$CreateSrsMediaScriptVersion = "1.8.1"

$SrsKitHumanVersion = $null
$SrsKitVlscName = $null
$SrsKitIsoSize = $null
$SrsKitIsoSha256 = $null


$robocopy_success = {$_ -lt 8 -and $_ -ge 0}

if ($ShowVersion) {
    Write-Output $CreateSrsMediaScriptVersion
    exit
}

function Remove-Directory {
  <#
    .SYNOPSIS
        
        Recursively remove a directory and all its children.

    .DESCRIPTION

        Powershell can't handle 260+ character paths, but robocopy can. This
        function allows us to safely remove a directory, even if the files
        inside exceed Powershell's usual 260 character limit.
  #>
param(
    [parameter(Mandatory=$true)]
    [string]$path <# The path to recursively remove #>
)

    # Make an empty reference directory
    $cleanup = Join-Path $PSScriptRoot "empty-temp"
    if (Test-Path $cleanup) {
        Remove-Item -Path $cleanup -Recurse -Force
    }
    New-Item -ItemType Directory $cleanup | Write-Debug

    # Use robocopy to clear out the guts of the victim path
    (Invoke-Native "& robocopy '$cleanup' '$path' /mir" $robocopy_success) | Write-Debug

    # Remove the folders, now that they're empty.
    Remove-Item $path -Force
    Remove-Item $cleanup -Force
}

function Test-OsIsoPath {
  <#
    .SYNOPSIS

        Test if $OsIsoPath is the expected Windows setup ISO for SRSv2.

    .DESCRIPTION

        Tests if the provided path references the Windows setup ISO
        that matches the media indicated in the SRSv2 installation
        metadata. Specifically, the ISO must:

          - Be the correct size
          - Produce the correct SHA256 hash

    .OUTPUTS bool

        $true if $OsIsoPath refers to the expected ISO, $false otherwise.
  #>
param(
  [parameter(Mandatory=$true)]
  $OsIsoPath, <# Path to the ISO file to check #>
  [parameter(Mandatory=$true)]
  $KitIsoSize, <# Expected size of the ISO in bytes #>
  [parameter(Mandatory=$true)]
  $KitIsoSha256, <# Expected SHA256 hash of the ISO file #>
  [parameter(Mandatory=$true)]
  [switch]$IsOem <# Whether OEM media is being used #>
)

    if (!(Test-Path $OsIsoPath)) {
        Write-Host "The path provided does not exist. Please specify a path to a Windows installation ISO file."
        return $false
    }

    if (!(Test-Path $OsIsoPath -PathType Leaf)) {
        Write-Host "The path provided does not refer to a file. Please specify a path to a Windows installation ISO file."
        return $false
    }

    $Iso = Get-ChildItem $OsIsoPath

    if ($Iso.Length -ne $KitIsoSize) {
        Write-Host "The ISO does not match the expected size."
        Write-Host "Verify that you downloaded the correct file, and that it is not corrupted."
        PrintWhereToGetMedia -IsOem:$IsOem
        return $false
    }

    if ((Get-FileHash -Algorithm SHA256 $Iso).Hash -ne $KitIsoSha256) {
        Write-Host "The ISO does not match the expected SHA256 hash."
        Write-Host "Verify that you downloaded the correct file, and that it is not corrupted."
        PrintWhereToGetMedia -IsOem:$IsOem
        return $false
    }

    return $true
}

function Test-Unattend-Compat {
    <#
        .SYNOPSIS
        
            Test to see if this script is compatible with a given SRSv2 Unattend.xml file.

        .DESCRIPTION

            Looks for metadata in the $xml parameter indicating the lowest version of
            the CreateSrsMedia script the XML file will work with.

        .OUTPUTS bool
            
            Return $true if CreateSrsMedia is compatible with the SRSv2
            Unattend.xml file in $xml, $false otherwise.
    #>
param(
    [parameter(Mandatory=$true)]
    [System.Xml.XmlDocument]$Xml, <# The SRSv2 AutoUnattend to check compatibility with. #>
    [parameter(Mandatory=$true)]
    [int]$Rev <# The maximum compatibility revision this script supports. #>
)
    $nodes = $Xml.SelectNodes("//comment()[starts-with(normalize-space(translate(., 'ABCDEFGHIJKLMNOPQRSTUVWXYZ', 'abcdefghijklmnopqrstuvwxyz')), 'srsv2-compat-rev:')]")

    # If the file has no srsv2-compat-rev value, assume rev 0, which all scripts work with.
    if ($nodes -eq $null -or $nodes.Count -eq 0) {
        return $true
    }

    $URev = 0

    # If there is more than one value, be conservative: take the biggest value
    $nodes | 
    ForEach-Object {
        $current = $_.InnerText.Split(":")[1]
        if ($URev -lt $current) {
            $URev = $current
        }
    }

    return $Rev -ge $URev

}

function Remove-Xml-Comments {
  <#
    .SYNOPSIS
        
        Remove all comments that are direct children of $node.

    .DESCRIPTION
        
        Remove all the comment children nodes (non-recursively) from the specified $node.
  #>
param(
    [parameter(Mandatory=$true)]
    [System.Xml.XmlNode]$node <# The XML node to strip comments from. #>
)
    $node.SelectNodes("comment()") |
    ForEach-Object {
        $node.RemoveChild($_) | Write-Debug
    }
}

function Add-AutoUnattend-Key {
  <#
    .SYNOPSIS
        
        Inject $key as a product key into the AutoUnattend XML $xml.

    .DESCRIPTION
        
        Injects the $key value as a product key in $xml, where $xml is an
        AutoUnattend file already containing a Microsoft-Windows-Setup UserData
        node. Any comments in the UserData node are stripped.

        If a ProductKey node already exists, this function does *not* remove or
        replace it.
  #>
param(
    [parameter(Mandatory=$true)]
    [System.Xml.XmlDocument]$xml, <# The SRSv2 AutoUnattend to modify. #>
    [parameter(Mandatory=$true)]
    [string]$key <# The Windows license key to inject. #>
)

    $XmlNs = @{"u"="urn:schemas-microsoft-com:unattend"}
    $node = (Select-Xml -Namespace $XmlNs -Xml $xml -XPath "//u:settings[@pass='specialize']").Node
    $NShellSetup = $xml.CreateElement("", "component", $XmlNs["u"])
    $NShellSetup.SetAttribute("name", "Microsoft-Windows-Shell-Setup") | Write-Debug
    $NShellSetup.SetAttribute("processorArchitecture", "amd64") | Write-Debug
    $NShellSetup.SetAttribute("publicKeyToken", "31bf3856ad364e35") | Write-Debug
    $NShellSetup.SetAttribute("language", "neutral") | Write-Debug
    $NShellSetup.SetAttribute("versionScope", "nonSxS") | Write-Debug
    $NProductKey = $xml.CreateElement("", "ProductKey", $XmlNs["u"])
    $NProductKey.InnerText = $key
    $NShellSetup.AppendChild($NProductKey) | Write-Debug
    $node.PrependChild($NShellSetup) | Write-Debug
}

function Set-AutoUnattend-Partitions {
  <#
    .SYNOPSIS

        Set up the AutoUnattend file for use with BIOS based systems, if requested.

    .DESCRIPTION

        If -BIOS is specified, reconfigure a (nominally UEFI) AutoUnattend
        partition configuration to be compatible with BIOS-based systems
        instead. Otherwise, do nothing.
  #>
param(
    [parameter(Mandatory=$true)]
    [System.Xml.XmlDocument]$xml, <# The SRSv2 AutoUnattend to modify. #>
    [parameter(Mandatory=$true)]
    [switch]$BIOS <# If True, assume UEFI input and reconfigure for BIOS. #>
)

    # for UEFI, do nothing.
    if (!$BIOS) {
        return
    }

    # BIOS logic...
    $XmlNs = @{"u"="urn:schemas-microsoft-com:unattend"}
    $node = (Select-Xml -Namespace $XmlNs -Xml $xml -XPath "//u:settings[@pass='windowsPE']/u:component[@name='Microsoft-Windows-Setup']").Node

    # Remove the first partition (EFI)
    $node.DiskConfiguration.Disk.CreatePartitions.RemoveChild($node.DiskConfiguration.Disk.CreatePartitions.CreatePartition[0]) | Write-Debug

    # Re-number the remaining partition as 1
    $node.DiskConfiguration.Disk.CreatePartitions.CreatePartition.Order = "1"

    # Install to partition 1
    $node.ImageInstall.OSImage.InstallTo.PartitionID = "1"
}

function Set-AutoUnattend-Sysprep-Mode {
  <#
    .SYNOPSIS
        
        Set the SRSv2 sysprep mode to "reboot" or "shutdown" in the AutoUnattend file $xml.

    .DESCRIPTION
        
        Sets the SRSv2 AutoUnattend represented by $xml to either reboot (if
        -Reboot is used), or shut down (if -shutdown is used). Any comments
        under the containing RunSynchronousCommand node are stripped.

        This function assumes that a singular sysprep command is specified in
        $xml with /generalize and /oobe flags, in the auditUser pass,
        Microsoft-Windows-Deployment component. It further assumes that the
        sysprep command has the /reboot option specified by default.
  #>
param(
    [parameter(Mandatory=$true)]
    [System.Xml.XmlDocument]$Xml, <# The SRSv2 AutoUnattend to modify. #>
    [parameter(Mandatory=$true,ParameterSetName='reboot')]
    [switch]$Reboot, <# Whether sysprep should perform a reboot or a shutdown. #>
    [parameter(Mandatory=$true,ParameterSetName='shutdown')]
    [switch]$Shutdown <# Whether sysprep should perform a shutdown or a reboot. #>
)
    $XmlNs = @{"u"="urn:schemas-microsoft-com:unattend"}
    $node = (Select-Xml -Namespace $XmlNs -Xml $Xml -XPath "//u:settings[@pass='auditUser']/u:component[@name='Microsoft-Windows-Deployment']/u:RunSynchronous/u:RunSynchronousCommand/u:Path[contains(translate(text(), 'ABCDEFGHIJKLMNOPQRSTUVWXYZ', 'abcdefghijklmnopqrstuvwxyz'), 'sysprep') and contains(translate(text(), 'ABCDEFGHIJKLMNOPQRSTUVWXYZ', 'abcdefghijklmnopqrstuvwxyz'), 'generalize') and contains(translate(text(), 'ABCDEFGHIJKLMNOPQRSTUVWXYZ', 'abcdefghijklmnopqrstuvwxyz'), 'oobe')]").Node
    Remove-Xml-Comments $node.ParentNode
    if ($Shutdown -or !$Reboot) {
        $node.InnerText = $node.InnerText.ToLowerInvariant() -replace ("/reboot", "/shutdown")
    }
}

function Get-TextListSelection {
  <#
    .SYNOPSIS

        Prompt the user to pick an item from an array.


    .DESCRIPTION

        Given an array of items, presents the user with a text-based, numbered
        list of the array items. The user must then select one item from the
        array (by index). That index is then returned.

        Invalid selections cause the user to be re-prompted for input.


    .OUTPUTS int

        The index of the item the user selected from the array.
  #>
  param(
    [parameter(Mandatory=$true)]<# The list of objects to select from #>
    $Options,
    [parameter(Mandatory=$false)]<# The property of the objects to use for the list #>
    $Property = $null,
    [parameter(Mandatory=$false)]<# The prompt to display to the user #>
    $Prompt = "Selection",
    [parameter(Mandatory=$false)]<# Whether to allow a blank entry to make the default selection #>
    [switch]
    $AllowDefault = $true,
    [parameter(Mandatory=$false)]<# Whether to automatically select the default value, without prompting #>
    [switch]
    $AutoDefault = $false
  )

  $index = 0
  $response = -1
  $DefaultValue = $null
  $DefaultIndex = -1

  if ($AllowDefault) {
    $DefaultIndex = 0
    if ($AutoDefault) {
      return $DefaultIndex
    }
  }

  $Options | Foreach-Object -Process {
    $value = $_
    if ($Property -ne $null) {
      $value = $_.$Property
    }
    if ($DefaultValue -eq $null) {
      $DefaultValue = $value
    }
    Write-Host("[{0,2}] {1}" -f $index, $value)
    $index++
  } -End {
    if ($AllowDefault) {
      Write-Host("(Default: {0})" -f $DefaultValue)
    }
    while ($response -lt 0 -or $response -ge $Options.Count) {
      try {
        $response = Read-Host -Prompt $Prompt -ErrorAction SilentlyContinue
        if ([string]::IsNullOrEmpty($response)) {
          [int]$response = $DefaultIndex
        } else {
          [int]$response = $response
        }
      } catch {}
    }
  }

  # Write this out for transcript purposes.
  Write-Transcript ("Selected option {0}." -f $response)

  return $response
}

function SyncDirectory {
  <#
    .SYNOPSIS
        Sync a source directory to a destination.

    .DESCRIPTION
        Given a source and destination directories, make the destination
        directory's contents match the source's, recursively.
  #>
  param(
    [parameter(Mandatory=$true)] <# The source directory containing the subirectory to sync. #>
    $Src,
    [parameter(Mandatory=$true)] <# The destination directory that may or may not yet contain the subdirectory being synchronized #>
    $Dst,
    [parameter(Mandatory=$false)] <# Any additional flags to pass to robocopy #>
    $Flags
  )

  (Invoke-Native "& robocopy /mir '$Src' '$Dst' /R:0 $Flags" $robocopy_success) | Write-Debug
  if ($LASTEXITCODE -gt 7) {
    Write-Error ("Copy failed. Try re-running with -Debug to see more details.{0}Source: {1}{0}Destination: {2}{0}Flags: {3}{0}Error code: {4}" -f "`n`t", $Src, $Dst, ($Flags -Join " "), $LASTEXITCODE)
  }
}

function SyncSubdirectory {
  <#
    .SYNOPSIS
        Sync a single subdirectory from a source directory to a destination.

    .DESCRIPTION
        Given a source directory Src with a subdirectory Subdir, recreate Subdir
        as a subdirectory under Dst.
  #>
  param(
    [parameter(Mandatory=$true)] <# The source directory containing the subirectory to sync. #>
    $Src,
    [parameter(Mandatory=$true)] <# The destination directory that may or may not yet contain the subdirectory being synchronized #>
    $Dst,
    [parameter(Mandatory=$true)] <# The name of the subdirectory to synchronize #>
    $Subdir,
    [parameter(Mandatory=$false)] <# Any additional flags to pass to robocopy #>
    $Flags
  )

  $Paths = Join-Path -Path @($Src, $Dst) -ChildPath $Subdir
  SyncDirectory $Paths[0] $Paths[1] $Flags
}

function SyncSubdirectories {
  <#
    .SYNOPSIS
        Recreate each subdirectory from the source in the destination.

    .DESCRIPTION
        For each subdirectory contained in the source, synchronize with a
        corresponding subdirectory in the destination. This does not synchronize
        non-directory files from the source to the destination, nor does it
        purge "extra" subdirectories in the destination where the source does
        not contain such directories.
  #>
  param(
    [parameter(Mandatory=$true)] <# The source directory #>
    $Src,
    [parameter(Mandatory=$true)] <# The destination directory #>
    $Dst,
    [parameter(Mandatory=$false)] <# Any additional flags to pass to robocopy #>
    $Flags
  )

  Get-ChildItem $Src -Directory | ForEach-Object { SyncSubdirectory $Src $Dst $_.Name $Flags }
}

function ConvertFrom-PSCustomObject {
<#
    .SYNOPSIS
        Recursively convert a PSCustomObject to a hashtable.

    .DESCRIPTION
        Converts a set of (potentially nested) PSCustomObjects into an easier-to-
        manipulate set of (potentially nested) hashtables. This operation does not
        recurse into arrays; any PSCustomObjects embedded in arrays will be left
        as-is.

    .OUTPUT hashtable
#>
param(
    [parameter(Mandatory=$true)]
    [PSCustomObject]$object <# The PSCustomeObject to recursively convert to a hashtable #>
)

    $retval = @{}

    $object.PSObject.Properties |% {
        $value = $null

        if ($_.Value -ne $null -and $_.Value.GetType().Name -eq "PSCustomObject") {
            $value = ConvertFrom-PSCustomObject $_.Value
        } else {
            $value = $_.Value
        }
        $retval.Add($_.Name, $value)
    }
    return $retval
}

function Resolve-Url {
<#
    .SYNOPSIS
        Recursively follow URL redirections until a non-redirecting URL is reached.

    .DESCRIPTION
        Chase URL redirections (e.g., FWLinks, safe links, URL-shortener links)
        until a non-redirection URL is found, or the redirection chain is deemed
        to be too long.

    .OUTPUT System.Uri
#>
param(
    [Parameter(Mandatory=$true)]
    [String]$url <# The URL to (recursively) resolve to a concrete target. #>
)
    $orig = $url
    $result = $null
    $depth = 0
    $maxdepth = 10

    do {
        if ($depth -ge $maxdepth) {
            Write-Error "Unable to resolve $orig after $maxdepth redirects."
        }
        $depth++
        $resolve = [Net.WebRequest]::Create($url)
        $resolve.Method = "HEAD"
        $resolve.AllowAutoRedirect = $false
        $result = $resolve.GetResponse()
        $url = $result.GetResponseHeader("Location")
    } while ($result.StatusCode -eq "Redirect")

    if ($result.StatusCode -ne "OK") {
        Write-Error ("Unable to resolve {0} due to status code {1}" -f $orig, $result.StatusCode)
    }

    return $result.ResponseUri
}

function Save-Url {
<#
    .SYNOPSIS
        Given a URL, download the target file to the same path as the currently-
        running script.

    .DESCRIPTION
        Download a file referenced by a URL, with some added niceties:

          - Tell the user the file is being downloaded
          - Skip the download if the file already exists
          - Keep track of partial downloads, and don't count them as "already
            downloaded" if they're interrupted

        Optionally, an output file name can be specified, and it will be used. If
        none is specified, then the file name is determined from the (fully
        resolved) URL that was provided.

    .OUTPUT string
#>
param(
    [Parameter(Mandatory=$true)]
    [String]$url, <# URL to download #>
    [Parameter(Mandatory=$true)]
    [String]$name, <# A friendly name describing what (functionally) is being downloaded; for the user. #>
    [Parameter(Mandatory=$false)]
    [String]$output = $null <# An optional file name to download the file as. Just a file name -- not a path! #>
)

    $res = (Resolve-Url $url)

    # If the filename is not specified, use the filename in the URL.
    if ([string]::IsNullOrEmpty($output)) {
        $output = (Split-Path $res.LocalPath -Leaf)
    }

    $File = Join-Path $PSScriptRoot $output
    if (!(Test-Path $File)) {
        Write-Host "Downloading $name... " -NoNewline
        $TmpFile = "${File}.downloading"

        # Clean up any existing (unfinished, previous) download.
        Remove-Item $TmpFile -Force -ErrorAction SilentlyContinue

        # Download to the temp file, then rename when the download is complete
        (New-Object System.Net.WebClient).DownloadFile($res, $TmpFile)
        Rename-Item $TmpFile $File -Force

        Write-Host "done"
    } else {
        Write-Host "Found $name already downloaded."
    }

    return $File
}

function Test-Signature {
<#
    .SYNOPSIS
        Verify the AuthentiCode signature of a file, deleting the file and writing
        an error if it fails verification.

    .DESCRIPTION
        Given a path, check that the target file has a valid AuthentiCode signature.
        If it does not, delete the file, and write an error to the error stream.
#>
param(
    [Parameter(Mandatory=$true)]
    [String]$Path <# The path of the file to verify the Authenticode signature of. #>
)
    if (!(Test-Path $Path)) {
        Write-Error ("File does not exist: {0}" -f $Path)
    }

    $name = (Get-Item $Path).Name
    Write-Host ("Validating signature for {0}... " -f $name) -NoNewline

    switch ((Get-AuthenticodeSignature $Path).Status) {
        ("Valid") {
            Write-Host "success."
        }

        default {
            Write-Host "failed."

            # Invalid files should not remain where they could do harm.
            Remove-Item $Path | Write-Debug
            Write-Error ("File {0} failed signature validation." -f $name)
        }
    }
}

function PrintWhereToGetLangpacks {
param(
    [parameter(Mandatory=$false)]
    [switch]$IsOem
)
    if ($IsOem) {
        Write-Host ("   OEMs:            http://go.microsoft.com/fwlink/?LinkId=131359")
        Write-Host ("   System builders: http://go.microsoft.com/fwlink/?LinkId=131358")
    } else {
        Write-Host ("   MPSA customers:         http://go.microsoft.com/fwlink/?LinkId=125893")
        Write-Host ("   Other volume licensees: http://www.microsoft.com/licensing/servicecenter")
    }
}

function PrintWhereToGetMedia {
param(
    [parameter(Mandatory=$false)]
    [switch]$IsOem
)

    if ($IsOem) {
        Write-Host ("   OEMs must order physical Windows 10 Enterprise IoT media.")
    } else {
        Write-Host ("   Enterprise customers can access Windows 10 Enterprise media from the Volume Licensing Service Center:")
        Write-Host ("   http://www.microsoft.com/licensing/servicecenter")
    }

    if ($script:SrsKitIsoSize -eq $null) {
        return
    }

    Write-Host     ("")
    Write-Host     ("   The correct media for this release has the following characteristics:")
    Write-Host     ("")
    Write-Host     ("     Major release: $script:SrsKitHumanVersion")
    if (!$IsOem) {
        Write-Host ("     Name in VLSC: $script:SrsKitVlscName")
    }
    Write-Host     ("     Size (bytes): $script:SrsKitIsoSize")
    Write-Host     ("     SHA256: $script:SrsKitIsoSha256")
    Write-Host     ("")
    Write-Host     ("   You must supply an ISO that matches the exact characteristics above.")
}

function Render-Menu {
<#
    .SYNOPSIS
      Present a data-driven menu system to the user.

    .DESCRIPTION
      Render a data-driven menu system to guide the user through more complicated
      decision-making processes.

    .NOTES
      Right now, the menu system is used only for selecting which driver pack to
      download.

      Action: Download
      Parameters:
        - Targets: an array of strings (URLs)
      Description:
        Chases redirects and downloads each URL listed in the "Targets" array.
        Verifies the downloaded file's AuthentiCode signature.
      Returns:
        a string (file path) for each downloaded file.

      Action: Menu
      Parameters:
        - Targets: an array of other MenuItem names (each must be a key in $MenuItems)
        - Message: Optional. The prompt text to use when asking for the user's
                   selection.
      Description:
        Presents a menu, composed of the names listed in "Targets," to the user. The
        menu item that is selected by the user is then recursively passed to
        Render-Menu for processing.

      Action: Redirect
      Parameters:
        - Target: A MenuItem name (must be a key in $MenuItems)
      Description:
        The menu item indicated by "Target" is recursively passed to Render-Menu
        for processing.

      Action: Warn
      Parameters:
        - Message: The warning to display to the user
      Description:
        Displays a warning consisting of the "Message" text to the user.

    .OUTPUT string
      One or more strings, each representing a downloaded file.
#>
[CmdletBinding()]
param(
    [parameter(Mandatory=$true)]
    $MenuItem, <# The initial menu item to process #>
    [parameter(Mandatory=$true)]
    $MenuItems, <# The menu items (recursively) referenced by the initial menu item #>
    [parameter(Mandatory=$true)]
    [hashtable]$Variables
)
    if ($MenuItem.ContainsKey("Variables")) {
        foreach ($Key in $MenuItem["Variables"].Keys) {
            if ($Variables.ContainsKey($Key)) {
                $Variables[$Key] = $MenuItem["Variables"][$Key]
            } else {
                $Variables.Add($Key, $MenuItem["Variables"][$Key])
            }
        }
    }
    Switch ($MenuItem.Action) {
        "Download" {
            Write-Verbose "Processing download menu entry."
            ForEach ($URL in $MenuItem["Targets"]) {
                $file = (Save-Url $URL "driver")
                Test-Signature $file
                Write-Output $file
            }
        }

        "Menu" {
            Write-Verbose "Processing nested menu entry."
            $Options = $MenuItem["Targets"]
            $Prompt = @{}
            if ($MenuItem.ContainsKey("Message")) {
                $Prompt = @{ "Prompt"=($MenuItem["Message"]) }
            }
            $Selection = $MenuItem["Targets"][(Get-TextListSelection -Options $Options -AllowDefault:$false @Prompt)]
            Render-Menu -MenuItem $MenuItems[$Selection] -MenuItems $MenuItems -Variables $Variables
        }

        "Redirect" {
            Write-Verbose ("Redirecting to {0}" -f $MenuItem["Target"])
            Render-Menu -MenuItem $MenuItems[$MenuItem["Target"]] -MenuItems $MenuItems -Variables $Variables
        }

        "Warn" {
            Write-Warning $MenuItem["Message"]
        }
    }
}

function Invoke-Native {
<#
    .SYNOPSIS
        Run a native command and process its exit code.

    .DESCRIPTION
        Invoke a command line specified in $command, and check the resulting $LASTEXITCODE against
        $success to determine if the command succeeded or failed. If the command failed, error out.
#>
[CmdletBinding()]
param(
    [parameter(Mandatory=$true)]
    [string]$command, <# The native command to execute. #>
    [parameter(Mandatory=$false)]
    [ScriptBlock]$success = {$_ -eq 0} <# Test of $_ (last exit code) that returns $true if $command was successful, $false otherwise. #>
)

    Invoke-Expression $command
    $result = $LASTEXITCODE
    if (!($result |% $success)) {
        Write-Error "Command '$command' failed test '$success' with code '$result'."
        exit 1
    }
}

function Expand-Archive {
<#
    .SYNOPSIS
        Extract files from supported archives.

    .NOTES
        Supported file types are .msi and .cab.
#>
[CmdletBinding()]
param(
    [parameter(Mandatory=$true)]
    [string]$source, <# The archive file to expand. #>
    [parameter(Mandatory=$true)]
    [string]$destination <# The directory to place the extracted archive files in. #>
)

    if (!(Test-Path $destination)) {
        mkdir $destination | Write-Debug
    }

    switch ([IO.Path]::GetExtension($source)) {
        ".msi" {
            Start-Process "msiexec" -ArgumentList ('/a "{0}" /qn TARGETDIR="{1}"' -f $source, $destination) -NoNewWindow -Wait
        }
        ".cab" {
            (& expand.exe "$source" -F:* "$destination") | Write-Debug
        }
        default {
            Write-Error "Unsupported archive type."
            exit 1
        }
    }
}

function Write-Transcript {
<#
    .SYNOPSIS
        Write diagnostic strings to the transcript, while keeping them
        unobtrusive in the normal script output.
#>
[CmdletBinding()]
param(
    [parameter(Mandatory=$true)]
    [string]$message
)

    Write-Host -ForegroundColor (Get-Host).UI.RawUI.BackgroundColor $message
}

####
## Start of main script
####

Start-Transcript

$WindowsIsoMount = $null

try {
    $AutoUnattendCompatLevel = 2

    # Set the default proxy to use default credentials.
    # .NET really should do this (and can, via System.Net DefaultProxy's "UseDefaultCredentials" flag), but
    # that flag is not set by default, and getting it set external to this script is unreasonably cumbersome.
    # Setting this value once, here, is sufficient for all further instances in this script to use the
    # default credentials.
    (New-Object System.Net.WebClient).Proxy.Credentials = [System.Net.CredentialCache]::DefaultNetworkCredentials

    # Just creating a lower scope for the temp vars.
    $ActualRuntime = "0.0.0.0"
    if ($true) {
        # Build a complete version string for the current OS this script is running on.
        $a = [System.Environment]::OSVersion.Version
        $b = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -Name UBR).UBR
        $ActualRuntime = [version]::New($a.Major, $a.Minor, $a.Build, $b)
    }

    # Warn about versions of Windows the script may not be tested with.
    # This ONLY has to do with the machine this script is ACTIVELY RUNNING ON.
    [version]$ScriptMinimumTestedRuntime = [version]::New("10", "0", "19045", "2604")
    if ($ActualRuntime -lt $ScriptMinimumTestedRuntime) {
        Write-Warning "This version of Windows may not be new enough to run this script."
        Write-Warning "If you encounter problems, please update to the latest widely-available version of Windows."
    }

    Write-Host "This script is running on OS build $ActualRuntime"

    # We have to do the copy-paste check first, as an "exit" from a copy-paste context will
    # close the PowerShell instance (even PowerShell ISE), and prevent other exit-inducing
    # errors from being seen.
    if ([string]::IsNullOrEmpty($PSCommandPath)) {
        Write-Host "This script must be saved to a file, and run as a script."
        Write-Host "It cannot be copy-pasted into a PowerShell prompt."

        # PowerShell ISE doesn't allow reading a key, so just wait a day...
        if (Test-Path Variable:psISE) {
            Start-Sleep -Seconds (60*60*24)
            exit
        }

        # Wait for the user to see the error and acknowledge before closing the shell.
        Write-Host -NoNewLine 'Press any key to continue...'
        $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown') | Out-Null
        exit
    }

    # DISM commands don't work in 32-bit PowerShell.
    try {
        if (!([Environment]::Is64BitProcess)) {
            Write-Host "This script must be run from 64-bit PowerShell."
            exit
        }
    } catch {
        Write-Host "Please make sure you have the latest version of PowerShell and the .NET runtime installed."
        exit
    }

    # Dot-sourcing is unecessary for this script, and has weird behaviors/side-effects.
    # Don't permit it.
    if ($MyInvocation.InvocationName -eq ".") {
        Write-Host "This script does not support being 'dot sourced.'"
        Write-Host "Please call the script using only its full or relative path, without a preceding dot/period."
        exit
    }

    # Like dot-sourcing, PowerShell ISE executes stuff in a way that causes weird behaviors/side-effects,
    # and is generally a hassle (and unecessary) to support.
    if (Test-Path Variable:psISE) {
        Write-Host "This script does not support being run in Powershell ISE."
        Write-Host "Please call this script using the normal PowerShell prompt, or by passing the script name directly to the PowerShell.exe executable."
        exit
    }

    # Have to be admin to do things like DISM commands.
    if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(`
        [Security.Principal.WindowsBuiltInRole] "Administrator")) {
        Write-Host "This script must be run from an elevated console."
        exit
    }

    Write-Host ("Script version {0}" -f $CreateSrsMediaScriptVersion)
    $UpdatedScript = Save-Url "https://go.microsoft.com/fwlink/?linkid=867842" "CreateSrsMedia" "update.ps1"
    Test-Signature $UpdatedScript
    Unblock-File $UpdatedScript
    [Version]$UpdatedScriptVersion = (& powershell -executionpolicy unrestricted ($UpdatedScript.Replace(" ", '` ')) -ShowVersion)
    if ($UpdatedScriptVersion -gt [Version]$CreateSrsMediaScriptVersion) {
        Write-Host ("Newer script found, version {0}" -f $UpdatedScriptVersion)
        Remove-Item $PSCommandPath
        Rename-Item $UpdatedScript $PSCommandPath
        $Arguments = ""
        $ScriptPart = 0

        # Find the first non-escaped space. This separates the script filename from the rest of the arguments.
        do {
            # If we find an escape character, jump over the character it's escaping.
            if($MyInvocation.Line[$ScriptPart] -eq "``") { $ScriptPart++ }
            $ScriptPart++
        } while($ScriptPart -lt $MyInvocation.Line.Length -and $MyInvocation.Line[$ScriptPart] -ne " ")

        # If we found an unescaped space, there are arguments -- extract them.
        if($ScriptPart -lt $MyInvocation.Line.Length) {
            $Arguments = $MyInvocation.Line.Substring($ScriptPart)
        }

        # Convert the script from a potentially relative path to a known-absolute path.
        # PSCommandPath does not escape spaces, so we need to do that.
        $Script = $PSCommandPath.Replace(" ", "`` ")

        Write-Host "Running the updated script."
        # Reconstruct a new, well-escaped, absolute-pathed, unrestricted call to PowerShell
        Start-Process "$psHome\powershell.exe" -ArgumentList ("-executionpolicy unrestricted " + $Script + $Arguments)
        Exit
    } else {
        Remove-Item $UpdatedScript
    }
    Write-Host ""

    # Script stats for debugging
    Write-Transcript (Get-FileHash -Algorithm SHA512 $PSCommandPath).Hash
    Write-Transcript (Get-Item $PSCommandPath).Length
    Write-Host ""

    # Initial sanity checks

    $ScriptDrive = [System.IO.DriveInfo]::GetDrives() |? { (Split-Path -Path $_.Name -Qualifier) -eq (Split-Path -Path $PSScriptRoot -Qualifier) }

    if ($ScriptDrive.DriveFormat -ne "NTFS") {
        Write-Host "This script must be run from an NTFS filesystem, as it can potentially cache very large files."
        exit
    }

    # Perform an advisory space check
    $EstimatedCacheSpace =  (1024*1024*1024*1.5) + # Estimated unpacked driver size
                            (1024*1024*1024*16) +  # Estimated exported WIM size
                            (1024*1024*100)        # Estimated unpacked SRSv2 kit size
    if ($ScriptDrive.AvailableFreeSpace -lt $EstimatedCacheSpace) {
        Write-Warning "The drive this script is running from may not have enough free space for the script to complete successfully."
        Write-Warning ("You should ensure at least {0:F2}GiB are available before continuing." -f ($EstimatedCacheSpace / (1024*1024*1024)) )
        Write-Warning "Would you like to proceed anyway?"
        do {
            $confirmation = (Read-Host -Prompt "YES or NO")
            if ($confirmation -eq "YES") {
                Write-Warning "Proceeding despite potentially insufficient scratch space."
                break
            }

            if ($confirmation -eq "NO") {
                Write-Host "Please re-run the script after you make more space available on the current drive, or move the script to a drive with more available space."
                exit
            }

            Write-Host "Invalid option."
        } while ($true)
    }

    # Determine OEM status
    $IsOem = $null
    if ($Manufacturing) {
        $IsOem = $true
    }
    while ($IsOem -eq $null) {
        Write-Host "What type of customer are you?"
        switch (Read-Host -Prompt "OEM or Enterprise") {
            "OEM" {
                $IsOem = $true
                Write-Transcript "OEM selected."
            }

            "Enterprise" {
                $IsOem = $false
                Write-Transcript "Enterprise selected."
            }

            Default {
                $IsOem = $null
            }
        }
    }


    if ($true) {
        $i = 1

        Write-Host ("Please make sure you have all of the following available:")
        Write-Host ("")
        Write-Host ("{0}. A USB drive with sufficient space (16GB+)." -f $i++)
        Write-Host ("   The contents of this drive WILL BE LOST!")
    if ($IsOem) {
        Write-Host ("{0}. Windows 10 Enterprise IoT media that matches your SRSv2 deployment kit." -f $i++)
    } else {
        Write-Host ("{0}. Windows 10 Enterprise media that matches your SRSv2 deployment kit." -f $i++)
    }
        PrintWhereToGetMedia -IsOem:$IsOem
        Write-Host ("{0}. Any language pack (LP and/or LIP) files to be included." -f $i++)
        PrintWhereToGetLangpacks -IsOem:$IsOem
        Write-Host ("")
        Write-Host ("Please do not continue until you have all these items in order.")
        Write-Host ("")
    }


    # Acquire the SRS deployment kit
    $SRSDK = Save-Url "https://go.microsoft.com/fwlink/?linkid=851168" "deployment kit"
    Test-Signature $SRSDK


    ## Extract the deployment kit.
    $RigelMedia = Join-Path $PSScriptRoot "SRSv2"

    if (Test-Path $RigelMedia) {
      Remove-Directory $RigelMedia
    }

    Write-Host "Extracting the deployment kit... " -NoNewline
    Expand-Archive $SRSDK $RigelMedia
    Write-Host "done."


    ## Pull relevant values from the deployment kit
    $RigelMedia = Join-Path $RigelMedia "Skype Room System Deployment Kit"

    $UnattendConfigFile = ([io.path]::Combine($RigelMedia, '$oem$', '$1', 'Rigel', 'x64', 'Scripts', 'Provisioning', 'config.json'))
    $UnattendConfig = @{}

    if ((Test-Path $UnattendConfigFile)) {
        $UnattendConfig = ConvertFrom-PSCustomObject (Get-Content $UnattendConfigFile | ConvertFrom-Json)
    }

    # Acquire the driver pack
    # We have to do this first now, in order to tell what OS-specific config files to pick out of the kit.
    Write-Host ""
    Write-Host "Please indicate what drivers you wish to use with this installation."
    $Variables = @{}
    $DriverPacks = Render-Menu -MenuItem $UnattendConfig["Drivers"]["RootItem"] -MenuItems $UnattendConfig["Drivers"]["MenuItems"] -Variables $Variables

    $BIOS = $false

    if ($Variables.ContainsKey("BIOS")) {
        $BIOS = $Variables["BIOS"]
    }

    # Determine the major OS. Default to 10 if not specified.
    $MajorOs = "10"
    if ($Variables.ContainsKey("OS")) {
        $MajorOs = $Variables["OS"]
    }

    # Swap in the set of variables for this major OS.
    # Use the root config by default if no OS subsection present.
    $MajorOsConfig = $UnattendConfig
    if ($UnattendConfig.ContainsKey("Win")) {
        $MajorOsConfig = $UnattendConfig["Win"][$MajorOs]
    }

    # If alternate config files are selected, copy them to the
    # root location, where they're expected to be.
    if ($MajorOsConfig.ContainsKey("AutoUnattend")) {
        $MajorOsConfigDir = ([io.path]::Combine($RigelMedia, "Provisioning", $MajorOsConfig["AutoUnattend"]))
        Copy-Item (Join-Path $MajorOsConfigDir "*.*") $RigelMedia -Force | Write-Debug
    }

    $UnattendFile = Join-Path $RigelMedia "AutoUnattend.xml"

    $xml = New-Object System.Xml.XmlDocument
    $XmlNs = @{"u"="urn:schemas-microsoft-com:unattend"}
    $xml.Load($UnattendFile)

    $SrsKitOs = (Select-Xml -Namespace $XmlNs -Xml $xml -XPath "//u:assemblyIdentity/@version").Node.Value

    # The language pack version should match the unattend version.
    $LangPackVersion = $SrsKitOs

    # In some cases, AutoUnattend does not/can not match the required
    # language pack's reported version number. In those cases, the correct
    # language pack version is explicitly specified in the config file.
    if ($MajorOsConfig.ContainsKey("LPVersion")) {
        $LangPackVersion = $MajorOsConfig["LPVersion"]
    }

    # In some cases, AutoUnattend does not/can not match the required media's
    # reported version number. In those cases, the correct media version is
    # explicitly specified in the config file.
    if ($MajorOsConfig.ContainsKey("MediaVersion")) {
        $SrsKitOs = $MajorOsConfig["MediaVersion"]
    }

    # Acquire detailed OS version and location information.
    $script:SrsKitHumanVersion = $MajorOsConfig["HumanVersion"]
    $SrsKitEffectiveVersion = $MajorOsConfig["EffectiveVersion"]
    $script:SrsKitVlscName = $MajorOsConfig["VlscName"]
    if ($IsOem) {
        $script:SrsKitIsoSize = $MajorOsConfig["OemSize"]
        $script:SrsKitIsoSha256 = $MajorOsConfig["OemSha256"]
    } else {
        $script:SrsKitIsoSize = $MajorOsConfig["VlscSize"]
        $script:SrsKitIsoSha256 = $MajorOsConfig["VlscSha256"]
    }

    # Now that we know what OS needs to be used, print out the full details.
    PrintWhereToGetMedia
    Write-Host ""

    $DriverDest = ((Select-Xml -Namespace $XmlNs -Xml $xml -XPath "//u:DriverPaths/u:PathAndCredentials/u:Path/text()").ToString())


    # Prevent old tools (e.g., DISM) from messing up images that are newer than the tool itself,
    # and creating difficult-to-debug images that look like they work right up until you can't
    # actually install them.
    if ($ActualRuntime -lt $SrsKitEffectiveVersion) {
        Write-Host ""
        Write-Host "The host OS this script is running from must be at least as new as the target"
        Write-Host "OS required by the deployment kit. Please update this machine to at least"
        Write-Host "Windows version $SrsKitEffectiveVersion and then re-run this script."
        Write-Host ""
        Write-Error "Current host OS is older than target OS version."
        exit
    }

    $DriverDest = $DriverDest.Replace("%configsetroot%", $RigelMedia)

    ## Extract the driver pack
    $DriverMedia = Join-Path $PSScriptRoot "Drivers"

    if (Test-Path $DriverMedia) {
      Remove-Directory $DriverMedia
    }

    New-Item -ItemType Directory $DriverMedia | Write-Debug

    ForEach ($DriverPack in $DriverPacks) {
        $Target = Join-Path $DriverMedia (Get-Item $DriverPack).BaseName
        Write-Host ("Extracting {0}... " -f (Split-Path $DriverPack -Leaf)) -NoNewline
        Expand-Archive $DriverPack $Target
        Write-Host "done."
    }

    # Acquire the language packs
    $LanguagePacks = @(Get-Item -Path (Join-Path $PSScriptRoot "*.cab"))
    $InstallLP = New-Object System.Collections.ArrayList
    $InstallLIP = New-Object System.Collections.ArrayList

    Write-Host "Identifying language packs... "
    ForEach ($LanguagePack in $LanguagePacks) {
        $package = $null
        try {
            $package = (Get-WindowsPackage -Online -PackagePath $LanguagePack)
        } catch {
            Write-Warning "$LanguagePack is not a language pack."
            continue
        }
        if ($package.ReleaseType -ine "LanguagePack") {
            Write-Warning "$LanguagePack is not a language pack."
            continue
        }
        $parts = $package.PackageName.Split("~")
        if ($parts[2] -ine "amd64") {
            Write-Warning "$LanguagePack is not for the right architecture."
            continue
        }
        if ($parts[4] -ine $LangPackVersion) {
            Write-Warning "$LanguagePack is not for the right OS version."
            continue
        }
        $type = ($package.CustomProperties |? {$_.Name -ieq "LPType"}).Value
        if ($type -ieq "LIP") {
            $InstallLIP.Add($LanguagePack) | Write-Debug
        } elseif ($type -ieq "Client") {
            $InstallLP.Add($LanguagePack) | Write-Debug
        } else {
            Write-Warning "$LanguagePack is of unknown type."
        }
    }
    Write-Host "... done identifying language packs."


    # Acquire the updates
    $InstallUpdates = New-Object System.Collections.ArrayList

    # Only get updates if the MSI indicates they're necessary.
    if ($MajorOsConfig.ContainsKey("RequiredUpdates")) {
        $MajorOsConfig["RequiredUpdates"].Keys |% {
            $URL = $MajorOsConfig["RequiredUpdates"][$_]
            $File = Save-Url $URL "update $_"
            $InstallUpdates.Add($File) | Write-Debug
        }
    }

    # Verify signatures on whatever updates were aquired.
    foreach ($update in $InstallUpdates) {
        Test-Signature $update
    }

    if ($InstallLP.Count -eq 0 -and $InstallLIP.Count -eq 0 -and $InstallUpdates -ne $null) {
        Write-Warning "THIS IS YOUR ONLY CHANCE TO PRE-INSTALL LANGUAGE PACKS."
        Write-Host "Because you are pre-installing an update, you will NOT be able to pre-install language packs to the image at a later point."
        Write-Host "You are currently building an image with NO pre-installed language packs."
        Write-Host "Are you ABSOLUTELY SURE this is what you intended?"

        do {
            $confirmation = (Read-Host -Prompt "YES or NO")
            if ($confirmation -eq "YES") {
                Write-Warning "PROCEEDING TO GENERATE SLIPSTREAM IMAGE WITH NO PRE-INSTALLED LANGUAGE PACKS."
                break
            }

            if ($confirmation -eq "NO") {
                Write-Host "Please place the LP and LIP cab files you wish to use in this directory, and run the script again."
                Write-Host ""
                Write-Host "You can download language packs from the following locations:"
                PrintWhereToGetLangpacks -IsOem:$IsOem
                exit
            }

            Write-Host "Invalid option."
        } while ($true)
    }

    # Discover and prompt for selection of a reasonable target drive
    $TargetDrive = $null

    $TargetType = "USB"
    if ($Manufacturing) {
        $TargetType = "File Backed Virtual"
    }
    $ValidTargetDisks = @((Get-Disk) |? {$_.BusType -eq $TargetType})

    if ($ValidTargetDisks.Count -eq 0) {
        Write-Host "You do not have any valid media plugged in. Ensure that you have a removable drive inserted into the computer."
        exit
    }

    Write-Host ""
    Write-Host "Reminder: all data on the drive you select will be lost!"
    Write-Host ""

    $TargetDisk = ($ValidTargetDisks[(Get-TextListSelection -Options $ValidTargetDisks -Property "FriendlyName" -Prompt "Please select a target drive" -AllowDefault:$false)])

    # Acquire the Windows install media root
    do {
        # Trim off leading/trailing quote marks, as pasting in a copied-as-path string will have.
        $WindowsIso = (Read-Host -Prompt "Please enter the path to the Windows install ISO file").Trim('"')
    } while ([string]::IsNullOrEmpty($WindowsIso) -or !(Test-OsIsoPath -OsIsoPath $WindowsIso -KitIsoSize $script:SrsKitIsoSize -KitIsoSha256 $script:SrsKitIsoSha256 -IsOem:$IsOem))

    $WindowsIsoMount = Mount-DiskImage $WindowsIso
    $WindowsMedia = ($WindowsIsoMount | Get-Volume).DriveLetter + ":"

    # All non-VL keys are OA3.0 based now
    $LicenseKey = ""

    if ($Manufacturing) {
        $LicenseKey = "XQQYW-NFFMW-XJPBH-K8732-CKFFD"
    } elseif ($IsOem) {
        $LicenseKey = "XQQYW-NFFMW-XJPBH-K8732-CKFFD"
    }

    ###
    ## Let the user know what we've discovered
    ###

    Write-Host ""
    if ($IsOem) {
        Write-Host "Creating OEM media."
    } else {
        Write-Host "Creating Enterprise media."
    }
    Write-Host ""
    if ($BIOS) {
        Write-Host "Creating BIOS-compatible media."
    } else {
        Write-Host "Creating UEFI-compatible media."
    }
    Write-Host ""
    Write-Host "Using SRSv2 kit:      " $SRSDK
    Write-Host "Using driver packs:   "
    ForEach ($pack in $DriverPacks) {
        Write-Host "    $pack"
    }
    Write-Host "Using Windows ISO:    " $WindowsIso
    Write-Host "ISO mounted at:       " $WindowsMedia

    Write-Host "Using language packs: "
    ForEach ($pack in $InstallLP) {
        Write-Host "    $pack"
    }
    ForEach ($pack in $InstallLIP) {
        Write-Host "    $pack"
    }

    Write-Host "Using updates:        "
    ForEach ($update in $InstallUpdates) {
        Write-Host "    $update"
    }
    Write-Host "Writing stick:        " $TargetDisk.FriendlyName
    Write-Host ""


    ###
    ## Make the stick.
    ###


    # Partition & format
    Write-Host "Formatting and partitioning the target drive... " -NoNewline
    Get-Disk $TargetDisk.DiskNumber | Initialize-Disk -PartitionStyle MBR -ErrorAction SilentlyContinue
    Clear-Disk -Number $TargetDisk.DiskNumber -RemoveData -RemoveOEM -Confirm:$false
    Get-Disk $TargetDisk.DiskNumber | Initialize-Disk -PartitionStyle MBR -ErrorAction SilentlyContinue
    Get-Disk $TargetDisk.DiskNumber | Set-Disk -PartitionStyle MBR

    ## Windows refuses to quick format FAT32 over 32GB in size.
    $part = $null
    try {
        ## For disks >= 32GB
        $part = New-Partition -DiskNumber $TargetDisk.DiskNumber -Size 32GB -AssignDriveLetter -IsActive -ErrorAction Stop
    } catch {
        ## For disks < 32GB
        $part = New-Partition -DiskNumber $TargetDisk.DiskNumber -UseMaximumSize -AssignDriveLetter -IsActive -ErrorAction Stop
    }

    $part | Format-Volume -FileSystem FAT32 -NewFileSystemLabel "SRSV2" -Confirm:$false | Write-Debug

    $TargetDrive = ("{0}:\" -f $part.DriveLetter)
    Write-Host "done."

    # Windows
    Write-Host "Copying Windows... " -NoNewline
    ## Exclude install.wim, since apparently some Windows source media are not USB EFI compatible (?) and have WIMs >4GB in size.
    SyncDirectory -Src $WindowsMedia -Dst $TargetDrive -Flags @("/xf", "install.wim")
    Write-Host "done."

    $NewInstallWim = (Join-Path $PSScriptRoot "install.wim")
    $InstallWimMnt = (Join-Path $PSScriptRoot "com-mnt")
    $SourceName = "Windows $MajorOs Enterprise"

    try {
        Write-Host "Copying the installation image... " -NoNewline
        Export-WindowsImage -DestinationImagePath "$NewInstallWim" -SourceImagePath (Join-Path (Join-Path $WindowsMedia "sources") "install.wim") -SourceName $SourceName | Write-Debug
        Write-Host "done."

        # Image update
        if ($InstallLP.Count -gt 0 -or $InstallLIP.Count -gt 0 -or $InstallUpdates -ne $null) {
            mkdir $InstallWimMnt | Write-Debug
            Write-Host "Mounting the installation image... " -NoNewline
            Mount-WindowsImage -ImagePath "$NewInstallWim" -Path "$InstallWimMnt" -Name $SourceName | Write-Debug
            Write-Host "done."

            Write-Host "Applying language packs... " -NoNewline
            ForEach ($pack in $InstallLP) {
                Add-WindowsPackage -Path "$InstallWimMnt" -PackagePath "$pack" -ErrorAction Stop | Write-Debug
            }
            ForEach ($pack in $InstallLIP) {
                Add-WindowsPackage -Path "$InstallWimMnt" -PackagePath "$pack" -ErrorAction Stop | Write-Debug
            }
            Write-Host "done."

            Write-Host "Applying updates... " -NoNewline
            ForEach ($update in $InstallUpdates) {
                Add-WindowsPackage -Path "$InstallWimMnt" -PackagePath "$update" -ErrorAction Stop | Write-Debug
            }
            Write-Host "done."

            Write-Host ""
            Write-Warning "PLEASE WAIT PATIENTLY"
            Write-Host "This next part can, on some hardware, take multiple hours to complete."
            Write-Host "Aborting at this point will result in NON-FUNCTIONAL MEDIA."
            Write-Host "To minimize wait time, consider hardware improvements:"
            Write-Host "  - Use a higher (single-core) performance CPU"
            Write-Host "  - Use a fast SSD, connected by a fast bus (6Gbps SATA, 8Gbps NVMe, etc.)"
            Write-Host ""

            Write-Host "Cleaning up the installation image... " -NoNewline
            Set-ItemProperty (Join-Path (Join-Path $TargetDrive "sources") "lang.ini") -name IsReadOnly -value $false
            Invoke-Native "& dism /quiet /image:$InstallWimMnt /gen-langini /distribution:$TargetDrive"
            Invoke-Native "& dism /quiet /image:$InstallWimMnt /cleanup-image /startcomponentcleanup /resetbase"
            Write-Host "done."

            Write-Host "Unmounting the installation image... " -NoNewline
            Dismount-WindowsImage -Path $InstallWimMnt -Save | Write-Debug
            rmdir $InstallWimMnt
            Write-Host "done."
        }

        Write-Host "Splitting the installation image... " -NoNewline
        Split-WindowsImage -ImagePath "$NewInstallWim" -SplitImagePath (Join-Path (Join-Path $TargetDrive "sources") "install.swm") -FileSize 2047 | Write-Debug
        del $NewInstallWim
        Write-Host "done."
    } catch {
        try { Dismount-WindowsImage -Path $InstallWimMnt -Discard -ErrorAction SilentlyContinue } catch {}
        del $InstallWimMnt -Force -ErrorAction SilentlyContinue
        del $NewInstallWim -Force -ErrorAction SilentlyContinue
        throw
    }

    # Drivers
    Write-Host "Injecting drivers... " -NoNewline
    SyncSubdirectories -Src $DriverMedia -Dst $DriverDest
    Write-Host "done."

    # Rigel
    Write-Host "Copying Rigel build... " -NoNewline
    SyncSubdirectories -Src $RigelMedia -Dst $TargetDrive
    Copy-Item (Join-Path $RigelMedia "*.*") $TargetDrive | Write-Debug
    Write-Host "done."

    # Snag and update the unattend
    Write-Host "Configuring unattend files... " -NoNewline

    $RootUnattendFile = ([io.path]::Combine($TargetDrive, 'AutoUnattend.xml'))
    $InnerUnattendFile = ([io.path]::Combine($TargetDrive, '$oem$', '$1', 'Rigel', 'x64', 'Scripts', 'Provisioning', 'AutoUnattend.xml'))

    ## Handle the root unattend
    $xml = New-Object System.Xml.XmlDocument
    $xml.Load($RootUnattendFile)
    if ($IsOem) {
        Add-AutoUnattend-Key $xml $LicenseKey
    }
    Set-AutoUnattend-Sysprep-Mode -Xml $xml -Shutdown
    Set-AutoUnattend-Partitions -Xml $xml -BIOS:$BIOS
    $xml.Save($RootUnattendFile)

    ## Handle the inner unattend
    $xml = New-Object System.Xml.XmlDocument
    $xml.Load($InnerUnattendFile)
    if ($IsOem) {
        Add-AutoUnattend-Key $xml "XQQYW-NFFMW-XJPBH-K8732-CKFFD"
    }
    Set-AutoUnattend-Sysprep-Mode -Xml $xml -Reboot
    Set-AutoUnattend-Partitions -Xml $xml -BIOS:$BIOS
    $xml.Save($InnerUnattendFile)

    Write-Host "done."

    # Let Windows setup know what kind of license key to check for.
    Write-Host "Selecting image... " -NoNewline
    $TargetEICfg = (Join-Path (Join-Path $TargetDrive "sources") "EI.cfg")
    $OEMEICfg = @"
[EditionID]
Enterprise
[Channel]
OEM
[VL]
0
"@
    $EnterpriseEICfg = @"
[EditionID]
Enterprise
[Channel]
Retail
[VL]
1
"@
    if ($IsOem) {
        $OEMEICfg | Out-File -FilePath $TargetEICfg -Force
    } else {
        $EnterpriseEICfg | Out-File -FilePath $TargetEICfg -Force
    }
    Write-Host "done."


    Write-Host "Cleaning up... " -NoNewline

    Remove-Directory $DriverMedia
    Remove-Directory $RigelMedia

    # This folder can sometimes cause copy errors during Windows Setup, specifically when Setup is creating the ConfigSet folder.
    Remove-Item (Join-Path $TargetDrive "System Volume Information") -Recurse -Force -ErrorAction SilentlyContinue

    Write-Host "done."


    Write-Host ""
    Write-Host "Please safely eject your USB stick before removing it."

    if ($InstallUpdates -ne $null) {
        Write-Warning "DO NOT PRE-INSTALL LANGUAGE PACKS AFTER THIS POINT"
        Write-Warning "You have applied a Windows Update to this media. Any pre-installed language packs must be added BEFORE Windows updates."
    }
} finally {
    try {
        if ($WindowsIsoMount -ne $null) {
            $WindowsIsoMount | Dismount-DiskImage | Write-Debug
        }
    } catch {}
    Stop-Transcript
}
# SIG # Begin signature block
# MIInkwYJKoZIhvcNAQcCoIInhDCCJ4ACAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCCYiLJa/E7WAqh1
# lo9kSoCxBaEn7Ca/sczAV7QHo7GKwaCCDXYwggX0MIID3KADAgECAhMzAAADTrU8
# esGEb+srAAAAAANOMA0GCSqGSIb3DQEBCwUAMH4xCzAJBgNVBAYTAlVTMRMwEQYD
# VQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jvc29mdCBDb2RlIFNpZ25p
# bmcgUENBIDIwMTEwHhcNMjMwMzE2MTg0MzI5WhcNMjQwMzE0MTg0MzI5WjB0MQsw
# CQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9u
# ZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMR4wHAYDVQQDExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24wggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIB
# AQDdCKiNI6IBFWuvJUmf6WdOJqZmIwYs5G7AJD5UbcL6tsC+EBPDbr36pFGo1bsU
# p53nRyFYnncoMg8FK0d8jLlw0lgexDDr7gicf2zOBFWqfv/nSLwzJFNP5W03DF/1
# 1oZ12rSFqGlm+O46cRjTDFBpMRCZZGddZlRBjivby0eI1VgTD1TvAdfBYQe82fhm
# WQkYR/lWmAK+vW/1+bO7jHaxXTNCxLIBW07F8PBjUcwFxxyfbe2mHB4h1L4U0Ofa
# +HX/aREQ7SqYZz59sXM2ySOfvYyIjnqSO80NGBaz5DvzIG88J0+BNhOu2jl6Dfcq
# jYQs1H/PMSQIK6E7lXDXSpXzAgMBAAGjggFzMIIBbzAfBgNVHSUEGDAWBgorBgEE
# AYI3TAgBBggrBgEFBQcDAzAdBgNVHQ4EFgQUnMc7Zn/ukKBsBiWkwdNfsN5pdwAw
# RQYDVR0RBD4wPKQ6MDgxHjAcBgNVBAsTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEW
# MBQGA1UEBRMNMjMwMDEyKzUwMDUxNjAfBgNVHSMEGDAWgBRIbmTlUAXTgqoXNzci
# tW2oynUClTBUBgNVHR8ETTBLMEmgR6BFhkNodHRwOi8vd3d3Lm1pY3Jvc29mdC5j
# b20vcGtpb3BzL2NybC9NaWNDb2RTaWdQQ0EyMDExXzIwMTEtMDctMDguY3JsMGEG
# CCsGAQUFBwEBBFUwUzBRBggrBgEFBQcwAoZFaHR0cDovL3d3dy5taWNyb3NvZnQu
# Y29tL3BraW9wcy9jZXJ0cy9NaWNDb2RTaWdQQ0EyMDExXzIwMTEtMDctMDguY3J0
# MAwGA1UdEwEB/wQCMAAwDQYJKoZIhvcNAQELBQADggIBAD21v9pHoLdBSNlFAjmk
# mx4XxOZAPsVxxXbDyQv1+kGDe9XpgBnT1lXnx7JDpFMKBwAyIwdInmvhK9pGBa31
# TyeL3p7R2s0L8SABPPRJHAEk4NHpBXxHjm4TKjezAbSqqbgsy10Y7KApy+9UrKa2
# kGmsuASsk95PVm5vem7OmTs42vm0BJUU+JPQLg8Y/sdj3TtSfLYYZAaJwTAIgi7d
# hzn5hatLo7Dhz+4T+MrFd+6LUa2U3zr97QwzDthx+RP9/RZnur4inzSQsG5DCVIM
# pA1l2NWEA3KAca0tI2l6hQNYsaKL1kefdfHCrPxEry8onJjyGGv9YKoLv6AOO7Oh
# JEmbQlz/xksYG2N/JSOJ+QqYpGTEuYFYVWain7He6jgb41JbpOGKDdE/b+V2q/gX
# UgFe2gdwTpCDsvh8SMRoq1/BNXcr7iTAU38Vgr83iVtPYmFhZOVM0ULp/kKTVoir
# IpP2KCxT4OekOctt8grYnhJ16QMjmMv5o53hjNFXOxigkQWYzUO+6w50g0FAeFa8
# 5ugCCB6lXEk21FFB1FdIHpjSQf+LP/W2OV/HfhC3uTPgKbRtXo83TZYEudooyZ/A
# Vu08sibZ3MkGOJORLERNwKm2G7oqdOv4Qj8Z0JrGgMzj46NFKAxkLSpE5oHQYP1H
# tPx1lPfD7iNSbJsP6LiUHXH1MIIHejCCBWKgAwIBAgIKYQ6Q0gAAAAAAAzANBgkq
# hkiG9w0BAQsFADCBiDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24x
# EDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlv
# bjEyMDAGA1UEAxMpTWljcm9zb2Z0IFJvb3QgQ2VydGlmaWNhdGUgQXV0aG9yaXR5
# IDIwMTEwHhcNMTEwNzA4MjA1OTA5WhcNMjYwNzA4MjEwOTA5WjB+MQswCQYDVQQG
# EwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwG
# A1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSgwJgYDVQQDEx9NaWNyb3NvZnQg
# Q29kZSBTaWduaW5nIFBDQSAyMDExMIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIIC
# CgKCAgEAq/D6chAcLq3YbqqCEE00uvK2WCGfQhsqa+laUKq4BjgaBEm6f8MMHt03
# a8YS2AvwOMKZBrDIOdUBFDFC04kNeWSHfpRgJGyvnkmc6Whe0t+bU7IKLMOv2akr
# rnoJr9eWWcpgGgXpZnboMlImEi/nqwhQz7NEt13YxC4Ddato88tt8zpcoRb0Rrrg
# OGSsbmQ1eKagYw8t00CT+OPeBw3VXHmlSSnnDb6gE3e+lD3v++MrWhAfTVYoonpy
# 4BI6t0le2O3tQ5GD2Xuye4Yb2T6xjF3oiU+EGvKhL1nkkDstrjNYxbc+/jLTswM9
# sbKvkjh+0p2ALPVOVpEhNSXDOW5kf1O6nA+tGSOEy/S6A4aN91/w0FK/jJSHvMAh
# dCVfGCi2zCcoOCWYOUo2z3yxkq4cI6epZuxhH2rhKEmdX4jiJV3TIUs+UsS1Vz8k
# A/DRelsv1SPjcF0PUUZ3s/gA4bysAoJf28AVs70b1FVL5zmhD+kjSbwYuER8ReTB
# w3J64HLnJN+/RpnF78IcV9uDjexNSTCnq47f7Fufr/zdsGbiwZeBe+3W7UvnSSmn
# Eyimp31ngOaKYnhfsi+E11ecXL93KCjx7W3DKI8sj0A3T8HhhUSJxAlMxdSlQy90
# lfdu+HggWCwTXWCVmj5PM4TasIgX3p5O9JawvEagbJjS4NaIjAsCAwEAAaOCAe0w
# ggHpMBAGCSsGAQQBgjcVAQQDAgEAMB0GA1UdDgQWBBRIbmTlUAXTgqoXNzcitW2o
# ynUClTAZBgkrBgEEAYI3FAIEDB4KAFMAdQBiAEMAQTALBgNVHQ8EBAMCAYYwDwYD
# VR0TAQH/BAUwAwEB/zAfBgNVHSMEGDAWgBRyLToCMZBDuRQFTuHqp8cx0SOJNDBa
# BgNVHR8EUzBRME+gTaBLhklodHRwOi8vY3JsLm1pY3Jvc29mdC5jb20vcGtpL2Ny
# bC9wcm9kdWN0cy9NaWNSb29DZXJBdXQyMDExXzIwMTFfMDNfMjIuY3JsMF4GCCsG
# AQUFBwEBBFIwUDBOBggrBgEFBQcwAoZCaHR0cDovL3d3dy5taWNyb3NvZnQuY29t
# L3BraS9jZXJ0cy9NaWNSb29DZXJBdXQyMDExXzIwMTFfMDNfMjIuY3J0MIGfBgNV
# HSAEgZcwgZQwgZEGCSsGAQQBgjcuAzCBgzA/BggrBgEFBQcCARYzaHR0cDovL3d3
# dy5taWNyb3NvZnQuY29tL3BraW9wcy9kb2NzL3ByaW1hcnljcHMuaHRtMEAGCCsG
# AQUFBwICMDQeMiAdAEwAZQBnAGEAbABfAHAAbwBsAGkAYwB5AF8AcwB0AGEAdABl
# AG0AZQBuAHQALiAdMA0GCSqGSIb3DQEBCwUAA4ICAQBn8oalmOBUeRou09h0ZyKb
# C5YR4WOSmUKWfdJ5DJDBZV8uLD74w3LRbYP+vj/oCso7v0epo/Np22O/IjWll11l
# hJB9i0ZQVdgMknzSGksc8zxCi1LQsP1r4z4HLimb5j0bpdS1HXeUOeLpZMlEPXh6
# I/MTfaaQdION9MsmAkYqwooQu6SpBQyb7Wj6aC6VoCo/KmtYSWMfCWluWpiW5IP0
# wI/zRive/DvQvTXvbiWu5a8n7dDd8w6vmSiXmE0OPQvyCInWH8MyGOLwxS3OW560
# STkKxgrCxq2u5bLZ2xWIUUVYODJxJxp/sfQn+N4sOiBpmLJZiWhub6e3dMNABQam
# ASooPoI/E01mC8CzTfXhj38cbxV9Rad25UAqZaPDXVJihsMdYzaXht/a8/jyFqGa
# J+HNpZfQ7l1jQeNbB5yHPgZ3BtEGsXUfFL5hYbXw3MYbBL7fQccOKO7eZS/sl/ah
# XJbYANahRr1Z85elCUtIEJmAH9AAKcWxm6U/RXceNcbSoqKfenoi+kiVH6v7RyOA
# 9Z74v2u3S5fi63V4GuzqN5l5GEv/1rMjaHXmr/r8i+sLgOppO6/8MO0ETI7f33Vt
# Y5E90Z1WTk+/gFcioXgRMiF670EKsT/7qMykXcGhiJtXcVZOSEXAQsmbdlsKgEhr
# /Xmfwb1tbWrJUnMTDXpQzTGCGXMwghlvAgEBMIGVMH4xCzAJBgNVBAYTAlVTMRMw
# EQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVN
# aWNyb3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jvc29mdCBDb2RlIFNp
# Z25pbmcgUENBIDIwMTECEzMAAANOtTx6wYRv6ysAAAAAA04wDQYJYIZIAWUDBAIB
# BQCgga4wGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQwHAYKKwYBBAGCNwIBCzEO
# MAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEIC6bs7jnnH+vvvwczl3fhdUY
# qr6BTfEk7jP3n8C2UIGxMEIGCisGAQQBgjcCAQwxNDAyoBSAEgBNAGkAYwByAG8A
# cwBvAGYAdKEagBhodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20wDQYJKoZIhvcNAQEB
# BQAEggEAz1rwHq469n/fowe50G40tA6M9grf6U/xEvt707BCQpwCi4rJ883dIFkq
# om7NXcI7mp6YPI7hVotcFCunQxOs8rA1TlaBUnSzNf8DqH2s+uVY0tdlzAZ5xKYA
# 6OCzS0yA/+tDY/Fpy7R+bFYd8vs9jOdqtSffYY0lcCWSD/wqIRLJcCNszj92UX6H
# PWvmr9ZS0oKjthxXii/nNfqVpCVd3syaUrmJu2Mi+KHH97R2/FKD8zZ0yW4BT/86
# fi3kpQTpdoTFNpgCVaNbKWOGpgNwEW2UJFX3wY+dfA54DS2bZCv22VaFR+QAu/9H
# C34NbEqb3H5yXMapU6OqMUcX/02/raGCFv0wghb5BgorBgEEAYI3AwMBMYIW6TCC
# FuUGCSqGSIb3DQEHAqCCFtYwghbSAgEDMQ8wDQYJYIZIAWUDBAIBBQAwggFRBgsq
# hkiG9w0BCRABBKCCAUAEggE8MIIBOAIBAQYKKwYBBAGEWQoDATAxMA0GCWCGSAFl
# AwQCAQUABCAMRer55leAY+KAZQKOryc3g3MdEFwxuGRItSW+lm60ywIGZDfrBUcZ
# GBMyMDIzMDUwMzE4MTEyMS41ODZaMASAAgH0oIHQpIHNMIHKMQswCQYDVQQGEwJV
# UzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UE
# ChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSUwIwYDVQQLExxNaWNyb3NvZnQgQW1l
# cmljYSBPcGVyYXRpb25zMSYwJAYDVQQLEx1UaGFsZXMgVFNTIEVTTjo4QTgyLUUz
# NEYtOUREQTElMCMGA1UEAxMcTWljcm9zb2Z0IFRpbWUtU3RhbXAgU2VydmljZaCC
# EVQwggcMMIIE9KADAgECAhMzAAABwvp9hw5UU0ckAAEAAAHCMA0GCSqGSIb3DQEB
# CwUAMHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQH
# EwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNV
# BAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwMB4XDTIyMTEwNDE5MDEy
# OFoXDTI0MDIwMjE5MDEyOFowgcoxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNo
# aW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29y
# cG9yYXRpb24xJTAjBgNVBAsTHE1pY3Jvc29mdCBBbWVyaWNhIE9wZXJhdGlvbnMx
# JjAkBgNVBAsTHVRoYWxlcyBUU1MgRVNOOjhBODItRTM0Ri05RERBMSUwIwYDVQQD
# ExxNaWNyb3NvZnQgVGltZS1TdGFtcCBTZXJ2aWNlMIICIjANBgkqhkiG9w0BAQEF
# AAOCAg8AMIICCgKCAgEAtfEJvPKOSFn3petp9wco29/UoJmDDyHpmmpRruRVWBF3
# 7By0nvrszScOV/K+LvHWWWC4S9cme4P63EmNhxTN/k2CgPnIt/sDepyACSkya4uk
# qc1sT2I+0Uod0xjy9K2+jLH8UNb9vM3yH/vCYnaJSUqgtqZUly82pgYSB6tDeZIY
# cQoOhTI+M1HhRxmxt8RaAKZnDnXgLdkhnIYDJrRkQBpIgahtExtTuOkmVp2y8YCo
# FPaUhUD2JT6hPiDD7qD7A77PLpFzD2QFmNezT8aHHhKsVBuJMLPXZO1k14j0/k68
# DZGts1YBtGegXNkyvkXSgCCxt3Q8WF8laBXbDnhHaDLBhCOBaZQ8jqcFUx8ZJSXQ
# 8sbvEnmWFZmgM93B9P/JTFTF6qBVFMDd/V0PBbRQC2TctZH4bfv+jyWvZOeFz5yl
# tPLRxUqBjv4KHIaJgBhU2ntMw4H0hpm4B7s6LLxkTsjLsajjCJI8PiKi/mPKYERd
# mRyvFL8/YA/PdqkIwWWg2Tj5tyutGFtfVR+6GbcCVhijjy7l7otxa/wYVSX66Lo0
# alaThjc+uojVwH4psL+A1qvbWDB9swoKla20eZubw7fzCpFe6qs++G01sst1SaA0
# GGmzuQCd04Ue1eH3DFRDZPsN+aWvA455Qmd9ZJLGXuqnBo4BXwVxdWZNj6+b4P8C
# AwEAAaOCATYwggEyMB0GA1UdDgQWBBRGsYh76V41aUCRXE9WvD++sIfGajAfBgNV
# HSMEGDAWgBSfpxVdAF5iXYP05dJlpxtTNRnpcjBfBgNVHR8EWDBWMFSgUqBQhk5o
# dHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NybC9NaWNyb3NvZnQlMjBU
# aW1lLVN0YW1wJTIwUENBJTIwMjAxMCgxKS5jcmwwbAYIKwYBBQUHAQEEYDBeMFwG
# CCsGAQUFBzAChlBodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NlcnRz
# L01pY3Jvc29mdCUyMFRpbWUtU3RhbXAlMjBQQ0ElMjAyMDEwKDEpLmNydDAMBgNV
# HRMBAf8EAjAAMBMGA1UdJQQMMAoGCCsGAQUFBwMIMA0GCSqGSIb3DQEBCwUAA4IC
# AQARdu3dCkcLLPfaJ3rR1M7D9jWHvneffkmXvFIJtqxHGWM1oqAh+bqxpI7HZz2M
# eNhh1Co+E9AabOgj94Sp1seXxdWISJ9lRGaAAWzA873aTB3/SjwuGqbqQuAvUzBF
# CO40UJ9anpavkpq/0nDqLb7XI5H+nsmjFyu8yqX1PMmnb4s1fbc/F30ijaASzqJ+
# p5rrgYWwDoMihM5bF0Y0riXihwE7eTShak/EwcxRmG3h+OT+Ox8KOLuLqwFFl1si
# TeQCp+YSt4J1tWXapqGJDlCbYr3Rz8+ryTS8CoZAU0vSHCOQcq12Th81p7QlHZv9
# cTRDhZg2TVyg8Gx3X6mkpNOXb56QUohI3Sn39WQJwjDn74J0aVYMai8mY6/WOurK
# MKEuSNhCiei0TK68vOY7sH0XEBWnRSbVefeStDo94UIUVTwd2HmBEfY8kfryp3Rl
# A9A4FvfUvDHMaF9BtvU/pK6d1CdKG29V0WN3uVzfYETJoRpjLYFGq0MvK6QVMmuN
# xk3bCRfj1acSWee14UGjglxWwvyOfNJe3pxcNFOd8Hhyp9d4AlQGVLNotaFvopgP
# LeJwUT3dl5VaAAhMwvIFmqwsffQy93morrprcnv74r5g3ejC39NYpFEoy+qmzLW1
# jFa1aXE2Xb/KZw2yawqldSp0Hu4VEkjGxFNc+AztIUWwmTCCB3EwggVZoAMCAQIC
# EzMAAAAVxedrngKbSZkAAAAAABUwDQYJKoZIhvcNAQELBQAwgYgxCzAJBgNVBAYT
# AlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYD
# VQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xMjAwBgNVBAMTKU1pY3Jvc29mdCBS
# b290IENlcnRpZmljYXRlIEF1dGhvcml0eSAyMDEwMB4XDTIxMDkzMDE4MjIyNVoX
# DTMwMDkzMDE4MzIyNVowfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0
# b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3Jh
# dGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTAwggIi
# MA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQDk4aZM57RyIQt5osvXJHm9DtWC
# 0/3unAcH0qlsTnXIyjVX9gF/bErg4r25PhdgM/9cT8dm95VTcVrifkpa/rg2Z4VG
# Iwy1jRPPdzLAEBjoYH1qUoNEt6aORmsHFPPFdvWGUNzBRMhxXFExN6AKOG6N7dcP
# 2CZTfDlhAnrEqv1yaa8dq6z2Nr41JmTamDu6GnszrYBbfowQHJ1S/rboYiXcag/P
# XfT+jlPP1uyFVk3v3byNpOORj7I5LFGc6XBpDco2LXCOMcg1KL3jtIckw+DJj361
# VI/c+gVVmG1oO5pGve2krnopN6zL64NF50ZuyjLVwIYwXE8s4mKyzbnijYjklqwB
# Sru+cakXW2dg3viSkR4dPf0gz3N9QZpGdc3EXzTdEonW/aUgfX782Z5F37ZyL9t9
# X4C626p+Nuw2TPYrbqgSUei/BQOj0XOmTTd0lBw0gg/wEPK3Rxjtp+iZfD9M269e
# wvPV2HM9Q07BMzlMjgK8QmguEOqEUUbi0b1qGFphAXPKZ6Je1yh2AuIzGHLXpyDw
# wvoSCtdjbwzJNmSLW6CmgyFdXzB0kZSU2LlQ+QuJYfM2BjUYhEfb3BvR/bLUHMVr
# 9lxSUV0S2yW6r1AFemzFER1y7435UsSFF5PAPBXbGjfHCBUYP3irRbb1Hode2o+e
# FnJpxq57t7c+auIurQIDAQABo4IB3TCCAdkwEgYJKwYBBAGCNxUBBAUCAwEAATAj
# BgkrBgEEAYI3FQIEFgQUKqdS/mTEmr6CkTxGNSnPEP8vBO4wHQYDVR0OBBYEFJ+n
# FV0AXmJdg/Tl0mWnG1M1GelyMFwGA1UdIARVMFMwUQYMKwYBBAGCN0yDfQEBMEEw
# PwYIKwYBBQUHAgEWM2h0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvRG9j
# cy9SZXBvc2l0b3J5Lmh0bTATBgNVHSUEDDAKBggrBgEFBQcDCDAZBgkrBgEEAYI3
# FAIEDB4KAFMAdQBiAEMAQTALBgNVHQ8EBAMCAYYwDwYDVR0TAQH/BAUwAwEB/zAf
# BgNVHSMEGDAWgBTV9lbLj+iiXGJo0T2UkFvXzpoYxDBWBgNVHR8ETzBNMEugSaBH
# hkVodHRwOi8vY3JsLm1pY3Jvc29mdC5jb20vcGtpL2NybC9wcm9kdWN0cy9NaWNS
# b29DZXJBdXRfMjAxMC0wNi0yMy5jcmwwWgYIKwYBBQUHAQEETjBMMEoGCCsGAQUF
# BzAChj5odHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpL2NlcnRzL01pY1Jvb0Nl
# ckF1dF8yMDEwLTA2LTIzLmNydDANBgkqhkiG9w0BAQsFAAOCAgEAnVV9/Cqt4Swf
# ZwExJFvhnnJL/Klv6lwUtj5OR2R4sQaTlz0xM7U518JxNj/aZGx80HU5bbsPMeTC
# j/ts0aGUGCLu6WZnOlNN3Zi6th542DYunKmCVgADsAW+iehp4LoJ7nvfam++Kctu
# 2D9IdQHZGN5tggz1bSNU5HhTdSRXud2f8449xvNo32X2pFaq95W2KFUn0CS9QKC/
# GbYSEhFdPSfgQJY4rPf5KYnDvBewVIVCs/wMnosZiefwC2qBwoEZQhlSdYo2wh3D
# YXMuLGt7bj8sCXgU6ZGyqVvfSaN0DLzskYDSPeZKPmY7T7uG+jIa2Zb0j/aRAfbO
# xnT99kxybxCrdTDFNLB62FD+CljdQDzHVG2dY3RILLFORy3BFARxv2T5JL5zbcqO
# Cb2zAVdJVGTZc9d/HltEAY5aGZFrDZ+kKNxnGSgkujhLmm77IVRrakURR6nxt67I
# 6IleT53S0Ex2tVdUCbFpAUR+fKFhbHP+CrvsQWY9af3LwUFJfn6Tvsv4O+S3Fb+0
# zj6lMVGEvL8CwYKiexcdFYmNcP7ntdAoGokLjzbaukz5m/8K6TT4JDVnK+ANuOaM
# mdbhIurwJ0I9JZTmdHRbatGePu1+oDEzfbzL6Xu/OHBE0ZDxyKs6ijoIYn/ZcGNT
# TY3ugm2lBRDBcQZqELQdVTNYs6FwZvKhggLLMIICNAIBATCB+KGB0KSBzTCByjEL
# MAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1v
# bmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjElMCMGA1UECxMcTWlj
# cm9zb2Z0IEFtZXJpY2EgT3BlcmF0aW9uczEmMCQGA1UECxMdVGhhbGVzIFRTUyBF
# U046OEE4Mi1FMzRGLTlEREExJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1w
# IFNlcnZpY2WiIwoBATAHBgUrDgMCGgMVAMp1N1VLhPMvWXEoZfmF4apZlnRUoIGD
# MIGApH4wfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNV
# BAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQG
# A1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTAwDQYJKoZIhvcNAQEF
# BQACBQDn/MV2MCIYDzIwMjMwNTAzMTkzNTE4WhgPMjAyMzA1MDQxOTM1MThaMHQw
# OgYKKwYBBAGEWQoEATEsMCowCgIFAOf8xXYCAQAwBwIBAAICAn4wBwIBAAICEkow
# CgIFAOf+FvYCAQAwNgYKKwYBBAGEWQoEAjEoMCYwDAYKKwYBBAGEWQoDAqAKMAgC
# AQACAwehIKEKMAgCAQACAwGGoDANBgkqhkiG9w0BAQUFAAOBgQCMw4rpxZiZvt/L
# FGpwi6/XpFkM8kcMpcWmHrXn+6XUTl06CL/t5kI2us74WjcXnhxEciTNtEC93vI4
# Nw8swcEWUtY3t3yAv6C1oAX9oiT0j2dK1y9lNY1NSgsnwG8fGawyLC+Wtt1yO6N2
# ASoOmWX+c5oUNoHqwRHUKMCS+OZtzDGCBA0wggQJAgEBMIGTMHwxCzAJBgNVBAYT
# AlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYD
# VQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBU
# aW1lLVN0YW1wIFBDQSAyMDEwAhMzAAABwvp9hw5UU0ckAAEAAAHCMA0GCWCGSAFl
# AwQCAQUAoIIBSjAaBgkqhkiG9w0BCQMxDQYLKoZIhvcNAQkQAQQwLwYJKoZIhvcN
# AQkEMSIEIB0FI2VKExkO1rWMscaC7z9JzXybmi/KQuFKjtpHuaDUMIH6BgsqhkiG
# 9w0BCRACLzGB6jCB5zCB5DCBvQQgypNgW8fpsMV57r0F5beUuiEVOVe4BdmaO+e2
# 8mGDUBYwgZgwgYCkfjB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3Rv
# bjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0
# aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMAITMwAA
# AcL6fYcOVFNHJAABAAABwjAiBCDLf4Ldzjt1bDVPgfHVeo+nArDAYAcTkwfYBZAd
# eUtfvjANBgkqhkiG9w0BAQsFAASCAgAEjo4ArtOIjJALNdf7FP/s8J9FoAJwhnu6
# 3VTEP0g+crjq2WVe2INzeTQ/PRBUfaRP9CwsqUHWaJTj2wfwzo88FOLm4692w0T4
# tO2xwc3KKxKBOR1UAM53QavfCRDmWzAgRp8DsNXvUvvccqG1VExQaVt7RaSx2LhE
# YcCvIUrG7jxUoIRVoEfRT6aLa9pPPJXl+AI0eaEifZa64rJScGD+x8n/PBypeyja
# QES1uQVeWNDoLFJ0bSTM9gTtlJND3xAVlHQZ5N2dPhbvD4HgC8t5iuwRurqP8r3G
# 4bsMILi+wfNGwKTe/pqPM6AXizT4dzx2NQssLBsqcxbhpBYZOrJNiR8wbwl2LG9i
# qHfIv8xecLw9+h+vahGHiOyBGjjZU0bcU745HFwfChJSGdREhOoDWGSBQQ0ufA8r
# 1wE7Pv4Z5nzKWKSlKbx2bwC6ir8mdpa3gF7MyOe4hGiaOWyiMZ3k8SgLF1qa6/Y/
# 3RpC24Cu2B4vIZjwREi5hNBMnS8H2EJCHPrDiEvMTdLXzaJL3dkXSO3p/5F5kUW7
# zPTM1IQGFYMrOzew3aj5GCGiBQ/XYB0Nih2si8dAceLsIRzPcVHIrud9KFbD45jV
# phhFPjKiEG4PAzPb79WltSQq7NmaHUqOs2W0LWkVYZ6ptjmCYtHBp/c5t1AGFrvl
# DSlGrkTZ5w==
# SIG # End signature block
