<#
.SYNOPSIS
    Usuwa preinstalowane oprogramowanie (bloatware) firmy Dell oraz McAfee.
.DESCRIPTION
    - Wymusza uprawnienia administratora
    - Zatrzymuje usługi i procesy Dell/McAfee
    - Deinstaluje przez winget (najskuteczniejsze), PackageManagement i AppX
    - Czyści typowe foldery i klucze rejestru
    - Loguje wszystko na pulpit
.NOTES
    Wymaga PowerShell 5.1+ oraz Windows 10/11.
    Po zakończeniu zalecany jest restart.
#>

[CmdletBinding()]
param (
    [switch]$LogToDesktop = $true,
    [switch]$RemoveLeftovers = $true   # czyści foldery i rejestr
)

#region --- Uprawnienia administratora ---
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Warning "Skrypt wymaga uprawnień administratora. Uruchom PowerShell jako Administrator."
    break
}
#endregion

#region --- Logowanie ---
$LogPath = $null
if ($LogToDesktop) {
    $Desktop = [Environment]::GetFolderPath('Desktop')
    $LogPath = Join-Path -Path $Desktop -ChildPath ("DellCleanup_Log_{0:yyyyMMdd_HHmmss}.txt" -f (Get-Date))
    Start-Transcript -Path $LogPath -Force | Out-Null
}
#endregion

Write-Host "`n=== Rozpoczynam czyszczenie systemu z oprogramowania Dell / McAfee ===" -ForegroundColor Cyan
Write-Host "Data: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor DarkGray

#region --- 1. Zatrzymanie usług i procesów ---
$ServicesToStop = @(
    'SupportAssistAgent',
    'DDVDataCollector',
    'DDVRuleProcessor',
    'DDVTerminator',
    'DellClientManagementService',
    'Dell.TechHub',
    'Dell.TechHub.Instrumentation.SubAgent',
    'Dell.TechHub.Analytics.SubAgent',
    'DellHardwareSupport',
    'McAfeeFramework',
    'McAfeeEngineService',
    'McAfeeAPService',
    'mfefire',
    'mfevtp'
)

Write-Host "`n[1/5] Zatrzymywanie usług..." -ForegroundColor Yellow
foreach ($svc in $ServicesToStop) {
    $service = Get-Service -Name $svc -ErrorAction SilentlyContinue
    if ($service -and $service.Status -ne 'Stopped') {
        try {
            Stop-Service -Name $svc -Force -ErrorAction Stop
            Write-Host "  ✓ Zatrzymano: $svc" -ForegroundColor Green
        } catch {
            Write-Host "  ✗ Nie udało się zatrzymać: $svc ($($_.Exception.Message))" -ForegroundColor DarkYellow
        }
    }
}

Write-Host "`n[2/5] Zatrzymywanie procesów..." -ForegroundColor Yellow
$ProcessPatterns = @('SupportAssist*', 'Dell*', 'McAfee*', 'mfemms*', 'mfevt*', 'ModuleCoreService*', 'PEFService*')
foreach ($pattern in $ProcessPatterns) {
    Get-Process -Name $pattern -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            Stop-Process -Id $_.Id -Force -ErrorAction Stop
            Write-Host "  ✓ Zabito: $($_.ProcessName) (PID $($_.Id))" -ForegroundColor Green
        } catch {
            Write-Host "  ✗ Nie udało się zabić: $($_.ProcessName)" -ForegroundColor DarkYellow
        }
    }
}
#endregion

#region --- 2. Deinstalacja przez winget (najlepsza metoda) ---
Write-Host "`n[3/5] Deinstalacja przez winget..." -ForegroundColor Yellow

$WingetPackages = @(
    'Dell.SupportAssist',
    'Dell.Optimizer',
    'Dell.DigitalDelivery',
    'Dell.Update',
    'Dell.CommandUpdate',
    'Dell.CommandMonitor',
    'Dell.PowerManager',
    'Dell.CoreServices',
    'McAfee.Security',
    'McAfee.WebAdvisor',
    'McAfee.LiveSafe',
    'McAfee.TotalProtection'
)

# Sprawdź czy winget jest dostępny
$winget = Get-Command winget -ErrorAction SilentlyContinue
if ($winget) {
    foreach ($pkg in $WingetPackages) {
        Write-Host "  Sprawdzam: $pkg" -NoNewline
        $list = winget list --id $pkg --exact 2>$null
        if ($LASTEXITCODE -eq 0 -and $list -match $pkg) {
            Write-Host " → odinstalowuję..." -ForegroundColor White
            winget uninstall --id $pkg --exact --silent --force --accept-source-agreements 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) {
                Write-Host "    ✓ Sukces" -ForegroundColor Green
            } else {
                Write-Host "    ✗ Błąd (kod $LASTEXITCODE)" -ForegroundColor Red
            }
        } else {
            Write-Host " → nie znaleziono" -ForegroundColor DarkGray
        }
    }
} else {
    Write-Host "  winget niedostępny – pomijam tę metodę" -ForegroundColor DarkYellow
}
#endregion

