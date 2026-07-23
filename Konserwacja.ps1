<#
.SYNOPSIS
    Zaawansowany skrypt konserwacji i czyszczenia systemu Windows 11.
.DESCRIPTION
    Czyści temp, cache Update, DNS, Sklep MS, Kosz + DISM + SFC.
    Obsługuje tryb interaktywny (-Menu) oraz parametry -Skip*.
.EXAMPLE
    .\Konserwacja.ps1 -Menu
.EXAMPLE
    .\Konserwacja.ps1 -SkipDISM -SkipSFC
#>

#Requires -Version 5.1
#Requires -RunAsAdministrator

[CmdletBinding()]
param (
    [switch]$SkipTemp,
    [switch]$SkipUpdateCache,
    [switch]$SkipStoreReset,
    [switch]$SkipDISM,
    [switch]$SkipSFC,
    [switch]$Menu
)

$ScriptVersion = "1.2.0"

$InformationPreference = 'Continue'
$script:ExitCode = 0

# --- FUNKCJE POMOCNICZE ---
function Write-Step    { param([string]$Text) Write-Information "`n$Text" }
function Write-Info    { param([string]$Text) Write-Information " -> $Text" }
function Write-Success { param([string]$Text) Write-Information " -> [OK] $Text" }
function Write-Warn    { param([string]$Text) Write-Warning " -> $Text" }
function Write-Err     { param([string]$Text) Write-Error " [!] $Text" }

function Invoke-Dism {
    param([string]$Arguments)
    $proc = Start-Process -FilePath "dism.exe" -ArgumentList $Arguments -Wait -NoNewWindow -PassThru
    return $proc.ExitCode
}

function Invoke-DismOutput {
    param([string]$Arguments)
    Write-Information ""
    dism.exe $Arguments.Split()
}

function Clear-Folder {
    param([string]$Path)
    if (Test-Path -LiteralPath $Path) {
        Write-Info "Skanowanie: $Path"
        $items = Get-ChildItem -LiteralPath $Path -Force -ErrorAction SilentlyContinue
        if ($items) {
            Write-Info "Wykryto $($items.Count) elementów. Usuwanie..."
            $err = $null
            $items | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue -ErrorVariable err
            if ($err) {
                Write-Warn "Część plików ($($err.Count)) nie mogła zostać usunięta."
            } else {
                Write-Success "Wyczyszczono zawartość $Path."
            }
        } else {
            Write-Info "Folder jest już pusty."
        }
    }
}

# --- MENU INTERAKTYWNE ---
if ($Menu -or (-not ($PSBoundParameters.ContainsKey('SkipTemp') -or 
                     $PSBoundParameters.ContainsKey('SkipUpdateCache') -or 
                     $PSBoundParameters.ContainsKey('SkipStoreReset') -or 
                     $PSBoundParameters.ContainsKey('SkipDISM') -or 
                     $PSBoundParameters.ContainsKey('SkipSFC')))) {
    
    Clear-Host
    Write-Information "=== Konserwacja Windows 11 v$ScriptVersion ===`n"
    Write-Information "Wybierz operacje, które chcesz wykonać (wpisz numery):`n"

    Write-Information "1 → Czyszczenie plików tymczasowych (Temp)"
    Write-Information "2 → Czyszczenie cache Windows Update"
    Write-Information "3 → Czyszczenie DNS, Kosz i Sklep MS"
    Write-Information "4 → DISM (czyszczenie + naprawa)"
    Write-Information "5 → SFC /scannow"
    Write-Information ""
    Write-Information "9 → Wykonaj WSZYSTKIE operacje"
    Write-Information "0 → Anuluj`n"
    
    $choice = Read-Host "Wpisz numery (np. 1 2 3 lub 9)"

    if ($choice -eq "0" -or [string]::IsNullOrWhiteSpace($choice)) {
        Write-Warn "Anulowano uruchomienie skryptu."
        exit 0
    }

    if ($choice -eq "9") {
        Write-Info "Wybrano: Wszystkie operacje"
        # nic nie skipujemy
    }
    else {
        $selected = $choice -split '\s+' | Where-Object { $_ -ne '' } | ForEach-Object { $_.Trim() }
        
        $SkipTemp         = $selected -notcontains "1"
        $SkipUpdateCache  = $selected -notcontains "2"
        $SkipStoreReset   = $selected -notcontains "3"
        $SkipDISM         = $selected -notcontains "4"
        $SkipSFC          = $selected -notcontains "5"

        Write-Info "Wybrane operacje: $($selected -join ', ')"
    }
}

