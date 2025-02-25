# Getting Started Guide

## Prerequisites

### System Requirements

- CPU: 2+ cores recommended
- RAM: Minimum 4GB, 8GB+ recommended
- Storage: 20GB+ free space
- Operating System: Linux, macOS, or Windows with WSL2

### Required Software

1. **Docker Engine**

   ```bash
   # Ubuntu
   curl -fsSL https://get.docker.com -o get-docker.sh
   sudo sh get-docker.sh

   # Verify installation
   docker --version   # Should be 20.10.0 or higher
   ```

2. **Docker Compose**

   ```bash
   # Should be included with Docker Desktop, if not:
   sudo apt-get install docker-compose-plugin

   # Verify installation
   docker compose version   # Should be 2.0.0 or higher
   ```

3. **AWS CLI**

   ```bash
   # Install AWS CLI
   curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
   unzip awscliv2.zip
   sudo ./aws/install

   # Verify installation
   aws --version
   ```

### AWS Configuration

1. Create an AWS account if you don't have one
2. Create an IAM user with S3 access
3. Note down:
   - AWS Access Key ID
   - AWS Secret Access Key
   - Preferred AWS Region

## Installation Steps

### 1. Clone the Repository

```bash
# Clone the repository
git clone https://github.com/your-username/postgres-docker-setup.git
cd postgres-docker-setup

# Make scripts executable
chmod +x set-permissions.sh
./set-permissions.sh
```

### 2. Configure Environment

```bash
# Copy example environment file
cp .env.example .env

# Edit .env file with your settings
nano .env
```

Required `.env` configurations:

```ini
# PostgreSQL Settings
POSTGRES_USER=your_username
POSTGRES_PASSWORD=your_secure_password
POSTGRES_DB=your_database_name

# AWS Settings
AWS_ACCESS_KEY_ID=your_access_key
AWS_SECRET_ACCESS_KEY=your_secret_key
AWS_REGION=your_region

# S3 Bucket Settings
S3_BUCKET_PREFIX=your_bucket_prefix
CLIENT_NAME=your_client_name
# S3_BUCKET will be automatically set to ${S3_BUCKET_PREFIX}-${CLIENT_NAME}

# Backup Settings
BACKUP_SCHEDULE="0 0 * * *"  # Daily at midnight
WAL_RETENTION_DAYS=1
BACKUP_RETENTION_DAYS=7
```

### 3. Run Setup Script

```bash
# Run the setup script
./setup.sh

# This will:
# - Validate your environment
# - Create necessary directories
# - Set up S3 bucket structure
# - Start Docker containers
```

### 4. Verify Installation

```bash
# Check container status
docker compose ps

# Should show three containers running:
# - postgres
# - pgbouncer
# - backup

# Test PostgreSQL connection
PGPASSWORD=your_password psql -h localhost -p 6432 -U your_username -d your_database -c "SELECT version();"

# Check backup service
docker compose logs backup
```

## Usage Examples

### Connect to Database

```bash
# Via PgBouncer (Recommended for applications)
postgresql://your_username:your_password@localhost:6432/your_database

# Direct PostgreSQL connection (For administrative tasks)
postgresql://your_username:your_password@localhost:5432/your_database
```

### Basic Operations

```bash
# Start services
docker compose up -d

# Stop services
docker compose down

# View logs
docker compose logs -f

# Restart specific service
docker compose restart postgres
docker compose restart pgbouncer
```

### Backup Operations

```bash
# List available backups
docker compose exec backup wal-g backup-list

# Trigger manual backup
docker compose exec backup wal-g backup-push /var/lib/postgresql/data

# View backup logs
docker compose logs backup
```

## Monitoring

### Check System Status

```bash
# PgBouncer pools
PGPASSWORD=your_password psql -h localhost -p 6432 -U your_username pgbouncer -c "SHOW POOLS;"

# PostgreSQL activity
PGPASSWORD=your_password psql -h localhost -p 6432 -U your_username -d your_database -c "SELECT * FROM pg_stat_activity;"
```

## Database Connectivity

### Connection Methods

#### 1. Direct PostgreSQL Connection (Port 5432)

```bash
# Command line connection
PGPASSWORD=your_password psql -h localhost -p 5432 -U your_username -d your_database

# Connection string format
postgresql://your_username:your_password@localhost:5432/your_database
```

#### 2. Via PgBouncer (Port 6432) - Recommended

```bash
# Command line connection
PGPASSWORD=your_password psql -h localhost -p 6432 -U your_username -d your_database

# Connection string format
postgresql://your_username:your_password@localhost:6432/your_database
```

### Application Integration Examples

#### 1. Fastify Application

