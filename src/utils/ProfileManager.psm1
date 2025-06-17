# User Profile Management for Windows Setup GUI
# Handles saving/loading user selection preferences

function Get-ProfileDirectory {
    [CmdletBinding()]
    param()
    
    $profileDir = Join-Path $env:APPDATA "WindowsSetupScript\Profiles"
    if (-not (Test-Path $profileDir)) {
        New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
    }
    return $profileDir
}

function Get-AvailableProfiles {
    [CmdletBinding()]
    param()
    
    try {
        $profileDir = Get-ProfileDirectory
        $profileFiles = Get-ChildItem -Path $profileDir -Filter "*.json" -ErrorAction SilentlyContinue
        
        $profiles = @()
        foreach ($file in $profileFiles) {
            try {
                $profileData = Get-Content -Path $file.FullName -Raw | ConvertFrom-Json
                $profiles += [PSCustomObject]@{
                    Name = $file.BaseName
                    DisplayName = if ($profileData.DisplayName) { $profileData.DisplayName } else { $file.BaseName }
                    Description = if ($profileData.Description) { $profileData.Description } else { "User profile" }
                    Created = $file.CreationTime
                    Modified = $file.LastWriteTime
                    FilePath = $file.FullName
                    AppCount = if ($profileData.SelectedApps) { $profileData.SelectedApps.Count } else { 0 }
                    BloatwareCount = if ($profileData.SelectedBloatware) { $profileData.SelectedBloatware.Count } else { 0 }
                    ServicesCount = if ($profileData.SelectedServices) { $profileData.SelectedServices.Count } else { 0 }
                    TweaksCount = if ($profileData.SelectedTweaks) { $profileData.SelectedTweaks.Count } else { 0 }
                }
            }
            catch {
                Write-Warning "Failed to read profile: $($file.Name) - $_"
            }
        }
        
        return $profiles | Sort-Object Modified -Descending
    }
    catch {
        Write-Error "Failed to get available profiles`: $_"
        return @()
    }
}

function Save-UserProfile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$ProfileName,
        
        [Parameter(Mandatory=$false)]
        [string]$DisplayName = "",
        
        [Parameter(Mandatory=$false)]
        [string]$Description = "",
        
        [Parameter(Mandatory=$true)]
        [hashtable]$Selections,
        
        [Parameter(Mandatory=$false)]
        [switch]$Overwrite
    )
    
    try {
        # Validate profile name
        $invalidChars = [System.IO.Path]::GetInvalidFileNameChars()
        $cleanProfileName = $ProfileName
        foreach ($char in $invalidChars) {
            $cleanProfileName = $cleanProfileName.Replace($char, '_')
        }
        
        $profileDir = Get-ProfileDirectory
        $profilePath = Join-Path $profileDir "$cleanProfileName.json"
        
        # Check if profile exists
        if ((Test-Path $profilePath) -and -not $Overwrite) {
            throw "Profile '$ProfileName' already exists. Use -Overwrite to replace it."
        }
        
        # Create profile data structure
        $profileData = @{
            DisplayName = if ($DisplayName) { $DisplayName } else { $ProfileName }
            Description = if ($Description) { $Description } else { "User profile created on $(Get-Date -Format 'yyyy-MM-dd HH:mm')" }
            Created = if (Test-Path $profilePath) { (Get-Item $profilePath).CreationTime.ToString('yyyy-MM-ddTHH:mm:ss') } else { (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss') }
            Modified = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss')
            Version = "1.0"
            WindowsSetupScriptVersion = "2.0"
            SelectedApps = if ($Selections.Apps) { $Selections.Apps } else { @() }
            SelectedBloatware = if ($Selections.Bloatware) { $Selections.Bloatware } else { @() }
            SelectedServices = if ($Selections.Services) { $Selections.Services } else { @() }
            SelectedTweaks = if ($Selections.Tweaks) { $Selections.Tweaks } else { @() }
            SystemInfo = @{
                WindowsVersion = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion").ProductName
                WindowsBuild = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion").CurrentBuild
                ComputerName = $env:COMPUTERNAME
                UserName = $env:USERNAME
            }
        }
        
        # Save to JSON file
        $jsonContent = $profileData | ConvertTo-Json -Depth 10 -Compress:$false
        Set-Content -Path $profilePath -Value $jsonContent -Encoding UTF8
        
        Write-LogMessage "Profile '$ProfileName' saved successfully to: $profilePath" -Level "SUCCESS"
        return $profilePath
    }
    catch {
        Write-LogMessage "Failed to save profile '$ProfileName'``: $_" -Level "ERROR"
        throw $_
    }
}

function Load-UserProfile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$ProfileName
    )
    
    try {
        $profileDir = Get-ProfileDirectory
        $profilePath = Join-Path $profileDir "$ProfileName.json"
        
        if (-not (Test-Path $profilePath)) {
            throw "Profile '$ProfileName' not found at: $profilePath"
        }
        
        $profileData = Get-Content -Path $profilePath -Raw | ConvertFrom-Json
        
        # Convert back to hashtable for easier manipulation
        $selections = @{
            Apps = if ($profileData.SelectedApps) { @($profileData.SelectedApps) } else { @() }
            Bloatware = if ($profileData.SelectedBloatware) { @($profileData.SelectedBloatware) } else { @() }
            Services = if ($profileData.SelectedServices) { @($profileData.SelectedServices) } else { @() }
            Tweaks = if ($profileData.SelectedTweaks) { @($profileData.SelectedTweaks) } else { @() }
        }
        
        $result = @{
            ProfileName = $ProfileName
            DisplayName = $profileData.DisplayName
            Description = $profileData.Description
            Created = $profileData.Created
            Modified = $profileData.Modified
            Selections = $selections
            SystemInfo = $profileData.SystemInfo
        }
        
        Write-LogMessage "Profile '$ProfileName' loaded successfully" -Level "SUCCESS"
        return $result
    }
    catch {
        Write-LogMessage "Failed to load profile '$ProfileName'``: $_" -Level "ERROR"
        throw $_
    }
}

