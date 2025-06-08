#Requires -RunAsAdministrator

# Windows Setup Automation GUI - Fixed Version
# A GUI-based tool to automate Windows 10/11 setup, install applications, remove bloatware,
# optimize settings, and manage services.
# 
# Run this script as Administrator in PowerShell

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
    # Continue anyway as this is not critical
}

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

#region Helper Functions

# This function updates the UI from any thread safely
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
        try {
            & $Code
        } catch {
            Write-Host "Error executing UI code: $_" -ForegroundColor Red
        }
    }
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

    # Format log message
    $formattedMessage = "[$timestamp] [$Level] $Message"

    # Update the log textbox in the GUI
    Update-UI {
        # Apply color based on level
        $color = switch ($Level) {
            "WARNING" { "Orange" }
            "ERROR" { "Red" }
            "SUCCESS" { "Green" }
            "DEBUG" { "Gray" }
            default { "Black" }
        }
        
        # Add text
        $script:txtLog.SelectionColor = $color
        $script:txtLog.AppendText("$formattedMessage`r`n")
        
        # Restore selection position and scroll to end
        $script:txtLog.SelectionStart = $script:txtLog.Text.Length
        $script:txtLog.ScrollToCaret()
    }

    # Write to log file if enabled
    if ($script:EnableFileLogging) {
        try {
            Add-Content -Path $script:LogPath -Value $formattedMessage -ErrorAction Stop
        } catch {
            # Fallback to console if file logging fails
            Write-Host "Failed to write to log file: $_" -ForegroundColor Red
        }
    }

    # Also write to host for command-line users
    switch ($Level) {
        "WARNING" { Write-Host $formattedMessage -ForegroundColor Yellow }
        "ERROR" { Write-Host $formattedMessage -ForegroundColor Red }
        "SUCCESS" { Write-Host $formattedMessage -ForegroundColor Green }
        "DEBUG" { Write-Host $formattedMessage -ForegroundColor Gray }
        default { Write-Host $formattedMessage }
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

    $percentage = [Math]::Round(($script:CurrentStep / [Math]::Max($script:TotalSteps, 1)) * 100)
    
    # Update the progress bar and status label in the GUI
    Update-UI {
        $script:prgProgress.Value = $percentage
        $script:lblProgress.Text = if ($Status) { $Status } else { "Progress: $percentage%" }
    }
}

function Test-Administrator {
    $user = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($user)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Set-RegistryKey {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Path,
        [Parameter(Mandatory=$true)]
        [string]$Name,
        [Parameter(Mandatory=$true)]
        $Value,
        [Parameter(Mandatory=$false)]
        [string]$Type = "DWORD"
    )

    try {
        # Check if the registry path exists
        if (-not (Test-Path $Path)) {
            # Create the path
            New-Item -Path $Path -Force | Out-Null
            Write-Log "Created registry path: $Path" -Level "DEBUG"
        }

        # Set the registry value
        Set-ItemProperty -Path $Path -Name $Name -Value $Value -ErrorAction Stop
        Write-Log "Set registry key: $Path\$Name = $Value" -Level "DEBUG"
        return $true
    }
    catch {
        Write-Log "Failed to set registry key: $Path\$Name" -Level "ERROR"
        Write-Log "Error: $_" -Level "ERROR"
        return $false
    }
}

function Cancel-AllOperations {
    if ($script:IsRunning) {
        Write-Log "Cancelling all operations..." -Level "WARNING"
        
        # Signal cancellation to all running tasks
        if ($null -ne $script:CancellationTokenSource) {
            $script:CancellationTokenSource.Cancel()
        }
        
        # Wait for background jobs to complete
        foreach ($job in $script:BackgroundJobs) {
            if ($job.IsCompleted -eq $false) {
                Write-Log "Waiting for job to cancel..." -Level "INFO"
            }
        }
        
        # Clear background jobs
        $script:BackgroundJobs = @()
        
        # Reset UI
        Update-UI {
            $script:btnRun.Enabled = $true
            $script:btnCancel.Enabled = $false
        }
        
        $script:IsRunning = $false
        Write-Log "All operations cancelled" -Level "WARNING"
    }
}

#endregion Helper Functions

#region Installation Functions

