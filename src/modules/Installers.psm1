# Installation modules for Windows Setup GUI

# Global variables
$script:UseDirectDownloadOnly = $false
$script:MaxRetries = 3
$script:RetryDelay = 5 # seconds
$script:InstallerTimeoutMinutes = 5 # Timeout for installer processes

# Function to run processes with timeout to prevent hanging
function Start-ProcessWithTimeout {
    param(
        [Parameter(Mandatory=$true)]
        [string]$FilePath,
        
        [Parameter(Mandatory=$false)]
        [string[]]$ArgumentList = @(),
        
        [Parameter(Mandatory=$false)]
        [int]$TimeoutMinutes = $script:InstallerTimeoutMinutes,
        
        [Parameter(Mandatory=$false)]
        [switch]$NoNewWindow = $false,
        
        [Parameter(Mandatory=$false)]
        [System.Threading.CancellationToken]$CancellationToken = [System.Threading.CancellationToken]::None
    )
    
    try {
        Write-LogMessage "Starting process: $FilePath with timeout: ${TimeoutMinutes}m" -Level "INFO"
        
        # Start the process
        $processParams = @{
            FilePath = $FilePath
            ArgumentList = $ArgumentList
            PassThru = $true
            NoNewWindow = $NoNewWindow
        }
        
        $process = Start-Process @processParams
        
        # Wait for completion or timeout, checking for cancellation
        $timeoutMs = $TimeoutMinutes * 60 * 1000
        $checkIntervalMs = 1000 # Check for cancellation every second
        $elapsed = 0
        
        while ($elapsed -lt $timeoutMs -and -not $process.HasExited) {
            # Check for cancellation
            if ($CancellationToken -and $CancellationToken -ne [System.Threading.CancellationToken]::None -and $CancellationToken.IsCancellationRequested) {
                Write-LogMessage "Process cancelled by user request" -Level "WARNING"
                try {
                    $process.Kill()
                    $process.WaitForExit(5000)
                } catch {
                    Write-LogMessage "Error killing cancelled process: $_" -Level "ERROR"
                }
                
                return [PSCustomObject]@{
                    ExitCode = -3
                    HasExited = $true
                    Id = $process.Id
                    Cancelled = $true
                }
            }
            
            Start-Sleep -Milliseconds $checkIntervalMs
            $elapsed += $checkIntervalMs
        }
        
        $completed = $process.HasExited
        
        if ($completed) {
            Write-LogMessage "Process completed with exit code: $($process.ExitCode)" -Level "INFO"
            return $process
        } else {
            # Timeout occurred
            Write-LogMessage "Process timed out after $TimeoutMinutes minutes, killing process" -Level "WARNING"
            
            try {
                $process.Kill()
                $process.WaitForExit(5000) # Wait up to 5 seconds for cleanup
            } catch {
                Write-LogMessage "Error killing timed-out process: $_" -Level "ERROR"
            }
            
            # Return a process-like object with timeout exit code
            return [PSCustomObject]@{
                ExitCode = -1
                HasExited = $true
                Id = $process.Id
                TimedOut = $true
            }
        }
    }
    catch {
        Write-LogMessage "Error starting process: $_" -Level "ERROR"
        return [PSCustomObject]@{
            ExitCode = -2
            HasExited = $true
            Id = -1
            Error = $_.Exception.Message
        }
    }
}

# Import the centralized logging system
$LoggingModule = Join-Path (Split-Path $PSScriptRoot) "utils\Logging.psm1"
if (Test-Path $LoggingModule) {
    Import-Module $LoggingModule -Force -Global
    Write-Verbose "Imported centralized logging module"
} else {
    # Fallback Write-LogMessage function if centralized logging is not available
    function Write-LogMessage {
        param (
            [Parameter(Mandatory=$true)]
            [string]$Message,
            
            [Parameter(Mandatory=$false)]
            [ValidateSet("INFO", "WARNING", "ERROR", "SUCCESS", "DEBUG")]
            [string]$Level = "INFO"
        )
        
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $logMessage = "[$timestamp] [$Level] $Message"
        
        # Write to console with color
        $color = switch ($Level) {
            "ERROR" { "Red" }
            "WARNING" { "Yellow" }
            "SUCCESS" { "Green" }
            "DEBUG" { "Gray" }
            default { "White" }
        }
        Write-Host $logMessage -ForegroundColor $color
        
        # Try to write to GUI if available
        if ($script:txtLog -ne $null) {
            try {
                $script:txtLog.SelectionColor = switch ($Level) {
                    "ERROR" { [System.Drawing.Color]::Red }
                    "WARNING" { [System.Drawing.Color]::Orange }
                    "SUCCESS" { [System.Drawing.Color]::Green }
                    default { [System.Drawing.Color]::Black }
                }
                $script:txtLog.AppendText("$logMessage`r`n")
                $script:txtLog.SelectionStart = $script:txtLog.Text.Length
                $script:txtLog.ScrollToCaret()
            }
            catch {
                Write-Host "Error updating log textbox: $_" -ForegroundColor Red
            }
        }
        
        # Write to log file if enabled
        if ($script:EnableFileLogging -and $script:LogPath) {
            try {
                Add-Content -Path $script:LogPath -Value $logMessage -ErrorAction Stop
            }
            catch {
                Write-Host "Failed to write to log file: $_" -ForegroundColor Red
            }
        }
    }
    Write-Warning "Centralized logging module not found, using fallback logging"
}