function Remove-UserProfile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$ProfileName,
        
        [Parameter(Mandatory=$false)]
        [switch]$Confirm = $true
    )
    
    try {
        $profileDir = Get-ProfileDirectory
        $profilePath = Join-Path $profileDir "$ProfileName.json"
        
        if (-not (Test-Path $profilePath)) {
            throw "Profile '$ProfileName' not found"
        }
        
        if ($Confirm) {
            $choice = Read-Host "Are you sure you want to delete profile '$ProfileName'? (y/N)"
            if ($choice -notmatch '^[Yy]') {
                Write-LogMessage "Profile deletion cancelled" -Level "INFO"
                return $false
            }
        }
        
        Remove-Item -Path $profilePath -Force
        Write-LogMessage "Profile '$ProfileName' deleted successfully" -Level "SUCCESS"
        return $true
    }
    catch {
        Write-LogMessage "Failed to delete profile '$ProfileName'``: $_" -Level "ERROR"
        throw $_
    }
}

function Export-UserProfile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$ProfileName,
        
        [Parameter(Mandatory=$true)]
        [string]$ExportPath
    )
    
    try {
        $profileDir = Get-ProfileDirectory
        $profilePath = Join-Path $profileDir "$ProfileName.json"
        
        if (-not (Test-Path $profilePath)) {
            throw "Profile '$ProfileName' not found"
        }
        
        # Ensure export directory exists
        $exportDir = Split-Path $ExportPath -Parent
        if ($exportDir -and -not (Test-Path $exportDir)) {
            New-Item -ItemType Directory -Path $exportDir -Force | Out-Null
        }
        
        Copy-Item -Path $profilePath -Destination $ExportPath -Force
        Write-LogMessage "Profile '$ProfileName' exported to: $ExportPath" -Level "SUCCESS"
        return $true
    }
    catch {
        Write-LogMessage "Failed to export profile '$ProfileName'``: $_" -Level "ERROR"
        throw $_
    }
}

function Import-UserProfile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$ImportPath,
        
        [Parameter(Mandatory=$false)]
        [string]$NewProfileName = "",
        
        [Parameter(Mandatory=$false)]
        [switch]$Overwrite
    )
    
    try {
        if (-not (Test-Path $ImportPath)) {
            throw "Import file not found: $ImportPath"
        }
        
        # Validate JSON structure
        $importData = Get-Content -Path $ImportPath -Raw | ConvertFrom-Json
        
        # Determine profile name
        $profileName = if ($NewProfileName) { 
            $NewProfileName 
        } else { 
            [System.IO.Path]::GetFileNameWithoutExtension($ImportPath)
        }
        
        $profileDir = Get-ProfileDirectory
        $profilePath = Join-Path $profileDir "$profileName.json"
        
        # Check if profile exists
        if ((Test-Path $profilePath) -and -not $Overwrite) {
            throw "Profile '$profileName' already exists. Use -Overwrite to replace it."
        }
        
        # Update metadata
        $importData.Modified = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss')
        if (-not $importData.Created) {
            $importData.Created = $importData.Modified
        }
        
        # Save imported profile
        $jsonContent = $importData | ConvertTo-Json -Depth 10 -Compress:$false
        Set-Content -Path $profilePath -Value $jsonContent -Encoding UTF8
        
        Write-LogMessage "Profile imported successfully as '$profileName'" -Level "SUCCESS"
        return $profileName
    }
    catch {
        Write-LogMessage "Failed to import profile from '$ImportPath'``: $_" -Level "ERROR"
        throw $_
    }
}

