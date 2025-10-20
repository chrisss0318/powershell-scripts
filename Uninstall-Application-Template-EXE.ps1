<#
.SYNOPSIS
    Template script for uninstalling EXE-based Windows applications via Microsoft Intune/Company Portal

.DESCRIPTION
    This script template is specifically designed for uninstalling applications that were installed
    via EXE installers. It retrieves the uninstall string from the registry and executes it.

    Common EXE uninstaller switches:
    - NSIS: /S (silent uninstall)
    - Inno Setup: /VERYSILENT /SUPPRESSMSGBOXES /NORESTART
    - InstallShield: /s /x /v"/qn"
    - WiX Burn: /uninstall /quiet /norestart

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
$AppPublisher = "Publisher"

# Uninstaller details
$UninstallArgs = "/S"  # Customize for your EXE uninstaller (see examples above)
$UseRegistryUninstallString = $true  # If true, uses UninstallString from registry; if false, uses custom path below
$CustomUninstallerPath = ""  # Only used if UseRegistryUninstallString is false

# Processes to terminate before uninstall (optional)
$ProcessesToStop = @()  # Example: @("AppProcess", "AppService")

# Folders/files to remove after uninstall (optional)
$PathsToClean = @()  # Example: @("$env:ProgramData\$AppPublisher\$AppName", "$env:LOCALAPPDATA\$AppName")

# Registry keys to remove after uninstall (optional)
$RegistryKeysToClean = @()  # Example: @("HKLM:\Software\$AppPublisher\$AppName")

# Logging
$LogPath = "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs"
$LogFile = "$LogPath\Uninstall-$AppName-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"

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

