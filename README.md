# Windows 10 Post-Reset Setup Script

A comprehensive PowerShell script to automate the setup of a fresh Windows 10 installation. Installs essential and preferred software, removes bloatware, and optimizes Windows settings for performance and privacy.

## Compatibility

- **Designed for:** Windows 10 64-bit
- **Partial support:** Windows 10 32-bit (some limitations with 64-bit specific applications)
- **Not recommended for:** Windows 11 (many optimizations are Windows 10 specific)

## Prerequisites

- Windows 10 (preferably 64-bit)
- PowerShell 5.1 or higher
- Administrator privileges
- Internet connection

## Usage

1. Download the script to your computer
2. Right-click on PowerShell and select "Run as administrator"
3. Navigate to the script location
4. Run the script with:

```powershell
PowerShell -ExecutionPolicy Bypass .\windows10-setup.ps1
```

## Features

### Package Manager

- Installs [Chocolatey](https://chocolatey.org/) - A powerful package manager for Windows

### Applications Installed

The script installs the following applications (selectable during execution):

| Application | Purpose | Default |
|-------------|---------|---------|
| Google Chrome | Web browser | ✓ |
| Spotify | Music streaming | ✓ |
| Discord | Communication platform | ✓ |
| Steam | Gaming platform | ✓ |
| Git | Version control | ✓ |
| Visual Studio Code | Code editor | ✓ |
| Python | Programming language | ✓ |
| PyCharm Community | Python IDE | ✓ |
| GitHub Desktop | Git GUI | ✓ |
| VMware Player | Virtualization | Optional |
| NVIDIA Drivers | GPU drivers | Optional |

### Windows Apps Removed (Bloatware)

The script removes the following pre-installed Windows applications:

- Microsoft.BingWeather
- Microsoft.GetHelp
- Microsoft.Getstarted
- Microsoft.Microsoft3DViewer
- Microsoft.MicrosoftOfficeHub
- Microsoft.MicrosoftSolitaireCollection
- Microsoft.MixedReality.Portal
- Microsoft.People
- Microsoft.Print3D
- Microsoft.SkypeApp
- Microsoft.Wallet
- Microsoft.WindowsAlarms
- Microsoft.WindowsCamera
- Microsoft.WindowsCommunicationsApps (Mail and Calendar)
- Microsoft.WindowsFeedbackHub
- Microsoft.WindowsMaps
- Microsoft.WindowsSoundRecorder
- Microsoft.YourPhone
- Microsoft.ZuneMusic
- Microsoft.ZuneVideo
- Microsoft.OneConnect
- Microsoft.BingNews
- Microsoft.Messaging
- Microsoft.Office.OneNote
- Various third-party apps (CandyCrush, Spotify store version, etc.)

### Windows Services Disabled

The script optionally disables these services for improved performance:

- DiagTrack (Connected User Experiences and Telemetry)
- dmwappushservice (WAP Push Message Routing Service)
- SysMain (Superfetch/Prefetch)
- WMPNetworkSvc (Windows Media Player Network Sharing)
- RemoteRegistry (Remote Registry)
- RemoteAccess (Routing and Remote Access)
- PrintNotify (Printer Extensions and Notifications)
- Fax (Fax service)
- wisvc (Windows Insider Service)
- RetailDemo (Retail Demo Service)
- MapsBroker (Downloaded Maps Manager)
- PcaSvc (Program Compatibility Assistant)
- WpcMonSvc (Parental Controls)
- CscService (Offline Files)

### Windows Optimizations

- Shows file extensions and hidden files
- Enables Developer Mode
- Disables Cortana
- Disables OneDrive startup
- Disables Windows tips and suggestions
- Reduces telemetry data collection
- Disables activity history
- Disables unnecessary background apps
- Optimizes taskbar (keeps search box but removes unnecessary elements)
- Configures search to prioritize local results over Bing

### Development Environment Setup

- Creates project folders structure
- Configures Git (optional)
- Installs VS Code extensions for Python development
- Configures Python with proper PATH setup

## Logging

The script creates detailed logs in the same directory:
- `setup-log-[timestamp].txt`

## Troubleshooting

- If an application fails to install, try running the script again
- For PATH-related issues, restart your computer after running the script
- If Python command isn't working, try using `py` instead
- Check the log file for detailed error information

## After Running

1. **Restart your computer** to ensure all changes take effect
2. Verify installations by opening applications
3. Configure additional application settings as needed

## Security Note

This script changes your execution policy temporarily to run. It's recommended to review the script content before running.

## Customization

You can modify the script to:
- Add or remove applications
- Change default selections
- Adjust Windows optimizations
- Add additional development tools

## License

Feel free to use, modify and distribute as needed.

## Potential Feature Loss

This script removes several built-in Windows features in favor of performance, privacy, and third-party alternatives. Be aware of these potential consequences:

### Notable App Removals:
- **Mail and Calendar apps** - You'll need alternative email/calendar applications
- **Your Phone** - Loses phone-to-PC integration features for Android/iPhone
- **Windows Camera** - Requires third-party camera applications instead
- **Maps** - Removes offline maps capability
- **Microsoft Office Hub** - Removes Office app promotions (not Office itself)
- **Media apps** - Removes Movies & TV and Groove Music (alternatives like VLC recommended)

### Service Disabling Consequences:
- **SysMain (Superfetch)** - May slightly reduce application launch speed on mechanical HDDs (minimal impact on SSDs)
- **Parental Controls** - Removes built-in family safety features
- **Offline Files** - Disables ability to work with network files when disconnected
- **Telemetry/Diagnostics** - May reduce Microsoft's ability to assist with certain troubleshooting
- **Program Compatibility** - May impact compatibility suggestions for older software

### Settings Changes:
- **Cortana disabled** - Removes voice assistant functionality
- **OneDrive startup disabled** - Must be manually started if needed
- **Background apps disabled** - Some apps may not update until manually opened
- **Activity history disabled** - Removes timeline features and certain cross-device experiences

Most users find these tradeoffs worthwhile for the improved performance, privacy, and cleaner system. All changes can be reversed manually if needed.# Windows 10 Post-Reset Setup Script

A comprehensive PowerShell script to automate the setup of a fresh Windows 10 installation. Installs essential software, removes bloatware, and optimizes Windows settings for performance and privacy.