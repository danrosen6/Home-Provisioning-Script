#Requires -RunAsAdministrator

# Windows Setup Automation GUI - Clean Fixed Version
# A comprehensive GUI-based tool to automate Windows 10/11 setup

# Load Windows Forms assemblies
try {
    Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
    Add-Type -AssemblyName System.Drawing -ErrorAction Stop
    Write-Host "Loaded Windows Forms assemblies successfully" -ForegroundColor Green
} catch {
    Write-Host "Failed to load Windows Forms assemblies: $_" -ForegroundColor Red
    exit 1
}

try {
    [System.Windows.Forms.Application]::EnableVisualStyles()
    Write-Host "Enabled visual styles successfully" -ForegroundColor Green
} catch {
    Write-Host "Failed to enable visual styles: $_" -ForegroundColor Red
}

# Import required modules
$ScriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path

# Validate script structure first
$requiredPaths = @(
    (Join-Path $ScriptPath "utils"),
    (Join-Path $ScriptPath "modules"),
    (Join-Path $ScriptPath "config")
)

$requiredModules = @(
    "utils/Logging.psm1",
    "utils/ConfigLoader.psm1", 
    "utils/JsonUtils.psm1",
    "utils/WingetUtils.psm1",
    "utils/ProfileManager.psm1",
    "utils/RecoveryUtils.psm1",
    "modules/Installers.psm1",
    "modules/SystemOptimizations.psm1"
)

# Check directory structure
foreach ($path in $requiredPaths) {
    if (-not (Test-Path $path)) {
        Write-Host "CRITICAL ERROR: Required directory missing: $path" -ForegroundColor Red
        Write-Host "Please ensure you're running this script from the correct location" -ForegroundColor Yellow
        Read-Host "Press Enter to exit"
        exit 1
    }
}

# Check required modules
foreach ($module in $requiredModules) {
    $modulePath = Join-Path $ScriptPath $module
    if (-not (Test-Path $modulePath)) {
        Write-Host "CRITICAL ERROR: Required module missing: $modulePath" -ForegroundColor Red
        Read-Host "Press Enter to exit"
        exit 1
    }
}

try {
    Import-Module (Join-Path $ScriptPath "utils/Logging.psm1") -Force -ErrorAction Stop
    Import-Module (Join-Path $ScriptPath "utils/JsonUtils.psm1") -Force -ErrorAction Stop
    Import-Module (Join-Path $ScriptPath "utils/ConfigLoader.psm1") -Force -ErrorAction Stop
    Import-Module (Join-Path $ScriptPath "utils/WingetUtils.psm1") -Force -ErrorAction Stop
    Import-Module (Join-Path $ScriptPath "utils/ProfileManager.psm1") -Force -ErrorAction Stop
    Import-Module (Join-Path $ScriptPath "utils/RecoveryUtils.psm1") -Force -ErrorAction Stop
    Import-Module (Join-Path $ScriptPath "modules/Installers.psm1") -Force -ErrorAction Stop
    Import-Module (Join-Path $ScriptPath "modules/SystemOptimizations.psm1") -Force -ErrorAction Stop
    Write-Host "All modules loaded successfully" -ForegroundColor Green
} catch {
    Write-Host "CRITICAL ERROR: Failed to load required modules: $_" -ForegroundColor Red
    Write-Host "Module load error details: $($_.Exception.Message)" -ForegroundColor Yellow
    Read-Host "Press Enter to exit"
    exit 1
}

# Initialize logging
try {
    Initialize-Logging
    Write-Host "Logging initialized successfully" -ForegroundColor Green
} catch {
    Write-Host "WARNING: Failed to initialize logging: $_" -ForegroundColor Yellow
}

Write-Host "===========================================================" -ForegroundColor Cyan
Write-Host "           Windows Setup Automation GUI" -ForegroundColor Green
Write-Host "===========================================================" -ForegroundColor Cyan

# Global variables
$script:SelectedApps = @()
$script:SelectedBloatware = @()
$script:SelectedServices = @()
$script:SelectedTweaks = @()
$script:OperationCancelled = $false

# Detect Windows version
$script:OSInfo = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
if ($script:OSInfo) {
    $buildNumber = [int]$script:OSInfo.BuildNumber
    $script:IsWindows11 = $buildNumber -ge 22000
    $script:WindowsVersion = if ($script:IsWindows11) { "Windows 11" } else { "Windows 10" }
    $script:BuildNumber = $script:OSInfo.BuildNumber
} else {
    $script:IsWindows11 = $false
    $script:WindowsVersion = "Unknown"
    $script:BuildNumber = "Unknown"
}

Write-Host "Detected: $($script:WindowsVersion) (Build: $($script:BuildNumber))" -ForegroundColor Yellow

