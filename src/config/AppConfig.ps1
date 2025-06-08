# Application configuration for Windows Setup GUI

$script:AppConfig = @{
    # Application categories
    Categories = @{
        "Development" = @{
            "Python" = @{
                "Name" = "Python"
                "Description" = "Python programming language"
                "Version" = "3.12"
                "CreateVirtualEnv" = $true
            }
            "PyCharm" = @{
                "Name" = "PyCharm"
                "Description" = "Python IDE"
                "Edition" = "Community"
                "ConfigureSettings" = $true
            }
            "Visual Studio Code" = @{
                "Name" = "Visual Studio Code"
                "Description" = "Code editor"
            }
        }
        "Productivity" = @{
            "Microsoft Office" = @{
                "Name" = "Microsoft Office"
                "Description" = "Office suite"
            }
            "Adobe Acrobat Reader" = @{
                "Name" = "Adobe Acrobat Reader"
                "Description" = "PDF reader"
            }
        }
    }
    
    # Bloatware to remove
    Bloatware = @(
        "Microsoft.3DBuilder"
        "Microsoft.BingFinance"
        "Microsoft.BingNews"
        "Microsoft.BingSports"
        "Microsoft.BingWeather"
        "Microsoft.GetHelp"
        "Microsoft.Getstarted"
        "Microsoft.MicrosoftOfficeHub"
        "Microsoft.MicrosoftSolitaireCollection"
        "Microsoft.MixedReality.Portal"
        "Microsoft.People"
        "Microsoft.SkypeApp"
        "Microsoft.WindowsAlarms"
        "Microsoft.WindowsFeedbackHub"
        "Microsoft.WindowsMaps"
        "Microsoft.ZuneMusic"
        "Microsoft.ZuneVideo"
    )
    
    # Services to configure
    Services = @{
        "DiagTrack" = @{
            "Name" = "Connected User Experiences and Telemetry"
            "StartupType" = "Disabled"
        }
        "SysMain" = @{
            "Name" = "SysMain"
            "StartupType" = "Disabled"
        }
    }
    
    # System optimizations
    Optimizations = @{
        "DisableTelemetry" = $true
        "DisableCortana" = $true
        "DisableWindowsSearch" = $true
        "DisableWindowsUpdate" = $false
        "DisableDefender" = $false
        "DisableFirewall" = $false
    }
} 