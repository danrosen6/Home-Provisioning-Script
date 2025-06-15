# Configuration loader utility for Windows Setup GUI

# Import JSON utilities for PowerShell 5.1 compatibility
$jsonUtilsPath = Join-Path $PSScriptRoot "JsonUtils.psm1"
if (Test-Path $jsonUtilsPath) {
    Import-Module $jsonUtilsPath -Force
}

function Get-ConfigurationData {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateSet("Apps", "Bloatware", "Services", "Tweaks")]
        [string]$ConfigType
    )
    
    try {
        $configPath = Join-Path $PSScriptRoot "..\config\$($ConfigType.ToLower()).json"
        
        if (-not (Test-Path $configPath)) {
            Write-Warning "Configuration file not found: $configPath"
            return @{}
        }
        
        $jsonContent = Get-Content -Path $configPath -Raw -ErrorAction Stop
        $configData = $jsonContent | ConvertFrom-JsonToHashtable -ErrorAction Stop
        
        Write-Verbose "Successfully loaded $ConfigType configuration with $($configData.Keys.Count) categories"
        return $configData
    }
    catch {
        Write-Error "Failed to load $ConfigType configuration: $_"
        return @{}
    }
}

function Get-WingetIdMapping {
    [CmdletBinding()]
    param()
    
    return @{
        "vscode" = "Microsoft.VisualStudioCode"
        "git" = "Git.Git"
        "python" = "Python.Python.3.13"
        "pycharm" = "JetBrains.PyCharm.Community"
        "intellij" = "JetBrains.IntelliJIDEA.Community"
        "webstorm" = "JetBrains.WebStorm"
        "androidstudio" = "JetBrains.AndroidStudio"
        "github" = "GitHub.GitHubDesktop"
        "postman" = "Postman.Postman"
        "nodejs" = "OpenJS.NodeJS"
        "terminal" = "Microsoft.WindowsTerminal"
        "chrome" = "Google.Chrome"
        "firefox" = "Mozilla.Firefox"
        "brave" = "Brave.Brave"
        "spotify" = "Spotify.Spotify"
        "discord" = "Discord.Discord"
        "steam" = "Valve.Steam"
        "vlc" = "VideoLAN.VLC"
        "7zip" = "7zip.7zip"
        "notepad" = "Notepad++.Notepad++"
        "powertoys" = "Microsoft.PowerToys"
    }
}

function Get-InstallerNameMapping {
    [CmdletBinding()]
    param()
    
    return @{
        "vscode" = "Visual Studio Code"
        "git" = "Git"
        "python" = "Python"
        "pycharm" = "PyCharm"
        "intellij" = "IntelliJ IDEA"
        "webstorm" = "WebStorm"
        "androidstudio" = "Android Studio"
        "github" = "GitHub Desktop"
        "postman" = "Postman"
        "nodejs" = "Node.js"
        "terminal" = "Windows Terminal"
        "chrome" = "Google Chrome"
        "firefox" = "Mozilla Firefox"
        "brave" = "Brave"
        "spotify" = "Spotify"
        "discord" = "Discord"
        "steam" = "Steam"
        "vlc" = "VLC"
        "7zip" = "7-Zip"
        "notepad" = "Notepad++"
        "powertoys" = "Microsoft PowerToys"
    }
}

function Test-ConfigurationIntegrity {
    [CmdletBinding()]
    param()
    
    $configTypes = @("Apps", "Bloatware", "Services", "Tweaks")
    $allValid = $true
    
    foreach ($configType in $configTypes) {
        $config = Get-ConfigurationData -ConfigType $configType
        
        if ($config.Keys.Count -eq 0) {
            Write-Warning "$configType configuration is empty or invalid"
            $allValid = $false
            continue
        }
        
        # Validate structure
        foreach ($category in $config.Keys) {
            $items = $config[$category]
            
            if (-not $items -or $items.Count -eq 0) {
                Write-Warning "$configType category '$category' is empty"
                $allValid = $false
                continue
            }
            
            foreach ($item in $items) {
                $requiredFields = @("Name", "Key", "Default", "Win10", "Win11")
                foreach ($field in $requiredFields) {
                    if (-not $item.ContainsKey($field)) {
                        Write-Warning "$configType item missing required field '$field': $($item | Out-String)"
                        $allValid = $false
                    }
                }
            }
        }
    }
    
    return $allValid
}

Export-ModuleMember -Function @(
    "Get-ConfigurationData",
    "Get-WingetIdMapping", 
    "Get-InstallerNameMapping",
    "Test-ConfigurationIntegrity"
)