# Load configuration data
Write-Host "Loading configuration files..." -ForegroundColor Gray

try {
    # Load configuration data
    $script:Apps = Get-ConfigurationData -ConfigType "Apps"
    $script:Bloatware = Get-ConfigurationData -ConfigType "Bloatware" 
    $script:Services = Get-ConfigurationData -ConfigType "Services"
    $script:Tweaks = Get-ConfigurationData -ConfigType "Tweaks"
    
    # Check if any configuration returned empty
    if ($script:Apps.Keys.Count -eq 0 -or $script:Bloatware.Keys.Count -eq 0 -or $script:Services.Keys.Count -eq 0 -or $script:Tweaks.Keys.Count -eq 0) {
        throw "One or more configuration files failed to load or are empty"
    }
    
    # Validate that we actually loaded data
    $appsCount = ($script:Apps.Values | ForEach-Object { if ($_ -and $_.Count) { $_.Count } else { 0 } } | Measure-Object -Sum).Sum
    $bloatwareCount = ($script:Bloatware.Values | ForEach-Object { if ($_ -and $_.Count) { $_.Count } else { 0 } } | Measure-Object -Sum).Sum
    $servicesCount = ($script:Services.Values | ForEach-Object { if ($_ -and $_.Count) { $_.Count } else { 0 } } | Measure-Object -Sum).Sum
    $tweaksCount = ($script:Tweaks.Values | ForEach-Object { if ($_ -and $_.Count) { $_.Count } else { 0 } } | Measure-Object -Sum).Sum
    
    if ($appsCount -eq 0 -or $bloatwareCount -eq 0 -or $servicesCount -eq 0 -or $tweaksCount -eq 0) {
        throw "Configuration loaded but contains empty data (Apps: $appsCount, Bloatware: $bloatwareCount, Services: $servicesCount, Tweaks: $tweaksCount)"
    }
    
    Write-Host "Configuration loaded successfully: Apps: $appsCount, Bloatware: $bloatwareCount, Services: $servicesCount, Tweaks: $tweaksCount" -ForegroundColor Green
}
catch {
    Write-Host "CRITICAL ERROR loading configuration: $_" -ForegroundColor Red
    
    try {
        Write-LogMessage "Failed to load configuration: $_" -Level "ERROR"
    }
    catch {
        # Logging not available, continue
    }
    
    Write-Host "Attempting to diagnose configuration issues..." -ForegroundColor Yellow
    
    $configFiles = @("apps.json", "bloatware.json", "services.json", "tweaks.json")
    $expectedConfigPath = Join-Path $ScriptPath "config"
    foreach ($file in $configFiles) {
        $filePath = Join-Path $expectedConfigPath $file
        if (Test-Path $filePath) {
            Write-Host "Found: $file" -ForegroundColor Green
            try {
                $content = Get-Content $filePath -Raw
                $json = $content | ConvertFrom-Json
                Write-Host "  Valid JSON structure" -ForegroundColor Green
            }
            catch {
                Write-Host "  Invalid JSON: $_" -ForegroundColor Red
            }
        }
        else {
            Write-Host "Missing: $file at $filePath" -ForegroundColor Red
        }
    }
    
    Write-Host "CANNOT CONTINUE: Configuration files are required for proper operation." -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}

# Helper functions
function Get-InstallerName {
    param([string]$AppKey)
    $mapping = Get-InstallerNameMapping
    if ($mapping.ContainsKey($AppKey)) {
        return $mapping[$AppKey]
    } else {
        return $AppKey
    }
}

function Get-WingetId {
    param([string]$AppKey)
    $wingetIds = Get-WingetIdMapping
    if ($wingetIds.ContainsKey($AppKey)) {
        return $wingetIds[$AppKey]
    } else {
        return $null
    }
}

# Create main form
$form = New-Object System.Windows.Forms.Form
$form.Text = "Windows Setup Automation"
$form.Size = New-Object System.Drawing.Size(1000, 800)
$form.StartPosition = "CenterScreen"
$form.MinimumSize = New-Object System.Drawing.Size(900, 700)
$form.MaximizeBox = $true

# Create header panel
$headerPanel = New-Object System.Windows.Forms.Panel
$headerPanel.Height = 80
$headerPanel.Dock = [System.Windows.Forms.DockStyle]::Top
$headerPanel.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 215)

$titleLabel = New-Object System.Windows.Forms.Label
$titleLabel.Text = "Windows Setup Automation"
$titleLabel.ForeColor = [System.Drawing.Color]::White
$titleLabel.Font = New-Object System.Drawing.Font("Segoe UI", 18, [System.Drawing.FontStyle]::Bold)
$titleLabel.Location = New-Object System.Drawing.Point(20, 15)
$titleLabel.AutoSize = $true
$headerPanel.Controls.Add($titleLabel)

