# Windows 11 Maintenance Script

Advanced PowerShell script designed to automate Windows 11 maintenance and system cleanup tasks.

## Features

- Temporary files cleanup:
  - User TEMP directory
  - System Windows TEMP directory

- Windows Update maintenance:
  - Stops Windows Update services
  - Clears SoftwareDistribution download cache
  - Restarts required services

- System cache cleanup:
  - DNS cache reset
  - Microsoft Store cache reset
  - Recycle Bin cleanup

- System integrity verification:
  - DISM StartComponentCleanup
  - DISM RestoreHealth
  - SFC /scannow

- Administration features:
  - Administrator privileges requirement
  - Execution logging using Start-Transcript
  - Runtime measurement
  - Error handling
  - Automation-friendly exit codes
  - Optional task skipping through parameters

## Usage

Run PowerShell as Administrator:

```powershell
.\Konserwacja.ps1
