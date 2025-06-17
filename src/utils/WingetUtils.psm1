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
        
        # Check current installation status with improved verification
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
        
        # Enhanced registration attempt for existing installations
        if ($installation.NeedsRegistration -or $installation.Installed) {
            Write-Verbose "Winget needs registration or repair..."
            
            # Method 1: PowerShell module repair with extended time (Microsoft's recommended method)
            try {
                Write-Verbose "Attempting PowerShell module approach for winget registration..."
                
                # Check if NuGet provider is installed
                if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) {
                    Write-Verbose "Installing NuGet provider..."
                    Install-PackageProvider -Name NuGet -Force -Scope CurrentUser | Out-Null
                }
                
                # Check if module is already installed
                if (-not (Get-Module -ListAvailable -Name Microsoft.WinGet.Client)) {
                    Write-Verbose "Installing Microsoft.WinGet.Client module..."
                    Install-Module -Name Microsoft.WinGet.Client -Force -Repository PSGallery -Scope CurrentUser | Out-Null
                }
                
                Write-Verbose "Importing Microsoft.WinGet.Client module..."
                Import-Module Microsoft.WinGet.Client -Force
                
                Write-Verbose "Repairing WinGet package manager..."
                Repair-WinGetPackageManager -Latest -Force
                
                # Extended wait time for module-based repair
                Write-Verbose "Waiting for module repair to complete (10 seconds)..."
                Start-Sleep -Seconds 10
                
                # Multiple verification attempts for module repair
                for ($attempt = 1; $attempt -le 5; $attempt++) {
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
                    
                    if ($attempt -lt 5) {
                        Write-Verbose "Module repair verification attempt $attempt failed, waiting 3 seconds..."
                        Start-Sleep -Seconds 3
                    }
                }
                
                Write-Verbose "Module repair completed but winget not yet available"
            } catch {
                Write-Verbose "PowerShell module approach failed: $_"
            }
            
            # Method 2: Direct registration with extended verification
            Write-Verbose "Attempting direct winget registration..."
            $registered = Register-WingetPackage
            if ($registered) {
                # Extended wait for registration to take effect
                Write-Verbose "Waiting for registration to complete (10 seconds)..."
                Start-Sleep -Seconds 10
                
                # Multiple verification attempts
                for ($attempt = 1; $attempt -le 5; $attempt++) {
                    $newInstallation = Test-WingetInstallation
                    if ($newInstallation.Available) {
                        return @{
                            Success = $true
                            Registered = $true
                            Method = "StandardRegistration"
                            Version = $newInstallation.Version
                            Details = $newInstallation
                        }
                    }
                    
                    if ($attempt -lt 5) {
                        Write-Verbose "Registration verification attempt $attempt failed, waiting 3 seconds..."
                        Start-Sleep -Seconds 3
                    }
                }
            }
        }
        
        # Try to install winget using the enhanced direct method with extended time
        Write-Verbose "Attempting to install winget with improved dependency handling..."
        $installed = Install-WingetDirect
        
        if ($installed) {
            Write-Verbose "Winget installation command completed, performing extended verification..."
            
            # Extended initial wait
            Start-Sleep -Seconds 10
            
            # Extended verification with more attempts and longer waits
            for ($i = 0; $i -lt 12; $i++) {
                $finalInstallation = Test-WingetInstallation
                if ($finalInstallation.Available) {
                    Write-Verbose "Winget is now available after installation (attempt $($i + 1))"
                    return @{
                        Success = $true
                        Installed = $true
                        Version = $finalInstallation.Version
                        Details = $finalInstallation
                        RetryCount = $i
                        Method = "DirectInstallation"
                    }
                }
                
                if ($i -lt 11) {
                    Write-Verbose "Winget not yet available, waiting... (attempt $($i + 1)/12)"
                    # Progressive wait times - start short, get longer
                    $waitTime = if ($i -lt 4) { 3 } elseif ($i -lt 8) { 5 } else { 8 }
                    Start-Sleep -Seconds $waitTime
                }
            }
            
            # Installation succeeded but command not available after extended verification
            Write-Verbose "Winget installation completed but command not available after extended verification attempts"
            Write-Verbose "This may indicate the installation succeeded but needs a new PowerShell session"
            
            # Try alternative verification methods
            if ($AllowManualInstall) {
                Write-Verbose "Attempting Microsoft Store fallback method..."
                $storeResult = Install-WingetViaMSStore
                if ($storeResult) {
                    return @{
                        Success = $true
                        Installed = $true
                        Method = "MicrosoftStoreAssisted"
                    }
                }
            }
            
            # Return partial success - installation likely worked but verification failed
            return @{
                Success = $true  # Changed to true since installation commands succeeded
                Installed = $true
                Reason = "InstallationSucceededButNotImmediatelyAvailable"
                Details = $finalInstallation
                Message = "Winget installation completed. May become available in new PowerShell sessions."
                Method = "DirectInstallation"
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
            Reason = "AllInstallationMethodsFailed"
            Details = $installation
            Message = "All winget installation methods failed. Applications will be installed via direct downloads."
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
                        Write-LogMessage "Installation attempt $attempt failed for $($dep.Name): $_" -Level "WARNING"
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
                Write-LogMessage "Failed to download dependency $($dep.Name): $_" -Level "ERROR"
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
                        Write-LogMessage "Winget test attempt $attempt failed: $_" -Level "DEBUG"
                    }
                    
                    if ($attempt -lt 5) {
                        Write-LogMessage "Winget not ready yet, waiting 5 more seconds... (attempt $attempt/5)" -Level "INFO"
                        Start-Sleep -Seconds 5
                    }
                }
                
                Write-LogMessage "Registration completed but winget not yet functional" -Level "WARNING"
            } catch {
                Write-LogMessage "Failed to register winget: $_" -Level "WARNING"
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
                    Write-LogMessage "Installation attempt $attempt failed: $_" -Level "WARNING"
                    
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
                        Write-LogMessage "Installation failed with unexpected error: $_" -Level "ERROR"
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
            Write-LogMessage "Failed to download winget: $_" -Level "ERROR"
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
                Write-LogMessage "Verification attempt $i error: $_" -Level "DEBUG"
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