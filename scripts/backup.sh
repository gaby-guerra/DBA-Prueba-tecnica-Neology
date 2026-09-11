#!/usr/bin/env bash
# =============================================================================
# PROYECTO: Sistema de Control de Acceso y Estacionamiento (Neology)
# ARCHIVO: scripts/backup.sh
# DESCRIPCIÓN: Estrategia de respaldo 
# =============================================================================

set -euo pipefail

DB_NAME="estacionamiento_db"
DB_USER="usr_backup"
DB_PASS="${DB_BACKUP_PWD:-'B@ckup_S3cure.2026'}"
DB_HOST="127.0.0.1"
DB_PORT="3306"

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_DIR="/var/backups/mariadb"
DEST_FILE="${BACKUP_DIR}/${DB_NAME}_full_${TIMESTAMP}.sql.gz.enc"
ENC_PASSPHRASE="${BACKUP_ENC_KEY:-'Ne0l0gy_EncKey_AES256_DBA'}"
LOG_FILE="/var/log/mariadb/backup_execution.log"

mkdir -p "${BACKUP_DIR}"
mkdir -p "$(dirname "${LOG_FILE}")"

echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] Iniciando respaldo de '${DB_NAME}'..." | tee -a "${LOG_FILE}"

mariadb-dump \
    --host="${DB_HOST}" \
    --port="${DB_PORT}" \
    --user="${DB_USER}" \
    --password="${DB_PASS}" \
    --single-transaction \
    --quick \
    --master-data=2 \
    --flush-logs \
    --routines \
    --triggers \
    --events \
    --databases "${DB_NAME}" \
    | gzip -9 \
    | openssl enc -aes-256-cbc -salt -pbkdf2 -pass "pass:${ENC_PASSPHRASE}" -out "${DEST_FILE}"

# Validación de salida
if [ -f "${DEST_FILE}" ] && [ -s "${DEST_FILE}" ]; then
    FILE_SIZE=$(du -h "${DEST_FILE}" | cut -f1)
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [EXITO] Respaldo generado y cifrado exitosamente: ${DEST_FILE} (${FILE_SIZE})" | tee -a "${LOG_FILE}"
else
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] El archivo de respaldo no se creó o está vacío." | tee -a "${LOG_FILE}"
    exit 1
fi

# Política de Retención Local (Depuración de archivos con más de 14 días)
find "${BACKUP_DIR}" -name "${DB_NAME}_full_*.sql.gz.enc" -type f -mtime +14 -exec rm -f {} +
echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] Política de retención aplicada. Archivos antiguos purgados." | tee -a "${LOG_FILE}"