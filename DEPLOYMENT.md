# Production Deployment Guide

This guide covers deploying the Host Discovery Service in a production environment with proper security, monitoring, and scalability considerations.

## Deployment Methods

The Host Discovery Service supports multiple deployment methods to suit different environments and requirements:

### 1. Docker Deployment (Recommended)
- **Use Cases**: Development, testing, containerized production environments
- **Advantages**: Easy setup, isolated environment, includes CA management
- **Files**: `docker-compose.prod.yml`, `docker-compose.test.yml`
- **Commands**: 
  ```bash
  # Production Docker deployment
  make start-prod
  
  # Test environment with multiple clients
  make start-test
  ```

### 2. Binary Deployment
- **Use Cases**: Production environments, system integration, custom deployments
- **Advantages**: Direct system installation, systemd integration, minimal overhead
- **Files**: Precompiled Linux binaries from GitHub releases
- **Commands**:
  ```bash
  # Configure repository
  make configure-repo REPO=your-org/discovery-service
  
  # Deploy production binaries
  sudo make deploy-production
  ```

### Quick Setup Guide

#### First-time Setup
1. **Configure your repository** (for binary deployment):
   ```bash
   make configure  # Interactive configuration
   # OR
   make configure-repo REPO=your-org/discovery-service
   ```

2. **Choose deployment method**:
   ```bash
   # Docker deployment (easier)
   make start-prod
   
   # Binary deployment (production-ready)
   sudo make deploy-production
   ```

3. **Verify deployment**:
   ```bash
   # Docker
   make status-prod
   
   # Binary
   make deploy-status
   ```

### Deployment Comparison

| Feature | Docker | Binary |
|---------|--------|--------|
| Setup Complexity | Low | Medium |
| Resource Usage | Higher | Lower |
| System Integration | Container | Native |
| Service Management | Docker Compose | systemd |
| Certificate Management | Included (Step CA) | Manual/External |
| Scaling | Container orchestration | System services |
| Updates | Image rebuild | Binary replacement |

---

## Docker Deployment (Detailed)

For Docker-based deployments, this guide focuses on production Docker configurations. For binary deployments, see [BINARY-DEPLOYMENT.md](BINARY-DEPLOYMENT.md).
</text>


## Prerequisites

### Infrastructure Requirements
- **Operating System**: Linux (Ubuntu 20.04+ or RHEL 8+ recommended)
- **Docker**: Version 20.10+ with Docker Compose v2
- **Memory**: Minimum 2GB RAM, 4GB+ recommended
- **Storage**: 20GB+ available disk space
- **Network**: Static IP addresses for discovery servers
- **Certificates**: SSL/TLS certificates for external access (optional)

### Security Requirements
- **Firewall**: Configured to allow only necessary ports
- **User Access**: Non-root user for running services
- **Certificate Management**: Secure storage for CA private keys
- **Monitoring**: Log aggregation and monitoring systems

### Required Tools
```bash
# Install required tools (Ubuntu/Debian)
sudo apt update
sudo apt install -y curl jq docker.io docker-compose-v2

# Install required tools (RHEL/CentOS)
sudo yum install -y curl jq docker docker-compose

# Start Docker service
sudo systemctl enable docker
sudo systemctl start docker

# Add user to docker group (logout/login required)
sudo usermod -aG docker $USER
```

## Production Architecture

### Recommended Topology
```
                    ┌─────────────────┐
                    │  Load Balancer  │
                    │    (HAProxy)    │
                    └─────────┬───────┘
                              │
        ┌─────────────────────┼─────────────────────┐
        │                     │                     │
   ┌────▼────┐           ┌────▼────┐           ┌────▼────┐
   │Discovery│           │Discovery│           │Discovery│
   │Server 1 │           │Server 2 │           │Server 3 │
   │Port 8443│           │Port 8443│           │Port 8443│
   └─────────┘           └─────────┘           └─────────┘
        │                     │                     │
   ┌────▼────┐           ┌────▼────┐           ┌────▼────┐
   │Step-CA 1│           │Step-CA 2│           │Step-CA 3│
   │Port 9000│           │Port 9000│           │Port 9000│
   └─────────┘           └─────────┘           └─────────┘
```

### Network Configuration
- **Discovery Server**: Port 8443 (HTTPS/mTLS) + 8080 (Health Check)
- **Step-CA**: Port 9000 (HTTPS, internal only)
- **Load Balancer**: Port 443 (external HTTPS, optional)

## Step 1: System Preparation

