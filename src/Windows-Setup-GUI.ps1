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
$script:SelectedApps = @()
$script:SelectedBloatware = @()
$script:SelectedServices = @()
$script:SelectedOptimizations = @()
$script:BackgroundJobs = @()
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
        [string]$Message,
        [Parameter(Mandatory=$false)]
        [string]$Level = "INFO"
    )

    if ($script:txtLog -ne $null) {
        try {
            $script:txtLog.Invoke([System.Action]{
                $script:txtLog.AppendText("$Message`r`n")
                $script:txtLog.ScrollToCaret()
            })
        } catch {
            Write-Host "Error updating log textbox: $_" -ForegroundColor Red
        }
    }
}

function Initialize-Checkboxes {
    param (
        [Parameter(Mandatory=$true)]
        [System.Windows.Forms.TabPage]$TabPage,
        [Parameter(Mandatory=$true)]
        [hashtable]$Categories,
        [Parameter(Mandatory=$true)]
        [string]$Type
    )

    $y = 10
    foreach ($category in $Categories.Keys) {
        # Create category label
        $label = New-Object System.Windows.Forms.Label
        $label.Text = $category
        $label.Location = New-Object System.Drawing.Point(10, $y)
        $label.AutoSize = $true
        $label.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
        $TabPage.Controls.Add($label)
        $y += 25

        # Create checkboxes for each item in the category
        foreach ($item in $Categories[$category]) {
            if (($script:IsWindows11 -and $item.Win11) -or (-not $script:IsWindows11 -and $item.Win10)) {
                $checkbox = New-Object System.Windows.Forms.CheckBox
                $checkbox.Text = $item.Name
                $checkbox.Location = New-Object System.Drawing.Point(20, $y)
                $checkbox.AutoSize = $true
                $checkbox.Checked = $item.Default
                $checkbox.Tag = $item.Key
                $checkbox.Add_CheckedChanged({
                    $key = $this.Tag
                    if ($this.Checked) {
                        switch ($Type) {
                            "App" { $script:SelectedApps += $key }
                            "Bloatware" { $script:SelectedBloatware += $key }
                            "Service" { $script:SelectedServices += $key }
                            "Optimization" { $script:SelectedOptimizations += $key }
                        }
                    } else {
                        switch ($Type) {
                            "App" { $script:SelectedApps = $script:SelectedApps | Where-Object { $_ -ne $key } }
                            "Bloatware" { $script:SelectedBloatware = $script:SelectedBloatware | Where-Object { $_ -ne $key } }
                            "Service" { $script:SelectedServices = $script:SelectedServices | Where-Object { $_ -ne $key } }
                            "Optimization" { $script:SelectedOptimizations = $script:SelectedOptimizations | Where-Object { $_ -ne $key } }
                        }
                    }
                })
                $TabPage.Controls.Add($checkbox)
                $y += 25
            }
        }
        $y += 10
    }
}

