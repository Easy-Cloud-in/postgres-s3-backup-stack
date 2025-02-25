#!/bin/bash
set -e

# Function for logging
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

# Function to check required commands
check_requirements() {
    log "Checking system requirements..."
    if ! command -v docker &> /dev/null; then
        log "Error: docker is required but not installed"
        exit 1
    fi

    if ! docker compose version &> /dev/null; then
        log "Error: docker compose is required but not installed"
        exit 1
    fi
}

# Function to run AWS CLI commands using Docker
aws_docker() {
    docker run --rm \
        -e AWS_ACCESS_KEY_ID="$AWS_ACCESS_KEY_ID" \
        -e AWS_SECRET_ACCESS_KEY="$AWS_SECRET_ACCESS_KEY" \
        -e AWS_REGION="$AWS_REGION" \
        amazon/aws-cli "$@"
}

# Function to create S3 bucket and folder
create_s3_structure() {
    local bucket_name=$1
    local client_name=$2
    local region=$3

    # Check if the bucket already exists
    if aws_docker s3api head-bucket --bucket "$bucket_name" 2>/dev/null; then
        log "Bucket '$bucket_name' already exists."
    else
        # Create the S3 bucket
        log "Creating bucket '$bucket_name'..."
        if ! aws_docker s3api create-bucket --bucket "$bucket_name" --region "$region" --create-bucket-configuration LocationConstraint="$region"; then
            log "Error: Failed to create bucket '$bucket_name'"
            exit 1
        fi
        log "Bucket '$bucket_name' created successfully."
    fi

    # Create a folder inside the bucket using the client-name
    local folder_key="${client_name}/"
    
    # Check if the folder already exists
    if aws_docker s3 ls "s3://$bucket_name/$folder_key" 2>/dev/null; then
        log "Folder '$client_name/' already exists in bucket '$bucket_name'."
    else
        # Create the folder
        log "Creating folder '$client_name/' in bucket '$bucket_name'..."
        if ! aws_docker s3api put-object --bucket "$bucket_name" --key "$folder_key"; then
            log "Error: Failed to create folder '$client_name/' in bucket '$bucket_name'"
            exit 1
        fi
        log "Folder '$client_name/' created successfully in bucket '$bucket_name'."
    fi

    # Apply S3 lifecycle policy with exported variables
    log "Applying S3 lifecycle policy..."
    export S3_BUCKET="$bucket_name"
    export CLIENT_NAME="$client_name"
    if ! ./scripts/configure-s3-lifecycle.sh; then
        log "Warning: Failed to apply S3 lifecycle policy"
    else
        log "S3 lifecycle policy applied successfully"
    fi
}