### Create Service User
```bash
# Create dedicated user for discovery service
sudo useradd -r -s /bin/false -d /opt/discovery discovery

# Create directory structure
sudo mkdir -p /opt/discovery/{app,data,logs,certs}
sudo chown -R discovery:discovery /opt/discovery
```

### Configure Firewall
```bash
# UFW (Ubuntu)
sudo ufw allow 8443/tcp  # Discovery Server API
sudo ufw allow 8080/tcp  # Health checks
sudo ufw allow 9000/tcp  # Step-CA (internal only if using separate hosts)

# Firewalld (RHEL/CentOS)
sudo firewall-cmd --permanent --add-port=8443/tcp
sudo firewall-cmd --permanent --add-port=8080/tcp
sudo firewall-cmd --permanent --add-port=9000/tcp
sudo firewall-cmd --reload
```

### System Limits
```bash
# Increase file descriptor limits
echo "discovery soft nofile 65536" | sudo tee -a /etc/security/limits.conf
echo "discovery hard nofile 65536" | sudo tee -a /etc/security/limits.conf

# Configure systemd limits (if using systemd services)
sudo mkdir -p /etc/systemd/system/docker.service.d
cat << 'EOF' | sudo tee /etc/systemd/system/docker.service.d/limits.conf
[Service]
LimitNOFILE=65536
LimitNPROC=65536
EOF
```

## Step 2: Deploy the Service

### Download and Setup
```bash
# Switch to discovery user
sudo -u discovery bash

# Clone repository (adjust URL as needed)
cd /opt/discovery/app
git clone https://github.com/your-org/host-discovery-service.git .
# OR download release tarball and extract

# Make scripts executable
chmod +x scripts/*.sh
```

### Production Configuration
Create production environment file:

```bash
# Create production environment configuration
cat << 'EOF' > /opt/discovery/app/.env.production
# Core Configuration
SERVER_PORT=8443
HEALTH_PORT=8080
MAX_HISTORY=1000
STALE_TIMEOUT=300

# Security
CA_CERT_FILE=/etc/ssl/certs/ca_chain.crt
CERT_FILE=/etc/ssl/certs/server.crt
KEY_FILE=/etc/ssl/certs/server.key

# Performance
READ_TIMEOUT=30
WRITE_TIMEOUT=30
REQUEST_TIMEOUT=30

# Logging
LOG_LEVEL=info
EOF
```

### Production Docker Compose
Create production-specific docker-compose file:

```bash
cat << 'EOF' > /opt/discovery/app/docker-compose.prod.yml
version: "3.8"

services:
  step-ca:
    image: smallstep/step-ca:latest
    container_name: discovery-ca
    restart: unless-stopped
    ports:
      - "127.0.0.1:9000:9000"  # Bind to localhost only
    environment:
      - DOCKER_STEPCA_INIT_NAME=Production Discovery CA
      - DOCKER_STEPCA_INIT_DNS_NAMES=step-ca,discovery-ca.internal
      - DOCKER_STEPCA_INIT_REMOTE_MANAGEMENT=false
    volumes:
      - /opt/discovery/data/step:/home/step
      - /opt/discovery/data/ca-config:/etc/step-ca
      - /opt/discovery/certs:/etc/ssl/step
    networks:
      - discovery-internal
    healthcheck:
      test: ["CMD", "step", "ca", "health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 10s
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

  discovery-server:
    build:
      context: ./server
      dockerfile: Dockerfile
    container_name: discovery-server
    restart: unless-stopped
    ports:
      - "8443:8443"
      - "127.0.0.1:8080:8080"  # Health check on localhost only
    env_file:
      - .env.production
    volumes:
      - /opt/discovery/certs:/etc/ssl/certs:ro
      - /opt/discovery/logs:/var/log/discovery
    depends_on:
      step-ca:
        condition: service_healthy
    networks:
      - discovery-internal
    healthcheck:
      test: ["CMD", "curl", "http://localhost:8080/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 15s
    logging:
      driver: "json-file"
      options:
        max-size: "50m"
        max-file: "5"

networks:
  discovery-internal:
    driver: bridge
    ipam:
      config:
        - subnet: 172.20.0.0/16
EOF
```

## Step 3: Initialize Production CA

### Generate Production Certificates
```bash
# Initialize the certificate authority
COMPOSE_FILE=docker-compose.prod.yml ./scripts/init-ca.sh

# Verify certificates were created
ls -la /opt/discovery/certs/
```

