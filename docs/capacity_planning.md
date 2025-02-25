# PostgreSQL Capacity Planning Guide

## Resource Requirements Calculator

### 1. Memory Allocation

```bash
#!/bin/bash
# Memory calculator for PostgreSQL and PgBouncer

calculate_memory() {
    local TOTAL_RAM_GB=$1
    local TOTAL_RAM_MB=$((TOTAL_RAM_GB * 1024))
    
    # PostgreSQL Memory Parameters
    local SHARED_BUFFERS=$((TOTAL_RAM_MB / 4))  # 25% of RAM
    local EFFECTIVE_CACHE_SIZE=$((TOTAL_RAM_MB * 3 / 4))  # 75% of RAM
    local MAINTENANCE_WORK_MEM=$((TOTAL_RAM_MB / 16))  # 6.25% of RAM
    local WORK_MEM=$((TOTAL_RAM_MB / 50))  # ~2% of RAM
    
    cat << EOF
PostgreSQL Memory Configuration:
--------------------------------
shared_buffers = ${SHARED_BUFFERS}MB
effective_cache_size = ${EFFECTIVE_CACHE_SIZE}MB
maintenance_work_mem = ${MAINTENANCE_WORK_MEM}MB
work_mem = ${WORK_MEM}MB
EOF
}
```

### 2. Connection Planning

```sql
-- Calculate optimal connection settings
WITH constants AS (
    SELECT 
        current_setting('max_connections')::int as max_conn,
        current_setting('shared_buffers')::int / 1024 / 1024 as shared_buffers_gb
)
SELECT 
    max_conn as current_max_connections,
    shared_buffers_gb as shared_buffers_gb,
    round(shared_buffers_gb * 1.5) as recommended_max_connections,
    round(shared_buffers_gb * 1.5 / 4) as recommended_pool_size
FROM constants;
```

## Capacity Thresholds

### 1. Database Size Planning

| Component | Warning Threshold | Critical Threshold | Action Required |
|-----------|------------------|-------------------|-----------------|
| Data Size | 70% of allocated space | 85% of allocated space | Increase storage/cleanup |
| Index Size | 50% of data size | 75% of data size | Index optimization |
| WAL Volume | >50GB/day | >100GB/day | Adjust WAL retention |
| Temp Space | >10% of total space | >20% of total space | Increase temp_buffers |

### 2. Connection Capacity

```sql
-- Monitor connection utilization
SELECT 
    count(*) * 100.0 / current_setting('max_connections')::float as connection_percentage,
    CASE 
        WHEN count(*) * 100.0 / current_setting('max_connections')::float > 75 THEN 'WARNING'
        WHEN count(*) * 100.0 / current_setting('max_connections')::float > 90 THEN 'CRITICAL'
        ELSE 'OK'
    END as status
FROM pg_stat_activity;
```

## Scaling Guidelines

### 1. Vertical Scaling Triggers

| Metric | Threshold | Scaling Recommendation |
|--------|-----------|----------------------|
| CPU Usage | >70% sustained | Increase CPU cores |
| Memory Usage | >85% sustained | Increase RAM |
| IOPS | >80% of provisioned | Increase storage IOPS |
| Storage Latency | >10ms average | Upgrade storage type |

### 2. Horizontal Scaling Indicators

```sql
-- Query to identify need for read replicas
SELECT 
    count(*) as total_queries,
    sum(CASE WHEN query ~* '^SELECT' THEN 1 ELSE 0 END) as select_queries,
    sum(CASE WHEN query ~* '^SELECT' THEN 1 ELSE 0 END)::float / count(*) * 100 
        as read_percentage
FROM pg_stat_statements
WHERE query !~ '^(SHOW|SET|BEGIN|COMMIT|ROLLBACK)';
```

## Performance Optimization

### 1. Index Optimization

```sql
-- Identify missing indexes
SELECT 
    schemaname || '.' || relname as table,
    seq_scan,
    seq_tup_read,
    idx_scan,
    seq_tup_read / CASE WHEN seq_scan = 0 THEN 1 ELSE seq_scan END 
        as avg_rows_per_scan
FROM pg_stat_user_tables
WHERE seq_scan > 0
ORDER BY seq_tup_read DESC
LIMIT 10;

-- Find unused indexes
SELECT 
    schemaname || '.' || tablename as table,
    indexname,
    idx_scan,
    pg_size_pretty(pg_relation_size(indexrelid)) as index_size
FROM pg_stat_user_indexes
WHERE idx_scan = 0
AND indexrelid NOT IN (
    SELECT conindid FROM pg_constraint
)
ORDER BY pg_relation_size(indexrelid) DESC;
```

