#!/usr/bin/env bash
# Orchestrates the base-stack scripts in order. Run this before anything in
# harbour-books-security/ — that folder assumes this stack already exists.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "== Harbour Books base stack provisioning =="
echo "This creates a VPC, subnets, security groups, an IAM role, an RDS MySQL instance,"
echo "and an EC2 instance running Nginx+Flask via Docker Compose — real, billable resources."
read -rp "Have you edited config.sh with your real region/CIDRs/IP? [y/N] " CONFIRM
[ "$CONFIRM" = "y" ] || { echo "Edit config.sh first, then re-run."; exit 0; }

"$SCRIPT_DIR/01-create-vpc-networking.sh"
"$SCRIPT_DIR/02-create-security-groups.sh"
"$SCRIPT_DIR/03-create-iam-role.sh"
"$SCRIPT_DIR/04-create-rds.sh"
"$SCRIPT_DIR/05-launch-ec2.sh"

echo
echo "Base stack is up. Next: run harbour-books-security/scripts/run-all.sh to add"
echo "monitoring, restrict ec2-sg egress, and migrate the DB password to Secrets Manager."
