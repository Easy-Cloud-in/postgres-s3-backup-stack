#!/bin/bash

# Function for logging
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

# Function to validate cron expression
validate_cron_syntax() {
    local schedule=$1
    
    if [ -z "$schedule" ]; then
        log "Error: Backup schedule is not set"
        return 1
    fi
    
    # Validate cron syntax
    if ! echo "$schedule" | grep -qE '^[0-9*,/-]+ [0-9*,/-]+ [0-9*,/-]+ [0-9*,/-]+ [0-9*,/-]+$'; then
        log "Error: Invalid backup schedule format"
        return 1
    fi
    
    return 0
}

# Function to validate backup frequency
validate_backup_frequency() {
    local schedule=$1
    
    # Add any specific frequency validation rules here
    return 0
}

# Function to validate retention periods
validate_retention_periods() {
    local wal_days=$1
    local backup_days=$2
    
    # Validate WAL retention days
    if ! [[ "$wal_days" =~ ^[0-9]+$ ]] || [ "$wal_days" -lt 1 ]; then
        log "Error: WAL retention days must be a positive number"
        return 1
    fi
    
    # Validate backup retention days
    if ! [[ "$backup_days" =~ ^[0-9]+$ ]] || [ "$backup_days" -lt 1 ]; then
        log "Error: Backup retention days must be a positive number"
        return 1
    fi
    
    # Ensure backup retention is greater than or equal to WAL retention
    if [ "$backup_days" -lt "$wal_days" ]; then
        log "Error: Backup retention period must be greater than or equal to WAL retention period"
        return 1
    fi
    
    return 0
}

# Main validation function
validate_backup_config() {
    log "Validating backup configuration..."
    
    # Validate cron syntax
    if ! validate_cron_syntax "$BACKUP_SCHEDULE"; then
        return 1
    fi
    
    # Validate backup frequency
    if ! validate_backup_frequency "$BACKUP_SCHEDULE"; then
        return 1
    fi
    
    # Validate retention periods
    if ! validate_retention_periods "$WAL_RETENTION_DAYS" "$BACKUP_RETENTION_DAYS"; then
        return 1
    fi
    
    log "Backup configuration is valid"
    return 0
}

# If script is run directly, validate using environment variables
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    validate_backup_config
fi 