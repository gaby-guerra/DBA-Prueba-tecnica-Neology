# Estrategia de Respaldo, Restauración y Recuperación ante Desastres (DRP)

Este documento define la arquitectura de continuidad de negocio, esquema de respaldos (completos, binlogs y PITR), métricas de recuperación (**RPO/RTO**) y correlación técnica entre **MariaDB** y **Oracle Database**.

---

## 1. Definición de Objetivos de Recuperación (RPO y RTO)

Para el sistema transaccional de control de acceso y estacionamiento (Neology), se establecen las siguientes métricas de criticidad del servicio:

* **RPO (Recovery Point Objective): $\le$ 5 minutos.**
  * *Tolerancia de pérdida de datos:* No más de 5 minutos de transacciones de acceso o cobro. Se logra mediante el volcado recurrente de *Binary Logs* y la replicación semi-síncrona en tiempo real hacia una réplica secundaria.
* **RTO (Recovery Time Objective): $\le$ 30 minutos.**
  * *Tiempo máximo admisible de recuperación:* 30 minutos para tener el sistema operativo ante una pérdida total del nodo maestro, soportado por conmutación automática de tráfico (failover) hacia el nodo secundario.

---

## 2. Arquitectura de Respaldos en MariaDB

### 2.1. Respaldo Completo (Full Backup)
* **Frecuencia:** Diario (01:00 AM, ventana de menor concurrencia vehicular).
* **Mecanismo:** `mariadb-dump` / `mariadb-backup` con `--single-transaction`. 
* **Características:** Garantiza consistencia transaccional sin aplicar locks de lectura que interrumpan la operación de casetas en tablas InnoDB.

### 2.2. Respaldos Continuos e Incrementales (Binary Logs)
* En motores MySQL/MariaDB, la estrategia incremental más robusta para alta transaccionalidad reside en los **Binary Logs** (`binlogs`).
* **Configuración obligatoria en `my.cnf`:**
  ```ini
  [mariadb]
  log_bin = /var/log/mysql/mariadb-bin
  binlog_format = ROW
  sync_binlog = 1
  expire_logs_days = 7