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
        
        # Try to install winget
        Write-Verbose "Attempting to install winget..."
        $installed = Install-WingetPackage
        
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
        # Create download directory
        $downloadDir = Join-Path $env:TEMP "WingetInstall"
        if (-not (Test-Path $downloadDir)) {
            New-Item -ItemType Directory -Path $downloadDir -Force | Out-Null
        }
        
        # Get latest release info
        Write-Verbose "Fetching latest winget release information..."
        $releaseUrl = "https://api.github.com/repos/microsoft/winget-cli/releases/latest"
        $release = Invoke-RestMethod -Uri $releaseUrl -TimeoutSec 15 -ErrorAction Stop
        
        $msixBundle = $release.assets | Where-Object { $_.name -like "*.msixbundle" } | Select-Object -First 1
        
        if (-not $msixBundle) {
            Write-Warning "Could not find winget MSIX bundle"
            return $false
        }
        
        $downloadPath = Join-Path $downloadDir $msixBundle.name
        Write-Verbose "Downloading winget bundle to: $downloadPath"
        
        # Download with retry logic
        $retryCount = 0
        $maxRetries = 3
        $downloaded = $false
        
        while ($retryCount -lt $maxRetries -and -not $downloaded) {
            try {
                $webClient = New-Object System.Net.WebClient
                $webClient.DownloadFile($msixBundle.browser_download_url, $downloadPath)
                $downloaded = $true
                Write-Verbose "Download completed successfully"
            }
            catch {
                $retryCount++
                Write-Verbose "Download attempt $retryCount failed: $_"
                if ($retryCount -lt $maxRetries) {
                    Start-Sleep -Seconds 2
                }
            }
        }
        
        if (-not $downloaded) {
            Write-Warning "Failed to download winget after $maxRetries attempts"
            return $false
        }
        
        # Verify download
        if (-not (Test-Path $downloadPath)) {
            Write-Warning "Download failed - file not found"
            return $false
        }
        
        # Install the bundle
        Write-Verbose "Installing winget package..."
        Add-AppxPackage -Path $downloadPath -ErrorAction Stop
        
        # Clean up
        Remove-Item $downloadPath -Force -ErrorAction SilentlyContinue
        Remove-Item $downloadDir -Force -Recurse -ErrorAction SilentlyContinue
        
        # Verify installation
        Start-Sleep -Seconds 3
        $verification = Test-WingetInstallation
        
        return $verification.Available
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