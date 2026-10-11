#!/usr/bin/env bash
# Creates ec2-sg (Nginx+Flask instance) and rds-sg (MySQL), matching the story's
# starting state: ec2-sg's egress is left at the AWS default allow-all rule on purpose —
# harbour-books-security/scripts/04-restrict-ec2-sg-egress.sh is what narrows it later.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../config.sh"
source "$SCRIPT_DIR/../lib.sh"

VPC_ID="${VPC_ID:-$(state_read vpc-id.txt)}"
[ -n "$VPC_ID" ] || { echo "No VPC ID found. Run 01-create-vpc-networking.sh first." >&2; exit 1; }

echo "Creating ec2-sg..."
EC2_SG_ID=$(aws ec2 create-security-group --group-name ec2-sg \
  --description "harbour-books EC2 (Nginx+Flask) security group" \
  --vpc-id "$VPC_ID" --region "$AWS_REGION" --query 'GroupId' --output text)
aws ec2 create-tags --resources "$EC2_SG_ID" --tags Key=Name,Value=ec2-sg "${TAGS[@]}" --region "$AWS_REGION"

aws ec2 authorize-security-group-ingress --group-id "$EC2_SG_ID" --protocol tcp --port 80 \
  --cidr 0.0.0.0/0 --region "$AWS_REGION" >/dev/null

if [ -n "${MY_IP_CIDR:-}" ] && [ "$MY_IP_CIDR" != "REPLACEME/32" ]; then
  aws ec2 authorize-security-group-ingress --group-id "$EC2_SG_ID" --protocol tcp --port 22 \
    --cidr "$MY_IP_CIDR" --region "$AWS_REGION" >/dev/null
else
  echo "MY_IP_CIDR not set — skipping SSH ingress (use SSM Session Manager to reach the box instead)."
fi
state_write ec2-sg-id.txt "$EC2_SG_ID"

echo "Creating rds-sg..."
RDS_SG_ID=$(aws ec2 create-security-group --group-name rds-sg \
  --description "harbour-books RDS MySQL security group" \
  --vpc-id "$VPC_ID" --region "$AWS_REGION" --query 'GroupId' --output text)
aws ec2 create-tags --resources "$RDS_SG_ID" --tags Key=Name,Value=rds-sg "${TAGS[@]}" --region "$AWS_REGION"

aws ec2 authorize-security-group-ingress --group-id "$RDS_SG_ID" --protocol tcp --port 3306 \
  --source-group "$EC2_SG_ID" --region "$AWS_REGION" >/dev/null
state_write rds-sg-id.txt "$RDS_SG_ID"

echo
echo "ec2-sg: $EC2_SG_ID (egress still allow-all — this is the gap to remediate)"
echo "rds-sg: $RDS_SG_ID (ingress 3306 from ec2-sg only, no public access)"
