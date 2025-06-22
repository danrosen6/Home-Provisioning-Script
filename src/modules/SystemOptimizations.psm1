# System optimization modules for Windows Setup GUI

# Global variables
$script:RegistryBackups = @{}
$script:ServiceBackups = @{}
$script:RegistryChangesRequiringRestart = @()
$script:RestartRequired = $false
$script:ExplorerRestartRequired = $false
$script:IsAdministrator = $null

# Timeout-based MessageBox function to prevent script hanging
function Show-TimeoutMessageBox {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,
        
        [Parameter(Mandatory=$false)]
        [string]$Title = "Confirmation",
        
        [Parameter(Mandatory=$false)]
        [int]$TimeoutSeconds = 30,
        
        [Parameter(Mandatory=$false)]
        [string]$DefaultResponse = "Yes"
    )
    
    try {
        # Create a runspace for the timeout
        $runspace = [runspacefactory]::CreateRunspace()
        $runspace.Open()
        
        # Create PowerShell instance
        $powershell = [powershell]::Create()
        $powershell.Runspace = $runspace
        
        # Add script to show MessageBox
        $script = {
            param($msg, $title)
            Add-Type -AssemblyName System.Windows.Forms
            return [System.Windows.Forms.MessageBox]::Show(
                $msg, 
                $title, 
                [System.Windows.Forms.MessageBoxButtons]::YesNo,
                [System.Windows.Forms.MessageBoxIcon]::Warning
            )
        }
        
        $powershell.AddScript($script)
        $powershell.AddParameter("msg", $Message)
        $powershell.AddParameter("title", $Title)
        
        # Start async execution
        $asyncResult = $powershell.BeginInvoke()
        
        # Wait for completion or timeout
        $completed = $asyncResult.AsyncWaitHandle.WaitOne(($TimeoutSeconds * 1000))
        
        if ($completed) {
            # Get result
            $result = $powershell.EndInvoke($asyncResult)
            $powershell.Dispose()
            $runspace.Dispose()
            
            return $result
        } else {
            # Timeout occurred
            Write-LogMessage "MessageBox timed out after $TimeoutSeconds seconds, using default response: $DefaultResponse" -Level "WARNING"
            
            # Clean up
            $powershell.Stop()
            $powershell.Dispose()
            $runspace.Dispose()
            
            # Return default response
            if ($DefaultResponse -eq "Yes") {
                return [System.Windows.Forms.DialogResult]::Yes
            } else {
                return [System.Windows.Forms.DialogResult]::No
            }
        }
    }
    catch {
        Write-LogMessage "Error showing timeout MessageBox: $_" -Level "ERROR"
        # Return safe default (No) on error
        return [System.Windows.Forms.DialogResult]::No
    }
}

# Import the centralized logging system
$LoggingModule = Join-Path (Join-Path (Split-Path $PSScriptRoot -Parent) "utils") "Logging.psm1"
if (Test-Path $LoggingModule) {
    Import-Module $LoggingModule -Force -Global
    Write-Verbose "Imported centralized logging module"
} else {
    # Fallback Write-LogMessage function if centralized logging is not available
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
        
        # Write to console with color
        $color = switch ($Level) {
            "ERROR" { "Red" }
            "WARNING" { "Yellow" }
            "SUCCESS" { "Green" }
            "DEBUG" { "Gray" }
            default { "White" }
        }
        Write-Host $logMessage -ForegroundColor $color
    }
    Write-Warning "Centralized logging module not found, using fallback logging"
}

