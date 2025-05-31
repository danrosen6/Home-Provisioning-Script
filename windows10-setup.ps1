# Windows 10 Post-Reset Setup Script
# Installs: Chrome, Spotify, Discord, Steam, PyCharm, VS Code, VMware Player, Python, Git, GitHub Desktop, NVIDIA Drivers
# Removes: Bloatware, disables telemetry, optimizes Windows settings
# Run this script as Administrator in PowerShell

#region Functions

function Test-Administrator {
    $user = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($user)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

#region Logging System
# Define log levels
enum LogLevel {
    DEBUG = 0
    INFO = 1
    WARNING = 2
    ERROR = 3
    CRITICAL = 4
}

# Global variables for logging
$script:LogPath = Join-Path -Path $PSScriptRoot -ChildPath "setup-log.txt"
$script:LogLevel = [LogLevel]::INFO  # Default log level
$script:EnableFileLogging = $true
$script:EnableConsoleLogging = $true
$script:TotalSteps = 9  # Total number of main steps in the script
$script:CurrentStep = 0
$script:StartTime = Get-Date

function Write-Log {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [LogLevel]$Level = [LogLevel]::INFO,

        [Parameter(Mandatory = $false)]
        [ConsoleColor]$ForegroundColor = [ConsoleColor]::White
    )

    # Skip if message level is below current log level
    if ([int]$Level -lt [int]$script:LogLevel) {
        return
    }

    # Format timestamp
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

    # Format level name
    $levelName = $Level.ToString().PadRight(8)

    # Format log message
    $formattedMessage = "[$timestamp] [$levelName] $Message"

    # Write to console if enabled
    if ($script:EnableConsoleLogging) {
        if ($Level -eq [LogLevel]::ERROR -or $Level -eq [LogLevel]::CRITICAL) {
            Write-Host $formattedMessage -ForegroundColor Red
        } elseif ($Level -eq [LogLevel]::WARNING) {
            Write-Host $formattedMessage -ForegroundColor Yellow
        } else {
            Write-Host $formattedMessage -ForegroundColor $ForegroundColor
        }
    }

    # Write to log file if enabled
    if ($script:EnableFileLogging) {
        try {
            Add-Content -Path $script:LogPath -Value $formattedMessage -ErrorAction Stop
        } catch {
            Write-Host "Failed to write to log file: $_" -ForegroundColor Red
        }
    }
}

function Start-ScriptLogging {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [string]$LogDirectory = $PSScriptRoot,

        [Parameter(Mandatory = $false)]
        [LogLevel]$Level = [LogLevel]::INFO,

        [Parameter(Mandatory = $false)]
        [switch]$AppendTimestamp,

        [Parameter(Mandatory = $false)]
        [switch]$DisableFileLogging = $false,

        [Parameter(Mandatory = $false)]
        [switch]$DisableConsoleLogging = $false
    )

    # Set log level
    $script:LogLevel = $Level

    # Configure logging destinations
    $script:EnableFileLogging = -not $DisableFileLogging
    $script:EnableConsoleLogging = -not $DisableConsoleLogging

    # Create log filename with timestamp if requested
    $logFileName = "setup-log"
    if ($AppendTimestamp) {
        $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
        $logFileName = "setup-log-$timestamp"
    }
    $script:LogPath = Join-Path -Path $LogDirectory -ChildPath "$logFileName.txt"

    # Create log directory if it doesn't exist
    if (-not (Test-Path $LogDirectory)) {
        New-Item -ItemType Directory -Path $LogDirectory -Force | Out-Null
    }

    # Initialize log file
    if ($script:EnableFileLogging) {
        $header = "=== Windows 10 Post-Reset Setup Script Log ==="
        $startTime = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $separator = "=" * 50

        Set-Content -Path $script:LogPath -Value $separator
        Add-Content -Path $script:LogPath -Value $header
        Add-Content -Path $script:LogPath -Value "Started at: $startTime"
        Add-Content -Path $script:LogPath -Value "Log Level: $Level"
        Add-Content -Path $script:LogPath -Value $separator
        Add-Content -Path $script:LogPath -Value ""
    }

    # Log system information
    Write-SystemInformation

    Write-Log "Logging initialized at level: $Level" -Level DEBUG
    Write-Log "Log file: $script:LogPath" -Level DEBUG
    Write-Log "Script started" -Level INFO -ForegroundColor Green
}

function Write-SystemInformation {
    [CmdletBinding()]
    param()

    Write-Log "Collecting system information..." -Level DEBUG

    try {
        # Get Windows version
        $osInfo = Get-CimInstance Win32_OperatingSystem
        $osVersion = "$($osInfo.Caption) ($($osInfo.Version))"
        Write-Log "OS: $osVersion" -Level INFO

        # Get PowerShell version
        $psVersion = $PSVersionTable.PSVersion.ToString()
        Write-Log "PowerShell Version: $psVersion" -Level INFO

        # Get CPU Info
        $cpuInfo = Get-CimInstance Win32_Processor | Select-Object -First 1
        Write-Log "CPU: $($cpuInfo.Name)" -Level INFO

        # Get Memory Info
        $totalMemoryGB = [math]::Round(($osInfo.TotalVisibleMemorySize / 1MB), 2)
        Write-Log "Memory: $totalMemoryGB GB" -Level INFO

        # Get free disk space
        $systemDrive = $env:SystemDrive
        $diskInfo = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$systemDrive'"
        $freeSpaceGB = [math]::Round(($diskInfo.FreeSpace / 1GB), 2)
        $totalSpaceGB = [math]::Round(($diskInfo.Size / 1GB), 2)
        Write-Log "Disk $systemDrive`: $freeSpaceGB GB free of $totalSpaceGB GB" -Level INFO

        # Get network connectivity
        $internetAccess = Test-Connection -ComputerName 8.8.8.8 -Count 1 -Quiet
        Write-Log "Internet connectivity: $internetAccess" -Level INFO

        # Check if script is running as admin
        $isAdmin = Test-Administrator
        Write-Log "Running as Administrator: $isAdmin" -Level INFO
    }
    catch {
        Write-Log "Error collecting system information: $_" -Level ERROR
    }
}

