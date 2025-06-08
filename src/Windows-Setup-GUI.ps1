#Requires -RunAsAdministrator

# Windows Setup Automation GUI
# A GUI-based tool to automate Windows 10/11 setup, install applications, remove bloatware,
# optimize settings, and manage services.

# Try loading the assemblies with better error handling
try {
    Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
    Add-Type -AssemblyName System.Drawing -ErrorAction Stop
    Write-Host "Loaded Windows Forms assemblies successfully" -ForegroundColor Green
} catch {
    Write-Host "Failed to load Windows Forms assemblies: $_" -ForegroundColor Red
    Write-Host "Make sure .NET Framework is properly installed" -ForegroundColor Yellow
    exit 1
}

# Enable visual styles with error handling
try {
    [System.Windows.Forms.Application]::EnableVisualStyles()
    Write-Host "Enabled visual styles successfully" -ForegroundColor Green
} catch {
    Write-Host "Failed to enable visual styles: $_" -ForegroundColor Red
    # Continue anyway as this is not critical
}

#region Variables

# Global variables
$script:LogPath = Join-Path -Path $PSScriptRoot -ChildPath "logs\setup-log-$(Get-Date -Format 'yyyyMMdd-HHmmss').txt"
$script:EnableFileLogging = $true
$script:IsRunning = $false
$script:TotalSteps = 0
$script:CurrentStep = 0
$script:StartTime = $null
$script:SelectedApps = @()
$script:SelectedBloatware = @()
$script:SelectedServices = @()
$script:SelectedOptimizations = @()
$script:BackgroundJobs = @()
$script:CancellationTokenSource = $null
$script:WingetInstallAttempted = $false
$script:UseDirectDownloadOnly = $false
$script:TempDirectory = Join-Path $env:TEMP "WindowsSetupGUI"
$script:UISyncContext = [System.Threading.SynchronizationContext]::Current

# Initialize UI elements
$script:txtLog = $null
$script:prgProgress = $null
$script:lblProgress = $null
$script:btnRun = $null
$script:btnCancel = $null
$script:tabInstall = $null
$script:tabRemove = $null
$script:tabServices = $null
$script:tabOptimize = $null
$script:tabSettings = $null

# Detect Windows version
$script:OSInfo = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
if ($script:OSInfo) {
    $script:OSVersion = [Version]$script:OSInfo.Version
    $script:OSName = $script:OSInfo.Caption
    $script:IsWindows11 = $script:OSVersion.Major -eq 10 -and $script:OSVersion.Build -ge 22000
} else {
    # Default values if detection fails
    $script:OSVersion = [Version]"10.0"
    $script:OSName = "Windows 10/11"
    $script:IsWindows11 = $false
    Write-Host "Warning: Could not detect Windows version, using defaults" -ForegroundColor Yellow
}

# App categories and definitions
$script:AppCategories = @{
    "Development" = @(
        @{Key="vscode"; Name="Visual Studio Code"; Default=$true; Win10=$true; Win11=$true}
        @{Key="git"; Name="Git"; Default=$true; Win10=$true; Win11=$true}
        @{Key="python"; Name="Python"; Default=$true; Win10=$true; Win11=$true}
        @{Key="pycharm"; Name="PyCharm Community"; Default=$true; Win10=$true; Win11=$true}
        @{Key="github"; Name="GitHub Desktop"; Default=$true; Win10=$true; Win11=$true}
        @{Key="postman"; Name="Postman"; Default=$true; Win10=$true; Win11=$true}
        @{Key="nodejs"; Name="Node.js"; Default=$false; Win10=$true; Win11=$true}
        @{Key="terminal"; Name="Windows Terminal"; Default=$true; Win10=$false; Win11=$true}
    )
    "Browsers" = @(
        @{Key="chrome"; Name="Google Chrome"; Default=$true; Win10=$true; Win11=$true}
        @{Key="firefox"; Name="Mozilla Firefox"; Default=$false; Win10=$true; Win11=$true}
        @{Key="brave"; Name="Brave Browser"; Default=$false; Win10=$true; Win11=$true}
    )
    "Media & Communication" = @(
        @{Key="spotify"; Name="Spotify"; Default=$true; Win10=$true; Win11=$true}
        @{Key="discord"; Name="Discord"; Default=$true; Win10=$true; Win11=$true}
        @{Key="steam"; Name="Steam"; Default=$true; Win10=$true; Win11=$true}
        @{Key="vlc"; Name="VLC Media Player"; Default=$false; Win10=$true; Win11=$true}
    )
    "Utilities" = @(
        @{Key="7zip"; Name="7-Zip"; Default=$false; Win10=$true; Win11=$true}
        @{Key="notepadplusplus"; Name="Notepad++"; Default=$false; Win10=$true; Win11=$true}
        @{Key="powertoys"; Name="Microsoft PowerToys"; Default=$true; Win10=$false; Win11=$true}
    )
}

