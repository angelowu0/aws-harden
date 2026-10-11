#!/usr/bin/env bash
# CloudWatch alarm: EC2 CPUUtilization > 70% for 5 consecutive 1-minute periods -> SNS.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../config.sh"
source "$SCRIPT_DIR/../lib.sh"

TOPIC_ARN="${TOPIC_ARN:-$(state_read sns-topic-arn.txt)}"
[ -n "$TOPIC_ARN" ] || { echo "No SNS topic ARN found. Run 01-create-sns-topic.sh first." >&2; exit 1; }

ALARM_NAME="harbour-books-ec2-cpu-high"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

aws cloudwatch put-metric-alarm \
  --alarm-name "$ALARM_NAME" \
  --alarm-description "CPUUtilization > 70% for 5 consecutive minutes on the harbour-books EC2 instance" \
  --namespace "AWS/EC2" \
  --metric-name "CPUUtilization" \
  --statistic Average \
  --period 60 \
  --evaluation-periods 5 \
  --threshold 70 \
  --comparison-operator GreaterThanThreshold \
  --dimensions Name=InstanceId,Value="$EC2_INSTANCE_ID" \
  --alarm-actions "$TOPIC_ARN" \
  --ok-actions "$TOPIC_ARN" \
  --treat-missing-data notBreaching \
  --region "$AWS_REGION"

aws cloudwatch tag-resource \
  --resource-arn "arn:aws:cloudwatch:${AWS_REGION}:${ACCOUNT_ID}:alarm:${ALARM_NAME}" \
  --tags "${TAGS[@]}" \
  --region "$AWS_REGION"

echo "Created alarm: $ALARM_NAME"
