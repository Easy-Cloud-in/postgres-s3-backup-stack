#!/bin/bash
set -e

# Log file
LOG_FILE="/var/log/backup.log"

# Logging function
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "Starting backup process..."

# Set explicit PostgreSQL connection parameters
export PGHOST="postgres"
export PGPORT="5432"
export PGUSER="$POSTGRES_USER"
export PGPASSWORD="$POSTGRES_PASSWORD"
export PGDATABASE="$POSTGRES_DB"

# Debug information
log "Debug: Environment variables"
log "POSTGRES_USER: $POSTGRES_USER"
log "POSTGRES_DB: $POSTGRES_DB"
log "PGHOST: $PGHOST"
log "PGPORT: $PGPORT"

# Test basic network connectivity
log "Testing network connectivity..."
if ! ping -c 1 postgres >/dev/null 2>&1; then
    log "ERROR: Cannot ping postgres host"
    # Add network debugging
    log "Network debugging:"
    ip addr show
    netstat -nr
    cat /etc/hosts
    exit 1
fi

# Test connection with verbose output
log "Testing PostgreSQL connection..."
PGPASSWORD="$POSTGRES_PASSWORD" psql -h postgres -p 5432 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "SELECT 1;" || {
    log "ERROR: Direct psql connection failed"
    exit 1
}

# Verify S3 access
log "Verifying S3 access..."
if ! aws s3 ls "${WALG_S3_PREFIX}" > /dev/null 2>&1; then
    log "ERROR: Cannot access S3 bucket"
    exit 1
fi

# Set explicit environment variables for WAL-G
export WALG_POSTGRESQL_DATABASE_URL="postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@postgres:5432/${POSTGRES_DB}?sslmode=disable"

# Perform backup with additional debugging
log "Initiating WAL-G backup..."
if WALG_LOG_LEVEL=DEVEL wal-g backup-push /var/lib/postgresql/data; then
    log "Backup completed successfully"
    log "Available backups:"
    wal-g backup-list
else
    log "ERROR: Backup failed"
    # Show PostgreSQL connection info
    log "Connection debugging:"
    netstat -an | grep 5432
    ss -tunlp | grep 5432
    exit 1
fi
