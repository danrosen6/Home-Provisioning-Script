#Requires -RunAsAdministrator

# Windows Setup Automation GUI - Simplified Version
# Uses JSON configs but keeps implementation simple

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# Import required modules
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
Import-Module (Join-Path $scriptPath "utils\Logging.psm1") -Force
Import-Module (Join-Path $scriptPath "utils\SimpleConfigLoader.psm1") -Force
Import-Module (Join-Path $scriptPath "modules\Installers.psm1") -Force
Import-Module (Join-Path $scriptPath "modules\SystemOptimizations.psm1") -Force

# Initialize logging
Initialize-Logging

# Load configurations from JSON files
$script:Apps = Get-ConfigData -ConfigType "apps"
$script:Bloatware = Get-ConfigData -ConfigType "bloatware" 
$script:Services = Get-ConfigData -ConfigType "services"
$script:Tweaks = Get-ConfigData -ConfigType "tweaks"

# Global variables
$script:CurrentTab = "Apps"
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

# Simple winget compatibility check
function Test-WingetAvailable {
    try {
        $buildNumber = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion").CurrentBuild
        $isCompatible = ([int]$buildNumber -ge 16299)
        $wingetAvailable = (Get-Command winget -ErrorAction SilentlyContinue) -ne $null
        
        return @{
            Compatible = $isCompatible
            Available = $wingetAvailable
            BuildNumber = $buildNumber
        }
    } catch {
        return @{
            Compatible = $false
            Available = $false
            BuildNumber = "Unknown"
        }
    }
}

# Helper functions
function Get-SelectedItems {
    $selectedItems = @()
    foreach ($control in $script:ContentDisplay.Controls) {
        if ($control -is [System.Windows.Forms.CheckBox] -and $control.Tag -and $control.Checked) {
            $selectedItems += $control.Tag
        }
    }
    return $selectedItems
}

function Update-StatusMessage {
    param($Message)
    
    $statusLabel.Text = $Message
    $logBox.Text += "$(Get-Date -Format 'HH:mm:ss'): $Message`r`n"
    $logBox.SelectionStart = $logBox.Text.Length
    $logBox.ScrollToCaret()
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

function Show-TabContent {
    param($Categories, $Title)
    
    # Clear and reset content area
    $script:ContentDisplay.Controls.Clear()
    $script:ContentDisplay.AutoScrollPosition = New-Object System.Drawing.Point(0, 0)
    
    $yPos = 20
    
    # Title
    $titleLabel = New-Object System.Windows.Forms.Label
    $titleLabel.Text = $Title
    $titleLabel.Font = New-Object System.Drawing.Font("Segoe UI", 14, [System.Drawing.FontStyle]::Bold)
    $titleLabel.Location = New-Object System.Drawing.Point(20, $yPos)
    $titleLabel.Size = New-Object System.Drawing.Size(800, 30)
    $titleLabel.AutoSize = $false
    $script:ContentDisplay.Controls.Add($titleLabel)
    $yPos += 50
    
    # Select All checkbox
    $selectAll = New-Object System.Windows.Forms.CheckBox
    $selectAll.Text = "Select All"
    $selectAll.Location = New-Object System.Drawing.Point(20, $yPos)
    $selectAll.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $selectAll.Size = New-Object System.Drawing.Size(200, 25)
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
        # Category header
        $header = New-Object System.Windows.Forms.Label
        $header.Text = $category
        $header.Location = New-Object System.Drawing.Point(20, $yPos)
        $header.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
        $header.ForeColor = [System.Drawing.Color]::FromArgb(0, 120, 215)
        $header.Size = New-Object System.Drawing.Size(750, 25)
        $header.AutoSize = $false
        $script:ContentDisplay.Controls.Add($header)
        $yPos += 40
        
        # Items in columns
        $xPos = 50
        $colWidth = 250
        $col = 0
        $maxCols = 3
        
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
            
            $col++
            if ($col -ge $maxCols) {
                $col = 0
                $yPos += 30
            }
        }
        
        # Complete current row and add spacing
        if ($col -gt 0) {
            $yPos += 30
        }
        $yPos += 20
    }
    
    # Set scroll area
    $script:ContentDisplay.AutoScrollMinSize = New-Object System.Drawing.Size(800, $yPos + 100)
    $script:ContentDisplay.PerformLayout()
}