# Function to get the latest version URLs dynamically
function Get-LatestVersionUrl {
    param (
        [Parameter(Mandatory=$true)]
        [string]$ApplicationName
    )
    
    switch ($ApplicationName) {
        "Git" {
            try {
                # Get latest Git release information
                $apiUrl = "https://api.github.com/repos/git-for-windows/git/releases/latest"
                $releaseInfo = Invoke-RestMethod -Uri $apiUrl -TimeoutSec 10 -ErrorAction Stop
                
                # Find the 64-bit installer asset
                $asset = $releaseInfo.assets | Where-Object { $_.name -like "Git-*-64-bit.exe" } | Select-Object -First 1
                
                if ($asset) {
                    return $asset.browser_download_url
                }
            } catch {
                Write-LogMessage "Error getting latest Git version: $_" -Level "WARNING"
            }
            # Fallback to a known URL pattern without version
            return "https://github.com/git-for-windows/git/releases/download/v2.49.0.windows.1/Git-2.49.0-64-bit.exe"
        }
        "Python" {
            try {
                # Get Python versions from the website
                $webRequest = Invoke-WebRequest -Uri "https://www.python.org/downloads/windows/" -UseBasicParsing -TimeoutSec 15 -ErrorAction Stop
                
                # Extract the latest Python 3 version
                if ($webRequest.Content -match "Latest Python 3 Release - Python (3\.\d+\.\d+)") {
                    $latestVersion = $matches[1]
                    return "https://www.python.org/ftp/python/$latestVersion/python-$latestVersion-amd64.exe"
                }
            } catch {
                Write-LogMessage "Error getting latest Python version: $_" -Level "WARNING"
            }
            # Fallback to a reasonably current version
            return "https://www.python.org/ftp/python/3.13.4/python-3.13.4-amd64.exe"
        }
        "PyCharm" {
            try {
                # Get latest PyCharm version from JetBrains website
                $webRequest = Invoke-WebRequest -Uri "https://data.services.jetbrains.com/products/releases?code=PCC&latest=true&type=release" -UseBasicParsing -TimeoutSec 15 -ErrorAction Stop
                
                $releaseInfo = $webRequest.Content | ConvertFrom-Json
                $latestVersion = $releaseInfo.PCC[0].version
                $downloadUrl = $releaseInfo.PCC[0].downloads.windows.link
                
                if ($downloadUrl) {
                    return $downloadUrl
                }
            } catch {
                Write-LogMessage "Error getting latest PyCharm version: $_" -Level "WARNING"
            }
            # Fallback to a known URL pattern
            return "https://download.jetbrains.com/python/pycharm-community-latest.exe"
        }
        "VLC" {
            try {
                # Get VLC version information
                $webRequest = Invoke-WebRequest -Uri "https://www.videolan.org/vlc/download-windows.html" -UseBasicParsing -TimeoutSec 15 -ErrorAction Stop
                
                # Extract the latest version
                if ($webRequest.Content -match "vlc-(\d+\.\d+\.\d+)-win64.exe") {
                    $latestVersion = $matches[1]
                    return "https://get.videolan.org/vlc/$latestVersion/win64/vlc-$latestVersion-win64.exe"
                }
            } catch {
                Write-LogMessage "Error getting latest VLC version: $_" -Level "WARNING"
            }
            # Fallback to a mirror that may have the latest version
            return "https://download.videolan.org/pub/videolan/vlc/last/win64/vlc-latest-win64.exe"
        }
        "7-Zip" {
            try {
                # Get 7-Zip version from website
                $webRequest = Invoke-WebRequest -Uri "https://www.7-zip.org/download.html" -UseBasicParsing -TimeoutSec 15 -ErrorAction Stop
                
                # Extract the latest version for 64-bit Windows
                if ($webRequest.Content -match "Download 7-Zip ([\d\.]+) \((?:\d{4}-\d{2}-\d{2})\) for Windows") {
                    $latestVersion = $matches[1]
                    $formattedVersion = $latestVersion -replace "\.", ""
                    return "https://www.7-zip.org/a/7z$formattedVersion-x64.exe"
                }
            } catch {
                Write-LogMessage "Error getting latest 7-Zip version: $_" -Level "WARNING"
            }
            # Fallback to a recent version
            return "https://www.7-zip.org/a/7z2409-x64.exe"
        }
        "Notepad++" {
            try {
                # Get latest Notepad++ release from GitHub
                $apiUrl = "https://api.github.com/repos/notepad-plus-plus/notepad-plus-plus/releases/latest"
                $releaseInfo = Invoke-RestMethod -Uri $apiUrl -TimeoutSec 10 -ErrorAction Stop
                
                # Find the 64-bit installer asset
                $asset = $releaseInfo.assets | Where-Object { $_.name -like "*Installer.x64.exe" } | Select-Object -First 1
                
                if ($asset) {
                    return $asset.browser_download_url
                }
            } catch {
                Write-LogMessage "Error getting latest Notepad++ version: $_" -Level "WARNING"
            }
            # Fallback to a URL that should redirect to the latest version
            return "https://github.com/notepad-plus-plus/notepad-plus-plus/releases/download/v8.8.1/npp.8.8.1.Installer.x64.exe"
        }
        default {
            # For all other applications, use the existing hardcoded URLs
            return $null
        }
    }
}

# Function to test if an application is installed
function Test-ApplicationInstalled {
    param (
        [Parameter(Mandatory=$true)]
        [string]$AppName,
        
        [Parameter(Mandatory=$false)]
        [string[]]$VerificationPaths = @(),
        
        [Parameter(Mandatory=$false)]
        [string]$RegistryPath = "",
        
        [Parameter(Mandatory=$false)]
        [string]$RegistryValue = "",
        
        [Parameter(Mandatory=$false)]
        [switch]$CheckCommand = $false,
        
        [Parameter(Mandatory=$false)]
        [string]$WingetId = ""
    )
    
    Write-LogMessage "Verifying installation for $AppName..." -Level "INFO"
    
    # First try winget-based detection if WingetId is provided and winget is available
    if ($WingetId -and (Get-Command winget -ErrorAction SilentlyContinue)) {
        try {
            $wingetList = winget list --id $WingetId --exact 2>$null
            if ($LASTEXITCODE -eq 0 -and $wingetList -and $wingetList -notmatch "No installed package found") {
                Write-LogMessage "Installation verified: Found $AppName via winget (ID: $WingetId)" -Level "SUCCESS"
                return $true
            }
        } catch {
            Write-LogMessage "Winget verification failed for $AppName, trying other methods..." -Level "DEBUG"
        }
    }
    
    # Try registry-based detection for common Windows programs
    try {
        $registryPaths = @(
            "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
            "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
            "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*"
        )
        
        foreach ($regPath in $registryPaths) {
            $installedPrograms = Get-ItemProperty $regPath -ErrorAction SilentlyContinue | Where-Object {
                $_.DisplayName -like "*$AppName*" -or 
                $_.DisplayName -like "*$(($AppName -split ' ')[0])*" -or
                ($AppName -eq "Google Chrome" -and $_.DisplayName -like "*Chrome*") -or
                ($AppName -eq "Mozilla Firefox" -and $_.DisplayName -like "*Firefox*") -or
                ($AppName -eq "Visual Studio Code" -and $_.DisplayName -like "*Visual Studio Code*") -or
                ($AppName -eq "7-Zip" -and $_.DisplayName -like "*7-Zip*") -or
                ($AppName -eq "Notepad++" -and $_.DisplayName -like "*Notepad++*")
            }
            
            if ($installedPrograms) {
                Write-LogMessage "Installation verified: Found $AppName in registry: $($installedPrograms[0].DisplayName)" -Level "SUCCESS"
                return $true
            }
        }
    } catch {
        Write-LogMessage "Registry check failed for $AppName, trying other methods..." -Level "DEBUG"
    }
    
    # First try checking verification paths if provided
    if ($VerificationPaths -and $VerificationPaths.Count -gt 0) {
        foreach ($path in $VerificationPaths) {
            # Handle wildcard paths specially
            if ($path -match "\*") {
                $directory = Split-Path -Parent $path
                $filename = Split-Path -Leaf $path
                
                # Skip if the base directory doesn't exist
                if (-not (Test-Path $directory)) {
                    continue
                }
                
                # Try to find matching files
                $matchingFiles = Get-ChildItem -Path $directory -Recurse -Filter $filename -ErrorAction SilentlyContinue
                if ($matchingFiles -and $matchingFiles.Count -gt 0) {
                    Write-LogMessage "Installation verified: Found $($matchingFiles[0].FullName) for $AppName" -Level "SUCCESS"
                    return $true
                }
                
                # For directories like Discord with version-numbered folders
                if ($path -match "app-\*") {
                    $parentDir = Split-Path -Parent $directory
                    $folderPattern = Split-Path -Leaf $directory
                    $fileNameToFind = $filename
                    
                    # Skip if the parent directory doesn't exist
                    if (-not (Test-Path $parentDir)) {
                        continue
                    }
                    
                    # Find version folders
                    $versionFolders = Get-ChildItem -Path $parentDir -Directory -Filter $folderPattern.Replace("*", "*") -ErrorAction SilentlyContinue
                    
                    foreach ($folder in $versionFolders) {
                        $potentialPath = Join-Path $folder.FullName $fileNameToFind
                        if (Test-Path $potentialPath) {
                            Write-LogMessage "Installation verified: Found $potentialPath for $AppName" -Level "SUCCESS"
                            return $true
                        }
                    }
                }
            }
            else {
                if (Test-Path $path) {
                    Write-LogMessage "Installation verified: Found $path for $AppName" -Level "SUCCESS"
                    return $true
                }
            }
        }
    }
    
    # Check registry if path provided
    if ($RegistryPath -and $RegistryValue) {
        try {
            $regValue = Get-ItemProperty -Path $RegistryPath -Name $RegistryValue -ErrorAction SilentlyContinue
            if ($regValue -and $regValue.$RegistryValue) {
                Write-LogMessage "Installation verified: Found registry entry for $AppName" -Level "SUCCESS"
                return $true
            }
        }
        catch {
            # Registry check failed, continue to other methods
        }
    }
    
    # Check command availability if requested
    if ($CheckCommand) {
        $appCommand = $AppName
        # Map some app names to their command names
        $commandMap = @{
            "Visual Studio Code" = "code"
            "Google Chrome" = "chrome"
            "Mozilla Firefox" = "firefox"
            "Git" = "git"
            "Python" = "python"
            "Notepad++" = "notepad++"
            "7-Zip" = "7z"
        }
        
        if ($commandMap.ContainsKey($AppName)) {
            $appCommand = $commandMap[$AppName]
        }
        
        if (Get-Command $appCommand -ErrorAction SilentlyContinue) {
            Write-LogMessage "Installation verified: Command '$appCommand' is available for $AppName" -Level "SUCCESS"
            return $true
        }
    }
    
    # For Windows 10/11 UWP apps
    if ($AppName -match "Microsoft|Windows") {
        try {
            $appxPackage = Get-AppxPackage -Name "*$AppName*" -ErrorAction SilentlyContinue
            if ($appxPackage) {
                Write-LogMessage "Installation verified: Found UWP package for $AppName" -Level "SUCCESS"
                return $true
            }
        }
        catch {
            # AppX check failed, continue
        }
    }
    
    # Try Windows Features for specific items
    if ($AppName -match "Windows Terminal|PowerToys") {
        try {
            # Check Microsoft Store apps
            $storeApp = Get-AppxPackage -Name "*$AppName*" -ErrorAction SilentlyContinue
            if ($storeApp) {
                Write-LogMessage "Installation verified: Found Microsoft Store app for $AppName" -Level "SUCCESS"
                return $true
            }
        }
        catch {
            # Store app check failed
        }
    }
    
    Write-LogMessage "Could not verify installation for $AppName" -Level "WARNING"
    return $false
}

