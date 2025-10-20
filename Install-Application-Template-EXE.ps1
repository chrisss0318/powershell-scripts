<#
.SYNOPSIS
    Template script for installing EXE-based Windows applications via Microsoft Intune/Company Portal

.DESCRIPTION
    This script template is specifically designed for EXE installers deployed through Intune.
    Customize the variables and installation logic for your specific application.

    Common EXE installer frameworks and their silent switches:
    - NSIS: /S
    - Inno Setup: /VERYSILENT /SUPPRESSMSGBOXES /NORESTART
    - InstallShield: /s /v"/qn"
    - WiX Burn: /quiet /norestart
    - Advanced Installer: /exenoui /quiet /norestart

.NOTES
    Author: Template
    Version: 1.0
    Intune Exit Codes:
        0 = Success
        1 = Generic failure
        3010 = Success with restart required
#>

#Requires -RunAsAdministrator

# ============================================
# CONFIGURATION - CUSTOMIZE THESE VALUES
# ============================================

# Application details
$AppName = "ApplicationName"
$AppVersion = "1.0.0"
$AppPublisher = "Publisher"
$AppInstallPath = "$env:ProgramFiles\$AppPublisher\$AppName"  # Expected installation path

# EXE installer details
$InstallerFileName = "setup.exe"
$InstallerArgs = "/S"  # Customize for your EXE installer type (see examples above)

# Detection method - How to verify installation succeeded
$DetectionMethod = "File"  # Options: "File", "Registry", "Both"
$DetectionFilePath = "$AppInstallPath\$AppName.exe"  # File to check for successful install
$DetectionRegistryPath = "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall"  # Registry location to check

# Logging
$LogPath = "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs"
$LogFile = "$LogPath\Install-$AppName-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"

# Installation requirements
$RequiredDiskSpaceGB = 1  # Minimum free disk space required

# ============================================
# FUNCTIONS
# ============================================

function Write-Log {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,

        [Parameter(Mandatory=$false)]
        [ValidateSet('Info', 'Warning', 'Error')]
        [string]$Level = 'Info'
    )

    $Timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $LogEntry = "[$Timestamp] [$Level] $Message"

    # Create log directory if it doesn't exist
    if (-not (Test-Path -Path $LogPath)) {
        New-Item -Path $LogPath -ItemType Directory -Force | Out-Null
    }

    # Write to log file
    Add-Content -Path $LogFile -Value $LogEntry

    # Also write to console
    switch ($Level) {
        'Error'   { Write-Error $Message }
        'Warning' { Write-Warning $Message }
        default   { Write-Output $Message }
    }
}

function Test-ApplicationInstalled {
    param(
        [string]$AppName,
        [string]$FilePath,
        [string]$Method
    )

    $Installed = $false

    # Check file-based detection
    if ($Method -eq "File" -or $Method -eq "Both") {
        if (Test-Path -Path $FilePath) {
            Write-Log "Detection: Application file found at $FilePath" -Level Info
            $Installed = $true
        }
    }

    # Check registry-based detection
    if (($Method -eq "Registry" -or $Method -eq "Both") -and -not $Installed) {
        $RegistryPaths = @(
            "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
            "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
        )

        foreach ($Path in $RegistryPaths) {
            $App = Get-ItemProperty -Path $Path -ErrorAction SilentlyContinue |
                   Where-Object { $_.DisplayName -like "*$AppName*" }

            if ($App) {
                Write-Log "Detection: Application found in registry: $($App.DisplayName)" -Level Info
                $Installed = $true
                break
            }
        }
    }

    return $Installed
}

# ============================================
# MAIN INSTALLATION LOGIC
# ============================================

