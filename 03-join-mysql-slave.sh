#!/bin/bash
set -e  # Exit immediately if any command fails

# ────────────────────────────────────────────────────────────────
# Load environment variables from .env-mysql
# ────────────────────────────────────────────────────────────────
export $(xargs < .env-mysql)

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
# BUILD SQL REPLICATION SETUP SCRIPT
# The script will:
# 1. Stop the current slave process
# 2. Configure it to connect to the master using credentials and binlog position
# 3. Start the slave
# 4. Show the slave status to verify replication
# ────────────────────────────────────────────────────────────────
# Trimmed and cleaned variables
MASTER_LOG_FILE=$(echo "$MASTER_LOG_FILE" | tr -d '\r' | xargs)
MASTER_LOG_POS=$(echo "$MASTER_LOG_POS" | tr -d '\r' | xargs)
MASTER_HOST=$(echo "$MASTER_HOST" | tr -d '\r' | xargs)
MYSQL_REPL_USER=$(echo "$MYSQL_REPL_USER" | tr -d '\r' | xargs)
MYSQL_REPL_PASSWORD=$(echo "$MYSQL_REPL_PASSWORD" | tr -d '\r' | xargs)

# Build SQL command with cleaned variables
SQL_COMMANDS=$(cat <<EOF
STOP SLAVE;
CHANGE MASTER TO
  MASTER_HOST='$MASTER_HOST',
  MASTER_USER='$MYSQL_REPL_USER',
  MASTER_PASSWORD='$MYSQL_REPL_PASSWORD',
  MASTER_LOG_FILE='$MASTER_LOG_FILE',
  MASTER_LOG_POS=$MASTER_LOG_POS;
START SLAVE;
DO SLEEP(1);
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
