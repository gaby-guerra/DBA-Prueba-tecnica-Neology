-- =============================================================================
-- PROYECTO: Sistema de Control de Acceso y Estacionamiento (Neology)
-- ARCHIVO: database/schema.sql
-- MOTOR: MariaDB 12.3
-- FECHA: 10-09-2026
-- DESCRIPCIÓN: Estructura de la base de datos
-- =============================================================================

-- 1. Creación de la base de datos
CREATE DATABASE IF NOT EXISTS estacionamiento_db
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_unicode_ci;

-- 2. Creación de tablas e indices.
USE estacionamiento_db;

-- =============================================================================
-- GESTIÓN DE AMBIENTES Y CONTROL DE CAMBIOS (NOTA DE ARQUITECTURA)
-- =============================================================================
/*
  NOTA DE DESPLIEGUE:
  El bloque DROP TABLE junto con SET FOREIGN_KEY_CHECKS = 0 se mantiene
  COMENTADO intencionalmente por directriz de seguridad operativa.

  1. AMBIENTE PRODUCTIVO:
     - En despliegues a Producción, NUNCA deben ejecutarse sentencias DROP destructivas.
     - La evolución del esquema debe gestionarse de forma no destructiva mediante:
       * Scripts incrementales de migración (ALTER TABLE / DDL versionado tipo Flyway/Liquibase).
       * Respaldos lógicos previos (mysqldump / mariadb-dump).
       * Ventanas de mantenimiento planificadas para validar dependencias y evitar locks prolongados.

  2. AMBIENTES DE DESARROLLO O QA:
     - El reinicio total de tablas solo es admisible para recreación desde cero (scratch build)
       en contenedores de pruebas unitarias o ambientes locales aislados.
*/

-- Descomentar ÚNICAMENTE para inicialización desde cero en ambientes locales/desarrollo:
-- SET FOREIGN_KEY_CHECKS = 0;
-- DROP TABLE IF EXISTS auditoria_log;
-- DROP TABLE IF EXISTS cargo_pago;
-- DROP TABLE IF EXISTS detalle_cierre_residente;
-- DROP TABLE IF EXISTS cierre_mensual;
-- DROP TABLE IF EXISTS estancia;
-- DROP TABLE IF EXISTS tarifa;
-- DROP TABLE IF EXISTS vehiculo;
-- DROP TABLE IF EXISTS residente;
-- DROP TABLE IF EXISTS tipo_vehiculo;
-- SET FOREIGN_KEY_CHECKS = 1;