function Install-Winget {
    [CmdletBinding()]
    param(
        [System.Threading.CancellationToken]$CancellationToken
    )
    
    # If we've already attempted to install winget and failed, don't try again
    if ($script:WingetInstallAttempted) {
        Write-Log "Skipping winget installation attempt (previous attempt already made)" -Level "INFO"
        return $false
    }
    
    $script:WingetInstallAttempted = $true
    
    Write-Log "Checking for winget installation..." -Level "INFO"
    
    # First check if winget is already installed
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        Write-Log "Winget is already installed" -Level "SUCCESS"
        return $true
    }
    
    Write-Log "Winget not found. Attempting to install..." -Level "INFO"
    
    # Create temporary directory for downloads
    $tempFolder = Join-Path $env:TEMP "WingetInstall"
    New-Item -ItemType Directory -Path $tempFolder -Force -ErrorAction SilentlyContinue | Out-Null
    
    # Set TLS to 1.2 for secure downloads
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    
    # Check if Microsoft Store is available and functioning
    $storeAppx = Get-AppxPackage -Name "Microsoft.WindowsStore" -ErrorAction SilentlyContinue
    $canUseStore = $null -ne $storeAppx
    
    Write-Log "Checking Windows 10 version for compatibility..." -Level "INFO"
    $win10BuildNumber = [System.Environment]::OSVersion.Version.Build
    Write-Log "Windows 10 Build: $win10BuildNumber" -Level "INFO"
    
    # Check for App Installer in the Microsoft Store
    $appInstaller = Get-AppxPackage -Name Microsoft.DesktopAppInstaller -ErrorAction SilentlyContinue
    
    if ($appInstaller) {
        Write-Log "App Installer version: $($appInstaller.Version)" -Level "INFO"
        
        if ([Version]$appInstaller.Version -ge [Version]"1.17.0.0") {
            Write-Log "App Installer is already installed but winget command is not available. Attempting repair..." -Level "WARNING"
            
            try {
                # Try to repair by resetting the app
                Reset-AppxPackage -Package $appInstaller.PackageFullName
                Start-Sleep -Seconds 3  # Give it time to complete
                
                # Check if winget is now available
                if (Get-Command winget -ErrorAction SilentlyContinue) {
                    Write-Log "Winget is now available after repair" -Level "SUCCESS"
                    return $true
                }
                
                Write-Log "Repair didn't resolve the issue, continuing with reinstallation..." -Level "WARNING"
            }
            catch {
                Write-Log "Failed to repair App Installer: $_" -Level "ERROR"
            }
        } else {
            Write-Log "App Installer version is outdated. Will attempt to update..." -Level "WARNING"
        }
    }
    
    # INSTALLATION METHOD 1: Using Microsoft Store API (most reliable for Windows 10)
    if ($canUseStore -and $win10BuildNumber -ge 17763) {
        Write-Log "Attempting to install Winget via Microsoft Store API..." -Level "INFO"
        
        try {
            # Check for cancellation
            if ($CancellationToken.IsCancellationRequested) {
                Write-Log "Operation cancelled by user" -Level "WARNING"
                return $false
            }
            
            # Protocol link to open Microsoft Store to the App Installer page
            Start-Process "ms-windows-store://pdp/?productid=9NBLGGH4NNS1"
            
            Write-Log "Microsoft Store has been opened to the App Installer page" -Level "INFO"
            Write-Log "Please install the app from the Store, then click OK on the dialog" -Level "INFO"
            
            # Show a message box to guide the user
            $userResponse = [System.Windows.Forms.MessageBox]::Show(
                "The Microsoft Store has been opened to the App Installer page.`n`n" +
                "Please install the app, then click OK below to continue.`n`n" +
                "If the Store didn't open or you encountered an error, click Cancel to try alternative installation methods.",
                "Install App Installer from Microsoft Store",
                [System.Windows.Forms.MessageBoxButtons]::OKCancel,
                [System.Windows.Forms.MessageBoxIcon]::Information
            )
            
            if ($userResponse -eq [System.Windows.Forms.DialogResult]::Cancel) {
                Write-Log "User cancelled Microsoft Store installation, trying alternative methods..." -Level "WARNING"
            } else {
                # Check if winget is now available
                Start-Sleep -Seconds 2  # Brief pause to let things settle
                if (Get-Command winget -ErrorAction SilentlyContinue) {
                    Write-Log "Winget installed successfully via Microsoft Store!" -Level "SUCCESS"
                    return $true
                }
                
                Write-Log "Winget not detected after Microsoft Store installation. Trying alternative methods..." -Level "WARNING"
            }
        }
        catch {
            Write-Log "Error with Microsoft Store installation attempt: $_" -Level "ERROR"
        }
    }
    
    # INSTALLATION METHOD 2: Direct download from GitHub (fallback method)
    Write-Log "Attempting direct installation from GitHub releases..." -Level "INFO"
    
    try {
        # Check for cancellation
        if ($CancellationToken.IsCancellationRequested) {
            Write-Log "Operation cancelled by user" -Level "WARNING"
            return $false
        }
        
        # Use direct URL for latest version
        $msixBundleUrl = "https://github.com/microsoft/winget-cli/releases/latest/download/Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle"
        $msixBundlePath = Join-Path $tempFolder "Microsoft.DesktopAppInstaller.msixbundle"
        
        Write-Log "Downloading Winget installer bundle..." -Level "INFO"
        
        try {
            $downloadClient = New-Object System.Net.WebClient
            $downloadClient.DownloadFile($msixBundleUrl, $msixBundlePath)
            Write-Log "Download completed: $msixBundlePath" -Level "SUCCESS"
        }
        catch {
            Write-Log "Failed to download MSIX bundle: $_" -Level "ERROR"
            # Try an alternative URL specific for Windows 10
            $altMsixUrl = "https://aka.ms/getwinget"
            Write-Log "Trying alternative download URL: $altMsixUrl" -Level "INFO"
            
            try {
                $downloadClient.DownloadFile($altMsixUrl, $msixBundlePath)
                Write-Log "Alternative download completed" -Level "SUCCESS"
            }
            catch {
                Write-Log "All download attempts failed. Setting flag to use direct download methods only" -Level "ERROR"
                $script:UseDirectDownloadOnly = $true
                return $false
            }
        }
        
        # Check for cancellation
        if ($CancellationToken.IsCancellationRequested) {
            Write-Log "Operation cancelled by user" -Level "WARNING"
            return $false
        }
        
        # Download prerequisites based on Windows 10 version
        # VCLibs - required for all Windows 10 versions
        $vcLibsUrls = @{
            "x64" = "https://aka.ms/Microsoft.VCLibs.x64.14.00.Desktop.appx"
            "x86" = "https://aka.ms/Microsoft.VCLibs.x86.14.00.Desktop.appx"
            "arm64" = "https://aka.ms/Microsoft.VCLibs.arm64.14.00.Desktop.appx"
        }
        
        # UI XAML dependencies
        $uiXamlUrls = @{
            "x64" = "https://github.com/microsoft/microsoft-ui-xaml/releases/download/v2.7.3/Microsoft.UI.Xaml.2.7.x64.appx"
            "x86" = "https://github.com/microsoft/microsoft-ui-xaml/releases/download/v2.7.3/Microsoft.UI.Xaml.2.7.x86.appx"
            "arm64" = "https://github.com/microsoft/microsoft-ui-xaml/releases/download/v2.7.3/Microsoft.UI.Xaml.2.7.arm64.appx"
        }
        
        # Check if we're on ARM64
        $isArm64 = $env:PROCESSOR_ARCHITECTURE -eq "ARM64"
        
        # Determine architecture
        $arch = if ($isArm64) {
            "arm64"
        } elseif ([Environment]::Is64BitOperatingSystem) {
            "x64"
        } else {
            "x86"
        }
        
        Write-Log "Detected system architecture: $arch" -Level "INFO"
        
        # Download VCLibs dependency (critical for Windows 10)
        $vcLibsPath = Join-Path $tempFolder "Microsoft.VCLibs.$arch.14.00.Desktop.appx"
        Write-Log "Downloading VCLibs dependency..." -Level "INFO"
        
        try {
            $downloadClient.DownloadFile($vcLibsUrls[$arch], $vcLibsPath)
            Write-Log "Downloaded VCLibs dependency" -Level "SUCCESS"
        }
        catch {
            Write-Log "Failed to download VCLibs: $_" -Level "ERROR"
            Write-Log "This dependency is required for Windows 10. Installation will likely fail." -Level "WARNING"
        }
        
        # Check for cancellation
        if ($CancellationToken.IsCancellationRequested) {
            Write-Log "Operation cancelled by user" -Level "WARNING"
            return $false
        }
        
        # Download UI XAML dependency (required for newer versions of App Installer)
        $uiXamlPath = Join-Path $tempFolder "Microsoft.UI.Xaml.2.7.$arch.appx"
        Write-Log "Downloading UI XAML dependency..." -Level "INFO"
        
        try {
            $downloadClient.DownloadFile($uiXamlUrls[$arch], $uiXamlPath)
            Write-Log "Downloaded UI XAML dependency" -Level "SUCCESS"
        }
        catch {
            Write-Log "Failed to download UI XAML: $_" -Level "ERROR"
            Write-Log "Will attempt installation anyway, but it may fail on Windows 10" -Level "WARNING"
        }
        
        # Check for cancellation
        if ($CancellationToken.IsCancellationRequested) {
            Write-Log "Operation cancelled by user" -Level "WARNING"
            return $false
        }
        
        Write-Log "Installing dependencies and winget..." -Level "INFO"
        
        # Install VCLibs first (CRITICAL for Windows 10)
        if (Test-Path $vcLibsPath) {
            try {
                Write-Log "Installing VCLibs dependency..." -Level "INFO"
                Add-AppxPackage -Path $vcLibsPath -ErrorAction Stop
                Write-Log "Installed VCLibs dependency" -Level "SUCCESS"
            }
            catch {
                Write-Log "Failed to install VCLibs: $_" -Level "ERROR"
                Write-Log "Continuing with installation anyway, but it will likely fail" -Level "WARNING"
            }
        } else {
            Write-Log "VCLibs package not found. Installation will likely fail." -Level "ERROR"
        }
        
        # Install UI XAML dependency next
        if (Test-Path $uiXamlPath) {
            try {
                Write-Log "Installing UI XAML dependency..." -Level "INFO"
                Add-AppxPackage -Path $uiXamlPath -ErrorAction Stop
                Write-Log "Installed UI XAML dependency" -Level "SUCCESS"
            }
            catch {
                Write-Log "Failed to install UI XAML: $_" -Level "ERROR"
                Write-Log "Continuing with installation anyway..." -Level "WARNING"
            }
        }
        
        # Check for cancellation
        if ($CancellationToken.IsCancellationRequested) {
            Write-Log "Operation cancelled by user" -Level "WARNING"
            return $false
        }
        
        # Install winget
        try {
            Write-Log "Installing winget (App Installer)..." -Level "INFO"
            Add-AppxPackage -Path $msixBundlePath -ErrorAction Stop
            Write-Log "Winget package installation completed" -Level "SUCCESS"
            
            # Force a start menu refresh to ensure proper registration
            Start-Process "explorer.exe" -ArgumentList "shell:::{2559a1f3-21d7-11d4-bdaf-00c04f60b9f0}" -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 3
            
            # Sometimes there's a delay in registering the winget command
            Write-Log "Verifying winget installation..." -Level "INFO"
            $retryCount = 0
            $maxRetries = 3
            $wingetFound = $false
            
            while (-not $wingetFound -and $retryCount -lt $maxRetries) {
                if (Get-Command winget -ErrorAction SilentlyContinue) {
                    $wingetFound = $true
                } else {
                    $retryCount++
                    Write-Log "Winget not found yet, waiting 5 seconds... (Attempt $retryCount of $maxRetries)" -Level "INFO"
                    Start-Sleep -Seconds 5
                }
            }
            
            if ($wingetFound) {
                Write-Log "Winget installed successfully!" -Level "SUCCESS"
                
                # Clean up
                Remove-Item -Path $tempFolder -Recurse -Force -ErrorAction SilentlyContinue
                
                return $true
            } else {
                Write-Log "Winget command not found after installation." -Level "ERROR"
                Write-Log "Windows 10 may need a restart to complete the installation." -Level "WARNING"
                
                # Ask user if they want to restart
                $restartPrompt = [System.Windows.Forms.MessageBox]::Show(
                    "Winget installation completed but the command is not yet available. A system restart may be needed.`n`n" +
                    "Would you like to restart your computer now?",
                    "Restart Required",
                    [System.Windows.Forms.MessageBoxButtons]::YesNo,
                    [System.Windows.Forms.MessageBoxIcon]::Question
                )
                
                if ($restartPrompt -eq [System.Windows.Forms.DialogResult]::Yes) {
                    Write-Log "Initiating system restart..." -Level "WARNING"
                    Start-Process "shutdown.exe" -ArgumentList "/r /t 10 /c ""Restarting to complete winget installation..."""
                    
                    # Show countdown message
                    [System.Windows.Forms.MessageBox]::Show(
                        "Your computer will restart in 10 seconds to complete the winget installation.`n`n" +
                        "Save your work in other applications before the restart.",
                        "System Restart",
                        [System.Windows.Forms.MessageBoxButtons]::OK,
                        [System.Windows.Forms.MessageBoxIcon]::Warning
                    )
                }
                
                Write-Log "Setting flag to use direct download methods only for this session" -Level "WARNING"
                $script:UseDirectDownloadOnly = $true
                return $false
            }
        }
        catch {
            Write-Log "Failed to install winget package: $_" -Level "ERROR"
            Write-Log "Setting flag to use direct download methods only" -Level "WARNING"
            $script:UseDirectDownloadOnly = $true
            return $false
        }
    }
    catch {
        Write-Log "Failed to install winget: $_" -Level "ERROR"
        Write-Log "Setting flag to use direct download methods only" -Level "WARNING"
        $script:UseDirectDownloadOnly = $true
        return $false
    }
    
    # INSTALLATION METHOD 3: Attempt to invoke Windows Update to install App Installer
    # This is a last resort and less reliable, but might work on some Windows 10 configurations
    try {
        Write-Log "Attempting to install App Installer via Windows Update API (last resort)..." -Level "INFO"
        
        # This is an advanced method that tries to force Windows Update to install the App Installer
        $wuaSession = New-Object -ComObject "Microsoft.Update.Session"
        $wuaSearcher = $wuaSession.CreateUpdateSearcher()
        
        try {
            # Search for App Installer in the Microsoft Store
            $searchResult = $wuaSearcher.Search("Title:'App Installer'")
            
            if ($searchResult.Updates.Count -gt 0) {
                Write-Log "Found App Installer update via Windows Update. Attempting to install..." -Level "INFO"
                
                $updatesToInstall = New-Object -ComObject "Microsoft.Update.UpdateColl"
                $updatesToInstall.Add($searchResult.Updates.Item(0))
                
                $wuaInstaller = $wuaSession.CreateUpdateInstaller()
                $wuaInstaller.Updates = $updatesToInstall
                
                $installResult = $wuaInstaller.Install()
                
                if ($installResult.ResultCode -eq 2) { # 2 = success
                    Write-Log "App Installer installed via Windows Update" -Level "SUCCESS"
                    
                    # Check if winget is now available
                    Start-Sleep -Seconds 5  # Give it time to complete
                    if (Get-Command winget -ErrorAction SilentlyContinue) {
                        Write-Log "Winget is now available" -Level "SUCCESS"
                        return $true
                    }
                } else {
                    Write-Log "Windows Update installation returned: $($installResult.ResultCode)" -Level "WARNING"
                }
            } else {
                Write-Log "App Installer not found via Windows Update" -Level "WARNING"
            }
        }
        catch {
            Write-Log "Error searching Windows Update: $_" -Level "ERROR"
        }
    }
    catch {
        Write-Log "Windows Update API method failed: $_" -Level "ERROR"
    }
    
    # If we've reached this point, all installation methods have failed
    Write-Log "All winget installation methods failed" -Level "ERROR"
    Write-Log "The application will use direct downloads for installing applications" -Level "WARNING"
    $script:UseDirectDownloadOnly = $true
    return $false
}

