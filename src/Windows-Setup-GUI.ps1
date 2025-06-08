#Requires -RunAsAdministrator

# Windows Setup Automation GUI
# A GUI-based tool to automate Windows 10/11 setup, install applications, remove bloatware,
# optimize settings, and manage services.

#region Variables

# Set up paths
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$modulePath = Join-Path $scriptPath "modules"
$utilsPath = Join-Path $scriptPath "utils"

# Import required modules
Import-Module (Join-Path $utilsPath "Logging.psm1") -Force
Import-Module (Join-Path $modulePath "Installers.psm1") -Force
Import-Module (Join-Path $modulePath "SystemOptimizations.psm1") -Force

# Global variables
$script:LogPath = Join-Path -Path $PSScriptRoot -ChildPath "setup-log-$(Get-Date -Format 'yyyyMMdd-HHmmss').txt"
$script:EnableFileLogging = $true
$script:IsRunning = $false
$script:TotalSteps = 0
$script:CurrentStep = 0
$script:StartTime = $null
$script:SelectedApps = @{}
$script:SelectedBloatware = @{}
$script:SelectedServices = @{}
$script:SelectedOptimizations = @{}
$script:BackgroundJobs = @()
$script:BackgroundWorker = $null
$script:PowerShell = $null
$script:Runspace = $null
$script:AsyncResult = $null
$script:ProgressTimer = $null
$script:CancellationTokenSource = $null
$script:WingetInstallAttempted = $false
$script:UseDirectDownloadOnly = $false
$script:TempDirectory = Join-Path $env:TEMP "WindowsSetupGUI"
$script:UISyncContext = [System.Threading.SynchronizationContext]::Current

# Initialize UI elements to avoid null reference issues
$script:txtLog = $null
$script:prgProgress = $null
$script:lblProgress = $null
$script:btnRun = $null
$script:btnCancel = $null
$script:tabInstall = $null
$script:tabRemove = $null
$script:tabServices = $null
$script:tabOptimize = $null
$script:tabSettings = $null

# Detect Windows version
$script:OSInfo = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
if ($script:OSInfo) {
    $script:OSVersion = [Version]$script:OSInfo.Version
    $script:OSName = $script:OSInfo.Caption
    $script:IsWindows11 = $script:OSVersion.Major -eq 10 -and $script:OSVersion.Build -ge 22000
} else {
    # Default values if detection fails
    $script:OSVersion = [Version]"10.0"
    $script:OSName = "Windows 10/11"
    $script:IsWindows11 = $false
    Write-Host "Warning: Could not detect Windows version, using defaults" -ForegroundColor Yellow
}

# App categories and definitions
$script:AppCategories = @{
    "Development" = @(
        @{Key="vscode"; Name="Visual Studio Code"; Default=$true; Win10=$true; Win11=$true}
        @{Key="git"; Name="Git"; Default=$true; Win10=$true; Win11=$true}
        @{Key="python"; Name="Python"; Default=$true; Win10=$true; Win11=$true}
        @{Key="pycharm"; Name="PyCharm Community"; Default=$true; Win10=$true; Win11=$true}
        @{Key="github"; Name="GitHub Desktop"; Default=$true; Win10=$true; Win11=$true}
        @{Key="postman"; Name="Postman"; Default=$true; Win10=$true; Win11=$true}
        @{Key="nodejs"; Name="Node.js"; Default=$false; Win10=$true; Win11=$true}
        @{Key="terminal"; Name="Windows Terminal"; Default=$true; Win10=$false; Win11=$true}
    )
    "Browsers" = @(
        @{Key="chrome"; Name="Google Chrome"; Default=$true; Win10=$true; Win11=$true}
        @{Key="firefox"; Name="Mozilla Firefox"; Default=$false; Win10=$true; Win11=$true}
        @{Key="brave"; Name="Brave Browser"; Default=$false; Win10=$true; Win11=$true}
    )
    "Media & Communication" = @(
        @{Key="spotify"; Name="Spotify"; Default=$true; Win10=$true; Win11=$true}
        @{Key="discord"; Name="Discord"; Default=$true; Win10=$true; Win11=$true}
        @{Key="steam"; Name="Steam"; Default=$true; Win10=$true; Win11=$true}
        @{Key="vlc"; Name="VLC Media Player"; Default=$false; Win10=$true; Win11=$true}
    )
    "Utilities" = @(
        @{Key="7zip"; Name="7-Zip"; Default=$false; Win10=$true; Win11=$true}
        @{Key="notepadplusplus"; Name="Notepad++"; Default=$false; Win10=$true; Win11=$true}
        @{Key="powertoys"; Name="Microsoft PowerToys"; Default=$true; Win10=$false; Win11=$true}
    )
}

