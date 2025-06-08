# Logging utilities for Windows Setup GUI

# Global variables
$script:LogFile = $null
$script:MaxLogSize = 5MB
$script:MaxLogFiles = 5

function Write-LogMessage {
    param (
        [Parameter(Mandatory=$true)]
        [string]$Message,
        
        [Parameter(Mandatory=$false)]
        [ValidateSet("INFO", "WARNING", "ERROR", "SUCCESS")]
        [string]$Level = "INFO"
    )
    
    try {
        if (-not $script:LogFile) {
            Initialize-Logging
        }
        
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $logMessage = "[$timestamp] [$Level] $Message"
        
        # Check if log file exists and create directory if needed
        $logDir = Split-Path -Parent $script:LogFile
        if (-not (Test-Path $logDir)) {
            New-Item -ItemType Directory -Path $logDir -Force | Out-Null
        }
        
        # Check log file size and rotate if needed
        if ((Test-Path $script:LogFile) -and ((Get-Item $script:LogFile).Length -gt $script:MaxLogSize)) {
            Rotate-LogFile
        }
        
        # Write to log file
        Add-Content -Path $script:LogFile -Value $logMessage
        
        # Write to console with color
        $color = switch ($Level) {
            "ERROR" { "Red" }
            "WARNING" { "Yellow" }
            "SUCCESS" { "Green" }
            default { "White" }
        }
        Write-Host $logMessage -ForegroundColor $color
    }
    catch {
        Write-Host "Failed to write to log: $_"
    }
}

function Initialize-Logging {
    try {
        $logDir = Join-Path $PSScriptRoot "..\logs"
        if (-not (Test-Path $logDir)) {
            New-Item -ItemType Directory -Path $logDir -Force | Out-Null
        }
        
        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $script:LogFile = Join-Path $logDir "setup_${timestamp}.log"
        
        # Test write permissions
        $testMessage = "[$timestamp] [INFO] Logging initialized"
        Add-Content -Path $script:LogFile -Value $testMessage
        
        Write-Host $testMessage
    }
    catch {
        Write-Host "Failed to initialize logging: $_"
    }
}

function Rotate-LogFile {
    try {
        $logDir = Split-Path -Parent $script:LogFile
        $logFiles = Get-ChildItem -Path $logDir -Filter "setup_*.log" | Sort-Object LastWriteTime -Descending
        
        # Remove old log files if we have too many
        if ($logFiles.Count -ge $script:MaxLogFiles) {
            $logFiles | Select-Object -Skip $script:MaxLogFiles | Remove-Item -Force
        }
        
        # Create new log file
        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $script:LogFile = Join-Path $logDir "setup_${timestamp}.log"
    }
    catch {
        Write-Host "Failed to rotate log file: $_"
    }
}

Export-ModuleMember -Function Write-LogMessage, Initialize-Logging, Rotate-LogFile 