# Legacy function - kept for backward compatibility during transition
# All download info is now stored in apps.json and accessed via Get-AppDownloadInfo
function Get-AppDirectDownloadInfo {
    param(
        [Parameter(Mandatory=$true)]
        [string]$AppName
    )
    
    Write-LogMessage "Using legacy Get-AppDirectDownloadInfo for $AppName - consider updating to use AppKey and JSON config" -Level "DEBUG"
    
    # Return null to force fallback to old hardcoded mapping if needed
    # This function is kept for compatibility but should be replaced
    return $null
}

function Test-InstalledVersion {
    param (
        [Parameter(Mandatory=$true)]
        [string]$AppName,
        
        [Parameter(Mandatory=$false)]
        [string]$Version
    )
    
    try {
        switch ($AppName) {
            "Python" {
                $pythonVersion = python --version 2>&1
                if ($pythonVersion -match "Python (\d+\.\d+\.\d+)") {
                    return $matches[1]
                }
            }
            "Git" {
                $gitVersion = git --version
                if ($gitVersion -match "git version (\d+\.\d+\.\d+)") {
                    return $matches[1]
                }
            }
            # Add more version checks for other apps
        }
    }
    catch {
        return $null
    }
    
    return $null
}

function Test-FileChecksum {
    param (
        [Parameter(Mandatory=$true)]
        [string]$FilePath,
        
        [Parameter(Mandatory=$true)]
        [string]$ExpectedChecksum
    )
    
    try {
        $hash = Get-FileHash -Path $FilePath -Algorithm SHA256
        return $hash.Hash -eq $ExpectedChecksum.Split(':')[1]
    }
    catch {
        Write-LogMessage "Failed to verify file checksum: $_" -Level "ERROR"
        return $false
    }
}

