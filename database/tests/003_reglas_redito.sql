BEGIN;

DO $$
DECLARE
  v_cliente integer;
  v_prestamo integer;
  v_capital numeric;
BEGIN
  INSERT INTO prestamos.cliente(nombre,documento,estado)
  VALUES('Prueba Regla REDITO','TEST-RULE-RED-' || txid_current(),'ACTIVO')
  RETURNING id_cliente INTO v_cliente;

  v_prestamo := prestamos.crear_prestamo_redito(
    v_cliente,
    10000,
    1000,
    'SEMANAL',
    current_date,
    'Prueba automática de reglas de rédito'
  );

  SELECT capital_pendiente INTO v_capital
  FROM prestamos.prestamos
  WHERE id_prestamo=v_prestamo;

  IF v_capital <> 10000 THEN
    RAISE EXCEPTION 'RÉDITO: capital inicial esperado 10000, obtenido %', v_capital;
  END IF;

  PERFORM prestamos.registrar_pago_redito(
    v_prestamo,
    1000,
    current_date,
    'Prueba de pago de rédito'
  );

  SELECT capital_pendiente INTO v_capital
  FROM prestamos.prestamos
  WHERE id_prestamo=v_prestamo;

  IF v_capital <> 10000 THEN
    RAISE EXCEPTION 'RÉDITO: pagar rédito no debe reducir capital. Capital obtenido: %', v_capital;
  END IF;

  PERFORM prestamos.registrar_abono_capital(
    v_prestamo,
    2000,
    current_date,
    'Prueba de abono a capital'
  );

  SELECT capital_pendiente INTO v_capital
  FROM prestamos.prestamos
  WHERE id_prestamo=v_prestamo;

  IF v_capital <> 8000 THEN
    RAISE EXCEPTION 'RÉDITO: después de abonar 2000 se esperaba capital 8000, obtenido %', v_capital;
  END IF;

  RAISE NOTICE 'REGLAS_REDITO_OK';
END $$;

ROLLBACK;
