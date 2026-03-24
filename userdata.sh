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

# Install systemd service
cat > /etc/systemd/system/fips140-nginx-demo.service << 'EOF'
[Unit]
Description=FIPS140 nginx demo
After=docker.service
Requires=docker.service

[Service]
WorkingDirectory=/home/ubuntu/FIPS140
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
