# System optimization modules for Windows Setup GUI

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

    Write-Log "Applying optimization: $OptimizationKey" -Level "INFO"

    switch ($OptimizationKey) {
        "DisableTelemetry" {
            Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" -Name "AllowTelemetry" -Value 0
            Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection" -Name "AllowTelemetry" -Value 0
        }
        "DisableCortana" {
            Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search" -Name "AllowCortana" -Value 0
        }
        "DisableWindowsSearch" {
            Stop-Service "WSearch" -Force
            Set-Service "WSearch" -StartupType Disabled
        }
        "DisableWindowsUpdate" {
            Stop-Service "wuauserv" -Force
            Set-Service "wuauserv" -StartupType Disabled
        }
        "DisableWindowsDefender" {
            Set-MpPreference -DisableRealtimeMonitoring $true
            Set-MpPreference -DisableIOAVProtection $true
        }
        "DisableWindowsFirewall" {
            Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled False
        }
        default {
            Write-Log "Unknown optimization key: $OptimizationKey" -Level "ERROR"
            return $false
        }
    }

    Write-Log "Successfully applied optimization: $OptimizationKey" -Level "SUCCESS"
    return $true
}

Export-ModuleMember -Function Optimize-System, Remove-Bloatware, Configure-Services, Apply-Optimization 