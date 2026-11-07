# Shared core functions used by both the background watchdog (PCGuard.ps1)
# and the GUI (PCGuard-GUI.ps1).

$script:TaskName = 'PCGuard-Watchdog'

function Get-SystemHealth {
    param([int]$TopProcessCount = 8)

    $os = Get-CimInstance Win32_OperatingSystem
    $ramFreePercent = [math]::Round(($os.FreePhysicalMemory / $os.TotalVisibleMemorySize) * 100, 1)
    $ramFreeGB  = [math]::Round($os.FreePhysicalMemory / 1MB, 2)
    $ramTotalGB = [math]::Round($os.TotalVisibleMemorySize / 1MB, 2)

    $cpu = (Get-CimInstance Win32_Processor | Measure-Object -Property LoadPercentage -Average).Average

    $disks = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" | ForEach-Object {
        [PSCustomObject]@{
            Drive       = $_.DeviceID
            FreePercent = [math]::Round(($_.FreeSpace / $_.Size) * 100, 1)
            FreeGB      = [math]::Round($_.FreeSpace / 1GB, 1)
            SizeGB      = [math]::Round($_.Size / 1GB, 1)
        }
    }

    $topProcs = Get-Process | Sort-Object WorkingSet -Descending | Select-Object -First $TopProcessCount |
        ForEach-Object {
            [PSCustomObject]@{
                Name  = $_.Name
                MemMB = [math]::Round($_.WorkingSet / 1MB, 0)
            }
        }

    [PSCustomObject]@{
        RamFreePercent = $ramFreePercent
        RamFreeGB      = $ramFreeGB
        RamTotalGB     = $ramTotalGB
        CpuPercent     = $cpu
        Disks          = $disks
        TopProcesses   = $topProcs
        Timestamp      = Get-Date
    }
}

