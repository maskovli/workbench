#Requires -Version 5.1

<#
.SYNOPSIS
    Windows Update script for Autopilot enrollment with interactive status window.

.DESCRIPTION
    Installs all available Windows Updates via the PSWindowsUpdate module.
    Shows a locked, visible status window during enrollment so the user can see
    progress. The window cannot be closed or minimized until updates complete.

    When updates require a reboot (and -NoReboot is NOT set), a 15-minute
    countdown panel appears with three buttons: Pause, Restart now, Shutdown.

.PARAMETER AutoReboot
    Reboots the machine automatically (30s wait, no countdown UI).
    Use this for fire-and-forget automation.

.PARAMETER NoReboot
    Suppresses reboot completely. Recommended for Autopilot ESP flows where
    Autopilot/Intune handles reboots.

.PARAMETER KBArticleID
    Limit to specific KB articles (optional).

.PARAMETER CountdownSeconds
    Length of reboot countdown in seconds. Defaults to 900 (15 minutes).

.NOTES
    Requires:  PSWindowsUpdate module (auto-installed)
    Context:   SYSTEM (Win32 app, Install behavior: System)
               Visible to user via ServiceUI.exe -process:explorer.exe
    Detection: HKLM:\SOFTWARE\AutopilotWindowsUpdate\Status = "Completed"
    Log:       C:\Windows\Logs\AutopilotWindowsUpdate\AutopilotWindowsUpdate.log
    Version:   1.4

    NOTE: Entire script uses ASCII characters to avoid parser errors when
    Windows PowerShell 5.1 reads files without UTF-8 BOM.
#>

[CmdletBinding()]
param(
    [switch]$AutoReboot,
    [switch]$NoReboot,
    [string[]]$KBArticleID,
    [int]$CountdownSeconds = 900
)

# StrictMode is intentionally NOT enabled -- PSWindowsUpdate is not compatible.
$ErrorActionPreference = 'Stop'
$VerbosePreference     = 'Continue'

#region ---- Logging and detection --------------------------------------------

$script:LogPath = 'C:\Windows\Logs\AutopilotWindowsUpdate\AutopilotWindowsUpdate.log'
$script:RegKey  = 'HKLM:\SOFTWARE\AutopilotWindowsUpdate'

function Write-FileLog {
    param([string]$Message, [string]$Level = 'INFO')
    try {
        $dir = Split-Path $script:LogPath -Parent
        if (-not (Test-Path $dir)) { New-Item -Path $dir -ItemType Directory -Force | Out-Null }
        "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [$Level] $Message" |
            Out-File -FilePath $script:LogPath -Append -Encoding utf8
    } catch { }
}

function Set-DetectionKey {
    param([string]$Status, [string]$Detail = '')
    try {
        if (-not (Test-Path $script:RegKey)) {
            New-Item -Path $script:RegKey -Force | Out-Null
        }
        Set-ItemProperty -Path $script:RegKey -Name 'Status'    -Value $Status -Type String -Force
        Set-ItemProperty -Path $script:RegKey -Name 'Timestamp' -Value (Get-Date -Format 'o') -Type String -Force
        if ($Detail) {
            Set-ItemProperty -Path $script:RegKey -Name 'Detail' -Value $Detail -Type String -Force
        }
    } catch {
        Write-FileLog "Could not write detection key: $_" -Level 'WARN'
    }
}

#endregion

#region ---- XAML layout ------------------------------------------------------