# --- INICJALIZACJA LOGOWANIA ---
$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
$timeStamp = (Get-Date).ToString('yyyy-MM-dd_HH-mm-ss')
$desktopPath = [Environment]::GetFolderPath('Desktop')
$logPath = Join-Path $desktopPath "Konserwacja_$timeStamp.log"

try {
    Start-Transcript -Path $logPath -Force -ErrorAction Stop
} catch {
    Write-Warn "Nie można uruchomić transkrypcji logów."
}

Register-EngineEvent PowerShell.Exiting -Action { Stop-Transcript -ErrorAction SilentlyContinue } | Out-Null

# --- PODSUMOWANIE OPERACJI ---
Write-Information "=== Zaawansowana konserwacja systemu Windows 11 ==="
Write-Info "Wersja skryptu: $ScriptVersion"
Write-Info "Data uruchomienia: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"

Write-Information "`n--- Wybrane operacje ---"
Write-Info "1. Czyszczenie Temp:          $(if ($SkipTemp) { '❌ POMINIĘTE' } else { '✅ WYKONANE' })"
Write-Info "2. Cache Windows Update:      $(if ($SkipUpdateCache) { '❌ POMINIĘTE' } else { '✅ WYKONANE' })"
Write-Info "3. DNS + Kosz + Sklep:        $(if ($SkipStoreReset) { '❌ POMINIĘTE' } else { '✅ WYKONANE' })"
Write-Info "4. DISM:                      $(if ($SkipDISM) { '❌ POMINIĘTE' } else { '✅ WYKONANE' })"
Write-Info "5. SFC:                       $(if ($SkipSFC) { '❌ POMINIĘTE' } else { '✅ WYKONANE' })"
Write-Information "-------------------------------------"