$versionLabel = New-Object System.Windows.Forms.Label
$versionLabel.Text = "$($script:WindowsVersion) (Build: $($script:BuildNumber))"
$versionLabel.ForeColor = [System.Drawing.Color]::White
$versionLabel.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$versionLabel.Location = New-Object System.Drawing.Point(20, 50)
$versionLabel.AutoSize = $true
$headerPanel.Controls.Add($versionLabel)

# Check winget compatibility
$wingetInfo = Test-WingetCompatibility
$wingetStatusLabel = New-Object System.Windows.Forms.Label
if ($wingetInfo.Compatible) {
    $wingetStatusLabel.Text = "[OK] Winget Compatible"
    $wingetStatusLabel.ForeColor = [System.Drawing.Color]::LightGreen
} else {
    $wingetStatusLabel.Text = "[WARN] Winget Incompatible (Build $($wingetInfo.BuildNumber) less than 16299)"
    $wingetStatusLabel.ForeColor = [System.Drawing.Color]::Yellow
}
$wingetStatusLabel.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$wingetStatusLabel.Location = New-Object System.Drawing.Point(750, 25)
$wingetStatusLabel.AutoSize = $true
$headerPanel.Controls.Add($wingetStatusLabel)

$form.Controls.Add($headerPanel)

# Create tab control with optimizations - moved to bottom
$tabControl = New-Object System.Windows.Forms.TabControl
$tabControl.Dock = [System.Windows.Forms.DockStyle]::Fill
$tabControl.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$tabControl.Alignment = [System.Windows.Forms.TabAlignment]::Bottom
$tabControl.SuspendLayout()  # Suspend layout for performance

# Apps tab
$appsTab = New-Object System.Windows.Forms.TabPage
$appsTab.Text = "Applications"
$appsTab.BackColor = [System.Drawing.Color]::White

$appsPanel = New-Object System.Windows.Forms.Panel
$appsPanel.Dock = [System.Windows.Forms.DockStyle]::Fill
$appsPanel.AutoScroll = $true
$appsPanel.SuspendLayout()  # Suspend layout for performance

# Add controls to Apps tab
$yPos = 35
$appsTitle = New-Object System.Windows.Forms.Label
$appsTitle.Text = "Select Applications to Install"
$appsTitle.Font = New-Object System.Drawing.Font("Segoe UI", 14, [System.Drawing.FontStyle]::Bold)
$appsTitle.Location = New-Object System.Drawing.Point(20, $yPos)
$appsTitle.AutoSize = $true
$appsPanel.Controls.Add($appsTitle)
$yPos += 40

# Apps Select All checkbox
$appsSelectAll = New-Object System.Windows.Forms.CheckBox
$appsSelectAll.Text = "Select All Applications"
$appsSelectAll.Location = New-Object System.Drawing.Point(20, $yPos)
$appsSelectAll.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$appsSelectAll.AutoSize = $true
$appsPanel.Controls.Add($appsSelectAll)
$yPos += 35

# Store app checkboxes
$script:AppCheckboxes = @()

# Add app categories and checkboxes
foreach ($category in $script:Apps.Keys | Sort-Object) {
    # Category header
    $categoryLabel = New-Object System.Windows.Forms.Label
    $categoryLabel.Text = $category
    $categoryLabel.Font = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)
    $categoryLabel.ForeColor = [System.Drawing.Color]::FromArgb(0, 120, 215)
    $categoryLabel.Location = New-Object System.Drawing.Point(20, $yPos)
    $categoryLabel.AutoSize = $true
    $appsPanel.Controls.Add($categoryLabel)
    $yPos += 30
    
    # Apps in category (3 columns)
    $col = 0
    $colWidth = 280
    $itemsInRow = 0
    
    foreach ($app in $script:Apps[$category]) {
        # Skip apps not compatible with current Windows version
        if (($script:IsWindows11 -and $app.Win11 -eq $false) -or 
            (-not $script:IsWindows11 -and $app.Win10 -eq $false)) {
            continue
        }
        
        $checkbox = New-Object System.Windows.Forms.CheckBox
        $checkbox.Text = $app.Name
        $checkbox.Tag = $app.Key
        $checkbox.Checked = $app.Default
        $checkbox.AutoSize = $true
        $checkbox.Location = New-Object System.Drawing.Point((40 + ($col * $colWidth)), $yPos)
        
        $appsPanel.Controls.Add($checkbox)
        $script:AppCheckboxes += $checkbox
        
        $col++
        $itemsInRow++
        if ($col -ge 3) {
            $col = 0
            $yPos += 25
        }
    }
    
    # Move to next row if items were added and not at start of row
    if ($itemsInRow -gt 0 -and $col -ne 0) {
        $yPos += 25
    }
    $yPos += 15  # Spacing between categories
}