### Secure CA Private Keys
```bash
# Move CA private keys to secure location
sudo mkdir -p /etc/ssl/private/discovery-ca
sudo mv /opt/discovery/data/step/secrets/* /etc/ssl/private/discovery-ca/
sudo chmod 600 /etc/ssl/private/discovery-ca/*
sudo chown root:root /etc/ssl/private/discovery-ca/*

# Update CA configuration to use secure path
# (This may require updating step-ca configuration)
```

## Step 4: Start Production Services

### Start Services
```bash
# Start the production stack
cd /opt/discovery/app
docker-compose -f docker-compose.prod.yml up -d

# Verify services are running
docker-compose -f docker-compose.prod.yml ps
```

### Verify Deployment
```bash
# Check health endpoints
curl -f http://localhost:8080/health

# Test API with test certificate (should fail on first run without client cert)
curl -k https://localhost:8443/api/v1/hosts

# Run production tests
./scripts/test-discovery.sh
```

## Step 5: Client Certificate Management

### Generate Client Certificates for Production Services

```bash
# Generate certificates for each service that will register
./scripts/generate-client-cert.sh \
  --service-name web-service \
  --instance-name prod-web-01 \
  --host web01.prod.internal \
  --output-dir /opt/discovery/certs/clients/

./scripts/generate-client-cert.sh \
  --service-name api-service \
  --instance-name prod-api-01 \
  --host api01.prod.internal \
  --output-dir /opt/discovery/certs/clients/

./scripts/generate-client-cert.sh \
  --service-name database \
  --instance-name prod-db-primary \
  --host db-primary.prod.internal \
  --output-dir /opt/discovery/certs/clients/
```

### Distribute Certificates Securely
```bash
# Example: Copy certificates to target hosts
for host in web01.prod.internal api01.prod.internal db-primary.prod.internal; do
  scp -r /opt/discovery/certs/clients/* root@$host:/etc/ssl/certs/discovery/
  ssh root@$host "chmod 644 /etc/ssl/certs/discovery/*.crt"
  ssh root@$host "chmod 600 /etc/ssl/certs/discovery/*.key"
  ssh root@$host "chown discovery-client:discovery-client /etc/ssl/certs/discovery/*"
done
```

## Step 6: Systemd Service Configuration

### Create Systemd Service
```bash
cat << 'EOF' | sudo tee /etc/systemd/system/discovery-service.service
[Unit]
Description=Host Discovery Service
Requires=docker.service
After=docker.service
StartLimitBurst=3
StartLimitInterval=60s

[Service]
Type=oneshot
RemainAfterExit=true
WorkingDirectory=/opt/discovery/app
ExecStart=/usr/bin/docker-compose -f docker-compose.prod.yml up -d
ExecStop=/usr/bin/docker-compose -f docker-compose.prod.yml down
ExecReload=/usr/bin/docker-compose -f docker-compose.prod.yml restart
TimeoutStartSec=300
Restart=on-failure
RestartSec=30
User=discovery
Group=discovery

[Install]
WantedBy=multi-user.target
EOF

# Enable and start the service
sudo systemctl daemon-reload
sudo systemctl enable discovery-service
sudo systemctl start discovery-service

# Verify service is running
sudo systemctl status discovery-service
```

## Step 7: Load Balancer Configuration (Optional)

### HAProxy Configuration
If running multiple discovery servers:

```bash
# Install HAProxy
sudo apt install haproxy  # Ubuntu/Debian
sudo yum install haproxy  # RHEL/CentOS

# Configure HAProxy
cat << 'EOF' | sudo tee -a /etc/haproxy/haproxy.cfg

# Discovery Service Load Balancer
frontend discovery_frontend
    bind *:443 ssl crt /etc/ssl/certs/discovery-public.pem
    default_backend discovery_servers
    
    # Health check endpoint (no SSL)
    acl health_check path_beg /health
    use_backend discovery_health if health_check

backend discovery_servers
    balance roundrobin
    option ssl-hello-chk
    server discovery1 discovery-server-1:8443 check ssl verify none
    server discovery2 discovery-server-2:8443 check ssl verify none
    server discovery3 discovery-server-3:8443 check ssl verify none

backend discovery_health
    balance roundrobin
    server health1 discovery-server-1:8080 check
    server health2 discovery-server-2:8080 check
    server health3 discovery-server-3:8080 check
EOF

# Restart HAProxy
sudo systemctl restart haproxy
sudo systemctl enable haproxy
```

## Step 8: Monitoring and Logging

