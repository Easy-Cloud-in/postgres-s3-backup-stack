#!/bin/bash
set -e

# Log files
LOG_FILE="/var/log/postgres/backup-test.log"
CRON_LOG="/var/log/cron.log"

# Logging function
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "Starting backup service..."

# Create backup.env with proper environment variables (without logging contents)
log "Setting up backup environment..."
mkdir -p /home/postgres
cat > /home/postgres/backup.env <<EOF
export POSTGRES_DB="${POSTGRES_DB}"
export POSTGRES_USER="${POSTGRES_USER}"
export POSTGRES_PASSWORD="${POSTGRES_PASSWORD}"
export AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID}"
export AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY}"
export AWS_REGION="${AWS_REGION}"
export S3_BUCKET="${S3_BUCKET}"
export S3_BUCKET_PREFIX="${S3_BUCKET_PREFIX}"
export CLIENT_NAME="${CLIENT_NAME}"
export WALG_S3_PREFIX="${WALG_S3_PREFIX}"
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/lib/postgresql/16/bin"
EOF

chmod 600 /home/postgres/backup.env
chown postgres:postgres /home/postgres/backup.env

# Validate backup configuration
if ! /usr/local/bin/validate-backup-config.sh; then
    log "ERROR: Invalid backup configuration"
    exit 1
fi

# Setup cron job (without showing schedule)
log "Setting up backup schedule..."
echo "SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/lib/postgresql/16/bin
${BACKUP_SCHEDULE} gosu postgres /bin/bash -c '. /home/postgres/backup.env && /usr/local/bin/perform-backup.sh' >> ${LOG_FILE} 2>&1
" > /etc/cron.d/postgres-backup

chmod 0644 /etc/cron.d/postgres-backup

# Verify AWS access (without showing bucket details)
log "Verifying backup storage access..."
if ! gosu postgres aws s3 ls "${WALG_S3_PREFIX}" > /dev/null 2>&1; then
    log "ERROR: Cannot access backup storage"
    exit 1
fi

# Start services
log "Starting backup services..."
cron

# Wait for database
log "Waiting for database connection..."
for i in {1..30}; do
    if gosu postgres pg_isready -h postgres -p 5432 > /dev/null 2>&1; then
        break
    fi
    sleep 2
    if [ $i -eq 30 ]; then
        log "ERROR: Database is not accessible"
        exit 1
    fi
done

# Run initial backup test
log "Running initial backup test..."
if /usr/local/bin/test-backup.sh; then
    log "Initial backup completed successfully"
else
    log "WARNING: Initial backup failed"
    log "Checking system status:"
    
    # Check PostgreSQL status
    log "Database status:"
    if gosu postgres pg_isready -h postgres -p 5432; then
        log "- PostgreSQL is accepting connections"
    else
        log "- PostgreSQL is not responding"
    fi
    
    # Check S3 access
    log "Storage access:"
    if gosu postgres aws s3 ls "s3://${S3_BUCKET}" > /dev/null 2>&1; then
        log "- S3 bucket is accessible"
    else
        log "- Cannot access S3 bucket"
    fi
    
    # Check WAL-G
    log "WAL-G status:"
    if gosu postgres wal-g --version > /dev/null 2>&1; then
        log "- WAL-G is working"
    else
        log "- WAL-G is not working properly"
    fi
fi

# Health check loop with minimal logging
log "Backup service is running"
while true; do
    if ! pgrep cron > /dev/null; then
        log "ERROR: Backup service stopped"
        exit 1
    fi
    sleep 60
done
