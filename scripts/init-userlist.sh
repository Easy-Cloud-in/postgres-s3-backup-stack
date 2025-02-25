#!/bin/bash
set -e

# Wait for PostgreSQL to be ready
MAX_RETRIES=30
RETRY_COUNT=0

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    if PGPASSWORD="${POSTGRES_PASSWORD}" psql -h postgres -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" -c '\q' 2>/dev/null; then
        break
    fi
    RETRY_COUNT=$((RETRY_COUNT + 1))
    echo "Waiting for PostgreSQL... (attempt $RETRY_COUNT/$MAX_RETRIES)"
    sleep 2
done

# Get SCRAM-SHA-256 hash
HASH=$(PGPASSWORD=$POSTGRES_PASSWORD psql -h postgres -U $POSTGRES_USER -d $POSTGRES_DB -tAc "SELECT rolpassword FROM pg_authid WHERE rolname = '$POSTGRES_USER'")

# Create userlist.txt with proper format
echo "\"$POSTGRES_USER\" \"$HASH\"" > /etc/pgbouncer/userlist.txt

# Process the template file and replace environment variables
envsubst < /etc/pgbouncer/pgbouncer.ini.template > /etc/pgbouncer/pgbouncer.ini

# Ensure proper permissions
chmod 644 /etc/pgbouncer/userlist.txt
chmod 644 /etc/pgbouncer/pgbouncer.ini

echo "PgBouncer user configuration completed successfully"

# Verify config file exists and is valid
if [ ! -f /etc/pgbouncer/pgbouncer.ini ]; then
    echo "Error: pgbouncer.ini not found!"
    ls -la /etc/pgbouncer/
    exit 1
fi

# Start PgBouncer
exec pgbouncer /etc/pgbouncer/pgbouncer.ini

