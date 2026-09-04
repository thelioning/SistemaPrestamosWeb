[CmdletBinding()]
param(
    [ValidatePattern('^([01]\d|2[0-3]):[0-5]\d$')][string]$Hora = '22:00',
    [ValidateRange(1, 3650)][int]$RetencionDias = 30
)

$ErrorActionPreference = 'Stop'
$script = Join-Path $PSScriptRoot 'respaldo-diario.ps1'
$logs = Join-Path $PSScriptRoot 'logs'
New-Item -ItemType Directory -Path $logs -Force | Out-Null

$accion = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$script`" -RetencionDias $RetencionDias" -WorkingDirectory $PSScriptRoot
$disparador = New-ScheduledTaskTrigger -Daily -At $Hora
$configuracion = New-ScheduledTaskSettingsSet -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Hours 2)
Register-ScheduledTask -TaskName 'SistemaPrestamos-BackupDiario' -Action $accion -Trigger $disparador -Settings $configuracion -Description 'Copia diaria verificada de las bases original y web del sistema de préstamos' -Force | Out-Null

Write-Host "Tarea diaria instalada para las $Hora. Retención: $RetencionDias días." -ForegroundColor Green
Write-Host "Puede probarla con: Start-ScheduledTask -TaskName 'SistemaPrestamos-BackupDiario'"
