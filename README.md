# Windows Setup Automation Script

A PowerShell-based GUI automation tool for setting up Windows 10/11 systems with applications, bloatware removal, service optimizations, and system tweaks.

## Overview

This script provides a graphical interface for automating common Windows setup tasks, including:
- Installing essential applications via winget or direct downloads
- Removing bloatware and unwanted Windows apps
- Disabling unnecessary services
- Applying privacy and performance tweaks

## Files Structure

- `Windows-Setup-GUI.ps1` - Main GUI application with tabs for different operations
- `modules/Installers.psm1` - Application installation and winget management
- `modules/SystemOptimizations.psm1` - System tweaks, service configuration, and bloatware removal
- `utils/Logging.psm1` - Centralized logging system with file rotation
- `utils/RecoveryUtils.psm1` - Recovery and operation state tracking

## How to Run

1. **Prerequisites**: Windows 10 1709+ or Windows 11, PowerShell 5.1+, Administrator privileges
2. **Run**: Right-click PowerShell → "Run as Administrator" → Navigate to src folder → Run `PowerShell -ExecutionPolicy Bypass .\Windows-Setup-GUI.ps1`
3. **Interface**: Use the tabs at bottom to switch between: Apps, Bloatware, Services, Tweaks
4. **Select items** in the main area using checkboxes
5. **Click "Run Selected Tasks"** to execute

## Applications Installed

### Development Tools
- **Visual Studio Code** - Code editor with extensions support
- **Git** - Version control system with Windows integration
- **Python 3.13** - Programming language with pip and PATH setup
- **PyCharm Community** - Python IDE by JetBrains
- **IntelliJ IDEA Community** - Java/Kotlin IDE
- **WebStorm** - JavaScript/TypeScript IDE
- **Android Studio** - Android development environment
- **GitHub Desktop** - Git GUI client
- **Postman** - API development and testing
- **Node.js** - JavaScript runtime (Windows 11 only)

### Browsers
- **Google Chrome** - Web browser
- **Mozilla Firefox** - Alternative web browser
- **Brave Browser** - Privacy-focused browser

### Media & Communication
- **Spotify** - Music streaming service
- **Discord** - Gaming and community chat
- **Steam** - Gaming platform
- **VLC Media Player** - Video/audio player

### Utilities
- **7-Zip** - File compression/extraction
- **Notepad++** - Advanced text editor
- **Microsoft PowerToys** - Windows utilities (Windows 11 only)
- **Windows Terminal** - Modern command-line interface

## Installation Methods

1. **Winget (Preferred)**: Fast, reliable package manager for Windows 10 1709+
2. **Direct Downloads**: Fallback method downloading from official sources
3. **Dynamic Version Detection**: Automatically retrieves latest versions for Git, Python, PyCharm, VLC, 7-Zip, Notepad++

## Bloatware Removed

### Microsoft Office & Productivity

**Microsoft Office Hub**
- ✅ Pros: Frees up storage space, reduces clutter, removes promotional content
- ⚠️ Cons: Can't quick-access Office trial/subscription info from Start menu

**Microsoft Teams (Consumer)**
- ✅ Pros: Prevents auto-start, reduces resource usage, improves boot time
- ⚠️ Cons: Need to manually install if you use Teams for personal communication

**OneNote (Store Version)**
- ✅ Pros: Removes redundant app (desktop version usually preferred), saves space
- ⚠️ Cons: Lose simplified touch-friendly interface, desktop version required separately

**Microsoft People**
- ✅ Pros: Stops contact syncing across services, improves privacy, reduces background activity
- ⚠️ Cons: No unified contact management, lose integration with Mail/Calendar apps

**Microsoft To-Do**
- ✅ Pros: Eliminates task sync, reduces Microsoft account dependencies
- ⚠️ Cons: Need alternative task management solution, lose Outlook integration

### Windows Built-ins

**Microsoft 3D Viewer**
- ✅ Pros: Frees storage, removes unused app for most users, faster system
- ⚠️ Cons: Can't view 3D models (.3mf, .obj files) without alternative software

**Mixed Reality Portal**
- ✅ Pros: Major storage savings (~500MB), removes VR overhead, improves performance
- ⚠️ Cons: Breaks Windows Mixed Reality headset functionality completely

**Print 3D**
- ✅ Pros: Removes niche app, saves storage, declutters Start menu
- ⚠️ Cons: Can't prepare models for 3D printing without third-party alternatives