```javascript
const Fastify = require('fastify');

async function build() {
  const fastify = Fastify({
    logger: true,
  });

  // Register PostgreSQL via PgBouncer
  fastify.register(require('@fastify/postgres'), {
    connectionString:
      'postgresql://your_username:your_password@localhost:6432/your_database',
    // Recommended pool settings
    pool: {
      min: 2,
      max: 10,
      idleTimeoutMillis: 30000,
      connectionTimeoutMillis: 2000,
    },
  });

  // Test endpoint
  fastify.get('/test', async (request, reply) => {
    try {
      const result = await fastify.pg.query('SELECT NOW() as current_time');
      return {
        status: 'success',
        time: result.rows[0].current_time,
      };
    } catch (err) {
      fastify.log.error(err);
      return reply.code(500).send({ error: 'Database connection failed' });
    }
  });

  return fastify;
}

// Start the server
async function start() {
  const fastify = await build();
  try {
    await fastify.listen({ port: 3000, host: '0.0.0.0' });
    console.log('Server running at http://localhost:3000');
  } catch (err) {
    fastify.log.error(err);
    process.exit(1);
  }
}

start();
```

#### 2. Node.js with node-postgres

```javascript
const { Pool } = require('pg');

const pool = new Pool({
  host: 'localhost',
  port: 6432, // PgBouncer port
  database: 'your_database',
  user: 'your_username',
  password: 'your_password',
});

// Example query
async function testConnection() {
  try {
    const result = await pool.query('SELECT NOW()');
    console.log('Connection successful:', result.rows[0]);
  } catch (err) {
    console.error('Connection error:', err);
  }
}
```

### Running the Test Application

1. **Install Dependencies**

```bash
# Using npm
npm install @fastify/postgres fastify pg

# Using pnpm
pnpm install @fastify/postgres fastify pg

# Using yarn
yarn add @fastify/postgres fastify pg
```

2. **Start the Application**

```bash
# Navigate to the test app directory
cd testapp

# Run the application
node app.js
```

3. **Test the Endpoints**

```bash
# Test database connection
curl http://localhost:3000/test

# Health check
curl http://localhost:3000/health
```

### Connection Pooling Best Practices

1. **PgBouncer Settings**

   - Use transaction pooling mode for best performance
   - Configure appropriate pool sizes based on your application needs
   - Monitor connection usage with PgBouncer admin console

2. **Application Settings**

   - Always use connection pooling in your applications
   - Set appropriate timeout values
   - Implement retry logic for connection failures
   - Close connections properly when not in use

3. **Monitoring Connections**

```bash
# Check active connections
PGPASSWORD=your_password psql -h localhost -p 6432 -U your_username pgbouncer -c "SHOW CLIENTS;"

# Check pool status
PGPASSWORD=your_password psql -h localhost -p 6432 -U your_username pgbouncer -c "SHOW POOLS;"

# Check server stats
PGPASSWORD=your_password psql -h localhost -p 6432 -U your_username pgbouncer -c "SHOW STATS;"
```

### Troubleshooting Database Connections

1. **Connection Refused**

```bash
# Check if PgBouncer is running
docker compose ps pgbouncer

# Check PgBouncer logs
docker compose logs pgbouncer
```

2. **Too Many Connections**

```bash
# Check current connections
PGPASSWORD=your_password psql -h localhost -p 6432 -U your_username pgbouncer -c "SHOW CLIENTS;"

# Review pool limits
PGPASSWORD=your_password psql -h localhost -p 6432 -U your_username pgbouncer -c "SHOW CONFIG;"
```

3. **Slow Queries**

```bash
# Check query statistics
PGPASSWORD=your_password psql -h localhost -p 5432 -U your_username -d your_database -c "
SELECT query, calls, total_time, rows
FROM pg_stat_statements
ORDER BY total_time DESC
LIMIT 5;"
```

## Troubleshooting

### Common Issues

1. **Connection Refused**

   ```bash
   # Check if containers are running
   docker compose ps

   # Check logs
   docker compose logs postgres
   docker compose logs pgbouncer
   ```

2. **Backup Failures**

   ```bash
   # Check backup logs
   docker compose logs backup

   # Verify AWS credentials
   docker compose exec backup aws s3 ls
   ```

3. **Permission Issues**
   ```bash
   # Re-run permissions script
   ./set-permissions.sh
   ```

## Maintenance

### Regular Tasks

1. Monitor disk usage

   ```bash
   docker system df
   ```

2. Check backup status daily

   ```bash
   docker compose exec backup wal-g backup-list
   ```

3. Review logs weekly
   ```bash
   docker compose logs --since=7d > weekly_logs.txt
   ```

## Security Notes

1. Never commit `.env` file to version control
2. Regularly rotate passwords and AWS credentials
3. Use strong passwords for database users
4. Keep Docker and all components updated
5. Monitor logs for suspicious activity

## Support

For issues or questions:

1. Check the troubleshooting section
2. Review logs for specific errors
3. Create an issue in the repository
4. Contact: SAKAR.SR
5. Visit: [easy-cloud.in](https://easy-cloud.in)

## Updates and Maintenance

### Updating the System

```bash
# Pull latest changes
git pull origin main

# Rebuild containers
docker compose build --no-cache

# Restart services
docker compose down
docker compose up -d
```

### Backup Verification

```bash
# Verify backup integrity
docker compose exec backup wal-g backup-list --detail

# Check S3 storage
docker compose exec backup aws s3 ls ${S3_BUCKET} --recursive
```
