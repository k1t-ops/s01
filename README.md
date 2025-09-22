# s01

A secure, production-ready service discovery system with mutual TLS authentication and automatic health monitoring.

## Overview

s01 enables secure service discovery across your infrastructure. Hosts report their status and health metrics, while other services can discover and monitor available hosts in real-time.

```
┌─────────────┐    ┌──────────────┐    ┌─────────────┐
│   step-ca   │    │   s01        │    │    s01      │
│  (CA & PKI) │    │   Server     │    │   Clients   │
│             │    │              │    │             │
│ Issues ────────→ │ Validates    │←──── Report      │
│ certs       │    │ requests     │    │ status      │
│             │    │ Stores data  │    │             │
└─────────────┘    └──────────────┘    └─────────────┘
```

## Key Features

- **🔐 Mutual TLS Security**: All communication encrypted and authenticated
- **📊 Health Monitoring**: Real-time CPU, memory, disk, and network metrics
- **⏰ Stale Detection**: Automatic "lost" status for unresponsive hosts
- **📈 Status History**: Configurable history tracking for trend analysis
- **🚀 Zero Dependencies**: Pure Go standard library, no external dependencies
- **🐳 Docker Ready**: Complete containerized deployment
- **🔧 Production Ready**: Configurable timeouts, limits, and monitoring

## 🚀 One-Liner Installation

Install precompiled binaries directly from GitHub releases:

### Using curl
```bash
# Install both server and client
curl -fsSL https://raw.githubusercontent.com/k1t-ops/s01/main/install.sh | bash

# Install server only
curl -fsSL https://raw.githubusercontent.com/k1t-ops/s01/main/install.sh | bash -s -- --server-only

# Install client only
curl -fsSL https://raw.githubusercontent.com/k1t-ops/s01/main/install.sh | bash -s -- --client-only
```

### Using wget
```bash
# Install both server and client
wget -qO- https://raw.githubusercontent.com/k1t-ops/s01/main/install.sh | bash

# Install server only
wget -qO- https://raw.githubusercontent.com/k1t-ops/s01/main/install.sh | bash -s -- --server-only

# Install client only
wget -qO- https://raw.githubusercontent.com/k1t-ops/s01/main/install.sh | bash -s -- --client-only
```

### Advanced Options
```bash
# Install specific version
curl -fsSL https://raw.githubusercontent.com/k1t-ops/s01/main/install.sh | bash -s -- --version v1.0.0

# System-wide installation (requires sudo)
curl -fsSL https://raw.githubusercontent.com/k1t-ops/s01/main/install.sh | sudo bash -s -- --system

# Custom install location
curl -fsSL https://raw.githubusercontent.com/k1t-ops/s01/main/install.sh | bash -s -- --prefix /opt/discovery
```

For detailed installation options, see **[📖 QUICK-INSTALL.md](QUICK-INSTALL.md)**

## Quick Start (Docker)

### 1. Initialize and Start
```bash
# Complete setup: CA + certificates + build + start
make init

# Check system health
make health
```

### 2. Run Tests
```bash
# Full test suite (13 tests)
make test
```

### 3. Start Demo Environment
```bash
# Start with demo clients showing multiple services
make start-demo
```

### 4. Query the API
```bash
# List all discovered hosts
curl -k --cert ca/certs/test-client.crt --key ca/certs/test-client.key \
  https://localhost:8443/api/v1/hosts | jq '.'

# Health check (no auth required)
curl http://localhost:8080/health | jq '.'
```

## API Endpoints

- **GET** `/health` - Health check (HTTP, no auth)
- **POST** `/api/v1/report` - Report host status (HTTPS, mTLS)
- **GET** `/api/v1/hosts` - List all hosts (HTTPS, mTLS)
- **GET** `/api/v1/hosts/{service}/{instance}` - Get specific host history (HTTPS, mTLS)

## Status Types

- **`healthy`** - Host is functioning normally
- **`degraded`** - Host has issues but is still operational
- **`unhealthy`** - Host has serious issues
- **`lost`** - Host hasn't reported for > `STALE_TIMEOUT` seconds (auto-detected)

## Configuration

Key environment variables:

```bash
SERVER_PORT=8443          # HTTPS API port
HEALTH_PORT=8080          # HTTP health check port
MAX_HISTORY=100           # Status history per host
STALE_TIMEOUT=300         # Seconds before marking host as "lost"
```

## Available Commands

```bash
make help                 # Show all available commands
make init                 # Complete initialization from zero
make test                 # Run full test suite
make start                # Start core services
make start-demo           # Start with demo clients
make health               # Check service health
make status               # Show service status
make clean-all            # Complete cleanup
```

## Production Deployment

For step-by-step production deployment instructions, see:
**[📖 DEPLOYMENT.md](DEPLOYMENT.md)**

## Testing & Validation

For comprehensive testing procedures and validation, see:
**[🧪 TESTING.md](TESTING.md)**

## Quick Certificate Generation

```bash
# Generate client certificate for your service
make cert SERVICE=my-service INSTANCE=my-instance-01

# Certificates will be created in ./ca/certs/
```

## Ports

- **8443**: s01 Server API (HTTPS, mTLS required)
- **8080**: Health check endpoint (HTTP, no auth)  
- **9000**: Step-CA management (HTTPS)

## Requirements

- Docker & Docker Compose
- `jq` (for JSON processing)
- `curl` (for testing)

---

**🚀 Ready to deploy in production?** → [DEPLOYMENT.md](DEPLOYMENT.md)

**🧪 Want to run comprehensive tests?** → [TESTING.md](TESTING.md)
