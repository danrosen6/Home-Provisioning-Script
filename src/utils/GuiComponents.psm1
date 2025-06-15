# GUI Components for Windows Setup GUI

function New-MainForm {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [string]$Title = "Windows Setup Automation",
        
        [Parameter(Mandatory=$false)]
        [System.Drawing.Size]$Size = [System.Drawing.Size]::new(900, 700),
        
        [Parameter(Mandatory=$false)]
        [System.Drawing.Size]$MinimumSize = [System.Drawing.Size]::new(800, 600)
    )
    
    $form = New-Object System.Windows.Forms.Form
    $form.Text = $Title
    $form.Size = $Size
    $form.StartPosition = "CenterScreen"
    $form.MinimumSize = $MinimumSize
    
    return $form
}

function New-HeaderPanel {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [System.Windows.Forms.Form]$ParentForm,
        
        [Parameter(Mandatory=$false)]
        [string]$Title = "Windows Setup Automation",
        
        [Parameter(Mandatory=$false)]
        [string]$OSInfo = ""
    )
    
    # Header at top
    $header = New-Object System.Windows.Forms.Panel
    $header.Height = 60
    $header.Dock = [System.Windows.Forms.DockStyle]::Top
    $header.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 215)
    
    $titleLabel = New-Object System.Windows.Forms.Label
    $titleLabel.Text = $Title
    $titleLabel.ForeColor = [System.Drawing.Color]::White
    $titleLabel.Font = New-Object System.Drawing.Font("Segoe UI", 16)
    $titleLabel.Location = New-Object System.Drawing.Point(20, 20)
    $titleLabel.AutoSize = $true
    $header.Controls.Add($titleLabel)
    
    if ($OSInfo) {
        $osLabel = New-Object System.Windows.Forms.Label
        $osLabel.Text = $OSInfo
        $osLabel.ForeColor = [System.Drawing.Color]::White
        $osLabel.Font = New-Object System.Drawing.Font("Segoe UI", 10)
        $osLabel.Location = New-Object System.Drawing.Point(750, 25)
        $osLabel.AutoSize = $true
        $header.Controls.Add($osLabel)
    }
    
    $ParentForm.Controls.Add($header)
    
    return $header
}

function New-BottomPanel {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [System.Windows.Forms.Form]$ParentForm
    )
    
    # Bottom area with tabs and controls
    $bottomArea = New-Object System.Windows.Forms.Panel
    $bottomArea.Height = 180
    $bottomArea.Dock = [System.Windows.Forms.DockStyle]::Bottom
    $bottomArea.BackColor = [System.Drawing.Color]::FromArgb(240, 240, 240)
    
    $ParentForm.Controls.Add($bottomArea)
    
    return $bottomArea
}

function New-TabControl {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [System.Windows.Forms.Panel]$ParentPanel,
        
        [Parameter(Mandatory=$false)]
        [System.Drawing.Size]$Size = [System.Drawing.Size]::new(500, 120),
        
        [Parameter(Mandatory=$false)]
        [System.Drawing.Point]$Location = [System.Drawing.Point]::new(20, 10)
    )
    
    # Tab control in bottom area
    $tabControl = New-Object System.Windows.Forms.TabControl
    $tabControl.Size = $Size
    $tabControl.Location = $Location
    
    $ParentPanel.Controls.Add($tabControl)
    
    return $tabControl
}

function New-ControlPanel {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [System.Windows.Forms.Panel]$ParentPanel,
        
        [Parameter(Mandatory=$false)]
        [System.Drawing.Size]$Size = [System.Drawing.Size]::new(350, 120),
        
        [Parameter(Mandatory=$false)]
        [System.Drawing.Point]$Location = [System.Drawing.Point]::new(530, 10)
    )
    
    # Control buttons area
    $controlPanel = New-Object System.Windows.Forms.Panel
    $controlPanel.Size = $Size
    $controlPanel.Location = $Location
    $controlPanel.BackColor = [System.Drawing.Color]::FromArgb(220, 220, 220)
    
    $ParentPanel.Controls.Add($controlPanel)
    
    return $controlPanel
}

