# Guía maestra de desarrollo — SistemaPrestamosWeb

> Documento de referencia permanente para continuar, revisar y terminar el proyecto de forma ordenada, segura y coherente.
>
> **Regla principal:** antes de crear una tabla, módulo, función, vista o pantalla nueva, verificar primero si ya existe soporte en la base de datos, backend o frontend. El proyecto ya contiene bastante lógica funcional y no debe duplicarse.

---

## 1. Propósito del proyecto

**SistemaPrestamosWeb** es una aplicación web para administrar un negocio de préstamos informales de tipo **SAN** y **Rédito**.

El objetivo funcional es centralizar:

- clientes;
- préstamos SAN;
- préstamos a Rédito;
- reenganches SAN;
- planes de cuotas;
- pagos;
- abonos a capital;
- pagos mixtos;
- atrasos;
- recibos;
- cierre de caja;
- usuarios y roles;
- reportes;
- historial y auditoría;
- control operativo de cobranza;
- evolución futura hacia una administración completa de cartera y caja.

La aplicación debe poder responder preguntas operativas como:

- ¿Cuánto dinero está prestado?
- ¿Cuánto se ha cobrado?
- ¿Cuánto queda pendiente?
- ¿Qué clientes tienen atraso?
- ¿A quién corresponde cobrar hoy?
- ¿Qué préstamos vencen próximamente?
- ¿Cuál es el historial completo de un cliente?
- ¿Qué usuario realizó o anuló una operación?
- ¿Cuánto efectivo debería existir realmente en caja?

---

## 2. Arquitectura actual

### Backend

- ASP.NET Core Web API
- .NET 10
- Npgsql
- PostgreSQL
- JWT
- QuestPDF

Ubicación:

```text
backend/SistemaPrestamos.Api/
```

### Frontend

- React
- TypeScript
- Vite
- Oxlint

Ubicación:

```text
frontend/
```

### Base de datos

PostgreSQL con esquema principal:

```text
prestamos
```

Base recomendada para desarrollo:

```text
prestamos_san_redito_web_dev
```

La base real de producción/original no debe utilizarse para pruebas de escritura.

### Versionado de base de datos

