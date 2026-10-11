#!/usr/bin/env bash
# Tears down everything this folder created, in reverse dependency order, using the IDs
# cached in scripts/.state/. Run harbour-books-security/scripts/teardown.sh FIRST if you
# ran that stack too (it depends on the EC2 role and RDS instance created here).
#
# NOTE: deletes the RDS instance WITHOUT a final snapshot (--skip-final-snapshot) — this
# is a class exercise, not production. Remove that flag if you want a snapshot kept.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../config.sh"
source "$SCRIPT_DIR/../lib.sh"

echo "This will DELETE the harbour-books base stack (EC2, RDS, IAM role, security groups, VPC)."
read -rp "Type 'delete' to confirm: " CONFIRM
[ "$CONFIRM" = "delete" ] || { echo "Aborted."; exit 0; }

INSTANCE_ID="$(state_read ec2-instance-id.txt)"
if [ -n "$INSTANCE_ID" ]; then
  echo "Terminating EC2 instance $INSTANCE_ID..."
  aws ec2 terminate-instances --instance-ids "$INSTANCE_ID" --region "$AWS_REGION" >/dev/null
  aws ec2 wait instance-terminated --instance-ids "$INSTANCE_ID" --region "$AWS_REGION"
fi

if aws rds describe-db-instances --db-instance-identifier "$RDS_INSTANCE_ID" --region "$AWS_REGION" >/dev/null 2>&1; then
  echo "Deleting RDS instance $RDS_INSTANCE_ID (no final snapshot)..."
  aws rds delete-db-instance --db-instance-identifier "$RDS_INSTANCE_ID" \
    --skip-final-snapshot --region "$AWS_REGION" >/dev/null
  aws rds wait db-instance-deleted --db-instance-identifier "$RDS_INSTANCE_ID" --region "$AWS_REGION"
fi

DB_SUBNET_GROUP_NAME="harbour-books-db-subnet-group"
aws rds delete-db-subnet-group --db-subnet-group-name "$DB_SUBNET_GROUP_NAME" --region "$AWS_REGION" 2>/dev/null || true

ROLE_NAME="$(state_read ec2-role-name.txt)"
PROFILE_NAME="$(state_read ec2-profile-name.txt)"
if [ -n "$ROLE_NAME" ]; then
  echo "Cleaning up IAM role $ROLE_NAME..."
  for POLICY_ARN in $(aws iam list-attached-role-policies --role-name "$ROLE_NAME" \
      --query 'AttachedPolicies[].PolicyArn' --output text); do
    aws iam detach-role-policy --role-name "$ROLE_NAME" --policy-arn "$POLICY_ARN"
  done
  [ -n "$PROFILE_NAME" ] && aws iam remove-role-from-instance-profile \
    --instance-profile-name "$PROFILE_NAME" --role-name "$ROLE_NAME" 2>/dev/null || true
  [ -n "$PROFILE_NAME" ] && aws iam delete-instance-profile --instance-profile-name "$PROFILE_NAME" 2>/dev/null || true
  aws iam delete-role --role-name "$ROLE_NAME" 2>/dev/null || true
fi

EC2_SG_ID="$(state_read ec2-sg-id.txt)"
RDS_SG_ID="$(state_read rds-sg-id.txt)"
# rds-sg must go first — ec2-sg is referenced by rds-sg's ingress rule.
[ -n "$RDS_SG_ID" ] && aws ec2 delete-security-group --group-id "$RDS_SG_ID" --region "$AWS_REGION" 2>/dev/null || true
[ -n "$EC2_SG_ID" ] && aws ec2 delete-security-group --group-id "$EC2_SG_ID" --region "$AWS_REGION" 2>/dev/null || true

PUBLIC_SUBNET_IDS_CSV="$(state_read public-subnet-ids.txt)"
PRIVATE_SUBNET_IDS_CSV="$(state_read private-subnet-ids.txt)"
IFS=',' read -r -a ALL_SUBNET_IDS <<< "${PUBLIC_SUBNET_IDS_CSV},${PRIVATE_SUBNET_IDS_CSV}"
for SUBNET_ID in "${ALL_SUBNET_IDS[@]}"; do
  [ -n "$SUBNET_ID" ] && aws ec2 delete-subnet --subnet-id "$SUBNET_ID" --region "$AWS_REGION" 2>/dev/null || true
done

PUBLIC_RT_ID="$(state_read public-rt-id.txt)"
[ -n "$PUBLIC_RT_ID" ] && aws ec2 delete-route-table --route-table-id "$PUBLIC_RT_ID" --region "$AWS_REGION" 2>/dev/null || true

IGW_ID="$(state_read igw-id.txt)"
VPC_ID="$(state_read vpc-id.txt)"
if [ -n "$IGW_ID" ] && [ -n "$VPC_ID" ]; then
  aws ec2 detach-internet-gateway --internet-gateway-id "$IGW_ID" --vpc-id "$VPC_ID" --region "$AWS_REGION" 2>/dev/null || true
  aws ec2 delete-internet-gateway --internet-gateway-id "$IGW_ID" --region "$AWS_REGION" 2>/dev/null || true
fi
[ -n "$VPC_ID" ] && aws ec2 delete-vpc --vpc-id "$VPC_ID" --region "$AWS_REGION" 2>/dev/null || true

rm -rf "$SCRIPT_DIR/.state"
echo "Teardown complete."
