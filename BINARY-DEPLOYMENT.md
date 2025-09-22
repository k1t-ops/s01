# Binary Deployment Guide

This guide covers deploying the Host Discovery Service using precompiled Linux binaries from GitHub releases. This deployment method is ideal for production environments where you want direct control over the service without Docker overhead.

## Overview

The binary deployment method:
- Downloads precompiled Linux binaries from GitHub releases
- Sets up systemd services for automatic startup
- Creates proper user accounts and directory structures
- Configures logging and security settings
- Provides easy management commands

## Prerequisites

### System Requirements
- Linux x86_64 system (Ubuntu 18.04+, CentOS 7+, or equivalent)
- Root access for system-wide installation
- Internet connectivity for downloading binaries

### Required Packages
```bash
# Ubuntu/Debian
sudo apt-get update
sudo apt-get install curl jq tar systemd

# CentOS/RHEL/Fedora
sudo yum install curl jq tar systemd
# or
sudo dnf install curl jq tar systemd
```

### Optional Requirements
- GitHub token for private repositories (set `GITHUB_TOKEN` environment variable)
- SSL certificates (for production deployments)

## Quick Start

### Update Repository Configuration
First, update the repository URL in the deployment scripts:

```bash
# Edit scripts/deploy.sh and scripts/deploy-binary.sh
# Change DEFAULT_REPO="your-org/discovery-service" to your actual repository
```

### Simple Deployments

```bash
# Deploy server only
sudo make deploy-server

# Deploy client only  
sudo make deploy-client

# Deploy both server and client
sudo make deploy-full

# Production deployment with optimized settings
sudo make deploy-production
```

### Custom Deployments

```bash
# Deploy specific version
sudo make deploy-full DEPLOY_ARGS="--version v1.2.3"

# Deploy from custom repository
sudo make deploy-server DEPLOY_ARGS="--repo myorg/discovery-service"

# Force overwrite existing installation
sudo make deploy-update DEPLOY_ARGS="--force"
```

## Installation Methods

### 1. Standard System Installation

Installs to standard system locations:
- Binaries: `/opt/discovery/`
- Configuration: `/etc/discovery/`
- Certificates: `/etc/ssl/discovery/`
- Data: `/var/lib/discovery/`
- Logs: `/var/log/discovery/`

```bash
sudo ./scripts/deploy.sh production --repo your-org/discovery-service
```

### 2. Development Installation

Installs to user-accessible locations without systemd:
- Binaries: `/usr/local/bin/`
- Configuration: `/usr/local/etc/discovery/`
- Certificates: `/usr/local/etc/ssl/discovery/`

```bash
sudo ./scripts/deploy.sh development --repo your-org/discovery-service
```

### 3. Custom Installation

Specify custom directories:
```bash
sudo ./scripts/deploy-binary.sh --all \
    --repo your-org/discovery-service \
    --install-dir /custom/bin \
    --config-dir /custom/etc \
    --cert-dir /custom/certs \
    --data-dir /custom/data \
    --log-dir /custom/logs
```

## Configuration

### Server Configuration (`/etc/discovery/server.conf`)

```bash
# Discovery Server Configuration
SERVER_PORT=8443
HEALTH_PORT=8080
MAX_HISTORY=1000
STALE_TIMEOUT=600
CERT_FILE=/etc/ssl/discovery/server.crt
KEY_FILE=/etc/ssl/discovery/server.key
CA_CERT_FILE=/etc/ssl/discovery/ca.crt
LOG_LEVEL=info
LOG_FILE=/var/log/discovery/server.log
DATA_DIR=/var/lib/discovery
```

### Client Configuration (`/etc/discovery/client.conf`)

```bash
# Discovery Client Configuration
SERVICE_NAME=my-service
INSTANCE_NAME=$(hostname)
SERVER_URL=https://localhost:8443
CERT_FILE=/etc/ssl/discovery/client.crt
KEY_FILE=/etc/ssl/discovery/client.key
CA_CERT_FILE=/etc/ssl/discovery/ca.crt
LOG_LEVEL=info
LOG_FILE=/var/log/discovery/client.log
REPORT_INTERVAL=30
TIMEOUT=30
RETRY_ATTEMPTS=3
RETRY_DELAY=5
HEALTH_CPU_THRESHOLD=80.0
HEALTH_MEMORY_THRESHOLD=85.0
HEALTH_DISK_THRESHOLD=85.0
HEALTH_NETWORK_ENABLED=true
HEALTH_SCORE_HEALTHY_MIN=80
HEALTH_SCORE_DEGRADED_MIN=60
```

