#!/bin/bash
# Clean up orphaned EBS volumes from a deleted EKS cluster
# Usage: ./cleanup-ebs-volumes.sh <aws-profile> <cluster-name>

set -e

AWS_PROFILE="${1:-default}"
CLUSTER_NAME="${2:-obs-lgtm-demo}"

echo "🔍 Checking for orphaned EBS volumes from cluster: $CLUSTER_NAME"

# Find volumes tagged with the cluster name
VOLUME_IDS=$(aws ec2 describe-volumes \
  --profile "$AWS_PROFILE" \
  --filters "Name=tag:kubernetes.io/cluster/$CLUSTER_NAME,Values=owned" \
  --query 'Volumes[?State==`available`].VolumeId' \
  --output text 2>/dev/null || echo "")

if [ -z "$VOLUME_IDS" ]; then
  echo "  ℹ️  No orphaned EBS volumes found"
  exit 0
fi

echo "  🗑️  Found orphaned EBS volumes:"
DELETED_COUNT=0
FAILED_COUNT=0

for volume_id in $VOLUME_IDS; do
  echo "    - Deleting volume: $volume_id"
  if aws ec2 delete-volume \
    --volume-id "$volume_id" \
    --profile "$AWS_PROFILE" 2>/dev/null; then
    ((DELETED_COUNT++))
  else
    echo "      ⚠️  Failed to delete $volume_id (may be in use or protected)"
    ((FAILED_COUNT++))
  fi
done

echo ""
echo "  ✅ EBS volume cleanup complete"
echo "     Deleted: $DELETED_COUNT volume(s)"
if [ $FAILED_COUNT -gt 0 ]; then
  echo "     Failed: $FAILED_COUNT volume(s)"
fi
