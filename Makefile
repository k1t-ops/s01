# S01 Makefile

.PHONY: help init build build-all start stop restart test health status logs clean cert dev

# Default target
help: ## Show available commands
	@echo "S01 Commands:"
	@echo ""
	@awk 'BEGIN {FS = ":.*##"}; /^[a-zA-Z_-]+:.*?##/ { printf "  %-15s %s\n", $$1, $$2 }' $(MAKEFILE_LIST)

# Setup and initialization
init: ## Initialize CA, build images, and start services
	@echo "Initializing S01..."
	@chmod +x scripts/*.sh
	@./scripts/init-ca.sh
	@$(MAKE) build-all
	@$(MAKE) start
	@echo "System ready! Try: make test"

# Build targets
build: ## Build s01 server image
	@docker-compose build s01-server

build-all: ## Build all Docker images
	@docker-compose build

# Service management
start: ## Start core services (CA and s01 server)
	@docker-compose up -d step-ca s01-server
	@echo "Services started:"
	@echo "  S01 Server: https://localhost:8443"
	@echo "  Step-CA: https://localhost:9000"

start-prod: ## Start production environment
	@docker-compose -f docker-compose.yml -f docker-compose.prod.yml up -d
	@echo "Production environment started:"
	@echo "  S01 Server: https://localhost:8443"
	@echo "  Step-CA: https://localhost:9000"

start-test: ## Start full test environment with all clients
	@docker-compose -f docker-compose.yml -f docker-compose.test.yml up -d
	@echo "Test environment started with all test clients"

start-demo: ## Start services with demo clients (legacy)
	@docker-compose up -d step-ca s01-server
	@docker-compose --profile demo up -d

stop: ## Stop all services
	@docker-compose down
	@docker-compose -f docker-compose.prod.yml down 2>/dev/null || true
	@docker-compose -f docker-compose.test.yml down 2>/dev/null || true

stop-prod: ## Stop production environment
	@docker-compose -f docker-compose.yml -f docker-compose.prod.yml down

stop-test: ## Stop test environment
	@docker-compose -f docker-compose.yml -f docker-compose.test.yml down

restart: stop start ## Restart core services

# Testing and monitoring
test: ## Run test suite
	@./scripts/test-s01.sh

test-load: ## Start load testing environment
	@docker-compose -f docker-compose.yml -f docker-compose.test.yml up -d load-test-client
	@echo "Load test client started"

health: ## Check service health
	@echo "Service Health:"
	@echo -n "  s01 Server: "
	@curl -s http://localhost:8080/health | jq -r '.status' 2>/dev/null || echo "DOWN"
	@echo -n "  Step-CA: "
	@docker-compose exec -T step-ca step ca health >/dev/null 2>&1 && echo "UP" || echo "DOWN"

status: ## Show service status
	@docker-compose ps

status-prod: ## Show production service status
	@docker-compose -f docker-compose.yml -f docker-compose.prod.yml ps

status-test: ## Show test environment status
	@docker-compose -f docker-compose.yml -f docker-compose.test.yml ps

# Certificate management
cert: ## Generate client certificate (usage: make cert SERVICE=web INSTANCE=web-01)
	@if [ -z "$(SERVICE)" ] || [ -z "$(INSTANCE)" ]; then \
		echo "Usage: make cert SERVICE=service-name INSTANCE=instance-name"; \
		echo "Example: make cert SERVICE=web INSTANCE=web-01"; \
		exit 1; \
	fi
	@./scripts/generate-client-cert.sh --service-name $(SERVICE) --instance-name $(INSTANCE) --output-dir ./certs

# Logging
logs: ## Show all service logs
	@docker-compose logs -f

logs-prod: ## Show production environment logs
	@docker-compose -f docker-compose.yml -f docker-compose.prod.yml logs -f

logs-test: ## Show test environment logs
	@docker-compose -f docker-compose.yml -f docker-compose.test.yml logs -f

logs-server: ## Show s01 server logs
	@docker-compose logs -f s01-server

logs-ca: ## Show step-ca logs
	@docker-compose logs -f step-ca

logs-clients: ## Show all test client logs
	@docker-compose -f docker-compose.yml -f docker-compose.test.yml logs -f client-web-01 client-api-01 client-db-primary client-worker-01

# Development
dev-server: ## Run s01 server locally
	@cd server && \
	CERT_FILE=../ca/certs/server.crt \
	KEY_FILE=../ca/certs/server.key \
	CA_CERT_FILE=../ca/certs/root_ca.crt \
	go run main.go

dev-client: ## Run s01 client locally
	@cd client && \
	SERVICE_NAME=dev-service \
	INSTANCE_NAME=dev-01 \
	SERVER_URL=https://localhost:8443 \
	CERT_FILE=../ca/certs/test-client.crt \
	KEY_FILE=../ca/certs/test-client.key \
	CA_CERT_FILE=../ca/certs/root_ca.crt \
	go run main.go

# Binary deployment (production/standalone)
deploy-server: ## Deploy s01 server binary from GitHub releases
	@./scripts/deploy.sh server --repo $(DEFAULT_REPO) $(DEPLOY_ARGS)

deploy-client: ## Deploy s01 client binary from GitHub releases
	@./scripts/deploy.sh client --repo $(DEFAULT_REPO) $(DEPLOY_ARGS)

deploy-full: ## Deploy both server and client binaries
	@./scripts/deploy.sh full --repo $(DEFAULT_REPO) $(DEPLOY_ARGS)

deploy-production: ## Deploy for production environment
	@./scripts/deploy.sh production --repo $(DEFAULT_REPO) $(DEPLOY_ARGS)

deploy-development: ## Deploy for development environment
	@./scripts/deploy.sh development --repo $(DEFAULT_REPO) $(DEPLOY_ARGS)

deploy-update: ## Update existing binary installation
	@./scripts/deploy.sh update --repo $(DEFAULT_REPO) $(DEPLOY_ARGS)

deploy-status: ## Check binary deployment status
	@./scripts/deploy.sh status

deploy-logs: ## Show binary deployment logs
	@./scripts/deploy.sh logs

deploy-start: ## Start deployed binary services
	@./scripts/deploy.sh start

deploy-stop: ## Stop deployed binary services
	@./scripts/deploy.sh stop

deploy-restart: ## Restart deployed binary services
	@./scripts/deploy.sh restart

deploy-remove: ## Remove binary installation completely
	@./scripts/deploy.sh remove

# Configuration
configure: ## Configure deployment repository settings
	@./scripts/configure-deployment.sh

configure-repo: ## Configure repository directly (usage: make configure-repo REPO=owner/repo-name)
	@if [ -z "$(REPO)" ]; then \
		echo "Usage: make configure-repo REPO=owner/repository-name"; \
		echo "Example: make configure-repo REPO=myorg/s01-service"; \
		exit 1; \
	fi
	@./scripts/configure-deployment.sh --repo $(REPO)

configure-check: ## Check current deployment configuration
	@./scripts/configure-deployment.sh --check

configure-reset: ## Reset deployment configuration to defaults
	@./scripts/configure-deployment.sh --reset

# Docker deployment variables
DEFAULT_REPO ?= your-org/s01-service
DEPLOY_ARGS ?=

# Cleanup
clean: ## Clean up containers and volumes
	@docker-compose down -v --remove-orphans
	@docker-compose -f docker-compose.prod.yml down -v --remove-orphans 2>/dev/null || true
	@docker-compose -f docker-compose.test.yml down -v --remove-orphans 2>/dev/null || true
	@docker system prune -f

clean-prod: ## Clean up production environment
	@docker-compose -f docker-compose.yml -f docker-compose.prod.yml down -v --remove-orphans

clean-test: ## Clean up test environment
	@docker-compose -f docker-compose.yml -f docker-compose.test.yml down -v --remove-orphans

clean-all: ## Remove everything including certificates
	@echo "WARNING: This will remove all certificates and data!"
	@read -p "Continue? [y/N] " -n 1 -r; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		$(MAKE) clean; \
		rm -rf ca/ certs/; \
		echo "Complete cleanup done"; \
	fi

# Environment helpers
env-init-prod: ## Initialize production environment with CA
	@echo "Initializing production environment..."
	@docker-compose --profile init up step-ca-init
	@$(MAKE) start-prod

env-init-test: ## Initialize test environment with CA
	@echo "Initializing test environment..."
	@docker-compose --profile init up step-ca-init
	@$(MAKE) start-test

scale-clients: ## Scale test clients (usage: make scale-clients COUNT=3)
	@if [ -z "$(COUNT)" ]; then \
		echo "Usage: make scale-clients COUNT=number"; \
		echo "Example: make scale-clients COUNT=3"; \
		exit 1; \
	fi
	@docker-compose -f docker-compose.yml -f docker-compose.test.yml up -d --scale client-worker-01=$(COUNT)
