#!/usr/bin/env bash
# Creates the DB subnet group (private subnets) and the RDS MySQL instance. Generates
# an initial master password here — 05-launch-ec2.sh drops this into a plaintext .env
# on the EC2 box, matching the story's starting gap. Migrate it out with
# harbour-books-security/scripts/05-migrate-db-password.sh once the stack is up.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../config.sh"
source "$SCRIPT_DIR/../lib.sh"
require_cmd openssl

RDS_SG_ID="${RDS_SG_ID:-$(state_read rds-sg-id.txt)}"
[ -n "$RDS_SG_ID" ] || { echo "No rds-sg ID found. Run 02-create-security-groups.sh first." >&2; exit 1; }

PRIVATE_SUBNET_IDS_CSV="${PRIVATE_SUBNET_IDS_CSV:-$(state_read private-subnet-ids.txt)}"
[ -n "$PRIVATE_SUBNET_IDS_CSV" ] || { echo "No private subnet IDs found. Run 01-create-vpc-networking.sh first." >&2; exit 1; }
IFS=',' read -r -a PRIVATE_SUBNET_IDS <<< "$PRIVATE_SUBNET_IDS_CSV"

DB_SUBNET_GROUP_NAME="harbour-books-db-subnet-group"
echo "Creating DB subnet group..."
aws rds create-db-subnet-group \
  --db-subnet-group-name "$DB_SUBNET_GROUP_NAME" \
  --db-subnet-group-description "harbour-books RDS subnet group (private subnets)" \
  --subnet-ids "${PRIVATE_SUBNET_IDS[@]}" \
  --tags "${TAGS[@]}" \
  --region "$AWS_REGION" >/dev/null

INITIAL_DB_PASSWORD=$(openssl rand -base64 24 | tr -dc 'A-Za-z0-9' | head -c 24)
state_write rds-initial-password.txt "$INITIAL_DB_PASSWORD"

echo "Creating RDS MySQL instance ${RDS_INSTANCE_ID} (this takes several minutes)..."
aws rds create-db-instance \
  --db-instance-identifier "$RDS_INSTANCE_ID" \
  --engine mysql \
  --db-instance-class "$RDS_INSTANCE_CLASS" \
  --allocated-storage 20 \
  --master-username "$RDS_MASTER_USERNAME" \
  --master-user-password "$INITIAL_DB_PASSWORD" \
  --db-name "$DB_NAME" \
  --vpc-security-group-ids "$RDS_SG_ID" \
  --db-subnet-group-name "$DB_SUBNET_GROUP_NAME" \
  --no-publicly-accessible \
  --no-multi-az \
  --backup-retention-period 1 \
  --tags "${TAGS[@]}" \
  --region "$AWS_REGION" >/dev/null

echo "Waiting for RDS instance to become available (typically 5-10 minutes)..."
aws rds wait db-instance-available --db-instance-identifier "$RDS_INSTANCE_ID" --region "$AWS_REGION"

RDS_ENDPOINT=$(aws rds describe-db-instances --db-instance-identifier "$RDS_INSTANCE_ID" \
  --region "$AWS_REGION" --query 'DBInstances[0].Endpoint.Address' --output text)
state_write rds-endpoint.txt "$RDS_ENDPOINT"

echo
echo "RDS endpoint: $RDS_ENDPOINT"
echo "Initial master password cached at scripts/.state/rds-initial-password.txt for 05-launch-ec2.sh to use."
echo "Delete that file once you've run the security remediation's password migration script."
