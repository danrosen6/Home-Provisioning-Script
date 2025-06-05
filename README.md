# Windows Post-Reset Setup Scripts

A collection of PowerShell scripts to automate the setup of fresh Windows installations. These scripts install essential software, remove bloatware, and optimize Windows settings for performance, privacy, and usability.

This repository contains two scripts:
- `windows10-setup.ps1` - For Windows 10 systems
- `windows11-setup.ps1` - For Windows 11 systems

## 🚀 Features

Both scripts provide:

- **Software Installation**: Automatically install popular and essential applications
- **Bloatware Removal**: Remove pre-installed, unnecessary Windows applications
- **System Optimization**: Configure Windows for better performance and privacy
- **Development Environment Setup**: Prepare your system for software development
- **Reliable Installation Methods**: Multiple fallback options for application installation

## 🔍 Choosing the Right Script

| Feature | Windows 10 Script | Windows 11 Script |
|---------|-------------------|-------------------|
| **Target OS** | Windows 10 (all versions) | Windows 11 (all versions) |
| **Check OS Compatibility** | Basic | Enhanced (checks TPM and Secure Boot) |
| **UI Optimizations** | Windows 10 specific | Windows 11 specific (taskbar, context menu) |
| **Default Apps** | Core development tools + browsers | Adds Windows Terminal and PowerToys |
| **Bloatware Removal** | Windows 10 bloatware | Windows 11 bloatware (includes Teams, Widgets) |

## 📋 Prerequisites

- Administrative privileges
- Internet connection
- PowerShell 5.1 or higher

## 💻 Usage

1. Download the appropriate script for your Windows version
2. Right-click on PowerShell and select "Run as administrator"
3. Navigate to the script location
4. Run the script with:

```powershell
# For Windows 10
PowerShell -ExecutionPolicy Bypass .\windows10-setup.ps1

# For Windows 11
PowerShell -ExecutionPolicy Bypass .\windows11-setup.ps1
```

## 📦 Applications Installed

Both scripts can install the following applications (selectable during execution):

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
| Postman | API testing tool | ✓ |

**Windows 11 script adds:**
- Windows Terminal (modern terminal experience)
- Microsoft PowerToys (productivity toolkit)

## 🧠 Reliable Installation System

The scripts use a progressive installation approach to ensure reliable application setup:

1. **Standard Package Manager**: Try Chocolatey first
2. **Checksum Bypass**: If standard installation fails due to checksums, retry with `--ignore-checksums` flag
3. **Direct Download**: If package manager fails, download directly from official sources
4. **Multiple Verification Paths**: Check multiple common installation locations to verify success

This approach is particularly valuable for frequently updated applications like Spotify, Chrome, and Discord.

## 🧹 Bloatware Removal & Service Optimization

The scripts provide comprehensive removal of pre-installed Windows applications and disable unnecessary services to improve performance, privacy, and system resources.

### Applications Removed (Both Windows 10 & 11)

#### Microsoft Applications
- **Microsoft Office Hub** - Replaced by standalone Office installations when needed
- **Microsoft 3D Viewer** - Rarely used 3D model viewing application
- **Microsoft Mixed Reality Portal** - VR platform rarely used by most users
- **Microsoft OneNote (Store version)** - Prefer the full desktop version if needed
- **Microsoft People** - Contact management app with limited functionality
- **Microsoft Wallet** - Rarely used payment service
- **Microsoft Messaging** - Legacy messaging app superseded by Teams/other platforms
- **Microsoft OneConnect** - Mobile plans connector (irrelevant for most PCs)

#### Bing Applications
- **Bing Weather** - Weather app with unnecessary data collection
- **Bing News** - News aggregator with personalization tracking
- **Bing Finance** - Financial news/tracking app

#### Windows Utilities (Replaceable)
- **Windows Alarms & Clock** - Basic functionality available elsewhere
- **Windows Camera** - Basic camera app (useful only on devices with cameras)
- **Windows Mail & Calendar** - Basic email/calendar (better alternatives exist)
- **Windows Maps** - Map application rarely used on desktop PCs
- **Windows Feedback Hub** - Microsoft feedback collection tool
- **Windows Get Help** - Microsoft support tool
- **Windows Get Started** - Tutorial app for new users
- **Windows Sound Recorder** - Basic recording tool (better alternatives exist)
- **Windows Your Phone** - Phone connectivity app (useful only for Android users)
- **Print 3D** - 3D printing utility rarely used

#### Media Applications
- **Zune Music** (Groove Music) - Microsoft's music player
- **Zune Video** (Movies & TV) - Microsoft's video player
- **Solitaire Collection** - Microsoft's card games bundle
- **Xbox-related apps** - Gaming overlay, identity provider, speech-to-text