### Environment Variables

You can override configuration using environment variables:
```bash
# Set environment variables in systemd service or shell
export SERVICE_NAME="web-service"
export INSTANCE_NAME="web-01"
export SERVER_URL="https://discovery.example.com:8443"
export LOG_LEVEL="debug"
```

## Certificate Management

### Development Certificates

For development, you can use self-signed certificates:
```bash
# Generate CA
openssl req -x509 -newkey rsa:4096 -keyout ca.key -out ca.crt -days 365 -nodes \
    -subj "/CN=Discovery CA"

# Generate server certificate
openssl req -newkey rsa:4096 -keyout server.key -out server.csr -nodes \
    -subj "/CN=discovery-server"
openssl x509 -req -in server.csr -CA ca.crt -CAkey ca.key -CAcreateserial \
    -out server.crt -days 365

# Generate client certificate
openssl req -newkey rsa:4096 -keyout client.key -out client.csr -nodes \
    -subj "/CN=discovery-client"
openssl x509 -req -in client.csr -CA ca.crt -CAkey ca.key -CAcreateserial \
    -out client.crt -days 365

# Install certificates
sudo cp ca.crt /etc/ssl/discovery/
sudo cp server.crt server.key /etc/ssl/discovery/
sudo cp client.crt client.key /etc/ssl/discovery/
sudo chown discovery:discovery /etc/ssl/discovery/*
sudo chmod 600 /etc/ssl/discovery/*.key
```

### Production Certificates

For production, use proper certificates from your CA or use the Step CA Docker setup to generate them.

## Service Management

### Systemd Services

The deployment creates systemd services automatically:

```bash
# Check status
sudo systemctl status discovery-server discovery-client

# Start services
sudo systemctl start discovery-server discovery-client

# Enable on boot
sudo systemctl enable discovery-server discovery-client

# Stop services
sudo systemctl stop discovery-server discovery-client

# Restart services
sudo systemctl restart discovery-server discovery-client

# View logs
sudo journalctl -u discovery-server -f
sudo journalctl -u discovery-client -f
```

### Manual Management

Without systemd, you can run services manually:

```bash
# Start server
cd /var/lib/discovery
sudo -u discovery /opt/discovery/discovery-server

# Start client (in another terminal)
sudo -u discovery /opt/discovery/discovery-client
```

### Using Makefile Commands

```bash
# Check deployment status
make deploy-status

# Start services
sudo make deploy-start

# Stop services
sudo make deploy-stop

# Restart services
sudo make deploy-restart

# View logs
make deploy-logs
```

## Health Monitoring

### Health Endpoints

- Server Health: `http://localhost:8080/health`
- Server API: `https://localhost:8443/`

### Monitoring Commands

```bash
# Check if services are running
curl -f http://localhost:8080/health

# Check process status
ps aux | grep discovery

# Check listening ports
netstat -tlnp | grep -E ':8080|:8443'
```

### Log Monitoring

```bash
# Real-time logs
sudo tail -f /var/log/discovery/server.log /var/log/discovery/client.log

# Search for errors
sudo grep -i error /var/log/discovery/*.log

# Check service logs
sudo journalctl -u discovery-server --since "1 hour ago"
```

## Updates and Maintenance

### Updating Services

```bash
# Update to latest version
sudo make deploy-update

# Update to specific version
sudo make deploy-update DEPLOY_ARGS="--version v2.0.0"

# Force update (overwrite existing)
sudo make deploy-update DEPLOY_ARGS="--force"
```

### Backup and Restore

```bash
# Backup configuration and data
sudo tar -czf discovery-backup-$(date +%Y%m%d).tar.gz \
    /etc/discovery/ \
    /etc/ssl/discovery/ \
    /var/lib/discovery/

# Restore from backup
sudo tar -xzf discovery-backup-20240101.tar.gz -C /
sudo chown -R discovery:discovery /var/lib/discovery/
sudo systemctl restart discovery-server discovery-client
```

### Log Rotation

Configure logrotate for discovery logs:

```bash
sudo tee /etc/logrotate.d/discovery << EOF
/var/log/discovery/*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 644 discovery discovery
    postrotate
        systemctl reload discovery-server discovery-client || true
    endscript
}
EOF
```

