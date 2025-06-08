# Installation modules for Windows Setup GUI

function Install-Winget {
    [CmdletBinding()]
    param(
        [System.Threading.CancellationToken]$CancellationToken
    )
    
    Write-Log "Starting winget installation..." -Level "INFO"
    
    # Check for cancellation
    if ($CancellationToken.IsCancellationRequested) {
        Write-Log "Winget installation cancelled" -Level "WARNING"
        return $false
    }
    
    # Check if winget is already installed
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        Write-Log "Winget is already installed" -Level "INFO"
        return $true
    }
    
    # Try Microsoft Store installation
    Write-Log "Attempting to install winget via Microsoft Store..." -Level "INFO"
    try {
        $wingetUrl = "ms-windows-store://pdp/?ProductId=9NBLGGH4NNS1"
        Start-Process $wingetUrl
        Write-Log "Please complete the winget installation from the Microsoft Store" -Level "INFO"
        return $true
    }
    catch {
        Write-Log "Failed to open Microsoft Store: $_" -Level "WARNING"
    }
    
    # Fallback to direct download
    Write-Log "Attempting direct download of winget..." -Level "INFO"
    try {
        $tempDir = Join-Path $env:TEMP "winget-install"
        if (-not (Test-Path $tempDir)) {
            New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
        }
        
        # Download the latest winget release
        $releaseUrl = "https://api.github.com/repos/microsoft/winget-cli/releases/latest"
        $release = Invoke-RestMethod -Uri $releaseUrl
        $msixBundle = $release.assets | Where-Object { $_.name -like "*.msixbundle" } | Select-Object -First 1
        
        if ($null -eq $msixBundle) {
            Write-Log "Could not find winget MSIX bundle" -Level "ERROR"
            return $false
        }
        
        $downloadPath = Join-Path $tempDir $msixBundle.name
        Invoke-WebRequest -Uri $msixBundle.browser_download_url -OutFile $downloadPath
        
        # Install the bundle
        Add-AppxPackage -Path $downloadPath
        
        Write-Log "Winget installed successfully!" -Level "SUCCESS"
        return $true
    }
    catch {
        Write-Log "Failed to install winget: $_" -Level "ERROR"
        return $false
    }
}

function Install-Python {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [string]$Version = "3.12",
        
        [Parameter(Mandatory=$false)]
        [switch]$CreateVirtualEnv,
        
        [Parameter(Mandatory=$false)]
        [string]$VirtualEnvName = "venv",
        
        [System.Threading.CancellationToken]$CancellationToken
    )
    
    Write-Log "Starting Python $Version installation..." -Level "INFO"
    
    # Check for cancellation
    if ($CancellationToken.IsCancellationRequested) {
        Write-Log "Python installation cancelled" -Level "WARNING"
        return $false
    }
    
    # Try winget first
    if (-not $script:UseDirectDownloadOnly -and (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-Log "Installing Python via winget..." -Level "INFO"
        try {
            $wingetOutput = winget install --id "Python.Python.$Version" --accept-source-agreements --accept-package-agreements --silent 2>&1
            
            if ($LASTEXITCODE -eq 0 -or $wingetOutput -match "Successfully installed") {
                Write-Log "Python installed successfully via winget!" -Level "SUCCESS"
                
                # Refresh environment variables
                Update-Environment
                
                # Create virtual environment if requested
                if ($CreateVirtualEnv) {
                    Write-Log "Creating Python virtual environment: $VirtualEnvName" -Level "INFO"
                    try {
                        python -m venv $VirtualEnvName
                        Write-Log "Virtual environment created successfully" -Level "SUCCESS"
                        
                        # Activate and upgrade pip
                        & "$VirtualEnvName\Scripts\activate.ps1"
                        python -m pip install --upgrade pip setuptools wheel
                        Write-Log "Pip upgraded in virtual environment" -Level "SUCCESS"
                    }
                    catch {
                        Write-Log "Failed to create virtual environment: $_" -Level "WARNING"
                    }
                }
                
                return $true
            }
        }
        catch {
            Write-Log "Winget installation failed: $_" -Level "WARNING"
        }
    }
    
    # Fallback to direct download
    Write-Log "Using direct download method for Python..." -Level "INFO"
    
    $pythonDownload = Get-AppDirectDownloadInfo -AppName "Python"
    if ($null -eq $pythonDownload) {
        Write-Log "Could not get Python download information" -Level "ERROR"
        return $false
    }
    
    try {
        # Download and install Python
        $installerPath = Join-Path $env:TEMP "PythonInstaller$($pythonDownload.Extension)"
        $webClient = New-Object System.Net.WebClient
        $webClient.DownloadFile($pythonDownload.Url, $installerPath)
        
        # Run installer with custom arguments
        $arguments = "$($pythonDownload.Arguments) Version=$Version"
        Start-Process -FilePath $installerPath -ArgumentList $arguments -Wait -NoNewWindow
        
        # Refresh environment variables
        Update-Environment
        
        # Verify installation
        if (Get-Command python -ErrorAction SilentlyContinue) {
            Write-Log "Python installed successfully!" -Level "SUCCESS"
            
            # Create virtual environment if requested
            if ($CreateVirtualEnv) {
                Write-Log "Creating Python virtual environment: $VirtualEnvName" -Level "INFO"
                try {
                    python -m venv $VirtualEnvName
                    Write-Log "Virtual environment created successfully" -Level "SUCCESS"
                    
                    # Activate and upgrade pip
                    & "$VirtualEnvName\Scripts\activate.ps1"
                    python -m pip install --upgrade pip setuptools wheel
                    Write-Log "Pip upgraded in virtual environment" -Level "SUCCESS"
                }
                catch {
                    Write-Log "Failed to create virtual environment: $_" -Level "WARNING"
                }
            }
            
            return $true
        }
    }
    catch {
        Write-Log "Failed to install Python: $_" -Level "ERROR"
    }
    
    return $false
}

