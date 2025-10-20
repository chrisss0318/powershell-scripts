<#
.SYNOPSIS
    Template script for installing MSI-based Windows applications via Microsoft Intune/Company Portal

.DESCRIPTION
    This script template is specifically designed for MSI installers deployed through Intune.
    Uses msiexec.exe with standard MSI switches for silent installation.

    Common MSI installation switches:
    - /i : Install
    - /qn : Quiet mode with no UI
    - /norestart : Do not restart after installation
    - /L*v : Verbose logging
    - PROPERTY=VALUE : Set MSI properties

.NOTES
    Author: Template
    Version: 1.0
    Intune Exit Codes:
        0 = Success
        1 = Generic failure
        3010 = Success with restart required

    Common MSI Exit Codes:
        0 = Success
        1603 = Fatal error during installation
        1618 = Another installation is in progress
        1641 = Installer initiated restart
        3010 = Restart required to complete installation
#>

#Requires -RunAsAdministrator

# ============================================
# CONFIGURATION - CUSTOMIZE THESE VALUES
# ============================================

# Application details
$AppName = "ApplicationName"
$AppVersion = "1.0.0"
$AppPublisher = "Publisher"
$ProductCode = ""  # MSI Product GUID (optional - can be auto-detected after install)

# MSI installer details
$MSIFileName = "setup.msi"

# MSI properties (customize as needed)
$MSIProperties = @(
    "ALLUSERS=1"                    # Install for all users
    "REBOOT=ReallySuppress"         # Suppress reboots
    # "INSTALLDIR=`"C:\Custom\Path`""  # Custom installation directory
    # "ADDLOCAL=ALL"                 # Install all features
    # "TRANSFORMS=custom.mst"        # Apply MSI transform file
)

# Logging
$LogPath = "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs"
$ScriptLogFile = "$LogPath\Install-$AppName-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
$MSILogFile = "$LogPath\Install-$AppName-MSI-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"

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
    Add-Content -Path $ScriptLogFile -Value $LogEntry

    # Also write to console
    switch ($Level) {
        'Error'   { Write-Error $Message }
        'Warning' { Write-Warning $Message }
        default   { Write-Output $Message }
    }
}

function Get-MSIProductInfo {
    param(
        [Parameter(Mandatory=$true)]
        [string]$MSIPath
    )

    try {
        $WindowsInstaller = New-Object -ComObject WindowsInstaller.Installer
        $MSIDatabase = $WindowsInstaller.GetType().InvokeMember("OpenDatabase", "InvokeMethod", $null, $WindowsInstaller, @($MSIPath, 0))

        # Query Property table
        $Query = "SELECT * FROM Property"
        $View = $MSIDatabase.GetType().InvokeMember("OpenView", "InvokeMethod", $null, $MSIDatabase, ($Query))
        $View.GetType().InvokeMember("Execute", "InvokeMethod", $null, $View, $null)

        $Properties = @{}

        while ($true) {
            $Record = $View.GetType().InvokeMember("Fetch", "InvokeMethod", $null, $View, $null)
            if ($null -eq $Record) { break }

            $Property = $Record.GetType().InvokeMember("StringData", "GetProperty", $null, $Record, 1)
            $Value = $Record.GetType().InvokeMember("StringData", "GetProperty", $null, $Record, 2)

            $Properties[$Property] = $Value
        }

        return $Properties
    }
    catch {
        Write-Log "Could not read MSI properties: $_" -Level Warning
        return $null
    }
}

