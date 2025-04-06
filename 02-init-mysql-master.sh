#!/bin/bash
set -e  # Exit immediately if any command fails

# ────────────────────────────────────────────────────────────────
# Load environment variables (e.g., container name, secrets path)
# ────────────────────────────────────────────────────────────────
export $(xargs < .env.master)

# Define the name of the MySQL master container
MASTER_CONTAINER_NAME="mysql57.master"

# Define where to store the output of the master status command
OUTPUT_FILE="./master_status.txt"

# ────────────────────────────────────────────────────────────────
# Execute SHOW MASTER STATUS inside the master container
# - Reads MySQL root password from Docker secret
# - Runs the MySQL command inside the container
# - Extracts the second line (actual status) using awk
# - Formats as: File=<log-bin-name> Position=<log-position>
# - Redirects output to a file on the host
# ────────────────────────────────────────────────────────────────
docker exec "$MASTER_CONTAINER_NAME" bash -c '
PASS=$(cat /run/secrets/mysql_root_password)
mysql -uroot -p"$PASS" -e "SHOW MASTER STATUS;" 2>/dev/null |
awk "NR==2 {print \"File=\" \$1 \" Position=\" \$2}"
' > "$OUTPUT_FILE"

# Notify the user of the output file location
printf "📄 Master status saved to %s\n" "$OUTPUT_FILE"
