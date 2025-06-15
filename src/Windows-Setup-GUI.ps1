#Requires -RunAsAdministrator

# Windows Setup Automation GUI - Fixed Version
# Clean implementation focused on working tab switching and scrolling

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# Import required modules - Import logging first so other modules can use it
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
Import-Module (Join-Path $scriptPath "utils\Logging.psm1") -Force

# Initialize logging immediately after import
Initialize-Logging

Import-Module (Join-Path $scriptPath "utils\RecoveryUtils.psm1") -Force
Import-Module (Join-Path $scriptPath "utils\ConfigLoader.psm1") -Force
Import-Module (Join-Path $scriptPath "utils\WingetUtils.psm1") -Force
Import-Module (Join-Path $scriptPath "utils\ProgressSystem.psm1") -Force
Import-Module (Join-Path $scriptPath "modules\Installers.psm1") -Force
Import-Module (Join-Path $scriptPath "modules\SystemOptimizations.psm1") -Force

# Helper functions

# Global variables
$script:SelectedApps = @()
$script:SelectedBloatware = @()
$script:SelectedServices = @()
$script:SelectedTweaks = @()

# Checkbox state storage
$script:CheckboxStates = @{
    Apps = @{}
    Bloatware = @{}
    Services = @{}
    Tweaks = @{}
}

# Detect Windows version
$script:OSInfo = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
if ($script:OSInfo) {
    $script:IsWindows11 = $script:OSInfo.Version -match "^10\.0\.2[2-9]"
} else {
    $script:IsWindows11 = $false
}

# Load configuration data
try {
    $script:Apps = Get-ConfigurationData -ConfigType "Apps"
    if ($script:Apps.Keys.Count -eq 0) {
        throw "Apps configuration is empty"
    }
} catch {
    Write-LogMessage "Failed to load apps configuration: $_" -Level "ERROR"
    # Fallback to minimal configuration
    $script:Apps = @{
        "Essential" = @(
            @{Name="Visual Studio Code"; Key="vscode"; Default=$true; Win10=$true; Win11=$true}
            @{Name="Git"; Key="git"; Default=$true; Win10=$true; Win11=$true}
            @{Name="Google Chrome"; Key="chrome"; Default=$true; Win10=$true; Win11=$true}
        )
    }
}

try {
    $script:Bloatware = Get-ConfigurationData -ConfigType "Bloatware"
    if ($script:Bloatware.Keys.Count -eq 0) {
        throw "Bloatware configuration is empty"
    }
} catch {
    Write-LogMessage "Failed to load bloatware configuration: $_" -Level "ERROR"
    # Fallback to minimal configuration
    $script:Bloatware = @{
        "Common Bloatware" = @(
            @{Name="Microsoft Office Hub"; Key="ms-officehub"; Default=$true; Win10=$true; Win11=$true}
            @{Name="Candy Crush Games"; Key="candy-crush"; Default=$true; Win10=$true; Win11=$true}
        )
    }
}

try {
    $script:Services = Get-ConfigurationData -ConfigType "Services"
    if ($script:Services.Keys.Count -eq 0) {
        throw "Services configuration is empty"
    }
} catch {
    Write-LogMessage "Failed to load services configuration: $_" -Level "ERROR"
    # Fallback to minimal configuration
    $script:Services = @{
        "Essential Services" = @(
            @{Name="Connected User Experiences and Telemetry"; Key="diagtrack"; Default=$true; Win10=$true; Win11=$true}
        )
    }
}

try {
    $script:Tweaks = Get-ConfigurationData -ConfigType "Tweaks"
    if ($script:Tweaks.Keys.Count -eq 0) {
        throw "Tweaks configuration is empty"
    }
} catch {
    Write-LogMessage "Failed to load tweaks configuration: $_" -Level "ERROR"
    # Fallback to minimal configuration
    $script:Tweaks = @{
        "Essential Tweaks" = @(
            @{Name="Show file extensions"; Key="show-extensions"; Default=$true; Win10=$true; Win11=$true}
            @{Name="Disable Cortana"; Key="disable-cortana"; Default=$true; Win10=$true; Win11=$true}
        )
    }
}

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

