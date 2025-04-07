#!/bin/bash
set -e  # Exit immediately if a command exits with a non-zero status

# Load environment variables from .env-mysql
export $(xargs < .env-mysql)

# Create secrets directory and write the trimmed MySQL root password to a file without newline
mkdir -p ./secrets
MYSQL_ROOT_PASSWORD_FILE_CLEAN=$(echo "$MYSQL_ROOT_PASSWORD_FILE" | tr -d '\r')  # Clean up any carriage returns
printf "%s" "$(echo "$MYSQL_ROOT_PASSWORD" | tr -d '\r' | xargs)" > "$MYSQL_ROOT_PASSWORD_FILE_CLEAN"

# Clean the MASTER_CNF to remove any carriage returns
MASTER_CNF_CLEAN=$(echo "$MASTER_CNF" | tr -d '\r')

# Split the MySQL replica databases into an array using ',' as a delimiter
IFS=',' read -ra DBS <<< "$MYSQL_REPLICAS_DB"

# Modify the MySQL master config file by inserting binlog_do_db entries for each replica database
awk -v repl="${MYSQL_REPLICAS_DB}" '
BEGIN {
    n = split(repl, arr, ",");  # Split the list of databases into an array
}
{
    if ($0 == "# Replicate") {
        # Insert binlog_do_db for each replica database
        for (i = 1; i <= n; i++) {
            print "binlog_do_db=" arr[i];
        }
    } else {
        print $0;
    }
}
' "$MASTER_CNF_CLEAN" > "${MASTER_CNF_CLEAN}.tmp" && mv "${MASTER_CNF_CLEAN}.tmp" "$MASTER_CNF_CLEAN"  # Save the changes to the config file

# Replace commas with spaces in the REPLICAS_DB_LIST for compatibility with backup-replicas.sh
MYSQL_REPLICAS_DB=$(echo "$MYSQL_REPLICAS_DB" | tr ',' ' ')  # Replace commas with spaces

# Update the backup-replicas.sh script with the new REPLICAS_DB_LIST
sed -i "s/^REPLICAS_DB_LIST=.*$/REPLICAS_DB_LIST=\"$MYSQL_REPLICAS_DB\"/" ./backup-replicas.sh

# Verify the update has been applied correctly
echo "Updated backup-replicas.sh with REPLICAS_DB_LIST: $MYSQL_REPLICAS_DB"

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
wait_for_healthy mysql57.master
wait_for_healthy mysql57.slave1

# Wait for the backup service to be running
wait_for_running mysql57_backup

# All services are up and healthy
echo "🚀 All services are up!"