function Get-DefaultProfiles {
    [CmdletBinding()]
    param()
    
    # Create some default profiles for common scenarios
    $defaultProfiles = @{
        "Developer-Essential" = @{
            DisplayName = "Developer Essentials"
            Description = "Essential tools for software development"
            Apps = @("vscode", "git", "python", "nodejs", "postman", "terminal")
            Bloatware = @("candy-crush", "candy-crush-soda", "ms-officehub", "xbox-gamebar", "zune-music")
            Services = @("diagtrack", "sysmain", "wsearch")
            Tweaks = @("show-extensions", "show-hidden", "disable-cortana", "disable-onedrive", "taskbar-left")
        }
        "Privacy-Focused" = @{
            DisplayName = "Privacy & Performance"
            Description = "Maximum privacy with performance optimizations"
            Apps = @("brave", "7zip", "vlc")
            Bloatware = @("ms-copilot", "bing-weather", "bing-news", "ms-widgets", "candy-crush", "candy-crush-soda", "facebook", "netflix", "disney", "tiktok")
            Services = @("diagtrack", "dmwappushsvc", "wisvc", "sysmain", "remoteregistry", "lfsvc")
            Tweaks = @("show-extensions", "disable-cortana", "disable-onedrive", "reduce-telemetry", "disable-activity", "search-bing", "disable-background", "disable-advertising-id", "disable-widgets", "disable-chat", "taskbar-left")
        }
        "Gaming-Setup" = @{
            DisplayName = "Gaming Setup"
            Description = "Gaming-focused configuration"
            Apps = @("steam", "discord", "spotify", "chrome")
            Bloatware = @("ms-officehub", "ms-teams", "ms-todo", "bing-news", "bing-finance")
            Services = @("diagtrack", "dmwappushsvc", "fax", "printnotify")
            Tweaks = @("show-extensions", "disable-cortana", "disable-onedrive", "disable-tips", "disable-startup-sound")
        }
        "Minimal-Clean" = @{
            DisplayName = "Minimal & Clean"
            Description = "Minimal installation with maximum cleanup"
            Apps = @("chrome", "7zip")
            Bloatware = @("ms-officehub", "ms-teams", "ms-copilot", "candy-crush", "candy-crush-soda", "facebook", "netflix", "disney", "tiktok", "spotify-store", "twitter", "linkedin", "instagram", "whatsapp", "xbox-gamebar", "xbox-gamingoverlay", "zune-music", "zune-video", "solitaire")
            Services = @("diagtrack", "dmwappushsvc", "wisvc", "sysmain", "wsearch", "remoteregistry", "fax", "retaildemo")
            Tweaks = @("show-extensions", "show-hidden", "disable-cortana", "disable-onedrive", "reduce-telemetry", "disable-activity", "search-bing", "disable-background", "disable-advertising-id", "disable-widgets", "disable-chat", "disable-tips", "taskbar-left", "classic-context")
        }
    }
    
    return $defaultProfiles
}

function Create-DefaultProfiles {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [switch]$Overwrite
    )
    
    try {
        $defaultProfiles = Get-DefaultProfiles
        $createdCount = 0
        
        foreach ($profileName in $defaultProfiles.Keys) {
            $profile = $defaultProfiles[$profileName]
            
            $selections = @{
                Apps = $profile.Apps
                Bloatware = $profile.Bloatware
                Services = $profile.Services
                Tweaks = $profile.Tweaks
            }
            
            try {
                Save-UserProfile -ProfileName $profileName -DisplayName $profile.DisplayName -Description $profile.Description -Selections $selections -Overwrite:$Overwrite
                $createdCount++
            }
            catch {
                if ($_.Exception.Message -like "*already exists*") {
                    Write-LogMessage "Default profile '$profileName' already exists (use -Overwrite to replace)" -Level "INFO"
                } else {
                    Write-LogMessage "Failed to create default profile '$profileName'``: $_" -Level "WARNING"
                }
            }
        }
        
        Write-LogMessage "Created $createdCount default profiles" -Level "SUCCESS"
        return $createdCount
    }
    catch {
        Write-LogMessage "Failed to create default profiles``: $_" -Level "ERROR"
        throw $_
    }
}

# Import logging function if available
if (-not (Get-Command Write-LogMessage -ErrorAction SilentlyContinue)) {
    function Write-LogMessage {
        param([string]$Message, [string]$Level = "INFO")
        $color = switch ($Level) {
            "ERROR" { "Red" }
            "WARNING" { "Yellow" }
            "SUCCESS" { "Green" }
            default { "White" }
        }
        Write-Host "[$Level] $Message" -ForegroundColor $color
    }
}

Export-ModuleMember -Function @(
    "Get-ProfileDirectory",
    "Get-AvailableProfiles",
    "Save-UserProfile",
    "Load-UserProfile",
    "Remove-UserProfile",
    "Export-UserProfile",
    "Import-UserProfile",
    "Get-DefaultProfiles",
    "Create-DefaultProfiles"
)