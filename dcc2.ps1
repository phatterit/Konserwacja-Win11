<#
.SYNOPSIS
    Usuwa preinstalowane oprogramowanie (bloatware) firmy Dell oraz McAfee.
.DESCRIPTION
    - Wymusza uprawnienia administratora
    - Zatrzymuje uslugi, procesy i zaplanowane zadania
    - Deinstaluje przez winget, PackageManagement i AppX
    - Czysci foldery, klucze rejestru i autostart
    - Loguje wszystko na pulpit
.NOTES
    Wymaga PowerShell 5.1+ oraz Windows 10/11.
    Po zakonczeniu zalecany jest restart.
#>

[CmdletBinding()]
param (
    [switch]$LogToDesktop = $true,
    [switch]$RemoveLeftovers = $true
)

#region --- Uprawnienia administratora ---
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Warning "Skrypt wymaga uprawnien administratora. Uruchom PowerShell jako Administrator."
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

#region --- 1. Zatrzymanie uslug ---
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
    'DellOptimizer',
    'DellOptimizerCore',
    'McAfeeFramework',
    'McAfeeEngineService',
    'McAfeeAPService',
    'mfefire',
    'mfevtp',
    'ModuleCoreService'
)

Write-Host "`n[1/6] Zatrzymywanie uslug..." -ForegroundColor Yellow
foreach ($svc in $ServicesToStop) {
    $service = Get-Service -Name $svc -ErrorAction SilentlyContinue
    if ($service -and $service.Status -ne 'Stopped') {
        try {
            Stop-Service -Name $svc -Force -ErrorAction Stop
            Write-Host "  v Zatrzymano: $svc" -ForegroundColor Green
        } catch {
            Write-Host "  x Nie udalo sie zatrzymac: $svc" -ForegroundColor DarkYellow
        }
    }
}
#endregion

#region --- 2. Zatrzymanie procesow ---
Write-Host "`n[2/6] Zatrzymywanie procesow..." -ForegroundColor Yellow
$ProcessPatterns = @(
    'SupportAssist*', 'Dell*', 'McAfee*', 'mfemms*', 'mfevt*',
    'ModuleCoreService*', 'PEFService*', 'DDV*', 'DSA*', 'Optimizer*'
)
foreach ($pattern in $ProcessPatterns) {
    Get-Process -Name $pattern -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            Stop-Process -Id $_.Id -Force -ErrorAction Stop
            Write-Host "  v Zabito: $($_.ProcessName) (PID $($_.Id))" -ForegroundColor Green
        } catch {
            Write-Host "  x Nie udalo sie zabic: $($_.ProcessName)" -ForegroundColor DarkYellow
        }
    }
}
#endregion

#region --- 3. Usuwanie zaplanowanych zadan ---
Write-Host "`n[3/6] Usuwanie zaplanowanych zadan Dell/McAfee..." -ForegroundColor Yellow
$TaskPatterns = @('*Dell*', '*SupportAssist*', '*Optimizer*', '*McAfee*', '*WebAdvisor*', '*Pair*')
foreach ($pattern in $TaskPatterns) {
    Get-ScheduledTask -TaskName $pattern -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            Unregister-ScheduledTask -TaskName $_.TaskName -Confirm:$false -ErrorAction Stop
            Write-Host "  v Usunieto zadanie: $($_.TaskName)" -ForegroundColor Green
        } catch {
            Write-Host "  x Nie udalo sie usunac zadania: $($_.TaskName)" -ForegroundColor DarkYellow
        }
    }
}
#endregion

#region --- 4. Deinstalacja przez winget ---
Write-Host "`n[4/6] Deinstalacja przez winget..." -ForegroundColor Yellow

$WingetPackages = @(
    # --- Dell ---
    'Dell.SupportAssist',
    'Dell.Optimizer',
    'Dell.DigitalDelivery',
    'Dell.Update',
    'Dell.CommandUpdate',
    'Dell.CommandMonitor',
    'Dell.PowerManager',
    'Dell.CoreServices',
    'Dell.MyDell',
    'Dell.Pair',
    'Dell.DisplayManager',
    'Dell.PeripheralManager',
    'Dell.MobileConnect',
    # --- McAfee ---
    'McAfee.Security',
    'McAfee.WebAdvisor',
    'McAfee.LiveSafe',
    'McAfee.TotalProtection'
)

