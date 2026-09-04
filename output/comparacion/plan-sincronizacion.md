# Plan seguro de sincronización

## Conclusión

La base `prestamos_san_redito` es la fuente transaccional más reciente. La base
web no contiene clientes, préstamos, pagos, reenganches, anulaciones ni cierres
exclusivos. Por tanto, no se recomienda mezclar manualmente filas en la base web
actual. La opción más segura es construir una tercera base candidata desde la
copia original y aplicar allí las capacidades web.

## Diferencias confirmadas

- 3 clientes faltantes en la web: IDs 26, 27 y 28.
- 6 préstamos faltantes: IDs 23 al 28.
- 46 pagos, 46 detalles y 46 recibos faltantes.
- 51 cuotas de planes de pago faltantes.
- 5 préstamos existentes tienen balances o estados más recientes en la original:
  IDs 3, 7, 10, 18 y 20.
- 22 cuotas existentes reflejan pagos más recientes en la original.
- La original tiene actividad hasta 2026-08-06; la web hasta 2026-07-12.
- La web contiene un administrador que debe preservarse.
- No existen anulaciones, reenganches ni cierres de caja exclusivos en la web.

El préstamo 28 confirma el requisito negociado de más de 13 semanas: tiene 25
semanas de RD$4,000 y un total acordado de RD$100,000.

## Procedimiento propuesto

1. Crear `prestamos_san_redito_web_sync_test` desde la copia verificada más
   reciente de `prestamos_san_redito`.
2. Aplicar en orden las migraciones web 002, 003, 004 y 005.
3. Transferir únicamente el administrador activo desde la base web actual.
4. Mantener los campos históricos originales de préstamos, planes y pagos.
5. Limpiar las rutas absolutas de PDF en la candidata y regenerar recibos desde
   la aplicación cuando sean solicitados.
6. Verificar conteos, relaciones, balances, cuotas, recibos y estados.
7. Conectar temporalmente una instancia local de la aplicación a la candidata y
   ejecutar pruebas funcionales de solo lectura.
8. Comparar los totales visibles con el sistema original.
9. Conservar intactas tanto la base original como la web actual hasta la
   aprobación final.

## Condición para el cambio definitivo

La base candidata solamente podrá sustituir a la base web después de validar:

- 28 clientes, 28 préstamos, 120 pagos y 120 recibos;
- cero relaciones huérfanas;
- cero balances negativos;
- planes SAN completos, incluido el préstamo de 25 semanas;
- acceso correcto del administrador;
- reportes, recibos y cierre de caja operativos.

Este documento no ejecuta ninguna migración ni modifica las bases existentes.