function Update-ScriptProgress {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Status,

        [Parameter(Mandatory = $false)]
        [switch]$IncrementStep
    )

    if ($IncrementStep) {
        $script:CurrentStep++
    }

    $percentage = [Math]::Round(($script:CurrentStep / $script:TotalSteps) * 100)
    $elapsed = (Get-Date) - $script:StartTime
    $elapsedFormatted = "{0:hh\:mm\:ss}" -f $elapsed

    $progressMessage = "[$percentage%] Step $script:CurrentStep of $script:TotalSteps - $Status (Elapsed: $elapsedFormatted)"
    Write-Log $progressMessage -Level INFO -ForegroundColor Cyan
}

function Complete-ScriptLogging {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [bool]$Success = $true
    )

    $endTime = Get-Date
    $duration = $endTime - $script:StartTime
    $durationFormatted = "{0:hh\:mm\:ss}" -f $duration

    $statusMessage = if ($Success) { "Successfully completed" } else { "Completed with errors" }
    $logLevel = if ($Success) { [LogLevel]::INFO } else { [LogLevel]::WARNING }
    $color = if ($Success) { [ConsoleColor]::Green } else { [ConsoleColor]::Yellow }

    Write-Log "Script $statusMessage in $durationFormatted" -Level $logLevel -ForegroundColor $color

    # Log to file only - final marker
    if ($script:EnableFileLogging) {
        $separator = "=" * 50
        Add-Content -Path $script:LogPath -Value ""
        Add-Content -Path $script:LogPath -Value $separator
        Add-Content -Path $script:LogPath -Value "Script ended at: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")"
        Add-Content -Path $script:LogPath -Value "Duration: $durationFormatted"
        Add-Content -Path $script:LogPath -Value "Final status: $statusMessage"
        Add-Content -Path $script:LogPath -Value $separator
    }
}
#endregion Logging System

function Initialize-Environment {
    # Set execution policy to allow script execution
    Set-ExecutionPolicy Bypass -Scope Process -Force

    # Initialize logging system
    Start-ScriptLogging -Level INFO -AppendTimestamp

    # Set up error handling to ensure script ends properly
    $ErrorActionPreference = "Continue"
    trap {
        Write-Log "Trapped error: $_" -Level ERROR
        Write-Log "Script will continue..." -Level WARNING
        continue
    }

    # Enable TLS 1.2 for secure downloads
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    Write-Log "TLS 1.2 enabled for secure downloads" -Level DEBUG

    Update-ScriptProgress -Status "Environment initialized"

    Write-Log "Starting Windows 10 Post-Reset Setup..." -Level INFO -ForegroundColor Green
    Write-Log "This will install selected applications and optimize Windows" -Level INFO -ForegroundColor Cyan
}

function Install-PackageManager {
    # Install Chocolatey if not already installed
    if (!(Get-Command choco -ErrorAction SilentlyContinue)) {
        Write-Log "Installing Chocolatey Package Manager..." -Level INFO -ForegroundColor Yellow
        try {
            Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))

            # Refresh environment variables
            $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")

            # Verify Chocolatey installation
            if (!(Get-Command choco -ErrorAction SilentlyContinue)) {
                throw "Chocolatey installation failed"
            }
            Write-Log "Chocolatey installed successfully!" -Level INFO -ForegroundColor Green
        } catch {
            Write-Log "Failed to install Chocolatey: $_" -Level ERROR -ForegroundColor Red
            Write-Log "Please install manually from https://chocolatey.org" -Level INFO
            exit 1
        }
    } else {
        Write-Log "Chocolatey is already installed" -Level INFO -ForegroundColor Green
    }

    # Configure Chocolatey
    Write-Log "Configuring Chocolatey settings..." -Level DEBUG
    choco feature enable -n allowGlobalConfirmation
    choco config set commandExecutionTimeoutSeconds 0
    Write-Log "Chocolatey configured" -Level DEBUG
}

function Update-Environment {
    Write-Log "Refreshing environment variables..." -Level DEBUG
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
    Write-Log "Environment variables refreshed" -Level DEBUG
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
            Write-Log "Created registry path: $Path" -Level DEBUG
        }

        # Set the registry value
        Set-ItemProperty -Path $Path -Name $Name -Value $Value -ErrorAction Stop
        Write-Log "Set registry key: $Path\$Name = $Value" -Level DEBUG
        return $true
    }
    catch {
        Write-Log "Failed to set registry key: $Path\$Name" -Level ERROR
        Write-Log "Error: $_" -Level ERROR
        return $false
    }
}

function Install-App {
    param(
        [Parameter(Mandatory=$true)]
        [string]$AppName,
        [Parameter(Mandatory=$true)]
        [string]$ChocoName,
        [Parameter(Mandatory=$false)]
        [string]$VerifyCommand = $null,
        [Parameter(Mandatory=$false)]
        [string]$PathToAdd = $null,
        [Parameter(Mandatory=$false)]
        [int]$MaxRetries = 2
    )

    Write-Log "Starting installation of $AppName ($ChocoName)..." -Level INFO -ForegroundColor Yellow

    # Check if already installed via Chocolatey
    $installed = choco list --local-only | Select-String -Pattern "^$ChocoName\s"
    if ($installed) {
        Write-Log "$AppName is already installed" -Level INFO -ForegroundColor Green
        return $true
    }

    # Try installation with retries
    $retryCount = 0
    $success = $false

    while (-not $success -and $retryCount -le $MaxRetries) {
        if ($retryCount -gt 0) {
            Write-Log "Retry attempt $retryCount of $MaxRetries for $AppName..." -Level WARNING -ForegroundColor Yellow
            Start-Sleep -Seconds 3
        }

        Write-Log "Running: choco install $ChocoName -y" -Level DEBUG
        $result = choco install $ChocoName -y --no-progress 2>&1

        if ($LASTEXITCODE -eq 0) {
            $success = $true
            Write-Log "Chocolatey reported successful installation of $AppName" -Level DEBUG
        } else {
            $retryCount++
            Write-Log "Installation attempt failed with exit code $LASTEXITCODE" -Level WARNING
            Write-Log "Error details: $result" -Level DEBUG
        }
    }

    if ($success) {
        Write-Log "$AppName installed successfully!" -Level INFO -ForegroundColor Green

        # Add to PATH if specified
        if ($PathToAdd -and (Test-Path $PathToAdd)) {
            $currentPath = [Environment]::GetEnvironmentVariable("Path", "User")
            if ($currentPath -notlike "*$PathToAdd*") {
                Write-Log "Adding $PathToAdd to PATH" -Level DEBUG
                [Environment]::SetEnvironmentVariable("Path", "$currentPath;$PathToAdd", "User")
                $env:Path += ";$PathToAdd"
                Write-Log "Added $PathToAdd to PATH" -Level INFO -ForegroundColor Green
            } else {
                Write-Log "$PathToAdd is already in PATH" -Level DEBUG
            }
        }

        # Verify installation if command provided
        if ($VerifyCommand) {
            Write-Log "Verifying installation by checking for command: $VerifyCommand" -Level DEBUG
            Start-Sleep -Seconds 2
            if (Get-Command $VerifyCommand -ErrorAction SilentlyContinue) {
                Write-Log "$AppName verified in PATH" -Level INFO -ForegroundColor Green
            } else {
                Write-Log "Warning: $AppName installed but $VerifyCommand not found in PATH" -Level WARNING -ForegroundColor Yellow
                Write-Log "This may require a system restart to resolve" -Level INFO
            }
        }

        return $true
    } else {
        Write-Log "Failed to install $AppName after $MaxRetries retries" -Level ERROR -ForegroundColor Red
        Write-Log "Error output: $result" -Level ERROR
        return $false
    }
}

