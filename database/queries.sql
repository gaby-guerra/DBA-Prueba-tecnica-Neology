-- =============================================================================
-- PROYECTO: Sistema de Gestión de Acceso y Estacionamiento (Neology)
-- ARCHIVO: database/queries.sql
-- MOTOR: MariaDB 12.3
-- FECHA: 10-09-2026
-- DESCRIPCIÓN: Consulta para validar los diferentes escenarios
-- =============================================================================

-- 1. Consultar los vehículos que se encuentran actualmente dentro del estacionamiento.
SELECT  v.placa,  fecha_entrada, fecha_salida
FROM  vehiculo v
INNER  JOIN  estancia e ON v.placa = e.placa
WHERE fecha_entrada >= current_date ()
AND fecha_salida IS NULL;

-- 2. Calcular la duración y el importe correspondiente a una estancia.
SET @placa = 'RES-102';

SELECT 
    e.id_estancia,
    e.placa,
    tv.codigo AS tipo_vehiculo,
    e.fecha_entrada,
    COALESCE(e.fecha_salida, NOW()) AS fecha_calculo,
    TIMESTAMPDIFF(MINUTE, e.fecha_entrada, COALESCE(e.fecha_salida, NOW())) AS minutos_estancia,
    t.costo_por_minuto,
    ROUND(
        TIMESTAMPDIFF(MINUTE, e.fecha_entrada, COALESCE(e.fecha_salida, NOW())) * t.costo_por_minuto, 
        2
    ) AS importe_total
FROM estancia e
INNER JOIN tarifa t 
    ON e.id_tarifa = t.id_tarifa
INNER JOIN tipo_vehiculo tv 
    ON t.id_tipo_vehiculo = tv.id_tipo_vehiculo
WHERE e.placa = @placa;

-- 3. Generar el reporte mensual de residentes.
-- Parámetros de consulta (Año y Mes a consultar)
SET @anio = 2026;
SET @mes  = 8;

SELECT 
    r.id_residente,
    CONCAT(r.nombre, ' ', r.apellido_p, ' ', COALESCE(r.apellido_m, '')) AS residente,
    r.numero_departamento,
    v.placa,
    v.marca,
    v.modelo,
    COUNT(e.id_estancia) AS total_estancias,
    COALESCE(SUM(e.minutos_totales), 0) AS total_minutos_acumulados,
    ROUND(COALESCE(SUM(e.minutos_totales * t.costo_por_minuto), 0.00), 2) AS total_a_pagar,
    COALESCE(cm.estado, 'SIN_CIERRE') AS estado_cierre,
    cm.fecha_cierre
FROM residente r
INNER JOIN vehiculo v 
    ON r.id_residente = v.id_residente
INNER JOIN estancia e 
    ON v.placa = e.placa 
    AND e.estado = 'FINALIZADA'
    AND YEAR(e.fecha_salida) = @anio 
    AND MONTH(e.fecha_salida) = @mes
INNER JOIN tarifa t 
    ON e.id_tarifa = t.id_tarifa
LEFT JOIN cierre_mensual cm 
    ON r.id_residente = cm.id_residente 
    AND cm.anio = @anio 
    AND cm.mes = @mes
WHERE r.activo = 1
GROUP BY 
    r.id_residente,
    r.nombre,
    r.apellido_p,
    r.apellido_m,
    r.numero_departamento,
    v.placa,
    v.marca,
    v.modelo,
    cm.estado,
    cm.fecha_cierre
ORDER BY 
    r.apellido_p ASC, 
    r.nombre ASC, 
    v.placa ASC;

-- 4. Consultar ingresos por día y por tipo de vehículo.
-- Parámetros de rango de fechas para el reporte
SET @fecha_inicio = '2026-08-01 00:00:00';
SET @fecha_fin    = '2026-08-31 23:59:59';

