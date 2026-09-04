# Pruebas SQL de la base de datos

Estas pruebas validan reglas críticas del negocio directamente en PostgreSQL.

## Principios

- Ejecutar solo sobre `prestamos_san_redito_web_dev` o una base temporal.
- Usar `-v ON_ERROR_STOP=1` para que `psql` termine ante la primera falla.
- Cada prueba funcional abre una transacción y termina con `ROLLBACK`.
- Los datos creados por una prueba no deben permanecer en la base.

## Archivos

- `001_smoke_schema.sql`: comprueba objetos esenciales del esquema.
- `002_reglas_san.sql`: valida cálculo y calendario de un préstamo SAN.
- `003_reglas_redito.sql`: valida que el rédito no reduzca capital y que un abono a capital sí lo haga.
- `004_anulacion_pagos.sql`: valida reversión de pagos SAN y de abonos a capital.

## Ejecución

Desde la raíz del repositorio:

```powershell
psql -U postgres -h localhost -d prestamos_san_redito_web_dev -v ON_ERROR_STOP=1 -f .\database\tests\001_smoke_schema.sql
psql -U postgres -h localhost -d prestamos_san_redito_web_dev -v ON_ERROR_STOP=1 -f .\database\tests\002_reglas_san.sql
psql -U postgres -h localhost -d prestamos_san_redito_web_dev -v ON_ERROR_STOP=1 -f .\database\tests\003_reglas_redito.sql
psql -U postgres -h localhost -d prestamos_san_redito_web_dev -v ON_ERROR_STOP=1 -f .\database\tests\004_anulacion_pagos.sql
```

Una prueba aprobada termina sin `ERROR`. Los bloques `DO` emiten mensajes `NOTICE` con sufijo `_OK` para facilitar la revisión manual.
