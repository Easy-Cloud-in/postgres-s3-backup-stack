#!/bin/bash
set -e

echo "=== WAL-G Backup Verification ==="

# Run commands as postgres user using gosu
gosu postgres bash <<'EOF'
# Check S3 path
echo -e "\nChecking S3 backup location..."
aws s3 ls "${WALG_S3_PREFIX}/basebackups_005/" || {
    echo "No basebackups found in S3"
    exit 1
}

# List all backups with sizes
echo -e "\nListing all backups in S3:"
aws s3 ls "${WALG_S3_PREFIX}/basebackups_005/" --recursive --human-readable

# Get total backup size
echo -e "\nCalculating total backup size:"
aws s3 ls "${WALG_S3_PREFIX}" --recursive --summarize --human-readable | grep "Total Size"
EOF
