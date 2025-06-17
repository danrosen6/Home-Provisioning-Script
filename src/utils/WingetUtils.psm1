# Enhanced Winget utilities for Windows Setup GUI
# Comprehensive winget installation and management system
# Handles all winget-related operations including dependency management

# Import logging if available
if (-not (Get-Command Write-LogMessage -ErrorAction SilentlyContinue)) {
    function Write-LogMessage {
        param([string]$Message, [string]$Level = "INFO")
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $color = switch ($Level) {
            "ERROR" { "Red" }
            "WARNING" { "Yellow" }
            "SUCCESS" { "Green" }
            "DEBUG" { "Gray" }
            default { "White" }
        }
        Write-Host "[$timestamp] [$Level] $Message" -ForegroundColor $color
    }
}

function Test-WingetCompatibility {
    [CmdletBinding()]
    param()
    
    try {
        $osInfo = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
        if (-not $osInfo) {
            Write-LogMessage "Could not detect Windows version" -Level "WARNING"
            return @{ Compatible = $false; Reason = "Version detection failed" }
        }
        
        $buildNumber = [int]$osInfo.BuildNumber
        $isWindows11 = $buildNumber -ge 22000
        $isWindows10 = $buildNumber -ge 10240 -and $buildNumber -lt 22000
        
        Write-LogMessage "Detected Windows build: $buildNumber" -Level "INFO"
        
        # Windows 11 - full compatibility
        if ($isWindows11) {
            return @{
                Compatible = $true
                Method = "PreInstalled"
                Version = "Windows 11"
                BuildNumber = $buildNumber
                Reason = "Windows 11 includes winget by default"
            }
        }
        
        # Windows 10 version checks
        if ($isWindows10) {
            # Windows 10 22H2 (19045) and later - best compatibility
            if ($buildNumber -ge 19045) {
                return @{
                    Compatible = $true
                    Method = "PreInstalled"
                    Version = "Windows 10 22H2+"
                    BuildNumber = $buildNumber
                    Reason = "Modern Windows 10 with winget support"
                }
            }
            # Windows 10 2004 (19041) to 21H2 (19044) - good compatibility
            elseif ($buildNumber -ge 19041) {
                return @{
                    Compatible = $true
                    Method = "StoreOrDirect"
                    Version = "Windows 10 2004-21H2"
                    BuildNumber = $buildNumber
                    Reason = "Compatible but may need manual installation"
                }
            }
            # Windows 10 1909 (18363) to 1903 (18362) - requires manual installation
            elseif ($buildNumber -ge 18362) {
                return @{
                    Compatible = $true
                    Method = "ManualOnly"
                    Version = "Windows 10 1903-1909"
                    BuildNumber = $buildNumber
                    Reason = "Requires manual installation with dependencies"
                }
            }
            # Windows 10 1809 (17763) and earlier - limited compatibility
            elseif ($buildNumber -ge 17763) {
                return @{
                    Compatible = $true
                    Method = "ManualWithDeps"
                    Version = "Windows 10 1809"
                    BuildNumber = $buildNumber
                    Reason = "Limited compatibility, manual installation required"
                }
            }
            # Windows 10 versions before 1809 - not compatible
            else {
                return @{
                    Compatible = $false
                    Version = "Windows 10 Pre-1809"
                    BuildNumber = $buildNumber
                    Reason = "Windows 10 build $buildNumber is too old for winget"
                }
            }
        }
        
        # Not Windows 10/11
        return @{
            Compatible = $false
            Version = "Unknown/Unsupported"
            BuildNumber = $buildNumber
            Reason = "Unsupported Windows version"
        }
    }
    catch {
        Write-LogMessage "Error checking Windows compatibility: $_" -Level "ERROR"
        return @{ Compatible = $false; Reason = "Compatibility check failed" }
    }
}

function Get-WindowsVersionName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$BuildNumber
    )
    
    $buildInt = [int]$BuildNumber
    
    if ($buildInt -ge 22000) {
        return "Windows 11"
    } elseif ($buildInt -ge 19041) {
        return "Windows 10 2004+"
    } elseif ($buildInt -ge 18363) {
        return "Windows 10 1909"
    } elseif ($buildInt -ge 18362) {
        return "Windows 10 1903"
    } elseif ($buildInt -ge 17763) {
        return "Windows 10 1809"
    } elseif ($buildInt -ge 17134) {
        return "Windows 10 1803"
    } elseif ($buildInt -ge 16299) {
        return "Windows 10 1709"
    } else {
        return "Windows 10 (Pre-1709)"
    }
}

