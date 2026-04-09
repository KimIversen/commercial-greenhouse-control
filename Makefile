# Greenhouse Control System - Run everything from your Mac
#
# First-time setup:
#   1. Add to ~/.ssh/config:
#        Host greenhouse
#          HostName 192.168.10.105
#          User greenhouse
#   2. Copy your SSH key: ssh-copy-id greenhouse
#   3. make deploy

# Connection
SERVER       := greenhouse
SERVER_DIR   := /opt/greenhouse
SSH          := ssh $(SERVER)
RSYNC        := rsync -avz --delete

.PHONY: help deploy deploy-ha deploy-esphome deploy-compose ssh status logs health backup restart restart-ha

help:
	@echo "Greenhouse Control System"
	@echo "========================="
	@echo ""
	@echo "Deploy (push changes from Mac to server):"
	@echo "  make deploy          - Push all configs and restart changed services"
	@echo "  make deploy-ha       - Push HA config and restart HA"
	@echo "  make deploy-esphome  - Push ESPHome configs only"
	@echo "  make deploy-compose  - Push docker-compose.yml and recreate services"
	@echo ""
	@echo "Server commands (run remotely via SSH):"
	@echo "  make ssh             - SSH into the server"
	@echo "  make status          - Show running services"
	@echo "  make logs            - Tail all logs"
	@echo "  make logs-ha         - Tail Home Assistant logs"
	@echo "  make health          - System health check"
	@echo "  make backup          - Run backup now"
	@echo "  make restart         - Restart all services"
	@echo "  make restart-ha      - Restart Home Assistant only"
	@echo "  make db              - Open MariaDB shell (via SSH tunnel)"
	@echo ""
	@echo "First-time setup:"
	@echo "  make setup-ssh       - Configure SSH key access"

# --- Deploy commands (Mac -> Server via rsync) ---

deploy: deploy-compose deploy-ha deploy-esphome deploy-scripts
	@echo ""
	@echo "All configs deployed. Restarting services..."
	$(SSH) "cd $(SERVER_DIR) && docker compose up -d"
	@echo "Done."

deploy-ha:
	@echo "Deploying Home Assistant config..."
	$(RSYNC) \
		--exclude='secrets.yaml' \
		--exclude='.storage/' \
		--exclude='*.log' \
		--exclude='*.db' \
		--exclude='home-assistant_v2.db*' \
		--exclude='tts/' \
		--exclude='blueprints/' \
		--exclude='custom_components/' \
		--exclude='.cloud/' \
		configs/homeassistant/ $(SERVER):$(SERVER_DIR)/config/homeassistant/
	@echo "Restarting Home Assistant..."
	$(SSH) "cd $(SERVER_DIR) && docker compose restart homeassistant"
	@echo "Done."

deploy-esphome:
	@echo "Deploying ESPHome configs..."
	$(RSYNC) \
		--exclude='secrets.yaml' \
		--exclude='.esphome/' \
		esphome/ $(SERVER):$(SERVER_DIR)/config/esphome/
	@echo "Done."

deploy-compose:
	@echo "Deploying docker-compose.yml..."
	rsync -avz configs/docker-compose.yml $(SERVER):$(SERVER_DIR)/docker-compose.yml

deploy-scripts:
	@echo "Deploying scripts..."
	rsync -avz scripts/backup.sh scripts/system-monitor.sh $(SERVER):$(SERVER_DIR)/scripts/
	$(SSH) "chmod +x $(SERVER_DIR)/scripts/*.sh"

# --- Server commands (via SSH) ---

ssh:
	@ssh $(SERVER)

status:
	@$(SSH) "cd $(SERVER_DIR) && docker compose ps"

logs:
	@$(SSH) "cd $(SERVER_DIR) && docker compose logs --tail=50 -f"

logs-ha:
	@$(SSH) "cd $(SERVER_DIR) && docker compose logs --tail=100 -f homeassistant"

logs-esphome:
	@$(SSH) "cd $(SERVER_DIR) && docker compose logs --tail=50 -f esphome"

logs-mqtt:
	@$(SSH) "cd $(SERVER_DIR) && docker compose logs --tail=50 -f mosquitto"

health:
	@$(SSH) 'echo "=== Services ===" && \
		cd $(SERVER_DIR) && docker compose ps && \
		echo "" && echo "=== Disk ===" && \
		df -h / && \
		echo "" && echo "=== Memory ===" && \
		free -h && \
		echo "" && echo "=== Load ===" && \
		uptime && \
		echo "" && echo "=== DB ===" && \
		docker exec greenhouse_mariadb mysqladmin ping -h localhost --silent 2>/dev/null && echo "MariaDB: OK" || echo "MariaDB: DOWN" && \
		echo "" && echo "=== HA ===" && \
		curl -sf http://localhost:8123/manifest.json >/dev/null && echo "Home Assistant: OK" || echo "Home Assistant: DOWN"'

backup:
	@$(SSH) "$(SERVER_DIR)/scripts/backup.sh"

restart:
	@echo "Restarting all services..."
	@$(SSH) "cd $(SERVER_DIR) && docker compose restart"

restart-ha:
	@$(SSH) "cd $(SERVER_DIR) && docker compose restart homeassistant"

restart-mqtt:
	@$(SSH) "cd $(SERVER_DIR) && docker compose restart mosquitto"

# Access MariaDB for AI/analysis work via SSH tunnel
# Usage: make db  (then connect with any SQL client to localhost:3307)
db:
	@echo "Opening SSH tunnel to MariaDB on localhost:3307..."
	@echo "Connect your SQL client to localhost:3307"
	@echo "Credentials are in the server's .env file"
	@echo "Press Ctrl+C to close the tunnel"
	@ssh -N -L 3307:localhost:3306 $(SERVER)

# --- First-time setup ---

setup-ssh:
	@echo "Setting up SSH key access to greenhouse server..."
	@echo "You may be asked for the greenhouse password."
	@ssh-copy-id -i ~/.ssh/{bitbucket_mb_air_15} $(SERVER)
	@echo ""
	@echo "Done. You should now be able to: make ssh"
