#!/bin/bash
set -e

# Set password encryption to SCRAM-SHA-256
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    ALTER SYSTEM SET password_encryption = 'scram-sha-256';
    SELECT pg_reload_conf();
    ALTER USER "$POSTGRES_USER" WITH PASSWORD '$POSTGRES_PASSWORD';
    CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
EOSQL