function Test-IsAdministrator {
    if ($script:IsAdministrator -eq $null) {
        $script:IsAdministrator = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    return $script:IsAdministrator
}

function Add-ExplorerRestartChange {
    param (
        [Parameter(Mandatory=$true)]
        [string]$ChangeDescription
    )
    
    # Mark that Explorer restart is required
    $script:ExplorerRestartRequired = $true
    
    # Log the change
    Write-LogMessage "Added Explorer restart change: $ChangeDescription" -Level "INFO"
}

function Restart-WindowsExplorer {
    param (
        [Parameter(Mandatory=$false)]
        [switch]$Force = $false
    )
    
    if (-not $Force -and -not $script:ExplorerRestartRequired) {
        Write-LogMessage "No Explorer restart required" -Level "INFO"
        return $true
    }
    
    try {
        Write-LogMessage "Restarting Windows Explorer to apply UI changes..." -Level "INFO"
        
        # Stop Explorer process
        Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        
        # Start Explorer process
        Start-Process explorer -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 1
        
        Write-LogMessage "Windows Explorer restarted successfully" -Level "SUCCESS"
        $script:ExplorerRestartRequired = $false
        return $true
    } catch {
        Write-LogMessage "Could not restart explorer automatically: $_" -Level "WARNING"
        Write-LogMessage "Please manually restart explorer.exe or log off/on to see UI changes" -Level "INFO"
        return $false
    }
}

function Set-ProtectedRegistryValue {
    param (
        [Parameter(Mandatory=$true)]
        [string]$Path,
        
        [Parameter(Mandatory=$true)]
        [string]$Name,
        
        [Parameter(Mandatory=$true)]
        [object]$Value,
        
        [Parameter(Mandatory=$false)]
        [string]$Type = "DWord",
        
        [Parameter(Mandatory=$false)]
        [switch]$RequireAdmin = $false
    )
    
    # Check admin requirements
    if ($RequireAdmin -and -not (Test-IsAdministrator)) {
        Write-LogMessage "Admin privileges required to modify $Path\$Name" -Level "WARNING"
        return $false
    }
    
    try {
        # Try PowerShell method first
        if (-not (Test-Path $Path)) {
            New-Item -Path $Path -Force | Out-Null
        }
        Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type $Type -Force -ErrorAction Stop
        
        # Verify the change was successful
        $verification = Get-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue
        if ($verification -and $verification.$Name -eq $Value) {
            Write-LogMessage "Successfully set $Path\$Name = $Value via PowerShell" -Level "SUCCESS"
            return $true
        } else {
            throw "Value verification failed after PowerShell set operation"
        }
    } catch {
        Write-LogMessage "PowerShell method failed for $Path\$Name : $_" -Level "WARNING"
        
        # Try cmd reg command for protected keys
        if (Test-IsAdministrator) {
            try {
                $regPath = $Path -replace "HKCU:", "HKEY_CURRENT_USER" -replace "HKLM:", "HKEY_LOCAL_MACHINE"
                $regType = switch ($Type) {
                    "DWord" { "REG_DWORD" }
                    "String" { "REG_SZ" }
                    "Binary" { "REG_BINARY" }
                    "ExpandString" { "REG_EXPAND_SZ" }
                    default { "REG_DWORD" }
                }
                
                & cmd /c "reg add `"$regPath`" /v `"$Name`" /t $regType /d `"$Value`" /f" 2>$null
                
                # Verify the change
                $currentValue = Get-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue
                if ($currentValue -and $currentValue.$Name -eq $Value) {
                    Write-LogMessage "Successfully set $Path\$Name = $Value via cmd reg" -Level "SUCCESS"
                    return $true
                } else {
                    Write-LogMessage "cmd reg command failed to set $Path\$Name" -Level "ERROR"
                    return $false
                }
            } catch {
                Write-LogMessage "cmd reg method also failed: $_" -Level "ERROR"
                return $false
            }
        } else {
            Write-LogMessage "Cannot use cmd reg method - not running as Administrator" -Level "WARNING"
            return $false
        }
    }
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
        [System.Threading.CancellationToken]$CancellationToken = [System.Threading.CancellationToken]::None
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
                    
                    $result = Show-TimeoutMessageBox -Message $dependencyMessage -Title "Service Dependencies Found" -TimeoutSeconds 30 -DefaultResponse "No"
                    
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
                # Try both service names - primary and alternate
                $serviceNames = @("dmwappushservice", "dmwappushsvc")
                $actualServiceName = $null
                
                # Find which service name exists
                foreach ($serviceName in $serviceNames) {
                    try {
                        $service = Get-Service -Name $serviceName -ErrorAction Stop
                        if ($service) {
                            $actualServiceName = $serviceName
                            Write-LogMessage "Found service with name: $actualServiceName (Display: $($service.DisplayName))" -Level "INFO"
                            break
                        }
                    } catch {
                        # Service not found with this name, try next
                        Write-LogMessage "Service '$serviceName' not found, trying next..." -Level "DEBUG"
                    }
                }
                
                if (-not $actualServiceName) {
                    Write-LogMessage "Service dmwappushservice/dmwappushsvc not found on this system - this is normal on some Windows versions" -Level "WARNING"
                    Save-OperationState -OperationType "SystemOptimization" -ItemKey $OptimizationKey -Status "Skipped" -AdditionalData @{
                        Reason = "Service not found on this system"
                        SearchedNames = $serviceNames -join ", "
                    }
                    return $true  # Return true since this is expected behavior, not a failure
                }
                
                # Check dependencies first
                $dependencyCheck = Test-ServiceDependency -ServiceName $actualServiceName
                
                if ($dependencyCheck.HasDependencies) {
                    $dependencyMessage = "The following services depend on $actualServiceName :`n"
                    $dependencyMessage += ($dependencyCheck.DependencyList -join "`n")
                    $dependencyMessage += "`n`nDisabling $actualServiceName may affect these services. Continue anyway?"
                    
                    $result = Show-TimeoutMessageBox -Message $dependencyMessage -Title "Service Dependencies Found" -TimeoutSeconds 30 -DefaultResponse "No"
                    
                    if ($result -eq [System.Windows.Forms.DialogResult]::No) {
                        Write-LogMessage "Skipping $actualServiceName service due to dependencies" -Level "WARNING"
                        Save-OperationState -OperationType "SystemOptimization" -ItemKey $OptimizationKey -Status "Skipped" -AdditionalData @{
                            Reason = "User opted to skip due to dependencies"
                            Dependencies = $dependencyCheck.DependencyList -join ", "
                        }
                        return $false
                    }
                }
                
                Save-ServiceState -ServiceName $actualServiceName
                Stop-Service $actualServiceName -Force -ErrorAction SilentlyContinue
                Set-Service $actualServiceName -StartupType Disabled
            }
            "sysmain" {
                # Check dependencies first
                $dependencyCheck = Test-ServiceDependency -ServiceName "SysMain"
                
                if ($dependencyCheck.HasDependencies) {
                    $dependencyMessage = "The following services depend on SysMain:`n"
                    $dependencyMessage += ($dependencyCheck.DependencyList -join "`n")
                    $dependencyMessage += "`n`nDisabling SysMain may affect these services. Continue anyway?"
                    
                    $result = Show-TimeoutMessageBox -Message $dependencyMessage -Title "Service Dependencies Found" -TimeoutSeconds 30 -DefaultResponse "No"
                    
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
                    
                    $result = Show-TimeoutMessageBox -Message $dependencyMessage -Title "Service Dependencies Found" -TimeoutSeconds 30 -DefaultResponse "No"
                    
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
                # Ensure registry path exists before trying to backup
                if (-not (Test-Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search")) {
                    New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search" -Force | Out-Null
                }
                # Backup existing value before modification
                Save-RegistryValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search" -Name "AllowCortana"
                # Apply the change
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
                if (Set-ProtectedRegistryValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "TaskbarAl" -Value 0 -Type "DWord") {
                    Add-ExplorerRestartChange -ChangeDescription "Set taskbar alignment to left (classic style)"
                }
            }
            "disable-widgets" {
                $success = $false
                
                # Disable widgets taskbar button
                if (Set-ProtectedRegistryValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "TaskbarDa" -Value 0 -Type "DWord") {
                    $success = $true
                }
                
                # Also disable widgets via policies (requires admin)
                if (Test-IsAdministrator) {
                    Set-ProtectedRegistryValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Dsh" -Name "AllowNewsAndInterests" -Value 0 -Type "DWord" -RequireAdmin | Out-Null
                    Set-ProtectedRegistryValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Feeds" -Name "EnableFeeds" -Value 0 -Type "DWord" -RequireAdmin | Out-Null
                }
                
                if ($success) {
                    Add-ExplorerRestartChange -ChangeDescription "Disable Widgets icon and service"
                }
            }
            "disable-chat" {
                if (Set-ProtectedRegistryValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "TaskbarMn" -Value 0 -Type "DWord") {
                    Add-ExplorerRestartChange -ChangeDescription "Disable Chat icon on taskbar"
                }
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
            "show-system-files" {
                if (-not (Test-Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced")) {
                    New-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Force | Out-Null
                }
                Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "ShowSuperHidden" -Value 1 -Type DWord
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
                Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "OneDriveSetup" -ErrorAction SilentlyContinue
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
            "disable-advertising-id" {
                if (-not (Test-Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo")) {
                    New-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo" -Force | Out-Null
                }
                Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo" -Name "Enabled" -Value 0 -Type DWord
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
                # Disable Teams consumer auto-start by removing the registry entry
                Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "com.squirrel.Teams.Teams" -ErrorAction SilentlyContinue
            }
            "disable-startup-sound" {
                # Disable startup sound as specified in tweaks.json
                if (-not (Test-Path "HKCU:\AppEvents\EventLabels\WindowsLogon")) {
                    New-Item -Path "HKCU:\AppEvents\EventLabels\WindowsLogon" -Force | Out-Null
                }
                Set-ItemProperty -Path "HKCU:\AppEvents\EventLabels\WindowsLogon" -Name "ExcludeFromCPL" -Value 1 -Type DWord
                
                # Also try the alternative method for better compatibility
                try {
                    if (-not (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\LogonUI\BootAnimation")) {
                        New-Item -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\LogonUI\BootAnimation" -Force | Out-Null
                    }
                    Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\LogonUI\BootAnimation" -Name "DisableStartupSound" -Value 1 -Type DWord
                } catch {
                    Write-LogMessage "Could not apply alternative startup sound disable (may require admin rights): $_" -Level "WARNING"
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
            "wsearch" {
                Save-ServiceState -ServiceName "WSearch"
                Stop-Service "WSearch" -Force -ErrorAction SilentlyContinue
                Set-Service "WSearch" -StartupType Disabled
            }
            "cscservice" {
                $service = Get-Service -Name "CscService" -ErrorAction SilentlyContinue
                if ($service) {
                    Save-ServiceState -ServiceName "CscService"
                    Stop-Service "CscService" -Force -ErrorAction SilentlyContinue
                    Set-Service "CscService" -StartupType Disabled
                } else {
                    Write-LogMessage "Service CscService not found on this system (may not be available on this Windows version)" -Level "WARNING"
                }
            }
            "lfsvc" {
                # Enhanced location services disable with comprehensive privacy settings
                Write-LogMessage "Disabling location services comprehensively..." -Level "INFO"
                
                $service = Get-Service -Name "lfsvc" -ErrorAction SilentlyContinue
                if ($service) {
                    Save-ServiceState -ServiceName "lfsvc"
                    Stop-Service "lfsvc" -Force -ErrorAction SilentlyContinue
                    Set-Service "lfsvc" -StartupType Disabled
                    Write-LogMessage "Disabled lfsvc (Geolocation Service)" -Level "INFO"
                } else {
                    Write-LogMessage "Geolocation Service (lfsvc) not found on this system" -Level "WARNING"
                }
                
                # System-wide location disable via Group Policy
                try {
                    if (-not (Test-Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors")) {
                        New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors" -Force | Out-Null
                    }
                    Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors" -Name "DisableLocation" -Value 1 -Type DWord -Force
                    Write-LogMessage "Applied Group Policy location disable" -Level "INFO"
                } catch {
                    Write-LogMessage "Could not apply Group Policy location disable: $_" -Level "WARNING"
                }
                
                # Capability Access Manager - Location
                try {
                    if (-not (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location")) {
                        New-Item -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location" -Force | Out-Null
                    }
                    Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location" -Name "Value" -Value "Deny" -Type String -Force
                    Write-LogMessage "Set Capability Access Manager to deny location access" -Level "INFO"
                } catch {
                    Write-LogMessage "Could not set Capability Access Manager location setting: $_" -Level "WARNING"
                }
                
                # User-level location privacy settings
                try {
                    if (-not (Test-Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\DeviceAccess\Global\{BFA794E4-F964-4FDB-90F6-51056BFE4B44}")) {
                        New-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\DeviceAccess\Global\{BFA794E4-F964-4FDB-90F6-51056BFE4B44}" -Force | Out-Null
                    }
                    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\DeviceAccess\Global\{BFA794E4-F964-4FDB-90F6-51056BFE4B44}" -Name "Value" -Value "Deny" -Type String -Force
                    Write-LogMessage "Set user-level location access to deny" -Level "INFO"
                } catch {
                    Write-LogMessage "Could not set user-level location access: $_" -Level "WARNING"
                }
                
                # Disable location scripting
                try {
                    if (-not (Test-Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\DeviceAccess\Global\LooselyCoupled")) {
                        New-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\DeviceAccess\Global\LooselyCoupled" -Force | Out-Null
                    }
                    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\DeviceAccess\Global\LooselyCoupled" -Name "Value" -Value "Deny" -Type String -Force
                    Write-LogMessage "Disabled location scripting access" -Level "INFO"
                } catch {
                    Write-LogMessage "Could not disable location scripting: $_" -Level "WARNING"
                }
            }
            "tabletinputservice" {
                Save-ServiceState -ServiceName "TabletInputService"
                Stop-Service "TabletInputService" -Force -ErrorAction SilentlyContinue
                Set-Service "TabletInputService" -StartupType Disabled
            }
            "homegrpservice" {
                $service = Get-Service -Name "HomeGroupProvider" -ErrorAction SilentlyContinue
                if ($service) {
                    Save-ServiceState -ServiceName "HomeGroupProvider"
                    Stop-Service "HomeGroupProvider" -Force -ErrorAction SilentlyContinue
                    Set-Service "HomeGroupProvider" -StartupType Disabled
                } else {
                    Write-LogMessage "Service HomeGroupProvider not found on this system (HomeGroup was removed in Windows 10 1803+)" -Level "WARNING"
                }
            }
            "walletservice" {
                $service = Get-Service -Name "WalletService" -ErrorAction SilentlyContinue
                if ($service) {
                    Save-ServiceState -ServiceName "WalletService"
                    Stop-Service "WalletService" -Force -ErrorAction SilentlyContinue
                    Set-Service "WalletService" -StartupType Disabled
                } else {
                    Write-LogMessage "Service WalletService not found on this system (may not be available on this Windows version)" -Level "WARNING"
                }
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
                if (Set-ProtectedRegistryValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "ShowTaskViewButton" -Value 0 -Type "DWord") {
                    Add-ExplorerRestartChange -ChangeDescription "Hide Task View button from taskbar"
                }
            }
            "hide-cortana-button" {
                if (Set-ProtectedRegistryValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Taskband" -Name "ShowCortanaButton" -Value 0 -Type "DWord") {
                    Add-ExplorerRestartChange -ChangeDescription "Hide Cortana button from taskbar"
                }
            }
            "configure-searchbox" {
                # SearchboxTaskbarMode: 0 = Hidden, 1 = Show search icon, 2 = Show search box
                if (Set-ProtectedRegistryValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" -Name "SearchboxTaskbarMode" -Value 1 -Type "DWord") {
                    Add-ExplorerRestartChange -ChangeDescription "Configure search box to show icon only"
                }
            }
            "disable-news-interests" {
                Write-LogMessage "Disabling News and Interests on Windows 10..." -Level "INFO"
                
                $success = $false
                
                # Method 1: Direct cmd reg approach (what worked before)
                if (Test-IsAdministrator) {
                    try {
                        Write-LogMessage "Attempting to disable News and Interests via cmd reg..." -Level "INFO"
                        
                        # Use the exact method that worked before
                        $regPath = "HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Feeds"
                        & cmd /c "reg add `"$regPath`" /v ShellFeedsTaskbarViewMode /t REG_DWORD /d 2 /f" 2>$null
                        
                        # Verify the change
                        $currentValue = Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Feeds" -Name "ShellFeedsTaskbarViewMode" -ErrorAction SilentlyContinue
                        if ($currentValue -and $currentValue.ShellFeedsTaskbarViewMode -eq 2) {
                            Write-LogMessage "Successfully disabled News and Interests via cmd reg" -Level "SUCCESS"
                            $success = $true
                            Add-ExplorerRestartChange -ChangeDescription "Disable News and Interests taskbar widget"
                        } else {
                            Write-LogMessage "cmd reg method failed to set ShellFeedsTaskbarViewMode" -Level "WARNING"
                        }
                    } catch {
                        Write-LogMessage "cmd reg method failed: $_" -Level "WARNING"
                    }
                }
                
                # Method 2: Group Policy approach (backup)
                if (Test-IsAdministrator) {
                    try {
                        if (-not (Test-Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Feeds")) {
                            New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Feeds" -Force | Out-Null
                        }
                        Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Feeds" -Name "EnableFeeds" -Value 0 -Type DWord -Force
                        Write-LogMessage "Successfully applied News and Interests group policy disable" -Level "SUCCESS"
                        $success = $true
                    } catch {
                        Write-LogMessage "Group policy method failed: $_" -Level "WARNING"
                    }
                }
                
                # Method 3: Alternative user registry settings (backup)
                try {
                    if (-not (Test-Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Feeds")) {
                        New-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Feeds" -Force | Out-Null
                    }
                    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Feeds" -Name "ShellFeedsTaskbarOpenOnHover" -Value 0 -Type DWord -ErrorAction SilentlyContinue
                    Write-LogMessage "Applied alternative News and Interests registry settings" -Level "SUCCESS"
                    $success = $true
                } catch {
                    Write-LogMessage "Alternative registry method failed: $_" -Level "WARNING"
                }
                
                # Force restart explorer if any method succeeded
                if ($success) {
                    Write-LogMessage "News and Interests disable operation completed successfully" -Level "SUCCESS"
                    
                    # Immediate Explorer restart for this critical change
                    if (Test-IsAdministrator) {
                        try {
                            Write-LogMessage "Restarting Windows Explorer immediately to apply News and Interests changes..." -Level "INFO"
                            Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
                            Start-Sleep -Seconds 2
                            Start-Process explorer -ErrorAction SilentlyContinue
                            Write-LogMessage "Explorer restarted successfully" -Level "SUCCESS"
                        } catch {
                            Write-LogMessage "Could not restart explorer automatically: $_" -Level "WARNING"
                        }
                    }
                } else {
                    Write-LogMessage "All News and Interests disable methods failed" -Level "ERROR"
                    Write-LogMessage "Manual workaround: Right-click taskbar -> News and interests -> Turn off" -Level "INFO"
                }
            }
            "disable-auto-restart" {
                if (-not (Test-Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU")) {
                    New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Force | Out-Null
                }
                Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Name "NoAutoRebootWithLoggedOnUsers" -Value 1 -Type DWord
            }
            "disable-fast-startup" {
                if (-not (Test-Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power")) {
                    New-Item -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power" -Force | Out-Null
                }
                Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power" -Name "HiberbootEnabled" -Value 0 -Type DWord
            }
            "disable-lock-screen" {
                if (-not (Test-Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization")) {
                    New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization" -Force | Out-Null
                }
                Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization" -Name "NoLockScreen" -Value 1 -Type DWord
            }
            "disable-search-highlights" {
                if (-not (Test-Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\SearchSettings")) {
                    New-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\SearchSettings" -Force | Out-Null
                }
                Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\SearchSettings" -Name "IsDynamicSearchBoxEnabled" -Value 0 -Type DWord
            }
            
            # General interface optimizations
            "dark-theme" {
                Write-LogMessage "Applying dark theme for applications and system UI" -Level "INFO"
                if (-not (Test-Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize")) {
                    New-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" -Force | Out-Null
                }
                Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" -Name "AppsUseLightTheme" -Value 0
                Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" -Name "SystemUsesLightTheme" -Value 0
            }
            "light-theme" {
                Write-LogMessage "Applying light theme for applications and system UI" -Level "INFO"
                if (-not (Test-Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize")) {
                    New-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" -Force | Out-Null
                }
                Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" -Name "AppsUseLightTheme" -Value 1
                Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" -Name "SystemUsesLightTheme" -Value 1
            }
            "disable-quickaccess" {
                if (-not (Test-Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer")) {
                    New-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer" -Force | Out-Null
                }
                Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer" -Name "ShowQuickAccess" -Value 0 -Type DWord
                Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer" -Name "ShowFrequent" -Value 0 -Type DWord
                Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer" -Name "ShowRecent" -Value 0 -Type DWord
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
                "internet-explorer" {
                    # Re-enable Internet Explorer
                    try {
                        Write-LogMessage "Attempting to re-enable Internet Explorer..." -Level "INFO"
                        Enable-WindowsOptionalFeature -FeatureName Internet-Explorer-Optional-amd64 -Online -NoRestart -ErrorAction Stop
                        Write-LogMessage "Internet Explorer re-enabled successfully" -Level "SUCCESS"
                    } catch {
                        Write-LogMessage "Failed to re-enable Internet Explorer via PowerShell: $_" -Level "WARNING"
                        # Try DISM as fallback
                        try {
                            & dism /online /Enable-Feature /FeatureName:Internet-Explorer-Optional-amd64 /NoRestart /Quiet
                            if ($LASTEXITCODE -eq 0) {
                                Write-LogMessage "Internet Explorer re-enabled via DISM" -Level "SUCCESS"
                            } else {
                                Write-LogMessage "DISM re-enable also failed" -Level "ERROR"
                            }
                        } catch {
                            Write-LogMessage "Both PowerShell and DISM re-enable methods failed" -Level "ERROR"
                        }
                    }
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

# Enhanced helper function to build configuration lookup table with metadata
function Build-BloatwareConfigLookup {
    [CmdletBinding()]
    param()
    
    $configLookup = @{}
    $configMetadata = $null
    
    try {
        # Try to use script-level configuration first
        if ($script:Bloatware) {
            # Extract metadata and configuration settings
            if ($script:Bloatware._metadata) {
                $configMetadata = $script:Bloatware._metadata
                Write-LogMessage "Loaded bloatware config version: $($configMetadata.version)" -Level "DEBUG"
            }
            
            # Store configuration settings globally for use by other functions
            if ($script:Bloatware._configuration) {
                $script:BloatwareConfiguration = $script:Bloatware._configuration
                Write-LogMessage "Loaded bloatware configuration settings" -Level "DEBUG"
            }
            
            # Build lookup table excluding metadata
            foreach ($category in $script:Bloatware.Keys) {
                if ($category -notlike "_*") {  # Skip metadata keys
                    foreach ($item in $script:Bloatware[$category]) {
                        if ($item.Key) {
                            $configLookup[$item.Key] = $item
                        }
                    }
                }
            }
            Write-LogMessage "Built config lookup from script variable: $($configLookup.Count) items" -Level "DEBUG"
        }
        # Fallback to direct config loading
        elseif (Get-Command Get-ConfigurationData -ErrorAction SilentlyContinue) {
            $configData = Get-ConfigurationData -ConfigType "Bloatware"
            
            # Extract metadata and configuration settings
            if ($configData._metadata) {
                $configMetadata = $configData._metadata
                Write-LogMessage "Loaded bloatware config version: $($configMetadata.version)" -Level "DEBUG"
            }
            
            if ($configData._configuration) {
                $script:BloatwareConfiguration = $configData._configuration
                Write-LogMessage "Loaded bloatware configuration settings" -Level "DEBUG"
            }
            
            # Build lookup table excluding metadata
            foreach ($category in $configData.Keys) {
                if ($category -notlike "_*") {  # Skip metadata keys
                    foreach ($item in $configData[$category]) {
                        if ($item.Key) {
                            $configLookup[$item.Key] = $item
                        }
                    }
                }
            }
            Write-LogMessage "Built config lookup from direct load: $($configLookup.Count) items" -Level "DEBUG"
        }
    } catch {
        Write-LogMessage "Failed to build config lookup: $($_.Exception.Message)" -Level "ERROR"
    }
    
    return $configLookup
}

# Helper function to validate removal method using JSON configuration
function Test-RemovalMethod {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Method
    )
    
    # Use configuration from JSON if available, fallback to defaults
    $validMethods = if ($script:BloatwareConfiguration -and $script:BloatwareConfiguration.valid_removal_methods) {
        $script:BloatwareConfiguration.valid_removal_methods
    } else {
        @("AppX", "MSI", "WindowsFeature", "Registry")  # Fallback defaults
    }
    
    $isValid = $Method -in $validMethods
    if (-not $isValid) {
        Write-LogMessage "Invalid removal method '$Method'. Valid methods: $($validMethods -join ', ')" -Level "WARNING"
    }
    
    return $isValid
}

# Enhanced helper function to remove AppX packages with optimized discovery
function Remove-AppXPackages {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string[]]$PackageNames,
        [Parameter(Mandatory=$true)]
        [string]$BloatwareKey,
        [Parameter(Mandatory=$false)]
        [switch]$DryRun
    )
    
    $removedCount = 0
    $errors = @()
    
    try {
        Write-LogMessage "Starting AppX package discovery for: $BloatwareKey" -Level "DEBUG"
        
        # Optimized batch discovery - get all packages once instead of individual queries
        $allInstalledPackages = @()
        $allProvisionedPackages = @()
        
        # Get all packages once for better performance
        Write-LogMessage "Discovering all installed AppX packages..." -Level "DEBUG"
        $installedPackageCache = Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue
        
        Write-LogMessage "Discovering all provisioned AppX packages..." -Level "DEBUG"
        $provisionedPackageCache = Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue
        
        # Filter packages based on the provided names/patterns
        foreach ($packageName in $PackageNames) {
            Write-LogMessage "Filtering packages for pattern: $packageName" -Level "DEBUG"
            
            if ($packageName -like "*`**") {
                # Wildcard pattern matching
                $matchingInstalled = $installedPackageCache | Where-Object { $_.Name -like $packageName }
                $matchingProvisioned = $provisionedPackageCache | Where-Object { $_.DisplayName -like $packageName }
            } else {
                # Exact name matching
                $matchingInstalled = $installedPackageCache | Where-Object { $_.Name -eq $packageName }
                $matchingProvisioned = $provisionedPackageCache | Where-Object { $_.DisplayName -eq $packageName }
            }
            
            if ($matchingInstalled) {
                $allInstalledPackages += $matchingInstalled
                Write-LogMessage "Found $($matchingInstalled.Count) installed package(s) for pattern: $packageName" -Level "DEBUG"
            }
            if ($matchingProvisioned) {
                $allProvisionedPackages += $matchingProvisioned
                Write-LogMessage "Found $($matchingProvisioned.Count) provisioned package(s) for pattern: $packageName" -Level "DEBUG"
            }
        }
        
        Write-LogMessage "Package discovery completed: $($allInstalledPackages.Count) installed, $($allProvisionedPackages.Count) provisioned" -Level "DEBUG"
        
        # Remove installed packages with improved error handling
        if ($allInstalledPackages -and $allInstalledPackages.Count -gt 0) {
            Write-LogMessage "Found $($allInstalledPackages.Count) total installed package(s) for: $BloatwareKey" -Level "INFO"
            
            if ($DryRun) {
                Write-LogMessage "[DRY RUN] Would remove $($allInstalledPackages.Count) installed packages" -Level "INFO"
                foreach ($pkg in $allInstalledPackages) {
                    Write-LogMessage "[DRY RUN] Would remove: $($pkg.Name) ($($pkg.Version))" -Level "INFO"
                }
                $removedCount += $allInstalledPackages.Count
            } else {
                $failedRemovals = @()
                foreach ($pkg in $allInstalledPackages) {
                    try {
                        $pkg | Remove-AppxPackage -ErrorAction Stop
                        $removedCount++
                        Write-LogMessage "Removed installed package: $($pkg.Name)" -Level "DEBUG"
                    } catch {
                        $failedRemovals += $pkg.Name
                        $errors += "Failed to remove $($pkg.Name): $($_.Exception.Message)"
                        Write-LogMessage "Failed to remove $($pkg.Name): $($_.Exception.Message)" -Level "WARNING"
                    }
                }
                
                if ($removedCount -gt 0) {
                    Write-LogMessage "Successfully removed $removedCount AppxPackage(s) for: $BloatwareKey" -Level "SUCCESS"
                }
                if ($failedRemovals.Count -gt 0) {
                    Write-LogMessage "Failed to remove $($failedRemovals.Count) packages: $($failedRemovals -join ', ')" -Level "WARNING"
                }
            }
        }
        
        # Remove provisioned packages with improved error handling
        if ($allProvisionedPackages -and $allProvisionedPackages.Count -gt 0) {
            Write-LogMessage "Found $($allProvisionedPackages.Count) total provisioned package(s) for: $BloatwareKey" -Level "INFO"
            
            if ($DryRun) {
                Write-LogMessage "[DRY RUN] Would remove $($allProvisionedPackages.Count) provisioned packages" -Level "INFO"
                foreach ($pkg in $allProvisionedPackages) {
                    Write-LogMessage "[DRY RUN] Would remove provisioned: $($pkg.DisplayName) ($($pkg.Version))" -Level "INFO"
                }
                $removedCount += $allProvisionedPackages.Count
            } else {
                $failedProvisionedRemovals = @()
                foreach ($pkg in $allProvisionedPackages) {
                    try {
                        $pkg | Remove-AppxProvisionedPackage -Online -ErrorAction Stop
                        $removedCount++
                        Write-LogMessage "Removed provisioned package: $($pkg.DisplayName)" -Level "DEBUG"
                    } catch {
                        $failedProvisionedRemovals += $pkg.DisplayName
                        $errors += "Failed to remove provisioned $($pkg.DisplayName): $($_.Exception.Message)"
                        Write-LogMessage "Failed to remove provisioned $($pkg.DisplayName): $($_.Exception.Message)" -Level "WARNING"
                    }
                }
                
                if (($removedCount - $allInstalledPackages.Count) -gt 0) {
                    Write-LogMessage "Successfully removed $(($removedCount - $allInstalledPackages.Count)) AppxProvisionedPackage(s) for: $BloatwareKey" -Level "SUCCESS"
                }
                if ($failedProvisionedRemovals.Count -gt 0) {
                    Write-LogMessage "Failed to remove $($failedProvisionedRemovals.Count) provisioned packages: $($failedProvisionedRemovals -join ', ')" -Level "WARNING"
                }
            }
        }
        
    } catch {
        $errors += "Error during AppX package removal: $($_.Exception.Message)"
        Write-LogMessage "Error during AppX package removal for $BloatwareKey`: $($_.Exception.Message)" -Level "ERROR"
    }
    
    # Return results with error information
    return @{
        RemovedCount = $removedCount
        Errors = $errors
    }
}

# Enhanced helper function to remove MSI packages with improved generalization
function Remove-MSIPackages {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string[]]$PackageNames,
        [Parameter(Mandatory=$true)]
        [string]$BloatwareKey,
        [Parameter(Mandatory=$false)]
        [switch]$DryRun
    )
    
    $removedCount = 0
    $errors = @()
    
    Write-LogMessage "Attempting MSI removal for: $BloatwareKey" -Level "INFO"
    
    try {
        # Get all MSI products once for better performance
        Write-LogMessage "Discovering MSI products..." -Level "DEBUG"
        $allMsiProducts = @()
        
        # Use CIM instead of WMI for better performance and reliability
        $installedProducts = Get-CimInstance -ClassName Win32_Product -ErrorAction SilentlyContinue
        
        if (-not $installedProducts) {
            Write-LogMessage "No MSI products found or WMI/CIM access failed" -Level "WARNING"
            return @{ RemovedCount = 0; Errors = @("Unable to access MSI product information") }
        }
        
        # Match products against package names
        foreach ($packageName in $PackageNames) {
            Write-LogMessage "Searching for MSI products matching: $packageName" -Level "DEBUG"
            
            try {
                if ($packageName -like "*`**") {
                    # Wildcard pattern matching
                    $matchingProducts = $installedProducts | Where-Object { $_.Name -like $packageName }
                } else {
                    # Exact name matching
                    $matchingProducts = $installedProducts | Where-Object { $_.Name -eq $packageName }
                }
                
                if ($matchingProducts) {
                    $allMsiProducts += $matchingProducts
                    Write-LogMessage "Found $($matchingProducts.Count) MSI product(s) for pattern: $packageName" -Level "DEBUG"
                }
            } catch {
                $errors += "Error searching for MSI products with pattern $packageName`: $($_.Exception.Message)"
                Write-LogMessage "Error searching for MSI products with pattern $packageName`: $($_.Exception.Message)" -Level "WARNING"
            }
        }
        
        # Remove or simulate removal of found products
        if ($allMsiProducts -and $allMsiProducts.Count -gt 0) {
            Write-LogMessage "Found $($allMsiProducts.Count) total MSI product(s) for: $BloatwareKey" -Level "INFO"
            
            if ($DryRun) {
                Write-LogMessage "[DRY RUN] Would remove $($allMsiProducts.Count) MSI products" -Level "INFO"
                foreach ($product in $allMsiProducts) {
                    Write-LogMessage "[DRY RUN] Would remove: $($product.Name) (Version: $($product.Version))" -Level "INFO"
                }
                $removedCount = $allMsiProducts.Count
            } else {
                $failedRemovals = @()
                foreach ($product in $allMsiProducts) {
                    try {
                        Write-LogMessage "Uninstalling MSI product: $($product.Name)" -Level "INFO"
                        
                        # Handle special cases with JSON-driven guidance
                        $skipRemoval = $false
                        if ($script:BloatwareConfiguration -and $script:BloatwareConfiguration.special_handling.msi_special_cases) {
                            $specialCases = $script:BloatwareConfiguration.special_handling.msi_special_cases
                            if ($specialCases.$BloatwareKey) {
                                $specialCase = $specialCases.$BloatwareKey
                                if ($product.Name -like $specialCase.product_name_pattern) {
                                    Write-LogMessage $specialCase.warning_message -Level "WARNING"
                                    if ($specialCase.guidance_message) {
                                        Write-LogMessage $specialCase.guidance_message -Level "WARNING"
                                    }
                                    $errors += $specialCase.warning_message
                                    $skipRemoval = $true
                                }
                            }
                        }
                        
                        if ($skipRemoval) {
                            continue
                        }
                        
                        # Attempt uninstallation
                        $uninstallResult = Invoke-CimMethod -InputObject $product -MethodName Uninstall -ErrorAction Stop
                        
                        if ($uninstallResult.ReturnValue -eq 0) {
                            $removedCount++
                            Write-LogMessage "Successfully uninstalled MSI product: $($product.Name)" -Level "SUCCESS"
                        } else {
                            $failedRemovals += $product.Name
                            $errors += "MSI uninstall failed for $($product.Name): Return code $($uninstallResult.ReturnValue)"
                            Write-LogMessage "MSI uninstall failed for $($product.Name): Return code $($uninstallResult.ReturnValue)" -Level "WARNING"
                        }
                    } catch {
                        $failedRemovals += $product.Name
                        $errors += "Failed to uninstall MSI product $($product.Name): $($_.Exception.Message)"
                        Write-LogMessage "Failed to uninstall MSI product $($product.Name): $($_.Exception.Message)" -Level "WARNING"
                    }
                }
                
                if ($removedCount -gt 0) {
                    Write-LogMessage "Successfully removed $removedCount MSI product(s) for: $BloatwareKey" -Level "SUCCESS"
                }
                if ($failedRemovals.Count -gt 0) {
                    Write-LogMessage "Failed to remove $($failedRemovals.Count) MSI products: $($failedRemovals -join ', ')" -Level "WARNING"
                }
            }
        } else {
            Write-LogMessage "No MSI products found matching the specified patterns for: $BloatwareKey" -Level "INFO"
        }
        
    } catch {
        $errors += "Error during MSI removal for $BloatwareKey`: $($_.Exception.Message)"
        Write-LogMessage "Error during MSI removal for $BloatwareKey`: $($_.Exception.Message)" -Level "ERROR"
    }
    
    return @{
        RemovedCount = $removedCount
        Errors = $errors
    }
}

# Helper function to remove Windows Features
function Remove-WindowsFeatures {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string[]]$FeatureNames,
        [Parameter(Mandatory=$true)]
        [string]$BloatwareKey,
        [Parameter(Mandatory=$false)]
        [switch]$DryRun
    )
    
    $removedCount = 0
    
    Write-LogMessage "Attempting Windows Feature removal for: $BloatwareKey" -Level "INFO"
    
    foreach ($featureName in $FeatureNames) {
        Write-LogMessage "Processing Windows Feature: $featureName" -Level "DEBUG"
        
        try {
            # Check if feature exists and is enabled
            $feature = Get-WindowsOptionalFeature -Online -FeatureName $featureName -ErrorAction SilentlyContinue
            
            if (-not $feature) {
                Write-LogMessage "Windows Feature not found: $featureName" -Level "WARNING"
                continue
            }
            
            if ($feature.State -eq "Disabled") {
                Write-LogMessage "Windows Feature already disabled: $featureName" -Level "INFO"
                continue
            }
            
            Write-LogMessage "Found enabled Windows Feature: $featureName" -Level "INFO"
            
            if ($DryRun) {
                Write-LogMessage "[DRY RUN] Would disable Windows Feature: $featureName" -Level "INFO"
            } else {
                try {
                    # Try DISM first (more reliable)
                    Write-LogMessage "Disabling Windows Feature via DISM: $featureName" -Level "DEBUG"
                    $dismResult = & dism /online /Disable-Feature /FeatureName:$featureName /NoRestart /Quiet
                    
                    if ($LASTEXITCODE -eq 0) {
                        Write-LogMessage "Successfully disabled Windows Feature via DISM: $featureName" -Level "SUCCESS"
                        $removedCount++
                    } else {
                        throw "DISM failed with exit code: $LASTEXITCODE"
                    }
                } catch {
                    Write-LogMessage "DISM method failed: $($_.Exception.Message). Trying PowerShell method..." -Level "WARNING"
                    
                    try {
                        Disable-WindowsOptionalFeature -FeatureName $featureName -Online -NoRestart -ErrorAction Stop
                        Write-LogMessage "Successfully disabled Windows Feature via PowerShell: $featureName" -Level "SUCCESS"
                        $removedCount++
                    } catch {
                        Write-LogMessage "PowerShell method also failed: $($_.Exception.Message)" -Level "ERROR"
                    }
                }
                
                # Add restart requirement if feature was disabled
                if ($removedCount -gt 0) {
                    $script:RestartRequired = $true
                    if (Get-Command Add-RestartRegistryChange -ErrorAction SilentlyContinue) {
                        Add-RestartRegistryChange -ChangeDescription "Disable Windows Feature: $featureName"
                    }
                }
            }
        } catch {
            Write-LogMessage "Error processing Windows Feature $featureName`: $($_.Exception.Message)" -Level "ERROR"
        }
    }
    
    return $removedCount
}

# Helper function to remove applications via Registry manipulation
function Remove-RegistryPackages {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string[]]$RegistryPaths,
        [Parameter(Mandatory=$true)]
        [string]$BloatwareKey,
        [Parameter(Mandatory=$false)]
        [switch]$DryRun
    )
    
    $removedCount = 0
    $errors = @()
    
    Write-LogMessage "Attempting Registry-based removal for: $BloatwareKey" -Level "INFO"
    
    try {
        foreach ($registryPath in $RegistryPaths) {
            Write-LogMessage "Processing registry path: $registryPath" -Level "DEBUG"
            
            try {
                # Validate registry path format
                if (-not ($registryPath -match '^HK(LM|CU|CR|U|CC):\\')) {
                    $errors += "Invalid registry path format: $registryPath"
                    Write-LogMessage "Invalid registry path format: $registryPath" -Level "WARNING"
                    continue
                }
                
                # Check if registry key exists
                if (-not (Test-Path $registryPath)) {
                    Write-LogMessage "Registry path does not exist: $registryPath" -Level "INFO"
                    continue
                }
                
                # Get registry key information for logging
                $regKey = Get-Item $registryPath -ErrorAction SilentlyContinue
                if ($regKey) {
                    Write-LogMessage "Found registry key: $registryPath" -Level "DEBUG"
                    
                    if ($DryRun) {
                        Write-LogMessage "[DRY RUN] Would remove registry key: $registryPath" -Level "INFO"
                        $removedCount++
                    } else {
                        # Backup registry key before removal (if backup system is available)
                        if (Get-Command Backup-RegistryKey -ErrorAction SilentlyContinue) {
                            try {
                                Backup-RegistryKey -RegistryPath $registryPath -BackupName "BloatwareRemoval_$BloatwareKey"
                                Write-LogMessage "Registry key backed up: $registryPath" -Level "DEBUG"
                            } catch {
                                Write-LogMessage "Failed to backup registry key $registryPath`: $($_.Exception.Message)" -Level "WARNING"
                            }
                        }
                        
                        # Remove registry key
                        try {
                            Remove-Item $registryPath -Recurse -Force -ErrorAction Stop
                            Write-LogMessage "Successfully removed registry key: $registryPath" -Level "SUCCESS"
                            $removedCount++
                        } catch {
                            $errors += "Failed to remove registry key $registryPath`: $($_.Exception.Message)"
                            Write-LogMessage "Failed to remove registry key $registryPath`: $($_.Exception.Message)" -Level "WARNING"
                        }
                    }
                }
            } catch {
                $errors += "Error processing registry path $registryPath`: $($_.Exception.Message)"
                Write-LogMessage "Error processing registry path $registryPath`: $($_.Exception.Message)" -Level "WARNING"
            }
        }
        
        if ($removedCount -gt 0 -and -not $DryRun) {
            Write-LogMessage "Successfully processed $removedCount registry path(s) for: $BloatwareKey" -Level "SUCCESS"
            
            # Mark that registry changes were made (may require restart/explorer restart)
            $script:ExplorerRestartRequired = $true
            if (Get-Command Add-RestartRegistryChange -ErrorAction SilentlyContinue) {
                Add-RestartRegistryChange -ChangeDescription "Registry-based bloatware removal: $BloatwareKey"
            }
        }
        
    } catch {
        $errors += "Error during registry removal for $BloatwareKey`: $($_.Exception.Message)"
        Write-LogMessage "Error during registry removal for $BloatwareKey`: $($_.Exception.Message)" -Level "ERROR"
    }
    
    return @{
        RemovedCount = $removedCount
        Errors = $errors
    }
}

# Improved main Remove-Bloatware function
function Remove-Bloatware {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, ParameterSetName="Key")]
        [string]$BloatwareKey,
        
        [Parameter(Mandatory=$true, ParameterSetName="List")]
        [string[]]$Bloatware,
        
        [Parameter(Mandatory=$false)]
        [System.Threading.CancellationToken]$CancellationToken = [System.Threading.CancellationToken]::None,
        
        [Parameter(Mandatory=$false)]
        [switch]$DryRun
    )
    
    Write-LogMessage "Starting bloatware removal$(if($DryRun){' (DRY RUN)'})..." -Level "INFO"
    
    # Check for cancellation
    if ($CancellationToken -and $CancellationToken.IsCancellationRequested) {
        Write-LogMessage "Bloatware removal cancelled" -Level "WARNING"
        return $false
    }
    
    try {
        if ($PSCmdlet.ParameterSetName -eq "Key") {
            return Remove-SingleBloatware -BloatwareKey $BloatwareKey -DryRun:$DryRun -CancellationToken $CancellationToken
        } else {
            return Remove-MultipleBloatware -BloatwareKeys $Bloatware -DryRun:$DryRun -CancellationToken $CancellationToken
        }
    } catch {
        Write-LogMessage "Failed to remove bloatware: $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}

# Enhanced single bloatware removal (JSON-driven with improved error handling)
function Remove-SingleBloatware {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$BloatwareKey,
        [Parameter(Mandatory=$false)]
        [switch]$DryRun,
        [Parameter(Mandatory=$false)]
        [System.Threading.CancellationToken]$CancellationToken
    )
    
    $totalRemovedCount = 0
    $allErrors = @()
    
    try {
        # Check for cancellation
        if ($CancellationToken -and $CancellationToken.IsCancellationRequested) {
            Write-LogMessage "Bloatware removal cancelled for: $BloatwareKey" -Level "WARNING"
            return $false
        }
        
        # Track operation in recovery system
        if (-not $DryRun) {
            Save-OperationState -OperationType "RemoveBloatware" -ItemKey $BloatwareKey -Status "InProgress"
        }
        
        # Load bloatware item configuration
        $bloatwareItem = $null
        
        try {
            # Build configuration lookup
            $configLookup = Build-BloatwareConfigLookup
            
            if ($configLookup.ContainsKey($BloatwareKey)) {
                $bloatwareItem = $configLookup[$BloatwareKey]
                Write-LogMessage "Found bloatware config for $BloatwareKey with method: $($bloatwareItem.Method)" -Level "DEBUG"
            }
        } catch {
            Write-LogMessage "Failed to load bloatware item configuration: $($_.Exception.Message)" -Level "DEBUG"
        }
        
        if (-not $bloatwareItem) {
            Write-LogMessage "Unknown bloatware key: $BloatwareKey (not found in configuration)" -Level "WARNING"
            if (-not $DryRun) {
                Save-OperationState -OperationType "RemoveBloatware" -ItemKey $BloatwareKey -Status "Failed" -AdditionalData @{
                    Error = "Bloatware key not found in JSON configuration"
                    Time = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                }
            }
            return $false
        }
        
        # Get package names and method
        $packageNames = $bloatwareItem.PackageName
        $method = $bloatwareItem.Method
        
        # Validate removal method
        if (-not (Test-RemovalMethod -Method $method)) {
            Write-LogMessage "Invalid removal method: $method for $BloatwareKey" -Level "ERROR"
            return $false
        }
        
        # Normalize package names to array
        if ($packageNames -is [string]) {
            $packageNames = @($packageNames)
        }
        
        Write-LogMessage "Removing bloatware: $BloatwareKey using method: $method" -Level "INFO"
        
        # Apply appropriate removal method
        switch ($method) {
            "AppX" {
                $result = Remove-AppXPackages -PackageNames $packageNames -BloatwareKey $BloatwareKey -DryRun:$DryRun
                $totalRemovedCount += $result.RemovedCount
                $allErrors += $result.Errors
            }
            "MSI" {
                $result = Remove-MSIPackages -PackageNames $packageNames -BloatwareKey $BloatwareKey -DryRun:$DryRun
                $totalRemovedCount += $result.RemovedCount
                $allErrors += $result.Errors
            }
            "WindowsFeature" {
                # For backwards compatibility, WindowsFeatures function returns count directly
                $removedCount = Remove-WindowsFeatures -FeatureNames $packageNames -BloatwareKey $BloatwareKey -DryRun:$DryRun
                $totalRemovedCount += $removedCount
            }
            "Registry" {
                # Use RegistryPaths property if available, fallback to PackageName
                $registryPaths = if ($bloatwareItem.RegistryPaths) { $bloatwareItem.RegistryPaths } else { $packageNames }
                $result = Remove-RegistryPackages -RegistryPaths $registryPaths -BloatwareKey $BloatwareKey -DryRun:$DryRun
                $totalRemovedCount += $result.RemovedCount
                $allErrors += $result.Errors
            }
            default {
                Write-LogMessage "Unknown removal method: $method for $BloatwareKey" -Level "ERROR"
                return $false
            }
        }
        
        # Apply special handling if defined (JSON-driven)
        $requiresSpecialHandling = $false
        if ($script:BloatwareConfiguration -and $script:BloatwareConfiguration.special_handling.keys) {
            $requiresSpecialHandling = $BloatwareKey -in $script:BloatwareConfiguration.special_handling.keys
        } else {
            # Fallback to hardcoded list if configuration not available
            $requiresSpecialHandling = $BloatwareKey -in @("ms-widgets", "ms-copilot", "internet-explorer")
        }
        
        if ($bloatwareItem.RequiresSpecialHandling -or $requiresSpecialHandling) {
            if (-not $DryRun) {
                $specialCount = Invoke-ConfigurableSpecialHandling -BloatwareKey $BloatwareKey
                $totalRemovedCount += $specialCount
            } else {
                Write-LogMessage "[DRY RUN] Would apply special handling for: $BloatwareKey" -Level "INFO"
            }
        }
        
        # Report results
        if ($allErrors.Count -gt 0) {
            Write-LogMessage "Encountered $($allErrors.Count) errors during removal of $BloatwareKey" -Level "WARNING"
            foreach ($error in $allErrors) {
                Write-LogMessage "Error: $error" -Level "WARNING"
            }
        }
        
        if ($totalRemovedCount -gt 0) {
            Write-LogMessage "Successfully $(if($DryRun){'would remove'}else{'removed'}) $totalRemovedCount item(s) for: $BloatwareKey" -Level "SUCCESS"
            if (-not $DryRun) {
                Save-OperationState -OperationType "RemoveBloatware" -ItemKey $BloatwareKey -Status "Completed" -AdditionalData @{
                    RemovedCount = $totalRemovedCount
                    Errors = $allErrors
                    Time = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                }
            }
            return $true
        } else {
            Write-LogMessage "No items found or removed for: $BloatwareKey" -Level "WARNING"
            if (-not $DryRun) {
                Save-OperationState -OperationType "RemoveBloatware" -ItemKey $BloatwareKey -Status "Completed" -AdditionalData @{
                    RemovedCount = 0
                    Errors = $allErrors
                    Time = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                }
            }
            return $allErrors.Count -eq 0  # Return true if no errors, even if nothing was removed
        }
        
    } catch {
        $allErrors += "Exception in Remove-SingleBloatware: $($_.Exception.Message)"
        Write-LogMessage "Failed to remove bloatware $BloatwareKey`: $($_.Exception.Message)" -Level "ERROR"
        if (-not $DryRun) {
            Save-OperationState -OperationType "RemoveBloatware" -ItemKey $BloatwareKey -Status "Failed" -AdditionalData @{
                Error = $_.Exception.Message
                Errors = $allErrors
                Time = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            }
        }
        return $false
    }
}

# JSON-driven special handling function for configurable operations
function Invoke-ConfigurableSpecialHandling {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$BloatwareKey
    )
    
    $handledCount = 0
    
    try {
        # Check if we have JSON configuration for special handling
        if ($script:BloatwareConfiguration -and $script:BloatwareConfiguration.special_handling.registry_operations) {
            $registryOps = $script:BloatwareConfiguration.special_handling.registry_operations
            
            if ($registryOps.$BloatwareKey) {
                Write-LogMessage "Applying JSON-configured special handling for: $BloatwareKey" -Level "INFO"
                
                # Determine Windows version for version-specific operations
                $windowsVersion = [System.Environment]::OSVersion.Version
                $windowsVersions = $script:BloatwareConfiguration.windows_versions
                
                $isWindows10 = $false
                $isWindows11 = $false
                
                if ($windowsVersions) {
                    $isWindows10 = $windowsVersion.Major -eq $windowsVersions.windows10.major -and $windowsVersion.Build -le $windowsVersions.windows10.build_max
                    $isWindows11 = $windowsVersion.Major -eq $windowsVersions.windows11.major -and $windowsVersion.Build -ge $windowsVersions.windows11.build_min
                } else {
                    # Fallback to hardcoded values if configuration not available
                    $isWindows10 = $windowsVersion.Major -eq 10 -and $windowsVersion.Build -lt 22000
                    $isWindows11 = $windowsVersion.Major -eq 10 -and $windowsVersion.Build -ge 22000
                }
                
                Write-LogMessage "Detected Windows version: Build $($windowsVersion.Build) $(if($isWindows10){'(Windows 10)'}elseif($isWindows11){'(Windows 11)'}else{'(Unknown)'})" -Level "DEBUG"
                
                $operations = $registryOps.$BloatwareKey
                
                # Handle version-specific operations (like widgets)
                if ($operations.windows10 -and $isWindows10) {
                    foreach ($op in $operations.windows10) {
                        $handledCount += Invoke-RegistryOperation -Operation $op
                    }
                }
                
                if ($operations.windows11 -and $isWindows11) {
                    foreach ($op in $operations.windows11) {
                        $handledCount += Invoke-RegistryOperation -Operation $op
                    }
                }
                
                # Handle general operations (like copilot - array format)
                if ($operations -is [array]) {
                    foreach ($op in $operations) {
                        $handledCount += Invoke-RegistryOperation -Operation $op
                    }
                }
                
                Write-LogMessage "Completed special handling for $BloatwareKey`: $handledCount operations" -Level "SUCCESS"
            } else {
                Write-LogMessage "No JSON configuration found for special handling: $BloatwareKey" -Level "DEBUG"
            }
        } else {
            Write-LogMessage "No special handling configuration available, falling back to legacy method" -Level "DEBUG"
            $handledCount = Invoke-LegacySpecialHandling -BloatwareKey $BloatwareKey
        }
    } catch {
        Write-LogMessage "Error in special handling for $BloatwareKey`: $($_.Exception.Message)" -Level "ERROR"
    }
    
    return $handledCount
}

# Helper function to execute registry operations from JSON configuration
function Invoke-RegistryOperation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$Operation
    )
    
    try {
        $path = $Operation.path
        $name = $Operation.name
        $value = $Operation.value
        $type = $Operation.type
        $description = $Operation.description
        
        Write-LogMessage "Applying registry operation: $description" -Level "DEBUG"
        
        # Ensure registry path exists
        if (-not (Test-Path $path)) {
            New-Item -Path $path -Force | Out-Null
            Write-LogMessage "Created registry path: $path" -Level "DEBUG"
        }
        
        # Set registry value
        Set-ItemProperty -Path $path -Name $name -Value $value -Type $type -Force
        Write-LogMessage "Set registry value: $path\$name = $value ($type)" -Level "DEBUG"
        
        return 1
    } catch {
        Write-LogMessage "Failed to apply registry operation '$($Operation.description)': $($_.Exception.Message)" -Level "WARNING"
        return 0
    }
}

# Legacy special handling function for backwards compatibility
function Invoke-LegacySpecialHandling {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$BloatwareKey
    )
    
    $handledCount = 0
    
    switch ($BloatwareKey) {
        "ms-widgets" {
            # Widgets/Weather/News special handling
            try {
                $windowsVersion = [System.Environment]::OSVersion.Version
                $isWindows10 = $windowsVersion.Major -eq 10 -and $windowsVersion.Build -lt 22000
                $isWindows11 = $windowsVersion.Major -eq 10 -and $windowsVersion.Build -ge 22000
                
                if ($isWindows11) {
                    # Windows 11 Widgets disable
                    if (-not (Test-Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced")) {
                        New-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Force | Out-Null
                    }
                    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "TaskbarDa" -Value 0 -Type DWord -Force
                    Write-LogMessage "Disabled Windows 11 Widgets taskbar button" -Level "INFO"
                    $handledCount++
                }
                
                if ($isWindows10) {
                    # Windows 10 News and Interests disable
                    if (-not (Test-Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Feeds")) {
                        New-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Feeds" -Force | Out-Null
                    }
                    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Feeds" -Name "ShellFeedsTaskbarViewMode" -Value 2 -Type DWord -Force
                    Write-LogMessage "Disabled Windows 10 News and Interests" -Level "INFO"
                    $handledCount++
                }
            } catch {
                Write-LogMessage "Failed to apply Widgets special handling: $_" -Level "WARNING"
            }
        }
        "ms-copilot" {
            # Copilot special handling
            try {
                # System-wide Copilot disable
                if (-not (Test-Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot")) {
                    New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot" -Force | Out-Null
                }
                Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot" -Name "TurnOffWindowsCopilot" -Value 1 -Type DWord -Force
                
                # User-level Copilot disable
                if (-not (Test-Path "HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot")) {
                    New-Item -Path "HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot" -Force | Out-Null
                }
                Set-ItemProperty -Path "HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot" -Name "TurnOffWindowsCopilot" -Value 1 -Type DWord -Force
                
                # Remove Copilot button from taskbar
                if (-not (Test-Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced")) {
                    New-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Force | Out-Null
                }
                Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "ShowCopilotButton" -Value 0 -Type DWord -Force
                
                Write-LogMessage "Applied Copilot special handling" -Level "INFO"
                $handledCount++
            } catch {
                Write-LogMessage "Failed to apply Copilot special handling: $_" -Level "WARNING"
            }
        }
        default {
            Write-LogMessage "No special handling defined for: $BloatwareKey" -Level "DEBUG"
        }
    }
    
    return $handledCount
}

# Multiple bloatware removal (enhanced with parallel processing)
function Remove-MultipleBloatware {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string[]]$BloatwareKeys,
        [Parameter(Mandatory=$false)]
        [switch]$DryRun,
        [Parameter(Mandatory=$false)]
        [System.Threading.CancellationToken]$CancellationToken
    )
    
    $successCount = 0
    $totalCount = $BloatwareKeys.Count
    
    Write-LogMessage "Starting batch bloatware removal: $totalCount items$(if($DryRun){' (DRY RUN)'})" -Level "INFO"
    
    foreach ($key in $BloatwareKeys) {
        if ($CancellationToken -and $CancellationToken.IsCancellationRequested) {
            Write-LogMessage "Batch bloatware removal cancelled" -Level "WARNING"
            break
        }
        
        Write-LogMessage "Processing bloatware key: $key ($($successCount + 1)/$totalCount)" -Level "INFO"
        
        $result = Remove-SingleBloatware -BloatwareKey $key -DryRun:$DryRun -CancellationToken $CancellationToken
        if ($result) {
            $successCount++
        }
    }
    
    Write-LogMessage "Batch bloatware removal completed: $successCount/$totalCount successful$(if($DryRun){' (DRY RUN)'})" -Level "SUCCESS"
    return $successCount -eq $totalCount
}

function Optimize-System {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [hashtable]$Optimizations = @{},
        
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
        [hashtable]$Services = @{},
        
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
                
                $result = Show-TimeoutMessageBox -Message $dependencyMessage -Title "Service Dependencies Found" -TimeoutSeconds 30 -DefaultResponse "No"
                
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
Export-ModuleMember -Function Set-SystemOptimization, Save-RegistryValue, Save-ServiceState, Restore-RegistryValue, Restore-ServiceState, Optimize-System, Remove-Bloatware, Configure-Services, Test-ServiceDependency, Add-RestartRegistryChange, Test-IsAdministrator, Add-ExplorerRestartChange, Restart-WindowsExplorer, Set-ProtectedRegistryValue