[xml]$Xaml = @'
<Window
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    Title="Windows Update - Autopilot Enrollment"
    Height="620" Width="780"
    MinHeight="620" MinWidth="780"
    WindowStartupLocation="CenterScreen"
    ResizeMode="NoResize"
    WindowStyle="SingleBorderWindow"
    Topmost="True"
    ShowInTaskbar="True">

    <Window.Resources>
        <Style x:Key="ActionButton" TargetType="Button">
            <Setter Property="FontFamily" Value="Segoe UI"/>
            <Setter Property="FontSize" Value="12"/>
            <Setter Property="Padding" Value="14,5"/>
            <Setter Property="Margin" Value="4,0"/>
            <Setter Property="MinHeight" Value="28"/>
            <Setter Property="MinWidth" Value="90"/>
            <Setter Property="Cursor" Value="Hand"/>
        </Style>
    </Window.Resources>

    <Grid Background="#F3F3F3">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <!-- Header -->
        <Border Grid.Row="0" Background="#0067B8" Padding="24,16">
            <StackPanel>
                <TextBlock Text="Windows Update"
                           FontFamily="Segoe UI" FontSize="22" FontWeight="SemiBold"
                           Foreground="White"/>
                <TextBlock Text="Updates are being installed. Please do not turn off your computer."
                           FontFamily="Segoe UI" FontSize="12"
                           Foreground="#C8DEFF" Margin="0,5,0,0"/>
            </StackPanel>
        </Border>

        <!-- Status and progress -->
        <StackPanel Grid.Row="1" Margin="24,16,24,8">
            <TextBlock x:Name="StatusText"
                       Text="Initializing..."
                       FontFamily="Segoe UI" FontSize="13" FontWeight="SemiBold"
                       Foreground="#1A1A1A"/>
            <ProgressBar x:Name="ProgressBar"
                         Height="6" Margin="0,10,0,0"
                         IsIndeterminate="True"
                         Foreground="#0067B8" Background="#D6E4F7"
                         BorderThickness="0"/>
            <TextBlock x:Name="CountText"
                       Text=""
                       FontFamily="Segoe UI" FontSize="11"
                       Foreground="#555555" Margin="0,6,0,0"/>
        </StackPanel>

        <!-- Log -->
        <Border Grid.Row="2" Margin="24,0,24,8"
                BorderBrush="#D0D0D0" BorderThickness="1" CornerRadius="3">
            <RichTextBox x:Name="LogBox"
                         Background="#1E1E1E" Foreground="#D4D4D4"
                         FontFamily="Consolas, Courier New"
                         FontSize="11"
                         IsReadOnly="True"
                         BorderThickness="0"
                         Padding="10"
                         VerticalScrollBarVisibility="Auto"
                         HorizontalScrollBarVisibility="Auto">
                <RichTextBox.Resources>
                    <Style TargetType="{x:Type Paragraph}">
                        <Setter Property="Margin" Value="0"/>
                        <Setter Property="LineHeight" Value="16"/>
                    </Style>
                </RichTextBox.Resources>
            </RichTextBox>
        </Border>

        <!-- Footer / Countdown -->
        <Border Grid.Row="3" Background="#E9E9E9"
                BorderBrush="#D0D0D0" BorderThickness="0,1,0,0"
                Padding="24,10" MinHeight="48">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>

                <!-- Default footer text -->
                <TextBlock x:Name="FooterLeft"
                           Grid.Column="0"
                           Text="Please wait - this window will close automatically."
                           FontFamily="Segoe UI" FontSize="11" Foreground="#555555"
                           VerticalAlignment="Center"/>

                <!-- Countdown panel (hidden by default) -->
                <StackPanel x:Name="CountdownPanel"
                            Grid.Column="0"
                            Orientation="Horizontal"
                            VerticalAlignment="Center"
                            Visibility="Collapsed">
                    <TextBlock x:Name="CountdownText"
                               Text="Restarting in 15:00"
                               FontFamily="Segoe UI" FontSize="14" FontWeight="SemiBold"
                               Foreground="#1A1A1A"
                               VerticalAlignment="Center"
                               Margin="0,0,18,0"/>
                    <Button x:Name="PauseBtn"    Content="Pause"       Style="{StaticResource ActionButton}"/>
                    <Button x:Name="RestartBtn"  Content="Restart now" Style="{StaticResource ActionButton}"/>
                    <Button x:Name="ShutdownBtn" Content="Shutdown"    Style="{StaticResource ActionButton}"/>
                </StackPanel>

                <TextBlock x:Name="FooterRight"
                           Grid.Column="1"
                           Text=""
                           FontFamily="Segoe UI" FontSize="11" Foreground="#888888"
                           VerticalAlignment="Center"/>
            </Grid>
        </Border>
    </Grid>
