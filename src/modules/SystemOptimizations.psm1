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

# Unified Remove-Bloatware function that handles both direct calls and batch removals
function Remove-Bloatware {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, ParameterSetName="Key")]
        [string]$BloatwareKey,
        
        [Parameter(Mandatory=$true, ParameterSetName="List")]
        [string[]]$Bloatware,
        
        [Parameter(Mandatory=$false)]
        [System.Threading.CancellationToken]$CancellationToken = [System.Threading.CancellationToken]::None
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
        "ms-copilot" = @("Microsoft.Windows.Ai.Copilot.Provider", "Microsoft.Copilot")
        "ms-clipchamp" = "*.ClipChamp*"
        "linkedin" = "*.LinkedIn*"
        "instagram" = "*.Instagram*"
        "whatsapp" = "*.WhatsApp*"
        "amazon-prime" = "*.AmazonPrimeVideo*"
        "skype-app" = "Microsoft.SkypeApp"
        "internet-explorer" = "Internet-Explorer-Optional-amd64"
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
            $packageNames = $packageMap[$BloatwareKey]
            if (-not $packageNames) {
                Write-LogMessage "Unknown bloatware key: $BloatwareKey" -Level "WARNING"
                Save-OperationState -OperationType "RemoveBloatware" -ItemKey $BloatwareKey -Status "Failed" -AdditionalData @{
                    Error = "Unknown bloatware key"
                    Time = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                }
                return $false
            }
            
            # Normalize to array for consistent processing
            if ($packageNames -is [string]) {
                $packageNames = @($packageNames)
            }
            
            Write-LogMessage "Removing bloatware: $BloatwareKey" -Level "INFO"
            
            $allInstalledPackages = @()
            $allProvisionedPackages = @()
            
            # Process each package name/pattern
            foreach ($packageName in $packageNames) {
                Write-LogMessage "Searching for packages matching: $packageName" -Level "DEBUG"
                
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
                
                if ($installedPackages) {
                    $allInstalledPackages += $installedPackages
                    Write-LogMessage "Found $($installedPackages.Count) installed package(s) for pattern: $packageName" -Level "DEBUG"
                }
                if ($provisionedPackages) {
                    $allProvisionedPackages += $provisionedPackages
                    Write-LogMessage "Found $($provisionedPackages.Count) provisioned package(s) for pattern: $packageName" -Level "DEBUG"
                }
            }
            
            $removedCount = 0
            
            # Remove installed packages for all users (using proven method from independent scripts)
            if ($allInstalledPackages -and $allInstalledPackages.Count -gt 0) {
                Write-LogMessage "Found $($allInstalledPackages.Count) total installed package(s) for: $BloatwareKey" -Level "INFO"
                try {
                    $allInstalledPackages | Remove-AppxPackage -ErrorAction SilentlyContinue
                    $removedCount += $allInstalledPackages.Count
                    Write-LogMessage "Removed $($allInstalledPackages.Count) AppxPackage(s) for: $BloatwareKey" -Level "INFO"
                } catch {
                    Write-LogMessage "Failed to remove some AppxPackages for $BloatwareKey - ${_}" -Level "WARNING"
                }
            }
            
            # Remove provisioned packages (using proven method from independent scripts)
            if ($allProvisionedPackages -and $allProvisionedPackages.Count -gt 0) {
                Write-LogMessage "Found $($allProvisionedPackages.Count) total provisioned package(s) for: $BloatwareKey" -Level "INFO"
                try {
                    $allProvisionedPackages | Remove-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue
                    $removedCount += $allProvisionedPackages.Count
                    Write-LogMessage "Removed $($allProvisionedPackages.Count) AppxProvisionedPackage(s) for: $BloatwareKey" -Level "INFO"
                } catch {
                    Write-LogMessage "Failed to remove some AppxProvisionedPackages for $BloatwareKey - ${_}" -Level "WARNING"
                }
            }
            
            # Special handling for Widgets/Weather/News (Windows 10 & 11)
            if ($BloatwareKey -eq "ms-widgets") {
                Write-LogMessage "Applying Widgets/Weather/News removal tweaks..." -Level "INFO"
                try {
                    # Detect Windows version for proper handling
                    $windowsVersion = [System.Environment]::OSVersion.Version
                    $isWindows10 = $windowsVersion.Major -eq 10 -and $windowsVersion.Build -lt 22000
                    $isWindows11 = $windowsVersion.Major -eq 10 -and $windowsVersion.Build -ge 22000
                    
                    Write-LogMessage "Detected Windows version: Build $($windowsVersion.Build) $(if($isWindows10){'(Windows 10)'}else{'(Windows 11)'})" -Level "INFO"
                    
                    if ($isWindows11) {
                        # Windows 11 Widgets handling
                        Write-LogMessage "Applying Windows 11 Widgets disable..." -Level "INFO"
                        
                        # Disable Widgets in taskbar (Windows 11 specific)
                        if (-not (Test-Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced")) {
                            New-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Force | Out-Null
                        }
                        Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "TaskbarDa" -Value 0 -Type DWord -Force
                        Write-LogMessage "Disabled Windows 11 Widgets taskbar button" -Level "INFO"
                    }
                    
                    if ($isWindows10) {
                        # Windows 10 News and Interests handling
                        Write-LogMessage "Applying Windows 10 News and Interests disable..." -Level "INFO"
                        
                        # Method 1: Disable News and Interests via user preferences
                        if (-not (Test-Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Feeds")) {
                            New-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Feeds" -Force | Out-Null
                        }
                        Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Feeds" -Name "ShellFeedsTaskbarViewMode" -Value 2 -Type DWord -Force
                        Write-LogMessage "Disabled News and Interests user preference" -Level "INFO"
                        
                        # Method 2: System-wide News and Interests disable
                        try {
                            if (-not (Test-Path "HKLM:\SOFTWARE\Microsoft\PolicyManager\default\NewsAndInterests\AllowNewsAndInterests")) {
                                New-Item -Path "HKLM:\SOFTWARE\Microsoft\PolicyManager\default\NewsAndInterests\AllowNewsAndInterests" -Force | Out-Null
                            }
                            Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\PolicyManager\default\NewsAndInterests\AllowNewsAndInterests" -Name "value" -Value 0 -Type DWord -Force
                            Write-LogMessage "Applied system-wide News and Interests disable" -Level "INFO"
                        } catch {
                            Write-LogMessage "Could not apply system-wide News and Interests disable (may require higher privileges): $_" -Level "DEBUG"
                        }
                        
                        # Method 3: Disable weather location services
                        try {
                            if (-not (Test-Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Feeds\DSB")) {
                                New-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Feeds\DSB" -Force | Out-Null
                            }
                            Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Feeds\DSB" -Name "ShowDynamicContent" -Value 0 -Type DWord -Force
                            Write-LogMessage "Disabled dynamic weather content" -Level "INFO"
                        } catch {
                            Write-LogMessage "Could not disable dynamic weather content: $_" -Level "DEBUG"
                        }
                    }
                    
                    # Common methods for both Windows 10 and 11
                    
                    # Disable News and Interests system-wide via Group Policy
                    if (-not (Test-Path "HKLM:\SOFTWARE\Policies\Microsoft\Dsh")) {
                        New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Dsh" -Force | Out-Null
                    }
                    Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Dsh" -Name "AllowNewsAndInterests" -Value 0 -Type DWord -Force
                    Write-LogMessage "Applied News and Interests Group Policy disable" -Level "INFO"
                    
                    # Disable Windows Feeds
                    if (-not (Test-Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Feeds")) {
                        New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Feeds" -Force | Out-Null
                    }
                    Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Feeds" -Name "EnableFeeds" -Value 0 -Type DWord -Force
                    Write-LogMessage "Applied Windows Feeds disable" -Level "INFO"
                    
                    # Disable web search in feeds
                    try {
                        if (-not (Test-Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\SearchSettings")) {
                            New-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\SearchSettings" -Force | Out-Null
                        }
                        Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\SearchSettings" -Name "IsAADCloudSearchEnabled" -Value 0 -Type DWord -Force
                        Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\SearchSettings" -Name "IsDeviceSearchHistoryEnabled" -Value 0 -Type DWord -Force
                        Write-LogMessage "Disabled web search in feeds" -Level "INFO"
                    } catch {
                        Write-LogMessage "Could not disable web search in feeds: $_" -Level "DEBUG"
                    }
                    
                    Write-LogMessage "Widgets/Weather/News removal tweaks applied successfully" -Level "SUCCESS"
                    $removedCount++
                } catch {
                    Write-LogMessage "Failed to apply Widgets/Weather/News removal tweaks: $_" -Level "WARNING"
                }
            }
            
            # Special handling for Internet Explorer (Windows 10 only)
            if ($BloatwareKey -eq "internet-explorer") {
                Write-LogMessage "Applying Internet Explorer disable (Windows Feature)..." -Level "INFO"
                try {
                    # Check Windows version - IE should only be handled on Windows 10
                    $windowsVersion = [System.Environment]::OSVersion.Version
                    $isWindows10 = $windowsVersion.Major -eq 10 -and $windowsVersion.Build -lt 22000
                    $isWindows11 = $windowsVersion.Major -eq 10 -and $windowsVersion.Build -ge 22000
                    
                    if ($isWindows11) {
                        Write-LogMessage "Internet Explorer is not available on Windows 11 - skipping" -Level "WARNING"
                        Save-OperationState -OperationType "RemoveBloatware" -ItemKey $BloatwareKey -Status "Skipped" -AdditionalData @{
                            Reason = "Not available on Windows 11"
                            WindowsVersion = $windowsVersion.Build
                        }
                        return $true
                    }
                    
                    Write-LogMessage "Proceeding with Internet Explorer disable..." -Level "INFO"
                    
                    # Method 1: Disable via DISM (most reliable)
                    Write-LogMessage "Disabling Internet Explorer via DISM..." -Level "INFO"
                    try {
                        $dismResult = & dism /online /Disable-Feature /FeatureName:Internet-Explorer-Optional-amd64 /NoRestart /Quiet
                        if ($LASTEXITCODE -eq 0) {
                            Write-LogMessage "Successfully disabled Internet Explorer via DISM" -Level "SUCCESS"
                            $removedCount++
                        } else {
                            Write-LogMessage "DISM command failed with exit code: $LASTEXITCODE" -Level "WARNING"
                            # Fall back to PowerShell method
                            throw "DISM method failed, trying PowerShell method"
                        }
                    } catch {
                        Write-LogMessage "DISM method failed: $($_). Trying PowerShell method..." -Level "WARNING"
                        
                        # Method 2: PowerShell fallback
                        try {
                            Write-LogMessage "Disabling Internet Explorer via PowerShell..." -Level "INFO"
                            Disable-WindowsOptionalFeature -FeatureName Internet-Explorer-Optional-amd64 -Online -NoRestart -ErrorAction Stop
                            Write-LogMessage "Successfully disabled Internet Explorer via PowerShell" -Level "SUCCESS"
                            $removedCount++
                        } catch {
                            Write-LogMessage "PowerShell method also failed: $_" -Level "ERROR"
                            throw $_
                        }
                    }
                    
                    # Add restart requirement
                    $script:RestartRequired = $true
                    Add-RestartRegistryChange -ChangeDescription "Disable Internet Explorer 11"
                    
                    Write-LogMessage "Internet Explorer has been disabled. System restart required for changes to take effect." -Level "SUCCESS"
                    Write-LogMessage "WARNING: IE Mode in Microsoft Edge will no longer function." -Level "WARNING"
                    
                } catch {
                    Write-LogMessage "Failed to disable Internet Explorer: $_" -Level "ERROR"
                    Write-LogMessage "You can manually disable IE through: Control Panel > Programs > Turn Windows features on or off > Uncheck Internet Explorer 11" -Level "INFO"
                }
            }
            
            # Special handling for Windows Copilot (both Win10 and Win11)
            if ($BloatwareKey -eq "ms-copilot") {
                Write-LogMessage "Applying Windows Copilot removal and registry tweaks..." -Level "INFO"
                try {
                    # Detect Windows version for proper handling
                    $windowsVersion = [System.Environment]::OSVersion.Version
                    $isWindows10 = $windowsVersion.Major -eq 10 -and $windowsVersion.Build -lt 22000
                    $isWindows11 = $windowsVersion.Major -eq 10 -and $windowsVersion.Build -ge 22000
                    
                    Write-LogMessage "Detected Windows version: Build $($windowsVersion.Build) $(if($isWindows10){'(Windows 10)'}else{'(Windows 11)'})" -Level "INFO"
                    
                    # Method 1: System-wide Copilot disable via Group Policy (Both Win10 & Win11)
                    if (-not (Test-Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot")) {
                        New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot" -Force | Out-Null
                    }
                    Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot" -Name "TurnOffWindowsCopilot" -Value 1 -Type DWord -Force
                    Write-LogMessage "Applied system-wide Copilot disable policy" -Level "INFO"
                    
                    # Method 2: User-level Copilot disable (Critical for Windows 10)
                    if (-not (Test-Path "HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot")) {
                        New-Item -Path "HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot" -Force | Out-Null
                    }
                    Set-ItemProperty -Path "HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot" -Name "TurnOffWindowsCopilot" -Value 1 -Type DWord -Force
                    Write-LogMessage "Applied user-level Copilot disable policy" -Level "INFO"
                    
                    # Method 3: Remove Copilot button from taskbar
                    if (-not (Test-Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced")) {
                        New-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Force | Out-Null
                    }
                    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "ShowCopilotButton" -Value 0 -Type DWord -Force
                    Write-LogMessage "Disabled Copilot button on taskbar" -Level "INFO"
                    
                    # Method 4: Windows 10 specific - Disable AI features
                    if ($isWindows10) {
                        # Disable Windows AI Platform (Windows 10 2024 H2)
                        try {
                            if (-not (Test-Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AI")) {
                                New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AI" -Force | Out-Null
                            }
                            Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AI" -Name "DisableAIDataAnalysis" -Value 1 -Type DWord -Force
                            Write-LogMessage "Disabled Windows 10 AI features" -Level "INFO"
                        } catch {
                            Write-LogMessage "Could not disable AI features (may not be available): $_" -Level "DEBUG"
                        }
                        
                        # Windows 10 Copilot context menu disable
                        try {
                            if (-not (Test-Path "HKCU:\Software\Microsoft\Windows\Shell\Copilot")) {
                                New-Item -Path "HKCU:\Software\Microsoft\Windows\Shell\Copilot" -Force | Out-Null
                            }
                            Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\Shell\Copilot" -Name "IsCopilotAvailable" -Value 0 -Type DWord -Force
                            Write-LogMessage "Disabled Windows 10 Copilot context integration" -Level "INFO"
                        } catch {
                            Write-LogMessage "Could not disable Copilot context integration: $_" -Level "DEBUG"
                        }
                    }
                    
                    Write-LogMessage "Windows Copilot removal and registry tweaks applied successfully" -Level "SUCCESS"
                    $removedCount++
                } catch {
                    Write-LogMessage "Failed to apply Copilot removal tweaks: $_" -Level "WARNING"
                }
            }
            
            if ($removedCount -gt 0) {
                Write-LogMessage "Successfully removed $removedCount package(s) for: $BloatwareKey" -Level "SUCCESS"
            } else {
                Write-LogMessage "No packages found matching patterns for: $BloatwareKey (patterns: $($packageNames -join ', '))" -Level "WARNING"
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