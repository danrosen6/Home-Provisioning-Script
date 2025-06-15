# Recovery utilities for Windows Setup GUI

# Import JSON utilities for PowerShell 5.1 compatibility
$jsonUtilsPath = Join-Path $PSScriptRoot "JsonUtils.psm1"
if (Test-Path $jsonUtilsPath) {
    Import-Module $jsonUtilsPath -Force
}

function New-SystemRestorePoint {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [string]$Description = "Windows Setup Automation"
    )
    
    try {
        Write-LogMessage "Creating system restore point..." -Level "INFO"
        
        # Check if System Restore is enabled
        $srEnabled = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore" -Name "RPSessionInterval" -ErrorAction SilentlyContinue).RPSessionInterval -ne 0
        
        if (-not $srEnabled) {
            Write-LogMessage "System Restore is not enabled. Attempting to enable..." -Level "WARNING"
            try {
                # Enable System Restore
                Enable-ComputerRestore -Drive $env:SystemDrive
                Write-LogMessage "System Restore has been enabled" -Level "SUCCESS"
            }
            catch {
                Write-LogMessage "Failed to enable System Restore: $_" -Level "ERROR"
                return $false
            }
        }
        
        # Create restore checkpoint
        $result = Checkpoint-Computer -Description $Description -RestorePointType "APPLICATION_INSTALL" -ErrorAction Stop
        
        if ($result) {
            Write-LogMessage "System restore point created successfully" -Level "SUCCESS"
            return $true
        } else {
            Write-LogMessage "Failed to create system restore point" -Level "ERROR"
            return $false
        }
    }
    catch {
        Write-LogMessage "Error creating system restore point: $_" -Level "ERROR"
        return $false
    }
}

function Save-OperationState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$OperationType,
        
        [Parameter(Mandatory=$true)]
        [string]$ItemKey,
        
        [Parameter(Mandatory=$false)]
        [string]$Status = "Pending",
        
        [Parameter(Mandatory=$false)]
        [hashtable]$AdditionalData = @{}
    )
    
    try {
        # Create recovery directory if it doesn't exist
        $recoveryDir = Join-Path $PSScriptRoot "..\recovery"
        if (-not (Test-Path $recoveryDir)) {
            New-Item -ItemType Directory -Path $recoveryDir -Force | Out-Null
        }
        
        # Create or update recovery state file
        $stateFile = Join-Path $recoveryDir "operation_state.json"
        
        # Load existing state if available
        $state = @{}
        if (Test-Path $stateFile) {
            $stateContent = Get-Content -Path $stateFile -Raw -ErrorAction SilentlyContinue
            if ($stateContent) {
                try {
                    $state = $stateContent | ConvertFrom-JsonToHashtable
                } catch {
                    $state = @{}
                }
            }
        }
        
        # Initialize operation type if it doesn't exist
        if (-not $state.ContainsKey($OperationType)) {
            $state[$OperationType] = @{}
        }
        
        # Update or add item state
        $state[$OperationType][$ItemKey] = @{
            Status = $Status
            Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            Data = $AdditionalData
        }
        
        # Save updated state
        $state | ConvertTo-Json -Depth 5 | Set-Content -Path $stateFile -Force
        
        return $true
    }
    catch {
        Write-LogMessage "Failed to save operation state: $_" -Level "ERROR"
        return $false
    }
}

function Get-OperationState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [string]$OperationType = "",
        
        [Parameter(Mandatory=$false)]
        [string]$ItemKey = ""
    )
    
    try {
        # Check if recovery state file exists
        $stateFile = Join-Path $PSScriptRoot "..\recovery\operation_state.json"
        if (-not (Test-Path $stateFile)) {
            return $null
        }
        
        # Load state
        $stateContent = Get-Content -Path $stateFile -Raw -ErrorAction SilentlyContinue
        if (-not $stateContent) {
            return $null
        }
        
        try {
            $state = $stateContent | ConvertFrom-JsonToHashtable
        } catch {
            Write-LogMessage "Error parsing state file: $_" -Level "ERROR"
            return $null
        }
        
        # Return specific operation type if requested
        if ($OperationType -and $state.ContainsKey($OperationType)) {
            # Return specific item if requested
            if ($ItemKey -and $state[$OperationType].ContainsKey($ItemKey)) {
                return $state[$OperationType][$ItemKey]
            }
            
            # Otherwise return the whole operation type
            return $state[$OperationType]
        }
        
        # Return everything if no specific request
        return $state
    }
    catch {
        Write-LogMessage "Failed to get operation state: $_" -Level "ERROR"
        return $null
    }
}

function Restore-FailedOperations {
    [CmdletBinding()]
    param()
    
    try {
        Write-LogMessage "Checking for failed operations to recover..." -Level "INFO"
        
        $state = Get-OperationState
        if (-not $state) {
            Write-LogMessage "No recovery state found" -Level "INFO"
            return $false
        }
        
        $recoveryNeeded = $false
        
        # Check each operation type
        foreach ($opType in $state.Keys) {
            $operations = $state[$opType]
            
            foreach ($itemKey in $operations.Keys) {
                $item = $operations[$itemKey]
                
                # Check for failed or incomplete operations
                if ($item.Status -eq "Failed" -or $item.Status -eq "InProgress") {
                    $recoveryNeeded = $true
                    
                    Write-LogMessage "Found failed operation: $opType - $itemKey" -Level "WARNING"
                    
                    switch ($opType) {
                        "InstallApp" {
                            # Retry app installation
                            Write-LogMessage "Attempting to recover failed app installation: $itemKey" -Level "INFO"
                            Install-Application -AppName $itemKey
                        }
                        "RemoveBloatware" {
                            # Retry bloatware removal
                            Write-LogMessage "Attempting to recover failed bloatware removal: $itemKey" -Level "INFO"
                            Remove-Bloatware -BloatwareKey $itemKey
                        }
                        "ServiceConfig" {
                            # Retry service configuration
                            Write-LogMessage "Attempting to recover failed service configuration: $itemKey" -Level "INFO"
                            Set-SystemOptimization -OptimizationKey $itemKey
                        }
                        "SystemOptimization" {
                            # Retry optimization
                            Write-LogMessage "Attempting to recover failed system optimization: $itemKey" -Level "INFO"
                            Set-SystemOptimization -OptimizationKey $itemKey
                        }
                        default {
                            Write-LogMessage "Unknown operation type: $opType - cannot recover" -Level "WARNING"
                        }
                    }
                }
            }
        }
        
        if (-not $recoveryNeeded) {
            Write-LogMessage "No failed operations found that need recovery" -Level "INFO"
        }
        
        return $recoveryNeeded
    }
    catch {
        Write-LogMessage "Failed to restore operations: $_" -Level "ERROR"
        return $false
    }
}

# Export the functions
Export-ModuleMember -Function New-SystemRestorePoint, Save-OperationState, Get-OperationState, Restore-FailedOperations