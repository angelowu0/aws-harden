#!/usr/bin/env bash
# Launches the public EC2 instance: installs Docker + Compose via user-data, ships the
# app/ files up, and starts Nginx+Flask. Intentionally writes the DB password into a
# plaintext .env on the box (the story's starting gap) — harbour-books-security's
# startup-fetch-secret.sh replaces that file's contents from Secrets Manager later.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../config.sh"
source "$SCRIPT_DIR/../lib.sh"

EC2_SG_ID="${EC2_SG_ID:-$(state_read ec2-sg-id.txt)}"
PUBLIC_SUBNET_IDS_CSV="${PUBLIC_SUBNET_IDS_CSV:-$(state_read public-subnet-ids.txt)}"
PROFILE_NAME="${PROFILE_NAME:-$(state_read ec2-profile-name.txt)}"
RDS_ENDPOINT="${RDS_ENDPOINT:-$(state_read rds-endpoint.txt)}"
DB_PASSWORD="${DB_PASSWORD:-$(state_read rds-initial-password.txt)}"

[ -n "$EC2_SG_ID" ] || { echo "No ec2-sg ID found. Run 02-create-security-groups.sh first." >&2; exit 1; }
[ -n "$PUBLIC_SUBNET_IDS_CSV" ] || { echo "No public subnet IDs found. Run 01-create-vpc-networking.sh first." >&2; exit 1; }
[ -n "$PROFILE_NAME" ] || { echo "No instance profile found. Run 03-create-iam-role.sh first." >&2; exit 1; }
[ -n "$RDS_ENDPOINT" ] || { echo "No RDS endpoint found. Run 04-create-rds.sh first." >&2; exit 1; }
[ -n "$DB_PASSWORD" ] || { echo "No DB password found. Run 04-create-rds.sh first." >&2; exit 1; }

PUBLIC_SUBNET_ID="${PUBLIC_SUBNET_IDS_CSV%%,*}"
APP_DIR="$SCRIPT_DIR/../app"

echo "Looking up latest Amazon Linux 2023 AMI in region [$AWS_REGION]..."
AMI_ID=$(aws ssm get-parameter \
  --name /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 \
  --region "$AWS_REGION" --query 'Parameter.Value' --output text)

b64() { base64 -w0 "$1" 2>/dev/null || base64 "$1" | tr -d '\n'; }

APP_PY_B64=$(b64 "$APP_DIR/app.py")
REQUIREMENTS_B64=$(b64 "$APP_DIR/requirements.txt")
DOCKERFILE_B64=$(b64 "$APP_DIR/Dockerfile")
NGINX_CONF_B64=$(b64 "$APP_DIR/nginx.conf")
COMPOSE_B64=$(b64 "$APP_DIR/docker-compose.yml")

USER_DATA_FILE="$(mktemp)"
cat > "$USER_DATA_FILE" <<USERDATA
#!/bin/bash
set -euo pipefail
dnf install -y docker
systemctl enable --now docker
curl -SL https://github.com/docker/compose/releases/latest/download/docker-compose-linux-x86_64 \\
  -o /usr/libexec/docker/cli-plugins/docker-compose
chmod +x /usr/libexec/docker/cli-plugins/docker-compose

mkdir -p /opt/harbour-books
cd /opt/harbour-books

echo "$APP_PY_B64" | base64 -d > app.py
echo "$REQUIREMENTS_B64" | base64 -d > requirements.txt
echo "$DOCKERFILE_B64" | base64 -d > Dockerfile
echo "$NGINX_CONF_B64" | base64 -d > nginx.conf
echo "$COMPOSE_B64" | base64 -d > docker-compose.yml

# --- INSECURE (intentional starting state): DB password dropped in a plaintext .env ---
cat > .env <<ENV
AWS_REGION=${AWS_REGION}
DB_HOST=${RDS_ENDPOINT}
DB_USER=${RDS_MASTER_USERNAME}
DB_PASSWORD=${DB_PASSWORD}
DB_NAME=${DB_NAME}
ENV
chmod 600 .env
# --- end insecure block; harbour-books-security/scripts/startup-fetch-secret.sh replaces this later ---

docker compose up -d --build
USERDATA

EXTRA_ARGS=()
if [ -n "${KEY_PAIR_NAME:-}" ] && [ "$KEY_PAIR_NAME" != "REPLACEME" ]; then
  EXTRA_ARGS+=(--key-name "$KEY_PAIR_NAME")
fi

# On Windows/Git Bash, MSYS_NO_PATHCONV (set in lib.sh) stops POSIX-looking argument
# values like SSM parameter names from being corrupted — but it also means a real POSIX
# temp-file path (from mktemp) won't get auto-translated for the native aws.exe to read.
# Convert it to a Windows path explicitly here, where a real file path is actually wanted.
if command -v cygpath >/dev/null 2>&1; then
  USER_DATA_FILE_FOR_CLI="$(cygpath -w "$USER_DATA_FILE")"
else
  USER_DATA_FILE_FOR_CLI="$USER_DATA_FILE"
fi

echo "Launching EC2 instance..."
INSTANCE_ID=$(aws ec2 run-instances \
  --image-id "$AMI_ID" \
  --instance-type "$EC2_INSTANCE_TYPE" \
  --subnet-id "$PUBLIC_SUBNET_ID" \
  --security-group-ids "$EC2_SG_ID" \
  --iam-instance-profile Name="$PROFILE_NAME" \
  --associate-public-ip-address \
  --user-data "file://$USER_DATA_FILE_FOR_CLI" \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=harbour-books-app},{Key=Project,Value=${PROJECT_TAG}},{Key=Owner,Value=${OWNER_TAG}},{Key=Environment,Value=${ENVIRONMENT_TAG}}]" \
  --region "$AWS_REGION" \
  "${EXTRA_ARGS[@]}" \
  --query 'Instances[0].InstanceId' --output text)

rm -f "$USER_DATA_FILE"
state_write ec2-instance-id.txt "$INSTANCE_ID"

echo "Waiting for instance to enter 'running' state..."
aws ec2 wait instance-running --instance-ids "$INSTANCE_ID" --region "$AWS_REGION"

PUBLIC_IP=$(aws ec2 describe-instances --instance-ids "$INSTANCE_ID" --region "$AWS_REGION" \
  --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)

echo
echo "Instance ID: $INSTANCE_ID"
echo "Public IP:   $PUBLIC_IP"
echo "Give it a few minutes to finish installing Docker and starting the app, then check: http://$PUBLIC_IP/"
