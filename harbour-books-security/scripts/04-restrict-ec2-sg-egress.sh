#!/usr/bin/env bash
# Narrows ec2-sg egress from allow-all down to: TCP 443 (image pulls) and TCP 3306 to rds-sg.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../config.sh"
source "$SCRIPT_DIR/../lib.sh"
require_cmd jq

echo "Current egress rules on $EC2_SG_ID:"
aws ec2 describe-security-groups --group-ids "$EC2_SG_ID" --region "$AWS_REGION" \
  --query 'SecurityGroups[0].IpPermissionsEgress' --output json

EGRESS_JSON=$(aws ec2 describe-security-groups --group-ids "$EC2_SG_ID" --region "$AWS_REGION" \
  --query 'SecurityGroups[0].IpPermissionsEgress' --output json)

if [ "$EGRESS_JSON" != "[]" ]; then
  echo "Revoking existing egress rule(s)..."
  # Strip Description fields — revoke matching is picky about them and they're not
  # meaningful for identifying the rule to remove.
  EGRESS_CLEAN=$(echo "$EGRESS_JSON" | jq '[.[] | del(.IpRanges[]?.Description, .Ipv6Ranges[]?.Description, .UserIdGroupPairs[]?.Description, .PrefixListIds[]?.Description)]')
  aws ec2 revoke-security-group-egress \
    --group-id "$EC2_SG_ID" \
    --ip-permissions "$EGRESS_CLEAN" \
    --region "$AWS_REGION"
fi

echo "Authorizing HTTPS (443) egress to 0.0.0.0/0 for container image pulls..."
HTTPS_RULE=$(cat <<EOF
[
  {
    "IpProtocol": "tcp",
    "FromPort": 443,
    "ToPort": 443,
    "IpRanges": [{"CidrIp": "0.0.0.0/0", "Description": "HTTPS for container image pulls"}]
  }
]
EOF
)
aws ec2 authorize-security-group-egress \
  --group-id "$EC2_SG_ID" \
  --ip-permissions "$HTTPS_RULE" \
  --region "$AWS_REGION"

echo "Authorizing MySQL (3306) egress to rds-sg ($RDS_SG_ID)..."
MYSQL_RULE=$(cat <<EOF
[
  {
    "IpProtocol": "tcp",
    "FromPort": 3306,
    "ToPort": 3306,
    "UserIdGroupPairs": [{"GroupId": "${RDS_SG_ID}", "Description": "MySQL to rds-sg"}]
  }
]
EOF
)
aws ec2 authorize-security-group-egress \
  --group-id "$EC2_SG_ID" \
  --ip-permissions "$MYSQL_RULE" \
  --region "$AWS_REGION"

aws ec2 create-tags --resources "$EC2_SG_ID" --tags "${TAGS[@]}" --region "$AWS_REGION"

echo
echo "New egress rules on $EC2_SG_ID:"
aws ec2 describe-security-groups --group-ids "$EC2_SG_ID" --region "$AWS_REGION" \
  --query 'SecurityGroups[0].IpPermissionsEgress' --output table
