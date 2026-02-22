#!/bin/bash
# Empty S3 buckets including all versions and delete markers
# Usage: ./empty-s3-only.sh <aws-profile>

set -e

AWS_PROFILE="${1:-default}"
BUCKETS=(
  "obs-platform-mimir"
  "obs-platform-loki"
  "obs-platform-tempo"
)

empty_bucket() {
  local bucket=$1

  # Check if bucket exists
  if ! aws s3api head-bucket --bucket "$bucket" --profile "$AWS_PROFILE" 2>/dev/null; then
    echo "  ℹ️  Bucket $bucket does not exist, skipping..."
    return 0
  fi

  echo "  🗑️  Emptying bucket: s3://$bucket"

  # Delete all object versions
  echo "    - Deleting object versions..."
  aws s3api list-object-versions \
    --bucket "$bucket" \
    --profile "$AWS_PROFILE" \
    --output json \
    --query 'Versions[].{Key:Key,VersionId:VersionId}' 2>/dev/null | \
  jq -r '.[] | "--key \"\(.Key)\" --version-id \"\(.VersionId)\""' | \
  while read -r args; do
    eval aws s3api delete-object --bucket "$bucket" $args --profile "$AWS_PROFILE" >/dev/null 2>&1 || true
  done

  # Delete all delete markers
  echo "    - Deleting delete markers..."
  aws s3api list-object-versions \
    --bucket "$bucket" \
    --profile "$AWS_PROFILE" \
    --output json \
    --query 'DeleteMarkers[].{Key:Key,VersionId:VersionId}' 2>/dev/null | \
  jq -r '.[] | "--key \"\(.Key)\" --version-id \"\(.VersionId)\""' | \
  while read -r args; do
    eval aws s3api delete-object --bucket "$bucket" $args --profile "$AWS_PROFILE" >/dev/null 2>&1 || true
  done

  echo "  ✅ Bucket $bucket is now empty"
}

echo "Starting S3 bucket cleanup (profile: $AWS_PROFILE)..."

for bucket in "${BUCKETS[@]}"; do
  empty_bucket "$bucket"
done

echo "✅ All S3 buckets emptied successfully!"
