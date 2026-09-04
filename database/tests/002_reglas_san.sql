BEGIN;

DO $$
DECLARE
  v_cliente integer;
  v_prestamo integer;
  v_total numeric;
  v_cuotas integer;
  v_primera date;
  v_ultima date;
BEGIN
  INSERT INTO prestamos.cliente(nombre,documento,estado)
  VALUES('Prueba Regla SAN','TEST-RULE-SAN-' || txid_current(),'ACTIVO')
  RETURNING id_cliente INTO v_cliente;

  v_prestamo := prestamos.crear_prestamo_san(
    v_cliente,
    5000,
    500,
    13,
    'SEMANAL',
    current_date,
    'Prueba automática de reglas SAN'
  );

  SELECT total_a_pagar INTO v_total
  FROM prestamos.prestamos
  WHERE id_prestamo=v_prestamo;

  IF v_total <> 6500 THEN
    RAISE EXCEPTION 'SAN: total esperado 6500, obtenido %', v_total;
  END IF;

  SELECT COUNT(*), MIN(fecha_vencimiento), MAX(fecha_vencimiento)
  INTO v_cuotas,v_primera,v_ultima
  FROM prestamos.plan_pagos
  WHERE id_prestamo=v_prestamo;

  IF v_cuotas <> 13 THEN
    RAISE EXCEPTION 'SAN: se esperaban 13 cuotas, se obtuvieron %', v_cuotas;
  END IF;

  IF v_primera <> current_date + 7 THEN
    RAISE EXCEPTION 'SAN: primer vencimiento incorrecto: %', v_primera;
  END IF;

  IF v_ultima <> current_date + 91 THEN
    RAISE EXCEPTION 'SAN: último vencimiento incorrecto: %', v_ultima;
  END IF;

  IF EXISTS (
    SELECT 1 FROM prestamos.plan_pagos
    WHERE id_prestamo=v_prestamo
      AND (monto_programado<>500 OR monto_pagado<>0 OR estado<>'PENDIENTE')
  ) THEN
    RAISE EXCEPTION 'SAN: el plan de pagos contiene valores iniciales incorrectos.';
  END IF;

  RAISE NOTICE 'REGLAS_SAN_OK';
END $$;

ROLLBACK;