function Install-WingetDependencies {
    [CmdletBinding()]
    param(
        [string]$DownloadDir
    )
    
    Write-LogMessage "Installing winget dependencies..." -Level "INFO"
    
    try {
        # Create dependencies directory
        $depsDir = Join-Path $DownloadDir "dependencies"
        if (-not (Test-Path $depsDir)) {
            New-Item -ItemType Directory -Path $depsDir -Force | Out-Null
        }
        
        # Download and install VCLibs (required for most winget operations)
        $vclibsUrl = "https://aka.ms/Microsoft.VCLibs.x64.14.00.Desktop.appx"
        $vclibsPath = Join-Path $depsDir "VCLibs.appx"
        
        Write-LogMessage "Downloading VCLibs dependency..." -Level "INFO"
        try {
            $webClient = New-Object System.Net.WebClient
            $webClient.DownloadFile($vclibsUrl, $vclibsPath)
            
            Write-LogMessage "Installing VCLibs dependency..." -Level "INFO"
            Add-AppxPackage -Path $vclibsPath -ErrorAction Stop
            Write-LogMessage "VCLibs installed successfully" -Level "SUCCESS"
        }
        catch {
            Write-LogMessage "VCLibs installation failed (may already be installed): $_" -Level "WARNING"
        }
        
        # Download and install UI Xaml (newer dependency for latest winget versions)
        try {
            $uiXamlUrl = "https://www.nuget.org/api/v2/package/Microsoft.UI.Xaml/2.8.6"
            $uiXamlPath = Join-Path $depsDir "UIXaml.zip"
            
            Write-LogMessage "Downloading UI Xaml framework..." -Level "INFO"
            $webClient = New-Object System.Net.WebClient
            $webClient.DownloadFile($uiXamlUrl, $uiXamlPath)
            
            # Extract and find the appropriate appx file
            $extractDir = Join-Path $depsDir "UIXaml"
            if (Test-Path $extractDir) {
                Remove-Item $extractDir -Recurse -Force
            }
            Expand-Archive -Path $uiXamlPath -DestinationPath $extractDir -Force
            
            # Find x64 appx file
            $appxFile = Get-ChildItem -Path $extractDir -Recurse -Filter "*.appx" | Where-Object { $_.Name -like "*x64*" } | Select-Object -First 1
            
            if ($appxFile) {
                Write-LogMessage "Installing UI Xaml framework..." -Level "INFO"
                Add-AppxPackage -Path $appxFile.FullName -ErrorAction Stop
                Write-LogMessage "UI Xaml installed successfully" -Level "SUCCESS"
            }
        }
        catch {
            Write-LogMessage "UI Xaml installation failed (may not be required): $_" -Level "WARNING"
        }
        
        # Clean up downloads
        Remove-Item $depsDir -Recurse -Force -ErrorAction SilentlyContinue
        
        return $true
    }
    catch {
        Write-LogMessage "Error installing winget dependencies: $_" -Level "ERROR"
        return $false
    }
}

function Resolve-WingetInstallationError {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [System.Management.Automation.ErrorRecord]$ErrorRecord,
        [string]$DownloadDir
    )
    
    $errorCode = if ($ErrorRecord.Exception.HResult) { "0x{0:X8}" -f $ErrorRecord.Exception.HResult } else { "Unknown" }
    $errorMessage = $ErrorRecord.Exception.Message
    
    Write-LogMessage "Diagnosing winget installation error (Code: $errorCode)" -Level "INFO"
    
    switch ($ErrorRecord.Exception.HResult) {
        0x80073CF3 {
            Write-LogMessage "Dependency validation error - missing framework packages" -Level "WARNING"
            Write-LogMessage "Attempting to install missing dependencies..." -Level "INFO"
            
            # Install dependencies and retry
            $result = Install-WingetDependencies -DownloadDir $DownloadDir
            if ($result) {
                Write-LogMessage "Dependencies installed successfully, retry installation" -Level "SUCCESS"
                return @{ CanRetry = $true; Action = "Retry with dependencies" }
            } else {
                Write-LogMessage "Failed to install dependencies" -Level "ERROR"
                return @{ CanRetry = $false; Action = "Manual dependency installation required" }
            }
        }
        
        0x80073CFE {
            Write-LogMessage "Package registration error - app installer conflict" -Level "WARNING"
            Write-LogMessage "Attempting to re-register App Installer..." -Level "INFO"
            
            try {
                Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe
                return @{ CanRetry = $true; Action = "Re-registered App Installer" }
            }
            catch {
                return @{ CanRetry = $false; Action = "Manual App Installer re-registration required" }
            }
        }
        
        0x80073D01 {
            Write-LogMessage "Installation space error - insufficient disk space" -Level "ERROR"
            return @{ CanRetry = $false; Action = "Free up disk space and retry manually" }
        }
        
        0x80073CF0 {
            Write-LogMessage "Package signature error - certificate trust issue" -Level "WARNING"
            Write-LogMessage "This may require manual certificate installation" -Level "INFO"
            return @{ CanRetry = $false; Action = "Manual certificate trust configuration required" }
        }
        
        default {
            Write-LogMessage "Unknown installation error: $errorMessage" -Level "ERROR"
            Write-LogMessage "Error code: $errorCode" -Level "DEBUG"
            
            # Check for common error patterns in message
            if ($errorMessage -match "access.*denied|permission") {
                return @{ CanRetry = $false; Action = "Run as administrator or check permissions" }
            }
            elseif ($errorMessage -match "network|internet|download") {
                return @{ CanRetry = $true; Action = "Check internet connection and retry" }
            }
            elseif ($errorMessage -match "policy|group.*policy") {
                return @{ CanRetry = $false; Action = "Check Group Policy restrictions for app installation" }
            }
            else {
                return @{ CanRetry = $false; Action = "Manual troubleshooting required" }
            }
        }
    }
}

function Test-PowerShellExecutionPolicy {
    [CmdletBinding()]
    param(
        [switch]$AutoFix
    )
    
    try {
        $currentPolicy = Get-ExecutionPolicy -Scope CurrentUser
        $systemPolicy = Get-ExecutionPolicy -Scope LocalMachine
        
        Write-LogMessage "PowerShell Execution Policy - CurrentUser: $currentPolicy, LocalMachine: $systemPolicy" -Level "INFO"
        
        # Check if policy allows script execution
        $restrictivePolicies = @("Restricted", "AllSigned")
        $needsFix = $currentPolicy -in $restrictivePolicies -and $systemPolicy -in $restrictivePolicies
        
        if ($needsFix) {
            Write-LogMessage "Restrictive execution policy detected" -Level "WARNING"
            
            if ($AutoFix) {
                Write-LogMessage "Attempting to set execution policy to RemoteSigned for current user..." -Level "INFO"
                try {
                    Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
                    Write-LogMessage "Execution policy updated successfully" -Level "SUCCESS"
                    return $true
                }
                catch {
                    Write-LogMessage "Failed to update execution policy: $_" -Level "ERROR"
                    return $false
                }
            } else {
                Write-LogMessage "Run: Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser" -Level "INFO"
                return $false
            }
        }
        
        return $true
    }
    catch {
        Write-LogMessage "Error checking execution policy: $_" -Level "ERROR"
        return $false
    }
}

