#!/bin/bash
# Empty S3 buckets including all versions and delete markers
# Usage: ./empty-s3-buckets.sh <aws-profile> [cluster-name]

set -e

AWS_PROFILE="${1:-default}"
CLUSTER_NAME="${2:-obs-lgtm-demo}"
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

delete_ebs_volumes() {
  echo ""
  echo "🔍 Checking for orphaned EBS volumes from cluster: $CLUSTER_NAME"

  # Find volumes tagged with the cluster name
  VOLUME_IDS=$(aws ec2 describe-volumes \
    --profile "$AWS_PROFILE" \
    --filters "Name=tag:kubernetes.io/cluster/$CLUSTER_NAME,Values=owned" \
    --query 'Volumes[?State==`available`].VolumeId' \
    --output text 2>/dev/null || echo "")

  if [ -z "$VOLUME_IDS" ]; then
    echo "  ℹ️  No orphaned EBS volumes found"
    return 0
  fi

  echo "  🗑️  Found orphaned EBS volumes:"
  for volume_id in $VOLUME_IDS; do
    echo "    - Deleting volume: $volume_id"
    aws ec2 delete-volume \
      --volume-id "$volume_id" \
      --profile "$AWS_PROFILE" 2>/dev/null || echo "      ⚠️  Failed to delete $volume_id (may be in use)"
  done

  echo "  ✅ EBS volume cleanup complete"
}

echo "Starting S3 bucket cleanup (profile: $AWS_PROFILE)..."

for bucket in "${BUCKETS[@]}"; do
  empty_bucket "$bucket"
done

echo "✅ All S3 buckets cleaned successfully!"

# Clean up EBS volumes
delete_ebs_volumes

echo ""
echo "✅ All AWS resources cleaned successfully!"
