#!/usr/bin/env bash
# =============================================================================
# PROYECTO: Sistema de Control de Acceso y Estacionamiento (Neology)
# ARCHIVO: scripts/restore.sh
# DESCRIPCIÓN: Restauración de base de datos desde dump
# =============================================================================

set -euo pipefail

DB_NAME="estacionamiento_db"
DB_USER="root"
DB_PASS="${DB_ROOT_PWD:-'Root_Adm1n.2026'}"
DB_HOST="127.0.0.1"
DB_PORT="3306"

BACKUP_FILE="${1:-}"
STOP_DATETIME="${2:-}" 
ENC_PASSPHRASE="${BACKUP_ENC_KEY:-'Ne0l0gy_EncKey_AES256_DBA'}"
BINLOG_DIR="/var/log/mysql"

if [ -z "${BACKUP_FILE}" ]; then
    echo "Uso: $0 <ruta_al_archivo_backup.sql.gz.enc> [punto_en_el_tiempo_PITR: 'YYYY-MM-DD HH:MM:SS']"
    exit 1
fi

if [ ! -f "${BACKUP_FILE}" ]; then
    echo "Error: El archivo de respaldo especificado no existe: ${BACKUP_FILE}"
    exit 1
fi

echo "================================================================="
echo "Iniciando proceso de restauración para: ${DB_NAME}"
echo "Archivo origen: ${BACKUP_FILE}"
echo "================================================================="

# 1. Desencriptar, descomprimir y restaurar el snapshot base
echo "[1/3] Desencriptando y cargando snapshot base..."
openssl enc -d -aes-256-cbc -pbkdf2 -pass "pass:${ENC_PASSPHRASE}" -in "${BACKUP_FILE}" \
    | gunzip \
    | mariadb --host="${DB_HOST}" --port="${DB_PORT}" --user="${DB_USER}" --password="${DB_PASS}"

echo "[2/3] Snapshot base restaurado exitosamente."

# 2. Recuperación a un Punto en el Tiempo (PITR) mediante Binary Logs (si fue requerido)
if [ -n "${STOP_DATETIME}" ]; then
    echo "[3/3] Aplicando Binary Logs hasta: ${STOP_DATETIME} (PITR)..."
    
    # Se concatenan los binlogs y se procesan hasta la fecha/hora indicada
    mariadb-binlog \
        --database="${DB_NAME}" \
        --stop-datetime="${STOP_DATETIME}" \
        ${BINLOG_DIR}/mariadb-bin.000* \
        | mariadb --host="${DB_HOST}" --port="${DB_PORT}" --user="${DB_USER}" --password="${DB_PASS}"
    
    echo "PITR completado con éxito hasta el timestamp: ${STOP_DATETIME}."
else
    echo "[3/3] No se especificó timestamp PITR. Restauración terminada con el estado del snapshot."
fi

echo "================================================================="
echo "Proceso de restauración y recuperación concluido con éxito."
echo "================================================================="