function Select-Applications {
    [CmdletBinding()]
    param()

    $availableApps = @{
        "1" = @{Key="chrome"; Name="Google Chrome"; Default=$true}
        "2" = @{Key="spotify"; Name="Spotify"; Default=$true}
        "3" = @{Key="discord"; Name="Discord"; Default=$true}
        "4" = @{Key="steam"; Name="Steam"; Default=$true}
        "5" = @{Key="git"; Name="Git"; Default=$true}
        "6" = @{Key="vscode"; Name="Visual Studio Code"; Default=$true}
        "7" = @{Key="python"; Name="Python"; Default=$true}
        "8" = @{Key="pycharm"; Name="PyCharm Community"; Default=$true}
        "9" = @{Key="github"; Name="GitHub Desktop"; Default=$true}
        "10" = @{Key="vmware"; Name="VMware Player"; Default=$false}
        "11" = @{Key="nvidia"; Name="NVIDIA Drivers"; Default=$false}
    }

    Write-Log "=== Select Applications to Install ===" -Level INFO -ForegroundColor Cyan
    Write-Host "Enter the numbers for applications you want to install (comma-separated)" -ForegroundColor Yellow
    Write-Host "Example: 1,3,5,7 or type 'all' for all apps" -ForegroundColor Yellow
    Write-Host "Default apps are pre-selected (indicated with [*])" -ForegroundColor Yellow
    Write-Host ""

    # Display available apps
    foreach ($key in $availableApps.Keys | Sort-Object) {
        $app = $availableApps[$key]
        $marker = if ($app.Default) { "[*]" } else { "[ ]" }
        Write-Host "$key. $marker $($app.Name)" -ForegroundColor White
    }

    # Get user selection
    $selection = Read-Host "`nYour selection (press Enter for defaults)"

    $selectedApps = @()

    if ([string]::IsNullOrWhiteSpace($selection)) {
        # Default selection
        Write-Log "User selected default applications" -Level DEBUG
        foreach ($key in $availableApps.Keys) {
            $app = $availableApps[$key]
            if ($app.Default) {
                $selectedApps += $app.Key
            }
        }
    }
    elseif ($selection -eq "all") {
        # All apps
        Write-Log "User selected all applications" -Level DEBUG
        foreach ($key in $availableApps.Keys) {
            $app = $availableApps[$key]
            $selectedApps += $app.Key
        }
    }
    else {
        # Parse user selection
        Write-Log "User provided custom selection: $selection" -Level DEBUG
        $selection.Split(',') | ForEach-Object {
            $appNumber = $_.Trim()
            if ($availableApps.ContainsKey($appNumber)) {
                $selectedApps += $availableApps[$appNumber].Key
            } else {
                Write-Log "Warning: Invalid selection number: $appNumber" -Level WARNING
            }
        }
    }

    # Confirm selection
    Write-Log "Selected applications: $($selectedApps -join ', ')" -Level INFO
    Write-Host "`nYou selected:" -ForegroundColor Green
    foreach ($appKey in $selectedApps) {
        $appName = ($availableApps.Values | Where-Object { $_.Key -eq $appKey }).Name
        Write-Host "- $appName" -ForegroundColor White
    }

    $confirmation = Read-Host "`nProceed with installation? [Y/N] (Default: Y)"
    if ($confirmation -eq '' -or $confirmation -eq 'Y') {
        Write-Log "User confirmed application selection" -Level DEBUG
        return $selectedApps
    }
    else {
        Write-Log "Installation cancelled by user" -Level WARNING -ForegroundColor Yellow
        exit 0
    }
}

function Install-Chrome {
    # Special handling for Chrome due to frequent checksum issues
    Write-Log "Starting Google Chrome installation (special handling)..." -Level INFO -ForegroundColor Yellow

    $chromeInstalled = choco list --local-only | Select-String -Pattern "^googlechrome\s"
    if ($chromeInstalled) {
        Write-Log "Google Chrome is already installed" -Level INFO -ForegroundColor Green
        return $true
    } else {
        # Try with checksum bypass due to frequent Google updates
        Write-Log "Attempting Chocolatey installation with checksum bypass..." -Level DEBUG
        $errorBefore = $ErrorActionPreference
        $ErrorActionPreference = "SilentlyContinue"

        choco install googlechrome -y --no-progress --ignore-checksums

        $ErrorActionPreference = $errorBefore

        # Check if Chrome was installed by looking for the executable
        if ((Test-Path "C:\Program Files\Google\Chrome\Application\chrome.exe") -or
            (Test-Path "C:\Program Files (x86)\Google\Chrome\Application\chrome.exe")) {
            Write-Log "Google Chrome installed successfully via Chocolatey!" -Level INFO -ForegroundColor Green
            return $true
        } else {
            Write-Log "Chocolatey installation failed, trying direct download..." -Level WARNING -ForegroundColor Yellow
            $chromeUrl = "https://dl.google.com/dl/chrome/install/googlechromestandaloneenterprise64.msi"
            $chromePath = "$env:TEMP\ChromeInstaller.msi"
            try {
                Write-Log "Downloading Chrome from official Google URL..." -Level DEBUG
                Invoke-WebRequest -Uri $chromeUrl -OutFile $chromePath -UseBasicParsing

                Write-Log "Running Chrome installer..." -Level DEBUG
                Start-Process msiexec.exe -ArgumentList "/i", $chromePath, "/quiet", "/norestart" -Wait -NoNewWindow
                Remove-Item $chromePath -Force -ErrorAction SilentlyContinue

                if ((Test-Path "C:\Program Files\Google\Chrome\Application\chrome.exe") -or
                    (Test-Path "C:\Program Files (x86)\Google\Chrome\Application\chrome.exe")) {
                    Write-Log "Google Chrome installed successfully via direct download!" -Level INFO -ForegroundColor Green
                    return $true
                } else {
                    throw "Chrome installation failed - executable not found after installation."
                }
            } catch {
                Write-Log "Chrome installation failed: $_" -Level ERROR -ForegroundColor Red
                Write-Log "Please install Chrome manually from https://google.com/chrome" -Level INFO
                return $false
            }
        }
    }
}