**Your Phone**
- ✅ Pros: Stops phone data syncing, improves privacy, reduces background processes
- ⚠️ Cons: Lose convenient phone-PC integration, no SMS/call handling on PC

**Windows Camera**
- ✅ Pros: Removes basic camera app, forces better alternatives
- ⚠️ Cons: No built-in camera functionality, need third-party camera software

**Mail and Calendar**
- ✅ Pros: Stops Microsoft account syncing, improves privacy, removes notifications
- ⚠️ Cons: No built-in email client, need Outlook/Thunderbird or web-based alternatives

**Windows Sound Recorder**
- ✅ Pros: Minimal storage saving, removes basic recording app
- ⚠️ Cons: No quick audio recording capability, need third-party solutions

**Microsoft Wallet**
- ✅ Pros: Removes payment integration, improves privacy, reduces tracking
- ⚠️ Cons: Can't store payment cards in Windows, no NFC payment capabilities

**Messaging**
- ✅ Pros: Stops SMS sync attempts, improves privacy, reduces background activity
- ⚠️ Cons: No text messaging from PC (where supported)

**OneConnect**
- ✅ Pros: Removes carrier-specific features, improves privacy
- ⚠️ Cons: May lose some cellular data management features

**ClipChamp (Windows 11)**
- ✅ Pros: Removes Microsoft's video editor, saves significant storage
- ⚠️ Cons: No built-in video editing capability, need alternatives like DaVinci Resolve

**Bing Weather**
- ✅ Pros: Stops location tracking, removes Bing integration, improves privacy
- ⚠️ Cons: No quick weather access, need web browser or third-party apps

**Bing News**
- ✅ Pros: Removes news notifications, stops Bing tracking, improves focus
- ⚠️ Cons: No personalized news feed, need browser or dedicated news apps

**Bing Finance**
- ✅ Pros: Removes financial tracking, stops Bing data collection
- ⚠️ Cons: No quick stock/portfolio tracking, need web-based alternatives

**Windows Alarms & Clock**
- ✅ Pros: Forces better third-party alternatives, removes basic functionality
- ⚠️ Cons: No built-in alarm/timer/stopwatch functionality

**Windows Maps**
- ✅ Pros: Stops location tracking, removes Microsoft mapping data collection
- ⚠️ Cons: No offline maps, need Google Maps/other alternatives in browser

**Windows Feedback Hub**
- ✅ Pros: Stops telemetry feedback, reduces Microsoft data collection
- ⚠️ Cons: Can't easily report Windows bugs or suggest features to Microsoft

**Get Help & Get Started**
- ✅ Pros: Removes tutorial apps, declutters Start menu, saves storage
- ⚠️ Cons: New users lose built-in help system, need online documentation

**Microsoft Widgets (Windows 11)**
- ✅ Pros: Major privacy improvement, stops news/ads, reduces tracking, improves performance
- ⚠️ Cons: No quick weather/news/stocks access from taskbar

**Microsoft Copilot**
- ✅ Pros: Prevents AI data collection, improves privacy, removes AI suggestions
- ⚠️ Cons: Lose AI assistant capabilities, need third-party AI tools

**Skype App**
- ✅ Pros: Removes redundant app (desktop version preferred), saves storage
- ⚠️ Cons: Need to manually install Skype if used for communication

### Entertainment & Gaming

**Xbox Gaming App**
- ✅ Pros: Disables Xbox integration, improves gaming performance, reduces background processes
- ⚠️ Cons: Lose Xbox Game Pass access, no Xbox Live integration, can't record gameplay

**Xbox Game Overlay, Gaming Overlay, Identity Provider, Speech to Text, TCUI**
- ✅ Pros: Eliminates gaming interruptions, improves performance, reduces RAM usage
- ⚠️ Cons: No in-game Xbox features, achievements, or social gaming capabilities

**Groove Music**
- ✅ Pros: Removes discontinued service, saves storage
- ⚠️ Cons: No built-in music player (though most use Spotify/alternatives anyway)

**Movies & TV**
- ✅ Pros: Forces better media players (VLC), removes Microsoft Store dependencies
- ⚠️ Cons: No built-in video player for purchased Microsoft content

**Solitaire Collection**
- ✅ Pros: Removes ads, stops game telemetry, saves storage
- ⚠️ Cons: No built-in casual games, need third-party alternatives

### Third-Party Apps

