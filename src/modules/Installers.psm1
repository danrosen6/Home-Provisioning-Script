# Installation modules for Windows Setup GUI

# Global variables
$script:UseDirectDownloadOnly = $false
$script:MaxRetries = 3
$script:RetryDelay = 5 # seconds
$script:InstallerTimeoutMinutes = 5 # Timeout for installer processes

# Function to run code with timeout to prevent hanging
function Invoke-WithTimeout {
    param(
        [Parameter(Mandatory=$true)]
        [scriptblock]$ScriptBlock,
        
        [Parameter(Mandatory=$false)]
        [int]$TimeoutSeconds = 30
    )
    
    try {
        $job = Start-Job -ScriptBlock $ScriptBlock
        $completed = Wait-Job $job -Timeout $TimeoutSeconds
        
        if ($completed) {
            $result = Receive-Job $job
            Remove-Job $job
            return $result
        } else {
            Remove-Job $job -Force
            throw "Operation timed out after $TimeoutSeconds seconds"
        }
    }
    catch {
        throw $_
    }
}

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

# Note: Required modules are imported by the main GUI script
# Provide fallback functions only if not available

if (-not (Get-Command Write-LogMessage -ErrorAction SilentlyContinue)) {
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
        
        $color = switch ($Level) {
            "ERROR" { "Red" }
            "WARNING" { "Yellow" }
            "SUCCESS" { "Green" }
            "DEBUG" { "Gray" }
            default { "White" }
        }
        Write-Host $logMessage -ForegroundColor $color
    }
}

if (-not (Get-Command Save-OperationState -ErrorAction SilentlyContinue)) {
    function Save-OperationState {
        param([string]$OperationType, [string]$ItemKey, [string]$Status, [hashtable]$AdditionalData)
        Write-Verbose "Operation state tracking disabled: $OperationType - $ItemKey - $Status"
    }
}

