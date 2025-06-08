#Requires -RunAsAdministrator

# Windows Setup Automation GUI
# A GUI-based tool to automate Windows 10/11 setup, install applications, remove bloatware,
# optimize settings, and manage services.

#region Variables

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

function Cancel-AllOperations {
    if ($script:IsRunning) {
        Write-Log "Cancelling all operations..." -Level "WARNING"
        
        if ($null -ne $script:CancellationTokenSource) {
            $script:CancellationTokenSource.Cancel()
        }
        
        foreach ($job in $script:BackgroundJobs) {
            if ($job.IsCompleted -eq $false) {
                Write-Log "Waiting for job to cancel..." -Level "INFO"
            }
        }
        
        $script:BackgroundJobs = @()
        
        if ($script:btnRun -ne $null) {
            $script:btnRun.Enabled = $true
        }
        if ($script:btnCancel -ne $null) {
            $script:btnCancel.Enabled = $false
        }
        
        $script:IsRunning = $false
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

# Create log textbox
$txtLog = New-Object System.Windows.Forms.TextBox
$txtLog.Multiline = $true
$txtLog.ScrollBars = "Vertical"
$txtLog.Dock = [System.Windows.Forms.DockStyle]::Fill
$txtLog.ReadOnly = $true
$txtLog.Font = New-Object System.Drawing.Font("Consolas", 9)

# Create progress bar
$prgProgress = New-Object System.Windows.Forms.ProgressBar
$prgProgress.Dock = [System.Windows.Forms.DockStyle]::Bottom
$prgProgress.Height = 20

# Create progress label
$lblProgress = New-Object System.Windows.Forms.Label
$lblProgress.Dock = [System.Windows.Forms.DockStyle]::Bottom
$lblProgress.Height = 20
$lblProgress.Text = "Ready"

# Create Run button
$btnRun = New-Object System.Windows.Forms.Button
$btnRun.Text = "Run Selected Operations"
$btnRun.Dock = [System.Windows.Forms.DockStyle]::Bottom
$btnRun.Height = 30
$btnRun.Add_Click({
    if (-not $script:IsRunning) {
        $script:IsRunning = $true
        $btnRun.Enabled = $false
        $btnCancel.Enabled = $true
        
        # Start the operations in a background job
        $script:BackgroundJobs = @()
        $script:CancellationTokenSource = New-Object System.Threading.CancellationTokenSource
        
        $job = Start-Job -ScriptBlock {
            param($SelectedApps, $SelectedBloatware, $SelectedServices, $SelectedOptimizations, $CancellationToken)
            
            # Import the script's functions
            . $using:script:LogPath
            
            # Process selected applications
            foreach ($app in $SelectedApps) {
                if ($CancellationToken.IsCancellationRequested) { break }
                Install-Application -AppName $app -CancellationToken $CancellationToken
            }
            
            # Process selected bloatware
            foreach ($bloat in $SelectedBloatware) {
                if ($CancellationToken.IsCancellationRequested) { break }
                Remove-Bloatware -AppIdentifier $bloat -CancellationToken $CancellationToken
            }
            
            # Process selected services
            foreach ($service in $SelectedServices) {
                if ($CancellationToken.IsCancellationRequested) { break }
                Set-Service -Name $service -StartupType Disabled
            }
            
            # Process selected optimizations
            foreach ($opt in $SelectedOptimizations) {
                if ($CancellationToken.IsCancellationRequested) { break }
                Apply-Optimization -OptimizationKey $opt
            }
            
        } -ArgumentList $script:SelectedApps, $script:SelectedBloatware, $script:SelectedServices, $script:SelectedOptimizations, $script:CancellationTokenSource.Token
        
        $script:BackgroundJobs += $job
        
        # Monitor the job
        $timer = New-Object System.Windows.Forms.Timer
        $timer.Interval = 1000
        $timer.Add_Tick({
            $completed = $true
            foreach ($job in $script:BackgroundJobs) {
                if ($job.State -eq "Running") {
                    $completed = $false
                    break
                }
            }
            
            if ($completed) {
                $timer.Stop()
                $script:IsRunning = $false
                $btnRun.Enabled = $true
                $btnCancel.Enabled = $false
                Write-Log "All operations completed" -Level "SUCCESS"
            }
        })
        $timer.Start()
    }
})

# Create Cancel button
$btnCancel = New-Object System.Windows.Forms.Button
$btnCancel.Text = "Cancel Operations"
$btnCancel.Dock = [System.Windows.Forms.DockStyle]::Bottom
$btnCancel.Height = 30
$btnCancel.Enabled = $false
$btnCancel.Add_Click({
    Cancel-AllOperations
})

# Add controls to form
$form.Controls.Add($tabControl)
$form.Controls.Add($txtLog)
$form.Controls.Add($prgProgress)
$form.Controls.Add($lblProgress)
$form.Controls.Add($btnRun)
$form.Controls.Add($btnCancel)

# Show the form
$form.ShowDialog()

# Cleanup
Cleanup-TempFiles

#endregion Main Script 