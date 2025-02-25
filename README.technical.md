# PostgreSQL Docker Setup - Technical Documentation

## System Architecture

### Components

1. **PostgreSQL (port 5432)**

   - Version: 16-bullseye
   - Role: Primary database server
   - Configuration: Custom optimized postgresql.conf

2. **PgBouncer (port 6432)**

   - Connection pooling middleware
   - Pool management strategy: transaction pooling
   - Default pool size: 20 connections
   - Max client connections: 1000

3. **WAL-G Backup Service**
   - Version: 2.0.1
   - Backup strategy: Full backups + WAL archiving
   - Storage: AWS S3
   - Retention management: Automated lifecycle policies

## Technical Specifications

### PostgreSQL Configuration

```ini
# Memory Configuration
shared_buffers = 256MB
work_mem = 16MB
maintenance_work_mem = 64MB
effective_cache_size = 768MB

# Checkpoint Configuration
checkpoint_timeout = 15min
checkpoint_completion_target = 0.9
max_wal_size = 1GB
min_wal_size = 80MB

# WAL Configuration
wal_level = replica
archive_mode = on
archive_command = 'wal-g wal-push %p'
archive_timeout = 60
```

### PgBouncer Settings

```ini
[databases]
* = host=postgres port=5432

[pgbouncer]
pool_mode = transaction
max_client_conn = 1000
default_pool_size = 20
reserve_pool_size = 10
reserve_pool_timeout = 5
max_db_connections = 50
max_user_connections = 200
```

### Backup System Architecture

1. **Full Backups**

   ```bash
   # Backup command structure
   wal-g backup-push /var/lib/postgresql/data

   # Backup verification
   wal-g backup-verify base_BACKUP_NAME
   ```

2. **WAL Archiving**

   ```bash
   # WAL push command
   wal-g wal-push %p

   # WAL fetch command
   wal-g wal-fetch %f %p
   ```

3. **S3 Lifecycle Configuration**
   ```json
   {
     "Rules": [
       {
         "ID": "WALRetention",
         "Filter": { "Prefix": "wal/" },
         "Status": "Enabled",
         "Expiration": { "Days": 3 }
       },
       {
         "ID": "BackupRetention",
         "Filter": { "Prefix": "backup/" },
         "Status": "Enabled",
         "Expiration": { "Days": 7 }
       }
     ]
   }
   ```

## Performance Monitoring

### Key Metrics

1. **PostgreSQL Metrics**

   ```sql
   -- Connection Status
   SELECT state, count(*) FROM pg_stat_activity GROUP BY state;

   -- Buffer Cache Hit Ratio
   SELECT
     sum(heap_blks_hit) / (sum(heap_blks_hit) + sum(heap_blks_read)) as hit_ratio
   FROM pg_statio_user_tables;

   -- Transaction Rates
   SELECT sum(xact_commit + xact_rollback) /
          extract(epoch from now() - pg_postmaster_start_time()) as tps
   FROM pg_stat_database;
   ```

2. **PgBouncer Metrics**

   ```sql
   -- Pool Status
   SHOW POOLS;

   -- Client Connections
   SHOW CLIENTS;

   -- Server Status
   SHOW SERVERS;
   ```

### Performance Tuning

1. **Connection Pooling Optimization**

   ```bash
   # Calculate optimal pool size
   pool_size = ((core_count * 2) + effective_spindle_count)

   # Example for 4 cores, 2 disks
   default_pool_size = ((4 * 2) + 2) = 10
   ```

2. **Memory Settings Calculation**

   ```bash
   # Shared Buffers (25% of RAM)
   shared_buffers = RAM * 0.25

   # Effective Cache Size (75% of RAM)
   effective_cache_size = RAM * 0.75

   # Work Memory
   work_mem = (RAM * 0.25) / (max_connections * 2)
   ```

## Disaster Recovery Procedures

### Full System Recovery

1. **Stop Services**

   ```bash
   docker compose down
   ```

2. **Clear Existing Data**

   ```bash
   rm -rf pgdata/* pg_archive/* pg_logs/*
   ```

3. **Restore Latest Backup**

   ```bash
   # Get latest backup name
   LATEST_BACKUP=$(docker compose exec backup wal-g backup-list | tail -n 1)

   # Restore backup
   docker compose exec backup wal-g backup-fetch /var/lib/postgresql/data $LATEST_BACKUP
   ```

4. **Recovery Configuration**
   ```bash
   # recovery.conf
   restore_command = 'wal-g wal-fetch "%f" "%p"'
   recovery_target_timeline = 'latest'
   ```

### Point-in-Time Recovery (PITR)

```bash
# Identify target timestamp
TARGET_TIME="2024-02-20 15:00:00.000000+00"

# Configure recovery
cat > recovery.conf << EOF
restore_command = 'wal-g wal-fetch "%f" "%p"'
recovery_target_time = '$TARGET_TIME'
recovery_target_timeline = 'latest'
EOF
```