## Security Considerations

### File Permissions

The deployment script sets secure permissions:
- Configuration files: 640 (readable by service user only)
- Certificate private keys: 600 (readable by owner only)
- Binaries: 755 (executable by all, writable by owner)
- Data directories: 755 (owned by service user)

### Network Security

```bash
# Firewall rules (adjust as needed)
sudo ufw allow 8080/tcp  # Health endpoint
sudo ufw allow 8443/tcp  # HTTPS API

# Or for specific networks
sudo ufw allow from 10.0.0.0/8 to any port 8080
sudo ufw allow from 10.0.0.0/8 to any port 8443
```

### Service User

The deployment creates a dedicated `discovery` user with limited privileges:
- No shell access (`/bin/false`)
- No home directory login
- Limited to service directories
- Systemd security features enabled

## Troubleshooting

### Common Issues

1. **Binary Not Found**
   ```bash
   # Check if GitHub repository and release exist
   curl -s https://api.github.com/repos/your-org/discovery-service/releases/latest
   
   # Verify binary names match expected pattern
   # Expected: discovery-server-linux-amd64.tar.gz, discovery-client-linux-amd64.tar.gz
   ```

2. **Permission Denied**
   ```bash
   # Fix file permissions
   sudo chown -R discovery:discovery /var/lib/discovery/
   sudo chmod -R 755 /var/lib/discovery/
   sudo chmod 600 /etc/ssl/discovery/*.key
   ```

3. **Service Won't Start**
   ```bash
   # Check systemd logs
   sudo journalctl -u discovery-server --no-pager
   
   # Verify configuration
   sudo -u discovery /opt/discovery/discovery-server --help
   
   # Check certificate files
   ls -la /etc/ssl/discovery/
   ```

4. **Connection Refused**
   ```bash
   # Check if service is listening
   sudo netstat -tlnp | grep :8443
   
   # Verify certificates
   openssl x509 -in /etc/ssl/discovery/server.crt -text -noout
   
   # Test connectivity
   curl -k https://localhost:8443/health
   ```

### Debug Mode

Enable debug logging:
```bash
# Edit configuration file
sudo sed -i 's/LOG_LEVEL=info/LOG_LEVEL=debug/' /etc/discovery/server.conf

# Restart service
sudo systemctl restart discovery-server

# Watch logs
sudo journalctl -u discovery-server -f
```

### Recovery Commands

```bash
# Complete reinstall
sudo make deploy-remove
sudo make deploy-production

# Reset configuration to defaults
sudo rm /etc/discovery/*.conf
sudo make deploy-update

# Reset certificates
sudo rm -rf /etc/ssl/discovery/*
# Then install new certificates
```

## Migration from Docker

If migrating from Docker deployment:

1. **Stop Docker services**
   ```bash
   make stop
   ```

2. **Export certificates**
   ```bash
   sudo cp ca/certs/* /tmp/discovery-certs/
   ```

3. **Deploy binaries**
   ```bash
   sudo make deploy-production
   ```

4. **Import certificates**
   ```bash
   sudo cp /tmp/discovery-certs/* /etc/ssl/discovery/
   sudo chown discovery:discovery /etc/ssl/discovery/*
   ```

5. **Start binary services**
   ```bash
   sudo make deploy-start
   ```

## Performance Tuning

### System Limits

```bash
# Increase file descriptor limits
sudo tee /etc/security/limits.d/discovery.conf << EOF
discovery soft nofile 65536
discovery hard nofile 65536
EOF
```

### Service Resources

Edit systemd service files to adjust resource limits:
```bash
sudo systemctl edit discovery-server
```

Add:
```ini
[Service]
MemoryMax=2G
CPUQuota=200%
LimitNOFILE=65536
```

## Integration Examples

### Load Balancer Configuration

For HAProxy:
```
backend discovery_servers
    balance roundrobin
    option httpchk GET /health
    server discovery1 10.0.1.10:8080 check
    server discovery2 10.0.1.11:8080 check
```

### Monitoring with Prometheus

The health endpoints can be monitored with custom Prometheus exporters or by parsing the JSON health responses.

### Service Discovery Integration

The client can be configured to register services with external service discovery systems by modifying the client configuration.

---

This binary deployment method provides a lightweight, efficient way to run the Host Discovery Service in production environments while maintaining full control over the system configuration and dependencies.