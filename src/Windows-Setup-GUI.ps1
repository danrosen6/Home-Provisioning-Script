#Requires -RunAsAdministrator

# Windows Setup Automation GUI - Fixed Version
# Clean implementation focused on working tab switching and scrolling

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# Import required modules
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
Import-Module (Join-Path $scriptPath "modules\Installers.psm1") -Force
Import-Module (Join-Path $scriptPath "modules\SystemOptimizations.psm1") -Force
Import-Module (Join-Path $scriptPath "utils\Logging.psm1") -Force
Import-Module (Join-Path $scriptPath "utils\RecoveryUtils.psm1") -Force

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

# App definitions
$script:Apps = @{
    "Development" = @(
        @{Name="Visual Studio Code"; Key="vscode"; Default=$true; Win10=$true; Win11=$true}
        @{Name="Git"; Key="git"; Default=$true; Win10=$true; Win11=$true}
        @{Name="Python"; Key="python"; Default=$true; Win10=$true; Win11=$true}
        @{Name="PyCharm Community"; Key="pycharm"; Default=$false; Win10=$true; Win11=$true}
        @{Name="GitHub Desktop"; Key="github"; Default=$false; Win10=$true; Win11=$true}
        @{Name="Postman"; Key="postman"; Default=$false; Win10=$true; Win11=$true}
        @{Name="Node.js"; Key="nodejs"; Default=$false; Win10=$false; Win11=$true}
        @{Name="Windows Terminal"; Key="terminal"; Default=$true; Win10=$false; Win11=$true}
    )
    "Browsers" = @(
        @{Name="Google Chrome"; Key="chrome"; Default=$true; Win10=$true; Win11=$true}
        @{Name="Mozilla Firefox"; Key="firefox"; Default=$false; Win10=$true; Win11=$true}
        @{Name="Brave Browser"; Key="brave"; Default=$false; Win10=$true; Win11=$true}
    )
    "Media & Communication" = @(
        @{Name="Spotify"; Key="spotify"; Default=$true; Win10=$true; Win11=$true}
        @{Name="Discord"; Key="discord"; Default=$true; Win10=$true; Win11=$true}
        @{Name="Steam"; Key="steam"; Default=$false; Win10=$true; Win11=$true}
        @{Name="VLC Media Player"; Key="vlc"; Default=$false; Win10=$true; Win11=$true}
    )
    "Utilities" = @(
        @{Name="7-Zip"; Key="7zip"; Default=$false; Win10=$true; Win11=$true}
        @{Name="Notepad++"; Key="notepad"; Default=$false; Win10=$true; Win11=$true}
        @{Name="Microsoft PowerToys"; Key="powertoys"; Default=$true; Win10=$false; Win11=$true}
    )
}

