#Requires -RunAsAdministrator

$Host.UI.RawUI.WindowTitle = "UWF Management (Safe Edition)"

function Test-UWFSupported {
    $os = Get-CimInstance Win32_OperatingSystem
    if ($os.Caption -match "Enterprise|Education|IoT") { return $true }
    Write-Host "[!] Edition: $($os.Caption)" -ForegroundColor Yellow
    Write-Host "    UWF only supports Enterprise / Education / IoT Enterprise." -ForegroundColor Red
    return $false
}

function Test-UWFInstalled {
    return (Test-Path "$env:SystemRoot\System32\uwfmgr.exe")
}

function Invoke-Uwf {
    param([string]$Arguments, [string]$SuccessMsg)
    $out = & uwfmgr.exe $Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[✗] Command failed: uwfmgr $Arguments" -ForegroundColor Red
        Write-Host "    $out" -ForegroundColor DarkRed
        return $false
    }
    Write-Host "[✓] $SuccessMsg" -ForegroundColor Green
    return $true
}

function Get-UWFEnabledState {
    if (-not (Test-UWFInstalled)) { return $null }
    $raw = & uwfmgr.exe filter get-config 2>&1 | Out-String
    if ($raw -match "Filter state:\s*ON")  { return "ON" }
    if ($raw -match "Filter state:\s*OFF") { return "OFF" }
    return "UNKNOWN"
}

function Show-UWFStatus {
    if (-not (Test-UWFInstalled)) {
        Write-Host "[!] UWF is not installed." -ForegroundColor Red
        return
    }
    Write-Host "`n--- Filter Config ---" -ForegroundColor Cyan
    & uwfmgr.exe filter get-config
    Write-Host "`n--- Volume C: Config ---" -ForegroundColor Cyan
    & uwfmgr.exe volume get-config C:
}

function Install-UWF {
    if (-not (Test-UWFSupported)) { return }
    Write-Host "`n[?] Install Unified Write Filter?" -ForegroundColor Yellow
    if ((Read-Host "Continue? (Y/N)") -ne 'Y') { return }

    try {
        $r = Enable-WindowsOptionalFeature -Online -FeatureName "Client-UnifiedWriteFilter" -All -NoRestart -ErrorAction Stop
        if ($r.RestartNeeded) {
            Write-Host "[✓] Installed. RESTART required." -ForegroundColor Green
        } else {
            Write-Host "[✓] Done (already present)." -ForegroundColor Green
        }
    } catch {
        Write-Host "[✗] Install failed: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "    Check: Edition = Enterprise/Edu/IoT? Internet/files available?" -ForegroundColor Gray
    }
}

function Enable-UWF {
    if (-not (Test-UWFSupported)) { return }
    if (-not (Test-UWFInstalled)) {
        Write-Host "[✗] UWF not installed. Run option 1 first." -ForegroundColor Red
        return
    }

    $state = Get-UWFEnabledState
    if ($state -eq "ON") {
        Write-Host "[i] UWF is already ENABLED (pending reboot or active)." -ForegroundColor Yellow
    }

    Write-Host "`n[!] WARNING: Enabling UWF + protecting C: means ALL changes" -ForegroundColor Red
    Write-Host "    to C: will be DISCARDED after every restart." -ForegroundColor Red
    Write-Host "    Save all work and back up important files first." -ForegroundColor Yellow
    if ((Read-Host "Type ENABLE to confirm") -ne 'ENABLE') { return }

    if (-not (Invoke-Uwf "filter enable" "Filter enable scheduled.")) { return }
    if (-not (Invoke-Uwf "volume protect C:" "C: protection scheduled.")) { return }

    Write-Host "`n[!] RESTART required. Use option 5." -ForegroundColor Yellow
}

function Disable-UWF {
    if (-not (Test-UWFInstalled)) {
        Write-Host "[✗] UWF not installed." -ForegroundColor Red
        return
    }

    # نمایش وضعیت فعلی
    $state = Get-UWFEnabledState
    Write-Host "`n--- Current UWF state: $state ---" -ForegroundColor Cyan

    if ($state -eq "OFF") {
        Write-Host "[i] UWF is already DISABLED (or disabled pending reboot)." -ForegroundColor Yellow
        Write-Host "    If you just disabled it, restart to apply." -ForegroundColor Gray
    }

    Write-Host "`n[!] Disabling UWF will stop protecting C:." -ForegroundColor Red
    Write-Host "    Changes to C: will be PERMANENT after restart." -ForegroundColor Red
    Write-Host "    A RESTART is required to apply the change." -ForegroundColor Yellow
    if ((Read-Host "Type DISABLE to confirm") -ne 'DISABLE') { return }

    if (-not (Invoke-Uwf "filter disable" "Filter disable scheduled.")) { return }

    # بررسی وضعیت پس از اجرا
    $after = Get-UWFEnabledState
    Write-Host "`n[i] State now: $after (change applies after restart)." -ForegroundColor Cyan

    $restart = Read-Host "Restart now? (Y/N)"
    if ($restart -eq 'Y') { Restart-System }
    else {
        Write-Host "[!] Remember to restart later. Until then, C: is still protected." -ForegroundColor Yellow
    }
}

function Restart-System {
    Write-Host "`n[?] Restarting in 15 seconds. Press Ctrl+C to cancel." -ForegroundColor Yellow
    for ($i = 15; $i -gt 0; $i--) {
        Write-Host "`r    $i ..." -NoNewline
        Start-Sleep 1
    }
    Write-Host ""
    Restart-Computer -Force
}

# Main loop
do {
    Clear-Host
    $state = if (Test-UWFInstalled) { Get-UWFEnabledState } else { "N/A" }
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "        UWF Management (Safe)           " -ForegroundColor Cyan
    Write-Host "        State: $state" -ForegroundColor $(if ($state -eq "ON") { "Green" } elseif ($state -eq "OFF") { "Yellow" } else { "Red" })
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  1. Install UWF"
    Write-Host "  2. Enable UWF + Protect C:  [DANGER]"
    Write-Host "  3. Disable UWF"
    Write-Host "  4. Show Status"
    Write-Host "  5. Restart (15s delay)"
    Write-Host "  0. Exit"
    Write-Host "========================================" -ForegroundColor Cyan

    switch (Read-Host "Choice (0-5)") {
        "1" { Install-UWF; Read-Host "Enter" }
        "2" { Enable-UWF; Read-Host "Enter" }
        "3" { Disable-UWF; Read-Host "Enter" }
        "4" { Show-UWFStatus; Read-Host "Enter" }
        "5" { Restart-System }
        "0" { exit }
        default { Write-Host "Invalid." -ForegroundColor Red; Start-Sleep 1 }
    }
} while ($true)