# Winget ID mappings for apps
$script:WingetMappings = @{
    "vscode" = "Microsoft.VisualStudioCode"
    "git" = "Git.Git"
    "python" = "Python.Python.3"
    "pycharm" = "JetBrains.PyCharm.Community"
    "github" = "GitHub.GitHubDesktop"
    "postman" = "Postman.Postman"
    "nodejs" = "OpenJS.NodeJS.LTS"
    "terminal" = "Microsoft.WindowsTerminal"
    "chrome" = "Google.Chrome"
    "firefox" = "Mozilla.Firefox"
    "brave" = "Brave.Browser"
    "spotify" = "Spotify.Spotify"
    "discord" = "Discord.Discord"
    "steam" = "Valve.Steam"
    "vlc" = "VideoLAN.VLC"
    "7zip" = "7zip.7zip"
    "notepadplusplus" = "Notepad++.Notepad++"
    "powertoys" = "Microsoft.PowerToys"
}

# Function to get direct download info for apps
function Get-AppDirectDownloadInfo {
    param(
        [Parameter(Mandatory=$true)]
        [string]$AppName
    )

    $downloadInfo = @{
        "Visual Studio Code" = @{
            Url = "https://code.visualstudio.com/sha/download?build=stable&os=win32-x64"
            Extension = ".exe"
            Arguments = "/VERYSILENT /MERGETASKS=!runcode"
            VerificationPaths = @(
                "${env:LOCALAPPDATA}\Programs\Microsoft VS Code\Code.exe",
                "C:\Program Files\Microsoft VS Code\Code.exe"
            )
        }
        "Git" = @{
            Url = "https://github.com/git-for-windows/git/releases/latest/download/Git-2.42.0.2-64-bit.exe"
            Extension = ".exe"
            Arguments = "/VERYSILENT /NORESTART"
            VerificationPaths = @(
                "C:\Program Files\Git\cmd\git.exe",
                "C:\Program Files (x86)\Git\cmd\git.exe"
            )
        }
        "Python" = @{
            Url = "https://www.python.org/ftp/python/3.12.2/python-3.12.2-amd64.exe"
            Extension = ".exe"
            Arguments = "/quiet InstallAllUsers=1 PrependPath=1"
            VerificationPaths = @(
                "C:\Program Files\Python312\python.exe",
                "C:\Python312\python.exe"
            )
        }
        "Google Chrome" = @{
            Url = "https://dl.google.com/chrome/install/latest/chrome_installer.exe"
            Extension = ".exe"
            Arguments = "/silent /install"
            VerificationPaths = @(
                "C:\Program Files\Google\Chrome\Application\chrome.exe",
                "C:\Program Files (x86)\Google\Chrome\Application\chrome.exe"
            )
        }
        "Mozilla Firefox" = @{
            Url = "https://download.mozilla.org/?product=firefox-latest&os=win64&lang=en-US"
            Extension = ".exe"
            Arguments = "/S"
            VerificationPaths = @(
                "C:\Program Files\Mozilla Firefox\firefox.exe",
                "C:\Program Files (x86)\Mozilla Firefox\firefox.exe"
            )
        }
        "Brave Browser" = @{
            Url = "https://referrals.brave.com/latest/BraveBrowserSetup.exe"
            Extension = ".exe"
            Arguments = "/silent /install"
            VerificationPaths = @(
                "C:\Program Files\BraveSoftware\Brave-Browser\Application\brave.exe",
                "C:\Program Files (x86)\BraveSoftware\Brave-Browser\Application\brave.exe"
            )
        }
        "Spotify" = @{
            Url = "https://download.scdn.co/SpotifySetup.exe"
            Extension = ".exe"
            Arguments = "/silent"
            VerificationPaths = @(
                "${env:LOCALAPPDATA}\Spotify\Spotify.exe",
                "C:\Program Files\Spotify\Spotify.exe"
            )
        }
        "Discord" = @{
            Url = "https://discord.com/api/downloads/distributions/app/installers/latest?channel=stable&platform=win&arch=x86"
            Extension = ".exe"
            Arguments = "/S"
            VerificationPaths = @(
                "${env:LOCALAPPDATA}\Discord\app-*\Discord.exe",
                "C:\Program Files\Discord\Discord.exe"
            )
        }
        "Steam" = @{
            Url = "https://cdn.akamai.steamstatic.com/client/installer/SteamSetup.exe"
            Extension = ".exe"
            Arguments = "/S"
            VerificationPaths = @(
                "C:\Program Files (x86)\Steam\Steam.exe",
                "C:\Program Files\Steam\Steam.exe"
            )
        }
        "VLC Media Player" = @{
            Url = "https://get.videolan.org/vlc/3.0.20/win64/vlc-3.0.20-win64.exe"
            Extension = ".exe"
            Arguments = "/S"
            VerificationPaths = @(
                "C:\Program Files\VideoLAN\VLC\vlc.exe",
                "C:\Program Files (x86)\VideoLAN\VLC\vlc.exe"
            )
        }
        "7-Zip" = @{
            Url = "https://www.7-zip.org/a/7z2401-x64.exe"
            Extension = ".exe"
            Arguments = "/S"
            VerificationPaths = @(
                "C:\Program Files\7-Zip\7z.exe",
                "C:\Program Files (x86)\7-Zip\7z.exe"
            )
        }
        "Notepad++" = @{
            Url = "https://github.com/notepad-plus-plus/notepad-plus-plus/releases/latest/download/npp.8.6.3.Installer.x64.exe"
            Extension = ".exe"
            Arguments = "/S"
            VerificationPaths = @(
                "C:\Program Files\Notepad++\notepad++.exe",
                "C:\Program Files (x86)\Notepad++\notepad++.exe"
            )
        }
        "Microsoft PowerToys" = @{
            Url = "https://github.com/microsoft/PowerToys/releases/latest/download/PowerToysSetup-x64.exe"
            Extension = ".exe"
            Arguments = "-silent"
            VerificationPaths = @(
                "${env:LOCALAPPDATA}\Programs\PowerToys\PowerToys.exe",
                "C:\Program Files\PowerToys\PowerToys.exe"
            )
        }
    }

    if ($downloadInfo.ContainsKey($AppName)) {
        return $downloadInfo[$AppName]
    } else {
        return $null
    }
}

