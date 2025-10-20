<#
.SYNOPSIS
    Uninstall MSI-based application via Intune

.DESCRIPTION
    Template for uninstalling MSI applications.
    Finds the product code in registry and uses msiexec /x to uninstall.

.NOTES
    Exit Codes: 0=Success, 1=Failure, 3010=Success with restart required
#>

#Requires -RunAsAdministrator

# ============================================
# CONFIGURATION
# ============================================

$AppName = "ApplicationName"  # Name or partial name to search for in registry
$ProductCode = ""  # Optional: Specify GUID directly, e.g., "{12345678-1234-1234-1234-123456789012}"

# Logging
$LogPath = "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs"
$MSILogFile = "$LogPath\MSI-Uninstall-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"

# ============================================
# MAIN
# ============================================

try {
    # Find the application in registry
    $Paths = @(
        "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )

    $App = $null
    foreach ($Path in $Paths) {
        $App = Get-ItemProperty -Path $Path -ErrorAction SilentlyContinue |
               Where-Object { $_.DisplayName -like "*$AppName*" -and $_.UninstallString -like "*msiexec*" }
        if ($App) { break }
    }

    if (-not $App) {
        Write-Output "Application '$AppName' not found (already uninstalled)"
        exit 0
    }

    Write-Output "Found: $($App.DisplayName) v$($App.DisplayVersion)"

    # Extract product code if not provided
    if (-not $ProductCode) {
        if ($App.UninstallString -match '\{[A-F0-9\-]{36}\}') {
            $ProductCode = $Matches[0]
        } else {
            Write-Error "Could not extract product code"
            exit 1
        }
    }

    # Create log directory
    if (-not (Test-Path -Path $LogPath)) {
        New-Item -Path $LogPath -ItemType Directory -Force | Out-Null
    }

    # Build msiexec arguments
    $MSIArgs = @("/x", $ProductCode, "/qn", "/norestart", "/L*v", "`"$MSILogFile`"")

    Write-Output "Running: msiexec.exe $($MSIArgs -join ' ')"

    # Run msiexec
    $Process = Start-Process -FilePath "msiexec.exe" `
                            -ArgumentList $MSIArgs `
                            -Wait `
                            -PassThru `
                            -NoNewWindow

    $ExitCode = $Process.ExitCode
    Write-Output "MSI exit code: $ExitCode | Log: $MSILogFile"

    # Handle MSI exit codes
    switch ($ExitCode) {
        0    { Write-Output "Uninstallation successful"; exit 0 }
        1605 { Write-Output "Product not found (already uninstalled)"; exit 0 }
        3010 { Write-Output "Uninstallation successful (restart required)"; exit 3010 }
        1641 { Write-Output "Uninstallation successful (restart initiated)"; exit 3010 }
        1603 { Write-Error "Fatal uninstallation error (see log)"; exit 1603 }
        default { Write-Error "Uninstallation failed with exit code $ExitCode (see log)"; exit $ExitCode }
    }
}
catch {
    Write-Error "Uninstallation error: $_"
    exit 1
}
