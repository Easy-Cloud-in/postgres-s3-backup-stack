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
if [ -z "$S3_BUCKET" ] || [ -z "$CLIENT_NAME" ]; then
    log "Error: S3_BUCKET and CLIENT_NAME environment variables must be set"
    exit 1
fi

# Create the lifecycle policy JSON file in the current directory
POLICY_FILE="lifecycle-policy.json"
trap 'rm -f "$POLICY_FILE"' EXIT

# Get existing lifecycle rules to preserve other client rules
EXISTING_RULES=$(aws_docker s3api get-bucket-lifecycle-configuration --bucket "${S3_BUCKET}" 2>/dev/null || echo '{"Rules": []}')

# Create the policy file with client-specific prefix
cat > "$POLICY_FILE" <<EOF
{
    "Rules": [
        {
            "ID": "Delete old backups - ${CLIENT_NAME}",
            "Status": "Enabled",
            "Filter": {
                "Prefix": "${CLIENT_NAME}/"
            },
            "Expiration": {
                "Days": 30
            }
        }
        $(echo "$EXISTING_RULES" | jq -r '.Rules[] | select(.Filter.Prefix != "'${CLIENT_NAME}'/") | "," + tostring')
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
log "Successfully applied lifecycle policy to bucket: ${S3_BUCKET} for client: ${CLIENT_NAME}"