function Test-WingetInstallation {
    [CmdletBinding()]
    param()
    
    try {
        # Check if winget command is available
        $wingetCmd = Get-Command winget -ErrorAction SilentlyContinue
        if (-not $wingetCmd) {
            return @{
                Installed = $false
                Available = $false
                Version = $null
                NeedsRegistration = $false
            }
        }
        
        # Try to get version
        $version = winget --version 2>$null
        if ($version) {
            return @{
                Installed = $true
                Available = $true
                Version = $version.Trim()
                NeedsRegistration = $false
            }
        }
        
        # Command exists but version failed - might need registration
        return @{
            Installed = $true
            Available = $false
            Version = $null
            NeedsRegistration = $true
        }
    }
    catch {
        return @{
            Installed = $false
            Available = $false
            Version = $null
            NeedsRegistration = $false
            Error = $_.Exception.Message
        }
    }
}

function Initialize-WingetEnvironment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [switch]$Force,
        [switch]$AllowManualInstall,
        [switch]$ForceGitHubMethod,
        [System.Threading.CancellationToken]$CancellationToken = [System.Threading.CancellationToken]::None
    )
    
    try {
        Write-LogMessage "Starting comprehensive winget installation process..." -Level "INFO"
        
        # Check for cancellation
        if ($CancellationToken.IsCancellationRequested) {
            Write-LogMessage "Winget installation cancelled" -Level "WARNING"
            return @{ Success = $false; Reason = "Cancelled" }
        }
        
        # Check Windows version compatibility
        $compatibility = Test-WingetCompatibility
        Write-LogMessage "Windows compatibility: $($compatibility.Version) - $($compatibility.Reason)" -Level "INFO"
        
        if (-not $compatibility.Compatible) {
            Write-LogMessage "Windows version not compatible with winget: $($compatibility.Reason)" -Level "ERROR"
            return @{
                Success = $false
                Reason = "IncompatibleWindows"
                Details = $compatibility
            }
        }
        
        # Create download directory
        $scriptPath = Split-Path -Parent $PSScriptRoot
        $downloadDir = Join-Path $scriptPath "downloads"
        if (-not (Test-Path $downloadDir)) {
            New-Item -ItemType Directory -Path $downloadDir -Force | Out-Null
            Write-LogMessage "Created download directory at: $downloadDir" -Level "INFO"
        }
        
        # Try different installation methods based on Windows version and user preference
        $installationMethod = if ($ForceGitHubMethod) { "GitHub" } else { $compatibility.Method }
        
        Write-LogMessage "Using installation method: $installationMethod" -Level "INFO"
        
        # Method 1: Check if already installed but not registered
        if (-not $ForceGitHubMethod) {
            $appInstaller = Get-AppxPackage -Name "Microsoft.DesktopAppInstaller" -ErrorAction SilentlyContinue
            if ($appInstaller) {
                Write-LogMessage "App Installer found: $($appInstaller.Version)" -Level "INFO"
                Write-LogMessage "Attempting to register winget..." -Level "INFO"
                
                try {
                    Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe
                    Start-Sleep -Seconds 10
                    
                    # Test if winget is now available
                    for ($attempt = 1; $attempt -le 5; $attempt++) {
                        if (Get-Command winget -ErrorAction SilentlyContinue) {
                            try {
                                $version = winget --version 2>$null
                                if ($version -and $version.Trim() -ne "") {
                                    Write-LogMessage "Winget successfully registered: $version" -Level "SUCCESS"
                                    return @{
                                        Success = $true
                                        Method = "Registration"
                                        Version = $version
                                    }
                                }
                            }
                            catch { }
                        }
                        
                        if ($attempt -lt 5) {
                            Start-Sleep -Seconds 3
                        }
                    }
                    
                    Write-LogMessage "Winget registration completed but command not available" -Level "WARNING"
                }
                catch {
                    Write-LogMessage "Failed to register winget: $_" -Level "WARNING"
                }
            }
        }
        
        # Method 2: GitHub direct installation (enhanced method) - prioritized for reliability
        Write-LogMessage "Attempting GitHub direct installation..." -Level "INFO"
        
        # Install dependencies if required for older Windows versions
        if ($installationMethod -in @("ManualOnly", "ManualWithDeps")) {
            Write-LogMessage "Installing winget dependencies for $($compatibility.Version)..." -Level "INFO"
            $depResult = Install-WingetDependencies -DownloadDir $downloadDir
            if (-not $depResult) {
                Write-LogMessage "Failed to install dependencies, continuing anyway..." -Level "WARNING"
            }
        }
        
        # Check execution policy first
        $policyOk = Test-PowerShellExecutionPolicy -AutoFix
        if (-not $policyOk) {
            Write-LogMessage "PowerShell execution policy may prevent winget installation" -Level "WARNING"
        }
        
        try {
            # Create winget-specific directory
            $wingetDir = Join-Path $downloadDir "winget"
            if (-not (Test-Path $wingetDir)) {
                New-Item -ItemType Directory -Path $wingetDir -Force | Out-Null
                Write-LogMessage "Created winget directory at: $wingetDir" -Level "INFO"
            }
            
            # Use GitHub API to get the latest winget release
            Write-LogMessage "Fetching latest winget release from GitHub..." -Level "INFO"
            $progressPreference = 'SilentlyContinue'  # Suppress progress bars
            
            try {
                $releaseUrl = "https://api.github.com/repos/microsoft/winget-cli/releases/latest"
                $release = Invoke-RestMethod -Uri $releaseUrl -TimeoutSec 30 -ErrorAction Stop
                $msixBundle = $release.assets | Where-Object { $_.browser_download_url.EndsWith(".msixbundle") } | Select-Object -First 1
                
                if ($null -eq $msixBundle) {
                    throw "Could not find winget MSIX bundle in latest release"
                }
                
                $downloadUrl = $msixBundle.browser_download_url
                $fileName = $msixBundle.name
                Write-LogMessage "Found winget release: $fileName" -Level "SUCCESS"
            }
            catch {
                Write-LogMessage "GitHub API failed, using fallback URL: $_" -Level "WARNING"
                # Fallback to known working URL
                $downloadUrl = "https://github.com/microsoft/winget-cli/releases/latest/download/Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle"
                $fileName = "Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle"
            }
            
            $downloadPath = Join-Path $wingetDir $fileName
            Write-LogMessage "Downloading winget from: $downloadUrl" -Level "INFO"
            
            # Download with enhanced error handling
            try {
                $webClient = New-Object System.Net.WebClient
                $webClient.DownloadFile($downloadUrl, $downloadPath)
                
                # Verify download
                if (-not (Test-Path $downloadPath)) {
                    throw "Download failed - file not found at expected location"
                }
                
                $fileSize = (Get-Item $downloadPath).Length
                if ($fileSize -lt 1MB) {
                    throw "Download appears incomplete (file size: $([math]::Round($fileSize/1KB, 2)) KB)"
                }
                
                Write-LogMessage "Download completed successfully ($([math]::Round($fileSize/1MB, 2)) MB)" -Level "SUCCESS"
            }
            catch {
                Write-LogMessage "Download failed: $_" -Level "ERROR"
                return @{ Success = $false; Reason = "DownloadFailed"; Error = $_.Exception.Message }
            }
            
            # Install the MSIX bundle with enhanced error handling
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
                    $errorAnalysis = Resolve-WingetInstallationError -ErrorRecord $_ -DownloadDir $downloadDir
                    Write-LogMessage "Installation attempt $attempt failed: $($errorAnalysis.Action)" -Level "WARNING"
                    
                    if ($errorAnalysis.CanRetry -and $attempt -lt 3) {
                        Start-Sleep -Seconds 5
                    } elseif (-not $errorAnalysis.CanRetry) {
                        Write-LogMessage "Cannot retry installation: $($errorAnalysis.Action)" -Level "ERROR"
                        break
                    }
                }
            }
            
            # Clean up download
            Remove-Item $downloadPath -Force -ErrorAction SilentlyContinue
            Write-LogMessage "Cleaned up downloaded package" -Level "INFO"
            
            if (-not $installSuccess) {
                Write-LogMessage "Failed to install winget after all attempts" -Level "ERROR"
                return @{ Success = $false; Reason = "InstallationFailed" }
            }
            
            # Extended verification with multiple attempts
            Write-LogMessage "Verifying winget installation..." -Level "INFO"
            
            for ($attempt = 1; $attempt -le 10; $attempt++) {
                Start-Sleep -Seconds 3
                
                if (Get-Command winget -ErrorAction SilentlyContinue) {
                    try {
                        $version = winget --version 2>$null
                        if ($version -and $version.Trim() -ne "") {
                            Write-LogMessage "Winget installed successfully! Version: $version" -Level "SUCCESS"
                            return @{
                                Success = $true
                                Method = "GitHubDirect"
                                Version = $version
                                Installed = $true
                            }
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
            return @{
                Success = $true
                Method = "GitHubDirect"
                Installed = $true
                Reason = "InstallationSucceededButNotImmediatelyAvailable"
                Message = "Winget installation completed. May become available in new PowerShell sessions."
            }
        }
        catch {
            Write-LogMessage "GitHub installation failed: $_" -Level "WARNING"
            Write-LogMessage "Attempting Microsoft Store as final fallback..." -Level "INFO"
            
            # Final fallback: Microsoft Store installation
            try {
                $wingetUrl = "ms-windows-store://pdp/?ProductId=9NBLGGH4NNS1"
                Start-Process $wingetUrl -ErrorAction Stop
                Write-LogMessage "Opened Microsoft Store for winget installation" -Level "INFO"
                Write-LogMessage "Please complete the installation manually and restart the application..." -Level "WARNING"
                
                # Brief wait to see if user installs quickly
                for ($check = 1; $check -le 4; $check++) {
                    Start-Sleep -Seconds 10
                    
                    if (Get-Command winget -ErrorAction SilentlyContinue) {
                        try {
                            $version = winget --version 2>$null
                            if ($version -and $version.Trim() -ne "") {
                                Write-LogMessage "Winget detected after Store installation: $version" -Level "SUCCESS"
                                return @{
                                    Success = $true
                                    Method = "MicrosoftStore"
                                    Version = $version
                                }
                            }
                        }
                        catch { }
                    }
                    
                    Write-LogMessage "Waiting for Store installation... (check $check/4)" -Level "INFO"
                }
                
                Write-LogMessage "Store installation initiated - please complete manually and restart" -Level "WARNING"
                return @{ 
                    Success = $false 
                    Reason = "StoreInstallationInitiated"
                    Message = "Microsoft Store opened for manual winget installation. Please complete and restart the application."
                }
            }
            catch {
                Write-LogMessage "Failed to open Microsoft Store: $_" -Level "ERROR"
                return @{ Success = $false; Reason = "AllMethodsFailed"; Error = $_.Exception.Message }
            }
        }
    }
    catch {
        Write-LogMessage "Error in winget installation process: $_" -Level "ERROR"
        return @{
            Success = $false
            Reason = "Exception"
            Error = $_.Exception.Message
        }
    }
}

function Register-WingetPackage {
    [CmdletBinding()]
    param()
    
    try {
        Write-Verbose "Attempting to register winget..."
        
        # Check if App Installer is available
        $appInstaller = Get-AppxPackage -Name "Microsoft.DesktopAppInstaller" -ErrorAction SilentlyContinue
        if (-not $appInstaller) {
            Write-Verbose "App Installer not found"
            return $false
        }
        
        Write-Verbose "App Installer found: $($appInstaller.Version)"
        
        # Try to register
        Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe -ErrorAction Stop
        Write-Verbose "Registration command completed"
        
        # Wait and verify
        Start-Sleep -Seconds 3
        $verification = Test-WingetInstallation
        
        return $verification.Available
    }
    catch {
        Write-Warning "Failed to register winget`: $_"
        return $false
    }
}

function Install-WingetPackage {
    [CmdletBinding()]
    param()
    
    try {
        Write-Verbose "Attempting to install winget automatically..."
        
        # Skip Microsoft Store method - go directly to automated installation
        Write-Verbose "Using direct download for seamless installation..."
        return Install-WingetDirect
    }
    catch {
        Write-Warning "Failed to install winget`: $_"
        return $false
    }
}

function Install-WingetDirect {
    [CmdletBinding()]
    param()
    
    try {
        # Import logging if available
        if (-not (Get-Command Write-LogMessage -ErrorAction SilentlyContinue)) {
            function Write-LogMessage {
                param([string]$Message, [string]$Level = "INFO")
                Write-Host "[$Level] $Message"
            }
        }
        
        Write-LogMessage "Starting enhanced winget installation with proper dependency sequencing..." -Level "INFO"
        
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
                Write-LogMessage "Winget command exists but not working properly, proceeding with installation..." -Level "INFO"
            }
        }
        
        # Create download directory
        $downloadDir = Join-Path $env:TEMP "winget-install"
        if (-not (Test-Path $downloadDir)) {
            New-Item -ItemType Directory -Path $downloadDir -Force | Out-Null
            Write-LogMessage "Created download directory at: $downloadDir" -Level "INFO"
        }
        
        # Step 1: Check and install dependencies in proper order with verification
        Write-LogMessage "Installing dependencies with proper sequencing and verification..." -Level "INFO"
        
        # Define dependencies in proper installation order
        $dependencies = @(
            @{
                Name = "Microsoft.VCLibs.x64.14.00.Desktop"
                Url = "https://aka.ms/Microsoft.VCLibs.x64.14.00.Desktop.appx"
                PackageName = "*VCLibs*"
                Required = $true
            },
            @{
                Name = "Microsoft.UI.Xaml.2.8"
                Url = "https://github.com/microsoft/microsoft-ui-xaml/releases/download/v2.8.6/Microsoft.UI.Xaml.2.8.x64.appx"
                PackageName = "*UI.Xaml*"
                Required = $true
            }
        )
        
        $dependenciesInstalled = 0
        $requiredDependenciesFailed = 0
        
        foreach ($dep in $dependencies) {
            Write-LogMessage "Processing dependency: $($dep.Name)" -Level "INFO"
            
            # Check if dependency is already installed
            $existingPackage = Get-AppxPackage -Name $dep.PackageName -ErrorAction SilentlyContinue
            if ($existingPackage) {
                Write-LogMessage "Dependency already installed: $($dep.Name) (Version: $($existingPackage.Version))" -Level "INFO"
                $dependenciesInstalled++
                continue
            }
            
            # Download dependency
            $depPath = Join-Path $downloadDir "$($dep.Name).appx"
            Write-LogMessage "Downloading dependency: $($dep.Name)" -Level "INFO"
            
            try {
                $webClient = New-Object System.Net.WebClient
                $webClient.DownloadFile($dep.Url, $depPath)
                
                if (-not (Test-Path $depPath)) {
                    Write-LogMessage "Download failed for dependency: $($dep.Name)" -Level "ERROR"
                    if ($dep.Required) { $requiredDependenciesFailed++ }
                    continue
                }
                
                # Verify download size
                $fileSize = (Get-Item $depPath).Length
                if ($fileSize -lt 1024) {
                    Write-LogMessage "Downloaded file too small for $($dep.Name), likely failed" -Level "ERROR"
                    if ($dep.Required) { $requiredDependenciesFailed++ }
                    continue
                }
                
                Write-LogMessage "Downloaded $($dep.Name) successfully ($([math]::Round($fileSize/1KB, 1)) KB)" -Level "SUCCESS"
                
                # Install dependency with retries
                $installSuccess = $false
                for ($attempt = 1; $attempt -le 3; $attempt++) {
                    try {
                        Write-LogMessage "Installing $($dep.Name) (attempt $attempt/3)..." -Level "INFO"
                        Add-AppxPackage -Path $depPath -ErrorAction Stop
                        
                        # Wait and verify installation
                        Start-Sleep -Seconds 3
                        $verifyPackage = Get-AppxPackage -Name $dep.PackageName -ErrorAction SilentlyContinue
                        if ($verifyPackage) {
                            Write-LogMessage "Successfully installed and verified: $($dep.Name)" -Level "SUCCESS"
                            $dependenciesInstalled++
                            $installSuccess = $true
                            break
                        } else {
                            Write-LogMessage "Installation completed but package not found in verification" -Level "WARNING"
                        }
                    }
                    catch {
                        Write-LogMessage "Installation attempt $attempt failed for $($dep.Name)``: $_" -Level "WARNING"
                        if ($attempt -lt 3) {
                            Start-Sleep -Seconds 5
                        }
                    }
                }
                
                if (-not $installSuccess -and $dep.Required) {
                    $requiredDependenciesFailed++
                    Write-LogMessage "Failed to install required dependency: $($dep.Name)" -Level "ERROR"
                }
            }
            catch {
                Write-LogMessage "Failed to download dependency $($dep.Name)``: $_" -Level "ERROR"
                if ($dep.Required) { $requiredDependenciesFailed++ }
            }
        }
        
        # Check if we have enough dependencies to proceed
        if ($requiredDependenciesFailed -gt 0) {
            Write-LogMessage "Failed to install $requiredDependenciesFailed required dependencies" -Level "ERROR"
            Write-LogMessage "Winget installation may fail, but attempting to continue..." -Level "WARNING"
        } else {
            Write-LogMessage "All dependencies installed successfully" -Level "SUCCESS"
        }
        
        # Step 2: Check if App Installer is already present and try registration first
        Write-LogMessage "Checking for existing App Installer..." -Level "INFO"
        $appInstaller = Get-AppxPackage -Name "Microsoft.DesktopAppInstaller" -ErrorAction SilentlyContinue
        if ($appInstaller) {
            Write-LogMessage "App Installer found: $($appInstaller.Version)" -Level "INFO"
            Write-LogMessage "Attempting to register winget with proper wait time..." -Level "INFO"
            
            try {
                Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe -ErrorAction Stop
                Write-LogMessage "Winget registration command completed successfully" -Level "SUCCESS"
                
                # Extended wait time for registration to take effect
                Write-LogMessage "Waiting for winget registration to complete (15 seconds)..." -Level "INFO"
                Start-Sleep -Seconds 15
                
                # Refresh environment variables
                $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
                
                # Test winget functionality with retries
                for ($attempt = 1; $attempt -le 5; $attempt++) {
                    try {
                        if (Get-Command winget -ErrorAction SilentlyContinue) {
                            $version = winget --version 2>$null
                            if ($version -and $version.Trim() -ne "") {
                                Write-LogMessage "Winget successfully registered and working: $version" -Level "SUCCESS"
                                Remove-Item $downloadDir -Recurse -Force -ErrorAction SilentlyContinue
                                return $true
                            }
                        }
                    }
                    catch {
                        Write-LogMessage "Winget test attempt $attempt failed``: $_" -Level "DEBUG"
                    }
                    
                    if ($attempt -lt 5) {
                        Write-LogMessage "Winget not ready yet, waiting 5 more seconds... (attempt $attempt/5)" -Level "INFO"
                        Start-Sleep -Seconds 5
                    }
                }
                
                Write-LogMessage "Registration completed but winget not yet functional" -Level "WARNING"
            } catch {
                Write-LogMessage "Failed to register winget``: $_" -Level "WARNING"
            }
        } else {
            Write-LogMessage "App Installer not found, need to install winget from scratch" -Level "INFO"
        }
        
        # Step 3: Download and install winget from GitHub
        Write-LogMessage "Downloading latest winget release..." -Level "INFO"
        
        # Use proper headers for GitHub API
        $headers = @{
            'User-Agent' = 'PowerShell-WingetInstaller'
            'Accept' = 'application/vnd.github.v3+json'
        }
        
        try {
            $releaseUrl = "https://api.github.com/repos/microsoft/winget-cli/releases/latest"
            $release = Invoke-RestMethod -Uri $releaseUrl -Headers $headers -TimeoutSec 30
            $msixBundle = $release.assets | Where-Object { $_.name -match "\.msixbundle$" } | Select-Object -First 1
            
            if (-not $msixBundle) {
                Write-LogMessage "Could not find winget MSIX bundle in latest release" -Level "ERROR"
                return $false
            }
            
            $bundlePath = Join-Path $downloadDir $msixBundle.name
            Write-LogMessage "Downloading winget from: $($msixBundle.browser_download_url)" -Level "INFO"
            Write-LogMessage "Target path: $bundlePath" -Level "INFO"
            
            # Download with WebClient for reliability
            $webClient = New-Object System.Net.WebClient
            $webClient.DownloadFile($msixBundle.browser_download_url, $bundlePath)
            
            # Verify download
            if (-not (Test-Path $bundlePath)) {
                Write-LogMessage "Download failed - file not found at expected location" -Level "ERROR"
                return $false
            }
            
            $fileSize = (Get-Item $bundlePath).Length
            Write-LogMessage "Download completed successfully (Size: $([math]::Round($fileSize/1MB, 2)) MB)" -Level "SUCCESS"
            
            # Install the bundle with proper error handling
            Write-LogMessage "Installing winget package..." -Level "INFO"
            
            $installSuccess = $false
            for ($attempt = 1; $attempt -le 3; $attempt++) {
                try {
                    Write-LogMessage "Installation attempt $attempt/3..." -Level "INFO"
                    Add-AppxPackage -Path $bundlePath -ForceApplicationShutdown -ErrorAction Stop
                    Write-LogMessage "Winget package installation command completed successfully" -Level "SUCCESS"
                    $installSuccess = $true
                    break
                }
                catch {
                    Write-LogMessage "Installation attempt $attempt failed``: $_" -Level "WARNING"
                    
                    # Check if it's a dependency version issue
                    if ($_.Exception.Message -like "*dependency*" -or $_.Exception.Message -like "*VCLibs*" -or $_.Exception.Message -like "*UI.Xaml*") {
                        Write-LogMessage "Dependency version conflict detected - this is common on older Windows 10 systems" -Level "WARNING"
                        
                        if ($attempt -eq 3) {
                            Write-LogMessage "All installation attempts failed due to dependency conflicts" -Level "ERROR"
                            Write-LogMessage "The script will continue using direct downloads instead of winget" -Level "INFO"
                            Remove-Item $downloadDir -Recurse -Force -ErrorAction SilentlyContinue
                            return $false
                        }
                    } else {
                        Write-LogMessage "Installation failed with unexpected error``: $_" -Level "ERROR"
                    }
                    
                    if ($attempt -lt 3) {
                        Write-LogMessage "Waiting 10 seconds before retry..." -Level "INFO"
                        Start-Sleep -Seconds 10
                    }
                }
            }
            
            if (-not $installSuccess) {
                Write-LogMessage "Failed to install winget after all attempts" -Level "ERROR"
                Remove-Item $downloadDir -Recurse -Force -ErrorAction SilentlyContinue
                return $false
            }
            
        } catch {
            Write-LogMessage "Failed to download winget``: $_" -Level "ERROR"
            Remove-Item $downloadDir -Recurse -Force -ErrorAction SilentlyContinue
            return $false
        }
        
        # Step 4: Extended verification with multiple attempts
        Write-LogMessage "Verifying winget installation with extended wait time..." -Level "INFO"
        
        # Clean up download directory first
        Remove-Item $downloadDir -Recurse -Force -ErrorAction SilentlyContinue
        Write-LogMessage "Cleaned up download directory" -Level "INFO"
        
        # Extended wait for installation to complete
        Write-LogMessage "Waiting for winget installation to fully complete (20 seconds)..." -Level "INFO"
        Start-Sleep -Seconds 20
        
        # Refresh environment variables multiple times
        for ($i = 1; $i -le 3; $i++) {
            $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
            Start-Sleep -Seconds 2
        }
        
        # Extended verification attempts
        $maxAttempts = 15
        $waitBetweenAttempts = 5
        
        for ($i = 1; $i -le $maxAttempts; $i++) {
            Write-LogMessage "Verification attempt $i/$maxAttempts..." -Level "INFO"
            
            try {
                if (Get-Command winget -ErrorAction SilentlyContinue) {
                    $version = winget --version 2>$null
                    if ($version -and $version.Trim() -ne "") {
                        Write-LogMessage "Winget installed successfully! Version: $version" -Level "SUCCESS"
                        Write-LogMessage "Winget is now ready for use" -Level "SUCCESS"
                        return $true
                    }
                }
            }
            catch {
                Write-LogMessage "Verification attempt $i error``: $_" -Level "DEBUG"
            }
            
            if ($i -lt $maxAttempts) {
                Write-LogMessage "Winget not ready yet, waiting $waitBetweenAttempts seconds..." -Level "INFO"
                Start-Sleep -Seconds $waitBetweenAttempts
            }
        }
        
        # Final check - installation may have succeeded but needs new session
        Write-LogMessage "Winget command not immediately available after installation" -Level "WARNING"
        Write-LogMessage "This is common and usually resolves in new PowerShell sessions" -Level "INFO"
        Write-LogMessage "Installation likely succeeded but winget may need a new session to become available" -Level "INFO"
        
        # Return true if installation commands succeeded, even if verification failed
        return $installSuccess
    }
    catch {
        Write-LogMessage "Failed to install winget``: $_" -Level "ERROR"
        return $false
    }
}

