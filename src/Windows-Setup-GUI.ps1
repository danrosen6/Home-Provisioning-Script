# Windows Setup GUI - Main Script
# This script provides a GUI for automating Windows setup tasks

# Import required modules
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
Import-Module (Join-Path $scriptPath "utils\Logging.ps1")
Import-Module (Join-Path $scriptPath "config\AppConfig.ps1")
Import-Module (Join-Path $scriptPath "config\DownloadConfig.ps1")
Import-Module (Join-Path $scriptPath "modules\Installers.ps1")
Import-Module (Join-Path $scriptPath "modules\SystemOptimizations.ps1")

# Initialize logging
Initialize-Logging

# Check Windows version
$windowsVersion = Get-WindowsVersion
$buildInfo = Get-WindowsBuildInfo -Version $windowsVersion

if ($null -eq $buildInfo) {
    Write-Log "Unsupported Windows version: $windowsVersion" -Level "ERROR"
    [System.Windows.Forms.MessageBox]::Show(
        "This script does not support your Windows version ($windowsVersion).`nPlease use a supported version of Windows 10 or 11.",
        "Unsupported Windows Version",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    )
    exit
}

Write-Log "Detected Windows $($buildInfo.OSType) $($buildInfo.BuildNumber) (Version $($buildInfo.Version))" -Level "INFO"

# Create GUI form
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$form = New-Object System.Windows.Forms.Form
$form.Text = "Windows Setup GUI - $($buildInfo.OSType) $($buildInfo.BuildNumber)"
$form.Size = New-Object System.Drawing.Size(800, 600)
$form.StartPosition = "CenterScreen"

# Create tab control
$tabControl = New-Object System.Windows.Forms.TabControl
$tabControl.Size = New-Object System.Drawing.Size(780, 550)
$tabControl.Location = New-Object System.Drawing.Point(10, 10)

# Applications tab
$appsTab = New-Object System.Windows.Forms.TabPage
$appsTab.Text = "Applications"
$tabControl.TabPages.Add($appsTab)

# Create checkboxes for each application
$y = 10
foreach ($category in $script:AppConfig.Categories.GetEnumerator()) {
    # Add category label
    $categoryLabel = New-Object System.Windows.Forms.Label
    $categoryLabel.Text = $category.Key
    $categoryLabel.Font = New-Object System.Drawing.Font("Arial", 10, [System.Drawing.FontStyle]::Bold)
    $categoryLabel.Location = New-Object System.Drawing.Point(10, $y)
    $categoryLabel.Size = New-Object System.Drawing.Size(200, 20)
    $appsTab.Controls.Add($categoryLabel)
    $y += 30
    
    # Add application checkboxes
    foreach ($app in $category.Value.GetEnumerator()) {
        $checkbox = New-Object System.Windows.Forms.CheckBox
        $checkbox.Text = "$($app.Value.Name) - $($app.Value.Description)"
        $checkbox.Location = New-Object System.Drawing.Point(20, $y)
        $checkbox.Size = New-Object System.Drawing.Size(400, 20)
        $checkbox.Tag = $app.Key
        
        # Check if application is compatible with current Windows version
        $downloadInfo = Get-AppDirectDownloadInfo -AppName $app.Key
        if ($null -eq $downloadInfo) {
            $checkbox.Enabled = $false
            $checkbox.Text += " (Not compatible with your Windows version)"
        }
        
        $appsTab.Controls.Add($checkbox)
        $y += 25
    }
    $y += 20
}

# System tab
$systemTab = New-Object System.Windows.Forms.TabPage
$systemTab.Text = "System"
$tabControl.TabPages.Add($systemTab)

# Create checkboxes for system optimizations
$y = 10
foreach ($optimization in $script:AppConfig.Optimizations.GetEnumerator()) {
    $checkbox = New-Object System.Windows.Forms.CheckBox
    $checkbox.Text = $optimization.Key
    $checkbox.Checked = $optimization.Value
    $checkbox.Location = New-Object System.Drawing.Point(10, $y)
    $checkbox.Size = New-Object System.Drawing.Size(200, 20)
    $checkbox.Tag = $optimization.Key
    $systemTab.Controls.Add($checkbox)
    $y += 25
}

# Add tab control to form
$form.Controls.Add($tabControl)

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
    $cancellationTokenSource = New-Object System.Threading.CancellationTokenSource
    $cancellationToken = $cancellationTokenSource.Token
    
    # Get selected applications
    $selectedApps = @()
    foreach ($control in $appsTab.Controls) {
        if ($control -is [System.Windows.Forms.CheckBox] -and $control.Checked -and $control.Enabled) {
            $selectedApps += $control.Tag
        }
    }
    
    # Get selected optimizations
    $selectedOptimizations = @{}
    foreach ($control in $systemTab.Controls) {
        if ($control -is [System.Windows.Forms.CheckBox]) {
            $selectedOptimizations[$control.Tag] = $control.Checked
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
            $progress = 10 + ($currentApp / $appCount * 60)
            $progressBar.Value = $progress
            $statusLabel.Text = "Installing $app..."
            
            # Verify application compatibility
            $downloadInfo = Get-AppDirectDownloadInfo -AppName $app
            if ($null -eq $downloadInfo) {
                Write-Log "Skipping $app - not compatible with Windows version $windowsVersion" -Level "WARNING"
                continue
            }
            
            switch ($app) {
                "Python" {
                    $config = $script:AppConfig.Categories.Development.Python
                    if (-not (Install-Python -Version $config.Version -CreateVirtualEnv:$config.CreateVirtualEnv -CancellationToken $cancellationToken)) {
                        throw "Failed to install Python"
                    }
                }
                "PyCharm" {
                    $config = $script:AppConfig.Categories.Development.PyCharm
                    if (-not (Install-PyCharm -Edition $config.Edition -ConfigureSettings:$config.ConfigureSettings -CancellationToken $cancellationToken)) {
                        throw "Failed to install PyCharm"
                    }
                }
                "Visual Studio Code" {
                    $downloadInfo = Get-AppDirectDownloadInfo -AppName "VisualStudioCode"
                    if ($null -eq $downloadInfo) {
                        throw "Could not get Visual Studio Code download information"
                    }
                    # Add Visual Studio Code installation logic here
                }
                # Add more application cases here
            }
        }
        
        # Apply system optimizations
        $progressBar.Value = 70
        $statusLabel.Text = "Applying system optimizations..."
        if (-not (Optimize-System -Optimizations $selectedOptimizations -CancellationToken $cancellationToken)) {
            throw "Failed to apply system optimizations"
        }
        
        # Remove bloatware
        $progressBar.Value = 80
        $statusLabel.Text = "Removing bloatware..."
        if (-not (Remove-Bloatware -CancellationToken $cancellationToken)) {
            throw "Failed to remove bloatware"
        }
        
        # Configure services
        $progressBar.Value = 90
        $statusLabel.Text = "Configuring services..."
        if (-not (Configure-Services -CancellationToken $cancellationToken)) {
            throw "Failed to configure services"
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
        $cancellationTokenSource.Dispose()
    }
})

# Show form
$form.ShowDialog() 