# --- GŁÓWNA LOGIKA SKRYPTU ---
try {
    if (-not $SkipTemp) {
        Write-Step "[1/5] Czyszczenie plików tymczasowych..."
        Clear-Folder -Path $env:TEMP
        Clear-Folder -Path "C:\Windows\Temp"
    } else {
        Write-Step "[1/5] [POMINIĘTO] Czyszczenie Temp"
    }

    if (-not $SkipUpdateCache) {
        Write-Step "[2/5] Czyszczenie cache Windows Update..."
        $updateServices = @('wuauserv', 'bits', 'cryptsvc')
        try {
            Write-Info "Zatrzymywanie usług..."
            Stop-Service -Name $updateServices -Force -ErrorAction Stop
            Start-Sleep -Seconds 2

            $sdPath = "C:\Windows\SoftwareDistribution"
            if (Test-Path $sdPath) {
                $sdItems = Get-ChildItem -Path $sdPath -Exclude "DataStore", "ReportingEvents" -Force -ErrorAction SilentlyContinue
                if ($sdItems) {
                    $sdItems | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
                    Write-Success "Cache Windows Update wyczyszczony."
                }
            }
        }
        catch {
            Write-Err "Błąd podczas czyszczenia cache aktualizacji: $_"
            $script:ExitCode = 1
        }
        finally {
            Write-Info "Wznawianie usług..."
            Start-Service -Name $updateServices -ErrorAction SilentlyContinue
        }
    } else {
        Write-Step "[2/5] [POMINIĘTO] Czyszczenie cache Windows Update"
    }

    if (-not $SkipStoreReset) {
        Write-Step "[3/5] Czyszczenie DNS, Kosza i Sklepu MS..."
        Clear-DnsClientCache
        Write-Success "Cache DNS wyczyszczony."

        try {
            Clear-RecycleBin -Force -ErrorAction Stop
            Write-Success "Kosz opróżniony."
        } catch {
            Write-Info "Kosz jest już pusty lub nie można go opróżnić."
        }

        Write-Info "Resetowanie cache Sklepu MS..."
        $storeProc = Start-Process "wsreset.exe" -Wait -NoNewWindow -PassThru
        if ($storeProc.ExitCode -eq 0) {
            Write-Success "Cache Sklepu zresetowany."
        }
    } else {
        Write-Step "[3/5] [POMINIĘTO] Czyszczenie DNS/Kosz/Sklep"
    }

    if (-not $SkipDISM) {
        Write-Step "[4/5] Operacje DISM..."
        Invoke-DismOutput "/online /cleanup-image /startcomponentcleanup"
        Invoke-DismOutput "/online /cleanup-image /analyzecomponentstore"

        Write-Info "Sprawdzanie stanu obrazu..."
        Invoke-DismOutput "/online /cleanup-image /scanhealth"
        $scanExit = Invoke-Dism "/online /cleanup-image /scanhealth"

        if ($scanExit -ne 0) {
            Write-Info "Wykryto problemy - uruchamianie naprawy..."
            $restoreExit = Invoke-Dism "/online /cleanup-image /restorehealth"
            if ($restoreExit -notin 0, 3010) {
                $script:ExitCode = 1
            }
        }
    } else {
        Write-Step "[4/5] [POMINIĘTO] Operacje DISM"
    }

    if (-not $SkipSFC) {
        Write-Step "[5/5] Skanowanie plików systemowych (SFC)..."
        $sfcProc = Start-Process -FilePath "sfc.exe" -ArgumentList "/scannow" -Wait -NoNewWindow -PassThru
        switch ($sfcProc.ExitCode) {
            0 { Write-Success "SFC: System jest w dobrym stanie." }
            1 { Write-Success "SFC: Uszkodzenia zostały naprawione." }
            2 { Write-Err "SFC: Niektóre uszkodzenia nie mogły zostać naprawione."; $script:ExitCode = 1 }
            default { Write-Warn "SFC zakończone kodem $($sfcProc.ExitCode)." }
        }
    } else {
        Write-Step "[5/5] [POMINIĘTO] Skanowanie SFC"
    }

    Write-Information "`n=== Konserwacja zakończona pomyślnie! ==="
    if (-not $SkipDISM -or -not $SkipSFC) {
        Write-Information "`n[!] Zalecany restart komputera po naprawach DISM/SFC."
    }
}
finally {
    $stopwatch.Stop()
    Write-Info "Czas wykonania: $($stopwatch.Elapsed.ToString('hh\:mm\:ss'))"
    try { Stop-Transcript -ErrorAction SilentlyContinue } catch {}
}