# Bloatware categories and definitions
$script:BloatwareCategories = @{
    "Microsoft Apps" = @(
        @{Key="ms-officehub"; Name="Microsoft Office Hub"; Default=$true; Win10=$true; Win11=$true}
        @{Key="ms-teams"; Name="Microsoft Teams (consumer)"; Default=$true; Win10=$false; Win11=$true}
        @{Key="ms-todo"; Name="Microsoft To Do"; Default=$true; Win10=$false; Win11=$true}
        @{Key="ms-3dviewer"; Name="Microsoft 3D Viewer"; Default=$true; Win10=$true; Win11=$true}
        @{Key="ms-mixedreality"; Name="Mixed Reality Portal"; Default=$true; Win10=$true; Win11=$true}
        @{Key="ms-onenote"; Name="OneNote (Store version)"; Default=$true; Win10=$true; Win11=$true}
        @{Key="ms-people"; Name="Microsoft People"; Default=$true; Win10=$true; Win11=$true}
        @{Key="ms-wallet"; Name="Microsoft Wallet"; Default=$true; Win10=$true; Win11=$true}
        @{Key="ms-messaging"; Name="Microsoft Messaging"; Default=$true; Win10=$true; Win11=$true}
        @{Key="ms-oneconnect"; Name="Microsoft OneConnect"; Default=$true; Win10=$true; Win11=$true}
    )
    "Bing Apps" = @(
        @{Key="bing-weather"; Name="Bing Weather"; Default=$true; Win10=$true; Win11=$true}
        @{Key="bing-news"; Name="Bing News"; Default=$true; Win10=$true; Win11=$true}
        @{Key="bing-finance"; Name="Bing Finance"; Default=$true; Win10=$true; Win11=$true}
    )
    "Windows Utilities" = @(
        @{Key="win-alarms"; Name="Windows Alarms & Clock"; Default=$true; Win10=$true; Win11=$true}
        @{Key="win-camera"; Name="Windows Camera"; Default=$true; Win10=$true; Win11=$true}
        @{Key="win-mail"; Name="Windows Mail & Calendar"; Default=$true; Win10=$true; Win11=$true}
        @{Key="win-maps"; Name="Windows Maps"; Default=$true; Win10=$true; Win11=$true}
        @{Key="win-feedback"; Name="Windows Feedback Hub"; Default=$true; Win10=$true; Win11=$true}
        @{Key="win-gethelp"; Name="Windows Get Help"; Default=$true; Win10=$true; Win11=$true}
        @{Key="win-getstarted"; Name="Windows Get Started"; Default=$true; Win10=$true; Win11=$true}
        @{Key="win-soundrec"; Name="Windows Sound Recorder"; Default=$true; Win10=$true; Win11=$true}
        @{Key="win-yourphone"; Name="Windows Your Phone"; Default=$true; Win10=$true; Win11=$true}
        @{Key="win-print3d"; Name="Print 3D"; Default=$true; Win10=$true; Win11=$true}
    )
    "Media Apps" = @(
        @{Key="zune-music"; Name="Groove Music"; Default=$true; Win10=$true; Win11=$true}
        @{Key="zune-video"; Name="Movies & TV"; Default=$true; Win10=$true; Win11=$true}
        @{Key="solitaire"; Name="Microsoft Solitaire Collection"; Default=$true; Win10=$true; Win11=$true}
        @{Key="xbox-apps"; Name="Xbox Apps"; Default=$true; Win10=$true; Win11=$true}
    )
    "Third-Party Bloatware" = @(
        @{Key="candy-crush"; Name="Candy Crush Games"; Default=$true; Win10=$true; Win11=$true}
        @{Key="spotify-store"; Name="Spotify (Store version)"; Default=$true; Win10=$true; Win11=$true}
        @{Key="facebook"; Name="Facebook"; Default=$true; Win10=$true; Win11=$true}
        @{Key="twitter"; Name="Twitter"; Default=$true; Win10=$true; Win11=$true}
        @{Key="netflix"; Name="Netflix"; Default=$true; Win10=$true; Win11=$true}
        @{Key="disney"; Name="Disney+"; Default=$true; Win10=$true; Win11=$true}
        @{Key="tiktok"; Name="TikTok"; Default=$true; Win10=$true; Win11=$true}
    )
    "Windows 11 Specific" = @(
        @{Key="ms-widgets"; Name="Microsoft Widgets"; Default=$true; Win10=$false; Win11=$true}
        @{Key="ms-clipchamp"; Name="Microsoft ClipChamp"; Default=$true; Win10=$false; Win11=$true}
        @{Key="gaming-app"; Name="Gaming App"; Default=$true; Win10=$false; Win11=$true}
        @{Key="linkedin"; Name="LinkedIn"; Default=$true; Win10=$false; Win11=$true}
    )
}

# Service categories and definitions
$script:ServiceCategories = @{
    "Telemetry & Data Collection" = @(
        @{Key="diagtrack"; Name="Connected User Experiences and Telemetry (DiagTrack)"; Default=$true; Win10=$true; Win11=$true}
        @{Key="dmwappushsvc"; Name="WAP Push Message Routing Service"; Default=$true; Win10=$true; Win11=$true}
    )
    "System Performance" = @(
        @{Key="sysmain"; Name="Superfetch/SysMain"; Default=$true; Win10=$true; Win11=$true}
        @{Key="wmpnetworksvc"; Name="Windows Media Player Network Sharing"; Default=$true; Win10=$true; Win11=$true}
    )
    "Security & Remote Access" = @(
        @{Key="remoteregistry"; Name="Remote Registry"; Default=$true; Win10=$true; Win11=$true}
        @{Key="remoteaccess"; Name="Routing and Remote Access"; Default=$true; Win10=$true; Win11=$true}
    )
    "Misc Services" = @(
        @{Key="printnotify"; Name="Printer Extensions and Notifications"; Default=$true; Win10=$true; Win11=$true}
        @{Key="fax"; Name="Fax Service"; Default=$true; Win10=$true; Win11=$true}
        @{Key="wisvc"; Name="Windows Insider Service"; Default=$true; Win10=$true; Win11=$true}
        @{Key="retaildemo"; Name="Retail Demo Service"; Default=$true; Win10=$true; Win11=$true}
        @{Key="mapsbroker"; Name="Downloaded Maps Manager"; Default=$true; Win10=$true; Win11=$true}
        @{Key="pcasvc"; Name="Program Compatibility Assistant"; Default=$true; Win10=$true; Win11=$true}
        @{Key="wpcmonsvc"; Name="Parental Controls"; Default=$true; Win10=$true; Win11=$true}
        @{Key="cscservice"; Name="Offline Files"; Default=$true; Win10=$true; Win11=$true}
    )
    "Windows 11 Specific Services" = @(
        @{Key="lfsvc"; Name="Geolocation Service"; Default=$true; Win10=$false; Win11=$true}
        @{Key="tabletinputservice"; Name="Touch Keyboard and Handwriting"; Default=$true; Win10=$false; Win11=$true}
        @{Key="homegrpservice"; Name="HomeGroup Provider"; Default=$true; Win10=$false; Win11=$true}
        @{Key="walletservice"; Name="Wallet Service"; Default=$true; Win10=$false; Win11=$true}
    )
}

# Optimization categories and definitions
$script:OptimizationCategories = @{
    "File Explorer" = @(
        @{Key="show-extensions"; Name="Show file extensions"; Default=$true; Win10=$true; Win11=$true}
        @{Key="show-hidden"; Name="Show hidden files"; Default=$true; Win10=$true; Win11=$true}
    )
    "Development Features" = @(
        @{Key="dev-mode"; Name="Enable Developer Mode"; Default=$true; Win10=$true; Win11=$true}
    )
    "Privacy & Telemetry" = @(
        @{Key="disable-cortana"; Name="Disable Cortana"; Default=$true; Win10=$true; Win11=$true}
        @{Key="disable-onedrive"; Name="Disable OneDrive startup"; Default=$true; Win10=$true; Win11=$true}
        @{Key="disable-tips"; Name="Disable Windows tips and suggestions"; Default=$true; Win10=$true; Win11=$true}
        @{Key="reduce-telemetry"; Name="Reduce telemetry data collection"; Default=$true; Win10=$true; Win11=$true}
        @{Key="disable-activity"; Name="Disable activity history"; Default=$true; Win10=$true; Win11=$true}
        @{Key="disable-background"; Name="Disable unnecessary background apps"; Default=$true; Win10=$true; Win11=$true}
    )
    "Search & Interface" = @(
        @{Key="search-bing"; Name="Configure search to prioritize local results over Bing"; Default=$true; Win10=$true; Win11=$true}
    )
    "Windows 11 Specific" = @(
        @{Key="taskbar-left" ; Name="Set taskbar alignment to left (classic style)"; Default=$true; Win10=$false; Win11=$true}
        @{Key="classic-context"; Name="Restore classic right-click context menu"; Default=$true; Win10=$false; Win11=$true}
        @{Key="disable-chat"; Name="Disable Chat icon on taskbar"; Default=$true; Win10=$false; Win11=$true}
        @{Key="disable-widgets"; Name="Disable Widgets icon and service"; Default=$true; Win10=$false; Win11=$true}
        @{Key="disable-snap"; Name="Disable Snap layouts when hovering maximize button"; Default=$true; Win10=$false; Win11=$true}
        @{Key="start-menu-pins"; Name="Configure Start Menu layout for more pins"; Default=$true; Win10=$false; Win11=$true}
        @{Key="disable-teams-autostart"; Name="Disable Teams consumer auto-start"; Default=$true; Win10=$false; Win11=$true}
        @{Key="disable-startup-sound"; Name="Disable startup sound"; Default=$true; Win10=$false; Win11=$true}
    )
}

