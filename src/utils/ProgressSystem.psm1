# Progress System for Windows Setup GUI

# Global progress state
$script:ProgressState = @{
    CurrentStep = 0
    TotalSteps = 0
    CurrentOperation = ""
    IsRunning = $false
    StartTime = $null
    DetailedLog = @()
    ProgressBar = $null
    StatusLabel = $null
    DetailsButton = $null
    DetailsPanel = $null
    DetailsTextBox = $null
    ParentForm = $null
    ShowDetails = $false
}

function Initialize-ProgressSystem {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [System.Windows.Forms.Control]$ParentContainer,
        
        [Parameter(Mandatory=$false)]
        [System.Drawing.Point]$Location = [System.Drawing.Point]::new(20, 140),
        
        [Parameter(Mandatory=$false)]
        [System.Drawing.Size]$Size = [System.Drawing.Size]::new(840, 60),
        
        [Parameter(Mandatory=$false)]
        [switch]$EnableDetails
    )
    
    try {
        # Create main progress panel
        $progressPanel = New-Object System.Windows.Forms.Panel
        $progressPanel.Location = $Location
        $progressPanel.Size = $Size
        $progressPanel.BackColor = [System.Drawing.Color]::FromArgb(250, 250, 250)
        $progressPanel.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
        
        # Create progress bar
        $script:ProgressState.ProgressBar = New-Object System.Windows.Forms.ProgressBar
        $script:ProgressState.ProgressBar.Location = New-Object System.Drawing.Point(10, 10)
        $script:ProgressState.ProgressBar.Size = New-Object System.Drawing.Size(640, 20)
        $script:ProgressState.ProgressBar.Style = [System.Windows.Forms.ProgressBarStyle]::Continuous
        $script:ProgressState.ProgressBar.Minimum = 0
        $script:ProgressState.ProgressBar.Maximum = 100
        $progressPanel.Controls.Add($script:ProgressState.ProgressBar)
        
        # Create status label
        $script:ProgressState.StatusLabel = New-Object System.Windows.Forms.Label
        $script:ProgressState.StatusLabel.Location = New-Object System.Drawing.Point(10, 35)
        $script:ProgressState.StatusLabel.Size = New-Object System.Drawing.Size(640, 20)
        $script:ProgressState.StatusLabel.Text = "Ready"
        $script:ProgressState.StatusLabel.Font = New-Object System.Drawing.Font("Segoe UI", 9)
        $progressPanel.Controls.Add($script:ProgressState.StatusLabel)
        
        if ($EnableDetails) {
            # Create details toggle button
            $script:ProgressState.DetailsButton = New-Object System.Windows.Forms.Button
            $script:ProgressState.DetailsButton.Location = New-Object System.Drawing.Point(660, 10)
            $script:ProgressState.DetailsButton.Size = New-Object System.Drawing.Size(70, 45)
            $script:ProgressState.DetailsButton.Text = "Details"
            $script:ProgressState.DetailsButton.Font = New-Object System.Drawing.Font("Segoe UI", 8)
            $script:ProgressState.DetailsButton.Add_Click({
                Toggle-ProgressDetails
            })
            $progressPanel.Controls.Add($script:ProgressState.DetailsButton)
            
            # Create expandable details panel (initially hidden)
            $script:ProgressState.DetailsPanel = New-Object System.Windows.Forms.Panel
            $script:ProgressState.DetailsPanel.Location = New-Object System.Drawing.Point($Location.X, $Location.Y + $Size.Height + 5)
            $script:ProgressState.DetailsPanel.Size = New-Object System.Drawing.Size($Size.Width, 150)
            $script:ProgressState.DetailsPanel.BackColor = [System.Drawing.Color]::FromArgb(240, 240, 240)
            $script:ProgressState.DetailsPanel.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
            $script:ProgressState.DetailsPanel.Visible = $false
            
            # Create details text box
            $script:ProgressState.DetailsTextBox = New-Object System.Windows.Forms.TextBox
            $script:ProgressState.DetailsTextBox.Location = New-Object System.Drawing.Point(5, 5)
            $script:ProgressState.DetailsTextBox.Size = New-Object System.Drawing.Size($Size.Width - 10, 140)
            $script:ProgressState.DetailsTextBox.Multiline = $true
            $script:ProgressState.DetailsTextBox.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
            $script:ProgressState.DetailsTextBox.ReadOnly = $true
            $script:ProgressState.DetailsTextBox.BackColor = [System.Drawing.Color]::White
            $script:ProgressState.DetailsTextBox.Font = New-Object System.Drawing.Font("Consolas", 8)
            $script:ProgressState.DetailsPanel.Controls.Add($script:ProgressState.DetailsTextBox)
            
            $ParentContainer.Controls.Add($script:ProgressState.DetailsPanel)
        }
        
        $ParentContainer.Controls.Add($progressPanel)
        $script:ProgressState.ParentForm = $ParentContainer
        
        return $progressPanel
    }
    catch {
        Write-Error "Failed to initialize progress system: $_"
        return $null
    }
}

