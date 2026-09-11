-- =============================================================================
-- PROYECTO: Sistema de Gestión de Acceso y Estacionamiento (Neology)
-- ARCHIVO: database/monthly-close.sql
-- MOTOR: MariaDB 12.3
-- FECHA: 10-09-2026
-- DESCRIPCIÓN: Store procedure para Operación de cierre mensual
-- =============================================================================

USE estacionamiento_db;

DELIMITER //

DROP PROCEDURE IF EXISTS sp_ejecutar_cierre_mensual //

CREATE PROCEDURE sp_ejecutar_cierre_mensual(
    IN p_anio SMALLINT,
    IN p_mes TINYINT,
    IN p_usuario VARCHAR(100)
)
proc_label: BEGIN
    -- Variables de control y manejo de errores
    DECLARE v_cierres_existentes INT DEFAULT 0;
    DECLARE v_total_residentes_procesados INT DEFAULT 0;
    DECLARE v_error_code CHAR(5) DEFAULT '00000';
    DECLARE v_error_msg TEXT;

    -- Manejo de excepciones transaccionales: Garantiza consistencia en caso de error
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1
            v_error_code = RETURNED_SQLSTATE,
            v_error_msg = MESSAGE_TEXT;
        
        ROLLBACK;
        
        -- Registro del fallo en auditoría para trazabilidad
        INSERT INTO auditoria_log (
            tabla_afectada, 
            operacion, 
            id_registro, 
            datos_previos, 
            datos_nuevos, 
            usuario_bd, 
            fecha_evento
        ) VALUES (
            'cierre_mensual',
            'UPDATE',
            CONCAT(p_anio, '-', LPAD(p_mes, 2, '0')),
            NULL,
            JSON_OBJECT('estado', 'ERROR_ROLLBACK', 'sqlstate', v_error_code, 'mensaje', v_error_msg),
            COALESCE(p_usuario, USER()),
            NOW()
        );
        
        RESIGNAL;
    END;

    -- Validación de parámetros de entrada
    IF p_mes NOT BETWEEN 1 AND 12 THEN
        SIGNAL SQLSTATE '45000' 
            SET MESSAGE_TEXT = 'Error: El mes ingresado debe ser un valor entre 1 y 12.';
    END IF;

    -- Prevención de ejecuciones duplicadas
    -- Revisa si ya existen cortes generados para este año y mes
    SELECT COUNT(*) INTO v_cierres_existentes
    FROM cierre_mensual
    WHERE anio = p_anio AND mes = p_mes;

    IF v_cierres_existentes > 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Operación cancelada: El cierre de este periodo (año/mes) ya fue procesado con anterioridad.';
    END IF;

    START TRANSACTION;

    -- Insertar las cabeceras de cierre consolidando minutos e importe por residente
    INSERT INTO cierre_mensual (
        id_residente, 
        anio, 
        mes, 
        minutos_acumulados, 
        monto_total, 
        estado, 
        fecha_cierre
    )
    SELECT 
        r.id_residente,
        p_anio,
        p_mes,
        COALESCE(SUM(e.minutos_totales), 0) AS total_minutos,
        COALESCE(ROUND(SUM(e.minutos_totales * t.costo_por_minuto), 2), 0.00) AS total_monto,
        'PENDIENTE' AS estado,
        NOW() AS fecha_cierre
    FROM residente r
    INNER JOIN vehiculo v 
        ON r.id_residente = v.id_residente
    INNER JOIN estancia e 
        ON v.placa = e.placa
    INNER JOIN tarifa t 
        ON e.id_tarifa = t.id_tarifa
    WHERE e.estado = 'FINALIZADA'
      AND YEAR(e.fecha_salida) = p_anio
      AND MONTH(e.fecha_salida) = p_mes
    GROUP BY r.id_residente;

    -- Validar si hubo actividad facturable de residentes en el periodo
    SET v_total_residentes_procesados = ROW_COUNT();

    IF v_total_residentes_procesados > 0 THEN
        -- Insertar el detalle partida por partida vinculando cada estancia con su cierre
        INSERT INTO detalle_cierre_residente (
            id_cierre, 
            id_estancia, 
            minutos_facturados, 
            costo_minuto_aplicado, 
            monto_facturado
        )
        SELECT 
            cm.id_cierre,
            e.id_estancia,
            e.minutos_totales,
            t.costo_por_minuto,
            ROUND(e.minutos_totales * t.costo_por_minuto, 2)
        FROM cierre_mensual cm
        INNER JOIN vehiculo v 
            ON cm.id_residente = v.id_residente
        INNER JOIN estancia e 
            ON v.placa = e.placa
        INNER JOIN tarifa t 
            ON e.id_tarifa = t.id_tarifa
        WHERE cm.anio = p_anio 
          AND cm.mes = p_mes
          AND e.estado = 'FINALIZADA'
          AND YEAR(e.fecha_salida) = p_anio
          AND MONTH(e.fecha_salida) = p_mes;
    END IF;

    -- Trazabilidad y auditoría: Quién, cuándo y qué se ejecutó
    INSERT INTO auditoria_log (
        tabla_afectada, 
        operacion, 
        id_registro, 
        datos_previos, 
        datos_nuevos, 
        usuario_bd, 
        fecha_evento
    ) VALUES (
        'cierre_mensual',
        'INSERT',
        CONCAT(p_anio, '-', LPAD(p_mes, 2, '0')),
        NULL,
        JSON_OBJECT(
            'accion', 'CIERRE_MENSUAL_EJECUTADO',
            'anio', p_anio,
            'mes', p_mes,
            'residentes_facturados', v_total_residentes_procesados,
            'ejecutado_por', COALESCE(p_usuario, USER())
        ),
        COALESCE(p_usuario, USER()),
        NOW()
    );
    COMMIT;

    -- Mensaje de éxito de la operación
    SELECT 
        'EXITO' AS resultado,
        CONCAT('Cierre completado para el periodo ', p_anio, '-', LPAD(p_mes, 2, '0')) AS mensaje,
        v_total_residentes_procesados AS residentes_afectados,
        COALESCE(p_usuario, USER()) AS ejecutado_por,
        NOW() AS fecha_ejecucion;

END //

DELIMITER ;