### 2. Query Optimization

```sql
-- Identify slow queries
SELECT 
    substring(query, 1, 50) as query_preview,
    calls,
    total_time / calls as avg_time,
    rows / calls as avg_rows,
    100.0 * shared_blks_hit / nullif(shared_blks_hit + shared_blks_read, 0) 
        as cache_hit_ratio
FROM pg_stat_statements
ORDER BY total_time DESC
LIMIT 10;
```

## Growth Planning

### 1. Storage Growth Calculator

```sql
-- Calculate daily growth rate
WITH table_sizes AS (
    SELECT 
        schemaname || '.' || relname as table_name,
        pg_total_relation_size(relid) as total_bytes,
        pg_relation_size(relid) as data_bytes,
        pg_total_relation_size(relid) - pg_relation_size(relid) as index_bytes
    FROM pg_stat_user_tables
)
SELECT 
    sum(total_bytes) / 1024 / 1024 / 1024 as total_size_gb,
    sum(data_bytes) / 1024 / 1024 / 1024 as data_size_gb,
    sum(index_bytes) / 1024 / 1024 / 1024 as index_size_gb,
    (sum(total_bytes) / 1024 / 1024 / 1024) * 0.02 as estimated_daily_growth_gb
FROM table_sizes;
```

### 2. Resource Projection

```sql
-- Project resource needs based on current growth
WITH growth_stats AS (
    SELECT 
        date_trunc('day', query_start) as day,
        count(*) as queries,
        sum(calls) as total_calls,
        sum(total_time) as total_time
    FROM pg_stat_statements
    GROUP BY 1
    ORDER BY 1
)
SELECT 
    avg(queries) as avg_daily_queries,
    avg(total_calls) as avg_daily_calls,
    avg(queries) * 1.5 as projected_peak_queries,
    avg(total_calls) * 1.5 as projected_peak_calls
FROM growth_stats;
```

## Monitoring and Alerts

### 1. Capacity Monitoring Queries

```sql
-- Monitor tablespace usage
SELECT 
    spcname as tablespace,
    pg_size_pretty(pg_tablespace_size(spcname)) as size,
    pg_size_pretty(pg_tablespace_size(spcname) - 
        (SELECT sum(pg_relation_size(c.oid))
         FROM pg_class c
         WHERE pg_tablespace_oid = spcname)) as free_space
FROM pg_tablespace;

-- Monitor connection slots
SELECT 
    max_conn,
    used_conn,
    res_for_super,
    max_conn - used_conn - res_for_super as free_conn
FROM
    (SELECT current_setting('max_connections')::int as max_conn,
            count(*) as used_conn,
            current_setting('superuser_reserved_connections')::int as res_for_super
    FROM pg_stat_activity) t;
```

### 2. Alert Configuration

```yaml
# Example Prometheus alert rules
groups:
- name: PostgresCapacityAlerts
  rules:
  - alert: HighConnectionUsage
    expr: pg_stat_activity_count > pg_settings_max_connections * 0.75
    for: 5m
    labels:
      severity: warning
    annotations:
      summary: High connection usage

  - alert: StorageNearingCapacity
    expr: pg_database_size_bytes / pg_database_size_bytes_total > 0.85
    for: 30m
    labels:
      severity: warning
    annotations:
      summary: Database storage usage high
```

## Scaling Procedures

### 1. Vertical Scaling Steps

```bash
#!/bin/bash
# Pre-scaling checks
check_scaling_prerequisites() {
    # Check current resource usage
    CPU_USAGE=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}')
    MEM_USAGE=$(free | grep Mem | awk '{print $3/$2 * 100.0}')
    DISK_USAGE=$(df -h | grep /data | awk '{print $5}' | sed 's/%//')
    
    echo "Current Usage:"
    echo "CPU: ${CPU_USAGE}%"
    echo "Memory: ${MEM_USAGE}%"
    echo "Disk: ${DISK_USAGE}%"
}
```

### 2. Horizontal Scaling Preparation

```sql
-- Prepare for read replica
SELECT pg_is_in_recovery(), current_setting('max_wal_senders'), 
       current_setting('wal_level');

-- Check replication slot status
SELECT slot_name, plugin, slot_type, active
FROM pg_replication_slots;

-- Monitor replication lag
SELECT client_addr, state, sent_lsn, write_lsn, 
       flush_lsn, replay_lsn, sync_state
FROM pg_stat_replication;
```