```text
database/
├── README.md
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

---

## 3. Estado funcional confirmado

La siguiente tabla representa el estado conocido del sistema después de revisar GitHub, el esquema PostgreSQL, backend y frontend.

| Módulo | Base de datos | Backend | Frontend | Estado |
|---|---|---|---|---|
| Autenticación | Sí | Sí | Sí | Completo |
| Roles ADMIN / COBRADOR / CONSULTA | Sí | Sí | Sí | Completo |
| Clientes | Sí | Sí | Sí | Parcial |
| Préstamos SAN | Sí | Sí | Sí | Funcional |
| Préstamos Rédito | Sí | Sí | Sí | Funcional |
| Reenganche SAN | Sí | Sí | Sí | Funcional |
| Plan de cuotas SAN | Sí | Sí | Sí | Funcional |
| Pagos SAN | Sí | Sí | Sí | Funcional |
| Pago de Rédito | Sí | Sí | Sí | Funcional |
| Abono a capital | Sí | Sí | Sí | Funcional |
| Pago mixto | Sí | Sí | Sí | Funcional |
| Anulación de pagos | Sí | Sí | Sí | Funcional |
| Recibos PDF | Sí | Sí | Sí | Funcional |
| Dashboard | Sí | Sí | Sí | Funcional |
| Atrasos | Sí | Sí | Sí | Funcional |
| Reportes | Sí | Sí | Sí | Funcional |
| Cierre de caja | Sí | Sí | Sí | Parcial |
| Historial del préstamo | Sí | Parcial | Parcial/no centralizado | Parcial |
| Auditoría de usuarios | Sí | Sí | No | Parcial |
| Movimientos de caja | Sí | No integrado claramente | No | Pendiente |
| Cobros del día | Datos disponibles | No | No | Pendiente |
| Próximos vencimientos | Datos disponibles | No | No | Pendiente |
| Expediente completo del cliente | Parcial | Parcial | Parcial | Pendiente |
| Historial crediticio | Datos disponibles | Parcial | No | Pendiente |
| Gastos / egresos | Base parcial | No | No | Pendiente |
| Auditoría global | Parcial | Parcial | No | Pendiente |
| Pruebas automatizadas | Sí | En desarrollo | N/A | Parcial |

---

## 4. Reglas financieras ya verificadas

Las siguientes pruebas se ejecutaron contra la base de desarrollo PostgreSQL y pasaron correctamente:

```text
SMOKE_SCHEMA_OK
REGLAS_SAN_OK
REGLAS_REDITO_OK
ANULACION_SAN_OK
ANULACION_CAPITAL_OK
```

Las pruebas funcionales están diseñadas con:

```sql
BEGIN;
...
ROLLBACK;
```

para evitar que los datos creados durante la prueba queden almacenados.

### SAN

La función de creación debe:

- crear el préstamo;
- calcular `total_a_pagar = cuota * cantidad_periodos`;
- crear el plan de pagos;
- generar las fechas según la frecuencia;
- mantener consistencia entre monto programado, monto pagado y estado de cuota;
- colocar el préstamo en SALDADO cuando todas las cuotas hayan sido pagadas.

### Rédito

Debe distinguir claramente:

- pago de rédito;
- abono a capital;
- pago mixto.

Un pago de rédito no debe reducir el capital pendiente.

Un abono a capital sí debe reducir `capital_pendiente`.

### Anulación

La anulación debe revertir correctamente el efecto financiero del pago y conservar trazabilidad.

La lógica actual exige motivo y registra información de anulación.

---

## 5. Tablas y elementos existentes que deben aprovecharse

Antes de crear nuevas estructuras debe revisarse especialmente lo siguiente.

### `prestamos.cliente`

Actualmente almacena:

```text
id_cliente
nombre
telefono
direccion
documento
estado
fecha_registro
```

Es suficiente como base inicial, pero la experiencia de usuario todavía debe evolucionar hacia una ficha completa del cliente.

### `prestamos.historial_prestamos`

Ya registra eventos importantes, por ejemplo:

```text
PAGO_ANULADO
REENGANCHE_APLICADO
REENGANCHE_CREADO
ORIGEN_REENGANCHE
```

**No crear otra tabla de historial de préstamos sin necesidad.**

El trabajo pendiente es exponer este historial correctamente mediante API y frontend.

### `prestamos.auditoria_usuarios`

Ya existe y el backend registra acciones relacionadas con administración de usuarios.

Trabajo pendiente:

- consulta administrativa;
- interfaz para ADMIN;
- ampliación gradual a otras operaciones críticas.

### `prestamos.movimientos_caja`

Ya existe con estructura para movimientos financieros.

Debe convertirse en el núcleo del futuro módulo de caja completa.

No crear una segunda tabla de movimientos salvo que exista una razón técnica demostrable.

### `prestamos.plan_pagos`

Contiene las fechas de vencimiento necesarias para:

- atrasos;
- cobros de hoy;
- cobros de mañana;
- próximos siete días;
- seguimiento de cuotas parciales.

No hace falta una tabla adicional para calendario de cobros SAN.

---

## 6. Limitaciones actuales identificadas

### 6.1 Clientes

Actualmente el módulo de clientes sirve para registrar y listar información básica, pero todavía no es una ficha crediticia completa.

Debe evolucionar a una vista central por cliente con:

```text
Datos personales
Préstamos activos
Préstamos saldados
Préstamos atrasados
Pagos
Recibos
Reenganches
Atrasos
Historial
Resumen financiero
```

### 6.2 Cobranza

El sistema identifica atrasos, pero todavía falta una herramienta diaria de cobranza.

Debe existir una vista:

```text
COBROS DE HOY
```

con al menos:

- cliente;
- préstamo;
- número de cuota;
- monto programado;
- monto pagado;
- saldo de la cuota;
- teléfono;
- estado.

Posteriormente:

```text
Hoy
Mañana
Próximos 7 días
Atrasados
```

### 6.3 Historial crediticio

No debe comenzar con un score inventado.

Primero mostrar indicadores objetivos derivados de la información real:

```text
Cantidad total de préstamos
Préstamos saldados
Préstamos activos
Préstamos atrasados
Total histórico prestado
Total histórico pagado
Saldo pendiente
Mayor atraso
Cuotas vencidas actuales
Cantidad de reenganches
```

Cuando estos indicadores estén validados se podrá evaluar una clasificación como Bueno/Regular/Riesgoso.

### 6.4 Caja

El cierre actual sirve principalmente como control de pagos cobrados.

La meta es una caja financiera completa:

```text
Saldo inicial
+ Cobros
+ Otros ingresos
- Desembolsos de préstamos
- Efectivo entregado por reenganches
- Gastos
- Retiros
= Saldo esperado
```

Debe aprovecharse `prestamos.movimientos_caja`.

### 6.5 Auditoría

Existe auditoría de usuarios, pero no una auditoría transversal completa.

Operaciones que deben dejar trazabilidad clara:

```text
CREAR_CLIENTE
EDITAR_CLIENTE
CREAR_PRESTAMO
CAMBIAR_ESTADO_PRESTAMO
REGISTRAR_PAGO
ANULAR_PAGO
CREAR_REENGANCHE
CERRAR_CAJA
REGISTRAR_GASTO
CREAR_USUARIO
CAMBIAR_ROL
DESACTIVAR_USUARIO
```

---

## 7. Hoja de ruta recomendada

### Fase 1 — Aprovechar lo existente

Orden recomendado:

1. Ficha completa del cliente.
2. Historial del préstamo.
3. Historial crediticio del cliente.
4. Cobros del día.
5. Próximos vencimientos.

**Objetivo:** mejorar la operación cotidiana sin alterar todavía la lógica financiera principal.

### Fase 2 — Caja completa

6. Integrar `movimientos_caja` con el backend.
7. Registrar desembolsos de préstamos.
8. Registrar efectivo entregado en reenganches.
9. Registrar gastos.
10. Registrar otros ingresos/egresos.
11. Mejorar cierre de caja.

### Fase 3 — Control y trazabilidad

12. Auditoría global.
13. Más pruebas automáticas.
14. Reportes adicionales.
15. Validaciones de integridad financiera.

### Fase 4 — Expansión

16. PWA / experiencia móvil.
17. Notificaciones.
18. Recordatorios de cobro.
19. Integraciones externas si el negocio realmente las requiere.

---

## 8. Próximo módulo recomendado: Ficha del Cliente

Este debe ser el siguiente desarrollo funcional porque:

- no requiere cambiar las reglas financieras ya validadas;
- reutiliza información existente;
- mejora inmediatamente el uso del sistema;
- servirá como punto de entrada al historial crediticio.

### Objetivo visual

Ejemplo conceptual:

```text
JUAN PÉREZ
Cédula: 000-0000000-0
Teléfono: 809-000-0000
Estado: ACTIVO

