<#
.SYNOPSIS
    Uninstall EXE-based application via Intune

.DESCRIPTION
    Template for uninstalling applications using EXE uninstallers.
    Finds the app in registry and runs its uninstall string.

.NOTES
    Exit Codes: 0=Success, 1=Failure, 3010=Success with restart required
#>

#Requires -RunAsAdministrator

# ============================================
# CONFIGURATION
# ============================================

$AppName = "ApplicationName"  # Name or partial name to search for in registry
$UninstallArgs = "/S"  # Silent uninstall arguments (leave empty to use registry value)

# ============================================
# FUNCTIONS
# ============================================

function Get-InstalledApplication {
    param([string]$Name)

    $Paths = @(
        "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )

    foreach ($Path in $Paths) {
        $App = Get-ItemProperty -Path $Path -ErrorAction SilentlyContinue |
               Where-Object { $_.DisplayName -like "*$Name*" }
        if ($App) { return $App }
    }
    return $null
}

# ============================================
# MAIN
# ============================================

try {
    # Find the application
    $App = Get-InstalledApplication -Name $AppName

    if (-not $App) {
        Write-Output "Application '$AppName' not found (already uninstalled)"
        exit 0
    }

    Write-Output "Found: $($App.DisplayName) v$($App.DisplayVersion)"

    # Parse uninstall string
    $UninstallString = $App.UninstallString
    if ($UninstallString -match '^"([^"]+)"(.*)$') {
        $UninstallerPath = $Matches[1]
        $RegistryArgs = $Matches[2].Trim()
    } else {
        $UninstallerPath = $UninstallString -replace '(.*\.exe).*', '$1'
        $RegistryArgs = $UninstallString.Replace($UninstallerPath, "").Trim()
    }

    # Use custom args if provided, otherwise use registry args
    $FinalArgs = if ($UninstallArgs) { $UninstallArgs } else { $RegistryArgs }

    Write-Output "Running uninstaller: $UninstallerPath $FinalArgs"

    # Run the uninstaller
    $Process = Start-Process -FilePath $UninstallerPath `
                            -ArgumentList $FinalArgs `
                            -Wait `
                            -PassThru `
                            -NoNewWindow

    $ExitCode = $Process.ExitCode
    Write-Output "Uninstaller exit code: $ExitCode"

    # Handle exit codes
    switch ($ExitCode) {
        0    { Write-Output "Uninstallation successful"; exit 0 }
        3010 { Write-Output "Uninstallation successful (restart required)"; exit 3010 }
        1641 { Write-Output "Uninstallation successful (restart initiated)"; exit 3010 }
        default { Write-Error "Uninstallation failed with exit code $ExitCode"; exit $ExitCode }
    }
}
catch {
    Write-Error "Uninstallation error: $_"
    exit 1
}
