#!/bin/sh

set -eo pipefail

# ==================================================================
# LIMPIEZA AGRESIVA AL INICIO
# ==================================================================

# Limpiar TODO en /tmp
rm -rf /tmp/* 2>/dev/null || true
rm -rf /tmp/.* 2>/dev/null || true

# Limpiar cache de APK
rm -rf /var/cache/apk/* 2>/dev/null || true

# Limpiar logs viejos
find /var/log -type f -name "*.log" -delete 2>/dev/null || true

# Limpiar cache de pip/python
rm -rf /root/.cache/* 2>/dev/null || true
rm -rf /home/*/.cache/* 2>/dev/null || true

# Mostrar espacio ANTES
echo "Disk usage BEFORE cleanup:"
df -h / | tail -n 1

# Forzar sync para liberar buffers
sync

echo "Disk usage AFTER cleanup:"
df -h / | tail -n 1
echo ""

# ==================================================================
# VALIDACIONES
# ==================================================================
if [ "${S3_ACCESS_KEY_ID}" == "**None**" ]; then
  echo "Warning: You did not set the S3_ACCESS_KEY_ID environment variable."
fi

if [ "${S3_SECRET_ACCESS_KEY}" == "**None**" ]; then
  echo "Warning: You did not set the S3_SECRET_ACCESS_KEY environment variable."
fi

if [ "${S3_BUCKET}" == "**None**" ]; then
  echo "You need to set the S3_BUCKET environment variable."
  exit 1
fi

if [ "${MONGO_HOST}" == "**None**" ]; then
  echo "You need to set the MONGO_HOST environment variable."
  exit 1
fi

if [ "${MONGO_USER}" == "**None**" ]; then
  echo "Warning: You did not set the MONGO_USER environment variable."
fi

if [ "${MONGO_PASSWORD}" == "**None**" ]; then
  echo "Warning: You did not set the MONGO_PASSWORD environment variable."
fi

if [ "${S3_IAMROLE}" != "true" ]; then
  export AWS_ACCESS_KEY_ID=$S3_ACCESS_KEY_ID
  export AWS_SECRET_ACCESS_KEY=$S3_SECRET_ACCESS_KEY
  export AWS_DEFAULT_REGION=$S3_REGION
fi

# ==================================================================
# CONFIGURACIÓN DE MONGODB
# ==================================================================
MONGO_CONN_OPTS="--host=${MONGO_HOST} --port=${MONGO_PORT}"

if [ "${MONGO_USER}" != "**None**" ] && [ "${MONGO_PASSWORD}" != "**None**" ]; then
  MONGO_CONN_OPTS="${MONGO_CONN_OPTS} --username=${MONGO_USER} --password=${MONGO_PASSWORD}"
fi

if [ "${MONGO_AUTH_DB}" != "**None**" ]; then
  MONGO_CONN_OPTS="${MONGO_CONN_OPTS} --authenticationDatabase=${MONGO_AUTH_DB}"
fi

DUMP_START_TIME=$(date +"%Y-%m-%dT%H%M%SZ")

# ==================================================================
# CONFIGURACIÓN DE S3
# ==================================================================
if [ "${S3_ENDPOINT}" == "**None**" ]; then
  AWS_ARGS=""
else
  AWS_ARGS="--endpoint-url ${S3_ENDPOINT}"
fi

# Verificar bucket una sola vez
if [ "${S3_ENSURE_BUCKET_EXISTS}" != "no" ]; then
  echo " Checking S3 bucket $S3_BUCKET..."
  EXISTS_ERR=`aws $AWS_ARGS s3api head-bucket --bucket "$S3_BUCKET" 2>&1 || true`
  if [[ ! -z "$EXISTS_ERR" ]]; then
    echo "Creating bucket $S3_BUCKET..."
    aws $AWS_ARGS s3api create-bucket --bucket $S3_BUCKET
  fi
fi

# mongodump extra options
MONGODUMP_OPTIONS=""
if [ ! -z "${MONGODUMP_EXTRA_OPTIONS}" ]; then
  MONGODUMP_OPTIONS="${MONGODUMP_EXTRA_OPTIONS}"
fi

# ==================================================================
# BACKUP - MODO MULTI FILES
# ==================================================================
if [ ! -z "$(echo $MULTI_FILES | grep -i -E "(yes|true|1)")" ]; then
  if [ "${MONGO_DATABASE}" == "--all-databases" ] || [ "${MONGO_DATABASE}" == "**None**" ]; then
    echo "Warning: MULTI_FILES with --all-databases requires manual database specification"
    echo "Please set MONGO_DATABASE to space-separated list: MONGO_DATABASE='db1 db2 db3'"
    echo "Falling back to single archive..."
    DATABASES=""
  else
    DATABASES=$MONGO_DATABASE
  fi

  if [ ! -z "$DATABASES" ]; then
    for DB in $DATABASES; do
      DB=$(echo $DB | xargs)
      
      echo ""
      echo "=================================================="
      echo "Backing up database: ${DB}"
      echo "=================================================="
      echo "Disk before backup:"
      df -h / | tail -n 1

      if [ "${S3_FILENAME}" == "**None**" ]; then
        S3_FILE="${DUMP_START_TIME}.${DB}.archive.gz"
      else
        S3_FILE="${S3_FILENAME}.${DB}.archive.gz"
      fi

      S3_PATH="s3://$S3_BUCKET/$S3_PREFIX/$S3_FILE"
      echo " Target: $S3_PATH"
      echo " Starting STREAMING backup (no disk usage)..."

      # STREAMING DIRECTO - NO USA DISCO
      mongodump $MONGO_CONN_OPTS --db=$DB --archive --gzip $MONGODUMP_OPTIONS | \
        aws $AWS_ARGS s3 cp - "$S3_PATH"
      
      if [ $? == 0 ]; then
        echo "Backup of ${DB} completed and uploaded!"
        
        # Limpiar inmediatamente después de cada DB
        rm -rf /tmp/* 2>/dev/null || true
        sync
        
        echo "Disk after backup:"
        df -h / | tail -n 1
      else
        >&2 echo "Error backing up ${DB}"
      fi
    done
    
    # Limpieza final agresiva
    echo ""
    rm -rf /tmp/*
    rm -rf /var/cache/*
    sync
    
    echo "All backups completed!"
    df -h / | tail -n 1
    exit 0
  fi
fi

# ==================================================================
# BACKUP - MODO SINGLE FILE
# ==================================================================
echo ""
echo "=================================================="
echo "Backing up: ${MONGO_DATABASE}"
echo "=================================================="
echo "Disk before backup:"
df -h / | tail -n 1

if [ "${S3_FILENAME}" == "**None**" ]; then
  S3_FILE="${DUMP_START_TIME}.dump.archive.gz"
else
  S3_FILE="${S3_FILENAME}.archive.gz"
fi

S3_PATH="s3://$S3_BUCKET/$S3_PREFIX/$S3_FILE"
echo "Target: $S3_PATH"
echo "Starting STREAMING backup (no disk usage)..."

# STREAMING DIRECTO - NO USA DISCO
if [ "${MONGO_DATABASE}" == "--all-databases" ] || [ "${MONGO_DATABASE}" == "**None**" ]; then
  mongodump $MONGO_CONN_OPTS --archive --gzip $MONGODUMP_OPTIONS | \
    aws $AWS_ARGS s3 cp - "$S3_PATH"
else
  mongodump $MONGO_CONN_OPTS --db=$MONGO_DATABASE --archive --gzip $MONGODUMP_OPTIONS | \
    aws $AWS_ARGS s3 cp - "$S3_PATH"
fi

if [ $? == 0 ]; then
  echo "Backup completed and uploaded!"

  # Limpieza inmediata
  rm -rf /tmp/* 2>/dev/null || true
  sync
  
  echo "Disk after backup:"
  df -h / | tail -n 1
else
  >&2 echo "Error creating backup"
fi

# ==================================================================
# LIMPIEZA FINAL AGRESIVA
# ==================================================================
echo ""
rm -rf /tmp/*
rm -rf /var/cache/*
rm -rf /root/.cache/*
sync

echo ""
echo "MongoDB backup finished!"
df -h / | tail -n 1