# Create main form
$form = New-Object System.Windows.Forms.Form
$form.Text = "Windows Setup Automation"
$form.Size = New-Object System.Drawing.Size(900, 700)
$form.StartPosition = "CenterScreen"
$form.MinimumSize = New-Object System.Drawing.Size(800, 600)

# Header
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
if ($script:IsWindows11) {
    $osLabel.Text = "Windows 11"
} else {
    $osLabel.Text = "Windows 10"
}
$osLabel.ForeColor = [System.Drawing.Color]::White
$osLabel.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$osLabel.Location = New-Object System.Drawing.Point(750, 25)
$osLabel.AutoSize = $true
$header.Controls.Add($osLabel)

$form.Controls.Add($header)

# Bottom control area
$bottomArea = New-Object System.Windows.Forms.Panel
$bottomArea.Height = 180
$bottomArea.Dock = [System.Windows.Forms.DockStyle]::Bottom
$bottomArea.BackColor = [System.Drawing.Color]::FromArgb(240, 240, 240)

# Tab control
$tabControl = New-Object System.Windows.Forms.TabControl
$tabControl.Size = New-Object System.Drawing.Size(500, 120)
$tabControl.Location = New-Object System.Drawing.Point(20, 10)

# Control buttons
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

# Log area
$logBox = New-Object System.Windows.Forms.TextBox
$logBox.Multiline = $true
$logBox.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
$logBox.ReadOnly = $true
$logBox.Location = New-Object System.Drawing.Point(20, 140)
$logBox.Size = New-Object System.Drawing.Size(840, 30)
$logBox.BackColor = [System.Drawing.Color]::Black
$logBox.ForeColor = [System.Drawing.Color]::Lime
$logBox.Font = New-Object System.Drawing.Font("Consolas", 8)
$bottomArea.Controls.Add($logBox)

$form.Controls.Add($bottomArea)

# Main content area
$contentArea = New-Object System.Windows.Forms.Panel
$contentArea.Dock = [System.Windows.Forms.DockStyle]::Fill
$contentArea.BackColor = [System.Drawing.Color]::White

$contentDisplay = New-Object System.Windows.Forms.Panel
$contentDisplay.Dock = [System.Windows.Forms.DockStyle]::Fill
$contentDisplay.AutoScroll = $true
$contentDisplay.BackColor = [System.Drawing.Color]::White

# Mouse wheel scrolling
$contentDisplay.Add_MouseWheel({
    param($sender, $e)
    $scrollAmount = [Math]::Max(1, [Math]::Abs($e.Delta) / 120) * 40
    $currentY = -$sender.AutoScrollPosition.Y
    
    if ($e.Delta -gt 0) {
        $newY = [Math]::Max(0, $currentY - $scrollAmount)
    } else {
        $contentHeight = $sender.AutoScrollMinSize.Height
        $panelHeight = $sender.ClientSize.Height
        $maxY = [Math]::Max(0, $contentHeight - $panelHeight)
        $newY = [Math]::Min($maxY, $currentY + $scrollAmount)
    }
    
    $sender.AutoScrollPosition = New-Object System.Drawing.Point(0, $newY)
    $e.Handled = $true
})

$contentDisplay.Add_MouseEnter({ $this.Focus() })

$contentArea.Controls.Add($contentDisplay)
$form.Controls.Add($contentArea)

# Store reference for tab switching
$script:ContentDisplay = $contentDisplay

# Create tabs
$tabApps = New-Object System.Windows.Forms.TabPage
$tabApps.Text = "Apps"

$tabBloatware = New-Object System.Windows.Forms.TabPage
$tabBloatware.Text = "Bloatware"

$tabServices = New-Object System.Windows.Forms.TabPage
$tabServices.Text = "Services"

$tabTweaks = New-Object System.Windows.Forms.TabPage
$tabTweaks.Text = "Tweaks"

$tabControl.TabPages.Add($tabApps)
$tabControl.TabPages.Add($tabBloatware)
$tabControl.TabPages.Add($tabServices)
$tabControl.TabPages.Add($tabTweaks)

