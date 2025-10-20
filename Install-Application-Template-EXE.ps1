<#
.SYNOPSIS
    Install EXE-based application via Intune

.DESCRIPTION
    Template for installing applications packaged as EXE installers.
    Common silent switches: NSIS (/S), Inno Setup (/VERYSILENT), InstallShield (/s /v"/qn")

.NOTES
    Exit Codes: 0=Success, 1=Failure, 3010=Success with restart required
#>

#Requires -RunAsAdministrator

# ============================================
# CONFIGURATION
# ============================================

$InstallerFileName = "setup.exe"
$InstallerArgs = "/S"  # Customize silent install arguments for your installer

# ============================================
# MAIN
# ============================================

try {
    # Get script directory and installer path
    $ScriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
    $InstallerPath = Join-Path -Path $ScriptPath -ChildPath $InstallerFileName

    # Verify installer exists
    if (-not (Test-Path -Path $InstallerPath)) {
        Write-Error "Installer not found: $InstallerPath"
        exit 1
    }

    Write-Output "Running installer: $InstallerPath $InstallerArgs"

    # Run the installer
    $Process = Start-Process -FilePath $InstallerPath `
                            -ArgumentList $InstallerArgs `
                            -Wait `
                            -PassThru `
                            -NoNewWindow

    $ExitCode = $Process.ExitCode
    Write-Output "Installer exit code: $ExitCode"

    # Handle common exit codes
    switch ($ExitCode) {
        0    { Write-Output "Installation successful"; exit 0 }
        3010 { Write-Output "Installation successful (restart required)"; exit 3010 }
        1641 { Write-Output "Installation successful (restart initiated)"; exit 3010 }
        default { Write-Error "Installation failed with exit code $ExitCode"; exit $ExitCode }
    }
}
catch {
    Write-Error "Installation error: $_"
    exit 1
}