function Test-MSIInstalled {
    param(
        [string]$AppName,
        [string]$ProductCode
    )

    # Search registry for installed application
    $RegistryPaths = @(
        "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )

    foreach ($Path in $RegistryPaths) {
        # Search by name
        $AppByName = Get-ItemProperty -Path $Path -ErrorAction SilentlyContinue |
                     Where-Object { $_.DisplayName -like "*$AppName*" }

        if ($AppByName) {
            return $AppByName
        }

        # Search by product code if provided
        if (-not [string]::IsNullOrEmpty($ProductCode)) {
            $AppByCode = Get-ItemProperty -Path "$Path\$ProductCode" -ErrorAction SilentlyContinue
            if ($AppByCode) {
                return $AppByCode
            }
        }
    }

    return $null
}

# ============================================
# MAIN INSTALLATION LOGIC
# ============================================

try {
    Write-Log "========================================" -Level Info
    Write-Log "Starting MSI installation of $AppName $AppVersion" -Level Info
    Write-Log "========================================" -Level Info

    # Get script directory
    $ScriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
    Write-Log "Script path: $ScriptPath" -Level Info

    # ========================================
    # PRE-INSTALLATION CHECKS
    # ========================================

    # Verify MSI file exists
    $MSIPath = Join-Path -Path $ScriptPath -ChildPath $MSIFileName
    if (-not (Test-Path -Path $MSIPath)) {
        Write-Log "MSI file not found at: $MSIPath" -Level Error
        exit 1
    }
    Write-Log "MSI file found: $MSIPath" -Level Info

    # Get MSI file info
    $MSIInfo = Get-Item -Path $MSIPath
    Write-Log "MSI file size: $([math]::Round($MSIInfo.Length / 1MB, 2)) MB" -Level Info

    # Extract MSI properties
    $MSIProps = Get-MSIProductInfo -MSIPath $MSIPath
    if ($MSIProps) {
        Write-Log "MSI Product Name: $($MSIProps['ProductName'])" -Level Info
        Write-Log "MSI Product Version: $($MSIProps['ProductVersion'])" -Level Info
        Write-Log "MSI Product Code: $($MSIProps['ProductCode'])" -Level Info
        Write-Log "MSI Manufacturer: $($MSIProps['Manufacturer'])" -Level Info

        # Save product code for later use
        if ([string]::IsNullOrEmpty($ProductCode)) {
            $ProductCode = $MSIProps['ProductCode']
        }
    }

    # Check if application is already installed
    $ExistingInstall = Test-MSIInstalled -AppName $AppName -ProductCode $ProductCode

    if ($ExistingInstall) {
        Write-Log "Application '$($ExistingInstall.DisplayName)' is already installed" -Level Warning
        Write-Log "Installed version: $($ExistingInstall.DisplayVersion)" -Level Info
        Write-Log "Proceeding with installation (MSI will upgrade if appropriate)" -Level Info
    }

    # Check disk space
    $SystemDrive = $env:SystemDrive
    $FreeSpaceGB = (Get-PSDrive -Name $SystemDrive.Trim(':') | Select-Object -ExpandProperty Free) / 1GB

    if ($FreeSpaceGB -lt $RequiredDiskSpaceGB) {
        Write-Log "Insufficient disk space. Required: $RequiredDiskSpaceGB GB, Available: $([math]::Round($FreeSpaceGB, 2)) GB" -Level Error
        exit 1
    }
    Write-Log "Disk space check passed. Available: $([math]::Round($FreeSpaceGB, 2)) GB" -Level Info

    # Check for pending reboots (MSI installs can fail if reboot is pending)
    $RebootPending = $false
    if (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending") {
        $RebootPending = $true
    }
    if (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired") {
        $RebootPending = $true
    }

    if ($RebootPending) {
        Write-Log "WARNING: System has pending reboot. Installation may fail." -Level Warning
    }

    # ========================================
    # INSTALLATION
    # ========================================

    Write-Log "Preparing MSI installation..." -Level Info

    # Build msiexec arguments
    $MSIArgs = @(
        "/i"
        "`"$MSIPath`""
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

    # Execute MSI installation
    $Process = Start-Process -FilePath "msiexec.exe" `
                            -ArgumentList $ArgumentList `
                            -Wait `
                            -PassThru `
                            -NoNewWindow

    $ExitCode = $Process.ExitCode
    Write-Log "MSI installation completed with exit code: $ExitCode" -Level Info

    # Interpret MSI exit codes
    switch ($ExitCode) {
        0 {
            Write-Log "Installation completed successfully" -Level Info
        }
        3010 {
            Write-Log "Installation completed successfully. Restart required to complete installation." -Level Warning
        }
        1641 {
            Write-Log "Installation completed successfully. Installer initiated restart." -Level Warning
            $ExitCode = 3010  # Normalize to Intune's restart code
        }
        1603 {
            Write-Log "Fatal error during installation. Check MSI log: $MSILogFile" -Level Error
            exit 1603
        }
        1618 {
            Write-Log "Another installation is already in progress" -Level Error
            exit 1618
        }
        1619 {
            Write-Log "MSI package could not be opened" -Level Error
            exit 1619
        }
        1638 {
            Write-Log "Another version of this product is already installed" -Level Error
            exit 1638
        }
        default {
            Write-Log "Installation completed with exit code: $ExitCode. Check MSI log: $MSILogFile" -Level Warning
        }
    }

    # ========================================
    # POST-INSTALLATION VERIFICATION
    # ========================================

    Write-Log "Waiting for installation to finalize..." -Level Info
    Start-Sleep -Seconds 10  # Allow Windows Installer service to finalize

    # Verify installation
    $InstalledApp = Test-MSIInstalled -AppName $AppName -ProductCode $ProductCode

    if ($InstalledApp) {
        Write-Log "Installation verification PASSED" -Level Info
        Write-Log "Installed: $($InstalledApp.DisplayName)" -Level Info
        Write-Log "Version: $($InstalledApp.DisplayVersion)" -Level Info
        Write-Log "Install Location: $($InstalledApp.InstallLocation)" -Level Info
        Write-Log "Uninstall String: $($InstalledApp.UninstallString)" -Level Info
    } else {
        Write-Log "Installation verification FAILED - Application not found in registry" -Level Error

        # Don't fail if installer returned success
        if ($ExitCode -eq 0 -or $ExitCode -eq 3010) {
            Write-Log "Installer reported success despite detection failure - proceeding" -Level Warning
        } else {
            Write-Log "Review MSI log file: $MSILogFile" -Level Error
            exit 1
        }
    }

    # Display MSI log location
    Write-Log "MSI installation log: $MSILogFile" -Level Info

    # ========================================
    # POST-INSTALLATION TASKS (Optional)
    # ========================================

    # Example: Configure application via registry
    <#
    $RegPath = "HKLM:\Software\$AppPublisher\$AppName"
    if (-not (Test-Path -Path $RegPath)) {
        New-Item -Path $RegPath -Force | Out-Null
    }
    Set-ItemProperty -Path $RegPath -Name "ConfigSetting" -Value "Value"
    Write-Log "Applied post-installation registry settings" -Level Info
    #>

    # Example: Copy configuration files
    <#
    $SourceConfig = Join-Path -Path $ScriptPath -ChildPath "config.xml"
    $DestConfig = "$env:ProgramData\$AppPublisher\$AppName\config.xml"
    if (Test-Path -Path $SourceConfig) {
        Copy-Item -Path $SourceConfig -Destination $DestConfig -Force
        Write-Log "Copied configuration file to $DestConfig" -Level Info
    }
    #>

    Write-Log "========================================" -Level Info
    Write-Log "Installation of $AppName completed successfully" -Level Info
    Write-Log "Script log: $ScriptLogFile" -Level Info
    Write-Log "MSI log: $MSILogFile" -Level Info
    Write-Log "========================================" -Level Info

    exit $ExitCode
}
catch {
    Write-Log "Fatal error during installation: $_" -Level Error
    Write-Log "Stack trace: $($_.ScriptStackTrace)" -Level Error
    Write-Log "Review logs at: $LogPath" -Level Error
    exit 1
}
