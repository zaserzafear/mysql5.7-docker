#!/bin/bash
set -euo pipefail

# ────────────────────────────────────────────────────────────────
# Load environment variables from .env-mysql
# ────────────────────────────────────────────────────────────────
export $(xargs < .env-mysql)

# Sanitize env values to remove carriage return issues
MYSQL_REPL_USER=$(echo "$MYSQL_REPL_USER" | tr -d '\r' | xargs)
MYSQL_REPL_PASSWORD=$(echo "$MYSQL_REPL_PASSWORD" | tr -d '\r' | xargs)

# ────────────────────────────────────────────────────────────────
# Build SQL for creating the replication user
# ────────────────────────────────────────────────────────────────
SQL_CREATE_REPL=$(cat <<EOF
CREATE USER IF NOT EXISTS '${MYSQL_REPL_USER}'@'%' IDENTIFIED BY 'REPL_PASSWORD_PLACEHOLDER';
GRANT REPLICATION SLAVE ON *.* TO '${MYSQL_REPL_USER}'@'%';
FLUSH PRIVILEGES;
EOF
)

# ────────────────────────────────────────────────────────────────
# Inject SQL into master container after replacing placeholder
# ────────────────────────────────────────────────────────────────
echo "🔧 Creating replication user '$MYSQL_REPL_USER' in $MASTER_CONTAINER_NAME..."

docker exec -i "$MASTER_CONTAINER_NAME" bash -c '
ROOT_PASS=$(cat /run/secrets/mysql_root_password)
REPL_PASS=$(cat /run/secrets/mysql_repl_password)

# Read SQL from stdin, replace placeholder, then execute
SQL=$(cat | sed "s/REPL_PASSWORD_PLACEHOLDER/${REPL_PASS}/g")
mysql -uroot -p"$ROOT_PASS" <<< "$SQL"
' <<< "$SQL_CREATE_REPL"

echo "✅ Replication user '$MYSQL_REPL_USER' created in $MASTER_CONTAINER_NAME"

# ────────────────────────────────────────────────────────────────
# Save current master status (log file and position) to a file
# ────────────────────────────────────────────────────────────────
echo "📊 Fetching master status from $MASTER_CONTAINER_NAME..."

docker exec "$MASTER_CONTAINER_NAME" bash -c '
ROOT_PASS=$(cat /run/secrets/mysql_root_password)
mysql -uroot -p"$ROOT_PASS" -e "SHOW MASTER STATUS\G" 2>/dev/null
' | awk '
  BEGIN {file=""; pos=""}
  /File:/ {file=$2}
  /Position:/ {pos=$2}
  END {
    if (file && pos) print "File=" file " Position=" pos
  }
' > "$MASTER_STATUS_FILE"

echo "📄 Master status saved to $MASTER_STATUS_FILE"