try {
    Write-Log "========================================" -Level Info
    Write-Log "Starting EXE installation of $AppName $AppVersion" -Level Info
    Write-Log "========================================" -Level Info

    # Get script directory
    $ScriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
    Write-Log "Script path: $ScriptPath" -Level Info

    # ========================================
    # PRE-INSTALLATION CHECKS
    # ========================================

    # Verify installer exists
    $InstallerPath = Join-Path -Path $ScriptPath -ChildPath $InstallerFileName
    if (-not (Test-Path -Path $InstallerPath)) {
        Write-Log "EXE installer not found at: $InstallerPath" -Level Error
        exit 1
    }
    Write-Log "EXE installer found: $InstallerPath" -Level Info

    # Get installer file info
    $InstallerInfo = Get-Item -Path $InstallerPath
    Write-Log "Installer size: $([math]::Round($InstallerInfo.Length / 1MB, 2)) MB" -Level Info

    # Check if application is already installed
    $AlreadyInstalled = Test-ApplicationInstalled -AppName $AppName -FilePath $DetectionFilePath -Method $DetectionMethod

    if ($AlreadyInstalled) {
        Write-Log "Application '$AppName' appears to be already installed" -Level Warning
        Write-Log "Proceeding with installation (will upgrade/reinstall if supported)" -Level Info
    }

    # Check disk space
    $SystemDrive = $env:SystemDrive
    $FreeSpaceGB = (Get-PSDrive -Name $SystemDrive.Trim(':') | Select-Object -ExpandProperty Free) / 1GB

    if ($FreeSpaceGB -lt $RequiredDiskSpaceGB) {
        Write-Log "Insufficient disk space. Required: $RequiredDiskSpaceGB GB, Available: $([math]::Round($FreeSpaceGB, 2)) GB" -Level Error
        exit 1
    }
    Write-Log "Disk space check passed. Available: $([math]::Round($FreeSpaceGB, 2)) GB" -Level Info

    # Check OS version (optional)
    $OSVersion = [System.Environment]::OSVersion.Version
    Write-Log "OS Version: $($OSVersion.Major).$($OSVersion.Minor) Build $($OSVersion.Build)" -Level Info

    # ========================================
    # INSTALLATION
    # ========================================

    Write-Log "Executing EXE installer..." -Level Info
    Write-Log "Command: $InstallerPath $InstallerArgs" -Level Info

    # Start the EXE installer
    $Process = Start-Process -FilePath $InstallerPath `
                            -ArgumentList $InstallerArgs `
                            -Wait `
                            -PassThru `
                            -NoNewWindow

    $ExitCode = $Process.ExitCode
    Write-Log "EXE installer completed with exit code: $ExitCode" -Level Info

    # Interpret exit codes (common for EXE installers)
    # Note: Exit codes vary by installer framework - customize as needed
    switch ($ExitCode) {
        0 {
            Write-Log "Installation completed successfully" -Level Info
        }
        3010 {
            Write-Log "Installation completed successfully. Restart required." -Level Warning
        }
        1641 {
            Write-Log "Installation completed successfully. Installer initiated restart." -Level Warning
            $ExitCode = 3010  # Normalize to Intune's restart code
        }
        1618 {
            Write-Log "Another installation is in progress. Please wait and try again." -Level Error
            exit 1618
        }
        1619 {
            Write-Log "Installation package could not be opened." -Level Error
            exit 1619
        }
        1602 {
            Write-Log "Installation was cancelled by user" -Level Error
            exit 1602
        }
        default {
            Write-Log "Installation completed with exit code: $ExitCode" -Level Warning
            Write-Log "Note: Verify this is a valid success code for your installer" -Level Warning
        }
    }

    # ========================================
    # POST-INSTALLATION VERIFICATION
    # ========================================

    Write-Log "Waiting for installation to complete..." -Level Info
    Start-Sleep -Seconds 10  # Give the installer time to finalize

    # Verify installation using detection method
    $InstallVerified = Test-ApplicationInstalled -AppName $AppName -FilePath $DetectionFilePath -Method $DetectionMethod

    if ($InstallVerified) {
        Write-Log "Installation verification PASSED" -Level Info
    } else {
        Write-Log "Installation verification FAILED - Application not detected" -Level Error
        Write-Log "Expected file location: $DetectionFilePath" -Level Error

        # Don't exit with error if installer returned success code
        if ($ExitCode -eq 0 -or $ExitCode -eq 3010) {
            Write-Log "Installer reported success despite detection failure - proceeding" -Level Warning
        } else {
            exit 1
        }
    }

    # ========================================
    # POST-INSTALLATION TASKS (Optional)
    # ========================================

    # Example: Create desktop shortcut
    <#
    $WshShell = New-Object -ComObject WScript.Shell
    $DesktopPath = [System.Environment]::GetFolderPath('CommonDesktopDirectory')
    $ShortcutPath = Join-Path -Path $DesktopPath -ChildPath "$AppName.lnk"
    $Shortcut = $WshShell.CreateShortcut($ShortcutPath)
    $Shortcut.TargetPath = $DetectionFilePath
    $Shortcut.Save()
    Write-Log "Created desktop shortcut: $ShortcutPath" -Level Info
    #>

    # Example: Configure application settings
    <#
    $ConfigPath = "$env:ProgramData\$AppPublisher\$AppName\config.ini"
    if (Test-Path -Path $ConfigPath) {
        Write-Log "Configuring application settings..." -Level Info
        # Add your configuration logic here
    }
    #>

    # Example: Set registry values
    <#
    $RegPath = "HKLM:\Software\$AppPublisher\$AppName"
    if (-not (Test-Path -Path $RegPath)) {
        New-Item -Path $RegPath -Force | Out-Null
    }
    Set-ItemProperty -Path $RegPath -Name "Setting1" -Value "Value1"
    Write-Log "Configured registry settings" -Level Info
    #>

    Write-Log "========================================" -Level Info
    Write-Log "Installation of $AppName completed successfully" -Level Info
    Write-Log "Log file: $LogFile" -Level Info
    Write-Log "========================================" -Level Info

    exit $ExitCode
}
catch {
    Write-Log "Fatal error during installation: $_" -Level Error
    Write-Log "Stack trace: $($_.ScriptStackTrace)" -Level Error
    exit 1
}
