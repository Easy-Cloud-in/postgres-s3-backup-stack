#!/bin/bash
set -e

# Function for logging
log() {
    # Only log errors and success messages
    if [[ $2 == "ERROR" ]] || [[ $1 == *"successful"* ]]; then
        echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
    fi
}

# Function to test PgBouncer connection
test_connection() {
    docker compose exec -T -e PGPASSWORD="${POSTGRES_PASSWORD}" postgres psql \
        -h pgbouncer \
        -p 6432 \
        -U "${POSTGRES_USER}" \
        -d postgres \
        -c "SELECT 1;" >/dev/null 2>&1
}

# Function to show PgBouncer status
show_status() {
    docker compose exec -T -e PGPASSWORD="${POSTGRES_PASSWORD}" postgres psql \
        -h pgbouncer \
        -p 6432 \
        -U "${POSTGRES_USER}" \
        -d postgres \
        -c "SELECT current_database(), current_user;" >/dev/null 2>&1
}

# Main function to wait for PgBouncer
wait_for_pgbouncer() {
    local retries=10
    local wait_time=2
    
    sleep 5
    
    for i in $(seq 1 $retries); do
        if test_connection; then
            log "PgBouncer connection successful!"
            show_status
            return 0
        fi
        
        if [ $i -eq $retries ]; then
            log "Could not connect to PgBouncer after $retries attempts" "ERROR"
            docker compose logs pgbouncer
            return 1
        fi
        sleep $wait_time
    done
}

# Ensure environment variables are set
if [ -z "$POSTGRES_USER" ] || [ -z "$POSTGRES_PASSWORD" ]; then
    log "POSTGRES_USER and POSTGRES_PASSWORD must be set" "ERROR"
    exit 1
fi

# Run main function
wait_for_pgbouncer
