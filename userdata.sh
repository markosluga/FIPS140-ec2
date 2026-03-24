#!/bin/bash
# Write systemd service unit for FIPS140-nginx-demo
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
