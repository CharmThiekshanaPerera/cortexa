# Registers PCGuard to run automatically every 15 minutes (per-user scheduled task, no admin needed)

$ScriptPath = Join-Path $PSScriptRoot 'PCGuard.ps1'
$TaskName = 'PCGuard-Watchdog'

$Action = New-ScheduledTaskAction -Execute 'powershell.exe' `
    -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$ScriptPath`""

$Trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 15) -RepetitionDuration (New-TimeSpan -Days 3650)

$Settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -MultipleInstances IgnoreNew

try {
    Register-ScheduledTask -TaskName $TaskName -Action $Action -Trigger $Trigger -Settings $Settings -Description "Monitors RAM/CPU/disk and alerts or cleans up when the PC is under pressure." -Force -ErrorAction Stop | Out-Null
    Write-Host "PCGuard installed. It will run every 15 minutes in the background."
    Write-Host "Logs: $PSScriptRoot\logs\"
    Write-Host "To uninstall: Unregister-ScheduledTask -TaskName '$TaskName' -Confirm:`$false"
} catch {
    Write-Host "Install FAILED: $_" -ForegroundColor Red
}
