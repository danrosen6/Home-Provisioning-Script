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
                    Write-LogMessage "Error killing cancelled process``: $_" -Level "ERROR"
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
                Write-LogMessage "Error killing timed-out process``: $_" -Level "ERROR"
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
        Write-LogMessage "Error starting process``: $_" -Level "ERROR"
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
                Write-Host "Error updating log textbox`: $_" -ForegroundColor Red
            }
        }
        
        # Write to log file if enabled
        if ($script:EnableFileLogging -and $script:LogPath) {
            try {
                Add-Content -Path $script:LogPath -Value $logMessage -ErrorAction Stop
            }
            catch {
                Write-Host "Failed to write to log file`: $_" -ForegroundColor Red
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
                Write-LogMessage "Error getting latest Git version``: $_" -Level "WARNING"
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
                Write-LogMessage "Error getting latest Python version``: $_" -Level "WARNING"
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
                Write-LogMessage "Error getting latest PyCharm version``: $_" -Level "WARNING"
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
                Write-LogMessage "Error getting latest VLC version``: $_" -Level "WARNING"
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
                Write-LogMessage "Error getting latest 7-Zip version``: $_" -Level "WARNING"
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
                Write-LogMessage "Error getting latest Notepad++ version``: $_" -Level "WARNING"
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
            Arguments = "/S"
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
            Arguments = "/SILENT"
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
            Url = if ($latestUrl) { $latestUrl } else { "https://github.com/git-for-windows/git/releases/download/v2.49.0.windows.1/Git-2.49.0-64-bit.exe" }
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
            Url = if ($latestUrl) { $latestUrl } else { "https://www.python.org/ftp/python/3.13.4/python-3.13.4-amd64.exe" }
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
            Arguments = "--silent"
            VerificationPaths = @(
                "${env:LocalAppData}\Discord\Update.exe",
                "${env:LocalAppData}\Discord\app-*\Discord.exe",
                "${env:ProgramFiles}\Discord\Discord.exe",
                "${env:ProgramFiles(x86)}\Discord\Discord.exe"
            )
        }
        "Notepad++" = @{
            Url = if ($latestUrl) { $latestUrl } else { "https://github.com/notepad-plus-plus/notepad-plus-plus/releases/download/v8.8.1/npp.8.8.1.Installer.x64.exe" }
            Extension = ".exe"
            Arguments = "/S"
            VerificationPaths = @(
                "${env:ProgramFiles}\Notepad++\notepad++.exe",
                "${env:ProgramFiles(x86)}\Notepad++\notepad++.exe"
            )
        }
        "7-Zip" = @{
            Url = if ($latestUrl) { $latestUrl } else { "https://www.7-zip.org/a/7z2409-x64.exe" }
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
        "IntelliJ IDEA" = @{
            Url = "https://download.jetbrains.com/idea/ideaIC-latest.exe"
            Extension = ".exe"
            Arguments = "/S /CONFIG=${env:TEMP}\IntelliJ_silent_config.config"
            VerificationPaths = @(
                "${env:ProgramFiles}\JetBrains\IntelliJ IDEA Community Edition*\bin\idea64.exe",
                "${env:ProgramFiles(x86)}\JetBrains\IntelliJ IDEA Community Edition*\bin\idea64.exe",
                "${env:LocalAppData}\JetBrains\Toolbox\apps\IDEA-C\*\bin\idea64.exe"
            )
        }
        "WebStorm" = @{
            Url = "https://download.jetbrains.com/webstorm/WebStorm-latest.exe"
            Extension = ".exe"
            Arguments = "/S /CONFIG=${env:TEMP}\WebStorm_silent_config.config"
            VerificationPaths = @(
                "${env:ProgramFiles}\JetBrains\WebStorm*\bin\webstorm64.exe",
                "${env:ProgramFiles(x86)}\JetBrains\WebStorm*\bin\webstorm64.exe",
                "${env:LocalAppData}\JetBrains\Toolbox\apps\WebStorm\*\bin\webstorm64.exe"
            )
        }
        "Android Studio" = @{
            Url = "https://redirector.gvt1.com/edgedl/android/studio/install/2024.2.1.12/android-studio-2024.2.1.12-windows.exe"
            Extension = ".exe"
            Arguments = "/S /CONFIG=${env:TEMP}\AndroidStudio_silent_config.config"
            VerificationPaths = @(
                "${env:ProgramFiles}\Android\Android Studio\bin\studio64.exe",
                "${env:LocalAppData}\Google\AndroidStudio*\bin\studio64.exe"
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
        Write-LogMessage "Failed to verify file checksum``: $_" -Level "ERROR"
        return $false
    }
}

function Install-Winget {
    [CmdletBinding()]
    param(
        [System.Threading.CancellationToken]$CancellationToken
    )
    
    Write-LogMessage "Starting enhanced winget installation process..." -Level "INFO"
    
    # Check for cancellation
    if ($CancellationToken.IsCancellationRequested) {
        Write-LogMessage "Winget installation cancelled" -Level "WARNING"
        return $false
    }
    
    # Import WingetUtils module for enhanced installation
    $wingetUtilsPath = Join-Path (Split-Path $PSScriptRoot) "utils\WingetUtils.psm1"
    if (Test-Path $wingetUtilsPath) {
        Import-Module $wingetUtilsPath -Force -Global
        Write-LogMessage "Imported enhanced WingetUtils module" -Level "INFO"
        
        # Use the enhanced installation environment
        try {
            Write-LogMessage "Initializing winget environment with improved dependency handling..." -Level "INFO"
            $result = Initialize-WingetEnvironment -AllowManualInstall
            
            if ($result.Success) {
                $method = if ($result.Method) { $result.Method } else { "Unknown" }
                $version = if ($result.Version) { $result.Version } else { "Unknown" }
                
                Write-LogMessage "Winget installation successful via $method" -Level "SUCCESS"
                Write-LogMessage "Winget version: $version" -Level "INFO"
                
                if ($result.Message) {
                    Write-LogMessage $result.Message -Level "INFO"
                }
                
                return $true
            } else {
                $reason = if ($result.Reason) { $result.Reason } else { "Unknown" }
                Write-LogMessage "Winget installation failed: $reason" -Level "WARNING"
                
                if ($result.Message) {
                    Write-LogMessage $result.Message -Level "INFO"
                }
                
                # Don't return false immediately - fallback to legacy method
                Write-LogMessage "Attempting legacy installation method as fallback..." -Level "INFO"
            }
        }
        catch {
            Write-LogMessage "Enhanced winget installation failed``: $_" -Level "WARNING"
            Write-LogMessage "Falling back to legacy installation method..." -Level "INFO"
        }
    } else {
        Write-LogMessage "WingetUtils module not found, using legacy installation method" -Level "WARNING"
    }
    
    # Legacy installation method as fallback
    Write-LogMessage "Using legacy winget installation method..." -Level "INFO"
    
    # Check Windows version compatibility first
    $buildNumber = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion").CurrentBuild
    $osName = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion").ProductName
    
    Write-LogMessage "System: $osName (Build $buildNumber)" -Level "INFO"
    
    if ([int]$buildNumber -lt 16299) {
        Write-LogMessage "Windows build $buildNumber is below minimum requirement for winget (16299 = Windows 10 1709)" -Level "ERROR"
        Write-LogMessage "Winget is not supported on this Windows version" -Level "ERROR"
        return $false
    }
    
    # Check if winget is already installed and working
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        try {
            $version = winget --version 2>$null
            if ($version -and $version.Trim() -ne "") {
                Write-LogMessage "Winget is already installed and working: $version" -Level "INFO"
                return $true
            }
        }
        catch {
            Write-LogMessage "Winget command exists but not working properly" -Level "WARNING"
        }
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
        Write-LogMessage "Attempting to register winget with extended wait time..." -Level "INFO"
        
        try {
            Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe
            Write-LogMessage "Winget registration command completed" -Level "INFO"
            
            # Extended wait and verification
            Write-LogMessage "Waiting for winget registration to complete (15 seconds)..." -Level "INFO"
            Start-Sleep -Seconds 15
            
            # Multiple verification attempts
            for ($attempt = 1; $attempt -le 5; $attempt++) {
                if (Get-Command winget -ErrorAction SilentlyContinue) {
                    try {
                        $version = winget --version 2>$null
                        if ($version -and $version.Trim() -ne "") {
                            Write-LogMessage "Winget successfully registered: $version" -Level "SUCCESS"
                            return $true
                        }
                    }
                    catch {
                        Write-LogMessage "Winget test failed on attempt $attempt" -Level "DEBUG"
                    }
                }
                
                if ($attempt -lt 5) {
                    Write-LogMessage "Winget not ready yet, waiting 5 more seconds... (attempt $attempt/5)" -Level "INFO"
                    Start-Sleep -Seconds 5
                }
            }
            
            Write-LogMessage "Winget registration completed but command not yet available" -Level "WARNING"
            Write-LogMessage "This may require a new PowerShell session" -Level "INFO"
        } catch {
            Write-LogMessage "Failed to register winget``: $_" -Level "WARNING"
        }
    }
    
    # Try Microsoft Store installation with extended wait
    Write-LogMessage "Attempting to install winget via Microsoft Store..." -Level "INFO"
    try {
        $wingetUrl = "ms-windows-store://pdp/?ProductId=9NBLGGH4NNS1"
        Start-Process $wingetUrl
        Write-LogMessage "Opened Microsoft Store for winget installation" -Level "INFO"
        Write-LogMessage "Please complete the installation and the script will wait for verification..." -Level "INFO"
        
        # Wait for user to complete Store installation with periodic checks
        for ($check = 1; $check -le 12; $check++) {
            Start-Sleep -Seconds 10
            
            if (Get-Command winget -ErrorAction SilentlyContinue) {
                try {
                    $version = winget --version 2>$null
                    if ($version -and $version.Trim() -ne "") {
                        Write-LogMessage "Winget detected after Store installation: $version" -Level "SUCCESS"
                        return $true
                    }
                }
                catch {
                    # Continue checking
                }
            }
            
            Write-LogMessage "Waiting for Store installation completion... (check $check/12)" -Level "INFO"
        }
        
        Write-LogMessage "Store installation timeout - proceeding to direct download" -Level "WARNING"
    }
    catch {
        Write-LogMessage "Failed to open Microsoft Store``: $_" -Level "WARNING"
    }
    
    # Fallback to direct download with enhanced error handling
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
        $release = Invoke-RestMethod -Uri $releaseUrl -TimeoutSec 30
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
        
        $fileSize = (Get-Item $downloadPath).Length
        Write-LogMessage "Download completed successfully ($([math]::Round($fileSize/1MB, 2)) MB)" -Level "SUCCESS"
        
        # Install the bundle with retry logic
        Write-LogMessage "Installing winget package..." -Level "INFO"
        
        $installSuccess = $false
        for ($attempt = 1; $attempt -le 3; $attempt++) {
            try {
                Add-AppxPackage -Path $downloadPath -ForceApplicationShutdown -ErrorAction Stop
                Write-LogMessage "Winget package installation completed (attempt $attempt)" -Level "SUCCESS"
                $installSuccess = $true
                break
            }
            catch {
                Write-LogMessage "Installation attempt $attempt failed``: $_" -Level "WARNING"
                if ($attempt -lt 3) {
                    Start-Sleep -Seconds 5
                }
            }
        }
        
        # Clean up download
        Remove-Item $downloadPath -Force -ErrorAction SilentlyContinue
        Write-LogMessage "Cleaned up downloaded package" -Level "INFO"
        
        if (-not $installSuccess) {
            Write-LogMessage "Failed to install winget after all attempts" -Level "ERROR"
            return $false
        }
        
        # Extended verification with multiple attempts
        Write-LogMessage "Verifying winget installation (extended verification)..." -Level "INFO"
        
        for ($attempt = 1; $attempt -le 10; $attempt++) {
            Start-Sleep -Seconds 5
            
            if (Get-Command winget -ErrorAction SilentlyContinue) {
                try {
                    $version = winget --version 2>$null
                    if ($version -and $version.Trim() -ne "") {
                        Write-LogMessage "Winget installed successfully! Version: $version" -Level "SUCCESS"
                        return $true
                    }
                }
                catch {
                    Write-LogMessage "Winget verification attempt $attempt failed" -Level "DEBUG"
                }
            }
            
            Write-LogMessage "Winget not ready yet, waiting... (attempt $attempt/10)" -Level "INFO"
        }
        
        Write-LogMessage "Winget installation completed but command not immediately available" -Level "WARNING"
        Write-LogMessage "This is common and usually resolves in new PowerShell sessions" -Level "INFO"
        return $true  # Return true since installation commands succeeded
    }
    catch {
        Write-LogMessage "Failed to install winget``: $_" -Level "ERROR"
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
        Write-LogMessage "Error creating silent config for $AppName```: $_" -Level "ERROR"
        return $null
    }
}

