#!/bin/bash

echo "=== AWS Configuration Debug ==="
echo "Checking AWS credentials..."
gosu postgres bash <<EOF
aws configure list
echo ""
echo "Testing S3 access..."
aws s3 ls "s3://${S3_BUCKET}"
echo ""
echo "Testing WAL-G configuration..."
echo "WALG_S3_PREFIX: ${WALG_S3_PREFIX}"
wal-g --version
EOF
