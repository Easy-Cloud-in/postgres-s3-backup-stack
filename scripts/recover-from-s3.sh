#!/bin/bash
set -e

# Function for logging
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

# Function to check if command succeeded
check_error() {
    if [ $? -ne 0 ]; then
        log "Error: $1"
        exit 1
    fi
}

# Function to validate environment variables
validate_env() {
    local required_vars=(
        "POSTGRES_USER"
        "POSTGRES_PASSWORD"
        "COMPOSE_PROJECT_NAME"
        "AWS_ACCESS_KEY_ID"
        "AWS_SECRET_ACCESS_KEY"
        "AWS_REGION"
        "S3_BUCKET"
        "CLIENT_NAME"
    )

    log "Validating environment configuration..."
    for var in "${required_vars[@]}"; do
        if [ -z "${!var}" ]; then
            log "Error: $var is not set in .env file"
            exit 1
        fi
    done
}

# Load environment variables
if [ -f .env ]; then
    set -a
    source .env
    set +a
else
    log "Error: .env file not found"
    exit 1
fi

# Validate environment variables
validate_env

# Stop existing containers if running
log "Stopping existing containers..."
docker compose down --volumes
check_error "Failed to stop containers"

# Clear existing data volume
log "Clearing existing data volume..."
VOLUME_NAME="${COMPOSE_PROJECT_NAME}_postgres_data"
docker volume rm -f "${VOLUME_NAME}" || true
check_error "Failed to clear data volume"

# Start only the backup container
log "Starting backup container for restore..."
docker compose up -d backup
check_error "Failed to start backup container"

# Wait for backup container to be ready
log "Waiting for backup container to be ready..."
for i in {1..30}; do
    if docker compose exec backup pg_isready -h postgres -p 5432 >/dev/null 2>&1; then
        break
    fi
    sleep 2
    if [ $i -eq 30 ]; then
        log "Error: Backup container not ready after 60 seconds"
        exit 1
    fi
done

# List available backups
log "Checking available backups..."
BACKUPS=$(docker compose exec backup wal-g backup-list 2>/dev/null)
check_error "Failed to list backups"

if [ -z "$BACKUPS" ]; then
    log "Error: No backups found in S3"
    exit 1
fi

# Get the latest backup name
LATEST_BACKUP=$(echo "$BACKUPS" | tail -n 1)
log "Latest backup found: ${LATEST_BACKUP}"

# Perform the restore
log "Starting restore process..."
docker compose exec backup wal-g backup-fetch /var/lib/postgresql/data "${LATEST_BACKUP}"
check_error "Failed to fetch backup"

# Create recovery configuration
log "Configuring recovery..."
docker compose exec backup bash -c "cat > /var/lib/postgresql/data/recovery.signal << EOF
# Recovery configuration
restore_command = 'wal-g wal-fetch \"%f\" \"%p\"'
recovery_target_timeline = 'latest'
EOF"
check_error "Failed to create recovery configuration"

# Set correct permissions
log "Setting permissions..."
docker compose exec backup chown -R postgres:postgres /var/lib/postgresql/data
check_error "Failed to set permissions"

# Stop backup container
log "Stopping backup container..."
docker compose stop backup
check_error "Failed to stop backup container"

# Start all services
log "Starting PostgreSQL..."
docker compose up -d postgres
check_error "Failed to start PostgreSQL"

# Wait for PostgreSQL to start and complete recovery
log "Waiting for PostgreSQL to start and complete recovery..."
recovery_completed=false
for i in {1..60}; do
    if docker compose exec postgres pg_isready -U "${POSTGRES_USER}" >/dev/null 2>&1; then
        # Check if recovery is complete
        if docker compose exec postgres psql -U "${POSTGRES_USER}" -c "SELECT pg_is_in_recovery();" | grep -q "f"; then
            recovery_completed=true
            break
        fi
    fi
    log "Recovery in progress... ($i/60)"
    sleep 5
done

if [ "$recovery_completed" = true ]; then
    log "Recovery completed successfully!"
    
    # Verify database is accessible
    if docker compose exec postgres psql -U "${POSTGRES_USER}" -c "SELECT current_timestamp;" >/dev/null 2>&1; then
        log "Database is accessible and working properly"
        
        # Start all remaining services
        log "Starting all services..."
        if docker compose up -d; then
            log "All services started successfully"
            exit 0
        else
            log "Error: Failed to start all services"
            exit 1
        fi
    else
        log "Error: Database is not accessible after recovery"
        exit 1
    fi
else
    log "Error: Recovery process timed out or failed"
    log "Please check logs with: docker compose logs postgres"
    exit 1
fi
