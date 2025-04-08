#!/bin/bash
set -e

# ✅ Run your custom script first
echo "🟢 Running mysql-entrypoint.sh..."
/mysql-entrypoint.sh

# ✅ Then run the original entrypoint
echo "🚀 Launching official MySQL entrypoint..."
exec /usr/local/bin/docker-entrypoint.sh "$@"
