#!/usr/bin/env bash
# Creates the EC2 instance role + profile. Grants only SSM (so you can reach the box
# via Session Manager without opening SSH wider than necessary) — no Secrets Manager
# access yet. That gets added later by harbour-books-security/scripts/06-create-iam-secret-policy.sh,
# scoped to exactly one secret ARN.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../config.sh"
source "$SCRIPT_DIR/../lib.sh"

ROLE_NAME="harbour-books-ec2-role"
PROFILE_NAME="harbour-books-ec2-profile"

TRUST_POLICY=$(cat <<'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {"Service": "ec2.amazonaws.com"},
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
)

echo "Creating IAM role ${ROLE_NAME}..."
aws iam create-role --role-name "$ROLE_NAME" --assume-role-policy-document "$TRUST_POLICY" --tags "${TAGS[@]}" >/dev/null

aws iam attach-role-policy --role-name "$ROLE_NAME" \
  --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore

echo "Creating instance profile ${PROFILE_NAME}..."
aws iam create-instance-profile --instance-profile-name "$PROFILE_NAME" --tags "${TAGS[@]}" >/dev/null
aws iam add-role-to-instance-profile --instance-profile-name "$PROFILE_NAME" --role-name "$ROLE_NAME"

echo "Waiting for the instance profile to propagate (IAM eventual consistency)..."
sleep 15

state_write ec2-role-name.txt "$ROLE_NAME"
state_write ec2-profile-name.txt "$PROFILE_NAME"

echo
echo "Role: $ROLE_NAME"
echo "Instance profile: $PROFILE_NAME"
echo "No secretsmanager permissions yet — added later by harbour-books-security/scripts/06-create-iam-secret-policy.sh."