#region --- 3. Deinstalacja przez PackageManagement + AppX ---
Write-Host "`n[4/5] Deinstalacja przez PackageManagement i AppX..." -ForegroundColor Yellow

$NamePatterns = @(
    '*Dell SupportAssist*',
    '*Dell Optimizer*',
    '*Dell Digital Delivery*',
    '*Dell Update*',
    '*Dell Command*',
    '*Dell Power Manager*',
    '*Dell Core Services*',
    '*McAfee*',
    '*WebAdvisor*',
    '*MyDell*'
)

# Klasyczne pakiety (MSI / EXE zarejestrowane w PackageManagement)
foreach ($pattern in $NamePatterns) {
    $packages = Get-Package -Name $pattern -ErrorAction SilentlyContinue
    foreach ($pkg in $packages) {
        Write-Host "  Znaleziono (Package): $($pkg.Name) v$($pkg.Version)" -ForegroundColor White
        try {
            Uninstall-Package -InputObject $pkg -Force -ErrorAction Stop | Out-Null
            Write-Host "    ✓ Odinstalowano" -ForegroundColor Green
        } catch {
            Write-Host "    ✗ Błąd: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
}

# Aplikacje AppX / UWP (często SupportAssist, Optimizer)
$AppXPatterns = @(
    '*Dell*',
    '*McAfee*',
    '*WebAdvisor*'
)

foreach ($pattern in $AppXPatterns) {
    $apps = Get-AppxPackage -Name $pattern -AllUsers -ErrorAction SilentlyContinue
    foreach ($app in $apps) {
        Write-Host "  Znaleziono (AppX): $($app.Name)" -ForegroundColor White
        try {
            Remove-AppxPackage -Package $app.PackageFullName -AllUsers -ErrorAction Stop
            Write-Host "    ✓ Usunięto AppX" -ForegroundColor Green
        } catch {
            # Próba bez -AllUsers
            try {
                Remove-AppxPackage -Package $app.PackageFullName -ErrorAction Stop
                Write-Host "    ✓ Usunięto AppX (bieżący użytkownik)" -ForegroundColor Green
            } catch {
                Write-Host "    ✗ Błąd AppX: $($_.Exception.Message)" -ForegroundColor Red
            }
        }
    }
}
#endregion

#region --- 4. Czyszczenie pozostałości (foldery + rejestr) ---
if ($RemoveLeftovers) {
    Write-Host "`n[5/5] Czyszczenie pozostałości..." -ForegroundColor Yellow

    $FoldersToRemove = @(
        "$env:ProgramFiles\Dell",
        "$env:ProgramFiles(x86)\Dell",
        "$env:ProgramFiles\McAfee",
        "$env:ProgramFiles(x86)\McAfee",
        "$env:ProgramData\Dell",
        "$env:ProgramData\McAfee",
        "$env:LOCALAPPDATA\Dell",
        "$env:LOCALAPPDATA\McAfee",
        "$env:APPDATA\Dell",
        "$env:APPDATA\McAfee"
    )

    foreach ($folder in $FoldersToRemove) {
        if (Test-Path $folder) {
            try {
                Remove-Item -Path $folder -Recurse -Force -ErrorAction Stop
                Write-Host "  ✓ Usunięto folder: $folder" -ForegroundColor Green
            } catch {
                Write-Host "  ✗ Nie udało się usunąć: $folder ($($_.Exception.Message))" -ForegroundColor DarkYellow
            }
        }
    }

    # Klucze rejestru (najczęstsze)
    $RegKeys = @(
        'HKLM:\SOFTWARE\Dell',
        'HKLM:\SOFTWARE\WOW6432Node\Dell',
        'HKLM:\SOFTWARE\McAfee',
        'HKLM:\SOFTWARE\WOW6432Node\McAfee',
        'HKCU:\SOFTWARE\Dell',
        'HKCU:\SOFTWARE\McAfee'
    )

    foreach ($key in $RegKeys) {
        if (Test-Path $key) {
            try {
                Remove-Item -Path $key -Recurse -Force -ErrorAction Stop
                Write-Host "  ✓ Usunięto klucz: $key" -ForegroundColor Green
            } catch {
                Write-Host "  ✗ Nie udało się usunąć klucza: $key" -ForegroundColor DarkYellow
            }
        }
    }
}
#endregion

#region --- Zakończenie ---
Write-Host "`n=== Czyszczenie zakończone ===" -ForegroundColor Cyan

if ($LogToDesktop -and $LogPath) {
    Stop-Transcript | Out-Null
    Write-Host "Log zapisano w: $LogPath" -ForegroundColor Cyan
}

Write-Host "`nZalecane jest PONOWNE URUCHOMIENIE komputera!" -ForegroundColor Yellow
Write-Host "Po restarcie możesz jeszcze raz uruchomić skrypt, aby usunąć ewentualne pozostałości." -ForegroundColor DarkGray
#endregion