function Start-ProgressOperation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [int]$TotalSteps,
        
        [Parameter(Mandatory=$false)]
        [string]$OperationName = "Processing"
    )
    
    if (-not $script:ProgressState.ProgressBar) {
        Write-Warning "Progress system not initialized"
        return
    }
    
    $script:ProgressState.CurrentStep = 0
    $script:ProgressState.TotalSteps = $TotalSteps
    $script:ProgressState.CurrentOperation = $OperationName
    $script:ProgressState.IsRunning = $true
    $script:ProgressState.StartTime = Get-Date
    $script:ProgressState.DetailedLog = @()
    
    # Reset progress bar
    $script:ProgressState.ProgressBar.Value = 0
    $script:ProgressState.ProgressBar.Style = [System.Windows.Forms.ProgressBarStyle]::Continuous
    
    # Update status
    Update-ProgressStatus -Message "Starting $OperationName..." -Step 0
    
    Write-Verbose "Started progress operation: $OperationName ($TotalSteps steps)"
}

function Update-ProgressStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,
        
        [Parameter(Mandatory=$false)]
        [int]$Step = -1,
        
        [Parameter(Mandatory=$false)]
        [ValidateSet("INFO", "SUCCESS", "WARNING", "ERROR")]
        [string]$Level = "INFO"
    )
    
    if (-not $script:ProgressState.ProgressBar) {
        Write-Host $Message
        return
    }
    
    try {
        # Update step if provided
        if ($Step -ge 0) {
            $script:ProgressState.CurrentStep = $Step
        } else {
            $script:ProgressState.CurrentStep++
        }
        
        # Calculate progress percentage
        if ($script:ProgressState.TotalSteps -gt 0) {
            $percentage = [Math]::Min(100, [Math]::Round(($script:ProgressState.CurrentStep / $script:ProgressState.TotalSteps) * 100))
            $script:ProgressState.ProgressBar.Value = $percentage
        }
        
        # Add timestamp to message
        $timestamp = Get-Date -Format "HH:mm:ss"
        $formattedMessage = "[$timestamp] $Message"
        
        # Update status label with truncation if needed
        $displayMessage = if ($Message.Length -gt 80) { $Message.Substring(0, 77) + "..." } else { $Message }
        $script:ProgressState.StatusLabel.Text = "$displayMessage ($($script:ProgressState.CurrentStep)/$($script:ProgressState.TotalSteps))"
        
        # Add to detailed log
        $logEntry = @{
            Timestamp = $timestamp
            Message = $Message
            Level = $Level
            Step = $script:ProgressState.CurrentStep
        }
        $script:ProgressState.DetailedLog += $logEntry
        
        # Update details text box if visible
        if ($script:ProgressState.DetailsTextBox -and $script:ProgressState.ShowDetails) {
            $colorPrefix = switch ($Level) {
                "SUCCESS" { "[✓] " }
                "WARNING" { "[!] " }
                "ERROR" { "[✗] " }
                default { "[·] " }
            }
            
            $detailLine = "$colorPrefix$formattedMessage"
            $script:ProgressState.DetailsTextBox.Text += "$detailLine`r`n"
            $script:ProgressState.DetailsTextBox.SelectionStart = $script:ProgressState.DetailsTextBox.Text.Length
            $script:ProgressState.DetailsTextBox.ScrollToCaret()
        }
        
        # Force UI update
        [System.Windows.Forms.Application]::DoEvents()
        
        # Also log to file if logging system is available
        if (Get-Command Write-LogMessage -ErrorAction SilentlyContinue) {
            Write-LogMessage -Message $Message -Level $Level
        }
    }
    catch {
        Write-Warning "Error updating progress status: $_"
    }
}