exit $script:ExitCode# --- MENU INTERAKTYWNE ---
if ($Menu -or (-not ($PSBoundParameters.ContainsKey('SkipTemp') -or 
                     $PSBoundParameters.ContainsKey('SkipUpdateCache') -or 
                     $PSBoundParameters.ContainsKey('SkipStoreReset') -or 
                     $PSBoundParameters.ContainsKey('SkipDISM') -or 
                     $PSBoundParameters.ContainsKey('SkipSFC')))) {
    
    Clear-Host
    Write-Information "=== Konserwacja Windows 11 v$ScriptVersion ===`n"
    Write-Information "Wybierz operacje, które chcesz wykonać (wpisz numery):`n"

    Write-Information "1 → Czyszczenie plików tymczasowych"
    Write-Information "2 → Czyszczenie cache Windows Update"
    Write-Information "3 → DNS + Kosz + Sklep MS"
    Write-Information "4 → DISM (czyszczenie i naprawa)"
    Write-Information "5 → SFC /scannow"
    Write-Information ""
    Write-Information "9 → WSZYSTKO"
    Write-Information "0 → Anuluj`n"

    $choice = Read-Host "Wpisz numery (np. 1 2 3 lub 9)"

    if ($choice -eq "0" -or [string]::IsNullOrWhiteSpace($choice)) {
        Write-Warn "Anulowano uruchomienie skryptu."
        exit 0
    }

    if ($choice -eq "9") {
        Write-Info "Wybrano: Wszystkie operacje"
        # nic nie skipujemy
    }
    else {
        $selected = $choice -split '\s+' | Where-Object { $_ -ne '' } | ForEach-Object { $_.Trim() }
        
        $SkipTemp         = $selected -notcontains "1"
        $SkipUpdateCache  = $selected -notcontains "2"
        $SkipStoreReset   = $selected -notcontains "3"
        $SkipDISM         = $selected -notcontains "4"
        $SkipSFC          = $selected -notcontains "5"

        Write-Info "Wybrane operacje: $($selected -join ', ')"
    }
}<#
.SYNOPSIS
    Zaawansowany skrypt konserwacji i czyszczenia systemu Windows 11.
.DESCRIPTION
    Czyści temp, cache Update, DNS, Sklep MS, Kosz + DISM + SFC.
    Obsługuje tryb interaktywny (-Menu) oraz parametry -Skip*.
.EXAMPLE
    .\Konserwacja.ps1 -Menu
.EXAMPLE
    .\Konserwacja.ps1 -SkipDISM -SkipSFC
#>

#Requires -Version 5.1
#Requires -RunAsAdministrator

[CmdletBinding()]
param (
    [switch]$SkipTemp,
    [switch]$SkipUpdateCache,
    [switch]$SkipStoreReset,
    [switch]$SkipDISM,
    [switch]$SkipSFC,
    [switch]$Menu
)

$ScriptVersion = "1.2.0"

$InformationPreference = 'Continue'
$script:ExitCode = 0

# --- FUNKCJE POMOCNICZE ---
function Write-Step    { param([string]$Text) Write-Information "`n$Text" }
function Write-Info    { param([string]$Text) Write-Information " -> $Text" }
function Write-Success { param([string]$Text) Write-Information " -> [OK] $Text" }
function Write-Warn    { param([string]$Text) Write-Warning " -> $Text" }
function Write-Err     { param([string]$Text) Write-Error " [!] $Text" }

function Invoke-Dism {
    param([string]$Arguments)
    $proc = Start-Process -FilePath "dism.exe" -ArgumentList $Arguments -Wait -NoNewWindow -PassThru
    return $proc.ExitCode
}

function Invoke-DismOutput {
    param([string]$Arguments)
    Write-Information ""
    dism.exe $Arguments.Split()
}

function Clear-Folder {
    param([string]$Path)
    if (Test-Path -LiteralPath $Path) {
        Write-Info "Skanowanie: $Path"
        $items = Get-ChildItem -LiteralPath $Path -Force -ErrorAction SilentlyContinue
        if ($items) {
            Write-Info "Wykryto $($items.Count) elementów. Usuwanie..."
            $err = $null
            $items | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue -ErrorVariable err
            if ($err) {
                Write-Warn "Część plików ($($err.Count)) nie mogła zostać usunięta."
            } else {
                Write-Success "Wyczyszczono zawartość $Path."
            }
        } else {
            Write-Info "Folder jest już pusty."
        }
    }
}

