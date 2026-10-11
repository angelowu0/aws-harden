#!/usr/bin/env bash
# Creates harbour-books-vpc: 2 public subnets (IGW route, for the EC2 instance) and
# 2 private subnets (no route to the internet, for RDS — a DB subnet group needs 2+ AZs).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../config.sh"
source "$SCRIPT_DIR/../lib.sh"

echo "Creating VPC ($VPC_CIDR)..."
VPC_ID=$(aws ec2 create-vpc --cidr-block "$VPC_CIDR" --region "$AWS_REGION" --query 'Vpc.VpcId' --output text)
aws ec2 create-tags --resources "$VPC_ID" --tags Key=Name,Value=harbour-books-vpc "${TAGS[@]}" --region "$AWS_REGION"
aws ec2 modify-vpc-attribute --vpc-id "$VPC_ID" --enable-dns-support '{"Value":true}' --region "$AWS_REGION"
aws ec2 modify-vpc-attribute --vpc-id "$VPC_ID" --enable-dns-hostnames '{"Value":true}' --region "$AWS_REGION"
state_write vpc-id.txt "$VPC_ID"

echo "Creating and attaching Internet Gateway..."
IGW_ID=$(aws ec2 create-internet-gateway --region "$AWS_REGION" --query 'InternetGateway.InternetGatewayId' --output text)
aws ec2 create-tags --resources "$IGW_ID" --tags Key=Name,Value=harbour-books-igw "${TAGS[@]}" --region "$AWS_REGION"
aws ec2 attach-internet-gateway --internet-gateway-id "$IGW_ID" --vpc-id "$VPC_ID" --region "$AWS_REGION"
state_write igw-id.txt "$IGW_ID"

echo "Creating public route table (0.0.0.0/0 -> IGW)..."
PUBLIC_RT_ID=$(aws ec2 create-route-table --vpc-id "$VPC_ID" --region "$AWS_REGION" --query 'RouteTable.RouteTableId' --output text)
aws ec2 create-tags --resources "$PUBLIC_RT_ID" --tags Key=Name,Value=harbour-books-public-rt "${TAGS[@]}" --region "$AWS_REGION"
aws ec2 create-route --route-table-id "$PUBLIC_RT_ID" --destination-cidr-block 0.0.0.0/0 --gateway-id "$IGW_ID" --region "$AWS_REGION" >/dev/null
state_write public-rt-id.txt "$PUBLIC_RT_ID"

PUBLIC_SUBNET_IDS=()
for i in "${!PUBLIC_SUBNET_CIDRS[@]}"; do
  AZ="${AVAILABILITY_ZONES[$i]}"
  CIDR="${PUBLIC_SUBNET_CIDRS[$i]}"
  echo "Creating public subnet $CIDR in $AZ..."
  SUBNET_ID=$(aws ec2 create-subnet --vpc-id "$VPC_ID" --cidr-block "$CIDR" --availability-zone "$AZ" \
    --region "$AWS_REGION" --query 'Subnet.SubnetId' --output text)
  aws ec2 create-tags --resources "$SUBNET_ID" --tags Key=Name,Value="harbour-books-public-$i" "${TAGS[@]}" --region "$AWS_REGION"
  aws ec2 modify-subnet-attribute --subnet-id "$SUBNET_ID" --map-public-ip-on-launch --region "$AWS_REGION"
  aws ec2 associate-route-table --subnet-id "$SUBNET_ID" --route-table-id "$PUBLIC_RT_ID" --region "$AWS_REGION" >/dev/null
  PUBLIC_SUBNET_IDS+=("$SUBNET_ID")
done
state_write public-subnet-ids.txt "$(IFS=,; echo "${PUBLIC_SUBNET_IDS[*]}")"

PRIVATE_SUBNET_IDS=()
for i in "${!PRIVATE_SUBNET_CIDRS[@]}"; do
  AZ="${AVAILABILITY_ZONES[$i]}"
  CIDR="${PRIVATE_SUBNET_CIDRS[$i]}"
  echo "Creating private subnet $CIDR in $AZ..."
  SUBNET_ID=$(aws ec2 create-subnet --vpc-id "$VPC_ID" --cidr-block "$CIDR" --availability-zone "$AZ" \
    --region "$AWS_REGION" --query 'Subnet.SubnetId' --output text)
  aws ec2 create-tags --resources "$SUBNET_ID" --tags Key=Name,Value="harbour-books-private-$i" "${TAGS[@]}" --region "$AWS_REGION"
  PRIVATE_SUBNET_IDS+=("$SUBNET_ID")
done
state_write private-subnet-ids.txt "$(IFS=,; echo "${PRIVATE_SUBNET_IDS[*]}")"
# Private subnets stay on the VPC's default main route table (local traffic only) —
# RDS doesn't need outbound internet access, so no NAT gateway is provisioned.

echo
echo "VPC: $VPC_ID"
echo "Public subnets: ${PUBLIC_SUBNET_IDS[*]}"
echo "Private subnets: ${PRIVATE_SUBNET_IDS[*]}"
