# spin-up.ps1 — template version, safe to commit.
# Copy to spin-up.local.ps1 and fill in your own values before running.
#
# PREREQUISITES — run these to find/create the required IDs:
#
#   List subnets in your VPC:
#     aws ec2 describe-subnets --region us-east-1 --profile <profile> `
#       --filters "Name=vpc-id,Values=<vpc-id>" `
#       --query "Subnets[*].{SubnetId:SubnetId,AZ:AvailabilityZone,CIDR:CidrBlock}" `
#       --output table
#
#   List security groups:
#     aws ec2 describe-security-groups --region us-east-1 --profile <profile> `
#       --query "SecurityGroups[*].{GroupId:GroupId,Name:GroupName,VPC:VpcId}" `
#       --output table
#
#   Create a security group with HTTP (port 80) open:
#     $SgId = aws ec2 create-security-group --region us-east-1 --profile <profile> `
#       --group-name "my-demo-sg" `
#       --description "Allow HTTP" `
#       --vpc-id <vpc-id> `
#       --query GroupId --output text
#
#     aws ec2 authorize-security-group-ingress --region us-east-1 --profile <profile> `
#       --group-id $SgId `
#       --protocol tcp --port 80 --cidr 0.0.0.0/0

# Fetch the latest Ubuntu 24.04 LTS AMI in us-east-1
$AmiId = aws ec2 describe-images `
  --region us-east-1 `
  --profile <profile> `
  --owners 099720109477 `
  --filters "Name=name,Values=ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*" `
            "Name=state,Values=available" `
  --query "sort_by(Images, &CreationDate)[-1].ImageId" `
  --output text

Write-Host "Using AMI: $AmiId"

# Try each subnet/AZ in order until one succeeds (Spot capacity varies by AZ).
# Add one entry per subnet you want to try, with the AZ as a comment.
$Subnets = @(
  "subnet-XXXXXXXXXXXXXXXXX",  # us-east-1a
  "subnet-XXXXXXXXXXXXXXXXX"   # us-east-1b
)

$SecurityGroup = "sg-XXXXXXXXXXXXXXXXX"
$Launched = $false

foreach ($SubnetId in $Subnets) {
  Write-Host "Trying subnet $SubnetId..."
  $InstanceId = aws ec2 run-instances `
    --region us-east-1 `
    --profile <profile> `
    --launch-template "LaunchTemplateName=<launch-template-name>,Version=`$Latest" `
    --image-id $AmiId `
    --network-interfaces "DeviceIndex=0,SubnetId=$SubnetId,AssociatePublicIpAddress=true,Groups=$SecurityGroup" `
    --query "Instances[0].InstanceId" `
    --output text 2>&1

  if ($LASTEXITCODE -eq 0) {
    Write-Host "Launched instance: $InstanceId"
    $Launched = $true
    break
  } elseif ($InstanceId -match "InsufficientInstanceCapacity|no Spot capacity") {
    Write-Host "No capacity in $SubnetId, trying next..."
  } else {
    Write-Error $InstanceId
    exit 1
  }
}

if (-not $Launched) {
  Write-Error "No Spot capacity available in any subnet."
  exit 1
}

Write-Host "Waiting for instance to enter running state..."
aws ec2 wait instance-running `
  --region us-east-1 `
  --profile <profile> `
  --instance-ids $InstanceId

$Dns = aws ec2 describe-instances `
  --region us-east-1 `
  --profile <profile> `
  --instance-ids $InstanceId `
  --query "Reservations[0].Instances[0].PublicDnsName" `
  --output text

Write-Host "Instance ready — open: http://$Dns"
