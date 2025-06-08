# Download configuration for Windows Setup GUI
# This module handles application download URLs and arguments based on Windows version

# Get Windows version information
function Get-WindowsVersion {
    $os = Get-WmiObject -Class Win32_OperatingSystem
    return $os.Version
}

function Get-WindowsOSType {
    $version = Get-WindowsVersion
    $buildNumber = [int]($version.Split('.')[2])
    
    # Windows 11 starts at build 22000
    if ($buildNumber -ge 22000) {
        return "Windows 11"
    }
    return "Windows 10"
}

function Get-WindowsBuildInfo {
    param (
        [string]$Version
    )
    
    $buildNumber = [int]($Version.Split('.')[2])
    $ostype = if ($buildNumber -ge 22000) { "Windows 11" } else { "Windows 10" }
    
    return @{
        OSType = $ostype
        Version = $Version
        BuildNumber = $buildNumber
        IsWindows11 = ($buildNumber -ge 22000)
    }
}

# Function to get system architecture
function Get-SystemArchitecture {
    if ([Environment]::Is64BitOperatingSystem) {
        return "x64"
    } else {
        return "x86"
    }
}

# Application download configuration
$script:DownloadConfig = @{
    # Version-specific configurations
    Windows10 = @{
        MinVersion = "10.0.10240"  # First Windows 10 version
        MaxVersion = "10.0.99999"  # Future-proof
    }
    Windows11 = @{
        MinVersion = "10.0.22000"  # First Windows 11 version
        MaxVersion = "10.0.99999"  # Future-proof
    }
    
    # Application download information
    Applications = @{
        "Visual Studio Code" = @{
            Windows10 = @{
                URL = "https://code.visualstudio.com/sha/download?build=stable&os=win32-x64"
                Arguments = "/VERYSILENT /MERGETASKS=!runcode"
                FileExtension = ".exe"
                VerificationPaths = @(
                    "${env:LOCALAPPDATA}\Programs\Microsoft VS Code\Code.exe",
                    "C:\Program Files\Microsoft VS Code\Code.exe"
                )
            }
            Windows11 = @{
                URL = "https://code.visualstudio.com/sha/download?build=stable&os=win32-x64"
                Arguments = "/VERYSILENT /MERGETASKS=!runcode"
                FileExtension = ".exe"
                VerificationPaths = @(
                    "${env:LOCALAPPDATA}\Programs\Microsoft VS Code\Code.exe",
                    "C:\Program Files\Microsoft VS Code\Code.exe"
                )
            }
        }
        "Git" = @{
            Windows10 = @{
                URL = "https://github.com/git-for-windows/git/releases/latest/download/Git-2.42.0.2-64-bit.exe"
                Arguments = "/VERYSILENT /NORESTART"
                FileExtension = ".exe"
                VerificationPaths = @(
                    "C:\Program Files\Git\cmd\git.exe",
                    "C:\Program Files (x86)\Git\cmd\git.exe"
                )
            }
            Windows11 = @{
                URL = "https://github.com/git-for-windows/git/releases/latest/download/Git-2.42.0.2-64-bit.exe"
                Arguments = "/VERYSILENT /NORESTART"
                FileExtension = ".exe"
                VerificationPaths = @(
                    "C:\Program Files\Git\cmd\git.exe",
                    "C:\Program Files (x86)\Git\cmd\git.exe"
                )
            }
        }
        "Python" = @{
            Windows10 = @{
                URL = "https://www.python.org/ftp/python/3.12.2/python-3.12.2-amd64.exe"  # Default to 64-bit
                Arguments = "/quiet InstallAllUsers=1 PrependPath=1"
                FileExtension = ".exe"
                VerificationPaths = @(
                    "C:\Program Files\Python312\python.exe",
                    "C:\Program Files (x86)\Python312\python.exe",
                    "C:\Python312\python.exe"
                )
            }
            Windows11 = @{
                URL = "https://www.python.org/ftp/python/3.12.2/python-3.12.2-amd64.exe"  # Default to 64-bit
                Arguments = "/quiet InstallAllUsers=1 PrependPath=1"
                FileExtension = ".exe"
                VerificationPaths = @(
                    "C:\Program Files\Python312\python.exe",
                    "C:\Program Files (x86)\Python312\python.exe",
                    "C:\Python312\python.exe"
                )
            }
        }
        "PyCharm Community" = @{
            Windows10 = @{
                URL = "https://download.jetbrains.com/python/pycharm-community-2023.3.4.exe"
                Arguments = "/S"
                FileExtension = ".exe"
                VerificationPaths = @(
                    "${env:LOCALAPPDATA}\Programs\JetBrains\PyCharm Community Edition\bin\pycharm64.exe",
                    "C:\Program Files\JetBrains\PyCharm Community Edition\bin\pycharm64.exe"
                )
            }
            Windows11 = @{
                URL = "https://download.jetbrains.com/python/pycharm-community-2023.3.4.exe"
                Arguments = "/S"
                FileExtension = ".exe"
                VerificationPaths = @(
                    "${env:LOCALAPPDATA}\Programs\JetBrains\PyCharm Community Edition\bin\pycharm64.exe",
                    "C:\Program Files\JetBrains\PyCharm Community Edition\bin\pycharm64.exe"
                )
            }
        }
        "Google Chrome" = @{
            Windows10 = @{
                URL = "https://dl.google.com/chrome/install/latest/chrome_installer.exe"
                Arguments = "/silent /install"
                FileExtension = ".exe"
                VerificationPaths = @(
                    "C:\Program Files\Google\Chrome\Application\chrome.exe",
                    "C:\Program Files (x86)\Google\Chrome\Application\chrome.exe"
                )
            }
            Windows11 = @{
                URL = "https://dl.google.com/chrome/install/latest/chrome_installer.exe"
                Arguments = "/silent /install"
                FileExtension = ".exe"
                VerificationPaths = @(
                    "C:\Program Files\Google\Chrome\Application\chrome.exe",
                    "C:\Program Files (x86)\Google\Chrome\Application\chrome.exe"
                )
            }
        }
        "Mozilla Firefox" = @{
            Windows10 = @{
                URL = "https://download.mozilla.org/?product=firefox-latest&os=win64&lang=en-US"
                Arguments = "/S"
                FileExtension = ".exe"
                VerificationPaths = @(
                    "C:\Program Files\Mozilla Firefox\firefox.exe",
                    "C:\Program Files (x86)\Mozilla Firefox\firefox.exe"
                )
            }
            Windows11 = @{
                URL = "https://download.mozilla.org/?product=firefox-latest&os=win64&lang=en-US"
                Arguments = "/S"
                FileExtension = ".exe"
                VerificationPaths = @(
                    "C:\Program Files\Mozilla Firefox\firefox.exe",
                    "C:\Program Files (x86)\Mozilla Firefox\firefox.exe"
                )
            }
        }
        "Brave Browser" = @{
            Windows10 = @{
                URL = "https://referrals.brave.com/latest/BraveBrowserSetup.exe"
                Arguments = "/silent /install"
                FileExtension = ".exe"
                VerificationPaths = @(
                    "C:\Program Files\BraveSoftware\Brave-Browser\Application\brave.exe",
                    "C:\Program Files (x86)\BraveSoftware\Brave-Browser\Application\brave.exe"
                )
            }
            Windows11 = @{
                URL = "https://referrals.brave.com/latest/BraveBrowserSetup.exe"
                Arguments = "/silent /install"
                FileExtension = ".exe"
                VerificationPaths = @(
                    "C:\Program Files\BraveSoftware\Brave-Browser\Application\brave.exe",
                    "C:\Program Files (x86)\BraveSoftware\Brave-Browser\Application\brave.exe"
                )
            }
        }
        "Spotify" = @{
            Windows10 = @{
                URL = "https://download.scdn.co/SpotifySetup.exe"
                Arguments = "/silent"
                FileExtension = ".exe"
                VerificationPaths = @(
                    "${env:LOCALAPPDATA}\Spotify\Spotify.exe",
                    "C:\Program Files\Spotify\Spotify.exe"
                )
            }
            Windows11 = @{
                URL = "https://download.scdn.co/SpotifySetup.exe"
                Arguments = "/silent"
                FileExtension = ".exe"
                VerificationPaths = @(
                    "${env:LOCALAPPDATA}\Spotify\Spotify.exe",
                    "C:\Program Files\Spotify\Spotify.exe"
                )
            }
        }
        "Discord" = @{
            Windows10 = @{
                URL = "https://discord.com/api/downloads/distributions/app/installers/latest?channel=stable&platform=win&arch=x86"
                Arguments = "/S"
                FileExtension = ".exe"
                VerificationPaths = @(
                    "${env:LOCALAPPDATA}\Discord\app-*\Discord.exe",
                    "C:\Program Files\Discord\Discord.exe"
                )
            }
            Windows11 = @{
                URL = "https://discord.com/api/downloads/distributions/app/installers/latest?channel=stable&platform=win&arch=x86"
                Arguments = "/S"
                FileExtension = ".exe"
                VerificationPaths = @(
                    "${env:LOCALAPPDATA}\Discord\app-*\Discord.exe",
                    "C:\Program Files\Discord\Discord.exe"
                )
            }
        }
        "Steam" = @{
            Windows10 = @{
                URL = "https://cdn.akamai.steamstatic.com/client/installer/SteamSetup.exe"
                Arguments = "/S"
                FileExtension = ".exe"
                VerificationPaths = @(
                    "C:\Program Files (x86)\Steam\Steam.exe",
                    "C:\Program Files\Steam\Steam.exe"
                )
            }
            Windows11 = @{
                URL = "https://cdn.akamai.steamstatic.com/client/installer/SteamSetup.exe"
                Arguments = "/S"
                FileExtension = ".exe"
                VerificationPaths = @(
                    "C:\Program Files (x86)\Steam\Steam.exe",
                    "C:\Program Files\Steam\Steam.exe"
                )
            }
        }
        "VLC Media Player" = @{
            Windows10 = @{
                URL = "https://get.videolan.org/vlc/3.0.20/win64/vlc-3.0.20-win64.exe"
                Arguments = "/S"
                FileExtension = ".exe"
                VerificationPaths = @(
                    "C:\Program Files\VideoLAN\VLC\vlc.exe",
                    "C:\Program Files (x86)\VideoLAN\VLC\vlc.exe"
                )
            }
            Windows11 = @{
                URL = "https://get.videolan.org/vlc/3.0.20/win64/vlc-3.0.20-win64.exe"
                Arguments = "/S"
                FileExtension = ".exe"
                VerificationPaths = @(
                    "C:\Program Files\VideoLAN\VLC\vlc.exe",
                    "C:\Program Files (x86)\VideoLAN\VLC\vlc.exe"
                )
            }
        }
        "7-Zip" = @{
            Windows10 = @{
                URL = "https://www.7-zip.org/a/7z2401-x64.exe"
                Arguments = "/S"
                FileExtension = ".exe"
                VerificationPaths = @(
                    "C:\Program Files\7-Zip\7z.exe",
                    "C:\Program Files (x86)\7-Zip\7z.exe"
                )
            }
            Windows11 = @{
                URL = "https://www.7-zip.org/a/7z2401-x64.exe"
                Arguments = "/S"
                FileExtension = ".exe"
                VerificationPaths = @(
                    "C:\Program Files\7-Zip\7z.exe",
                    "C:\Program Files (x86)\7-Zip\7z.exe"
                )
            }
        }
        "Notepad++" = @{
            Windows10 = @{
                URL = "https://github.com/notepad-plus-plus/notepad-plus-plus/releases/latest/download/npp.8.6.3.Installer.x64.exe"
                Arguments = "/S"
                FileExtension = ".exe"
                VerificationPaths = @(
                    "C:\Program Files\Notepad++\notepad++.exe",
                    "C:\Program Files (x86)\Notepad++\notepad++.exe"
                )
            }
            Windows11 = @{
                URL = "https://github.com/notepad-plus-plus/notepad-plus-plus/releases/latest/download/npp.8.6.3.Installer.x64.exe"
                Arguments = "/S"
                FileExtension = ".exe"
                VerificationPaths = @(
                    "C:\Program Files\Notepad++\notepad++.exe",
                    "C:\Program Files (x86)\Notepad++\notepad++.exe"
                )
            }
        }
        "Microsoft PowerToys" = @{
            Windows10 = @{
                URL = "https://github.com/microsoft/PowerToys/releases/latest/download/PowerToysSetup-x64.exe"
                Arguments = "-silent"
                FileExtension = ".exe"
                VerificationPaths = @(
                    "${env:LOCALAPPDATA}\Programs\PowerToys\PowerToys.exe",
                    "C:\Program Files\PowerToys\PowerToys.exe"
                )
            }
            Windows11 = @{
                URL = "https://github.com/microsoft/PowerToys/releases/latest/download/PowerToysSetup-x64.exe"
                Arguments = "-silent"
                FileExtension = ".exe"
                VerificationPaths = @(
                    "${env:LOCALAPPDATA}\Programs\PowerToys\PowerToys.exe",
                    "C:\Program Files\PowerToys\PowerToys.exe"
                )
            }
        }
    }
}

