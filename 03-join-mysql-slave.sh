#!/bin/bash
set -e  # Exit immediately if any command fails

# ────────────────────────────────────────────────────────────────
# CONFIGURATION VARIABLES
# ────────────────────────────────────────────────────────────────
SLAVE_CONTAINER_NAME="mysql57.slave1"         # Docker container name for the MySQL slave
MASTER_HOST="mysql-master"                    # Hostname or IP address of the MySQL master (used inside container)
MASTER_USER="root"                            # Replication user (usually root or a specific replication user)
MASTER_STATUS_FILE="./master_status.txt"      # Path to the file containing the master's binary log position

# ────────────────────────────────────────────────────────────────
# READ MASTER STATUS FROM FILE
# Extract binlog filename and position from saved file
# Expected format: File=<log-bin-name> Position=<log-position>
# ────────────────────────────────────────────────────────────────
MASTER_LOG_FILE=$(awk '{print $1}' "$MASTER_STATUS_FILE" | cut -d'=' -f2)
MASTER_LOG_POS=$(awk '{print $2}' "$MASTER_STATUS_FILE" | cut -d'=' -f2)

# Validate extracted values
if [[ -z "$MASTER_LOG_FILE" || -z "$MASTER_LOG_POS" ]]; then
  echo "❌ Failed to read master status from $MASTER_STATUS_FILE"
  exit 1
fi

# ────────────────────────────────────────────────────────────────
# RETRIEVE MASTER PASSWORD FROM SECRET FILE
# This is a host-side check, assuming secrets are mounted locally
# ────────────────────────────────────────────────────────────────
if [[ ! -f "./secrets/mysql_root_password.txt" ]]; then
  echo "❌ Missing root password file at ./secrets/mysql_root_password.txt"
  exit 1
fi

MASTER_PASSWORD=$(< ./secrets/mysql_root_password.txt)

# ────────────────────────────────────────────────────────────────
# BUILD SQL REPLICATION SETUP SCRIPT
# The script will:
# 1. Stop the current slave process
# 2. Configure it to connect to the master using credentials and binlog position
# 3. Start the slave
# 4. Show the slave status to verify replication
# ────────────────────────────────────────────────────────────────
SQL_COMMANDS=$(cat <<EOF
STOP SLAVE;
CHANGE MASTER TO
  MASTER_HOST='$MASTER_HOST',
  MASTER_USER='$MASTER_USER',
  MASTER_PASSWORD='$MASTER_PASSWORD',
  MASTER_LOG_FILE='$MASTER_LOG_FILE',
  MASTER_LOG_POS=$MASTER_LOG_POS;
START SLAVE;
SHOW SLAVE STATUS\G
EOF
)

# ────────────────────────────────────────────────────────────────
# EXECUTE SQL SCRIPT INSIDE THE SLAVE CONTAINER
# - The root password is read from the container’s secrets volume
# - SQL is passed via standard input using heredoc
# ────────────────────────────────────────────────────────────────
docker exec -i "$SLAVE_CONTAINER_NAME" bash -c '
PASS=$(cat /run/secrets/mysql_root_password)
mysql -uroot -p"$PASS"
' <<< "$SQL_COMMANDS"
