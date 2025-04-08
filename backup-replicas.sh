#!/bin/bash
set -e

MYSQL_ROOT_PASSWORD=$(cat /run/secrets/mysql_root_password)
TIMESTAMP=$(date +%F-%H-%M)

echo "Backing up databases: $MYSQL_BACKUP_DB from $MYSQL_BACKUP_HOST"
/usr/bin/mariadb-dump --skip-ssl -h"$MYSQL_BACKUP_HOST" -uroot -p"$MYSQL_ROOT_PASSWORD" --databases $MYSQL_BACKUP_DB \
  | gzip > /backups/backup-replicas-$TIMESTAMP.sql.gz

echo "✅ Backup for $MYSQL_BACKUP_DB from $MYSQL_BACKUP_HOST completed at $TIMESTAMP!"
