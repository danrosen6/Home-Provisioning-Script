# Logging utilities for Windows Setup GUI

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
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    
    # Write to log file
    if ($LogFile) {
        Add-Content -Path $LogFile -Value $logMessage
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

function Initialize-Logging {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [string]$LogDirectory = "logs"
    )
    
    # Create logs directory if it doesn't exist
    if (-not (Test-Path $LogDirectory)) {
        New-Item -ItemType Directory -Path $LogDirectory -Force | Out-Null
    }
    
    # Create log file with timestamp
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $script:LogFile = Join-Path $LogDirectory "setup-log-$timestamp.txt"
    
    Write-Log "Logging initialized. Log file: $($script:LogFile)" -Level "INFO"
}

Export-ModuleMember -Function Write-Log, Initialize-Logging 