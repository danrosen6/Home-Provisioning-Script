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
        # More robust path resolution - prioritize config directory structure
        $possiblePaths = @(
            (Join-Path $PSScriptRoot "..\config\$($ConfigType.ToLower()).json"),
            (Join-Path $PSScriptRoot "config\$($ConfigType.ToLower()).json"),
            (Join-Path (Get-Location) "config\$($ConfigType.ToLower()).json"),
            (Join-Path $PSScriptRoot "$($ConfigType.ToLower()).json"),
            (Join-Path (Get-Location) "$($ConfigType.ToLower()).json"),
            (Join-Path (Get-Location) "src\$($ConfigType.ToLower()).json")
        )
        
        $configPath = $null
        foreach ($path in $possiblePaths) {
            if (Test-Path $path) {
                $configPath = $path
                Write-Verbose "Found config file at: $configPath"
                break
            }
        }
        
        if (-not $configPath) {
            $errorMessage = "Configuration file not found for $ConfigType. Searched paths: $($possiblePaths -join ', ')"
            Write-Warning $errorMessage
            try {
                Write-LogMessage $errorMessage -Level "ERROR"
            } catch {
                # Logging not available, continue with warning only
            }
            return @{}
        }
        
        $jsonContent = Get-Content -Path $configPath -Raw -ErrorAction Stop
        $configData = $jsonContent | ConvertFrom-JsonToHashtable -ErrorAction Stop
        
        # Validate that we have actual data
        if ($configData.Keys.Count -eq 0) {
            throw "Configuration file $configPath is empty or has no valid categories"
        }
        
        $totalItems = ($configData.Values | ForEach-Object { if ($_ -is [array]) { $_.Count } else { 0 } } | Measure-Object -Sum).Sum
        try {
            Write-LogMessage "Successfully loaded $ConfigType configuration: $($configData.Keys.Count) categories, $totalItems items total" -Level "INFO"
        } catch {
            # Logging not available, continue with verbose only
        }
        Write-Verbose "Successfully loaded $ConfigType configuration with $($configData.Keys.Count) categories"
        return $configData
    }
    catch {
        Write-Error "Failed to load $ConfigType configuration``: $_"
        return @{}
    }
}

function Get-WingetIdMapping {
    [CmdletBinding()]
    param()
    
    try {
        # Get winget IDs from the apps configuration JSON
        $appsConfig = Get-ConfigurationData -ConfigType "Apps"
        $wingetIds = @{}
        
        foreach ($category in $appsConfig.Keys) {
            $appsInCategory = $appsConfig[$category]
            foreach ($app in $appsInCategory) {
                if ($app.WingetId -and $app.Key) {
                    $wingetIds[$app.Key] = $app.WingetId
                }
            }
        }
        
        return $wingetIds
    } catch {
        Write-LogMessage "Error building winget ID mapping from JSON``: $_" -Level "WARNING"
        # Fallback to minimal hardcoded mapping
        return @{
            "vscode" = "Microsoft.VisualStudioCode"
            "git" = "Git.Git"
            "chrome" = "Google.Chrome"
            "firefox" = "Mozilla.Firefox"
        }
    }
}

function Get-InstallerNameMapping {
    [CmdletBinding()]
    param()
    
    try {
        # Get installer names from the apps configuration JSON
        $appsConfig = Get-ConfigurationData -ConfigType "Apps"
        $installerNames = @{}
        
        foreach ($category in $appsConfig.Keys) {
            $appsInCategory = $appsConfig[$category]
            foreach ($app in $appsInCategory) {
                if ($app.Name -and $app.Key) {
                    $installerNames[$app.Key] = $app.Name
                }
            }
        }
        
        return $installerNames
    } catch {
        Write-LogMessage "Error building installer name mapping from JSON``: $_" -Level "WARNING"
        # Fallback to minimal hardcoded mapping
        return @{
            "vscode" = "Visual Studio Code"
            "git" = "Git"
            "chrome" = "Google Chrome"
            "firefox" = "Mozilla Firefox"
        }
    }
}