# Winget ID mappings for apps
$script:WingetMappings = @{
    "vscode" = "Microsoft.VisualStudioCode"
    "git" = "Git.Git"
    "python" = "Python.Python.3"
    "pycharm" = "JetBrains.PyCharm.Community"
    "github" = "GitHub.GitHubDesktop"
    "postman" = "Postman.Postman"
    "nodejs" = "OpenJS.NodeJS.LTS"
    "terminal" = "Microsoft.WindowsTerminal"
    "chrome" = "Google.Chrome"
    "firefox" = "Mozilla.Firefox"
    "brave" = "Brave.Browser"
    "spotify" = "Spotify.Spotify"
    "discord" = "Discord.Discord"
    "steam" = "Valve.Steam"
    "vlc" = "VideoLAN.VLC"
    "7zip" = "7zip.7zip"
    "notepadplusplus" = "Notepad++.Notepad++"
    "powertoys" = "Microsoft.PowerToys"
}

#endregion Variables

#region Module Imports

# Import required modules
$modulePath = Join-Path $PSScriptRoot "modules"
$utilsPath = Join-Path $PSScriptRoot "utils"
$configPath = Join-Path $PSScriptRoot "config"

# Import logging module
Import-Module (Join-Path $utilsPath "Logging.psm1") -Force

# Import installer and optimization modules
Import-Module (Join-Path $modulePath "Installers.psm1") -Force
Import-Module (Join-Path $modulePath "SystemOptimizations.psm1") -Force

# Import configuration
. (Join-Path $configPath "AppConfig.ps1")
. (Join-Path $configPath "DownloadConfig.ps1")

#endregion Module Imports

#region Helper Functions

function Initialize-Logging {
    # Create log directory if it doesn't exist
    $logDir = Split-Path -Parent $script:LogPath
    if (-not (Test-Path $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }
    
    # Create initial log entry
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $header = "=== Windows Setup Automation Log ==="
    $header += "`nStarted at: $timestamp"
    $header += "`nWindows Version: $($script:OSName)"
    $header += "`n================================`n"
    
    Add-Content -Path $script:LogPath -Value $header
    Write-Log "Logging initialized" -Level "INFO"
}

function Write-Log {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [ValidateSet("INFO", "WARNING", "ERROR", "SUCCESS", "DEBUG")]
        [string]$Level = "INFO"
    )

    # Format timestamp
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $formattedMessage = "[$timestamp] [$Level] $Message"

    # Update the log textbox in the GUI if available
    if ($script:txtLog -ne $null) {
        try {
            $color = switch ($Level) {
                "WARNING" { "Orange" }
                "ERROR" { "Red" }
                "SUCCESS" { "Green" }
                "DEBUG" { "Gray" }
                default { "Black" }
            }
            
            $script:txtLog.SelectionColor = $color
            $script:txtLog.AppendText("$formattedMessage`r`n")
            $script:txtLog.SelectionStart = $script:txtLog.Text.Length
            $script:txtLog.ScrollToCaret()
        }
        catch {
            Write-Host "Error updating log textbox: $_" -ForegroundColor Red
        }
    }

    # Write to log file if enabled
    if ($script:EnableFileLogging) {
        try {
            Add-Content -Path $script:LogPath -Value $formattedMessage -ErrorAction Stop
        }
        catch {
            Write-Host "Failed to write to log file: $_" -ForegroundColor Red
        }
    }

    # Also write to host
    switch ($Level) {
        "WARNING" { Write-Host $formattedMessage -ForegroundColor Yellow }
        "ERROR" { Write-Host $formattedMessage -ForegroundColor Red }
        "SUCCESS" { Write-Host $formattedMessage -ForegroundColor Green }
        "DEBUG" { Write-Host $formattedMessage -ForegroundColor Gray }
        default { Write-Host $formattedMessage }
    }
}

function Cleanup-TempFiles {
    try {
        $tempFolder = Join-Path $env:TEMP "WingetInstall"
        if (Test-Path $tempFolder) {
            Remove-Item -Path $tempFolder -Recurse -Force -ErrorAction Stop
            Write-Log "Cleaned up temporary files" -Level "INFO"
        }
    }
    catch {
        Write-Log "Failed to clean up temporary files: $_" -Level "WARNING"
    }
}

function Update-Progress {
    param (
        [string]$Status,
        [switch]$IncrementStep
    )

    if ($IncrementStep) {
        $script:CurrentStep++
    }

    $percentage = [Math]::Round(($script:CurrentStep / [Math]::Max($script:TotalSteps, 1)) * 100)
    
    if ($script:prgProgress -ne $null) {
        $script:prgProgress.Value = $percentage
    }
    
    if ($script:lblProgress -ne $null) {
        $script:lblProgress.Text = if ($Status) { $Status } else { "Progress: $percentage%" }
    }
}

function Update-UI {
    param (
        [Parameter(Mandatory=$true)]
        [ScriptBlock]$Code
    )
    
    if ($null -eq $script:txtLog) {
        # If UI hasn't been initialized yet, just run the code directly
        & $Code
        return
    }
    
    if ($script:txtLog.InvokeRequired) {
        try {
            $script:txtLog.Invoke($Code)
        } catch {
            Write-Host "Error updating UI: $_" -ForegroundColor Red
        }
    } else {
        & $Code
    }
}

function Update-ProgressBar {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [string]$Status,

        [Parameter(Mandatory = $false)]
        [switch]$IncrementStep
    )

    if ($IncrementStep) {
        $script:CurrentStep++
    }

    $percentage = if ($script:TotalSteps -gt 0) { 
        [Math]::Round(($script:CurrentStep / $script:TotalSteps) * 100) 
    } else { 
        0 
    }
    
    # Update the progress bar and status label in the GUI
    try {
        if ($script:prgProgress -ne $null) {
            $script:prgProgress.Value = [Math]::Min($percentage, 100)
        }
        if ($script:lblProgress -ne $null) {
            $script:lblProgress.Text = if ($Status) { $Status } else { "Progress: $percentage%" }
        }
    }
    catch {
        Write-Host "Error updating progress bar: $_" -ForegroundColor Red
    }
}