#### Third-Party Bloatware
- **Candy Crush games** - Pre-installed games
- **Spotify (Store version)** - Replaced with standalone desktop version
- **Facebook** - Pre-installed app
- **Twitter** - Pre-installed app
- **Netflix** - Pre-installed app
- **Disney+** - Pre-installed app
- **TikTok** - Pre-installed app
- **Other partner applications** - Various promotional pre-installs

### Windows 11 Specific Removals
- **Microsoft Teams (consumer)** - Personal chat app pre-installed on Windows 11
- **Microsoft Widgets** - News and information sidebar
- **Microsoft ClipChamp** - Video editor
- **Microsoft To-Do** - Task management app
- **Gaming App** - Xbox app center
- **LinkedIn** - Professional social network app

### Services Disabled (Performance Optimization)
The scripts can optionally disable these non-essential services:

- **Connected User Experiences and Telemetry (DiagTrack)** - Collects usage data for Microsoft
- **WAP Push Service** - Legacy mobile device messaging service
- **Superfetch/SysMain** - Preloading system (minimal benefit on modern SSDs)
- **Windows Media Player Network Sharing** - Network media sharing
- **Remote Registry** - Remote registry editing (security improvement)
- **Routing and Remote Access** - Network routing capabilities
- **Printer Extensions and Notifications** - Enhanced printer functionality
- **Fax Service** - Legacy fax capabilities
- **Windows Insider Service** - Preview builds management
- **Retail Demo Service** - Used only in store display units
- **Downloaded Maps Manager** - Offline maps functionality
- **Program Compatibility Assistant** - Legacy program compatibility
- **Parental Controls** - Family safety features
- **Offline Files** - Document synchronization for network files
- **Geolocation Service** (Windows 11) - Location tracking
- **Touch Keyboard and Handwriting** (Windows 11) - Tablet input features
- **HomeGroup Provider** (if present) - Legacy home network sharing
- **Wallet Service** (Windows 11) - Payment service

### Impact and Benefits
Removing these applications and services provides several advantages:

- **Reduced System Resource Usage**: Less RAM and CPU usage from background processes
- **Improved Privacy**: Fewer apps collecting telemetry and usage data
- **Cleaner Start Menu**: Less clutter in your application list
- **Faster Updates**: Fewer components to update during Windows Update
- **Disk Space Savings**: Up to several GB of storage reclaimed
- **Reduced Network Activity**: Less background communication with Microsoft servers
- **Better Performance**: Particularly noticeable on systems with limited resources

### Recovery Options
If you need any of these applications later:
- Most can be reinstalled from the Microsoft Store
- Disabled services can be re-enabled through Services management console
- System Restore points (if enabled) can revert wholesale changes

## ⚙️ Windows Optimizations

### Common Optimizations (Both Scripts):
- Show file extensions and hidden files
- Enable Developer Mode
- Disable Cortana
- Disable OneDrive startup
- Disable Windows tips and suggestions
- Reduce telemetry data collection
- Disable activity history
- Disable unnecessary background apps
- Configure search to prioritize local results over Bing

### Windows 11 Specific Optimizations:
- Set taskbar alignment to left (classic style)
- Restore classic right-click context menu
- Disable Chat icon on taskbar
- Disable Widgets icon and service
- Disable Snap layouts when hovering maximize button
- Configure Start Menu layout for more pins
- Disable Teams consumer auto-start
- Disable startup sound

## 🛠️ Development Environment Setup

Both scripts:
- Create project folders structure (Projects, Python, GitHub, APIs)
- Configure Git (optional)
- Install VS Code extensions for Python development
- Configure Python with proper PATH setup
- Set up dedicated APIs folder for API testing with Postman

## 📝 Logging

The scripts create detailed logs in the same directory:
- `setup-log-[timestamp].txt`

## ❓ Troubleshooting

- If an application fails to install, try running the script again
- For PATH-related issues, restart your computer after running the script
- If Python command isn't working, try using `py` instead
- Check the log file for detailed error information

## ⚠️ Potential Feature Loss

These scripts remove several built-in Windows features in favor of performance, privacy, and third-party alternatives. Notable changes:

- **Built-in Apps**: Mail/Calendar, Camera, Maps, Office Hub, Xbox integration
- **Services**: Superfetch (minimal impact on SSDs), Parental Controls, Offline Files
- **Features**: Cortana, OneDrive auto-start, background app updates, activity history/timeline

On Windows 11:
- **UI Features**: Centered taskbar, new context menu, Widgets, Teams integration, Snap layouts hover

Most users find these tradeoffs worthwhile for improved performance and privacy. All changes can be manually reversed if needed.

## 🔒 Security Note

These scripts change your execution policy temporarily to run. It's recommended to review the script content before running.

## 🛠️ Customization

You can modify the scripts to:
- Add or remove applications
- Change default selections
- Adjust Windows optimizations
- Add additional development tools

## 📄 License

These scripts are provided as-is, free to use, modify, and distribute.

## 🙏 Acknowledgments

Thanks to the Chocolatey team for their package manager that makes automated software installation possible.