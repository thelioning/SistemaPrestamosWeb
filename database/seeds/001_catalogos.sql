BEGIN;

-- Tipos de préstamo requeridos por las funciones crear_prestamo_san y crear_prestamo_redito.
INSERT INTO prestamos.tipos_prestamo(nombre)
SELECT 'SAN'
WHERE NOT EXISTS (SELECT 1 FROM prestamos.tipos_prestamo WHERE UPPER(nombre)='SAN');

INSERT INTO prestamos.tipos_prestamo(nombre)
SELECT 'REDITO'
WHERE NOT EXISTS (SELECT 1 FROM prestamos.tipos_prestamo WHERE UPPER(nombre)='REDITO');

-- Frecuencias utilizadas por la aplicación.
INSERT INTO prestamos.frecuencias_pago(nombre,dias)
SELECT 'SEMANAL',7
WHERE NOT EXISTS (SELECT 1 FROM prestamos.frecuencias_pago WHERE UPPER(nombre)='SEMANAL');

INSERT INTO prestamos.frecuencias_pago(nombre,dias)
SELECT 'QUINCENAL',15
WHERE NOT EXISTS (SELECT 1 FROM prestamos.frecuencias_pago WHERE UPPER(nombre)='QUINCENAL');

INSERT INTO prestamos.frecuencias_pago(nombre,dias)
SELECT 'MENSUAL',30
WHERE NOT EXISTS (SELECT 1 FROM prestamos.frecuencias_pago WHERE UPPER(nombre)='MENSUAL');

-- Estados reconocidos por backend, vistas y migraciones existentes.
INSERT INTO prestamos.estados_prestamo(nombre)
SELECT v.nombre
FROM (VALUES
  ('ACTIVO'),
  ('SALDADO'),
  ('ATRASADO'),
  ('CANCELADO'),
  ('RENEGOCIADO'),
  ('REENGANCHADO')
) AS v(nombre)
WHERE NOT EXISTS (
  SELECT 1 FROM prestamos.estados_prestamo e WHERE UPPER(e.nombre)=UPPER(v.nombre)
);

-- Tipos de pago usados por PagoRepository y por las funciones almacenadas.
INSERT INTO prestamos.tipos_pago(nombre)
SELECT v.nombre
FROM (VALUES
  ('CUOTA_SAN'),
  ('REDITO'),
  ('ABONO_CAPITAL'),
  ('MIXTO'),
  ('REENGANCHE')
) AS v(nombre)
WHERE NOT EXISTS (
  SELECT 1 FROM prestamos.tipos_pago t WHERE UPPER(t.nombre)=UPPER(v.nombre)
);

COMMIT;