# Bloatware definitions
$script:Bloatware = @{
    "Microsoft Office & Productivity" = @(
        @{Name="Microsoft Office Hub"; Key="ms-officehub"; Default=$true; Win10=$true; Win11=$true}
        @{Name="Microsoft Teams (Consumer)"; Key="ms-teams"; Default=$true; Win10=$false; Win11=$true}
        @{Name="OneNote (Store)"; Key="ms-onenote"; Default=$true; Win10=$true; Win11=$true}
        @{Name="Microsoft People"; Key="ms-people"; Default=$true; Win10=$true; Win11=$true}
        @{Name="Microsoft To-Do"; Key="ms-todo"; Default=$true; Win10=$false; Win11=$true}
    )
    "Windows Built-ins" = @(
        @{Name="Microsoft 3D Viewer"; Key="ms-3dviewer"; Default=$true; Win10=$true; Win11=$true}
        @{Name="Mixed Reality Portal"; Key="ms-mixedreality"; Default=$true; Win10=$true; Win11=$true}
        @{Name="Print 3D"; Key="win-print3d"; Default=$true; Win10=$true; Win11=$true}
        @{Name="Your Phone"; Key="win-yourphone"; Default=$true; Win10=$true; Win11=$true}
        @{Name="Windows Camera"; Key="win-camera"; Default=$true; Win10=$true; Win11=$true}
        @{Name="Mail and Calendar"; Key="win-mail"; Default=$true; Win10=$true; Win11=$true}
        @{Name="Windows Sound Recorder"; Key="win-soundrec"; Default=$true; Win10=$true; Win11=$true}
        @{Name="Microsoft Wallet"; Key="ms-wallet"; Default=$true; Win10=$true; Win11=$true}
        @{Name="Messaging"; Key="ms-messaging"; Default=$true; Win10=$true; Win11=$true}
        @{Name="OneConnect"; Key="ms-oneconnect"; Default=$true; Win10=$true; Win11=$true}
        @{Name="ClipChamp"; Key="ms-clipchamp"; Default=$true; Win10=$false; Win11=$true}
    )
    "Entertainment & Media" = @(
        @{Name="Xbox Apps"; Key="xbox-apps"; Default=$true; Win10=$true; Win11=$true}
        @{Name="Groove Music"; Key="zune-music"; Default=$true; Win10=$true; Win11=$true}
        @{Name="Movies & TV"; Key="zune-video"; Default=$true; Win10=$true; Win11=$true}
        @{Name="Solitaire Collection"; Key="solitaire"; Default=$true; Win10=$true; Win11=$true}
    )
    "Third-Party Apps" = @(
        @{Name="Candy Crush Games"; Key="candy-crush"; Default=$true; Win10=$true; Win11=$true}
        @{Name="Facebook"; Key="facebook"; Default=$true; Win10=$true; Win11=$true}
        @{Name="Netflix"; Key="netflix"; Default=$true; Win10=$true; Win11=$true}
        @{Name="Disney+"; Key="disney"; Default=$true; Win10=$true; Win11=$true}
        @{Name="TikTok"; Key="tiktok"; Default=$true; Win10=$true; Win11=$true}
        @{Name="Spotify"; Key="spotify-store"; Default=$true; Win10=$true; Win11=$true}
        @{Name="Twitter"; Key="twitter"; Default=$true; Win10=$true; Win11=$true}
        @{Name="LinkedIn"; Key="linkedin"; Default=$true; Win10=$false; Win11=$true}
    )
}

# Services definitions
$script:Services = @{
    "Telemetry & Privacy" = @(
        @{Name="Connected User Experiences and Telemetry"; Key="diagtrack"; Default=$true; Win10=$true; Win11=$true}
        @{Name="WAP Push Message Routing"; Key="dmwappushsvc"; Default=$true; Win10=$true; Win11=$true}
        @{Name="Windows Insider Service"; Key="wisvc"; Default=$true; Win10=$true; Win11=$true}
    )
    "Performance & Storage" = @(
        @{Name="Superfetch/SysMain"; Key="sysmain"; Default=$true; Win10=$true; Win11=$true}
        @{Name="Windows Search"; Key="wsearch"; Default=$false; Win10=$true; Win11=$true}
        @{Name="Offline Files"; Key="cscservice"; Default=$true; Win10=$true; Win11=$true}
    )
    "Network & Media" = @(
        @{Name="Windows Media Player Network Sharing"; Key="wmpnetworksvc"; Default=$true; Win10=$true; Win11=$true}
        @{Name="Remote Registry"; Key="remoteregistry"; Default=$true; Win10=$true; Win11=$true}
        @{Name="Remote Access"; Key="remoteaccess"; Default=$true; Win10=$true; Win11=$true}
        @{Name="Fax Service"; Key="fax"; Default=$true; Win10=$true; Win11=$true}
    )
    "System & Interface" = @(
        @{Name="Program Compatibility Assistant"; Key="pcasvc"; Default=$true; Win10=$true; Win11=$true}
        @{Name="Parental Controls"; Key="wpcmonsvc"; Default=$true; Win10=$true; Win11=$true}
        @{Name="Downloaded Maps Manager"; Key="mapsbroker"; Default=$true; Win10=$true; Win11=$true}
        @{Name="Printer Extensions and Notifications"; Key="printnotify"; Default=$true; Win10=$true; Win11=$true}
        @{Name="Retail Demo Service"; Key="retaildemo"; Default=$true; Win10=$true; Win11=$true}
        @{Name="Geolocation Service"; Key="lfsvc"; Default=$true; Win10=$false; Win11=$true}
        @{Name="Touch Keyboard and Handwriting Panel"; Key="tabletinputservice"; Default=$true; Win10=$false; Win11=$true}
        @{Name="HomeGroup Provider"; Key="homegrpservice"; Default=$true; Win10=$false; Win11=$true}
        @{Name="Microsoft Wallet Service"; Key="walletservice"; Default=$true; Win10=$false; Win11=$true}
    )
}