# Function to validate required environment variables
validate_env() {
    log "Validating environment configuration..."
    local required_vars=(
        "AWS_ACCESS_KEY_ID"
        "AWS_SECRET_ACCESS_KEY"
        "AWS_REGION"
        "S3_BUCKET"
        "BACKUP_SCHEDULE"
        "WAL_RETENTION_DAYS"
        "BACKUP_RETENTION_DAYS"
    )

    local missing_vars=()
    for var in "${required_vars[@]}"; do
        if [ -z "${!var}" ]; then
            missing_vars+=("$var")
        fi
    done

    if [ ${#missing_vars[@]} -ne 0 ]; then
        log "Error: Missing required configuration:"
        printf '%s\n' "${missing_vars[@]}"
        exit 1
    fi
}

# Function to safely set permissions
set_permissions() {
    local path=$1
    local perms=$2
    
    if ! chmod "$perms" "$path" 2>/dev/null; then
        log "Warning: Failed to set permissions on $path, attempting with sudo..."
        if ! sudo chmod "$perms" "$path"; then
            log "Error: Failed to set permissions on $path even with sudo"
            return 1
        fi
    fi
}

# Function to safely create directory
create_dir() {
    local dir=$1
    local perms=$2
    
    if [ ! -d "$dir" ]; then
        if ! mkdir -p "$dir" 2>/dev/null; then
            log "Warning: Failed to create $dir, attempting with sudo..."
            if ! sudo mkdir -p "$dir"; then
                log "Error: Failed to create $dir even with sudo"
                return 1
            fi
        fi
    fi
    
    set_permissions "$dir" "$perms"
}

# Function to create required directories and config files
create_directories() {
    log "Creating required directories..."
    
    # Create directories with proper permissions
    create_dir "pg_logs" "777"
    create_dir "pgbouncer/logs" "777"
    create_dir "pg_archive" "777"
    create_dir "pgdata" "777"
    create_dir "config" "755"
    create_dir "scripts/docker-entrypoint-initdb.d" "755"
    create_dir "backup_logs" "777"
    
    # Handle pgbouncer.ini file
    if [ ! -f "pgbouncer/pgbouncer.ini" ]; then
        touch "pgbouncer/pgbouncer.ini" 2>/dev/null || sudo touch "pgbouncer/pgbouncer.ini"
    fi
    set_permissions "pgbouncer/pgbouncer.ini" "666"
    
    log "Directories created successfully"
}

# Function to update .env with client name
update_env_with_client() {
    local client_name=$1
    if ! grep -q "^CLIENT_NAME=" .env; then
        echo "CLIENT_NAME=$client_name" >> .env
    else
        sed -i "s/^CLIENT_NAME=.*/CLIENT_NAME=$client_name/" .env
    fi
}

# Function to validate backup configuration
validate_backup_config() {
    # log "Validating backup configuration..."
    
    # Show current values for debugging
    # log "Current configuration values:"
    # log "BACKUP_SCHEDULE: $BACKUP_SCHEDULE"
    # log "WAL_RETENTION_DAYS: $WAL_RETENTION_DAYS"
    # log "BACKUP_RETENTION_DAYS: $BACKUP_RETENTION_DAYS"
    
    if ! ./scripts/validate-backup-config.sh; then
        log "Error: Invalid backup configuration"
        exit 1
    fi
}

# Function to check container health
check_container_health() {
    local container="htxppdb-backup"
    local max_attempts=30
    local attempt=1
    local delay=2

    log "Waiting for backup service to initialize..."
    
    while [ $attempt -le $max_attempts ]; do
        if docker compose logs backup | grep -q "Backup service is running"; then
            log "Backup service initialized successfully"
            return 0
        fi
        
        # Check if container is running
        if ! docker compose ps backup | grep -q "Up"; then
            if docker compose logs backup | grep -q "ERROR:"; then
                log "Error: Backup service failed to start"
                return 1
            fi
        fi
        
        sleep $delay
        attempt=$((attempt + 1))
    done

    log "Error: Backup service initialization timed out"
    return 1
}

# Main setup process
main() {
    log "Starting setup process..."
    
    # Check requirements
    check_requirements
    
    # Load environment variables
    if [ -f .env ]; then
        set -a
        source .env
        set +a
    else
        log "Error: Configuration file (.env) not found"
        exit 1
    fi

    # Ask for client name
    read -p "Please enter the client name: " client_name
    if [ -z "$client_name" ]; then
        log "Error: Client name cannot be empty"
        exit 1
    fi

    # Validate environment
    validate_env
    
    # Validate backup configuration
    validate_backup_config
    
    # Update client name
    update_env_with_client "$client_name"
    export CLIENT_NAME="$client_name"
    log "Client name set successfully"

    # Create S3 bucket and folder structure
    log "Setting up S3 bucket structure..."
    create_s3_structure "$S3_BUCKET" "$CLIENT_NAME" "$AWS_REGION"
    
    # Create required directories
    create_directories
    
    log "Starting services..."
    if ! docker compose up -d; then
        log "Error: Failed to start services" "ERROR"
        exit 1
    fi
    
    # Wait for PostgreSQL
    log "Waiting for PostgreSQL to become healthy..."
    for i in {1..30}; do
        if docker compose ps postgres | grep -q "healthy"; then
            log "PostgreSQL is healthy"
            break
        fi
        if [ $i -eq 30 ]; then
            log "Error: PostgreSQL failed to become healthy" "ERROR"
            exit 1
        fi
        sleep 5
    done
    
    # Wait for PgBouncer
    log "Waiting for PgBouncer to become healthy..."
    for i in {1..30}; do
        if docker compose ps pgbouncer | grep -q "healthy"; then
            chmod +x scripts/check-pgbouncer.sh
            export POSTGRES_USER
            export POSTGRES_PASSWORD
            export PG_BOUNCER_PORT
            export POSTGRES_DB
            if ./scripts/check-pgbouncer.sh; then
                log "PgBouncer is healthy and accessible"
                break
            fi
        fi
        if [ $i -eq 30 ]; then
            log "Error: PgBouncer failed to become healthy" "ERROR"
            docker compose logs pgbouncer
            exit 1
        fi
        sleep 5
    done

    # Check container health
    if ! check_container_health; then
        exit 1
    fi

    log "Setup completed successfully! Services are running and accessible:"
    log "- PostgreSQL is running and healthy"
    log "- PgBouncer is accessible on port ${PG_BOUNCER_PORT}"
    log "- Backup service is running properly"
    exit 0
}

# Run main function
main "$@"