function Install-Winget {
    [CmdletBinding()]
    param(
        [System.Threading.CancellationToken]$CancellationToken
    )
    
    Write-LogMessage "Starting winget installation..." -Level "INFO"
    
    # Check for cancellation
    if ($CancellationToken.IsCancellationRequested) {
        Write-LogMessage "Winget installation cancelled" -Level "WARNING"
        return $false
    }
    
    # Check Windows version compatibility first
    $buildNumber = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion").CurrentBuild
    $osName = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion").ProductName
    
    Write-LogMessage "System: $osName (Build $buildNumber)" -Level "INFO"
    
    if ([int]$buildNumber -lt 16299) {
        Write-LogMessage "Windows build $buildNumber is below minimum requirement for winget (16299 = Windows 10 1709)" -Level "ERROR"
        Write-LogMessage "Winget is not supported on this Windows version" -Level "ERROR"
        return $false
    }
    
    # Check if winget is already installed
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        $version = winget --version 2>$null
        Write-LogMessage "Winget is already installed: $version" -Level "INFO"
        return $true
    }
    
    # Create src-specific download directory
    $scriptPath = Split-Path -Parent $PSScriptRoot
    $downloadDir = Join-Path $scriptPath "downloads"
    if (-not (Test-Path $downloadDir)) {
        New-Item -ItemType Directory -Path $downloadDir -Force | Out-Null
        Write-LogMessage "Created download directory at: $downloadDir" -Level "INFO"
    }
    
    # Check if App Installer is already present but winget not registered
    $appInstaller = Get-AppxPackage -Name "Microsoft.DesktopAppInstaller" -ErrorAction SilentlyContinue
    if ($appInstaller) {
        Write-LogMessage "App Installer found: $($appInstaller.Version)" -Level "INFO"
        Write-LogMessage "Attempting to register winget using Microsoft's recommended method..." -Level "INFO"
        
        try {
            # First try the standard registration
            Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe
            Write-LogMessage "Winget registration command completed" -Level "INFO"
            
            # Wait longer and verify multiple times
            for ($i = 0; $i -lt 6; $i++) {
                Start-Sleep -Seconds 3
                # Refresh environment variables
                $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
                
                if (Get-Command winget -ErrorAction SilentlyContinue) {
                    $version = winget --version 2>$null
                    if ($version) {
                        Write-LogMessage "Winget successfully registered: $version" -Level "SUCCESS"
                        return $true
                    }
                }
                Write-LogMessage "Waiting for winget registration to complete... (attempt $($i + 1)/6)" -Level "INFO"
            }
            
            # Try PowerShell module approach as fallback
            Write-LogMessage "Standard registration not working, trying PowerShell module approach..." -Level "INFO"
            try {
                # Install WinGet PowerShell module if available
                Install-PackageProvider -Name NuGet -Force -Scope CurrentUser | Out-Null
                Install-Module -Name Microsoft.WinGet.Client -Force -Repository PSGallery -Scope CurrentUser | Out-Null
                Import-Module Microsoft.WinGet.Client -Force
                
                # Use Repair-WinGetPackageManager cmdlet
                Repair-WinGetPackageManager -Force
                
                # Wait and verify
                Start-Sleep -Seconds 5
                if (Get-Command winget -ErrorAction SilentlyContinue) {
                    $version = winget --version 2>$null
                    if ($version) {
                        Write-LogMessage "Winget successfully installed via PowerShell module: $version" -Level "SUCCESS"
                        return $true
                    }
                }
            } catch {
                Write-LogMessage "PowerShell module approach failed: $_" -Level "WARNING"
            }
            
            Write-LogMessage "Winget registration completed but command not yet available" -Level "WARNING"
            Write-LogMessage "This may require a new PowerShell session or user logout/login" -Level "INFO"
            
        } catch {
            Write-LogMessage "Failed to register winget: $_" -Level "WARNING"
        }
    }
    
    # Skip Microsoft Store installation - proceed directly to automated download
    Write-LogMessage "Proceeding with automated winget installation..." -Level "INFO"
    
    # Fallback to direct download
    Write-LogMessage "Attempting direct download of winget..." -Level "INFO"
    try {
        # Create winget-specific directory
        $wingetDir = Join-Path $downloadDir "winget"
        if (-not (Test-Path $wingetDir)) {
            New-Item -ItemType Directory -Path $wingetDir -Force | Out-Null
            Write-LogMessage "Created winget directory at: $wingetDir" -Level "INFO"
        }
        
        # Download the latest winget release
        $releaseUrl = "https://api.github.com/repos/microsoft/winget-cli/releases/latest"
        Write-LogMessage "Fetching latest winget release information..." -Level "INFO"
        $release = Invoke-RestMethod -Uri $releaseUrl -TimeoutSec 15
        $msixBundle = $release.assets | Where-Object { $_.name -like "*.msixbundle" } | Select-Object -First 1
        
        if ($null -eq $msixBundle) {
            Write-LogMessage "Could not find winget MSIX bundle" -Level "ERROR"
            return $false
        }
        
        $downloadPath = Join-Path $wingetDir $msixBundle.name
        Write-LogMessage "Downloading winget bundle to: $downloadPath" -Level "INFO"
        
        # Download with progress reporting
        $webClient = New-Object System.Net.WebClient
        $webClient.DownloadFile($msixBundle.browser_download_url, $downloadPath)
        
        # Verify download
        if (-not (Test-Path $downloadPath)) {
            Write-LogMessage "Download failed - file not found at expected location" -Level "ERROR"
            return $false
        }
        
        Write-LogMessage "Download completed successfully" -Level "SUCCESS"
        
        # Install the bundle (with comprehensive dependency handling)
        Write-LogMessage "Installing winget package..." -Level "INFO"
        $wingetInstalled = $false
        
        try {
            Add-AppxPackage -Path $downloadPath -ErrorAction Stop
            $wingetInstalled = $true
            Write-LogMessage "Winget installed successfully via direct package installation" -Level "SUCCESS"
        } catch {
            $errorMessage = $_.Exception.Message
            Write-LogMessage "Direct installation failed: $errorMessage" -Level "WARNING"
            
            # Try PowerShell module method first (most reliable for dependency handling)
            Write-LogMessage "Attempting PowerShell module installation to handle dependencies..." -Level "INFO"
            try {
                # Install NuGet provider and WinGet module
                [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
                Install-PackageProvider -Name NuGet -Force -Scope CurrentUser | Out-Null
                Install-Module -Name Microsoft.WinGet.Client -Force -Repository PSGallery -Scope CurrentUser -AllowClobber | Out-Null
                Import-Module Microsoft.WinGet.Client -Force
                
                # Use Repair-WinGetPackageManager to handle dependencies automatically
                Write-LogMessage "Running Repair-WinGetPackageManager to install winget with dependencies..." -Level "INFO"
                Repair-WinGetPackageManager -Force
                
                # Verify installation
                Start-Sleep -Seconds 5
                if (Get-Command winget -ErrorAction SilentlyContinue) {
                    $version = winget --version 2>$null
                    if ($version) {
                        Write-LogMessage "Winget successfully installed via PowerShell module: $version" -Level "SUCCESS"
                        $wingetInstalled = $true
                    }
                }
            } catch {
                Write-LogMessage "PowerShell module method failed: $_" -Level "WARNING"
            }
            
            # If PowerShell module method failed, try manual dependency installation
            if (-not $wingetInstalled) {
                Write-LogMessage "Attempting manual dependency installation..." -Level "INFO"
                try {
                    # Download and install Microsoft.UI.Xaml.2.8 framework
                    $uiXamlUrl = "https://www.nuget.org/api/v2/package/Microsoft.UI.Xaml/2.8.6"
                    $uiXamlNupkg = Join-Path $wingetDir "Microsoft.UI.Xaml.2.8.6.nupkg"
                    
                    Write-LogMessage "Downloading Microsoft.UI.Xaml framework from NuGet..." -Level "INFO"
                    $webClient = New-Object System.Net.WebClient
                    $webClient.DownloadFile($uiXamlUrl, $uiXamlNupkg)
                    
                    # Extract nupkg (it's a zip file)
                    $extractPath = Join-Path $wingetDir "xaml_extract"
                    if (Test-Path $extractPath) { Remove-Item $extractPath -Recurse -Force }
                    
                    Add-Type -AssemblyName System.IO.Compression.FileSystem
                    [System.IO.Compression.ZipFile]::ExtractToDirectory($uiXamlNupkg, $extractPath)
                    
                    # Find and install the x64 appx file
                    $appxFiles = Get-ChildItem -Path $extractPath -Recurse -Filter "*.appx" | Where-Object { 
                        $_.Name -like "*x64*" -or $_.Name -like "*neutral*" 
                    }
                    
                    foreach ($appxFile in $appxFiles) {
                        try {
                            Write-LogMessage "Installing framework: $($appxFile.Name)" -Level "INFO"
                            Add-AppxPackage -Path $appxFile.FullName -ForceApplicationShutdown -ErrorAction SilentlyContinue
                        } catch {
                            Write-LogMessage "Framework install attempt: $_" -Level "DEBUG"
                        }
                    }
                    
                    # Clean up
                    Remove-Item $extractPath -Recurse -Force -ErrorAction SilentlyContinue
                    Remove-Item $uiXamlNupkg -Force -ErrorAction SilentlyContinue
                    
                    # Retry winget installation
                    Write-LogMessage "Retrying winget installation after framework install..." -Level "INFO"
                    Add-AppxPackage -Path $downloadPath -ErrorAction Stop
                    $wingetInstalled = $true
                    Write-LogMessage "Winget installed successfully after dependency installation" -Level "SUCCESS"
                    
                } catch {
                    Write-LogMessage "Manual dependency installation failed: $_" -Level "ERROR"
                }
            }
            
            # Final fallback - throw error if all methods failed
            if (-not $wingetInstalled) {
                throw "All winget installation methods failed. Cannot proceed with winget as primary install method."
            }
        }
        
        # Clean up download
        Remove-Item $downloadPath -Force -ErrorAction SilentlyContinue
        Write-LogMessage "Cleaned up downloaded package" -Level "INFO"
        
        # Verify installation with multiple attempts
        Write-LogMessage "Verifying winget installation..." -Level "INFO"
        Start-Sleep -Seconds 5  # Give more time for installation to complete
        
        for ($i = 0; $i -lt 10; $i++) {  # Try up to 10 times with 2 second intervals
            # Refresh environment variables to ensure PATH updates are available
            $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
            
            if (Get-Command winget -ErrorAction SilentlyContinue) {
                # Double-check that winget actually works
                try {
                    $version = winget --version 2>$null
                    if ($version) {
                        Write-LogMessage "Winget installed successfully: $version" -Level "SUCCESS"
                        return $true
                    }
                } catch {
                    # Command exists but doesn't work properly yet
                }
            }
            
            if ($i -lt 9) {  # Don't sleep on the last iteration
                Write-LogMessage "Winget not yet available, waiting... (attempt $($i + 1)/10)" -Level "INFO"
                Start-Sleep -Seconds 2
            }
        }
        
        Write-LogMessage "Winget command not found or not working after installation" -Level "ERROR"
        return $false
    }
    catch {
        Write-LogMessage "Failed to install winget: $_" -Level "ERROR"
        return $false
    }
}