# System tweaks definitions
$script:Tweaks = @{
    "File Explorer" = @(
        @{Name="Show file extensions"; Key="show-extensions"; Default=$true}
        @{Name="Show hidden files"; Key="show-hidden"; Default=$true}
        @{Name="Disable quick access"; Key="disable-quickaccess"; Default=$false}
    )
    "Privacy & Telemetry" = @(
        @{Name="Disable Cortana"; Key="disable-cortana"; Default=$true}
        @{Name="Disable OneDrive auto-start"; Key="disable-onedrive"; Default=$true}
        @{Name="Reduce telemetry"; Key="reduce-telemetry"; Default=$true}
        @{Name="Disable activity history"; Key="disable-activity"; Default=$true}
        @{Name="Disable web search in Start Menu"; Key="search-bing"; Default=$true}
        @{Name="Disable background apps"; Key="disable-background"; Default=$true}
    )
    "Interface" = @(
        @{Name="Dark theme"; Key="dark-theme"; Default=$false}
        @{Name="Classic right-click menu"; Key="classic-context"; Default=$true}
        @{Name="Taskbar left alignment"; Key="taskbar-left"; Default=$true}
        @{Name="Disable widgets"; Key="disable-widgets"; Default=$true}
        @{Name="Disable Chat icon on taskbar"; Key="disable-chat"; Default=$true}
        @{Name="Disable Snap layouts"; Key="disable-snap"; Default=$false}
        @{Name="Disable tips and suggestions"; Key="disable-tips"; Default=$true}
        @{Name="Disable startup sound"; Key="disable-startup-sound"; Default=$true}
    )
    "System Performance" = @(
        @{Name="Enable developer mode"; Key="dev-mode"; Default=$false}
        @{Name="Disable Teams auto-start"; Key="disable-teams-autostart"; Default=$true}
        @{Name="Configure Start menu layout"; Key="start-menu-pins"; Default=$false}
    )
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
$osLabel.Text = if ($script:IsWindows11) { "Windows 11" } else { "Windows 10" }
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

# Log area at very bottom
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

function Get-WingetId {
    param($AppKey)
    
    $wingetIds = @{
        "chrome" = "Google.Chrome"
        "firefox" = "Mozilla.Firefox" 
        "brave" = "Brave.Brave"
        "vscode" = "Microsoft.VisualStudioCode"
        "git" = "Git.Git"
        "python" = "Python.Python.3.12"
        "pycharm" = "JetBrains.PyCharm.Community"
        "github" = "GitHub.GitHubDesktop"
        "postman" = "Postman.Postman"
        "nodejs" = "OpenJS.NodeJS"
        "terminal" = "Microsoft.WindowsTerminal"
        "spotify" = "Spotify.Spotify"
        "discord" = "Discord.Discord"
        "steam" = "Valve.Steam"
        "vlc" = "VideoLAN.VLC"
        "7zip" = "7zip.7zip"
        "notepad" = "Notepad++.Notepad++"
        "powertoys" = "Microsoft.PowerToys"
    }
    
    return $wingetIds[$AppKey]
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

# Show initial content (Apps tab)
Show-TabContent -Categories $script:Apps -Title "Select Applications to Install"

# Event handlers
$runBtn.Add_Click({
    try {
        $runBtn.Enabled = $false
        $cancelBtn.Text = "Cancel"
        $logBox.Text = ""
        
        Update-StatusMessage "Starting Windows Setup Operations..."
        
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
            Update-StatusMessage "No items selected. Please select items to process."
            return
        }
        
        Update-StatusMessage "$operationType - Processing $($selectedItems.Count) items..."
        
        # Process based on operation type
        switch ($selectedTab.Text) {
            "Apps" {
                # Ensure winget is available (important for all Windows versions)
                Update-StatusMessage "Checking winget availability..."
                try {
                    $wingetVersion = winget --version 2>$null
                    if (-not $wingetVersion) {
                        Update-StatusMessage "Winget not found - attempting to register..."
                        try {
                            # Check Windows version compatibility (Windows 10 1709+ required)
                            $osVersion = [System.Environment]::OSVersion.Version
                            $buildNumber = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion").CurrentBuild
                            
                            if ([int]$buildNumber -lt 16299) {
                                Update-StatusMessage "⚠ Windows version too old for winget (requires build 16299+) - using direct downloads"
                            } else {
                                Update-StatusMessage "Registering winget via App Installer..."
                                
                                # Use the proper registration method for winget
                                Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe
                                
                                # Wait a moment for registration to complete
                                Start-Sleep -Seconds 5
                                
                                # Verify installation
                                $wingetVersion = winget --version 2>$null
                                if ($wingetVersion) {
                                    Update-StatusMessage "✓ Winget successfully registered: $wingetVersion"
                                } else {
                                    Update-StatusMessage "⚠ Winget registration completed but command not yet available - using direct downloads"
                                    Update-StatusMessage "Note: You may need to restart PowerShell or log out/in for winget to be available"
                                }
                            }
                            
                        } catch {
                            Update-StatusMessage "⚠ Failed to register winget automatically - using direct downloads"
                            Write-LogMessage -Message "Winget registration failed: $_" -Level "WARNING"
                            Update-StatusMessage "Tip: Try running manually: Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe"
                        }
                    } else {
                        Update-StatusMessage "✓ Winget available: $wingetVersion"
                    }
                } catch {
                    Update-StatusMessage "⚠ Winget check failed - using direct downloads"
                }
                
                foreach ($appKey in $selectedItems) {
                    Update-StatusMessage "Installing $appKey..."
                    try {
                        # Provide winget IDs for prioritized installation
                        $wingetId = Get-WingetId -AppKey $appKey
                        if ($wingetId) {
                            Install-Application -AppName $appKey -WingetId $wingetId
                        } else {
                            Install-Application -AppName $appKey
                        }
                        Update-StatusMessage "✓ Successfully installed $appKey"
                    } catch {
                        Update-StatusMessage "✗ Failed to install $appKey`: $_"
                        Write-LogMessage -Message "Failed to install $appKey`: $_" -Level "ERROR"
                    }
                }
            }
            "Bloatware" {
                foreach ($bloatKey in $selectedItems) {
                    Update-StatusMessage "Removing bloatware $bloatKey..."
                    try {
                        Remove-Bloatware -BloatwareKey $bloatKey
                        Update-StatusMessage "✓ Successfully removed $bloatKey"
                    } catch {
                        Update-StatusMessage "✗ Failed to remove $bloatKey`: $_"
                        Write-LogMessage -Message "Failed to remove bloatware $bloatKey`: $_" -Level "ERROR"
                    }
                }
            }
            "Services" {
                foreach ($serviceKey in $selectedItems) {
                    Update-StatusMessage "Disabling service $serviceKey..."
                    try {
                        Set-SystemOptimization -OptimizationKey $serviceKey
                        Update-StatusMessage "✓ Successfully disabled $serviceKey"
                    } catch {
                        Update-StatusMessage "✗ Failed to disable $serviceKey`: $_"
                        Write-LogMessage -Message "Failed to disable service $serviceKey`: $_" -Level "ERROR"
                    }
                }
            }
            "Tweaks" {
                foreach ($tweakKey in $selectedItems) {
                    Update-StatusMessage "Applying tweak $tweakKey..."
                    try {
                        Set-SystemOptimization -OptimizationKey $tweakKey
                        Update-StatusMessage "✓ Successfully applied $tweakKey"
                    } catch {
                        Update-StatusMessage "✗ Failed to apply $tweakKey`: $_"
                        Write-LogMessage -Message "Failed to apply tweak $tweakKey`: $_" -Level "ERROR"
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

# Initialize logging
Initialize-Logging

Write-Host "Launching Windows Setup GUI..." -ForegroundColor Green
Write-Host "4 tabs: Install Apps, Remove Bloatware, Disable Services, System Tweaks" -ForegroundColor Yellow

# Show form
[void]$form.ShowDialog()