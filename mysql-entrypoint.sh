#!/bin/bash
set -e

CONFIG_DIR_TMP="/tmp/mysql"
CONF_SOURCE="$CONFIG_DIR_TMP/mysql-${SERVER_MODE}.cnf"
CONFIG_DIR="/etc/mysql/conf.d"

# Update logrotate config
LOGROTATE_FILE="/etc/logrotate.d/mysql"
if [[ -n "$LOGROTATE_DAYS" && -f "$LOGROTATE_FILE" ]]; then
  sed -i "s/\$LOGROTATE_DAYS_REPLACE/$LOGROTATE_DAYS/g" "$LOGROTATE_FILE"
  echo "📝 Updated logrotate config: replaced \$LOGROTATE_DAYS_REPLACE with $LOGROTATE_DAYS"
else
  echo "ℹ️ Skipping logrotate config update. Either LOGROTATE_DAYS is unset or $LOGROTATE_FILE not found."
fi

# Add logrotate cron job to /etc/crontab if LOGROTATE_CRON is set
if [[ -n "$LOGROTATE_CRON" ]]; then
  echo "🕓 Configuring cron job for logrotate in /etc/crontab"

  CRON_CMD="/usr/sbin/logrotate /etc/logrotate.conf >/dev/null 2>&1"
  CRON_ENTRY="$LOGROTATE_CRON root $CRON_CMD"

  # Add to /etc/crontab if not already present
  if ! grep -Fq "$CRON_CMD" /etc/crontab; then
    echo "$CRON_ENTRY" >> /etc/crontab
    echo "✅ Cron job added to /etc/crontab: $CRON_ENTRY"
  else
    echo "ℹ️ Cron job already exists in /etc/crontab."
  fi

  # Start cron daemon in background
  echo "🚀 Starting cron daemon..."
  crond
fi

# Determine target config file based on server mode
if [ "$SERVER_MODE" = "master" ]; then
  echo "🟢 Initializing in MASTER mode..."
  TARGET_CNF="$CONFIG_DIR/mysql-master.cnf"
elif [ "$SERVER_MODE" = "slave" ]; then
  echo "🟡 Initializing in SLAVE mode..."
  TARGET_CNF="$CONFIG_DIR/mysql-slave.cnf"
else
  echo "⚠️ Invalid SERVER_MODE: '$SERVER_MODE'. Must be 'master' or 'slave'. Skipping replication configuration."
  TARGET_CNF=""
fi

# Display current environment values
echo "🔍 Configuration:"
echo "  - LOGROTATE_DAYS    = ${LOGROTATE_DAYS:-unset}"
echo "  - SERVER_MODE       = $SERVER_MODE"
echo "  - SERVER_ID         = $SERVER_ID"
echo "  - MYSQL_REPLICAS_DB = $MYSQL_REPLICAS_DB"
echo "  - CONF_SOURCE       = $CONF_SOURCE"
echo "  - TARGET_CNF        = $TARGET_CNF"

# Update MySQL config
if [[ "$MYSQL_REPLICAS_DB" != "none" && -n "$TARGET_CNF" && -f "$CONF_SOURCE" ]]; then
  echo "🛠️  Applying replication settings to: $TARGET_CNF"

  IFS=',' read -ra DBS <<< "$MYSQL_REPLICAS_DB"

  awk -v repl="$MYSQL_REPLICAS_DB" '
  BEGIN {
      n = split(repl, arr, ",");
  }
  {
      if ($0 == "# Replicate") {
          for (i = 1; i <= n; i++) {
              print "binlog_do_db=" arr[i];
          }
      } else {
          print $0;
      }
  }
  ' "$CONF_SOURCE" > "$TARGET_CNF"

  sed -i "s/\$SERVER_ID_REPLACE/$SERVER_ID/g" "$TARGET_CNF"
  echo "✅ SERVER_ID placeholder replaced with: $SERVER_ID"
  echo "✅ Replication databases added: $MYSQL_REPLICAS_DB"
else
  echo "ℹ️ Skipping configuration update. Conditions not met or source file missing."
fi