function Create-SelectionUI {
    param(
        [Parameter(Mandatory=$true)]
        [System.Windows.Forms.TabPage]$Panel,
        [Parameter(Mandatory=$true)]
        [hashtable]$Categories,
        [Parameter(Mandatory=$true)]
        [ref]$SelectedItemsArray
    )
    
    try {
        # Clear the panel
        $Panel.Controls.Clear()
        
        # Panel for checkboxes with auto-scroll
        $scrollPanel = New-Object System.Windows.Forms.Panel
        $scrollPanel.AutoScroll = $true
        $scrollPanel.Dock = [System.Windows.Forms.DockStyle]::Fill
        $Panel.Controls.Add($scrollPanel)
        
        # Y position tracker for controls
        $yPos = 10
        
        # Add select all checkbox
        $cbSelectAll = New-Object System.Windows.Forms.CheckBox
        $cbSelectAll.Text = "Select All"
        $cbSelectAll.Location = New-Object System.Drawing.Point(10, $yPos)
        $cbSelectAll.Width = 200
        $cbSelectAll.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
        $cbSelectAll.Add_Click({
            try {
                $isChecked = $this.Checked
                $scrollPanel = $this.Parent
                
                # Check/uncheck all checkboxes in this panel
                foreach ($control in $scrollPanel.Controls) {
                    if ($control -is [System.Windows.Forms.CheckBox] -and $control -ne $this) {
                        $control.Checked = $isChecked
                    }
                    elseif ($control -is [System.Windows.Forms.FlowLayoutPanel]) {
                        foreach ($childControl in $control.Controls) {
                            if ($childControl -is [System.Windows.Forms.CheckBox]) {
                                $childControl.Checked = $isChecked
                            }
                        }
                    }
                }
                
                # Determine which tab this is and update the appropriate selection
                $tabPage = $scrollPanel.Parent
                if ($tabPage -eq $script:tabInstall) {
                    Update-SelectedItems -Panel $scrollPanel -SelectedItemsArray ([ref]$script:SelectedApps)
                }
                elseif ($tabPage -eq $script:tabRemove) {
                    Update-SelectedItems -Panel $scrollPanel -SelectedItemsArray ([ref]$script:SelectedBloatware)
                }
                elseif ($tabPage -eq $script:tabServices) {
                    Update-SelectedItems -Panel $scrollPanel -SelectedItemsArray ([ref]$script:SelectedServices)
                }
                elseif ($tabPage -eq $script:tabOptimize) {
                    Update-SelectedItems -Panel $scrollPanel -SelectedItemsArray ([ref]$script:SelectedOptimizations)
                }
            }
            catch {
                # Silently handle any errors
            }
        })
        $scrollPanel.Controls.Add($cbSelectAll)
        
        $yPos += 30
        
        # For each category, create a group
        foreach ($category in $Categories.Keys | Sort-Object) {
            # Add category header
            $categoryLabel = New-Object System.Windows.Forms.Label
            $categoryLabel.Text = $category
            $categoryLabel.Location = New-Object System.Drawing.Point(10, $yPos)
            $categoryLabel.AutoSize = $true
            $categoryLabel.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
            $categoryLabel.ForeColor = [System.Drawing.Color]::FromArgb(0, 120, 215)
            $scrollPanel.Controls.Add($categoryLabel)
            
            $yPos += 25
            
            # Create a FlowLayoutPanel for the items in this category
            $flowPanel = New-Object System.Windows.Forms.FlowLayoutPanel
            $flowPanel.Location = New-Object System.Drawing.Point(20, $yPos)
            $flowPanel.Width = $Panel.Width - 60
            $flowPanel.AutoSize = $true
            $flowPanel.FlowDirection = [System.Windows.Forms.FlowDirection]::LeftToRight
            $flowPanel.WrapContents = $true
            $flowPanel.Padding = New-Object System.Windows.Forms.Padding(0)
            
            # Add checkboxes for each item in this category
            foreach ($item in $Categories[$category] | Sort-Object -Property Name) {
                # Skip items that aren't applicable to this Windows version
                if (($script:IsWindows11 -and -not $item.Win11) -or 
                    (-not $script:IsWindows11 -and -not $item.Win10)) {
                    continue
                }
                
                $cb = New-Object System.Windows.Forms.CheckBox
                $cb.Text = $item.Name
                $cb.Tag = $item.Key
                $cb.AutoSize = $true
                $cb.Width = 200
                $cb.Margin = New-Object System.Windows.Forms.Padding(0, 0, 10, 5)
                $cb.Checked = $item.Default
                $cb.Add_Click({
                    # Find the scroll panel (grandparent of checkbox) and update selection
                    try {
                        $flowPanel = $this.Parent
                        $scrollPanel = $flowPanel.Parent
                        if ($scrollPanel -ne $null) {
                            # Determine which tab this is based on the panel's parent
                            $tabPage = $scrollPanel.Parent
                            if ($tabPage -eq $script:tabInstall) {
                                Update-SelectedItems -Panel $scrollPanel -SelectedItemsArray ([ref]$script:SelectedApps)
                            }
                            elseif ($tabPage -eq $script:tabRemove) {
                                Update-SelectedItems -Panel $scrollPanel -SelectedItemsArray ([ref]$script:SelectedBloatware)
                            }
                            elseif ($tabPage -eq $script:tabServices) {
                                Update-SelectedItems -Panel $scrollPanel -SelectedItemsArray ([ref]$script:SelectedServices)
                            }
                            elseif ($tabPage -eq $script:tabOptimize) {
                                Update-SelectedItems -Panel $scrollPanel -SelectedItemsArray ([ref]$script:SelectedOptimizations)
                            }
                        }
                    }
                    catch {
                        # Silently handle any errors in selection update
                    }
                })
                $flowPanel.Controls.Add($cb)
            }
            
            $scrollPanel.Controls.Add($flowPanel)
            $yPos += $flowPanel.Height + 20
        }
        
        # Initial population of selected items
        Update-SelectedItems -Panel $scrollPanel -SelectedItemsArray $SelectedItemsArray
    } catch {
        Write-Log "Error in Create-SelectionUI: $_" -Level "ERROR"
    }
}

function Update-SelectedItems {
    param(
        [Parameter(Mandatory=$true)]
        [System.Windows.Forms.Panel]$Panel,
        [Parameter(Mandatory=$true)]
        [ref]$SelectedItemsArray
    )
    
    try {
        $selectedItems = @()
        
        foreach ($control in $Panel.Controls) {
            if ($control -is [System.Windows.Forms.CheckBox] -and $control.Tag -and $control.Checked) {
                $selectedItems += $control.Tag
            }
            elseif ($control -is [System.Windows.Forms.FlowLayoutPanel]) {
                foreach ($childControl in $control.Controls) {
                    if ($childControl -is [System.Windows.Forms.CheckBox] -and $childControl.Tag -and $childControl.Checked) {
                        $selectedItems += $childControl.Tag
                    }
                }
            }
        }
        
        $SelectedItemsArray.Value = $selectedItems
    } catch {
        Write-Log "Error in Update-SelectedItems: $_" -Level "ERROR"
    }
}