-- =============================================================================
-- TABLA 1: tipo_vehiculo
-- Catálogo extensible para clasificación de unidades y política de cobro.
-- =============================================================================
CREATE TABLE tipo_vehiculo (
    id_tipo_vehiculo INT AUTO_INCREMENT PRIMARY KEY,
    codigo VARCHAR(20) NOT NULL,
    descripcion VARCHAR(100) NOT NULL,
    requiere_pago TINYINT(1) NOT NULL DEFAULT 1 COMMENT '0: Oficial/Exento, 1: Aplica cobro',
    activo TINYINT(1) NOT NULL DEFAULT 1,
    fecha_creacion DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_tipo_vehiculo_codigo UNIQUE (codigo)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- =============================================================================
-- TABLA 2: residente
-- Datos maestros de los residentes del complejo habitacional / corporativo.
-- =============================================================================
CREATE TABLE residente (
    id_residente INT AUTO_INCREMENT PRIMARY KEY,
	apellido_p VARCHAR(120) NOT NULL,
	apellido_m VARCHAR(120),
    nombre VARCHAR(120) NOT NULL,
    numero_departamento VARCHAR(30) NOT NULL,
    telefono VARCHAR(20) NULL,
    correo VARCHAR(100) NULL,
    activo TINYINT(1) NOT NULL DEFAULT 1,
    fecha_alta DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- =============================================================================
-- TABLA 3: vehiculo
-- Unidades vehiculares registradas o visitantes recurrentes.
-- =============================================================================
CREATE TABLE vehiculo (
    placa VARCHAR(15) NOT NULL PRIMARY KEY,
    id_tipo_vehiculo INT NOT NULL,
    id_residente INT NULL COMMENT 'Vinculación solo si tipo_vehiculo es RESIDENTE',
    marca VARCHAR(50) NULL,
    modelo VARCHAR(50) NULL,
    color VARCHAR(30) NULL,
    activo TINYINT(1) NOT NULL DEFAULT 1,
    fecha_registro DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_vehiculo_tipo 
        FOREIGN KEY (id_tipo_vehiculo) REFERENCES tipo_vehiculo (id_tipo_vehiculo) 
        ON UPDATE CASCADE,
    CONSTRAINT fk_vehiculo_residente 
        FOREIGN KEY (id_residente) REFERENCES residente (id_residente) 
        ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- =============================================================================
-- TABLA 4: tarifa
-- Versionamiento de precios por minuto según el tipo de vehículo.
-- =============================================================================
CREATE TABLE tarifa (
    id_tarifa INT AUTO_INCREMENT PRIMARY KEY,
    id_tipo_vehiculo INT NOT NULL,
    costo_por_minuto DECIMAL(6, 4) NOT NULL COMMENT 'Tarifa por minuto (ej. 0.0500, 0.5000)',
    fecha_inicio DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    fecha_fin DATETIME NULL COMMENT 'NULL representa la tarifa actualmente vigente',
    activo TINYINT(1) NOT NULL DEFAULT 1,
    CONSTRAINT fk_tarifa_tipo 
        FOREIGN KEY (id_tipo_vehiculo) REFERENCES tipo_vehiculo (id_tipo_vehiculo) 
        ON UPDATE CASCADE,
    CONSTRAINT chk_tarifa_costo CHECK (costo_por_minuto >= 0.0000)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- =============================================================================
-- TABLA 5: estancia
-- Control transaccional de accesos y permanencia.
-- Implementa restricción de negocio: "Un vehículo no puede tener más de una estancia abierta".
-- =============================================================================
CREATE TABLE estancia (
    id_estancia BIGINT AUTO_INCREMENT PRIMARY KEY,
    placa VARCHAR(15) NOT NULL,
    id_tarifa INT NOT NULL,
    fecha_entrada DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    fecha_salida DATETIME NULL,
    minutos_totales INT NULL DEFAULT 0,
    estado ENUM('ABIERTA', 'FINALIZADA', 'CANCELADA') NOT NULL DEFAULT 'ABIERTA',
    
    -- Columna virtual única para asegurar máximo 1 estancia abierta por vehículo:
    -- Si fecha_salida IS NULL devuelve 'PLACA-ACTIVA'; si ya cerró devuelve NULL.
    estancia_activa_uk VARCHAR(40) GENERATED ALWAYS AS (
        IF(fecha_salida IS NULL, CONCAT(placa, '-ACTIVA'), NULL)
    ) VIRTUAL,
    
    CONSTRAINT fk_estancia_vehiculo 
        FOREIGN KEY (placa) REFERENCES vehiculo (placa) 
        ON UPDATE CASCADE,
    CONSTRAINT fk_estancia_tarifa 
        FOREIGN KEY (id_tarifa) REFERENCES tarifa (id_tarifa) 
        ON UPDATE CASCADE,
    CONSTRAINT chk_estancia_fechas CHECK (fecha_salida IS NULL OR fecha_salida >= fecha_entrada),
    CONSTRAINT chk_estancia_minutos CHECK (minutos_totales >= 0),
    CONSTRAINT uq_estancia_vehiculo_activa UNIQUE (estancia_activa_uk)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- =============================================================================
-- TABLA 6: cierre_mensual
-- Resumen de acumulación de tiempo y cargos de residentes al corte mensual.
-- =============================================================================
CREATE TABLE cierre_mensual (
    id_cierre INT AUTO_INCREMENT PRIMARY KEY,
    id_residente INT NOT NULL,
    anio SMALLINT NOT NULL,
    mes TINYINT NOT NULL,
    minutos_acumulados INT NOT NULL DEFAULT 0,
    monto_total DECIMAL(10, 2) NOT NULL DEFAULT 0.00,
    estado ENUM('PENDIENTE', 'PAGADO', 'CANCELADO') NOT NULL DEFAULT 'PENDIENTE',
    fecha_cierre DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_cierre_residente 
        FOREIGN KEY (id_residente) REFERENCES residente (id_residente) 
        ON UPDATE CASCADE,
    CONSTRAINT uq_cierre_periodo UNIQUE (id_residente, anio, mes),
    CONSTRAINT chk_cierre_mes CHECK (mes BETWEEN 1 AND 12)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- =============================================================================
-- TABLA 7: detalle_cierre_residente
-- Trazabilidad de qué estancias individuales integraron cada corte mensual.
-- =============================================================================
CREATE TABLE detalle_cierre_residente (
    id_detalle BIGINT AUTO_INCREMENT PRIMARY KEY,
    id_cierre INT NOT NULL,
    id_estancia BIGINT NOT NULL,
    minutos_facturados INT NOT NULL,
    costo_minuto_aplicado DECIMAL(6, 4) NOT NULL,
    monto_facturado DECIMAL(10, 2) NOT NULL,
    CONSTRAINT fk_detalle_cierre 
        FOREIGN KEY (id_cierre) REFERENCES cierre_mensual (id_cierre) 
        ON DELETE CASCADE,
    CONSTRAINT fk_detalle_estancia 
        FOREIGN KEY (id_estancia) REFERENCES estancia (id_estancia) 
        ON UPDATE CASCADE,
    CONSTRAINT uq_detalle_estancia UNIQUE (id_estancia)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- =============================================================================
-- TABLA 8: cargo_pago
-- Transacciones de pago (inmediatas para no residentes o consolidadas para cortes).
-- =============================================================================
CREATE TABLE cargo_pago (
    id_pago BIGINT AUTO_INCREMENT PRIMARY KEY,
    tipo_cargo ENUM('INMEDIATO', 'MENSUAL') NOT NULL COMMENT 'INMEDIATO = No residentes, MENSUAL = Corte residentes',
    id_estancia BIGINT NULL COMMENT 'Relacionado a cobro inmediato (No residentes)',
    id_cierre INT NULL COMMENT 'Relacionado a liquidación de mes (Residentes)',
    monto DECIMAL(10, 2) NOT NULL,
    metodo_pago ENUM('EFECTIVO', 'TARJETA_CREDITO', 'TARJETA_DEBITO', 'TRANSFERENCIA') NOT NULL,
    referencia VARCHAR(100) NULL,
    fecha_pago DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_pago_estancia 
        FOREIGN KEY (id_estancia) REFERENCES estancia (id_estancia) 
        ON UPDATE CASCADE,
    CONSTRAINT fk_pago_cierre 
        FOREIGN KEY (id_cierre) REFERENCES cierre_mensual (id_cierre) 
        ON UPDATE CASCADE,
    CONSTRAINT chk_pago_monto CHECK (monto >= 0.00)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- =============================================================================
-- TABLA 9: auditoria_log
-- Bitácora de eventos relevantes para trazabilidad y cambios en el sistema.
-- =============================================================================
CREATE TABLE auditoria_log (
    id_auditoria BIGINT AUTO_INCREMENT PRIMARY KEY,
    tabla_afectada VARCHAR(60) NOT NULL,
    operacion ENUM('INSERT', 'UPDATE', 'DELETE') NOT NULL,
    id_registro VARCHAR(64) NOT NULL,
    datos_previos LONGTEXT CHARACTER SET utf8mb4 COLLATE utf8mb4_bin NULL CHECK (json_valid(datos_previos)),
    datos_nuevos LONGTEXT CHARACTER SET utf8mb4 COLLATE utf8mb4_bin NULL CHECK (json_valid(datos_nuevos)),
    usuario_bd VARCHAR(100) NOT NULL DEFAULT (CURRENT_USER()),
    fecha_evento DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- =============================================================================
-- ÍNDICES
-- =============================================================================
CREATE INDEX idx_estancia_placa_fecha ON estancia (placa, fecha_entrada);
CREATE INDEX idx_estancia_estado ON estancia (estado);
CREATE INDEX idx_tarifa_vigencia ON tarifa (id_tipo_vehiculo, fecha_inicio, fecha_fin);
CREATE INDEX idx_cierre_periodo ON cierre_mensual (anio, mes);
CREATE INDEX idx_auditoria_tabla_fecha ON auditoria_log (tabla_afectada, fecha_evento);