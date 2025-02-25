# Function to create S3 bucket and apply lifecycle policy
create_s3_structure() {
    local client_name=$1
    local region=$2
    local bucket_prefix=$3
    
    # Create bucket name based on client name
    local bucket_name="${bucket_prefix}-${client_name}"
    
    # Check if the bucket already exists
    if aws_docker s3api head-bucket --bucket "$bucket_name" 2>/dev/null; then
        log "Bucket '$bucket_name' already exists."
    else
        # Create the S3 bucket
        log "Creating bucket '$bucket_name'..."
        if ! aws_docker s3api create-bucket --bucket "$bucket_name" --region "$region" --create-bucket-configuration LocationConstraint="$region"; then
            log "Error: Failed to create bucket '$bucket_name'"
            exit 1
        fi
        log "Bucket '$bucket_name' created successfully."
    fi

    # Apply S3 lifecycle policy with exported variables
    log "Applying S3 lifecycle policy..."
    export S3_BUCKET="$bucket_name"
    export CLIENT_NAME="$client_name"
    export S3_BUCKET_PREFIX="$bucket_prefix"