function Create-ScrollableTabContent {
    param($TabPage, $Categories, $SelectedArray)
    
    # Clear tab
    $TabPage.Controls.Clear()
    
    # Create scrollable panel
    $panel = New-Object System.Windows.Forms.Panel
    $panel.Dock = [System.Windows.Forms.DockStyle]::Fill
    $panel.AutoScroll = $true
    $panel.BackColor = [System.Drawing.Color]::White
    $TabPage.Controls.Add($panel)
    
    $yPos = 10
    
    # Select All checkbox
    $selectAll = New-Object System.Windows.Forms.CheckBox
    $selectAll.Text = "Select All"
    $selectAll.Location = New-Object System.Drawing.Point(10, $yPos)
    $selectAll.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    $selectAll.AutoSize = $true
    $selectAll.Add_CheckedChanged({
        $checked = $this.Checked
        foreach ($control in $this.Parent.Controls) {
            if ($control -is [System.Windows.Forms.CheckBox] -and $control -ne $this) {
                $control.Checked = $checked
            }
        }
    })
    $panel.Controls.Add($selectAll)
    $yPos += 40
    
    # Add categories and items
    foreach ($category in $Categories.Keys | Sort-Object) {
        # Category header
        $header = New-Object System.Windows.Forms.Label
        $header.Text = $category
        $header.Location = New-Object System.Drawing.Point(10, $yPos)
        $header.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
        $header.ForeColor = [System.Drawing.Color]::FromArgb(0, 120, 215)
        $header.AutoSize = $true
        $panel.Controls.Add($header)
        $yPos += 30
        
        # Items
        foreach ($item in $Categories[$category]) {
            $checkbox = New-Object System.Windows.Forms.CheckBox
            $checkbox.Text = $item.Name
            $checkbox.Tag = $item.Key
            $checkbox.Location = New-Object System.Drawing.Point(30, $yPos)
            $checkbox.AutoSize = $true
            $checkbox.Checked = $item.Default
            $panel.Controls.Add($checkbox)
            $yPos += 25
        }
        $yPos += 15
    }
    
    # Set scroll size
    $panel.AutoScrollMinSize = New-Object System.Drawing.Size(0, $yPos)
}

# Create main form
$form = New-Object System.Windows.Forms.Form
$form.Text = "Windows Setup Automation"
$form.Size = New-Object System.Drawing.Size(900, 700)
$form.StartPosition = "CenterScreen"
$form.MinimumSize = New-Object System.Drawing.Size(800, 600)

# Header at top
$header = New-Object System.Windows.Forms.Panel
$header.Height = 60
$header.Dock = [System.Windows.Forms.DockStyle]::Top
$header.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 215)

$title = New-Object System.Windows.Forms.Label
$title.Text = "Windows Setup Automation"
$title.ForeColor = [System.Drawing.Color]::White
$title.Font = New-Object System.Drawing.Font("Segoe UI", 16)
$title.Location = New-Object System.Drawing.Point(20, 20)
$title.AutoSize = $true
$header.Controls.Add($title)

$osLabel = New-Object System.Windows.Forms.Label
$wingetCompat = Test-WingetCompatibility
if ($script:IsWindows11) {
    $osText = "Windows 11"
} else {
    $osText = "Windows 10"
}
if (-not $wingetCompat.Compatible) {
    $osText += " (Build $($wingetCompat.BuildNumber))"
}
$osLabel.Text = $osText
$osLabel.ForeColor = [System.Drawing.Color]::White
$osLabel.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$osLabel.Location = New-Object System.Drawing.Point(750, 25)
$osLabel.AutoSize = $true
$header.Controls.Add($osLabel)

$form.Controls.Add($header)

# Bottom area with tabs and controls
$bottomArea = New-Object System.Windows.Forms.Panel
$bottomArea.Height = 180
$bottomArea.Dock = [System.Windows.Forms.DockStyle]::Bottom
$bottomArea.BackColor = [System.Drawing.Color]::FromArgb(240, 240, 240)

# Tab control in bottom area
$tabControl = New-Object System.Windows.Forms.TabControl
$tabControl.Size = New-Object System.Drawing.Size(500, 120)
$tabControl.Location = New-Object System.Drawing.Point(20, 10)

# Control buttons area
$controlPanel = New-Object System.Windows.Forms.Panel
$controlPanel.Size = New-Object System.Drawing.Size(350, 120)
$controlPanel.Location = New-Object System.Drawing.Point(530, 10)
$controlPanel.BackColor = [System.Drawing.Color]::FromArgb(220, 220, 220)