function Install-WingetViaMSStore {
    [CmdletBinding()]
    param()
    
    try {
        Write-Verbose "Attempting Microsoft Store installation method..."
        
        # Import logging if available
        if (-not (Get-Command Write-LogMessage -ErrorAction SilentlyContinue)) {
            function Write-LogMessage {
                param([string]$Message, [string]$Level = "INFO")
                Write-Host "[$Level] $Message"
            }
        }
        
        # Method 1: Try to trigger MS Store installation
        $storeAppId = "9NBLGGH4NNS1"  # App Installer store ID
        Write-LogMessage "Opening Microsoft Store for App Installer..." -Level "INFO"
        Start-Process "ms-windows-store://pdp/?productid=$storeAppId"
        
        Write-LogMessage "Please complete the installation in Microsoft Store." -Level "INFO"
        Write-LogMessage "The script will check for winget availability every 5 seconds..." -Level "INFO"
        
        # Wait for user to complete installation
        $timeout = 300  # 5 minutes
        $elapsed = 0
        $checkInterval = 5
        
        while ($elapsed -lt $timeout) {
            Start-Sleep -Seconds $checkInterval
            $elapsed += $checkInterval
            
            if (Get-Command winget -ErrorAction SilentlyContinue) {
                $version = winget --version 2>$null
                Write-LogMessage "Winget detected after Store installation! Version: $version" -Level "SUCCESS"
                return $true
            }
            
            # Update progress
            $remaining = $timeout - $elapsed
            Write-Progress -Activity "Waiting for winget installation" -Status "Time remaining: $remaining seconds" -PercentComplete (($elapsed / $timeout) * 100)
        }
        
        Write-Progress -Activity "Waiting for winget installation" -Completed
        Write-LogMessage "Timeout reached. Winget not detected." -Level "WARNING"
        return $false
    }
    catch {
        Write-LogMessage "Store installation method failed``: $_" -Level "ERROR"
        return $false
    }
}

