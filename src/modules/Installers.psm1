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
}

function Get-AppDirectDownloadInfo {
    param (
        [Parameter(Mandatory=$true)]
        [string]$AppName
    )
    
    # Define download information for common applications (matching GUI app keys)
    $downloadInfo = @{
        "vscode" = @{
            Url = "https://code.visualstudio.com/sha/download?build=stable&os=win32-x64"
            FileName = "VSCodeSetup-x64.exe"
            FileType = "exe"
            Arguments = "/VERYSILENT /MERGETASKS=!runcode"
        }
        "git" = @{
            Url = "https://github.com/git-for-windows/git/releases/download/v2.43.0.windows.1/Git-2.43.0-64-bit.exe"
            FileName = "Git-2.43.0-64-bit.exe"
            FileType = "exe"
            Arguments = "/VERYSILENT /NORESTART /NOCANCEL /SP- /CLOSEAPPLICATIONS /RESTARTAPPLICATIONS"
        }
        "python" = @{
            Url = "https://www.python.org/ftp/python/3.12.1/python-3.12.1-amd64.exe"
            FileName = "python-3.12.1-amd64.exe"
            FileType = "exe"
            Arguments = "/quiet InstallAllUsers=1 PrependPath=1"
        }
        "pycharm" = @{
            Url = "https://download.jetbrains.com/python/pycharm-community-2023.3.2.exe"
            FileName = "pycharm-community-2023.3.2.exe"
            FileType = "exe"
            Arguments = "/S /CONFIG=silent.config"
        }
        "github" = @{
            Url = "https://central.github.com/deployments/desktop/desktop/latest/win32"
            FileName = "GitHubDesktopSetup.exe"
            FileType = "exe"
            Arguments = "--silent"
        }
        "postman" = @{
            Url = "https://dl.pstmn.io/download/latest/win64"
            FileName = "PostmanSetup.exe"
            FileType = "exe"
            Arguments = "--silent"
        }
        "nodejs" = @{
            Url = "https://nodejs.org/dist/v20.10.0/node-v20.10.0-x64.msi"
            FileName = "node-v20.10.0-x64.msi"
            FileType = "msi"
            Arguments = "/quiet /norestart"
        }
        "chrome" = @{
            Url = "https://dl.google.com/chrome/install/latest/chrome_installer.exe"
            FileName = "chrome_installer.exe"
            FileType = "exe"
            Arguments = "/silent /install"
        }
        "firefox" = @{
            Url = "https://download.mozilla.org/?product=firefox-latest&os=win64&lang=en-US"
            FileName = "FirefoxSetup.exe"
            FileType = "exe"
            Arguments = "/S"
        }
        "brave" = @{
            Url = "https://referrals.brave.com/latest/BraveBrowserSetup.exe"
            FileName = "BraveBrowserSetup.exe"
            FileType = "exe"
            Arguments = "/silent /install"
        }
        "spotify" = @{
            Url = "https://download.scdn.co/SpotifySetup.exe"
            FileName = "SpotifySetup.exe"
            FileType = "exe"
            Arguments = "/silent"
        }
        "discord" = @{
            Url = "https://discord.com/api/downloads/distributions/app/installers/latest?channel=stable&platform=win&arch=x64"
            FileName = "DiscordSetup.exe"
            FileType = "exe"
            Arguments = "--silent"
        }
        "steam" = @{
            Url = "https://cdn.akamai.steamstatic.com/client/installer/SteamSetup.exe"
            FileName = "SteamSetup.exe"
            FileType = "exe"
            Arguments = "/S"
        }
        "vlc" = @{
            Url = "https://download.videolan.org/vlc/last/win64/vlc-3.0.20-win64.exe"
            FileName = "vlc-3.0.20-win64.exe"
            FileType = "exe"
            Arguments = "/S"
        }
        "7zip" = @{
            Url = "https://www.7-zip.org/a/7z2301-x64.msi"
            FileName = "7z2301-x64.msi"
            FileType = "msi"
            Arguments = "/quiet /norestart"
        }
        "notepadplusplus" = @{
            Url = "https://github.com/notepad-plus-plus/notepad-plus-plus/releases/download/v8.6.2/npp.8.6.2.Installer.x64.exe"
            FileName = "npp.8.6.2.Installer.x64.exe"
            FileType = "exe"
            Arguments = "/S"
        }
        "powertoys" = @{
            Url = "https://github.com/microsoft/PowerToys/releases/download/v0.78.0/PowerToysSetup-0.78.0-x64.exe"
            FileName = "PowerToysSetup-0.78.0-x64.exe"
            FileType = "exe"
            Arguments = "/silent"
        }
        "terminal" = @{
            Url = "https://github.com/microsoft/terminal/releases/download/v1.18.3282.0/Microsoft.WindowsTerminal_Win11_1.18.3282.0_8wekyb3d8bbwe.msixbundle"
            FileName = "Microsoft.WindowsTerminal.msixbundle"
            FileType = "msixbundle"
            Arguments = ""
        }
    }
    
    return $downloadInfo[$AppName]
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
        Write-Log "Failed to verify file checksum: $_" -Level "ERROR"
        return $false
    }
}

