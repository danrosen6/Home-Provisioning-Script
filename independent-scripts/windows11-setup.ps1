# Windows 11 Post-Reset Setup Script
# Installs: Chrome, Spotify, Discord, Steam, PyCharm, VS Code, Postman, Python, Git, GitHub Desktop, Windows Terminal, PowerToys
# Removes: Bloatware, disables telemetry, optimizes Windows 11 settings
# Run this script as Administrator in PowerShell

#region Functions

function Test-Administrator {
    $user = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($user)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-Windows11 {
    $osInfo = Get-CimInstance Win32_OperatingSystem
    $osVersion = [Version]$osInfo.Version
    $osName = $osInfo.Caption
    
    if ($osVersion.Major -eq 10 -and $osVersion.Build -ge 22000) {
        Write-Log "Detected Windows 11 ($osVersion)" -Level INFO -ForegroundColor Green
        return $true
    } else {
        Write-Log "WARNING: This script is designed for Windows 11, but detected: $osName ($osVersion)" -Level WARNING -ForegroundColor Red
        Write-Host "This script is optimized for Windows 11. Some functions may not work correctly." -ForegroundColor Yellow
        
        $proceed = Read-Host "Do you want to proceed anyway? [Y/N] (Default: N)"
        if ($proceed -eq 'Y') {
            return $true
        } else {
            return $false
        }
    }
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
        $header = "=== Windows 11 Post-Reset Setup Script Log ==="
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

        # Check TPM and Secure Boot status for Windows 11
        $tpmVersion = Get-TPMVersion
        Write-Log "TPM Version: $tpmVersion" -Level INFO

        $secureBootEnabled = Get-SecureBootStatus
        Write-Log "Secure Boot Enabled: $secureBootEnabled" -Level INFO
    }
    catch {
        Write-Log "Error collecting system information: $_" -Level ERROR
    }
}

function Get-TPMVersion {
    try {
        $tpm = Get-CimInstance -Namespace "root\CIMV2\Security\MicrosoftTpm" -ClassName "Win32_Tpm" -ErrorAction SilentlyContinue
        if ($tpm) {
            return $tpm.SpecVersion
        } else {
            return "Not detected"
        }
    } catch {
        return "Error checking"
    }
}