function Install-Python {
    Write-Log "Starting Python installation (special handling)..." -Level INFO -ForegroundColor Yellow

    $pythonResult = choco install python3 -y --no-progress 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Log "Python installed successfully via Chocolatey!" -Level INFO -ForegroundColor Green

        # Refresh environment variables
        Write-Log "Refreshing environment to detect Python..." -Level DEBUG
        Update-Environment

        # Find Python installation - Chocolatey installs to C:\PythonXXX
        Write-Log "Searching for Python installation directory..." -Level DEBUG
        $pythonPaths = Get-ChildItem -Path "C:\Python*" -Directory -ErrorAction SilentlyContinue |
                        Sort-Object Name -Descending

        if ($pythonPaths) {
            $pythonPath = $pythonPaths[0].FullName
            $pythonScriptsPath = Join-Path $pythonPath "Scripts"

            Write-Log "Found Python at: $pythonPath" -Level INFO -ForegroundColor Green

            # Add Python to PATH
            $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
            if ($userPath -notlike "*$pythonPath*") {
                Write-Log "Adding Python and Scripts directories to PATH..." -Level DEBUG
                [Environment]::SetEnvironmentVariable("Path", "$pythonPath;$pythonScriptsPath;$userPath", "User")
                $env:Path = "$pythonPath;$pythonScriptsPath;$env:Path"
                Write-Log "Python added to PATH" -Level INFO -ForegroundColor Green
            } else {
                Write-Log "Python is already in PATH" -Level DEBUG
            }

            # Verify Python installation
            try {
                $pythonVersion = & "$pythonPath\python.exe" --version 2>&1
                Write-Log "Python version: $pythonVersion" -Level INFO -ForegroundColor Green

                # Upgrade pip
                Write-Log "Upgrading pip to latest version..." -Level DEBUG
                & "$pythonPath\python.exe" -m pip install --upgrade pip --quiet
                Write-Log "Pip upgraded successfully" -Level DEBUG

                # Note about virtual environments
                Write-Log "Python is ready for virtual environments!" -Level INFO -ForegroundColor Cyan
                Write-Log "Create a venv with: python -m venv myenv" -Level INFO
                Write-Log "Activate with: myenv\Scripts\activate" -Level INFO

                return $true
            } catch {
                Write-Log "Warning: Could not verify Python installation: $_" -Level WARNING -ForegroundColor Yellow
                return $true # Still consider it a success
            }
        } else {
            Write-Log "Warning: Could not find Python installation path" -Level WARNING -ForegroundColor Yellow
            Write-Log "Python may still work - try 'python' or 'py' in a new terminal" -Level INFO
            return $true # Still consider it a success
        }
    } else {
        Write-Log "Failed to install Python" -Level ERROR -ForegroundColor Red
        Write-Log "Error details: $pythonResult" -Level ERROR
        return $false
    }
}

function Install-VMware {
    Write-Log "VMware Player installation (special handling)..." -Level INFO -ForegroundColor Yellow
    Write-Log "VMware Player installation through Chocolatey often fails due to network issues." -Level INFO

    Write-Host "Would you like to open the VMware download page in your browser? [Y/N] (Default: Y)" -ForegroundColor White
    $vmwareChoice = Read-Host -Prompt "Your choice"
    if ($vmwareChoice -eq '' -or $vmwareChoice -eq 'Y') {
        Write-Log "Opening VMware Player download page in browser..." -Level INFO
        Start-Process "https://www.vmware.com/products/workstation-player/workstation-player-evaluation.html"
        Write-Log "After downloading, run the installer manually." -Level INFO
        Write-Log "NOTE: VMware Player is free for non-commercial use." -Level INFO
        return $true
    } else {
        Write-Log "User skipped VMware Player installation" -Level INFO -ForegroundColor Yellow
        Write-Log "VMware Player can be downloaded later from: https://www.vmware.com/products/workstation-player/workstation-player-evaluation.html" -Level INFO
        return $false
    }
}

function Install-NvidiaDrivers {
    Write-Log "NVIDIA driver installation (special handling)..." -Level INFO -ForegroundColor Yellow
    Write-Log "Note: Automated NVIDIA driver installation can be unreliable" -Level WARNING

    Write-Host "Attempt automatic NVIDIA driver installation? [Y/N] (Default: N)" -ForegroundColor White
    $nvidiaChoice = Read-Host -Prompt "Your choice"
    if ($nvidiaChoice -eq '') { $nvidiaChoice = 'N' }

    if ($nvidiaChoice -eq 'Y') {
        # Try automatic installation
        Write-Log "Attempting automatic NVIDIA driver installation..." -Level INFO
        $success = Install-App -AppName "NVIDIA Display Driver" -ChocoName "nvidia-display-driver"

        if (-not $success) {
            Write-Log "Automatic driver installation failed. Trying GeForce Experience instead..." -Level WARNING -ForegroundColor Yellow
            $success = Install-App -AppName "GeForce Experience" -ChocoName "geforce-experience"
            if ($success) {
                Write-Log "GeForce Experience installed. Use it to download the correct drivers for your GPU" -Level INFO -ForegroundColor Green
                return $true
            } else {
                Write-Log "Failed to install GeForce Experience" -Level ERROR -ForegroundColor Red
                Write-Log "Please install NVIDIA drivers manually from https://www.nvidia.com/Download/index.aspx" -Level INFO
                return $false
            }
        } else {
            Write-Log "NVIDIA drivers installed successfully!" -Level INFO -ForegroundColor Green
            return $true
        }
    } else {
        Write-Log "User skipped NVIDIA driver installation" -Level INFO -ForegroundColor Yellow
        Write-Log "NVIDIA drivers can be installed manually from: https://www.nvidia.com/Download/index.aspx" -Level INFO
        return $false
    }
}

