[CmdletBinding()]
param(
    [string]$Servidor = 'localhost',
    [int]$Puerto = 5432,
    [string]$BaseDatos = 'prestamos_san_redito_web_dev',
    [string]$Usuario = 'postgres',
    [string]$Directorio = (Join-Path $PSScriptRoot 'backups'),
    [ValidateRange(1, 3650)][int]$RetencionDias = 30
)

$ErrorActionPreference = 'Stop'
$postgres = Get-ChildItem 'C:\Program Files\PostgreSQL' -Directory -ErrorAction SilentlyContinue |
    Sort-Object { [int]$_.Name } -Descending |
    Select-Object -First 1
if (-not $postgres) { throw 'No se encontró PostgreSQL en C:\Program Files\PostgreSQL.' }

$pgDump = Join-Path $postgres.FullName 'bin\pg_dump.exe'
$pgRestore = Join-Path $postgres.FullName 'bin\pg_restore.exe'
if (-not (Test-Path $pgDump) -or -not (Test-Path $pgRestore)) {
    throw 'No se encontraron pg_dump y pg_restore.'
}

New-Item -ItemType Directory -Path $Directorio -Force | Out-Null
$marca = Get-Date -Format 'yyyyMMdd-HHmmss'
$destino = Join-Path $Directorio "${BaseDatos}-${marca}.dump"
$temporal = "${destino}.tmp"

try {
    & $pgDump --host=$Servidor --port=$Puerto --username=$Usuario --dbname=$BaseDatos --format=custom --compress=9 --no-password --file=$temporal
    if ($LASTEXITCODE -ne 0) { throw "pg_dump terminó con código $LASTEXITCODE." }
    if (-not (Test-Path $temporal) -or (Get-Item $temporal).Length -eq 0) { throw 'La copia generada está vacía.' }

    & $pgRestore --list $temporal | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'La copia no superó la verificación de lectura.' }

    Move-Item -LiteralPath $temporal -Destination $destino
    Get-ChildItem -LiteralPath $Directorio -Filter "${BaseDatos}-*.dump" -File |
        Where-Object LastWriteTime -lt (Get-Date).AddDays(-$RetencionDias) |
        Remove-Item -Force

    $archivo = Get-Item -LiteralPath $destino
    Write-Host "Copia creada correctamente: $($archivo.FullName)" -ForegroundColor Green
    Write-Host "Tamaño: $([math]::Round($archivo.Length / 1MB, 2)) MB"
}
catch {
    Remove-Item -LiteralPath $temporal -Force -ErrorAction SilentlyContinue
    throw
}