function Get-AppDownloadInfo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$AppKey
    )
    
    try {
        $appsConfig = Get-ConfigurationData -ConfigType "Apps"
        
        # Find the app in the configuration
        $appInfo = $null
        foreach ($category in $appsConfig.Keys) {
            $appsInCategory = $appsConfig[$category]
            $appInfo = $appsInCategory | Where-Object { $_.Key -eq $AppKey }
            if ($appInfo) { break }
        }
        
        if (-not $appInfo) {
            Write-Verbose "App '$AppKey' not found in configuration"
            return $null
        }
        
        # Return download information if available
        if ($appInfo.DirectDownload) {
            $downloadInfo = @{
                WingetId = $appInfo.WingetId
                Url = $appInfo.DirectDownload.Url
                UrlType = $appInfo.DirectDownload.UrlType
                AssetPattern = $appInfo.DirectDownload.AssetPattern
                FallbackUrl = $appInfo.DirectDownload.FallbackUrl
                Extension = $appInfo.DirectDownload.Extension
                Arguments = $appInfo.DirectDownload.Arguments
                VerificationPaths = $appInfo.DirectDownload.VerificationPaths
                RequiredFeatures = $appInfo.DirectDownload.RequiredFeatures
                PostInstall = $appInfo.DirectDownload.PostInstall
                Commands = $appInfo.DirectDownload.Commands
            }
            
            # Resolve dynamic URLs
            if ($downloadInfo.UrlType -and $downloadInfo.UrlType -ne "direct") {
                $resolvedUrl = Resolve-DynamicUrl -UrlInfo $downloadInfo -AppName $appInfo.Name
                if ($resolvedUrl) {
                    $downloadInfo.ResolvedUrl = $resolvedUrl
                }
            }
            
            # Expand environment variables in verification paths
            if ($downloadInfo.VerificationPaths) {
                $expandedPaths = @()
                foreach ($path in $downloadInfo.VerificationPaths) {
                    $expandedPath = $path -replace '%ProgramFiles%', $env:ProgramFiles
                    $expandedPath = $expandedPath -replace '%ProgramFiles\(x86\)%', ${env:ProgramFiles(x86)}
                    $expandedPath = $expandedPath -replace '%LocalAppData%', $env:LocalAppData
                    $expandedPath = $expandedPath -replace '%APPDATA%', $env:APPDATA
                    $expandedPaths += $expandedPath
                }
                $downloadInfo.VerificationPaths = $expandedPaths
            }
            
            return $downloadInfo
        }
        
        return $null
    }
    catch {
        Write-Error "Failed to get download info for '$AppKey'``: $_"
        return $null
    }
}

function Resolve-DynamicUrl {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$UrlInfo,
        [Parameter(Mandatory=$true)]
        [string]$AppName
    )
    
    try {
        switch ($UrlInfo.UrlType) {
            "github-asset" {
                return Resolve-GitHubAssetUrl -ApiUrl $UrlInfo.Url -AssetPattern $UrlInfo.AssetPattern -FallbackUrl $UrlInfo.FallbackUrl -AppName $AppName
            }
            "jetbrains-api" {
                return Resolve-JetBrainsUrl -ApiUrl $UrlInfo.Url -FallbackUrl $UrlInfo.FallbackUrl -AppName $AppName
            }
            "dynamic-python" {
                return Resolve-PythonUrl -FallbackUrl $UrlInfo.FallbackUrl
            }
            "dynamic-vlc" {
                return Resolve-VLCUrl -FallbackUrl $UrlInfo.FallbackUrl
            }
            "dynamic-7zip" {
                return Resolve-7ZipUrl -FallbackUrl $UrlInfo.FallbackUrl
            }
            "redirect-page" {
                return Resolve-RedirectUrl -Url $UrlInfo.Url -FallbackUrl $UrlInfo.FallbackUrl
            }
            "feature-install" {
                return "feature-install"
            }
            default {
                Write-Verbose "Unknown URL type: $($UrlInfo.UrlType), using original URL"
                return $UrlInfo.Url
            }
        }
    }
    catch {
        Write-LogMessage "Failed to resolve dynamic URL for $AppName ``: $_" -Level "WARNING"
        return $UrlInfo.FallbackUrl
    }
}

function Resolve-GitHubAssetUrl {
    [CmdletBinding()]
    param(
        [string]$ApiUrl,
        [string]$AssetPattern,
        [string]$FallbackUrl,
        [string]$AppName
    )
    
    try {
        Write-Verbose "Resolving GitHub asset URL for $AppName"
        $headers = @{
            'User-Agent' = 'PowerShell Windows Setup Script'
            'Accept' = 'application/vnd.github.v3+json'
        }
        
        $release = Invoke-RestMethod -Uri $ApiUrl -Headers $headers -TimeoutSec 15 -ErrorAction Stop
        
        if ($AssetPattern) {
            $asset = $release.assets | Where-Object { $_.name -like $AssetPattern } | Select-Object -First 1
        } else {
            # Default to first executable asset
            $asset = $release.assets | Where-Object { $_.name -match '\.(exe|msi|msix|msixbundle)$' } | Select-Object -First 1
        }
        
        if ($asset) {
            Write-Verbose "Found GitHub asset: $($asset.name)"
            return $asset.browser_download_url
        } else {
            Write-Verbose "No matching asset found for pattern: $AssetPattern"
            return $FallbackUrl
        }
    }
    catch {
        Write-Verbose "GitHub API call failed`: $_"
        return $FallbackUrl
    }
}

