<#
.SYNOPSIS
    Zaawansowany skrypt konserwacji i czyszczenia systemu Windows 11.
.DESCRIPTION
    Automatyzuje proces czyszczenia plików tymczasowych, cache Windows Update, DNS, MS Store, Kosza 
    oraz weryfikuje spójność systemu narzędziami DISM i SFC. Wykorzystuje natywne strumienie PowerShell,
    sprawdza kody wyjścia procesów, bezpiecznie obsługuje ścieżki (w tym OneDrive) i pozwala na
    sterowanie przełącznikami. Zwraca kod 0 (sukces) lub 1 (błąd) dla narzędzi automatyzacji.
.EXAMPLE
    .\Konserwacja.ps1 -SkipDISM -SkipSFC
.EXAMPLE
    .\Konserwacja.ps1 -InformationAction Continue
#>

# Wymagania wstępne wbudowane w skrypt
#Requires -Version 5.1
#Requires -RunAsAdministrator

[CmdletBinding()]
param (
    [switch]$SkipTemp,
    [switch]$SkipUpdateCache,
    [switch]$SkipStoreReset,
    [switch]$SkipDISM,
    [switch]$SkipSFC
)

# Wymuszenie wyświetlania komunikatów strumienia Information
$InformationPreference = 'Continue'

# Zmienna przechowująca ogólny status skryptu (0 = Sukces, 1 = Błędy)
$globalExitCode = 0

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
                Write-Warn "Część plików ($($err.Count)) nie mogła zostać usunięta (używane przez procesy)."
            } else {
                Write-Success "Wyczyszczono zawartość $Path."
            }
        } else {
            Write-Info "Folder jest już pusty."
        }
    }
}

# --- INICJALIZACJA LOGOWANIA I STOPERA ---

$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
$timeStamp = (Get-Date).ToString('yyyy-MM-dd_HH-mm-ss')

$desktopPath = [Environment]::GetFolderPath('Desktop')
$logPath = Join-Path $desktopPath "Konserwacja_$timeStamp.log"

try {
    Start-Transcript -Path $logPath -Force -ErrorAction Stop
} catch {
    Write-Warn "Nie można uruchomić transkrypcji logów. Skrypt będzie kontynuowany bez zapisu."
}

# --- GŁÓWNA LOGIKA SKRYPTU ---