$runBtn = New-Object System.Windows.Forms.Button
$runBtn.Text = "Run Selected Tasks"
$runBtn.Size = New-Object System.Drawing.Size(150, 35)
$runBtn.Location = New-Object System.Drawing.Point(20, 20)
$runBtn.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 215)
$runBtn.ForeColor = [System.Drawing.Color]::White
$runBtn.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$controlPanel.Controls.Add($runBtn)

$cancelBtn = New-Object System.Windows.Forms.Button
$cancelBtn.Text = "Cancel"
$cancelBtn.Size = New-Object System.Drawing.Size(100, 35)
$cancelBtn.Location = New-Object System.Drawing.Point(180, 20)
$cancelBtn.BackColor = [System.Drawing.Color]::Gray
$cancelBtn.ForeColor = [System.Drawing.Color]::White
$cancelBtn.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$controlPanel.Controls.Add($cancelBtn)

$statusLabel = New-Object System.Windows.Forms.Label
$statusLabel.Text = "Select options in tabs and click Run"
$statusLabel.Location = New-Object System.Drawing.Point(20, 65)
$statusLabel.Size = New-Object System.Drawing.Size(300, 20)
$controlPanel.Controls.Add($statusLabel)

$bottomArea.Controls.Add($tabControl)
$bottomArea.Controls.Add($controlPanel)

# Progress area at very bottom
$progressArea = Initialize-ProgressSystem -ParentContainer $bottomArea -Location (New-Object System.Drawing.Point(20, 140)) -Size (New-Object System.Drawing.Size(840, 60)) -EnableDetails

$form.Controls.Add($bottomArea)

# Main content area (fills remaining space above bottom area)
$contentArea = New-Object System.Windows.Forms.Panel
$contentArea.Dock = [System.Windows.Forms.DockStyle]::Fill
$contentArea.BackColor = [System.Drawing.Color]::White

# Large content display area with proper scrolling
$contentDisplay = New-Object System.Windows.Forms.Panel
$contentDisplay.Dock = [System.Windows.Forms.DockStyle]::Fill
$contentDisplay.AutoScroll = $true
$contentDisplay.BackColor = [System.Drawing.Color]::White
$contentDisplay.BorderStyle = [System.Windows.Forms.BorderStyle]::None

# Force scroll bars to appear when needed
$contentDisplay.Add_Layout({
    $this.AutoScrollMinSize = New-Object System.Drawing.Size($this.AutoScrollMinSize.Width, $this.AutoScrollMinSize.Height)
})

# Enable mouse wheel scrolling with improved handling
$contentDisplay.Add_MouseWheel({
    param($sender, $e)
    $scrollAmount = [Math]::Max(1, [Math]::Abs($e.Delta) / 120) * 40  # Larger scroll amount
    $currentY = -$sender.AutoScrollPosition.Y
    
    if ($e.Delta -gt 0) {
        # Scroll up
        $newY = [Math]::Max(0, $currentY - $scrollAmount)
    } else {
        # Scroll down
        $contentHeight = $sender.AutoScrollMinSize.Height
        $panelHeight = $sender.ClientSize.Height
        $maxY = [Math]::Max(0, $contentHeight - $panelHeight)
        $newY = [Math]::Min($maxY, $currentY + $scrollAmount)
        
        # Debug scrolling
        Write-Host "Scrolling: Current=$currentY, New=$newY, Max=$maxY, Content=$contentHeight, Panel=$panelHeight" -ForegroundColor Cyan
    }
    
    $sender.AutoScrollPosition = New-Object System.Drawing.Point(0, $newY)
    $e.Handled = $true
})

# Ensure panel gets focus when mouse enters for wheel scrolling
$contentDisplay.Add_MouseEnter({
    $this.Focus()
})

# Make sure scroll position is reset properly when content changes
$contentDisplay.Add_ControlAdded({
    $this.AutoScrollPosition = New-Object System.Drawing.Point(0, 0)
})

$contentArea.Controls.Add($contentDisplay)

$form.Controls.Add($contentArea)

# Store reference to content display for tab switching
$script:ContentDisplay = $contentDisplay

# Create small tabs for bottom area
$tabInstall = New-Object System.Windows.Forms.TabPage
$tabInstall.Text = "Apps"

$tabRemove = New-Object System.Windows.Forms.TabPage
$tabRemove.Text = "Bloatware"

$tabServices = New-Object System.Windows.Forms.TabPage
$tabServices.Text = "Services"

$tabTweaks = New-Object System.Windows.Forms.TabPage
$tabTweaks.Text = "Tweaks"