function Resolve-JetBrainsUrl {
    [CmdletBinding()]
    param(
        [string]$ApiUrl,
        [string]$FallbackUrl,
        [string]$AppName
    )
    
    try {
        Write-Verbose "Resolving JetBrains URL for $AppName"
        $response = Invoke-RestMethod -Uri $ApiUrl -TimeoutSec 15 -ErrorAction Stop
        
        # Extract download URL from JetBrains API response
        $productCode = $ApiUrl.Split('=')[1].Split('&')[0]  # Extract product code from URL
        if ($response.$productCode -and $response.$productCode[0].downloads.windows.link) {
            return $response.$productCode[0].downloads.windows.link
        }
        
        return $FallbackUrl
    }
    catch {
        Write-Verbose "JetBrains API call failed`: $_"
        return $FallbackUrl
    }
}

function Resolve-PythonUrl {
    [CmdletBinding()]
    param([string]$FallbackUrl)
    
    try {
        Write-Verbose "Resolving latest Python URL"
        $webRequest = Invoke-WebRequest -Uri "https://www.python.org/downloads/windows/" -UseBasicParsing -TimeoutSec 15 -ErrorAction Stop
        
        if ($webRequest.Content -match "Latest Python 3 Release - Python (3\.\d+\.\d+)") {
            $latestVersion = $matches[1]
            return "https://www.python.org/ftp/python/$latestVersion/python-$latestVersion-amd64.exe"
        }
        
        return $FallbackUrl
    }
    catch {
        Write-Verbose "Python version lookup failed`: $_"
        return $FallbackUrl
    }
}

function Resolve-VLCUrl {
    [CmdletBinding()]
    param([string]$FallbackUrl)
    
    try {
        Write-Verbose "Resolving latest VLC URL"
        $webRequest = Invoke-WebRequest -Uri "https://www.videolan.org/vlc/download-windows.html" -UseBasicParsing -TimeoutSec 15 -ErrorAction Stop
        
        if ($webRequest.Content -match "vlc-(\d+\.\d+\.\d+)-win64.exe") {
            $latestVersion = $matches[1]
            return "https://get.videolan.org/vlc/$latestVersion/win64/vlc-$latestVersion-win64.exe"
        }
        
        return $FallbackUrl
    }
    catch {
        Write-Verbose "VLC version lookup failed`: $_"
        return $FallbackUrl
    }
}

function Resolve-7ZipUrl {
    [CmdletBinding()]
    param([string]$FallbackUrl)
    
    try {
        Write-Verbose "Resolving latest 7-Zip URL"
        $webRequest = Invoke-WebRequest -Uri "https://www.7-zip.org/download.html" -UseBasicParsing -TimeoutSec 15 -ErrorAction Stop
        
        if ($webRequest.Content -match "Download 7-Zip ([\d\.]+)") {
            $latestVersion = $matches[1]
            $formattedVersion = $latestVersion -replace "\.", ""
            return "https://www.7-zip.org/a/7z$formattedVersion-x64.exe"
        }
        
        return $FallbackUrl
    }
    catch {
        Write-Verbose "7-Zip version lookup failed`: $_"
        return $FallbackUrl
    }
}

function Resolve-RedirectUrl {
    [CmdletBinding()]
    param(
        [string]$Url,
        [string]$FallbackUrl
    )
    
    try {
        Write-Verbose "Following redirect for URL: $Url"
        $response = Invoke-WebRequest -Uri $Url -Method Head -MaximumRedirection 0 -ErrorAction SilentlyContinue
        
        if ($response.Headers.Location) {
            return $response.Headers.Location
        }
        
        return $FallbackUrl
    }
    catch {
        Write-Verbose "Redirect resolution failed`: $_"
        return $FallbackUrl
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
    "Get-AppDownloadInfo",
    "Test-ConfigurationIntegrity",
    "Resolve-DynamicUrl",
    "Resolve-GitHubAssetUrl",
    "Resolve-JetBrainsUrl",
    "Resolve-PythonUrl",
    "Resolve-VLCUrl",
    "Resolve-7ZipUrl",
    "Resolve-RedirectUrl"
)