try {
    Write-Information "=== Rozpoczynanie procedury czyszczenia i konserwacji systemu ==="
    Write-Info "Data uruchomienia: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"

    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    Write-Information "`n--- Informacje o środowisku ---"
    Write-Info "Komputer: $env:COMPUTERNAME"
    if ($os) { Write-Info "System: $($os.Caption) ($($os.OSArchitecture))" }
    Write-Info "PowerShell: $($PSVersionTable.PSVersion.ToString())"

    # 1. Czyszczenie folderów Temp
    if (-not $SkipTemp) {
        Write-Step "[1/6] Czyszczenie plików tymczasowych (Temp)..."
        Clear-Folder -Path $env:TEMP
        Clear-Folder -Path "C:\Windows\Temp"
    } else {
        Write-Step "[1/6] [POMINIĘTO] Czyszczenie plików tymczasowych (Temp)"
    }

    # 2. Czyszczenie cache Windows Update
    if (-not $SkipUpdateCache) {
        Write-Step "[2/6] Czyszczenie cache Windows Update..."

        $updateServices = @('wuauserv', 'bits', 'cryptsvc')

        try {
            Write-Info "Zatrzymywanie usług: $($updateServices -join ', ')..."
            Stop-Service -Name $updateServices -Force -ErrorAction Stop
            
            Write-Info "Oczekiwanie na zwolnienie blokad plików (2s)..."
            Start-Sleep -Seconds 2

            $sdPath = "C:\Windows\SoftwareDistribution"
            if (Test-Path -LiteralPath $sdPath) {
                Write-Info "Skanowanie $sdPath (z wyłączeniem DataStore i ReportingEvents)..."
                $sdItems = Get-ChildItem -Path $sdPath -Exclude "DataStore", "ReportingEvents" -Force -ErrorAction SilentlyContinue
                
                if ($sdItems) {
                    Write-Info "Usuwanie $($sdItems.Count) obiektów z SoftwareDistribution..."
                    $errWU = $null
                    $sdItems | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue -ErrorVariable errWU
                    
                    if ($errWU) {
                        Write-Warn "Część plików nie mogła zostać usunięta ($($errWU.Count))."
                    } else {
                        Write-Success "Wyczyszczono cache SoftwareDistribution."
                    }
                } else {
                    Write-Info "Brak plików do usunięcia w SoftwareDistribution."
                }
            }
        }
        catch {
            Write-Err "Błąd podczas czyszczenia SoftwareDistribution: $_"
            $globalExitCode = 1
        }
        finally {
            Write-Info "Wznawianie usług: $($updateServices -join ', ')..."
            Start-Service -Name $updateServices -ErrorAction SilentlyContinue
            
            foreach ($svc in $updateServices) {
                try { (Get-Service $svc -ErrorAction SilentlyContinue).WaitForStatus('Running', '00:00:10') } catch {}
            }
        }
    } else {
        Write-Step "[2/6] [POMINIĘTO] Czyszczenie cache Windows Update"
    }

    # 3. Cache DNS, Sklep MS i Kosz
    Write-Step "[3/6] Czyszczenie cache DNS, Kosza oraz Sklepu MS..."

    Write-Info "Czyszczenie DNS..."
    Clear-DnsClientCache
    Write-Success "Pamięć podręczna DNS wyczyszczona."

    try {
        Clear-RecycleBin -Force -ErrorAction Stop
        Write-Success "Kosz opróżniony."
    } catch {
        if ($_.Exception.HResult -eq -2147467259 -or $_.Exception.Message -like "*empty*") {
            Write-Info "Kosz jest już pusty."
        } else {
            Write-Warn "Nie udało się opróżnić Kosza."
        }
    }

    if (-not $SkipStoreReset) {
        Write-Info "Resetowanie cache Sklepu (wsreset.exe)..."
        $storeProc = Start-Process "wsreset.exe" -Wait -NoNewWindow -PassThru
        
        if ($storeProc.ExitCode -eq 0) {
            Write-Success "Cache Sklepu MS zresetowany."
        } else {
            Write-Warn "wsreset.exe zakończył się kodem $($storeProc.ExitCode)."
            $globalExitCode = 1
        }
    } else {
        Write-Info "[POMINIĘTO] Resetowanie cache Sklepu MS"
    }

    # 4. Czyszczenie magazynu WinSxS oraz naprawa (DISM)
    if (-not $SkipDISM) {
        Write-Step "[4/6] Bezpieczne czyszczenie magazynu WinSxS (DISM)..."
        Write-Info "Uruchamianie /StartComponentCleanup..."
        $dismCleanExit = Invoke-Dism "/online /cleanup-image /startcomponentcleanup"

        switch ($dismCleanExit) {
            0    { Write-Success "DISM (StartComponentCleanup): Zakończono sukcesem." }
            3010 { Write-Warn "DISM (StartComponentCleanup): Sukces, wymagany restart komputera." }
            default { 
                Write-Err "DISM (StartComponentCleanup): Błąd (Kod: $dismCleanExit)." 
                $globalExitCode = 1
            }
        }
        
        Write-Info "Generowanie logu analizy magazynu (/AnalyzeComponentStore)..."
        Invoke-Dism "/online /cleanup-image /analyzecomponentstore" | Out-Null

        # 5. Sprawdzenie i naprawa obrazu systemu
        Write-Step "[5/6] Weryfikacja spójności obrazu systemu (DISM)..."
        Write-Info "Szybkie sprawdzanie stanu obrazu (/CheckHealth)..."
        $checkExit = Invoke-Dism "/online /cleanup-image /checkhealth"

        if ($checkExit -eq 0) {
            Write-Success "DISM (CheckHealth): Obraz jest zdrowy, pomijam czasochłonne /RestoreHealth."
        } else {
            Write-Info "Wykryto flagę uszkodzenia. Uruchamianie /RestoreHealth..."
            $restoreExit = Invoke-Dism "/online /cleanup-image /restorehealth"

            switch ($restoreExit) {
                0    { Write-Success "DISM (RestoreHealth): Pomyślnie naprawiono." }
                3010 { Write-Warn "DISM (RestoreHealth): Naprawiono uszkodzenia, wymagany restart." }
                default { 
                    Write-Err "DISM (RestoreHealth): Błąd (Kod: $restoreExit)." 
                    $globalExitCode = 1
                }
            }
        }
    } else {
        Write-Step "[4/6] [POMINIĘTO] Czyszczenie magazynu WinSxS (DISM)"
        Write-Step "[5/6] [POMINIĘTO] Weryfikacja spójności obrazu systemu (DISM)"
    }

    # 6. Weryfikacja plików systemowych (SFC)
    if (-not $SkipSFC) {
        Write-Step "[6/6] Skanowanie spójności plików systemowych (SFC)..."
        $sfcProc = Start-Process -FilePath "sfc.exe" -ArgumentList "/scannow" -Wait -NoNewWindow -PassThru

        switch ($sfcProc.ExitCode) {
            0 { Write-Success "SFC: Brak naruszeń integralności." }
            1 { Write-Success "SFC: Wykryto i pomyślnie naprawiono uszkodzenia plików." }
            2 { Write-Err "SFC: Znaleziono uszkodzenia, których nie można naprawić." ; $globalExitCode = 1 }
            default { Write-Warn "SFC: Zakończono z kodem $($sfcProc.ExitCode). Zobacz CBS.log." }
        }
    } else {
        Write-Step "[6/6] [POMINIĘTO] Skanowanie spójności plików systemowych (SFC)"
    }

    Write-Information "`n=== Konserwacja zakończona! ==="
    
    if (-not $SkipSFC -or -not $SkipDISM) {
        Write-Information "`n[!] UWAGA: Jeżeli SFC lub DISM wykonały naprawę plików, zalecane jest ponowne uruchomienie komputera."
    }
}
finally {
    $stopwatch.Stop()
    $elapsed = $stopwatch.Elapsed
    
    Write-Info "Całkowity czas wykonania: $($elapsed.ToString('hh\:mm\:ss'))"
    
    try {
        Stop-Transcript -ErrorAction SilentlyContinue
    } catch {}
}

exit $globalExitCode
