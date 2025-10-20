<#
.SYNOPSIS
    Template script for installing Windows applications via Microsoft Intune/Company Portal

.DESCRIPTION
    This script template provides a framework for installing applications through Intune.
    Customize the variables and installation logic for your specific application.

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

# Installation file details
$InstallerFileName = "setup.exe"  # or .msi
$InstallerArgs = "/S /quiet"      # Customize for your installer type

# Logging
$LogPath = "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs"
$LogFile = "$LogPath\Install-$AppName-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"

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

# ============================================
# MAIN INSTALLATION LOGIC
# ============================================

try {
    Write-Log "========================================" -Level Info
    Write-Log "Starting installation of $AppName $AppVersion" -Level Info
    Write-Log "========================================" -Level Info

    # Get script directory
    $ScriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
    Write-Log "Script path: $ScriptPath" -Level Info

    # Verify installer exists
    $InstallerPath = Join-Path -Path $ScriptPath -ChildPath $InstallerFileName
    if (-not (Test-Path -Path $InstallerPath)) {
        Write-Log "Installer not found at: $InstallerPath" -Level Error
        exit 1
    }
    Write-Log "Installer found: $InstallerPath" -Level Info

    # ========================================
    # PRE-INSTALLATION CHECKS
    # ========================================

    # Example: Check if application is already installed
    # Customize this based on your application
    <#
    $InstalledApp = Get-ItemProperty -Path "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*" |
                    Where-Object { $_.DisplayName -like "*$AppName*" }

    if ($InstalledApp) {
        Write-Log "Application is already installed. Version: $($InstalledApp.DisplayVersion)" -Level Warning
        # Uncomment to skip installation if already present
        # exit 0
    }
    #>

    # Example: Check disk space
    $RequiredSpaceGB = 1  # Customize this value
    $SystemDrive = $env:SystemDrive
    $FreeSpaceGB = (Get-PSDrive -Name $SystemDrive.Trim(':') | Select-Object -ExpandProperty Free) / 1GB

    if ($FreeSpaceGB -lt $RequiredSpaceGB) {
        Write-Log "Insufficient disk space. Required: $RequiredSpaceGB GB, Available: $([math]::Round($FreeSpaceGB, 2)) GB" -Level Error
        exit 1
    }
    Write-Log "Disk space check passed. Available: $([math]::Round($FreeSpaceGB, 2)) GB" -Level Info

    # ========================================
    # INSTALLATION
    # ========================================

    Write-Log "Beginning installation..." -Level Info

    # Example for EXE installer
    if ($InstallerFileName -match '\.exe$') {
        Write-Log "Running EXE installer: $InstallerPath $InstallerArgs" -Level Info
        $Process = Start-Process -FilePath $InstallerPath -ArgumentList $InstallerArgs -Wait -PassThru -NoNewWindow
        $ExitCode = $Process.ExitCode
    }
    # Example for MSI installer
    elseif ($InstallerFileName -match '\.msi$') {
        Write-Log "Running MSI installer: $InstallerPath" -Level Info
        $MSIArgs = "/i `"$InstallerPath`" /qn /norestart /L*v `"$LogPath\MSI-Install-$AppName.log`""
        $Process = Start-Process -FilePath "msiexec.exe" -ArgumentList $MSIArgs -Wait -PassThru -NoNewWindow
        $ExitCode = $Process.ExitCode
    }
    else {
        Write-Log "Unsupported installer type: $InstallerFileName" -Level Error
        exit 1
    }

    # Check installation result
    Write-Log "Installation process completed with exit code: $ExitCode" -Level Info

    # Common exit codes
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
        default {
            Write-Log "Installation failed with exit code: $ExitCode" -Level Error
            exit $ExitCode
        }
    }

    # ========================================
    # POST-INSTALLATION TASKS
    # ========================================

    # Example: Verify installation
    Start-Sleep -Seconds 5  # Give the installer time to complete

    <#
    $InstalledApp = Get-ItemProperty -Path "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*" |
                    Where-Object { $_.DisplayName -like "*$AppName*" }

    if ($InstalledApp) {
        Write-Log "Installation verified. Application found in registry." -Level Info
    } else {
        Write-Log "Warning: Application not found in registry after installation" -Level Warning
    }
    #>

    # Example: Create shortcuts, configure settings, etc.
    # Add your custom post-installation tasks here

    Write-Log "========================================" -Level Info
    Write-Log "Installation of $AppName completed successfully" -Level Info
    Write-Log "========================================" -Level Info

    exit $ExitCode
}
catch {
    Write-Log "Fatal error during installation: $_" -Level Error
    Write-Log "Stack trace: $($_.ScriptStackTrace)" -Level Error
    exit 1
}
