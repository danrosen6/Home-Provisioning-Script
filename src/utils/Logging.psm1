# Logging utilities for Windows Setup GUI

# Global variables
$script:LogFile = $null
$script:MaxLogSize = 10MB
$script:MaxLogFiles = 5

function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,
        
        [Parameter(Mandatory=$false)]
        [ValidateSet("INFO", "WARNING", "ERROR", "SUCCESS")]
        [string]$Level = "INFO",
        
        [Parameter(Mandatory=$false)]
        [string]$LogFile = $script:LogFile
    )
    
    try {
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $logMessage = "[$timestamp] [$Level] $Message"
        
        # Write to log file
        if ($LogFile) {
            # Check if log file exists and rotate if needed
            if (Test-Path $LogFile) {
                $fileSize = (Get-Item $LogFile).Length
                if ($fileSize -gt $script:MaxLogSize) {
                    Rotate-LogFile -LogFile $LogFile
                }
            }
            
            # Ensure directory exists
            $logDir = Split-Path -Parent $LogFile
            if (-not (Test-Path $logDir)) {
                New-Item -ItemType Directory -Path $logDir -Force | Out-Null
            }
            
            Add-Content -Path $LogFile -Value $logMessage -ErrorAction Stop
        }
        
        # Write to console with color
        $color = switch ($Level) {
            "INFO" { "White" }
            "WARNING" { "Yellow" }
            "ERROR" { "Red" }
            "SUCCESS" { "Green" }
            default { "White" }
        }
        
        Write-Host $logMessage -ForegroundColor $color
    }
    catch {
        Write-Host "Failed to write log: $_" -ForegroundColor Red
    }
}

function Rotate-LogFile {
    param(
        [Parameter(Mandatory=$true)]
        [string]$LogFile
    )
    
    try {
        $logDir = Split-Path -Parent $LogFile
        $logName = Split-Path -Leaf $LogFile
        $logBase = [System.IO.Path]::GetFileNameWithoutExtension($logName)
        $logExt = [System.IO.Path]::GetExtension($logName)
        
        # Remove oldest log if we have too many
        $existingLogs = Get-ChildItem -Path $logDir -Filter "$logBase*$logExt" | Sort-Object LastWriteTime -Descending
        if ($existingLogs.Count -ge $script:MaxLogFiles) {
            $existingLogs | Select-Object -Last 1 | Remove-Item -Force
        }
        
        # Rename current log with timestamp
        $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
        $newName = "$logBase-$timestamp$logExt"
        $newPath = Join-Path $logDir $newName
        Rename-Item -Path $LogFile -NewName $newName -Force
    }
    catch {
        Write-Host "Failed to rotate log file: $_" -ForegroundColor Red
    }
}

function Initialize-Logging {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [string]$LogDirectory = "logs"
    )
    
    try {
        # Create logs directory if it doesn't exist
        if (-not (Test-Path $LogDirectory)) {
            New-Item -ItemType Directory -Path $LogDirectory -Force | Out-Null
        }
        
        # Create log file with timestamp
        $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
        $script:LogFile = Join-Path $LogDirectory "setup-log-$timestamp.txt"
        
        # Test write permissions
        Add-Content -Path $script:LogFile -Value "Logging initialized" -ErrorAction Stop
        
        Write-Log "Logging initialized. Log file: $($script:LogFile)" -Level "INFO"
        return $true
    }
    catch {
        Write-Host "Failed to initialize logging: $_" -ForegroundColor Red
        return $false
    }
}

Export-ModuleMember -Function Write-Log, Initialize-Logging, Rotate-LogFile 