SELECT 
    DATE(cp.fecha_pago) AS fecha,
    tv.codigo AS tipo_vehiculo,
    tv.descripcion,
    COUNT(cp.id_pago) AS total_transacciones,
    ROUND(SUM(cp.monto), 2) AS total_ingresos
FROM cargo_pago cp
LEFT JOIN estancia e 
    ON cp.id_estancia = e.id_estancia
LEFT JOIN vehiculo ve 
    ON e.placa = ve.placa
LEFT JOIN cierre_mensual cm 
    ON cp.id_cierre = cm.id_cierre
LEFT JOIN residente r 
    ON cm.id_residente = r.id_residente
INNER JOIN tipo_vehiculo tv 
    ON tv.id_tipo_vehiculo = CASE 
        WHEN cp.tipo_cargo = 'MENSUAL' THEN 2 
        ELSE ve.id_tipo_vehiculo 
    END
WHERE cp.fecha_pago BETWEEN @fecha_inicio AND @fecha_fin
GROUP BY 
    DATE(cp.fecha_pago),
    tv.id_tipo_vehiculo,
    tv.codigo,
    tv.descripcion
ORDER BY 
    fecha DESC, 
    total_ingresos DESC;

-- 5. Consultar el promedio de permanencia por tipo de vehículo.
SELECT 
    tv.codigo AS tipo_vehiculo,
    tv.descripcion,
    COUNT(e.id_estancia) AS total_estancias_concluidas,
    ROUND(AVG(e.minutos_totales), 2) AS promedio_minutos,
    CONCAT(
        LPAD(FLOOR(AVG(e.minutos_totales) / 60), 2, '0'), 
        ':', 
        LPAD(ROUND(MOD(AVG(e.minutos_totales), 60)), 2, '0')
    ) AS promedio_hh_mm,
    MIN(e.minutos_totales) AS estancia_minima_minutos,
    MAX(e.minutos_totales) AS estancia_maxima_minutos
FROM tipo_vehiculo tv
INNER JOIN tarifa t 
    ON tv.id_tipo_vehiculo = t.id_tipo_vehiculo
INNER JOIN estancia e 
    ON t.id_tarifa = e.id_tarifa
WHERE e.estado = 'FINALIZADA'
  AND e.fecha_salida IS NOT NULL
GROUP BY 
    tv.id_tipo_vehiculo, 
    tv.codigo, 
    tv.descripcion
ORDER BY 
    promedio_minutos DESC;
	
-- 6. Identificar vehículos con más de una estancia abierta.
-- Nota: Si este query se ejecuta sobre la base de datos con el esquema implementado, devolverá 0 filas,
-- Lo anterior debido a la restricción de integridad en uq_estancia_vehiculo_activa sobre estancia_activa_uk
-- bloquea a nivel de motor cualquier intento de registrar un segundo acceso sin haber concluido el anterior.
SELECT 
    v.placa,
    tv.codigo AS tipo_vehiculo,
    v.marca,
    v.modelo,
    COUNT(e.id_estancia) AS estancias_abiertas,
    GROUP_CONCAT(e.id_estancia ORDER BY e.fecha_entrada ASC SEPARATOR ', ') AS ids_estancias,
    MIN(e.fecha_entrada) AS primer_acceso_abierto,
    MAX(e.fecha_entrada) AS ultimo_acceso_abierto
FROM vehiculo v
INNER JOIN estancia e 
    ON v.placa = e.placa
INNER JOIN tipo_vehiculo tv 
    ON v.id_tipo_vehiculo = tv.id_tipo_vehiculo
WHERE e.fecha_salida IS NULL
   OR e.estado = 'ABIERTA'
GROUP BY 
    v.placa,
    tv.codigo,
    v.marca,
    v.modelo
HAVING COUNT(e.id_estancia) > 1;

