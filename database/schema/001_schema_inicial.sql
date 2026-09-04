--
-- PostgreSQL database dump
--

\restrict CmL2Kv33xPEaxHtd6NC9hRNNZzCb9hvnFUWexBlxdShcJPCXHHp8Janj0cENNRH

-- Dumped from database version 18.4
-- Dumped by pg_dump version 18.4

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: prestamos; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA prestamos;


--
-- Name: actualizar_ruta_recibo(integer, text); Type: FUNCTION; Schema: prestamos; Owner: -
--

CREATE FUNCTION prestamos.actualizar_ruta_recibo(p_id_recibo integer, p_ruta_pdf text) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
    UPDATE prestamos.recibos_pago
    SET 
        ruta_pdf = p_ruta_pdf,
        estado = 'PDF_GENERADO'
    WHERE id_recibo = p_id_recibo;
END;
$$;


--
-- Name: anular_pago(integer, text, character varying); Type: FUNCTION; Schema: prestamos; Owner: -
--

CREATE FUNCTION prestamos.anular_pago(p_id_pago integer, p_motivo text, p_usuario character varying) RETURNS integer
    LANGUAGE plpgsql
    AS $_$
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
$_$;


--
-- Name: cerrar_caja(date, numeric, text, character varying); Type: FUNCTION; Schema: prestamos; Owner: -
--

CREATE FUNCTION prestamos.cerrar_caja(p_fecha date, p_total_declarado numeric, p_observacion text, p_usuario character varying) RETURNS integer
    LANGUAGE plpgsql
    AS $$
DECLARE v_id integer;v_total numeric;v_pagos integer;v_anulados integer;
BEGIN
 IF p_fecha>current_date THEN RAISE EXCEPTION 'No puede cerrar una fecha futura.';END IF;
 IF p_total_declarado<0 THEN RAISE EXCEPTION 'El total declarado no puede ser negativo.';END IF;
 PERFORM pg_advisory_xact_lock(hashtext('cierre-caja-'||p_fecha::text));
 IF EXISTS(SELECT 1 FROM prestamos.cierres_caja WHERE fecha=p_fecha) THEN RAISE EXCEPTION 'La caja de esta fecha ya está cerrada.';END IF;
 SELECT COALESCE(SUM(monto_pagado) FILTER(WHERE estado='APLICADO'),0),COUNT(*) FILTER(WHERE estado='APLICADO'),COUNT(*) FILTER(WHERE estado='ANULADO') INTO v_total,v_pagos,v_anulados FROM prestamos.pagos WHERE fecha_pago=p_fecha;
 INSERT INTO prestamos.cierres_caja(fecha,total_sistema,total_declarado,diferencia,cantidad_pagos,cantidad_anulados,observacion,usuario)
 VALUES(p_fecha,v_total,p_total_declarado,p_total_declarado-v_total,v_pagos,v_anulados,NULLIF(trim(coalesce(p_observacion,'')),''),left(coalesce(p_usuario,'Sistema'),120)) RETURNING id_cierre INTO v_id;
 INSERT INTO prestamos.cierre_caja_detalle(id_cierre,tipo_pago,cantidad,total)
 SELECT v_id,tp.nombre,COUNT(*),SUM(pg.monto_pagado) FROM prestamos.pagos pg JOIN prestamos.tipos_pago tp ON tp.id_tipo_pago=pg.id_tipo_pago WHERE pg.fecha_pago=p_fecha AND pg.estado='APLICADO' GROUP BY tp.nombre;
 RETURN v_id;
END $$;


--
-- Name: crear_prestamo_redito(integer, numeric, numeric, character varying, date, text); Type: FUNCTION; Schema: prestamos; Owner: -
--

CREATE FUNCTION prestamos.crear_prestamo_redito(p_id_cliente integer, p_monto_prestado numeric, p_monto_redito numeric, p_frecuencia character varying, p_fecha_inicio date, p_observacion text DEFAULT NULL::text) RETURNS integer
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_id_prestamo INTEGER;
    v_id_tipo INTEGER;
    v_id_frecuencia INTEGER;
    v_id_estado INTEGER;
BEGIN
    IF p_monto_prestado <= 0 THEN
        RAISE EXCEPTION 'El monto prestado debe ser mayor que cero.';
    END IF;

    IF p_monto_redito <= 0 THEN
        RAISE EXCEPTION 'El monto del rédito debe ser mayor que cero.';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM prestamos.cliente
        WHERE id_cliente = p_id_cliente
    ) THEN
        RAISE EXCEPTION 'El cliente indicado no existe.';
    END IF;

    SELECT id_tipo_prestamos
    INTO v_id_tipo
    FROM prestamos.tipos_prestamo
    WHERE UPPER(nombre) = 'REDITO';

    SELECT id_frecuencia
    INTO v_id_frecuencia
    FROM prestamos.frecuencias_pago
    WHERE UPPER(nombre) = UPPER(p_frecuencia);

    IF v_id_frecuencia IS NULL THEN
        RAISE EXCEPTION 'La frecuencia indicada no existe.';
    END IF;

    SELECT id_estado_prestamo
    INTO v_id_estado
    FROM prestamos.estados_prestamo
    WHERE UPPER(nombre) = 'ACTIVO';

    INSERT INTO prestamos.prestamos (
        id_cliente,
        id_tipo_prestamos,
        id_frecuencia,
        id_estado_prestamo,
        monto_prestado,
        monto_redito,
        capital_pendiente,
        fecha_inicio,
        observacion
    )
    VALUES (
        p_id_cliente,
        v_id_tipo,
        v_id_frecuencia,
        v_id_estado,
        p_monto_prestado,
        p_monto_redito,
        p_monto_prestado,
        p_fecha_inicio,
        p_observacion
    )
    RETURNING id_prestamo INTO v_id_prestamo;

    RETURN v_id_prestamo;
END;
$$;


--
-- Name: crear_prestamo_san(integer, numeric, numeric, integer, character varying, date, text); Type: FUNCTION; Schema: prestamos; Owner: -
--

CREATE FUNCTION prestamos.crear_prestamo_san(p_id_cliente integer, p_monto_prestado numeric, p_cuota numeric, p_cantidad_periodos integer, p_frecuencia character varying, p_fecha_inicio date, p_observacion text DEFAULT NULL::text) RETURNS integer
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_id_prestamo INTEGER;
    v_id_tipo INTEGER;
    v_id_frecuencia INTEGER;
    v_id_estado INTEGER;
    v_dias INTEGER;
BEGIN
    SELECT id_tipo_prestamos
    INTO v_id_tipo
    FROM prestamos.tipos_prestamo
    WHERE nombre = 'SAN';

    SELECT id_frecuencia, dias
    INTO v_id_frecuencia, v_dias
    FROM prestamos.frecuencias_pago
    WHERE UPPER(nombre) = UPPER(p_frecuencia);

    SELECT id_estado_prestamo
    INTO v_id_estado
    FROM prestamos.estados_prestamo
    WHERE nombre = 'ACTIVO';

    INSERT INTO prestamos.prestamos (
        id_cliente,
        id_tipo_prestamos,
        id_frecuencia,
        id_estado_prestamo,
        monto_prestado,
        cuota,
        cantidad_periodos,
        total_a_pagar,
        fecha_inicio,
        fecha_fin_estimada,
        observacion
    )
    VALUES (
        p_id_cliente,
        v_id_tipo,
        v_id_frecuencia,
        v_id_estado,
        p_monto_prestado,
        p_cuota,
        p_cantidad_periodos,
        p_cuota * p_cantidad_periodos,
        p_fecha_inicio,
        p_fecha_inicio + (p_cantidad_periodos * v_dias),
        p_observacion
    )
    RETURNING id_prestamo INTO v_id_prestamo;

    INSERT INTO prestamos.plan_pagos (
        id_prestamo,
        numero_cuota,
        fecha_vencimiento,
        monto_programado,
        monto_pagado,
        estado
    )
    SELECT
        v_id_prestamo,
        gs.numero_cuota,
        p_fecha_inicio + (gs.numero_cuota * v_dias),
        p_cuota,
        0,
        'PENDIENTE'
    FROM generate_series(1, p_cantidad_periodos) AS gs(numero_cuota);

    RETURN v_id_prestamo;