function Cancel-AllOperations {
    if ($script:IsRunning) {
        Write-Log "Cancelling all operations..." -Level "WARNING"
        
        # Stop PowerShell runspace operations
        try {
            if ($script:PowerShell -ne $null) {
                $script:PowerShell.Stop()
                Write-Log "PowerShell execution stopped" -Level "INFO"
            }
        }
        catch {
            Write-Log "Error stopping PowerShell: $_" -Level "WARNING"
        }
        
        # Clean up timers
        if ($script:ProgressTimer -ne $null) {
            $script:ProgressTimer.Stop()
            $script:ProgressTimer.Dispose()
            $script:ProgressTimer = $null
        }
        
        # Clean up PowerShell and runspace
        if ($script:PowerShell -ne $null) {
            $script:PowerShell.Dispose()
            $script:PowerShell = $null
        }
        
        if ($script:Runspace -ne $null) {
            $script:Runspace.Close()
            $script:Runspace.Dispose()
            $script:Runspace = $null
        }
        
        # Clean up old job-based approach if any jobs exist
        if ($script:BackgroundJobs.Count -gt 0) {
            foreach ($job in $script:BackgroundJobs) {
                if ($job.State -eq "Running") {
                    Stop-Job -Job $job -ErrorAction SilentlyContinue
                    Remove-Job -Job $job -ErrorAction SilentlyContinue
                }
            }
            $script:BackgroundJobs = @()
        }
        
        # Clean up BackgroundWorker if it exists
        if ($script:BackgroundWorker -ne $null -and $script:BackgroundWorker.IsBusy) {
            $script:BackgroundWorker.CancelAsync()
        }
        
        # Clean up cancellation token
        if ($script:CancellationTokenSource -ne $null) {
            $script:CancellationTokenSource.Dispose()
            $script:CancellationTokenSource = $null
        }
        
        # Reset UI state
        $script:IsRunning = $false
        $script:btnRun.Enabled = $true
        $script:btnCancel.Enabled = $false
        
        Update-ProgressBar -Status "Operations cancelled"
        Write-Log "All operations cancelled" -Level "WARNING"
    }
}

function Update-LogTextBox {
    param (
        [string]$Message,
        [string]$Level = "INFO"
    )
    
    try {
        if ($script:txtLog.InvokeRequired) {
            $script:txtLog.Invoke({
                param($msg, $lvl)
                $script:txtLog.SelectionStart = $script:txtLog.TextLength
                $script:txtLog.SelectionLength = 0
                
                # Set color based on level
                switch ($lvl) {
                    "ERROR" { $script:txtLog.SelectionColor = [System.Drawing.Color]::Red }
                    "WARNING" { $script:txtLog.SelectionColor = [System.Drawing.Color]::Orange }
                    "SUCCESS" { $script:txtLog.SelectionColor = [System.Drawing.Color]::Green }
                    default { $script:txtLog.SelectionColor = [System.Drawing.Color]::Black }
                }
                
                $script:txtLog.AppendText("${msg}`r`n")
                $script:txtLog.ScrollToCaret()
            }, $Message, $Level)
        }
        else {
            $script:txtLog.SelectionStart = $script:txtLog.TextLength
            $script:txtLog.SelectionLength = 0
            
            # Set color based on level
            switch ($Level) {
                "ERROR" { $script:txtLog.SelectionColor = [System.Drawing.Color]::Red }
                "WARNING" { $script:txtLog.SelectionColor = [System.Drawing.Color]::Orange }
                "SUCCESS" { $script:txtLog.SelectionColor = [System.Drawing.Color]::Green }
                default { $script:txtLog.SelectionColor = [System.Drawing.Color]::Black }
            }
            
            $script:txtLog.AppendText("${Message}`r`n")
            $script:txtLog.ScrollToCaret()
        }
    }
    catch {
        Write-Host "Error updating log textbox: $_"
    }
}

#endregion Helper Functions

#region Main Script

# Try loading the assemblies with better error handling
try {
    Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
    Add-Type -AssemblyName System.Drawing -ErrorAction Stop
    Write-Host "Loaded Windows Forms assemblies successfully" -ForegroundColor Green
} catch {
    Write-Host "Failed to load Windows Forms assemblies: $_" -ForegroundColor Red
    Write-Host "Make sure .NET Framework is properly installed" -ForegroundColor Yellow
    exit 1
}

# Enable visual styles with error handling
try {
    [System.Windows.Forms.Application]::EnableVisualStyles()
    Write-Host "Enabled visual styles successfully" -ForegroundColor Green
} catch {
    Write-Host "Failed to enable visual styles: $_" -ForegroundColor Red
}

# Initialize logging
Initialize-Logging

# Create the main form using the original's sophisticated layout
$form = New-Object System.Windows.Forms.Form
$form.Text = "Windows Setup Automation"
$form.Width = 800
$form.Height = 650
$form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedSingle
$form.MaximizeBox = $false

# Calculate sizes based on form dimensions
$formWidth = $form.Width

# Create header panel
$headerPanel = New-Object System.Windows.Forms.Panel
$headerPanel.Dock = [System.Windows.Forms.DockStyle]::Top
$headerPanel.Height = 60
$headerPanel.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 215)
$form.Controls.Add($headerPanel)

# Create title label
$lblTitle = New-Object System.Windows.Forms.Label
$lblTitle.Text = "Windows Setup Automation"
$lblTitle.ForeColor = [System.Drawing.Color]::White
$lblTitle.Font = New-Object System.Drawing.Font("Segoe UI", 16, [System.Drawing.FontStyle]::Regular)
$lblTitle.AutoSize = $true
$lblTitle.Location = New-Object System.Drawing.Point(15, 15)
$headerPanel.Controls.Add($lblTitle)

# Create OS badge
$lblOSBadge = New-Object System.Windows.Forms.Label
$lblOSBadge.Text = if ($script:IsWindows11) { "Windows 11 Detected" } else { "Windows 10 Detected" }
$lblOSBadge.ForeColor = [System.Drawing.Color]::White
$lblOSBadge.BackColor = [System.Drawing.Color]::FromArgb(50, 255, 255, 255)
$lblOSBadge.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Regular)
$lblOSBadge.AutoSize = $true
$lblOSBadge.Padding = New-Object System.Windows.Forms.Padding(8, 5, 8, 5)
$lblOSBadge.Location = New-Object System.Drawing.Point(($formWidth - 180), 15)
$headerPanel.Controls.Add($lblOSBadge)

# Create tab control
$tabControl = New-Object System.Windows.Forms.TabControl
$tabControl.Location = New-Object System.Drawing.Point(0, 60)
$tabControl.Size = New-Object System.Drawing.Size($formWidth, 400)
$tabControl.Dock = [System.Windows.Forms.DockStyle]::Fill
$form.Controls.Add($tabControl)

