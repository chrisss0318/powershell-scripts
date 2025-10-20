<#
.SYNOPSIS
    Template script for uninstalling MSI-based Windows applications via Microsoft Intune/Company Portal

.DESCRIPTION
    This script template is specifically designed for uninstalling applications that were installed
    via MSI packages. Uses msiexec.exe with standard MSI switches for silent uninstallation.

    MSI uninstallation switches:
    - /x : Uninstall
    - /qn : Quiet mode with no UI
    - /norestart : Do not restart after uninstallation
    - /L*v : Verbose logging

.NOTES
    Author: Template
    Version: 1.0
    Intune Exit Codes:
        0 = Success
        1 = Generic failure
        3010 = Success with restart required

    Common MSI Exit Codes:
        0 = Success
        1603 = Fatal error during uninstallation
        1605 = Product not found
        1618 = Another installation is in progress
        1641 = Installer initiated restart
        3010 = Restart required to complete uninstallation
#>

#Requires -RunAsAdministrator

# ============================================
# CONFIGURATION - CUSTOMIZE THESE VALUES
# ============================================

# Application details
$AppName = "ApplicationName"
$AppPublisher = "Publisher"
$ProductCode = ""  # MSI Product GUID (optional - will auto-detect if not specified)

# MSI uninstallation properties (optional)
$MSIProperties = @(
    "REBOOT=ReallySuppress"  # Suppress reboots
    # Add any custom MSI properties needed for uninstallation
)

# Processes to terminate before uninstall (optional)
$ProcessesToStop = @()  # Example: @("AppProcess", "AppService")

# Folders/files to remove after uninstall (optional)
$PathsToClean = @()  # Example: @("$env:ProgramData\$AppPublisher\$AppName")

# Registry keys to remove after uninstall (optional)
$RegistryKeysToClean = @()  # Example: @("HKLM:\Software\$AppPublisher\$AppName")

# Logging
$LogPath = "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs"
$ScriptLogFile = "$LogPath\Uninstall-$AppName-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
$MSILogFile = "$LogPath\Uninstall-$AppName-MSI-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"

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
    Add-Content -Path $ScriptLogFile -Value $LogEntry

    # Also write to console
    switch ($Level) {
        'Error'   { Write-Error $Message }
        'Warning' { Write-Warning $Message }
        default   { Write-Output $Message }
    }
}

