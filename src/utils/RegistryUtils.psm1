# Registry utilities for Windows Setup GUI

function Set-RegistryValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,
        
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,
        
        [Parameter(Mandatory=$true)]
        [AllowNull()]
        $Value,
        
        [Parameter(Mandatory=$false)]
        [ValidateSet("String", "ExpandString", "Binary", "DWord", "MultiString", "QWord")]
        [string]$Type = "DWord",
        
        [Parameter(Mandatory=$false)]
        [switch]$CreatePath,
        
        [Parameter(Mandatory=$false)]
        [switch]$BackupOriginal
    )
    
    try {
        # Backup original value if requested
        if ($BackupOriginal) {
            Save-RegistryValue -Path $Path -Name $Name
        }
        
        # Create registry path if it doesn't exist and CreatePath is specified
        if ($CreatePath -and -not (Test-Path $Path)) {
            Write-Verbose "Creating registry path: $Path"
            New-Item -Path $Path -Force | Out-Null
        }
        
        # Verify path exists
        if (-not (Test-Path $Path)) {
            throw "Registry path does not exist: $Path"
        }
        
        # Set the registry value
        Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type $Type -Force
        Write-Verbose "Set registry value: $Path\$Name = $Value ($Type)"
        
        return $true
    }
    catch {
        Write-Error "Failed to set registry value $Path\$Name: $_"
        return $false
    }
}

function Get-RegistryValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,
        
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,
        
        [Parameter(Mandatory=$false)]
        $DefaultValue = $null
    )
    
    try {
        if (Test-Path $Path) {
            $property = Get-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue
            if ($property) {
                return $property.$Name
            }
        }
        
        return $DefaultValue
    }
    catch {
        Write-Verbose "Failed to get registry value $Path\$Name: $_"
        return $DefaultValue
    }
}

function Remove-RegistryValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,
        
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,
        
        [Parameter(Mandatory=$false)]
        [switch]$BackupOriginal
    )
    
    try {
        # Backup original value if requested
        if ($BackupOriginal) {
            Save-RegistryValue -Path $Path -Name $Name
        }
        
        if (Test-Path $Path) {
            Remove-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue
            Write-Verbose "Removed registry value: $Path\$Name"
            return $true
        }
        
        return $false
    }
    catch {
        Write-Error "Failed to remove registry value $Path\$Name: $_"
        return $false
    }
}

function Set-MultipleRegistryValues {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [hashtable[]]$RegistryEntries,
        
        [Parameter(Mandatory=$false)]
        [switch]$BackupOriginals,
        
        [Parameter(Mandatory=$false)]
        [switch]$ContinueOnError
    )
    
    $results = @()
    $successCount = 0
    $failureCount = 0
    
    foreach ($entry in $RegistryEntries) {
        try {
            # Validate required fields
            if (-not $entry.Path -or -not $entry.Name) {
                throw "Registry entry missing required Path or Name field"
            }
            
            $params = @{
                Path = $entry.Path
                Name = $entry.Name
                Value = $entry.Value
                BackupOriginal = $BackupOriginals
            }
            
            # Add optional parameters if present
            if ($entry.Type) { $params.Type = $entry.Type }
            if ($entry.CreatePath) { $params.CreatePath = $entry.CreatePath }
            
            $success = Set-RegistryValue @params
            
            $results += @{
                Path = $entry.Path
                Name = $entry.Name
                Success = $success
                Error = $null
            }
            
            if ($success) {
                $successCount++
            } else {
                $failureCount++
                if (-not $ContinueOnError) {
                    break
                }
            }
        }
        catch {
            $failureCount++
            $results += @{
                Path = $entry.Path
                Name = $entry.Name
                Success = $false
                Error = $_.Exception.Message
            }
            
            Write-Error "Failed to set registry entry $($entry.Path)\$($entry.Name): $_"
            
            if (-not $ContinueOnError) {
                break
            }
        }
    }
    
    return @{
        Results = $results
        SuccessCount = $successCount
        FailureCount = $failureCount
        TotalEntries = $RegistryEntries.Count
    }
}