# Create tabs
$script:tabInstall = New-Object System.Windows.Forms.TabPage
$script:tabInstall.Text = "Install"
$tabControl.Controls.Add($script:tabInstall)

$script:tabRemove = New-Object System.Windows.Forms.TabPage
$script:tabRemove.Text = "Remove"
$tabControl.Controls.Add($script:tabRemove)

$script:tabServices = New-Object System.Windows.Forms.TabPage
$script:tabServices.Text = "Services"
$tabControl.Controls.Add($script:tabServices)

$script:tabOptimize = New-Object System.Windows.Forms.TabPage
$script:tabOptimize.Text = "Optimize"
$tabControl.Controls.Add($script:tabOptimize)

# Create footer panel
$footerPanel = New-Object System.Windows.Forms.Panel
$footerPanel.Dock = [System.Windows.Forms.DockStyle]::Bottom
$footerPanel.Height = 170
$form.Controls.Add($footerPanel)

# Create action panel (Run button area)
$actionPanel = New-Object System.Windows.Forms.Panel
$actionPanel.Dock = [System.Windows.Forms.DockStyle]::Top
$actionPanel.Height = 50
$actionPanel.BackColor = [System.Drawing.Color]::FromArgb(245, 245, 245)
$actionPanel.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$footerPanel.Controls.Add($actionPanel)

# Run button
$script:btnRun = New-Object System.Windows.Forms.Button
$script:btnRun.Text = "Run Selected Tasks"
$script:btnRun.Size = New-Object System.Drawing.Size(150, 32)
$script:btnRun.Location = New-Object System.Drawing.Point(($formWidth - 320), 8)
$script:btnRun.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 215)
$script:btnRun.ForeColor = [System.Drawing.Color]::White
$script:btnRun.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$actionPanel.Controls.Add($script:btnRun)

# Cancel button
$script:btnCancel = New-Object System.Windows.Forms.Button
$script:btnCancel.Text = "Cancel"
$script:btnCancel.Size = New-Object System.Drawing.Size(100, 32)
$script:btnCancel.Location = New-Object System.Drawing.Point(($formWidth - 160), 8)
$script:btnCancel.BackColor = [System.Drawing.Color]::FromArgb(220, 220, 220)
$script:btnCancel.ForeColor = [System.Drawing.Color]::Black
$script:btnCancel.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$script:btnCancel.Enabled = $false
$actionPanel.Controls.Add($script:btnCancel)

# Summary label
$lblSummary = New-Object System.Windows.Forms.Label
$lblSummary.Text = "Ready to start"
$lblSummary.AutoSize = $true
$lblSummary.Location = New-Object System.Drawing.Point(15, 15)
$actionPanel.Controls.Add($lblSummary)

# Progress panel
$progressPanel = New-Object System.Windows.Forms.Panel
$progressPanel.Dock = [System.Windows.Forms.DockStyle]::Fill
$progressPanel.Padding = New-Object System.Windows.Forms.Padding(10)
$footerPanel.Controls.Add($progressPanel)

# Progress status label
$script:lblProgress = New-Object System.Windows.Forms.Label
$script:lblProgress.Text = "Status: Ready"
$script:lblProgress.AutoSize = $true
$script:lblProgress.Location = New-Object System.Drawing.Point(0, 0)
$progressPanel.Controls.Add($script:lblProgress)

# Progress bar
$script:prgProgress = New-Object System.Windows.Forms.ProgressBar
$script:prgProgress.Location = New-Object System.Drawing.Point(0, 20)
$script:prgProgress.Size = New-Object System.Drawing.Size(($formWidth - 20), 20)
$script:prgProgress.Style = [System.Windows.Forms.ProgressBarStyle]::Continuous
$progressPanel.Controls.Add($script:prgProgress)

# Log text box
$script:txtLog = New-Object System.Windows.Forms.RichTextBox
$script:txtLog.Location = New-Object System.Drawing.Point(0, 45)
$script:txtLog.Size = New-Object System.Drawing.Size(($formWidth - 20), 65)
$script:txtLog.ReadOnly = $true
$script:txtLog.BackColor = [System.Drawing.Color]::FromArgb(250, 250, 250)
$script:txtLog.Font = New-Object System.Drawing.Font("Consolas", 8)
$progressPanel.Controls.Add($script:txtLog)

# Create selection UI for each tab
Create-SelectionUI -Panel $script:tabInstall -Categories $script:AppCategories -SelectedItemsArray ([ref]$script:SelectedApps)
Create-SelectionUI -Panel $script:tabRemove -Categories $script:BloatwareCategories -SelectedItemsArray ([ref]$script:SelectedBloatware)
Create-SelectionUI -Panel $script:tabServices -Categories $script:ServiceCategories -SelectedItemsArray ([ref]$script:SelectedServices)
Create-SelectionUI -Panel $script:tabOptimize -Categories $script:OptimizationCategories -SelectedItemsArray ([ref]$script:SelectedOptimizations)