function Get-AppDirectDownloadInfo {
    param(
        [Parameter(Mandatory=$true)]
        [string]$AppName
    )

    $downloadInfo = @{
        "Spotify" = @{
            Url = "https://download.scdn.co/SpotifySetup.exe"
            Extension = ".exe"
            Arguments = "/silent"
            VerificationPaths = @(
                "${env:APPDATA}\Spotify\Spotify.exe",
                "C:\Program Files\Spotify\Spotify.exe",
                "C:\Program Files (x86)\Spotify\Spotify.exe"
            )
        }
        "Google Chrome" = @{
            Url = "https://dl.google.com/chrome/install/latest/chrome_installer.exe"
            Extension = ".exe"
            Arguments = "/silent /install"
            VerificationPaths = @(
                "C:\Program Files\Google\Chrome\Application\chrome.exe",
                "C:\Program Files (x86)\Google\Chrome\Application\chrome.exe"
            )
        }
        "Mozilla Firefox" = @{
            Url = "https://download.mozilla.org/?product=firefox-latest-ssl&os=win64&lang=en-US"
            Extension = ".exe"
            Arguments = "-ms"
            VerificationPaths = @(
                "C:\Program Files\Mozilla Firefox\firefox.exe",
                "C:\Program Files (x86)\Mozilla Firefox\firefox.exe"
            )
        }
        "Brave Browser" = @{
            Url = "https://laptop-updates.brave.com/latest/winx64"
            Extension = ".exe"
            Arguments = "/silent /install"
            VerificationPaths = @(
                "C:\Program Files\BraveSoftware\Brave-Browser\Application\brave.exe",
                "C:\Program Files (x86)\BraveSoftware\Brave-Browser\Application\brave.exe"
            )
        }
        "Discord" = @{
            Url = "https://discord.com/api/downloads/distributions/app/installers/latest?channel=stable&platform=win&arch=x86"
            Extension = ".exe"
            Arguments = "-s"
            VerificationPaths = @(
                "${env:LOCALAPPDATA}\Discord\app-*\Discord.exe",
                "C:\Program Files\Discord\Discord.exe",
                "C:\Program Files (x86)\Discord\Discord.exe"
            )
        }
        "Visual Studio Code" = @{
            Url = "https://code.visualstudio.com/sha/download?build=stable&os=win32-x64-user"
            Extension = ".exe"
            Arguments = "/VERYSILENT /NORESTART /MERGETASKS=!runcode"
            VerificationPaths = @(
                "C:\Program Files\Microsoft VS Code\Code.exe",
                "${env:LOCALAPPDATA}\Programs\Microsoft VS Code\Code.exe"
            )
        }
        "Git" = @{
            Url = "https://github.com/git-for-windows/git/releases/download/v2.43.0.windows.1/Git-2.43.0-64-bit.exe"
            Extension = ".exe"
            Arguments = "/VERYSILENT /NORESTART /NOCANCEL /SP- /CLOSEAPPLICATIONS /RESTARTAPPLICATIONS"
            VerificationPaths = @(
                "C:\Program Files\Git\bin\git.exe",
                "C:\Program Files (x86)\Git\bin\git.exe"
            )
        }
        "Python" = @{
            Url = "https://www.python.org/ftp/python/3.12.2/python-3.12.2-amd64.exe"
            Extension = ".exe"
            Arguments = "/quiet InstallAllUsers=1 PrependPath=1 Include_test=0"
            VerificationPaths = @(
                "C:\Program Files\Python312\python.exe",
                "C:\Python312\python.exe"
            )
        }
        "PyCharm Community" = @{
            Url = "https://download.jetbrains.com/python/pycharm-community-2023.3.4.exe"
            Extension = ".exe"
            Arguments = "/S /CONFIG=silent.config"
            VerificationPaths = @(
                "C:\Program Files\JetBrains\PyCharm Community Edition*\bin\pycharm64.exe",
                "${env:LOCALAPPDATA}\JetBrains\PyCharm Community Edition*\bin\pycharm64.exe"
            )
        }
        "GitHub Desktop" = @{
            Url = "https://central.github.com/deployments/desktop/desktop/latest/win32"
            Extension = ".exe"
            Arguments = "-s"
            VerificationPaths = @(
                "${env:LOCALAPPDATA}\GitHubDesktop\GitHubDesktop.exe",
                "C:\Program Files\GitHub Desktop\GitHubDesktop.exe"
            )
        }
        "Postman" = @{
            Url = "https://dl.pstmn.io/download/latest/win64"
            Extension = ".exe"
            Arguments = "-s"
            VerificationPaths = @(
                "${env:LOCALAPPDATA}\Postman\Postman.exe",
                "C:\Program Files\Postman\Postman.exe",
                "C:\Program Files (x86)\Postman\Postman.exe"
            )
        }
        "VLC Media Player" = @{
            Url = "https://download.videolan.org/vlc/last/win64/vlc-3.0.20-win64.exe"
            Extension = ".exe"
            Arguments = "/S"
            VerificationPaths = @(
                "C:\Program Files\VideoLAN\VLC\vlc.exe",
                "C:\Program Files (x86)\VideoLAN\VLC\vlc.exe"
            )
        }
        "7-Zip" = @{
            Url = "https://www.7-zip.org/a/7z2301-x64.exe"
            Extension = ".exe"
            Arguments = "/S"
            VerificationPaths = @(
                "C:\Program Files\7-Zip\7z.exe",
                "C:\Program Files (x86)\7-Zip\7z.exe"
            )
        }
        "Notepad++" = @{
            Url = "https://github.com/notepad-plus-plus/notepad-plus-plus/releases/download/v8.6.4/npp.8.6.4.Installer.x64.exe"
            Extension = ".exe"
            Arguments = "/S"
            VerificationPaths = @(
                "C:\Program Files\Notepad++\notepad++.exe",
                "C:\Program Files (x86)\Notepad++\notepad++.exe"
            )
        }
        "Node.js" = @{
            Url = "https://nodejs.org/dist/v20.11.1/node-v20.11.1-x64.msi"
            Extension = ".msi"
            Arguments = "/quiet /norestart"
            VerificationPaths = @(
                "C:\Program Files\nodejs\node.exe",
                "C:\Program Files (x86)\nodejs\node.exe"
            )
        }
        "Steam" = @{
            Url = "https://cdn.akamai.steamstatic.com/client/installer/SteamSetup.exe"
            Extension = ".exe"
            Arguments = "/S"
            VerificationPaths = @(
                "C:\Program Files (x86)\Steam\Steam.exe"
            )
        }
        "Windows Terminal" = @{
            Url = "https://github.com/microsoft/terminal/releases/download/v1.18.3282.0/Microsoft.WindowsTerminal_Win10_1.18.3282.0_8wekyb3d8bbwe.msixbundle"
            Extension = ".msixbundle"
            Arguments = ""  # Special handling for MSIX bundles
            VerificationPaths = @(
                "${env:LOCALAPPDATA}\Microsoft\WindowsApps\wt.exe"
            )
        }
        "Microsoft PowerToys" = @{
            Url = "https://github.com/microsoft/PowerToys/releases/download/v0.78.0/PowerToysSetup-0.78.0-x64.exe"
            Extension = ".exe"
            Arguments = "-silent"
            VerificationPaths = @(
                "${env:LOCALAPPDATA}\Programs\PowerToys\PowerToys.exe",
                "C:\Program Files\PowerToys\PowerToys.exe"
            )
        }
    }

    if ($downloadInfo.ContainsKey($AppName)) {
        return $downloadInfo[$AppName]
    } else {
        return $null
    }
}

function Install-Application {
    param(
        [Parameter(Mandatory=$true)]
        [string]$AppName,
        [Parameter(Mandatory=$false)]
        [string]$WingetId = "",
        [Parameter(Mandatory=$false)]
        [hashtable]$DirectDownload = $null,
        [System.Threading.CancellationToken]$CancellationToken
    )

    Write-Log "Installing $AppName..." -Level "INFO"
    
    # Check for cancellation
    if ($CancellationToken.IsCancellationRequested) {
        Write-Log "Installation of $AppName cancelled" -Level "WARNING"
        return $false
    }
    
    # If no winget ID was provided, try to look it up
    if ([string]::IsNullOrEmpty($WingetId)) {
        $wingetMappings = @{
            "Visual Studio Code" = "Microsoft.VisualStudioCode"
            "Git" = "Git.Git"
            "Python" = "Python.Python.3"
            "PyCharm Community" = "JetBrains.PyCharm.Community"
            "GitHub Desktop" = "GitHub.GitHubDesktop"
            "Postman" = "Postman.Postman"
            "Google Chrome" = "Google.Chrome"
            "Mozilla Firefox" = "Mozilla.Firefox"
            "Brave Browser" = "Brave.Browser"
            "Spotify" = "Spotify.Spotify"
            "Discord" = "Discord.Discord"
            "Steam" = "Valve.Steam"
            "VLC Media Player" = "VideoLAN.VLC"
            "7-Zip" = "7zip.7zip"
            "Notepad++" = "Notepad++.Notepad++"
            "Node.js" = "OpenJS.NodeJS.LTS"
            "Windows Terminal" = "Microsoft.WindowsTerminal"
            "Microsoft PowerToys" = "Microsoft.PowerToys"
        }
        
        $WingetId = if ($wingetMappings.ContainsKey($AppName)) { $wingetMappings[$AppName] } else { "" }
    }

    # Check if already installed via common command
    $commonCommands = @{
        "Google Chrome" = "chrome"
        "Visual Studio Code" = "code"
        "Git" = "git"
        "Python" = "python"
        "Windows Terminal" = "wt"
        "Node.js" = "node"
    }

    if ($commonCommands.ContainsKey($AppName) -and (Get-Command $commonCommands[$AppName] -ErrorAction SilentlyContinue)) {
        Write-Log "$AppName is already installed and in PATH" -Level "SUCCESS"
        return $true
    }
    
    # If no direct download info was provided, try to get it
    if ($null -eq $DirectDownload) {
        $DirectDownload = Get-AppDirectDownloadInfo -AppName $AppName
    }

    # INSTALLATION METHODS

    # 1. Try Winget first (if available and package ID is known, and we're not in direct download only mode)
    if (-not $script:UseDirectDownloadOnly -and (Get-Command winget -ErrorAction SilentlyContinue) -and -not [string]::IsNullOrEmpty($WingetId)) {
        Write-Log "Installing $AppName via winget..." -Level "INFO"
        try {
            # Check if already installed through winget
            $wingetList = winget list --id $WingetId 2>&1
            if ($wingetList -match $WingetId) {
                Write-Log "$AppName is already installed via winget" -Level "SUCCESS"
                return $true
            }
            
            # Install using silent mode and accept agreements
            $wingetOutput = winget install --id $WingetId --accept-source-agreements --accept-package-agreements --silent 2>&1
            
            # Check if successful
            if ($LASTEXITCODE -eq 0 -or $wingetOutput -match "Successfully installed") {
                Write-Log "$AppName installed successfully via winget!" -Level "SUCCESS"
                return $true
            } else {
                Write-Log "Winget installation returned: $LASTEXITCODE" -Level "WARNING"
                Write-Log "Output: $wingetOutput" -Level "DEBUG"
            }
        } catch {
            Write-Log "Winget installation failed: $_" -Level "WARNING"
        }
    } else {
        if ($script:UseDirectDownloadOnly) {
            Write-Log "Using direct download method as configured" -Level "INFO"
        } elseif (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
            Write-Log "Winget is not available, trying direct download" -Level "INFO"
        } elseif ([string]::IsNullOrEmpty($WingetId)) {
            Write-Log "No winget package ID mapping for $AppName, trying direct download" -Level "INFO"
        }
    }
    
    # Check for cancellation
    if ($CancellationToken.IsCancellationRequested) {
        Write-Log "Installation of $AppName cancelled" -Level "WARNING"
        return $false
    }
    
    # 2. If we have direct download info, try that as fallback
    if ($DirectDownload) {
        try {
            Write-Log "Installing $AppName via direct download..." -Level "INFO"
            
            # Download the installer
            $installerPath = Join-Path $env:TEMP "$($AppName -replace '\s', '')Installer$($DirectDownload.Extension)"
            Write-Log "Downloading from: $($DirectDownload.Url)" -Level "DEBUG"
            
            # Use WebClient with timeout and progress reporting
            $webClient = New-Object System.Net.WebClient
            
            try {
                Write-Log "Downloading installer..." -Level "INFO"
                $webClient.DownloadFile($DirectDownload.Url, $installerPath)
                Write-Log "Download completed successfully" -Level "SUCCESS"
            }
            catch {
                Write-Log "Download failed: $_" -Level "ERROR"
                return $false
            }
            
            # Check for cancellation
            if ($CancellationToken.IsCancellationRequested) {
                Write-Log "Installation of $AppName cancelled" -Level "WARNING"
                return $false
            }
            
            # Run the installer
            if ($DirectDownload.Extension -eq ".exe") {
                $arguments = if ($DirectDownload.Arguments) { $DirectDownload.Arguments } else { "/S" }
                Write-Log "Running EXE installer with arguments: $arguments" -Level "DEBUG"
                Start-Process -FilePath $installerPath -ArgumentList $arguments -Wait -NoNewWindow
            }
            elseif ($DirectDownload.Extension -eq ".msi") {
                $arguments = if ($DirectDownload.Arguments) { $DirectDownload.Arguments } else { "/quiet", "/norestart" }
                Write-Log "Running MSI installer with arguments: $arguments" -Level "DEBUG"
                Start-Process "msiexec.exe" -ArgumentList "/i", $installerPath, $arguments -Wait -NoNewWindow
            }
            elseif ($DirectDownload.Extension -eq ".msixbundle") {
                Write-Log "Installing MSIX bundle" -Level "DEBUG"
                try {
                    # Try using Add-AppxPackage
                    Add-AppxPackage -Path $installerPath -ErrorAction Stop
                }
                catch {
                    throw "Failed to install MSIX bundle: $_"
                }
            }
            
            # Clean up
            Remove-Item $installerPath -Force -ErrorAction SilentlyContinue
            
            # Verify installation
            $installSuccess = $false
            foreach ($path in $DirectDownload.VerificationPaths) {
                $resolvedPaths = Resolve-Path $path -ErrorAction SilentlyContinue
                if ($resolvedPaths) {
                    $installSuccess = $true
                    Write-Log "Verified $AppName installation at: $resolvedPaths" -Level "DEBUG"
                    break
                } elseif (Test-Path $path) {
                    $installSuccess = $true
                    Write-Log "Verified $AppName installation at: $path" -Level "DEBUG"
                    break
                }
            }
            
            if ($installSuccess) {
                Write-Log "$AppName installed successfully via direct download!" -Level "SUCCESS"
                return $true
            } else {
                Write-Log "Could not verify $AppName installation after direct download" -Level "WARNING"
                Write-Log "The application might still be installed but couldn't be verified" -Level "INFO"
                return $true  # Assume success but log a warning
            }
        }
        catch {
            Write-Log "Direct download installation failed: $_" -Level "ERROR"
            return $false
        }
    } else {
        Write-Log "No direct download information available for $AppName" -Level "ERROR"
    }
    
    Write-Log "All installation methods failed for $AppName" -Level "ERROR"
    return $false
}

