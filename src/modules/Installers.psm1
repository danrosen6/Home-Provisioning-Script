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
    
    # Define download information for common applications
    $downloadInfo = @{
        "Python" = @{
            Url = "https://www.python.org/ftp/python/3.12.0/python-3.12.0-amd64.exe"
            FileName = "python-3.12.0-amd64.exe"
            FileType = "exe"
            Arguments = "/quiet InstallAllUsers=1 PrependPath=1"
            Checksum = "SHA256:1234567890abcdef" # Replace with actual checksum
        }
        "Git" = @{
            Url = "https://github.com/git-for-windows/git/releases/download/v2.42.0.windows.2/Git-2.42.0.2-64-bit.exe"
            FileName = "Git-2.42.0.2-64-bit.exe"
            FileType = "exe"
            Arguments = "/VERYSILENT /NORESTART /NOCANCEL /SP- /CLOSEAPPLICATIONS /RESTARTAPPLICATIONS /COMPONENTS=`"icons,ext\reg\shellhere,assoc,assoc_sh`""
            Checksum = "SHA256:1234567890abcdef" # Replace with actual checksum
        }
        "VSCode" = @{
            Url = "https://code.visualstudio.com/sha/download?build=stable&os=win32-x64"
            FileName = "VSCodeSetup-x64.exe"
            FileType = "exe"
            Arguments = "/VERYSILENT /MERGETASKS=!runcode"
        }
        "Chrome" = @{
            Url = "https://dl.google.com/chrome/install/latest/chrome_installer.exe"
            FileName = "chrome_installer.exe"
            FileType = "exe"
            Arguments = "/silent /install"
        }
        "Firefox" = @{
            Url = "https://download.mozilla.org/?product=firefox-latest&os=win64&lang=en-US"
            FileName = "FirefoxSetup.exe"
            FileType = "exe"
            Arguments = "/S"
        }
        "Brave" = @{
            Url = "https://referrals.brave.com/latest/BraveBrowserSetup.exe"
            FileName = "BraveBrowserSetup.exe"
            FileType = "exe"
            Arguments = "/silent /install"
        }
        "7zip" = @{
            Url = "https://www.7-zip.org/a/7z2301-x64.msi"
            FileName = "7z2301-x64.msi"
            FileType = "msi"
            Arguments = "/quiet /norestart"
        }
        "NotepadPlusPlus" = @{
            Url = "https://github.com/notepad-plus-plus/notepad-plus-plus/releases/download/v8.6.2/npp.8.6.2.Installer.x64.exe"
            FileName = "npp.8.6.2.Installer.x64.exe"
            FileType = "exe"
            Arguments = "/S"
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
    
    # Get download info
    $downloadInfo = Get-AppDirectDownloadInfo -AppName $AppName
    if (-not $downloadInfo) {
        Write-LogMessage "No download info found for $AppName" -Level "ERROR"
        return $false
    }
    
    try {
        # Try winget first if available
        if (Get-Command winget -ErrorAction SilentlyContinue) {
            $wingetOutput = winget install $AppName --silent --accept-source-agreements --accept-package-agreements 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-LogMessage "Successfully installed $AppName via winget" -Level "SUCCESS"
                return $true
            }
        }
        
        # Fallback to direct download
        $tempFile = Join-Path $env:TEMP $downloadInfo.FileName
        Invoke-WebRequest -Uri $downloadInfo.Url -OutFile $tempFile
        
        if ($downloadInfo.FileType -eq "msi") {
            $process = Start-Process msiexec.exe -ArgumentList "/i `"$tempFile`" /quiet /norestart" -Wait -PassThru
        } else {
            $process = Start-Process $tempFile -ArgumentList $downloadInfo.Arguments -Wait -PassThru
        }
        
        if ($process.ExitCode -eq 0) {
            Write-LogMessage "Successfully installed $AppName" -Level "SUCCESS"
            return $true
        } else {
            Write-LogMessage "Installation failed for $AppName with exit code $($process.ExitCode)" -Level "ERROR"
            return $false
        }
    }
    catch {
        Write-LogMessage "Failed to install $AppName : $_" -Level "ERROR"
        return $false
    }
    finally {
        if (Test-Path $tempFile -ErrorAction SilentlyContinue) {
            Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
        }
    }
}

Export-ModuleMember -Function Install-Winget, Install-Python, Update-Environment, Install-Application, Get-AppDirectDownloadInfo 