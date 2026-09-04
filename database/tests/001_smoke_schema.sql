DO $$
DECLARE
  v_objeto text;
BEGIN
  FOREACH v_objeto IN ARRAY ARRAY[
    'prestamos.cliente',
    'prestamos.prestamos',
    'prestamos.plan_pagos',
    'prestamos.pagos',
    'prestamos.detalle_pagos',
    'prestamos.recibos_pago',
    'prestamos.tipos_prestamo',
    'prestamos.tipos_pago',
    'prestamos.frecuencias_pago',
    'prestamos.estados_prestamo',
    'prestamos.historial_prestamos',
    'prestamos.cierres_caja',
    'prestamos.usuarios'
  ]
  LOOP
    IF to_regclass(v_objeto) IS NULL THEN
      RAISE EXCEPTION 'Falta el objeto requerido: %', v_objeto;
    END IF;
  END LOOP;

  IF to_regclass('prestamos.vw_prestamos_general') IS NULL THEN
    RAISE EXCEPTION 'Falta la vista prestamos.vw_prestamos_general';
  END IF;

  IF to_regclass('prestamos.vw_dashboard') IS NULL THEN
    RAISE EXCEPTION 'Falta la vista prestamos.vw_dashboard';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='prestamos' AND p.proname='crear_prestamo_san'
  ) THEN
    RAISE EXCEPTION 'Falta la función prestamos.crear_prestamo_san';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='prestamos' AND p.proname='crear_prestamo_redito'
  ) THEN
    RAISE EXCEPTION 'Falta la función prestamos.crear_prestamo_redito';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='prestamos' AND p.proname='registrar_pago_san'
  ) THEN
    RAISE EXCEPTION 'Falta la función prestamos.registrar_pago_san';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='prestamos' AND p.proname='anular_pago'
  ) THEN
    RAISE EXCEPTION 'Falta la función prestamos.anular_pago';
  END IF;

  RAISE NOTICE 'SMOKE_SCHEMA_OK';
END $$;