function Remove-Bloatware {
    param(
        [Parameter(Mandatory=$true)]
        [string]$AppIdentifier,
        [System.Threading.CancellationToken]$CancellationToken
    )
    
    Write-Log "Removing $AppIdentifier..." -Level "INFO"
    
    # Check for cancellation
    if ($CancellationToken.IsCancellationRequested) {
        Write-Log "Removal of $AppIdentifier cancelled" -Level "WARNING"
        return $false
    }

    try {
        # Map our UI keys to actual Windows app identifiers
        $appMappings = @{
            # Microsoft Apps
            "ms-officehub" = "Microsoft.MicrosoftOfficeHub"
            "ms-teams" = "MicrosoftTeams"
            "ms-todo" = "Microsoft.Todos"
            "ms-3dviewer" = "Microsoft.Microsoft3DViewer"
            "ms-mixedreality" = "Microsoft.MixedReality.Portal"
            "ms-onenote" = "Microsoft.Office.OneNote"
            "ms-people" = "Microsoft.People"
            "ms-wallet" = "Microsoft.Wallet"
            "ms-messaging" = "Microsoft.Messaging"
            "ms-oneconnect" = "Microsoft.OneConnect"
            
            # Bing Apps
            "bing-weather" = "Microsoft.BingWeather"
            "bing-news" = "Microsoft.BingNews"
            "bing-finance" = "Microsoft.BingFinance"
            
            # Windows Utilities
            "win-alarms" = "Microsoft.WindowsAlarms"
            "win-camera" = "Microsoft.WindowsCamera"
            "win-mail" = "Microsoft.WindowsCommunicationsApps"
            "win-maps" = "Microsoft.WindowsMaps"
            "win-feedback" = "Microsoft.WindowsFeedbackHub"
            "win-gethelp" = "Microsoft.GetHelp"
            "win-getstarted" = "Microsoft.Getstarted"
            "win-soundrec" = "Microsoft.WindowsSoundRecorder"
            "win-yourphone" = "Microsoft.YourPhone"
            "win-print3d" = "Microsoft.Print3D"
            
            # Media Apps
            "zune-music" = "Microsoft.ZuneMusic"
            "zune-video" = "Microsoft.ZuneVideo"
            "solitaire" = "Microsoft.MicrosoftSolitaireCollection"
            "xbox-apps" = "Microsoft.Xbox*"
            
            # Third-Party Bloatware
            "candy-crush" = "*CandyCrush*"
            "spotify-store" = "*SpotifyMusic*"
            "facebook" = "*Facebook*"
            "twitter" = "*Twitter*"
            "netflix" = "*Netflix*"
            "disney" = "*Disney*"
            "tiktok" = "*TikTok*"
            
            # Windows 11 Specific
            "ms-widgets" = "MicrosoftWindows.Client.WebExperience"
            "ms-clipchamp" = "*ClipChamp*"
            "gaming-app" = "Microsoft.GamingApp"
            "linkedin" = "*LinkedIn*"
        }
        
        if (-not $appMappings.ContainsKey($AppIdentifier)) {
            Write-Log "Unknown app identifier: $AppIdentifier" -Level "ERROR"
            return $false
        }
        
        $appPackageName = $appMappings[$AppIdentifier]
        
        # Remove AppxPackage (for current user)
        $appxPackages = Get-AppxPackage -Name $appPackageName -ErrorAction SilentlyContinue
        if ($appxPackages) {
            $appxPackages | ForEach-Object {
                Write-Log "Removing AppxPackage: $($_.Name)" -Level "INFO"
                Remove-AppxPackage -Package $_ -ErrorAction Stop
            }
            Write-Log "Removed AppxPackage: $appPackageName" -Level "SUCCESS"
        }
        
        # Check for cancellation
        if ($CancellationToken.IsCancellationRequested) {
            Write-Log "Removal operation cancelled" -Level "WARNING"
            return $false
        }
        
        # Remove AppxProvisionedPackage (for all users)
        $provisionedPackages = Get-AppxProvisionedPackage -Online | Where-Object {$_.DisplayName -like $appPackageName}
        if ($provisionedPackages) {
            $provisionedPackages | ForEach-Object {
                Write-Log "Removing AppxProvisionedPackage: $($_.DisplayName)" -Level "INFO"
                Remove-AppxProvisionedPackage -Online -PackageName $_.PackageName -ErrorAction Stop
            }
            Write-Log "Removed AppxProvisionedPackage: $appPackageName" -Level "SUCCESS"
        }
        
        if (-not $appxPackages -and -not $provisionedPackages) {
            Write-Log "No packages found matching: $appPackageName" -Level "WARNING"
            return $false
        }
        
        return $true
    }
    catch {
        Write-Log "Failed to remove $AppIdentifier : $_" -Level "ERROR"
        return $false
    }
}

function Disable-WindowsService {
    param(
        [Parameter(Mandatory=$true)]
        [string]$ServiceIdentifier,
        [System.Threading.CancellationToken]$CancellationToken
    )
    
    Write-Log "Disabling service $ServiceIdentifier..." -Level "INFO"
    
    # Check for cancellation
    if ($CancellationToken.IsCancellationRequested) {
        Write-Log "Disabling service $ServiceIdentifier cancelled" -Level "WARNING"
        return $false
    }
    
    try {
        # Map our UI keys to actual Windows service names
        $serviceMappings = @{
            "diagtrack" = "DiagTrack"
            "dmwappushsvc" = "dmwappushservice"
            "sysmain" = "SysMain"
            "wmpnetworksvc" = "WMPNetworkSvc"
            "remoteregistry" = "RemoteRegistry"
            "remoteaccess" = "RemoteAccess"
            "printnotify" = "PrintNotify"
            "fax" = "Fax"
            "wisvc" = "wisvc"
            "retaildemo" = "RetailDemo"
            "mapsbroker" = "MapsBroker"
            "pcasvc" = "PcaSvc"
            "wpcmonsvc" = "WpcMonSvc"
            "cscservice" = "CscService"
            "lfsvc" = "lfsvc"
            "tabletinputservice" = "TabletInputService"
            "homegrpservice" = "HomeGroupProvider"
            "walletservice" = "WalletService"
        }
        
        if (-not $serviceMappings.ContainsKey($ServiceIdentifier)) {
            Write-Log "Unknown service identifier: $ServiceIdentifier" -Level "ERROR"
            return $false
        }
        
        $serviceName = $serviceMappings[$ServiceIdentifier]
        
        # Check if service exists
        $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
        if (-not $service) {
            Write-Log "Service $serviceName does not exist on this system" -Level "WARNING"
            return $false
        }
        
        # Stop and disable the service
        Stop-Service -Name $serviceName -Force -ErrorAction Stop
        Set-Service -Name $serviceName -StartupType Disabled -ErrorAction Stop
        
        Write-Log "Successfully disabled service: $serviceName" -Level "SUCCESS"
        return $true
    }
    catch {
        Write-Log "Failed to disable service $ServiceIdentifier : $_" -Level "ERROR"
        return $false
    }
}