function Get-AppDirectDownloadInfo {
    param (
        [string]$AppName
    )
    
    $windowsVersion = Get-WindowsVersion
    $ostype = Get-WindowsOSType
    $architecture = Get-SystemArchitecture
    
    # Check if application exists in config
    if (-not $script:DownloadConfig.Applications.ContainsKey($AppName)) {
        Write-Log "Application $AppName not found in download configuration" -Level "WARNING"
        return $null
    }
    
    # Get version-specific config
    $appConfig = $script:DownloadConfig.Applications[$AppName]
    if (-not $appConfig.ContainsKey($ostype)) {
        Write-Log "No download configuration for $AppName on $ostype" -Level "WARNING"
        return $null
    }
    
    $config = $appConfig[$ostype]
    
    # Handle architecture-specific URLs
    if ($AppName -eq "Python") {
        if ($architecture -eq "x64") {
            $config.URL = "https://www.python.org/ftp/python/3.12.2/python-3.12.2-amd64.exe"
            $config.VerificationPaths = @(
                "C:\Program Files\Python312\python.exe",
                "C:\Program Files (x86)\Python312\python.exe",
                "C:\Python312\python.exe"
            )
        } else {
            $config.URL = "https://www.python.org/ftp/python/3.12.2/python-3.12.2.exe"
            $config.VerificationPaths = @(
                "C:\Program Files (x86)\Python312\python.exe",
                "C:\Python312\python.exe"
            )
        }
    }
    
    return $config
}

# Export functions
# Export-ModuleMember -Function Get-WindowsVersion, Get-WindowsOSType, Get-WindowsBuildInfo, Get-AppDirectDownloadInfo

# Remove the Export-ModuleMember line
# Export-ModuleMember -Function Get-WindowsVersion, Get-WindowsOSType, Get-WindowsBuildInfo, Get-AppDirectDownloadInfo 