function Complete-ProgressOperation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [string]$FinalMessage = "Operation completed",
        
        [Parameter(Mandatory=$false)]
        [ValidateSet("SUCCESS", "WARNING", "ERROR")]
        [string]$CompletionStatus = "SUCCESS"
    )
    
    if (-not $script:ProgressState.ProgressBar) {
        Write-Host $FinalMessage
        return
    }
    
    # Set progress to 100%
    $script:ProgressState.ProgressBar.Value = 100
    $script:ProgressState.CurrentStep = $script:ProgressState.TotalSteps
    
    # Calculate elapsed time
    $elapsed = if ($script:ProgressState.StartTime) {
        $timeSpan = (Get-Date) - $script:ProgressState.StartTime
        " (Elapsed: $($timeSpan.ToString('mm\:ss')))"
    } else { "" }
    
    # Update final status
    Update-ProgressStatus -Message "$FinalMessage$elapsed" -Level $CompletionStatus
    
    $script:ProgressState.IsRunning = $false
    
    Write-Verbose "Completed progress operation: $FinalMessage"
}

function Set-ProgressIndeterminate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message
    )
    
    if ($script:ProgressState.ProgressBar) {
        $script:ProgressState.ProgressBar.Style = [System.Windows.Forms.ProgressBarStyle]::Marquee
        $script:ProgressState.StatusLabel.Text = $Message
        [System.Windows.Forms.Application]::DoEvents()
    }
}

function Set-ProgressDeterminate {
    [CmdletBinding()]
    param()
    
    if ($script:ProgressState.ProgressBar) {
        $script:ProgressState.ProgressBar.Style = [System.Windows.Forms.ProgressBarStyle]::Continuous
        [System.Windows.Forms.Application]::DoEvents()
    }
}

function Toggle-ProgressDetails {
    [CmdletBinding()]
    param()
    
    if (-not $script:ProgressState.DetailsPanel) {
        return
    }
    
    $script:ProgressState.ShowDetails = -not $script:ProgressState.ShowDetails
    $script:ProgressState.DetailsPanel.Visible = $script:ProgressState.ShowDetails
    
    # Update button text
    if ($script:ProgressState.DetailsButton) {
        $script:ProgressState.DetailsButton.Text = if ($script:ProgressState.ShowDetails) { "Hide" } else { "Details" }
    }
    
    # If showing details, populate with current log
    if ($script:ProgressState.ShowDetails -and $script:ProgressState.DetailsTextBox) {
        $script:ProgressState.DetailsTextBox.Text = ""
        foreach ($entry in $script:ProgressState.DetailedLog) {
            $colorPrefix = switch ($entry.Level) {
                "SUCCESS" { "[✓] " }
                "WARNING" { "[!] " }
                "ERROR" { "[✗] " }
                default { "[·] " }
            }
            $detailLine = "$colorPrefix[$($entry.Timestamp)] $($entry.Message)"
            $script:ProgressState.DetailsTextBox.Text += "$detailLine`r`n"
        }
        $script:ProgressState.DetailsTextBox.SelectionStart = $script:ProgressState.DetailsTextBox.Text.Length
        $script:ProgressState.DetailsTextBox.ScrollToCaret()
    }
}

function Get-ProgressState {
    [CmdletBinding()]
    param()
    
    return $script:ProgressState.Clone()
}

function Reset-ProgressSystem {
    [CmdletBinding()]
    param()
    
    if ($script:ProgressState.ProgressBar) {
        $script:ProgressState.ProgressBar.Value = 0
        $script:ProgressState.ProgressBar.Style = [System.Windows.Forms.ProgressBarStyle]::Continuous
    }
    
    if ($script:ProgressState.StatusLabel) {
        $script:ProgressState.StatusLabel.Text = "Ready"
    }
    
    if ($script:ProgressState.DetailsTextBox) {
        $script:ProgressState.DetailsTextBox.Text = ""
    }
    
    $script:ProgressState.CurrentStep = 0
    $script:ProgressState.TotalSteps = 0
    $script:ProgressState.CurrentOperation = ""
    $script:ProgressState.IsRunning = $false
    $script:ProgressState.DetailedLog = @()
    $script:ProgressState.StartTime = $null
}

Export-ModuleMember -Function @(
    "Initialize-ProgressSystem",
    "Start-ProgressOperation",
    "Update-ProgressStatus", 
    "Complete-ProgressOperation",
    "Set-ProgressIndeterminate",
    "Set-ProgressDeterminate",
    "Toggle-ProgressDetails",
    "Get-ProgressState",
    "Reset-ProgressSystem"
)