# --- MENU INTERAKTYWNE ---
if ($Menu -or (-not ($PSBoundParameters.ContainsKey('SkipTemp') -or 
                     $PSBoundParameters.ContainsKey('SkipUpdateCache') -or 
                     $PSBoundParameters.ContainsKey('SkipStoreReset') -or 
                     $PSBoundParameters.ContainsKey('SkipDISM') -or 
                     $PSBoundParameters.ContainsKey('SkipSFC')))) {
    
    Clear-Host
    Write-Information "=== Konserwacja Windows 11 v$ScriptVersion ===`n"
    Write-Information "Wybierz operacje, które chcesz wykonać (wpisz numery oddzielone spacją):`n"

    $menuOptions = @{
        "1" = "Czyszczenie plików tymczasowych (Temp)"
        "2" = "Czyszczenie cache Windows Update"
        "3" = "Czyszczenie DNS, Kosz i Reset Sklepu MS"
        "4" = "DISM - czyszczenie i naprawa obrazu"
        "5" = "SFC /scannow"
    }

    foreach ($key in $menuOptions.Keys | Sort-Object) {
        Write-Information "$key → $($menuOptions[$key])"
    }

    Write-Information "`nwszystko → Wykonaj wszystkie operacje"
    Write-Information "puste    → Anuluj`n"

    $choice = Read-Host "Twój wybór"

    if ([string]::IsNullOrWhiteSpace($choice)) {
        Write-Warn "Anulowano uruchomienie skryptu."
        exit 0
    }

    if ($choice -like "*wszystko*") {
        # Wszystkie operacje włączone (żadne Skip nie jest ustawione)
    }
    else {
        $selected = $choice -split '\s+' | ForEach-Object { $_.Trim() }
        if ($selected -notcontains "1") { $SkipTemp = $true }
        if ($selected -notcontains "2") { $SkipUpdateCache = $true }
        if ($selected -notcontains "3") { $SkipStoreReset = $true }
        if ($selected -notcontains "4") { $SkipDISM = $true }
        if ($selected -notcontains "5") { $SkipSFC = $true }
    }
}

# --- INICJALIZACJA LOGOWANIA ---
$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
$timeStamp = (Get-Date).ToString('yyyy-MM-dd_HH-mm-ss')
$desktopPath = [Environment]::GetFolderPath('Desktop')
$logPath = Join-Path $desktopPath "Konserwacja_$timeStamp.log"

try {
    Start-Transcript -Path $logPath -Force -ErrorAction Stop
} catch {
    Write-Warn "Nie można uruchomić transkrypcji logów."
}

Register-EngineEvent PowerShell.Exiting -Action { Stop-Transcript -ErrorAction SilentlyContinue } | Out-Null

# --- PODSUMOWANIE OPERACJI ---
Write-Information "=== Zaawansowana konserwacja systemu Windows 11 ==="
Write-Info "Wersja skryptu: $ScriptVersion"
Write-Info "Data uruchomienia: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"

Write-Information "`n--- Wybrane operacje ---"
Write-Info "1. Czyszczenie Temp:          $(if ($SkipTemp) { '❌ POMINIĘTE' } else { '✅ WYKONANE' })"
Write-Info "2. Cache Windows Update:      $(if ($SkipUpdateCache) { '❌ POMINIĘTE' } else { '✅ WYKONANE' })"
Write-Info "3. DNS + Kosz + Sklep:        $(if ($SkipStoreReset) { '❌ POMINIĘTE' } else { '✅ WYKONANE' })"
Write-Info "4. DISM:                      $(if ($SkipDISM) { '❌ POMINIĘTE' } else { '✅ WYKONANE' })"
Write-Info "5. SFC:                       $(if ($SkipSFC) { '❌ POMINIĘTE' } else { '✅ WYKONANE' })"
Write-Information "-------------------------------------"

