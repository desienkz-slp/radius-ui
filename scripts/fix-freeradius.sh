#!/bin/bash
# Script to fix FreeRADIUS SQL logging (radpostauth & radacct)
# This script will be executed automatically during the update process

echo "[System] Applying FreeRADIUS SQL logging fixes..."

# Function to fix sql uncommenting in specific sections of a file
fix_sql_in_section() {
    local section=$1
    local file=$2
    if [ -f "$file" ]; then
        # Use awk to find the section block and uncomment sql inside it
        awk -v target_section="$section" '
        BEGIN { in_section = 0 }
        $0 ~ "^[[:space:]]*" target_section "[[:space:]]*\\{" { in_section = 1 }
        /^[[:space:]]*\}/ { if (in_section) in_section = 0 }
        {
            if (in_section && $0 ~ /^[[:space:]]*#[[:space:]]*sql[[:space:]]*$/) {
                sub(/^[[:space:]]*#[[:space:]]*/, "    ")
            }
            if (in_section && $0 ~ /^[[:space:]]*#[[:space:]]*-sql[[:space:]]*$/) {
                sub(/^[[:space:]]*#[[:space:]]*/, "    ")
            }
            print
        }' "$file" > "${file}.tmp" && mv "${file}.tmp" "$file"
        echo "[System] Fixed $section in $file"
    else
        echo "[System] File $file not found, skipping..."
    fi
}

# Fix post-auth (for radpostauth)
fix_sql_in_section "post-auth" "/etc/freeradius/3.0/sites-available/default"
fix_sql_in_section "post-auth" "/etc/freeradius/3.0/sites-available/inner-tunnel"
fix_sql_in_section "post-auth" "/etc/raddb/sites-available/default"
fix_sql_in_section "post-auth" "/etc/raddb/sites-available/inner-tunnel"

# Fix accounting (for radacct)
fix_sql_in_section "accounting" "/etc/freeradius/3.0/sites-available/default"
fix_sql_in_section "accounting" "/etc/freeradius/3.0/sites-available/inner-tunnel"
fix_sql_in_section "accounting" "/etc/raddb/sites-available/default"
fix_sql_in_section "accounting" "/etc/raddb/sites-available/inner-tunnel"

echo "[System] Restarting FreeRADIUS service..."
systemctl restart freeradius || systemctl restart radiusd || echo "[System] Failed to restart FreeRADIUS, please restart manually."
echo "[System] Fixes applied successfully."