function Start-SelectedOperations {
    try {
        # Prevent multiple runs
        if ($script:IsRunning) {
            [System.Windows.Forms.MessageBox]::Show(
                "Operations are already in progress. Please wait for them to complete.",
                "Operations in Progress",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information
            )
            return
        }
        
        # Calculate total steps
        $script:TotalSteps = $script:SelectedApps.Count + $script:SelectedBloatware.Count + 
                             $script:SelectedServices.Count + $script:SelectedOptimizations.Count
        
        if ($script:TotalSteps -eq 0) {
            Write-Log "No operations selected" -Level "WARNING"
            [System.Windows.Forms.MessageBox]::Show("Please select at least one operation to perform.", "No Operations Selected", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
            return
        }
        
        # Update UI state
        $script:btnRun.Enabled = $false
        $script:btnCancel.Enabled = $true
        $script:txtLog.Clear()
        
        $script:IsRunning = $true
        $script:StartTime = Get-Date
        $script:CurrentStep = 0
        
        Write-Log "Starting selected operations..." -Level "INFO"
        Update-ProgressBar -Status "Starting operations..."
        
        # Create PowerShell runspace for background operations
        $script:PowerShell = [PowerShell]::Create()
        $script:Runspace = [RunspaceFactory]::CreateRunspace()
        $script:Runspace.Open()
        $script:PowerShell.Runspace = $script:Runspace
        
        # Import modules in the runspace
        $script:PowerShell.AddScript({
            param($modulePath, $utilsPath, $selectedApps, $selectedBloatware, $selectedServices, $selectedOptimizations, $totalSteps, $useDirectDownloadOnly)
            
            # Import required modules
            Import-Module (Join-Path $utilsPath "Logging.psm1") -Force
            Import-Module (Join-Path $modulePath "Installers.psm1") -Force
            Import-Module (Join-Path $modulePath "SystemOptimizations.psm1") -Force
            
            # Set the direct download flag in the runspace
            $script:UseDirectDownloadOnly = $useDirectDownloadOnly
            
            $stepCount = 0
            $results = @()
            
            # If winget is not available and we haven't tried to install it, try now
            if ($useDirectDownloadOnly -and -not (Get-Command winget -ErrorAction SilentlyContinue)) {
                $results += @{
                    Step = 0
                    Percentage = 0
                    Status = "Attempting to install winget..."
                    Type = "Progress"
                }
                
                # Try to install winget (simplified version for background)
                try {
                    # Check Windows version first
                    $osInfo = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
                    if ($osInfo -and $osInfo.Version) {
                        $osVersion = [Version]$osInfo.Version
                        if ($osVersion.Build -ge 17763) {  # Windows 10 1809+
                            # Try to install via PowerShell
                            $appInstallerUrl = "https://aka.ms/getwinget"
                            $tempPath = Join-Path $env:TEMP "Microsoft.DesktopAppInstaller.msixbundle"
                            
                            Invoke-WebRequest -Uri $appInstallerUrl -OutFile $tempPath -UseBasicParsing -TimeoutSec 30
                            Add-AppxPackage -Path $tempPath -ErrorAction Stop
                            Remove-Item $tempPath -Force -ErrorAction SilentlyContinue
                            
                            # Wait and test
                            Start-Sleep -Seconds 3
                            $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("PATH", "User")
                            
                            if (Get-Command winget -ErrorAction SilentlyContinue) {
                                $script:UseDirectDownloadOnly = $false
                                $results += @{
                                    Step = 0
                                    Percentage = 0
                                    Status = "Winget successfully installed!"
                                    Type = "Success"
                                }
                            }
                        }
                    }
                }
                catch {
                    $results += @{
                        Step = 0
                        Percentage = 0
                        Status = "Winget installation failed, using direct downloads"
                        Type = "Warning"
                    }
                }
            }
            
            try {
                # Install selected applications
                foreach ($app in $selectedApps) {
                    $stepCount++
                    $percentage = [Math]::Round(($stepCount / $totalSteps) * 100)
                    $results += @{
                        Step = $stepCount
                        Percentage = $percentage
                        Status = "Installing application: $app"
                        Type = "Progress"
                    }
                    
                    try {
                        Install-Application -AppName $app
                        $results += @{
                            Step = $stepCount
                            Percentage = $percentage
                            Status = "[SUCCESS] Installed: $app"
                            Type = "Success"
                        }
                    }
                    catch {
                        $results += @{
                            Step = $stepCount
                            Percentage = $percentage
                            Status = "[ERROR] Failed to install: $app - $_"
                            Type = "Error"
                        }
                    }
                }
                
                # Remove selected bloatware
                foreach ($bloat in $selectedBloatware) {
                    $stepCount++
                    $percentage = [Math]::Round(($stepCount / $totalSteps) * 100)
                    $results += @{
                        Step = $stepCount
                        Percentage = $percentage
                        Status = "Removing bloatware: $bloat"
                        Type = "Progress"
                    }
                    
                    try {
                        Remove-Bloatware -BloatwareKey $bloat
                        $results += @{
                            Step = $stepCount
                            Percentage = $percentage
                            Status = "[SUCCESS] Removed: $bloat"
                            Type = "Success"
                        }
                    }
                    catch {
                        $results += @{
                            Step = $stepCount
                            Percentage = $percentage
                            Status = "[ERROR] Failed to remove: $bloat - $_"
                            Type = "Error"
                        }
                    }
                }
                
                # Configure selected services
                foreach ($service in $selectedServices) {
                    $stepCount++
                    $percentage = [Math]::Round(($stepCount / $totalSteps) * 100)
                    $results += @{
                        Step = $stepCount
                        Percentage = $percentage
                        Status = "Configuring service: $service"
                        Type = "Progress"
                    }
                    
                    try {
                        Set-SystemOptimization -OptimizationKey $service
                        $results += @{
                            Step = $stepCount
                            Percentage = $percentage
                            Status = "[SUCCESS] Configured service: $service"
                            Type = "Success"
                        }
                    }
                    catch {
                        $results += @{
                            Step = $stepCount
                            Percentage = $percentage
                            Status = "[ERROR] Failed to configure service: $service - $_"
                            Type = "Error"
                        }
                    }
                }
                
                # Apply selected optimizations
                foreach ($opt in $selectedOptimizations) {
                    $stepCount++
                    $percentage = [Math]::Round(($stepCount / $totalSteps) * 100)
                    $results += @{
                        Step = $stepCount
                        Percentage = $percentage
                        Status = "Applying optimization: $opt"
                        Type = "Progress"
                    }
                    
                    try {
                        Set-SystemOptimization -OptimizationKey $opt
                        $results += @{
                            Step = $stepCount
                            Percentage = $percentage
                            Status = "[SUCCESS] Applied optimization: $opt"
                            Type = "Success"
                        }
                    }
                    catch {
                        $results += @{
                            Step = $stepCount
                            Percentage = $percentage
                            Status = "[ERROR] Failed to apply optimization: $opt - $_"
                            Type = "Error"
                        }
                    }
                }
                
                return $results
            }
            catch {
                return @{
                    Step = -1
                    Percentage = 0
                    Status = "Critical error: $_"
                    Type = "CriticalError"
                }
            }
        })
        
        # Add parameters
        $script:PowerShell.AddArgument($modulePath)
        $script:PowerShell.AddArgument($utilsPath)
        $script:PowerShell.AddArgument($script:SelectedApps)
        $script:PowerShell.AddArgument($script:SelectedBloatware)
        $script:PowerShell.AddArgument($script:SelectedServices)
        $script:PowerShell.AddArgument($script:SelectedOptimizations)
        $script:PowerShell.AddArgument($script:TotalSteps)
        $script:PowerShell.AddArgument($script:UseDirectDownloadOnly)
        
        # Start async execution
        $script:AsyncResult = $script:PowerShell.BeginInvoke()
        
        # Create timer to check for completion and update progress
        $script:ProgressTimer = New-Object System.Windows.Forms.Timer
        $script:ProgressTimer.Interval = 500
        $script:ProgressTimer.Add_Tick({
            try {
                if ($script:AsyncResult.IsCompleted) {
                    # Get results
                    $results = $script:PowerShell.EndInvoke($script:AsyncResult)
                    
                    # Process results and update UI
                    foreach ($result in $results) {
                        if ($result.Type -eq "Progress") {
                            $script:CurrentStep = $result.Step
                            Update-ProgressBar -Status $result.Status
                            Write-Log $result.Status -Level "INFO"
                        }
                        elseif ($result.Type -eq "Success") {
                            Write-Log $result.Status -Level "SUCCESS"
                        }
                        elseif ($result.Type -eq "Error") {
                            Write-Log $result.Status -Level "ERROR"
                        }
                        elseif ($result.Type -eq "Warning") {
                            Write-Log $result.Status -Level "WARNING"
                        }
                        elseif ($result.Type -eq "CriticalError") {
                            Write-Log $result.Status -Level "ERROR"
                        }
                        elseif ($result.Type -eq "Method") {
                            Write-Log $result.Status -Level "INFO"
                        }
                        elseif ($result.Type -eq "Download") {
                            Write-Log $result.Status -Level "INFO"
                        }
                        elseif ($result.Type -eq "Install") {
                            Write-Log $result.Status -Level "INFO"
                        }
                    }
                    
                    # Calculate elapsed time
                    $elapsed = (Get-Date) - $script:StartTime
                    Write-Log "Total time: $($elapsed.ToString('mm\:ss'))" -Level "INFO"
                    Write-Log "All operations completed!" -Level "SUCCESS"
                    Update-ProgressBar -Status "All operations completed!"
                    
                    # Cleanup and reset UI
                    $script:ProgressTimer.Stop()
                    $script:ProgressTimer.Dispose()
                    $script:ProgressTimer = $null
                    
                    if ($script:PowerShell -ne $null) {
                        $script:PowerShell.Dispose()
                        $script:PowerShell = $null
                    }
                    
                    if ($script:Runspace -ne $null) {
                        $script:Runspace.Close()
                        $script:Runspace.Dispose()
                        $script:Runspace = $null
                    }
                    
                    $script:IsRunning = $false
                    $script:btnRun.Enabled = $true
                    $script:btnCancel.Enabled = $false
                }
            }
            catch {
                Write-Log "Error in progress timer: $_" -Level "ERROR"
                # Reset UI on error
                $script:IsRunning = $false
                $script:btnRun.Enabled = $true
                $script:btnCancel.Enabled = $false
                if ($script:ProgressTimer -ne $null) {
                    $script:ProgressTimer.Stop()
                    $script:ProgressTimer.Dispose()
                    $script:ProgressTimer = $null
                }
            }
        })
        
        $script:ProgressTimer.Start()
    }
    catch {
        Write-Log "Error in Start-SelectedOperations: $_" -Level "ERROR"
        $script:IsRunning = $false
        $script:btnRun.Enabled = $true
        $script:btnCancel.Enabled = $false
    }
}

# Add Run button click handler
$script:btnRun.Add_Click({
    Start-SelectedOperations
})

# Add Cancel button click handler
$script:btnCancel.Add_Click({
    Cancel-AllOperations
})

function Install-Winget {
    try {
        Write-Log "Attempting to install winget..." -Level "INFO"
        
        # Check if we're on Windows 10 version 1809 or later (required for winget)
        if ($script:OSVersion.Build -lt 17763) {
            Write-Log "Windows version too old for winget (requires Windows 10 1809+)" -Level "WARNING"
            return $false
        }
        
        # Try to install App Installer from Microsoft Store (contains winget)
        Write-Log "Installing App Installer package..." -Level "INFO"
        
        # Download and install the latest App Installer package
        $appInstallerUrl = "https://aka.ms/getwinget"
        $tempPath = Join-Path $env:TEMP "Microsoft.DesktopAppInstaller.msixbundle"
        
        try {
            # Download App Installer
            Write-Log "Downloading App Installer from Microsoft..." -Level "INFO"
            Invoke-WebRequest -Uri $appInstallerUrl -OutFile $tempPath -UseBasicParsing
            
            # Install the package
            Write-Log "Installing App Installer package..." -Level "INFO"
            Add-AppxPackage -Path $tempPath -ErrorAction Stop
            
            # Clean up temp file
            Remove-Item $tempPath -Force -ErrorAction SilentlyContinue
            
            # Wait a moment for installation to complete
            Start-Sleep -Seconds 3
            
            # Refresh PATH environment variable
            $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("PATH", "User")
            
            # Test if winget is now available
            if (Get-Command winget -ErrorAction SilentlyContinue) {
                Write-Log "Winget successfully installed!" -Level "SUCCESS"
                return $true
            } else {
                Write-Log "Winget installation completed but command not found. May need system restart." -Level "WARNING"
                return $false
            }
        }
        catch {
            Write-Log "Failed to install winget via App Installer: $_" -Level "ERROR"
            
            # Try alternative method: Install via PowerShell
            Write-Log "Trying alternative installation method..." -Level "INFO"
            
            try {
                # Install using Add-AppxPackage with online source
                $msixUrl = "https://github.com/microsoft/winget-cli/releases/latest/download/Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle"
                $msixPath = Join-Path $env:TEMP "winget.msixbundle"
                
                Invoke-WebRequest -Uri $msixUrl -OutFile $msixPath -UseBasicParsing
                Add-AppxPackage -Path $msixPath -ErrorAction Stop
                
                Remove-Item $msixPath -Force -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 3
                
                # Refresh PATH
                $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("PATH", "User")
                
                if (Get-Command winget -ErrorAction SilentlyContinue) {
                    Write-Log "Winget successfully installed via alternative method!" -Level "SUCCESS"
                    return $true
                } else {
                    Write-Log "Alternative winget installation failed" -Level "ERROR"
                    return $false
                }
            }
            catch {
                Write-Log "Alternative winget installation failed: $_" -Level "ERROR"
                return $false
            }
        }
    }
    catch {
        Write-Log "Error during winget installation: $_" -Level "ERROR"
        return $false
    }
}

# Add event handler for form shown
$form.Add_Shown({
    Write-Log "Windows Setup Automation GUI started" -Level "INFO"
    Write-Log "Detected OS: $($script:OSName)" -Level "INFO"
    
    # Quick winget check without installation attempt
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-Log "Winget is not installed. Direct download methods will be used for application installations." -Level "WARNING"
        Write-Log "Note: The system will attempt to install winget automatically when you run operations if needed." -Level "INFO"
        Write-Log "You can also manually install winget from the Microsoft Store (App Installer)." -Level "INFO"
        $script:UseDirectDownloadOnly = $true
    } else {
        Write-Log "Winget is available and will be used for application installations" -Level "SUCCESS"
        $script:UseDirectDownloadOnly = $false
    }
    
    Write-Log "Select applications and click 'Run Selected Tasks' to begin" -Level "INFO"
})

# Add event handler for form closing
$form.Add_FormClosing({
    param($formSender, $e)
    
    # If operations are in progress, confirm before closing
    if ($script:IsRunning) {
        $result = [System.Windows.Forms.MessageBox]::Show(
            "Operations are still in progress. Are you sure you want to exit?`n`nThis will cancel all running operations.",
            "Confirm Exit",
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )
        
        if ($result -eq [System.Windows.Forms.DialogResult]::No) {
            $e.Cancel = $true
            return
        }
        
        # Cancel all operations
        Cancel-AllOperations
    }
})

# Show the form
Write-Host "Launching GUI interface..." -ForegroundColor Green
[void]$form.ShowDialog()

# Cleanup
if ($script:ProgressTimer -ne $null) {
    $script:ProgressTimer.Stop()
    $script:ProgressTimer.Dispose()
}
Cleanup-TempFiles

#endregion Main Script 