# Apps Select All event handler
$appsSelectAll.Add_CheckedChanged({
    $appsPanel.SuspendLayout()
    foreach ($checkbox in $script:AppCheckboxes) {
        $checkbox.Checked = $appsSelectAll.Checked
    }
    $appsPanel.ResumeLayout()
})

$appsPanel.ResumeLayout()  # Resume layout after adding all controls
$appsTab.Controls.Add($appsPanel)
$tabControl.TabPages.Add($appsTab)

# Bloatware tab
$bloatwareTab = New-Object System.Windows.Forms.TabPage
$bloatwareTab.Text = "Bloatware"
$bloatwareTab.BackColor = [System.Drawing.Color]::White

$bloatwarePanel = New-Object System.Windows.Forms.Panel
$bloatwarePanel.Dock = [System.Windows.Forms.DockStyle]::Fill
$bloatwarePanel.AutoScroll = $true
$bloatwarePanel.SuspendLayout()  # Suspend layout for performance

# Add controls to Bloatware tab
$yPos = 35
$bloatwareTitle = New-Object System.Windows.Forms.Label
$bloatwareTitle.Text = "Select Bloatware to Remove"
$bloatwareTitle.Font = New-Object System.Drawing.Font("Segoe UI", 14, [System.Drawing.FontStyle]::Bold)
$bloatwareTitle.Location = New-Object System.Drawing.Point(20, $yPos)
$bloatwareTitle.AutoSize = $true
$bloatwarePanel.Controls.Add($bloatwareTitle)
$yPos += 40

# Bloatware Select All checkbox
$bloatwareSelectAll = New-Object System.Windows.Forms.CheckBox
$bloatwareSelectAll.Text = "Select All Bloatware"
$bloatwareSelectAll.Location = New-Object System.Drawing.Point(20, $yPos)
$bloatwareSelectAll.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$bloatwareSelectAll.AutoSize = $true
$bloatwarePanel.Controls.Add($bloatwareSelectAll)
$yPos += 35

$script:BloatwareCheckboxes = @()

# Add bloatware categories and checkboxes
foreach ($category in $script:Bloatware.Keys | Sort-Object) {
    # Category header
    $categoryLabel = New-Object System.Windows.Forms.Label
    $categoryLabel.Text = $category
    $categoryLabel.Font = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)
    $categoryLabel.ForeColor = [System.Drawing.Color]::FromArgb(220, 53, 69)
    $categoryLabel.Location = New-Object System.Drawing.Point(20, $yPos)
    $categoryLabel.AutoSize = $true
    $bloatwarePanel.Controls.Add($categoryLabel)
    $yPos += 30
    
    # Bloatware items in category (3 columns)
    $col = 0
    $colWidth = 280
    $itemsInRow = 0
    
    foreach ($item in $script:Bloatware[$category]) {
        # Skip items not compatible with current Windows version
        if (($script:IsWindows11 -and $item.Win11 -eq $false) -or 
            (-not $script:IsWindows11 -and $item.Win10 -eq $false)) {
            continue
        }
        
        $checkbox = New-Object System.Windows.Forms.CheckBox
        $checkbox.Text = $item.Name
        $checkbox.Tag = $item.Key
        $checkbox.Checked = $item.Default
        $checkbox.AutoSize = $true
        $checkbox.Location = New-Object System.Drawing.Point((40 + ($col * $colWidth)), $yPos)
        
        $bloatwarePanel.Controls.Add($checkbox)
        $script:BloatwareCheckboxes += $checkbox
        
        $col++
        $itemsInRow++
        if ($col -ge 3) {
            $col = 0
            $yPos += 25
        }
    }
    
    if ($itemsInRow -gt 0 -and $col -ne 0) {
        $yPos += 25
    }
    $yPos += 15
}

$bloatwareSelectAll.Add_CheckedChanged({
    $bloatwarePanel.SuspendLayout()
    foreach ($checkbox in $script:BloatwareCheckboxes) {
        $checkbox.Checked = $bloatwareSelectAll.Checked
    }
    $bloatwarePanel.ResumeLayout()
})

$bloatwarePanel.ResumeLayout()  # Resume layout after adding all controls
$bloatwareTab.Controls.Add($bloatwarePanel)
$tabControl.TabPages.Add($bloatwareTab)

# Services tab
$servicesTab = New-Object System.Windows.Forms.TabPage
$servicesTab.Text = "Services"
$servicesTab.BackColor = [System.Drawing.Color]::White

$servicesPanel = New-Object System.Windows.Forms.Panel
$servicesPanel.Dock = [System.Windows.Forms.DockStyle]::Fill
$servicesPanel.AutoScroll = $true
$servicesPanel.SuspendLayout()  # Suspend layout for performance