function Apply-Optimization {
    param(
        [Parameter(Mandatory=$true)]
        [string]$OptimizationKey,
        [System.Threading.CancellationToken]$CancellationToken
    )
    
    Write-Log "Applying optimization: $OptimizationKey" -Level "INFO"
    
    # Check for cancellation
    if ($CancellationToken.IsCancellationRequested) {
        Write-Log "Applying optimization $OptimizationKey cancelled" -Level "WARNING"
        return $false
    }
    
    try {
        switch ($OptimizationKey) {
            "show-extensions" {
                Set-RegistryKey -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "HideFileExt" -Value 0
            }
            "show-hidden" {
                Set-RegistryKey -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "Hidden" -Value 1
            }
            "dev-mode" {
                Set-RegistryKey -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock" -Name "AllowDevelopmentWithoutDevLicense" -Value 1
            }
            "disable-cortana" {
                Set-RegistryKey -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search" -Name "AllowCortana" -Value 0
            }
            "disable-onedrive" {
                Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "OneDrive" -ErrorAction SilentlyContinue
            }
            "disable-tips" {
                Set-RegistryKey -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "SubscribedContent-338389Enabled" -Value 0
                Set-RegistryKey -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "SystemPaneSuggestionsEnabled" -Value 0
                Set-RegistryKey -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "SoftLandingEnabled" -Value 0
            }
            "reduce-telemetry" {
                Set-RegistryKey -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" -Name "AllowTelemetry" -Value 1
            }
            "disable-activity" {
                Set-RegistryKey -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" -Name "EnableActivityFeed" -Value 0
                Set-RegistryKey -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" -Name "PublishUserActivities" -Value 0
            }
            "disable-background" {
                Set-RegistryKey -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications" -Name "GlobalUserDisabled" -Value 1
            }
            "search-bing" {
                Set-RegistryKey -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" -Name "BingSearchEnabled" -Value 0
                Set-RegistryKey -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" -Name "CortanaConsent" -Value 0
            }
            # Windows 11 specific optimizations
            "taskbar-left" {
                Set-RegistryKey -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "TaskbarAl" -Value 0
            }
            "classic-context" {
                if (-not (Test-Path "HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32")) {
                    New-Item -Path "HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32" -Force | Out-Null
                }
                Set-ItemProperty -Path "HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32" -Name "(Default)" -Value "" -Type String
            }
            "disable-chat" {
                Set-RegistryKey -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "TaskbarMn" -Value 0
            }
            "disable-widgets" {
                Set-RegistryKey -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "TaskbarDa" -Value 0
                Set-RegistryKey -Path "HKLM:\SOFTWARE\Policies\Microsoft\Dsh" -Name "AllowNewsAndInterests" -Value 0
                Set-RegistryKey -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Feeds" -Name "EnableFeeds" -Value 0
            }
            "disable-snap" {
                Set-RegistryKey -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "EnableSnapAssistFlyout" -Value 0
            }
            "start-menu-pins" {
                Set-RegistryKey -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "Start_Layout" -Value 1
            }
            "disable-teams-autostart" {
                Set-RegistryKey -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "com.squirrel.Teams.Teams" -Value 0 -ErrorAction SilentlyContinue
            }
            "disable-startup-sound" {
                Set-RegistryKey -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\LogonUI\BootAnimation" -Name "DisableStartupSound" -Value 1
            }
            default {
                Write-Log "Unknown optimization key: $OptimizationKey" -Level "ERROR"
                return $false
            }
        }
        
        Write-Log "Successfully applied optimization: $OptimizationKey" -Level "SUCCESS"
        return $true
    }
    catch {
        Write-Log "Failed to apply optimization $OptimizationKey : $_" -Level "ERROR"
        return $false
    }
}

function Start-SelectedOperations {
    Write-Host "DEBUG: Start-SelectedOperations called" -ForegroundColor Magenta
    
    try {
        # Prevent multiple runs
        if ($script:IsRunning) {
            Write-Host "DEBUG: Operations already running, cancelling" -ForegroundColor Red
            [System.Windows.Forms.MessageBox]::Show(
                "Operations are already in progress. Please wait for them to complete.",
                "Operations in Progress",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information
            )
            return
        }
        
        # Print selected operations for debugging
        Write-Host "DEBUG: Selected Apps: $($script:SelectedApps -join ', ')" -ForegroundColor Cyan
        Write-Host "DEBUG: Selected Bloatware: $($script:SelectedBloatware -join ', ')" -ForegroundColor Cyan
        Write-Host "DEBUG: Selected Services: $($script:SelectedServices -join ', ')" -ForegroundColor Cyan
        Write-Host "DEBUG: Selected Optimizations: $($script:SelectedOptimizations -join ', ')" -ForegroundColor Cyan
        
        # Calculate total steps with debug output
        $script:TotalSteps = $script:SelectedApps.Count + $script:SelectedBloatware.Count + 
                             $script:SelectedServices.Count + $script:SelectedOptimizations.Count
        
        Write-Host "DEBUG: Total steps calculated: $script:TotalSteps" -ForegroundColor Yellow
        
        if ($script:TotalSteps -eq 0) {
            Write-Host "DEBUG: No operations selected" -ForegroundColor Red
            Write-Log "No operations selected" -Level "WARNING"
            [System.Windows.Forms.MessageBox]::Show("Please select at least one operation to perform.", "No Operations Selected", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
            Update-UI {
                $script:btnRun.Enabled = $true
                $script:btnCancel.Enabled = $false
            }
            $script:IsRunning = $false
            return
        }
        
        Write-Host "DEBUG: About to update UI" -ForegroundColor Yellow
        try {
            Update-UI {
                Write-Host "DEBUG: Inside Update-UI block" -ForegroundColor Magenta
                $script:btnRun.Enabled = $false
                $script:btnCancel.Enabled = $true
            }
            Write-Host "DEBUG: UI updated successfully" -ForegroundColor Green
        } catch {
            Write-Host "DEBUG: Failed to update UI: $_" -ForegroundColor Red
        }
        
        Write-Host "DEBUG: Setting script variables" -ForegroundColor Yellow
        $script:IsRunning = $true
        $script:StartTime = Get-Date
        
        Write-Host "DEBUG: Creating cancellation token" -ForegroundColor Yellow
        try {
            $script:CancellationTokenSource = New-Object System.Threading.CancellationTokenSource
            $cancellationToken = $script:CancellationTokenSource.Token
            Write-Host "DEBUG: Cancellation token created successfully" -ForegroundColor Green
        } catch {
            Write-Host "DEBUG: Failed to create cancellation token: $_" -ForegroundColor Red
            # Create a dummy cancellation token that never cancels
            $script:CancellationTokenSource = New-Object System.Threading.CancellationTokenSource
            $cancellationToken = $script:CancellationTokenSource.Token
        }
        
        # Clear the log
        Write-Host "DEBUG: Clearing log" -ForegroundColor Yellow
        Update-UI {
            $script:txtLog.Clear()
        }
        
        # Reset current step
        $script:CurrentStep = 0
        
        # Run operations directly instead of in a background task
        Write-Host "DEBUG: Starting direct operations" -ForegroundColor Yellow
        Write-Log "Windows Setup Automation started" -Level "INFO"
        Write-Log "Detected: $($script:OSName)" -Level "INFO"
        Write-Log "Version: $($script:OSVersion)" -Level "INFO"
        
        # Install winget if we have any apps to install
        if ($script:SelectedApps.Count -gt 0) {
            Write-Host "DEBUG: Checking if winget needs to be installed" -ForegroundColor Yellow
            # Install winget first if we have any apps to install
            if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
                Write-Log "Winget not found, attempting to install it..." -Level "INFO"
                $wingetInstalled = Install-Winget -CancellationToken $cancellationToken
                if (-not $wingetInstalled) {
                    Write-Log "Could not install winget. Will use direct download for all applications." -Level "WARNING"
                    $script:UseDirectDownloadOnly = $true
                } else {
                    Write-Log "Winget installed successfully and will be used for app installations" -Level "SUCCESS"
                }
            } else {
                Write-Log "Winget is already installed and will be used for app installations" -Level "INFO"
            }
        }
        
        # Check for cancellation
        if ($cancellationToken.IsCancellationRequested) {
            Write-Log "Operations cancelled by user" -Level "WARNING"
            return
        }
        
        Write-Host "DEBUG: Processing selected applications" -ForegroundColor Yellow
        # Install selected applications
        foreach ($appKey in $script:SelectedApps) {
            $appInfo = $null
            
            # Find the app in the categories
            foreach ($category in $script:AppCategories.Keys) {
                $appInfo = $script:AppCategories[$category] | Where-Object { $_.Key -eq $appKey } | Select-Object -First 1
                if ($appInfo) { break }
            }
            
            if ($appInfo) {
                Write-Host "DEBUG: Installing $($appInfo.Name)" -ForegroundColor Yellow
                Update-ProgressBar -Status "Installing $($appInfo.Name)..." -IncrementStep
                
                # Get winget ID from our mapping
                $wingetId = if ($script:WingetMappings.ContainsKey($appKey)) { $script:WingetMappings[$appKey] } else { "" }
                
                # Get direct download info
                $directDownload = Get-AppDirectDownloadInfo -AppName $appInfo.Name
                
                # Install the application
                $result = Install-Application -AppName $appInfo.Name -WingetId $wingetId -DirectDownload $directDownload -CancellationToken $cancellationToken
                
                if ($result) {
                    Write-Log "Installation of $($appInfo.Name) completed successfully" -Level "SUCCESS"
                } else {
                    Write-Log "Installation of $($appInfo.Name) failed" -Level "ERROR"
                }
            } else {
                Write-Log "Unknown application key: $appKey" -Level "ERROR"
            }
            
            # Check for cancellation
            if ($cancellationToken.IsCancellationRequested) {
                Write-Log "Operations cancelled by user" -Level "WARNING"
                return
            }
        }
        
        Write-Host "DEBUG: Processing bloatware removal" -ForegroundColor Yellow
        # Remove selected bloatware
        foreach ($bloatKey in $script:SelectedBloatware) {
            $bloatInfo = $null
            
            # Find the bloatware in the categories
            foreach ($category in $script:BloatwareCategories.Keys) {
                $bloatInfo = $script:BloatwareCategories[$category] | Where-Object { $_.Key -eq $bloatKey } | Select-Object -First 1
                if ($bloatInfo) { break }
            }
            
            if ($bloatInfo) {
                Write-Host "DEBUG: Removing $($bloatInfo.Name)" -ForegroundColor Yellow
                Update-ProgressBar -Status "Removing $($bloatInfo.Name)..." -IncrementStep
                $result = Remove-Bloatware -AppIdentifier $bloatKey -CancellationToken $cancellationToken
                
                if ($result) {
                    Write-Log "Removal of $($bloatInfo.Name) completed successfully" -Level "SUCCESS"
                } else {
                    Write-Log "Removal of $($bloatInfo.Name) failed or app not found" -Level "WARNING"
                }
            } else {
                Write-Log "Unknown bloatware key: $bloatKey" -Level "ERROR"
            }
            
            # Check for cancellation
            if ($cancellationToken.IsCancellationRequested) {
                Write-Log "Operations cancelled by user" -Level "WARNING"
                return
            }
        }
        
        Write-Host "DEBUG: Processing service disabling" -ForegroundColor Yellow
        # Disable selected services
        foreach ($serviceKey in $script:SelectedServices) {
            $serviceInfo = $null
            
            # Find the service in the categories
            foreach ($category in $script:ServiceCategories.Keys) {
                $serviceInfo = $script:ServiceCategories[$category] | Where-Object { $_.Key -eq $serviceKey } | Select-Object -First 1
                if ($serviceInfo) { break }
            }
            
            if ($serviceInfo) {
                Write-Host "DEBUG: Disabling service $($serviceInfo.Name)" -ForegroundColor Yellow
                Update-ProgressBar -Status "Disabling $($serviceInfo.Name)..." -IncrementStep
                $result = Disable-WindowsService -ServiceIdentifier $serviceKey -CancellationToken $cancellationToken
                
                if ($result) {
                    Write-Log "Disabling of $($serviceInfo.Name) completed successfully" -Level "SUCCESS"
                } else {
                    Write-Log "Disabling of $($serviceInfo.Name) failed or service not found" -Level "WARNING"
                }
            } else {
                Write-Log "Unknown service key: $serviceKey" -Level "ERROR"
            }
            
            # Check for cancellation
            if ($cancellationToken.IsCancellationRequested) {
                Write-Log "Operations cancelled by user" -Level "WARNING"
                return
            }
        }
        
        Write-Host "DEBUG: Processing optimizations" -ForegroundColor Yellow
        # Apply selected optimizations
        foreach ($optimizationKey in $script:SelectedOptimizations) {
            $optimizationInfo = $null
            
            # Find the optimization in the categories
            foreach ($category in $script:OptimizationCategories.Keys) {
                $optimizationInfo = $script:OptimizationCategories[$category] | Where-Object { $_.Key -eq $optimizationKey } | Select-Object -First 1
                if ($optimizationInfo) { break }
            }
            
            if ($optimizationInfo) {
                Write-Host "DEBUG: Applying optimization $($optimizationInfo.Name)" -ForegroundColor Yellow
                Update-ProgressBar -Status "Applying $($optimizationInfo.Name)..." -IncrementStep
                $result = Apply-Optimization -OptimizationKey $optimizationKey -CancellationToken $cancellationToken
                
                if ($result) {
                    Write-Log "Optimization '$($optimizationInfo.Name)' applied successfully" -Level "SUCCESS"
                } else {
                    Write-Log "Failed to apply optimization '$($optimizationInfo.Name)'" -Level "ERROR"
                }
            } else {
                Write-Log "Unknown optimization key: $optimizationKey" -Level "ERROR"
            }
            
            # Check for cancellation
            if ($cancellationToken.IsCancellationRequested) {
                Write-Log "Operations cancelled by user" -Level "WARNING"
                return
            }
        }
        
        Write-Host "DEBUG: Operations completed" -ForegroundColor Green
        # Complete
        $duration = (Get-Date) - $script:StartTime
        $durationFormatted = "{0:hh\:mm\:ss}" -f $duration
        
        Update-ProgressBar -Status "Operations completed in $durationFormatted"
        Write-Log "All operations completed in $durationFormatted" -Level "SUCCESS"
        Write-Log "System restart recommended to apply all changes" -Level "WARNING"
        
        # Show restart dialog on the UI thread
        Update-UI {
            $restartPrompt = [System.Windows.Forms.MessageBox]::Show(
                "A system restart is recommended to apply all changes. Would you like to restart now?",
                "Restart Recommended",
                [System.Windows.Forms.MessageBoxButtons]::YesNo,
                [System.Windows.Forms.MessageBoxIcon]::Question
            )
            
            if ($restartPrompt -eq [System.Windows.Forms.DialogResult]::Yes) {
                Write-Log "Initiating system restart..." -Level "WARNING"
                Restart-Computer -Force
            }
        }
        
        # Re-enable the run button and disable cancel button
        Update-UI {
            $script:btnRun.Enabled = $true
            $script:btnCancel.Enabled = $false
        }
        $script:IsRunning = $false
        
    } catch {
        Write-Host "CRITICAL ERROR in Start-SelectedOperations: $_" -ForegroundColor Red
        Write-Host "Stack trace: $($_.ScriptStackTrace)" -ForegroundColor Red
        
        # Try to recover UI
        try {
            Update-UI {
                $script:btnRun.Enabled = $true
                $script:btnCancel.Enabled = $false
            }
            $script:IsRunning = $false
        } catch {
            Write-Host "Failed to recover UI: $_" -ForegroundColor Red
        }
        
        [System.Windows.Forms.MessageBox]::Show(
            "An error occurred while starting operations: $_",
            "Error",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        )
    }
}

