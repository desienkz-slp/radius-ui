#!/bin/bash
# Script to fix FreeRADIUS SQL logging (radpostauth & radacct)
# This script will be executed automatically during the update process

echo "[System] Applying FreeRADIUS SQL logging fixes..."

# Function to fix sql uncommenting globally in a file
fix_sql_in_file() {
    local file=$1
    if [ -f "$file" ]; then
        # Uncomment isolated '# sql' or '# -sql'
        sed -i 's/^[[:space:]]*#[[:space:]]*sql[[:space:]]*$/\tsql/' "$file"
        sed -i 's/^[[:space:]]*#[[:space:]]*-sql[[:space:]]*$/\t-sql/' "$file"
        echo "[System] Fixed sql uncommenting in $file"
    else
        echo "[System] File $file not found, skipping..."
    fi
}

fix_sql_in_file "/etc/freeradius/3.0/sites-available/default"
fix_sql_in_file "/etc/freeradius/3.0/sites-available/inner-tunnel"
fix_sql_in_file "/etc/raddb/sites-available/default"
fix_sql_in_file "/etc/raddb/sites-available/inner-tunnel"

echo "[System] Restarting FreeRADIUS service..."
systemctl restart freeradius || systemctl restart radiusd || echo "[System] Failed to restart FreeRADIUS, please restart manually."
echo "[System] Fixes applied successfully."