# Add controls to Services tab
$yPos = 35
$servicesTitle = New-Object System.Windows.Forms.Label
$servicesTitle.Text = "Select Services to Disable"
$servicesTitle.Font = New-Object System.Drawing.Font("Segoe UI", 14, [System.Drawing.FontStyle]::Bold)
$servicesTitle.Location = New-Object System.Drawing.Point(20, $yPos)
$servicesTitle.AutoSize = $true
$servicesPanel.Controls.Add($servicesTitle)
$yPos += 40

# Services Select All checkbox
$servicesSelectAll = New-Object System.Windows.Forms.CheckBox
$servicesSelectAll.Text = "Select All Services"
$servicesSelectAll.Location = New-Object System.Drawing.Point(20, $yPos)
$servicesSelectAll.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$servicesSelectAll.AutoSize = $true
$servicesPanel.Controls.Add($servicesSelectAll)
$yPos += 35

$script:ServiceCheckboxes = @()

# Add service categories and checkboxes
foreach ($category in $script:Services.Keys | Sort-Object) {
    # Category header
    $categoryLabel = New-Object System.Windows.Forms.Label
    $categoryLabel.Text = $category
    $categoryLabel.Font = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)
    $categoryLabel.ForeColor = [System.Drawing.Color]::FromArgb(255, 193, 7)
    $categoryLabel.Location = New-Object System.Drawing.Point(20, $yPos)
    $categoryLabel.AutoSize = $true
    $servicesPanel.Controls.Add($categoryLabel)
    $yPos += 30
    
    # Service items in category (2 columns for longer descriptions)
    $col = 0
    $colWidth = 400
    $itemsInRow = 0
    
    foreach ($service in $script:Services[$category]) {
        # Skip services not compatible with current Windows version
        if (($script:IsWindows11 -and $service.Win11 -eq $false) -or 
            (-not $script:IsWindows11 -and $service.Win10 -eq $false)) {
            continue
        }
        
        $checkbox = New-Object System.Windows.Forms.CheckBox
        $checkbox.Text = $service.Name
        $checkbox.Tag = $service.Key
        $checkbox.Checked = $service.Default
        $checkbox.AutoSize = $true
        $checkbox.Location = New-Object System.Drawing.Point((40 + ($col * $colWidth)), $yPos)
        
        $servicesPanel.Controls.Add($checkbox)
        $script:ServiceCheckboxes += $checkbox
        
        $col++
        $itemsInRow++
        if ($col -ge 2) {
            $col = 0
            $yPos += 25
        }
    }
    
    if ($itemsInRow -gt 0 -and $col -ne 0) {
        $yPos += 25
    }
    $yPos += 15
}

$servicesSelectAll.Add_CheckedChanged({
    $servicesPanel.SuspendLayout()
    foreach ($checkbox in $script:ServiceCheckboxes) {
        $checkbox.Checked = $servicesSelectAll.Checked
    }
    $servicesPanel.ResumeLayout()
})

$servicesPanel.ResumeLayout()  # Resume layout after adding all controls
$servicesTab.Controls.Add($servicesPanel)
$tabControl.TabPages.Add($servicesTab)

# Tweaks tab
$tweaksTab = New-Object System.Windows.Forms.TabPage
$tweaksTab.Text = "Tweaks"
$tweaksTab.BackColor = [System.Drawing.Color]::White

$tweaksPanel = New-Object System.Windows.Forms.Panel
$tweaksPanel.Dock = [System.Windows.Forms.DockStyle]::Fill
$tweaksPanel.AutoScroll = $true
$tweaksPanel.SuspendLayout()  # Suspend layout for performance

# Add controls to Tweaks tab
$yPos = 35
$tweaksTitle = New-Object System.Windows.Forms.Label
$tweaksTitle.Text = "Select System Tweaks to Apply"
$tweaksTitle.Font = New-Object System.Drawing.Font("Segoe UI", 14, [System.Drawing.FontStyle]::Bold)
$tweaksTitle.Location = New-Object System.Drawing.Point(20, $yPos)
$tweaksTitle.AutoSize = $true
$tweaksPanel.Controls.Add($tweaksTitle)
$yPos += 40

# Tweaks Select All checkbox
$tweaksSelectAll = New-Object System.Windows.Forms.CheckBox
$tweaksSelectAll.Text = "Select All Tweaks"
$tweaksSelectAll.Location = New-Object System.Drawing.Point(20, $yPos)
$tweaksSelectAll.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$tweaksSelectAll.AutoSize = $true
$tweaksPanel.Controls.Add($tweaksSelectAll)
$yPos += 35

$script:TweakCheckboxes = @()

