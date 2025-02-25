#!/bin/bash
set -e

LOG_FILE="/var/log/postgres/backup-test.log"

# Setup logging
log() {
    echo "[$(date)] $1" | tee -a "$LOG_FILE"
}

# Export required environment variables
export PGHOST="postgres"
export PGPORT="5432"
export PGUSER="${POSTGRES_USER}"
export PGPASSWORD="${POSTGRES_PASSWORD}"
export PGDATABASE="${POSTGRES_DB}"
export WALG_LOG_LEVEL=DEVEL
export AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID}"
export AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY}"
export AWS_REGION="${AWS_REGION}"
export WALG_S3_PREFIX="${WALG_S3_PREFIX}"

# Function to run commands as postgres user
run_as_postgres() {
    gosu postgres "$@"
}

# Function to check S3 path for WAL files
check_wal_path() {
    local base_path="${WALG_S3_PREFIX}"
    local possible_paths=("wal_005" "wal" "wal_files" "archive")
    
    for path in "${possible_paths[@]}"; do
        log "Checking for WAL files in: ${path}"
        if wal_files=$(run_as_postgres aws s3 ls "${base_path}/${path}/" 2>/dev/null); then
            if [ -n "$wal_files" ]; then
                log "Found WAL files in: ${path}"
                echo "$wal_files"
                return 0
            fi
        fi
    done
    
    log "No WAL files found in any expected location"
    return 1
}

# Verify database connection
log "Verifying database connection..."
if ! run_as_postgres pg_isready -h postgres -p 5432; then
    log "ERROR: Cannot connect to database"
    exit 1
fi

# Verify PostgreSQL is accepting connections
log "Verifying PostgreSQL connection..."
if ! run_as_postgres psql -c "SELECT version();" > /dev/null 2>&1; then
    log "ERROR: Cannot execute query on PostgreSQL"
    log "Connection error: $(run_as_postgres psql -c "SELECT version();" 2>&1)"
    exit 1
fi

# Create backup with error logging
log "Creating backup..."
if backup_output=$(run_as_postgres wal-g backup-push /var/lib/postgresql/data 2>&1); then
    log "Backup completed successfully"
    
    # Show backup details (without sensitive info)
    log "Checking backup status..."
    if backup_list=$(run_as_postgres wal-g backup-list 2>&1); then
        backup_count=$(echo "$backup_list" | wc -l)
        log "Total backups available: $backup_count"
    fi
    
    # Check WAL files in various possible locations
    log "Checking WAL archives..."
    if ! check_wal_path; then
        log "WARNING: Could not find WAL archives"
        # List all folders in the bucket for debugging
        log "Available folders in backup location:"
        run_as_postgres aws s3 ls "${WALG_S3_PREFIX}/" 2>/dev/null | tee -a "$LOG_FILE"
    fi
else
    log "ERROR: Backup failed"
    log "Backup error details:"
    echo "$backup_output" | grep -v -E "password|secret|key" | tee -a "$LOG_FILE"
    exit 1
fi
