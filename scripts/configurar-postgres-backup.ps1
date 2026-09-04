[CmdletBinding()]
param(
    [string]$Servidor = 'localhost',
    [int]$Puerto = 5432,
    [string]$BaseDatos = 'prestamos_san_redito_web_dev',
    [string]$Usuario = 'postgres'
)

$ErrorActionPreference = 'Stop'
$clave = Read-Host 'Escriba la clave de PostgreSQL' -AsSecureString
$ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($clave)

try {
    $claveTexto = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
    $directorio = Join-Path $env:APPDATA 'postgresql'
    $archivo = Join-Path $directorio 'pgpass.conf'
    New-Item -ItemType Directory -Path $directorio -Force | Out-Null

    $escapada = $claveTexto.Replace('\', '\\').Replace(':', '\:')
    $linea = "${Servidor}:${Puerto}:${BaseDatos}:${Usuario}:${escapada}"
    $lineas = if (Test-Path $archivo) { @(Get-Content $archivo) } else { @() }
    $prefijo = "${Servidor}:${Puerto}:${BaseDatos}:${Usuario}:"
    $lineas = @($lineas | Where-Object { -not $_.StartsWith($prefijo) }) + $linea
    Set-Content -LiteralPath $archivo -Value $lineas -Encoding ascii

    & icacls.exe $archivo /inheritance:r /grant:r "${env:USERNAME}:(R,W)" | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'No se pudieron proteger los permisos de pgpass.conf.' }

    Write-Host "Acceso guardado de forma local y protegido para $BaseDatos." -ForegroundColor Green
}
finally {
    if ($ptr -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
    $claveTexto = $null
}