function Get-InstalledApplication {
    param(
        [Parameter(Mandatory=$true)]
        [string]$AppName
    )

    # Search both 64-bit and 32-bit registry locations
    $RegistryPaths = @(
        "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )

    foreach ($Path in $RegistryPaths) {
        $App = Get-ItemProperty -Path $Path -ErrorAction SilentlyContinue |
               Where-Object { $_.DisplayName -like "*$AppName*" }

        if ($App) {
            return $App
        }
    }

    return $null
}

function Stop-ApplicationProcesses {
    param(
        [Parameter(Mandatory=$true)]
        [array]$ProcessNames
    )

    foreach ($ProcessName in $ProcessNames) {
        $RunningProcesses = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue

        if ($RunningProcesses) {
            Write-Log "Stopping process: $ProcessName (PID: $($RunningProcesses.Id -join ', '))" -Level Warning

            try {
                $RunningProcesses | Stop-Process -Force -ErrorAction Stop
                Start-Sleep -Seconds 2
                Write-Log "Process $ProcessName stopped successfully" -Level Info
            }
            catch {
                Write-Log "Failed to stop process $ProcessName : $_" -Level Error
            }
        }
    }
}

function Remove-LeftoverPaths {
    param(
        [Parameter(Mandatory=$true)]
        [array]$Paths
    )

    foreach ($Path in $Paths) {
        # Expand environment variables
        $ExpandedPath = [System.Environment]::ExpandEnvironmentVariables($Path)

        if (Test-Path -Path $ExpandedPath) {
            Write-Log "Removing leftover path: $ExpandedPath" -Level Info

            try {
                Remove-Item -Path $ExpandedPath -Recurse -Force -ErrorAction Stop
                Write-Log "Successfully removed: $ExpandedPath" -Level Info
            }
            catch {
                Write-Log "Failed to remove $ExpandedPath : $_" -Level Warning
            }
        }
    }
}

function Remove-LeftoverRegistry {
    param(
        [Parameter(Mandatory=$true)]
        [array]$RegistryPaths
    )

    foreach ($RegPath in $RegistryPaths) {
        if (Test-Path -Path $RegPath) {
            Write-Log "Removing registry key: $RegPath" -Level Info

            try {
                Remove-Item -Path $RegPath -Recurse -Force -ErrorAction Stop
                Write-Log "Successfully removed registry key: $RegPath" -Level Info
            }
            catch {
                Write-Log "Failed to remove registry key $RegPath : $_" -Level Warning
            }
        }
    }
}

# ============================================
# MAIN UNINSTALLATION LOGIC
# ============================================

try {
    Write-Log "========================================" -Level Info
    Write-Log "Starting EXE uninstallation of $AppName" -Level Info
    Write-Log "========================================" -Level Info

    # ========================================
    # PRE-UNINSTALLATION CHECKS
    # ========================================

    # Check if application is installed
    $InstalledApp = Get-InstalledApplication -AppName $AppName

    if (-not $InstalledApp) {
        Write-Log "Application '$AppName' is not installed. Nothing to uninstall." -Level Warning
        Write-Log "Desired state (uninstalled) already achieved" -Level Info
        exit 0
    }

    Write-Log "Found installed application: $($InstalledApp.DisplayName)" -Level Info
    Write-Log "Version: $($InstalledApp.DisplayVersion)" -Level Info
    Write-Log "Publisher: $($InstalledApp.Publisher)" -Level Info
    Write-Log "Install Location: $($InstalledApp.InstallLocation)" -Level Info

    # ========================================
    # STOP RUNNING PROCESSES
    # ========================================

    if ($ProcessesToStop.Count -gt 0) {
        Write-Log "Checking for running processes to terminate..." -Level Info
        Stop-ApplicationProcesses -ProcessNames $ProcessesToStop
    }

    # ========================================
    # DETERMINE UNINSTALLER PATH
    # ========================================

    if ($UseRegistryUninstallString) {
        $UninstallString = $InstalledApp.UninstallString

        if ([string]::IsNullOrEmpty($UninstallString)) {
            Write-Log "No uninstall string found in registry" -Level Error
            exit 1
        }

        Write-Log "Uninstall string from registry: $UninstallString" -Level Info

        # Parse the uninstall string
        # Handle quoted paths: "C:\Path\uninstall.exe" /args
        if ($UninstallString -match '^"([^"]+)"(.*)$') {
            $UninstallerPath = $Matches[1]
            $RegistryArgs = $Matches[2].Trim()
        }
        # Handle unquoted paths: C:\Path\uninstall.exe /args
        elseif ($UninstallString -match '^([^\s]+)(.*)$') {
            $UninstallerPath = $Matches[1]
            $RegistryArgs = $Matches[2].Trim()
        }
        else {
            $UninstallerPath = $UninstallString
            $RegistryArgs = ""
        }

        Write-Log "Parsed uninstaller path: $UninstallerPath" -Level Info
        Write-Log "Parsed registry arguments: $RegistryArgs" -Level Info

        # Use custom args if specified, otherwise use registry args
        if ([string]::IsNullOrEmpty($UninstallArgs)) {
            $FinalArgs = $RegistryArgs
        } else {
            $FinalArgs = $UninstallArgs
            Write-Log "Using custom uninstall arguments instead of registry arguments" -Level Info
        }
    }
    else {
        # Use custom uninstaller path
        $UninstallerPath = [System.Environment]::ExpandEnvironmentVariables($CustomUninstallerPath)
        $FinalArgs = $UninstallArgs

        Write-Log "Using custom uninstaller path: $UninstallerPath" -Level Info
    }

    # Verify uninstaller exists
    if (-not (Test-Path -Path $UninstallerPath)) {
        Write-Log "Uninstaller not found at: $UninstallerPath" -Level Error
        exit 1
    }

    Write-Log "Uninstaller found: $UninstallerPath" -Level Info

    # ========================================
    # UNINSTALLATION
    # ========================================

    Write-Log "Executing EXE uninstaller..." -Level Info
    Write-Log "Command: $UninstallerPath $FinalArgs" -Level Info

    # Execute the uninstaller
    $Process = Start-Process -FilePath $UninstallerPath `
                            -ArgumentList $FinalArgs `
                            -Wait `
                            -PassThru `
                            -NoNewWindow

    $ExitCode = $Process.ExitCode
    Write-Log "EXE uninstaller completed with exit code: $ExitCode" -Level Info

    # Interpret exit codes (common for EXE installers)
    switch ($ExitCode) {
        0 {
            Write-Log "Uninstallation completed successfully" -Level Info
        }
        3010 {
            Write-Log "Uninstallation completed successfully. Restart required." -Level Warning
        }
        1641 {
            Write-Log "Uninstallation completed successfully. Installer initiated restart." -Level Warning
            $ExitCode = 3010
        }
        1602 {
            Write-Log "Uninstallation was cancelled by user" -Level Warning
        }
        1603 {
            Write-Log "Fatal error during uninstallation" -Level Error
        }
        default {
            Write-Log "Uninstallation completed with exit code: $ExitCode" -Level Warning
        }
    }

    # ========================================
    # POST-UNINSTALLATION CLEANUP
    # ========================================

    Write-Log "Waiting for uninstallation to complete..." -Level Info
    Start-Sleep -Seconds 10

    # Verify uninstallation
    $StillInstalled = Get-InstalledApplication -AppName $AppName

    if ($StillInstalled) {
        Write-Log "WARNING: Application still appears in registry after uninstallation" -Level Warning
        Write-Log "This may be normal for some installers" -Level Info
    } else {
        Write-Log "Uninstallation verified. Application removed from registry." -Level Info
    }

    # Clean up leftover files/folders
    if ($PathsToClean.Count -gt 0) {
        Write-Log "Cleaning up leftover files and folders..." -Level Info
        Remove-LeftoverPaths -Paths $PathsToClean
    }

    # Clean up leftover registry keys
    if ($RegistryKeysToClean.Count -gt 0) {
        Write-Log "Cleaning up leftover registry keys..." -Level Info
        Remove-LeftoverRegistry -RegistryPaths $RegistryKeysToClean
    }

    Write-Log "========================================" -Level Info
    Write-Log "Uninstallation of $AppName completed successfully" -Level Info
    Write-Log "Log file: $LogFile" -Level Info
    Write-Log "========================================" -Level Info

    exit $ExitCode
}
catch {
    Write-Log "Fatal error during uninstallation: $_" -Level Error
    Write-Log "Stack trace: $($_.ScriptStackTrace)" -Level Error
    exit 1
}
