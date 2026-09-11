-- =============================================================================
-- PROYECTO: Sistema de Gestión de Acceso y Estacionamiento (Neology)
-- ARCHIVO: database/data.sql
-- DESCRIPCIÓN: Carga de datos iniciales, catálogos, tarifas y casos de prueba.
-- =============================================================================

-- 1. TIPOS DE VEHÍCULO
INSERT INTO tipo_vehiculo (id_tipo_vehiculo, codigo, descripcion, requiere_pago, activo) VALUES
(1, 'OFICIAL', 'Vehículo de servicio público, emergencia o administración', 0, 1),
(2, 'RESIDENTE', 'Vehículo perteneciente a un habitante del complejo', 1, 1),
(3, 'NO_RESIDENTE', 'Vehículo visitante o usuario externo', 1, 1);
COMMIT;

-- 2. TARIFAS BASE (Vigentes)
-- Reglas: Oficial $0.00, Residente $0.05/min, No Residente $0.50/min
INSERT INTO tarifa (id_tarifa, id_tipo_vehiculo, costo_por_minuto, fecha_inicio, fecha_fin, activo) VALUES
(1, 1, 0.0000, '2026-01-01 00:00:00', NULL, 1),
(2, 2, 0.0500, '2026-01-01 00:00:00', NULL, 1),
(3, 3, 0.5000, '2026-01-01 00:00:00', NULL, 1);
COMMIT;

-- 3. RESIDENTES
INSERT INTO residente (id_residente, apellido_p, apellido_m, nombre, numero_departamento, telefono, correo, activo) VALUES
(1, 'Mendoza', 'Silva', 'Carlos', 'Torre A - Depto 402', '5551234567', 'carlos.mendoza@email.com', 1),
(2, 'Rios', 'Castro', 'Mariana', 'Torre B - Depto 105', '5559876543', 'mariana.rios@email.com', 1);
COMMIT;

-- 4. VEHÍCULOS
INSERT INTO vehiculo (placa, id_tipo_vehiculo, id_residente, marca, modelo, color, activo) VALUES
-- Vehículos Oficiales
('OFI-001', 1, NULL, 'Ford', 'F-150 Patrulla', 'Blanco/Azul', 1),
('OFI-002', 1, NULL, 'Chevrolet', 'Express Ambulancia', 'Blanco/Rojo', 1),

-- Vehículos Residentes (Asignados a su titular)
('RES-101', 2, 1, 'Mazda', 'Mazda 3', 'Rojo', 1),
('RES-102', 2, 1, 'Nissan', 'Kicks', 'Gris', 1),
('RES-201', 2, 2, 'Volkswagen', 'Jetta', 'Plata', 1),

-- Vehículos No Residentes (Visitantes)
('VIS-901', 3, NULL, 'Toyota', 'Corolla', 'Blanco', 1),
('VIS-902', 3, NULL, 'Honda', 'Civic', 'Negro', 1),
('VIS-903', 3, NULL, 'Kia', 'Rio', 'Azul', 1);
COMMIT;

-- 5. HISTORIAL DE ESTANCIAS (Mes anterior: Agosto 2026 - Casos cerrados)

-- Estancia 1: No Residente (Duración 120 min -> 120 * 0.50 = $60.00)
INSERT INTO estancia (id_estancia, placa, id_tarifa, fecha_entrada, fecha_salida, minutos_totales, estado) VALUES
(1001, 'VIS-901', 3, '2026-08-10 10:00:00', '2026-08-10 12:00:00', 120, 'FINALIZADA');

-- Pago inmediato para la estancia 1001 (Regla: No residentes pagan al salir)
INSERT INTO cargo_pago (id_pago, id_estancia, id_cierre, monto, metodo_pago, referencia, fecha_pago) VALUES
(5001, 1001, NULL, 60.00, 'TARJETA_DEBITO', 'AUTH-892104', '2026-08-10 12:01:00');

