#!/usr/bin/env bash
# Creates a least-privilege IAM policy (secretsmanager:GetSecretValue on exactly one
# secret ARN) and attaches it to the EC2 instance role.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../config.sh"
source "$SCRIPT_DIR/../lib.sh"

SECRET_ARN="${SECRET_ARN:-$(state_read secret-arn.txt)}"
[ -n "$SECRET_ARN" ] || { echo "No secret ARN found. Run 05-migrate-db-password.sh first." >&2; exit 1; }

POLICY_NAME="harbour-books-secret-read"

POLICY_DOC=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ReadHarbourBooksDbSecret",
      "Effect": "Allow",
      "Action": "secretsmanager:GetSecretValue",
      "Resource": "${SECRET_ARN}"
    }
  ]
}
EOF
)

echo "Creating IAM policy ${POLICY_NAME}..."
POLICY_ARN=$(aws iam create-policy \
  --policy-name "$POLICY_NAME" \
  --policy-document "$POLICY_DOC" \
  --tags "${TAGS[@]}" \
  --query Policy.Arn --output text)

state_write iam-policy-arn.txt "$POLICY_ARN"

echo "Attaching policy to role ${EC2_INSTANCE_ROLE_NAME}..."
aws iam attach-role-policy \
  --role-name "$EC2_INSTANCE_ROLE_NAME" \
  --policy-arn "$POLICY_ARN"

echo "Policy ARN: $POLICY_ARN"
echo "Attached to role: $EC2_INSTANCE_ROLE_NAME"
echo "Note: this grants GetSecretValue on that one secret only — no other secretsmanager actions, no wildcard resources."