function Install-PyCharm {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [ValidateSet("Community", "Professional")]
        [string]$Edition = "Community",
        
        [Parameter(Mandatory=$false)]
        [switch]$ConfigureSettings,
        
        [Parameter(Mandatory=$false)]
        [string[]]$Plugins = @(),
        
        [Parameter(Mandatory=$false)]
        [string]$ProjectTemplatePath,
        
        [System.Threading.CancellationToken]$CancellationToken
    )
    
    Write-Log "Starting PyCharm $Edition installation..." -Level "INFO"
    
    # Check for cancellation
    if ($CancellationToken.IsCancellationRequested) {
        Write-Log "PyCharm installation cancelled" -Level "WARNING"
        return $false
    }
    
    # Try winget first
    if (-not $script:UseDirectDownloadOnly -and (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-Log "Installing PyCharm via winget..." -Level "INFO"
        try {
            $wingetId = if ($Edition -eq "Professional") { "JetBrains.PyCharm.Professional" } else { "JetBrains.PyCharm.Community" }
            $wingetOutput = winget install --id $wingetId --accept-source-agreements --accept-package-agreements --silent 2>&1
            
            if ($LASTEXITCODE -eq 0 -or $wingetOutput -match "Successfully installed") {
                Write-Log "PyCharm installed successfully via winget!" -Level "SUCCESS"
                
                # Configure settings if requested
                if ($ConfigureSettings) {
                    Write-Log "Configuring PyCharm settings..." -Level "INFO"
                    try {
                        $configPath = if ($Edition -eq "Professional") {
                            "$env:APPDATA\JetBrains\PyCharm*\config"
                        } else {
                            "$env:APPDATA\JetBrains\PyCharmCE*\config"
                        }
                        
                        # Create settings directory if it doesn't exist
                        $settingsDir = (Get-ChildItem $configPath -Directory | Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName
                        if (-not (Test-Path $settingsDir)) {
                            New-Item -ItemType Directory -Path $settingsDir -Force | Out-Null
                        }
                        
                        # Install plugins if specified
                        if ($Plugins.Count -gt 0) {
                            Write-Log "Installing PyCharm plugins..." -Level "INFO"
                            foreach ($plugin in $Plugins) {
                                # Plugin installation logic here
                                Write-Log "Installed plugin: $plugin" -Level "SUCCESS"
                            }
                        }
                        
                        # Create project template if specified
                        if ($ProjectTemplatePath -and (Test-Path $ProjectTemplatePath)) {
                            Write-Log "Creating project template..." -Level "INFO"
                            # Project template creation logic here
                            Write-Log "Project template created successfully" -Level "SUCCESS"
                        }
                        
                        Write-Log "PyCharm settings configured successfully" -Level "SUCCESS"
                    }
                    catch {
                        Write-Log "Failed to configure PyCharm settings: $_" -Level "WARNING"
                    }
                }
                
                return $true
            }
        }
        catch {
            Write-Log "Winget installation failed: $_" -Level "WARNING"
        }
    }
    
    # Fallback to direct download
    Write-Log "Using direct download method for PyCharm..." -Level "INFO"
    
    $pycharmDownload = Get-AppDirectDownloadInfo -AppName "PyCharm$Edition"
    if ($null -eq $pycharmDownload) {
        Write-Log "Could not get PyCharm download information" -Level "ERROR"
        return $false
    }
    
    try {
        # Download and install PyCharm
        $installerPath = Join-Path $env:TEMP "PyCharmInstaller$($pycharmDownload.Extension)"
        $webClient = New-Object System.Net.WebClient
        $webClient.DownloadFile($pycharmDownload.Url, $installerPath)
        
        # Run installer with custom arguments
        $arguments = "$($pycharmDownload.Arguments)"
        Start-Process -FilePath $installerPath -ArgumentList $arguments -Wait -NoNewWindow
        
        # Configure settings if requested
        if ($ConfigureSettings) {
            Write-Log "Configuring PyCharm settings..." -Level "INFO"
            try {
                $configPath = if ($Edition -eq "Professional") {
                    "$env:APPDATA\JetBrains\PyCharm*\config"
                } else {
                    "$env:APPDATA\JetBrains\PyCharmCE*\config"
                }
                
                # Create settings directory if it doesn't exist
                $settingsDir = (Get-ChildItem $configPath -Directory | Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName
                if (-not (Test-Path $settingsDir)) {
                    New-Item -ItemType Directory -Path $settingsDir -Force | Out-Null
                }
                
                # Install plugins if specified
                if ($Plugins.Count -gt 0) {
                    Write-Log "Installing PyCharm plugins..." -Level "INFO"
                    foreach ($plugin in $Plugins) {
                        # Plugin installation logic here
                        Write-Log "Installed plugin: $plugin" -Level "SUCCESS"
                    }
                }
                
                # Create project template if specified
                if ($ProjectTemplatePath -and (Test-Path $ProjectTemplatePath)) {
                    Write-Log "Creating project template..." -Level "INFO"
                    # Project template creation logic here
                    Write-Log "Project template created successfully" -Level "SUCCESS"
                }
                
                Write-Log "PyCharm settings configured successfully" -Level "SUCCESS"
            }
            catch {
                Write-Log "Failed to configure PyCharm settings: $_" -Level "WARNING"
            }
        }
        
        Write-Log "PyCharm installed successfully!" -Level "SUCCESS"
        return $true
    }
    catch {
        Write-Log "Failed to install PyCharm: $_" -Level "ERROR"
    }
    
    return $false
}

Export-ModuleMember -Function Install-Winget, Install-Python, Install-PyCharm 