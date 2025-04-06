#!/bin/bash

# Load environment variables (password from secrets)
MYSQL_ROOT_PASSWORD=$(cat /run/secrets/mysql_root_password)

# List of databases to backup (replace with your actual list or dynamic list)
REPLICAS_DB_LIST="db1 db2 db3"

# Prepare a timestamp for the backup file
TIMESTAMP=$(date +\%F-\%H-\%M)

# Run mysqldump for all databases in a single command
echo "Backing up databases: $REPLICAS_DB_LIST"
/usr/bin/mariadb-dump --skip-ssl -hmysql-slave1 -uroot -p"$MYSQL_ROOT_PASSWORD" --databases $REPLICAS_DB_LIST | gzip > /backups/backup-replicas-$TIMESTAMP.sql.gz

echo "Backup for $REPLICAS_DB_LIST completed!"