-- 7. Detectar registros con fechas inconsistentes.
--Esta consulta no retorna datos ya que la tabla estancia contiene una restricción CHECK que la protege
--Si se intenta hacer un insert con fecha_salida menor que fecha_entrada MariaDB la rechazará
SELECT 
    'ESTANCIA: Salida anterior a la entrada' AS tipo_inconsistencia,
    e.id_estancia AS id_registro,
    e.placa,
    e.fecha_entrada,
    e.fecha_salida,
    CONCAT(
        'Diferencia negativa: ', 
        TIMESTAMPDIFF(MINUTE, e.fecha_entrada, e.fecha_salida), 
        ' minutos'
    ) AS detalle_error
FROM estancia e
WHERE e.fecha_salida IS NOT NULL
  AND e.fecha_salida < e.fecha_entrada

UNION ALL

SELECT 
    'ESTANCIA: Fecha en el futuro (desfase de reloj/captura)' AS tipo_inconsistencia,
    e.id_estancia AS id_registro,
    e.placa,
    e.fecha_entrada,
    e.fecha_salida,
    CONCAT(
        'Entrada futura respecto al servidor por: ', 
        TIMESTAMPDIFF(MINUTE, NOW(), e.fecha_entrada), 
        ' minutos'
    ) AS detalle_error
FROM estancia e
WHERE e.fecha_entrada > NOW()

UNION ALL

SELECT 
    'TARIFA: Fin de vigencia anterior al inicio' AS tipo_inconsistencia,
    t.id_tarifa AS id_registro,
    tv.codigo AS placa,
    t.fecha_inicio AS fecha_entrada,
    t.fecha_fin AS fecha_salida,
    CONCAT(
        'Vigencia invertida: ', 
        TIMESTAMPDIFF(MINUTE, t.fecha_inicio, t.fecha_fin), 
        ' minutos'
    ) AS detalle_error
FROM tarifa t
INNER JOIN tipo_vehiculo tv 
    ON t.id_tipo_vehiculo = tv.id_tipo_vehiculo
WHERE t.fecha_fin IS NOT NULL 
  AND t.fecha_fin < t.fecha_inicio;
  
-- 8. Consultar los vehículos con mayor tiempo acumulado durante el mes.
-- Parámetros de consulta (Año y Mes a evaluar)
SET @anio = 2026;
SET @mes  = 8;

SELECT 
    v.placa,
    tv.codigo AS tipo_vehiculo,
    v.marca,
    v.modelo,
    -- Conteo de visitas en el mes
    COUNT(e.id_estancia) AS total_accesos,
    -- Tiempo acumulado en minutos
    SUM(e.minutos_totales) AS tiempo_total_minutos,
    -- Representación formateada en Días, Horas y Minutos
    CONCAT(
        FLOOR(SUM(e.minutos_totales) / 1440), 'd ',
        LPAD(FLOOR(MOD(SUM(e.minutos_totales), 1440) / 60), 2, '0'), 'h ',
        LPAD(MOD(SUM(e.minutos_totales), 60), 2, '0'), 'm'
    ) AS tiempo_acumulado_formato,
    -- Información del propietario si es residente
    CASE 
        WHEN r.id_residente IS NOT NULL 
        THEN CONCAT(r.nombre, ' ', r.apellido_p, ' (', r.numero_departamento, ')')
        ELSE 'VISITANTE / OFICIAL'
    END AS asignado_a
FROM vehiculo v
INNER JOIN estancia e 
    ON v.placa = e.placa
INNER JOIN tipo_vehiculo tv 
    ON v.id_tipo_vehiculo = tv.id_tipo_vehiculo
LEFT JOIN residente r 
    ON v.id_residente = r.id_residente
WHERE e.estado = 'FINALIZADA'
  AND e.fecha_salida IS NOT NULL
  AND YEAR(e.fecha_salida) = @anio
  AND MONTH(e.fecha_salida) = @mes
GROUP BY 
    v.placa,
    tv.codigo,
    v.marca,
    v.modelo,
    r.id_residente,
    r.nombre,
    r.apellido_p,
    r.numero_departamento
ORDER BY 
    tiempo_total_minutos DESC
LIMIT 10; -- Se limita a los 10 primeros