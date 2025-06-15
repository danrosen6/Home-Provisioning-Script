# Winget utilities for Windows Setup GUI

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
        [switch]$Force
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
        
        if ($installation.Available) {
            Write-Verbose "Winget is already available: $($installation.Version)"
            return @{
                Success = $true
                AlreadyAvailable = $true
                Version = $installation.Version
                Details = $installation
            }
        }
        
        if ($installation.NeedsRegistration) {
            Write-Verbose "Winget needs registration..."
            $registered = Register-WingetPackage
            if ($registered) {
                $newInstallation = Test-WingetInstallation
                return @{
                    Success = $newInstallation.Available
                    Registered = $true
                    Version = $newInstallation.Version
                    Details = $newInstallation
                }
            }
        }
        
        # Try to install winget using the proven direct method
        Write-Verbose "Attempting to install winget..."
        $installed = Install-WingetDirect
        
        if ($installed) {
            $finalInstallation = Test-WingetInstallation
            return @{
                Success = $finalInstallation.Available
                Installed = $true
                Version = $finalInstallation.Version
                Details = $finalInstallation
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
        Write-Verbose "Attempting to install winget..."
        
        # Try Microsoft Store first
        try {
            Write-Verbose "Opening Microsoft Store for winget installation..."
            $wingetUrl = "ms-windows-store://pdp/?ProductId=9NBLGGH4NNS1"
            Start-Process $wingetUrl -ErrorAction Stop
            Write-Verbose "Microsoft Store opened. Manual installation required."
            return $false  # Requires manual action
        }
        catch {
            Write-Verbose "Failed to open Microsoft Store: $_"
        }
        
        # Try direct download as fallback
        Write-Verbose "Attempting direct download installation..."
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
        
        Write-LogMessage "Starting winget installation..." -Level "INFO"
        
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
        
        # Create download directory using proper path structure
        $scriptPath = if ($PSScriptRoot) { Split-Path -Parent (Split-Path -Parent $PSScriptRoot) } else { $env:TEMP }
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
        
        # Fallback to direct download using GitHub API (proven working approach)
        Write-LogMessage "Attempting direct download of winget..." -Level "INFO"
        try {
            # Create winget-specific directory
            $wingetDir = Join-Path $downloadDir "winget"
            if (-not (Test-Path $wingetDir)) {
                New-Item -ItemType Directory -Path $wingetDir -Force | Out-Null
                Write-LogMessage "Created winget directory at: $wingetDir" -Level "INFO"
            }
            
            # Download the latest winget release using GitHub API
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
    catch {
        Write-Warning "Failed to install winget directly: $_"
        return $false
    }
}

Export-ModuleMember -Function @(
    "Test-WingetCompatibility",
    "Get-WindowsVersionName",
    "Test-WingetInstallation", 
    "Initialize-WingetEnvironment",
    "Register-WingetPackage",
    "Install-WingetPackage",
    "Install-WingetDirect"
)