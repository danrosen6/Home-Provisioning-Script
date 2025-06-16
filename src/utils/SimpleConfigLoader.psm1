# Simple Configuration Loader for Windows Setup GUI
# Just reads JSON files and converts them to PowerShell objects

function Get-ConfigData {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateSet("apps", "bloatware", "services", "tweaks")]
        [string]$ConfigType
    )
    
    try {
        # Get script directory and build config path
        $configPath = Join-Path (Split-Path $PSScriptRoot) "config\$ConfigType.json"
        
        if (-not (Test-Path $configPath)) {
            Write-Warning "Config file not found: $configPath"
            return @{}
        }
        
        # Read and parse JSON
        $jsonContent = Get-Content -Path $configPath -Raw -Encoding UTF8
        $configData = $jsonContent | ConvertFrom-Json
        
        # Convert to hashtable for easier use
        $result = @{}
        foreach ($property in $configData.PSObject.Properties) {
            $categoryItems = @()
            foreach ($item in $property.Value) {
                $categoryItems += @{
                    Name = $item.Name
                    Key = $item.Key
                    Default = $item.Default
                    Win10 = $item.Win10
                    Win11 = $item.Win11
                    WingetId = $item.WingetId
                }
            }
            $result[$property.Name] = $categoryItems
        }
        
        Write-Verbose "Loaded $ConfigType config with $($result.Keys.Count) categories"
        return $result
        
    } catch {
        Write-Error "Failed to load $ConfigType config: $_"
        return @{}
    }
}

function Get-WingetIdFromConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$AppKey
    )
    
    try {
        $appsConfig = Get-ConfigData -ConfigType "apps"
        
        foreach ($category in $appsConfig.Values) {
            foreach ($app in $category) {
                if ($app.Key -eq $AppKey -and $app.WingetId) {
                    return $app.WingetId
                }
            }
        }
        
        return $null
    } catch {
        return $null
    }
}

Export-ModuleMember -Function Get-ConfigData, Get-WingetIdFromConfig