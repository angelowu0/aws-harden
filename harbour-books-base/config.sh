#!/usr/bin/env bash
# Central config for the harbour-books-base provisioning scripts (the "class stack"
# itself: VPC, subnets, security groups, IAM role, RDS MySQL, EC2 with Nginx+Flask).
# Fill in every REPLACEME below before running anything in scripts/.

export AWS_REGION="ap-southeast-2"

export PROJECT_TAG="harbour-books"
export OWNER_TAG="Angelo Wu"
export ENVIRONMENT_TAG="dev"

export VPC_CIDR="10.20.0.0/16"
PUBLIC_SUBNET_CIDRS=("10.20.0.0/24" "10.20.1.0/24")
PRIVATE_SUBNET_CIDRS=("10.20.10.0/24" "10.20.11.0/24")
AVAILABILITY_ZONES=("${AWS_REGION}a" "${AWS_REGION}b")

# Your IP for SSH access to the instance, e.g. "$(curl -s https://checkip.amazonaws.com)/32".
# Leave as REPLACEME to skip opening port 22 entirely (use SSM Session Manager instead —
# the IAM role created in 03-create-iam-role.sh already grants that).
export MY_IP_CIDR="REPLACEME/32"

# Existing EC2 key pair name for SSH, or leave as REPLACEME to launch without one (SSM only).
export KEY_PAIR_NAME="REPLACEME"

export EC2_INSTANCE_TYPE="t3.micro"
export RDS_INSTANCE_CLASS="db.t3.micro"
export RDS_INSTANCE_ID="harbour-books-db"
export RDS_MASTER_USERNAME="admin"
export DB_NAME="harbourbooks"