### Log Management
```bash
# Configure log rotation
cat << 'EOF' | sudo tee /etc/logrotate.d/discovery-service
/opt/discovery/logs/*.log {
    daily
    missingok
    rotate 30
    compress
    delaycompress
    notifempty
    sharedscripts
    postrotate
        docker-compose -f /opt/discovery/app/docker-compose.prod.yml restart discovery-server
    endscript
}
EOF
```

### Monitoring Scripts
```bash
# Create monitoring script
cat << 'EOF' > /opt/discovery/app/scripts/monitor-production.sh
#!/bin/bash

DISCOVERY_URL="https://localhost:8443"
HEALTH_URL="http://localhost:8080/health"
ALERT_EMAIL="ops@company.com"

# Check service health
if ! curl -f -s "$HEALTH_URL" >/dev/null; then
    echo "ALERT: Discovery service health check failed" | mail -s "Discovery Service Down" "$ALERT_EMAIL"
    exit 1
fi

# Check certificate expiration (warn 30 days before)
CERT_FILE="/opt/discovery/certs/server.crt"
EXPIRY=$(openssl x509 -in "$CERT_FILE" -noout -enddate | cut -d= -f2)
EXPIRY_EPOCH=$(date -d "$EXPIRY" +%s)
CURRENT_EPOCH=$(date +%s)
DAYS_UNTIL_EXPIRY=$(( (EXPIRY_EPOCH - CURRENT_EPOCH) / 86400 ))

if [ "$DAYS_UNTIL_EXPIRY" -lt 30 ]; then
    echo "WARNING: Server certificate expires in $DAYS_UNTIL_EXPIRY days" | mail -s "Certificate Expiration Warning" "$ALERT_EMAIL"
fi

# Check registered hosts count
HOSTS_COUNT=$(curl -s -k --cert /opt/discovery/certs/test-client.crt --key /opt/discovery/certs/test-client.key "$DISCOVERY_URL/api/v1/hosts" | jq -r '.total')

if [ "$HOSTS_COUNT" -lt 1 ]; then
    echo "WARNING: No hosts registered in discovery service" | mail -s "No Registered Hosts" "$ALERT_EMAIL"
fi

echo "Discovery service healthy. $HOSTS_COUNT hosts registered."
EOF

chmod +x /opt/discovery/app/scripts/monitor-production.sh

# Add to crontab
echo "*/5 * * * * /opt/discovery/app/scripts/monitor-production.sh" | sudo -u discovery crontab -
```

### Prometheus Metrics (Advanced)
```bash
# Add metrics endpoint to discovery server (requires code modification)
# Create metrics collection script
cat << 'EOF' > /opt/discovery/app/scripts/collect-metrics.sh
#!/bin/bash

# Collect metrics for Prometheus or other monitoring systems
METRICS_FILE="/var/lib/discovery/metrics"

HEALTH_DATA=$(curl -s http://localhost:8080/health)
TOTAL_HOSTS=$(echo "$HEALTH_DATA" | jq -r '.total_hosts')
STATUS=$(echo "$HEALTH_DATA" | jq -r '.status')

# Export metrics in Prometheus format
cat << METRICS > "$METRICS_FILE"
# HELP discovery_service_up Discovery service status
# TYPE discovery_service_up gauge
discovery_service_up{status="$STATUS"} 1

# HELP discovery_registered_hosts Total number of registered hosts
# TYPE discovery_registered_hosts gauge
discovery_registered_hosts $TOTAL_HOSTS

# HELP discovery_service_info Discovery service information
# TYPE discovery_service_info gauge
discovery_service_info{version="1.0.0"} 1
METRICS
EOF
```

## Step 9: Backup and Disaster Recovery

### Backup Configuration
```bash
# Create backup script
cat << 'EOF' > /opt/discovery/app/scripts/backup.sh
#!/bin/bash

BACKUP_DIR="/opt/discovery/backups/$(date +%Y-%m-%d_%H-%M-%S)"
mkdir -p "$BACKUP_DIR"

# Backup certificates and CA data
cp -r /opt/discovery/certs "$BACKUP_DIR/"
cp -r /opt/discovery/data "$BACKUP_DIR/"

# Backup configuration
cp /opt/discovery/app/.env.production "$BACKUP_DIR/"
cp /opt/discovery/app/docker-compose.prod.yml "$BACKUP_DIR/"

# Create tarball
cd /opt/discovery/backups
tar -czf "discovery-backup-$(date +%Y-%m-%d_%H-%M-%S).tar.gz" "$(basename $BACKUP_DIR)"
rm -rf "$BACKUP_DIR"

# Keep only last 7 days of backups
find /opt/discovery/backups -name "*.tar.gz" -mtime +7 -delete

echo "Backup completed: discovery-backup-$(date +%Y-%m-%d_%H-%M-%S).tar.gz"
EOF

chmod +x /opt/discovery/app/scripts/backup.sh

# Add to daily cron
echo "0 2 * * * /opt/discovery/app/scripts/backup.sh" | sudo -u discovery crontab -
```

