#!/usr/bin/env bash
# Creates the SNS topic that both CloudWatch alarms notify, and subscribes your email.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../config.sh"
source "$SCRIPT_DIR/../lib.sh"

echo "Creating SNS topic ${SNS_TOPIC_NAME}..."
TOPIC_ARN=$(aws sns create-topic \
  --name "$SNS_TOPIC_NAME" \
  --region "$AWS_REGION" \
  --query TopicArn --output text)

aws sns tag-resource --resource-arn "$TOPIC_ARN" --tags "${TAGS[@]}" --region "$AWS_REGION"

echo "Subscribing ${NOTIFICATION_EMAIL}..."
aws sns subscribe \
  --topic-arn "$TOPIC_ARN" \
  --protocol email \
  --notification-endpoint "$NOTIFICATION_EMAIL" \
  --region "$AWS_REGION" >/dev/null

state_write sns-topic-arn.txt "$TOPIC_ARN"

echo "SNS topic ARN: $TOPIC_ARN"
echo "Check ${NOTIFICATION_EMAIL} for a confirmation email — alarms will not deliver until you confirm the subscription."