function Get-MSIInstalledApplication {
    param(
        [string]$AppName,
        [string]$ProductCode
    )

    # Search both 64-bit and 32-bit registry locations
    $RegistryPaths = @(
        "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )

    foreach ($Path in $RegistryPaths) {
        # Search by name
        $AppByName = Get-ItemProperty -Path $Path -ErrorAction SilentlyContinue |
                     Where-Object { $_.DisplayName -like "*$AppName*" -and $_.UninstallString -like "*msiexec*" }

        if ($AppByName) {
            return $AppByName
        }

        # Search by product code if provided
        if (-not [string]::IsNullOrEmpty($ProductCode)) {
            $FullPath = $Path.Replace('*', $ProductCode)
            $AppByCode = Get-ItemProperty -Path $FullPath -ErrorAction SilentlyContinue

            if ($AppByCode -and $AppByCode.UninstallString -like "*msiexec*") {
                return $AppByCode
            }
        }
    }

    return $null
}

function Get-ProductCodeFromRegistry {
    param(
        [Parameter(Mandatory=$true)]
        [string]$UninstallString
    )

    # Extract product code from uninstall string
    # Format: MsiExec.exe /X{GUID} or MsiExec.exe /I{GUID}
    if ($UninstallString -match '\{[A-F0-9]{8}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{12}\}') {
        return $Matches[0]
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
    Write-Log "Starting MSI uninstallation of $AppName" -Level Info
    Write-Log "========================================" -Level Info

    # ========================================
    # PRE-UNINSTALLATION CHECKS
    # ========================================

    # Check if application is installed
    $InstalledApp = Get-MSIInstalledApplication -AppName $AppName -ProductCode $ProductCode

    if (-not $InstalledApp) {
        Write-Log "Application '$AppName' is not installed. Nothing to uninstall." -Level Warning
        Write-Log "Desired state (uninstalled) already achieved" -Level Info
        exit 0
    }

    Write-Log "Found installed MSI application: $($InstalledApp.DisplayName)" -Level Info
    Write-Log "Version: $($InstalledApp.DisplayVersion)" -Level Info
    Write-Log "Publisher: $($InstalledApp.Publisher)" -Level Info
    Write-Log "Install Location: $($InstalledApp.InstallLocation)" -Level Info

    # Extract product code if not provided
    if ([string]::IsNullOrEmpty($ProductCode)) {
        $ProductCode = Get-ProductCodeFromRegistry -UninstallString $InstalledApp.UninstallString

        if ([string]::IsNullOrEmpty($ProductCode)) {
            Write-Log "Could not extract product code from uninstall string: $($InstalledApp.UninstallString)" -Level Error
            exit 1
        }

        Write-Log "Product Code extracted: $ProductCode" -Level Info
    } else {
        Write-Log "Using provided Product Code: $ProductCode" -Level Info
    }

    # ========================================
    # STOP RUNNING PROCESSES
    # ========================================

    if ($ProcessesToStop.Count -gt 0) {
        Write-Log "Checking for running processes to terminate..." -Level Info
        Stop-ApplicationProcesses -ProcessNames $ProcessesToStop
    }

    # Check for other MSI installations in progress
    $MsiexecProcesses = Get-Process -Name "msiexec" -ErrorAction SilentlyContinue |
                        Where-Object { $_.MainWindowTitle -ne "" }

    if ($MsiexecProcesses) {
        Write-Log "WARNING: Another Windows Installer process is running. Uninstall may fail." -Level Warning
        Write-Log "Active MSI processes: $($MsiexecProcesses.Count)" -Level Warning
    }

    # ========================================
    # UNINSTALLATION
    # ========================================

    Write-Log "Preparing MSI uninstallation..." -Level Info

    # Build msiexec arguments for uninstallation
    $MSIArgs = @(
        "/x"
        $ProductCode
        "/qn"  # Quiet mode, no UI
        "/norestart"  # Don't restart automatically
        "/L*v"  # Verbose logging
        "`"$MSILogFile`""  # Log file path
    )

    # Add custom properties
    if ($MSIProperties.Count -gt 0) {
        $MSIArgs += $MSIProperties
        Write-Log "MSI Properties: $($MSIProperties -join ' ')" -Level Info
    }

    $ArgumentList = $MSIArgs -join " "
    Write-Log "Executing: msiexec.exe $ArgumentList" -Level Info

    # Execute MSI uninstallation
    $Process = Start-Process -FilePath "msiexec.exe" `
                            -ArgumentList $ArgumentList `
                            -Wait `
                            -PassThru `
                            -NoNewWindow

    $ExitCode = $Process.ExitCode
    Write-Log "MSI uninstallation completed with exit code: $ExitCode" -Level Info

    # Interpret MSI exit codes
    switch ($ExitCode) {
        0 {
            Write-Log "Uninstallation completed successfully" -Level Info
        }
        3010 {
            Write-Log "Uninstallation completed successfully. Restart required." -Level Warning
        }
        1641 {
            Write-Log "Uninstallation completed successfully. Installer initiated restart." -Level Warning
            $ExitCode = 3010  # Normalize to Intune's restart code
        }
        1603 {
            Write-Log "Fatal error during uninstallation. Check MSI log: $MSILogFile" -Level Error
            exit 1603
        }
        1605 {
            Write-Log "Product not found. May already be uninstalled." -Level Warning
            # Treat as success since desired state is achieved
            $ExitCode = 0
        }
        1618 {
            Write-Log "Another installation is already in progress" -Level Error
            exit 1618
        }
        default {
            Write-Log "Uninstallation completed with exit code: $ExitCode. Check MSI log: $MSILogFile" -Level Warning
        }
    }

    # ========================================
    # POST-UNINSTALLATION CLEANUP
    # ========================================

    Write-Log "Waiting for uninstallation to finalize..." -Level Info
    Start-Sleep -Seconds 10  # Allow Windows Installer service to finalize

    # Verify uninstallation
    $StillInstalled = Get-MSIInstalledApplication -AppName $AppName -ProductCode $ProductCode

    if ($StillInstalled) {
        Write-Log "WARNING: Application still appears in registry after uninstallation" -Level Warning
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

    # Display MSI log location
    Write-Log "MSI uninstallation log: $MSILogFile" -Level Info

    Write-Log "========================================" -Level Info
    Write-Log "Uninstallation of $AppName completed successfully" -Level Info
    Write-Log "Script log: $ScriptLogFile" -Level Info
    Write-Log "MSI log: $MSILogFile" -Level Info
    Write-Log "========================================" -Level Info

    exit $ExitCode
}
catch {
    Write-Log "Fatal error during uninstallation: $_" -Level Error
    Write-Log "Stack trace: $($_.ScriptStackTrace)" -Level Error
    Write-Log "Review logs at: $LogPath" -Level Error
    exit 1
}