$winget = Get-Command winget -ErrorAction SilentlyContinue
if ($winget) {
    winget source update --disable-interactivity 2>$null | Out-Null

    foreach ($pkg in $WingetPackages) {
        Write-Host "  Sprawdzam: $pkg" -NoNewline
        $listOutput = winget list --id $pkg --exact --accept-source-agreements 2>$null
        $isInstalled = ($LASTEXITCODE -eq 0) -and ($listOutput -match [regex]::Escape($pkg))

        if ($isInstalled) {
            Write-Host " -> odinstalowuje..." -ForegroundColor White
            winget uninstall --id $pkg --exact --silent --force `
                --accept-source-agreements --accept-package-agreements 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) {
                Write-Host "    v Sukces" -ForegroundColor Green
            } else {
                Write-Host "    x Blad (kod $LASTEXITCODE)" -ForegroundColor Red
            }
        } else {
            Write-Host " -> nie znaleziono" -ForegroundColor DarkGray
        }
    }

    # Dodatkowe proby po nazwie (gdy ID sie rozni)
    $WingetNames = @(
        'Dell Pair',
        'Dell Core Services',
        'Dell Display and Peripheral Manager',
        'Dell Peripheral Manager',
        'Dell SupportAssist Remediation',
        'MyDell'
    )
    foreach ($name in $WingetNames) {
        Write-Host "  Sprawdzam nazwe: $name" -NoNewline
        $listOutput = winget list --name $name --accept-source-agreements 2>$null
        if ($LASTEXITCODE -eq 0 -and $listOutput -match [regex]::Escape($name)) {
            Write-Host " -> odinstalowuje..." -ForegroundColor White
            winget uninstall --name $name --silent --force `
                --accept-source-agreements --accept-package-agreements 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) {
                Write-Host "    v Sukces" -ForegroundColor Green
            } else {
                Write-Host "    x Blad (kod $LASTEXITCODE)" -ForegroundColor Red
            }
        } else {
            Write-Host " -> nie znaleziono" -ForegroundColor DarkGray
        }
    }
} else {
    Write-Host "  winget niedostepny - pomijam te metode" -ForegroundColor DarkYellow
}
#endregion

#region --- 5. PackageManagement + AppX + specjalne przypadki ---
Write-Host "`n[5/6] Deinstalacja przez PackageManagement, AppX i specjalne deinstalatory..." -ForegroundColor Yellow

$NamePatterns = @(
    '*Dell SupportAssist*',
    '*Dell Optimizer*',
    '*Dell Digital Delivery*',
    '*Dell Update*',
    '*Dell Command*',
    '*Dell Power Manager*',
    '*Dell Core Services*',
    '*Dell Pair*',
    '*Dell Display*',
    '*Dell Peripheral*',
    '*Dell Mobile Connect*',
    '*Dell Customer Connect*',
    '*MyDell*',
    '*SupportAssist Remediation*',
    '*McAfee*',
    '*WebAdvisor*'
)

