#!/bin/bash

# Make scripts executable
chmod +x setup.sh
chmod +x gitsetup.sh
chmod +x scripts/docker-entrypoint-initdb.d/init.sh
chmod +x scripts/backup-entrypoint.sh
chmod +x scripts/configure-s3-lifecycle.sh
chmod +x scripts/cleanup.sh
chmod +x scripts/check-pgbouncer.sh
chmod +x scripts/init-userlist.sh
chmod +x scripts/test-backup.sh
chmod +x scripts/verify-walg.sh
chmod +x scripts/perform-backup.sh
chmod +x scripts/validate-backup-config.sh


# Set read permissions for config files
chmod 644 config/postgresql.conf
chmod 644 .env
chmod 644 docker-compose.yaml
chmod 644 Dockerfile
chmod 644 Dockerfile.backup-service

# Create pgbouncer directory if it doesn't exist
mkdir -p pgbouncer

# Set proper permissions for PgBouncer files
touch pgbouncer/userlist.txt
chmod 666 pgbouncer/userlist.txt
chmod 777 pgbouncer

