#!/usr/bin/env bash
# =============================================================================
# PROYECTO: Sistema de Control de Acceso y Estacionamiento (Neology)
# ARCHIVO: scripts/backup.sh
# DESCRIPCIÓN: Estrategia de respaldo 
# =============================================================================

set -euo pipefail

# 1. Configuración de rutas relativas portables
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"
BACKUP_DIR="${PROJECT_ROOT}/backups"
LOG_DIR="${PROJECT_ROOT}/logs"
LOG_FILE="${LOG_DIR}/backup_execution.log"

# 2. Parámetros de base de datos
DB_NAME="estacionamiento_db"
DB_USER="root"
DB_PASS="${DB_BACKUP_PWD:-}"
DB_HOST="127.0.0.1"
DB_PORT="3306"

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
DEST_FILE="${BACKUP_DIR}/${DB_NAME}_full_${TIMESTAMP}.sql.gz.enc"
ENC_PASSPHRASE="${BACKUP_ENC_KEY:-Ne0l0gy_EncKey_AES256_DBA}"

# 3. Crear directorios locales si no existen
mkdir -p "${BACKUP_DIR}"
mkdir -p "${LOG_DIR}"

echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] Iniciando respaldo de '${DB_NAME}'..." | tee -a "${LOG_FILE}"

# 4. Generación de dump consistente, compresión y cifrado AES-256
mariadb-dump \
    --host="${DB_HOST}" \
    --port="${DB_PORT}" \
    --user="${DB_USER}" \
    ${DB_PASS:+-p"${DB_PASS}"} \
    --single-transaction \
    --quick \
    --flush-logs \
    --routines \
    --triggers \
    --events \
    --databases "${DB_NAME}" \
    | gzip -9 \
    | openssl enc -aes-256-cbc -salt -pbkdf2 -pass "pass:${ENC_PASSPHRASE}" -out "${DEST_FILE}"

# 5. Validación de archivo generado
if [ -f "${DEST_FILE}" ] && [ -s "${DEST_FILE}" ]; then
    FILE_SIZE=$(du -h "${DEST_FILE}" | cut -f1)
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [EXITO] Respaldo generado y cifrado exitosamente: ${DEST_FILE} (${FILE_SIZE})" | tee -a "${LOG_FILE}"
else
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] El archivo de respaldo no se generó correctamente." | tee -a "${LOG_FILE}"
    exit 1
fi

# 6. Retención local: purga de archivos mayores a 14 días
find "${BACKUP_DIR}" -name "${DB_NAME}_full_*.sql.gz.enc" -type f -mtime +14 -exec rm -f {} +
echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] Política de retención aplicada." | tee -a "${LOG_FILE}"