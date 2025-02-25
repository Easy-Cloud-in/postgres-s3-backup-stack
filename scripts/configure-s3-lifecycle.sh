#!/bin/bash
set -e

# Function for logging
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

# Function to run AWS CLI commands using Docker
aws_docker() {
    docker run --rm \
        -v "$(pwd):/workspace" \
        -w /workspace \
        -e AWS_ACCESS_KEY_ID="$AWS_ACCESS_KEY_ID" \
        -e AWS_SECRET_ACCESS_KEY="$AWS_SECRET_ACCESS_KEY" \
        -e AWS_REGION="$AWS_REGION" \
        amazon/aws-cli "$@"
}

# Verify environment variables
if [ -z "$S3_BUCKET" ]; then
    log "Error: S3_BUCKET environment variable must be set"
    exit 1
fi

# Create the lifecycle policy JSON file in the current directory
POLICY_FILE="lifecycle-policy.json"
trap 'rm -f "$POLICY_FILE"' EXIT

# Create the policy file for the entire bucket (no client-specific prefix needed)
cat > "$POLICY_FILE" <<EOF
{
    "Rules": [
        {
            "ID": "Delete old backups",
            "Status": "Enabled",
            "Filter": {
                "Prefix": ""
            },
            "Expiration": {
                "Days": 30
            }
        }
    ]
}
EOF

# Apply the lifecycle policy
if ! aws_docker s3api put-bucket-lifecycle-configuration \
    --bucket "${S3_BUCKET}" \
    --lifecycle-configuration "file:///workspace/${POLICY_FILE}"; then
    log "Error: Failed to apply lifecycle policy to bucket: ${S3_BUCKET}"
    rm -f "$POLICY_FILE"
    exit 1
fi

rm -f "$POLICY_FILE"
log "Successfully applied lifecycle policy to bucket: ${S3_BUCKET}"