function New-ActionButtons {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [System.Windows.Forms.Panel]$ParentPanel
    )
    
    $runBtn = New-Object System.Windows.Forms.Button
    $runBtn.Text = "Run Selected Tasks"
    $runBtn.Size = New-Object System.Drawing.Size(150, 35)
    $runBtn.Location = New-Object System.Drawing.Point(20, 20)
    $runBtn.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 215)
    $runBtn.ForeColor = [System.Drawing.Color]::White
    $runBtn.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $ParentPanel.Controls.Add($runBtn)
    
    $cancelBtn = New-Object System.Windows.Forms.Button
    $cancelBtn.Text = "Cancel"
    $cancelBtn.Size = New-Object System.Drawing.Size(100, 35)
    $cancelBtn.Location = New-Object System.Drawing.Point(180, 20)
    $cancelBtn.BackColor = [System.Drawing.Color]::Gray
    $cancelBtn.ForeColor = [System.Drawing.Color]::White
    $cancelBtn.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $ParentPanel.Controls.Add($cancelBtn)
    
    $statusLabel = New-Object System.Windows.Forms.Label
    $statusLabel.Text = "Select options in tabs and click Run"
    $statusLabel.Location = New-Object System.Drawing.Point(20, 65)
    $statusLabel.Size = New-Object System.Drawing.Size(300, 20)
    $ParentPanel.Controls.Add($statusLabel)
    
    return @{
        RunButton = $runBtn
        CancelButton = $cancelBtn
        StatusLabel = $statusLabel
    }
}

function New-LogTextBox {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [System.Windows.Forms.Panel]$ParentPanel,
        
        [Parameter(Mandatory=$false)]
        [System.Drawing.Point]$Location = [System.Drawing.Point]::new(20, 140),
        
        [Parameter(Mandatory=$false)]
        [System.Drawing.Size]$Size = [System.Drawing.Size]::new(840, 30)
    )
    
    # Log area at very bottom
    $logBox = New-Object System.Windows.Forms.TextBox
    $logBox.Multiline = $true
    $logBox.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
    $logBox.ReadOnly = $true
    $logBox.Location = $Location
    $logBox.Size = $Size
    $logBox.BackColor = [System.Drawing.Color]::Black
    $logBox.ForeColor = [System.Drawing.Color]::Lime
    $logBox.Font = New-Object System.Drawing.Font("Consolas", 8)
    $ParentPanel.Controls.Add($logBox)
    
    return $logBox
}

function New-ContentArea {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [System.Windows.Forms.Form]$ParentForm
    )
    
    # Main content area (fills remaining space above bottom area)
    $contentArea = New-Object System.Windows.Forms.Panel
    $contentArea.Dock = [System.Windows.Forms.DockStyle]::Fill
    $contentArea.BackColor = [System.Drawing.Color]::White
    
    $ParentForm.Controls.Add($contentArea)
    
    return $contentArea
}

function New-ScrollableContentDisplay {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [System.Windows.Forms.Panel]$ParentPanel
    )
    
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
    
    $ParentPanel.Controls.Add($contentDisplay)
    
    return $contentDisplay
}

function New-TabPages {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [System.Windows.Forms.TabControl]$TabControl,
        
        [Parameter(Mandatory=$false)]
        [string[]]$TabNames = @("Apps", "Bloatware", "Services", "Tweaks")
    )
    
    $tabPages = @{}
    
    foreach ($tabName in $TabNames) {
        $tabPage = New-Object System.Windows.Forms.TabPage
        $tabPage.Text = $tabName
        $TabControl.TabPages.Add($tabPage)
        $tabPages[$tabName] = $tabPage
    }
    
    return $tabPages
}

