#!/bin/bash
set -e

# Install dependencies
apt-get update -y
apt-get install -y git ca-certificates curl gnupg

# Install Docker if not present
if ! command -v docker &> /dev/null; then
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
    https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
    > /etc/apt/sources.list.d/docker.list
  apt-get update -y
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
  systemctl enable docker
  systemctl start docker
  usermod -aG docker ubuntu
  newgrp docker
fi

# Pull the repo
git clone -b deploy-on-ec2 https://github.com/markosluga/FIPS140.git /home/ubuntu/FIPS140
chown -R ubuntu:ubuntu /home/ubuntu/FIPS140

# Script to fetch IMDSv2 credentials and write .env for docker-compose
cat > /usr/local/bin/fetch-imds-credentials.sh << 'EOF'
#!/bin/bash
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
ROLE=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/iam/security-credentials/)
CREDS=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/iam/security-credentials/$ROLE)
cat > /home/ubuntu/FIPS140/.env << ENVEOF
AWS_ACCESS_KEY_ID=$(echo $CREDS | python3 -c "import sys,json; print(json.load(sys.stdin)['AccessKeyId'])")
AWS_SECRET_ACCESS_KEY=$(echo $CREDS | python3 -c "import sys,json; print(json.load(sys.stdin)['SecretAccessKey'])")
AWS_SESSION_TOKEN=$(echo $CREDS | python3 -c "import sys,json; print(json.load(sys.stdin)['Token'])")
ENVEOF
chmod 600 /home/ubuntu/FIPS140/.env
EOF
chmod +x /usr/local/bin/fetch-imds-credentials.sh

# Install systemd service
cat > /etc/systemd/system/fips140-nginx-demo.service << 'EOF'
[Unit]
Description=FIPS140 nginx demo
After=docker.service
Requires=docker.service

[Service]
WorkingDirectory=/home/ubuntu/FIPS140
ExecStartPre=/usr/local/bin/fetch-imds-credentials.sh
ExecStart=/usr/bin/docker compose up
ExecStop=/usr/bin/docker compose down
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable fips140-nginx-demo
systemctl start fips140-nginx-demo