# Add tabs to control
$tabControl.TabPages.Add($tabInstall)
$tabControl.TabPages.Add($tabRemove)
$tabControl.TabPages.Add($tabServices)
$tabControl.TabPages.Add($tabTweaks)

# Function to populate main content area based on selected tab
function Show-TabContent {
    param($Categories, $Title)
    
    # Properly clear all controls and reset scroll position
    $script:ContentDisplay.Controls.Clear()
    $script:ContentDisplay.AutoScrollPosition = New-Object System.Drawing.Point(0, 0)
    
    # Force a layout update to clear any cached positions
    $script:ContentDisplay.PerformLayout()
    $script:ContentDisplay.Refresh()
    
    $yPos = 20
    
    # Title with explicit sizing to prevent overlap
    $titleLabel = New-Object System.Windows.Forms.Label
    $titleLabel.Text = $Title
    $titleLabel.Font = New-Object System.Drawing.Font("Segoe UI", 14, [System.Drawing.FontStyle]::Bold)
    $titleLabel.Location = New-Object System.Drawing.Point(20, $yPos)
    $titleLabel.Size = New-Object System.Drawing.Size(800, 30)  # Explicit size
    $titleLabel.AutoSize = $false
    $script:ContentDisplay.Controls.Add($titleLabel)
    $yPos += 50
    
    # Select All checkbox with explicit sizing
    $selectAll = New-Object System.Windows.Forms.CheckBox
    $selectAll.Text = "Select All"
    $selectAll.Location = New-Object System.Drawing.Point(20, $yPos)
    $selectAll.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $selectAll.Size = New-Object System.Drawing.Size(200, 25)  # Explicit size
    $selectAll.AutoSize = $false
    $selectAll.Add_CheckedChanged({
        $checked = $this.Checked
        foreach ($control in $script:ContentDisplay.Controls) {
            if ($control -is [System.Windows.Forms.CheckBox] -and $control -ne $this) {
                $control.Checked = $checked
            }
        }
    })
    $script:ContentDisplay.Controls.Add($selectAll)
    $yPos += 50
    
    # Add categories and items
    foreach ($category in $Categories.Keys | Sort-Object) {
        # Category header with explicit sizing
        $header = New-Object System.Windows.Forms.Label
        $header.Text = $category
        $header.Location = New-Object System.Drawing.Point(20, $yPos)
        $header.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
        $header.ForeColor = [System.Drawing.Color]::FromArgb(0, 120, 215)
        $header.Size = New-Object System.Drawing.Size(750, 25)  # Explicit size
        $header.AutoSize = $false
        $script:ContentDisplay.Controls.Add($header)
        $yPos += 40
        
        # Items in columns with better layout tracking
        $xPos = [int]50
        $colWidth = [int]250
        $col = [int]0
        $maxCols = [int]3
        $rowStartY = $yPos
        $itemsInCategory = 0
        
        foreach ($item in $Categories[$category]) {
            # Skip items not for this Windows version
            if (($script:IsWindows11 -and $item.Win11 -eq $false) -or 
                (-not $script:IsWindows11 -and $item.Win10 -eq $false)) {
                continue
            }
            
            $checkbox = New-Object System.Windows.Forms.CheckBox
            $checkbox.Text = $item.Name
            $checkbox.Tag = $item.Key
            $xPosition = $xPos + ($col * $colWidth)
            $checkbox.Location = New-Object System.Drawing.Point($xPosition, $yPos)
            $checkbox.Size = New-Object System.Drawing.Size(240, 25)
            $checkbox.Checked = $item.Default
            $script:ContentDisplay.Controls.Add($checkbox)
            
            $itemsInCategory++
            $col++
            if ($col -ge $maxCols) {
                $col = 0
                $yPos += 30
            }
        }
        
        # Ensure we move to next row if items were added
        if ($itemsInCategory -gt 0) {
            if ($col -gt 0) {
                $yPos += 30  # Complete the current row
            }
            $yPos += 20  # Add spacing between categories
        }
    }
    
    # Calculate and set scroll size with generous margin
    $scrollHeight = $yPos + 150  # Generous margin for complete scrolling
    $scrollWidth = 800  # Ensure horizontal space for 3 columns
    
    # Force the panel to recognize the new content size
    $script:ContentDisplay.AutoScrollMinSize = New-Object System.Drawing.Size($scrollWidth, $scrollHeight)
    
    # Multiple refresh approaches to ensure scroll bars appear
    $script:ContentDisplay.Invalidate()
    $script:ContentDisplay.Update()
    $script:ContentDisplay.PerformLayout()
    $script:ContentDisplay.Refresh()
    
    # Reset scroll position to top for new content
    $script:ContentDisplay.AutoScrollPosition = New-Object System.Drawing.Point(0, 0)
    
    # Small delay to allow Windows Forms to calculate layout
    [System.Windows.Forms.Application]::DoEvents()
    Start-Sleep -Milliseconds 50
    
    # Final refresh after delay
    $script:ContentDisplay.PerformLayout()
    
    # Ensure the panel can receive focus for mouse wheel events
    $script:ContentDisplay.Focus()
    
    # Debug output to check scroll area
    Write-Host "Content height: $yPos, Scroll area: $scrollHeight, Panel size: $($script:ContentDisplay.ClientSize.Height)" -ForegroundColor Yellow
}

