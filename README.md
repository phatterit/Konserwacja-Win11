# Windows 11 Maintenance & Cleanup PowerShell Script

Advanced PowerShell script designed to automate Windows 11 maintenance tasks, 
system cleanup and integrity verification.

The script performs safe cleanup operations, repairs Windows components and 
provides detailed execution logs for troubleshooting and enterprise usage.

## Features

- Temporary files cleanup:
  - User TEMP directory
  - Windows TEMP directory

- Windows Update maintenance:
  - Stops Windows Update services
  - Clears SoftwareDistribution cache
  - Restores required services automatically

- System cache cleanup:
  - DNS cache flush
  - Microsoft Store cache reset
  - Recycle Bin cleanup

- Windows component maintenance:
  - DISM StartComponentCleanup
  - DISM AnalyzeComponentStore
  - DISM ScanHealth
  - DISM RestoreHealth (when required)

- System file verification:
  - SFC /scannow integrity check

- Logging:
  - Automatic transcript logging
  - Timestamped log files stored on Desktop

- Automation support:
  - Exit codes compatible with management platforms
  - Parameter-based execution control
  - PowerShell 5.1 and PowerShell 7+ compatibility


## Requirements

- Windows 11
- PowerShell 5.1 or newer
- Administrator privileges


## Usage

Run standard maintenance:

```powershell
.\Konserwacja.ps1