**Candy Crush Games**
- ✅ Pros: Removes ads, stops game telemetry, saves storage, improves productivity
- ⚠️ Cons: Need to manually install if you actually play these games

**Social Media Apps (Facebook, Twitter, LinkedIn, Instagram, WhatsApp, TikTok)**
- ✅ Pros: Reduces notifications, improves privacy, saves storage, better browser experience
- ⚠️ Cons: No native app experience, push notifications require browser

**Streaming Apps (Netflix, Disney+, Hulu, Amazon Prime Video, Spotify Store)**
- ✅ Pros: Forces browser use (often better), saves storage, reduces background activity
- ⚠️ Cons: No offline downloads, lose app-specific features, need browser bookmarks

**PicsArt**
- ✅ Pros: Removes ads, saves storage, forces better photo editing alternatives
- ⚠️ Cons: No quick photo editing capability, need GIMP/Photoshop alternatives

## Services Disabled

### Telemetry & Privacy

**Connected User Experiences and Telemetry (DiagTrack)**
- ✅ Pros: Major privacy improvement, stops data collection, reduces network usage, improves performance
- ⚠️ Cons: May limit Microsoft's ability to diagnose system issues, some diagnostic features unavailable

**WAP Push Message Routing (dmwappushservice)**
- ✅ Pros: Stops carrier message routing, improves privacy, reduces background processes
- ⚠️ Cons: May break some carrier-specific features, MMS functionality might be affected

**Windows Insider Service (wisvc)**
- ✅ Pros: Prevents automatic enrollment in beta programs, improves system stability
- ⚠️ Cons: Can't participate in Windows Insider Program, no access to preview builds

### Performance & Storage

**Superfetch/SysMain**
- ✅ Pros: Significant performance improvement on SSDs, reduces disk usage, faster boot times, less RAM consumption
- ⚠️ Cons: Slower first-time app launches, reduced performance on HDDs, longer program loading on older systems

**Windows Search (wsearch)** *(Optional)*
- ✅ Pros: Major performance boost, reduces disk I/O, saves CPU resources, improves startup time
- ⚠️ Cons: No instant file search, Start menu search limited, need third-party search tools (Everything)

**Offline Files (CscService)**
- ✅ Pros: Eliminates sync conflicts, reduces background activity, saves storage space
- ⚠️ Cons: No automatic file synchronization, lose offline access to network files

### Network & Media

**Windows Media Player Network Sharing (WMPNetworkSvc)**
- ✅ Pros: Improves security, reduces attack surface, stops media broadcasting
- ⚠️ Cons: Can't share media to other devices, DLNA functionality broken

**Remote Registry (RemoteRegistry)**
- ✅ Pros: Major security improvement, prevents remote registry access, reduces attack surface
- ⚠️ Cons: Breaks some enterprise management tools, remote administration more difficult

**Remote Access (RemoteAccess)**
- ✅ Pros: Enhanced security, prevents VPN vulnerabilities, reduces background processes
- ⚠️ Cons: Built-in VPN functionality disabled, may break some networking features

**Fax Service**
- ✅ Pros: Removes obsolete functionality, saves resources, improves security
- ⚠️ Cons: Can't send/receive faxes through Windows (most users don't need this anyway)

### System & Interface

**Program Compatibility Assistant (PcaSvc)**
- ✅ Pros: Stops annoying compatibility warnings, reduces background scanning
- ⚠️ Cons: No automatic compatibility fixes, older programs may not run properly

**Parental Controls (WpcMonSvc)**
- ✅ Pros: Reduces background activity, improves privacy, removes monitoring
- ⚠️ Cons: No built-in parental control features, need third-party solutions

**Downloaded Maps Manager (MapsBroker)**
- ✅ Pros: Stops automatic map downloads, saves bandwidth, improves privacy
- ⚠️ Cons: No offline maps, maps apps may load slower

**Printer Extensions and Notifications (PrintNotify)**
- ✅ Pros: Reduces printer-related background activity, fewer notifications
- ⚠️ Cons: Less detailed printer status information, some printer features may not work

**Retail Demo Service (RetailDemo)**
- ✅ Pros: Removes store demo features, saves resources
- ⚠️ Cons: Can't use retail demo mode (only relevant for store displays)

**Geolocation Service (lfsvc)** *(Windows 11)*
- ✅ Pros: Major privacy improvement, stops location tracking, saves battery
- ⚠️ Cons: Location-based features broken, weather/maps need manual location, Find My Device disabled

