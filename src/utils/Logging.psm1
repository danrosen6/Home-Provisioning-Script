# Logging utilities for Windows Setup GUI

# Global variables
$script:LogFile = $null
$script:MaxLogSize = 5MB
$script:MaxLogFiles = 5
$script:LogErrorShown = $false

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
    
    # Write to console with color (always do this first)
    $color = switch ($Level) {
        "ERROR" { "Red" }
        "WARNING" { "Yellow" }
        "SUCCESS" { "Green" }
        default { "White" }
    }
    Write-Host $logMessage -ForegroundColor $color
    
    # Try to write to log file
    try {
        if (-not $script:LogFile) {
            Initialize-Logging
        }
        
        if ($script:LogFile) {
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
            Add-Content -Path $script:LogFile -Value $logMessage -ErrorAction Stop
        }
    }
    catch {
        # Only show this error once to avoid spam
        if (-not $script:LogErrorShown) {
            Write-Host "Warning: Failed to write to log file ($($script:LogFile)): $_" -ForegroundColor Yellow
            $script:LogErrorShown = $true
        }
    }
}

function Initialize-Logging {
    try {
        # Determine the correct log directory based on script location
        $srcPath = Split-Path -Parent $PSScriptRoot
        $logDir = Join-Path $srcPath "logs"
        
        # If that doesn't exist, create logs directory in the src folder
        if (-not (Test-Path $logDir)) {
            $logDir = Join-Path $PSScriptRoot "..\logs"
            if (-not (Test-Path $logDir)) {
                New-Item -ItemType Directory -Path $logDir -Force | Out-Null
                Write-Host "Created log directory: $logDir" -ForegroundColor Green
            }
        }
        
        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $script:LogFile = Join-Path $logDir "setup_${timestamp}.log"
        
        # Test write permissions
        $testMessage = "[$timestamp] [INFO] Logging initialized - Log file: $($script:LogFile)"
        Add-Content -Path $script:LogFile -Value $testMessage
        
        Write-Host $testMessage -ForegroundColor Green
    }
    catch {
        Write-Host "Failed to initialize logging: $_" -ForegroundColor Red
        Write-Host "Attempted log directory: $logDir" -ForegroundColor Yellow
        Write-Host "PSScriptRoot: $PSScriptRoot" -ForegroundColor Yellow
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

function Get-LogFilePath {
    return $script:LogFile
}

function Get-LogDirectory {
    if ($script:LogFile) {
        return Split-Path -Parent $script:LogFile
    }
    return $null
}

Export-ModuleMember -Function Write-LogMessage, Initialize-Logging, Rotate-LogFile, Get-LogFilePath, Get-LogDirectory 