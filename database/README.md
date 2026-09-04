# Base de datos de SistemaPrestamosWeb

Esta carpeta contiene la definición versionada de PostgreSQL que usa el sistema de préstamos SAN y Rédito.

## Objetivo

La base de datos se versiona en Git mediante archivos SQL. Git conserva estructura, migraciones, catálogos y datos ficticios de prueba. No se deben versionar datos reales de clientes, contraseñas, cadenas de conexión ni respaldos de producción.

## Estructura

```text
database/
├── schema/
│   └── 001_schema_inicial.sql
├── migrations/
│   ├── 002_reenganche_san.sql
│   ├── 003_anulacion_pagos.sql
│   ├── 004_cierre_caja.sql
│   └── 005_usuarios_roles.sql
├── seeds/
│   ├── 001_catalogos.sql
│   └── 002_datos_prueba.sql
└── tests/
    ├── README.md
    ├── 001_smoke_schema.sql
    ├── 002_reglas_san.sql
    ├── 003_reglas_redito.sql
    └── 004_anulacion_pagos.sql
```

## Base de desarrollo

Use una base separada de la base real. El nombre recomendado actualmente es:

```text
prestamos_san_redito_web_dev
```

Nunca ejecute pruebas destructivas sobre la base de producción.

## Crear una base desde cero

Ejemplo desde PowerShell, suponiendo que PostgreSQL está disponible en PATH:

```powershell
createdb -U postgres -h localhost prestamos_san_redito_web_dev
psql -U postgres -h localhost -d prestamos_san_redito_web_dev -f .\database\schema\001_schema_inicial.sql
```

`001_schema_inicial.sql` fue generado con `pg_dump --schema-only`, por lo que contiene estructura, funciones, vistas, índices y restricciones, pero no datos de negocio.

## Migraciones

El esquema inicial representa una fotografía completa de la estructura actual. Las migraciones se conservan porque documentan la evolución del sistema y permiten revisar cambios específicos.

En una base que ya contiene el esquema inicial actualizado no deben reaplicarse automáticamente todas las migraciones sin verificar primero si sus cambios ya están presentes.

## Catálogos

Para insertar los valores básicos requeridos por las funciones y el backend:

```powershell
psql -U postgres -h localhost -d prestamos_san_redito_web_dev -f .\database\seeds\001_catalogos.sql
```

Este script es idempotente: puede ejecutarse más de una vez sin duplicar los valores conocidos.

## Datos ficticios de prueba

Solo en una base de desarrollo:

```powershell
psql -U postgres -h localhost -d prestamos_san_redito_web_dev -f .\database\seeds\002_datos_prueba.sql
```

Los registros creados por ese script están identificados como datos de prueba y no representan clientes reales.

## Pruebas SQL

Las pruebas de `database/tests` usan transacciones y terminan con `ROLLBACK`, por lo que validan reglas de negocio sin conservar las operaciones de prueba.

Ejemplo:

```powershell
psql -U postgres -h localhost -d prestamos_san_redito_web_dev -v ON_ERROR_STOP=1 -f .\database\tests\001_smoke_schema.sql
psql -U postgres -h localhost -d prestamos_san_redito_web_dev -v ON_ERROR_STOP=1 -f .\database\tests\002_reglas_san.sql
psql -U postgres -h localhost -d prestamos_san_redito_web_dev -v ON_ERROR_STOP=1 -f .\database\tests\003_reglas_redito.sql
psql -U postgres -h localhost -d prestamos_san_redito_web_dev -v ON_ERROR_STOP=1 -f .\database\tests\004_anulacion_pagos.sql
```

## Generar nuevamente el esquema

Cuando la base de desarrollo cambie y se decida actualizar la fotografía completa:

```powershell
pg_dump `
  -U postgres `
  -h localhost `
  --schema-only `
  --no-owner `
  --no-privileges `
  -d prestamos_san_redito_web_dev `
  -f .\database\schema\001_schema_inicial.sql `
  -W
```

Antes de hacer commit, confirme que el archivo no contiene sentencias de carga de datos fuera del código de funciones.

## Seguridad

No guardar en Git:

- `appsettings.Development.json`
- contraseñas PostgreSQL
- claves JWT
- archivos `.dump`
- respaldos reales
- datos personales de clientes
- recibos o reportes con información real

Los secretos del backend deben mantenerse en configuración local o en un gestor de secretos.