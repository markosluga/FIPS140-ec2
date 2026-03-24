# Spin up a FIPS140-nginx-demo spot instance from the launch template
aws ec2 run-instances `
  --region us-east-2 `
  --profile demos `
  --launch-template LaunchTemplateName=FIPS140-nginx-demo `
  --network-interfaces "DeviceIndex=0,SubnetId=subnet-0e6738b4475b7922d,AssociatePublicIpAddress=true,Groups=sg-059edb1dfdab3663f" `
  --output table