function Set-GitConfig {
    Write-Log "=== Configuring Git ===" -Level INFO -ForegroundColor Cyan

    if (Get-Command git -ErrorAction SilentlyContinue) {
        Write-Host "Would you like to configure Git now? [Y/N] (Default: N)" -ForegroundColor White
        $configureGit = Read-Host -Prompt "Your choice"
        if ($configureGit -eq '') { $configureGit = 'N' }

        if ($configureGit -eq 'Y') {
            $gitName = Read-Host "Enter your Git username"
            $gitEmail = Read-Host "Enter your Git email"

            if ($gitName) {
                git config --global user.name "$gitName"
                Write-Log "Git username set to: $gitName" -Level INFO -ForegroundColor Green
            }
            if ($gitEmail) {
                git config --global user.email "$gitEmail"
                Write-Log "Git email set to: $gitEmail" -Level INFO -ForegroundColor Green
            }

            # Set default branch name to main
            git config --global init.defaultBranch main
            Write-Log "Git default branch set to 'main'" -Level INFO

            # Set up credential manager
            git config --global credential.helper manager-core
            Write-Log "Git credential manager configured" -Level INFO

            return $true
        } else {
            Write-Log "User skipped Git configuration" -Level INFO
        }
    } else {
        Write-Log "Git not found in PATH, skipping configuration" -Level WARNING
    }
    return $false
}

function Install-VSCodeExtensions {
    Write-Log "=== Installing VS Code Extensions ===" -Level INFO -ForegroundColor Cyan

    Update-Environment
    if (Get-Command code -ErrorAction SilentlyContinue) {
        $extensions = @(
            "ms-python.python",
            "ms-python.vscode-pylance",
            "ms-python.debugpy",
            "ms-vscode.powershell",
            "GitHub.vscode-pull-request-github",
            "eamodio.gitlens"
        )

        $installedCount = 0
        $failedCount = 0

        foreach ($ext in $extensions) {
            Write-Log "Installing VS Code extension: $ext" -Level INFO -ForegroundColor Yellow
            & code --install-extension $ext --force 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) {
                Write-Log "✓ $ext installed" -Level INFO -ForegroundColor Green
                $installedCount++
            } else {
                Write-Log "✗ Failed to install $ext" -Level WARNING -ForegroundColor Red
                $failedCount++
            }
        }

        Write-Log "VS Code extensions installation complete: $installedCount installed, $failedCount failed" -Level INFO -ForegroundColor Cyan
        return ($failedCount -eq 0)
    } else {
        Write-Log "VS Code not found in PATH. Please restart PowerShell and run:" -Level WARNING -ForegroundColor Yellow
        Write-Log "code --install-extension ms-python.python" -Level INFO
        return $false
    }
}

function New-DevelopmentFolders {
    Write-Log "=== Creating Development Folders ===" -Level INFO -ForegroundColor Cyan

    $folders = @(
        "$env:USERPROFILE\Desktop\Projects",
        "$env:USERPROFILE\Desktop\Projects\Python",
        "$env:USERPROFILE\Desktop\Projects\GitHub",
        "$env:USERPROFILE\Desktop\VMs",
        "$env:USERPROFILE\.vscode"
    )

    $createdCount = 0
    foreach ($folder in $folders) {
        if (!(Test-Path $folder)) {
            New-Item -ItemType Directory -Path $folder -Force | Out-Null
            Write-Log "Created: $folder" -Level INFO -ForegroundColor Green
            $createdCount++
        } else {
            Write-Log "Folder already exists: $folder" -Level DEBUG
        }
    }

    Write-Log "Created $createdCount new folders" -Level INFO
}

function Set-OptimalWindowsSettings {
    Update-ScriptProgress -Status "Configuring Windows settings"
    Write-Log "Starting Windows optimization..." -Level INFO -ForegroundColor Cyan

    # Show file extensions
    Write-Log "Showing file extensions..." -Level DEBUG
    Set-RegistryKey -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "HideFileExt" -Value 0

    # Show hidden files
    Write-Log "Showing hidden files..." -Level DEBUG
    Set-RegistryKey -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "Hidden" -Value 1

    # Enable Developer Mode
    try {
        Write-Log "Enabling Developer Mode..." -Level DEBUG
        Set-RegistryKey -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock" -Name "AllowDevelopmentWithoutDevLicense" -Value 1
        Write-Log "Developer Mode enabled" -Level INFO -ForegroundColor Green
    } catch {
        Write-Log "Could not enable Developer Mode (requires admin rights): $_" -Level WARNING -ForegroundColor Yellow
    }

    # Disable Cortana
    Write-Log "Disabling Cortana..." -Level DEBUG
    Set-RegistryKey -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search" -Name "AllowCortana" -Value 0

    # Disable OneDrive startup
    Write-Log "Disabling OneDrive auto-start..." -Level DEBUG
    Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "OneDrive" -ErrorAction SilentlyContinue

    # Disable Windows Tips and Suggestions
    Write-Log "Disabling Windows tips and suggestions..." -Level DEBUG
    Set-RegistryKey -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "SubscribedContent-338389Enabled" -Value 0
    Set-RegistryKey -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "SystemPaneSuggestionsEnabled" -Value 0
    Set-RegistryKey -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "SoftLandingEnabled" -Value 0

    # Disable Telemetry
    Write-Log "Reducing telemetry..." -Level DEBUG
    Set-RegistryKey -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" -Name "AllowTelemetry" -Value 1

    # Disable Activity History
    Write-Log "Disabling activity history..." -Level DEBUG
    Set-RegistryKey -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" -Name "EnableActivityFeed" -Value 0
    Set-RegistryKey -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" -Name "PublishUserActivities" -Value 0

    # Disable Background Apps
    Write-Log "Disabling unnecessary background apps..." -Level DEBUG
    Set-RegistryKey -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications" -Name "GlobalUserDisabled" -Value 1

    # Clean up taskbar (keeping search functionality)
    Write-Log "Cleaning up taskbar (keeping search box)..." -Level DEBUG
    # Hide Cortana button (not the search box)
    Set-RegistryKey -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Taskband" -Name "ShowCortanaButton" -Value 0

    # Configure search box to always show the full search box
    Write-Log "Configuring taskbar to always show search box..." -Level DEBUG
    # SearchboxTaskbarMode: 0 = Hidden, 1 = Show search icon, 2 = Show search box
    Set-RegistryKey -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" -Name "SearchboxTaskbarMode" -Value 2

    # Hide Task View button
    Set-RegistryKey -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "ShowTaskViewButton" -Value 0

    # Configure Search to use local search instead of Bing
    Write-Log "Configuring Windows Search to prioritize local results..." -Level DEBUG
    # Disable Bing search in Start Menu
    Set-RegistryKey -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" -Name "BingSearchEnabled" -Value 0
    # Disable Cortana web search
    Set-RegistryKey -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" -Name "CortanaConsent" -Value 0

    Write-Log "Windows settings optimization complete" -Level INFO -ForegroundColor Green
}

