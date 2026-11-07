# PCGuard background watchdog - run every 15 min via the scheduled task
# installed by the GUI or Install-PCGuard.ps1

param(
    [switch]$AutoClean = $true,
    [int]$RamFreePercentWarn = 15,
    [int]$DiskFreePercentWarn = 10,
    [int]$DiskFreePercentCritical = 8,
    [int]$TopProcessCount = 5
)

$ErrorActionPreference = 'SilentlyContinue'
$RootDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Import-Module (Join-Path $RootDir 'PCGuardCore.psm1') -Force

$LogDir = Join-Path $RootDir 'logs'
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir | Out-Null }
$LogFile = Join-Path $LogDir ("pcguard_{0:yyyy-MM}.log" -f (Get-Date))

$cfg = Get-PCGuardConfig -RootDir $RootDir
if (-not $PSBoundParameters.ContainsKey('RamFreePercentWarn'))      { $RamFreePercentWarn = $cfg.RamFreePercentWarn }
if (-not $PSBoundParameters.ContainsKey('DiskFreePercentWarn'))     { $DiskFreePercentWarn = $cfg.DiskFreePercentWarn }
if (-not $PSBoundParameters.ContainsKey('DiskFreePercentCritical')) { $DiskFreePercentCritical = $cfg.DiskFreePercentCritical }
if (-not $PSBoundParameters.ContainsKey('AutoClean'))               { $AutoClean = [bool]$cfg.AutoClean }

function Write-Log {
    param([string]$Message)
    Add-Content -Path $LogFile -Value ("{0:yyyy-MM-dd HH:mm:ss}  {1}" -f (Get-Date), $Message)
}

function Send-Notification {
    param([string]$Title, [string]$Body)
    try {
        Add-Type -AssemblyName System.Windows.Forms
        $ni = New-Object System.Windows.Forms.NotifyIcon
        $ni.Icon = [System.Drawing.SystemIcons]::Warning
        $ni.Visible = $true
        $ni.BalloonTipTitle = $Title
        $ni.BalloonTipText = $Body
        $ni.ShowBalloonTip(10000)
        Start-Sleep -Seconds 1
        $ni.Dispose()
    } catch { Write-Log "Notification failed: $_" }
}

$health = Get-SystemHealth -TopProcessCount $TopProcessCount

Write-Log ("RAM: {0}% free ({1} GB / {2} GB) | CPU: {3}%" -f $health.RamFreePercent, $health.RamFreeGB, $health.RamTotalGB, $health.CpuPercent)
foreach ($d in $health.Disks) {
    Write-Log ("Disk {0}: {1}% free ({2} GB)" -f $d.Drive, $d.FreePercent, $d.FreeGB)
}

$net = Get-NetworkStats
Write-Log ("NET: sent={0}MB recv={1}MB" -f [math]::Round($net.TotalSentBytes / 1MB, 2), [math]::Round($net.TotalReceivedBytes / 1MB, 2))

$alerts = @()

if ($health.RamFreePercent -lt $RamFreePercentWarn) {
    $top = $health.TopProcesses | ForEach-Object { "$($_.Name) ($($_.MemMB) MB)" }
    $alerts += "Low RAM: only $($health.RamFreePercent)% free ($($health.RamFreeGB) GB).`nTop processes: $($top -join ', ')"
}

if ($health.CpuPercent -ge 90) {
    $alerts += "High CPU load: $($health.CpuPercent)% average across cores."
}

foreach ($d in $health.Disks) {
    if ($d.FreePercent -lt $DiskFreePercentWarn) {
        $alerts += "Low disk space on $($d.Drive): only $($d.FreePercent)% free ($($d.FreeGB) GB)."
    }
    if ($AutoClean -and $d.Drive -eq 'C:' -and $d.FreePercent -lt $DiskFreePercentCritical) {
        $freed = Invoke-SafeCleanup
        if ($freed -gt 0) {
            $alerts += "Disk C: was critically low. Auto-cleanup freed ~$freed MB from Temp/npm-cache."
        }
    }
}

if ($alerts.Count -gt 0) {
    $body = ($alerts -join "`n`n")
    Write-Log "ALERT: $body"
    if ($cfg.FocusMode) {
        Write-Log "Focus Mode is on - Windows notification suppressed (still logged)."
    } else {
        Send-Notification -Title "Cortexa: performance warning" -Body ($body.Substring(0, [math]::Min(250, $body.Length)))
    }
    if ($cfg.WebhookUrl) {
        Send-WebhookAlert -WebhookUrl $cfg.WebhookUrl -WebhookType $cfg.WebhookType -Message "Cortexa alert on $env:COMPUTERNAME`:`n$body"
    }
}

if ($cfg.AiEnabled) {
    $ollama = Test-OllamaAvailable
    if ($ollama.Available) {
        $ai = Invoke-AiSystemAnalysis -Model $cfg.AiModel
        if ($ai.Success) {
            Write-Log ("AI_INSIGHT: " + ($ai.Response -replace "`r?`n", ' '))
        } else {
            Write-Log "AI analysis failed: $($ai.Response)"
        }
    } else {
        Write-Log "AI analysis skipped: Ollama is not running."
    }
}

# Auto-generate one health report per calendar day, kept in the Reports folder.
$reportsDir = Join-Path $RootDir 'Reports'
if (-not (Test-Path $reportsDir)) { New-Item -ItemType Directory -Path $reportsDir | Out-Null }
$dailyMarker = Join-Path $reportsDir ("daily_{0:yyyy-MM-dd}.marker" -f (Get-Date))
if (-not (Test-Path $dailyMarker)) {
    try {
        $reportPath = Export-HealthReport -RootDir $reportsDir -LogDir $LogDir
        New-Item -ItemType File -Path $dailyMarker | Out-Null
        Write-Log "Daily report generated: $reportPath"
    } catch { Write-Log "Daily report generation failed: $_" }
    # Keep only the last 30 days of reports/markers.
    Get-ChildItem $reportsDir -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^(PCGuard-Report_|daily_)' -and $_.LastWriteTime -lt (Get-Date).AddDays(-30) } |
        Remove-Item -Force -ErrorAction SilentlyContinue
}