function Enable-PrivacySettings {
    [CmdletBinding()]
    param()
    
    Write-Verbose "Applying privacy registry settings..."
    
    $privacySettings = @(
        # Disable telemetry
        @{
            Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection"
            Name = "AllowTelemetry"
            Value = 0
            CreatePath = $true
        },
        @{
            Path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection"
            Name = "AllowTelemetry"
            Value = 0
            CreatePath = $true
        },
        
        # Disable activity history
        @{
            Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System"
            Name = "EnableActivityFeed"
            Value = 0
            CreatePath = $true
        },
        @{
            Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System"
            Name = "PublishUserActivities"
            Value = 0
            CreatePath = $true
        },
        
        # Disable background apps
        @{
            Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications"
            Name = "GlobalUserDisabled"
            Value = 1
            CreatePath = $true
        },
        
        # Disable tips and suggestions
        @{
            Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
            Name = "SubscribedContent-338389Enabled"
            Value = 0
            CreatePath = $true
        },
        @{
            Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
            Name = "SystemPaneSuggestionsEnabled"
            Value = 0
            CreatePath = $true
        },
        @{
            Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
            Name = "SoftLandingEnabled"
            Value = 0
            CreatePath = $true
        }
    )
    
    return Set-MultipleRegistryValues -RegistryEntries $privacySettings -BackupOriginals -ContinueOnError
}

function Enable-FileExplorerSettings {
    [CmdletBinding()]
    param()
    
    Write-Verbose "Applying File Explorer registry settings..."
    
    $explorerSettings = @(
        # Show file extensions
        @{
            Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
            Name = "HideFileExt"
            Value = 0
            CreatePath = $true
        },
        
        # Show hidden files
        @{
            Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
            Name = "Hidden"
            Value = 1
            CreatePath = $true
        },
        
        # Disable quick access recent files
        @{
            Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer"
            Name = "ShowFrequent"
            Value = 0
            CreatePath = $true
        },
        @{
            Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer"
            Name = "ShowRecent"
            Value = 0
            CreatePath = $true
        }
    )
    
    return Set-MultipleRegistryValues -RegistryEntries $explorerSettings -BackupOriginals -ContinueOnError
}

function Enable-Windows11Optimizations {
    [CmdletBinding()]
    param()
    
    Write-Verbose "Applying Windows 11 registry optimizations..."
    
    $win11Settings = @(
        # Taskbar left alignment
        @{
            Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
            Name = "TaskbarAl"
            Value = 0
            CreatePath = $true
        },
        
        # Classic right-click menu
        @{
            Path = "HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32"
            Name = "(Default)"
            Value = ""
            Type = "String"
            CreatePath = $true
        },
        
        # Disable widgets
        @{
            Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
            Name = "TaskbarDa"
            Value = 0
            CreatePath = $true
        },
        
        # Disable Chat icon
        @{
            Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
            Name = "TaskbarMn"
            Value = 0
            CreatePath = $true
        },
        
        # Disable Snap layouts hover
        @{
            Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
            Name = "EnableSnapAssistFlyout"
            Value = 0
            CreatePath = $true
        }
    )
    
    return Set-MultipleRegistryValues -RegistryEntries $win11Settings -BackupOriginals -ContinueOnError
}

function Enable-Windows10Optimizations {
    [CmdletBinding()]
    param()
    
    Write-Verbose "Applying Windows 10 registry optimizations..."
    
    $win10Settings = @(
        # Hide Task View button
        @{
            Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
            Name = "ShowTaskViewButton"
            Value = 0
            CreatePath = $true
        },
        
        # Hide Cortana button
        @{
            Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Taskband"
            Name = "ShowCortanaButton"
            Value = 0
            CreatePath = $true
        },
        
        # Configure search box (show search box = 2)
        @{
            Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search"
            Name = "SearchboxTaskbarMode"
            Value = 2
            CreatePath = $true
        },
        
        # Disable News and Interests
        @{
            Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Feeds"
            Name = "ShellFeedsTaskbarViewMode"
            Value = 2
            CreatePath = $true
        }
    )
    
    return Set-MultipleRegistryValues -RegistryEntries $win10Settings -BackupOriginals -ContinueOnError
}

# Import backup/restore functions from SystemOptimizations if available
$backupModule = Join-Path (Split-Path $PSScriptRoot) "modules\SystemOptimizations.psm1"
if (Test-Path $backupModule) {
    . $backupModule
    # Functions Save-RegistryValue and Restore-RegistryValue should be available
}

Export-ModuleMember -Function @(
    "Set-RegistryValue",
    "Get-RegistryValue", 
    "Remove-RegistryValue",
    "Set-MultipleRegistryValues",
    "Enable-PrivacySettings",
    "Enable-FileExplorerSettings",
    "Enable-Windows11Optimizations",
    "Enable-Windows10Optimizations"
)