function Remove-Bloatware {
    Update-ScriptProgress -Status "Removing Windows bloatware"
    Write-Log "Starting bloatware removal..." -Level INFO -ForegroundColor Cyan

    $bloatware = @(
        "Microsoft.BingWeather"
        "Microsoft.GetHelp"
        "Microsoft.Getstarted"
        "Microsoft.Microsoft3DViewer"
        "Microsoft.MicrosoftOfficeHub"
        "Microsoft.MicrosoftSolitaireCollection"
        "Microsoft.MixedReality.Portal"
        "Microsoft.People"
        "Microsoft.Print3D"
        "Microsoft.SkypeApp"
        "Microsoft.Wallet"
        "Microsoft.WindowsAlarms"
        "Microsoft.WindowsCamera"
        "Microsoft.WindowsCommunicationsApps"  # Mail and Calendar
        "Microsoft.WindowsFeedbackHub"
        "Microsoft.WindowsMaps"
        "Microsoft.WindowsSoundRecorder"
        "Microsoft.YourPhone"
        "Microsoft.ZuneMusic"
        "Microsoft.ZuneVideo"
        "Microsoft.OneConnect"
        "Microsoft.BingNews"
        "Microsoft.Messaging"
        "Microsoft.Office.OneNote"  # Use the desktop version instead
        "*.CandyCrush*"
        "*.Spotify*"  # We're installing desktop version
        "*.Twitter*"
        "*.Facebook*"
        "*.Netflix*"
        "*.Hulu*"
        "*.PicsArt*"
        "*.TikTok*"
    )

    $totalApps = $bloatware.Count
    $removedCount = 0
    $failedCount = 0

    Write-Log "Found $totalApps bloatware items to remove" -Level INFO

    foreach ($app in $bloatware) {
        Write-Log "Removing $app..." -Level DEBUG -ForegroundColor Yellow
        try {
            $appxPackages = Get-AppxPackage -Name $app -AllUsers -ErrorAction SilentlyContinue
            if ($appxPackages) {
                $appxPackages | Remove-AppxPackage -ErrorAction SilentlyContinue
                $removedCount++
                Write-Log "Removed AppxPackage: $app" -Level DEBUG
            }

            $provisionedPackages = Get-AppxProvisionedPackage -Online | Where-Object {$_.DisplayName -like $app}
            if ($provisionedPackages) {
                $provisionedPackages | Remove-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue
                Write-Log "Removed AppxProvisionedPackage: $app" -Level DEBUG
            }
        } catch {
            $failedCount++
            Write-Log ("Failed to remove {0}: {1}" -f $app, $_) -Level WARNING
        }
    }

    Write-Log "Bloatware removal complete: Removed $removedCount of $totalApps applications" -Level INFO -ForegroundColor Green
    if ($failedCount -gt 0) {
        Write-Log "$failedCount applications could not be removed" -Level WARNING -ForegroundColor Yellow
    }
}

function Disable-UnnecessaryServices {
    Write-Log "=== Disabling Unnecessary Services ===" -Level INFO -ForegroundColor Cyan

    $services = @(
        "DiagTrack"                    # Connected User Experiences and Telemetry
        "dmwappushservice"             # WAP Push Message Routing Service
        "SysMain"                      # Superfetch/Prefetch
        # "Windows Search"             # Commented out to keep search functionality
        "WMPNetworkSvc"               # Windows Media Player Network Sharing
        "RemoteRegistry"              # Remote Registry
        "RemoteAccess"                # Routing and Remote Access
        "PrintNotify"                 # Printer Extensions and Notifications
        "Fax"                         # Fax service
        "wisvc"                       # Windows Insider Service
        "RetailDemo"                  # Retail Demo Service
        "MapsBroker"                  # Downloaded Maps Manager
        "PcaSvc"                      # Program Compatibility Assistant
        "WpcMonSvc"                   # Parental Controls
        "CscService"                  # Offline Files
    )

    $disabledCount = 0
    $failedCount = 0

    foreach ($service in $services) {
        try {
            Write-Log "Disabling $service..." -Level DEBUG -ForegroundColor Yellow

            $svc = Get-Service -Name $service -ErrorAction SilentlyContinue
            if ($svc) {
                Stop-Service -Name $service -Force -ErrorAction SilentlyContinue
                Set-Service -Name $service -StartupType Disabled -ErrorAction SilentlyContinue
                $disabledCount++
                Write-Log "Service $service disabled" -Level DEBUG
            } else {
                Write-Log "Service $service not found on this system" -Level DEBUG
            }
        } catch {
            $failedCount++
            Write-Log ("Failed to disable {0}: {1}" -f $service, $_) -Level WARNING
            # Service might not exist on this version of Windows
        }
    }

    Write-Log "Services optimization complete: Disabled $disabledCount services" -Level INFO -ForegroundColor Green
    if ($failedCount -gt 0) {
        Write-Log "$failedCount services could not be disabled" -Level WARNING -ForegroundColor Yellow
    }
}

