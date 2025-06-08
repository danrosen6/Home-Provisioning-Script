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
        Python = @{
            Windows10 = @{
                URL = "https://www.python.org/ftp/python/3.11.0/python-3.11.0-amd64.exe"
                Arguments = "/quiet InstallAllUsers=1 PrependPath=1"
                FileExtension = ".exe"
            }
            Windows11 = @{
                URL = "https://www.python.org/ftp/python/3.11.0/python-3.11.0-amd64.exe"
                Arguments = "/quiet InstallAllUsers=1 PrependPath=1"
                FileExtension = ".exe"
            }
        }
        PyCharm = @{
            Windows10 = @{
                Community = @{
                    URL = "https://download.jetbrains.com/python/pycharm-community-2023.1.exe"
                    Arguments = "/S"
                    FileExtension = ".exe"
                }
                Professional = @{
                    URL = "https://download.jetbrains.com/python/pycharm-professional-2023.1.exe"
                    Arguments = "/S"
                    FileExtension = ".exe"
                }
            }
            Windows11 = @{
                Community = @{
                    URL = "https://download.jetbrains.com/python/pycharm-community-2023.1.exe"
                    Arguments = "/S"
                    FileExtension = ".exe"
                }
                Professional = @{
                    URL = "https://download.jetbrains.com/python/pycharm-professional-2023.1.exe"
                    Arguments = "/S"
                    FileExtension = ".exe"
                }
            }
        }
        VisualStudioCode = @{
            Windows10 = @{
                URL = "https://code.visualstudio.com/sha/download?build=stable&os=win32-x64"
                Arguments = "/VERYSILENT /MERGETASKS=!runcode"
                FileExtension = ".exe"
            }
            Windows11 = @{
                URL = "https://code.visualstudio.com/sha/download?build=stable&os=win32-x64"
                Arguments = "/VERYSILENT /MERGETASKS=!runcode"
                FileExtension = ".exe"
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
    
    return $appConfig[$ostype]
}

# Export functions
Export-ModuleMember -Function Get-WindowsVersion, Get-WindowsOSType, Get-WindowsBuildInfo, Get-AppDirectDownloadInfo 