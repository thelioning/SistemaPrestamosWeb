param(
    [Parameter(Mandatory = $true)]
    [string]$Nombre,
    [Parameter(Mandatory = $true)]
    [string]$Usuario
)

$ErrorActionPreference = 'Stop'
$project = Join-Path $PSScriptRoot '..\backend\SistemaPrestamos.Api\SistemaPrestamos.Api.csproj'
$securePassword = Read-Host 'Escriba la clave (minimo 10 caracteres)' -AsSecureString
$pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword)

try {
    $password = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
    if ($password.Length -lt 10) { throw 'La clave debe tener al menos 10 caracteres.' }

    $secretLine = dotnet user-secrets list --project $project |
        Where-Object { $_ -like 'Setup:Key = *' } |
        Select-Object -First 1
    if (-not $secretLine) { throw 'No se encontró la clave local de configuración.' }
    $setupKey = $secretLine.Substring($secretLine.IndexOf('=') + 1).Trim()

    $body = @{ nombre = $Nombre; usuario = $Usuario; clave = $password } | ConvertTo-Json -Compress
    $utf8Body = [Text.Encoding]::UTF8.GetBytes($body)
    try {
        Invoke-RestMethod -Method Post -Uri 'http://localhost:5159/api/auth/bootstrap' `
            -Headers @{ 'X-Setup-Key' = $setupKey } -ContentType 'application/json; charset=utf-8' `
            -Body $utf8Body | Out-Null
    }
    catch {
        if ($_.Exception.Response) {
            $stream = $_.Exception.Response.GetResponseStream()
            $reader = New-Object IO.StreamReader($stream)
            $detail = $reader.ReadToEnd()
            if ($detail) { Write-Error "El servidor respondio: $detail" }
        }
        throw
    }
    Write-Host 'Administrador creado correctamente.' -ForegroundColor Green
}
finally {
    if ($pointer -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer) }
    $password = $null
}