### Disaster Recovery Plan
1. **Certificate Recovery**: Store CA private keys in secure, offline location
2. **Data Recovery**: Regular backups of certificate database and configuration
3. **Service Recovery**: Documented procedure for rebuilding services
4. **Network Recovery**: DNS and firewall configuration documentation

## Step 10: Security Hardening

### Additional Security Measures
```bash
# 1. Disable root SSH access (if not already done)
sudo sed -i 's/PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
sudo systemctl reload ssh

# 2. Enable fail2ban
sudo apt install fail2ban  # Ubuntu/Debian
sudo systemctl enable fail2ban
sudo systemctl start fail2ban

# 3. Configure automatic security updates
sudo apt install unattended-upgrades
echo 'Unattended-Upgrade::Automatic-Reboot "false";' | sudo tee -a /etc/apt/apt.conf.d/50unattended-upgrades

# 4. Secure Docker daemon
sudo mkdir -p /etc/docker
cat << 'EOF' | sudo tee /etc/docker/daemon.json
{
    "live-restore": true,
    "userland-proxy": false,
    "no-new-privileges": true
}
EOF
sudo systemctl restart docker
```

### Certificate Security
```bash
# Set strict permissions on certificates
find /opt/discovery/certs -name "*.crt" -exec chmod 644 {} \;
find /opt/discovery/certs -name "*.key" -exec chmod 600 {} \;
chown -R discovery:discovery /opt/discovery/certs
```

## Production Checklist

### Pre-Deployment
- [ ] System requirements verified
- [ ] Firewall configured
- [ ] SSL certificates ready
- [ ] Backup strategy defined
- [ ] Monitoring configured
- [ ] Security hardening applied

### Post-Deployment
- [ ] Services start automatically on boot
- [ ] Health checks passing
- [ ] Logs being collected and rotated
- [ ] Monitoring alerts configured
- [ ] Backup jobs running
- [ ] Documentation updated
- [ ] Team access configured
- [ ] Disaster recovery tested

### Ongoing Maintenance
- [ ] Regular security updates
- [ ] Certificate rotation schedule
- [ ] Capacity monitoring
- [ ] Performance optimization
- [ ] Backup validation
- [ ] Documentation updates

## Troubleshooting

### Common Production Issues

1. **Service Won't Start**
```bash
# Check logs
sudo journalctl -u discovery-service -f
docker-compose -f docker-compose.prod.yml logs

# Check file permissions
ls -la /opt/discovery/certs/
```

2. **Certificate Issues**
```bash
# Verify certificate chain
openssl verify -CAfile /opt/discovery/certs/root_ca.crt /opt/discovery/certs/server.crt

# Check certificate expiration
openssl x509 -in /opt/discovery/certs/server.crt -noout -enddate
```

3. **Performance Issues**
```bash
# Check resource usage
docker stats discovery-server discovery-ca

# Monitor API response times
curl -w "@curl-format.txt" -s -o /dev/null https://localhost:8443/health
```

4. **High Availability Issues**
```bash
# Check load balancer status
sudo systemctl status haproxy
curl -f http://loadbalancer:443/health
```

### Performance Tuning

```bash
# Optimize Docker containers
docker-compose -f docker-compose.prod.yml up -d --remove-orphans

# Monitor memory usage
docker stats --no-stream discovery-server

# Optimize history retention
# Edit .env.production and adjust MAX_HISTORY value
```

## Scaling Considerations

### Horizontal Scaling
- Deploy multiple discovery servers behind load balancer
- Use shared certificate authority
- Implement health checks for each instance
- Consider database backend for large deployments

### Vertical Scaling
- Increase container memory limits
- Optimize garbage collection settings
- Monitor and adjust history retention
- Use SSD storage for better I/O performance

---

## Support and Maintenance

For production support:
1. Monitor service logs regularly
2. Set up proper alerting for failures
3. Keep certificates up to date
4. Plan for regular maintenance windows
5. Document any customizations made

This completes the production deployment of your Host Discovery Service. Remember to regularly review and update your security measures and certificates.