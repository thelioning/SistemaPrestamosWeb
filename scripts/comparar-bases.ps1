[CmdletBinding()]
param(
    [string]$BaseOriginal = 'prestamos_san_redito',
    [string]$BaseWeb = 'prestamos_san_redito_web_dev',
    [string]$DirectorioSalida = (Join-Path $PSScriptRoot '..\output\comparacion')
)

$ErrorActionPreference = 'Stop'
$postgres = Get-ChildItem 'C:\Program Files\PostgreSQL' -Directory -ErrorAction SilentlyContinue |
    Sort-Object { [int]$_.Name } -Descending | Select-Object -First 1
if (-not $postgres) { throw 'No se encontró PostgreSQL.' }
$psql = Join-Path $postgres.FullName 'bin\psql.exe'

$consultas = [ordered]@{
    clientes = @{
        Key = 'id_cliente'
        Sql = "SELECT row_to_json(x)::text FROM (SELECT id_cliente,nombre,telefono,direccion,documento,estado FROM prestamos.cliente ORDER BY id_cliente) x"
    }
    prestamos = @{
        Key = 'id_prestamo'
        Sql = "SELECT row_to_json(x)::text FROM (SELECT p.id_prestamo,p.id_cliente,tp.nombre tipo,f.nombre frecuencia,e.nombre estado,p.monto_prestado,p.cuota,p.cantidad_periodos,p.total_a_pagar,p.monto_redito,p.capital_pendiente,p.fecha_inicio,p.fecha_fin_estimada,p.observacion FROM prestamos.prestamos p JOIN prestamos.tipos_prestamo tp ON tp.id_tipo_prestamos=p.id_tipo_prestamos JOIN prestamos.frecuencias_pago f ON f.id_frecuencia=p.id_frecuencia JOIN prestamos.estados_prestamo e ON e.id_estado_prestamo=p.id_estado_prestamo ORDER BY p.id_prestamo) x"
    }
    pagos = @{
        Key = 'id_pago'
        Sql = "SELECT row_to_json(x)::text FROM (SELECT p.id_pago,p.id_prestamo,tp.nombre tipo_pago,p.fecha_pago,p.monto_pagado,p.observacion FROM prestamos.pagos p JOIN prestamos.tipos_pago tp ON tp.id_tipo_pago=p.id_tipo_pago ORDER BY p.id_pago) x"
    }
    recibos = @{
        Key = 'id_recibo'
        Sql = "SELECT row_to_json(x)::text FROM (SELECT id_recibo,id_pago,numero_recibo,estado FROM prestamos.recibos_pago ORDER BY id_recibo) x"
    }
    plan_pagos = @{
        Key = 'id_plan_pago'
        Sql = "SELECT row_to_json(x)::text FROM (SELECT id_plan_pago,id_prestamo,numero_cuota,fecha_vencimiento,monto_programado,monto_pagado,estado FROM prestamos.plan_pagos ORDER BY id_plan_pago) x"
    }
    detalle_pagos = @{
        Key = 'id_detalle_pago'
        Sql = "SELECT row_to_json(x)::text FROM (SELECT id_detalle_pago,id_pago,concepto,monto FROM prestamos.detalle_pagos ORDER BY id_detalle_pago) x"
    }
}

function Consultar([string]$Base, [string]$Sql) {
    $salida = @(& $psql --host=localhost --port=5432 --username=postgres --dbname=$Base --no-password --no-psqlrc --tuples-only --no-align --command=$Sql)
    if ($LASTEXITCODE -ne 0) { throw "Falló la lectura de $Base." }
    return @($salida | Where-Object { $_ } | ForEach-Object { $_ | ConvertFrom-Json })
}

function Canonico($Fila, [string]$Clave) {
    $objeto = [ordered]@{}
    foreach ($propiedad in ($Fila.PSObject.Properties | Where-Object Name -ne $Clave | Sort-Object Name)) {
        $objeto[$propiedad.Name] = $propiedad.Value
    }
    return ($objeto | ConvertTo-Json -Compress -Depth 5)
}

function Escapar([object]$Valor) {
    if ($null -eq $Valor) { return '' }
    return ([string]$Valor).Replace('|','\|').Replace("`r",' ').Replace("`n",' ')
}

New-Item -ItemType Directory -Path $DirectorioSalida -Force | Out-Null
$resultado = [ordered]@{ generado = (Get-Date).ToString('s'); original = $BaseOriginal; web = $BaseWeb; tablas = [ordered]@{} }
$datos = @{}

