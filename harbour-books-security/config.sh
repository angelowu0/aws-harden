#!/usr/bin/env bash
# Central config for the harbour-books security remediation scripts.
# Fill in every REPLACEME below with real values from the class AWS account
# before running anything in scripts/. All other scripts `source` this file.
#
# Find the values with:
#   aws ec2 describe-vpcs --filters Name=tag:Name,Values=harbour-books-vpc
#   aws ec2 describe-instances --filters Name=tag:Name,Values=<your ec2 name tag>
#   aws ec2 describe-security-groups --filters Name=group-name,Values=ec2-sg,rds-sg
#   aws rds describe-db-instances
#   aws iam list-roles   # the role behind the EC2 instance profile

export AWS_REGION="ap-southeast-2"

# Tags applied to every new/updated resource (per acceptance criteria)
export PROJECT_TAG="harbour-books"
export OWNER_TAG="Angelo Wu"
export ENVIRONMENT_TAG="dev"

# Existing class-stack resources
export VPC_ID="vpc-060d1e7c6f1c2ee58"                   # harbour-books-vpc
export EC2_INSTANCE_ID="i-0a0a1ccd7794e237d"            # public EC2 (Nginx + Flask via Docker Compose)
export EC2_SG_ID="sg-0d1169f68662078e8"                 # ec2-sg
export RDS_SG_ID="sg-050588163f55d65e0"                 # rds-sg
export RDS_INSTANCE_ID="harbour-books-db"               # RDS MySQL instance identifier
export RDS_MASTER_USERNAME="admin"                      # current RDS master username
export EC2_INSTANCE_ROLE_NAME="harbour-books-ec2-role"  # IAM role behind the EC2 instance profile

# Where alarm notifications go
export NOTIFICATION_EMAIL="angelowu0@gmail.com"

# Names for the new resources this remediation creates
export SNS_TOPIC_NAME="harbour-books-alerts"
export SECRET_NAME="harbour-books/rds/master-password"
export LOG_GROUP_NAME="/harbour-books/flask-app"        # bonus: ERROR log metric filter
