BEGIN;

ALTER TABLE prestamos.pagos
  ADD COLUMN IF NOT EXISTS numero_cuota integer,
  ADD COLUMN IF NOT EXISTS estado varchar(12) NOT NULL DEFAULT 'APLICADO',
  ADD COLUMN IF NOT EXISTS fecha_anulacion timestamp without time zone,
  ADD COLUMN IF NOT EXISTS motivo_anulacion text,
  ADD COLUMN IF NOT EXISTS usuario_anulacion varchar(120);

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='ck_pagos_estado') THEN
    ALTER TABLE prestamos.pagos ADD CONSTRAINT ck_pagos_estado CHECK (estado IN ('APLICADO','ANULADO'));
  END IF;
END $$;

-- La aplicación histórica registró las cuotas SAN en orden, pero no conservó
-- su número. Esta vinculación permite auditar y anular esos pagos existentes.
WITH pagos_san AS (
  SELECT pg.id_pago,pg.id_prestamo,
         row_number() OVER(PARTITION BY pg.id_prestamo ORDER BY pg.id_pago) AS posicion
  FROM prestamos.pagos pg
  JOIN prestamos.tipos_pago tp ON tp.id_tipo_pago=pg.id_tipo_pago
  WHERE tp.nombre='CUOTA_SAN' AND pg.numero_cuota IS NULL
), cuotas AS (
  SELECT pp.id_prestamo,pp.numero_cuota,
         row_number() OVER(PARTITION BY pp.id_prestamo ORDER BY pp.numero_cuota) AS posicion
  FROM prestamos.plan_pagos pp
)
UPDATE prestamos.pagos pg SET numero_cuota=c.numero_cuota
FROM pagos_san ps JOIN cuotas c ON c.id_prestamo=ps.id_prestamo AND c.posicion=ps.posicion
WHERE pg.id_pago=ps.id_pago;

CREATE OR REPLACE FUNCTION prestamos.anular_pago(
  p_id_pago integer,
  p_motivo text,
  p_usuario varchar
) RETURNS integer LANGUAGE plpgsql AS $$
DECLARE
  v_pago prestamos.pagos%ROWTYPE;
  v_tipo varchar;
  v_concepto_capital numeric;
  v_estado_actual varchar;
  v_nuevo_pagado numeric;
  v_id_activo integer;
  v_id_atrasado integer;
BEGIN
  IF length(trim(coalesce(p_motivo,''))) < 8 THEN
    RAISE EXCEPTION 'Indique un motivo de al menos 8 caracteres.';
  END IF;

  SELECT pg.* INTO v_pago
  FROM prestamos.pagos pg
  WHERE pg.id_pago=p_id_pago FOR UPDATE;

  IF v_pago.id_pago IS NULL THEN RAISE EXCEPTION 'El pago no existe.'; END IF;
  SELECT nombre INTO v_tipo FROM prestamos.tipos_pago WHERE id_tipo_pago=v_pago.id_tipo_pago;
  IF v_pago.estado='ANULADO' THEN RAISE EXCEPTION 'Este pago ya fue anulado.'; END IF;
  IF EXISTS(SELECT 1 FROM prestamos.pagos x WHERE x.id_prestamo=v_pago.id_prestamo AND x.estado='APLICADO' AND x.id_pago>v_pago.id_pago) THEN
    RAISE EXCEPTION 'Solo puede anularse el último pago aplicado de este préstamo.';
  END IF;

  SELECT ep.nombre INTO v_estado_actual
  FROM prestamos.prestamos p JOIN prestamos.estados_prestamo ep ON ep.id_estado_prestamo=p.id_estado_prestamo
  WHERE p.id_prestamo=v_pago.id_prestamo FOR UPDATE OF p;

  IF v_tipo='CUOTA_SAN' THEN
    IF v_pago.numero_cuota IS NULL THEN
      RAISE EXCEPTION 'Este pago SAN antiguo no tiene una cuota vinculada y requiere revisión manual.';
    END IF;
    SELECT monto_pagado-v_pago.monto_pagado INTO v_nuevo_pagado
    FROM prestamos.plan_pagos
    WHERE id_prestamo=v_pago.id_prestamo AND numero_cuota=v_pago.numero_cuota FOR UPDATE;
    IF v_nuevo_pagado IS NULL OR v_nuevo_pagado<0 THEN
      RAISE EXCEPTION 'La cuota no contiene saldo pagado suficiente para revertir este movimiento.';
    END IF;
    UPDATE prestamos.plan_pagos SET monto_pagado=v_nuevo_pagado,
      estado=CASE WHEN v_nuevo_pagado=0 THEN 'PENDIENTE' WHEN v_nuevo_pagado<monto_programado THEN 'PARCIAL' ELSE 'PAGADO' END
    WHERE id_prestamo=v_pago.id_prestamo AND numero_cuota=v_pago.numero_cuota;
  ELSE
    SELECT coalesce(sum(monto),0) INTO v_concepto_capital
    FROM prestamos.detalle_pagos WHERE id_pago=v_pago.id_pago AND concepto='CAPITAL';
    IF v_concepto_capital>0 THEN
      UPDATE prestamos.prestamos
      SET capital_pendiente=least(monto_prestado,coalesce(capital_pendiente,0)+v_concepto_capital)
      WHERE id_prestamo=v_pago.id_prestamo;
    END IF;
  END IF;

  IF v_estado_actual='SALDADO' THEN
    SELECT id_estado_prestamo INTO v_id_activo FROM prestamos.estados_prestamo WHERE nombre='ACTIVO';
    SELECT id_estado_prestamo INTO v_id_atrasado FROM prestamos.estados_prestamo WHERE nombre='ATRASADO';
    UPDATE prestamos.prestamos SET id_estado_prestamo=
      CASE WHEN v_tipo='CUOTA_SAN' AND EXISTS(
        SELECT 1 FROM prestamos.plan_pagos pp WHERE pp.id_prestamo=v_pago.id_prestamo
          AND pp.monto_pagado<pp.monto_programado AND pp.fecha_vencimiento<current_date
      ) THEN v_id_atrasado ELSE v_id_activo END
    WHERE id_prestamo=v_pago.id_prestamo;
  END IF;

  UPDATE prestamos.pagos SET estado='ANULADO',fecha_anulacion=current_timestamp,
    motivo_anulacion=trim(p_motivo),usuario_anulacion=left(coalesce(p_usuario,'Sistema'),120)
  WHERE id_pago=v_pago.id_pago;
  UPDATE prestamos.recibos_pago SET estado='ANULADO' WHERE id_pago=v_pago.id_pago;
  INSERT INTO prestamos.historial_prestamos(id_prestamo,accion,descripcion)
  VALUES(v_pago.id_prestamo,'PAGO_ANULADO','Se anuló el pago #'||v_pago.id_pago||' por RD$'||v_pago.monto_pagado||'. Motivo: '||trim(p_motivo));
  RETURN v_pago.id_pago;
END;
$$;

COMMIT;
