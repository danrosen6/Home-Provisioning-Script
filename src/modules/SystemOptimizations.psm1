# System optimization modules for Windows Setup GUI

# Global variables
$script:RegistryBackups = @{}
$script:ServiceBackups = @{}
$script:RegistryChangesRequiringRestart = @()
$script:RestartRequired = $false

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

function Add-RestartRegistryChange {
    param (
        [Parameter(Mandatory=$true)]
        [string]$ChangeDescription
    )
    
    # Add to global registry changes list
    $script:RegistryChangesRequiringRestart += $ChangeDescription
    $script:RestartRequired = $true
    
    # Log the change
    Write-LogMessage "Added registry change requiring restart: $ChangeDescription" -Level "INFO"
}

function Test-ServiceDependency {
    param (
        [Parameter(Mandatory=$true)]
        [string]$ServiceName
    )
    
    try {
        # Get the service
        $service = Get-Service -Name $ServiceName -ErrorAction Stop
        
        # Check if any other services depend on this one
        $dependentServices = Get-Service | Where-Object { $_.ServicesDependedOn | Where-Object { $_.Name -eq $ServiceName } }
        
        if ($dependentServices -and $dependentServices.Count -gt 0) {
            $dependencyList = $dependentServices | ForEach-Object { $_.DisplayName }
            return @{
                HasDependencies = $true
                DependentServices = $dependentServices
                DependencyList = $dependencyList
            }
        } else {
            return @{
                HasDependencies = $false
                DependentServices = @()
                DependencyList = @()
            }
        }
    }
    catch {
        Write-LogMessage "Error checking dependencies for service $ServiceName : $_" -Level "ERROR"
        return @{
            HasDependencies = $false
            DependentServices = @()
            DependencyList = @()
            Error = $_
        }
    }
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
    
    # Track operation in recovery system
    Save-OperationState -OperationType "SystemOptimization" -ItemKey $OptimizationKey -Status "InProgress"

    try {
        switch ($OptimizationKey) {
            # Service optimizations with dependency checks
            "diagtrack" {
                # Check dependencies first
                $dependencyCheck = Test-ServiceDependency -ServiceName "DiagTrack"
                
                if ($dependencyCheck.HasDependencies) {
                    $dependencyMessage = "The following services depend on DiagTrack:`n"
                    $dependencyMessage += ($dependencyCheck.DependencyList -join "`n")
                    $dependencyMessage += "`n`nDisabling DiagTrack may affect these services. Continue anyway?"
                    
                    $result = [System.Windows.Forms.MessageBox]::Show(
                        $dependencyMessage,
                        "Service Dependencies Found",
                        [System.Windows.Forms.MessageBoxButtons]::YesNo,
                        [System.Windows.Forms.MessageBoxIcon]::Warning
                    )
                    
                    if ($result -eq [System.Windows.Forms.DialogResult]::No) {
                        Write-LogMessage "Skipping DiagTrack service due to dependencies" -Level "WARNING"
                        Save-OperationState -OperationType "SystemOptimization" -ItemKey $OptimizationKey -Status "Skipped" -AdditionalData @{
                            Reason = "User opted to skip due to dependencies"
                            Dependencies = $dependencyCheck.DependencyList -join ", "
                        }
                        return $false
                    }
                }
                
                Save-ServiceState -ServiceName "DiagTrack"
                Stop-Service "DiagTrack" -Force -ErrorAction SilentlyContinue
                Set-Service "DiagTrack" -StartupType Disabled
            }
            "dmwappushsvc" {
                # Check dependencies first
                $dependencyCheck = Test-ServiceDependency -ServiceName "dmwappushservice"
                
                if ($dependencyCheck.HasDependencies) {
                    $dependencyMessage = "The following services depend on dmwappushservice:`n"
                    $dependencyMessage += ($dependencyCheck.DependencyList -join "`n")
                    $dependencyMessage += "`n`nDisabling dmwappushservice may affect these services. Continue anyway?"
                    
                    $result = [System.Windows.Forms.MessageBox]::Show(
                        $dependencyMessage,
                        "Service Dependencies Found",
                        [System.Windows.Forms.MessageBoxButtons]::YesNo,
                        [System.Windows.Forms.MessageBoxIcon]::Warning
                    )
                    
                    if ($result -eq [System.Windows.Forms.DialogResult]::No) {
                        Write-LogMessage "Skipping dmwappushservice service due to dependencies" -Level "WARNING"
                        Save-OperationState -OperationType "SystemOptimization" -ItemKey $OptimizationKey -Status "Skipped" -AdditionalData @{
                            Reason = "User opted to skip due to dependencies"
                            Dependencies = $dependencyCheck.DependencyList -join ", "
                        }
                        return $false
                    }
                }
                
                Save-ServiceState -ServiceName "dmwappushservice"
                Stop-Service "dmwappushservice" -Force -ErrorAction SilentlyContinue
                Set-Service "dmwappushservice" -StartupType Disabled
            }
            "sysmain" {
                # Check dependencies first
                $dependencyCheck = Test-ServiceDependency -ServiceName "SysMain"
                
                if ($dependencyCheck.HasDependencies) {
                    $dependencyMessage = "The following services depend on SysMain:`n"
                    $dependencyMessage += ($dependencyCheck.DependencyList -join "`n")
                    $dependencyMessage += "`n`nDisabling SysMain may affect these services. Continue anyway?"
                    
                    $result = [System.Windows.Forms.MessageBox]::Show(
                        $dependencyMessage,
                        "Service Dependencies Found",
                        [System.Windows.Forms.MessageBoxButtons]::YesNo,
                        [System.Windows.Forms.MessageBoxIcon]::Warning
                    )
                    
                    if ($result -eq [System.Windows.Forms.DialogResult]::No) {
                        Write-LogMessage "Skipping SysMain service due to dependencies" -Level "WARNING"
                        Save-OperationState -OperationType "SystemOptimization" -ItemKey $OptimizationKey -Status "Skipped" -AdditionalData @{
                            Reason = "User opted to skip due to dependencies"
                            Dependencies = $dependencyCheck.DependencyList -join ", "
                        }
                        return $false
                    }
                }
                
                Save-ServiceState -ServiceName "SysMain"
                Stop-Service "SysMain" -Force -ErrorAction SilentlyContinue
                Set-Service "SysMain" -StartupType Disabled
            }
            "wmpnetworksvc" {
                $dependencyCheck = Test-ServiceDependency -ServiceName "WMPNetworkSvc"
                
                if ($dependencyCheck.HasDependencies) {
                    $dependencyMessage = "The following services depend on WMPNetworkSvc:`n"
                    $dependencyMessage += ($dependencyCheck.DependencyList -join "`n")
                    $dependencyMessage += "`n`nDisabling WMPNetworkSvc may affect these services. Continue anyway?"
                    
                    $result = [System.Windows.Forms.MessageBox]::Show(
                        $dependencyMessage,
                        "Service Dependencies Found",
                        [System.Windows.Forms.MessageBoxButtons]::YesNo,
                        [System.Windows.Forms.MessageBoxIcon]::Warning
                    )
                    
                    if ($result -eq [System.Windows.Forms.DialogResult]::No) {
                        Write-LogMessage "Skipping WMPNetworkSvc service due to dependencies" -Level "WARNING"
                        Save-OperationState -OperationType "SystemOptimization" -ItemKey $OptimizationKey -Status "Skipped" -AdditionalData @{
                            Reason = "User opted to skip due to dependencies"
                            Dependencies = $dependencyCheck.DependencyList -join ", "
                        }
                        return $false
                    }
                }
                
                Save-ServiceState -ServiceName "WMPNetworkSvc"
                Stop-Service "WMPNetworkSvc" -Force -ErrorAction SilentlyContinue
                Set-Service "WMPNetworkSvc" -StartupType Disabled
            }
            
            # Registry changes that require restart
            "disable-cortana" {
                Save-RegistryValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search" -Name "AllowCortana"
                if (-not (Test-Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search")) {
                    New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search" -Force | Out-Null
                }
                Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search" -Name "AllowCortana" -Value 0
                Add-RestartRegistryChange -ChangeDescription "Disable Cortana"
            }
            "classic-context" {
                if (-not (Test-Path "HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32")) {
                    New-Item -Path "HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32" -Force | Out-Null
                }
                Set-ItemProperty -Path "HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32" -Name "(Default)" -Value "" -Type String
                Add-RestartRegistryChange -ChangeDescription "Restore classic right-click context menu"
            }
            "taskbar-left" {
                if (-not (Test-Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced")) {
                    New-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Force | Out-Null
                }
                Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "TaskbarAl" -Value 0
                Add-RestartRegistryChange -ChangeDescription "Set taskbar alignment to left (classic style)"
            }
            "disable-widgets" {
                if (-not (Test-Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced")) {
                    New-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Force | Out-Null
                }
                Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "TaskbarDa" -Value 0
                
                # Also disable widgets via policies
                try {
                    if (-not (Test-Path "HKLM:\SOFTWARE\Policies\Microsoft\Dsh")) {
                        New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Dsh" -Force | Out-Null
                    }
                    Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Dsh" -Name "AllowNewsAndInterests" -Value 0
                    
                    if (-not (Test-Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Feeds")) {
                        New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Feeds" -Force | Out-Null
                    }
                    Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Feeds" -Name "EnableFeeds" -Value 0
                } catch {
                    Write-LogMessage "Could not disable widgets via policies (may require admin rights): $_" -Level "WARNING"
                }
                
                Add-RestartRegistryChange -ChangeDescription "Disable Widgets icon and service"
            }
            "disable-chat" {
                if (-not (Test-Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced")) {
                    New-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Force | Out-Null
                }
                Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "TaskbarMn" -Value 0
                Add-RestartRegistryChange -ChangeDescription "Disable Chat icon on taskbar"
            }
            "disable-snap" {
                if (-not (Test-Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced")) {
                    New-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Force | Out-Null
                }
                Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "EnableSnapAssistFlyout" -Value 0
                Add-RestartRegistryChange -ChangeDescription "Disable Snap layouts when hovering maximize button"
            }
            
            # Other optimizations - keep the rest of the switch cases from original function
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
            "reduce-telemetry" {
                if (-not (Test-Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection")) {
                    New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" -Force | Out-Null
                }
                Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" -Name "AllowTelemetry" -Value 0
            }
            "disable-onedrive" {
                Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "OneDrive" -ErrorAction SilentlyContinue
            }
            "disable-tips" {
                if (-not (Test-Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager")) {
                    New-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Force | Out-Null
                }
                Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "SubscribedContent-338389Enabled" -Value 0
                Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "SystemPaneSuggestionsEnabled" -Value 0
                Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "SoftLandingEnabled" -Value 0
            }
            "disable-activity" {
                if (-not (Test-Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System")) {
                    New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" -Force | Out-Null
                }
                Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" -Name "EnableActivityFeed" -Value 0
                Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" -Name "PublishUserActivities" -Value 0
            }
            "disable-background" {
                if (-not (Test-Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications")) {
                    New-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications" -Force | Out-Null
                }
                Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications" -Name "GlobalUserDisabled" -Value 1
            }
            "search-bing" {
                if (-not (Test-Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search")) {
                    New-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" -Force | Out-Null
                }
                Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" -Name "BingSearchEnabled" -Value 0
                Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" -Name "CortanaConsent" -Value 0
            }
            "start-menu-pins" {
                if (-not (Test-Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced")) {
                    New-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Force | Out-Null
                }
                Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "Start_Layout" -Value 1
            }
            "disable-teams-autostart" {
                # Disable Teams consumer auto-start
                Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "com.squirrel.Teams.Teams" -ErrorAction SilentlyContinue
                
                # Also try to disable via registry value approach
                try {
                    if (-not (Test-Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run")) {
                        New-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Force | Out-Null
                    }
                    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "com.squirrel.Teams.Teams" -Value 0 -ErrorAction SilentlyContinue
                } catch {
                    # Ignore errors if property doesn't exist
                }
            }
            "disable-startup-sound" {
                if (-not (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\LogonUI\BootAnimation")) {
                    New-Item -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\LogonUI\BootAnimation" -Force | Out-Null
                }
                Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\LogonUI\BootAnimation" -Name "DisableStartupSound" -Value 1
                
                # Also disable boot animation (Windows 11)
                try {
                    if (-not (Test-Path "HKLM:\SYSTEM\CurrentControlSet\Control\BootControl")) {
                        New-Item -Path "HKLM:\SYSTEM\CurrentControlSet\Control\BootControl" -Force | Out-Null
                    }
                    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\BootControl" -Name "BootProgressAnimation" -Value 0
                } catch {
                    Write-LogMessage "Could not disable boot animation (requires admin rights): $_" -Level "WARNING"
                }
            }
            # Additional service configurations
            "printnotify" {
                Save-ServiceState -ServiceName "PrintNotify"
                Stop-Service "PrintNotify" -Force -ErrorAction SilentlyContinue
                Set-Service "PrintNotify" -StartupType Disabled
            }
            "wisvc" {
                Save-ServiceState -ServiceName "wisvc"
                Stop-Service "wisvc" -Force -ErrorAction SilentlyContinue
                Set-Service "wisvc" -StartupType Disabled
            }
            "retaildemo" {
                Save-ServiceState -ServiceName "RetailDemo"
                Stop-Service "RetailDemo" -Force -ErrorAction SilentlyContinue
                Set-Service "RetailDemo" -StartupType Disabled
            }
            "mapsbroker" {
                Save-ServiceState -ServiceName "MapsBroker"
                Stop-Service "MapsBroker" -Force -ErrorAction SilentlyContinue
                Set-Service "MapsBroker" -StartupType Disabled
            }
            "pcasvc" {
                Save-ServiceState -ServiceName "PcaSvc"
                Stop-Service "PcaSvc" -Force -ErrorAction SilentlyContinue
                Set-Service "PcaSvc" -StartupType Disabled
            }
            "wpcmonsvc" {
                Save-ServiceState -ServiceName "WpcMonSvc"
                Stop-Service "WpcMonSvc" -Force -ErrorAction SilentlyContinue
                Set-Service "WpcMonSvc" -StartupType Disabled
            }
            "cscservice" {
                Save-ServiceState -ServiceName "CscService"
                Stop-Service "CscService" -Force -ErrorAction SilentlyContinue
                Set-Service "CscService" -StartupType Disabled
            }
            "lfsvc" {
                Save-ServiceState -ServiceName "lfsvc"
                Stop-Service "lfsvc" -Force -ErrorAction SilentlyContinue
                Set-Service "lfsvc" -StartupType Disabled
            }
            "tabletinputservice" {
                Save-ServiceState -ServiceName "TabletInputService"
                Stop-Service "TabletInputService" -Force -ErrorAction SilentlyContinue
                Set-Service "TabletInputService" -StartupType Disabled
            }
            "homegrpservice" {
                Save-ServiceState -ServiceName "HomeGroupProvider"
                Stop-Service "HomeGroupProvider" -Force -ErrorAction SilentlyContinue
                Set-Service "HomeGroupProvider" -StartupType Disabled
            }
            "walletservice" {
                Save-ServiceState -ServiceName "WalletService"
                Stop-Service "WalletService" -Force -ErrorAction SilentlyContinue
                Set-Service "WalletService" -StartupType Disabled
            }
            
            # Windows 11 specific optimizations
            "start-menu-pins" {
                if (-not (Test-Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced")) {
                    New-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Force | Out-Null
                }
                Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "Start_Layout" -Value 1
                Add-RestartRegistryChange -ChangeDescription "Configure Start menu layout"
            }
            
            # Windows 10 specific optimizations
            "hide-taskview" {
                if (-not (Test-Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced")) {
                    New-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Force | Out-Null
                }
                Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "ShowTaskViewButton" -Value 0
            }
            "hide-cortana-button" {
                if (-not (Test-Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Taskband")) {
                    New-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Taskband" -Force | Out-Null
                }
                Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Taskband" -Name "ShowCortanaButton" -Value 0
            }
            "configure-searchbox" {
                if (-not (Test-Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search")) {
                    New-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" -Force | Out-Null
                }
                # SearchboxTaskbarMode: 0 = Hidden, 1 = Show search icon, 2 = Show search box
                Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" -Name "SearchboxTaskbarMode" -Value 2
            }
            
            # General interface optimizations
            "dark-theme" {
                if (-not (Test-Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize")) {
                    New-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" -Force | Out-Null
                }
                Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" -Name "AppsUseLightTheme" -Value 0
                Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" -Name "SystemUsesLightTheme" -Value 0
            }
            "disable-quickaccess" {
                if (-not (Test-Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer")) {
                    New-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer" -Force | Out-Null
                }
                Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer" -Name "ShowFrequent" -Value 0
                Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer" -Name "ShowRecent" -Value 0
            }
            default {
                Write-LogMessage "Unknown optimization key: ${OptimizationKey}" -Level "WARNING"
                Save-OperationState -OperationType "SystemOptimization" -ItemKey $OptimizationKey -Status "Failed" -AdditionalData @{
                    Error = "Unknown optimization key"
                    Time = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                }
                return $false
            }
        }

        Write-LogMessage "Successfully applied optimization: ${OptimizationKey}" -Level "SUCCESS"
        Save-OperationState -OperationType "SystemOptimization" -ItemKey $OptimizationKey -Status "Completed"
        return $true
    }
    catch {
        Write-LogMessage "Failed to apply optimization ${OptimizationKey}: $_" -Level "ERROR"
        Save-OperationState -OperationType "SystemOptimization" -ItemKey $OptimizationKey -Status "Failed" -AdditionalData @{
            Error = $_.Exception.Message
            Time = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        }
        
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

# Unified Remove-Bloatware function that handles both direct calls and batch removals
function Remove-Bloatware {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, ParameterSetName="Key")]
        [string]$BloatwareKey,
        
        [Parameter(Mandatory=$true, ParameterSetName="List")]
        [string[]]$Bloatware,
        
        [Parameter(Mandatory=$false)]
        [System.Threading.CancellationToken]$CancellationToken
    )
    
    # Map keys to actual package names and wildcard patterns
    $packageMap = @{
        "ms-officehub" = "Microsoft.MicrosoftOfficeHub"
        "ms-teams" = "Microsoft.MicrosoftTeams"
        "ms-teams-consumer" = "MicrosoftTeams"
        "ms-todo" = "*.Todos*"
        "ms-3dviewer" = "Microsoft.Microsoft3DViewer"
        "ms-mixedreality" = "Microsoft.MixedReality.Portal"
        "ms-onenote" = "Microsoft.Office.OneNote"
        "ms-people" = "Microsoft.People"
        "ms-wallet" = "Microsoft.Wallet"
        "ms-messaging" = "Microsoft.Messaging"
        "ms-oneconnect" = "Microsoft.OneConnect"
        "ms-skype" = "Microsoft.SkypeApp"
        "bing-weather" = "Microsoft.BingWeather"
        "bing-news" = "Microsoft.BingNews"
        "bing-finance" = "Microsoft.BingFinance"
        "win-alarms" = "Microsoft.WindowsAlarms"
        "win-camera" = "Microsoft.WindowsCamera"
        "win-mail" = "Microsoft.WindowsCommunicationsApps"
        "win-maps" = "Microsoft.WindowsMaps"
        "win-feedback" = "Microsoft.WindowsFeedbackHub"
        "win-gethelp" = "Microsoft.GetHelp"
        "win-getstarted" = "Microsoft.Getstarted"
        "win-soundrec" = "Microsoft.WindowsSoundRecorder"
        "win-yourphone" = "Microsoft.YourPhone"
        "win-print3d" = "Microsoft.Print3D"
        "zune-music" = "Microsoft.ZuneMusic"
        "zune-video" = "Microsoft.ZuneVideo"
        "solitaire" = "Microsoft.MicrosoftSolitaireCollection"
        "gaming-app" = "Microsoft.GamingApp"
        "xbox-gameoverlay" = "Microsoft.XboxGameOverlay"
        "xbox-gamingoverlay" = "Microsoft.XboxGamingOverlay"
        "xbox-identity" = "Microsoft.XboxIdentityProvider"
        "xbox-speech" = "Microsoft.XboxSpeechToTextOverlay"
        "xbox-tcui" = "Microsoft.Xbox.TCUI"
        "candy-crush" = "*.CandyCrush*"
        "spotify-store" = "*.Spotify*"
        "facebook" = "*.Facebook*"
        "twitter" = "*.Twitter*"
        "netflix" = "*.Netflix*"
        "hulu" = "*.Hulu*"
        "picsart" = "*.PicsArt*"
        "disney" = "*.Disney*"
        "tiktok" = "*.TikTok*"
        "ms-widgets" = "MicrosoftWindows.Client.WebExperience"
        "ms-clipchamp" = "*.ClipChamp*"
        "linkedin" = "*.LinkedIn*"
    }
    
    Write-LogMessage "Starting bloatware removal..." -Level "INFO"
    
    # Check for cancellation
    if ($CancellationToken -and $CancellationToken.IsCancellationRequested) {
        Write-LogMessage "Bloatware removal cancelled" -Level "WARNING"
        return $false
    }
    
    try {
        # Track operation in recovery system
        if ($PSCmdlet.ParameterSetName -eq "Key") {
            Save-OperationState -OperationType "RemoveBloatware" -ItemKey $BloatwareKey -Status "InProgress"
        }
        
        # Handle different parameter sets
        if ($PSCmdlet.ParameterSetName -eq "Key") {
            # Single package removal using key
            $packageName = $packageMap[$BloatwareKey]
            if (-not $packageName) {
                Write-LogMessage "Unknown bloatware key: $BloatwareKey" -Level "WARNING"
                Save-OperationState -OperationType "RemoveBloatware" -ItemKey $BloatwareKey -Status "Failed" -AdditionalData @{
                    Error = "Unknown bloatware key"
                    Time = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                }
                return $false
            }
            
            Write-LogMessage "Removing bloatware: $BloatwareKey" -Level "INFO"
            
            # Check if packages exist first (handle both exact names and wildcard patterns)
            if ($packageName -like "*`**") {
                # Wildcard pattern - use -like matching
                $installedPackages = Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue | Where-Object { $_.Name -like $packageName }
                $provisionedPackages = Get-AppxProvisionedPackage -Online | Where-Object { $_.DisplayName -like $packageName }
            } else {
                # Exact name matching
                $installedPackages = Get-AppxPackage -Name $packageName -AllUsers -ErrorAction SilentlyContinue
                $provisionedPackages = Get-AppxProvisionedPackage -Online | Where-Object { $_.DisplayName -eq $packageName }
            }
            
            $removedCount = 0
            
            # Remove installed packages for all users (using proven method from independent scripts)
            if ($installedPackages) {
                Write-LogMessage "Found $($installedPackages.Count) installed package(s): $packageName" -Level "INFO"
                try {
                    $installedPackages | Remove-AppxPackage -ErrorAction SilentlyContinue
                    $removedCount += $installedPackages.Count
                    Write-LogMessage "Removed AppxPackage: $packageName" -Level "INFO"
                } catch {
                    Write-LogMessage "Failed to remove AppxPackage $packageName - ${_}" -Level "WARNING"
                }
            }
            
            # Remove provisioned packages (using proven method from independent scripts)
            if ($provisionedPackages) {
                Write-LogMessage "Found $($provisionedPackages.Count) provisioned package(s): $packageName" -Level "INFO"
                try {
                    $provisionedPackages | Remove-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue
                    $removedCount += $provisionedPackages.Count
                    Write-LogMessage "Removed AppxProvisionedPackage: $packageName" -Level "INFO"
                } catch {
                    Write-LogMessage "Failed to remove AppxProvisionedPackage $packageName - ${_}" -Level "WARNING"
                }
            }
            
            # Special handling for Windows 11 Widgets
            if ($BloatwareKey -eq "ms-widgets") {
                Write-LogMessage "Applying Windows 11 Widgets registry tweaks..." -Level "INFO"
                try {
                    # Disable Widgets in taskbar
                    if (-not (Test-Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced")) {
                        New-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Force | Out-Null
                    }
                    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "TaskbarDa" -Value 0 -Type DWord -Force
                    
                    # Disable News and Interests
                    if (-not (Test-Path "HKLM:\SOFTWARE\Policies\Microsoft\Dsh")) {
                        New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Dsh" -Force | Out-Null
                    }
                    Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Dsh" -Name "AllowNewsAndInterests" -Value 0 -Type DWord -Force
                    
                    # Disable Windows Feeds
                    if (-not (Test-Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Feeds")) {
                        New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Feeds" -Force | Out-Null
                    }
                    Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Feeds" -Name "EnableFeeds" -Value 0 -Type DWord -Force
                    
                    Write-LogMessage "Windows 11 Widgets registry tweaks applied successfully" -Level "SUCCESS"
                    $removedCount++
                } catch {
                    Write-LogMessage "Failed to apply Widgets registry tweaks: $_" -Level "WARNING"
                }
            }
            
            if ($removedCount -gt 0) {
                Write-LogMessage "Successfully removed $removedCount package(s) for: $BloatwareKey" -Level "SUCCESS"
            } else {
                Write-LogMessage "No packages found matching pattern $packageName for: $BloatwareKey" -Level "WARNING"
            }
            Save-OperationState -OperationType "RemoveBloatware" -ItemKey $BloatwareKey -Status "Completed"
            return $true
        }
        else {
            # Multiple package removal from list
            foreach ($app in $Bloatware) {
                if ($CancellationToken -and $CancellationToken.IsCancellationRequested) {
                    Write-LogMessage "Bloatware removal cancelled" -Level "WARNING"
                    return $false
                }
                
                Write-LogMessage "Removing $app..." -Level "INFO"
                Get-AppxPackage -Name $app -AllUsers | Remove-AppxPackage -ErrorAction SilentlyContinue
                Get-AppxProvisionedPackage -Online | Where-Object DisplayName -like $app | Remove-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue
                Write-LogMessage "Removed $app" -Level "SUCCESS"
            }
            
            Write-LogMessage "Bloatware removal completed successfully!" -Level "SUCCESS"
            return $true
        }
    }
    catch {
        if ($PSCmdlet.ParameterSetName -eq "Key") {
            Save-OperationState -OperationType "RemoveBloatware" -ItemKey $BloatwareKey -Status "Failed" -AdditionalData @{
                Error = $_.Exception.Message
                Time = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            }
        }
        Write-LogMessage "Failed to remove bloatware: $_" -Level "ERROR"
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
    
    Write-LogMessage "Starting system optimization..." -Level "INFO"
    
    # Check for cancellation
    if ($CancellationToken.IsCancellationRequested) {
        Write-LogMessage "System optimization cancelled" -Level "WARNING"
        return $false
    }
    
    try {
        # Disable Telemetry
        if ($Optimizations.DisableTelemetry) {
            Write-LogMessage "Disabling Windows Telemetry..." -Level "INFO"
            Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" -Name "AllowTelemetry" -Value 0
            Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection" -Name "AllowTelemetry" -Value 0
            Write-LogMessage "Windows Telemetry disabled" -Level "SUCCESS"
        }
        
        # Disable Cortana
        if ($Optimizations.DisableCortana) {
            Write-LogMessage "Disabling Cortana..." -Level "INFO"
            Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search" -Name "AllowCortana" -Value 0
            Write-LogMessage "Cortana disabled" -Level "SUCCESS"
        }
        
        # Disable Windows Search
        if ($Optimizations.DisableWindowsSearch) {
            Write-LogMessage "Disabling Windows Search..." -Level "INFO"
            Stop-Service "WSearch" -Force
            Set-Service "WSearch" -StartupType Disabled
            Write-LogMessage "Windows Search disabled" -Level "SUCCESS"
        }
        
        # Disable Windows Update
        if ($Optimizations.DisableWindowsUpdate) {
            Write-LogMessage "Disabling Windows Update..." -Level "INFO"
            Stop-Service "wuauserv" -Force
            Set-Service "wuauserv" -StartupType Disabled
            Write-LogMessage "Windows Update disabled" -Level "SUCCESS"
        }
        
        # Disable Windows Defender
        if ($Optimizations.DisableDefender) {
            Write-LogMessage "Disabling Windows Defender..." -Level "INFO"
            Set-MpPreference -DisableRealtimeMonitoring $true
            Set-MpPreference -DisableIOAVProtection $true
            Write-LogMessage "Windows Defender disabled" -Level "SUCCESS"
        }
        
        # Disable Windows Firewall
        if ($Optimizations.DisableFirewall) {
            Write-LogMessage "Disabling Windows Firewall..." -Level "INFO"
            Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled False
            Write-LogMessage "Windows Firewall disabled" -Level "SUCCESS"
        }
        
        Write-LogMessage "System optimization completed successfully!" -Level "SUCCESS"
        return $true
    }
    catch {
        Write-LogMessage "Failed to optimize system: $_" -Level "ERROR"
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
    
    Write-LogMessage "Starting service configuration..." -Level "INFO"
    
    # Check for cancellation
    if ($CancellationToken.IsCancellationRequested) {
        Write-LogMessage "Service configuration cancelled" -Level "WARNING"
        return $false
    }
    
    try {
        foreach ($service in $Services.GetEnumerator()) {
            Write-LogMessage "Configuring service: $($service.Value.Name)..." -Level "INFO"
            
            # Check for service dependencies
            $dependencyCheck = Test-ServiceDependency -ServiceName $service.Key
            
            if ($dependencyCheck.HasDependencies) {
                $dependencyMessage = "The following services depend on $($service.Value.Name):`n"
                $dependencyMessage += ($dependencyCheck.DependencyList -join "`n")
                $dependencyMessage += "`n`nConfiguring $($service.Value.Name) may affect these services. Continue anyway?"
                
                $result = [System.Windows.Forms.MessageBox]::Show(
                    $dependencyMessage,
                    "Service Dependencies Found",
                    [System.Windows.Forms.MessageBoxButtons]::YesNo,
                    [System.Windows.Forms.MessageBoxIcon]::Warning
                )
                
                if ($result -eq [System.Windows.Forms.DialogResult]::No) {
                    Write-LogMessage "Skipping $($service.Value.Name) service configuration due to dependencies" -Level "WARNING"
                    continue
                }
            }
            
            Set-Service -Name $service.Key -StartupType $service.Value.StartupType
            Write-LogMessage "Configured service: $($service.Value.Name)" -Level "SUCCESS"
        }
        
        Write-LogMessage "Service configuration completed successfully!" -Level "SUCCESS"
        return $true
    }
    catch {
        Write-LogMessage "Failed to configure services: $_" -Level "ERROR"
        return $false
    }
}

# Export updated functions
Export-ModuleMember -Function Set-SystemOptimization, Save-RegistryValue, Save-ServiceState, Restore-RegistryValue, Restore-ServiceState, Optimize-System, Remove-Bloatware, Configure-Services, Test-ServiceDependency, Add-RestartRegistryChange