function Get-SelectedItems {
    param($CurrentCategories)
    
    $selectedItems = @()
    
    foreach ($control in $script:ContentDisplay.Controls) {
        if ($control -is [System.Windows.Forms.CheckBox] -and $control.Tag -and $control.Checked) {
            $selectedItems += $control.Tag
        }
    }
    
    return $selectedItems
}

function Update-StatusMessage {
    param(
        [string]$Message,
        [ValidateSet("INFO", "SUCCESS", "WARNING", "ERROR")]
        [string]$Level = "INFO"
    )
    
    # Update traditional status label
    $statusLabel.Text = $Message
    
    # Update progress system if available
    try {
        Update-ProgressStatus -Message $Message -Level $Level
    } catch {
        # Fallback to console output if progress system fails
        Write-Host "$(Get-Date -Format 'HH:mm:ss'): $Message" -ForegroundColor $(
            switch ($Level) {
                "SUCCESS" { "Green" }
                "WARNING" { "Yellow" }
                "ERROR" { "Red" }
                default { "White" }
            }
        )
    }
    
    [System.Windows.Forms.Application]::DoEvents()
}

function Save-CheckboxStates {
    param($TabType)
    
    $script:CheckboxStates[$TabType] = @{}
    
    foreach ($control in $script:ContentDisplay.Controls) {
        if ($control -is [System.Windows.Forms.CheckBox] -and $control.Tag) {
            $script:CheckboxStates[$TabType][$control.Tag] = $control.Checked
        }
    }
}

function Restore-CheckboxStates {
    param($TabType)
    
    if (-not $script:CheckboxStates.ContainsKey($TabType)) {
        return
    }
    
    foreach ($control in $script:ContentDisplay.Controls) {
        if ($control -is [System.Windows.Forms.CheckBox] -and $control.Tag) {
            if ($script:CheckboxStates[$TabType].ContainsKey($control.Tag)) {
                $control.Checked = $script:CheckboxStates[$TabType][$control.Tag]
            }
        }
    }
}



function Show-WindowsUpdateDialog {
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$WingetInfo
    )
    
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    
    # Create the dialog form
    $updateForm = New-Object System.Windows.Forms.Form
    $updateForm.Text = "Windows Update Required for Winget"
    $updateForm.Size = New-Object System.Drawing.Size(500, 400)
    $updateForm.StartPosition = "CenterParent"
    $updateForm.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $updateForm.MaximizeBox = $false
    $updateForm.MinimizeBox = $false
    $updateForm.ShowInTaskbar = $false
    
    # Warning icon and main message
    $iconLabel = New-Object System.Windows.Forms.Label
    $iconLabel.Text = "[WARNING]"
    $iconLabel.Font = New-Object System.Drawing.Font("Segoe UI", 16)
    $iconLabel.Location = New-Object System.Drawing.Point(20, 20)
    $iconLabel.Size = New-Object System.Drawing.Size(40, 40)
    $updateForm.Controls.Add($iconLabel)
    
    $titleLabel = New-Object System.Windows.Forms.Label
    $titleLabel.Text = "Windows Update Required"
    $titleLabel.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
    $titleLabel.Location = New-Object System.Drawing.Point(70, 25)
    $titleLabel.Size = New-Object System.Drawing.Size(400, 30)
    $updateForm.Controls.Add($titleLabel)
    
    # Information text
    $infoText = @"
Your current Windows version does not support winget (Windows Package Manager):