END;
$$;


--
-- Name: crear_reenganche_san(integer, numeric, numeric, integer, character varying, date, text); Type: FUNCTION; Schema: prestamos; Owner: -
--

CREATE FUNCTION prestamos.crear_reenganche_san(p_id_prestamo_origen integer, p_monto_nuevo numeric, p_cuota numeric, p_cantidad_periodos integer, p_frecuencia character varying, p_fecha_inicio date, p_observacion text DEFAULT NULL::text) RETURNS integer
    LANGUAGE plpgsql
    AS $_$
DECLARE v_id_cliente integer; v_tipo varchar; v_estado varchar; v_saldo numeric(12,2); v_id_nuevo integer; v_id_estado integer; v_id_tipo_pago integer; v_id_pago integer;
BEGIN
 SELECT p.id_cliente,tp.nombre,ep.nombre INTO v_id_cliente,v_tipo,v_estado FROM prestamos.prestamos p JOIN prestamos.tipos_prestamo tp ON tp.id_tipo_prestamos=p.id_tipo_prestamos JOIN prestamos.estados_prestamo ep ON ep.id_estado_prestamo=p.id_estado_prestamo WHERE p.id_prestamo=p_id_prestamo_origen FOR UPDATE OF p;
 IF v_id_cliente IS NULL THEN RAISE EXCEPTION 'El préstamo de origen no existe.'; END IF;
 IF v_tipo<>'SAN' THEN RAISE EXCEPTION 'El reenganche solo aplica a préstamos SAN.'; END IF;
 IF v_estado<>'ACTIVO' THEN RAISE EXCEPTION 'El préstamo de origen debe estar activo.'; END IF;
 SELECT COALESCE(SUM(monto_programado-monto_pagado),0) INTO v_saldo FROM prestamos.plan_pagos WHERE id_prestamo=p_id_prestamo_origen;
 IF v_saldo<=0 THEN RAISE EXCEPTION 'El préstamo no tiene saldo pendiente.'; END IF;
 IF p_monto_nuevo<=v_saldo THEN RAISE EXCEPTION 'El nuevo monto debe ser mayor que el saldo pendiente de RD$%.',v_saldo; END IF;
 v_id_nuevo:=prestamos.crear_prestamo_san(v_id_cliente,p_monto_nuevo,p_cuota,p_cantidad_periodos,p_frecuencia,p_fecha_inicio,p_observacion);
 UPDATE prestamos.prestamos SET id_prestamo_origen=p_id_prestamo_origen,monto_descontado=v_saldo,monto_entregado=p_monto_nuevo-v_saldo WHERE id_prestamo=v_id_nuevo;
 SELECT id_tipo_pago INTO v_id_tipo_pago FROM prestamos.tipos_pago WHERE nombre='REENGANCHE';
 INSERT INTO prestamos.pagos(id_prestamo,id_tipo_pago,fecha_pago,monto_pagado,observacion) VALUES(p_id_prestamo_origen,v_id_tipo_pago,p_fecha_inicio,v_saldo,'Saldo cancelado mediante reenganche al préstamo #'||v_id_nuevo) RETURNING id_pago INTO v_id_pago;
 INSERT INTO prestamos.detalle_pagos(id_pago,concepto,monto) VALUES(v_id_pago,'REENGANCHE',v_saldo);
 UPDATE prestamos.plan_pagos SET monto_pagado=monto_programado,estado='PAGADA' WHERE id_prestamo=p_id_prestamo_origen AND monto_pagado<monto_programado;
 SELECT id_estado_prestamo INTO v_id_estado FROM prestamos.estados_prestamo WHERE nombre='REENGANCHADO';
 UPDATE prestamos.prestamos SET id_estado_prestamo=v_id_estado WHERE id_prestamo=p_id_prestamo_origen;
 INSERT INTO prestamos.historial_prestamos(id_prestamo,accion,descripcion) VALUES(v_id_nuevo,'ORIGEN_REENGANCHE','Préstamo creado mediante reenganche del préstamo #'||p_id_prestamo_origen||'. Descuento RD$'||v_saldo||'. Entregado RD$'||(p_monto_nuevo-v_saldo));
 RETURN v_id_nuevo;
END $_$;


--
-- Name: fn_bloquear_fecha_cerrada(); Type: FUNCTION; Schema: prestamos; Owner: -
--

CREATE FUNCTION prestamos.fn_bloquear_fecha_cerrada() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
 IF EXISTS(SELECT 1 FROM prestamos.cierres_caja WHERE fecha=NEW.fecha_pago) THEN
   RAISE EXCEPTION 'La caja del % está cerrada; no se permiten nuevos movimientos ni anulaciones.',to_char(NEW.fecha_pago,'DD/MM/YYYY');
 END IF;
 RETURN NEW;
END $$;


--
-- Name: fn_historial_pago_registrado(); Type: FUNCTION; Schema: prestamos; Owner: -
--

CREATE FUNCTION prestamos.fn_historial_pago_registrado() RETURNS trigger
    LANGUAGE plpgsql
    AS $_$
DECLARE
    v_tipo_pago VARCHAR;
    v_numero_recibo VARCHAR;
BEGIN
    SELECT nombre
    INTO v_tipo_pago
    FROM prestamos.tipos_pago
    WHERE id_tipo_pago = NEW.id_tipo_pago;

    INSERT INTO prestamos.historial_prestamos (
        id_prestamo,
        accion,
        descripcion
    )
    VALUES (
        NEW.id_prestamo,
        'PAGO_' || v_tipo_pago,
        'Se registró un pago por RD$' || NEW.monto_pagado
    );

    v_numero_recibo := 
        'REC-' || TO_CHAR(NEW.fecha_registro, 'YYYYMMDD') || '-' || LPAD(NEW.id_pago::TEXT, 6, '0');

    INSERT INTO prestamos.recibos_pago (
        id_pago,
        numero_recibo
    )
    VALUES (
        NEW.id_pago,
        v_numero_recibo
    );

    RETURN NEW;
END;
$_$;


--
-- Name: fn_historial_prestamo_creado(); Type: FUNCTION; Schema: prestamos; Owner: -
--

CREATE FUNCTION prestamos.fn_historial_prestamo_creado() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    INSERT INTO prestamos.historial_prestamos (
        id_prestamo,
        accion,
        descripcion
    )
    VALUES (
        NEW.id_prestamo,
        'PRESTAMO_CREADO',
        'Se registró un nuevo préstamo en el sistema.'
    );

    RETURN NEW;
END;
$$;


--
-- Name: registrar_abono_capital(integer, numeric, date, text); Type: FUNCTION; Schema: prestamos; Owner: -
--

CREATE FUNCTION prestamos.registrar_abono_capital(p_id_prestamo integer, p_monto_abono numeric, p_fecha_pago date, p_observacion text DEFAULT NULL::text) RETURNS integer
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_id_pago INTEGER;
    v_id_tipo_pago INTEGER;
    v_tipo_prestamo VARCHAR;
    v_capital_pendiente NUMERIC;
    v_id_estado_saldado INTEGER;
