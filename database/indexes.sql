-- =============================================================================
-- PROYECTO: Sistema de Gestión de Acceso y Estacionamiento (Neology)
-- ARCHIVO: database/indexes.sql
-- MOTOR: MariaDB 12.3
-- FECHA: 10-09-2026
-- DESCRIPCIÓN: Índices estratégicos de rendimiento y cobertura para alta concurrencia.
-- =============================================================================

USE estacionamiento_db;

-- -----------------------------------------------------------------------------
-- ÍNDICE 1: Cobertura para cálculo de cobros y validación de estancias activas
-- Consulta 2 (Cálculo de estancia) y accesos frecuentes por placa
-- -----------------------------------------------------------------------------
-- Justificación:
-- Orden: (placa, fecha_salida, fecha_entrada, id_tarifa)
-- 1. `placa`: Máxima selectividad (filtro de igualdad directa).
-- 2. `fecha_salida`: Permite evaluar si es nula o rango sin scan adicional.
-- 3. `fecha_entrada`, `id_tarifa`: Al incluirlos al final, el índice actúa como
--    Covering Index (Index-Only Scan), evitando viajes al clustered index (Primary Key).
CREATE INDEX idx_estancia_placa_salida_cobro 
ON estancia (placa, fecha_salida, fecha_entrada, id_tarifa);

-- -----------------------------------------------------------------------------
-- ÍNDICE 2: Optimización de reportes cronológicos y cortes de residentes
-- Consultas 3 (Reporte mensual) y 8 (Top permanencia mensual)
-- -----------------------------------------------------------------------------
-- Justificación:
-- Orden: (estado, fecha_salida, minutos_totales, placa, id_tarifa)
-- 1. `estado`: Filtro de igualdad previo ('FINALIZADA').
-- 2. `fecha_salida`: Filtro de rango temporal (mes/año).
-- 3. `minutos_totales`, `placa`, `id_tarifa`: Columnas necesarias para SUM/AVG/JOINs,
--    eliminando la lectura de páginas de datos de la tabla base en lecturas masivas.
CREATE INDEX idx_estancia_cierre_analitica 
ON estancia (estado, fecha_salida, minutos_totales, placa, id_tarifa);

-- -----------------------------------------------------------------------------
-- ÍNDICE 3: Flujo de caja e ingresos consolidados
-- Consulta 4 (Ingresos por día y tipo de vehículo)
-- -----------------------------------------------------------------------------
-- Justificación:
-- Orden: (fecha_pago, tipo_cargo, monto, id_estancia, id_cierre)
-- Permite agrupar por DATE(fecha_pago) rápidamente mediante un escaneo por rango.
CREATE INDEX idx_pago_analitica_fecha 
ON cargo_pago (fecha_pago, tipo_cargo, monto, id_estancia, id_cierre);