function Cancel-AllOperations {
    if ($script:IsRunning) {
        Write-Log "Cancelling all operations..." -Level "WARNING"
        
        if ($script:CancellationTokenSource -ne $null) {
            $script:CancellationTokenSource.Cancel()
        }
        
        foreach ($job in $script:BackgroundJobs) {
            if ($job.State -eq "Running") {
                Write-Log "Waiting for job to cancel..." -Level "INFO"
                Stop-Job -Job $job
                Remove-Job -Job $job
            }
        }
        
        $script:IsRunning = $false
        $script:btnRun.Enabled = $true
        $script:btnCancel.Enabled = $false
        
        if ($script:timer -ne $null) {
            $script:timer.Stop()
            $script:timer.Dispose()
            $script:timer = $null
        }
        
        Write-Log "All operations cancelled" -Level "WARNING"
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

# Create the main form
$form = New-Object System.Windows.Forms.Form
$form.Text = "Windows Setup Automation"
$form.Size = New-Object System.Drawing.Size(800, 600)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false
$form.MinimizeBox = $true

# Create tab control
$tabControl = New-Object System.Windows.Forms.TabControl
$tabControl.Dock = [System.Windows.Forms.DockStyle]::Fill
$tabControl.Size = New-Object System.Drawing.Size(780, 500)

# Create tabs
$tabInstall = New-Object System.Windows.Forms.TabPage
$tabInstall.Text = "Install Applications"
$tabInstall.UseVisualStyleBackColor = $true

$tabRemove = New-Object System.Windows.Forms.TabPage
$tabRemove.Text = "Remove Bloatware"
$tabRemove.UseVisualStyleBackColor = $true

$tabServices = New-Object System.Windows.Forms.TabPage
$tabServices.Text = "Manage Services"
$tabServices.UseVisualStyleBackColor = $true

$tabOptimize = New-Object System.Windows.Forms.TabPage
$tabOptimize.Text = "Optimize Windows"
$tabOptimize.UseVisualStyleBackColor = $true

# Add tabs to control
$tabControl.TabPages.Add($tabInstall)
$tabControl.TabPages.Add($tabRemove)
$tabControl.TabPages.Add($tabServices)
$tabControl.TabPages.Add($tabOptimize)

# Initialize checkboxes for each tab
Initialize-Checkboxes -TabPage $tabInstall -Categories $script:AppCategories -Type "App"
Initialize-Checkboxes -TabPage $tabRemove -Categories $script:BloatwareCategories -Type "Bloatware"
Initialize-Checkboxes -TabPage $tabServices -Categories $script:ServiceCategories -Type "Service"
Initialize-Checkboxes -TabPage $tabOptimize -Categories $script:OptimizationCategories -Type "Optimization"

# Create log textbox
$txtLog = New-Object System.Windows.Forms.TextBox
$txtLog.Multiline = $true
$txtLog.ScrollBars = "Vertical"
$txtLog.Dock = [System.Windows.Forms.DockStyle]::Fill
$txtLog.ReadOnly = $true
$txtLog.Font = New-Object System.Drawing.Font("Consolas", 9)
$script:txtLog = $txtLog

# Create progress bar
$prgProgress = New-Object System.Windows.Forms.ProgressBar
$prgProgress.Dock = [System.Windows.Forms.DockStyle]::Bottom
$prgProgress.Height = 20
$script:prgProgress = $prgProgress

# Create progress label
$lblProgress = New-Object System.Windows.Forms.Label
$lblProgress.Dock = [System.Windows.Forms.DockStyle]::Bottom
$lblProgress.Height = 20
$lblProgress.Text = "Ready"
$script:lblProgress = $lblProgress

# Create Run button
$btnRun = New-Object System.Windows.Forms.Button
$btnRun.Text = "Run Selected Operations"
$btnRun.Dock = [System.Windows.Forms.DockStyle]::Bottom
$btnRun.Height = 30
$script:btnRun = $btnRun

# Create Cancel button
$btnCancel = New-Object System.Windows.Forms.Button
$btnCancel.Text = "Cancel Operations"
$btnCancel.Dock = [System.Windows.Forms.DockStyle]::Bottom
$btnCancel.Height = 30
$btnCancel.Enabled = $false
$script:btnCancel = $btnCancel

# Add controls to form
$form.Controls.Add($tabControl)
$form.Controls.Add($txtLog)
$form.Controls.Add($prgProgress)
$form.Controls.Add($lblProgress)
$form.Controls.Add($btnRun)
$form.Controls.Add($btnCancel)

# Add Run button click handler
$btnRun.Add_Click({
    if (-not $script:IsRunning) {
        $script:IsRunning = $true
        $script:btnRun.Enabled = $false
        $script:btnCancel.Enabled = $true
        
        # Start the operations in a background job
        $script:BackgroundJobs = @()
        $script:CancellationTokenSource = New-Object System.Threading.CancellationTokenSource
        
        $job = Start-Job -ScriptBlock {
            param($SelectedApps, $SelectedBloatware, $SelectedServices, $SelectedOptimizations, $CancellationToken)
            
            # Import the required modules
            $scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
            $modulePath = Join-Path $scriptPath "modules"
            $utilsPath = Join-Path $scriptPath "utils"
            
            Import-Module (Join-Path $utilsPath "Logging.psm1") -Force
            Import-Module (Join-Path $modulePath "Installers.psm1") -Force
            Import-Module (Join-Path $modulePath "SystemOptimizations.psm1") -Force
            
            # Process selected applications
            foreach ($app in $SelectedApps) {
                if ($CancellationToken.IsCancellationRequested) { break }
                try {
                    Install-Application -AppName $app -CancellationToken $CancellationToken
                } catch {
                    Write-Log "Failed to install ${app}: $_" -Level "ERROR"
                }
            }
            
            # Process selected bloatware
            foreach ($bloat in $SelectedBloatware) {
                if ($CancellationToken.IsCancellationRequested) { break }
                try {
                    Remove-Bloatware -AppIdentifier $bloat -CancellationToken $CancellationToken
                } catch {
                    Write-Log "Failed to remove ${bloat}: $_" -Level "ERROR"
                }
            }
            
            # Process selected services
            foreach ($service in $SelectedServices) {
                if ($CancellationToken.IsCancellationRequested) { break }
                try {
                    Set-Service -Name $service -StartupType Disabled
                    Write-Log "Disabled service: ${service}" -Level "SUCCESS"
                } catch {
                    Write-Log "Failed to disable service ${service}: $_" -Level "ERROR"
                }
            }
            
            # Process selected optimizations
            foreach ($opt in $SelectedOptimizations) {
                if ($CancellationToken.IsCancellationRequested) { break }
                try {
                    Apply-Optimization -OptimizationKey $opt
                } catch {
                    Write-Log "Failed to apply optimization ${opt}: $_" -Level "ERROR"
                }
            }
            
        } -ArgumentList $script:SelectedApps, $script:SelectedBloatware, $script:SelectedServices, $script:SelectedOptimizations, $script:CancellationTokenSource.Token
        
        $script:BackgroundJobs += $job
        
        # Create and start the timer
        $script:timer = New-Object System.Windows.Forms.Timer
        $script:timer.Interval = 1000
        $script:timer.Add_Tick({
            $completed = $true
            foreach ($job in $script:BackgroundJobs) {
                if ($job.State -eq "Running") {
                    $completed = $false
                    break
                }
            }
            
            if ($completed) {
                if ($script:timer -ne $null) {
                    $script:timer.Stop()
                    $script:timer.Dispose()
                    $script:timer = $null
                }
                $script:IsRunning = $false
                $script:btnRun.Enabled = $true
                $script:btnCancel.Enabled = $false
                Write-Log "All operations completed" -Level "SUCCESS"
            }
        })
        $script:timer.Start()
    }
})

# Add Cancel button click handler
$btnCancel.Add_Click({
    Cancel-AllOperations
})

# Show the form
$form.ShowDialog()

# Cleanup
if ($script:timer -ne $null) {
    $script:timer.Stop()
    $script:timer.Dispose()
}
Cleanup-TempFiles

#endregion Main Script 