function Add-SelectAllCheckbox {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [System.Windows.Forms.Panel]$ParentPanel,
        
        [Parameter(Mandatory=$false)]
        [System.Drawing.Point]$Location = [System.Drawing.Point]::new(20, 50),
        
        [Parameter(Mandatory=$false)]
        [string]$Text = "Select All"
    )
    
    $selectAll = New-Object System.Windows.Forms.CheckBox
    $selectAll.Text = $Text
    $selectAll.Location = $Location
    $selectAll.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $selectAll.Size = New-Object System.Drawing.Size(200, 25)
    $selectAll.AutoSize = $false
    $selectAll.Add_CheckedChanged({
        $checked = $this.Checked
        foreach ($control in $this.Parent.Controls) {
            if ($control -is [System.Windows.Forms.CheckBox] -and $control -ne $this) {
                $control.Checked = $checked
            }
        }
    })
    $ParentPanel.Controls.Add($selectAll)
    
    return $selectAll
}

function New-TitleLabel {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [System.Windows.Forms.Panel]$ParentPanel,
        
        [Parameter(Mandatory=$true)]
        [string]$Text,
        
        [Parameter(Mandatory=$false)]
        [System.Drawing.Point]$Location = [System.Drawing.Point]::new(20, 20)
    )
    
    $titleLabel = New-Object System.Windows.Forms.Label
    $titleLabel.Text = $Text
    $titleLabel.Font = New-Object System.Drawing.Font("Segoe UI", 14, [System.Drawing.FontStyle]::Bold)
    $titleLabel.Location = $Location
    $titleLabel.Size = New-Object System.Drawing.Size(800, 30)
    $titleLabel.AutoSize = $false
    $ParentPanel.Controls.Add($titleLabel)
    
    return $titleLabel
}

function Add-CategoryHeader {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [System.Windows.Forms.Panel]$ParentPanel,
        
        [Parameter(Mandatory=$true)]
        [string]$Text,
        
        [Parameter(Mandatory=$true)]
        [System.Drawing.Point]$Location
    )
    
    $header = New-Object System.Windows.Forms.Label
    $header.Text = $Text
    $header.Location = $Location
    $header.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
    $header.ForeColor = [System.Drawing.Color]::FromArgb(0, 120, 215)
    $header.Size = New-Object System.Drawing.Size(750, 25)
    $header.AutoSize = $false
    $ParentPanel.Controls.Add($header)
    
    return $header
}

function Add-ItemCheckbox {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [System.Windows.Forms.Panel]$ParentPanel,
        
        [Parameter(Mandatory=$true)]
        [hashtable]$Item,
        
        [Parameter(Mandatory=$true)]
        [System.Drawing.Point]$Location
    )
    
    $checkbox = New-Object System.Windows.Forms.CheckBox
    $checkbox.Text = $Item.Name
    $checkbox.Tag = $Item.Key
    $checkbox.Location = $Location
    $checkbox.Size = New-Object System.Drawing.Size(240, 25)
    $checkbox.Checked = $Item.Default
    $ParentPanel.Controls.Add($checkbox)
    
    return $checkbox
}

# Parameter validation function
function Test-RequiredParameters {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$Parameters,
        
        [Parameter(Mandatory=$true)]
        [string[]]$RequiredKeys
    )
    
    foreach ($key in $RequiredKeys) {
        if (-not $Parameters.ContainsKey($key) -or $null -eq $Parameters[$key]) {
            throw "Required parameter '$key' is missing or null"
        }
    }
}

Export-ModuleMember -Function @(
    "New-MainForm",
    "New-HeaderPanel", 
    "New-BottomPanel",
    "New-TabControl",
    "New-ControlPanel",
    "New-ActionButtons",
    "New-LogTextBox",
    "New-ContentArea",
    "New-ScrollableContentDisplay",
    "New-TabPages",
    "Add-SelectAllCheckbox",
    "New-TitleLabel",
    "Add-CategoryHeader",
    "Add-ItemCheckbox",
    "Test-RequiredParameters"
)