function Install-WingetOffline {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$OfflinePackagePath
    )
    
    try {
        # Import logging if available
        if (-not (Get-Command Write-LogMessage -ErrorAction SilentlyContinue)) {
            function Write-LogMessage {
                param([string]$Message, [string]$Level = "INFO")
                Write-Host "[$Level] $Message"
            }
        }
        
        Write-LogMessage "Starting offline winget installation from: $OfflinePackagePath" -Level "INFO"
        
        if (-not (Test-Path $OfflinePackagePath)) {
            throw "Offline package path not found: $OfflinePackagePath"
        }
        
        # Install dependencies first
        $dependencies = Get-ChildItem -Path $OfflinePackagePath -Filter "*.appx" | 
            Where-Object { $_.Name -notmatch "DesktopAppInstaller" } | 
            Sort-Object Name  # Install in alphabetical order for consistency
            
        foreach ($dep in $dependencies) {
            Write-LogMessage "Installing dependency: $($dep.Name)" -Level "INFO"
            try {
                Add-AppxPackage -Path $dep.FullName -ErrorAction Stop
                Write-LogMessage "Successfully installed: $($dep.Name)" -Level "SUCCESS"
            }
            catch {
                Write-LogMessage "Failed to install dependency $($dep.Name)``: $_" -Level "WARNING"
            }
        }
        
        # Install winget bundle
        $wingetBundle = Get-ChildItem -Path $OfflinePackagePath -Filter "*.msixbundle" | 
            Select-Object -First 1
            
        if (-not $wingetBundle) {
            # Try alternative patterns
            $wingetBundle = Get-ChildItem -Path $OfflinePackagePath -Filter "*DesktopAppInstaller*.appx" | 
                Select-Object -First 1
        }
        
        if (-not $wingetBundle) {
            throw "Winget bundle not found in offline package"
        }
        
        Write-LogMessage "Installing winget from: $($wingetBundle.Name)" -Level "INFO"
        Add-AppxPackage -Path $wingetBundle.FullName -ForceApplicationShutdown -ErrorAction Stop
        
        # Verify installation
        Start-Sleep -Seconds 3
        if (Get-Command winget -ErrorAction SilentlyContinue) {
            $version = winget --version 2>$null
            Write-LogMessage "Winget installed successfully! Version: $version" -Level "SUCCESS"
            return $true
        }
        
        Write-LogMessage "Installation completed but winget command not immediately available" -Level "WARNING"
        return $true
    }
    catch {
        Write-LogMessage "Offline installation failed``: $_" -Level "ERROR"
        return $false
    }
}

