# Greenhouse Control System Makefile
# Usage: make <target>

# Configuration
GITHUB_USER := KimIversen
REPO_NAME := commercial-greenhouse-control
GITHUB_URL := https://raw.githubusercontent.com/$(GITHUB_USER)/$(REPO_NAME)/main
COMPOSE_FILE := docker-compose.yml

# Colors for output
GREEN := \033[0;32m
YELLOW := \033[1;33m
RED := \033[0;31m
NC := \033[0m # No Color

.PHONY: help update update-makefile update-configs update-scripts restart-all status logs backup health check-updates install-make

# Default target
help:
	@echo "$(GREEN)Greenhouse Control System Management$(NC)"
	@echo "====================================="
	@echo ""
	@echo "$(YELLOW)Available commands:$(NC)"
	@echo "  $(GREEN)make update$(NC)          - Update all configs and restart services"
	@echo "  $(GREEN)make update-makefile$(NC) - Update Makefile from GitHub"
	@echo "  $(GREEN)make update-configs$(NC)  - Update configuration files only"
	@echo "  $(GREEN)make update-scripts$(NC)  - Update scripts only"
	@echo "  $(GREEN)make restart-all$(NC)     - Restart all Docker services"
	@echo "  $(GREEN)make status$(NC)          - Show status of all services"
	@echo "  $(GREEN)make logs$(NC)            - Show recent logs from all services"
	@echo "  $(GREEN)make health$(NC)          - Check system health"
	@echo "  $(GREEN)make backup$(NC)          - Run manual backup"
	@echo "  $(GREEN)make check-updates$(NC)   - Check for available updates"
	@echo "  $(GREEN)make install-make$(NC)    - Install make if not present"
	@echo ""
	@echo "$(YELLOW)Examples:$(NC)"
	@echo "  make update              # Update everything and restart"
	@echo "  make logs SERVICE=homeassistant  # Show logs for specific service"
	@echo "  make status              # Check if all services are running"

# Main update command - updates everything and restarts
update: check-updates update-makefile update-configs update-scripts restart-all status
	@echo "$(GREEN)✅ Full system update completed!$(NC)"

# Update Makefile itself
update-makefile:
	@echo "$(YELLOW)📥 Updating Makefile from GitHub...$(NC)"
	@curl -s -o Makefile.new $(GITHUB_URL)/Makefile
	@if [ -f Makefile.new ]; then \
		mv Makefile Makefile.backup.$$(date +%Y%m%d_%H%M%S) 2>/dev/null || true; \
		mv Makefile.new Makefile; \
		echo "✅ Makefile updated"; \
	else \
		echo "$(RED)❌ Failed to download Makefile$(NC)"; \
	fi

# Update configuration files
update-configs:
	@echo "$(YELLOW)📥 Updating configuration files...$(NC)"
	@mkdir -p config/homeassistant config/mariadb config/mosquitto
	
	@echo "Downloading Home Assistant configuration..."
	@curl -s -o config/homeassistant/configuration.yaml.new $(GITHUB_URL)/configs/homeassistant/configuration.yaml
	@if [ -f config/homeassistant/configuration.yaml.new ]; then \
		mv config/homeassistant/configuration.yaml config/homeassistant/configuration.yaml.backup.$$(date +%Y%m%d_%H%M%S) 2>/dev/null || true; \
		mv config/homeassistant/configuration.yaml.new config/homeassistant/configuration.yaml; \
		echo "✅ Home Assistant configuration updated"; \
	else \
		echo "$(RED)❌ Failed to download Home Assistant configuration$(NC)"; \
	fi
	
	@echo "Downloading Home Assistant Lovelace dashboard..."
	@curl -s -o config/homeassistant/ui-lovelace.yaml.new $(GITHUB_URL)/configs/homeassistant/ui-lovelace.yaml
	@if [ -f config/homeassistant/ui-lovelace.yaml.new ]; then \
		mv config/homeassistant/ui-lovelace.yaml config/homeassistant/ui-lovelace.yaml.backup.$$(date +%Y%m%d_%H%M%S) 2>/dev/null || true; \
		mv config/homeassistant/ui-lovelace.yaml.new config/homeassistant/ui-lovelace.yaml; \
		echo "✅ Home Assistant Lovelace dashboard updated"; \
	else \
		echo "$(RED)❌ Failed to download Home Assistant Lovelace dashboard$(NC)"; \
	fi
	
	@echo "Downloading Docker Compose configuration..."
	@curl -s -o docker-compose.yml.new $(GITHUB_URL)/configs/docker-compose.yml
	@if [ -f docker-compose.yml.new ]; then \
		mv docker-compose.yml docker-compose.yml.backup.$$(date +%Y%m%d_%H%M%S) 2>/dev/null || true; \
		mv docker-compose.yml.new docker-compose.yml; \
		echo "✅ Docker Compose configuration updated"; \
	else \
		echo "$(RED)❌ Failed to download Docker Compose configuration$(NC)"; \
	fi
	
	@echo "Downloading MariaDB configuration..."
	@curl -s -o config/mariadb/my.cnf.new $(GITHUB_URL)/configs/mariadb/my.cnf
	@if [ -f config/mariadb/my.cnf.new ]; then \
		mv config/mariadb/my.cnf config/mariadb/my.cnf.backup.$$(date +%Y%m%d_%H%M%S) 2>/dev/null || true; \
		mv config/mariadb/my.cnf.new config/mariadb/my.cnf; \
		echo "✅ MariaDB configuration updated"; \
	else \
		echo "$(RED)❌ Failed to download MariaDB configuration$(NC)"; \
	fi

# Update scripts
update-scripts:
	@echo "$(YELLOW)📥 Updating scripts...$(NC)"
	@mkdir -p scripts
	
	@echo "Downloading backup script..."
	@curl -s -o scripts/backup.sh.new $(GITHUB_URL)/scripts/backup.sh
	@if [ -f scripts/backup.sh.new ]; then \
		mv scripts/backup.sh scripts/backup.sh.backup.$$(date +%Y%m%d_%H%M%S) 2>/dev/null || true; \
		mv scripts/backup.sh.new scripts/backup.sh; \
		chmod +x scripts/backup.sh; \
		echo "✅ Backup script updated"; \
	else \
		echo "$(RED)❌ Failed to download backup script$(NC)"; \
	fi
	
	@echo "Downloading system monitor script..."
	@curl -s -o scripts/system-monitor.sh.new $(GITHUB_URL)/scripts/system-monitor.sh
	@if [ -f scripts/system-monitor.sh.new ]; then \
		mv scripts/system-monitor.sh scripts/system-monitor.sh.backup.$$(date +%Y%m%d_%H%M%S) 2>/dev/null || true; \
		mv scripts/system-monitor.sh.new scripts/system-monitor.sh; \
		chmod +x scripts/system-monitor.sh; \
		echo "✅ System monitor script updated"; \
	else \
		echo "$(RED)❌ Failed to download system monitor script$(NC)"; \
	fi

# Restart all services
restart-all:
	@echo "$(YELLOW)🔄 Restarting all services...$(NC)"
	@docker-compose down
	@echo "Waiting for clean shutdown..."
	@sleep 5
	@docker-compose up -d
	@echo "Waiting for services to start..."
	@sleep 30
	@echo "$(GREEN)✅ All services restarted$(NC)"

# Show status of all services
status:
	@echo "$(YELLOW)📊 Service Status:$(NC)"
	@docker-compose ps
	@echo ""
	@echo "$(YELLOW)🔍 Health Check:$(NC)"
	@docker-compose ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}" | grep -E "(Up|Exited|Restarting)"

# Show logs from services
logs:
	@if [ -n "$(SERVICE)" ]; then \
		echo "$(YELLOW)📋 Logs for $(SERVICE):$(NC)"; \
		docker-compose logs --tail=50 $(SERVICE); \
	else \
		echo "$(YELLOW)📋 Recent logs from all services:$(NC)"; \
		docker-compose logs --tail=20; \
	fi

# Check system health
health:
	@echo "$(YELLOW)🏥 System Health Check:$(NC)"
	@echo ""
	@echo "📊 Container Status:"
	@docker-compose ps --format "table {{.Name}}\t{{.Status}}"
	@echo ""
	@echo "💾 Disk Usage:"
	@df -h / | grep -E "(Filesystem|/dev)"
	@echo ""
	@echo "🧠 Memory Usage:"
	@free -h | grep -E "(Mem|Swap)"
	@echo ""
	@echo "⚡ CPU Load:"
	@uptime
	@echo ""
	@echo "🗄️ Database Connection Test:"
	@if docker exec greenhouse_mariadb mysqladmin ping -h localhost --silent 2>/dev/null; then \
		echo "$(GREEN)✅ Database: Connected$(NC)"; \
	else \
		echo "$(RED)❌ Database: Connection failed$(NC)"; \
	fi
	@echo ""
	@echo "🌐 Home Assistant API Test:"
	@if curl -f http://localhost:8123/api/ >/dev/null 2>&1; then \
		echo "$(GREEN)✅ Home Assistant: API responding$(NC)"; \
	else \
		echo "$(RED)❌ Home Assistant: API not responding$(NC)"; \
	fi

# Run manual backup
backup:
	@echo "$(YELLOW)💾 Running manual backup...$(NC)"
	@if [ -f scripts/backup.sh ]; then \
		./scripts/backup.sh; \
		echo "$(GREEN)✅ Backup completed$(NC)"; \
	else \
		echo "$(RED)❌ Backup script not found$(NC)"; \
	fi

# Check for available updates
check-updates:
	@echo "$(YELLOW)🔍 Checking for updates...$(NC)"
	@echo "Current repository: $(GITHUB_URL)"
	@echo "Checking GitHub connectivity..."
	# Uses curl’s --write-out to capture the final status code after redirects
	@if code=$$(curl -s -o /dev/null -w '%{http_code}' -L $(GITHUB_URL)/README.md); \
   	[ "$$code" -lt 400 ]; then \
        	printf '%b\n' '$(GREEN)✅ GitHub repository accessible$(NC)'; \
   	else \
        	printf '%b\n' '$(RED)❌ GitHub returned HTTP $$code$(NC)'; \
        	exit 1; \
   	fi

# Install make if not present
install-make:
	@echo "$(YELLOW)📦 Installing make...$(NC)"
	@if command -v make >/dev/null 2>&1; then \
		echo "$(GREEN)✅ make is already installed$(NC)"; \
	else \
		echo "Installing make..."; \
		sudo apt update && sudo apt install -y make; \
		echo "$(GREEN)✅ make installed successfully$(NC)"; \
	fi

# Quick shortcuts
restart: restart-all
update-all: update
ps: status
log: logs

# Advanced targets
clean-containers:
	@echo "$(YELLOW)🧹 Cleaning unused Docker containers...$(NC)"
	@docker system prune -f
	@echo "$(GREEN)✅ Cleanup completed$(NC)"

pull-images:
	@echo "$(YELLOW)📥 Pulling latest Docker images...$(NC)"
	@docker-compose pull
	@echo "$(GREEN)✅ Images updated$(NC)"

# Development targets
dev-update: update-configs
	@echo "$(YELLOW)🔧 Development update (configs only, no restart)$(NC)"
	@echo "$(GREEN)✅ Configs updated - restart manually when ready$(NC)"

# Show environment info
env-info:
	@echo "$(YELLOW)🔧 Environment Information:$(NC)"
	@echo "User: $$(whoami)"
	@echo "Directory: $$(pwd)"
	@echo "Docker Compose version: $$(docker-compose --version)"
	@echo "Docker version: $$(docker --version)"
	@echo "Make version: $$(make --version | head -n1)"
	@echo "GitHub URL: $(GITHUB_URL)"

# Show detailed help
help-detailed: help
	@echo ""
	@echo "$(YELLOW)Detailed Usage:$(NC)"
	@echo ""
	@echo "$(GREEN)Configuration Management:$(NC)"
	@echo "  make update-configs    - Downloads latest config files from GitHub"
	@echo "  make update-scripts    - Downloads latest scripts from GitHub"
	@echo "  make dev-update        - Update configs without restarting (for testing)"
	@echo ""
	@echo "$(GREEN)Service Management:$(NC)"
	@echo "  make restart-all       - Stop and start all Docker containers"
	@echo "  make pull-images       - Update Docker images to latest versions"
	@echo "  make clean-containers  - Remove unused Docker containers and images"
	@echo ""
	@echo "$(GREEN)Monitoring:$(NC)"
	@echo "  make status            - Show container status"
	@echo "  make health           - Comprehensive system health check"
	@echo "  make logs             - Show logs from all services"
	@echo "  make logs SERVICE=name - Show logs from specific service"
	@echo ""
	@echo "$(GREEN)Maintenance:$(NC)"
	@echo "  make backup           - Run manual backup"
	@echo "  make env-info         - Show environment information"
