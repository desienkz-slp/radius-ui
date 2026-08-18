#!/bin/bash
# Script to fix FreeRADIUS post-auth SQL logging
# This script will be executed automatically during the update process

echo "[System] Applying FreeRADIUS post-auth fixes..."

# Function to fix sql uncommenting in a file
fix_sql_in_postauth() {
    local file=$1
    if [ -f "$file" ]; then
        # Use awk to find post-auth section and uncomment sql inside it
        awk '
        BEGIN { in_post_auth = 0 }
        /^[[:space:]]*post-auth[[:space:]]*\{/ { in_post_auth = 1 }
        /^[[:space:]]*\}/ { if (in_post_auth) in_post_auth = 0 }
        {
            if (in_post_auth && $0 ~ /^[[:space:]]*#[[:space:]]*sql[[:space:]]*$/) {
                sub(/^[[:space:]]*#[[:space:]]*/, "    ")
            }
            if (in_post_auth && $0 ~ /^[[:space:]]*#[[:space:]]*-sql[[:space:]]*$/) {
                sub(/^[[:space:]]*#[[:space:]]*/, "    ")
            }
            print
        }' "$file" > "${file}.tmp" && mv "${file}.tmp" "$file"
        echo "[System] Fixed $file"
    else
        echo "[System] File $file not found, skipping..."
    fi
}

fix_sql_in_postauth "/etc/freeradius/3.0/sites-available/default"
fix_sql_in_postauth "/etc/freeradius/3.0/sites-available/inner-tunnel"

# Also try raddb path for CentOS/RHEL if freeradius 3.0 path not found
fix_sql_in_postauth "/etc/raddb/sites-available/default"
fix_sql_in_postauth "/etc/raddb/sites-available/inner-tunnel"

echo "[System] Restarting FreeRADIUS service..."
systemctl restart freeradius || systemctl restart radiusd || echo "[System] Failed to restart FreeRADIUS, please restart manually."
echo "[System] Fixes applied successfully."
