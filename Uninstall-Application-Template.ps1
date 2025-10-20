<#
.SYNOPSIS
    Template script for uninstalling Windows applications via Microsoft Intune/Company Portal

.DESCRIPTION
    This script template provides a framework for uninstalling applications through Intune.
    Customize the variables and uninstallation logic for your specific application.

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

# Uninstallation details
$UninstallString = ""  # Can be auto-detected or specified
$UninstallArgs = "/S /quiet"  # Customize for your installer type

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

# ============================================
# MAIN UNINSTALLATION LOGIC
# ============================================

try {
    Write-Log "========================================" -Level Info
    Write-Log "Starting uninstallation of $AppName" -Level Info
    Write-Log "========================================" -Level Info

    # ========================================
    # PRE-UNINSTALLATION CHECKS
    # ========================================

    # Check if application is installed
    $InstalledApp = Get-InstalledApplication -AppName $AppName

    if (-not $InstalledApp) {
        Write-Log "Application '$AppName' is not installed. Nothing to uninstall." -Level Warning
        exit 0  # Exit successfully as the desired state (uninstalled) is already achieved
    }

    Write-Log "Found installed application: $($InstalledApp.DisplayName)" -Level Info
    Write-Log "Version: $($InstalledApp.DisplayVersion)" -Level Info
    Write-Log "Publisher: $($InstalledApp.Publisher)" -Level Info

    # Get uninstall string from registry if not manually specified
    if ([string]::IsNullOrEmpty($UninstallString)) {
        $UninstallString = $InstalledApp.UninstallString

        if ([string]::IsNullOrEmpty($UninstallString)) {
            Write-Log "No uninstall string found in registry" -Level Error
            exit 1
        }

        Write-Log "Uninstall string from registry: $UninstallString" -Level Info
    }

    # ========================================
    # STOP RUNNING PROCESSES (if needed)
    # ========================================

    # Example: Stop application processes before uninstalling
    <#
    $ProcessNames = @("ApplicationProcess1", "ApplicationProcess2")
    foreach ($ProcessName in $ProcessNames) {
        $RunningProcesses = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue
        if ($RunningProcesses) {
            Write-Log "Stopping process: $ProcessName" -Level Warning
            $RunningProcesses | Stop-Process -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 2
        }
    }
    #>

    # ========================================
    # UNINSTALLATION
    # ========================================

    Write-Log "Beginning uninstallation..." -Level Info

    # Determine uninstaller type and execute
    if ($UninstallString -match 'msiexec') {
        # MSI uninstallation
        Write-Log "Detected MSI installer" -Level Info

        # Extract product code from uninstall string
        if ($UninstallString -match '\{[A-F0-9\-]+\}') {
            $ProductCode = $Matches[0]
            Write-Log "Product Code: $ProductCode" -Level Info

            $MSIArgs = "/x $ProductCode /qn /norestart /L*v `"$LogPath\MSI-Uninstall-$AppName.log`""
            Write-Log "Running: msiexec.exe $MSIArgs" -Level Info

            $Process = Start-Process -FilePath "msiexec.exe" -ArgumentList $MSIArgs -Wait -PassThru -NoNewWindow
            $ExitCode = $Process.ExitCode
        }
        else {
            Write-Log "Could not extract product code from uninstall string" -Level Error
            exit 1
        }
    }
    elseif ($UninstallString -match '\.exe') {
        # EXE uninstallation
        Write-Log "Detected EXE installer" -Level Info

        # Parse the uninstall string
        # Handle quoted paths
        if ($UninstallString -match '^"([^"]+)"(.*)$') {
            $UninstallerPath = $Matches[1]
            $ExistingArgs = $Matches[2].Trim()
        }
        else {
            $UninstallerPath = $UninstallString.Split(' ')[0]
            $ExistingArgs = $UninstallString.Substring($UninstallerPath.Length).Trim()
        }

        # Verify uninstaller exists
        if (-not (Test-Path -Path $UninstallerPath)) {
            Write-Log "Uninstaller not found at: $UninstallerPath" -Level Error
            exit 1
        }

        # Combine arguments (prefer custom args if specified, otherwise use existing)
        $FinalArgs = if ([string]::IsNullOrEmpty($UninstallArgs)) { $ExistingArgs } else { $UninstallArgs }

        Write-Log "Running: $UninstallerPath $FinalArgs" -Level Info
        $Process = Start-Process -FilePath $UninstallerPath -ArgumentList $FinalArgs -Wait -PassThru -NoNewWindow
        $ExitCode = $Process.ExitCode
    }
    else {
        Write-Log "Unsupported uninstaller type: $UninstallString" -Level Error
        exit 1
    }

    # Check uninstallation result
    Write-Log "Uninstallation process completed with exit code: $ExitCode" -Level Info

    # Common exit codes
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
        default {
            Write-Log "Uninstallation failed with exit code: $ExitCode" -Level Error
            exit $ExitCode
        }
    }

    # ========================================
    # POST-UNINSTALLATION TASKS
    # ========================================

    # Give the uninstaller time to complete
    Start-Sleep -Seconds 5

    # Verify uninstallation
    $StillInstalled = Get-InstalledApplication -AppName $AppName

    if ($StillInstalled) {
        Write-Log "Warning: Application still appears in registry after uninstallation" -Level Warning
    } else {
        Write-Log "Uninstallation verified. Application removed from registry." -Level Info
    }

    # Example: Remove leftover files/folders
    <#
    $AppDataPath = "$env:ProgramData\$AppPublisher\$AppName"
    if (Test-Path -Path $AppDataPath) {
        Write-Log "Removing application data: $AppDataPath" -Level Info
        Remove-Item -Path $AppDataPath -Recurse -Force -ErrorAction SilentlyContinue
    }
    #>

    # Example: Remove registry keys
    <#
    $RegistryPath = "HKLM:\Software\$AppPublisher\$AppName"
    if (Test-Path -Path $RegistryPath) {
        Write-Log "Removing registry key: $RegistryPath" -Level Info
        Remove-Item -Path $RegistryPath -Recurse -Force -ErrorAction SilentlyContinue
    }
    #>

    Write-Log "========================================" -Level Info
    Write-Log "Uninstallation of $AppName completed successfully" -Level Info
    Write-Log "========================================" -Level Info

    exit $ExitCode
}
catch {
    Write-Log "Fatal error during uninstallation: $_" -Level Error
    Write-Log "Stack trace: $($_.ScriptStackTrace)" -Level Error
    exit 1
}
