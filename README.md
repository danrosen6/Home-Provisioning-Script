# Windows Setup GUI - Enhanced Edition

A comprehensive Windows provisioning script with **GUI interface**, featuring dynamic software installation, user profiles, and intelligent system resource management.

## 🚀 Quick Start

1. **Run as Administrator** (required for system modifications)
2. **Launch**: `.\src\Windows-Setup-GUI.ps1`
3. **Select Applications**: Choose from 30+ applications across 4 categories using **checkboxes**
4. **Pick Installation Method**:
   - **Run Selected Operations**: Process all selected items sequentially
   - **Quick Setup**: Automatically select and install defaults
5. **Save Your Configuration**: Use profiles for future setups

## ✨ Key Features

### 🎯 GUI Interface with Checkboxes
- **Tabbed Interface**: Separate tabs for Apps, Bloatware, Services, and Tweaks
- **Checkbox Selection**: Easy point-and-click selection with "Select All" options
- **Category Organization**: Items grouped by logical categories
- **Windows Version Filtering**: Only shows compatible items for your OS version
- **Visual Progress**: Progress bar and status updates during operations

### 🛠️ Smart Installation
- **Winget Integration**: Uses Windows Package Manager when available, falls back to direct downloads
- **Dynamic URLs**: Always installs the latest software versions automatically
- **Robust Error Handling**: Graceful fallbacks ensure installations succeed
- **Compatibility Detection**: Automatically detects Windows version and winget support

### 👤 User Profiles
- **Save Configurations**: Save your preferred selections as reusable profiles
- **Default Profiles**: Pre-built profiles for common scenarios
- **Quick Loading**: One-click profile application
- **Profile Management**: Easy profile creation and management

### 🛡️ System Safety
- **Administrator Checks**: Ensures proper permissions before making changes
- **Comprehensive Logging**: Full operation tracking for troubleshooting
- **Error Recovery**: Graceful handling of failed operations
- **User Confirmations**: Clear feedback and progress indication

## 📦 What Gets Managed

### Applications (30+)
- **Development**: VS Code, Git, Python, Node.js, Docker, WSL
- **Browsers**: Chrome, Firefox, Brave
- **Media**: Spotify, Discord, VLC, Steam
- **Utilities**: 7-Zip, Notepad++, PowerToys, Windows Terminal

### Bloatware Removal (40+)
- **Microsoft Bloat**: Office Hub, Teams, Copilot, Xbox apps
- **Third-party Apps**: Candy Crush, Facebook, Netflix, TikTok
- **Built-in Apps**: 3D Viewer, Paint 3D, Mixed Reality Portal

### System Optimizations
- **Services**: Disable telemetry, Superfetch, unnecessary services
- **Tweaks**: Show file extensions, disable Cortana, optimize taskbar
- **Privacy**: Reduce data collection, disable advertising ID

## 🏗️ Project Structure

```
src/
├── modules/          # Core functionality modules
│   ├── Installers.psm1         # Application installation logic
│   └── SystemOptimizations.psm1 # System tweaks and service management
├── utils/            # Utility functions  
│   ├── ConfigLoader.psm1       # Configuration file loader
│   ├── JsonUtils.psm1          # JSON handling utilities
│   ├── Logging.psm1            # Logging system
│   ├── ProfileManager.psm1     # User profile management
│   └── WingetUtils.psm1        # Winget integration utilities
├── config/           # JSON configuration files
│   ├── apps.json               # Application definitions with dynamic URLs
│   ├── bloatware.json          # Bloatware removal definitions
│   ├── services.json           # Service management definitions
│   └── tweaks.json             # System tweak definitions
└── Windows-Setup-GUI.ps1       # Main GUI application
```

## 🔧 Advanced Usage

### Configuration Files
All applications, bloatware, services, and tweaks are defined in JSON files located in the `config/` directory. You can easily add or modify items by editing these files.

### Adding Custom Applications
Edit `config/apps.json` to add new applications:

```json
{
  "Name": "My Custom App",
  "Key": "my-custom-app",
  "WingetId": "Publisher.AppName",
  "Default": false,
  "Win10": true,
  "Win11": true,
  "DirectDownload": {
    "Url": "https://example.com/download",
    "UrlType": "direct",
    "Arguments": "/silent"
  }
}
```

### Profile Management
The GUI includes basic profile functionality. Advanced profile management can be accessed through the ProfileManager module functions.

## ❓ FAQ

### Does winget installation require a restart?
**No!** Winget installation is a user-space operation that never requires a system restart. If winget isn't immediately available after installation, simply start a new PowerShell session.

## 🔧 Winget Installation Process - Technical Details

### What is Winget?
Windows Package Manager (winget) is Microsoft's official command-line package manager for Windows 10 and Windows 11. It enables automated software installation, updates, and management directly from the command line or PowerShell.

### Compatibility Requirements
- **Windows 10**: Version 1709 (Build 16299) or later
- **Windows 11**: All versions natively supported
- **PowerShell**: 5.1 or later (included with Windows)
- **Internet Connection**: Required for downloads and package manifest updates

