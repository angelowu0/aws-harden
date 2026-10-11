#!/usr/bin/env bash
# Generates a new RDS master password, stores it in Secrets Manager, and rotates RDS to use it.
# Replaces the plaintext password that currently lives in a shell variable on the EC2 box.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../config.sh"
source "$SCRIPT_DIR/../lib.sh"
require_cmd openssl

NEW_PASSWORD=$(openssl rand -base64 32 | tr -dc 'A-Za-z0-9' | head -c 32)

SECRET_STRING=$(cat <<EOF
{"username":"${RDS_MASTER_USERNAME}","password":"${NEW_PASSWORD}"}
EOF
)

echo "Creating secret ${SECRET_NAME} in Secrets Manager..."
SECRET_ARN=$(aws secretsmanager create-secret \
  --name "$SECRET_NAME" \
  --description "Master password for the harbour-books RDS MySQL instance" \
  --secret-string "$SECRET_STRING" \
  --tags "${TAGS[@]}" \
  --region "$AWS_REGION" \
  --query ARN --output text)

state_write secret-arn.txt "$SECRET_ARN"

echo "Rotating RDS master password to match the secret..."
aws rds modify-db-instance \
  --db-instance-identifier "$RDS_INSTANCE_ID" \
  --master-user-password "$NEW_PASSWORD" \
  --apply-immediately \
  --region "$AWS_REGION" >/dev/null

echo
echo "Secret ARN: $SECRET_ARN"
echo
echo "NEXT STEPS (manual):"
echo "  1. Wait for RDS to finish applying the change:"
echo "     aws rds describe-db-instances --db-instance-identifier $RDS_INSTANCE_ID --region $AWS_REGION --query 'DBInstances[0].DBInstanceStatus'"
echo "  2. On the EC2 box, remove the old plaintext password: unset the shell variable and delete it from any"
echo "     .bashrc / .env / docker-compose env_file where it was previously set."
echo "  3. Run 06-create-iam-secret-policy.sh to grant the instance role read access to this secret."
echo "  4. Use scripts/startup-fetch-secret.sh (run ON the instance) to populate .env from Secrets Manager going forward."