**Touch Keyboard and Handwriting Panel (TabletInputService)** *(Windows 11)*
- ✅ Pros: Saves resources on non-touch devices, reduces background processes
- ⚠️ Cons: No on-screen keyboard, handwriting recognition disabled, breaks tablet functionality

**HomeGroup Provider** *(Windows 10 only)*
- ✅ Pros: Removes deprecated functionality, improves security, saves resources
- ⚠️ Cons: No HomeGroup network sharing (feature was removed by Microsoft anyway)

**Microsoft Wallet Service** *(Windows 11)*
- ✅ Pros: Improves privacy, removes payment tracking, reduces background activity
- ⚠️ Cons: No Windows payment integration, NFC payments disabled

## System Tweaks Applied

### File Explorer

**Show file extensions**
- ✅ Pros: Major security improvement, prevents malicious files disguised as documents, easier file identification
- ⚠️ Cons: Slightly more cluttered file names, may confuse non-technical users

**Show hidden files**
- ✅ Pros: Full system visibility, easier troubleshooting, access to configuration files
- ⚠️ Cons: Can accidentally delete system files, more cluttered view, may overwhelm beginners

**Disable quick access** *(Optional)*
- ✅ Pros: Improved privacy, prevents recent file tracking, cleaner File Explorer
- ⚠️ Cons: Less convenient access to frequently used folders, need to navigate manually

### Privacy & Telemetry

**Disable Cortana**
- ✅ Pros: Major privacy improvement, stops voice data collection, reduces background processes, saves resources
- ⚠️ Cons: No voice assistant, lose voice commands, reduced search functionality

**Disable OneDrive auto-start**
- ✅ Pros: Faster boot time, prevents automatic cloud sync, improves privacy, saves resources
- ⚠️ Cons: No automatic file backup, need to manually start OneDrive, lose seamless cloud integration

**Reduce telemetry**
- ✅ Pros: Significant privacy improvement, reduces data sent to Microsoft, improved performance
- ⚠️ Cons: May limit Microsoft's ability to improve Windows, some diagnostic features unavailable

**Disable activity history**
- ✅ Pros: Prevents activity tracking, improves privacy, stops cross-device syncing of activities
- ⚠️ Cons: No timeline feature, can't resume activities across devices

**Disable web search in Start Menu**
- ✅ Pros: Faster local search, prevents Bing tracking, no unwanted web results
- ⚠️ Cons: Can't search web directly from Start menu, need to open browser manually

**Disable background apps**
- ✅ Pros: Significant performance improvement, better battery life, reduced resource usage
- ⚠️ Cons: Apps won't update in background, no live tiles, delayed notifications

### Windows 11 Interface

**Taskbar left alignment**
- ✅ Pros: Familiar Windows 10 layout, consistent with older versions, easier muscle memory
- ⚠️ Cons: Lose modern centered design, may seem outdated to new users

**Classic right-click menu**
- ✅ Pros: Full functionality immediately visible, faster access to advanced options, familiar interface
- ⚠️ Cons: More cluttered appearance, overwhelming for casual users

**Disable widgets**
- ✅ Pros: Major privacy improvement, removes ads/news, better performance, cleaner taskbar
- ⚠️ Cons: No quick weather/news access, lose personalized information at a glance

**Disable Chat icon on taskbar**
- ✅ Pros: Cleaner taskbar, removes Microsoft Teams integration, saves space
- ⚠️ Cons: No quick access to Teams chat, need to use full Teams app

**Disable Snap layouts hover** *(Optional)*
- ✅ Pros: Prevents accidental triggers, cleaner maximize button behavior
- ⚠️ Cons: Lose convenient window arrangement, need manual window resizing

**Configure Start menu layout** *(Optional)*
- ✅ Pros: Simplified Start menu, removes recommendations, cleaner appearance
- ⚠️ Cons: Less personalized experience, fewer quick access options

### Windows 10 Interface

**Hide Task View button**
- ✅ Pros: Saves taskbar space, removes unused feature for many users
- ⚠️ Cons: No quick access to virtual desktops, need keyboard shortcut (Win+Tab)

**Hide Cortana button**
- ✅ Pros: Cleaner taskbar, saves space, reduces Cortana prominence
- ⚠️ Cons: No visible Cortana access, need to use search box or voice activation