# Function to check if an app is compatible with the current Windows version
function Test-AppCompatibility {
    param(
        [Parameter(Mandatory=$true)]
        [string]$AppKey
    )

    # Find the app in categories
    foreach ($category in $script:AppCategories.Values) {
        foreach ($app in $category) {
            if ($app.Key -eq $AppKey) {
                if ($script:IsWindows11) {
                    return $app.Win11
                } else {
                    return $app.Win10
                }
            }
        }
    }
    return $false
}

# Function to get installed version of an app
function Get-InstalledVersion {
    param(
        [Parameter(Mandatory=$true)]
        [string]$AppName
    )

    try {
        # Try winget first
        if (Get-Command winget -ErrorAction SilentlyContinue) {
            $wingetInfo = winget list --exact --id $script:WingetMappings[$AppName] 2>&1
            if ($wingetInfo -match "(\d+\.\d+\.\d+)") {
                return $matches[1]
            }
        }

        # Fall back to specific checks for common apps
        switch ($AppName) {
            "vscode" {
                $paths = @(
                    "${env:LOCALAPPDATA}\Programs\Microsoft VS Code\Code.exe",
                    "C:\Program Files\Microsoft VS Code\Code.exe"
                )
                foreach ($path in $paths) {
                    if (Test-Path $path) {
                        return (Get-Item $path).VersionInfo.ProductVersion
                    }
                }
            }
            "python" {
                $paths = @(
                    "C:\Program Files\Python312\python.exe",
                    "C:\Python312\python.exe"
                )
                foreach ($path in $paths) {
                    if (Test-Path $path) {
                        $version = & $path --version 2>&1
                        if ($version -match "Python (\d+\.\d+\.\d+)") {
                            return $matches[1]
                        }
                    }
                }
            }
            "git" {
                if (Get-Command git -ErrorAction SilentlyContinue) {
                    $version = git --version
                    if ($version -match "git version (\d+\.\d+\.\d+)") {
                        return $matches[1]
                    }
                }
            }
            "chrome" {
                $paths = @(
                    "C:\Program Files\Google\Chrome\Application\chrome.exe",
                    "C:\Program Files (x86)\Google\Chrome\Application\chrome.exe"
                )
                foreach ($path in $paths) {
                    if (Test-Path $path) {
                        return (Get-Item $path).VersionInfo.ProductVersion
                    }
                }
            }
            "firefox" {
                $paths = @(
                    "C:\Program Files\Mozilla Firefox\firefox.exe",
                    "C:\Program Files (x86)\Mozilla Firefox\firefox.exe"
                )
                foreach ($path in $paths) {
                    if (Test-Path $path) {
                        return (Get-Item $path).VersionInfo.ProductVersion
                    }
                }
            }
            "brave" {
                $paths = @(
                    "C:\Program Files\BraveSoftware\Brave-Browser\Application\brave.exe",
                    "C:\Program Files (x86)\BraveSoftware\Brave-Browser\Application\brave.exe"
                )
                foreach ($path in $paths) {
                    if (Test-Path $path) {
                        return (Get-Item $path).VersionInfo.ProductVersion
                    }
                }
            }
        }
    }
    catch {
        Write-Log ("Error checking version for {0}: {1}" -f $AppName, $_) -Level ERROR
    }
    return $null
}