</Window>
'@

#endregion

#region ---- Helpers ----------------------------------------------------------

# Disable close button via P/Invoke (removes SC_CLOSE from system menu)
function Disable-WindowCloseButton {
    param($WindowHandle)
    if (-not ('Win32Window' -as [type])) {
        Add-Type @'
            using System;
            using System.Runtime.InteropServices;
            public class Win32Window {
                [DllImport("user32.dll")] public static extern IntPtr GetSystemMenu(IntPtr hWnd, bool bRevert);
                [DllImport("user32.dll")] public static extern bool RemoveMenu(IntPtr hMenu, uint uPosition, uint uFlags);
                public const uint MF_BYCOMMAND = 0x00000000;
                public const uint SC_CLOSE     = 0xF060;
            }
'@
    }

    $sysMenu = [Win32Window]::GetSystemMenu($WindowHandle, $false)
    [Win32Window]::RemoveMenu($sysMenu, [Win32Window]::SC_CLOSE, [Win32Window]::MF_BYCOMMAND) | Out-Null
}

#endregion

#region ---- WPF window and runspace ------------------------------------------

function Start-UpdateWindow {
    param(
        [switch]$AutoReboot,
        [switch]$NoReboot,
        [string[]]$KBArticleID,
        [int]$CountdownSeconds = 900
    )

    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms

    $reader = [System.Xml.XmlNodeReader]::new($Xaml)
    $window = [Windows.Markup.XamlReader]::Load($reader)

    # Control references
    $ctrlStatus      = $window.FindName('StatusText')
    $ctrlProgress    = $window.FindName('ProgressBar')
    $ctrlCount       = $window.FindName('CountText')
    $ctrlLog         = $window.FindName('LogBox')
    $ctrlFooterLeft  = $window.FindName('FooterLeft')
    $ctrlFooterR     = $window.FindName('FooterRight')
    $ctrlCountdownP  = $window.FindName('CountdownPanel')
    $ctrlCountdownT  = $window.FindName('CountdownText')
    $ctrlPauseBtn    = $window.FindName('PauseBtn')
    $ctrlRestartBtn  = $window.FindName('RestartBtn')
    $ctrlShutdownBtn = $window.FindName('ShutdownBtn')

    # Synchronized state shared between main thread, runspace and UI dispatcher
    $uiState = [hashtable]::Synchronized(@{
        ClosingPermitted = $false
        CountdownSeconds = $CountdownSeconds
        CountdownPaused  = $false
        CountdownTimer   = $null
    })

    # Block close until uiState.ClosingPermitted is true
    $window.Add_Closing({
        param($s, $e)
        if (-not $uiState.ClosingPermitted) { $e.Cancel = $true }
    }.GetNewClosure())

    $window.Add_SourceInitialized({
        $hwnd = (New-Object System.Windows.Interop.WindowInteropHelper($window)).Handle
        Disable-WindowCloseButton -WindowHandle $hwnd
    })

    # Run Windows Update in a separate runspace
    $dispatcher = $window.Dispatcher

    $runspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()
    $runspace.ApartmentState = 'STA'
    $runspace.ThreadOptions  = 'ReuseThread'
    $runspace.Open()

    # Share variables with the runspace
    $runspace.SessionStateProxy.SetVariable('dispatcher',      $dispatcher)
    $runspace.SessionStateProxy.SetVariable('ctrlStatus',      $ctrlStatus)
    $runspace.SessionStateProxy.SetVariable('ctrlProgress',    $ctrlProgress)
    $runspace.SessionStateProxy.SetVariable('ctrlCount',       $ctrlCount)
    $runspace.SessionStateProxy.SetVariable('ctrlLog',         $ctrlLog)
    $runspace.SessionStateProxy.SetVariable('ctrlFooterLeft',  $ctrlFooterLeft)
    $runspace.SessionStateProxy.SetVariable('ctrlFooterR',     $ctrlFooterR)
    $runspace.SessionStateProxy.SetVariable('ctrlCountdownP',  $ctrlCountdownP)
    $runspace.SessionStateProxy.SetVariable('ctrlCountdownT',  $ctrlCountdownT)
    $runspace.SessionStateProxy.SetVariable('ctrlPauseBtn',    $ctrlPauseBtn)
    $runspace.SessionStateProxy.SetVariable('ctrlRestartBtn',  $ctrlRestartBtn)
    $runspace.SessionStateProxy.SetVariable('ctrlShutdownBtn', $ctrlShutdownBtn)
    $runspace.SessionStateProxy.SetVariable('autoReboot',      $AutoReboot.IsPresent)
    $runspace.SessionStateProxy.SetVariable('noReboot',        $NoReboot.IsPresent)
    $runspace.SessionStateProxy.SetVariable('kbFilter',        $KBArticleID)
    $runspace.SessionStateProxy.SetVariable('countdownSeconds',$CountdownSeconds)
    $runspace.SessionStateProxy.SetVariable('window',          $window)
    $runspace.SessionStateProxy.SetVariable('uiState',         $uiState)
    $runspace.SessionStateProxy.SetVariable('LogPath',         $script:LogPath)
    $runspace.SessionStateProxy.SetVariable('RegKey',          $script:RegKey)

    $ps = [System.Management.Automation.PowerShell]::Create()
    $ps.Runspace = $runspace

    [void]$ps.AddScript({

        # ---- File log helper ----------------------------------------------
        function Write-FileLog {
            param([string]$Message, [string]$Level = 'INFO')
            try {
                $dir = Split-Path $LogPath -Parent
                if (-not (Test-Path $dir)) { New-Item -Path $dir -ItemType Directory -Force | Out-Null }
                "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [$Level] $Message" |
                    Out-File -FilePath $LogPath -Append -Encoding utf8
            } catch { }
        }

        function Set-DetectionKey {
            param([string]$Status, [string]$Detail = '')
            try {
                if (-not (Test-Path $RegKey)) { New-Item -Path $RegKey -Force | Out-Null }
                Set-ItemProperty -Path $RegKey -Name 'Status'    -Value $Status -Type String -Force
                Set-ItemProperty -Path $RegKey -Name 'Timestamp' -Value (Get-Date -Format 'o') -Type String -Force
                if ($Detail) { Set-ItemProperty -Path $RegKey -Name 'Detail' -Value $Detail -Type String -Force }
            } catch {
                Write-FileLog "Could not write detection key: $_" -Level 'WARN'
            }
        }

        # ---- UI helpers (use GetNewClosure to capture variables across threads)
        function Set-Status {
            param([string]$Text)
            try {
                $sb = { $ctrlStatus.Text = $Text }.GetNewClosure()
                $dispatcher.Invoke($sb)
            } catch { Write-FileLog "Set-Status failed: $_" -Level 'WARN' }
        }

        function Set-Count {
            param([string]$Text)
            try {
                $sb = { $ctrlCount.Text = $Text }.GetNewClosure()
                $dispatcher.Invoke($sb)
            } catch { Write-FileLog "Set-Count failed: $_" -Level 'WARN' }
        }

        function Set-Footer {
            param([string]$Text)
            try {
                $sb = { $ctrlFooterR.Text = $Text }.GetNewClosure()
                $dispatcher.Invoke($sb)
            } catch { Write-FileLog "Set-Footer failed: $_" -Level 'WARN' }
        }

        function Set-ProgressDeterminate {
            param([double]$Value, [double]$Max)
            try {
                $sb = {
                    $ctrlProgress.IsIndeterminate = $false
                    $ctrlProgress.Maximum = $Max
                    $ctrlProgress.Value = $Value
                }.GetNewClosure()
                $dispatcher.Invoke($sb)
            } catch { Write-FileLog "Set-ProgressDeterminate failed: $_" -Level 'WARN' }
        }

        function Set-ProgressIndeterminate {
            try {
                $sb = { $ctrlProgress.IsIndeterminate = $true }.GetNewClosure()
                $dispatcher.Invoke($sb)
            } catch { Write-FileLog "Set-ProgressIndeterminate failed: $_" -Level 'WARN' }
        }

        function Write-Log {
            param([string]$Message, [string]$Color = '#D4D4D4')

            Write-FileLog -Message $Message

            try {
                $stamp = "[$(Get-Date -Format 'HH:mm:ss')] $Message"
                $sb = {
                    $doc  = $ctrlLog.Document
                    $para = New-Object System.Windows.Documents.Paragraph
                    $run  = New-Object System.Windows.Documents.Run $stamp
                    $run.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString($Color)
                    $para.Inlines.Add($run)
                    $doc.Blocks.Add($para)
                    $ctrlLog.ScrollToEnd()
                }.GetNewClosure()
                $dispatcher.Invoke($sb)
            } catch {
                Write-FileLog "Write-Log UI failed: $_" -Level 'WARN'
            }
        }

        function Close-WindowSafely {
            try {
                $sb = {
                    $uiState.ClosingPermitted = $true
                    $window.Close()
                }.GetNewClosure()
                $dispatcher.Invoke($sb)
            } catch { Write-FileLog "Close-Window failed: $_" -Level 'WARN' }
        }

        function Start-RebootCountdown {
            param([int]$Seconds = 900)

            Write-FileLog "Starting reboot countdown ($Seconds seconds)."

            $sb = {
                # Switch UI to countdown mode
                $ctrlFooterLeft.Visibility = [System.Windows.Visibility]::Collapsed
                $ctrlCountdownP.Visibility = [System.Windows.Visibility]::Visible

                $uiState.CountdownSeconds = $Seconds
                $uiState.CountdownPaused  = $false

                $m = [math]::Floor($Seconds / 60)
                $s = $Seconds % 60
                $ctrlCountdownT.Text = ("Restarting in {0:D2}:{1:D2}" -f $m, $s)

                # Timer
                $timer = New-Object System.Windows.Threading.DispatcherTimer
                $timer.Interval = [TimeSpan]::FromSeconds(1)
                $uiState.CountdownTimer = $timer

                $timer.Add_Tick({
                    if (-not $uiState.CountdownPaused) {
                        $uiState.CountdownSeconds = $uiState.CountdownSeconds - 1
                        $sec = $uiState.CountdownSeconds

                        if ($sec -le 0) {
                            $timer.Stop()
                            $ctrlCountdownT.Text = "Restarting now..."
                            $uiState.ClosingPermitted = $true
                            try { Restart-Computer -Force } catch { }
                            return
                        }

                        $mm = [math]::Floor($sec / 60)
                        $ss = $sec % 60
                        $ctrlCountdownT.Text = ("Restarting in {0:D2}:{1:D2}" -f $mm, $ss)
                    }
                }.GetNewClosure())

                $timer.Start()

                # Pause / Resume
                $ctrlPauseBtn.Add_Click({
                    $uiState.CountdownPaused = -not $uiState.CountdownPaused
                    if ($uiState.CountdownPaused) {
                        $ctrlPauseBtn.Content = "Resume"
                        $ctrlCountdownT.Foreground = [System.Windows.Media.Brushes]::DarkOrange
                    } else {
                        $ctrlPauseBtn.Content = "Pause"
                        $ctrlCountdownT.Foreground = [System.Windows.Media.Brushes]::Black
                    }
                }.GetNewClosure())

                # Restart now
                $ctrlRestartBtn.Add_Click({
                    if ($uiState.CountdownTimer) { $uiState.CountdownTimer.Stop() }
                    $ctrlCountdownT.Text = "Restarting now..."
                    $ctrlPauseBtn.IsEnabled    = $false
                    $ctrlRestartBtn.IsEnabled  = $false
                    $ctrlShutdownBtn.IsEnabled = $false
                    $uiState.ClosingPermitted = $true
                    try { Restart-Computer -Force } catch { }
                }.GetNewClosure())

                # Shutdown
                $ctrlShutdownBtn.Add_Click({
                    if ($uiState.CountdownTimer) { $uiState.CountdownTimer.Stop() }
                    $ctrlCountdownT.Text = "Shutting down..."
                    $ctrlPauseBtn.IsEnabled    = $false
                    $ctrlRestartBtn.IsEnabled  = $false
                    $ctrlShutdownBtn.IsEnabled = $false
                    $uiState.ClosingPermitted = $true
                    try { Stop-Computer -Force } catch { }
                }.GetNewClosure())
            }.GetNewClosure()

            $dispatcher.Invoke($sb)
        }

        # ---- 0. Start log ------------------------------------------------
        Write-FileLog "==============================================="
        Write-FileLog "AutopilotWindowsUpdate started (user: $env:USERNAME, machine: $env:COMPUTERNAME)"
        Write-FileLog "Parameters: AutoReboot=$autoReboot  NoReboot=$noReboot  KB=$($kbFilter -join ',')  Countdown=${countdownSeconds}s"

        Set-Status "Initializing..."
        Write-Log "Script started." '#9CDCFE'

        # ---- 1. Install module -------------------------------------------
        try {
            Set-Status "Preparing PSWindowsUpdate module..."
            Write-Log "Checking NuGet package provider..." '#9CDCFE'

            $nuget = Get-PackageProvider -Name NuGet -ListAvailable -ErrorAction SilentlyContinue |
                Where-Object { $_.Version -ge '2.8.5.201' }

            if (-not $nuget) {
                Write-Log "Installing NuGet 2.8.5.201+..." '#DCDCAA'
                Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope AllUsers | Out-Null
                Write-Log "NuGet installed." '#4EC9B0'
            } else {
                Write-Log "NuGet OK (v$($nuget.Version))." '#4EC9B0'
            }

            try {
                $gallery = Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue
                if ($gallery -and $gallery.InstallationPolicy -ne 'Trusted') {
                    Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
                    Write-Log "PSGallery set to Trusted." '#4EC9B0'
                }
            } catch { }

            $pswu = Get-Module -ListAvailable -Name PSWindowsUpdate |
                Where-Object { $_.Version -ge '2.0.0' } |
                Sort-Object Version -Descending | Select-Object -First 1

            if (-not $pswu) {
                Write-Log "Installing PSWindowsUpdate from PSGallery..." '#DCDCAA'
                Install-Module -Name PSWindowsUpdate -Force -Scope AllUsers -AllowClobber
                Write-Log "PSWindowsUpdate installed." '#4EC9B0'
            } else {
                Write-Log "PSWindowsUpdate OK (v$($pswu.Version))." '#4EC9B0'
            }

            Import-Module PSWindowsUpdate -Force -Verbose:$false
            $loadedVer = (Get-Module PSWindowsUpdate).Version
            Write-Log "Module loaded: PSWindowsUpdate $loadedVer" '#4EC9B0'
        }
        catch {
            Write-Log "ERROR during module install: $_" '#F44747'
            Write-FileLog "ERROR during module install: $_" -Level 'ERROR'
            Set-DetectionKey -Status 'Failed' -Detail "ModuleInstall: $_"
            Set-Status "Error - see log"
            Start-Sleep -Seconds 10
            Close-WindowSafely
            return
        }

        # ---- 2. Search for updates ---------------------------------------
        $updates = @()
        try {
            Set-Status "Searching for available updates..."
            Set-ProgressIndeterminate
            Write-Log "" '#D4D4D4'
            Write-Log "================================================" '#555555'
            Write-Log "  Searching for Windows updates..." '#9CDCFE'
            Write-Log "================================================" '#555555'

            $getParams = @{
                MicrosoftUpdate = $true
                ErrorAction     = 'Stop'
            }
            if ($kbFilter) { $getParams['KBArticleID'] = $kbFilter }

            $updates = @(Get-WindowsUpdate @getParams)

            if ($updates.Count -eq 0) {
                Write-Log "" '#D4D4D4'
                Write-Log "  No updates available - machine is up to date." '#4EC9B0'
                Write-FileLog "No updates found - machine is already up to date."
                Set-DetectionKey -Status 'Completed' -Detail 'NoUpdatesNeeded'
                Set-Status "No updates found."
                Set-Count  ""
                Set-ProgressDeterminate -Value 1 -Max 1
                Set-Footer "Completed $(Get-Date -Format 'HH:mm')"

                Start-Sleep -Seconds 3
                Close-WindowSafely
                return
            }

            Write-Log "" '#D4D4D4'
            Write-Log "  Found $($updates.Count) update(s):" '#9CDCFE'
            Write-Log "" '#D4D4D4'

            $i = 0
            foreach ($u in $updates) {
                $i++
                $kb    = if ($u.KB)    { "KB$($u.KB)" } else { "-" }
                $title = if ($u.Title) { $u.Title }     else { "Unknown" }
                $size  = if ($u.Size)  { " ($($u.Size))" } else { "" }
                Write-Log ("  {0,3}. [{1}] {2}{3}" -f $i, $kb, $title, $size) '#D4D4D4'
            }

            Set-Count "Found $($updates.Count) update(s)"
        }
        catch {
            Write-Log "ERROR during search: $_" '#F44747'
            Write-FileLog "ERROR during search: $_" -Level 'ERROR'
            Set-DetectionKey -Status 'Failed' -Detail "Search: $_"
            Set-Status "Search error - see log"
            Start-Sleep -Seconds 10
            Close-WindowSafely
            return
        }

        # ---- 3. Download and install -------------------------------------
        try {
            Write-Log "" '#D4D4D4'
            Write-Log "================================================" '#555555'
            Write-Log "  Starting download and installation..." '#9CDCFE'
            Write-Log "================================================" '#555555'
            Write-Log "" '#D4D4D4'

            Set-Status "Installing updates (0 / $($updates.Count))..."
            Set-ProgressDeterminate -Value 0 -Max $updates.Count

            $installParams = @{
                MicrosoftUpdate = $true
                AcceptAll       = $true
                Verbose         = $true
                ErrorAction     = 'Continue'
            }

            if ($autoReboot) { $installParams['AutoReboot']   = $true }
            if ($noReboot)   { $installParams['IgnoreReboot'] = $true }
            if ($kbFilter)   { $installParams['KBArticleID']  = $kbFilter }

            $current      = 0
            $rebootNeeded = $false
            $failedCount  = 0

            Install-WindowsUpdate @installParams 4>&1 3>&1 2>&1 | ForEach-Object {
                $line = $_

                if ($line -is [System.Management.Automation.VerboseRecord]) {
                    Write-Log "  [v] $($line.Message)" '#808080'
                }
                elseif ($line -is [System.Management.Automation.WarningRecord]) {
                    Write-Log "  [!] $($line.Message)" '#CE9178'
                    if ($line.Message -match 'reboot') { $rebootNeeded = $true }
                }
                elseif ($line -is [System.Management.Automation.ErrorRecord]) {
                    Write-Log "  [X] ERROR: $($line.Exception.Message)" '#F44747'
                    Write-FileLog "ERROR: $($line.Exception.Message)" -Level 'ERROR'
                }
                elseif ($line -ne $null -and $line.PSObject -ne $null) {
                    $hasTitle  = $line.PSObject.Properties.Match('Title').Count  -gt 0
                    $hasResult = $line.PSObject.Properties.Match('Result').Count -gt 0
                    $hasStatus = $line.PSObject.Properties.Match('Status').Count -gt 0

                    if ($hasTitle -and ($hasResult -or $hasStatus)) {
                        $current++
                        $kb     = if ($line.KB)    { "KB$($line.KB)" } else { "" }
                        $uTitle = if ($line.Title) { $line.Title }     else { "Unknown" }
                        $result = if ($hasResult)  { "$($line.Result)" }
                                  elseif ($hasStatus) { "$($line.Status)" }
                                  else { "?" }

                        $color = '#DCDCAA'
                        if ($result -match 'Installed|Succeeded|OK') { $color = '#4EC9B0' }
                        elseif ($result -match 'Failed|Error') {
                            $color = '#F44747'
                            $failedCount++
                        }
                        elseif ($result -match 'Reboot') {
                            $color = '#CE9178'
                            $rebootNeeded = $true
                        }

                        Set-ProgressDeterminate -Value $current -Max $updates.Count
                        Set-Status "Installing ($current / $($updates.Count)): $kb"
                        Set-Count  "$current of $($updates.Count) processed"
                        Write-Log ("  [{0,-12}] {1} {2}" -f $result, $kb, $uTitle) $color
                        Write-FileLog "Processed: [$result] $kb $uTitle"
                    }
                    else {
                        Write-Log "    $line" '#808080'
                    }
                }
            }

            Write-Log "" '#D4D4D4'
            Write-Log "================================================" '#555555'

            try {
                if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') {
                    $rebootNeeded = $true
                }
                if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') {
                    $rebootNeeded = $true
                }
            } catch { }

            $detail = "$($updates.Count)Updates"
            if ($failedCount -gt 0) { $detail += "/${failedCount}Failed" }
            if ($rebootNeeded)      { $detail += "/RebootRequired" }

            if ($rebootNeeded -and -not $noReboot) {
                Write-Log "  Updates complete - reboot required." '#CE9178'
                Write-FileLog "Installation complete - reboot required. ($detail)"
                Set-DetectionKey -Status 'Completed' -Detail $detail
                Set-Status "Updates complete - reboot required"
                Set-Count  "All updates processed"
                Set-Footer "Completed $(Get-Date -Format 'HH:mm')"
                Set-ProgressDeterminate -Value $updates.Count -Max $updates.Count

                if ($autoReboot) {
                    Write-Log "  Rebooting in 30 seconds (AutoReboot)..." '#CE9178'
                    Set-Status "Rebooting in 30 seconds..."
                    Start-Sleep -Seconds 30
                    $uiState.ClosingPermitted = $true
                    Restart-Computer -Force
                } else {
                    $mins = [math]::Floor($countdownSeconds / 60)
                    Write-Log "  Showing $mins-minute reboot countdown." '#CE9178'
                    Start-RebootCountdown -Seconds $countdownSeconds
                    # Runspace returns; countdown runs on UI thread
                }
            } else {
                Write-Log "  All updates processed." '#4EC9B0'
                Write-FileLog "Installation complete. $detail"
                Set-DetectionKey -Status 'Completed' -Detail $detail
                Set-Status "Updates complete."
                Set-Count  "$($updates.Count) update(s) processed"
                Set-ProgressDeterminate -Value $updates.Count -Max $updates.Count
                Set-Footer "Completed $(Get-Date -Format 'HH:mm')"

                Start-Sleep -Seconds 5
                Close-WindowSafely
            }
        }
        catch {
            Write-Log "" '#D4D4D4'
            Write-Log "UNEXPECTED ERROR during install: $_" '#F44747'
            Write-FileLog "ERROR during install: $_" -Level 'ERROR'
            Set-DetectionKey -Status 'Failed' -Detail "Install: $_"
            Set-Status "Error - see log"
            Set-Footer "Error $(Get-Date -Format 'HH:mm')"
            Start-Sleep -Seconds 15
            Close-WindowSafely
        }
    })

    # Start runspace job asynchronously
    $asyncResult = $ps.BeginInvoke()

    # Show the window (blocks until closed)
    [void]$window.ShowDialog()

    # Cleanup
    if (-not $asyncResult.IsCompleted) {
        $ps.Stop()
    }
    $ps.Dispose()
    $runspace.Close()
    $runspace.Dispose()
}

#endregion

#region ---- Entry point ------------------------------------------------------

if ($MyInvocation.InvocationName -ne '.') {
    Write-FileLog "Script invoked: $($MyInvocation.MyCommand.Path)"
    try {
        Start-UpdateWindow `
            -AutoReboot:$AutoReboot `
            -NoReboot:$NoReboot `
            -KBArticleID $KBArticleID `
            -CountdownSeconds $CountdownSeconds
        Write-FileLog "Script exited normally (exit 0)."
        exit 0
    }
    catch {
        Write-FileLog "Critical error at top level: $_" -Level 'ERROR'
        Set-DetectionKey -Status 'Failed' -Detail "TopLevel: $_"
        Write-Error "Critical error: $_"
        exit 1
    }
}

#endregion
