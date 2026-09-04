# Validación de la base candidata

Base: `prestamos_san_redito_web_sync_test`

Fecha: 2026-08-07

## Resultado

La candidata fue creada desde el respaldo original verificado y recibió las
migraciones de reenganche, anulación de pagos, cierre de caja y usuarios/roles.

| Control | Resultado |
|---|---:|
| Clientes | 28 |
| Préstamos | 28 |
| Pagos | 120 |
| Recibos | 120 |
| Cuotas del plan | 181 |
| Usuarios administradores activos | 1 |
| Reenganches históricos | 1 |
| Recibos sin pago | 0 |
| Pagos sin recibo | 0 |
| Planes SAN incompletos | 0 |
| Balances negativos | 0 |
| Cuotas históricas sin vincular | 0 |
| Vínculos de cuota inconsistentes | 0 |
| Rutas PDF absolutas | 0 |

## Reenganche histórico preservado

El préstamo 28 conserva como origen el préstamo 20, un saldo absorbido de
RD$1,000 y un efectivo entregado de RD$70,000. Esta operación permanece fuera
de los cobros de caja porque el saldo absorbido no representa entrada de
efectivo.

## Seguridad y recuperación

- El administrador activo coincide con el de la base web anterior.
- La candidata fue respaldada en formato personalizado de PostgreSQL.
- Su respaldo fue restaurado correctamente en una base temporal.
- Backend y frontend compilaron sin errores.

La conexión normal de la aplicación todavía apunta a
`prestamos_san_redito_web_dev`. No se realizó el cambio definitivo.
