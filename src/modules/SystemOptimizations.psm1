# System optimization modules for Windows Setup GUI

# Global variables
$script:RegistryBackups = @{}
$script:ServiceBackups = @{}

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

function Save-RegistryValue {
    param (
        [Parameter(Mandatory=$true)]
        [string]$Path,
        
        [Parameter(Mandatory=$true)]
        [string]$Name
    )
    
    try {
        if (Test-Path $Path) {
            $value = Get-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue
            if ($value) {
                $backupKey = "${Path}|${Name}"
                $script:RegistryBackups[$backupKey] = $value.$Name
                return $true
            }
        }
        return $false
    }
    catch {
        Write-LogMessage "Failed to backup registry value: $_" -Level "ERROR"
        return $false
    }
}

function Save-ServiceState {
    param (
        [Parameter(Mandatory=$true)]
        [string]$ServiceName
    )
    
    try {
        $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
        if ($service) {
            $script:ServiceBackups[$ServiceName] = @{
                Status = $service.Status
                StartType = $service.StartType
            }
            return $true
        }
        return $false
    }
    catch {
        Write-LogMessage "Failed to backup service: $_" -Level "ERROR"
        return $false
    }
}

function Restore-RegistryValue {
    param (
        [Parameter(Mandatory=$true)]
        [string]$Path,
        
        [Parameter(Mandatory=$true)]
        [string]$Name
    )
    
    try {
        $backupKey = "${Path}|${Name}"
        if ($script:RegistryBackups.ContainsKey($backupKey)) {
            Set-ItemProperty -Path $Path -Name $Name -Value $script:RegistryBackups[$backupKey]
            Write-LogMessage "Restored registry value: ${Path}\${Name}" -Level "INFO"
            return $true
        }
        return $false
    }
    catch {
        Write-LogMessage "Failed to restore registry value: $_" -Level "ERROR"
        return $false
    }
}

function Restore-ServiceState {
    param (
        [Parameter(Mandatory=$true)]
        [string]$ServiceName
    )
    
    try {
        if ($script:ServiceBackups.ContainsKey($ServiceName)) {
            $backup = $script:ServiceBackups[$ServiceName]
            Set-Service -Name $ServiceName -StartupType $backup.StartType
            if ($backup.Status -eq "Running") {
                Start-Service -Name $ServiceName
            }
            Write-LogMessage "Restored service: ${ServiceName}" -Level "INFO"
            return $true
        }
        return $false
    }
    catch {
        Write-LogMessage "Failed to restore service: $_" -Level "ERROR"
        return $false
    }
}

