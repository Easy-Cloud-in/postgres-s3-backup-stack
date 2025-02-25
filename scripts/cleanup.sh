#!/bin/bash

# Function for logging
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

# Function to check if docker compose is available
check_docker() {
    if ! command -v docker &> /dev/null; then
        log "Error: docker is not installed"
        exit 1
    fi

    if ! docker compose version &> /dev/null; then
        log "Error: docker compose is not installed"
        exit 1
    fi
}

# Function to safely remove directory
remove_dir() {
    local dir=$1
    if [ -d "$dir" ]; then
        log "Removing directory: $dir"
        if ! rm -rf "$dir"; then
            log "Warning: Failed to remove $dir, attempting with sudo..."
            if ! sudo rm -rf "$dir"; then
                log "Error: Failed to remove $dir even with sudo"
                return 1
            fi
        fi
    else
        log "Directory $dir does not exist, skipping..."
    fi
}

# Load environment variables
if [ -f .env ]; then
    source .env
else
    log "Warning: .env file not found"
fi

# Main cleanup function
cleanup() {
    log "Starting cleanup process..."

    # Stop all containers and remove networks from the compose file
    log "Stopping containers and removing networks..."
    docker compose down --remove-orphans --volumes --rmi all

    # Remove any dangling networks related to this project
    PROJECT_NAME=$(basename $(pwd))
    log "Removing project networks..."
    docker network ls --filter "name=${PROJECT_NAME}_" -q | xargs -r docker network rm

    # Remove images built for this project
    log "Removing project images..."
    for image in POSTGRES_IMAGE BACKUP_IMAGE PGBOUNCER_IMAGE; do
        if [ ! -z "${!image}" ]; then
            log "Removing ${!image}..."
            docker rmi "${!image}" 2>/dev/null || true
        fi
    done

    # Remove local directories and their contents
    log "Removing local directories and files..."
    
    # List of directories to remove
    directories=(
        "pgdata"
        "pg_archive"
        "pg_logs"
        "pgbouncer/logs"
        "backup_logs"
    )

    # Remove each directory
    for dir in "${directories[@]}"; do
        remove_dir "$dir"
    done

    # Remove specific files
    files_to_remove=(
        "pgbouncer/userlist.txt"
        "pgbouncer/pgbouncer.ini"
    )

    for file in "${files_to_remove[@]}"; do
        if [ -f "$file" ]; then
            log "Removing file: $file"
            rm -f "$file" 2>/dev/null || sudo rm -f "$file"
        fi
    done

    # Remove all log files
    log "Removing log files..."
    find . -type f -name "*.log" -exec rm -f {} + 2>/dev/null || sudo find . -type f -name "*.log" -exec rm -f {} +

    # Recreate necessary directories with proper permissions
    log "Recreating directory structure..."
    mkdir -p pg_logs pgbouncer/logs pg_archive pgdata backup_logs
    chmod 777 pg_logs pgbouncer/logs pg_archive pgdata backup_logs || sudo chmod 777 pg_logs pgbouncer/logs pg_archive pgdata backup_logs

    log "Cleanup completed successfully!"
    log "To restart the services, run: docker compose up -d"
}

# Check requirements
check_docker

# Ask for confirmation
read -p "This will remove all containers, volumes, networks, and data related to this project. Are you sure? (y/N) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]
then
    cleanup
else
    log "Cleanup cancelled"
    exit 1
fi
