BEGIN;

-- Datos completamente ficticios para una base de desarrollo.
-- El script evita duplicarlos usando documentos reservados para prueba.

INSERT INTO prestamos.cliente(nombre,telefono,direccion,documento,estado)
SELECT 'Cliente Prueba SAN','809-555-0101','Dirección ficticia de prueba','TEST-SAN-001','ACTIVO'
WHERE NOT EXISTS (
  SELECT 1 FROM prestamos.cliente WHERE documento='TEST-SAN-001'
);

INSERT INTO prestamos.cliente(nombre,telefono,direccion,documento,estado)
SELECT 'Cliente Prueba REDITO','809-555-0102','Dirección ficticia de prueba','TEST-RED-001','ACTIVO'
WHERE NOT EXISTS (
  SELECT 1 FROM prestamos.cliente WHERE documento='TEST-RED-001'
);

DO $$
DECLARE
  v_cliente integer;
BEGIN
  SELECT id_cliente INTO v_cliente
  FROM prestamos.cliente
  WHERE documento='TEST-SAN-001'
  ORDER BY id_cliente
  LIMIT 1;

  IF NOT EXISTS (
    SELECT 1
    FROM prestamos.prestamos p
    JOIN prestamos.tipos_prestamo tp ON tp.id_tipo_prestamos=p.id_tipo_prestamos
    WHERE p.id_cliente=v_cliente AND tp.nombre='SAN'
  ) THEN
    PERFORM prestamos.crear_prestamo_san(
      v_cliente,
      5000,
      500,
      13,
      'SEMANAL',
      current_date,
      'Préstamo SAN ficticio para pruebas de desarrollo'
    );
  END IF;
END $$;

DO $$
DECLARE
  v_cliente integer;
BEGIN
  SELECT id_cliente INTO v_cliente
  FROM prestamos.cliente
  WHERE documento='TEST-RED-001'
  ORDER BY id_cliente
  LIMIT 1;

  IF NOT EXISTS (
    SELECT 1
    FROM prestamos.prestamos p
    JOIN prestamos.tipos_prestamo tp ON tp.id_tipo_prestamos=p.id_tipo_prestamos
    WHERE p.id_cliente=v_cliente AND tp.nombre='REDITO'
  ) THEN
    PERFORM prestamos.crear_prestamo_redito(
      v_cliente,
      10000,
      1000,
      'SEMANAL',
      current_date,
      'Préstamo a rédito ficticio para pruebas de desarrollo'
    );
  END IF;
END $$;

COMMIT;
