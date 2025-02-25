# PostgreSQL Docker Setup with Backup Solution to AWS S3

A containerized PostgreSQL setup with PgBouncer connection pooling and automated backups using WAL-G.

## Setup

1. Clone the repository
2. Copy the example environment file:
   ```bash
   cp .env.example .env
   ```
3. Update the `.env` file with your configurations
4. Run the setup script:
   ```bash
   chmod +x setup.sh
   ./setup.sh
   ```

## Connecting to PostgreSQL

### Direct PostgreSQL Connection

```javascript
// Using node-postgres
const { Pool } = require('pg');

const pool = new Pool({
  host: 'localhost',
  port: 5432, // Default PostgreSQL port
  database: 'htxppdb', // From POSTGRES_DB in .env
  user: 'dhana', // From POSTGRES_USER in .env
  password: 'htxpp-client', // From POSTGRES_PASSWORD in .env
});
```

### Via PgBouncer (Recommended)

```javascript
// Fastify example with @fastify/postgres
const fastify = require('fastify')();

fastify.register(require('@fastify/postgres'), {
  connectionString: 'postgres://dhana:htxpp-client@localhost:6432/htxppdb',
  // Note: Using PgBouncer port (6432) instead of PostgreSQL port (5432)
});

// Or using node-postgres
const { Pool } = require('pg');

const pool = new Pool({
  host: 'localhost',
  port: 6432, // PgBouncer port from PG_BOUNCER_PORT in .env
  database: 'htxppdb', // From POSTGRES_DB in .env
  user: 'dhana', // From POSTGRES_USER in .env
  password: 'htxpp-client', // From POSTGRES_PASSWORD in .env
});
```

### Connection String Format

```
postgresql://[user]:[password]@[host]:[port]/[database]
```

Example:

```
# Direct PostgreSQL connection:
postgresql://dhana:htxpp-client@localhost:5432/htxppdb

# Via PgBouncer:
postgresql://dhana:htxpp-client@localhost:6432/htxppdb
```

## Viewing Logs

### PostgreSQL Logs

```bash
# View latest PostgreSQL log
tail -f pg_logs/postgresql-*.log

# Search for errors
grep "ERROR" pg_logs/postgresql-*.log

# View logs from container
docker compose logs postgres
```

### PgBouncer Logs

```bash
# View PgBouncer logs
tail -f pgbouncer/logs/pgbouncer.log

# View logs from container
docker compose logs pgbouncer
```

### Backup Service Logs

```bash
# View backup service logs
docker compose logs backup
```

## Common Commands

### Service Management

```bash
# Start all services
docker compose up -d

# Stop all services
docker compose down

# Restart a specific service
docker compose restart postgres
docker compose restart pgbouncer

# View service status
docker compose ps
```

### Database Operations

```bash
# Connect to PostgreSQL directly
PGPASSWORD=htxpp-client psql -h localhost -p 5432 -U dhana -d htxppdb

# Connect via PgBouncer
PGPASSWORD=htxpp-client psql -h localhost -p 6432 -U dhana -d htxppdb

# PgBouncer admin console
PGPASSWORD=htxpp-client psql -h localhost -p 6432 -U dhana pgbouncer
```

### Monitoring

```bash
# Check PgBouncer pools
psql -h localhost -p 6432 -U dhana pgbouncer -c "SHOW POOLS;"

# Check PgBouncer clients
psql -h localhost -p 6432 -U dhana pgbouncer -c "SHOW CLIENTS;"

# Check PostgreSQL activity
psql -h localhost -p 5432 -U dhana -d htxppdb -c "SELECT * FROM pg_stat_activity;"
```

## Backup and Recovery

Backups are automatically scheduled according to the configuration in `.env`:

- WAL archives are retained for `WAL_RETENTION_DAYS` (default: 1 day)
- Full backups are retained for `BACKUP_RETENTION_DAYS` (default: 7 days)

### Manual Backup

```bash
# Trigger a manual backup
docker compose exec backup wal-g backup-push /var/lib/postgresql/data
```

### List Backups

```bash
# List available backups
docker compose exec backup wal-g backup-list
```

### Backup Details Explanation

The `wal-g backup-list --detail` output shows:

1. Backup Name: `base_000000010000000000000005`

   - This is a base backup associated with WAL segment 5

2. Timing Information:

   - Modified: 2025-02-20T14:29:27Z
   - Start Time: 2025-02-20T14:29:24Z
   - Finish Time: 2025-02-20T14:29:26Z
   - Total Duration: ~2 seconds

3. Technical Details:
   - PostgreSQL Version: 160007 (PostgreSQL 16)
   - Data Directory: /var/lib/postgresql/data
   - WAL Position: 0/5000028 to 0/5000100
   - Permanent: false (subject to retention policy)

To verify this backup's integrity:

```bash
docker compose exec backup wal-g backup-verify base_000000010000000000000005
```

## Environment Variables

Key environment variables in `.env`:

- `POSTGRES_USER`: Database username
- `POSTGRES_PASSWORD`: Database password
- `POSTGRES_DB`: Database name
- `PG_BOUNCER_PORT`: PgBouncer port (default: 6432)
- `MAX_CLIENT_CONN`: Maximum PgBouncer client connections
- `DEFAULT_POOL_SIZE`: Default PgBouncer pool size

## Security Notes

1. Always use PgBouncer (port 6432) for application connections
2. Keep your `.env` file secure and never commit it to version control
3. Regularly rotate database passwords and AWS credentials
4. Monitor logs for any suspicious activity

## Troubleshooting

1. If PgBouncer connection fails:

   - Check if PgBouncer is running: `docker compose ps`
   - Verify PgBouncer logs: `docker compose logs pgbouncer`
   - Ensure credentials in `.env` are correct

2. If PostgreSQL is unreachable:
   - Check PostgreSQL status: `docker compose ps postgres`
   - View PostgreSQL logs: `docker compose logs postgres`
   - Verify port mappings: `docker compose port postgres 5432`

```

This README.md provides:
1. Connection examples specific to your setup
2. Log viewing commands
3. Common operational commands
4. Backup and monitoring instructions
5. Troubleshooting guidance



#You can monitor the effectiveness of the pooling with:

psql -h localhost -p 6432 -U dhana pgbouncer -c "SHOW POOLS;"

# List all available backups

docker compose exec backup wal-g backup-list

# Show detailed information about backups

docker compose exec backup wal-g backup-list --detail

# View backup service logs

docker compose logs backup

# Follow backup logs in real-time

docker compose logs -f backup

# Copy test scripts to container

docker compose cp scripts/verify-walg.sh backup:/scripts/
docker compose cp scripts/test-backup.sh backup:/scripts/

# Make them executable

docker compose exec backup chmod +x /scripts/verify-walg.sh
docker compose exec backup chmod +x /scripts/test-backup.sh

# Run verification

docker compose exec backup /scripts/verify-walg.sh

# Run test backup

docker compose exec backup /scripts/test-backup.sh

# Verify WAL integrity

docker compose exec backup wal-g wal-verify --integrity

# Verify WAL archive

docker compose exec backup wal-g wal-show

# Verify specific backup

docker compose exec backup wal-g backup-verify base_BACKUP_NAME

# List all available backups with details

docker compose exec backup wal-g backup-list --detail

# List contents of your S3 bucket

docker compose exec backup aws s3 ls ${S3_BUCKET} --recursive

# To see the size of backups

docker compose exec backup aws s3 ls ${S3_BUCKET} --recursive --human-readable --summarize

docker compose exec backup /scripts/verify-walg.sh
```