BEGIN
    IF p_monto_abono <= 0 THEN
        RAISE EXCEPTION 'El abono debe ser mayor que cero.';
    END IF;

    SELECT 
        tp.nombre,
        p.capital_pendiente
    INTO 
        v_tipo_prestamo,
        v_capital_pendiente
    FROM prestamos.prestamos p
    INNER JOIN prestamos.tipos_prestamo tp
        ON p.id_tipo_prestamos = tp.id_tipo_prestamos
    WHERE p.id_prestamo = p_id_prestamo;

    IF v_tipo_prestamo IS NULL THEN
        RAISE EXCEPTION 'El préstamo no existe.';
    END IF;

    IF v_tipo_prestamo <> 'REDITO' THEN
        RAISE EXCEPTION 'Este préstamo no es de tipo REDITO.';
    END IF;

    IF p_monto_abono > v_capital_pendiente THEN
        RAISE EXCEPTION 'El abono no puede ser mayor que el capital pendiente.';
    END IF;

    SELECT id_tipo_pago
    INTO v_id_tipo_pago
    FROM prestamos.tipos_pago
    WHERE nombre = 'ABONO_CAPITAL';

    INSERT INTO prestamos.pagos (
        id_prestamo,
        id_tipo_pago,
        fecha_pago,
        monto_pagado,
        observacion
    )
    VALUES (
        p_id_prestamo,
        v_id_tipo_pago,
        p_fecha_pago,
        p_monto_abono,
        p_observacion
    )
    RETURNING id_pago INTO v_id_pago;

    INSERT INTO prestamos.detalle_pagos (
        id_pago,
        concepto,
        monto
    )
    VALUES (
        v_id_pago,
        'CAPITAL',
        p_monto_abono
    );

    UPDATE prestamos.prestamos
    SET capital_pendiente = capital_pendiente - p_monto_abono
    WHERE id_prestamo = p_id_prestamo;

    IF v_capital_pendiente - p_monto_abono = 0 THEN
        SELECT id_estado_prestamo
        INTO v_id_estado_saldado
        FROM prestamos.estados_prestamo
        WHERE nombre = 'SALDADO';

        UPDATE prestamos.prestamos
        SET id_estado_prestamo = v_id_estado_saldado
        WHERE id_prestamo = p_id_prestamo;
    END IF;

    RETURN v_id_pago;
END;
$$;


--
-- Name: registrar_pago_mixto(integer, numeric, numeric, date, text); Type: FUNCTION; Schema: prestamos; Owner: -
--

CREATE FUNCTION prestamos.registrar_pago_mixto(p_id_prestamo integer, p_monto_redito numeric, p_monto_capital numeric, p_fecha_pago date, p_observacion text DEFAULT NULL::text) RETURNS integer
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_id_pago INTEGER;
    v_id_tipo_pago INTEGER;
    v_tipo_prestamo VARCHAR;
    v_capital_pendiente NUMERIC;
    v_total_pago NUMERIC;
    v_id_estado_saldado INTEGER;
BEGIN
    IF p_monto_redito < 0 OR p_monto_capital < 0 THEN
        RAISE EXCEPTION 'Los montos no pueden ser negativos.';
    END IF;

    v_total_pago := p_monto_redito + p_monto_capital;

    IF v_total_pago <= 0 THEN
        RAISE EXCEPTION 'El pago mixto debe tener un monto mayor que cero.';
    END IF;

    SELECT 
        tp.nombre,
        p.capital_pendiente
    INTO 
        v_tipo_prestamo,
        v_capital_pendiente
    FROM prestamos.prestamos p
    INNER JOIN prestamos.tipos_prestamo tp
        ON p.id_tipo_prestamos = tp.id_tipo_prestamos
    WHERE p.id_prestamo = p_id_prestamo;

    IF v_tipo_prestamo IS NULL THEN
        RAISE EXCEPTION 'El préstamo no existe.';
    END IF;

    IF v_tipo_prestamo <> 'REDITO' THEN
        RAISE EXCEPTION 'El pago mixto solo aplica a préstamos tipo REDITO.';
    END IF;

    IF p_monto_capital > v_capital_pendiente THEN
        RAISE EXCEPTION 'El abono a capital no puede ser mayor que el capital pendiente.';
    END IF;

    SELECT id_tipo_pago
    INTO v_id_tipo_pago
    FROM prestamos.tipos_pago
    WHERE nombre = 'MIXTO';

    INSERT INTO prestamos.pagos (
        id_prestamo,
        id_tipo_pago,
        fecha_pago,
        monto_pagado,
        observacion
    )
    VALUES (
        p_id_prestamo,
        v_id_tipo_pago,
        p_fecha_pago,
        v_total_pago,
        p_observacion
    )
    RETURNING id_pago INTO v_id_pago;

    IF p_monto_redito > 0 THEN
        INSERT INTO prestamos.detalle_pagos (
            id_pago,
            concepto,
            monto
        )
        VALUES (
            v_id_pago,
            'REDITO',
            p_monto_redito
        );
    END IF;

    IF p_monto_capital > 0 THEN
        INSERT INTO prestamos.detalle_pagos (
            id_pago,
            concepto,
            monto
        )
        VALUES (
            v_id_pago,
            'CAPITAL',
            p_monto_capital
        );

        UPDATE prestamos.prestamos
        SET capital_pendiente = capital_pendiente - p_monto_capital
        WHERE id_prestamo = p_id_prestamo;
    END IF;

    IF v_capital_pendiente - p_monto_capital = 0 THEN
        SELECT id_estado_prestamo
        INTO v_id_estado_saldado
        FROM prestamos.estados_prestamo
        WHERE nombre = 'SALDADO';

        UPDATE prestamos.prestamos
        SET id_estado_prestamo = v_id_estado_saldado
        WHERE id_prestamo = p_id_prestamo;
    END IF;

    RETURN v_id_pago;
END;
$$;


--
-- Name: registrar_pago_redito(integer, numeric, date, text); Type: FUNCTION; Schema: prestamos; Owner: -
--

CREATE FUNCTION prestamos.registrar_pago_redito(p_id_prestamo integer, p_monto_pagado numeric, p_fecha_pago date, p_observacion text DEFAULT NULL::text) RETURNS integer
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_id_pago INTEGER;
    v_id_tipo_pago INTEGER;
    v_tipo_prestamo VARCHAR;
BEGIN
    IF p_monto_pagado <= 0 THEN
        RAISE EXCEPTION 'El monto pagado debe ser mayor que cero.';
    END IF;

    SELECT tp.nombre
    INTO v_tipo_prestamo
    FROM prestamos.prestamos p
    INNER JOIN prestamos.tipos_prestamo tp
        ON p.id_tipo_prestamos = tp.id_tipo_prestamos
    WHERE p.id_prestamo = p_id_prestamo;

    IF v_tipo_prestamo IS NULL THEN
        RAISE EXCEPTION 'El préstamo no existe.';
    END IF;

    IF v_tipo_prestamo <> 'REDITO' THEN
        RAISE EXCEPTION 'Este préstamo no es de tipo REDITO.';
    END IF;

    SELECT id_tipo_pago
    INTO v_id_tipo_pago
    FROM prestamos.tipos_pago
    WHERE nombre = 'REDITO';

    INSERT INTO prestamos.pagos (
        id_prestamo,
        id_tipo_pago,
        fecha_pago,
        monto_pagado,
        observacion
    )
    VALUES (
        p_id_prestamo,
        v_id_tipo_pago,
        p_fecha_pago,
        p_monto_pagado,
        p_observacion
    )
    RETURNING id_pago INTO v_id_pago;

    INSERT INTO prestamos.detalle_pagos (
        id_pago,
        concepto,
        monto
    )
    VALUES (
        v_id_pago,
        'REDITO',
        p_monto_pagado
    );

    RETURN v_id_pago;
END;
$$;


--
-- Name: registrar_pago_san(integer, integer, numeric, date, text); Type: FUNCTION; Schema: prestamos; Owner: -
--

CREATE FUNCTION prestamos.registrar_pago_san(p_id_prestamo integer, p_numero_cuota integer, p_monto_pagado numeric, p_fecha_pago date, p_observacion text DEFAULT NULL::text) RETURNS integer
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_id_pago INTEGER;
    v_id_tipo_pago INTEGER;
    v_monto_programado NUMERIC;
    v_monto_pagado_actual NUMERIC;
    v_nuevo_pagado NUMERIC;
    v_pendientes INTEGER;
    v_id_estado_saldado INTEGER;