# Function to update progress in the UI
function Update-Progress {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,
        
        [Parameter(Mandatory=$false)]
        [string]$SubMessage = "",
        
        [Parameter(Mandatory=$false)]
        [int]$PercentComplete = -1
    )

    try {
        if ($script:txtLog -and $script:txtLog.InvokeRequired) {
            $script:txtLog.Invoke([System.Action]{
                $script:txtLog.AppendText("$Message`r`n")
                if ($SubMessage) {
                    $script:txtLog.AppendText("  $SubMessage`r`n")
                }
                $script:txtLog.ScrollToCaret()
            })
        }

        if ($script:prgProgress -and $PercentComplete -ge 0) {
            if ($script:prgProgress.InvokeRequired) {
                $script:prgProgress.Invoke([System.Action]{
                    $script:prgProgress.Value = $PercentComplete
                })
            }
        }

        if ($script:lblProgress -and $script:lblProgress.InvokeRequired) {
            $script:lblProgress.Invoke([System.Action]{
                $script:lblProgress.Text = $Message
            })
        }

        Write-Log $Message -Level INFO
        if ($SubMessage) {
            Write-Log "  $SubMessage" -Level INFO
        }
    }
    catch {
        Write-Log ("Error updating progress: {0}" -f $_) -Level ERROR
    }
}