# --- GŁÓWNA LOGIKA SKRYPTU ---
try {
    if (-not $SkipTemp) {
        Write-Step "[1/5] Czyszczenie plików tymczasowych..."
        Clear-Folder -Path $env:TEMP
        Clear-Folder -Path "C:\Windows\Temp"
    } else {
        Write-Step "[1/5] [POMINIĘTO] Czyszczenie Temp"
    }

    if (-not $SkipUpdateCache) {
        Write-Step "[2/5] Czyszczenie cache Windows Update..."
        $updateServices = @('wuauserv', 'bits', 'cryptsvc')
        try {
            Write-Info "Zatrzymywanie usług..."
            Stop-Service -Name $updateServices -Force -ErrorAction Stop
            Start-Sleep -Seconds 2

            $sdPath = "C:\Windows\SoftwareDistribution"
            if (Test-Path $sdPath) {
                $sdItems = Get-ChildItem -Path $sdPath -Exclude "DataStore", "ReportingEvents" -Force -ErrorAction SilentlyContinue
                if ($sdItems) {
                    $sdItems | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
                    Write-Success "Cache Windows Update wyczyszczony."
                }
            }
        }
        catch {
            Write-Err "Błąd podczas czyszczenia cache aktualizacji: $_"
            $script:ExitCode = 1
        }
        finally {
            Write-Info "Wznawianie usług..."
            Start-Service -Name $updateServices -ErrorAction SilentlyContinue
        }
    } else {
        Write-Step "[2/5] [POMINIĘTO] Czyszczenie cache Windows Update"
    }

    if (-not $SkipStoreReset) {
        Write-Step "[3/5] Czyszczenie DNS, Kosza i Sklepu MS..."
        Clear-DnsClientCache
        Write-Success "Cache DNS wyczyszczony."

        try {
            Clear-RecycleBin -Force -ErrorAction Stop
            Write-Success "Kosz opróżniony."
        } catch {
            Write-Info "Kosz jest już pusty lub nie można go opróżnić."
        }

        Write-Info "Resetowanie cache Sklepu MS..."
        $storeProc = Start-Process "wsreset.exe" -Wait -NoNewWindow -PassThru
        if ($storeProc.ExitCode -eq 0) {
            Write-Success "Cache Sklepu zresetowany."
        }
    } else {
        Write-Step "[3/5] [POMINIĘTO] Czyszczenie DNS/Kosz/Sklep"
    }

    if (-not $SkipDISM) {
        Write-Step "[4/5] Operacje DISM..."
        Invoke-DismOutput "/online /cleanup-image /startcomponentcleanup"
        Invoke-DismOutput "/online /cleanup-image /analyzecomponentstore"

        Write-Info "Sprawdzanie stanu obrazu..."
        Invoke-DismOutput "/online /cleanup-image /scanhealth"
        $scanExit = Invoke-Dism "/online /cleanup-image /scanhealth"

        if ($scanExit -ne 0) {
            Write-Info "Wykryto problemy - uruchamianie naprawy..."
            $restoreExit = Invoke-Dism "/online /cleanup-image /restorehealth"
            if ($restoreExit -notin 0, 3010) {
                $script:ExitCode = 1
            }
        }
    } else {
        Write-Step "[4/5] [POMINIĘTO] Operacje DISM"
    }

    if (-not $SkipSFC) {
        Write-Step "[5/5] Skanowanie plików systemowych (SFC)..."
        $sfcProc = Start-Process -FilePath "sfc.exe" -ArgumentList "/scannow" -Wait -NoNewWindow -PassThru
        switch ($sfcProc.ExitCode) {
            0 { Write-Success "SFC: System jest w dobrym stanie." }
            1 { Write-Success "SFC: Uszkodzenia zostały naprawione." }
            2 { Write-Err "SFC: Niektóre uszkodzenia nie mogły zostać naprawione."; $script:ExitCode = 1 }
            default { Write-Warn "SFC zakończone kodem $($sfcProc.ExitCode)." }
        }
    } else {
        Write-Step "[5/5] [POMINIĘTO] Skanowanie SFC"
    }

    Write-Information "`n=== Konserwacja zakończona pomyślnie! ==="
    if (-not $SkipDISM -or -not $SkipSFC) {
        Write-Information "`n[!] Zalecany restart komputera po naprawach DISM/SFC."
    }
}
finally {
    $stopwatch.Stop()
    Write-Info "Czas wykonania: $($stopwatch.Elapsed.ToString('hh\:mm\:ss'))"
    try { Stop-Transcript -ErrorAction SilentlyContinue } catch {}
}

exit $script:ExitCode