Current Version: $($WingetInfo.VersionName) (Build $($WingetInfo.BuildNumber))
Required Version: Windows 10 1709 or later (Build 16299+)

Winget provides faster and more reliable application installations. Without it, applications will be downloaded directly from their official sources, which may be slower.

You can update Windows to enable winget support, or continue with direct downloads.
"@
    
    $infoLabel = New-Object System.Windows.Forms.Label
    $infoLabel.Text = $infoText
    $infoLabel.Location = New-Object System.Drawing.Point(20, 70)
    $infoLabel.Size = New-Object System.Drawing.Size(440, 180)
    $infoLabel.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $updateForm.Controls.Add($infoLabel)
    
    # Button panel
    $buttonPanel = New-Object System.Windows.Forms.Panel
    $buttonPanel.Location = New-Object System.Drawing.Point(20, 270)
    $buttonPanel.Size = New-Object System.Drawing.Size(440, 80)
    $updateForm.Controls.Add($buttonPanel)
    
    # Open Windows Update button
    $updateButton = New-Object System.Windows.Forms.Button
    $updateButton.Text = "Open Windows Update"
    $updateButton.Size = New-Object System.Drawing.Size(140, 30)
    $updateButton.Location = New-Object System.Drawing.Point(0, 0)
    $updateButton.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 215)
    $updateButton.ForeColor = [System.Drawing.Color]::White
    $updateButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $updateButton.Add_Click({
        try {
            Start-Process "ms-settings:windowsupdate"
            [System.Windows.Forms.MessageBox]::Show(
                "Windows Update has been opened. Please install all available updates and restart your computer. After restarting, you can run this setup script again to use winget.",
                "Windows Update Opened",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information
            )
        } catch {
            [System.Windows.Forms.MessageBox]::Show(
                "Could not open Windows Update automatically. Please manually go to Settings > Update & Security > Windows Update and install all available updates.",
                "Manual Update Required",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Warning
            )
        }
    })
    $buttonPanel.Controls.Add($updateButton)
    
    # Recheck button
    $recheckButton = New-Object System.Windows.Forms.Button
    $recheckButton.Text = "Recheck Compatibility"
    $recheckButton.Size = New-Object System.Drawing.Size(140, 30)
    $recheckButton.Location = New-Object System.Drawing.Point(150, 0)
    $recheckButton.Add_Click({
        $newWingetInfo = Test-WingetCompatibility
        if ($newWingetInfo.Compatible) {
            [System.Windows.Forms.MessageBox]::Show(
                "Great! Your Windows version now supports winget. The script will continue with winget-based installations.",
                "Winget Compatible",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information
            )
            $updateForm.DialogResult = [System.Windows.Forms.DialogResult]::Retry
            $updateForm.Close()
        } else {
            [System.Windows.Forms.MessageBox]::Show(
                "Your Windows version still does not support winget. Please install more updates or continue with direct downloads.",
                "Still Incompatible",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Warning
            )
        }
    })
    $buttonPanel.Controls.Add($recheckButton)
    
    # Continue anyway button
    $continueButton = New-Object System.Windows.Forms.Button
    $continueButton.Text = "Continue with Direct Downloads"
    $continueButton.Size = New-Object System.Drawing.Size(140, 30)
    $continueButton.Location = New-Object System.Drawing.Point(300, 0)
    $continueButton.Add_Click({
        $updateForm.DialogResult = [System.Windows.Forms.DialogResult]::Ignore
        $updateForm.Close()
    })
    $buttonPanel.Controls.Add($continueButton)
    
    # Help text
    $helpLabel = New-Object System.Windows.Forms.Label
    $helpLabel.Text = "TIP: After updating Windows, restart your computer and run this script again for the best experience."
    $helpLabel.Location = New-Object System.Drawing.Point(0, 40)
    $helpLabel.Size = New-Object System.Drawing.Size(440, 30)
    $helpLabel.Font = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Italic)
    $helpLabel.ForeColor = [System.Drawing.Color]::Gray
    $buttonPanel.Controls.Add($helpLabel)
    
    # Show the dialog and return the result
    return $updateForm.ShowDialog()
}

# Track current tab for state saving
$script:CurrentTab = "Apps"

