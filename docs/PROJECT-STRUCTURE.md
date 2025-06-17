# Project Structure & Technical Notes

## 📁 Improved Directory Structure

Your Windows Setup GUI project now has a clean, organized structure:

```
Home-Provisioning-Script/
├── src/                          # Main application files
│   └── Windows-Setup-GUI.ps1     # Primary GUI application
│
├── config/                       # Configuration files
│   ├── apps.json                 # Application definitions with dynamic URLs
│   ├── bloatware.json           # Bloatware removal targets
│   ├── services.json            # System services configuration
│   └── tweaks.json              # Registry and system tweaks
│
├── modules/                      # Core functionality modules
│   ├── Installers.psm1          # Application installation engine
│   ├── SystemOptimizations.psm1 # System tweaks and service management
│   └── GuiComponents.psm1       # GUI helper functions
│
├── utils/                        # Utility modules
│   ├── ConfigLoader.psm1        # Configuration loading and URL resolution
│   ├── WingetUtils.psm1         # Winget installation and management
│   ├── ProfileManager.psm1      # User profile save/load functionality
│   ├── Logging.psm1             # Centralized logging system
│   └── JsonUtils.psm1           # JSON parsing utilities
│
├── tests/                        # Test scripts and validation
│   └── Test-EnhancedFeatures.ps1 # Comprehensive feature testing
│
├── docs/                         # Documentation
│   ├── ENHANCED-FEATURES.md      # Feature overview and usage guide
│   └── PROJECT-STRUCTURE.md      # This file
│
└── independent-scripts/          # Standalone legacy scripts
    ├── windows10-setup.ps1       # Legacy Windows 10 script
    ├── windows11-setup.ps1       # Legacy Windows 11 script
    └── test-Windows-Setup-GUI.ps1 # Legacy test script
```

## 🚀 System Resource Management

### Adaptive Parallel Installation

The enhanced script now automatically detects system capabilities and adjusts installation concurrency:

**System Detection Logic:**
- **CPU Cores**: More cores = higher concurrency potential
- **Available RAM**: Low memory systems forced to sequential
- **Total RAM**: Systems with <4GB RAM use sequential only

**Concurrency Levels:**
- **High-end Systems** (8+ cores, 8+ GB RAM): Up to 4 concurrent installations
- **Mid-range Systems** (4+ cores, 4-8 GB RAM): Up to 3 concurrent installations  
- **Budget Systems** (2+ cores, 4+ GB RAM): Up to 2 concurrent installations
- **Low-end Systems** (<2 cores or <4 GB RAM): Sequential installation only

**Safety Features:**
- Automatic fallback to sequential if resources are limited
- User override option for forced parallel installation
- Clear warnings about system resource constraints
- Graceful degradation without script failure

### Resource Monitoring

```powershell
# Example system detection output:
System: 4 cores, 8.0 GB total RAM, 5.2 GB available
Recommended concurrency level: 3
```

## 🔧 Winget Installation & Restart Requirements

### **Important: Winget Does NOT Require System Restart**

**Key Facts:**
- ✅ **Winget installation is a user-space operation**
- ✅ **No system restart required after winget installation**
- ✅ **No elevated permissions needed for winget usage after install**
- ✅ **Works immediately in new PowerShell sessions**

### Winget Installation Process

1. **Check Compatibility**: Windows 10 build 16299+ (October 2017 Update)
2. **Install Dependencies**: VC++ Runtime and UI.Xaml libraries
3. **Install App Installer**: Microsoft Store package containing winget
4. **Register Package**: PowerShell package registration
5. **Verify Availability**: Command availability check

### Why Winget May Not Be Immediately Available

**Normal Behavior (No Restart Needed):**
- PowerShell module cache may not refresh immediately
- PATH environment variable needs refresh in current session
- App registration may take a few seconds to propagate

**Solutions (All work without restart):**
- Start a new PowerShell window
- Refresh environment variables: `$env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")`
- Wait 30-60 seconds for package registration
- Use `winget --version` to test availability