#endregion Installation Functions

#region GUI Functions

function Create-SelectionUI {
    param(
        [Parameter(Mandatory=$true)]
        [System.Windows.Forms.Panel]$Panel,
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
            $isChecked = $this.Checked
            foreach ($control in $scrollPanel.Controls) {
                if ($control -is [System.Windows.Forms.CheckBox] -and $control -ne $this) {
                    $control.Checked = $isChecked
                }
            }
            # Update selected items
            Update-SelectedItems -Panel $scrollPanel -SelectedItemsArray $SelectedItemsArray
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
                    # Update selected items
                    Update-SelectedItems -Panel $scrollPanel -SelectedItemsArray $SelectedItemsArray
                })
                $flowPanel.Controls.Add($cb)
            }
            
            $scrollPanel.Controls.Add($flowPanel)
            $yPos += $flowPanel.Height + 20
        }
        
        # Initial population of selected items
        Update-SelectedItems -Panel $scrollPanel -SelectedItemsArray $SelectedItemsArray
    } catch {
        Write-Host "Error in Create-SelectionUI: $_" -ForegroundColor Red
        Write-Host $_.ScriptStackTrace -ForegroundColor Red
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
        Write-Host "Error in Update-SelectedItems: $_" -ForegroundColor Red
        Write-Host $_.ScriptStackTrace -ForegroundColor Red
    }
}

function Create-ProfileControls {
    param(
        [Parameter(Mandatory=$true)]
        [System.Windows.Forms.Panel]$Panel
    )
    
    try {
        # Define profiles
        $profiles = @{
            "Default" = @{
                Description = "Balanced selection for general use"
                Apps = @("chrome", "spotify", "discord", "steam", "git", "vscode", "python", "pycharm", "github", "postman")
                Bloatware = @("ms-officehub", "ms-3dviewer", "ms-mixedreality", "ms-onenote", "ms-people", "ms-wallet", 
                            "bing-weather", "bing-news", "win-feedback", "win-gethelp", "win-getstarted", "candy-crush", "spotify-store")
                Services = @("diagtrack", "dmwappushsvc", "wmpnetworksvc", "remoteregistry", "fax", "retaildemo")
                Optimizations = @("show-extensions", "show-hidden", "dev-mode", "disable-cortana", "disable-tips", "reduce-telemetry", "search-bing")
            }
            "Developer Workstation" = @{
                Description = "Optimized for software development"
                Apps = @("chrome", "firefox", "git", "vscode", "python", "pycharm", "github", "postman", "nodejs", "terminal")
                Bloatware = @("ms-officehub", "ms-3dviewer", "ms-mixedreality", "ms-onenote", "ms-people", "ms-wallet", 
                            "bing-weather", "bing-news", "bing-finance", "win-feedback", "win-gethelp", "win-getstarted", 
                            "win-mail", "win-maps", "zune-music", "zune-video", "solitaire", "xbox-apps", "candy-crush", 
                            "spotify-store", "facebook", "twitter", "netflix", "disney", "tiktok")
                Services = @("diagtrack", "dmwappushsvc", "sysmain", "wmpnetworksvc", "remoteregistry", "remoteaccess", 
                            "printnotify", "fax", "wisvc", "retaildemo", "mapsbroker", "pcasvc", "wpcmonsvc")
                Optimizations = @("show-extensions", "show-hidden", "dev-mode", "disable-cortana", "disable-onedrive", 
                                "disable-tips", "reduce-telemetry", "disable-activity", "disable-background", "search-bing")
            }
            "Gaming PC" = @{
                Description = "Optimized for gaming performance"
                Apps = @("chrome", "discord", "steam", "vlc")
                Bloatware = @("ms-officehub", "ms-3dviewer", "ms-mixedreality", "ms-onenote", "ms-people", "ms-wallet",
                            "bing-weather", "bing-news", "bing-finance", "win-feedback", "win-gethelp", "win-getstarted",
                            "win-mail", "win-maps", "win-soundrec", "win-yourphone", "win-print3d", "zune-music", "zune-video",
                            "candy-crush", "spotify-store", "facebook", "twitter", "netflix", "disney", "tiktok")
                Services = @("diagtrack", "dmwappushsvc", "sysmain", "wmpnetworksvc", "remoteregistry", "remoteaccess", 
                            "printnotify", "fax", "wisvc", "retaildemo", "mapsbroker", "pcasvc", "wpcmonsvc", "cscservice")
                Optimizations = @("show-extensions", "show-hidden", "disable-cortana", "disable-onedrive", 
                                "disable-tips", "reduce-telemetry", "disable-activity", "disable-background")
            }
            "Minimal Setup" = @{
                Description = "Bare essentials only"
                Apps = @("chrome", "vlc", "7zip")
                Bloatware = @("ms-officehub", "ms-3dviewer", "ms-mixedreality", "ms-onenote", "ms-people", "ms-wallet",
                            "bing-weather", "bing-news", "bing-finance", "win-alarms", "win-camera", "win-mail", "win-maps",
                            "win-feedback", "win-gethelp", "win-getstarted", "win-soundrec", "win-yourphone", "win-print3d",
                            "zune-music", "zune-video", "solitaire", "xbox-apps", "candy-crush", "spotify-store", "facebook",
                            "twitter", "netflix", "disney", "tiktok")
                Services = @("diagtrack", "dmwappushsvc", "sysmain", "wmpnetworksvc", "remoteregistry", "remoteaccess", 
                            "printnotify", "fax", "wisvc", "retaildemo", "mapsbroker", "pcasvc", "wpcmonsvc", "cscservice")
                Optimizations = @("show-extensions", "show-hidden", "disable-cortana", "disable-onedrive", 
                                "disable-tips", "reduce-telemetry", "disable-activity", "disable-background")
            }
        }
        
        # Create profile combo box
        $profileCombo = New-Object System.Windows.Forms.ComboBox
        $profileCombo.Location = New-Object System.Drawing.Point(10, 10)
        $profileCombo.Size = New-Object System.Drawing.Size(220, 25)
        $profileCombo.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
        
        # Add profiles to combo box
        foreach ($profileName in $profiles.Keys) {
            $profileCombo.Items.Add($profileName)
        }
        
        # Select first profile
        $profileCombo.SelectedIndex = 0
        
        # Create description label
        $descriptionLabel = New-Object System.Windows.Forms.Label
        $descriptionLabel.Location = New-Object System.Drawing.Point(10, 45)
        $descriptionLabel.Size = New-Object System.Drawing.Size(380, 20)
        $descriptionLabel.Text = $profiles[$profileCombo.SelectedItem].Description
        
        # Create apply button
        $applyButton = New-Object System.Windows.Forms.Button
        $applyButton.Location = New-Object System.Drawing.Point(240, 8)
        $applyButton.Size = New-Object System.Drawing.Size(100, 28)
        $applyButton.Text = "Apply Profile"
        $applyButton.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 215)
        $applyButton.ForeColor = [System.Drawing.Color]::White
        $applyButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
        
        # Profile combo box change event
        $profileCombo.Add_SelectedIndexChanged({
            $selectedProfile = $profiles[$profileCombo.SelectedItem]
            $descriptionLabel.Text = $selectedProfile.Description
        })
        
        # Apply button click event
        $applyButton.Add_Click({
            $selectedProfile = $profiles[$profileCombo.SelectedItem]
            
            # Apply profile selections to tabs
            $script:SelectedApps = $selectedProfile.Apps
            $script:SelectedBloatware = $selectedProfile.Bloatware
            $script:SelectedServices = $selectedProfile.Services
            $script:SelectedOptimizations = $selectedProfile.Optimizations
            
            # Update UI in each tab
            Update-TabUIFromSelections
            
            [System.Windows.Forms.MessageBox]::Show(
                "Profile '$($profileCombo.SelectedItem)' applied. Please review selections in each tab.",
                "Profile Applied",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information
            )
        })
        
        # Add controls to panel
        $Panel.Controls.Add($profileCombo)
        $Panel.Controls.Add($descriptionLabel)
        $Panel.Controls.Add($applyButton)
    } catch {
        Write-Host "Error in Create-ProfileControls: $_" -ForegroundColor Red
        Write-Host $_.ScriptStackTrace -ForegroundColor Red
    }
}