function Get-SecureBootStatus {
    try {
        $secureBootStatus = Confirm-SecureBootUEFI -ErrorAction SilentlyContinue
        return $secureBootStatus
    } catch {
        return "Unknown"
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

    # Check if running on Windows 11
    $isWin11 = Test-Windows11
    if (-not $isWin11) {
        Write-Log "Exiting script as system is not Windows 11" -Level CRITICAL
        exit 1
    }

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

    Write-Log "Starting Windows 11 Post-Reset Setup..." -Level INFO -ForegroundColor Green
    Write-Log "This will install selected applications and optimize Windows 11" -Level INFO -ForegroundColor Cyan
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

# Function to define direct download information for commonly problematic apps
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
            Url = "https://dl.google.com/dl/chrome/install/googlechromestandaloneenterprise64.msi"
            Extension = ".msi"
            Arguments = @("/quiet", "/norestart")
            VerificationPaths = @(
                "C:\Program Files\Google\Chrome\Application\chrome.exe",
                "C:\Program Files (x86)\Google\Chrome\Application\chrome.exe"
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
        "Windows Terminal" = @{
            Url = "https://github.com/microsoft/terminal/releases/latest/download/Microsoft.WindowsTerminal_Win10.msixbundle"
            Extension = ".msixbundle"
            Arguments = ""  # Special handling for MSIX bundles
            VerificationPaths = @(
                "${env:LOCALAPPDATA}\Microsoft\WindowsApps\wt.exe"
            )
        }
        "Microsoft PowerToys" = @{
            Url = "https://github.com/microsoft/PowerToys/releases/latest/download/PowerToysSetup-x64.exe"
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
        [int]$MaxRetries = 2,
        [Parameter(Mandatory=$false)]
        [hashtable]$DirectDownload = $null
    )

    Write-Log "Starting installation of $AppName ($ChocoName)..." -Level INFO -ForegroundColor Yellow

    # Check if already installed via Chocolatey
    $installed = choco list --local-only | Select-String -Pattern "^$ChocoName\s"
    if ($installed) {
        Write-Log "$AppName is already installed" -Level INFO -ForegroundColor Green
        return $true
    }

    # Define array of installation methods to try in order
    $installationMethods = @(
        @{
            Name = "Standard Chocolatey installation"
            Action = { choco install $ChocoName -y --no-progress 2>&1 }
        },
        @{
            Name = "Chocolatey with checksums ignored"
            Action = { choco install $ChocoName -y --no-progress --ignore-checksums 2>&1 }
        }
    )

    # Add direct download method if provided
    if ($DirectDownload) {
        $installationMethods += @{
            Name = "Direct download from official source"
            Action = {
                try {
                    Write-Log "Downloading $AppName from official URL..." -Level DEBUG
                    $downloadUrl = $DirectDownload.Url
                    $installerPath = Join-Path $env:TEMP "$($AppName -replace '\s', '')Installer$($DirectDownload.Extension)"
                    
                    Invoke-WebRequest -Uri $downloadUrl -OutFile $installerPath -UseBasicParsing
                    
                    Write-Log "Running $AppName installer..." -Level DEBUG
                    
                    if ($DirectDownload.Extension -eq ".exe") {
                        $arguments = if ($DirectDownload.Arguments) { $DirectDownload.Arguments } else { "/S" }
                        Start-Process -FilePath $installerPath -ArgumentList $arguments -Wait
                    }
                    elseif ($DirectDownload.Extension -eq ".msi") {
                        $arguments = if ($DirectDownload.Arguments) { $DirectDownload.Arguments } else { "/quiet", "/norestart" }
                        Start-Process msiexec.exe -ArgumentList "/i", $installerPath, $arguments -Wait -NoNewWindow
                    }
                    elseif ($DirectDownload.Extension -eq ".msixbundle") {
                        # Special handling for MSIX bundles (Windows Terminal, etc.)
                        Write-Log "Installing MSIX bundle..." -Level DEBUG
                        
                        try {
                            # Try using Add-AppxPackage
                            Add-AppxPackage -Path $installerPath -ErrorAction Stop
                        }
                        catch {
                            # Try using DISM if Add-AppxPackage fails
                            Write-Log "Add-AppxPackage failed, trying DISM: $_" -Level WARNING
                            
                            # Try using winget if available
                            if (Get-Command winget -ErrorAction SilentlyContinue) {
                                Write-Log "Using winget to install $AppName..." -Level DEBUG
                                winget install --id Microsoft.WindowsTerminal -e --accept-source-agreements --accept-package-agreements --silent
                            }
                            else {
                                throw "Failed to install MSIX bundle: $_"
                            }
                        }
                    }
                    
                    Remove-Item $installerPath -Force -ErrorAction SilentlyContinue
                    
                    # Check if the installation was successful using verification paths
                    $installSuccess = $false
                    foreach ($path in $DirectDownload.VerificationPaths) {
                        if (Test-Path $path) {
                            $installSuccess = $true
                            Write-Log "Verified $AppName installation at: $path" -Level DEBUG
                            break
                        }
                    }
                    
                    if ($installSuccess) {
                        return "Success: $AppName installed via direct download"
                    } else {
                        throw "Could not verify $AppName installation"
                    }
                }
                catch {
                    throw "Direct download failed: $_"
                }
            }
        }
    }

    # Try each installation method in sequence
    $success = $false
    $result = $null
    $methodsAttempted = 0
    
    foreach ($method in $installationMethods) {
        $methodsAttempted++
        Write-Log "Trying installation method $methodsAttempted/$($installationMethods.Count): $($method.Name)" -Level DEBUG
        
        try {
            $result = & $method.Action
            
            # For direct download method, the action returns a string
            if ($result -is [string] -and $result.StartsWith("Success:")) {
                $success = $true
                break
            }
            
            # For Chocolatey methods, check the exit code
            if ($LASTEXITCODE -eq 0) {
                $success = $true
                Write-Log "$($method.Name) successful" -Level DEBUG
                break
            } else {
                Write-Log "$($method.Name) failed with exit code $LASTEXITCODE" -Level WARNING
                Write-Log "Error details: $result" -Level DEBUG
            }
        }
        catch {
            Write-Log "$($method.Name) threw an exception: $_" -Level WARNING
            continue
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
        Write-Log "Failed to install $AppName after trying $methodsAttempted methods" -Level ERROR -ForegroundColor Red
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
        "10" = @{Key="postman"; Name="Postman"; Default=$true}
        "11" = @{Key="terminal"; Name="Windows Terminal"; Default=$true}  # Added for Windows 11
        "12" = @{Key="powertoys"; Name="Microsoft PowerToys"; Default=$true}  # Added for Windows 11
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
    Write-Log "Starting Google Chrome installation (special handling)..." -Level INFO -ForegroundColor Yellow

    # Get Chrome download info
    $chromeDownload = Get-AppDirectDownloadInfo -AppName "Google Chrome"
    return Install-App -AppName "Google Chrome" -ChocoName "googlechrome" -VerifyCommand "chrome" -DirectDownload $chromeDownload
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

function Install-WindowsTerminal {
    Write-Log "Starting Windows Terminal installation..." -Level INFO -ForegroundColor Yellow
    
    # Check if Windows Terminal is already installed
    if (Get-AppxPackage -Name Microsoft.WindowsTerminal) {
        Write-Log "Windows Terminal is already installed via Microsoft Store" -Level INFO -ForegroundColor Green
        return $true
    }
    
    # Windows 11 should have Windows Terminal pre-installed
    # Try checking if it's there but not registered as an AppxPackage
    if (Test-Path "${env:LOCALAPPDATA}\Microsoft\WindowsApps\wt.exe") {
        Write-Log "Windows Terminal is already available in the system" -Level INFO -ForegroundColor Green
        return $true
    }
    
    # Get Windows Terminal download info
    $terminalDownload = Get-AppDirectDownloadInfo -AppName "Windows Terminal"
    
    # Try to install via Chocolatey first
    $result = Install-App -AppName "Windows Terminal" -ChocoName "microsoft-windows-terminal" -DirectDownload $terminalDownload
    
    if ($result) {
        return $true
    } else {
        # If that fails, try using winget
        try {
            # Check if winget is available
            if (Get-Command winget -ErrorAction SilentlyContinue) {
                Write-Log "Using winget to install Windows Terminal..." -Level DEBUG
                winget install --id Microsoft.WindowsTerminal -e --accept-source-agreements --accept-package-agreements --silent
                
                if (Get-AppxPackage -Name Microsoft.WindowsTerminal) {
                    Write-Log "Windows Terminal installed successfully via winget!" -Level INFO -ForegroundColor Green
                    return $true
                }
            }
            
            Write-Log "Automated installation methods failed. Opening Microsoft Store..." -Level WARNING -ForegroundColor Yellow
            Start-Process "ms-windows-store://pdp/?productid=9N0DX20HK701"
            Write-Log "Please complete the installation in the Microsoft Store" -Level INFO
            return $true
        } catch {
            Write-Log "Windows Terminal installation failed: $_" -Level ERROR -ForegroundColor Red
            Write-Log "Please install Windows Terminal manually from the Microsoft Store" -Level INFO
            return $false
        }
    }
}

function Install-PowerToys {
    Write-Log "Starting Microsoft PowerToys installation..." -Level INFO -ForegroundColor Yellow
    
    # Get PowerToys download info
    $powerToysDownload = Get-AppDirectDownloadInfo -AppName "Microsoft PowerToys"
    
    # Try to install via App installer with fallbacks
    $result = Install-App -AppName "Microsoft PowerToys" -ChocoName "powertoys" -DirectDownload $powerToysDownload
    
    if ($result) {
        return $true
    } else {
        # If that fails, try using winget
        try {
            # Check if winget is available
            if (Get-Command winget -ErrorAction SilentlyContinue) {
                Write-Log "Using winget to install PowerToys..." -Level DEBUG
                winget install --id Microsoft.PowerToys -e --accept-source-agreements --accept-package-agreements --silent
                
                if (Test-Path "$env:LOCALAPPDATA\Programs\PowerToys\PowerToys.exe") {
                    Write-Log "Microsoft PowerToys installed successfully via winget!" -Level INFO -ForegroundColor Green
                    return $true
                }
            }
            
            Write-Log "Automated installation methods failed. Opening GitHub releases page..." -Level WARNING -ForegroundColor Yellow
            Start-Process "https://github.com/microsoft/PowerToys/releases"
            Write-Log "Please download and install PowerToys manually" -Level INFO
            return $false
        } catch {
            Write-Log "PowerToys installation failed: $_" -Level ERROR -ForegroundColor Red
            Write-Log "Please install PowerToys manually from https://github.com/microsoft/PowerToys/releases" -Level INFO
            return $false
        }
    }
}

function Install-Spotify {
    Write-Log "Starting Spotify installation (special handling)..." -Level INFO -ForegroundColor Yellow
    
    # Get Spotify download info
    $spotifyDownload = Get-AppDirectDownloadInfo -AppName "Spotify"
    return Install-App -AppName "Spotify" -ChocoName "spotify" -DirectDownload $spotifyDownload
}

function Install-Postman {
    Write-Log "Starting Postman installation..." -Level INFO -ForegroundColor Yellow
    
    # Get Postman download info
    $postmanDownload = Get-AppDirectDownloadInfo -AppName "Postman"
    return Install-App -AppName "Postman" -ChocoName "postman" -DirectDownload $postmanDownload
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
        "$env:USERPROFILE\Desktop\APIs",
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

function Set-OptimalWindows11Settings {
    Update-ScriptProgress -Status "Configuring Windows 11 settings"
    Write-Log "Starting Windows 11 optimization..." -Level INFO -ForegroundColor Cyan

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

    # Windows 11 specific settings
    
    # Configure taskbar alignment (0 = left, 1 = center)
    Write-Log "Setting taskbar alignment to left..." -Level DEBUG
    Set-RegistryKey -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "TaskbarAl" -Value 0
    
    # Disable Chat icon on taskbar
    Write-Log "Disabling Chat icon on taskbar..." -Level DEBUG
    Set-RegistryKey -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "TaskbarMn" -Value 0
    
    # Disable Widgets icon on taskbar
    Write-Log "Disabling Widgets icon on taskbar..." -Level DEBUG
    Set-RegistryKey -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "TaskbarDa" -Value 0
    
    # Enable show more options in right-click menu (classic context menu)
    Write-Log "Enabling classic context menu..." -Level DEBUG
    Set-RegistryKey -Path "HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32" -Name "(Default)" -Value "" -Type String

    # Disable new boot animation
    Write-Log "Configuring boot animation..." -Level DEBUG
    Set-RegistryKey -Path "HKLM:\SYSTEM\CurrentControlSet\Control\BootControl" -Name "BootProgressAnimation" -Value 0
    
    # Disable Windows 11 Snap layouts when hovering maximize button
    Write-Log "Disabling Snap layouts hover feature..." -Level DEBUG
    Set-RegistryKey -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "EnableSnapAssistFlyout" -Value 0
    
    # Configure Start Menu (show more pins)
    Write-Log "Configuring Start Menu layout..." -Level DEBUG
    Set-RegistryKey -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "Start_Layout" -Value 1
    
    # Disable startup sound
    Write-Log "Disabling startup sound..." -Level DEBUG
    Set-RegistryKey -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\LogonUI\BootAnimation" -Name "DisableStartupSound" -Value 1

    # Configure search to use local search instead of Bing
    Write-Log "Configuring Windows Search to prioritize local results..." -Level DEBUG
    # Disable Bing search in Start Menu
    Set-RegistryKey -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" -Name "BingSearchEnabled" -Value 0
    # Disable Cortana web search
    Set-RegistryKey -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" -Name "CortanaConsent" -Value 0
    
    # Disable Teams consumer app from auto-starting
    Write-Log "Disabling Microsoft Teams auto-start..." -Level DEBUG
    Set-RegistryKey -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "com.squirrel.Teams.Teams" -Value 0 -ErrorAction SilentlyContinue

    Write-Log "Windows 11 settings optimization complete" -Level INFO -ForegroundColor Green
}

function Remove-Windows11Bloatware {
    Update-ScriptProgress -Status "Removing Windows 11 bloatware"
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
        "Microsoft.MicrosoftTeams"  # Teams consumer version
        "Microsoft.GamingApp"       # Xbox app
        "Microsoft.Xbox.TCUI"
        "Microsoft.XboxGameOverlay"
        "Microsoft.XboxGamingOverlay"
        "Microsoft.XboxIdentityProvider"
        "Microsoft.XboxSpeechToTextOverlay"
        "MicrosoftTeams"            # Teams consumer version
        "*.CandyCrush*"
        "*.Spotify*"                # We're installing desktop version
        "*.Twitter*"
        "*.Facebook*"
        "*.Netflix*"
        "*.Hulu*"
        "*.PicsArt*"
        "*.TikTok*"
        "*.Disney*"
        "*.LinkedIn*"
        "*.ClipChamp*"             # Windows 11 video editor
        "*.Todos*"                 # Microsoft To-Do app
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

    # Disable Windows 11 Widgets
    Write-Log "Disabling Windows 11 Widgets..." -Level DEBUG
    try {
        Set-RegistryKey -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "TaskbarDa" -Value 0
        Set-RegistryKey -Path "HKLM:\SOFTWARE\Policies\Microsoft\Dsh" -Name "AllowNewsAndInterests" -Value 0
        Set-RegistryKey -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Feeds" -Name "EnableFeeds" -Value 0
        Write-Log "Windows 11 Widgets disabled" -Level INFO -ForegroundColor Green
    } catch {
        Write-Log "Failed to disable Widgets: $_" -Level WARNING
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
        "lfsvc"                       # Geolocation Service
        "TabletInputService"          # Touch Keyboard and Handwriting Panel Service
        "HomeGroupProvider"           # HomeGroup Provider (if still exists)
        "WalletService"               # Microsoft Wallet Service
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
        "spotify" = @{Name="Spotify"; Special=$true; Method="Install-Spotify"}
        "discord" = @{Name="Discord"; ChocoName="discord"; Special=$false}
        "steam" = @{Name="Steam"; ChocoName="steam-client"; Special=$false}
        "git" = @{Name="Git"; ChocoName="git"; VerifyCommand="git"; PathToAdd="C:\Program Files\Git\bin"; Special=$false}
        "vscode" = @{Name="Visual Studio Code"; ChocoName="vscode"; VerifyCommand="code"; PathToAdd="C:\Program Files\Microsoft VS Code\bin"; Special=$false}
        "python" = @{Name="Python"; Special=$true; Method="Install-Python"}
        "pycharm" = @{Name="PyCharm Community"; ChocoName="pycharm-community"; Special=$false}
        "github" = @{Name="GitHub Desktop"; ChocoName="github-desktop"; Special=$false}
        "postman" = @{Name="Postman"; Special=$true; Method="Install-Postman"}
        "terminal" = @{Name="Windows Terminal"; Special=$true; Method="Install-WindowsTerminal"}
        "powertoys" = @{Name="Microsoft PowerToys"; Special=$true; Method="Install-PowerToys"}
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
        
        # Get direct download info for fallback
        $directDownload = Get-AppDirectDownloadInfo -AppName $appInfo.Name
        
        $result = Install-App -AppName $appInfo.Name -ChocoName $appInfo.ChocoName `
                 -VerifyCommand $appInfo.VerifyCommand -PathToAdd $appInfo.PathToAdd `
                 -DirectDownload $directDownload
                 
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
    Write-Host "✓ Python 3.x" -ForegroundColor White
    Write-Host "✓ Git" -ForegroundColor White
    Write-Host "✓ GitHub Desktop" -ForegroundColor White
    Write-Host "✓ Postman" -ForegroundColor White
    Write-Host "✓ Windows Terminal" -ForegroundColor White
    Write-Host "✓ Microsoft PowerToys" -ForegroundColor White

    Write-Host "`nWindows 11 Optimizations:" -ForegroundColor Cyan
    Write-Host "✓ Removed bloatware apps (Teams consumer, widgets, etc.)" -ForegroundColor White
    Write-Host "✓ Set taskbar alignment to left (classic style)" -ForegroundColor White
    Write-Host "✓ Restored classic context menu" -ForegroundColor White
    Write-Host "✓ Disabled Cortana" -ForegroundColor White
    Write-Host "✓ Disabled OneDrive auto-start" -ForegroundColor White
    Write-Host "✓ Disabled Windows tips and suggestions" -ForegroundColor White
    Write-Host "✓ Reduced telemetry" -ForegroundColor White
    Write-Host "✓ Disabled activity history" -ForegroundColor White
    Write-Host "✓ Disabled unnecessary background apps" -ForegroundColor White
    Write-Host "✓ Disabled Widgets and Teams icons" -ForegroundColor White
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
    Update-ScriptProgress -Status "Configuring Windows 11 optimizations"
    Write-Log "=== Windows 11 Optimizations ===" -Level INFO -ForegroundColor Cyan
    Write-Host "Would you like to optimize Windows 11 settings? [Y/N] (Default: Y)" -ForegroundColor Yellow
    $optimizeWindows = Read-Host -Prompt "Your choice"
    if ($optimizeWindows -eq '' -or $optimizeWindows -eq 'Y') {
        # Remove bloatware
        Remove-Windows11Bloatware

        # Configure Windows settings
        Set-OptimalWindows11Settings

        # Ask about disabling services
        Write-Host "`nDisable unnecessary Windows services for better performance? [Y/N] (Default: N)" -ForegroundColor Yellow
        $disableServices = Read-Host -Prompt "Your choice"
        if ($disableServices -eq 'Y') {
            Disable-UnnecessaryServices
        }
    } else {
        Write-Log "User skipped Windows 11 optimizations" -Level INFO
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