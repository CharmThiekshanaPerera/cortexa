# Cortexa — System Health Monitor

A local Windows system-monitoring and optimization app built in PowerShell + WPF, with an optional local AI agent (via [Ollama](https://ollama.com)) for diagnosis and advice. No cloud services, no telemetry — everything runs on this machine.

## Launching

- Double-click the **Cortexa** shortcut on the Desktop, or
- Run `PCGuard.bat` in this folder, or
- Run directly: `powershell -ExecutionPolicy Bypass -File PCGuard-GUI.ps1`

The app requests administrator privileges via a UAC prompt on every launch (needed for ending protected processes, managing scheduled tasks/startup items, Docker/WSL cleanup, and System Restore points). If you decline the prompt, it keeps running at standard privileges with reduced functionality — a badge next to the title shows which mode you're in.

## What it does

| Tab | Purpose |
|---|---|
| **Dashboard** | Live RAM/CPU/disk stat tiles with sparkline trends, system info (uptime/battery/GPU), quick actions (Speed Boost, Free Up RAM, Clean Temp, Stop Unwanted Software, Create Restore Point, Battery Health Report), top processes, recent alerts, recent system errors |
| **Processes** | Advanced task manager — multi-select, End Task / End Task Tree, Open File Location, Set Priority, Ask AI About Selected, auto-refresh |
| **Disk Analysis** | Largest folders/files scanner (background job, non-blocking), live Disk I/O, WSL/Docker footprint + cleanup |
| **Network** | Live download/upload sparkline, per-adapter totals, active connections (netstat-style), traffic history |
| **Tasks** | Windows Scheduled Tasks browser with Enable/Disable |
| **Startup** | Registry Run-key + Startup-folder items, with reversible Enable/Disable (backed up before disabling) and AI Review |
| **Security** | Windows Defender / Firewall / BitLocker status, disk health (SMART), devices reporting driver errors |
| **History** | Trend chart (RAM/CPU/Disk free %) built from the background watchdog's logged scans |
| **AI Agent** | Chat with a local Ollama model about your system, run a full analysis with clickable suggested-action chips |
| **Settings** | Alert thresholds, unwanted-software list, webhook alerts (Slack/Discord), AI auto-analysis toggle, settings backup/restore |

## Background watchdog

A separate scheduled task (`PCGuard-Watchdog`) runs `PCGuard.ps1` every 15 minutes, independent of whether the GUI is open. It logs RAM/CPU/disk/network stats, raises a Windows toast (and optional webhook) when thresholds are breached, auto-cleans Temp/npm-cache when disk gets critical, generates one HTML health report per day, and (if enabled in Settings) runs an AI analysis.

Install/uninstall it from the Dashboard's "Install/Uninstall Watchdog" button, or manually:
```powershell
. .\PCGuardCore.psm1
Install-Watchdog -ScriptDir "C:\Users\Charm\PCGuard"
# or
Uninstall-Watchdog
```

## AI Agent (optional)

Requires [Ollama](https://ollama.com) installed with at least one model pulled (e.g. `ollama pull qwen2.5:3b`). The AI Agent tab shows connection status and lets you start the Ollama server from inside the app if it isn't already running.

**Design principle: advisory only.** The AI never executes anything on its own — it can only suggest actions from a fixed whitelist (Free Up RAM, Clean Temp, Stop Unwanted Software, Speed Boost, Shutdown WSL, Create Restore Point), rendered as buttons you click yourself. See `DEVELOPMENT.md` for how this is enforced.

## Folder layout

```
PCGuard/
  PCGuard-GUI.ps1       # the app (WPF UI + all code-behind)
  PCGuardCore.psm1       # shared logic - all real work happens here
  PCGuard.ps1             # background watchdog (runs via scheduled task)
  Install-PCGuard.ps1     # standalone watchdog installer (GUI has its own button too)
  PCGuard.bat             # launcher (hides the console window)
  cortexa.ico             # app icon
  config.json             # user settings (created on first Save Settings)
  logs/                   # watchdog's monthly log files
  Reports/                # daily auto-generated HTML health reports + battery reports
  DisabledStartupItems/   # backups of disabled startup items (created on first disable)
```

## Requirements

- Windows 10/11
- PowerShell 5.1+ (built in) or PowerShell 7+
- Administrator rights (requested automatically)
- Optional: [Ollama](https://ollama.com) for the AI Agent tab
- Optional: Docker Desktop / WSL2 (only needed if you want to use those specific cleanup features)

See `DEVELOPMENT.md` for architecture details and `TESTING.md` for how to validate changes before relying on them.