# Helper function to download offline package for later use
function Get-WingetOfflinePackage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$DestinationPath
    )
    
    try {
        Write-Verbose "Downloading winget offline package to: $DestinationPath"
        
        # Create destination directory
        if (-not (Test-Path $DestinationPath)) {
            New-Item -ItemType Directory -Path $DestinationPath -Force | Out-Null
        }
        
        # Download dependencies
        $dependencies = @(
            @{
                Name = "Microsoft.VCLibs.x64.14.00.Desktop.appx"
                Url = "https://aka.ms/Microsoft.VCLibs.x64.14.00.Desktop.appx"
            },
            @{
                Name = "Microsoft.UI.Xaml.2.8.x64.appx"
                Url = "https://github.com/microsoft/microsoft-ui-xaml/releases/download/v2.8.6/Microsoft.UI.Xaml.2.8.x64.appx"
            }
        )
        
        foreach ($dep in $dependencies) {
            $depPath = Join-Path $DestinationPath $dep.Name
            Write-Verbose "Downloading: $($dep.Name)"
            Invoke-WebRequest -Uri $dep.Url -OutFile $depPath -UseBasicParsing
        }
        
        # Download latest winget
        $headers = @{
            'User-Agent' = 'PowerShell'
            'Accept' = 'application/vnd.github.v3+json'
        }
        
        $releaseUrl = "https://api.github.com/repos/microsoft/winget-cli/releases/latest"
        $release = Invoke-RestMethod -Uri $releaseUrl -Headers $headers
        $msixBundle = $release.assets | Where-Object { $_.name -match "\.msixbundle$" } | Select-Object -First 1
        
        if ($msixBundle) {
            $bundlePath = Join-Path $DestinationPath $msixBundle.name
            Write-Verbose "Downloading: $($msixBundle.name)"
            Invoke-WebRequest -Uri $msixBundle.browser_download_url -OutFile $bundlePath -UseBasicParsing
        }
        
        Write-Verbose "Offline package created successfully at: $DestinationPath"
        return $true
    }
    catch {
        Write-Warning "Failed to create offline package`: $_"
        return $false
    }
}

# Export all functions
Export-ModuleMember -Function @(
    "Test-WingetCompatibility",
    "Get-WindowsVersionName",
    "Install-WingetDependencies",
    "Resolve-WingetInstallationError",
    "Test-PowerShellExecutionPolicy",
    "Test-WingetInstallation", 
    "Initialize-WingetEnvironment",
    "Register-WingetPackage",
    "Install-WingetPackage",
    "Install-WingetDirect",
    "Install-WingetViaMSStore",
    "Install-WingetOffline",
    "Get-WingetOfflinePackage"
)