# Add tweak categories and checkboxes
foreach ($category in $script:Tweaks.Keys | Sort-Object) {
    # Category header
    $categoryLabel = New-Object System.Windows.Forms.Label
    $categoryLabel.Text = $category
    $categoryLabel.Font = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)
    $categoryLabel.ForeColor = [System.Drawing.Color]::FromArgb(108, 117, 125)
    $categoryLabel.Location = New-Object System.Drawing.Point(20, $yPos)
    $categoryLabel.AutoSize = $true
    $tweaksPanel.Controls.Add($categoryLabel)
    $yPos += 30
    
    # Tweak items in category (2 columns)
    $col = 0
    $colWidth = 400
    $itemsInRow = 0
    
    foreach ($tweak in $script:Tweaks[$category]) {
        # Skip tweaks not compatible with current Windows version
        if (($script:IsWindows11 -and $tweak.Win11 -eq $false) -or 
            (-not $script:IsWindows11 -and $tweak.Win10 -eq $false)) {
            continue
        }
        
        $checkbox = New-Object System.Windows.Forms.CheckBox
        $checkbox.Text = $tweak.Name
        $checkbox.Tag = $tweak.Key
        $checkbox.Checked = $tweak.Default
        $checkbox.AutoSize = $true
        $checkbox.Location = New-Object System.Drawing.Point((40 + ($col * $colWidth)), $yPos)
        
        $tweaksPanel.Controls.Add($checkbox)
        $script:TweakCheckboxes += $checkbox
        
        $col++
        $itemsInRow++
        if ($col -ge 2) {
            $col = 0
            $yPos += 25
        }
    }
    
    if ($itemsInRow -gt 0 -and $col -ne 0) {
        $yPos += 25
    }
    $yPos += 15
}

$tweaksSelectAll.Add_CheckedChanged({
    $tweaksPanel.SuspendLayout()
    foreach ($checkbox in $script:TweakCheckboxes) {
        $checkbox.Checked = $tweaksSelectAll.Checked
    }
    $tweaksPanel.ResumeLayout()
})

$tweaksPanel.ResumeLayout()  # Resume layout after adding all controls
$tweaksTab.Controls.Add($tweaksPanel)
$tabControl.TabPages.Add($tweaksTab)

$tabControl.ResumeLayout()  # Resume layout after all tabs added
$form.Controls.Add($tabControl)

# Create bottom panel for buttons and status
$bottomPanel = New-Object System.Windows.Forms.Panel
$bottomPanel.Height = 120
$bottomPanel.Dock = [System.Windows.Forms.DockStyle]::Bottom
$bottomPanel.BackColor = [System.Drawing.Color]::FromArgb(248, 249, 250)

# Main action buttons
$runButton = New-Object System.Windows.Forms.Button
$runButton.Text = "Run Current Tab"
$runButton.Size = New-Object System.Drawing.Size(180, 35)
$runButton.Location = New-Object System.Drawing.Point(20, 20)
$runButton.BackColor = [System.Drawing.Color]::FromArgb(0, 123, 255)
$runButton.ForeColor = [System.Drawing.Color]::White
$runButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$runButton.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)

$closeButton = New-Object System.Windows.Forms.Button
$closeButton.Text = "Close"
$closeButton.Size = New-Object System.Drawing.Size(80, 35)
$closeButton.Location = New-Object System.Drawing.Point(220, 20)
$closeButton.BackColor = [System.Drawing.Color]::FromArgb(220, 53, 69)
$closeButton.ForeColor = [System.Drawing.Color]::White
$closeButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$closeButton.Font = New-Object System.Drawing.Font("Segoe UI", 9)

# Status label
$statusLabel = New-Object System.Windows.Forms.Label
$statusLabel.Text = "Ready - Select options in current tab and click 'Run Current Tab'"
$statusLabel.Location = New-Object System.Drawing.Point(20, 65)
$statusLabel.AutoSize = $true
$statusLabel.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$statusLabel.ForeColor = [System.Drawing.Color]::FromArgb(108, 117, 125)

# Progress bar - positioned to not overlap with close button
$progressBar = New-Object System.Windows.Forms.ProgressBar
$progressBar.Size = New-Object System.Drawing.Size(400, 20)
$progressBar.Location = New-Object System.Drawing.Point(320, 30)
$progressBar.Style = [System.Windows.Forms.ProgressBarStyle]::Continuous
$progressBar.Visible = $false

$bottomPanel.Controls.AddRange(@($runButton, $closeButton, $statusLabel, $progressBar))
$form.Controls.Add($bottomPanel)

