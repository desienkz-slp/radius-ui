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

# Patch strongSwan L2TP conn: pfs=no is deprecated/ignored in 5.9, add explicit esp proposals.
# Idempotent: skipped when an esp= line already exists. Backup kept next to the file.
IPSEC_CONF="/etc/ipsec.conf"
if [ -f "$IPSEC_CONF" ] && grep -q 'conn L2TP-PSK-noNAT' "$IPSEC_CONF" && ! grep -q '^[[:space:]]*esp=' "$IPSEC_CONF"; then
    echo "[System] Patching $IPSEC_CONF with ESP proposals..."
    cp "$IPSEC_CONF" "$IPSEC_CONF.bak.$(date +%Y%m%d%H%M%S)"
    sed -i '/^[[:space:]]*pfs=no[[:space:]]*$/d' "$IPSEC_CONF"
    sed -i '/^[[:space:]]*authby=secret[[:space:]]*$/a\    esp=aes256-sha1-modp1024,aes192-sha1-modp1024,aes128-sha1-modp1024,aes256-sha1,aes192-sha1,aes128-sha1,3des-sha1' "$IPSEC_CONF"
    ipsec reload || systemctl reload strongswan-starter || echo "[System] ipsec reload failed, restart strongswan-starter manually."
fi

# Ensure UFW allows L2TP/IPsec (IKE, NAT-T, L2TP, ESP). Idempotent: existing rules are skipped.
if command -v ufw >/dev/null 2>&1; then
    echo "[System] Ensuring UFW rules for L2TP/IPsec..."
    ufw allow 500/udp >/dev/null
    ufw allow 4500/udp >/dev/null
    ufw allow 1701/udp >/dev/null
    ufw allow proto esp from any to any >/dev/null
else
    echo "[System] ufw not installed, skipping L2TP firewall rules."
fi

echo "[System] Restarting FreeRADIUS service..."
systemctl restart freeradius || systemctl restart radiusd || echo "[System] Failed to restart FreeRADIUS, please restart manually."
echo "[System] Fixes applied successfully."