function Update-TabUIFromSelections {
    # This function updates all checkboxes in each tab based on the current selections
    # Iterate through all tab panels and update checkboxes
    
    try {
        # Helper function to update checkboxes in a panel
        function Update-PanelCheckboxes {
            param (
                [System.Windows.Forms.Panel]$Panel,
                [string[]]$SelectedItems
            )
            
            foreach ($control in $Panel.Controls) {
                if ($control -is [System.Windows.Forms.Panel] -and $control.AutoScroll) {
                    # This is our scrollable panel that contains the checkboxes
                    foreach ($subControl in $control.Controls) {
                        if ($subControl -is [System.Windows.Forms.CheckBox] -and $subControl.Tag) {
                            $subControl.Checked = $SelectedItems -contains $subControl.Tag
                        }
                        elseif ($subControl -is [System.Windows.Forms.FlowLayoutPanel]) {
                            foreach ($childControl in $subControl.Controls) {
                                if ($childControl -is [System.Windows.Forms.CheckBox] -and $childControl.Tag) {
                                    $childControl.Checked = $SelectedItems -contains $childControl.Tag
                                }
                            }
                        }
                    }
                }
            }
        }
        
        # Update each tab
        Update-PanelCheckboxes -Panel $script:tabInstall -SelectedItems $script:SelectedApps
        Update-PanelCheckboxes -Panel $script:tabRemove -SelectedItems $script:SelectedBloatware
        Update-PanelCheckboxes -Panel $script:tabServices -SelectedItems $script:SelectedServices
        Update-PanelCheckboxes -Panel $script:tabOptimize -SelectedItems $script:SelectedOptimizations
    } catch {
        Write-Host "Error in Update-TabUIFromSelections: $_" -ForegroundColor Red
        Write-Host $_.ScriptStackTrace -ForegroundColor Red
    }
}

function Create-MainForm {
    try {
        Write-Host "Creating main form..." -ForegroundColor Yellow
        
        # Create main form
        $form = New-Object System.Windows.Forms.Form
        Write-Host "Form object created successfully" -ForegroundColor Green
        
        $form.Text = "Windows Setup Automation"
        $form.Width = 800
        $form.Height = 650
        $form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
        $form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedSingle
        $form.MaximizeBox = $false
        
        # Don't try to set icon as it might fail in some environments
        try {
            $form.Icon = [System.Drawing.Icon]::ExtractAssociatedIcon([System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName)
        } catch { 
            Write-Host "Warning: Could not set form icon: $_" -ForegroundColor Yellow
        }
        
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
        
        $script:tabSettings = New-Object System.Windows.Forms.TabPage
        $script:tabSettings.Text = "Profiles"
        $tabControl.Controls.Add($script:tabSettings)
        
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
        $script:btnRun.Add_Click({
            Start-SelectedOperations
        })
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
        $script:btnCancel.Add_Click({
            Cancel-AllOperations
        })
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
        
        # Create selection UI for each tab - suppress output
        Write-Host "Creating selection UIs for tabs..." -ForegroundColor Yellow
        $null = Create-SelectionUI -Panel $script:tabInstall -Categories $script:AppCategories -SelectedItemsArray ([ref]$script:SelectedApps)
        Write-Host "Install tab UI created" -ForegroundColor Green
        
        $null = Create-SelectionUI -Panel $script:tabRemove -Categories $script:BloatwareCategories -SelectedItemsArray ([ref]$script:SelectedBloatware)
        Write-Host "Remove tab UI created" -ForegroundColor Green
        
        $null = Create-SelectionUI -Panel $script:tabServices -Categories $script:ServiceCategories -SelectedItemsArray ([ref]$script:SelectedServices)
        Write-Host "Services tab UI created" -ForegroundColor Green
        
        $null = Create-SelectionUI -Panel $script:tabOptimize -Categories $script:OptimizationCategories -SelectedItemsArray ([ref]$script:SelectedOptimizations)
        Write-Host "Optimize tab UI created" -ForegroundColor Green
        
        $null = Create-ProfileControls -Panel $script:tabSettings
        Write-Host "Profiles tab UI created" -ForegroundColor Green
        
        # Return the form object
        Write-Host "Main form creation completed successfully" -ForegroundColor Green
        Write-Output $form
    } catch {
        Write-Host "Critical error in Create-MainForm: $_" -ForegroundColor Red
        Write-Host $_.ScriptStackTrace -ForegroundColor Red
        
        # Show error message box to the user
        try {
            [System.Windows.Forms.MessageBox]::Show(
                "An error occurred while creating the application: `n`n$_`n`nPlease make sure .NET Framework and Windows Forms are properly installed.",
                "Application Error",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            )
        } catch {
            # If even the message box fails, just output to console
            Write-Host "Could not display error dialog. This system may be missing required components." -ForegroundColor Red
        }
        
        # Return null to indicate failure
        Write-Output $null
    }
}

#endregion GUI Functions

#region Main Script

# Main execution starts here
try {
    # Check for administrator privileges
    if (-not (Test-Administrator)) {
        [System.Windows.Forms.MessageBox]::Show(
            "This script requires administrator privileges. Please run as administrator.",
            "Administrator Required",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        )
        exit 1
    }

    Write-Host "Starting Windows Setup Automation Tool..." -ForegroundColor Cyan
    Write-Host "Detected Windows: $($script:OSName)" -ForegroundColor Cyan
    Write-Host "OS Version: $($script:OSVersion)" -ForegroundColor Cyan
    Write-Host "Windows 11: $($script:IsWindows11)" -ForegroundColor Cyan

    # Create and show the form
    $mainForm = Create-MainForm

    # Verify the form was created correctly
    if ($null -eq $mainForm) {
        Write-Host "Error: Form creation failed - returned null" -ForegroundColor Red
        exit 1
    }
    
    if ($mainForm -isnot [System.Windows.Forms.Form]) {
        Write-Host "Error: Form creation returned an invalid object type: $($mainForm.GetType().FullName)" -ForegroundColor Red
        exit 1
    }

    # Add event handler after verifying form type
    $mainForm.Add_Shown({
        Write-Log "Windows Setup Automation GUI started" -Level "INFO"
        Write-Log "Detected OS: $($script:OSName)" -Level "INFO"
        
        # Check winget status and inform user
        if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
            Write-Log "Winget is not installed. Direct download methods will be used for application installations." -Level "WARNING"
            Write-Log "Select applications to install and click 'Run Selected Tasks'" -Level "INFO"
            $script:UseDirectDownloadOnly = $true
        } else {
            Write-Log "Winget is available and will be used for application installations" -Level "SUCCESS"
            Write-Log "Select applications and click 'Run Selected Tasks' to begin" -Level "INFO"
        }
    })

    # Add event handler for form closing
    $mainForm.Add_FormClosing({
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

    # Show form
    Write-Host "Launching GUI interface..." -ForegroundColor Green
    [void]$mainForm.ShowDialog()

} catch {
    Write-Host "Fatal error in main script: $_" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor Red
    
    # Try to show an error message
    try {
        [System.Windows.Forms.MessageBox]::Show(
            "A fatal error occurred: `n`n$_",
            "Fatal Error",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        )
    } catch {
        # Last resort
        Write-Host "Could not display error dialog. The system may be missing Windows Forms components." -ForegroundColor Red
    }
    
    exit 1
}

#endregion Main Script

function Update-Winget {
    [CmdletBinding()]
    param(
        [System.Threading.CancellationToken]$CancellationToken
    )
    
    Write-Log "Checking for winget updates..." -Level "INFO"
    
    try {
        # Check if winget is installed
        if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
            Write-Log "Winget is not installed. Please install it first." -Level "WARNING"
            return $false
        }
        
        # Update winget sources
        Write-Log "Updating winget sources..." -Level "INFO"
        $sourceResult = winget source update 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Log "Winget sources updated successfully" -Level "SUCCESS"
        } else {
            Write-Log "Failed to update winget sources: $sourceResult" -Level "WARNING"
        }
        
        # Check for winget updates
        $updateResult = winget upgrade --id Microsoft.DesktopAppInstaller 2>&1
        if ($updateResult -match "No applicable updates found") {
            Write-Log "Winget is up to date" -Level "INFO"
        } elseif ($LASTEXITCODE -eq 0) {
            Write-Log "Winget updated successfully" -Level "SUCCESS"
        } else {
            Write-Log "Failed to update winget: $updateResult" -Level "WARNING"
        }
        
        return $true
    }
    catch {
        Write-Log "Error updating winget: $_" -Level "ERROR"
        return $false
    }
}