# Function to get the latest version URLs dynamically based on app configuration
function Get-LatestVersionUrl {
    param (
        [Parameter(Mandatory=$false)]
        [string]$ApplicationName,
        
        [Parameter(Mandatory=$false)]
        [hashtable]$AppConfig
    )
    
    # If AppConfig is provided, use it; otherwise try to find by ApplicationName
    if (-not $AppConfig -and $ApplicationName) {
        # Legacy support - try to map ApplicationName to AppKey for JSON lookup
        $appKeyMap = @{
            "Git" = "git"
            "Python" = "python"
            "PyCharm" = "pycharm"
            "VLC" = "vlc"
            "7-Zip" = "7zip"
            "Notepad++" = "notepad"
        }
        
        $appKey = $appKeyMap[$ApplicationName]
        if ($appKey) {
            $AppConfig = Get-AppDownloadInfo -AppKey $appKey
        }
    }
    
    if (-not $AppConfig) {
        Write-LogMessage "No configuration available for dynamic URL retrieval" -Level "WARNING"
        return $null
    }
    
    $urlType = $AppConfig.UrlType
    $fallbackUrl = $AppConfig.FallbackUrl
    
    try {
        switch ($urlType) {
            "github-asset" {
                $apiUrl = $AppConfig.Url
                $releaseInfo = Invoke-RestMethod -Uri $apiUrl -TimeoutSec 10 -ErrorAction Stop
                
                # Find matching asset based on pattern
                $assetPattern = $AppConfig.AssetPattern
                if ($assetPattern) {
                    $asset = $releaseInfo.assets | Where-Object { $_.name -like $assetPattern } | Select-Object -First 1
                    if ($asset) {
                        Write-LogMessage "Found latest GitHub asset: $($asset.name)" -Level "INFO"
                        return $asset.browser_download_url
                    }
                }
            }
            "dynamic-python" {
                $webRequest = Invoke-WebRequest -Uri $AppConfig.Url -UseBasicParsing -TimeoutSec 15 -ErrorAction Stop
                
                if ($webRequest.Content -match "Latest Python 3 Release - Python (3\.\d+\.\d+)") {
                    $latestVersion = $matches[1]
                    $latestUrl = "https://www.python.org/ftp/python/$latestVersion/python-$latestVersion-amd64.exe"
                    Write-LogMessage "Found latest Python version: $latestVersion" -Level "INFO"
                    return $latestUrl
                }
            }
            "jetbrains-api" {
                $webRequest = Invoke-WebRequest -Uri $AppConfig.Url -UseBasicParsing -TimeoutSec 15 -ErrorAction Stop
                
                $releaseInfo = $webRequest.Content | ConvertFrom-Json
                $downloadUrl = $releaseInfo.PCC[0].downloads.windows.link
                
                if ($downloadUrl) {
                    Write-LogMessage "Found latest JetBrains download URL" -Level "INFO"
                    return $downloadUrl
                }
            }
            "dynamic-vlc" {
                $webRequest = Invoke-WebRequest -Uri $AppConfig.Url -UseBasicParsing -TimeoutSec 15 -ErrorAction Stop
                
                if ($webRequest.Content -match "vlc-(\d+\.\d+\.\d+)-win64.exe") {
                    $latestVersion = $matches[1]
                    $latestUrl = "https://get.videolan.org/vlc/$latestVersion/win64/vlc-$latestVersion-win64.exe"
                    Write-LogMessage "Found latest VLC version: $latestVersion" -Level "INFO"
                    return $latestUrl
                }
            }
            "dynamic-7zip" {
                $webRequest = Invoke-WebRequest -Uri $AppConfig.Url -UseBasicParsing -TimeoutSec 15 -ErrorAction Stop
                
                if ($webRequest.Content -match "Download 7-Zip ([\d\.]+) \((?:\d{4}-\d{2}-\d{2})\) for Windows") {
                    $latestVersion = $matches[1]
                    $formattedVersion = $latestVersion -replace "\.", ""
                    $latestUrl = "https://www.7-zip.org/a/7z$formattedVersion-x64.exe"
                    Write-LogMessage "Found latest 7-Zip version: $latestVersion" -Level "INFO"
                    return $latestUrl
                }
            }
            default {
                Write-LogMessage "Unknown URL type: $urlType, using static URL" -Level "DEBUG"
                return $AppConfig.Url
            }
        }
    } catch {
        Write-LogMessage "Error getting latest version URL: $_" -Level "WARNING"
    }
    
    # Use fallback URL if dynamic retrieval failed
    if ($fallbackUrl) {
        Write-LogMessage "Using fallback URL" -Level "INFO"
        return $fallbackUrl
    }
    
    # Final fallback to static URL from config
    return $AppConfig.Url
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

# Legacy function - provides basic download info as fallback when JSON config fails
function Get-AppDirectDownloadInfo {
    param(
        [Parameter(Mandatory=$true)]
        [string]$AppName
    )
    
    Write-LogMessage "Using legacy fallback download info for $AppName" -Level "DEBUG"
    
    # Basic fallback download information for common apps
    $fallbackDownloads = @{
        "Google Chrome" = @{
            Url = "https://dl.google.com/dl/chrome/install/googlechromestandaloneenterprise64.msi"
            Extension = ".msi"
            Arguments = @("/quiet", "/norestart")
        }
        "Mozilla Firefox" = @{
            Url = "https://download.mozilla.org/?product=firefox-latest-ssl&os=win64&lang=en-US"
            Extension = ".exe"
            Arguments = "-ms"
        }
        "Visual Studio Code" = @{
            Url = "https://code.visualstudio.com/sha/download?build=stable&os=win32-x64-user"
            Extension = ".exe"
            Arguments = "/VERYSILENT /NORESTART /MERGETASKS=!runcode"
        }
        "Git" = @{
            Url = "https://github.com/git-for-windows/git/releases/download/v2.49.0.windows.1/Git-2.49.0-64-bit.exe"
            Extension = ".exe"
            Arguments = "/VERYSILENT /NORESTART /NOCANCEL /SP- /CLOSEAPPLICATIONS /RESTARTAPPLICATIONS"
        }
        "Python" = @{
            Url = "https://www.python.org/ftp/python/3.13.4/python-3.13.4-amd64.exe"
            Extension = ".exe"
            Arguments = "/quiet InstallAllUsers=1 PrependPath=1 Include_test=0"
        }
        "Microsoft PowerToys" = @{
            Url = "https://github.com/microsoft/PowerToys/releases/latest/download/PowerToysSetup-x64.exe"
            Extension = ".exe"
            Arguments = "-silent"
        }
    }
    
    if ($fallbackDownloads.ContainsKey($AppName)) {
        return $fallbackDownloads[$AppName]
    }
    
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
    
    Write-LogMessage "Starting enhanced winget installation..." -Level "INFO"
    
    # Check for cancellation
    if ($CancellationToken.IsCancellationRequested) {
        Write-LogMessage "Winget installation cancelled" -Level "WARNING"
        return $false
    }
    
    # Use the enhanced winget initialization
    try {
        $result = Initialize-WingetEnvironment -AllowManualInstall
        
        if ($result.Success) {
            if ($result.AlreadyAvailable) {
                Write-LogMessage "Winget was already available: $($result.Version)" -Level "INFO"
            } elseif ($result.Registered) {
                Write-LogMessage "Winget successfully registered via $($result.Method): $($result.Version)" -Level "SUCCESS"
            } elseif ($result.Installed) {
                Write-LogMessage "Winget successfully installed via $($result.Method): $($result.Version)" -Level "SUCCESS"
            }
            return $true
        } else {
            $reason = $result.Reason
            Write-LogMessage "Winget installation failed: $reason" -Level "ERROR"
            
            if ($result.Details -and $result.Details.Error) {
                Write-LogMessage "Error details: $($result.Details.Error)" -Level "ERROR"
            }
            
            # Provide helpful information based on failure reason
            switch ($reason) {
                "IncompatibleWindows" {
                    $compatibility = $result.Details
                    Write-LogMessage "Windows $($compatibility.VersionName) (Build $($compatibility.BuildNumber)) is not compatible with winget" -Level "ERROR"
                    Write-LogMessage "Minimum requirement: $($compatibility.MinimumVersion) (Build $($compatibility.MinimumBuild))" -Level "INFO"
                }
                "InstallationSucceededButNotAvailable" {
                    Write-LogMessage "Installation completed but winget command not available - may require system restart" -Level "WARNING"
                }
                "InstallationFailed" {
                    Write-LogMessage "All installation methods failed. Manual installation may be required." -Level "ERROR"
                }
            }
            
            return $false
        }
    } catch {
        Write-LogMessage "Error during winget installation: $_" -Level "ERROR"
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
        [System.Threading.CancellationToken]$CancellationToken = [System.Threading.CancellationToken]::None,
        
        [Parameter(Mandatory=$false)]
        [int]$TimeoutMinutes = 10
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
        
        # Use the legacy name-based mapping only if no AppKey was provided and we couldn't get from JSON
        if (-not $WingetId) {
            Write-LogMessage "No WingetId found in JSON configuration for $AppName" -Level "DEBUG"
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
    
    # Check global and script-level UseDirectDownloadOnly flags
    if ((Get-Variable -Name "UseDirectDownloadOnly" -Scope Global -ErrorAction SilentlyContinue) -and $Global:UseDirectDownloadOnly) {
        $script:UseDirectDownloadOnly = $true
    }
    
    # Check if winget should be used (determined by main GUI)
    $wingetAvailable = $false
    
    if (-not $script:UseDirectDownloadOnly) {
        # Simple check for winget command availability
        if (Get-Command winget -ErrorAction SilentlyContinue) {
            $wingetAvailable = $true
            Write-LogMessage "Winget is available for $AppName installation" -Level "DEBUG"
        } else {
            Write-LogMessage "Winget not available for $AppName, using direct download" -Level "DEBUG"
        }
    } else {
        Write-LogMessage "Direct download mode enabled - skipping winget for $AppName" -Level "DEBUG"
    }
    
    if ($wingetAvailable) {
        # WingetId was already determined earlier for installation verification
        Write-LogMessage "Winget is available, checking WingetId for $AppName..." -Level "DEBUG"
        
        if ($WingetId) {
            Write-LogMessage "Installing $AppName via winget (ID: $WingetId)..." -Level "INFO"
            try {
                Write-LogMessage "Executing: winget install --id $WingetId --accept-source-agreements --accept-package-agreements --silent" -Level "DEBUG"
                
                # Use timeout protection for winget install to prevent GUI freezing
                $wingetResult = Invoke-WithTimeout -ScriptBlock {
                    $output = winget install --id $WingetId --accept-source-agreements --accept-package-agreements --silent 2>&1
                    return @{
                        Output = $output
                        ExitCode = $LASTEXITCODE
                    }
                } -TimeoutSeconds 300  # 5 minute timeout
                
                $wingetExitCode = $wingetResult.ExitCode
                $wingetOutput = $wingetResult.Output
                
                if ($wingetOutput -match "Successfully installed" -or $wingetOutput -match "No applicable update found") {
                    Write-LogMessage "$AppName installed successfully via winget!" -Level "SUCCESS"
                    # Get build number for logging
                    $buildNumber = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -ErrorAction SilentlyContinue).CurrentBuild
                    
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
                    # Get build number for error logging
                    $buildNumber = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -ErrorAction SilentlyContinue).CurrentBuild
                    
                    Write-LogMessage "Winget installation failed for $AppName" -Level "WARNING"
                    Write-LogMessage "Winget output: $wingetOutput" -Level "DEBUG"
                    Write-LogMessage "Windows build: $buildNumber (winget requires 16299+)" -Level "DEBUG"
                    # Continue to direct download method
                }
            }
            catch {
                Write-LogMessage "Error using winget: $_" -Level "WARNING"
                # Continue to direct download method
            }
        } else {
            Write-LogMessage "No WingetId available for $AppName, proceeding to direct download" -Level "DEBUG"
        }
    } else {
        Write-LogMessage "Winget not available for $AppName installation, using direct download method" -Level "DEBUG"
    }
    
    # If no direct download info was provided, try to get it
    if ($null -eq $DirectDownload) {
        Write-LogMessage "No DirectDownload provided, attempting to retrieve for $AppName (AppKey: $AppKey)" -Level "DEBUG"
        
        # Try to get from JSON configuration first if AppKey is provided
        if ($AppKey) {
            Write-LogMessage "Looking up JSON configuration for AppKey: $AppKey" -Level "DEBUG"
            $appConfig = Get-AppDownloadInfo -AppKey $AppKey
            if ($appConfig) {
                Write-LogMessage "JSON config found for $AppKey - URL: $($appConfig.Url)" -Level "DEBUG"
            } else {
                Write-LogMessage "JSON config NOT found for $AppKey" -Level "WARNING"
            }
            if ($appConfig -and $appConfig.Url) {
                $DirectDownload = @{
                    Url = $appConfig.Url
                    Extension = $appConfig.Extension
                    Arguments = $appConfig.Arguments
                    VerificationPaths = $appConfig.VerificationPaths
                }
                Write-LogMessage "Using download info from JSON config for $AppName (URL: $($appConfig.Url))" -Level "INFO"
                
                # Handle dynamic URL retrieval based on UrlType
                if ($appConfig.UrlType) {
                    $latestUrl = Get-LatestVersionUrl -AppConfig $appConfig
                    if ($latestUrl) {
                        Write-LogMessage "Using dynamically retrieved latest version URL for $AppName" -Level "INFO"
                        $DirectDownload.Url = $latestUrl
                    }
                }
            }
        }
        
        # Fallback to legacy hardcoded function if no JSON config found
        if ($null -eq $DirectDownload) {
            Write-LogMessage "No JSON configuration found for $AppName, trying legacy method" -Level "WARNING"
            
            # Get the standard download info from legacy function
            $DirectDownload = Get-AppDirectDownloadInfo -AppName $AppName
            
            # Try dynamic URL retrieval using legacy ApplicationName mapping
            if ($DirectDownload) {
                $latestUrl = Get-LatestVersionUrl -ApplicationName $AppName
                if ($latestUrl) {
                    Write-LogMessage "Using dynamically retrieved latest version URL for $AppName" -Level "INFO"
                    $DirectDownload.Url = $latestUrl
                }
            }
        }
    }
    
    if ($null -eq $DirectDownload) {
        Write-LogMessage "No download information available for $AppName (AppKey: $AppKey)" -Level "ERROR"
        Write-LogMessage "This means both winget and direct download methods failed to provide installation info" -Level "ERROR"
        Save-OperationState -OperationType "InstallApp" -ItemKey $AppName -Status "Failed" -AdditionalData @{
            Error = "No download information available"
            AppKey = $AppKey
            WingetAvailable = $wingetAvailable
            WingetId = $WingetId
            Time = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        }
        return $false
    } else {
        Write-LogMessage "DirectDownload info retrieved for $AppName - URL: $($DirectDownload.Url), Extension: $($DirectDownload.Extension)" -Level "DEBUG"
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