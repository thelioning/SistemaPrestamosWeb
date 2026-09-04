[CmdletBinding()]
param(
    [string[]]$BasesDatos = @('prestamos_san_redito', 'prestamos_san_redito_web_dev'),
    [ValidateRange(1, 3650)][int]$RetencionDias = 30
)

$ErrorActionPreference = 'Stop'
$scriptRespaldo = Join-Path $PSScriptRoot 'respaldar-postgres.ps1'
$directorioLogs = Join-Path $PSScriptRoot 'logs'
$directorioBackups = Join-Path $PSScriptRoot 'backups'
New-Item -ItemType Directory -Path $directorioLogs -Force | Out-Null
$log = Join-Path $directorioLogs ('backup-' + (Get-Date -Format 'yyyy-MM') + '.log')

function Escribir-Log([string]$Mensaje) {
    Add-Content -LiteralPath $log -Value ("[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Mensaje) -Encoding utf8
}

try {
    Escribir-Log "INICIO - Bases: $($BasesDatos -join ', ')"
    foreach ($base in $BasesDatos) {
        Escribir-Log "Respaldando $base"
        $salida = & $scriptRespaldo -BaseDatos $base -Directorio $directorioBackups -RetencionDias $RetencionDias 2>&1
        $ejecucionCorrecta = $?
        $salida | ForEach-Object { Escribir-Log ([string]$_) }
        if (-not $ejecucionCorrecta) { throw "Falló el respaldo de $base." }
    }
    Escribir-Log 'FIN CORRECTO'
    exit 0
}
catch {
    Escribir-Log ("ERROR - " + $_.Exception.Message)
    exit 1
}