function Update-Environment {
    Write-LogMessage "Updating environment variables..." -Level "INFO"
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
}

function New-SilentInstallConfig {
    param(
        [Parameter(Mandatory=$true)]
        [string]$AppName,
        [string]$ConfigPath = "${env:TEMP}\${AppName}_silent_config"
    )
    
    # Define configuration templates for different applications
    $configTemplates = @{
        "PyCharm" = @{
            Extension = ".config"
            Content = @"
mode=silent
launcher64=1
launcher32=0
updatePATH=1
updateContextMenu=1
associateFiles=
createDesktopShortcut=1
createQuickLaunchShortcut=0
installationPath=
"@
        }
        "IntelliJ" = @{
            Extension = ".config"
            Content = @"
mode=silent
launcher64=1
launcher32=0
updatePATH=1
updateContextMenu=1
associateFiles=java,groovy,kt
createDesktopShortcut=1
createQuickLaunchShortcut=0
"@
        }
        "WebStorm" = @{
            Extension = ".config"
            Content = @"
mode=silent
launcher64=1
launcher32=0
updatePATH=1
updateContextMenu=1
associateFiles=js,ts,html,css
createDesktopShortcut=1
createQuickLaunchShortcut=0
"@
        }
        "AndroidStudio" = @{
            Extension = ".config"
            Content = @"
mode=silent
launcher64=1
launcher32=0
updatePATH=1
updateContextMenu=0
associateFiles=
createDesktopShortcut=1
createQuickLaunchShortcut=0
jre=${env:ProgramFiles}\Android\Android Studio\jre
"@
        }
        "TeamViewer" = @{
            Extension = ".ini"
            Content = @"
[Setup]
CUSTOMCONFIGID=
APITOKEN=
ASSIGNMENTOPTIONS=
"@
        }
    }
    
    try {
        $template = $configTemplates[$AppName]
        if (-not $template) {
            Write-LogMessage "No silent config template found for $AppName" -Level "WARNING"
            return $null
        }
        
        $fullConfigPath = $ConfigPath + $template.Extension
        Write-LogMessage "Creating silent installation config for $AppName at: $fullConfigPath" -Level "INFO"
        
        Set-Content -Path $fullConfigPath -Value $template.Content -Encoding UTF8
        
        if (Test-Path $fullConfigPath) {
            Write-LogMessage "Silent config for $AppName created successfully" -Level "INFO"
            return $fullConfigPath
        } else {
            Write-LogMessage "Failed to create silent config file for $AppName" -Level "ERROR"
            return $null
        }
    } catch {
        Write-LogMessage "Error creating silent config for $AppName`: $_" -Level "ERROR"
        return $null
    }
}

