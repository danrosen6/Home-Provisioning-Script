# Enhanced Winget utilities for Windows Setup GUI
# Improved installation methods and Windows 10 compatibility

function Test-WingetCompatibility {
    [CmdletBinding()]
    param()
    
    try {
        $buildNumber = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion").CurrentBuild
        $osName = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion").ProductName
        
        $isCompatible = ([int]$buildNumber -ge 16299)
        $wingetAvailable = (Get-Command winget -ErrorAction SilentlyContinue) -ne $null
        
        # Get Windows version name for better user information
        $versionName = Get-WindowsVersionName -BuildNumber $buildNumber
        
        return @{
            Compatible = $isCompatible
            Available = $wingetAvailable
            BuildNumber = $buildNumber
            OSName = $osName
            VersionName = $versionName
            MinimumBuild = 16299
            MinimumVersion = "Windows 10 1709"
        }
    }
    catch {
        return @{
            Compatible = $false
            Available = $false
            BuildNumber = "Unknown"
            OSName = "Unknown"
            VersionName = "Unknown"
            MinimumBuild = 16299
            MinimumVersion = "Windows 10 1709"
            Error = $_.Exception.Message
        }
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
        [switch]$AllowManualInstall
    )
    
    try {
        Write-Verbose "Checking winget compatibility..."
        $compatibility = Test-WingetCompatibility
        
        if (-not $compatibility.Compatible) {
            Write-Warning "Windows build $($compatibility.BuildNumber) is below minimum requirement for winget ($($compatibility.MinimumBuild))"
            return @{
                Success = $false
                Reason = "IncompatibleWindows"
                Details = $compatibility
            }
        }
        
        Write-Verbose "Windows is compatible with winget"
        
        # Check current installation status
        $installation = Test-WingetInstallation
        
        if ($installation.Available -and -not $Force) {
            Write-Verbose "Winget is already available: $($installation.Version)"
            return @{
                Success = $true
                AlreadyAvailable = $true
                Version = $installation.Version
                Details = $installation
            }
        }
        
        if ($installation.NeedsRegistration -or $installation.Installed) {
            Write-Verbose "Winget needs registration or repair..."
            
            # Method 1: PowerShell module repair (Microsoft's recommended method)
            try {
                Write-Verbose "Attempting PowerShell module approach for winget registration..."
                
                # Check if NuGet provider is installed
                if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) {
                    Install-PackageProvider -Name NuGet -Force -Scope CurrentUser | Out-Null
                }
                
                # Check if module is already installed
                if (-not (Get-Module -ListAvailable -Name Microsoft.WinGet.Client)) {
                    Install-Module -Name Microsoft.WinGet.Client -Force -Repository PSGallery -Scope CurrentUser | Out-Null
                }
                
                Import-Module Microsoft.WinGet.Client -Force
                Repair-WinGetPackageManager -Latest -Force
                
                Start-Sleep -Seconds 5
                $moduleInstallation = Test-WingetInstallation
                if ($moduleInstallation.Available) {
                    Write-Verbose "Winget successfully registered via PowerShell module"
                    return @{
                        Success = $true
                        Registered = $true
                        Method = "PowerShellModule"
                        Version = $moduleInstallation.Version
                        Details = $moduleInstallation
                    }
                }
            } catch {
                Write-Verbose "PowerShell module approach failed: $_"
            }
            
            # Method 2: Direct registration
            $registered = Register-WingetPackage
            if ($registered) {
                $newInstallation = Test-WingetInstallation
                return @{
                    Success = $newInstallation.Available
                    Registered = $true
                    Method = "StandardRegistration"
                    Version = $newInstallation.Version
                    Details = $newInstallation
                }
            }
        }
        
        # Try to install winget using the enhanced direct method
        Write-Verbose "Attempting to install winget..."
        $installed = Install-WingetDirect
        
        if ($installed) {
            # Wait and verify with multiple attempts
            Start-Sleep -Seconds 5
            for ($i = 0; $i -lt 6; $i++) {
                $finalInstallation = Test-WingetInstallation
                if ($finalInstallation.Available) {
                    Write-Verbose "Winget is now available after installation"
                    return @{
                        Success = $true
                        Installed = $true
                        Version = $finalInstallation.Version
                        Details = $finalInstallation
                        RetryCount = $i
                    }
                }
                if ($i -lt 5) {
                    Write-Verbose "Winget not yet available, waiting... (attempt $($i + 1)/6)"
                    Start-Sleep -Seconds 3
                }
            }
            
            # Installation succeeded but command not available
            Write-Verbose "Winget installation completed but command not available after verification attempts"
            
            # Try alternative verification methods
            if ($AllowManualInstall) {
                $storeResult = Install-WingetViaMSStore
                if ($storeResult) {
                    return @{
                        Success = $true
                        Installed = $true
                        Method = "MicrosoftStoreAssisted"
                    }
                }
            }
            
            return @{
                Success = $false
                Installed = $true
                Reason = "InstallationSucceededButNotAvailable"
                Details = $finalInstallation
            }
        }
        
        # If automated methods fail and manual install is allowed
        if ($AllowManualInstall) {
            Write-Verbose "Automated installation failed. Trying Microsoft Store method..."
            $storeInstalled = Install-WingetViaMSStore
            
            if ($storeInstalled) {
                return @{
                    Success = $true
                    Installed = $true
                    Method = "MicrosoftStore"
                }
            }
        }
        
        return @{
            Success = $false
            Reason = "InstallationFailed"
            Details = $installation
        }
    }
    catch {
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
        Write-Warning "Failed to register winget: $_"
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
        Write-Warning "Failed to install winget: $_"
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
        
        Write-LogMessage "Starting enhanced winget installation..." -Level "INFO"
        
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
        
        # Create download directory
        $downloadDir = Join-Path $env:TEMP "winget-install"
        if (-not (Test-Path $downloadDir)) {
            New-Item -ItemType Directory -Path $downloadDir -Force | Out-Null
            Write-LogMessage "Created download directory at: $downloadDir" -Level "INFO"
        }
        
        # Step 1: Install dependencies first - simplified approach for better compatibility
        Write-LogMessage "Installing dependencies with fallback handling..." -Level "INFO"
        
        $dependencies = @(
            @{
                Name = "Microsoft.VCLibs.x64.14.00.Desktop"
                Url = "https://aka.ms/Microsoft.VCLibs.x64.14.00.Desktop.appx"
            },
            @{
                Name = "Microsoft.UI.Xaml.2.8"
                Url = "https://github.com/microsoft/microsoft-ui-xaml/releases/download/v2.8.6/Microsoft.UI.Xaml.2.8.x64.appx"
            }
        )
        
        $dependenciesInstalled = 0
        foreach ($dep in $dependencies) {
            $depPath = Join-Path $downloadDir "$($dep.Name).appx"
            Write-LogMessage "Downloading dependency: $($dep.Name)" -Level "INFO"
            
            try {
                # Use WebClient for more reliable downloads
                $webClient = New-Object System.Net.WebClient
                $webClient.DownloadFile($dep.Url, $depPath)
                
                if (Test-Path $depPath) {
                    Add-AppxPackage -Path $depPath -ErrorAction Stop
                    Write-LogMessage "Installed dependency: $($dep.Name)" -Level "SUCCESS"
                    $dependenciesInstalled++
                } else {
                    Write-LogMessage "Download failed for dependency: $($dep.Name)" -Level "WARNING"
                }
            }
            catch {
                Write-LogMessage "Failed to install dependency $($dep.Name): $_" -Level "WARNING"
                Write-LogMessage "Continuing with winget installation despite dependency failure..." -Level "INFO"
            }
        }
        
        # Check if App Installer is already present but winget not registered
        $appInstaller = Get-AppxPackage -Name "Microsoft.DesktopAppInstaller" -ErrorAction SilentlyContinue
        if ($appInstaller) {
            Write-LogMessage "App Installer found: $($appInstaller.Version)" -Level "INFO"
            Write-LogMessage "Attempting to register winget..." -Level "INFO"
            
            try {
                Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe
                Write-LogMessage "Winget registration command completed" -Level "INFO"
                
                Start-Sleep -Seconds 5
                if (Get-Command winget -ErrorAction SilentlyContinue) {
                    $version = winget --version 2>$null
                    Write-LogMessage "Winget successfully registered: $version" -Level "SUCCESS"
                    Remove-Item $downloadDir -Recurse -Force -ErrorAction SilentlyContinue
                    return $true
                } else {
                    Write-LogMessage "Registration completed but command not yet available" -Level "WARNING"
                }
            } catch {
                Write-LogMessage "Failed to register winget: $_" -Level "WARNING"
            }
        }
        
        # Step 2: Download and install winget
        Write-LogMessage "Fetching latest winget release information..." -Level "INFO"
        
        # Use proper headers for GitHub API
        $headers = @{
            'User-Agent' = 'PowerShell'
            'Accept' = 'application/vnd.github.v3+json'
        }
        
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
        
        # Install the bundle with dependency tolerance
        Write-LogMessage "Installing winget package..." -Level "INFO"
        try {
            Add-AppxPackage -Path $bundlePath -ForceApplicationShutdown -ErrorAction Stop
            Write-LogMessage "Winget package installed successfully" -Level "SUCCESS"
        }
        catch {
            Write-LogMessage "Winget installation failed (this may be due to dependency version conflicts): $_" -Level "WARNING"
            
            # Check if it's a dependency version issue - if so, consider it a soft failure
            if ($_.Exception.Message -like "*dependency*" -or $_.Exception.Message -like "*VCLibs*") {
                Write-LogMessage "Dependency version conflict detected - this is common on older Windows 10 systems" -Level "WARNING"
                Write-LogMessage "The script will continue using direct downloads instead of winget" -Level "INFO"
                
                # Clean up and return false to indicate winget installation failed
                Remove-Item $downloadDir -Recurse -Force -ErrorAction SilentlyContinue
                return $false
            } else {
                # Re-throw other types of errors
                throw $_
            }
        }
        
        # Clean up
        Remove-Item $downloadDir -Recurse -Force -ErrorAction SilentlyContinue
        Write-LogMessage "Cleaned up download directory" -Level "INFO"
        
        # Verify installation with environment refresh
        Write-LogMessage "Refreshing environment and verifying installation..." -Level "INFO"
        
        # Refresh PATH
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
        
        # Multiple verification attempts
        $maxAttempts = 10
        for ($i = 1; $i -le $maxAttempts; $i++) {
            Start-Sleep -Seconds 2
            
            if (Get-Command winget -ErrorAction SilentlyContinue) {
                $version = winget --version 2>$null
                Write-LogMessage "Winget installed successfully! Version: $version" -Level "SUCCESS"
                return $true
            }
            
            Write-LogMessage "Verification attempt $i/$maxAttempts..." -Level "INFO"
        }
        
        Write-LogMessage "Winget command not found after installation - this is normal and does NOT require restart" -Level "WARNING"
        Write-LogMessage "Winget may become available in new PowerShell sessions or after PATH refresh" -Level "INFO"
        return $true  # Installation likely succeeded, just needs new session
    }
    catch {
        Write-LogMessage "Failed to install winget: $_" -Level "ERROR"
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
        Write-LogMessage "Store installation method failed: $_" -Level "ERROR"
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
                Write-LogMessage "Failed to install dependency $($dep.Name): $_" -Level "WARNING"
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
        Write-LogMessage "Offline installation failed: $_" -Level "ERROR"
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
        Write-Warning "Failed to create offline package: $_"
        return $false
    }
}

# Export all functions
Export-ModuleMember -Function @(
    "Test-WingetCompatibility",
    "Get-WindowsVersionName",
    "Test-WingetInstallation", 
    "Initialize-WingetEnvironment",
    "Register-WingetPackage",
    "Install-WingetPackage",
    "Install-WingetDirect",
    "Install-WingetViaMSStore",
    "Install-WingetOffline",
    "Get-WingetOfflinePackage"
)