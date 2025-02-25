# Monitoring Guide

## Quick Reference

### Key Monitoring Commands
```bash
# PostgreSQL Activity
psql -h localhost -p 5432 -U ${POSTGRES_USER} -d ${POSTGRES_DB} -c "
SELECT datname, usename, state, query 
FROM pg_stat_activity 
WHERE state != 'idle';"

# PgBouncer Stats
psql -h localhost -p 6432 -U ${POSTGRES_USER} pgbouncer -c "SHOW POOLS;"
psql -h localhost -p 6432 -U ${POSTGRES_USER} pgbouncer -c "SHOW STATS;"

# Backup Status
docker compose exec backup wal-g backup-list --detail
```

## System Health Metrics

### 1. Database Performance Metrics

```sql
-- Connection Status
SELECT count(*), state 
FROM pg_stat_activity 
GROUP BY state;

-- Transaction Rate
SELECT sum(xact_commit + xact_rollback) / 
       extract(epoch from now() - pg_postmaster_start_time()) as tps
FROM pg_stat_database;

-- Cache Hit Ratio
SELECT 
    sum(heap_blks_hit) / (sum(heap_blks_hit) + sum(heap_blks_read))::float 
    as cache_hit_ratio 
FROM pg_statio_user_tables;
```

### 2. Connection Pool Metrics

```sql
-- Active Connections
SHOW POOLS;

-- Connection Stats
SHOW STATS;

-- Server Status
SHOW SERVERS;
```

### 3. Backup Health

```bash
# Backup Success Rate
grep "backup-push completed" /var/log/postgres/backup.log | wc -l

# Latest Backup Status
docker compose exec backup wal-g backup-list --detail | tail -n 1

# WAL Archive Status
docker compose exec backup wal-g wal-verify
```

## Alert Thresholds

| Metric | Warning | Critical | Action |
|--------|---------|----------|--------|
| Connection Count | >80% | >90% | Scale pool size |
| Cache Hit Ratio | <90% | <80% | Increase shared_buffers |
| Transaction Rate | >1000/s | >2000/s | Monitor load |
| Backup Age | >24h | >48h | Check backup system |

## Monitoring Scripts

### 1. Connection Monitor
```bash
#!/bin/bash
MAX_CONNECTIONS=100
WARN_THRESHOLD=80
CRIT_THRESHOLD=90

conn_count=$(psql -t -c "SELECT count(*) FROM pg_stat_activity;")
percentage=$((conn_count * 100 / MAX_CONNECTIONS))

if [ $percentage -gt $CRIT_THRESHOLD ]; then
    echo "CRITICAL: Connection count at ${percentage}%"
    exit 2
elif [ $percentage -gt $WARN_THRESHOLD ]; then
    echo "WARNING: Connection count at ${percentage}%"
    exit 1
fi
echo "OK: Connection count at ${percentage}%"
exit 0
```

### 2. Backup Monitor
```bash
#!/bin/bash
WARN_HOURS=24
CRIT_HOURS=48

latest_backup=$(docker compose exec -T backup wal-g backup-list | tail -n 1)
backup_time=$(date -d "${latest_backup}" +%s)
current_time=$(date +%s)
hours_diff=$(( (current_time - backup_time) / 3600 ))

if [ $hours_diff -gt $CRIT_HOURS ]; then
    echo "CRITICAL: Last backup is ${hours_diff} hours old"
    exit 2
elif [ $hours_diff -gt $WARN_HOURS ]; then
    echo "WARNING: Last backup is ${hours_diff} hours old"
    exit 1
fi
echo "OK: Last backup is ${hours_diff} hours old"
exit 0
```

## Integration Examples

### 1. Prometheus Integration

```yaml
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'postgres'
    static_configs:
      - targets: ['localhost:9187']
    metrics_path: '/metrics'
```

### 2. Grafana Dashboard

```json
{
  "dashboard": {
    "panels": [
      {
        "title": "Active Connections",
        "type": "graph",
        "datasource": "Prometheus",
        "targets": [
          {
            "expr": "pg_stat_activity_count"
          }
        ]
      }
    ]
  }
}
```

## Troubleshooting Guide

### Common Issues

1. High Connection Count
```sql
-- Find connection sources
SELECT client_addr, count(*) 
FROM pg_stat_activity 
GROUP BY client_addr 
ORDER BY count(*) DESC;
```

2. Slow Queries
```sql
-- Find long-running queries
SELECT pid, now() - query_start as duration, query 
FROM pg_stat_activity 
WHERE state = 'active' 
ORDER BY duration DESC;
```

3. Pool Exhaustion
```sql
-- Check pool status
SHOW POOLS;
-- Reset stuck pools if needed
RELOAD;
```