function Install-ApplicationsParallel {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string[]]$SelectedApps,
        [Parameter(Mandatory=$false)]
        [int]$MaxParallel = 2
    )

    Update-ScriptProgress -Status "Installing selected applications"
    Write-Log "Starting application installation process" -Level INFO -ForegroundColor Cyan
    Write-Log "Selected apps: $($SelectedApps -join ', ')" -Level DEBUG

    # Define available applications and their installation methods
    $appDefinitions = @{
        "chrome" = @{Name="Google Chrome"; Special=$true; Method="Install-Chrome"}
        "spotify" = @{Name="Spotify"; ChocoName="spotify"; Special=$false}
        "discord" = @{Name="Discord"; ChocoName="discord"; Special=$false}
        "steam" = @{Name="Steam"; ChocoName="steam-client"; Special=$false}
        "git" = @{Name="Git"; ChocoName="git"; VerifyCommand="git"; PathToAdd="C:\Program Files\Git\bin"; Special=$false}
        "vscode" = @{Name="Visual Studio Code"; ChocoName="vscode"; VerifyCommand="code"; PathToAdd="C:\Program Files\Microsoft VS Code\bin"; Special=$false}
        "python" = @{Name="Python"; Special=$true; Method="Install-Python"}
        "pycharm" = @{Name="PyCharm Community"; ChocoName="pycharm-community"; Special=$false}
        "github" = @{Name="GitHub Desktop"; ChocoName="github-desktop"; Special=$false}
        "vmware" = @{Name="VMware Player"; Special=$true; Method="Install-VMware"}
        "nvidia" = @{Name="NVIDIA Drivers"; Special=$true; Method="Install-NvidiaDrivers"}
    }

    # Track installation results
    $installationResults = @{}

    # Process apps with special installation procedures
    $specialApps = $SelectedApps | Where-Object {
        $appDefinitions.ContainsKey($_) -and $appDefinitions[$_].Special
    }

    Write-Log "Processing special applications first: $($specialApps -join ', ')" -Level DEBUG

    foreach ($app in $specialApps) {
        if ($appDefinitions.ContainsKey($app)) {
            $appInfo = $appDefinitions[$app]
            Write-Log "Installing special application: $($appInfo.Name)..." -Level INFO -ForegroundColor Cyan

            # Call special installation method
            $methodName = $appInfo.Method
            Write-Log "Calling special installation method: $methodName" -Level DEBUG
            $result = & $methodName
            $installationResults[$app] = $result

            $status = if ($result) { "succeeded" } else { "failed" }
            Write-Log "Installation of $($appInfo.Name) $status" -Level INFO
        }
    }

    # Process standard apps
    $standardApps = $SelectedApps | Where-Object {
        $appDefinitions.ContainsKey($_) -and -not $appDefinitions[$_].Special
    }

    Write-Log "Processing standard applications: $($standardApps -join ', ')" -Level DEBUG

    foreach ($app in $standardApps) {
        $appInfo = $appDefinitions[$app]
        Write-Log "Installing standard application: $($appInfo.Name)..." -Level INFO
        $result = Install-App -AppName $appInfo.Name -ChocoName $appInfo.ChocoName -VerifyCommand $appInfo.VerifyCommand -PathToAdd $appInfo.PathToAdd
        $installationResults[$app] = $result
    }

    # Report installation results
    Write-Log "=== Installation Results ===" -Level INFO -ForegroundColor Cyan
    $successCount = 0
    $failCount = 0

    foreach ($app in $SelectedApps) {
        if ($appDefinitions.ContainsKey($app)) {
            $appInfo = $appDefinitions[$app]
            $success = $installationResults.ContainsKey($app) -and $installationResults[$app]
            $status = if ($success) { "✓ Success" } else { "✗ Failed" }
            $color = if ($success) { "Green" } else { "Red" }

            Write-Log "$($appInfo.Name): $status" -Level INFO -ForegroundColor $color

            if ($success) {
                $successCount++
            } else {
                $failCount++
            }
        }
    }

    $totalApps = $SelectedApps.Count
    $successPercentage = [Math]::Round(($successCount / $totalApps) * 100)

    Write-Log "Installation complete: $successCount of $totalApps applications installed successfully ($successPercentage%)" -Level INFO -ForegroundColor Cyan

    if ($failCount -gt 0) {
        Write-Log "$failCount applications failed to install" -Level WARNING -ForegroundColor Yellow
    }
}

function Test-Installations {
    Update-ScriptProgress -Status "Verifying installations"
    Write-Log "=== Verifying Installations ===" -Level INFO -ForegroundColor Cyan

    $commands = @{
        "Git" = "git --version"
        "Python" = "python --version"
        "pip" = "pip --version"
        "VS Code" = "code --version"
    }

    $verifiedCount = 0
    foreach ($tool in $commands.Keys) {
        try {
            $output = Invoke-Expression $commands[$tool] 2>&1
            Write-Log "✓ $tool is working: $output" -Level INFO -ForegroundColor Green
            $verifiedCount++
        } catch {
            Write-Log "✗ $tool is not accessible from PATH" -Level WARNING -ForegroundColor Red
            Write-Log "  You may need to restart your computer for PATH changes to take effect" -Level INFO
        }
    }

    Write-Log "Verified $verifiedCount of $($commands.Count) tools" -Level INFO
}

