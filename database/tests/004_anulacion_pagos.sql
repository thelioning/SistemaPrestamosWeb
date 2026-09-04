BEGIN;

DO $$
DECLARE
  v_cliente integer;
  v_prestamo integer;
  v_pago integer;
  v_pagado numeric;
  v_estado text;
BEGIN
  INSERT INTO prestamos.cliente(nombre,documento,estado)
  VALUES('Prueba Anulación SAN','TEST-ANN-SAN-' || txid_current(),'ACTIVO')
  RETURNING id_cliente INTO v_cliente;

  v_prestamo := prestamos.crear_prestamo_san(
    v_cliente,5000,500,13,'SEMANAL',current_date,'Prueba de anulación SAN'
  );

  v_pago := prestamos.registrar_pago_san(
    v_prestamo,1,500,current_date,'Pago SAN que será anulado'
  );

  UPDATE prestamos.pagos SET numero_cuota=1 WHERE id_pago=v_pago;

  PERFORM prestamos.anular_pago(
    v_pago,'Prueba automatizada de anulación SAN','Pruebas SQL'
  );

  SELECT monto_pagado INTO v_pagado
  FROM prestamos.plan_pagos
  WHERE id_prestamo=v_prestamo AND numero_cuota=1;

  SELECT estado INTO v_estado
  FROM prestamos.pagos
  WHERE id_pago=v_pago;

  IF v_pagado<>0 OR v_estado<>'ANULADO' THEN
    RAISE EXCEPTION 'ANULACIÓN SAN: la reversión no restauró correctamente la cuota.';
  END IF;

  RAISE NOTICE 'ANULACION_SAN_OK';
END $$;

DO $$
DECLARE
  v_cliente integer;
  v_prestamo integer;
  v_pago integer;
  v_capital numeric;
  v_estado text;
BEGIN
  INSERT INTO prestamos.cliente(nombre,documento,estado)
  VALUES('Prueba Anulación Capital','TEST-ANN-CAP-' || txid_current(),'ACTIVO')
  RETURNING id_cliente INTO v_cliente;

  v_prestamo := prestamos.crear_prestamo_redito(
    v_cliente,10000,1000,'SEMANAL',current_date,'Prueba de anulación de capital'
  );

  v_pago := prestamos.registrar_abono_capital(
    v_prestamo,2000,current_date,'Abono que será anulado'
  );

  SELECT capital_pendiente INTO v_capital
  FROM prestamos.prestamos
  WHERE id_prestamo=v_prestamo;

  IF v_capital<>8000 THEN
    RAISE EXCEPTION 'ANULACIÓN CAPITAL: el abono previo no dejó capital en 8000.';
  END IF;

  PERFORM prestamos.anular_pago(
    v_pago,'Prueba automatizada de anulación de capital','Pruebas SQL'
  );

  SELECT capital_pendiente INTO v_capital
  FROM prestamos.prestamos
  WHERE id_prestamo=v_prestamo;

  SELECT estado INTO v_estado
  FROM prestamos.pagos
  WHERE id_pago=v_pago;

  IF v_capital<>10000 OR v_estado<>'ANULADO' THEN
    RAISE EXCEPTION 'ANULACIÓN CAPITAL: la reversión no restauró correctamente el capital.';
  END IF;

  RAISE NOTICE 'ANULACION_CAPITAL_OK';
END $$;

ROLLBACK;