function Invoke-SafeCleanup {
    $freedMB = 0
    $targets = @(
        "$env:LOCALAPPDATA\Temp",
        "$env:LOCALAPPDATA\npm-cache",
        "C:\Windows\Temp"
    )
    foreach ($t in $targets) {
        if (Test-Path $t) {
            $before = (Get-ChildItem $t -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
            Get-ChildItem $t -Recurse -Force -ErrorAction SilentlyContinue |
                Where-Object { -not $_.PSIsContainer } |
                Remove-Item -Force -ErrorAction SilentlyContinue
            Get-ChildItem $t -Recurse -Force -ErrorAction SilentlyContinue -Directory |
                Where-Object { (Get-ChildItem $_.FullName -Force -ErrorAction SilentlyContinue | Measure-Object).Count -eq 0 } |
                Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
            $after = (Get-ChildItem $t -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
            $freedMB += [math]::Round((($before - $after) / 1MB), 1)
        }
    }
    return $freedMB
}

function Test-WatchdogInstalled {
    return [bool](Get-ScheduledTask -TaskName $script:TaskName -ErrorAction SilentlyContinue)
}

function Install-Watchdog {
    param([string]$ScriptDir, [int]$IntervalMinutes = 15)

    $scriptPath = Join-Path $ScriptDir 'PCGuard.ps1'
    $action = New-ScheduledTaskAction -Execute 'powershell.exe' `
        -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$scriptPath`""
    $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) `
        -RepetitionInterval (New-TimeSpan -Minutes $IntervalMinutes) `
        -RepetitionDuration (New-TimeSpan -Days 3650)
    # Stagger any post-boot catch-up run so it doesn't fire in the first
    # busy moments right after login, alongside everything else starting up.
    $trigger.Delay = 'PT2M'
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
        -StartWhenAvailable -MultipleInstances IgnoreNew

    Register-ScheduledTask -TaskName $script:TaskName -Action $action -Trigger $trigger -Settings $settings `
        -Description "Monitors RAM/CPU/disk and alerts or cleans up when the PC is under pressure." `
        -Force -ErrorAction Stop | Out-Null
}

function Uninstall-Watchdog {
    Unregister-ScheduledTask -TaskName $script:TaskName -Confirm:$false -ErrorAction SilentlyContinue
}

function Get-RecentAlerts {
    param([string]$LogDir, [int]$Count = 20)

    $logFile = Join-Path $LogDir ("pcguard_{0:yyyy-MM}.log" -f (Get-Date))
    if (-not (Test-Path $logFile)) { return @() }
    $result = @(Get-Content $logFile -Tail 400 | Where-Object { $_ -match 'ALERT' } | Select-Object -Last $Count)
    return $result
}

function Get-HealthHistory {
    # Parses the watchdog's own log lines (not the GUI's live scans) into a time series
    # for the trend chart. Returns points oldest-first.
    param([string]$LogDir, [int]$MaxPoints = 50)

    $logFile = Join-Path $LogDir ("pcguard_{0:yyyy-MM}.log" -f (Get-Date))
    if (-not (Test-Path $logFile)) { return @() }

    $lines = Get-Content $logFile -Tail 2000
    $points = @()
    $current = $null
    foreach ($line in $lines) {
        if ($line -match 'RAM:\s*([\d.]+)%\s*free.*\|\s*CPU:\s*([\d.]+)?%?') {
            if ($current) { $points += [PSCustomObject]$current }
            $current = @{ RamFree = [double]$matches[1]; Cpu = if ($matches[2]) { [double]$matches[2] } else { 0 }; DiskCFree = $null }
        }
        elseif ($line -match 'Disk C:: ([\d.]+)% free' -and $current) {
            $current.DiskCFree = [double]$matches[1]
        }
    }
    if ($current) { $points += [PSCustomObject]$current }
    return $points | Select-Object -Last $MaxPoints
}

function Get-TopFolders {
    # Scans the immediate subfolders of a path and sizes them. Can be slow on large
    # trees, so the GUI runs this inside a background job.
    param([string]$Path, [int]$Top = 15)

    Get-ChildItem $Path -Directory -Force -ErrorAction SilentlyContinue | ForEach-Object {
        $size = (Get-ChildItem $_.FullName -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
        [PSCustomObject]@{ Folder = $_.FullName; SizeGB = [math]::Round($size / 1GB, 2) }
    } | Sort-Object SizeGB -Descending | Select-Object -First $Top
}

function Get-WslDockerInfo {
    $vmmem = Get-Process -Name 'vmmemWSL' -ErrorAction SilentlyContinue
    $wslMemMB = if ($vmmem) { [math]::Round(($vmmem | Measure-Object WorkingSet -Sum).Sum / 1MB, 0) } else { 0 }

    $distros = @()
    try {
        $env:WSL_UTF8 = '1'
        $raw = (wsl --list --verbose 2>$null) -join "`n"
        if ($raw) {
            $distros = $raw -split "`r?`n" | Select-Object -Skip 1 | Where-Object { $_.Trim() -ne '' } |
                ForEach-Object { ($_ -replace '^\*', '').Trim() -split '\s+' | Select-Object -First 1 } |
                Where-Object { $_.Length -gt 1 }
        }
    } catch {}

    $dockerPath = "$env:LOCALAPPDATA\Docker"
    $dockerGB = 0
    if (Test-Path $dockerPath) {
        $dockerGB = [math]::Round(((Get-ChildItem $dockerPath -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum) / 1GB, 2)
    }
    $wslDiskPath = "$env:LOCALAPPDATA\wsl"
    $wslDiskGB = 0
    if (Test-Path $wslDiskPath) {
        $wslDiskGB = [math]::Round(((Get-ChildItem $wslDiskPath -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum) / 1GB, 2)
    }

    [PSCustomObject]@{
        WslRunningMemMB = $wslMemMB
        Distros         = $distros
        DockerDiskGB    = $dockerGB
        WslDiskGB       = $wslDiskGB
    }
}

function Invoke-WslShutdown {
    wsl --shutdown 2>$null
}

function Get-PCGuardConfig {
    param([string]$RootDir)
    $path = Join-Path $RootDir 'config.json'
    $cfg = [ordered]@{
        RamFreePercentWarn       = 15
        DiskFreePercentWarn      = 10
        DiskFreePercentCritical  = 8
        AutoClean                = $true
        UnwantedProcesses        = @()
        FocusMode                = $false
        WebhookUrl               = ''
        WebhookType              = 'Slack'
        AiEnabled                = $false
        AiModel                  = 'qwen2.5:3b'
        CustomRules              = @()
        AutoApproveActions       = @()
    }
    if (Test-Path $path) {
        try {
            $loaded = Get-Content $path -Raw | ConvertFrom-Json
            foreach ($k in @($cfg.Keys)) {
                if ($null -ne $loaded.$k) { $cfg[$k] = $loaded.$k }
            }
        } catch {}
    }
    return [PSCustomObject]$cfg
}

function Save-PCGuardConfig {
    param([string]$RootDir, [PSCustomObject]$Config)
    $path = Join-Path $RootDir 'config.json'
    $Config | ConvertTo-Json | Set-Content -Path $path -Encoding UTF8
}

function Export-HealthReport {
    param([string]$RootDir, [string]$LogDir)

    $health = Get-SystemHealth -TopProcessCount 15
    $wslInfo = Get-WslDockerInfo
    $alerts = Get-RecentAlerts -LogDir $LogDir -Count 30
    $reportPath = Join-Path $RootDir ("PCGuard-Report_{0:yyyyMMdd_HHmmss}.html" -f (Get-Date))

    $procRows = ($health.TopProcesses | ForEach-Object { "<tr><td>$($_.Name)</td><td>$($_.MemMB) MB</td></tr>" }) -join "`n"
    $diskRows = ($health.Disks | ForEach-Object { "<tr><td>$($_.Drive)</td><td>$($_.FreePercent)%</td><td>$($_.FreeGB) GB / $($_.SizeGB) GB</td></tr>" }) -join "`n"
    $alertRows = if ($alerts.Count -gt 0) { ($alerts | ForEach-Object { "<li>$_</li>" }) -join "`n" } else { "<li>None recorded</li>" }

    $html = @"
<html><head><title>PCGuard Report</title>
<style>body{font-family:Segoe UI,Arial;background:#1e1e1e;color:#e0e0e0;padding:24px}
table{border-collapse:collapse;margin-bottom:20px}td,th{padding:6px 14px;border:1px solid #444;text-align:left}
h1,h2{color:#fff}</style></head><body>
<h1>PCGuard System Report</h1>
<p>Generated: $(Get-Date)</p>
<h2>RAM</h2><p>$($health.RamFreePercent)% free ($($health.RamFreeGB) GB / $($health.RamTotalGB) GB)</p>
<h2>CPU</h2><p>$($health.CpuPercent)% load</p>
<h2>Disks</h2><table><tr><th>Drive</th><th>Free %</th><th>Free / Total</th></tr>$diskRows</table>
<h2>Top Processes</h2><table><tr><th>Name</th><th>Memory</th></tr>$procRows</table>
<h2>WSL / Docker</h2><p>WSL running memory: $($wslInfo.WslRunningMemMB) MB | Docker disk use: $($wslInfo.DockerDiskGB) GB | WSL disk use: $($wslInfo.WslDiskGB) GB</p>
<h2>Recent Alerts</h2><ul>$alertRows</ul>
</body></html>
"@
    $html | Set-Content -Path $reportPath -Encoding UTF8
    return $reportPath
}

function Get-NetworkStats {
    # Cumulative counters since the adapter was last reset (not since app start).
    # Callers sample this twice and divide by elapsed time to get a live rate.
    $adapters = Get-NetAdapterStatistics -ErrorAction SilentlyContinue | Where-Object {
        $_.ReceivedBytes -gt 0 -or $_.SentBytes -gt 0
    } | ForEach-Object {
        [PSCustomObject]@{
            Name          = $_.Name
            SentMB        = [math]::Round($_.SentBytes / 1MB, 2)
            ReceivedMB    = [math]::Round($_.ReceivedBytes / 1MB, 2)
            SentBytes     = $_.SentBytes
            ReceivedBytes = $_.ReceivedBytes
        }
    }
    $totalSent = ($adapters | Measure-Object SentBytes -Sum).Sum
    $totalRecv = ($adapters | Measure-Object ReceivedBytes -Sum).Sum

    [PSCustomObject]@{
        Adapters           = $adapters
        TotalSentBytes     = [double]$totalSent
        TotalReceivedBytes = [double]$totalRecv
        Timestamp          = Get-Date
    }
}

function Get-ActiveConnections {
    param([int]$Top = 200)

    $procCache = @{}
    Get-NetTCPConnection -ErrorAction SilentlyContinue | Select-Object -First $Top | ForEach-Object {
        $procId = $_.OwningProcess
        if (-not $procCache.ContainsKey($procId)) {
            $p = Get-Process -Id $procId -ErrorAction SilentlyContinue
            $procCache[$procId] = if ($p) { $p.ProcessName } else { "PID $procId" }
        }
        [PSCustomObject]@{
            Process       = $procCache[$procId]
            Pid           = $procId
            LocalAddress  = $_.LocalAddress
            LocalPort     = $_.LocalPort
            RemoteAddress = $_.RemoteAddress
            RemotePort    = $_.RemotePort
            State         = if ($_.State) { $_.State.ToString() } else { 'Unknown' }
        }
    } | Sort-Object Process, RemoteAddress
}

function Get-NetworkHistory {
    # Parses NET lines the watchdog logs each run, returns cumulative points
    # oldest-first. The GUI converts consecutive points into per-interval deltas.
    param([string]$LogDir, [int]$MaxPoints = 50)

    $logFile = Join-Path $LogDir ("pcguard_{0:yyyy-MM}.log" -f (Get-Date))
    if (-not (Test-Path $logFile)) { return @() }

    $points = @()
    Get-Content $logFile -Tail 2000 | ForEach-Object {
        if ($_ -match 'NET: sent=([\d.]+)MB recv=([\d.]+)MB') {
            $sentMB = [double]$matches[1]
            $recvMB = [double]$matches[2]
            $ts = $null
            if ($_ -match '^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})') { $ts = [datetime]$matches[1] }
            $points += [PSCustomObject]@{ Timestamp = $ts; SentMB = $sentMB; ReceivedMB = $recvMB }
        }
    }
    return $points | Select-Object -Last $MaxPoints
}

function Get-SystemInfo {
    $os = Get-CimInstance Win32_OperatingSystem
    $uptime = (Get-Date) - $os.LastBootUpTime

    $battery = Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue | Select-Object -First 1
    $batteryText = if ($battery) {
        $statusMap = @{ 1='Discharging'; 2='On AC'; 3='Fully Charged'; 4='Low'; 5='Critical'; 6='Charging'; 7='Charging High'; 8='Charging Low'; 9='Charging Critical'; 10='Unknown'; 11='Partially Charged' }
        $st = $statusMap[[int]$battery.BatteryStatus]
        "$($battery.EstimatedChargeRemaining)% ($st)"
    } else { "No battery (desktop)" }

    $gpuPercent = $null
    try {
        $samples = (Get-Counter '\GPU Engine(*)\Utilization Percentage' -ErrorAction Stop).CounterSamples
        $gpuPercent = [math]::Round((($samples | Measure-Object CookedValue -Sum).Sum), 1)
        if ($gpuPercent -gt 100) { $gpuPercent = 100 }
    } catch { $gpuPercent = $null }

    [PSCustomObject]@{
        UptimeText  = "{0}d {1}h {2}m" -f $uptime.Days, $uptime.Hours, $uptime.Minutes
        BootTime    = $os.LastBootUpTime
        BatteryText = $batteryText
        GpuPercent  = $gpuPercent
    }
}

function Get-DiskIoStats {
    try {
        $samples = (Get-Counter '\PhysicalDisk(_Total)\Disk Read Bytes/sec', '\PhysicalDisk(_Total)\Disk Write Bytes/sec' -ErrorAction Stop).CounterSamples
        $read  = ($samples | Where-Object { $_.Path -like '*read*' } | Select-Object -First 1).CookedValue
        $write = ($samples | Where-Object { $_.Path -like '*write*' } | Select-Object -First 1).CookedValue
        [PSCustomObject]@{ ReadMBs = [math]::Round($read / 1MB, 2); WriteMBs = [math]::Round($write / 1MB, 2); Available = $true }
    } catch {
        [PSCustomObject]@{ ReadMBs = 0; WriteMBs = 0; Available = $false }
    }
}

function Get-RecentSystemEvents {
    param([int]$Hours = 24, [int]$Top = 15)
    try {
        $since = (Get-Date).AddHours(-$Hours)
        @(Get-WinEvent -FilterHashtable @{ LogName = 'System', 'Application'; Level = 1, 2; StartTime = $since } -MaxEvents $Top -ErrorAction Stop |
            ForEach-Object {
                [PSCustomObject]@{
                    Time    = $_.TimeCreated
                    Log     = $_.LogName
                    Level   = $_.LevelDisplayName
                    Source  = $_.ProviderName
                    Message = (($_.Message -split "`r?`n")[0])
                }
            })
    } catch {
        @()
    }
}

function Get-ScheduledTasksList {
    param([int]$Top = 400)
    Get-ScheduledTask -ErrorAction SilentlyContinue | ForEach-Object {
        $info = $_ | Get-ScheduledTaskInfo -ErrorAction SilentlyContinue
        [PSCustomObject]@{
            Name        = $_.TaskName
            Path        = $_.TaskPath
            State       = $_.State.ToString()
            LastRunTime = if ($info -and $info.LastRunTime -and $info.LastRunTime.Year -gt 1700) { $info.LastRunTime } else { $null }
            NextRunTime = if ($info -and $info.NextRunTime -and $info.NextRunTime.Year -gt 1700) { $info.NextRunTime } else { $null }
            Author      = $_.Author
        }
    } | Sort-Object Name | Select-Object -First $Top
}

function Set-ScheduledTaskState {
    param([string]$TaskName, [string]$TaskPath, [bool]$Enable)
    if ($Enable) {
        Enable-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath -ErrorAction Stop | Out-Null
    } else {
        Disable-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath -ErrorAction Stop | Out-Null
    }
}

function Get-ProcessesDetailed {
    Get-Process | ForEach-Object {
        $responding = $true
        try { $responding = $_.Responding } catch {}
        $priority = $null
        try { $priority = $_.PriorityClass.ToString() } catch {}
        $threads = 0
        try { $threads = $_.Threads.Count } catch {}
        $start = $null
        try { $start = $_.StartTime } catch {}
        [PSCustomObject]@{
            Name      = $_.Name
            Id        = $_.Id
            Status    = if ($responding) { 'Responding' } else { 'Not Responding' }
            MemMB     = [math]::Round($_.WorkingSet / 1MB, 1)
            CpuSec    = if ($_.CPU) { [math]::Round($_.CPU, 1) } else { 0 }
            Threads   = $threads
            Priority  = $priority
            StartTime = $start
        }
    } | Sort-Object MemMB -Descending
}

function Stop-ProcessTree {
    param([int]$ProcessId)
    $children = Get-CimInstance Win32_Process -Filter "ParentProcessId=$ProcessId" -ErrorAction SilentlyContinue
    foreach ($c in $children) { Stop-ProcessTree -ProcessId $c.ProcessId }
    Stop-Process -Id $ProcessId -Force -ErrorAction SilentlyContinue
}

function Set-ProcessPriority {
    param([int]$ProcessId, [string]$Priority)
    $p = Get-Process -Id $ProcessId -ErrorAction Stop
    $p.PriorityClass = [System.Diagnostics.ProcessPriorityClass]$Priority
}

function Get-ProcessFilePath {
    param([int]$ProcessId)
    try { (Get-Process -Id $ProcessId -ErrorAction Stop).Path } catch { $null }
}

function Invoke-FreeUpRam {
    # Trims the working set of eligible background processes (EmptyWorkingSet,
    # a documented Win32 API) so Windows reclaims pages those apps aren't
    # actively using. This is a real, bounded optimization - not a "RAM cleaner"
    # gimmick - and processes simply reallocate pages back as needed.
    param([string[]]$ExcludeNames = @())

    if (-not ('PCGuardNative.Memory' -as [type])) {
        Add-Type -Namespace PCGuardNative -Name Memory -MemberDefinition @"
[DllImport("psapi.dll")]
public static extern bool EmptyWorkingSet(IntPtr hProcess);
"@
    }

    $critical = @('System', 'Idle', 'smss', 'csrss', 'wininit', 'services', 'lsass', 'winlogon', 'dwm', 'Registry', 'MemCompression') + $ExcludeNames
    $before = (Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory
    $trimmed = 0
    foreach ($p in (Get-Process -ErrorAction SilentlyContinue)) {
        if ($critical -contains $p.ProcessName) { continue }
        if ($p.Id -eq $PID) { continue }
        try {
            if ([PCGuardNative.Memory]::EmptyWorkingSet($p.Handle)) { $trimmed++ }
        } catch {}
    }
    Start-Sleep -Milliseconds 400
    $after = (Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory

    [PSCustomObject]@{
        ProcessesTrimmed = $trimmed
        FreedMB          = [math]::Round(($after - $before) / 1024, 1)
    }
}

function Invoke-StopUnwantedProcesses {
    param([string[]]$Names)
    $stopped = @()
    foreach ($n in $Names) {
        $n = $n.Trim()
        if (-not $n) { continue }
        foreach ($p in (Get-Process -Name $n -ErrorAction SilentlyContinue)) {
            try {
                Stop-Process -Id $p.Id -Force -ErrorAction Stop
                $stopped += "$($p.ProcessName) (PID $($p.Id))"
            } catch {}
        }
    }
    return $stopped
}

function Invoke-CreateRestorePoint {
    param([string]$Description = "Cortexa manual checkpoint")
    try {
        Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction SilentlyContinue
        Checkpoint-Computer -Description $Description -RestorePointType "MODIFY_SETTINGS" -ErrorAction Stop
        [PSCustomObject]@{ Success = $true; Message = "Restore point created: $Description" }
    } catch {
        [PSCustomObject]@{ Success = $false; Message = $_.Exception.Message }
    }
}

function Get-StartupItemsDetailed {
    $items = @()

    foreach ($hive in @(
        @{ Root = 'HKCU:'; Path = 'Software\Microsoft\Windows\CurrentVersion\Run' },
        @{ Root = 'HKLM:'; Path = 'Software\Microsoft\Windows\CurrentVersion\Run' }
    )) {
        $full = Join-Path $hive.Root $hive.Path
        if (Test-Path $full) {
            $key = Get-Item $full
            foreach ($valueName in $key.GetValueNames()) {
                if (-not $valueName) { continue }
                $items += [PSCustomObject]@{
                    Name    = $valueName
                    Command = $key.GetValue($valueName)
                    Source  = 'Registry'
                    Hive    = $hive.Root
                    KeyPath = $hive.Path
                    Enabled = $true
                }
            }
        }
    }

    $startupFolders = @(
        [Environment]::GetFolderPath('Startup'),
        [Environment]::GetFolderPath('CommonStartup')
    )
    foreach ($folder in $startupFolders) {
        if (Test-Path $folder) {
            Get-ChildItem $folder -Filter '*.lnk' -ErrorAction SilentlyContinue | ForEach-Object {
                $items += [PSCustomObject]@{
                    Name    = $_.BaseName
                    Command = $_.FullName
                    Source  = 'Startup Folder'
                    Hive    = $null
                    KeyPath = $folder
                    Enabled = $true
                }
            }
        }
    }

    $disabledDir = Join-Path $PSScriptRoot 'DisabledStartupItems'
    if (Test-Path $disabledDir) {
        Get-ChildItem $disabledDir -ErrorAction SilentlyContinue | ForEach-Object {
            if ($_.Extension -eq '.lnk') {
                $items += [PSCustomObject]@{ Name = $_.BaseName; Command = $_.FullName; Source = 'Startup Folder'; Hive = $null; KeyPath = $disabledDir; Enabled = $false }
            } elseif ($_.Extension -eq '.json') {
                try {
                    $backup = Get-Content $_.FullName -Raw | ConvertFrom-Json
                    $items += [PSCustomObject]@{ Name = $backup.Name; Command = $backup.Command; Source = 'Registry'; Hive = $backup.Hive; KeyPath = $backup.KeyPath; Enabled = $false }
                } catch {}
            }
        }
    }

    return $items | Sort-Object Name
}

function Disable-StartupItem {
    param([PSCustomObject]$Item, [string]$RootDir)
    $disabledDir = Join-Path $RootDir 'DisabledStartupItems'
    if (-not (Test-Path $disabledDir)) { New-Item -ItemType Directory -Path $disabledDir | Out-Null }

    if ($Item.Source -eq 'Registry') {
        $backup = @{ Name = $Item.Name; Command = $Item.Command; Hive = $Item.Hive; KeyPath = $Item.KeyPath }
        $backupFile = Join-Path $disabledDir ("{0}.json" -f ($Item.Name -replace '[\\/:*?"<>|]', '_'))
        $backup | ConvertTo-Json | Set-Content -Path $backupFile -Encoding UTF8
        Remove-ItemProperty -Path (Join-Path $Item.Hive $Item.KeyPath) -Name $Item.Name -ErrorAction Stop
    } else {
        $dest = Join-Path $disabledDir (Split-Path $Item.Command -Leaf)
        Move-Item -Path $Item.Command -Destination $dest -Force -ErrorAction Stop
    }
}

function Enable-StartupItem {
    param([PSCustomObject]$Item, [string]$RootDir)
    $disabledDir = Join-Path $RootDir 'DisabledStartupItems'

    if ($Item.Source -eq 'Registry') {
        $backupFile = Join-Path $disabledDir ("{0}.json" -f ($Item.Name -replace '[\\/:*?"<>|]', '_'))
        $full = Join-Path $Item.Hive $Item.KeyPath
        if (-not (Test-Path $full)) { New-Item -Path $full -Force | Out-Null }
        New-ItemProperty -Path $full -Name $Item.Name -Value $Item.Command -PropertyType String -Force | Out-Null
        if (Test-Path $backupFile) { Remove-Item $backupFile -Force }
    } else {
        $startupFolder = [Environment]::GetFolderPath('Startup')
        $dest = Join-Path $startupFolder (Split-Path $Item.Command -Leaf)
        Move-Item -Path $Item.Command -Destination $dest -Force -ErrorAction Stop
    }
}

function Get-SecurityStatus {
    $defender = $null
    try { $defender = Get-MpComputerStatus -ErrorAction Stop } catch {}

    $firewall = @()
    try { $firewall = Get-NetFirewallProfile -ErrorAction Stop | Select-Object Name, Enabled } catch {}

    $bitlocker = @()
    try { $bitlocker = Get-BitLockerVolume -ErrorAction Stop | Select-Object MountPoint, VolumeStatus, ProtectionStatus } catch {}

    $pnpErrors = @()
    try { $pnpErrors = Get-PnpDevice -ErrorAction Stop | Where-Object { $_.Status -eq 'Error' } | Select-Object FriendlyName, InstanceId, Status } catch {}

    [PSCustomObject]@{
        DefenderEnabled       = if ($defender) { $defender.AntivirusEnabled } else { $null }
        RealTimeProtection    = if ($defender) { $defender.RealTimeProtectionEnabled } else { $null }
        SignaturesAge         = if ($defender) { $defender.AntivirusSignatureAge } else { $null }
        Firewall              = @($firewall)
        BitLocker             = @($bitlocker)
        PnpErrors             = @($pnpErrors)
    }
}

function Get-DiskHealth {
    try {
        Get-PhysicalDisk -ErrorAction Stop | ForEach-Object {
            $counters = $_ | Get-StorageReliabilityCounter -ErrorAction SilentlyContinue
            [PSCustomObject]@{
                FriendlyName    = $_.FriendlyName
                MediaType       = $_.MediaType
                HealthStatus    = $_.HealthStatus
                OperationalStatus = ($_.OperationalStatus -join ', ')
                TemperatureC    = if ($counters) { $counters.Temperature } else { $null }
                WearPercent     = if ($counters -and $counters.Wear) { $counters.Wear } else { $null }
                ReadErrors      = if ($counters) { $counters.ReadErrorsTotal } else { $null }
            }
        }
    } catch {
        @()
    }
}

function Get-BatteryHealthReport {
    param([string]$RootDir)
    $hasBattery = Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue
    if (-not $hasBattery) { return [PSCustomObject]@{ Available = $false } }

    $reportsDir = Join-Path $RootDir 'Reports'
    if (-not (Test-Path $reportsDir)) { New-Item -ItemType Directory -Path $reportsDir | Out-Null }
    $htmlPath = Join-Path $reportsDir "BatteryReport_$(Get-Date -Format 'yyyyMMdd_HHmmss').html"
    $xmlPath = [System.IO.Path]::ChangeExtension($htmlPath, '.xml')

    try {
        powercfg /batteryreport /output $htmlPath /duration 7 | Out-Null
        powercfg /batteryreport /output $xmlPath /xml /duration 7 | Out-Null

        $designCapacity = $null
        $fullChargeCapacity = $null
        if (Test-Path $xmlPath) {
            [xml]$xml = Get-Content $xmlPath -Raw
            $designCapacity = [double]$xml.BatteryReport.Design.DesignCapacity
            $fullChargeCapacity = [double]$xml.BatteryReport.Design.FullChargeCapacity
        }
        $wearPercent = if ($designCapacity -and $fullChargeCapacity) { [math]::Round((1 - ($fullChargeCapacity / $designCapacity)) * 100, 1) } else { $null }

        [PSCustomObject]@{
            Available          = $true
            HtmlPath           = $htmlPath
            DesignCapacity     = $designCapacity
            FullChargeCapacity = $fullChargeCapacity
            WearPercent        = $wearPercent
        }
    } catch {
        [PSCustomObject]@{ Available = $false; Error = $_.Exception.Message }
    }
}

function Get-LargestFiles {
    param([string]$Path, [int]$Top = 30)
    Get-ChildItem $Path -File -Recurse -Force -ErrorAction SilentlyContinue |
        Sort-Object Length -Descending | Select-Object -First $Top |
        ForEach-Object { [PSCustomObject]@{ FilePath = $_.FullName; SizeMB = [math]::Round($_.Length / 1MB, 2) } }
}

function Export-PCGuardSettings {
    param([string]$RootDir, [string]$DestPath)
    $configPath = Join-Path $RootDir 'config.json'
    if (Test-Path $configPath) { Copy-Item $configPath $DestPath -Force }
}

function Import-PCGuardSettings {
    param([string]$RootDir, [string]$SourcePath)
    $configPath = Join-Path $RootDir 'config.json'
    Copy-Item $SourcePath $configPath -Force
}

function Send-WebhookAlert {
    param([string]$WebhookUrl, [string]$WebhookType, [string]$Message)
    if (-not $WebhookUrl) { return }
    try {
        $body = if ($WebhookType -eq 'Discord') { @{ content = $Message } } else { @{ text = $Message } }
        Invoke-RestMethod -Uri $WebhookUrl -Method Post -Body ($body | ConvertTo-Json) -ContentType 'application/json' -ErrorAction Stop | Out-Null
    } catch {}
}

function Test-OllamaAvailable {
    param([string]$BaseUrl = 'http://localhost:11434')
    try {
        $tags = Invoke-RestMethod -Uri "$BaseUrl/api/tags" -TimeoutSec 3 -ErrorAction Stop
        [PSCustomObject]@{ Available = $true; Models = @($tags.models | ForEach-Object { $_.name }) }
    } catch {
        [PSCustomObject]@{ Available = $false; Models = @() }
    }
}

function Start-OllamaServer {
    $exe = "$env:LOCALAPPDATA\Programs\Ollama\ollama.exe"
    if (-not (Test-Path $exe)) { return $false }
    Start-Process $exe -ArgumentList "serve" -WindowStyle Hidden
    for ($i = 0; $i -lt 10; $i++) {
        Start-Sleep -Seconds 1
        if ((Test-OllamaAvailable).Available) { return $true }
    }
    return $false
}

function Invoke-OllamaGenerate {
    param([string]$Model, [string]$Prompt, [string]$SystemPrompt = '', [string]$BaseUrl = 'http://localhost:11434', [int]$TimeoutSec = 60)
    $body = @{ model = $Model; prompt = $Prompt; system = $SystemPrompt; stream = $false } | ConvertTo-Json
    try {
        $result = Invoke-RestMethod -Uri "$BaseUrl/api/generate" -Method Post -Body $body -ContentType 'application/json' -TimeoutSec $TimeoutSec -ErrorAction Stop
        [PSCustomObject]@{ Success = $true; Response = $result.response }
    } catch {
        [PSCustomObject]@{ Success = $false; Response = $_.Exception.Message }
    }
}

function Get-AiSystemContext {
    # A compact plain-text snapshot of current system state, sized for a small
    # local model's context window - not the full detail Cortexa's own UI shows.
    $health = Get-SystemHealth -TopProcessCount 6
    $sysInfo = Get-SystemInfo
    $sec = Get-SecurityStatus

    $lines = @()
    $lines += "RAM: $($health.RamFreePercent)% free ($($health.RamFreeGB) GB of $($health.RamTotalGB) GB)"
    $lines += "CPU load: $($health.CpuPercent)%"
    foreach ($d in $health.Disks) { $lines += "Disk $($d.Drive) $($d.FreePercent)% free ($($d.FreeGB) GB of $($d.SizeGB) GB)" }
    $lines += "Uptime: $($sysInfo.UptimeText)"
    $lines += "Battery: $($sysInfo.BatteryText)"
    $lines += "Top processes by memory: " + (($health.TopProcesses | ForEach-Object { "$($_.Name) $($_.MemMB)MB" }) -join ', ')
    $lines += "Windows Defender enabled: $($sec.DefenderEnabled); real-time protection: $($sec.RealTimeProtection)"
    if ($sec.PnpErrors.Count -gt 0) { $lines += "Devices with driver errors: " + (($sec.PnpErrors | ForEach-Object { $_.FriendlyName }) -join ', ') }
    return ($lines -join "`n")
}

$script:AiSystemPrompt = @"
You are Cortexa, an AI assistant built into a Windows PC health monitoring app. You are given a live snapshot of the user's system (RAM, CPU, disk, processes, security status). Your job: give a short, plain-language diagnosis of anything concerning, and up to 3 concrete, prioritized recommendations.

Rules:
- Be concise. Prefer short sentences and a short bullet list over long paragraphs.
- Only flag things that are actually concerning given the numbers; do not invent problems.
- You cannot take any action yourself - only suggest what the user should click/do in the Cortexa app (e.g. "Free Up RAM", "Clean Temp Junk", "Stop Unwanted Software", "Speed Boost Now", check the Startup or Security tab).
- Never ask the user to run arbitrary commands or install unrelated software.
- End your reply with one line starting exactly with "SUGGESTED_ACTIONS:" followed by a comma-separated list using ONLY these exact tokens, including only the ones that actually apply: FreeRam, CleanTemp, StopUnwanted, SpeedBoost, ShutdownWsl, RestorePoint. If none apply, write "SUGGESTED_ACTIONS: None".
"@

function Get-AiHistoricalBaseline {
    # A short "what's normal for this PC" summary from the watchdog's own
    # logged history, so the AI can say whether today's numbers are actually
    # unusual rather than judging them in isolation. Returns $null until
    # there's enough history to be meaningful.
    param([string]$LogDir, [int]$MinPoints = 3)
    $points = @(Get-HealthHistory -LogDir $LogDir -MaxPoints 200)
    if ($points.Count -lt $MinPoints) { return $null }

    $avgRam = [math]::Round(($points | Measure-Object -Property RamFree -Average).Average, 1)
    $avgCpu = [math]::Round(($points | Measure-Object -Property Cpu -Average).Average, 1)
    $diskPoints = @($points | Where-Object { $null -ne $_.DiskCFree })
    $avgDisk = if ($diskPoints.Count -gt 0) { [math]::Round(($diskPoints | Measure-Object -Property DiskCFree -Average).Average, 1) } else { $null }

    $diskText = if ($null -ne $avgDisk) { "Disk C free avg $avgDisk%" } else { "" }
    "Historical baseline for this PC (last $($points.Count) watchdog scans): RAM free avg $avgRam%, CPU avg $avgCpu%. $diskText"
}

function Invoke-AiSystemAnalysis {
    param([string]$Model, [string]$LogDir = $null, [string]$BaseUrl = 'http://localhost:11434')
    $context = Get-AiSystemContext
    $baseline = if ($LogDir) { Get-AiHistoricalBaseline -LogDir $LogDir } else { $null }
    $prompt = "Here is the current system snapshot:`n$context"
    if ($baseline) {
        $prompt += "`n`n$baseline`n`nCompare today's numbers to this baseline - call out anything that is unusual for THIS specific PC, not just generically high or low."
    }
    $prompt += "`n`nGive your diagnosis and recommendations."
    Invoke-OllamaGenerate -Model $Model -Prompt $prompt -SystemPrompt $script:AiSystemPrompt -BaseUrl $BaseUrl -TimeoutSec 60
}

# Actions eligible for per-action auto-approve, hard-coded independent of
# anything the UI or config ever sends in - this is the real enforcement
# point, not just a UI restriction. Deliberately excludes anything that ends
# a process, stops software, or touches System Restore.
$script:AutoApproveEligibleActions = @('FreeRam', 'CleanTemp')

function Get-AutoApproveEligibleActions {
    # Module-internal $script: variables aren't visible across the module
    # boundary, so the GUI must go through this accessor rather than trying
    # to read $script:AutoApproveEligibleActions directly - that would
    # silently resolve to nothing in the importing script's own scope.
    return $script:AutoApproveEligibleActions
}

function Invoke-AiParseRule {
    param([string]$Model, [string]$UserText, [string]$BaseUrl = 'http://localhost:11434')
    $sys = @"
You turn a plain-language monitoring request into a structured rule for Cortexa, a PC monitoring app. Cortexa can only watch ONE thing: whether a named process's memory usage exceeds a threshold.

Reply with ONLY one line:
RULE: process=<process name, no .exe>;thresholdMB=<whole number of megabytes>

Examples:
"tell me if chrome uses more than 2GB" -> RULE: process=chrome;thresholdMB=2048
"alert me if spotify goes over 500mb" -> RULE: process=spotify;thresholdMB=500

If the request isn't a process-memory-threshold request (it's about something else, or too vague to extract a process name and a number), reply with exactly: RULE: None
"@
    Invoke-OllamaGenerate -Model $Model -Prompt $UserText -SystemPrompt $sys -BaseUrl $BaseUrl -TimeoutSec 30
}

function Get-AiParsedRule {
    param([string]$ResponseText)
    if ($ResponseText -match '(?im)RULE:\s*process=([^;]+);\s*thresholdMB=(\d+)') {
        $proc = $matches[1].Trim() -replace '\.exe$', ''
        $threshold = [int]$matches[2]
        if ($proc -and $threshold -gt 0) {
            return [PSCustomObject]@{ Process = $proc; ThresholdMB = $threshold }
        }
    }
    return $null
}

function Add-CustomRule {
    param([string]$RootDir, [string]$Process, [int]$ThresholdMB)
    $cfg = Get-PCGuardConfig -RootDir $RootDir
    $rules = @($cfg.CustomRules)
    $rules += [PSCustomObject]@{ Id = [guid]::NewGuid().ToString(); Process = $Process; ThresholdMB = $ThresholdMB; Created = (Get-Date).ToString('yyyy-MM-dd HH:mm') }
    $cfg.CustomRules = $rules
    Save-PCGuardConfig -RootDir $RootDir -Config $cfg
    return $rules
}

function Remove-CustomRule {
    param([string]$RootDir, [string]$Id)
    $cfg = Get-PCGuardConfig -RootDir $RootDir
    $cfg.CustomRules = @($cfg.CustomRules | Where-Object { $_.Id -ne $Id })
    Save-PCGuardConfig -RootDir $RootDir -Config $cfg
    return $cfg.CustomRules
}

function Get-CustomRuleViolations {
    # Checked by the watchdog each run. Returns one alert line per rule
    # currently being exceeded (by any single matching process instance).
    param([object[]]$Rules)
    $violations = @()
    foreach ($rule in $Rules) {
        $procs = @(Get-Process -Name $rule.Process -ErrorAction SilentlyContinue)
        foreach ($p in $procs) {
            $memMB = [math]::Round($p.WorkingSet / 1MB, 0)
            if ($memMB -gt $rule.ThresholdMB) {
                $violations += "Custom rule: '$($rule.Process)' is using $memMB MB, above your threshold of $($rule.ThresholdMB) MB (PID $($p.Id))."
                break
            }
        }
    }
    return $violations
}

function Invoke-AiExplainAlert {
    param([string]$Model, [string]$AlertText, [string]$BaseUrl = 'http://localhost:11434')
    $context = Get-AiSystemContext
    $prompt = "This alert was logged by Cortexa's background watchdog:`n`n$AlertText`n`nCurrent system snapshot for context:`n$context`n`nIn 2-4 short sentences, explain in plain language why this likely happened and what, specifically, the user should do about it in the Cortexa app."
    $sys = "You are Cortexa, a PC assistant. Be concise and specific. Reference actual Cortexa features (Free Up RAM, Clean Temp Junk, Speed Boost Now, Disk Analysis tab, Startup tab) where relevant, not generic Windows advice."
    Invoke-OllamaGenerate -Model $Model -Prompt $prompt -SystemPrompt $sys -BaseUrl $BaseUrl -TimeoutSec 45
}

function Get-AiSuggestedActions {
    # Parses the "SUGGESTED_ACTIONS: ..." contract line out of an analysis
    # response. Returns the cleaned display text plus the whitelisted action
    # tokens found (unknown tokens are silently dropped - defense in depth
    # against a small model not following the format exactly).
    param([string]$ResponseText)
    $whitelist = @('FreeRam', 'CleanTemp', 'StopUnwanted', 'SpeedBoost', 'ShutdownWsl', 'RestorePoint')
    $actions = @()
    $displayText = $ResponseText

    if ($ResponseText -match '(?im)^SUGGESTED_ACTIONS:\s*(.+)$') {
        $raw = $matches[1]
        $tokens = $raw -split ',' | ForEach-Object { $_.Trim() }
        $actions = @($tokens | Where-Object { $whitelist -contains $_ })
        $displayText = ($ResponseText -replace '(?im)^SUGGESTED_ACTIONS:\s*.+$', '').Trim()
    }

    [PSCustomObject]@{ DisplayText = $displayText; Actions = $actions }
}

function Invoke-AiExplainProcess {
    param([string]$Model, [string]$ProcessName, [string]$ProcessPath, [double]$MemMB, [string]$BaseUrl = 'http://localhost:11434')
    $pathInfo = if ($ProcessPath) { "File location: $ProcessPath" } else { "File location: unknown (may be a protected system process)" }
    $prompt = "Explain what the Windows process '$ProcessName' is, in 2-4 short sentences. $pathInfo. It is currently using $MemMB MB of RAM. Say plainly whether it is generally safe for a user to end this process, or whether it's a system-critical process that should be left alone. If you don't recognize the specific process, say so honestly rather than guessing, and advise checking the file location/publisher instead."
    $sys = "You are Cortexa, a PC assistant. Be concise, factual, and honest about uncertainty. Do not invent information about unfamiliar processes."
    Invoke-OllamaGenerate -Model $Model -Prompt $prompt -SystemPrompt $sys -BaseUrl $BaseUrl -TimeoutSec 45
}

function Invoke-AiReviewStartupItems {
    param([string]$Model, [object[]]$Items, [string]$BaseUrl = 'http://localhost:11434')
    $list = ($Items | Select-Object -First 30 | ForEach-Object { "- $($_.Name): $($_.Command)" }) -join "`n"
    $prompt = "Here is the list of this Windows PC's startup items (programs that launch at sign-in):`n$list`n`nFor each one, give a very short verdict: either 'Safe to disable if unused' or 'Keep (needed for Windows/hardware/security)' or 'Unsure - research before disabling'. Group your answer by verdict, not by listing each item separately with long explanations. Keep the whole reply under 200 words."
    $sys = "You are Cortexa, a PC assistant reviewing Windows startup programs. Be concise and practical. Do not recommend disabling antivirus, audio drivers, GPU drivers, or other hardware/security-critical software."
    Invoke-OllamaGenerate -Model $Model -Prompt $prompt -SystemPrompt $sys -BaseUrl $BaseUrl -TimeoutSec 60
}

$script:CommandBarTabWhitelist = @('Dashboard', 'Processes', 'Disk Analysis', 'Network', 'Tasks', 'Startup', 'Security', 'History', 'AI Agent', 'Settings')
$script:CommandBarActionTokens = @('FreeRam', 'CleanTemp', 'StopUnwanted', 'SpeedBoost', 'ShutdownWsl', 'RestorePoint', 'EndProcess', 'OpenTab')

function Invoke-AiParseCommand {
    # Maps a free-text user request to ONE action from a fixed whitelist. This
    # is a routing/classification call, not a free execution call - the GUI
    # re-validates the parsed token (and, for EndProcess, the target process)
    # against the same whitelist again before ever doing anything, and always
    # confirms with the user first.
    param([string]$Model, [string]$UserRequest, [string]$BaseUrl = 'http://localhost:11434')

    $sys = @"
You are a command router for Cortexa, a PC monitoring app. Map the user's request to exactly ONE of these actions and reply with ONLY a single line, nothing else:

ACTION: FreeRam          (trim idle process memory)
ACTION: CleanTemp        (clean Temp/npm-cache junk)
ACTION: StopUnwanted     (stop the user's configured unwanted software)
ACTION: SpeedBoost       (clean temp + free RAM + stop unwanted software + shutdown WSL)
ACTION: ShutdownWsl      (shut down WSL)
ACTION: RestorePoint     (create a Windows System Restore point)
ACTION: EndProcess:<name> (end a specific named process, e.g. ACTION: EndProcess:spotify)
ACTION: OpenTab:<name>   (switch to a tab; <name> must be exactly one of: Dashboard, Processes, Disk Analysis, Network, Tasks, Startup, Security, History, AI Agent, Settings)
ACTION: None             (the request doesn't match any of the above, or is unclear/unsafe)

Rules: output nothing but that one "ACTION: ..." line. Never invent a new action. If genuinely unsure, use None.
"@
    Invoke-OllamaGenerate -Model $Model -Prompt $UserRequest -SystemPrompt $sys -BaseUrl $BaseUrl -TimeoutSec 30
}

function Get-AiParsedCommand {
    # Small local models don't always follow the exact "ACTION: Token" format -
    # testing found ~60% of runs drop the "ACTION:" prefix and just emit the
    # bare token (e.g. "CleanTemp" instead of "ACTION: CleanTemp"). This parses
    # the strict format first, then falls back to finding a known token
    # anywhere in the response, so a model's formatting slip doesn't cause a
    # workable command to silently fail as "None".
    param([string]$ResponseText)
    $text = ($ResponseText | Out-String).Trim()
    if (-not $text) { return [PSCustomObject]@{ Action = 'None'; Arg = $null } }

    if ($text -match '(?im)ACTION:\s*([A-Za-z]+)(?::(.+))?\s*$') {
        $token = $matches[1].Trim()
        $arg = if ($matches[2]) { $matches[2].Trim() } else { $null }
        if ($script:CommandBarActionTokens -contains $token) {
            return [PSCustomObject]@{ Action = $token; Arg = $arg }
        }
    }

    # Fallback: check the last non-empty line first (models sometimes prepend
    # a sentence of reasoning before the token), then the whole response.
    $lastLine = ($text -split "`r?`n" | Where-Object { $_.Trim() } | Select-Object -Last 1)
    foreach ($candidate in @($lastLine, $text)) {
        if (-not $candidate) { continue }
        if ($candidate -match '(?i)\b(EndProcess|OpenTab)\s*:\s*([^\s,.;]+)') {
            $token = $script:CommandBarActionTokens | Where-Object { $_ -ieq $matches[1] } | Select-Object -First 1
            if ($token) { return [PSCustomObject]@{ Action = $token; Arg = $matches[2].Trim() } }
        }
        foreach ($known in $script:CommandBarActionTokens) {
            if ($candidate -match "(?i)\b$known\b") {
                return [PSCustomObject]@{ Action = $known; Arg = $null }
            }
        }
    }

    return [PSCustomObject]@{ Action = 'None'; Arg = $null }
}

function Invoke-OllamaPullModel {
    param([string]$ModelName, [string]$BaseUrl = 'http://localhost:11434')
    try {
        $body = @{ model = $ModelName; stream = $false } | ConvertTo-Json
        Invoke-RestMethod -Uri "$BaseUrl/api/pull" -Method Post -Body $body -ContentType 'application/json' -TimeoutSec 1800 -ErrorAction Stop | Out-Null
        [PSCustomObject]@{ Success = $true; Message = "Pulled '$ModelName'." }
    } catch {
        [PSCustomObject]@{ Success = $false; Message = $_.Exception.Message }
    }
}

function Invoke-OllamaDeleteModel {
    param([string]$ModelName, [string]$BaseUrl = 'http://localhost:11434')
    try {
        Invoke-RestMethod -Uri "$BaseUrl/api/delete" -Method Delete -Body (@{ model = $ModelName } | ConvertTo-Json) -ContentType 'application/json' -ErrorAction Stop | Out-Null
        [PSCustomObject]@{ Success = $true; Message = "Deleted '$ModelName'." }
    } catch {
        [PSCustomObject]@{ Success = $false; Message = $_.Exception.Message }
    }
}

function Invoke-AiChat {
    param([string]$Model, [string]$UserMessage, [string]$LogDir = $null, [string]$BaseUrl = 'http://localhost:11434')
    $context = Get-AiSystemContext
    $baseline = if ($LogDir) { Get-AiHistoricalBaseline -LogDir $LogDir } else { $null }
    $systemPrompt = $script:AiSystemPrompt + "`n`nCurrent system snapshot (for your reference, don't repeat it verbatim unless asked):`n$context"
    if ($baseline) { $systemPrompt += "`n`n$baseline" }
    Invoke-OllamaGenerate -Model $Model -Prompt $UserMessage -SystemPrompt $systemPrompt -BaseUrl $BaseUrl -TimeoutSec 60
}

function Write-AiActionLog {
    # Append-only audit trail of every AI-suggested action and what the user
    # decided about it. One JSON object per line (easy to parse, easy to tail).
    param([string]$RootDir, [string]$Source, [string]$Action, [string]$Label, [string]$Decision, [string]$Detail = '')
    $logDir = Join-Path $RootDir 'logs'
    if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir | Out-Null }
    $logFile = Join-Path $logDir 'ai_actions.log'
    $entry = [PSCustomObject]@{
        Time     = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        Source   = $Source
        Action   = $Action
        Label    = $Label
        Decision = $Decision
        Detail   = $Detail
    }
    Add-Content -Path $logFile -Value ($entry | ConvertTo-Json -Compress)
}

function Get-AiActionLog {
    param([string]$RootDir, [int]$Top = 50)
    $logFile = Join-Path $RootDir 'logs\ai_actions.log'
    if (-not (Test-Path $logFile)) { return @() }
    $lines = @(Get-Content $logFile -Tail 500 -ErrorAction SilentlyContinue)
    $parsed = @()
    foreach ($line in $lines) {
        try { $parsed += (ConvertFrom-Json $line) } catch {}
    }
    return @($parsed | Select-Object -Last $Top | Sort-Object Time -Descending)
}

Export-ModuleMember -Function Get-SystemHealth, Invoke-SafeCleanup, Test-WatchdogInstalled, Install-Watchdog, Uninstall-Watchdog, Get-RecentAlerts, Get-HealthHistory, Get-TopFolders, Get-WslDockerInfo, Invoke-WslShutdown, Get-PCGuardConfig, Save-PCGuardConfig, Export-HealthReport, Get-NetworkStats, Get-ActiveConnections, Get-NetworkHistory, Get-SystemInfo, Get-DiskIoStats, Get-RecentSystemEvents, Get-ScheduledTasksList, Set-ScheduledTaskState, Get-ProcessesDetailed, Stop-ProcessTree, Set-ProcessPriority, Get-ProcessFilePath, Invoke-FreeUpRam, Invoke-StopUnwantedProcesses, Invoke-CreateRestorePoint, Get-StartupItemsDetailed, Disable-StartupItem, Enable-StartupItem, Get-SecurityStatus, Get-DiskHealth, Get-BatteryHealthReport, Get-LargestFiles, Export-PCGuardSettings, Import-PCGuardSettings, Send-WebhookAlert, Test-OllamaAvailable, Start-OllamaServer, Invoke-OllamaGenerate, Get-AiSystemContext, Invoke-AiSystemAnalysis, Invoke-AiChat, Get-AiSuggestedActions, Invoke-AiExplainProcess, Invoke-AiReviewStartupItems, Invoke-AiParseCommand, Get-AiParsedCommand, Invoke-OllamaPullModel, Invoke-OllamaDeleteModel, Write-AiActionLog, Get-AiActionLog, Get-AiHistoricalBaseline, Invoke-AiExplainAlert, Invoke-AiParseRule, Get-AiParsedRule, Add-CustomRule, Remove-CustomRule, Get-CustomRuleViolations, Get-AutoApproveEligibleActions