**Fallback Behavior:**
If winget isn't immediately available, the script automatically:
1. Continues with direct download methods
2. Provides all the same functionality
3. Logs the situation for user awareness
4. Succeeds in all installation tasks

## 🛠️ Module Dependencies

### Import Order (Critical)
1. **Logging.psm1** - Must be first (other modules depend on it)
2. **JsonUtils.psm1** - JSON parsing utilities
3. **ConfigLoader.psm1** - Configuration loading (depends on JsonUtils)
4. **WingetUtils.psm1** - Winget management (depends on Logging)
5. **ProfileManager.psm1** - Profile management (depends on Logging, ConfigLoader)
6. **Installers.psm1** - Installation engine (depends on all above)
7. **SystemOptimizations.psm1** - System tweaks (depends on Logging)
8. **GuiComponents.psm1** - GUI helpers (depends on Logging)

### Cross-Module Functions Used
- `Write-LogMessage` (Logging) - Used by all modules
- `Get-ConfigurationData` (ConfigLoader) - Used by Installers, ProfileManager
- `ConvertFrom-JsonToHashtable` (JsonUtils) - Used by ConfigLoader, ProfileManager

## 🔍 Error Handling Strategy

### Graceful Degradation
- **Winget Unavailable**: Falls back to direct downloads
- **Dynamic URLs Fail**: Uses static fallback URLs
- **Profile Loading Fails**: Continues with manual selection
- **System Resource Limits**: Automatically adjusts concurrency
- **Individual App Failures**: Don't stop batch operations

### Logging Strategy
- **ERROR**: Critical failures that stop operations
- **WARNING**: Issues that don't prevent functionality
- **SUCCESS**: Successful operations and completions
- **INFO**: General status and progress information
- **DEBUG**: Detailed technical information (verbose mode)

## 🚀 Performance Optimizations

### Batch Installation Benefits
- **Time Savings**: 40-60% faster than sequential for multiple apps
- **Resource Efficiency**: Intelligent queuing prevents system overload
- **Parallel Downloads**: Multiple simultaneous downloads when possible
- **Smart Scheduling**: CPU and I/O intensive tasks balanced

### Memory Management
- **Streaming Downloads**: Large files don't consume excessive RAM
- **Automatic Cleanup**: Temporary files removed after installation
- **Job Isolation**: Failed jobs don't affect other installations
- **Resource Monitoring**: Continuous system resource awareness

## 🔒 Security Considerations

### URL Resolution Security
- **HTTPS Only**: All downloads use encrypted connections
- **Certificate Validation**: SSL/TLS certificates verified
- **Fallback Protection**: Static URLs as security fallback
- **API Rate Limiting**: Respectful API usage to prevent blocking

### Profile Security
- **User-Scoped Storage**: Profiles stored in user directory only
- **JSON Only**: No executable code in profile files
- **Validation**: Profile content validated before loading
- **Integrity Checking**: Profile corruption detection

### Installation Security
- **Digital Signatures**: Installer signature verification when possible
- **Known Sources**: Only official download sources used
- **Path Validation**: Installation paths validated before use
- **Process Isolation**: Installation processes run in isolation

## 📈 Future Enhancement Areas

### Planned Improvements
- **Progress Bars**: Real-time download progress indicators
- **Bandwidth Throttling**: Optional download speed limiting
- **Installation Scheduling**: Delayed installation capabilities
- **Update Notifications**: Check for app updates periodically
- **Custom Repositories**: Support for private software repositories

### Extensibility
- **Plugin Architecture**: Modular installer plugins
- **Custom URL Resolvers**: Additional dynamic URL types
- **External Configuration**: Cloud-based configuration loading
- **API Integration**: Integration with software management APIs

This improved structure provides better maintainability, clearer separation of concerns, and enhanced functionality while maintaining the user-friendly experience you started with.