function Install-Winget {
    [CmdletBinding()]
    param(
        [System.Threading.CancellationToken]$CancellationToken
    )
    
    Write-Log "Starting winget installation..." -Level "INFO"
    
    # Check for cancellation
    if ($CancellationToken.IsCancellationRequested) {
        Write-Log "Winget installation cancelled" -Level "WARNING"
        return $false
    }
    
    # Check if winget is already installed
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        Write-Log "Winget is already installed" -Level "INFO"
        return $true
    }
    
    # Try Microsoft Store installation
    Write-Log "Attempting to install winget via Microsoft Store..." -Level "INFO"
    try {
        $wingetUrl = "ms-windows-store://pdp/?ProductId=9NBLGGH4NNS1"
        Start-Process $wingetUrl
        Write-Log "Please complete the winget installation from the Microsoft Store" -Level "INFO"
        return $true
    }
    catch {
        Write-Log "Failed to open Microsoft Store: $_" -Level "WARNING"
    }
    
    # Fallback to direct download
    Write-Log "Attempting direct download of winget..." -Level "INFO"
    try {
        $tempDir = Join-Path $env:TEMP "winget-install"
        if (-not (Test-Path $tempDir)) {
            New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
        }
        
        # Download the latest winget release
        $releaseUrl = "https://api.github.com/repos/microsoft/winget-cli/releases/latest"
        $release = Invoke-RestMethod -Uri $releaseUrl
        $msixBundle = $release.assets | Where-Object { $_.name -like "*.msixbundle" } | Select-Object -First 1
        
        if ($null -eq $msixBundle) {
            Write-Log "Could not find winget MSIX bundle" -Level "ERROR"
            return $false
        }
        
        $downloadPath = Join-Path $tempDir $msixBundle.name
        Invoke-WebRequest -Uri $msixBundle.browser_download_url -OutFile $downloadPath
        
        # Install the bundle
        Add-AppxPackage -Path $downloadPath
        
        Write-Log "Winget installed successfully!" -Level "SUCCESS"
        return $true
    }
    catch {
        Write-Log "Failed to install winget: $_" -Level "ERROR"
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
        $installerPath = Join-Path $env:TEMP $pythonDownload.FileName
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

function Update-Environment {
    Write-Log "Updating environment variables..." -Level "INFO"
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
}

function Install-Application {
    param (
        [Parameter(Mandatory=$true)]
        [string]$AppName,
        
        [Parameter(Mandatory=$false)]
        [string]$WingetId,
        
        [Parameter(Mandatory=$false)]
        [hashtable]$DirectDownload,
        
        [System.Threading.CancellationToken]$CancellationToken
    )

    Write-Log "Installing ${AppName}..." -Level "INFO"
    
    # Check for cancellation
    if ($CancellationToken.IsCancellationRequested) {
        Write-Log "Installation cancelled" -Level "WARNING"
        return $false
    }
    
    # Check if already installed with correct version
    $installedVersion = Test-InstalledVersion -AppName $AppName
    if ($installedVersion) {
        Write-Log "${AppName} version $installedVersion is already installed" -Level "INFO"
        return $true
    }
    
    # Try winget first if not using direct download only
    if (-not $script:UseDirectDownloadOnly) {
        try {
            if ($WingetId) {
                Write-Log "Attempting to install ${AppName} using winget..." -Level "INFO"
                $wingetOutput = winget install --id $WingetId --silent --accept-source-agreements --accept-package-agreements 2>&1
                
                if ($LASTEXITCODE -eq 0 -or $wingetOutput -match "Successfully installed") {
                    Write-Log "Successfully installed ${AppName} using winget" -Level "SUCCESS"
                    return $true
                } else {
                    Write-Log "Winget installation failed for ${AppName} with exit code $LASTEXITCODE" -Level "WARNING"
                }
            }
        } catch {
            Write-Log "Winget installation failed for ${AppName}: $($_.Exception.Message)" -Level "WARNING"
        }
    }
    
    # Try direct download if available
    if ($DirectDownload) {
        $tempFile = Join-Path $env:TEMP $DirectDownload.FileName
        $retryCount = 0
        
        while ($retryCount -lt $script:MaxRetries) {
            try {
                Write-Log "Downloading ${AppName} from direct source (Attempt $($retryCount + 1))..." -Level "INFO"
                
                # Download the file
                Invoke-WebRequest -Uri $DirectDownload.Url -OutFile $tempFile
                
                # Verify checksum if available
                if ($DirectDownload.Checksum -and -not (Test-FileChecksum -FilePath $tempFile -ExpectedChecksum $DirectDownload.Checksum)) {
                    throw "File checksum verification failed"
                }
                
                # Install based on file type
                $success = $false
                switch ($DirectDownload.FileType) {
                    "msi" {
                        $process = Start-Process msiexec.exe -ArgumentList "/i `"$tempFile`" /quiet /norestart" -Wait -PassThru
                        $success = $process.ExitCode -eq 0
                    }
                    "exe" {
                        $process = Start-Process $tempFile -ArgumentList $DirectDownload.InstallArgs -Wait -PassThru
                        $success = $process.ExitCode -eq 0
                    }
                    default {
                        throw "Unsupported file type: $($DirectDownload.FileType)"
                    }
                }
                
                if ($success) {
                    Write-Log "Successfully installed ${AppName}" -Level "SUCCESS"
                    return $true
                } else {
                    throw "Installation failed with exit code $($process.ExitCode)"
                }
            }
            catch {
                $retryCount++
                if ($retryCount -lt $script:MaxRetries) {
                    Write-Log "Installation attempt $retryCount failed: $_" -Level "WARNING"
                    Write-Log "Retrying in $script:RetryDelay seconds..." -Level "INFO"
                    Start-Sleep -Seconds $script:RetryDelay
                } else {
                    Write-Log "All installation attempts failed for ${AppName}: $_" -Level "ERROR"
                }
            }
            finally {
                # Cleanup
                if (Test-Path $tempFile) {
                    Remove-Item $tempFile -Force
                }
            }
        }
    }
    
    Write-Log "Failed to install ${AppName} - no valid installation method found" -Level "ERROR"
    return $false
}

# Add simplified Install-Application function for compatibility
function Install-Application {
    param(
        [Parameter(Mandatory=$true)]
        [string]$AppName
    )
    
    Write-LogMessage "Installing $AppName..." -Level "INFO"
    
    # Winget package ID mappings
    $wingetMappings = @{
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
    
    # Initialize temp file variable
    $tempFile = $null
    
    try {
        # Try winget first if available and not in direct-download-only mode
        if (-not $script:UseDirectDownloadOnly -and (Get-Command winget -ErrorAction SilentlyContinue)) {
            $wingetId = $wingetMappings[$AppName]
            if ($wingetId) {
                Write-LogMessage "📦 METHOD: Using winget package manager for $AppName" -Level "INFO"
                Write-LogMessage "🔍 WINGET: Searching for package ID: $wingetId" -Level "INFO"
                
                $wingetOutput = winget install --id $wingetId --silent --accept-source-agreements --accept-package-agreements 2>&1
                if ($LASTEXITCODE -eq 0 -or ($wingetOutput -match "Successfully installed" -or $wingetOutput -match "already installed")) {
                    Write-LogMessage "✅ WINGET: Successfully installed $AppName via winget package manager" -Level "SUCCESS"
                    return $true
                } else {
                    Write-LogMessage "❌ WINGET: Installation failed - $wingetOutput" -Level "WARNING"
                    Write-LogMessage "🔄 FALLBACK: Switching to direct download method for $AppName" -Level "WARNING"
                }
            } else {
                Write-LogMessage "❌ WINGET: No package ID found for $AppName" -Level "WARNING"
                Write-LogMessage "🔄 FALLBACK: Using direct download method" -Level "WARNING"
            }
        } else {
            if ($script:UseDirectDownloadOnly) {
                Write-LogMessage "📦 METHOD: Using direct download for $AppName (winget unavailable)" -Level "INFO"
            } else {
                Write-LogMessage "❌ WINGET: Package manager not available" -Level "WARNING"
                Write-LogMessage "📦 METHOD: Using direct download for $AppName" -Level "WARNING"
            }
        }
        
        # Fallback to direct download
        $downloadInfo = Get-AppDirectDownloadInfo -AppName $AppName
        if (-not $downloadInfo) {
            Write-LogMessage "❌ DIRECT: No download information available for $AppName" -Level "ERROR"
            return $false
        }
        
        Write-LogMessage "🌐 DIRECT: Starting direct download for $AppName" -Level "INFO"
        Write-LogMessage "📂 SOURCE: $($downloadInfo.Url)" -Level "INFO"
        Write-LogMessage "📄 FILE: $($downloadInfo.FileName) ($($downloadInfo.FileType.ToUpper()))" -Level "INFO"
        
        $tempFile = Join-Path $env:TEMP $downloadInfo.FileName
        
        # Download with retry logic
        $maxRetries = 3
        $retryCount = 0
        $downloadSuccess = $false
        
        while ($retryCount -lt $maxRetries -and -not $downloadSuccess) {
            try {
                Write-LogMessage "⬇️ DOWNLOAD: Attempt $($retryCount + 1)/$maxRetries - Downloading $($downloadInfo.FileName)..." -Level "INFO"
                
                # Get file size if possible for progress
                $downloadStart = Get-Date
                Invoke-WebRequest -Uri $downloadInfo.Url -OutFile $tempFile -UseBasicParsing -TimeoutSec 30
                $downloadEnd = Get-Date
                $downloadTime = ($downloadEnd - $downloadStart).TotalSeconds
                
                if (Test-Path $tempFile) {
                    $fileSize = (Get-Item $tempFile).Length
                    $fileSizeMB = [Math]::Round($fileSize / 1MB, 2)
                    Write-LogMessage "✅ DOWNLOAD: Completed - $fileSizeMB MB in $([Math]::Round($downloadTime, 1))s" -Level "SUCCESS"
                    $downloadSuccess = $true
                } else {
                    throw "File not created after download"
                }
            }
            catch {
                $retryCount++
                if ($retryCount -lt $maxRetries) {
                    Write-LogMessage "❌ DOWNLOAD: Attempt $retryCount failed - $_" -Level "WARNING"
                    Write-LogMessage "🔄 RETRY: Waiting 2 seconds before retry..." -Level "WARNING"
                    Start-Sleep -Seconds 2
                } else {
                    throw "Download failed after $maxRetries attempts: $_"
                }
            }
        }
        
        # Install the downloaded file with detailed progress
        $installStart = Get-Date
        Write-LogMessage "🔧 INSTALL: Starting installation of $AppName..." -Level "INFO"
        
        if ($downloadInfo.FileType -eq "msi") {
            Write-LogMessage "📦 INSTALLER: Using MSI installer (Windows Installer)" -Level "INFO"
            Write-LogMessage "⚙️ COMMAND: msiexec.exe /i `"$($downloadInfo.FileName)`" /quiet /norestart" -Level "INFO"
            
            $process = Start-Process msiexec.exe -ArgumentList "/i `"$tempFile`" /quiet /norestart" -Wait -PassThru
            $installEnd = Get-Date
            $installTime = ($installEnd - $installStart).TotalSeconds
            
            if ($process.ExitCode -eq 0) {
                Write-LogMessage "✅ INSTALL: $AppName installed successfully via MSI in $([Math]::Round($installTime, 1))s" -Level "SUCCESS"
                return $true
            } else {
                Write-LogMessage "❌ INSTALL: MSI installation failed for $AppName (Exit Code: $($process.ExitCode))" -Level "ERROR"
                return $false
            }
        } elseif ($downloadInfo.FileType -eq "msixbundle" -or $downloadInfo.FileType -eq "msix") {
            Write-LogMessage "📦 INSTALLER: Using MSIX package installer (Universal Windows Platform)" -Level "INFO"
            Write-LogMessage "⚙️ COMMAND: Add-AppxPackage -Path `"$($downloadInfo.FileName)`"" -Level "INFO"
            
            try {
                Add-AppxPackage -Path $tempFile -ErrorAction Stop
                $installEnd = Get-Date
                $installTime = ($installEnd - $installStart).TotalSeconds
                Write-LogMessage "✅ INSTALL: $AppName installed successfully via MSIX package in $([Math]::Round($installTime, 1))s" -Level "SUCCESS"
                return $true
            }
            catch {
                $installEnd = Get-Date
                $installTime = ($installEnd - $installStart).TotalSeconds
                Write-LogMessage "❌ INSTALL: MSIX installation failed for $AppName after $([Math]::Round($installTime, 1))s - $_" -Level "ERROR"
                return $false
            }
        } else {
            Write-LogMessage "📦 INSTALLER: Using EXE installer (Executable)" -Level "INFO"
            Write-LogMessage "⚙️ COMMAND: `"$($downloadInfo.FileName)`" $($downloadInfo.Arguments)" -Level "INFO"
            
            $process = Start-Process $tempFile -ArgumentList $downloadInfo.Arguments -Wait -PassThru
            $installEnd = Get-Date
            $installTime = ($installEnd - $installStart).TotalSeconds
            
            if ($process.ExitCode -eq 0) {
                Write-LogMessage "✅ INSTALL: $AppName installed successfully via EXE in $([Math]::Round($installTime, 1))s" -Level "SUCCESS"
                return $true
            } else {
                Write-LogMessage "❌ INSTALL: EXE installation failed for $AppName (Exit Code: $($process.ExitCode)) after $([Math]::Round($installTime, 1))s" -Level "ERROR"
                return $false
            }
        }
    }
    catch {
        Write-LogMessage "Failed to install $AppName : $_" -Level "ERROR"
        return $false
    }
    finally {
        if ($tempFile -and (Test-Path $tempFile -ErrorAction SilentlyContinue)) {
            Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
        }
    }
}

Export-ModuleMember -Function Install-Winget, Install-Python, Update-Environment, Install-Application, Get-AppDirectDownloadInfo 