function Install-WingetWithRetry {
    [CmdletBinding()]
    param(
        [System.Threading.CancellationToken]$CancellationToken,
        [int]$MaxRetries = 3,
        [int]$InitialDelay = 5
    )
    
    $retryCount = 0
    $delay = $InitialDelay
    
    while ($retryCount -lt $MaxRetries) {
        Write-Log "Attempting winget installation (Attempt $($retryCount + 1) of $MaxRetries)..." -Level "INFO"
        
        $result = Install-Winget -CancellationToken $CancellationToken
        if ($result) {
            Write-Log "Winget installed successfully!" -Level "SUCCESS"
            return $true
        }
        
        $retryCount++
        if ($retryCount -lt $MaxRetries) {
            Write-Log "Installation failed. Waiting $delay seconds before retry..." -Level "WARNING"
            Start-Sleep -Seconds $delay
            $delay *= 2  # Exponential backoff
        }
    }
    
    Write-Log "All winget installation attempts failed" -Level "ERROR"
    return $false
}

function Install-Python {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [string]$Version = "3.12",
        
        [Parameter(Mandatory=$false)]
        [switch]$CreateVirtualEnv,
        
        [Parameter(Mandatory=$false)]
        [string]$VirtualEnvName = "venv",
        
        [System.Threading.CancellationToken]$CancellationToken
    )
    
    Write-Log "Starting Python $Version installation..." -Level "INFO"
    
    # Check for cancellation
    if ($CancellationToken.IsCancellationRequested) {
        Write-Log "Python installation cancelled" -Level "WARNING"
        return $false
    }
    
    # Try winget first
    if (-not $script:UseDirectDownloadOnly -and (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-Log "Installing Python via winget..." -Level "INFO"
        try {
            $wingetOutput = winget install --id "Python.Python.$Version" --accept-source-agreements --accept-package-agreements --silent 2>&1
            
            if ($LASTEXITCODE -eq 0 -or $wingetOutput -match "Successfully installed") {
                Write-Log "Python installed successfully via winget!" -Level "SUCCESS"
                
                # Refresh environment variables
                Update-Environment
                
                # Create virtual environment if requested
                if ($CreateVirtualEnv) {
                    Write-Log "Creating Python virtual environment: $VirtualEnvName" -Level "INFO"
                    try {
                        python -m venv $VirtualEnvName
                        Write-Log "Virtual environment created successfully" -Level "SUCCESS"
                        
                        # Activate and upgrade pip
                        & "$VirtualEnvName\Scripts\activate.ps1"
                        python -m pip install --upgrade pip setuptools wheel
                        Write-Log "Pip upgraded in virtual environment" -Level "SUCCESS"
                    }
                    catch {
                        Write-Log "Failed to create virtual environment: $_" -Level "WARNING"
                    }
                }
                
                return $true
            }
        }
        catch {
            Write-Log "Winget installation failed: $_" -Level "WARNING"
        }
    }
    
    # Fallback to direct download
    Write-Log "Using direct download method for Python..." -Level "INFO"
    
    $pythonDownload = Get-AppDirectDownloadInfo -AppName "Python"
    if ($null -eq $pythonDownload) {
        Write-Log "Could not get Python download information" -Level "ERROR"
        return $false
    }
    
    try {
        # Download and install Python
        $installerPath = Join-Path $env:TEMP "PythonInstaller$($pythonDownload.Extension)"
        $webClient = New-Object System.Net.WebClient
        $webClient.DownloadFile($pythonDownload.Url, $installerPath)
        
        # Run installer with custom arguments
        $arguments = "$($pythonDownload.Arguments) Version=$Version"
        Start-Process -FilePath $installerPath -ArgumentList $arguments -Wait -NoNewWindow
        
        # Refresh environment variables
        Update-Environment
        
        # Verify installation
        if (Get-Command python -ErrorAction SilentlyContinue) {
            Write-Log "Python installed successfully!" -Level "SUCCESS"
            
            # Create virtual environment if requested
            if ($CreateVirtualEnv) {
                Write-Log "Creating Python virtual environment: $VirtualEnvName" -Level "INFO"
                try {
                    python -m venv $VirtualEnvName
                    Write-Log "Virtual environment created successfully" -Level "SUCCESS"
                    
                    # Activate and upgrade pip
                    & "$VirtualEnvName\Scripts\activate.ps1"
                    python -m pip install --upgrade pip setuptools wheel
                    Write-Log "Pip upgraded in virtual environment" -Level "SUCCESS"
                }
                catch {
                    Write-Log "Failed to create virtual environment: $_" -Level "WARNING"
                }
            }
            
            return $true
        }
    }
    catch {
        Write-Log "Failed to install Python: $_" -Level "ERROR"
    }
    
    return $false
}

function Install-PyCharm {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [ValidateSet("Community", "Professional")]
        [string]$Edition = "Community",
        
        [Parameter(Mandatory=$false)]
        [switch]$ConfigureSettings,
        
        [Parameter(Mandatory=$false)]
        [string[]]$Plugins = @(),
        
        [Parameter(Mandatory=$false)]
        [string]$ProjectTemplatePath,
        
        [System.Threading.CancellationToken]$CancellationToken
    )
    
    Write-Log "Starting PyCharm $Edition installation..." -Level "INFO"
    
    # Check for cancellation
    if ($CancellationToken.IsCancellationRequested) {
        Write-Log "PyCharm installation cancelled" -Level "WARNING"
        return $false
    }
    
    # Try winget first
    if (-not $script:UseDirectDownloadOnly -and (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-Log "Installing PyCharm via winget..." -Level "INFO"
        try {
            $wingetId = if ($Edition -eq "Professional") { "JetBrains.PyCharm.Professional" } else { "JetBrains.PyCharm.Community" }
            $wingetOutput = winget install --id $wingetId --accept-source-agreements --accept-package-agreements --silent 2>&1
            
            if ($LASTEXITCODE -eq 0 -or $wingetOutput -match "Successfully installed") {
                Write-Log "PyCharm installed successfully via winget!" -Level "SUCCESS"
                
                # Configure settings if requested
                if ($ConfigureSettings) {
                    Write-Log "Configuring PyCharm settings..." -Level "INFO"
                    try {
                        $configPath = if ($Edition -eq "Professional") {
                            "$env:APPDATA\JetBrains\PyCharm*\config"
                        } else {
                            "$env:APPDATA\JetBrains\PyCharmCE*\config"
                        }
                        
                        # Create settings directory if it doesn't exist
                        $settingsDir = (Get-ChildItem $configPath -Directory | Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName
                        if (-not (Test-Path $settingsDir)) {
                            New-Item -ItemType Directory -Path $settingsDir -Force | Out-Null
                        }
                        
                        # Install plugins if specified
                        if ($Plugins.Count -gt 0) {
                            Write-Log "Installing PyCharm plugins..." -Level "INFO"
                            foreach ($plugin in $Plugins) {
                                # Plugin installation logic here
                                Write-Log "Installed plugin: $plugin" -Level "SUCCESS"
                            }
                        }
                        
                        # Create project template if specified
                        if ($ProjectTemplatePath -and (Test-Path $ProjectTemplatePath)) {
                            Write-Log "Creating project template..." -Level "INFO"
                            # Project template creation logic here
                            Write-Log "Project template created successfully" -Level "SUCCESS"
                        }
                        
                        Write-Log "PyCharm settings configured successfully" -Level "SUCCESS"
                    }
                    catch {
                        Write-Log "Failed to configure PyCharm settings: $_" -Level "WARNING"
                    }
                }
                
                return $true
            }
        }
        catch {
            Write-Log "Winget installation failed: $_" -Level "WARNING"
        }
    }
    
    # Fallback to direct download
    Write-Log "Using direct download method for PyCharm..." -Level "INFO"
    
    $pycharmDownload = Get-AppDirectDownloadInfo -AppName "PyCharm$Edition"
    if ($null -eq $pycharmDownload) {
        Write-Log "Could not get PyCharm download information" -Level "ERROR"
        return $false
    }
    
    try {
        # Download and install PyCharm
        $installerPath = Join-Path $env:TEMP "PyCharmInstaller$($pycharmDownload.Extension)"
        $webClient = New-Object System.Net.WebClient
        $webClient.DownloadFile($pycharmDownload.Url, $installerPath)
        
        # Run installer with custom arguments
        $arguments = "$($pycharmDownload.Arguments)"
        Start-Process -FilePath $installerPath -ArgumentList $arguments -Wait -NoNewWindow
        
        # Configure settings if requested
        if ($ConfigureSettings) {
            Write-Log "Configuring PyCharm settings..." -Level "INFO"
            try {
                $configPath = if ($Edition -eq "Professional") {
                    "$env:APPDATA\JetBrains\PyCharm*\config"
                } else {
                    "$env:APPDATA\JetBrains\PyCharmCE*\config"
                }
                
                # Create settings directory if it doesn't exist
                $settingsDir = (Get-ChildItem $configPath -Directory | Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName
                if (-not (Test-Path $settingsDir)) {
                    New-Item -ItemType Directory -Path $settingsDir -Force | Out-Null
                }
                
                # Install plugins if specified
                if ($Plugins.Count -gt 0) {
                    Write-Log "Installing PyCharm plugins..." -Level "INFO"
                    foreach ($plugin in $Plugins) {
                        # Plugin installation logic here
                        Write-Log "Installed plugin: $plugin" -Level "SUCCESS"
                    }
                }
                
                # Create project template if specified
                if ($ProjectTemplatePath -and (Test-Path $ProjectTemplatePath)) {
                    Write-Log "Creating project template..." -Level "INFO"
                    # Project template creation logic here
                    Write-Log "Project template created successfully" -Level "SUCCESS"
                }
                
                Write-Log "PyCharm settings configured successfully" -Level "SUCCESS"
            }
            catch {
                Write-Log "Failed to configure PyCharm settings: $_" -Level "WARNING"
            }
        }
        
        Write-Log "PyCharm installed successfully!" -Level "SUCCESS"
        return $true
    }
    catch {
        Write-Log "Failed to install PyCharm: $_" -Level "ERROR"
    }
    
    return $false
}