### Installation Process Overview
The script uses a multi-stage approach to ensure winget is available:

#### Stage 1: Detection
```powershell
# Check if winget command is available
Get-Command winget -ErrorAction SilentlyContinue

# Verify Windows compatibility
$buildNumber = [System.Environment]::OSVersion.Version.Build
$isCompatible = $buildNumber -ge 16299
```

#### Stage 2: Installation Methods (Automatic Fallback Chain)

**Method 1: Microsoft Store (Preferred)**
- Downloads latest App Installer package (.msixbundle)
- Source: `https://aka.ms/getwinget`
- Includes all dependencies automatically
- **No restart required**

**Method 2: GitHub Releases (Fallback)**
- Downloads winget from official Microsoft repository
- Includes Microsoft.VCLibs and Microsoft.UI.Xaml dependencies
- Self-contained installation package
- **No restart required**

**Method 3: PowerShell Gallery (Alternative)**
- Uses PowerShell package management
- Installs winget module if available
- **No restart required**

#### Stage 3: Dependency Management
Winget requires these runtime dependencies (automatically installed):

1. **Microsoft.VCLibs.140.00.UWPDesktop**
   - Visual C++ Redistributable for UWP apps
   - Required for winget's core functionality

2. **Microsoft.UI.Xaml.2.7** (or later)
   - UI framework for modern Windows apps
   - Required for winget's interface components

3. **Microsoft.DesktopAppInstaller**
   - The main winget application package
   - Contains the actual winget.exe executable

#### Stage 4: Registration & Verification
```powershell
# Register with Windows (if needed)
Add-AppxPackage -RegisterByFamilyName "Microsoft.DesktopAppInstaller_8wekyb3d8bbwe"

# Verify installation
winget --version
```

### Why No Restart is Required

**User-Space Installation**: Winget installs as a UWP (Universal Windows Platform) app in user space, not as a system service or driver.

**PATH Registration**: The winget executable is automatically registered in the Windows app execution alias system, making it available in new PowerShell sessions without modifying system PATH.

**Immediate Availability**: Once installed, winget is immediately available in:
- New PowerShell windows
- New Command Prompt windows
- Current session (after refresh)

### Installation Flow in This Script

1. **Compatibility Check**: Verify Windows version supports winget
2. **Existence Check**: Look for existing winget installation
3. **Download & Install**: Use the most reliable method available
4. **Dependency Resolution**: Ensure all required components are present
5. **Verification**: Test winget functionality
6. **Graceful Fallback**: If winget fails, use direct downloads instead

### Troubleshooting Common Issues

**"Winget not found" after installation**: 
- Start a new PowerShell session
- The current session may not have the updated app aliases

**"App Installer not installed"**:
- Install from Microsoft Store manually
- Or let the script use GitHub releases method

**"This app can't run on your PC"**:
- Windows version too old (< Build 16299)
- Script automatically detects this and uses direct downloads

**Installation hangs or fails**:
- Network connectivity issues
- Windows Update needed (rare cases)
- Script automatically falls back to direct downloads

### Performance Benefits of Winget

- **Faster Downloads**: Parallel processing capabilities
- **Automatic Updates**: Can check for and install updates
- **Dependency Management**: Handles app dependencies automatically
- **Verification**: Built-in package verification and signatures
- **Cleanup**: Automatic cleanup of installation files

### Direct Download Fallback

When winget is unavailable, the script seamlessly falls back to:
- **Dynamic URLs**: Always gets latest software versions
- **GitHub API**: For open-source software releases
- **Official Sources**: Direct from software vendor websites
- **Verification**: Manual verification of installation success

### What if I want to customize the applications list?
Yes! Edit the JSON files in the `config/` directory to add, remove, or modify applications, bloatware, services, and tweaks.

### How do I save my selections for future use?
The GUI includes profile functionality (currently basic implementation). You can extend this by using the ProfileManager module functions directly.

## 🛠️ Requirements

- **Windows 10 1709+ or Windows 11** (for optimal winget support)
- **PowerShell 5.1+** (comes with Windows)
- **Administrator privileges** (for system modifications)
- **Internet connection** (for downloads and dynamic URL resolution)
- **.NET Framework** (for Windows Forms GUI - typically pre-installed)

## 🎉 What Makes This Special

✅ **Complete GUI Interface** - Point-and-click checkbox interface, no command line required  
✅ **Modular Architecture** - Clean separation of concerns with dedicated modules  
✅ **JSON Configuration** - Easy to maintain and customize without touching code  
✅ **Intelligent Winget Handling** - Automatic detection, installation, and fallback  
✅ **Windows Version Aware** - Only shows compatible options for your OS  
✅ **Comprehensive Logging** - Full operation tracking for troubleshooting  
✅ **Error Recovery** - Graceful handling of failures with clear user feedback  

---

**Ready to set up your Windows system?** Run `.\src\Windows-Setup-GUI.ps1` as Administrator and enjoy the clean, checkbox-based interface for configuring your Windows installation!

*This enhanced edition provides exactly what you need: a user-friendly GUI tool that makes Windows provisioning simple and reliable.*