# Function to install an application
function Install-Application {
    param(
        [Parameter(Mandatory=$true)]
        [string]$AppName,
        
        [Parameter(Mandatory=$true)]
        [string]$AppKey
    )

    try {
        # Check compatibility
        if (-not (Test-AppCompatibility -AppKey $AppKey)) {
            Update-Progress ("Skipping {0} - not compatible with current Windows version" -f $AppName) -Level WARNING
            return $false
        }

        # Check current version
        $currentVersion = Get-InstalledVersion -AppName $AppKey
        if ($currentVersion) {
            Update-Progress ("Current version of {0}: {1}" -f $AppName, $currentVersion)
        }

        # Try winget first
        if (Get-Command winget -ErrorAction SilentlyContinue) {
            Update-Progress ("Installing {0} via winget..." -f $AppName)
            $wingetId = $script:WingetMappings[$AppKey]
            if ($wingetId) {
                $wingetResult = winget install --id $wingetId --exact --accept-source-agreements --accept-package-agreements --silent
                if ($LASTEXITCODE -eq 0) {
                    Update-Progress ("Successfully installed {0} via winget" -f $AppName) -Level SUCCESS
                    return $true
                }
            }
        }

        # Fall back to direct download
        Update-Progress ("Falling back to direct download for {0}..." -f $AppName)
        $downloadInfo = Get-AppDirectDownloadInfo -AppName $AppName
        if ($downloadInfo) {
            Update-Progress ("Downloading {0} from: {1}" -f $AppName, $downloadInfo.Url)
            $installerPath = Join-Path $env:TEMP ("{0}Installer{1}" -f ($AppName -replace '\s', ''), $downloadInfo.Extension)
            
            Invoke-WebRequest -Uri $downloadInfo.Url -OutFile $installerPath -UseBasicParsing
            
            Update-Progress ("Running {0} installer..." -f $AppName)
            if ($downloadInfo.Extension -eq ".exe") {
                Start-Process -FilePath $installerPath -ArgumentList $downloadInfo.Arguments -Wait
            }
            elseif ($downloadInfo.Extension -eq ".msi") {
                Start-Process msiexec.exe -ArgumentList "/i", $installerPath, $downloadInfo.Arguments -Wait -NoNewWindow
            }
            
            Remove-Item $installerPath -Force -ErrorAction SilentlyContinue
            
            # Verify installation
            $installSuccess = $false
            foreach ($path in $downloadInfo.VerificationPaths) {
                if (Test-Path $path) {
                    $installSuccess = $true
                    Update-Progress ("Verified {0} installation at: {1}" -f $AppName, $path) -Level SUCCESS
                    break
                }
            }
            
            if ($installSuccess) {
                return $true
            }
        }

        Update-Progress ("Failed to install {0}" -f $AppName) -Level ERROR
        return $false
    }
    catch {
        Update-Progress ("Error installing {0}: {1}" -f $AppName, $_) -Level ERROR
        return $false
    }
}

#endregion Helper Functions

#region GUI Creation