**Configure search box**
- ✅ Pros: Full search functionality visible, easier to use, consistent interface
- ⚠️ Cons: Takes up more taskbar space, may be cluttered on smaller screens

**Disable News and Interests**
- ✅ Pros: Major privacy improvement, removes ads, better performance, cleaner taskbar
- ⚠️ Cons: No quick news/weather access, need browser or separate apps

### General Interface

**Dark theme** *(Optional)*
- ✅ Pros: Easier on eyes in low light, modern appearance, may save battery on OLED screens
- ⚠️ Cons: Some apps may not support dark theme properly, harder to read for some users

**Disable tips and suggestions**
- ✅ Pros: Less intrusive experience, fewer notifications, improved focus
- ⚠️ Cons: May miss helpful Windows features, less guidance for new users

**Disable startup sound**
- ✅ Pros: Quieter boot process, professional environment friendly, faster perceived boot
- ⚠️ Cons: No audio confirmation of successful boot, may miss audio hardware issues

### System Performance

**Enable developer mode** *(Optional)*
- ✅ Pros: Can install unsigned apps, access developer features, more flexibility
- ⚠️ Cons: Reduced security, may allow potentially harmful apps, not needed by most users

**Disable Teams auto-start**
- ✅ Pros: Faster boot time, saves resources, prevents unwanted Teams launches
- ⚠️ Cons: Need to manually start Teams for meetings, may miss notifications initially

## Pros of Using This Script

### ✅ Advantages
- **Time Saving**: Automates hours of manual configuration
- **Consistency**: Ensures identical setup across multiple machines
- **Safety**: Creates recovery points and tracks operations
- **Flexibility**: Granular control over what gets installed/removed
- **Privacy**: Reduces telemetry and tracking significantly
- **Performance**: Disables resource-heavy services and features
- **Latest Versions**: Dynamic version detection for key applications
- **Comprehensive Logging**: Detailed logs for troubleshooting
- **Windows Version Aware**: Adapts tweaks based on Windows 10 vs 11
- **User-Friendly**: GUI interface with clear categorization

### ✅ Technical Benefits
- **Winget Integration**: Uses Microsoft's official package manager when available
- **Fallback Methods**: Direct downloads when winget unavailable
- **Service Dependencies**: Checks dependencies before disabling services
- **Registry Backups**: Saves original values for potential rollback
- **Operation Recovery**: Can resume failed operations
- **Timeout Protection**: Prevents hanging on problematic installers

## Cons and Considerations

### ⚠️ Potential Drawbacks
- **Requires Admin Rights**: Must run as administrator
- **System Changes**: Makes significant modifications to Windows
- **Compatibility Risk**: Some tweaks might affect specific hardware/software
- **Learning Curve**: Users should understand what each option does
- **Irreversible Changes**: Some modifications are difficult to undo completely
- **Microsoft Updates**: Future Windows updates might re-enable some features
- **Support Impact**: Modifications might complicate technical support

### ⚠️ Specific Risks
- **Service Dependencies**: Disabling services might affect other applications
- **Registry Modifications**: Incorrect changes could cause system instability
- **Bloatware Removal**: Some users might want certain "bloatware" apps
- **Privacy vs Functionality**: Some privacy tweaks might break expected features
- **Corporate Environments**: May violate company IT policies

## Safety Features

- **System Restore Points**: Creates recovery points before major changes
- **Operation Tracking**: Maintains state of all operations for recovery
- **Dependency Checking**: Verifies service dependencies before changes
- **Registry Backups**: Saves original registry values
- **Comprehensive Logging**: Detailed logs with rotation and error tracking
- **Timeout Protection**: Prevents hanging during installations
- **Version Compatibility**: Adapts behavior based on Windows version

## Best Practices

1. **Create a backup** or system image before running
2. **Test on non-critical systems** first
3. **Review selections** carefully before executing
4. **Keep Windows updated** for best compatibility
5. **Run with stable internet** for downloads
6. **Monitor logs** for any errors or warnings
7. **Restart when prompted** to complete registry changes

## Troubleshooting

- **Check logs** in `logs/` directory for detailed error information
- **Run as Administrator** - required for most operations
- **Internet connection** needed for downloads and winget
- **Windows version** compatibility - some features require specific builds
- **Antivirus software** might interfere with installations
- **Recovery options** available through operation state tracking

---

**Note**: This script makes significant changes to your Windows system. While safety measures are implemented, always ensure you have backups and understand the implications of each modification before proceeding.
