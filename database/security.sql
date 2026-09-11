-- =============================================================================
-- PROYECTO: Sistema de Gestión de Acceso y Estacionamiento (Neology)
-- ARCHIVO: database/security.sql
-- MOTOR: MariaDB 12.3
-- FECHA: 10-09-2026
-- DESCRIPCIÓN: Esquema de RBAC (Role-Based Access Control), principio de mínimo
--              privilegio, protección de datos sensibles y auditoría administrativa.
-- =============================================================================

USE estacionamiento_db;

-- =============================================================================
-- 1. CREACIÓN DE ROLES (Separación de Responsabilidades)
-- =============================================================================

CREATE ROLE IF NOT EXISTS rol_app_transaccional;
CREATE ROLE IF NOT EXISTS rol_analitica_reportes;
CREATE ROLE IF NOT EXISTS rol_soporte_operativo;
CREATE ROLE IF NOT EXISTS rol_dba_administrador;

-- =============================================================================
-- 2. ASIGNACIÓN DE PRIVILEGIOS POR ROL (Principio de Mínimo Privilegio)
-- =============================================================================

-- 2.1. ROL APLICACIÓN (Casetas, accesos, validación y facturación inmediata)
-- Solo DML estricto sobre datos operativos; no modifica tarifas ni borra auditoría.
GRANT SELECT, INSERT, UPDATE ON estacionamiento_db.estancia TO rol_app_transaccional;
GRANT SELECT, INSERT ON estacionamiento_db.cargo_pago TO rol_app_transaccional;
GRANT SELECT, INSERT, UPDATE ON estacionamiento_db.vehiculo TO rol_app_transaccional;
GRANT SELECT, INSERT, UPDATE ON estacionamiento_db.residente TO rol_app_transaccional;
GRANT SELECT ON estacionamiento_db.tipo_vehiculo TO rol_app_transaccional;
GRANT SELECT ON estacionamiento_db.tarifa TO rol_app_transaccional;
GRANT SELECT ON estacionamiento_db.cierre_mensual TO rol_app_transaccional;
GRANT SELECT ON estacionamiento_db.detalle_cierre_residente TO rol_app_transaccional;
GRANT EXECUTE ON PROCEDURE estacionamiento_db.sp_ejecutar_cierre_mensual TO rol_app_transaccional;

-- 2.2. ROL REPORTES DE SOLO LECTURA (BI, dashboards y reporteo contable)
-- Acceso exclusivo de lectura sin privilegios de modificación ni exposición de DDL.
GRANT SELECT ON estacionamiento_db.tipo_vehiculo TO rol_analitica_reportes;
GRANT SELECT ON estacionamiento_db.tarifa TO rol_analitica_reportes;
GRANT SELECT ON estacionamiento_db.estancia TO rol_analitica_reportes;
GRANT SELECT ON estacionamiento_db.cierre_mensual TO rol_analitica_reportes;
GRANT SELECT ON estacionamiento_db.detalle_cierre_residente TO rol_analitica_reportes;
GRANT SELECT ON estacionamiento_db.cargo_pago TO rol_analitica_reportes;
GRANT SELECT ON estacionamiento_db.vehiculo TO rol_analitica_reportes;

-- 2.3. ROL OPERACIÓN Y SOPORTE (Monitoreo de procesos, corrección controlada)
-- Permite lectura técnica general, visualización de logs de fallos y re-ejecución de cierres.
GRANT SELECT ON estacionamiento_db.* TO rol_soporte_operativo;
GRANT EXECUTE ON PROCEDURE estacionamiento_db.sp_ejecutar_cierre_mensual TO rol_soporte_operativo;
GRANT INSERT ON estacionamiento_db.auditoria_log TO rol_soporte_operativo;

-- 2.4. ROL DBA (Administración total de estructura, índices y gobernanza de la BD)
GRANT ALL PRIVILEGES ON estacionamiento_db.* TO rol_dba_administrador WITH GRANT OPTION;

-- =============================================================================
-- 3. RESTRICCIÓN DE ACCESO A DATOS SENSIBLES (Data Masking vía Vistas)
-- Los analistas de reportes no deben visualizar datos personales de contacto
-- directo (teléfono, correo) de los residentes ni tokens/referencias bancarias.
-- =============================================================================

CREATE OR REPLACE VIEW v_residente_reportes AS
SELECT 
    id_residente,
    apellido_p,
    apellido_m,
    nombre,
    numero_departamento,
    -- Enmascaramiento de datos de contacto
    CONCAT(LEFT(telefono, 2), '******', RIGHT(telefono, 2)) AS telefono_enmascarado,
    CONCAT(LEFT(correo, 3), '***@***', RIGHT(correo, 4)) AS correo_enmascarado,
    activo,
    fecha_alta
FROM residente;

CREATE OR REPLACE VIEW v_cargo_pago_reportes AS
SELECT 
    id_pago,
    tipo_cargo,
    id_estancia,
    id_cierre,
    monto,
    metodo_pago,
    -- Enmascaramiento de autorización/tarjeta en referencia
    CASE 
        WHEN referencia IS NOT NULL THEN CONCAT('REF-***-', RIGHT(referencia, 4))
        ELSE 'SIN_REFERENCIA'
    END AS referencia_anonimizada,
    fecha_pago
FROM cargo_pago;

