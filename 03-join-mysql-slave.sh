#!/bin/bash
set -euo pipefail

# ────────────────────────────────────────────────────────────────
# Load environment variables from .env-mysql
# ────────────────────────────────────────────────────────────────
export $(xargs < .env-mysql)

# ────────────────────────────────────────────────────────────────
# Parse master status file
# ────────────────────────────────────────────────────────────────
MASTER_LOG_FILE=$(awk '{print $1}' "$MASTER_STATUS_FILE" | cut -d'=' -f2)
MASTER_LOG_POS=$(awk '{print $2}' "$MASTER_STATUS_FILE" | cut -d'=' -f2)

if [[ -z "$MASTER_LOG_FILE" || -z "$MASTER_LOG_POS" ]]; then
  echo "❌ Failed to read master status from $MASTER_STATUS_FILE"
  exit 1
fi

# ────────────────────────────────────────────────────────────────
# Configure slave to connect to master using replication user
# Secrets (root + replication password) are read inside container
# ────────────────────────────────────────────────────────────────

# Trimmed and cleaned variables
MASTER_HOST=$(echo "$MASTER_HOST" | tr -d '\r' | xargs)
MYSQL_REPL_USER=$(echo "$MYSQL_REPL_USER" | tr -d '\r' | xargs)
MASTER_LOG_FILE=$(echo "$MASTER_LOG_FILE" | tr -d '\r' | xargs)
MASTER_LOG_POS=$(echo "$MASTER_LOG_POS" | tr -d '\r' | xargs)

SQL_COMMANDS=$(cat <<EOF
STOP SLAVE;
CHANGE MASTER TO
  MASTER_HOST='$MASTER_HOST',
  MASTER_USER='$MYSQL_REPL_USER',
  MASTER_PASSWORD='REPL_PASSWORD_PLACEHOLDER',
  MASTER_LOG_FILE='$MASTER_LOG_FILE',
  MASTER_LOG_POS=$MASTER_LOG_POS;
START SLAVE;
DO SLEEP(1);
SHOW SLAVE STATUS\G
EOF
)

docker exec -i "$SLAVE_CONTAINER_NAME" bash -c '
ROOT_PASS=$(cat /run/secrets/mysql_root_password)
REPL_PASS=$(cat /run/secrets/mysql_repl_password)

# Replace placeholder in SQL with actual replication password
SQL=$(cat <<EOSQL
'"$SQL_COMMANDS"'
EOSQL
)
SQL="${SQL//REPL_PASSWORD_PLACEHOLDER/$REPL_PASS}"

# Run SQL via mysql
mysql -uroot -p"$ROOT_PASS" <<< "$SQL"
'