-- Estancia 2: Oficial (Duración 180 min -> Exento = $0.00)
INSERT INTO estancia (id_estancia, placa, id_tarifa, fecha_entrada, fecha_salida, minutos_totales, estado) VALUES
(1002, 'OFI-001', 1, '2026-08-15 08:30:00', '2026-08-15 11:30:00', 180, 'FINALIZADA');

-- Estancias 3 y 4: Residente Carlos Mendoza (Agosto 2026)
-- Estancia 3: 600 min -> 600 * 0.05 = $30.00
INSERT INTO estancia (id_estancia, placa, id_tarifa, fecha_entrada, fecha_salida, minutos_totales, estado) VALUES
(1003, 'RES-101', 2, '2026-08-01 18:00:00', '2026-08-02 04:00:00', 600, 'FINALIZADA');

-- Estancia 4: 400 min -> 400 * 0.05 = $20.00
INSERT INTO estancia (id_estancia, placa, id_tarifa, fecha_entrada, fecha_salida, minutos_totales, estado) VALUES
(1004, 'RES-101', 2, '2026-08-12 19:00:00', '2026-08-13 01:40:00', 400, 'FINALIZADA');
COMMIT;

-- 6. CIERRE MENSUAL HISTÓRICO (Regla: Conservar historial al iniciar nuevo mes)
-- Cierre de Agosto 2026 para Carlos Mendoza (Total: 1000 min -> $50.00)
INSERT INTO cierre_mensual (id_cierre, id_residente, anio, mes, minutos_acumulados, monto_total, estado, fecha_cierre) VALUES
(1, 1, 2026, 8, 1000, 50.00, 'PAGADO', '2026-08-31 23:59:59');

INSERT INTO detalle_cierre_residente (id_detalle, id_cierre, id_estancia, minutos_facturados, costo_minuto_aplicado, monto_facturado) VALUES
(1, 1, 1003, 600, 0.0500, 30.00),
(2, 1, 1004, 400, 0.0500, 20.00);

-- 5.1 PAGO INMEDIATO PARA ESTANCIA (No Residente)
INSERT INTO cargo_pago (id_pago, tipo_cargo, id_estancia, id_cierre, monto, metodo_pago, referencia, fecha_pago) VALUES
(5001, 'INMEDIATO', 1001, NULL, 60.00, 'TARJETA_DEBITO', 'AUTH-892104', '2026-08-10 12:01:00');

-- 6.1 PAGO DE CIERRE MENSUAL (Residente)
INSERT INTO cargo_pago (id_pago, tipo_cargo, id_estancia, id_cierre, monto, metodo_pago, referencia, fecha_pago) VALUES
(5002, 'MENSUAL', NULL, 1, 50.00, 'TRANSFERENCIA', 'TRANSF-SPEI-33019', '2026-09-02 10:15:00');
COMMIT;

-- 7. ESTANCIAS VIGENTES / ABIERTAS (Mes en curso: Septiembre 2026)
-- Prueba de regla: Vehículos con estancia abierta (fecha_salida IS NULL)
INSERT INTO estancia (id_estancia, placa, id_tarifa, fecha_entrada, fecha_salida, minutos_totales, estado) VALUES
(1005, 'RES-102', 2, '2026-09-10 14:00:00', NULL, 0, 'ABIERTA'),
(1006, 'VIS-902', 3, '2026-09-10 17:30:00', NULL, 0, 'ABIERTA');
COMMIT;

-- 8. REGISTRO INICIAL EN TABLA DE AUDITORÍA
INSERT INTO auditoria_log (tabla_afectada, operacion, id_registro, datos_previos, datos_nuevos, usuario_bd, fecha_evento) VALUES
('tarifa', 'INSERT', '3', NULL, JSON_OBJECT('id_tarifa', 3, 'costo_por_minuto', 0.5000, 'codigo', 'NO_RESIDENTE'), 'root@localhost', CURRENT_TIMESTAMP);
COMMIT;