[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Archivo,
    [string]$Servidor = 'localhost',
    [int]$Puerto = 5432,
    [string]$Usuario = 'postgres',
    [string]$BaseCredencial = 'prestamos_san_redito_web_dev'
)

$ErrorActionPreference = 'Stop'
$archivoResuelto = (Resolve-Path -LiteralPath $Archivo).Path
$postgres = Get-ChildItem 'C:\Program Files\PostgreSQL' -Directory -ErrorAction SilentlyContinue |
    Sort-Object { [int]$_.Name } -Descending |
    Select-Object -First 1
if (-not $postgres) { throw 'No se encontró PostgreSQL.' }

$createdb = Join-Path $postgres.FullName 'bin\createdb.exe'
$dropdb = Join-Path $postgres.FullName 'bin\dropdb.exe'
$pgRestore = Join-Path $postgres.FullName 'bin\pg_restore.exe'
$psql = Join-Path $postgres.FullName 'bin\psql.exe'
$baseTemporal = 'prestamos_restore_test_' + (Get-Date -Format 'yyyyMMdd_HHmmss')
$pgpassTemporal = Join-Path ([IO.Path]::GetTempPath()) ("pgpass-$baseTemporal.conf")
$pgpassAnterior = $env:PGPASSFILE

if (-not $env:PGPASSWORD) {
    $pgpassLocal = Join-Path $env:APPDATA 'postgresql\pgpass.conf'
    if (-not (Test-Path -LiteralPath $pgpassLocal)) { throw 'No existe la credencial local de PostgreSQL.' }
    $prefijo = "${Servidor}:${Puerto}:${BaseCredencial}:${Usuario}:"
    $linea = Get-Content -LiteralPath $pgpassLocal | Where-Object { $_.StartsWith($prefijo) } | Select-Object -First 1
    if (-not $linea) { throw "No existe una credencial local para $BaseCredencial." }
    $secreto = $linea.Substring($prefijo.Length)
    Set-Content -LiteralPath $pgpassTemporal -Encoding ascii -Value @(
        "${Servidor}:${Puerto}:postgres:${Usuario}:${secreto}",
        "${Servidor}:${Puerto}:${baseTemporal}:${Usuario}:${secreto}"
    )
    & icacls.exe $pgpassTemporal /inheritance:r /grant:r "${env:USERNAME}:(R,W)" | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'No se pudo proteger la credencial temporal.' }
    $env:PGPASSFILE = $pgpassTemporal
}

try {
    & $createdb --host=$Servidor --port=$Puerto --username=$Usuario --no-password $baseTemporal
    if ($LASTEXITCODE -ne 0) { throw 'No se pudo crear la base temporal de verificación.' }

    & $pgRestore --host=$Servidor --port=$Puerto --username=$Usuario --dbname=$baseTemporal --no-owner --no-privileges --exit-on-error --no-password $archivoResuelto
    if ($LASTEXITCODE -ne 0) { throw 'La restauración de prueba falló.' }

    $consulta = "SELECT 'clientes=' || count(*) FROM prestamos.cliente UNION ALL SELECT 'prestamos=' || count(*) FROM prestamos.prestamos UNION ALL SELECT 'pagos=' || count(*) FROM prestamos.pagos UNION ALL SELECT 'recibos=' || count(*) FROM prestamos.recibos_pago;"
    $conteos = & $psql --host=$Servidor --port=$Puerto --username=$Usuario --dbname=$baseTemporal --no-password --tuples-only --no-align --command=$consulta
    if ($LASTEXITCODE -ne 0) { throw 'La base fue restaurada, pero no superó la validación de tablas.' }

    Write-Host 'Restauración verificada correctamente.' -ForegroundColor Green
    $conteos | ForEach-Object { Write-Host $_ }
}
finally {
    & $dropdb --host=$Servidor --port=$Puerto --username=$Usuario --if-exists --force --no-password $baseTemporal 2>$null
    if ($null -eq $pgpassAnterior) { Remove-Item Env:PGPASSFILE -ErrorAction SilentlyContinue }
    else { $env:PGPASSFILE = $pgpassAnterior }
    Remove-Item -LiteralPath $pgpassTemporal -Force -ErrorAction SilentlyContinue
}