BEGIN
    SELECT id_tipo_pago
    INTO v_id_tipo_pago
    FROM prestamos.tipos_pago
    WHERE nombre = 'CUOTA_SAN';

    SELECT 
        pp.monto_programado,
        pp.monto_pagado
    INTO 
        v_monto_programado,
        v_monto_pagado_actual
    FROM prestamos.plan_pagos pp
    WHERE pp.id_prestamo = p_id_prestamo
      AND pp.numero_cuota = p_numero_cuota;

    IF v_monto_programado IS NULL THEN
        RAISE EXCEPTION 'La cuota indicada no existe para este préstamo.';
    END IF;

    v_nuevo_pagado := v_monto_pagado_actual + p_monto_pagado;

    IF v_nuevo_pagado > v_monto_programado THEN
        RAISE EXCEPTION 'El pago excede el monto pendiente de la cuota.';
    END IF;

    INSERT INTO prestamos.pagos (
        id_prestamo,
        id_tipo_pago,
        fecha_pago,
        monto_pagado,
        observacion
    )
    VALUES (
        p_id_prestamo,
        v_id_tipo_pago,
        p_fecha_pago,
        p_monto_pagado,
        p_observacion
    )
    RETURNING id_pago INTO v_id_pago;

    INSERT INTO prestamos.detalle_pagos (
        id_pago,
        concepto,
        monto
    )
    VALUES (
        v_id_pago,
        'CUOTA_SAN',
        p_monto_pagado
    );

    UPDATE prestamos.plan_pagos
    SET 
        monto_pagado = v_nuevo_pagado,
        estado = CASE 
                    WHEN v_nuevo_pagado = monto_programado THEN 'PAGADO'
                    ELSE 'PARCIAL'
                 END
    WHERE id_prestamo = p_id_prestamo
      AND numero_cuota = p_numero_cuota;

    SELECT COUNT(*)
    INTO v_pendientes
    FROM prestamos.plan_pagos
    WHERE id_prestamo = p_id_prestamo
      AND estado <> 'PAGADO';

    IF v_pendientes = 0 THEN
        SELECT id_estado_prestamo
        INTO v_id_estado_saldado
        FROM prestamos.estados_prestamo
        WHERE nombre = 'SALDADO';

        UPDATE prestamos.prestamos
        SET id_estado_prestamo = v_id_estado_saldado
        WHERE id_prestamo = p_id_prestamo;
    END IF;

    RETURN v_id_pago;
END;
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: auditoria_usuarios; Type: TABLE; Schema: prestamos; Owner: -
--