function Show-Summary {
    Update-ScriptProgress -Status "Displaying summary"
    Write-Log "================================" -Level INFO -ForegroundColor Green
    Write-Log "Setup Complete!" -Level INFO -ForegroundColor Green
    Write-Log "================================" -Level INFO -ForegroundColor Green

    Write-Host "`nInstalled Software:" -ForegroundColor Cyan
    Write-Host "✓ Google Chrome" -ForegroundColor White
    Write-Host "✓ Spotify" -ForegroundColor White
    Write-Host "✓ Discord" -ForegroundColor White
    Write-Host "✓ Steam" -ForegroundColor White
    Write-Host "✓ PyCharm Community Edition" -ForegroundColor White
    Write-Host "✓ Visual Studio Code (with Python extensions)" -ForegroundColor White
    Write-Host "✓ VMware Player (manual download)" -ForegroundColor White
    Write-Host "✓ Python 3.x" -ForegroundColor White
    Write-Host "✓ Git" -ForegroundColor White
    Write-Host "✓ GitHub Desktop" -ForegroundColor White
    Write-Host "✓ NVIDIA Drivers (if selected)" -ForegroundColor White

    Write-Host "`nWindows Optimizations:" -ForegroundColor Cyan
    Write-Host "✓ Removed bloatware apps (Candy Crush, etc.)" -ForegroundColor White
    Write-Host "✓ Disabled Cortana" -ForegroundColor White
    Write-Host "✓ Disabled OneDrive auto-start" -ForegroundColor White
    Write-Host "✓ Disabled Windows tips and suggestions" -ForegroundColor White
    Write-Host "✓ Reduced telemetry" -ForegroundColor White
    Write-Host "✓ Disabled activity history" -ForegroundColor White
    Write-Host "✓ Disabled unnecessary background apps" -ForegroundColor White
    Write-Host "✓ Cleaned up taskbar (kept search box)" -ForegroundColor White
    Write-Host "✓ Configured search for local results (disabled Bing)" -ForegroundColor White

    Write-Host "`nIMPORTANT NEXT STEPS:" -ForegroundColor Yellow
    Write-Host "1. RESTART your computer to ensure all PATH changes take effect" -ForegroundColor Cyan
    Write-Host "2. After restart, verify installations by opening new terminals" -ForegroundColor Cyan
    Write-Host "3. Launch apps that need initial setup (Steam, Discord, etc.)" -ForegroundColor Cyan
    Write-Host "4. Python is ready - create virtual environments with: python -m venv myenv" -ForegroundColor Cyan
    Write-Host "5. If any tool isn't working, try running 'refreshenv' in a new PowerShell" -ForegroundColor Cyan

    Write-Host "`nTroubleshooting:" -ForegroundColor Yellow
    Write-Host "- If 'python' doesn't work, use 'py' instead" -ForegroundColor White
    Write-Host "- For PATH issues, restart PowerShell or run: refreshenv" -ForegroundColor White
    Write-Host "- Check installed packages: choco list --local-only" -ForegroundColor White
    Write-Host "- Check the log file at: $script:LogPath" -ForegroundColor White
}

function Show-RestartPrompt {
    Write-Host ""
    Write-Log "Script completed!" -Level INFO -ForegroundColor Green

    # Add timeout to restart prompt to prevent hanging
    $timeoutSeconds = 30
    Write-Log "The computer will restart automatically in $timeoutSeconds seconds" -Level WARNING -ForegroundColor Yellow
    Write-Host "Press 'R' to restart now, 'C' to cancel, or wait for auto-restart" -ForegroundColor Cyan

    $timer = [System.Diagnostics.Stopwatch]::StartNew()
    $userInput = $null

    while ($timer.Elapsed.TotalSeconds -lt $timeoutSeconds -and $null -eq $userInput) {
        if ([Console]::KeyAvailable) {
            $key = [Console]::ReadKey($true)
            $userInput = $key.KeyChar
        }

        # Update countdown
        $remaining = [Math]::Round($timeoutSeconds - $timer.Elapsed.TotalSeconds)
        Write-Host -NoNewline "`rTime remaining: $remaining seconds  "
        Start-Sleep -Milliseconds 100
    }

    Write-Host "" # New line after countdown

    if ($userInput -eq 'r' -or $userInput -eq 'R' -or $null -eq $userInput) {
        Write-Log "Restarting computer..." -Level WARNING -ForegroundColor Green
        Restart-Computer -Force
    } else {
        Write-Log "Restart cancelled by user" -Level WARNING -ForegroundColor Yellow
        Write-Host "Please restart your computer manually when ready" -ForegroundColor Yellow
        Write-Host "Press any key to exit..."
        $null = [Console]::ReadKey($true)
    }
}

#endregion Functions

#region Main Script

try {
    # Check for administrator privileges
    if (-not (Test-Administrator)) {
        Write-Host "This script requires administrator privileges. Please run as administrator." -ForegroundColor Red
        exit 1
    }

    # Initialize environment
    Initialize-Environment

    # Install Chocolatey
    Update-ScriptProgress -Status "Installing package manager (Chocolatey)"
    Install-PackageManager

    # Get user application selection
    Update-ScriptProgress -Status "Selecting applications"
    $selectedApps = Select-Applications

    # Install applications
    Install-ApplicationsParallel -SelectedApps $selectedApps

    # Ask about Windows optimizations
    Update-ScriptProgress -Status "Configuring Windows optimizations"
    Write-Log "=== Windows Optimizations ===" -Level INFO -ForegroundColor Cyan
    Write-Host "Would you like to optimize Windows settings? [Y/N] (Default: Y)" -ForegroundColor Yellow
    $optimizeWindows = Read-Host -Prompt "Your choice"
    if ($optimizeWindows -eq '' -or $optimizeWindows -eq 'Y') {
        # Remove bloatware
        Remove-Bloatware

        # Configure Windows settings
        Set-OptimalWindowsSettings

        # Ask about disabling services
        Write-Host "`nDisable unnecessary Windows services for better performance? [Y/N] (Default: N)" -ForegroundColor Yellow
        $disableServices = Read-Host -Prompt "Your choice"
        if ($disableServices -eq 'Y') {
            Disable-UnnecessaryServices
        }
    } else {
        Write-Log "User skipped Windows optimizations" -Level INFO
    }

    # Configure development environment
    Update-ScriptProgress -Status "Setting up development environment"
    New-DevelopmentFolders

    # Configure Git if installed
    if ($selectedApps -contains "git") {
        Set-GitConfig
    }

    # Install VS Code extensions if VS Code is installed
    if ($selectedApps -contains "vscode") {
        Install-VSCodeExtensions
    }

    # Verify installations
    Update-ScriptProgress -Status "Verifying installations"
    Test-Installations

    # Show summary
    Update-ScriptProgress -Status "Script completed successfully"
    Show-Summary

    # Complete logging
    Complete-ScriptLogging -Success $true

    # Ensure transcript is stopped properly
    try {
        Stop-Transcript
    } catch {
        # Transcript might not be running, that's okay
    }

    # Prompt for restart
    Show-RestartPrompt
} catch {
    Write-Log "Fatal error: $_" -Level CRITICAL -ForegroundColor Red
    Write-Log "Stack trace: $($_.ScriptStackTrace)" -Level ERROR
    Complete-ScriptLogging -Success $false

    Write-Host "`nThe script encountered a fatal error. Please check the log file at: $script:LogPath" -ForegroundColor Red
    Write-Host "Press any key to exit..."
    $null = [Console]::ReadKey($true)
    exit 1
}

#endregion Main Script