function Install-Application {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$AppName,
        
        [Parameter(Mandatory=$false)]
        [string]$AppKey = "",
        
        [Parameter(Mandatory=$false)]
        [string]$WingetId = "",
        
        [Parameter(Mandatory=$false)]
        [hashtable]$DirectDownload = $null,
        
        [Parameter(Mandatory=$false)]
        [switch]$Force,
        
        [Parameter(Mandatory=$false)]
        [System.Threading.CancellationToken]$CancellationToken = [System.Threading.CancellationToken]::None
    )
    
    Write-LogMessage "Installing application: $AppName" -Level "INFO"
    
    # Track in recovery system
    Save-OperationState -OperationType "InstallApp" -ItemKey $AppName -Status "InProgress"
    
    # Check for cancellation
    if ($CancellationToken -and $CancellationToken -ne [System.Threading.CancellationToken]::None -and $CancellationToken.IsCancellationRequested) {
        Write-LogMessage "Installation cancelled" -Level "WARNING"
        Save-OperationState -OperationType "InstallApp" -ItemKey $AppName -Status "Cancelled"
        return $false
    }
    
    # Get WingetId early for installation verification
    if (-not $WingetId) {
        if ($AppKey) {
            # Try to get from JSON configuration first
            $appConfig = Get-AppDownloadInfo -AppKey $AppKey
            if ($appConfig -and $appConfig.WingetId) {
                $WingetId = $appConfig.WingetId
                Write-LogMessage "Using WingetId from JSON config: $WingetId for $AppName" -Level "DEBUG"
            }
        }
        
        # Fallback to hardcoded mapping if still no WingetId
        if (-not $WingetId) {
            $WingetId = switch ($AppName) {
                "Visual Studio Code" { "Microsoft.VisualStudioCode" }
                "Git" { "Git.Git" }
                "Python" { "Python.Python.3" }
                "PyCharm" { "JetBrains.PyCharm.Community" }
                "GitHub Desktop" { "GitHub.GitHubDesktop" }
                "Postman" { "Postman.Postman" }
                "Node.js" { "OpenJS.NodeJS.LTS" }
                "Windows Terminal" { "Microsoft.WindowsTerminal" }
                "Google Chrome" { "Google.Chrome" }
                "Mozilla Firefox" { "Mozilla.Firefox" }
                "Brave Browser" { "Brave.Browser" }
                "Spotify" { "Spotify.Spotify" }
                "Discord" { "Discord.Discord" }
                "Steam" { "Valve.Steam" }
                "VLC" { "VideoLAN.VLC" }
                "7-Zip" { "7zip.7zip" }
                "Notepad++" { "Notepad++.Notepad++" }
                "Microsoft PowerToys" { "Microsoft.PowerToys" }
                default { $null }
            }
        }
    }
    
    # Skip if already installed and not forced
    if (-not $Force) {
        $isInstalled = Test-ApplicationInstalled -AppName $AppName -CheckCommand -WingetId $WingetId
        if ($isInstalled) {
            Write-LogMessage "$AppName is already installed, skipping installation" -Level "INFO"
            Save-OperationState -OperationType "InstallApp" -ItemKey $AppName -Status "Skipped" -AdditionalData @{
                Reason = "Already installed"
            }
            return $true
        }
    }
    
    # Check Windows version compatibility for winget first
    $buildNumber = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion").CurrentBuild
    $wingetCompatible = ([int]$buildNumber -ge 16299)  # Windows 10 1709 build 16299 minimum
    
    if (-not $wingetCompatible) {
        Write-LogMessage "Windows build $buildNumber is below minimum for winget (16299). Using direct download." -Level "INFO"
    }
    
    # Try winget first if compatible and available (with retry for recently installed winget)
    $wingetAvailable = $false
    if (-not $script:UseDirectDownloadOnly -and $wingetCompatible) {
        # Check for winget availability with retry (in case it was just installed)
        for ($i = 0; $i -lt 3; $i++) {
            # Refresh environment variables to ensure PATH updates are available
            $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
            
            if (Get-Command winget -ErrorAction SilentlyContinue) {
                # Verify winget actually works by testing version command
                try {
                    $testVersion = winget --version 2>$null
                    if ($testVersion) {
                        $wingetAvailable = $true
                        Write-LogMessage "Winget is available and working for $AppName installation" -Level "INFO"
                        break
                    }
                } catch {
                    Write-LogMessage "Winget command found but not working yet, retrying..." -Level "DEBUG"
                }
            }
            
            if ($i -lt 2) {  # Don't sleep on the last iteration
                Write-LogMessage "Winget not yet available for $AppName, waiting... (attempt $($i + 1)/3)" -Level "DEBUG"
                Start-Sleep -Seconds 3
            }
        }
    }
    
    if ($wingetAvailable) {
        # WingetId was already determined earlier for installation verification
        
        if ($WingetId) {
            Write-LogMessage "Installing $AppName via winget (ID: $WingetId)..." -Level "INFO"
            try {
                $wingetOutput = winget install --id $WingetId --accept-source-agreements --accept-package-agreements --silent 2>&1
                
                if ($LASTEXITCODE -eq 0 -or $wingetOutput -match "Successfully installed") {
                    Write-LogMessage "$AppName installed successfully via winget!" -Level "SUCCESS"
                    Save-OperationState -OperationType "InstallApp" -ItemKey $AppName -Status "Completed" -AdditionalData @{
                        Method = "Winget"
                        WingetId = $WingetId
                        WindowsBuild = $buildNumber
                    }
                    
                    # Refresh environment variables
                    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
                    
                    return $true
                }
                else {
                    Write-LogMessage "Winget installation failed with exit code: $LASTEXITCODE" -Level "WARNING"
                    Write-LogMessage "Winget output: $wingetOutput" -Level "DEBUG"
                    Write-LogMessage "Windows build: $buildNumber (winget requires 16299+)" -Level "DEBUG"
                    # Continue to direct download method
                }
            }
            catch {
                Write-LogMessage "Error using winget: $_" -Level "WARNING"
                # Continue to direct download method
            }
        }
    }
    
    # If no direct download info was provided, try to get it
    if ($null -eq $DirectDownload) {
        # Try to get from JSON configuration first if AppKey is provided
        if ($AppKey) {
            $appConfig = Get-AppDownloadInfo -AppKey $AppKey
            if ($appConfig -and $appConfig.Url) {
                $DirectDownload = @{
                    Url = $appConfig.Url
                    Extension = $appConfig.Extension
                    Arguments = $appConfig.Arguments
                    VerificationPaths = $appConfig.VerificationPaths
                }
                Write-LogMessage "Using download info from JSON config for $AppName" -Level "INFO"
                
                # Handle dynamic URL retrieval for GitHub releases
                if ($appConfig.UrlType -eq "github-asset") {
                    $latestUrl = Get-LatestVersionUrl -ApplicationName $AppName
                    if ($latestUrl) {
                        Write-LogMessage "Using dynamically retrieved latest version URL for $AppName" -Level "INFO"
                        $DirectDownload.Url = $latestUrl
                    }
                }
            }
        }
        
        # Fallback to hardcoded function if no JSON config found
        if ($null -eq $DirectDownload) {
            # First try to get dynamic latest version
            $latestUrl = Get-LatestVersionUrl -ApplicationName $AppName
            
            # Then get the standard download info
            $DirectDownload = Get-AppDirectDownloadInfo -AppName $AppName
            
            # Update with latest URL if available
            if ($latestUrl -and $DirectDownload) {
                Write-LogMessage "Using dynamically retrieved latest version URL for $AppName" -Level "INFO"
                $DirectDownload.Url = $latestUrl
            }
        }
    }
    
    if ($null -eq $DirectDownload) {
        Write-LogMessage "No download information available for $AppName" -Level "ERROR"
        Save-OperationState -OperationType "InstallApp" -ItemKey $AppName -Status "Failed" -AdditionalData @{
            Error = "No download information available"
            Time = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        }
        return $false
    }
    
    try {
        # Create download directory
        $scriptPath = Split-Path -Parent $PSScriptRoot
        $downloadDir = Join-Path $scriptPath "downloads"
        if (-not (Test-Path $downloadDir)) {
            New-Item -ItemType Directory -Path $downloadDir -Force | Out-Null
        }
        
        # Create app-specific directory
        $appDir = Join-Path $downloadDir $AppName
        if (-not (Test-Path $appDir)) {
            New-Item -ItemType Directory -Path $appDir -Force | Out-Null
        }
        
        # Download the installer
        $installerPath = Join-Path $appDir "$AppName$($DirectDownload.Extension)"
        Write-LogMessage "Downloading from: $($DirectDownload.Url)" -Level "INFO"
        
        try {
            $webClient = New-Object System.Net.WebClient
            $webClient.DownloadFile($DirectDownload.Url, $installerPath)
            Write-LogMessage "Download completed successfully" -Level "SUCCESS"
        }
        catch {
            Write-LogMessage "Download failed: $_" -Level "ERROR"
            Save-OperationState -OperationType "InstallApp" -ItemKey $AppName -Status "Failed" -AdditionalData @{
                Error = "Download failed: $_"
                Time = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            }
            return $false
        }
        
        # Check for cancellation
        if ($CancellationToken -and $CancellationToken -ne [System.Threading.CancellationToken]::None -and $CancellationToken.IsCancellationRequested) {
            Write-LogMessage "Installation cancelled" -Level "WARNING"
            Save-OperationState -OperationType "InstallApp" -ItemKey $AppName -Status "Cancelled"
            return $false
        }
        
        # Run the installer based on extension type
        Write-LogMessage "Running installer..." -Level "INFO"
        
        if ($DirectDownload.Extension -eq ".exe") {
            $arguments = if ($DirectDownload.Arguments) { $DirectDownload.Arguments } else { "/S" }
            
            # Handle applications that require silent config files
            if ($arguments -like "*CONFIG=*" -or $arguments -like "*config*") {
                $configPath = New-SilentInstallConfig -AppName $AppName
                if ($null -eq $configPath) {
                    Write-LogMessage "Failed to create silent config for $AppName, using basic silent installation" -Level "WARNING"
                    $arguments = "/S"
                } else {
                    # Update arguments to use the created config file
                    $arguments = $arguments -replace '\$\{env:TEMP\}\\[^"]*', $configPath
                }
            }
            
            $process = Start-ProcessWithTimeout -FilePath $installerPath -ArgumentList $arguments -TimeoutMinutes $script:InstallerTimeoutMinutes -CancellationToken $CancellationToken
        }
        elseif ($DirectDownload.Extension -eq ".msi") {
            $arguments = if ($DirectDownload.Arguments) { $DirectDownload.Arguments } else { "/quiet", "/norestart" }
            $allArgs = @("/i", $installerPath) + $arguments
            $process = Start-ProcessWithTimeout -FilePath "msiexec.exe" -ArgumentList $allArgs -TimeoutMinutes $script:InstallerTimeoutMinutes -NoNewWindow -CancellationToken $CancellationToken
        }
        elseif ($DirectDownload.Extension -eq ".msixbundle") {
            # Special handling for MSIX bundles (Windows Terminal, etc.)
            Write-LogMessage "Installing MSIX bundle..." -Level "INFO"
            
            try {
                # Try using Add-AppxPackage
                Add-AppxPackage -Path $installerPath -ErrorAction Stop
                $process = [PSCustomObject]@{ ExitCode = 0 }
            }
            catch {
                Write-LogMessage "Add-AppxPackage failed, trying winget fallback: $_" -Level "WARNING"
                
                # Try using winget if available
                if (Get-Command winget -ErrorAction SilentlyContinue) {
                    Write-LogMessage "Using winget to install $AppName..." -Level "INFO"
                    $wingetResult = winget install --id Microsoft.WindowsTerminal -e --accept-source-agreements --accept-package-agreements --silent 2>&1
                    
                    if ($LASTEXITCODE -eq 0) {
                        $process = [PSCustomObject]@{ ExitCode = 0 }
                    } else {
                        throw "Winget installation failed: $wingetResult"
                    }
                } else {
                    throw "Failed to install MSIX bundle and winget not available: $_"
                }
            }
        }
        else {
            Write-LogMessage "Unsupported installer type: $($DirectDownload.Extension)" -Level "ERROR"
            $process = [PSCustomObject]@{ ExitCode = 1 }
        }
        
        # Check for timeout or cancellation
        if ($process.PSObject.Properties.Name -contains "Cancelled" -and $process.Cancelled) {
            Write-LogMessage "Installation was cancelled by user" -Level "WARNING"
            Save-OperationState -OperationType "InstallApp" -ItemKey $AppName -Status "Cancelled" -AdditionalData @{
                Time = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            }
            return $false
        }
        elseif ($process.PSObject.Properties.Name -contains "TimedOut" -and $process.TimedOut) {
            Write-LogMessage "Installation timed out after $script:InstallerTimeoutMinutes minutes" -Level "ERROR"
            Save-OperationState -OperationType "InstallApp" -ItemKey $AppName -Status "Failed" -AdditionalData @{
                Error = "Installation timed out"
                TimeoutMinutes = $script:InstallerTimeoutMinutes
                Time = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            }
            return $false
        }
        elseif ($process.ExitCode -eq 0 -or $process.ExitCode -eq $null -or $process.ExitCode -eq "") {
            Write-LogMessage "Installation completed successfully" -Level "SUCCESS"
            
            # Verify installation
            $verificationResult = Test-ApplicationInstalled -AppName $AppName -VerificationPaths $DirectDownload.VerificationPaths -CheckCommand -WingetId $WingetId
            
            if ($verificationResult) {
                Write-LogMessage "Installation verified for $AppName" -Level "SUCCESS"
                Save-OperationState -OperationType "InstallApp" -ItemKey $AppName -Status "Completed" -AdditionalData @{
                    Method = "Direct"
                    Url = $DirectDownload.Url
                }
            } else {
                Write-LogMessage "Installation completed but verification failed for $AppName" -Level "WARNING"
                Save-OperationState -OperationType "InstallApp" -ItemKey $AppName -Status "CompletedWithWarning" -AdditionalData @{
                    Method = "Direct"
                    Url = $DirectDownload.Url
                    Warning = "Verification failed"
                }
            }
            
            # Clean up installer
            Remove-Item $installerPath -Force -ErrorAction SilentlyContinue
            
            return $true
        } else {
            Write-LogMessage "Installation failed with exit code: $($process.ExitCode)" -Level "ERROR"
            Save-OperationState -OperationType "InstallApp" -ItemKey $AppName -Status "Failed" -AdditionalData @{
                Error = "Installation failed with exit code: $($process.ExitCode)"
                Time = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            }
            return $false
        }
    }
    catch {
        Write-LogMessage "Failed to install $AppName : $_" -Level "ERROR"
        Save-OperationState -OperationType "InstallApp" -ItemKey $AppName -Status "Failed" -AdditionalData @{
            Error = $_.Exception.Message
            Time = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        }
        return $false
    }
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
        
        [System.Threading.CancellationToken]$CancellationToken = [System.Threading.CancellationToken]::None
    )
    
    Write-LogMessage "Starting Python $Version installation..." -Level "INFO"
    
    # Check for cancellation
    if ($CancellationToken -and $CancellationToken -ne [System.Threading.CancellationToken]::None -and $CancellationToken.IsCancellationRequested) {
        Write-LogMessage "Python installation cancelled" -Level "WARNING"
        return $false
    }
    
    # Try winget first
    if (-not $script:UseDirectDownloadOnly -and (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-LogMessage "Installing Python via winget..." -Level "INFO"
        try {
            $wingetOutput = winget install --id "Python.Python.3" --accept-source-agreements --accept-package-agreements --silent 2>&1
            
            if ($LASTEXITCODE -eq 0 -or $wingetOutput -match "Successfully installed") {
                Write-LogMessage "Python installed successfully via winget!" -Level "SUCCESS"
                
                # Refresh environment variables and verify
                Update-Environment
                if (Get-Command python -ErrorAction SilentlyContinue) {
                    $pythonVersion = python --version 2>&1
                    Write-LogMessage "Python version: $pythonVersion" -Level "SUCCESS"
                    
                    # Upgrade pip
                    Write-LogMessage "Upgrading pip to latest version..." -Level "INFO"
                    python -m pip install --upgrade pip --quiet
                    Write-LogMessage "Pip upgraded successfully" -Level "SUCCESS"
                    
                    return $true
                }
            }
        }
        catch {
            Write-LogMessage "Winget installation failed: $_" -Level "WARNING"
        }
    }
    
    # Fallback to direct download with enhanced setup
    Write-LogMessage "Using direct download method for Python..." -Level "INFO"
    
    # Try to get the latest version URL
    $latestUrl = Get-LatestVersionUrl -ApplicationName "Python"
    
    # Get the download info
    $pythonDownload = Get-AppDirectDownloadInfo -AppName "Python"
    if ($null -eq $pythonDownload) {
        Write-LogMessage "Could not get Python download information" -Level "ERROR"
        return $false
    }
    
    # Update URL if we have a latest version
    if ($latestUrl) {
        $pythonDownload.Url = $latestUrl
        Write-LogMessage "Using latest Python version URL: $latestUrl" -Level "INFO"
    }
    
    try {
        # Download and install Python
        $installerPath = Join-Path $env:TEMP "python-installer.exe"
        Write-LogMessage "Downloading Python from: $($pythonDownload.Url)" -Level "INFO"
        
        $webClient = New-Object System.Net.WebClient
        $webClient.DownloadFile($pythonDownload.Url, $installerPath)
        
        # Run installer with enhanced arguments
        Write-LogMessage "Installing Python with arguments: $($pythonDownload.Arguments)" -Level "INFO"
        $process = Start-ProcessWithTimeout -FilePath $installerPath -ArgumentList $pythonDownload.Arguments -TimeoutMinutes $script:InstallerTimeoutMinutes -NoNewWindow -CancellationToken $CancellationToken
        
        # Check for timeout or cancellation
        if ($process.PSObject.Properties.Name -contains "Cancelled" -and $process.Cancelled) {
            Write-LogMessage "Python installation was cancelled by user" -Level "WARNING"
            return $false
        }
        elseif ($process.PSObject.Properties.Name -contains "TimedOut" -and $process.TimedOut) {
            Write-LogMessage "Python installation timed out after $script:InstallerTimeoutMinutes minutes" -Level "ERROR"
            return $false
        }
        elseif ($process.ExitCode -eq 0) {
            Write-LogMessage "Python installer completed successfully" -Level "SUCCESS"
            
            # Refresh environment variables
            Update-Environment
            Start-Sleep -Seconds 3
            
            # Try multiple verification methods
            $pythonFound = $false
            $pythonPath = $null
            
            # Check command availability first
            if (Get-Command python -ErrorAction SilentlyContinue) {
                $pythonVersion = python --version 2>&1
                Write-LogMessage "Python command available: $pythonVersion" -Level "SUCCESS"
                $pythonFound = $true
            }
            
            # If command not found, search installation paths
            if (-not $pythonFound) {
                Write-LogMessage "Python command not found, searching installation paths..." -Level "INFO"
                
                $searchPaths = @(
                    "${env:ProgramFiles}\Python*",
                    "${env:LocalAppData}\Programs\Python\Python*"
                )
                
                foreach ($searchPath in $searchPaths) {
                    $pythonDirs = Get-ChildItem -Path (Split-Path $searchPath) -Directory -Filter (Split-Path $searchPath -Leaf) -ErrorAction SilentlyContinue
                    if ($pythonDirs) {
                        $pythonPath = $pythonDirs[0].FullName
                        $pythonExe = Join-Path $pythonPath "python.exe"
                        if (Test-Path $pythonExe) {
                            Write-LogMessage "Found Python at: $pythonPath" -Level "SUCCESS"
                            
                            # Add to PATH
                            $scriptsPath = Join-Path $pythonPath "Scripts"
                            Set-PathEnvironment -PathToAdd $pythonPath
                            if (Test-Path $scriptsPath) {
                                Set-PathEnvironment -PathToAdd $scriptsPath
                            }
                            
                            $pythonFound = $true
                            break
                        }
                    }
                }
            }
            
            if ($pythonFound) {
                # Upgrade pip
                Write-LogMessage "Upgrading pip to latest version..." -Level "INFO"
                try {
                    if ($pythonPath) {
                        & "$pythonPath\python.exe" -m pip install --upgrade pip --quiet
                    } else {
                        python -m pip install --upgrade pip --quiet
                    }
                    Write-LogMessage "Pip upgraded successfully" -Level "SUCCESS"
                }
                catch {
                    Write-LogMessage "Warning: Could not upgrade pip: $_" -Level "WARNING"
                }
                
                Write-LogMessage "Python is ready for development!" -Level "SUCCESS"
                Write-LogMessage "Create virtual environments with: python -m venv myenv" -Level "INFO"
                Write-LogMessage "Activate with: myenv\\Scripts\\activate" -Level "INFO"
                
                return $true
            } else {
                Write-LogMessage "Python installation verification failed" -Level "ERROR"
                return $false
            }
        } else {
            Write-LogMessage "Python installer failed with exit code: $($process.ExitCode)" -Level "ERROR"
            return $false
        }
    }
    catch {
        Write-LogMessage "Failed to install Python: $_" -Level "ERROR"
        return $false
    }
}

