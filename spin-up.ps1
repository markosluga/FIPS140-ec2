# Fetch the latest Ubuntu 24.04 LTS AMI in us-east-2
$AmiId = aws ec2 describe-images `
  --region us-east-2 `
  --profile demos `
  --owners 099720109477 `
  --filters "Name=name,Values=ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*" `
            "Name=state,Values=available" `
  --query "sort_by(Images, &CreationDate)[-1].ImageId" `
  --output text

Write-Host "Using AMI: $AmiId"

# Spin up a spot instance using the launch template, overriding the AMI
aws ec2 run-instances `
  --region us-east-2 `
  --profile demos `
  --launch-template LaunchTemplateName=FIPS140-nginx-demo,Version=5 `
  --image-id $AmiId `
  --network-interfaces "DeviceIndex=0,SubnetId=subnet-0e6738b4475b7922d,AssociatePublicIpAddress=true,Groups=sg-059edb1dfdab3663f" `
  --output table
