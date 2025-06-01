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
| VMware Player | Virtualization | Optional |
| NVIDIA Drivers | GPU drivers | Optional |

**Windows 11 script adds:**
- Windows Terminal (modern terminal experience)
- Microsoft PowerToys (productivity toolkit)

## 🧹 Bloatware Removal

The scripts remove various pre-installed applications, including:

- Microsoft Office Hub
- Bing apps (Weather, News)
- Xbox apps (on Windows 11)
- Microsoft Teams (consumer version, on Windows 11)
- Casual games (Solitaire, Candy Crush)
- Mixed Reality Portal
- Various utility apps (3D Viewer, Your Phone, etc.)
- Store versions of apps we install desktop versions of (Spotify, etc.)

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
- Create project folders structure
- Configure Git (optional)
- Install VS Code extensions for Python development
- Configure Python with proper PATH setup

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