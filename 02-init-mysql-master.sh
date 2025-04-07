#!/bin/bash
set -e  # Exit immediately if a command exits with a non-zero status

# ────────────────────────────────────────────────────────────────
# Load environment variables from .env-mysql
# ────────────────────────────────────────────────────────────────
export $(xargs < .env-mysql)

# Build SQL on the host (repl user + placeholder password)
SQL_CREATE_REPL=$(cat <<EOF
CREATE USER IF NOT EXISTS '$MYSQL_REPL_USER'@'%' IDENTIFIED BY 'REPL_PASSWORD_PLACEHOLDER';
GRANT REPLICATION SLAVE ON *.* TO '$MYSQL_REPL_USER'@'%';
FLUSH PRIVILEGES;
EOF
)

# Inject into container, replace placeholder with actual secret
docker exec -i "$MASTER_CONTAINER_NAME" bash -c '
ROOT_PASS=$(cat /run/secrets/mysql_root_password)
REPL_PASS=$(cat /run/secrets/mysql_repl_password)

# Replace placeholder and run
SQL_INPUT=$(cat)
SQL_INPUT="${SQL_INPUT//REPL_PASSWORD_PLACEHOLDER/$REPL_PASS}"
mysql -uroot -p"$ROOT_PASS" <<< "$SQL_INPUT"
' <<< "$SQL"

echo "✅ Replication user '$MYSQL_REPL_USER' created in $MASTER_CONTAINER_NAME"



# ────────────────────────────────────────────────────────────────
# Get current master status and save to file
# ────────────────────────────────────────────────────────────────
docker exec "$MASTER_CONTAINER_NAME" bash -c '
ROOT_PASS=$(cat /run/secrets/mysql_root_password)
mysql -uroot -p"$ROOT_PASS" -e "SHOW MASTER STATUS;" 2>/dev/null |
awk "NR==2 {print \"File=\" \$1 \" Position=\" \$2}"
' > "$MASTER_STATUS_FILE"

printf "📄 Master status saved to %s\n" "$MASTER_STATUS_FILE"
