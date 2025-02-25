# PostgreSQL Capacity Planning - User Guide

## Quick Start

### 1. Calculate Resource Requirements

To calculate recommended PostgreSQL memory settings for your server:

```bash
# Run the memory calculator (replace 32 with your total RAM in GB)
./calculate_memory.sh 32
```

Example output:
```
PostgreSQL Memory Configuration:
--------------------------------
shared_buffers = 8192MB
effective_cache_size = 24576MB
maintenance_work_mem = 2048MB
work_mem = 655MB
```

### 2. Check Current Usage

Run these commands via PgBouncer (port 6432) to check your system's status:

```bash
# Connection usage
PGPASSWORD=htxpp-client psql -h localhost -p 6432 -U dhana -d htxppdb -c "
SELECT count(*) * 100.0 / current_setting('max_connections')::float as connection_percentage
FROM pg_stat_activity;"

# Storage usage
PGPASSWORD=htxpp-client psql -h localhost -p 6432 -U dhana -d htxppdb -c "
SELECT pg_size_pretty(pg_database_size(current_database())) as db_size;"
```

## When to Scale

### Warning Signs

Monitor these metrics and take action when you see:

1. **Connection Pool Saturation**
   ```bash
   # Check pool status
   PGPASSWORD=htxpp-client psql -h localhost -p 6432 -U dhana pgbouncer -c "SHOW POOLS;"
   ```
   - Warning: >75% pool usage
   - Critical: >90% pool usage

2. **Storage Usage**
   ```bash
   # Check database size
   PGPASSWORD=htxpp-client psql -h localhost -p 6432 -U dhana -d htxppdb -c "
   SELECT pg_size_pretty(sum(pg_relation_size(c.oid)))
   FROM pg_class c;"
   ```
   - Warning: >70% storage used
   - Critical: >85% storage used

3. **Performance Issues**
   ```bash
   # Check slow queries
   PGPASSWORD=htxpp-client psql -h localhost -p 6432 -U dhana -d htxppdb -c "
   SELECT substring(query, 1, 50) as query_preview,
          total_time / calls as avg_time
   FROM pg_stat_statements
   ORDER BY total_time DESC
   LIMIT 5;"
   ```
   - Warning: Queries taking >1 second
   - Critical: Queries taking >5 seconds

## Regular Maintenance Tasks

### 1. Index Optimization

Run monthly to identify unused indexes:

```bash
# Find unused indexes
PGPASSWORD=htxpp-client psql -h localhost -p 6432 -U dhana -d htxppdb -c "
SELECT schemaname || '.' || tablename as table,
       indexname,
       pg_size_pretty(pg_relation_size(indexrelid)) as index_size
FROM pg_stat_user_indexes
WHERE idx_scan = 0
AND indexrelid NOT IN (SELECT conindid FROM pg_constraint)
ORDER BY pg_relation_size(indexrelid) DESC
LIMIT 5;"
```

### 2. Growth Tracking

Monitor monthly growth rate:

```bash
# Calculate growth rate
PGPASSWORD=htxpp-client psql -h localhost -p 6432 -U dhana -d htxppdb -c "
WITH table_sizes AS (
    SELECT pg_total_relation_size(relid) as total_bytes
    FROM pg_stat_user_tables
)
SELECT 
    sum(total_bytes) / 1024 / 1024 / 1024 as total_size_gb,
    (sum(total_bytes) / 1024 / 1024 / 1024) * 0.02 as estimated_daily_growth_gb
FROM table_sizes;"
```

## Scaling Decisions

### When to Scale Vertically

1. **CPU Bound**
   - Symptom: High CPU usage (>70% sustained)
   - Action: Increase CPU cores
   - Command to check:
     ```bash
     top -bn1 | grep "Cpu(s)"
     ```

2. **Memory Bound**
   - Symptom: High memory usage (>85% sustained)
   - Action: Increase RAM
   - Command to check:
     ```bash
     free -m
     ```

### When to Scale Horizontally

1. **Read-Heavy Workload**
   - Symptom: High read percentage (>80%)
   - Action: Add read replicas
   - Command to check:
     ```bash
     PGPASSWORD=htxpp-client psql -h localhost -p 6432 -U dhana -d htxppdb -c "
     SELECT sum(CASE WHEN query ~* '^SELECT' THEN 1 ELSE 0 END)::float / count(*) * 100 
     as read_percentage
     FROM pg_stat_statements
     WHERE query !~ '^(SHOW|SET|BEGIN|COMMIT|ROLLBACK)';"
     ```

2. **Connection Saturation**
   - Symptom: High connection usage (>75%)
   - Action: Implement connection pooling or add more pools
   - Command to check:
     ```bash
     PGPASSWORD=htxpp-client psql -h localhost -p 6432 -U dhana pgbouncer -c "SHOW POOLS;"
     ```

## Troubleshooting Common Issues

### 1. Slow Queries

```bash
# Identify slow queries
PGPASSWORD=htxpp-client psql -h localhost -p 6432 -U dhana -d htxppdb -c "
SELECT substring(query, 1, 50) as query_preview,
       calls,
       total_time / calls as avg_time,
       rows / calls as avg_rows
FROM pg_stat_statements
ORDER BY total_time DESC
LIMIT 5;"
```

### 2. Connection Issues

```bash
# Check connection status
PGPASSWORD=htxpp-client psql -h localhost -p 6432 -U dhana pgbouncer -c "
SHOW CLIENTS;"

# Check pool status
PGPASSWORD=htxpp-client psql -h localhost -p 6432 -U dhana pgbouncer -c "
SHOW POOLS;"
```

### 3. Storage Issues

```bash
# Check table sizes
PGPASSWORD=htxpp-client psql -h localhost -p 6432 -U dhana -d htxppdb -c "
SELECT schemaname || '.' || relname as table_name,
       pg_size_pretty(pg_total_relation_size(relid)) as total_size,
       pg_size_pretty(pg_relation_size(relid)) as data_size,
       pg_size_pretty(pg_total_relation_size(relid) - pg_relation_size(relid)) 
       as index_size
FROM pg_stat_user_tables
ORDER BY pg_total_relation_size(relid) DESC
LIMIT 5;"
```

## Best Practices

1. **Regular Monitoring**
   - Run connection checks daily
   - Monitor storage growth weekly
   - Review performance metrics monthly

2. **Proactive Scaling**
   - Plan scaling when reaching 70% of any resource
   - Schedule maintenance during low-usage periods
   - Keep at least 20% headroom for growth

3. **Documentation**
   - Record all scaling decisions
   - Track growth patterns
   - Document performance baselines

## Need Help?

For technical issues or capacity planning assistance:
- Create an issue in the repository
- Contact: SAKAR.SR
- Website: [easy-cloud.in](https://easy-cloud.in)