function Install-Application {
    param(
        [Parameter(Mandatory=$true)]
        [string]$AppName,
        [Parameter(Mandatory=$false)]
        [string]$AppKey = "",
        [Parameter(Mandatory=$false)]
        [string]$WingetId = "",
        [Parameter(Mandatory=$false)]
        [hashtable]$DirectDownload = $null,
        [Parameter(Mandatory=$false)]
        [switch]$Force,
        [System.Threading.CancellationToken]$CancellationToken = [System.Threading.CancellationToken]::None
    )
    
    Write-LogMessage "Installing application: $AppName" -Level "INFO"
    
    # Track in recovery system
    $trackingKey = if ($AppKey -and $AppKey -ne "") { $AppKey } else { $AppName }
    Save-OperationState -OperationType "InstallApp" -ItemKey $trackingKey -Status "InProgress"
    
    # Check for cancellation
    if ($CancellationToken -and $CancellationToken -ne [System.Threading.CancellationToken]::None -and $CancellationToken.IsCancellationRequested) {
        Write-LogMessage "Installation cancelled" -Level "WARNING"
        Save-OperationState -OperationType "InstallApp" -ItemKey $trackingKey -Status "Cancelled"
        return $false
    }
    
    # Skip if already installed and not forced
    if (-not $Force) {
        $isInstalled = Test-ApplicationInstalled -AppName $AppName -CheckCommand
        if ($isInstalled) {
            Write-LogMessage "$AppName is already installed, skipping installation" -Level "INFO"
            Save-OperationState -OperationType "InstallApp" -ItemKey $trackingKey -Status "Skipped" -AdditionalData @{
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
    
    # Enhanced winget installation with proper dependency checks and extended time
    if (-not $script:UseDirectDownloadOnly -and $wingetCompatible) {
        
        # First, ensure winget is properly installed and working
        Write-LogMessage "Verifying winget installation status..." -Level "INFO"
        $wingetAvailable = $false
        
        if (Get-Command winget -ErrorAction SilentlyContinue) {
            try {
                $version = winget --version 2>$null
                if ($version -and $version.Trim() -ne "") {
                    Write-LogMessage "Winget is available: $version" -Level "INFO"
                    $wingetAvailable = $true
                } else {
                    Write-LogMessage "Winget command exists but version check failed" -Level "WARNING"
                }
            }
            catch {
                Write-LogMessage "Winget command exists but not working properly``: $_" -Level "WARNING"
            }
        }
        
        # If winget is not available, try to install it first with extended time
        if (-not $wingetAvailable) {
            Write-LogMessage "Winget not available, attempting installation before proceeding..." -Level "INFO"
            
            # Try to install winget with extended time allowance
            $wingetInstalled = Install-Winget -CancellationToken $CancellationToken
            
            if ($wingetInstalled) {
                Write-LogMessage "Winget installation completed, waiting for availability..." -Level "INFO"
                
                # Extended wait for winget to become available after installation
                for ($attempt = 1; $attempt -le 8; $attempt++) {
                    Start-Sleep -Seconds 8
                    
                    if (Get-Command winget -ErrorAction SilentlyContinue) {
                        try {
                            $version = winget --version 2>$null
                            if ($version -and $version.Trim() -ne "") {
                                Write-LogMessage "Winget is now available after installation: $version" -Level "SUCCESS"
                                $wingetAvailable = $true
                                break
                            }
                        }
                        catch {
                            Write-LogMessage "Winget still not working on attempt $attempt" -Level "DEBUG"
                        }
                    }
                    
                    Write-LogMessage "Waiting for winget to become available... (attempt $attempt/8)" -Level "INFO"
                }
                
                if (-not $wingetAvailable) {
                    Write-LogMessage "Winget installation completed but command not available after extended wait" -Level "WARNING"
                    Write-LogMessage "Proceeding with direct download method" -Level "INFO"
                }
            } else {
                Write-LogMessage "Winget installation failed, proceeding with direct download method" -Level "WARNING"
            }
        }
        
        # If winget is available, try to use it for installation
        if ($wingetAvailable) {
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
                
                # Enhanced winget installation with retry logic
                $wingetSuccess = $false
                for ($attempt = 1; $attempt -le 2; $attempt++) {
                    try {
                        Write-LogMessage "Winget installation attempt $attempt/2 for $AppName..." -Level "INFO"
                        $wingetOutput = winget install --id $WingetId --accept-source-agreements --accept-package-agreements --silent 2>&1
                        
                        if ($LASTEXITCODE -eq 0 -or $wingetOutput -match "Successfully installed") {
                            Write-LogMessage "$AppName installed successfully via winget!" -Level "SUCCESS"
                            Save-OperationState -OperationType "InstallApp" -ItemKey $trackingKey -Status "Completed" -AdditionalData @{
                                Method = "Winget"
                                WingetId = $WingetId
                                WindowsBuild = $buildNumber
                                Attempt = $attempt
                            }
                            
                            # Refresh environment variables
                            $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
                            
                            $wingetSuccess = $true
                            break
                        }
                        else {
                            Write-LogMessage "Winget installation attempt $attempt failed with exit code: $LASTEXITCODE" -Level "WARNING"
                            Write-LogMessage "Winget output: $wingetOutput" -Level "DEBUG"
                            
                            if ($attempt -lt 2) {
                                Write-LogMessage "Waiting 5 seconds before retry..." -Level "INFO"
                                Start-Sleep -Seconds 5
                            }
                        }
                    }
                    catch {
                        Write-LogMessage "Error using winget on attempt $attempt```: $_" -Level "WARNING"
                        if ($attempt -lt 2) {
                            Start-Sleep -Seconds 5
                        }
                    }
                }
                
                if ($wingetSuccess) {
                    return $true
                } else {
                    Write-LogMessage "All winget installation attempts failed for $AppName" -Level "WARNING"
                    Write-LogMessage "Windows build: $buildNumber (winget requires 16299+)" -Level "DEBUG"
                    Write-LogMessage "Proceeding with direct download method..." -Level "INFO"
                }
            } else {
                Write-LogMessage "No winget ID mapping found for $AppName, using direct download" -Level "INFO"
            }
        } else {
            Write-LogMessage "Winget not available for $AppName installation, using direct download" -Level "INFO"
        }
    } else {
        if ($script:UseDirectDownloadOnly) {
            Write-LogMessage "Direct download mode enabled, skipping winget for $AppName" -Level "INFO"
        } elseif (-not $wingetCompatible) {
            Write-LogMessage "Windows build $buildNumber incompatible with winget, using direct download for $AppName" -Level "INFO"
        }
    }
    
    # If no direct download info was provided, try to get it from configuration
    if ($null -eq $DirectDownload) {
        # Use AppKey if provided, otherwise fall back to AppName
        $keyToUse = if ($AppKey -and $AppKey -ne "") { $AppKey } else { $AppName }
        
        # Get download info from JSON configuration with dynamic URL resolution
        $DirectDownload = Get-AppDownloadInfo -AppKey $keyToUse
        
        if ($DirectDownload -and $DirectDownload.ResolvedUrl) {
            Write-LogMessage "Using dynamically resolved URL for $AppName : $($DirectDownload.ResolvedUrl)" -Level "INFO"
            $DirectDownload.ActualUrl = $DirectDownload.ResolvedUrl
        } elseif ($DirectDownload) {
            $DirectDownload.ActualUrl = $DirectDownload.Url
        }
        
        # Fallback to legacy method if JSON config fails
        if ($null -eq $DirectDownload) {
            $latestUrl = Get-LatestVersionUrl -ApplicationName $AppName
            $DirectDownload = Get-AppDirectDownloadInfo -AppName $AppName
            
            if ($latestUrl -and $DirectDownload) {
                Write-LogMessage "Using legacy dynamic URL resolution for $AppName" -Level "INFO"
                $DirectDownload.ActualUrl = $latestUrl
            }
        }
    }
    
    if ($null -eq $DirectDownload) {
        Write-LogMessage "No download information available for $AppName" -Level "ERROR"
        Save-OperationState -OperationType "InstallApp" -ItemKey $trackingKey -Status "Failed" -AdditionalData @{
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
        
        # Handle special installation types
        if ($DirectDownload.UrlType -eq "feature-install") {
            Write-LogMessage "Installing Windows feature: $AppName" -Level "INFO"
            return Install-WindowsFeature -FeatureInfo $DirectDownload -AppName $AppName
        }
        
        # Use the resolved URL for download
        $downloadUrl = if ($DirectDownload.ActualUrl) { $DirectDownload.ActualUrl } else { $DirectDownload.Url }
        
        # Download the installer
        $installerPath = Join-Path $appDir "$AppName$($DirectDownload.Extension)"
        Write-LogMessage "Downloading from: $downloadUrl" -Level "INFO"
        
        try {
            $webClient = New-Object System.Net.WebClient
            $webClient.DownloadFile($downloadUrl, $installerPath)
            Write-LogMessage "Download completed successfully" -Level "SUCCESS"
        }
        catch {
            Write-LogMessage "Download failed``: $_" -Level "ERROR"
            Save-OperationState -OperationType "InstallApp" -ItemKey $trackingKey -Status "Failed" -AdditionalData @{
                Error = "Download failed`: $_"
                Time = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            }
            return $false
        }
        
        # Check for cancellation
        if ($CancellationToken -and $CancellationToken -ne [System.Threading.CancellationToken]::None -and $CancellationToken.IsCancellationRequested) {
            Write-LogMessage "Installation cancelled" -Level "WARNING"
            Save-OperationState -OperationType "InstallApp" -ItemKey $trackingKey -Status "Cancelled"
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
                Write-LogMessage "Add-AppxPackage failed, trying winget fallback``: $_" -Level "WARNING"
                
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
                    throw "Failed to install MSIX bundle and winget not available`: $_"
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
            Save-OperationState -OperationType "InstallApp" -ItemKey $trackingKey -Status "Cancelled" -AdditionalData @{
                Time = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            }
            return $false
        }
        elseif ($process.PSObject.Properties.Name -contains "TimedOut" -and $process.TimedOut) {
            Write-LogMessage "Installation timed out after $script:InstallerTimeoutMinutes minutes" -Level "ERROR"
            Save-OperationState -OperationType "InstallApp" -ItemKey $trackingKey -Status "Failed" -AdditionalData @{
                Error = "Installation timed out"
                TimeoutMinutes = $script:InstallerTimeoutMinutes
                Time = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            }
            return $false
        }
        elseif ($process.ExitCode -eq 0) {
            Write-LogMessage "Installation completed successfully" -Level "SUCCESS"
            
            # Verify installation
            $verificationResult = Test-ApplicationInstalled -AppName $AppName -VerificationPaths $DirectDownload.VerificationPaths -CheckCommand
            
            if ($verificationResult) {
                Write-LogMessage "Installation verified for $AppName" -Level "SUCCESS"
                Save-OperationState -OperationType "InstallApp" -ItemKey $trackingKey -Status "Completed" -AdditionalData @{
                    Method = "Direct"
                    Url = $DirectDownload.Url
                }
            } else {
                Write-LogMessage "Installation completed but verification failed for $AppName" -Level "WARNING"
                Save-OperationState -OperationType "InstallApp" -ItemKey $trackingKey -Status "CompletedWithWarning" -AdditionalData @{
                    Method = "Direct"
                    Url = $DirectDownload.Url
                    Warning = "Verification failed"
                }
            }
            
            # Clean up installer
            Remove-Item $installerPath -Force -ErrorAction SilentlyContinue
            
            # Handle post-install actions
            if ($DirectDownload.PostInstall) {
                Invoke-PostInstallActions -PostInstallInfo $DirectDownload.PostInstall -AppName $AppName
            }
            
            return $true
        } else {
            Write-LogMessage "Installation failed with exit code: $($process.ExitCode)" -Level "ERROR"
            Save-OperationState -OperationType "InstallApp" -ItemKey $trackingKey -Status "Failed" -AdditionalData @{
                Error = "Installation failed with exit code: $($process.ExitCode)"
                Time = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            }
            return $false
        }
    }
    catch {
        Write-LogMessage "Failed to install $AppName ``: $_" -Level "ERROR"
        Save-OperationState -OperationType "InstallApp" -ItemKey $trackingKey -Status "Failed" -AdditionalData @{
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
            Write-LogMessage "Winget installation failed``: $_" -Level "WARNING"
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
                    Write-LogMessage "Warning: Could not upgrade pip``: $_" -Level "WARNING"
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
        Write-LogMessage "Failed to install Python``: $_" -Level "ERROR"
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
            Write-LogMessage "Error installing extension $ext ``: $_" -Level "ERROR"
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

function Install-WindowsFeature {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$FeatureInfo,
        [Parameter(Mandatory=$true)]
        [string]$AppName
    )
    
    try {
        Write-LogMessage "Installing Windows feature: $AppName" -Level "INFO"
        
        if ($FeatureInfo.Commands) {
            foreach ($command in $FeatureInfo.Commands) {
                Write-LogMessage "Executing: $command" -Level "INFO"
                $result = Invoke-Expression $command
                
                if ($LASTEXITCODE -ne 0) {
                    Write-LogMessage "Command failed with exit code: $LASTEXITCODE" -Level "WARNING"
                } else {
                    Write-LogMessage "Command completed successfully" -Level "SUCCESS"
                }
            }
        }
        
        # Handle post-install actions for features
        if ($FeatureInfo.PostInstall) {
            Invoke-PostInstallActions -PostInstallInfo $FeatureInfo.PostInstall -AppName $AppName
        }
        
        Write-LogMessage "Windows feature installation completed: $AppName" -Level "SUCCESS"
        return $true
    }
    catch {
        Write-LogMessage "Failed to install Windows feature $AppName ``: $_" -Level "ERROR"
        return $false
    }
}

function Invoke-PostInstallActions {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$PostInstallInfo,
        [Parameter(Mandatory=$true)]
        [string]$AppName
    )
    
    try {
        Write-LogMessage "Processing post-install actions for $AppName" -Level "INFO"
        
        # Set environment variables
        if ($PostInstallInfo.EnvironmentVariables) {
            foreach ($envVar in $PostInstallInfo.EnvironmentVariables) {
                $name = $envVar.Name
                $value = $envVar.Value
                $target = if ($envVar.Target) { $envVar.Target } else { "User" }
                
                # Expand environment variables in the value
                $expandedValue = [System.Environment]::ExpandEnvironmentVariables($value)
                
                Write-LogMessage "Setting environment variable: $name = $expandedValue (Target: $target)" -Level "INFO"
                [System.Environment]::SetEnvironmentVariable($name, $expandedValue, $target)
            }
        }
        
        # Show restart required message
        if ($PostInstallInfo.RestartRequired) {
            $message = if ($PostInstallInfo.Message) { $PostInstallInfo.Message } else { "$AppName requires a system restart to complete installation" }
            Write-LogMessage $message -Level "WARNING"
            
            # Could add GUI notification here
        }
        
        # Display additional steps
        if ($PostInstallInfo.AdditionalSteps) {
            Write-LogMessage "Additional steps required for $AppName :" -Level "INFO"
            foreach ($step in $PostInstallInfo.AdditionalSteps) {
                Write-LogMessage "  - $step" -Level "INFO"
            }
        }
        
        # Execute post-install commands
        if ($PostInstallInfo.Commands) {
            foreach ($command in $PostInstallInfo.Commands) {
                Write-LogMessage "Executing post-install command: $command" -Level "INFO"
                try {
                    $result = Invoke-Expression $command
                    if ($LASTEXITCODE -eq 0) {
                        Write-LogMessage "Post-install command completed successfully" -Level "SUCCESS"
                    } else {
                        Write-LogMessage "Post-install command failed with exit code: $LASTEXITCODE" -Level "WARNING"
                    }
                }
                catch {
                    Write-LogMessage "Post-install command error``: $_" -Level "ERROR"
                }
            }
        }
        
        Write-LogMessage "Post-install actions completed for $AppName" -Level "SUCCESS"
    }
    catch {
        Write-LogMessage "Error in post-install actions for $AppName ``: $_" -Level "ERROR"
    }
}

function Get-OptimalConcurrency {
    [CmdletBinding()]
    param()
    
    try {
        # Get system information
        $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
        $memory = Get-CimInstance Win32_ComputerSystem
        $os = Get-CimInstance Win32_OperatingSystem
        
        $coreCount = $cpu.NumberOfCores
        $totalMemoryGB = [math]::Round($memory.TotalPhysicalMemory / 1GB, 1)
        $availableMemoryGB = [math]::Round($os.FreePhysicalMemory / 1MB / 1024, 1)
        
        Write-LogMessage "System: $coreCount cores, $totalMemoryGB GB total RAM, $availableMemoryGB GB available" -Level "INFO"
        
        # Determine optimal concurrency based on system resources
        $concurrency = 1  # Start conservative
        
        # CPU-based scaling
        if ($coreCount -ge 8) {
            $concurrency = 4
        } elseif ($coreCount -ge 4) {
            $concurrency = 3
        } elseif ($coreCount -ge 2) {
            $concurrency = 2
        }
        
        # Memory constraints (reduce if low memory)
        if ($availableMemoryGB -lt 2) {
            $concurrency = 1
            Write-LogMessage "Limited available memory detected - using sequential installation" -Level "WARNING"
        } elseif ($availableMemoryGB -lt 4) {
            $concurrency = [math]::Min($concurrency, 2)
            Write-LogMessage "Moderate memory available - limiting concurrency to 2" -Level "INFO"
        }
        
        # Total memory constraints
        if ($totalMemoryGB -lt 4) {
            $concurrency = 1
            Write-LogMessage "Low total memory system detected - using sequential installation" -Level "WARNING"
        } elseif ($totalMemoryGB -lt 8) {
            $concurrency = [math]::Min($concurrency, 2)
        }
        
        Write-LogMessage "Recommended concurrency level: $concurrency" -Level "INFO"
        return $concurrency
    }
    catch {
        Write-LogMessage "Error detecting system resources, defaulting to sequential installation``: $_" -Level "WARNING"
        return 1
    }
}

function Install-ApplicationBatch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string[]]$AppKeys,
        [Parameter(Mandatory=$false)]
        [int]$MaxConcurrency = 0,  # 0 = auto-detect
        [Parameter(Mandatory=$false)]
        [switch]$ForceParallel,
        [System.Threading.CancellationToken]$CancellationToken = [System.Threading.CancellationToken]::None
    )
    
    # Determine optimal concurrency
    if ($MaxConcurrency -eq 0) {
        $MaxConcurrency = Get-OptimalConcurrency
    }
    
    # Safety check - if system is too weak and not forced, suggest sequential
    if ($MaxConcurrency -eq 1 -and -not $ForceParallel -and $AppKeys.Count -gt 1) {
        Write-LogMessage "System resources suggest sequential installation would be safer." -Level "WARNING"
        Write-LogMessage "Consider using 'Run Selected Tasks' instead, or use -ForceParallel to override." -Level "INFO"
        
        # Ask user preference via return code that GUI can handle
        return @{
            Completed = @()
            Failed = @()
            Total = $AppKeys.Count
            Recommendation = "sequential"
            Message = "Weak system detected. Sequential installation recommended for stability."
        }
    }
    
    Write-LogMessage "Starting batch installation of $($AppKeys.Count) applications (Concurrency: $MaxConcurrency)" -Level "INFO"
    
    $jobs = @()
    $completed = @()
    $failed = @()
    
    try {
        $appQueue = [System.Collections.Queue]::new($AppKeys)
        $runningJobs = @{}
        
        while ($appQueue.Count -gt 0 -or $runningJobs.Count -gt 0) {
            # Start new jobs up to max concurrency
            while ($runningJobs.Count -lt $MaxConcurrency -and $appQueue.Count -gt 0) {
                $appKey = $appQueue.Dequeue()
                $installerName = Get-InstallerName -AppKey $appKey
                
                Write-LogMessage "Starting installation: $installerName" -Level "INFO"
                
                $scriptBlock = {
                    param($AppKey, $InstallerName)
                    
                    try {
                        $result = Install-Application -AppName $InstallerName -AppKey $AppKey -CancellationToken $using:CancellationToken
                        return @{
                            AppKey = $AppKey
                            AppName = $InstallerName
                            Success = $result
                            Error = $null
                        }
                    }
                    catch {
                        return @{
                            AppKey = $AppKey
                            AppName = $InstallerName
                            Success = $false
                            Error = $_.Exception.Message
                        }
                    }
                }
                
                $job = Start-Job -ScriptBlock $scriptBlock -ArgumentList $appKey, $installerName
                $runningJobs[$job.Id] = @{
                    Job = $job
                    AppKey = $appKey
                    AppName = $installerName
                    StartTime = Get-Date
                }
            }
            
            # Check for completed jobs
            $completedJobs = $runningJobs.Values | Where-Object { $_.Job.State -in @('Completed', 'Failed', 'Stopped') }
            
            foreach ($jobInfo in $completedJobs) {
                $job = $jobInfo.Job
                $result = Receive-Job -Job $job
                Remove-Job -Job $job
                
                $runningJobs.Remove($job.Id)
                
                if ($result.Success) {
                    $completed += $result.AppKey
                    Write-LogMessage "Completed: $($result.AppName)" -Level "SUCCESS"
                } else {
                    $failed += $result.AppKey
                    Write-LogMessage "Failed: $($result.AppName) - $($result.Error)" -Level "ERROR"
                }
            }
            
            # Check for cancellation
            if ($CancellationToken.IsCancellationRequested) {
                Write-LogMessage "Batch installation cancelled" -Level "WARNING"
                break
            }
            
            Start-Sleep -Seconds 1
        }
        
        # Clean up any remaining jobs
        foreach ($jobInfo in $runningJobs.Values) {
            Stop-Job -Job $jobInfo.Job -ErrorAction SilentlyContinue
            Remove-Job -Job $jobInfo.Job -ErrorAction SilentlyContinue
        }
        
        Write-LogMessage "Batch installation completed. Success: $($completed.Count), Failed: $($failed.Count)" -Level "INFO"
        
        return @{
            Completed = $completed
            Failed = $failed
            Total = $AppKeys.Count
        }
    }
    catch {
        Write-LogMessage "Error in batch installation``: $_" -Level "ERROR"
        return @{
            Completed = $completed
            Failed = $failed + ($AppKeys | Where-Object { $_ -notin $completed })
            Total = $AppKeys.Count
        }
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
    'Set-PathEnvironment',
    'Install-WindowsFeature',
    'Invoke-PostInstallActions',
    'Install-ApplicationBatch',
    'Get-OptimalConcurrency'
)