function Create-MainForm {
    try {
        $form = New-Object System.Windows.Forms.Form
        $form.Text = "Windows Setup GUI - $($script:OSName)"
        $form.Size = New-Object System.Drawing.Size(800, 600)
        $form.StartPosition = "CenterScreen"
        $form.Add_FormClosing({
            # Clean up resources
            if ($script:CancellationTokenSource) {
                $script:CancellationTokenSource.Dispose()
            }
            Cleanup-TempFiles
        })
        
        # Create tab control
        $tabControl = New-Object System.Windows.Forms.TabControl
        $tabControl.Size = New-Object System.Drawing.Size(780, 550)
        $tabControl.Location = New-Object System.Drawing.Point(10, 10)
        
        # Create tabs
        $tabInstall = New-Object System.Windows.Forms.TabPage
        $tabInstall.Text = "Install Applications"
        $tabControl.TabPages.Add($tabInstall)
        
        # Create application checkboxes
        $y = 10
        foreach ($category in $script:AppCategories.GetEnumerator()) {
            # Add category label
            $categoryLabel = New-Object System.Windows.Forms.Label
            $categoryLabel.Text = $category.Key
            $categoryLabel.Font = New-Object System.Drawing.Font("Arial", 10, [System.Drawing.FontStyle]::Bold)
            $categoryLabel.Location = New-Object System.Drawing.Point(10, $y)
            $categoryLabel.Size = New-Object System.Drawing.Size(200, 20)
            $tabInstall.Controls.Add($categoryLabel)
            $y += 30
            
            # Add application checkboxes
            foreach ($app in $category.Value) {
                $checkbox = New-Object System.Windows.Forms.CheckBox
                $checkbox.Text = $app.Name
                $checkbox.Location = New-Object System.Drawing.Point(20, $y)
                $checkbox.Size = New-Object System.Drawing.Size(400, 20)
                $checkbox.Tag = $app.Key
                $checkbox.Checked = $app.Default
                
                # Disable if not compatible with current Windows version
                if (($script:IsWindows11 -and -not $app.Win11) -or (-not $script:IsWindows11 -and -not $app.Win10)) {
                    $checkbox.Enabled = $false
                    $checkbox.Text += " (Not compatible with your Windows version)"
                }
                
                $tabInstall.Controls.Add($checkbox)
                $y += 25
            }
            $y += 20
        }
        
        # Create progress bar
        $progressBar = New-Object System.Windows.Forms.ProgressBar
        $progressBar.Location = New-Object System.Drawing.Point(10, 560)
        $progressBar.Size = New-Object System.Drawing.Size(780, 20)
        $form.Controls.Add($progressBar)
        
        # Create status label
        $statusLabel = New-Object System.Windows.Forms.Label
        $statusLabel.Location = New-Object System.Drawing.Point(10, 580)
        $statusLabel.Size = New-Object System.Drawing.Size(780, 20)
        $form.Controls.Add($statusLabel)
        
        # Create start button
        $startButton = New-Object System.Windows.Forms.Button
        $startButton.Location = New-Object System.Drawing.Point(700, 560)
        $startButton.Size = New-Object System.Drawing.Size(90, 40)
        $startButton.Text = "Start"
        $form.Controls.Add($startButton)
        
        # Add button click handler
        $startButton.Add_Click({
            $startButton.Enabled = $false
            $progressBar.Value = 0
            $statusLabel.Text = "Starting setup..."
            
            # Create cancellation token source
            $script:CancellationTokenSource = New-Object System.Threading.CancellationTokenSource
            $cancellationToken = $script:CancellationTokenSource.Token
            
            # Get selected applications
            $selectedApps = @()
            foreach ($control in $tabInstall.Controls) {
                if ($control -is [System.Windows.Forms.CheckBox] -and $control.Checked -and $control.Enabled) {
                    $selectedApps += $control.Tag
                }
            }
            
            # Start installation process
            try {
                # Install winget if not present
                if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
                    $statusLabel.Text = "Installing winget..."
                    if (-not (Install-Winget -CancellationToken $cancellationToken)) {
                        throw "Failed to install winget"
                    }
                    $progressBar.Value = 10
                }
                
                # Install selected applications
                $appCount = $selectedApps.Count
                $currentApp = 0
                foreach ($app in $selectedApps) {
                    $currentApp++
                    $progress = 10 + ($currentApp / $appCount * 90)
                    $progressBar.Value = $progress
                    $statusLabel.Text = "Installing $app..."
                    
                    $wingetId = $script:WingetMappings[$app]
                    if (-not (Install-Application -AppName $app -WingetId $wingetId -CancellationToken $cancellationToken)) {
                        Write-Log "Failed to install $app" -Level "ERROR"
                    }
                }
                
                $progressBar.Value = 100
                $statusLabel.Text = "Setup completed successfully!"
            }
            catch {
                $statusLabel.Text = "Error: $_"
                Write-Log "Setup failed: $_" -Level "ERROR"
            }
            finally {
                $startButton.Enabled = $true
                if ($script:CancellationTokenSource) {
                    $script:CancellationTokenSource.Dispose()
                    $script:CancellationTokenSource = $null
                }
            }
        })
        
        # Add tab control to form
        $form.Controls.Add($tabControl)
        
        return $form
    }
    catch {
        Write-Host "Critical error in Create-MainForm: $_" -ForegroundColor Red
        Write-Host $_.ScriptStackTrace -ForegroundColor Red
        
        # Show error message box to the user
        try {
            [System.Windows.Forms.MessageBox]::Show(
                "An error occurred while creating the application: `n`n$_`n`nPlease make sure .NET Framework and Windows Forms are properly installed.",
                "Application Error",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            )
        }
        catch {
            # If even the message box fails, just output to console
            Write-Host "Could not display error dialog. This system may be missing required components." -ForegroundColor Red
        }
        
        return $null
    }
}

#endregion GUI Creation

#region Main Script

# Initialize logging
Initialize-Logging

# Create and show the main form
$mainForm = Create-MainForm
if ($mainForm) {
    $mainForm.ShowDialog()
}

# Cleanup
Cleanup-TempFiles

#endregion Main Script 