foreach ($nombre in $consultas.Keys) {
    $def = $consultas[$nombre]
    $original = @(Consultar $BaseOriginal $def.Sql)
    $web = @(Consultar $BaseWeb $def.Sql)
    $datos[$nombre] = @{ original=$original; web=$web }
    $mapOriginal = @{}; $mapWeb = @{}
    foreach ($fila in $original) { $mapOriginal[[string]$fila.($def.Key)] = $fila }
    foreach ($fila in $web) { $mapWeb[[string]$fila.($def.Key)] = $fila }
    $faltantes = @($mapOriginal.Keys | Where-Object { -not $mapWeb.ContainsKey($_) } | Sort-Object {[int]$_})
    $adicionales = @($mapWeb.Keys | Where-Object { -not $mapOriginal.ContainsKey($_) } | Sort-Object {[int]$_})
    $modificados = @()
    foreach ($id in ($mapOriginal.Keys | Where-Object { $mapWeb.ContainsKey($_) } | Sort-Object {[int]$_})) {
        if ((Canonico $mapOriginal[$id] $def.Key) -ne (Canonico $mapWeb[$id] $def.Key)) {
            $campos = @()
            foreach ($p in ($mapOriginal[$id].PSObject.Properties | Where-Object Name -ne $def.Key)) {
                $a = $p.Value | ConvertTo-Json -Compress
                $b = $mapWeb[$id].($p.Name) | ConvertTo-Json -Compress
                if ($a -ne $b) { $campos += $p.Name }
            }
            $modificados += [ordered]@{ id=[int]$id; campos=$campos; original=$mapOriginal[$id]; web=$mapWeb[$id] }
        }
    }
    $resultado.tablas[$nombre] = [ordered]@{
        total_original=$original.Count; total_web=$web.Count; faltantes_en_web=@($faltantes | ForEach-Object {[int]$_}); adicionales_en_web=@($adicionales | ForEach-Object {[int]$_}); modificados=$modificados
    }
}

$json = Join-Path $DirectorioSalida 'comparacion-completa.json'
$resultado | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $json -Encoding utf8

$lineas = [Collections.Generic.List[string]]::new()
$lineas.Add('# Comparación de bases del Sistema de Préstamos')
$lineas.Add('')
$lineas.Add("Generado: $($resultado.generado)")
$lineas.Add('')
$lineas.Add('| Tabla | Original | Web | Faltan en web | Adicionales web | Modificados |')
$lineas.Add('|---|---:|---:|---:|---:|---:|')
foreach ($nombre in $resultado.tablas.Keys) {
    $t=$resultado.tablas[$nombre]
    $lineas.Add("| $nombre | $($t.total_original) | $($t.total_web) | $($t.faltantes_en_web.Count) | $($t.adicionales_en_web.Count) | $($t.modificados.Count) |")
}

$lineas.Add(''); $lineas.Add('## Clientes faltantes en la web'); $lineas.Add('')
$lineas.Add('| ID | Nombre | Documento | Teléfono | Estado |')
$lineas.Add('|---:|---|---|---|---|')
$idsClientes=@($resultado.tablas.clientes.faltantes_en_web)
foreach($c in $datos.clientes.original | Where-Object {$idsClientes -contains $_.id_cliente}) {
    $lineas.Add("| $($c.id_cliente) | $(Escapar $c.nombre) | $(Escapar $c.documento) | $(Escapar $c.telefono) | $(Escapar $c.estado) |")
}

$lineas.Add(''); $lineas.Add('## Préstamos faltantes en la web'); $lineas.Add('')
$lineas.Add('| ID | Cliente | Tipo | Estado | Monto | Inicio |')
$lineas.Add('|---:|---|---|---|---:|---|')
$idsPrestamos=@($resultado.tablas.prestamos.faltantes_en_web)
$clientesOriginal=@{}; foreach($c in $datos.clientes.original){$clientesOriginal[[int]$c.id_cliente]=$c.nombre}
foreach($p in $datos.prestamos.original | Where-Object {$idsPrestamos -contains $_.id_prestamo}) {
    $lineas.Add("| $($p.id_prestamo) | $(Escapar $clientesOriginal[[int]$p.id_cliente]) | $($p.tipo) | $($p.estado) | $($p.monto_prestado) | $($p.fecha_inicio) |")
}

$lineas.Add(''); $lineas.Add('## Pagos faltantes agrupados'); $lineas.Add('')
$lineas.Add('| Préstamo | Cliente | Cantidad | Total | Primera fecha | Última fecha |')
$lineas.Add('|---:|---|---:|---:|---|---|')
$idsPagos=@($resultado.tablas.pagos.faltantes_en_web)
$prestamosOriginal=@{}; foreach($p in $datos.prestamos.original){$prestamosOriginal[[int]$p.id_prestamo]=$p}
$pagosFaltantes=@($datos.pagos.original | Where-Object {$idsPagos -contains $_.id_pago})
foreach($grupo in $pagosFaltantes | Group-Object id_prestamo | Sort-Object {[int]$_.Name}) {
    $p=$prestamosOriginal[[int]$grupo.Name]; $fechas=@($grupo.Group.fecha_pago | Sort-Object)
    $total=($grupo.Group | Measure-Object monto_pagado -Sum).Sum
    $lineas.Add("| $($grupo.Name) | $(Escapar $clientesOriginal[[int]$p.id_cliente]) | $($grupo.Count) | $total | $($fechas[0]) | $($fechas[-1]) |")
}

$lineas.Add(''); $lineas.Add('## Registros modificados'); $lineas.Add('')
foreach($nombre in $resultado.tablas.Keys) {
    $mods=@($resultado.tablas[$nombre].modificados)
    $lineas.Add("- ${nombre}: $($mods.Count)" + $(if($mods.Count){" (IDs: " + (($mods | ForEach-Object id) -join ', ') + ')' }else{''}))
}

$md = Join-Path $DirectorioSalida 'informe-comparacion.md'
$lineas | Set-Content -LiteralPath $md -Encoding utf8
Write-Host "Informe creado: $md" -ForegroundColor Green
Write-Host "Detalle JSON: $json"
