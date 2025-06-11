# Installation modules for Windows Setup GUI

# Global variables
$script:UseDirectDownloadOnly = $false
$script:MaxRetries = 3
$script:RetryDelay = 5 # seconds

# Define Write-LogMessage function for module compatibility
function Write-LogMessage {
    param (
        [Parameter(Mandatory=$true)]
        [string]$Message,
        
        [Parameter(Mandatory=$false)]
        [ValidateSet("INFO", "WARNING", "ERROR", "SUCCESS")]
        [string]$Level = "INFO"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    
    # Write to console with color
    $color = switch ($Level) {
        "ERROR" { "Red" }
        "WARNING" { "Yellow" }
        "SUCCESS" { "Green" }
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
            return "https://github.com/git-for-windows/git/releases/latest/download/Git-64-bit.exe"
        }
        "Python" {
            try {
                # Get Python versions from the website
                $webRequest = Invoke-WebRequest -Uri "https://www.python.org/downloads/windows/" -UseBasicParsing -ErrorAction Stop
                
                # Extract the latest Python 3 version
                if ($webRequest.Content -match "Latest Python 3 Release - Python (3\.\d+\.\d+)") {
                    $latestVersion = $matches[1]
                    return "https://www.python.org/ftp/python/$latestVersion/python-$latestVersion-amd64.exe"
                }
            } catch {
                Write-LogMessage "Error getting latest Python version: $_" -Level "WARNING"
            }
            # Fallback to a reasonably current version
            return "https://www.python.org/ftp/python/3.12.2/python-3.12.2-amd64.exe"
        }
        "PyCharm" {
            try {
                # Get latest PyCharm version from JetBrains website
                $webRequest = Invoke-WebRequest -Uri "https://data.services.jetbrains.com/products/releases?code=PCC&latest=true&type=release" -UseBasicParsing -ErrorAction Stop
                
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
                $webRequest = Invoke-WebRequest -Uri "https://www.videolan.org/vlc/download-windows.html" -UseBasicParsing -ErrorAction Stop
                
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
                $webRequest = Invoke-WebRequest -Uri "https://www.7-zip.org/download.html" -UseBasicParsing -ErrorAction Stop
                
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
            return "https://www.7-zip.org/a/7z2301-x64.exe"
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
            return "https://github.com/notepad-plus-plus/notepad-plus-plus/releases/latest/download/npp.Installer.x64.exe"
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
        [switch]$CheckCommand = $false
    )
    
    Write-LogMessage "Verifying installation for $AppName..." -Level "INFO"
    
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

function Get-AppDirectDownloadInfo {
    param(
        [Parameter(Mandatory=$true)]
        [string]$AppName
    )

    # Use dynamic version lookup first for applications with hardcoded versions
    $latestUrl = Get-LatestVersionUrl -ApplicationName $AppName
    
    $downloadInfo = @{
        "Brave" = @{
            Url = "https://referrals.brave.com/latest/BraveBrowserSetup.exe"
            Extension = ".exe"
            Arguments = "/silent /install"
            VerificationPaths = @(
                "${env:ProgramFiles}\BraveSoftware\Brave-Browser\Application\brave.exe",
                "${env:ProgramFiles(x86)}\BraveSoftware\Brave-Browser\Application\brave.exe"
            )
        }
        "Google Chrome" = @{
            Url = "https://dl.google.com/dl/chrome/install/googlechromestandaloneenterprise64.msi"
            Extension = ".msi"
            Arguments = @("/quiet", "/norestart")
            VerificationPaths = @(
                "${env:ProgramFiles}\Google\Chrome\Application\chrome.exe",
                "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe"
            )
        }
        "Mozilla Firefox" = @{
            Url = "https://download.mozilla.org/?product=firefox-latest-ssl&os=win64&lang=en-US"
            Extension = ".exe"
            Arguments = "-ms"
            VerificationPaths = @(
                "${env:ProgramFiles}\Mozilla Firefox\firefox.exe",
                "${env:ProgramFiles(x86)}\Mozilla Firefox\firefox.exe"
            )
        }
        "Postman" = @{
            Url = "https://dl.pstmn.io/download/latest/win64"
            Extension = ".exe"
            Arguments = "-s"
            VerificationPaths = @(
                "${env:LocalAppData}\Postman\Postman.exe",
                "${env:ProgramFiles}\Postman\Postman.exe",
                "${env:ProgramFiles(x86)}\Postman\Postman.exe"
            )
        }
        "GitHub Desktop" = @{
            Url = "https://desktop.github.com/releases/latest/GitHubDesktopSetup.exe"
            Extension = ".exe"
            Arguments = "/silent"
            VerificationPaths = @(
                "${env:LocalAppData}\GitHubDesktop\GitHubDesktop.exe"
            )
        }
        "Git" = @{
            Url = if ($latestUrl) { $latestUrl } else { "https://github.com/git-for-windows/git/releases/latest/download/Git-64-bit.exe" }
            Extension = ".exe"
            Arguments = '/VERYSILENT /NORESTART /NOCANCEL /SP- /CLOSEAPPLICATIONS /RESTARTAPPLICATIONS /COMPONENTS="icons,ext\reg\shellhere,assoc,assoc_sh"'
            VerificationPaths = @(
                "${env:ProgramFiles}\Git\cmd\git.exe",
                "${env:ProgramFiles(x86)}\Git\cmd\git.exe"
            )
        }
        "Visual Studio Code" = @{
            Url = "https://code.visualstudio.com/sha/download?build=stable&os=win32-x64-user"
            Extension = ".exe"
            Arguments = "/VERYSILENT /NORESTART /MERGETASKS=!runcode"
            VerificationPaths = @(
                "${env:ProgramFiles}\Microsoft VS Code\Code.exe",
                "${env:LocalAppData}\Programs\Microsoft VS Code\Code.exe",
                "${env:ProgramFiles(x86)}\Microsoft VS Code\Code.exe"
            )
        }
        "PyCharm" = @{
            Url = if ($latestUrl) { $latestUrl } else { "https://download.jetbrains.com/python/pycharm-community-latest.exe" }
            Extension = ".exe"
            Arguments = "/S /CONFIG=${env:TEMP}\silent.config"
            VerificationPaths = @(
                "${env:ProgramFiles}\JetBrains\PyCharm Community Edition*\bin\pycharm64.exe",
                "${env:ProgramFiles(x86)}\JetBrains\PyCharm Community Edition*\bin\pycharm64.exe",
                "${env:ProgramFiles}\JetBrains\PyCharm Community Edition*\bin\pycharm.exe",
                "${env:LocalAppData}\JetBrains\Toolbox\apps\PyCharm-C\*\bin\pycharm64.exe"
            )
        }
        "Python" = @{
            Url = if ($latestUrl) { $latestUrl } else { "https://www.python.org/ftp/python/3.12.2/python-3.12.2-amd64.exe" }
            Extension = ".exe"
            Arguments = "/quiet InstallAllUsers=1 PrependPath=1 Include_test=0 Include_pip=1 Include_tcltk=1"
            VerificationPaths = @(
                "${env:ProgramFiles}\Python312\python.exe",
                "${env:ProgramFiles}\Python311\python.exe", 
                "${env:ProgramFiles}\Python310\python.exe",
                "${env:LocalAppData}\Programs\Python\Python312\python.exe",
                "${env:LocalAppData}\Programs\Python\Python311\python.exe",
                "${env:LocalAppData}\Microsoft\WindowsApps\python.exe"
            )
        }
        "Steam" = @{
            Url = "https://cdn.akamai.steamstatic.com/client/installer/SteamSetup.exe"
            Extension = ".exe"
            Arguments = "/S"
            VerificationPaths = @(
                "${env:ProgramFiles(x86)}\Steam\Steam.exe"
            )
        }
        "VLC" = @{
            Url = if ($latestUrl) { $latestUrl } else { "https://download.videolan.org/pub/videolan/vlc/last/win64/vlc-latest-win64.exe" }
            Extension = ".exe"
            Arguments = "/S"
            VerificationPaths = @(
                "${env:ProgramFiles}\VideoLAN\VLC\vlc.exe",
                "${env:ProgramFiles(x86)}\VideoLAN\VLC\vlc.exe"
            )
        }
        "Spotify" = @{
            Url = "https://download.scdn.co/SpotifySetup.exe"
            Extension = ".exe"
            Arguments = "/silent"
            VerificationPaths = @(
                "${env:APPDATA}\Spotify\Spotify.exe",
                "${env:ProgramFiles}\Spotify\Spotify.exe",
                "${env:ProgramFiles(x86)}\Spotify\Spotify.exe"
            )
        }
        "Discord" = @{
            Url = "https://discord.com/api/downloads/distributions/app/installers/latest?channel=stable&platform=win&arch=x86"
            Extension = ".exe"
            Arguments = "-s"
            VerificationPaths = @(
                "${env:LocalAppData}\Discord\Update.exe",
                "${env:LocalAppData}\Discord\app-*\Discord.exe",
                "${env:ProgramFiles}\Discord\Discord.exe",
                "${env:ProgramFiles(x86)}\Discord\Discord.exe"
            )
        }
        "Notepad++" = @{
            Url = if ($latestUrl) { $latestUrl } else { "https://github.com/notepad-plus-plus/notepad-plus-plus/releases/latest/download/npp.Installer.x64.exe" }
            Extension = ".exe"
            Arguments = "/S"
            VerificationPaths = @(
                "${env:ProgramFiles}\Notepad++\notepad++.exe",
                "${env:ProgramFiles(x86)}\Notepad++\notepad++.exe"
            )
        }
        "7-Zip" = @{
            Url = if ($latestUrl) { $latestUrl } else { "https://www.7-zip.org/a/7z2301-x64.exe" }
            Extension = ".exe"
            Arguments = "/S"
            VerificationPaths = @(
                "${env:ProgramFiles}\7-Zip\7z.exe",
                "${env:ProgramFiles(x86)}\7-Zip\7z.exe"
            )
        }
        "Windows Terminal" = @{
            Url = "https://github.com/microsoft/terminal/releases/latest/download/Microsoft.WindowsTerminal_Win10.msixbundle"
            Extension = ".msixbundle"
            Arguments = ""
            VerificationPaths = @(
                "${env:LocalAppData}\Microsoft\WindowsApps\wt.exe"
            )
        }
        "Microsoft PowerToys" = @{
            Url = "https://github.com/microsoft/PowerToys/releases/latest/download/PowerToysSetup-x64.exe"
            Extension = ".exe"
            Arguments = "-silent"
            VerificationPaths = @(
                "${env:LocalAppData}\Programs\PowerToys\PowerToys.exe",
                "${env:ProgramFiles}\PowerToys\PowerToys.exe"
            )
        }
        "Node.js" = @{
            Url = "https://nodejs.org/dist/latest/node-latest-x64.msi"
            Extension = ".msi"
            Arguments = @("/quiet", "/norestart")
            VerificationPaths = @(
                "${env:ProgramFiles}\nodejs\node.exe",
                "${env:ProgramFiles(x86)}\nodejs\node.exe"
            )
        }
    }

    if ($downloadInfo.ContainsKey($AppName)) {
        return $downloadInfo[$AppName]
    } else {
        return $null
    }
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
        Write-LogMessage "Attempting to register winget..." -Level "INFO"
        
        try {
            Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe
            Write-LogMessage "Winget registration command completed" -Level "INFO"
            
            # Wait and verify
            Start-Sleep -Seconds 5
            if (Get-Command winget -ErrorAction SilentlyContinue) {
                $version = winget --version 2>$null
                Write-LogMessage "Winget successfully registered: $version" -Level "SUCCESS"
                return $true
            } else {
                Write-LogMessage "Winget registration completed but command not yet available" -Level "WARNING"
                Write-LogMessage "This may require a new PowerShell session or user logout/login" -Level "INFO"
            }
        } catch {
            Write-LogMessage "Failed to register winget: $_" -Level "WARNING"
        }
    }
    
    # Try Microsoft Store installation
    Write-LogMessage "Attempting to install winget via Microsoft Store..." -Level "INFO"
    try {
        $wingetUrl = "ms-windows-store://pdp/?ProductId=9NBLGGH4NNS1"
        Start-Process $wingetUrl
        Write-LogMessage "Please complete the winget installation from the Microsoft Store" -Level "INFO"
        return $true
    }
    catch {
        Write-LogMessage "Failed to open Microsoft Store: $_" -Level "WARNING"
    }
    
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
        $release = Invoke-RestMethod -Uri $releaseUrl
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
        
        # Install the bundle
        Write-LogMessage "Installing winget package..." -Level "INFO"
        Add-AppxPackage -Path $downloadPath -ErrorAction Stop
        
        # Clean up download
        Remove-Item $downloadPath -Force -ErrorAction SilentlyContinue
        Write-LogMessage "Cleaned up downloaded package" -Level "INFO"
        
        # Verify installation
        Start-Sleep -Seconds 3  # Give time for installation to complete
        if (Get-Command winget -ErrorAction SilentlyContinue) {
            Write-LogMessage "Winget installed successfully!" -Level "SUCCESS"
            return $true
        } else {
            Write-LogMessage "Winget command not found after installation" -Level "ERROR"
            return $false
        }
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

function Install-Application {
    param(
        [Parameter(Mandatory=$true)]
        [string]$AppName,
        [Parameter(Mandatory=$false)]
        [string]$WingetId = "",
        [Parameter(Mandatory=$false)]
        [hashtable]$DirectDownload = $null,
        [Parameter(Mandatory=$false)]
        [switch]$Force,
        [System.Threading.CancellationToken]$CancellationToken
    )
    
    Write-LogMessage "Installing application: $AppName" -Level "INFO"
    
    # Track in recovery system
    Save-OperationState -OperationType "InstallApp" -ItemKey $AppName -Status "InProgress"
    
    # Check for cancellation
    if ($CancellationToken.IsCancellationRequested) {
        Write-LogMessage "Installation cancelled" -Level "WARNING"
        Save-OperationState -OperationType "InstallApp" -ItemKey $AppName -Status "Cancelled"
        return $false
    }
    
    # Skip if already installed and not forced
    if (-not $Force) {
        $isInstalled = Test-ApplicationInstalled -AppName $AppName -CheckCommand
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
    
    # Try winget first if compatible and available
    if (-not $script:UseDirectDownloadOnly -and $wingetCompatible -and (Get-Command winget -ErrorAction SilentlyContinue)) {
        # Map app name to winget ID if not provided
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
        if ($CancellationToken.IsCancellationRequested) {
            Write-LogMessage "Installation cancelled" -Level "WARNING"
            Save-OperationState -OperationType "InstallApp" -ItemKey $AppName -Status "Cancelled"
            return $false
        }
        
        # Run the installer based on extension type
        Write-LogMessage "Running installer..." -Level "INFO"
        
        if ($DirectDownload.Extension -eq ".exe") {
            $arguments = if ($DirectDownload.Arguments) { $DirectDownload.Arguments } else { "/S" }
            $process = Start-Process -FilePath $installerPath -ArgumentList $arguments -Wait -PassThru
        }
        elseif ($DirectDownload.Extension -eq ".msi") {
            $arguments = if ($DirectDownload.Arguments) { $DirectDownload.Arguments } else { "/quiet", "/norestart" }
            $process = Start-Process msiexec.exe -ArgumentList "/i", $installerPath, $arguments -Wait -NoNewWindow -PassThru
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
        
        if ($process.ExitCode -eq 0) {
            Write-LogMessage "Installation completed successfully" -Level "SUCCESS"
            
            # Verify installation
            $verificationResult = Test-ApplicationInstalled -AppName $AppName -VerificationPaths $DirectDownload.VerificationPaths -CheckCommand
            
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
        
        [System.Threading.CancellationToken]$CancellationToken
    )
    
    Write-LogMessage "Starting Python $Version installation..." -Level "INFO"
    
    # Check for cancellation
    if ($CancellationToken.IsCancellationRequested) {
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
        $process = Start-Process -FilePath $installerPath -ArgumentList $pythonDownload.Arguments -Wait -NoNewWindow -PassThru
        
        if ($process.ExitCode -eq 0) {
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