function New-DevelopmentFolders {
    [CmdletBinding()]
    param()
    
    Write-LogMessage "Creating development folders..." -Level "INFO"
    
    $folders = @(
        "$env:USERPROFILE\Desktop\Projects",
        "$env:USERPROFILE\Desktop\Projects\Python", 
        "$env:USERPROFILE\Desktop\Projects\GitHub",
        "$env:USERPROFILE\Desktop\APIs",
        "$env:USERPROFILE\.vscode"
    )
    
    $createdCount = 0
    foreach ($folder in $folders) {
        if (-not (Test-Path $folder)) {
            New-Item -ItemType Directory -Path $folder -Force | Out-Null
            Write-LogMessage "Created: $folder" -Level "SUCCESS"
            $createdCount++
        } else {
            Write-LogMessage "Folder already exists: $folder" -Level "INFO"
        }
    }
    
    Write-LogMessage "Created $createdCount new development folders" -Level "INFO"
    return $true
}

function Install-VSCodeExtensions {
    [CmdletBinding()]
    param()
    
    Write-LogMessage "Installing VS Code extensions..." -Level "INFO"
    
    # Update environment variables to ensure 'code' command is available
    Update-Environment
    
    if (-not (Get-Command code -ErrorAction SilentlyContinue)) {
        Write-LogMessage "VS Code not found in PATH. Extensions will need to be installed manually." -Level "WARNING"
        return $false
    }
    
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
        Write-LogMessage "Installing VS Code extension: $ext" -Level "INFO"
        try {
            $result = & code --install-extension $ext --force 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-LogMessage "Successfully installed extension: $ext" -Level "SUCCESS"
                $installedCount++
            } else {
                Write-LogMessage "Failed to install extension: $ext" -Level "ERROR"
                $failedCount++
            }
        } catch {
            Write-LogMessage "Error installing extension $ext : $_" -Level "ERROR"
            $failedCount++
        }
    }
    
    Write-LogMessage "VS Code extensions installation complete: $installedCount installed, $failedCount failed" -Level "INFO"
    return ($failedCount -eq 0)
}

function Set-PathEnvironment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$PathToAdd
    )
    
    if (-not (Test-Path $PathToAdd)) {
        Write-LogMessage "Path does not exist, cannot add to PATH: $PathToAdd" -Level "WARNING"
        return $false
    }
    
    $currentPath = [Environment]::GetEnvironmentVariable("Path", "User")
    if ($currentPath -notlike "*$PathToAdd*") {
        Write-LogMessage "Adding $PathToAdd to PATH" -Level "INFO"
        [Environment]::SetEnvironmentVariable("Path", "$currentPath;$PathToAdd", "User")
        $env:Path += ";$PathToAdd"
        Write-LogMessage "Added $PathToAdd to PATH" -Level "SUCCESS"
        return $true
    } else {
        Write-LogMessage "$PathToAdd is already in PATH" -Level "INFO"
        return $true
    }
}

# Export functions
Export-ModuleMember -Function @(
    'Test-FileChecksum',
    'Get-AppDirectDownloadInfo',
    'Install-Application',
    'Install-Winget',
    'Test-ApplicationInstalled',
    'Get-LatestVersionUrl',
    'Update-Environment',
    'Install-Python',
    'New-DevelopmentFolders',
    'Install-VSCodeExtensions',
    'Set-PathEnvironment'
)