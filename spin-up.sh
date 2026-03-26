#!/bin/bash
# spin-up.sh — template version, safe to commit.
# Copy to spin-up.local.sh and fill in your own values before running.
#
# PREREQUISITES — run these to find/create the required IDs:
#
#   List subnets in your VPC:
#     aws ec2 describe-subnets --region us-east-1 --profile <profile> \
#       --filters "Name=vpc-id,Values=<vpc-id>" \
#       --query "Subnets[*].{SubnetId:SubnetId,AZ:AvailabilityZone,CIDR:CidrBlock}" \
#       --output table
#
#   List security groups:
#     aws ec2 describe-security-groups --region us-east-1 --profile <profile> \
#       --query "SecurityGroups[*].{GroupId:GroupId,Name:GroupName,VPC:VpcId}" \
#       --output table
#
#   Create a security group with HTTP (port 80) open:
#     SG_ID=$(aws ec2 create-security-group --region us-east-1 --profile <profile> \
#       --group-name "my-demo-sg" \
#       --description "Allow HTTP" \
#       --vpc-id <vpc-id> \
#       --query GroupId --output text)
#
#     aws ec2 authorize-security-group-ingress --region us-east-1 --profile <profile> \
#       --group-id "$SG_ID" \
#       --protocol tcp --port 80 --cidr 0.0.0.0/0

# Fetch the latest Ubuntu 24.04 LTS AMI in us-east-1
AMI_ID=$(aws ec2 describe-images \
  --region us-east-1 \
  --profile <profile> \
  --owners 099720109477 \
  --filters "Name=name,Values=ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*" \
            "Name=state,Values=available" \
  --query 'sort_by(Images, &CreationDate)[-1].ImageId' \
  --output text)

echo "Using AMI: $AMI_ID"

# Try each subnet/AZ in order until one succeeds (Spot capacity varies by AZ).
# Add one entry per subnet you want to try, with the AZ as a comment.
SUBNETS=(
  "subnet-XXXXXXXXXXXXXXXXX"  # us-east-1a
  "subnet-XXXXXXXXXXXXXXXXX"  # us-east-1b
)

SECURITY_GROUP="sg-XXXXXXXXXXXXXXXXX"
LAUNCHED=false

for SUBNET_ID in "${SUBNETS[@]}"; do
  echo "Trying subnet $SUBNET_ID..."
  INSTANCE_ID=$(aws ec2 run-instances \
    --region us-east-1 \
    --profile <profile> \
    --launch-template "LaunchTemplateName=<launch-template-name>,Version=\$Latest" \
    --image-id "$AMI_ID" \
    --network-interfaces "DeviceIndex=0,SubnetId=$SUBNET_ID,AssociatePublicIpAddress=true,Groups=$SECURITY_GROUP" \
    --query 'Instances[0].InstanceId' \
    --output text 2>&1)

  if [ $? -eq 0 ]; then
    echo "Launched instance: $INSTANCE_ID"
    LAUNCHED=true
    break
  elif echo "$INSTANCE_ID" | grep -q "InsufficientInstanceCapacity\|no Spot capacity"; then
    echo "No capacity in $SUBNET_ID, trying next..."
  else
    echo "$INSTANCE_ID" >&2
    exit 1
  fi
done

if [ "$LAUNCHED" = false ]; then
  echo "No Spot capacity available in any subnet." >&2
  exit 1
fi

echo "Waiting for instance to enter running state..."
aws ec2 wait instance-running \
  --region us-east-1 \
  --profile <profile> \
  --instance-ids "$INSTANCE_ID"

IP=$(aws ec2 describe-instances \
  --region us-east-1 \
  --profile <profile> \
  --instance-ids "$INSTANCE_ID" \
  --query 'Reservations[0].Instances[0].PublicIpAddress' \
  --output text)

echo "Instance ready - open: http://$IP"