foreach ($pattern in $NamePatterns) {
    $packages = Get-Package -Name $pattern -ErrorAction SilentlyContinue
    foreach ($pkg in $packages) {
        Write-Host "  Znaleziono (Package): $($pkg.Name) v$($pkg.Version)" -ForegroundColor White
        try {
            Uninstall-Package -InputObject $pkg -Force -ErrorAction Stop | Out-Null
            Write-Host "    v Odinstalowano" -ForegroundColor Green
        } catch {
            Write-Host "    x Blad: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
}

# AppX (UWP)
$AppXPatterns = @(
    '*Dell*',
    '*McAfee*',
    '*WebAdvisor*',
    '*MyDell*'
)
foreach ($pattern in $AppXPatterns) {
    $apps = @()
    $apps += Get-AppxPackage -Name $pattern -ErrorAction SilentlyContinue
    $apps += Get-AppxPackage -Name $pattern -AllUsers -ErrorAction SilentlyContinue
    $apps = $apps | Sort-Object -Property PackageFullName -Unique

    foreach ($app in $apps) {
        Write-Host "  Znaleziono (AppX): $($app.Name)" -ForegroundColor White
        try {
            Remove-AppxPackage -Package $app.PackageFullName -ErrorAction Stop
            Write-Host "    v Usunieto AppX" -ForegroundColor Green
        } catch {
            try {
                Remove-AppxPackage -Package $app.PackageFullName -AllUsers -ErrorAction Stop
                Write-Host "    v Usunieto AppX (AllUsers)" -ForegroundColor Green
            } catch {
                Write-Host "    x Blad AppX: $($_.Exception.Message)" -ForegroundColor Red
            }
        }
    }
}

# Specjalny przypadek: Dell Pair (oficjalny cichy deinstalator)
$DellPairUninstaller = "${env:ProgramFiles}\Dell\Dell Pair\Uninstall.exe"
if (Test-Path $DellPairUninstaller) {
    Write-Host "  Znaleziono Dell Pair - uruchamiam oficjalny deinstalator..." -ForegroundColor White
    try {
        Start-Process -FilePath $DellPairUninstaller -ArgumentList '/S' -Wait -NoNewWindow -ErrorAction Stop
        Write-Host "    v Dell Pair odinstalowany" -ForegroundColor Green
    } catch {
        Write-Host "    x Blad deinstalacji Dell Pair: $($_.Exception.Message)" -ForegroundColor Red
    }
}
#endregion

#region --- 6. Czyszczenie pozostalosci ---
if ($RemoveLeftovers) {
    Write-Host "`n[6/6] Czyszczenie pozostalosci (foldery, rejestr, autostart)..." -ForegroundColor Yellow

    $FoldersToRemove = @(
        "$env:ProgramFiles\Dell\SupportAssist",
        "$env:ProgramFiles\Dell\DellOptimizer",
        "$env:ProgramFiles\Dell\UpdateService",
        "$env:ProgramFiles\Dell\Dell Pair",
        "$env:ProgramFiles\Dell\CoreServices",
        "$env:ProgramFiles\Dell\DisplayManager",
        "$env:ProgramFiles\Dell\Peripheral Manager",
        "${env:ProgramFiles(x86)}\Dell\SupportAssistAgent",
        "${env:ProgramFiles(x86)}\Dell\CommandUpdate",
        "${env:ProgramFiles(x86)}\Dell\Dell Pair",
        "$env:ProgramFiles\McAfee",
        "${env:ProgramFiles(x86)}\McAfee",
        "$env:ProgramData\Dell\SupportAssist",
        "$env:ProgramData\Dell\UpdateService",
        "$env:ProgramData\Dell\Pair",
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
                Write-Host "  v Usunieto folder: $folder" -ForegroundColor Green
            } catch {
                Write-Host "  x Nie udalo sie usunac: $folder" -ForegroundColor DarkYellow
            }
        }
    }

    $RegKeys = @(
        'HKLM:\SOFTWARE\Dell\SupportAssist',
        'HKLM:\SOFTWARE\Dell\UpdateService',
        'HKLM:\SOFTWARE\Dell\Pair',
        'HKLM:\SOFTWARE\Dell\CoreServices',
        'HKLM:\SOFTWARE\WOW6432Node\Dell\SupportAssist',
        'HKLM:\SOFTWARE\WOW6432Node\Dell\Pair',
        'HKLM:\SOFTWARE\McAfee',
        'HKLM:\SOFTWARE\WOW6432Node\McAfee',
        'HKCU:\SOFTWARE\Dell',
        'HKCU:\SOFTWARE\McAfee'
    )

    foreach ($key in $RegKeys) {
        if (Test-Path $key) {
            try {
                Remove-Item -Path $key -Recurse -Force -ErrorAction Stop
                Write-Host "  v Usunieto klucz: $key" -ForegroundColor Green
            } catch {
                Write-Host "  x Nie udalo sie usunac klucza: $key" -ForegroundColor DarkYellow
            }
        }
    }

    # Autostart
    $RunKeys = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'
    )
    $RunPatterns = @('*Dell*', '*SupportAssist*', '*Optimizer*', '*McAfee*', '*WebAdvisor*', '*Pair*')

    foreach ($runKey in $RunKeys) {
        if (Test-Path $runKey) {
            $props = Get-ItemProperty -Path $runKey -ErrorAction SilentlyContinue
            foreach ($pattern in $RunPatterns) {
                $props.PSObject.Properties | Where-Object {
                    $_.Name -like $pattern -or ($_.Value -and $_.Value -like $pattern)
                } | ForEach-Object {
                    try {
                        Remove-ItemProperty -Path $runKey -Name $_.Name -Force -ErrorAction Stop
                        Write-Host "  v Usunieto autostart: $($_.Name)" -ForegroundColor Green
                    } catch {
                        Write-Host "  x Nie udalo sie usunac autostartu: $($_.Name)" -ForegroundColor DarkYellow
                    }
                }
            }
        }
    }
}
#endregion

#region --- Zakonczenie ---
Write-Host "`n=== Czyszczenie zakonczone ===" -ForegroundColor Cyan

if ($LogToDesktop -and $LogPath) {
    Stop-Transcript | Out-Null
    Write-Host "Log zapisano w: $LogPath" -ForegroundColor Cyan
}

Write-Host "`nZalecane jest PONOWNE URUCHOMIENIE komputera!" -ForegroundColor Yellow
Write-Host "Po restarcie mozesz uruchomic skrypt drugi raz, aby usunac ewentualne pozostalosci." -ForegroundColor DarkGray
#endregion
