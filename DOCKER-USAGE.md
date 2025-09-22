# Docker Compose Usage Guide

This project uses multiple Docker Compose configurations to support different deployment scenarios. This document explains how to use each configuration effectively.

## Available Configurations

### 1. Base Configuration (`docker-compose.yml`)
**Purpose**: Core services only (CA + Discovery Server)
**Use Case**: Minimal setup for development or when you only need the essential services

**Services Included**:
- `step-ca` - Certificate Authority
- `step-ca-init` - CA initialization helper (profile: init)
- `discovery-server` - Main discovery service

### 2. Production Configuration (`docker-compose.prod.yml`)
**Purpose**: Production-ready deployment with optimized settings
**Use Case**: Production environments, staging, or production-like testing

**Key Features**:
- Named volumes for data persistence
- Resource limits and reservations
- Optimized logging configuration
- Always restart policy
- Production-grade health checks
- Reduced verbosity (warn level logging)
- Higher resource limits and longer timeouts

### 3. Testing Configuration (`docker-compose.test.yml`)
**Purpose**: Full testing environment with multiple clients
**Use Case**: Development, integration testing, load testing, demonstrations

**Services Included**:
- All base services
- Multiple test clients simulating different service types
- Debug logging enabled
- Faster health checks and shorter timeouts
- Additional load testing client

## Usage Commands

### Basic Development Setup
Start only the core services (CA + Server):
```bash
docker-compose up -d
```

### Production Deployment
Deploy with production configuration:
```bash
docker-compose -f docker-compose.yml -f docker-compose.prod.yml up -d
```

### Full Testing Environment
Start with all test clients:
```bash
docker-compose -f docker-compose.yml -f docker-compose.test.yml up -d
```

### Initialize CA (First Time Setup)
Run the CA initialization before starting other services:
```bash
docker-compose --profile init up step-ca-init
```

### View Logs
```bash
# All services
docker-compose logs -f

# Specific service
docker-compose logs -f discovery-server

# Production logs
docker-compose -f docker-compose.yml -f docker-compose.prod.yml logs -f
```

### Stop Services
```bash
# Stop all services
docker-compose down

# Stop and remove volumes (careful in production!)
docker-compose down -v

# Stop production setup
docker-compose -f docker-compose.yml -f docker-compose.prod.yml down
```

## Environment-Specific Configurations

### Development Environment Variables
```bash
export CA_PASSWORD=developmentpassword123
export LOG_LEVEL=debug
```

### Production Environment Variables
```bash
export CA_PASSWORD=your_secure_production_password
export LOG_LEVEL=warn
export MAX_HISTORY=5000
export STALE_TIMEOUT=1800
```

## Network Configuration

- **Base/Production**: `discovery-net` (172.20.0.0/16)
- **Testing**: `discovery-test-net` (172.21.0.0/16)

This separation prevents network conflicts when running multiple environments simultaneously.

## Volume Management

### Development (Bind Mounts)
- `./ca/step:/home/step`
- `./ca/config:/etc/step-ca`
- `./ca/certs:/etc/ssl/step`

### Production (Named Volumes)
- `step-ca-data:/home/step`
- `ca-config:/etc/step-ca`
- `ca-certs:/etc/ssl/step`
- `server-config:/etc/discovery`

## Service Scaling

### Scale Test Clients
```bash
docker-compose -f docker-compose.yml -f docker-compose.test.yml up -d --scale client-worker-01=3
```

### Production Scaling
```bash
docker-compose -f docker-compose.yml -f docker-compose.prod.yml up -d --scale discovery-server=2
```

## Health Monitoring

All configurations include health checks. Monitor service health:

```bash
# Check status
docker-compose ps

# Health check logs
docker-compose logs discovery-server | grep health
```

### Health Endpoints
- Discovery Server Health: `http://localhost:8080/health`
- Step CA Health: Available via `step ca health` command

## Troubleshooting

### Common Issues

1. **CA Not Initialized**
   ```bash
   docker-compose --profile init up step-ca-init
   ```

2. **Certificate Issues**
   ```bash
   docker-compose down
   sudo rm -rf ./ca/step ./ca/config ./ca/certs
   docker-compose --profile init up step-ca-init
   ```

3. **Network Conflicts**
   ```bash
   docker network prune
   docker-compose down
   docker-compose up -d
   ```

4. **Port Conflicts**
   - Production uses standard ports (8080, 8443, 9000)
   - Modify port mappings in override files if needed

### Debug Mode
Enable debug logging for troubleshooting:
```bash
LOG_LEVEL=debug docker-compose -f docker-compose.yml -f docker-compose.test.yml up -d
```

## Best Practices

### Development
- Use test configuration for feature development
- Regularly clean up test data: `docker-compose down -v`
- Monitor logs during development: `docker-compose logs -f`

### Production
- Always use named volumes for data persistence
- Set up proper monitoring and alerting
- Use environment files for sensitive configuration
- Regular backup of CA data and certificates
- Monitor resource usage and scale as needed

### Security
- Change default passwords before production deployment
- Regularly rotate certificates
- Use proper firewall rules
- Monitor access logs
- Keep images updated

## Integration with CI/CD

### Testing Pipeline
```bash
# In CI environment
docker-compose -f docker-compose.yml -f docker-compose.test.yml up -d
# Run integration tests
docker-compose -f docker-compose.yml -f docker-compose.test.yml down -v
```

### Production Deployment
```bash
# Build and tag images
docker-compose -f docker-compose.yml -f docker-compose.prod.yml build
docker-compose -f docker-compose.yml -f docker-compose.prod.yml push

# Deploy
docker-compose -f docker-compose.yml -f docker-compose.prod.yml up -d
```
