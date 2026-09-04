# Copia segura de PostgreSQL

1. No modificar la base original `prestamos_san_redito`.
2. Crear `prestamos_san_redito_web_dev` desde pgAdmin o `createdb`.
3. Restaurar en ella `respaldo_completo_prestamos.sql`.
4. Copiar `appsettings.Development.example.json` como `appsettings.Development.json` y completar los secretos localmente.
5. Comparar conteos de `cliente`, `prestamos`, `pagos`, `plan_pagos` y `recibos_pago` antes de probar escrituras.

`appsettings.Development.json` está ignorado por Git y no debe compartirse.

## Copias automáticas

Los respaldos usan el formato personalizado de PostgreSQL, se verifican antes de
publicarse y se guardan en `scripts/backups`. La base original no se utiliza.

La tarea diaria protege por separado `prestamos_san_redito` y
`prestamos_san_redito_web_dev`. Sus resultados se registran mensualmente en
`scripts/logs`.

```powershell
Set-Location "C:\Users\elmacho\Downloads\SistemaPrestamosWeb"
.\scripts\configurar-postgres-backup.ps1
.\scripts\respaldar-postgres.ps1
$ultima = Get-ChildItem .\scripts\backups\*.dump | Sort-Object LastWriteTime -Descending | Select-Object -First 1
.\scripts\probar-restauracion.ps1 -Archivo $ultima.FullName
```

Para instalar una tarea diaria a las 10:00 p. m. con 30 días de retención,
abra PowerShell como administrador y ejecute:

```powershell
.\scripts\instalar-backup-diario.ps1 -Hora '22:00' -RetencionDias 30
```

`probar-restauracion.ps1` crea una base temporal, valida tablas principales y la
elimina al terminar. Nunca restaura encima de la base activa.