# Tab selection event handler
$tabControl.Add_SelectedIndexChanged({
    # Save current tab state before switching
    Save-CheckboxStates -TabType $script:CurrentTab
    
    $selectedTab = $tabControl.SelectedTab
    
    # Add small delay to ensure proper tab switching
    [System.Windows.Forms.Application]::DoEvents()
    
    switch ($selectedTab.Text) {
        "Apps" { 
            $script:CurrentTab = "Apps"
            Show-TabContent -Categories $script:Apps -Title "Select Applications to Install"
            # Small delay before restoring states
            [System.Windows.Forms.Application]::DoEvents()
            Start-Sleep -Milliseconds 50
            Restore-CheckboxStates -TabType "Apps"
        }
        "Bloatware" { 
            $script:CurrentTab = "Bloatware"
            Show-TabContent -Categories $script:Bloatware -Title "Select Bloatware to Remove"
            [System.Windows.Forms.Application]::DoEvents()
            Start-Sleep -Milliseconds 50
            Restore-CheckboxStates -TabType "Bloatware"
        }
        "Services" { 
            $script:CurrentTab = "Services"
            Show-TabContent -Categories $script:Services -Title "Select Services to Disable"
            [System.Windows.Forms.Application]::DoEvents()
            Start-Sleep -Milliseconds 50
            Restore-CheckboxStates -TabType "Services"
        }
        "Tweaks" { 
            $script:CurrentTab = "Tweaks"
            Show-TabContent -Categories $script:Tweaks -Title "Select System Tweaks to Apply"
            [System.Windows.Forms.Application]::DoEvents()
            Start-Sleep -Milliseconds 50
            Restore-CheckboxStates -TabType "Tweaks"
        }
    }
})

# Show initial content (Apps tab) with winget compatibility info
$wingetInfo = Test-WingetCompatibility
if ($wingetInfo.Compatible) {
    if ($wingetInfo.Available) {
        Show-TabContent -Categories $script:Apps -Title "Select Applications to Install (Winget Available)"
    } else {
        Show-TabContent -Categories $script:Apps -Title "Select Applications to Install (Winget Compatible - May Need Registration)"
    }
} else {
    Show-TabContent -Categories $script:Apps -Title "Select Applications to Install (Direct Downloads - Build $($wingetInfo.BuildNumber) < 16299)"
}