## Security Implementation

### Network Security

1. **Container Network Isolation**

   ```yaml
   # docker-compose.yml network configuration
   networks:
     postgres_net:
       internal: true
   ```

2. **Port Exposure**
   ```yaml
   ports:
     - '127.0.0.1:5432:5432' # PostgreSQL
     - '127.0.0.1:6432:6432' # PgBouncer
   ```

### Access Control

1. **Database User Management**

   ```sql
   -- Create application user
   CREATE ROLE app_user WITH LOGIN PASSWORD 'secure_password';

   -- Grant minimal privileges
   GRANT CONNECT ON DATABASE app_db TO app_user;
   GRANT USAGE ON SCHEMA public TO app_user;
   GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO app_user;
   ```

2. **PgBouncer Authentication**
   ```ini
   # userlist.txt
   "app_user" "md5hash_of_password"
   ```

## Maintenance Procedures

### Database Maintenance

1. **Vacuum Operations**

   ```sql
   -- Regular vacuum
   VACUUM ANALYZE;

   -- Full vacuum
   VACUUM FULL;
   ```

2. **Index Maintenance**

   ```sql
   -- Reindex specific table
   REINDEX TABLE table_name;

   -- Reindex entire database
   REINDEX DATABASE database_name;
   ```

### Backup Verification

```bash
# Verify backup integrity
docker compose exec backup wal-g backup-verify $BACKUP_NAME

# Check WAL archive
docker compose exec backup wal-g wal-verify

# Test restore process
./scripts/test-restore.sh
```

## Monitoring and Logging

### Log Configuration

1. **PostgreSQL Logging**

   ```ini
   log_destination = 'csvlog'
   logging_collector = on
   log_directory = 'pg_log'
   log_filename = 'postgresql-%Y-%m-%d_%H%M%S.log'
   log_min_duration_statement = 1000
   log_checkpoints = on
   log_connections = on
   log_disconnections = on
   log_lock_waits = on
   ```

2. **PgBouncer Logging**
   ```ini
   log_connections = 1
   log_disconnections = 1
   log_pooler_errors = 1
   stats_period = 60
   ```

### Monitoring Queries

```sql
-- Active Queries
SELECT pid, age(clock_timestamp(), query_start), usename, query
FROM pg_stat_activity
WHERE state != 'idle' AND query != '<IDLE>'
ORDER BY query_start desc;

-- Table Statistics
SELECT schemaname, relname, seq_scan, seq_tup_read,
       idx_scan, idx_tup_fetch, n_tup_ins, n_tup_upd, n_tup_del
FROM pg_stat_user_tables
ORDER BY seq_scan DESC;

-- Index Usage
SELECT schemaname, tablename, indexname, idx_scan,
       idx_tup_read, idx_tup_fetch
FROM pg_stat_user_indexes
ORDER BY idx_scan DESC;
```

## Development Guidelines

### Connection String Formats

1. **Direct PostgreSQL Connection**

   ```
   postgresql://user:password@localhost:5432/dbname
   ```

2. **PgBouncer Connection**
   ```
   postgresql://user:password@localhost:6432/dbname
   ```

### Environment Configuration

```bash
# Required Variables
POSTGRES_USER=dbuser
POSTGRES_PASSWORD=secure_password
POSTGRES_DB=appdb
PG_BOUNCER_PORT=6432

# AWS Configuration
AWS_ACCESS_KEY_ID=your_access_key
AWS_SECRET_ACCESS_KEY=your_secret_key
AWS_REGION=your_region
S3_BUCKET=your_bucket

# Backup Configuration
WAL_RETENTION_DAYS=3
BACKUP_RETENTION_DAYS=7
```

## Troubleshooting Guide

### Common Issues

1. **Connection Failures**

   ```bash
   # Check PostgreSQL logs
   tail -f pg_logs/postgresql-*.log

   # Check PgBouncer logs
   tail -f pgbouncer/logs/pgbouncer.log
   ```

2. **Backup Failures**

   ```bash
   # Check WAL-G status
   docker compose exec backup wal-g backup-list

   # Verify S3 access
   docker compose exec backup aws s3 ls ${S3_BUCKET}
   ```

3. **Performance Issues**
   ```sql
   -- Check for long-running queries
   SELECT pid, now() - pg_stat_activity.query_start AS duration, query
   FROM pg_stat_activity
   WHERE pg_stat_activity.query != '<IDLE>'
   AND pg_stat_activity.waiting = true;
   ```

---

## Technical Support

For technical issues or contributions:

- Create an issue in the repository
- Contact: SAKAR.SR
- Website: [easy-cloud.in](https://easy-cloud.in)

Built with assistance from AUGMENT AI