# Event handlers
function Update-StatusLabel {
    param([string]$Message, [string]$Color = "Gray")
    $statusLabel.Text = $Message
    try {
        $statusLabel.ForeColor = [System.Drawing.Color]::FromName($Color)
    } catch {
        $statusLabel.ForeColor = [System.Drawing.Color]::Gray
    }
    [System.Windows.Forms.Application]::DoEvents()
}

function Get-SelectedItems {
    param([array]$Checkboxes)
    
    $selected = @()
    foreach ($checkbox in $Checkboxes) {
        if ($checkbox.Checked) {
            $selected += $checkbox.Tag
        }
    }
    return $selected
}

$runButton.Add_Click({
    try {
        $script:OperationCancelled = $false
        $runButton.Enabled = $false
        $closeButton.Text = "Cancel"
        $progressBar.Visible = $true
        
        # Get current active tab
        $activeTab = $tabControl.SelectedTab
        $activeTabName = $activeTab.Text
        
        $selectedItems = @()
        $operationType = ""
        
        # Determine which tab is active and get selected items
        switch ($activeTabName) {
            "Applications" {
                $selectedItems = Get-SelectedItems -Checkboxes $script:AppCheckboxes
                $operationType = "Apps"
            }
            "Bloatware" {
                $selectedItems = Get-SelectedItems -Checkboxes $script:BloatwareCheckboxes
                $operationType = "Bloatware"
            }
            "Services" {
                $selectedItems = Get-SelectedItems -Checkboxes $script:ServiceCheckboxes
                $operationType = "Services"
            }
            "Tweaks" {
                $selectedItems = Get-SelectedItems -Checkboxes $script:TweakCheckboxes
                $operationType = "Tweaks"
            }
        }
        
        if ($selectedItems.Count -eq 0) {
            Update-StatusLabel "No items selected in $activeTabName tab. Please select items to process." "Orange"
            $runButton.Enabled = $true
            $closeButton.Text = "Close"
            $progressBar.Visible = $false
            return
        }
        
        Update-StatusLabel "Starting $operationType operations... ($($selectedItems.Count) items)" "Blue"
        $progressBar.Maximum = $selectedItems.Count
        $progressBar.Value = 0
        
        $currentStep = 0
        
        # Execute operations based on tab type
        switch ($operationType) {
            "Apps" {
                # Check if winget is already available before initializing
                $wingetNeedsSetup = $true
                if (Get-Command winget -ErrorAction SilentlyContinue) {
                    try {
                        $testVersion = winget --version 2>&1
                        if ($LASTEXITCODE -eq 0 -and $testVersion -and $testVersion.Trim() -ne "") {
                            Write-LogMessage "Winget already available: $testVersion" -Level "INFO"
                            $wingetNeedsSetup = $false
                        }
                    }
                    catch {
                        Write-LogMessage "Winget command found but not working properly" -Level "WARNING"
                    }
                }
                
                if ($wingetNeedsSetup) {
                    Update-StatusLabel "Setting up winget environment..." "Blue"
                    
                    # Create progress callback for winget initialization
                    $wingetProgressCallback = {
                        param([string]$Status, [int]$PercentComplete)
                        Update-StatusLabel $Status "Blue"
                        if ($PercentComplete -ge 0) {
                            $progressBar.Value = [math]::Min($PercentComplete, 100)
                        }
                        [System.Windows.Forms.Application]::DoEvents()
                    }
                    
                    $wingetResult = Initialize-WingetEnvironment -ProgressCallback $wingetProgressCallback -TimeoutMinutes 15
                } else {
                    Update-StatusLabel "Winget ready, starting installations..." "Blue"
                }
                
                foreach ($appKey in $selectedItems) {
                    if ($script:OperationCancelled) {
                        Update-StatusLabel "Operations cancelled by user" "Orange"
                        break
                    }
                    
                    $currentStep++
                    $progressBar.Value = $currentStep
                    
                    $installerName = Get-InstallerName -AppKey $appKey
                    $wingetId = Get-WingetId -AppKey $appKey
                    Update-StatusLabel "Installing $installerName... ($currentStep of $($selectedItems.Count))" "Blue"
                    
                    try {
                        # Get DirectDownload info from configuration
                        $appConfig = $null
                        foreach ($category in $script:Apps.Keys) {
                            $app = $script:Apps[$category] | Where-Object { $_.Key -eq $appKey }
                            if ($app) {
                                $appConfig = $app
                                break
                            }
                        }
                        
                        $directDownload = if ($appConfig -and $appConfig.DirectDownload) { $appConfig.DirectDownload } else { $null }
                        Install-Application -AppName $installerName -AppKey $appKey -WingetId $wingetId -DirectDownload $directDownload -TimeoutMinutes 15 -DownloadTimeoutMinutes 10
                        Write-LogMessage "Successfully installed $installerName" -Level "SUCCESS"
                    } catch {
                        Write-LogMessage "Failed to install $installerName - $_" -Level "ERROR"
                    }
                    
                    # Update UI every 5 operations or on final operation for better performance
                    if ($currentStep % 5 -eq 0 -or $currentStep -eq $selectedItems.Count) {
                        [System.Windows.Forms.Application]::DoEvents()
                    }
                }
            }
            "Bloatware" {
                foreach ($bloatKey in $selectedItems) {
                    if ($script:OperationCancelled) {
                        Update-StatusLabel "Operations cancelled by user" "Orange"
                        break
                    }
                    
                    $currentStep++
                    $progressBar.Value = $currentStep
                    Update-StatusLabel "Removing bloatware $bloatKey... ($currentStep of $($selectedItems.Count))" "Blue"
                    
                    try {
                        Remove-Bloatware -BloatwareKey $bloatKey
                        Write-LogMessage "Successfully removed bloatware $bloatKey" -Level "SUCCESS"
                    } catch {
                        Write-LogMessage "Failed to remove bloatware $bloatKey - $_" -Level "ERROR"
                    }
                    
                    # Update UI every 5 operations or on final operation for better performance
                    if ($currentStep % 5 -eq 0 -or $currentStep -eq $selectedItems.Count) {
                        [System.Windows.Forms.Application]::DoEvents()
                    }
                }
            }
            "Services" {
                foreach ($serviceKey in $selectedItems) {
                    if ($script:OperationCancelled) {
                        Update-StatusLabel "Operations cancelled by user" "Orange"
                        break
                    }
                    
                    $currentStep++
                    $progressBar.Value = $currentStep
                    Update-StatusLabel "Disabling service $serviceKey... ($currentStep of $($selectedItems.Count))" "Blue"
                    
                    try {
                        Set-SystemOptimization -OptimizationKey $serviceKey
                        Write-LogMessage "Successfully disabled service $serviceKey" -Level "SUCCESS"
                    } catch {
                        Write-LogMessage "Failed to disable service $serviceKey - $_" -Level "ERROR"
                    }
                    
                    # Update UI every 5 operations or on final operation for better performance
                    if ($currentStep % 5 -eq 0 -or $currentStep -eq $selectedItems.Count) {
                        [System.Windows.Forms.Application]::DoEvents()
                    }
                }
            }
            "Tweaks" {
                foreach ($tweakKey in $selectedItems) {
                    if ($script:OperationCancelled) {
                        Update-StatusLabel "Operations cancelled by user" "Orange"
                        break
                    }
                    
                    $currentStep++
                    $progressBar.Value = $currentStep
                    Update-StatusLabel "Applying tweak $tweakKey... ($currentStep of $($selectedItems.Count))" "Blue"
                    
                    try {
                        Set-SystemOptimization -OptimizationKey $tweakKey
                        Write-LogMessage "Successfully applied tweak $tweakKey" -Level "SUCCESS"
                    } catch {
                        Write-LogMessage "Failed to apply tweak $tweakKey - $_" -Level "ERROR"
                    }
                    
                    # Update UI every 5 operations or on final operation for better performance
                    if ($currentStep % 5 -eq 0 -or $currentStep -eq $selectedItems.Count) {
                        [System.Windows.Forms.Application]::DoEvents()
                    }
                }
            }
        }
        
        if (-not $script:OperationCancelled) {
            Update-StatusLabel "$operationType operations completed! Check logs for details." "Green"
            [System.Windows.Forms.MessageBox]::Show("$operationType operations have been completed!", "Operations Complete", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
        }
        
    } catch {
        Update-StatusLabel "Error during operations: $_" "Red"
        Write-LogMessage "GUI operation error: $_" -Level "ERROR"
        [System.Windows.Forms.MessageBox]::Show("An error occurred: $_", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    } finally {
        $runButton.Enabled = $true
        $closeButton.Text = "Close"
        $progressBar.Visible = $false
        $script:OperationCancelled = $false
    }
})

$closeButton.Add_Click({
    if ($closeButton.Text -eq "Cancel") {
        # Cancel ongoing operations
        $script:OperationCancelled = $true
        Update-StatusLabel "Cancelling operations..." "Orange"
    } else {
        # Close the form
        $form.Close()
    }
})

# Show the form
Write-Host "Launching Windows Setup GUI..." -ForegroundColor Green
Write-Host "GUI loaded with $($script:AppCheckboxes.Count) applications, $($script:BloatwareCheckboxes.Count) bloatware items, $($script:ServiceCheckboxes.Count) services, and $($script:TweakCheckboxes.Count) tweaks" -ForegroundColor Yellow

$logPath = Get-LogFilePath
if ($logPath) {
    Write-Host "Log file: $logPath" -ForegroundColor Cyan
}

[void]$form.ShowDialog()