CREATE TABLE prestamos.auditoria_usuarios (
    id_auditoria integer NOT NULL,
    id_usuario integer NOT NULL,
    accion character varying(40) NOT NULL,
    detalle text,
    realizado_por integer,
    fecha timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


--
-- Name: auditoria_usuarios_id_auditoria_seq; Type: SEQUENCE; Schema: prestamos; Owner: -
--

ALTER TABLE prestamos.auditoria_usuarios ALTER COLUMN id_auditoria ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME prestamos.auditoria_usuarios_id_auditoria_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: cierre_caja_detalle; Type: TABLE; Schema: prestamos; Owner: -
--

CREATE TABLE prestamos.cierre_caja_detalle (
    id_detalle integer NOT NULL,
    id_cierre integer NOT NULL,
    tipo_pago character varying(40) NOT NULL,
    cantidad integer NOT NULL,
    total numeric(14,2) NOT NULL
);


--
-- Name: cierre_caja_detalle_id_detalle_seq; Type: SEQUENCE; Schema: prestamos; Owner: -
--

ALTER TABLE prestamos.cierre_caja_detalle ALTER COLUMN id_detalle ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME prestamos.cierre_caja_detalle_id_detalle_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: cierres_caja; Type: TABLE; Schema: prestamos; Owner: -
--

CREATE TABLE prestamos.cierres_caja (
    id_cierre integer NOT NULL,
    fecha date NOT NULL,
    total_sistema numeric(14,2) NOT NULL,
    total_declarado numeric(14,2) NOT NULL,
    diferencia numeric(14,2) NOT NULL,
    cantidad_pagos integer NOT NULL,
    cantidad_anulados integer NOT NULL,
    observacion text,
    usuario character varying(120) NOT NULL,
    fecha_registro timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT ck_cierre_totales CHECK (((total_sistema >= (0)::numeric) AND (total_declarado >= (0)::numeric)))
);


--
-- Name: cierres_caja_id_cierre_seq; Type: SEQUENCE; Schema: prestamos; Owner: -
--

ALTER TABLE prestamos.cierres_caja ALTER COLUMN id_cierre ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME prestamos.cierres_caja_id_cierre_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: cliente; Type: TABLE; Schema: prestamos; Owner: -
--

CREATE TABLE prestamos.cliente (
    id_cliente integer NOT NULL,
    nombre character varying(50) NOT NULL,
    telefono character varying(20),
    direccion text,
    documento character varying(30),
    estado character varying(15) DEFAULT 'ACTIVO'::character varying,
    fecha_registro timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: cliente_id_cliente_seq; Type: SEQUENCE; Schema: prestamos; Owner: -
--

ALTER TABLE prestamos.cliente ALTER COLUMN id_cliente ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME prestamos.cliente_id_cliente_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: configuracion_sistema; Type: TABLE; Schema: prestamos; Owner: -
--

CREATE TABLE prestamos.configuracion_sistema (
    id_configuracion integer NOT NULL,
    clave character varying(50) NOT NULL,
    valor text NOT NULL
);


--
-- Name: configuracion_sistema_id_configuracion_seq; Type: SEQUENCE; Schema: prestamos; Owner: -
--

ALTER TABLE prestamos.configuracion_sistema ALTER COLUMN id_configuracion ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME prestamos.configuracion_sistema_id_configuracion_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: detalle_pagos; Type: TABLE; Schema: prestamos; Owner: -
--

CREATE TABLE prestamos.detalle_pagos (
    id_detalle_pago integer NOT NULL,
    id_pago integer NOT NULL,
    concepto character varying(30) NOT NULL,
    monto numeric(12,2) NOT NULL
);


--
-- Name: detalle_pagos_id_detalle_pago_seq; Type: SEQUENCE; Schema: prestamos; Owner: -
--

ALTER TABLE prestamos.detalle_pagos ALTER COLUMN id_detalle_pago ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME prestamos.detalle_pagos_id_detalle_pago_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: estados_prestamo; Type: TABLE; Schema: prestamos; Owner: -
--

CREATE TABLE prestamos.estados_prestamo (
    id_estado_prestamo integer NOT NULL,
    nombre character varying(20) NOT NULL
);


--
-- Name: estados_prestamo_id_estado_prestamo_seq; Type: SEQUENCE; Schema: prestamos; Owner: -
--

ALTER TABLE prestamos.estados_prestamo ALTER COLUMN id_estado_prestamo ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME prestamos.estados_prestamo_id_estado_prestamo_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: frecuencias_pago; Type: TABLE; Schema: prestamos; Owner: -
--

CREATE TABLE prestamos.frecuencias_pago (
    id_frecuencia integer NOT NULL,
    nombre character varying(20) NOT NULL,
    dias integer NOT NULL
);


--
-- Name: frecuencias_pago_id_frecuencia_seq; Type: SEQUENCE; Schema: prestamos; Owner: -
--

ALTER TABLE prestamos.frecuencias_pago ALTER COLUMN id_frecuencia ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME prestamos.frecuencias_pago_id_frecuencia_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: historial_prestamos; Type: TABLE; Schema: prestamos; Owner: -
--

CREATE TABLE prestamos.historial_prestamos (
    id_historial integer NOT NULL,
    id_prestamo integer NOT NULL,
    fecha timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    accion character varying(50) NOT NULL,
    descripcion text
);


--
-- Name: historial_prestamos_id_historial_seq; Type: SEQUENCE; Schema: prestamos; Owner: -
--

ALTER TABLE prestamos.historial_prestamos ALTER COLUMN id_historial ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME prestamos.historial_prestamos_id_historial_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: movimientos_caja; Type: TABLE; Schema: prestamos; Owner: -
--

CREATE TABLE prestamos.movimientos_caja (
    id_movimiento integer NOT NULL,
    fecha timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    tipo_movimiento character varying(20) NOT NULL,
    monto numeric(12,2) NOT NULL,
    descripcion text,
    id_prestamo integer,
    id_pago integer
);


--
-- Name: movimientos_caja_id_movimiento_seq; Type: SEQUENCE; Schema: prestamos; Owner: -
--

ALTER TABLE prestamos.movimientos_caja ALTER COLUMN id_movimiento ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME prestamos.movimientos_caja_id_movimiento_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: pagos; Type: TABLE; Schema: prestamos; Owner: -
--

CREATE TABLE prestamos.pagos (
    id_pago integer NOT NULL,
    id_prestamo integer NOT NULL,
    id_tipo_pago integer NOT NULL,
    fecha_pago date NOT NULL,
    monto_pagado numeric(12,2) NOT NULL,
    observacion text,
    fecha_registro timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    numero_cuota integer,
    estado character varying(12) DEFAULT 'APLICADO'::character varying NOT NULL,
    fecha_anulacion timestamp without time zone,
    motivo_anulacion text,
    usuario_anulacion character varying(120),
    CONSTRAINT ck_pagos_estado CHECK (((estado)::text = ANY ((ARRAY['APLICADO'::character varying, 'ANULADO'::character varying])::text[])))
);


--
-- Name: pagos_id_pago_seq; Type: SEQUENCE; Schema: prestamos; Owner: -
--

ALTER TABLE prestamos.pagos ALTER COLUMN id_pago ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME prestamos.pagos_id_pago_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: plan_pagos; Type: TABLE; Schema: prestamos; Owner: -
--

CREATE TABLE prestamos.plan_pagos (
    id_plan_pago integer NOT NULL,
    id_prestamo integer NOT NULL,
    numero_cuota integer NOT NULL,
    fecha_vencimiento date NOT NULL,
    monto_programado numeric(12,2) NOT NULL,
    monto_pagado numeric(12,2) DEFAULT 0,
    estado character varying(20) DEFAULT 'PENDIENTE'::character varying
);


--
-- Name: plan_pagos_id_plan_pago_seq; Type: SEQUENCE; Schema: prestamos; Owner: -
--

ALTER TABLE prestamos.plan_pagos ALTER COLUMN id_plan_pago ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME prestamos.plan_pagos_id_plan_pago_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: prestamos; Type: TABLE; Schema: prestamos; Owner: -
--

CREATE TABLE prestamos.prestamos (
    id_prestamo integer NOT NULL,
    id_cliente integer NOT NULL,
    id_tipo_prestamos integer NOT NULL,
    id_frecuencia integer NOT NULL,
    id_estado_prestamo integer NOT NULL,
    monto_prestado numeric(12,2) NOT NULL,
    cuota numeric(12,2),
    cantidad_periodos integer,
    total_a_pagar numeric(12,2),
    monto_redito numeric(12,2),
    capital_pendiente numeric(12,2),
    fecha_inicio date NOT NULL,
    fecha_fin_estimada date,
    observacion text,
    fecha_registro timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    id_prestamo_origen integer,
    monto_descontado numeric(12,2),
    monto_entregado numeric(12,2)
);


--
-- Name: prestamos_id_prestamo_seq; Type: SEQUENCE; Schema: prestamos; Owner: -
--

ALTER TABLE prestamos.prestamos ALTER COLUMN id_prestamo ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME prestamos.prestamos_id_prestamo_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: recibos_pago; Type: TABLE; Schema: prestamos; Owner: -
--

CREATE TABLE prestamos.recibos_pago (
    id_recibo integer NOT NULL,
    id_pago integer NOT NULL,
    numero_recibo character varying(30) NOT NULL,
    fecha_emision timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    ruta_pdf text,
    estado character varying(20) DEFAULT 'GENERADO'::character varying
);


--
-- Name: recibos_pago_id_recibo_seq; Type: SEQUENCE; Schema: prestamos; Owner: -
--

ALTER TABLE prestamos.recibos_pago ALTER COLUMN id_recibo ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME prestamos.recibos_pago_id_recibo_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: respaldos; Type: TABLE; Schema: prestamos; Owner: -
--

CREATE TABLE prestamos.respaldos (
    id_respaldo integer NOT NULL,
    fecha timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    ruta_archivo text NOT NULL,
    observacion text
);


--
-- Name: respaldos_id_respaldo_seq; Type: SEQUENCE; Schema: prestamos; Owner: -
--

ALTER TABLE prestamos.respaldos ALTER COLUMN id_respaldo ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME prestamos.respaldos_id_respaldo_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: tipos_pago; Type: TABLE; Schema: prestamos; Owner: -
--

CREATE TABLE prestamos.tipos_pago (
    id_tipo_pago integer NOT NULL,
    nombre character varying(30) NOT NULL
);


--
-- Name: tipos_pago_id_tipo_pago_seq; Type: SEQUENCE; Schema: prestamos; Owner: -
--

ALTER TABLE prestamos.tipos_pago ALTER COLUMN id_tipo_pago ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME prestamos.tipos_pago_id_tipo_pago_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: tipos_prestamo; Type: TABLE; Schema: prestamos; Owner: -
--

CREATE TABLE prestamos.tipos_prestamo (
    id_tipo_prestamos integer NOT NULL,
    nombre character varying(20) NOT NULL
);


--
-- Name: tipos_prestamo_id_tipo_prestamos_seq; Type: SEQUENCE; Schema: prestamos; Owner: -
--

ALTER TABLE prestamos.tipos_prestamo ALTER COLUMN id_tipo_prestamos ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME prestamos.tipos_prestamo_id_tipo_prestamos_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: usuarios; Type: TABLE; Schema: prestamos; Owner: -
--

CREATE TABLE prestamos.usuarios (
    id_usuario integer NOT NULL,
    nombre character varying(100) NOT NULL,
    usuario character varying(50) NOT NULL,
    clave_hash text NOT NULL,
    rol character varying(20) DEFAULT 'ADMIN'::character varying NOT NULL,
    estado character varying(15) DEFAULT 'ACTIVO'::character varying NOT NULL,
    fecha_registro timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    ultimo_acceso timestamp without time zone,
    CONSTRAINT ck_usuarios_estado CHECK (((estado)::text = ANY ((ARRAY['ACTIVO'::character varying, 'INACTIVO'::character varying])::text[]))),
    CONSTRAINT ck_usuarios_rol CHECK (((rol)::text = ANY ((ARRAY['ADMIN'::character varying, 'COBRADOR'::character varying, 'CONSULTA'::character varying])::text[])))
);


--
-- Name: usuarios_id_usuario_seq; Type: SEQUENCE; Schema: prestamos; Owner: -
--

ALTER TABLE prestamos.usuarios ALTER COLUMN id_usuario ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME prestamos.usuarios_id_usuario_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: vw_prestamos_general; Type: VIEW; Schema: prestamos; Owner: -
--

CREATE VIEW prestamos.vw_prestamos_general AS
 SELECT p.id_prestamo,
    c.id_cliente,
    c.nombre AS cliente,
    tp.nombre AS tipo_prestamo,
    fp.nombre AS frecuencia,
    ep.nombre AS estado,
    p.monto_prestado,
    p.cuota,
    p.cantidad_periodos,
    p.total_a_pagar,
    p.monto_redito,
    p.capital_pendiente,
    p.fecha_inicio,
    p.fecha_fin_estimada,
    p.observacion,
    COALESCE(san.total_pagado_san, (0)::numeric) AS total_pagado_san,
    COALESCE(red.total_redito_pagado, (0)::numeric) AS total_redito_pagado,
    COALESCE(red.total_capital_abonado, (0)::numeric) AS total_capital_abonado,
        CASE
            WHEN ((tp.nombre)::text = 'SAN'::text) THEN (p.total_a_pagar - COALESCE(san.total_pagado_san, (0)::numeric))
            WHEN ((tp.nombre)::text = 'REDITO'::text) THEN p.capital_pendiente
            ELSE (0)::numeric
        END AS saldo_pendiente
   FROM ((((((prestamos.prestamos p
     JOIN prestamos.cliente c ON ((p.id_cliente = c.id_cliente)))
     JOIN prestamos.tipos_prestamo tp ON ((p.id_tipo_prestamos = tp.id_tipo_prestamos)))
     JOIN prestamos.frecuencias_pago fp ON ((p.id_frecuencia = fp.id_frecuencia)))
     JOIN prestamos.estados_prestamo ep ON ((p.id_estado_prestamo = ep.id_estado_prestamo)))
     LEFT JOIN ( SELECT plan_pagos.id_prestamo,
            sum(plan_pagos.monto_pagado) AS total_pagado_san
           FROM prestamos.plan_pagos
          GROUP BY plan_pagos.id_prestamo) san ON ((p.id_prestamo = san.id_prestamo)))
     LEFT JOIN ( SELECT pg.id_prestamo,
            sum(
                CASE
                    WHEN ((dp.concepto)::text = 'REDITO'::text) THEN dp.monto
                    ELSE (0)::numeric
                END) AS total_redito_pagado,
            sum(
                CASE
                    WHEN ((dp.concepto)::text = 'CAPITAL'::text) THEN dp.monto
                    ELSE (0)::numeric
                END) AS total_capital_abonado
           FROM (prestamos.pagos pg
             JOIN prestamos.detalle_pagos dp ON ((pg.id_pago = dp.id_pago)))
          GROUP BY pg.id_prestamo) red ON ((p.id_prestamo = red.id_prestamo)));


--
-- Name: vw_dashboard; Type: VIEW; Schema: prestamos; Owner: -
--

CREATE VIEW prestamos.vw_dashboard AS
 SELECT COALESCE(sum(monto_prestado), (0)::numeric) AS total_prestado,
    ((COALESCE(sum(total_pagado_san), (0)::numeric) + COALESCE(sum(total_redito_pagado), (0)::numeric)) + COALESCE(sum(total_capital_abonado), (0)::numeric)) AS total_cobrado,
    COALESCE(sum(saldo_pendiente), (0)::numeric) AS total_pendiente,
    COALESCE(sum(total_redito_pagado), (0)::numeric) AS total_redito_cobrado,
    COALESCE(sum(total_capital_abonado), (0)::numeric) AS total_capital_abonado,
    count(*) AS cantidad_prestamos,
    count(*) FILTER (WHERE ((estado)::text = 'ACTIVO'::text)) AS prestamos_activos,
    count(*) FILTER (WHERE ((estado)::text = 'SALDADO'::text)) AS prestamos_saldados,
    count(*) FILTER (WHERE ((estado)::text = 'ATRASADO'::text)) AS prestamos_atrasados,
    count(*) FILTER (WHERE ((tipo_prestamo)::text = 'SAN'::text)) AS prestamos_san,
    count(*) FILTER (WHERE ((tipo_prestamo)::text = 'REDITO'::text)) AS prestamos_redito
   FROM prestamos.vw_prestamos_general;


--
-- Name: vw_pagos_detallados; Type: VIEW; Schema: prestamos; Owner: -
--

CREATE VIEW prestamos.vw_pagos_detallados AS
 SELECT pg.id_pago,
    pg.id_prestamo,
    c.nombre AS cliente,
    tp.nombre AS tipo_prestamo,
    tpg.nombre AS tipo_pago,
    pg.fecha_pago,
    pg.monto_pagado,
    dp.concepto,
    dp.monto AS monto_detalle,
    pg.observacion,
    pg.fecha_registro
   FROM (((((prestamos.pagos pg
     JOIN prestamos.prestamos p ON ((pg.id_prestamo = p.id_prestamo)))
     JOIN prestamos.cliente c ON ((p.id_cliente = c.id_cliente)))
     JOIN prestamos.tipos_prestamo tp ON ((p.id_tipo_prestamos = tp.id_tipo_prestamos)))
     JOIN prestamos.tipos_pago tpg ON ((pg.id_tipo_pago = tpg.id_tipo_pago)))
     LEFT JOIN prestamos.detalle_pagos dp ON ((pg.id_pago = dp.id_pago)));


--
-- Name: vw_prestamos_redito; Type: VIEW; Schema: prestamos; Owner: -
--

CREATE VIEW prestamos.vw_prestamos_redito AS
 SELECT id_prestamo,
    id_cliente,
    cliente,
    frecuencia,
    estado,
    monto_prestado,
    monto_redito,
    total_redito_pagado,
    total_capital_abonado,
    capital_pendiente,
    fecha_inicio,
    observacion
   FROM prestamos.vw_prestamos_general
  WHERE ((tipo_prestamo)::text = 'REDITO'::text);


--
-- Name: vw_prestamos_san; Type: VIEW; Schema: prestamos; Owner: -
--

CREATE VIEW prestamos.vw_prestamos_san AS
 SELECT id_prestamo,
    id_cliente,
    cliente,
    frecuencia,
    estado,
    monto_prestado,
    cuota,
    cantidad_periodos,
    total_a_pagar,
    total_pagado_san AS total_pagado,
    saldo_pendiente,
    fecha_inicio,
    fecha_fin_estimada,
    observacion
   FROM prestamos.vw_prestamos_general
  WHERE ((tipo_prestamo)::text = 'SAN'::text);


--
-- Name: vw_recibo_detalle; Type: VIEW; Schema: prestamos; Owner: -
--

CREATE VIEW prestamos.vw_recibo_detalle AS
 SELECT r.id_recibo,
    r.numero_recibo,
    pg.id_pago,
    dp.concepto,
    dp.monto
   FROM ((prestamos.recibos_pago r
     JOIN prestamos.pagos pg ON ((r.id_pago = pg.id_pago)))
     JOIN prestamos.detalle_pagos dp ON ((pg.id_pago = dp.id_pago)));


--
-- Name: vw_recibo_encabezado; Type: VIEW; Schema: prestamos; Owner: -
--

CREATE VIEW prestamos.vw_recibo_encabezado AS
 SELECT r.id_recibo,
    r.numero_recibo,
    r.fecha_emision,
    r.ruta_pdf,
    r.estado AS estado_recibo,
    pg.id_pago,
    pg.fecha_pago,
    pg.monto_pagado,
    pg.observacion,
    p.id_prestamo,
    c.nombre AS cliente,
    c.telefono,
    tp.nombre AS tipo_prestamo,
    tpg.nombre AS tipo_pago,
    p.monto_prestado,
    p.total_a_pagar,
    p.capital_pendiente
   FROM (((((prestamos.recibos_pago r
     JOIN prestamos.pagos pg ON ((r.id_pago = pg.id_pago)))
     JOIN prestamos.prestamos p ON ((pg.id_prestamo = p.id_prestamo)))
     JOIN prestamos.cliente c ON ((p.id_cliente = c.id_cliente)))
     JOIN prestamos.tipos_prestamo tp ON ((p.id_tipo_prestamos = tp.id_tipo_prestamos)))
     JOIN prestamos.tipos_pago tpg ON ((pg.id_tipo_pago = tpg.id_tipo_pago)));


--
-- Name: vw_recibos_pago; Type: VIEW; Schema: prestamos; Owner: -
--

CREATE VIEW prestamos.vw_recibos_pago AS
 SELECT r.id_recibo,
    r.numero_recibo,
    r.fecha_emision,
    r.ruta_pdf,
    pg.id_pago,
    pg.fecha_pago,
    pg.monto_pagado,
    pg.observacion,
    c.nombre AS cliente,
    c.telefono,
    tp.nombre AS tipo_prestamo,
    tpg.nombre AS tipo_pago,
    p.id_prestamo,
    p.monto_prestado,
    p.total_a_pagar,
    p.capital_pendiente
   FROM (((((prestamos.recibos_pago r
     JOIN prestamos.pagos pg ON ((r.id_pago = pg.id_pago)))
     JOIN prestamos.prestamos p ON ((pg.id_prestamo = p.id_prestamo)))
     JOIN prestamos.cliente c ON ((p.id_cliente = c.id_cliente)))
     JOIN prestamos.tipos_prestamo tp ON ((p.id_tipo_prestamos = tp.id_tipo_prestamos)))
     JOIN prestamos.tipos_pago tpg ON ((pg.id_tipo_pago = tpg.id_tipo_pago)));


--
-- Name: vw_resumen_cliente; Type: VIEW; Schema: prestamos; Owner: -
--

CREATE VIEW prestamos.vw_resumen_cliente AS
 SELECT c.id_cliente,
    c.nombre AS cliente,
    c.telefono,
    count(p.id_prestamo) AS cantidad_prestamos,
    COALESCE(sum(v.monto_prestado), (0)::numeric) AS total_prestado,
    COALESCE(sum(v.saldo_pendiente), (0)::numeric) AS total_pendiente,
    COALESCE(sum(v.total_pagado_san), (0)::numeric) AS total_pagado_san,
    COALESCE(sum(v.total_redito_pagado), (0)::numeric) AS total_redito_pagado,
    COALESCE(sum(v.total_capital_abonado), (0)::numeric) AS total_capital_abonado
   FROM ((prestamos.cliente c
     LEFT JOIN prestamos.prestamos p ON ((c.id_cliente = p.id_cliente)))
     LEFT JOIN prestamos.vw_prestamos_general v ON ((p.id_prestamo = v.id_prestamo)))
  GROUP BY c.id_cliente, c.nombre, c.telefono;


--
-- Name: auditoria_usuarios auditoria_usuarios_pkey; Type: CONSTRAINT; Schema: prestamos; Owner: -
--

ALTER TABLE ONLY prestamos.auditoria_usuarios
    ADD CONSTRAINT auditoria_usuarios_pkey PRIMARY KEY (id_auditoria);


--
-- Name: cierre_caja_detalle cierre_caja_detalle_id_cierre_tipo_pago_key; Type: CONSTRAINT; Schema: prestamos; Owner: -
--

ALTER TABLE ONLY prestamos.cierre_caja_detalle
    ADD CONSTRAINT cierre_caja_detalle_id_cierre_tipo_pago_key UNIQUE (id_cierre, tipo_pago);


--
-- Name: cierre_caja_detalle cierre_caja_detalle_pkey; Type: CONSTRAINT; Schema: prestamos; Owner: -
--

ALTER TABLE ONLY prestamos.cierre_caja_detalle
    ADD CONSTRAINT cierre_caja_detalle_pkey PRIMARY KEY (id_detalle);


--
-- Name: cierres_caja cierres_caja_fecha_key; Type: CONSTRAINT; Schema: prestamos; Owner: -
--

ALTER TABLE ONLY prestamos.cierres_caja
    ADD CONSTRAINT cierres_caja_fecha_key UNIQUE (fecha);


--
-- Name: cierres_caja cierres_caja_pkey; Type: CONSTRAINT; Schema: prestamos; Owner: -
--

ALTER TABLE ONLY prestamos.cierres_caja
    ADD CONSTRAINT cierres_caja_pkey PRIMARY KEY (id_cierre);


--
-- Name: cliente cliente_pkey; Type: CONSTRAINT; Schema: prestamos; Owner: -
--

ALTER TABLE ONLY prestamos.cliente
    ADD CONSTRAINT cliente_pkey PRIMARY KEY (id_cliente);


--
-- Name: configuracion_sistema configuracion_sistema_clave_key; Type: CONSTRAINT; Schema: prestamos; Owner: -
--

ALTER TABLE ONLY prestamos.configuracion_sistema
    ADD CONSTRAINT configuracion_sistema_clave_key UNIQUE (clave);


--
-- Name: configuracion_sistema configuracion_sistema_pkey; Type: CONSTRAINT; Schema: prestamos; Owner: -
--

ALTER TABLE ONLY prestamos.configuracion_sistema
    ADD CONSTRAINT configuracion_sistema_pkey PRIMARY KEY (id_configuracion);


--
-- Name: detalle_pagos detalle_pagos_pkey; Type: CONSTRAINT; Schema: prestamos; Owner: -
--

ALTER TABLE ONLY prestamos.detalle_pagos
    ADD CONSTRAINT detalle_pagos_pkey PRIMARY KEY (id_detalle_pago);


--
-- Name: estados_prestamo estados_prestamo_pkey; Type: CONSTRAINT; Schema: prestamos; Owner: -
--

ALTER TABLE ONLY prestamos.estados_prestamo
    ADD CONSTRAINT estados_prestamo_pkey PRIMARY KEY (id_estado_prestamo);


--
-- Name: frecuencias_pago frecuencias_pago_nombre_key; Type: CONSTRAINT; Schema: prestamos; Owner: -
--

ALTER TABLE ONLY prestamos.frecuencias_pago
    ADD CONSTRAINT frecuencias_pago_nombre_key UNIQUE (nombre);


--
-- Name: frecuencias_pago frecuencias_pago_pkey; Type: CONSTRAINT; Schema: prestamos; Owner: -
--

ALTER TABLE ONLY prestamos.frecuencias_pago
    ADD CONSTRAINT frecuencias_pago_pkey PRIMARY KEY (id_frecuencia);


--
-- Name: historial_prestamos historial_prestamos_pkey; Type: CONSTRAINT; Schema: prestamos; Owner: -
--

ALTER TABLE ONLY prestamos.historial_prestamos
    ADD CONSTRAINT historial_prestamos_pkey PRIMARY KEY (id_historial);


--
-- Name: movimientos_caja movimientos_caja_pkey; Type: CONSTRAINT; Schema: prestamos; Owner: -
--

ALTER TABLE ONLY prestamos.movimientos_caja
    ADD CONSTRAINT movimientos_caja_pkey PRIMARY KEY (id_movimiento);


--
-- Name: pagos pagos_pkey; Type: CONSTRAINT; Schema: prestamos; Owner: -
--

ALTER TABLE ONLY prestamos.pagos
    ADD CONSTRAINT pagos_pkey PRIMARY KEY (id_pago);


--
-- Name: plan_pagos plan_pagos_pkey; Type: CONSTRAINT; Schema: prestamos; Owner: -
--

ALTER TABLE ONLY prestamos.plan_pagos
    ADD CONSTRAINT plan_pagos_pkey PRIMARY KEY (id_plan_pago);


--
-- Name: prestamos prestamos_pkey; Type: CONSTRAINT; Schema: prestamos; Owner: -
--

ALTER TABLE ONLY prestamos.prestamos
    ADD CONSTRAINT prestamos_pkey PRIMARY KEY (id_prestamo);


--
-- Name: recibos_pago recibos_pago_id_pago_key; Type: CONSTRAINT; Schema: prestamos; Owner: -
--

ALTER TABLE ONLY prestamos.recibos_pago
    ADD CONSTRAINT recibos_pago_id_pago_key UNIQUE (id_pago);


--
-- Name: recibos_pago recibos_pago_numero_recibo_key; Type: CONSTRAINT; Schema: prestamos; Owner: -
--

ALTER TABLE ONLY prestamos.recibos_pago
    ADD CONSTRAINT recibos_pago_numero_recibo_key UNIQUE (numero_recibo);


--
-- Name: recibos_pago recibos_pago_pkey; Type: CONSTRAINT; Schema: prestamos; Owner: -
--

ALTER TABLE ONLY prestamos.recibos_pago
    ADD CONSTRAINT recibos_pago_pkey PRIMARY KEY (id_recibo);


--
-- Name: respaldos respaldos_pkey; Type: CONSTRAINT; Schema: prestamos; Owner: -
--

ALTER TABLE ONLY prestamos.respaldos
    ADD CONSTRAINT respaldos_pkey PRIMARY KEY (id_respaldo);


--
-- Name: tipos_pago tipos_pago_nombre_key; Type: CONSTRAINT; Schema: prestamos; Owner: -
--

ALTER TABLE ONLY prestamos.tipos_pago
    ADD CONSTRAINT tipos_pago_nombre_key UNIQUE (nombre);


--
-- Name: tipos_pago tipos_pago_pkey; Type: CONSTRAINT; Schema: prestamos; Owner: -
--

ALTER TABLE ONLY prestamos.tipos_pago
    ADD CONSTRAINT tipos_pago_pkey PRIMARY KEY (id_tipo_pago);


--
-- Name: tipos_prestamo tipos_prestamo_nombre_key; Type: CONSTRAINT; Schema: prestamos; Owner: -
--

ALTER TABLE ONLY prestamos.tipos_prestamo
    ADD CONSTRAINT tipos_prestamo_nombre_key UNIQUE (nombre);


--
-- Name: tipos_prestamo tipos_prestamo_pkey; Type: CONSTRAINT; Schema: prestamos; Owner: -
--

ALTER TABLE ONLY prestamos.tipos_prestamo
    ADD CONSTRAINT tipos_prestamo_pkey PRIMARY KEY (id_tipo_prestamos);


--
-- Name: usuarios usuarios_pkey; Type: CONSTRAINT; Schema: prestamos; Owner: -
--

ALTER TABLE ONLY prestamos.usuarios
    ADD CONSTRAINT usuarios_pkey PRIMARY KEY (id_usuario);


--
-- Name: usuarios usuarios_usuario_key; Type: CONSTRAINT; Schema: prestamos; Owner: -
--

ALTER TABLE ONLY prestamos.usuarios
    ADD CONSTRAINT usuarios_usuario_key UNIQUE (usuario);


--
-- Name: pagos trg_bloquear_fecha_cerrada; Type: TRIGGER; Schema: prestamos; Owner: -
--

CREATE TRIGGER trg_bloquear_fecha_cerrada BEFORE INSERT OR UPDATE OF fecha_pago, estado ON prestamos.pagos FOR EACH ROW EXECUTE FUNCTION prestamos.fn_bloquear_fecha_cerrada();


--
-- Name: pagos trg_historial_pago_registrado; Type: TRIGGER; Schema: prestamos; Owner: -
--

CREATE TRIGGER trg_historial_pago_registrado AFTER INSERT ON prestamos.pagos FOR EACH ROW EXECUTE FUNCTION prestamos.fn_historial_pago_registrado();


--
-- Name: prestamos trg_historial_prestamo_creado; Type: TRIGGER; Schema: prestamos; Owner: -
--

CREATE TRIGGER trg_historial_prestamo_creado AFTER INSERT ON prestamos.prestamos FOR EACH ROW EXECUTE FUNCTION prestamos.fn_historial_prestamo_creado();


--
-- Name: auditoria_usuarios auditoria_usuarios_id_usuario_fkey; Type: FK CONSTRAINT; Schema: prestamos; Owner: -
--

ALTER TABLE ONLY prestamos.auditoria_usuarios
    ADD CONSTRAINT auditoria_usuarios_id_usuario_fkey FOREIGN KEY (id_usuario) REFERENCES prestamos.usuarios(id_usuario);


--
-- Name: auditoria_usuarios auditoria_usuarios_realizado_por_fkey; Type: FK CONSTRAINT; Schema: prestamos; Owner: -
--

ALTER TABLE ONLY prestamos.auditoria_usuarios
    ADD CONSTRAINT auditoria_usuarios_realizado_por_fkey FOREIGN KEY (realizado_por) REFERENCES prestamos.usuarios(id_usuario);


--
-- Name: cierre_caja_detalle cierre_caja_detalle_id_cierre_fkey; Type: FK CONSTRAINT; Schema: prestamos; Owner: -
--

ALTER TABLE ONLY prestamos.cierre_caja_detalle
    ADD CONSTRAINT cierre_caja_detalle_id_cierre_fkey FOREIGN KEY (id_cierre) REFERENCES prestamos.cierres_caja(id_cierre);


--
-- Name: movimientos_caja fk_caja_pago; Type: FK CONSTRAINT; Schema: prestamos; Owner: -
--

ALTER TABLE ONLY prestamos.movimientos_caja
    ADD CONSTRAINT fk_caja_pago FOREIGN KEY (id_pago) REFERENCES prestamos.pagos(id_pago);


--
-- Name: movimientos_caja fk_caja_prestamo; Type: FK CONSTRAINT; Schema: prestamos; Owner: -
--

ALTER TABLE ONLY prestamos.movimientos_caja
    ADD CONSTRAINT fk_caja_prestamo FOREIGN KEY (id_prestamo) REFERENCES prestamos.prestamos(id_prestamo);


--
-- Name: detalle_pagos fk_detalle_pago; Type: FK CONSTRAINT; Schema: prestamos; Owner: -
--

ALTER TABLE ONLY prestamos.detalle_pagos
    ADD CONSTRAINT fk_detalle_pago FOREIGN KEY (id_pago) REFERENCES prestamos.pagos(id_pago);


--
-- Name: historial_prestamos fk_historial_prestamo; Type: FK CONSTRAINT; Schema: prestamos; Owner: -
--

ALTER TABLE ONLY prestamos.historial_prestamos
    ADD CONSTRAINT fk_historial_prestamo FOREIGN KEY (id_prestamo) REFERENCES prestamos.prestamos(id_prestamo);


--
-- Name: pagos fk_pago_prestamo; Type: FK CONSTRAINT; Schema: prestamos; Owner: -
--

ALTER TABLE ONLY prestamos.pagos
    ADD CONSTRAINT fk_pago_prestamo FOREIGN KEY (id_prestamo) REFERENCES prestamos.prestamos(id_prestamo);


--
-- Name: pagos fk_pago_tipo; Type: FK CONSTRAINT; Schema: prestamos; Owner: -
--

ALTER TABLE ONLY prestamos.pagos
    ADD CONSTRAINT fk_pago_tipo FOREIGN KEY (id_tipo_pago) REFERENCES prestamos.tipos_pago(id_tipo_pago);


--
-- Name: plan_pagos fk_plan_prestamo; Type: FK CONSTRAINT; Schema: prestamos; Owner: -
--

ALTER TABLE ONLY prestamos.plan_pagos
    ADD CONSTRAINT fk_plan_prestamo FOREIGN KEY (id_prestamo) REFERENCES prestamos.prestamos(id_prestamo);


--
-- Name: prestamos fk_prestamo_cliente; Type: FK CONSTRAINT; Schema: prestamos; Owner: -
--

ALTER TABLE ONLY prestamos.prestamos
    ADD CONSTRAINT fk_prestamo_cliente FOREIGN KEY (id_cliente) REFERENCES prestamos.cliente(id_cliente);


--
-- Name: prestamos fk_prestamo_estado; Type: FK CONSTRAINT; Schema: prestamos; Owner: -
--

ALTER TABLE ONLY prestamos.prestamos
    ADD CONSTRAINT fk_prestamo_estado FOREIGN KEY (id_estado_prestamo) REFERENCES prestamos.estados_prestamo(id_estado_prestamo);


--
-- Name: prestamos fk_prestamo_frecuencia; Type: FK CONSTRAINT; Schema: prestamos; Owner: -
--

ALTER TABLE ONLY prestamos.prestamos
    ADD CONSTRAINT fk_prestamo_frecuencia FOREIGN KEY (id_frecuencia) REFERENCES prestamos.frecuencias_pago(id_frecuencia);


--
-- Name: prestamos fk_prestamo_origen; Type: FK CONSTRAINT; Schema: prestamos; Owner: -
--

ALTER TABLE ONLY prestamos.prestamos
    ADD CONSTRAINT fk_prestamo_origen FOREIGN KEY (id_prestamo_origen) REFERENCES prestamos.prestamos(id_prestamo);


--
-- Name: prestamos fk_prestamo_tipo; Type: FK CONSTRAINT; Schema: prestamos; Owner: -
--

ALTER TABLE ONLY prestamos.prestamos
    ADD CONSTRAINT fk_prestamo_tipo FOREIGN KEY (id_tipo_prestamos) REFERENCES prestamos.tipos_prestamo(id_tipo_prestamos);


--
-- Name: recibos_pago fk_recibo_pago; Type: FK CONSTRAINT; Schema: prestamos; Owner: -
--

ALTER TABLE ONLY prestamos.recibos_pago
    ADD CONSTRAINT fk_recibo_pago FOREIGN KEY (id_pago) REFERENCES prestamos.pagos(id_pago);


--
-- PostgreSQL database dump complete
--

\unrestrict CmL2Kv33xPEaxHtd6NC9hRNNZzCb9hvnFUWexBlxdShcJPCXHHp8Janj0cENNRH