-- Reemplazar permisos directos de tablas sensibles para el rol de reportes por vistas protegidas
REVOKE SELECT ON estacionamiento_db.residente FROM rol_analitica_reportes;
REVOKE SELECT ON estacionamiento_db.cargo_pago FROM rol_analitica_reportes;
GRANT SELECT ON estacionamiento_db.v_residente_reportes TO rol_analitica_reportes;
GRANT SELECT ON estacionamiento_db.v_cargo_pago_reportes TO rol_analitica_reportes;

-- =============================================================================
-- 4. MANEJO SEGURO DE CREDENCIALES Y CREACIÓN DE USUARIOS
-- Políticas de complejidad, expiración de contraseñas, TLS/SSL obligatorio y límites de recursos.
-- =============================================================================

-- 4.1. Usuario de Servicio de la Aplicación (Restringido a la subnet de servidores app)
CREATE USER IF NOT EXISTS 'usr_parking_backend'@'10.0.1.%'
    IDENTIFIED BY 'App_Str0ng.Secur3#2026'
    REQUIRE SSL
    WITH MAX_QUERIES_PER_HOUR 0
         MAX_CONNECTIONS_PER_HOUR 0
         MAX_USER_CONNECTIONS 50;

-- 4.2. Usuario de BI / Reportería (Contraseña expirable a 90 días)
CREATE USER IF NOT EXISTS 'usr_bi_reporter'@'%'
    IDENTIFIED BY 'Rep0rt.P@ssw0rd$2026'
    REQUIRE SSL
    PASSWORD EXPIRE INTERVAL 90 DAY
    WITH MAX_USER_CONNECTIONS 10;

-- 4.3. Usuario de Soporte / Mesa de Ayuda
CREATE USER IF NOT EXISTS 'usr_support_ops'@'10.0.2.%'
    IDENTIFIED BY 'S0pp0rt_Oper.2026!'
    REQUIRE SSL
    PASSWORD EXPIRE INTERVAL 60 DAY
    WITH MAX_USER_CONNECTIONS 5;

-- 4.4. Usuario DBA Primario (Solo acceso desde estación de gestión o red de admin)
CREATE USER IF NOT EXISTS 'usr_dba_admin'@'10.0.0.%'
    IDENTIFIED BY 'DBA_Adm1n.M@st3r#2026'
    REQUIRE SSL
    PASSWORD EXPIRE INTERVAL 30 DAY
    FAILED_LOGIN_ATTEMPTS 3 PASSWORD_LOCK_TIME 1;

-- =============================================================================
-- 5. ASIGNACIÓN Y ACTIVACIÓN AUTOMÁTICA DE ROLES
-- =============================================================================

GRANT rol_app_transaccional TO 'usr_parking_backend'@'10.0.1.%';
GRANT rol_analitica_reportes TO 'usr_bi_reporter'@'%';
GRANT rol_soporte_operativo TO 'usr_support_ops'@'10.0.2.%';
GRANT rol_dba_administrador TO 'usr_dba_admin'@'10.0.0.%';

-- Activación automática de roles al iniciar sesión
SET DEFAULT ROLE rol_app_transaccional FOR 'usr_parking_backend'@'10.0.1.%';
SET DEFAULT ROLE rol_analitica_reportes FOR 'usr_bi_reporter'@'%';
SET DEFAULT ROLE rol_soporte_operativo FOR 'usr_support_ops'@'10.0.2.%';
SET DEFAULT ROLE rol_dba_administrador FOR 'usr_dba_admin'@'10.0.0.%';

-- =============================================================================
-- 6. AUDITORÍA DE OPERACIONES ADMINISTRATIVAS
-- El plugin de auditoría de MariaDB registra conexiones y comandos DDL/DCL.
-- =============================================================================

-- Instalación del plugin de auditoría nativo (MariaDB Audit Plugin)
INSTALL SONAME 'server_audit';

-- Configuración de directrices de auditoría administrativa:
-- server_audit_events: Captura conexiones, desconexiones y consultas DDL/DCL
-- server_audit_excl_users: Excluye el usuario transaccional frecuente para no saturar el log
SET GLOBAL server_audit_logging = ON;
SET GLOBAL server_audit_events = 'CONNECT,QUERY_DDL,QUERY_DCL';
SET GLOBAL server_audit_file_rotations = 9;
SET GLOBAL server_audit_file_rotate_size = 104857600; -- 100 MB
SET GLOBAL server_audit_excl_users = 'usr_parking_backend';

-- =============================================================================
-- 7. REVOCACIÓN DE PERMISOS Y DESPROVISIÓN (Protocolo de Offboarding)
-- =============================================================================

/*
  PROTOCOLO ANTE BAJA O INCIDENTE DE SEGURIDAD:
  1. Revocación total de roles asignados.
  2. Bloqueo inmediato de la cuenta de usuario (ACCOUNT LOCK).
  3. Desconexión de sesiones activas en el motor.
  4. Eliminación definitiva de credenciales tras la ventana forense.

  EJEMPLO DE APLICACIÓN:
  REVOKE rol_soporte_operativo FROM 'usr_support_ops'@'10.0.2.%';
  ALTER USER 'usr_support_ops'@'10.0.2.%' ACCOUNT LOCK;
  
  -- Terminar procesos activos del usuario:
  -- SELECT CONCAT('KILL ', id, ';') FROM information_schema.processlist WHERE user = 'usr_support_ops';
  
  -- Baja definitiva:
  -- DROP USER 'usr_support_ops'@'10.0.2.%';
*/

FLUSH PRIVILEGES;