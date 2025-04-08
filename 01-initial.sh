#!/bin/bash
set -e  # Exit immediately if a command exits with a non-zero status

# Load environment variables from .env-mysql
export $(xargs < .env-mysql)

# Create secrets directory and write the trimmed MySQL root password to a file without newline
mkdir -p ./secrets
MYSQL_ROOT_PASSWORD_FILE_CLEAN=$(echo "$MYSQL_ROOT_PASSWORD_FILE" | tr -d '\r')  # Clean up any carriage returns
printf "%s" "$(echo "$MYSQL_ROOT_PASSWORD" | tr -d '\r' | xargs)" > "$MYSQL_ROOT_PASSWORD_FILE_CLEAN"

MYSQL_REPL_PASSWORD_FILE_CLEAN=$(echo "$MYSQL_REPL_PASSWORD_FILE" | tr -d '\r')  # Clean up any carriage returns
printf "%s" "$(echo "$MYSQL_REPL_PASSWORD" | tr -d '\r' | xargs)" > "$MYSQL_REPL_PASSWORD_FILE_CLEAN"

# Start all Docker services (build if necessary)
docker compose up -d --build

echo "🔄 Waiting for MySQL master and slave to be healthy..."

# Function to wait for a container to be healthy based on its healthcheck status
wait_for_healthy() {
  local container="$1"
  echo -n "⏳ $container..."
  until [ "$(docker inspect --format='{{.State.Health.Status}}' "$container" 2>/dev/null)" = "healthy" ]; do
    sleep 2
    echo -n "."
  done
  echo " ✅"
}

# Function to wait for a container to be running (no healthcheck)
wait_for_running() {
  local container="$1"
  echo -n "⏳ $container..."
  until [ "$(docker inspect --format='{{.State.Running}}' "$container" 2>/dev/null)" = "true" ]; do
    sleep 2
    echo -n "."
  done
  echo " ✅"
}

# Wait for the MySQL master and slave containers to become healthy
wait_for_healthy $MASTER_CONTAINER_NAME
wait_for_healthy $SLAVE_CONTAINER_NAME

# Wait for the backup service to be running
wait_for_running $BACKUP_CONTAINER_NAME

# All services are up and healthy
echo "🚀 All services are up!"