# Tab selection handler
$tabControl.Add_SelectedIndexChanged({
    Save-CheckboxStates -TabType $script:CurrentTab
    
    $selectedTab = $tabControl.SelectedTab
    [System.Windows.Forms.Application]::DoEvents()
    
    switch ($selectedTab.Text) {
        "Apps" { 
            $script:CurrentTab = "Apps"
            Show-TabContent -Categories $script:Apps -Title "Select Applications to Install"
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

# Run button handler
$runBtn.Add_Click({
    try {
        $runBtn.Enabled = $false
        $cancelBtn.Text = "Cancel"
        $logBox.Text = ""
        
        Update-StatusMessage "Starting Windows Setup Operations..."
        Save-CheckboxStates -TabType $script:CurrentTab
        
        $selectedTab = $tabControl.SelectedTab
        $selectedItems = Get-SelectedItems
        
        if ($selectedItems.Count -eq 0) {
            Update-StatusMessage "No items selected. Please select items to process."
            return
        }
        
        Update-StatusMessage "Processing $($selectedItems.Count) items..."
        
        switch ($selectedTab.Text) {
            "Apps" {
                $wingetInfo = Test-WingetAvailable
                if ($wingetInfo.Available) {
                    Update-StatusMessage "Using winget for installations"
                } else {
                    Update-StatusMessage "Using direct downloads (winget not available)"
                }
                
                foreach ($appKey in $selectedItems) {
                    Update-StatusMessage "Installing $appKey..."
                    try {
                        if ($wingetInfo.Available) {
                            $wingetId = Get-WingetIdFromConfig -AppKey $appKey
                            if ($wingetId) {
                                Install-Application -AppName $appKey -WingetId $wingetId
                            } else {
                                Install-Application -AppName $appKey
                            }
                        } else {
                            Install-Application -AppName $appKey
                        }
                        Update-StatusMessage "[SUCCESS] Installed $appKey"
                    } catch {
                        Update-StatusMessage "[ERROR] Failed to install $appKey - $_"
                        Write-LogMessage -Message "Failed to install $appKey - $_" -Level "ERROR"
                    }
                }
            }
            "Bloatware" {
                foreach ($bloatKey in $selectedItems) {
                    Update-StatusMessage "Removing $bloatKey..."
                    try {
                        Remove-Bloatware -BloatwareKey $bloatKey
                        Update-StatusMessage "[SUCCESS] Removed $bloatKey"
                    } catch {
                        Update-StatusMessage "[ERROR] Failed to remove $bloatKey - $_"
                        Write-LogMessage -Message "Failed to remove $bloatKey - $_" -Level "ERROR"
                    }
                }
            }
            "Services" {
                foreach ($serviceKey in $selectedItems) {
                    Update-StatusMessage "Disabling service $serviceKey..."
                    try {
                        Set-SystemOptimization -OptimizationKey $serviceKey
                        Update-StatusMessage "[SUCCESS] Disabled $serviceKey"
                    } catch {
                        Update-StatusMessage "[ERROR] Failed to disable $serviceKey - $_"
                        Write-LogMessage -Message "Failed to disable $serviceKey - $_" -Level "ERROR"
                    }
                }
            }
            "Tweaks" {
                foreach ($tweakKey in $selectedItems) {
                    Update-StatusMessage "Applying tweak $tweakKey..."
                    try {
                        Set-SystemOptimization -OptimizationKey $tweakKey
                        Update-StatusMessage "[SUCCESS] Applied $tweakKey"
                    } catch {
                        Update-StatusMessage "[ERROR] Failed to apply $tweakKey - $_"
                        Write-LogMessage -Message "Failed to apply $tweakKey - $_" -Level "ERROR"
                    }
                }
            }
        }
        
        Update-StatusMessage "All operations completed!"
        
    } catch {
        Update-StatusMessage "Error during operations: $_"
        Write-LogMessage -Message "GUI operation error: $_" -Level "ERROR"
    } finally {
        $runBtn.Enabled = $true
        $cancelBtn.Text = "Close"
    }
})

$cancelBtn.Add_Click({
    $form.Close()
})

# Show initial content
$wingetInfo = Test-WingetAvailable
if ($wingetInfo.Available) {
    Show-TabContent -Categories $script:Apps -Title "Select Applications to Install (Winget Available)"
} else {
    Show-TabContent -Categories $script:Apps -Title "Select Applications to Install (Direct Downloads)"
}

Write-Host "Launching Windows Setup GUI..." -ForegroundColor Green
Write-Host "Using JSON configurations for apps, bloatware, services, and tweaks" -ForegroundColor Yellow

$logPath = Get-LogFilePath
if ($logPath) {
    Write-Host "Log file: $logPath" -ForegroundColor Cyan
}

# Show the form
[void]$form.ShowDialog()