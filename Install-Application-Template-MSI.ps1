<#
.SYNOPSIS
    Install MSI-based application via Intune

.DESCRIPTION
    Template for installing applications packaged as MSI installers.
    Uses msiexec.exe with standard silent installation switches.

.NOTES
    Exit Codes: 0=Success, 1=Failure, 3010=Success with restart required
#>

#Requires -RunAsAdministrator

# ============================================
# CONFIGURATION
# ============================================

$MSIFileName = "setup.msi"

# MSI properties (customize as needed)
$MSIProperties = @(
    "ALLUSERS=1"
    "REBOOT=ReallySuppress"
)

# Logging
$LogPath = "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs"
$MSILogFile = "$LogPath\MSI-Install-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"

# ============================================
# MAIN
# ============================================

try {
    # Get script directory and MSI path
    $ScriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
    $MSIPath = Join-Path -Path $ScriptPath -ChildPath $MSIFileName

    # Verify MSI exists
    if (-not (Test-Path -Path $MSIPath)) {
        Write-Error "MSI not found: $MSIPath"
        exit 1
    }

    # Create log directory
    if (-not (Test-Path -Path $LogPath)) {
        New-Item -Path $LogPath -ItemType Directory -Force | Out-Null
    }

    Write-Output "Installing MSI: $MSIPath"

    # Build msiexec arguments
    $MSIArgs = @(
        "/i", "`"$MSIPath`""
        "/qn"
        "/norestart"
        "/L*v", "`"$MSILogFile`""
    ) + $MSIProperties

    # Run msiexec
    $Process = Start-Process -FilePath "msiexec.exe" `
                            -ArgumentList $MSIArgs `
                            -Wait `
                            -PassThru `
                            -NoNewWindow

    $ExitCode = $Process.ExitCode
    Write-Output "MSI exit code: $ExitCode"
    Write-Output "MSI log: $MSILogFile"

    # Handle MSI exit codes
    switch ($ExitCode) {
        0    { Write-Output "Installation successful"; exit 0 }
        3010 { Write-Output "Installation successful (restart required)"; exit 3010 }
        1641 { Write-Output "Installation successful (restart initiated)"; exit 3010 }
        1603 { Write-Error "Fatal installation error (see log)"; exit 1603 }
        1618 { Write-Error "Another installation in progress"; exit 1618 }
        default { Write-Error "Installation failed with exit code $ExitCode (see log)"; exit $ExitCode }
    }
}
catch {
    Write-Error "Installation error: $_"
    exit 1
}