Resumen
------------------------------------------------
Préstamos totales        7
Saldados                 5
Activos                  1
Atrasados                1
Total histórico          RD$95,000
Saldo actual             RD$12,500
Mayor atraso             14 días

[Préstamos] [Pagos] [Recibos] [Historial]
```

### Backend requerido

Idealmente debe existir un endpoint de detalle de cliente, por ejemplo:

```text
GET /api/clientes/{id}
```

Puede devolver:

- datos del cliente;
- resumen de cartera;
- préstamos;
- atrasos;
- historial agregado.

No se debe construir una consulta gigantesca sin necesidad. Puede dividirse en endpoints especializados si mejora mantenimiento y rendimiento.

---

## 9. Próximas pruebas requeridas

Agregar gradualmente:

```text
005_reenganche.sql
006_cierre_caja.sql
007_roles_permisos.sql
008_atrasos.sql
009_recibos.sql
010_movimientos_caja.sql
```

Cada prueba financiera debe:

1. preparar únicamente los datos mínimos requeridos;
2. validar resultados con condiciones explícitas;
3. lanzar excepción si algo no coincide;
4. usar `ROLLBACK` cuando sea posible;
5. evitar depender de clientes reales existentes.

---

## 10. Flujo correcto para cambios en base de datos

### Nunca modificar directamente la base de producción como primer paso

Toda evolución de estructura debe seguir este patrón:

```text
1. Analizar necesidad
2. Revisar schema actual
3. Confirmar que la estructura no existe
4. Crear nueva migración SQL
5. Ejecutarla en prestamos_san_redito_web_dev
6. Crear/actualizar prueba SQL
7. Ejecutar pruebas
8. Actualizar backend
9. Actualizar frontend
10. Ejecutar build + lint + pruebas
11. Commit
12. Push
```

### Nomenclatura

Las migraciones deben seguir secuencia:

```text
006_nombre_descriptivo.sql
007_nombre_descriptivo.sql
...
```

No editar una migración ya aplicada para cambiar la historia del proyecto salvo que se esté corrigiendo un error antes de que dicha migración haya sido distribuida/aplicada.

---

## 11. Regeneración del esquema base

El archivo:

```text
database/schema/001_schema_inicial.sql
```

es una fotografía estructural de la base de desarrollo.

Puede regenerarse mediante `pg_dump` solo después de confirmar que la base de desarrollo representa correctamente la estructura deseada.

Ejemplo:

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

No incluir dumps con datos reales en Git.

---

## 12. Seguridad y datos sensibles

No subir al repositorio:

```text
appsettings.Development.json
.env
contraseñas
JWT secrets
connection strings reales
dumps de producción
backups reales
documentos de clientes
cédulas reales
teléfonos reales
recibos PDF reales
logs con información sensible
```

El `.gitignore` debe seguir excluyendo:

```text
.vs/
*.csproj.user
**/bin/
**/obj/
frontend/node_modules/
frontend/dist/
.env
scripts/backups/
scripts/logs/
output/
tmp/
```

---

## 13. Reglas de trabajo para mantener el proyecto limpio

### Antes de programar

- revisar GitHub;
- revisar la base versionada;
- revisar controladores existentes;
- revisar servicios/repositorios existentes;
- revisar la pantalla equivalente más cercana;
- revisar roles y permisos;
- revisar pruebas existentes.

### Al crear un módulo nuevo

Debe conservar:

- estilo visual del resto de la aplicación;
- manejo común de errores;
- autorización del backend;
- restricciones de rol;
- nomenclatura existente;
- consultas parametrizadas;
- transacciones cuando corresponda;
- trazabilidad en operaciones sensibles.

### No aceptar una funcionalidad como terminada solamente porque compila

Debe verificarse:

```text
Build backend
Lint frontend
Build frontend
Prueba de base de datos
Prueba funcional del caso de negocio
Permisos por rol
Estados antes/después
No regresión de módulos relacionados
```

---

## 14. Definition of Done (DoD)

Una funcionalidad se considera terminada cuando cumple todos los puntos aplicables:

- [ ] Requisito funcional claramente definido.
- [ ] Se verificó que no duplicaba funcionalidad existente.
- [ ] Migración versionada si hubo cambio de BD.
- [ ] Consulta/función SQL probada.
- [ ] Backend implementado.
- [ ] Autorización validada.
- [ ] Frontend implementado.
- [ ] Manejo de estados vacío/carga/error.
- [ ] Responsive básico.
- [ ] Prueba automatizada o script reproducible.
- [ ] `dotnet build` exitoso.
- [ ] `npm run lint` exitoso.
- [ ] `npm run build` exitoso.
- [ ] GitHub Actions exitoso.
- [ ] Sin secretos ni datos sensibles.
- [ ] Documentación actualizada.

---

## 15. Comandos frecuentes de validación

### Estado Git

```powershell
git status -sb
```

### Sincronizar

```powershell
git pull origin main
```

### Backend

```powershell
dotnet build .\backend\SistemaPrestamos.Api\SistemaPrestamos.Api.csproj
```

### Frontend

```powershell
Set-Location .\frontend
npm ci
npm run lint
npm run build
Set-Location ..
```

### Smoke test de base de datos

```powershell
psql -U postgres -h localhost -d prestamos_san_redito_web_dev -v ON_ERROR_STOP=1 -f .\database\tests\001_smoke_schema.sql
```

### Reglas SAN

```powershell
psql -U postgres -h localhost -d prestamos_san_redito_web_dev -v ON_ERROR_STOP=1 -f .\database\tests\002_reglas_san.sql
```

### Reglas Rédito

```powershell
psql -U postgres -h localhost -d prestamos_san_redito_web_dev -v ON_ERROR_STOP=1 -f .\database\tests\003_reglas_redito.sql
```

### Anulación

```powershell
psql -U postgres -h localhost -d prestamos_san_redito_web_dev -v ON_ERROR_STOP=1 -f .\database\tests\004_anulacion_pagos.sql
```

---

## 16. Estado de prioridad para la próxima sesión

### Prioridad inmediata

```text
1. Ficha completa del cliente
2. Historial del préstamo
3. Historial crediticio
4. Cobros del día
5. Próximos vencimientos
```

### Después

```text
6. Movimientos de caja
7. Gastos y egresos
8. Cierre de caja completo
9. Auditoría global
10. Pruebas faltantes
```

---

## 17. Regla de continuidad para futuras sesiones o asistentes

Cuando se retome el proyecto:

1. Leer primero este archivo.
2. Revisar `git status -sb`.
3. Revisar el último commit de `main`.
4. No asumir que una tarea pendiente sigue pendiente: comprobar el código actual.
5. No crear tablas ni servicios nuevos antes de buscar equivalentes existentes.
6. No alterar reglas financieras SAN/Rédito sin pruebas que demuestren el cambio.
7. Actualizar este documento cuando cambie de forma significativa el estado del proyecto.

Este archivo debe funcionar como **memoria técnica del proyecto y hoja de ruta**, no como documentación de usuario final.