function Set-SystemOptimization {
    param (
        [string]$OptimizationKey,
        [System.Threading.CancellationToken]$CancellationToken
    )

    Write-LogMessage "Applying optimization: ${OptimizationKey}" -Level "INFO"

    try {
        switch ($OptimizationKey) {
            # Service optimizations
            "diagtrack" {
                Save-ServiceState -ServiceName "DiagTrack"
                Stop-Service "DiagTrack" -Force -ErrorAction SilentlyContinue
                Set-Service "DiagTrack" -StartupType Disabled
            }
            "dmwappushsvc" {
                Save-ServiceState -ServiceName "dmwappushservice"
                Stop-Service "dmwappushservice" -Force -ErrorAction SilentlyContinue
                Set-Service "dmwappushservice" -StartupType Disabled
            }
            "sysmain" {
                Save-ServiceState -ServiceName "SysMain"
                Stop-Service "SysMain" -Force -ErrorAction SilentlyContinue
                Set-Service "SysMain" -StartupType Disabled
            }
            "wmpnetworksvc" {
                Save-ServiceState -ServiceName "WMPNetworkSvc"
                Stop-Service "WMPNetworkSvc" -Force -ErrorAction SilentlyContinue
                Set-Service "WMPNetworkSvc" -StartupType Disabled
            }
            "remoteregistry" {
                Save-ServiceState -ServiceName "RemoteRegistry"
                Stop-Service "RemoteRegistry" -Force -ErrorAction SilentlyContinue
                Set-Service "RemoteRegistry" -StartupType Disabled
            }
            "remoteaccess" {
                Save-ServiceState -ServiceName "RemoteAccess"
                Stop-Service "RemoteAccess" -Force -ErrorAction SilentlyContinue
                Set-Service "RemoteAccess" -StartupType Disabled
            }
            "fax" {
                Save-ServiceState -ServiceName "Fax"
                Stop-Service "Fax" -Force -ErrorAction SilentlyContinue
                Set-Service "Fax" -StartupType Disabled
            }
            
            # System optimizations
            "show-extensions" {
                if (-not (Test-Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced")) {
                    New-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Force | Out-Null
                }
                Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "HideFileExt" -Value 0
            }
            "show-hidden" {
                if (-not (Test-Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced")) {
                    New-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Force | Out-Null
                }
                Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "Hidden" -Value 1
            }
            "dev-mode" {
                if (-not (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock")) {
                    New-Item -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock" -Force | Out-Null
                }
                Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock" -Name "AllowDevelopmentWithoutDevLicense" -Value 1
            }
            "disable-cortana" {
                if (-not (Test-Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search")) {
                    New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search" -Force | Out-Null
                }
                Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search" -Name "AllowCortana" -Value 0
            }
            "reduce-telemetry" {
                if (-not (Test-Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection")) {
                    New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" -Force | Out-Null
                }
                Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" -Name "AllowTelemetry" -Value 0
            }
            "taskbar-left" {
                if (-not (Test-Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced")) {
                    New-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Force | Out-Null
                }
                Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "TaskbarAl" -Value 0
            }
            "disable-chat" {
                if (-not (Test-Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced")) {
                    New-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Force | Out-Null
                }
                Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "TaskbarMn" -Value 0
            }
            "disable-widgets" {
                if (-not (Test-Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced")) {
                    New-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Force | Out-Null
                }
                Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "TaskbarDa" -Value 0
            }
            default {
                Write-LogMessage "Unknown optimization key: ${OptimizationKey}" -Level "WARNING"
                return $false
            }
        }

        Write-LogMessage "Successfully applied optimization: ${OptimizationKey}" -Level "SUCCESS"
        return $true
    }
    catch {
        Write-LogMessage "Failed to apply optimization ${OptimizationKey}: $_" -Level "ERROR"
        
        # Attempt rollback
        try {
            switch ($OptimizationKey) {
                "DisableTelemetry" {
                    Restore-RegistryValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" -Name "AllowTelemetry"
                    Restore-RegistryValue -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection" -Name "AllowTelemetry"
                }
                "DisableCortana" {
                    Restore-RegistryValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search" -Name "AllowCortana"
                }
                "DisableWindowsSearch" {
                    Restore-ServiceState -ServiceName "WSearch"
                }
                "DisableWindowsUpdate" {
                    Restore-ServiceState -ServiceName "wuauserv"
                }
                "DisableWindowsDefender" {
                    Restore-RegistryValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender" -Name "DisableAntiSpyware"
                }
                "DisableWindowsFirewall" {
                    Restore-RegistryValue -Path "HKLM:\SYSTEM\CurrentControlSet\Services\SharedAccess\Parameters\FirewallPolicy\StandardProfile" -Name "EnableFirewall"
                }
            }
            Write-LogMessage "Successfully rolled back optimization: ${OptimizationKey}" -Level "INFO"
        }
        catch {
            Write-LogMessage "Failed to roll back optimization ${OptimizationKey}: $_" -Level "ERROR"
        }
        
        return $false
    }
}

function Optimize-System {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [hashtable]$Optimizations = $script:AppConfig.Optimizations,
        
        [System.Threading.CancellationToken]$CancellationToken
    )
    
    Write-Log "Starting system optimization..." -Level "INFO"
    
    # Check for cancellation
    if ($CancellationToken.IsCancellationRequested) {
        Write-Log "System optimization cancelled" -Level "WARNING"
        return $false
    }
    
    try {
        # Disable Telemetry
        if ($Optimizations.DisableTelemetry) {
            Write-Log "Disabling Windows Telemetry..." -Level "INFO"
            Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" -Name "AllowTelemetry" -Value 0
            Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection" -Name "AllowTelemetry" -Value 0
            Write-Log "Windows Telemetry disabled" -Level "SUCCESS"
        }
        
        # Disable Cortana
        if ($Optimizations.DisableCortana) {
            Write-Log "Disabling Cortana..." -Level "INFO"
            Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search" -Name "AllowCortana" -Value 0
            Write-Log "Cortana disabled" -Level "SUCCESS"
        }
        
        # Disable Windows Search
        if ($Optimizations.DisableWindowsSearch) {
            Write-Log "Disabling Windows Search..." -Level "INFO"
            Stop-Service "WSearch" -Force
            Set-Service "WSearch" -StartupType Disabled
            Write-Log "Windows Search disabled" -Level "SUCCESS"
        }
        
        # Disable Windows Update
        if ($Optimizations.DisableWindowsUpdate) {
            Write-Log "Disabling Windows Update..." -Level "INFO"
            Stop-Service "wuauserv" -Force
            Set-Service "wuauserv" -StartupType Disabled
            Write-Log "Windows Update disabled" -Level "SUCCESS"
        }
        
        # Disable Windows Defender
        if ($Optimizations.DisableDefender) {
            Write-Log "Disabling Windows Defender..." -Level "INFO"
            Set-MpPreference -DisableRealtimeMonitoring $true
            Set-MpPreference -DisableIOAVProtection $true
            Write-Log "Windows Defender disabled" -Level "SUCCESS"
        }
        
        # Disable Windows Firewall
        if ($Optimizations.DisableFirewall) {
            Write-Log "Disabling Windows Firewall..." -Level "INFO"
            Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled False
            Write-Log "Windows Firewall disabled" -Level "SUCCESS"
        }
        
        Write-Log "System optimization completed successfully!" -Level "SUCCESS"
        return $true
    }
    catch {
        Write-Log "Failed to optimize system: $_" -Level "ERROR"
        return $false
    }
}

function Remove-Bloatware {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [string[]]$Bloatware = $script:AppConfig.Bloatware,
        
        [System.Threading.CancellationToken]$CancellationToken
    )
    
    Write-Log "Starting bloatware removal..." -Level "INFO"
    
    # Check for cancellation
    if ($CancellationToken.IsCancellationRequested) {
        Write-Log "Bloatware removal cancelled" -Level "WARNING"
        return $false
    }
    
    try {
        foreach ($app in $Bloatware) {
            Write-Log "Removing $app..." -Level "INFO"
            Get-AppxPackage -Name $app -AllUsers | Remove-AppxPackage -ErrorAction SilentlyContinue
            Get-AppxProvisionedPackage -Online | Where-Object DisplayName -like $app | Remove-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue
            Write-Log "Removed $app" -Level "SUCCESS"
        }
        
        Write-Log "Bloatware removal completed successfully!" -Level "SUCCESS"
        return $true
    }
    catch {
        Write-Log "Failed to remove bloatware: $_" -Level "ERROR"
        return $false
    }
}

function Configure-Services {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [hashtable]$Services = $script:AppConfig.Services,
        
        [System.Threading.CancellationToken]$CancellationToken
    )
    
    Write-Log "Starting service configuration..." -Level "INFO"
    
    # Check for cancellation
    if ($CancellationToken.IsCancellationRequested) {
        Write-Log "Service configuration cancelled" -Level "WARNING"
        return $false
    }
    
    try {
        foreach ($service in $Services.GetEnumerator()) {
            Write-Log "Configuring service: $($service.Value.Name)..." -Level "INFO"
            Set-Service -Name $service.Key -StartupType $service.Value.StartupType
            Write-Log "Configured service: $($service.Value.Name)" -Level "SUCCESS"
        }
        
        Write-Log "Service configuration completed successfully!" -Level "SUCCESS"
        return $true
    }
    catch {
        Write-Log "Failed to configure services: $_" -Level "ERROR"
        return $false
    }
}

# Add simplified Remove-Bloatware function for compatibility
function Remove-Bloatware {
    param(
        [Parameter(Mandatory=$true)]
        [string]$BloatwareKey
    )
    
    Write-LogMessage "Removing bloatware: $BloatwareKey" -Level "INFO"
    
    # Map keys to actual package names
    $packageMap = @{
        "ms-officehub" = "*Microsoft.Office*"
        "ms-teams" = "*MicrosoftTeams*"
        "ms-todo" = "*Microsoft.Todos*"
        "ms-3dviewer" = "*Microsoft.Microsoft3DViewer*"
        "ms-mixedreality" = "*Microsoft.MixedReality*"
        "ms-onenote" = "*Microsoft.Office.OneNote*"
        "ms-people" = "*Microsoft.People*"
        "ms-wallet" = "*Microsoft.Wallet*"
        "ms-messaging" = "*Microsoft.Messaging*"
        "ms-oneconnect" = "*Microsoft.OneConnect*"
        "bing-weather" = "*Microsoft.BingWeather*"
        "bing-news" = "*Microsoft.BingNews*"
        "bing-finance" = "*Microsoft.BingFinance*"
        "win-alarms" = "*Microsoft.WindowsAlarms*"
        "win-camera" = "*Microsoft.WindowsCamera*"
        "win-mail" = "*microsoft.windowscommunicationsapps*"
        "win-maps" = "*Microsoft.WindowsMaps*"
        "win-feedback" = "*Microsoft.WindowsFeedbackHub*"
        "win-gethelp" = "*Microsoft.GetHelp*"
        "win-getstarted" = "*Microsoft.Getstarted*"
        "win-soundrec" = "*Microsoft.WindowsSoundRecorder*"
        "win-yourphone" = "*Microsoft.YourPhone*"
        "win-print3d" = "*Microsoft.Print3D*"
        "zune-music" = "*Microsoft.ZuneMusic*"
        "zune-video" = "*Microsoft.ZuneVideo*"
        "solitaire" = "*Microsoft.MicrosoftSolitaireCollection*"
        "xbox-apps" = "*Microsoft.Xbox*"
        "candy-crush" = "*king.com.CandyCrush*"
        "spotify-store" = "*SpotifyAB.SpotifyMusic*"
        "facebook" = "*Facebook*"
        "twitter" = "*Twitter*"
        "netflix" = "*Netflix*"
        "disney" = "*Disney*"
        "tiktok" = "*TikTok*"
        "ms-widgets" = "*MicrosoftWindows.Client.WebExperience*"
        "ms-clipchamp" = "*Clipchamp.Clipchamp*"
        "gaming-app" = "*Microsoft.GamingApp*"
        "linkedin" = "*LinkedIn*"
    }
    
    $packageName = $packageMap[$BloatwareKey]
    if (-not $packageName) {
        Write-LogMessage "Unknown bloatware key: $BloatwareKey" -Level "WARNING"
        return $false
    }
    
    try {
        # Remove for all users
        Get-AppxPackage $packageName -AllUsers | Remove-AppxPackage -ErrorAction SilentlyContinue
        # Remove provisioned packages
        Get-AppxProvisionedPackage -Online | Where-Object DisplayName -like $packageName | Remove-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue
        
        Write-LogMessage "Successfully removed: $BloatwareKey" -Level "SUCCESS"
        return $true
    }
    catch {
        Write-LogMessage "Failed to remove $BloatwareKey : $_" -Level "ERROR"
        return $false
    }
}

Export-ModuleMember -Function Set-SystemOptimization, Save-RegistryValue, Save-ServiceState, Restore-RegistryValue, Restore-ServiceState, Optimize-System, Remove-Bloatware, Configure-Services 