# Event handlers
$runBtn.Add_Click({
    try {
        $runBtn.Enabled = $false
        $cancelBtn.Text = "Cancel"
        
        # Reset progress system
        Reset-ProgressSystem
        
        Update-StatusMessage "Starting Windows Setup Operations..." "INFO"
        
        # Save current tab state before processing
        Save-CheckboxStates -TabType $script:CurrentTab
        
        # Determine current tab and get selected items
        $selectedTab = $tabControl.SelectedTab
        $selectedItems = @()
        $operationType = ""
        
        switch ($selectedTab.Text) {
            "Apps" { 
                $selectedItems = Get-SelectedItems -CurrentCategories $script:Apps
                $operationType = "Install Applications"
            }
            "Bloatware" { 
                $selectedItems = Get-SelectedItems -CurrentCategories $script:Bloatware
                $operationType = "Remove Bloatware"
            }
            "Services" { 
                $selectedItems = Get-SelectedItems -CurrentCategories $script:Services
                $operationType = "Disable Services"
            }
            "Tweaks" { 
                $selectedItems = Get-SelectedItems -CurrentCategories $script:Tweaks
                $operationType = "Apply System Tweaks"
            }
        }
        
        if ($selectedItems.Count -eq 0) {
            Update-StatusMessage "No items selected. Please select items to process." "WARNING"
            return
        }
        
        # Start progress tracking
        Start-ProgressOperation -TotalSteps $selectedItems.Count -OperationName $operationType
        Update-StatusMessage "$operationType - Processing $($selectedItems.Count) items..." "INFO"
        
        # Process based on operation type
        switch ($selectedTab.Text) {
            "Apps" {
                # Setup winget environment before installing apps
                Update-StatusMessage "Setting up winget environment..." "INFO"
                
                # Initialize winget environment (check → install → verify)
                $wingetResult = Initialize-WingetEnvironment
                
                if ($wingetResult.Success) {
                    if ($wingetResult.AlreadyAvailable) {
                        Update-StatusMessage "Winget is ready (version: $($wingetResult.Version))" "SUCCESS"
                    } elseif ($wingetResult.Installed) {
                        Update-StatusMessage "Winget installed successfully (version: $($wingetResult.Version))" "SUCCESS"
                    } elseif ($wingetResult.Registered) {
                        Update-StatusMessage "Winget registered successfully (version: $($wingetResult.Version))" "SUCCESS"
                    }
                    $script:UseWingetForApps = $true
                } else {
                    switch ($wingetResult.Reason) {
                        "IncompatibleWindows" {
                            $buildNumber = $wingetResult.Details.BuildNumber
                            Update-StatusMessage "Windows build $buildNumber incompatible with winget (requires 16299+)" "WARNING"
                        }
                        "InstallationFailed" {
                            Update-StatusMessage "Failed to install winget, using direct downloads" "WARNING"
                        }
                        default {
                            Update-StatusMessage "Winget setup failed, using direct downloads" "WARNING"
                        }
                    }
                    $script:UseWingetForApps = $false
                }
                
                # Winget setup complete - proceed with app installations
                
                foreach ($appKey in $selectedItems) {
                    $installerName = Get-InstallerName -AppKey $appKey
                    Update-StatusMessage "Installing $installerName..." "INFO"
                    try {
                        if ($script:UseWingetForApps) {
                            # Use winget with ID mapping for optimal installation
                            $wingetId = Get-WingetId -AppKey $appKey
                            if ($wingetId) {
                                Install-Application -AppName $installerName -WingetId $wingetId
                            } else {
                                Install-Application -AppName $installerName
                            }
                        } else {
                            # Use direct downloads (winget not available/compatible)
                            Install-Application -AppName $installerName
                        }
                        Update-StatusMessage "Successfully installed $installerName" "SUCCESS"
                    } catch {
                        Update-StatusMessage "Failed to install $installerName - $_" "ERROR"
                        Write-LogMessage -Message "Failed to install $appKey - ${_}" -Level "ERROR"
                    }
                }
            }
            "Bloatware" {
                foreach ($bloatKey in $selectedItems) {
                    Update-StatusMessage "Removing bloatware $bloatKey..." "INFO"
                    try {
                        Remove-Bloatware -BloatwareKey $bloatKey
                        Update-StatusMessage "Successfully removed $bloatKey" "SUCCESS"
                    } catch {
                        Update-StatusMessage "Failed to remove $bloatKey - $_" "ERROR"
                        Write-LogMessage -Message "Failed to remove bloatware $bloatKey - ${_}" -Level "ERROR"
                    }
                }
            }
            "Services" {
                foreach ($serviceKey in $selectedItems) {
                    Update-StatusMessage "Disabling service $serviceKey..." "INFO"
                    try {
                        Set-SystemOptimization -OptimizationKey $serviceKey
                        Update-StatusMessage "Successfully disabled $serviceKey" "SUCCESS"
                    } catch {
                        Update-StatusMessage "Failed to disable $serviceKey - $_" "ERROR"
                        Write-LogMessage -Message "Failed to disable service $serviceKey - ${_}" -Level "ERROR"
                    }
                }
            }
            "Tweaks" {
                foreach ($tweakKey in $selectedItems) {
                    Update-StatusMessage "Applying tweak $tweakKey..." "INFO"
                    try {
                        Set-SystemOptimization -OptimizationKey $tweakKey
                        Update-StatusMessage "Successfully applied $tweakKey" "SUCCESS"
                    } catch {
                        Update-StatusMessage "Failed to apply $tweakKey - $_" "ERROR"
                        Write-LogMessage -Message "Failed to apply tweak $tweakKey - ${_}" -Level "ERROR"
                    }
                }
            }
        }
        
        # Complete progress operation
        Complete-ProgressOperation -FinalMessage "All operations completed successfully!" -CompletionStatus "SUCCESS"
        
    } catch {
        Complete-ProgressOperation -FinalMessage "Error during operations: $_" -CompletionStatus "ERROR"
        Write-LogMessage -Message "GUI operation error: $_" -Level "ERROR"
    } finally {
        $runBtn.Enabled = $true
        $cancelBtn.Text = "Close"
    }
})

$cancelBtn.Add_Click({
    $form.Close()
})

Write-Host "Launching Windows Setup GUI..." -ForegroundColor Green
Write-Host "4 tabs: Install Apps, Remove Bloatware, Disable Services, System Tweaks" -ForegroundColor Yellow

# Display log file location
$logPath = Get-LogFilePath
if ($logPath) {
    Write-Host "Log file: $logPath" -ForegroundColor Cyan
} else {
    Write-Host "Warning: Logging may not be working properly" -ForegroundColor Yellow
}

# Show form
[void]$form.ShowDialog()