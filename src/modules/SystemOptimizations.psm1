# System optimization modules for Windows Setup GUI

# Global variables
$script:RegistryBackups = @{}
$script:ServiceBackups = @{}

function Backup-RegistryValue {
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
        Write-Log "Failed to backup registry value: $_" -Level "ERROR"
        return $false
    }
}

function Backup-Service {
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
        Write-Log "Failed to backup service: $_" -Level "ERROR"
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
            Write-Log "Restored registry value: ${Path}\${Name}" -Level "INFO"
            return $true
        }
        return $false
    }
    catch {
        Write-Log "Failed to restore registry value: $_" -Level "ERROR"
        return $false
    }
}

function Restore-Service {
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
            Write-Log "Restored service: ${ServiceName}" -Level "INFO"
            return $true
        }
        return $false
    }
    catch {
        Write-Log "Failed to restore service: $_" -Level "ERROR"
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

function Apply-Optimization {
    param (
        [string]$OptimizationKey,
        [System.Threading.CancellationToken]$CancellationToken
    )

    Write-Log "Applying optimization: ${OptimizationKey}" -Level "INFO"

    try {
        switch ($OptimizationKey) {
            "DisableTelemetry" {
                # Backup current settings
                Backup-RegistryValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" -Name "AllowTelemetry"
                Backup-RegistryValue -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection" -Name "AllowTelemetry"
                
                # Apply changes
                Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" -Name "AllowTelemetry" -Value 0
                Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection" -Name "AllowTelemetry" -Value 0
            }
            "DisableCortana" {
                Backup-RegistryValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search" -Name "AllowCortana"
                Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search" -Name "AllowCortana" -Value 0
            }
            "DisableWindowsSearch" {
                Backup-Service -ServiceName "WSearch"
                Stop-Service "WSearch" -Force
                Set-Service "WSearch" -StartupType Disabled
            }
            "DisableWindowsUpdate" {
                Backup-Service -ServiceName "wuauserv"
                Stop-Service "wuauserv" -Force
                Set-Service "wuauserv" -StartupType Disabled
            }
            "DisableWindowsDefender" {
                Backup-RegistryValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender" -Name "DisableAntiSpyware"
                Set-MpPreference -DisableRealtimeMonitoring $true
                Set-MpPreference -DisableIOAVProtection $true
            }
            "DisableWindowsFirewall" {
                Backup-RegistryValue -Path "HKLM:\SYSTEM\CurrentControlSet\Services\SharedAccess\Parameters\FirewallPolicy\StandardProfile" -Name "EnableFirewall"
                Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled False
            }
            default {
                throw "Unknown optimization key: ${OptimizationKey}"
            }
        }

        Write-Log "Successfully applied optimization: ${OptimizationKey}" -Level "SUCCESS"
        return $true
    }
    catch {
        Write-Log "Failed to apply optimization ${OptimizationKey}: $_" -Level "ERROR"
        
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
                    Restore-Service -ServiceName "WSearch"
                }
                "DisableWindowsUpdate" {
                    Restore-Service -ServiceName "wuauserv"
                }
                "DisableWindowsDefender" {
                    Restore-RegistryValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender" -Name "DisableAntiSpyware"
                }
                "DisableWindowsFirewall" {
                    Restore-RegistryValue -Path "HKLM:\SYSTEM\CurrentControlSet\Services\SharedAccess\Parameters\FirewallPolicy\StandardProfile" -Name "EnableFirewall"
                }
            }
            Write-Log "Successfully rolled back optimization: ${OptimizationKey}" -Level "INFO"
        }
        catch {
            Write-Log "Failed to roll back optimization ${OptimizationKey}: $_" -Level "ERROR"
        }
        
        return $false
    }
}

Export-ModuleMember -Function Optimize-System, Remove-Bloatware, Configure-Services, Apply-Optimization, Backup-RegistryValue, Backup-Service, Restore-RegistryValue, Restore-Service 