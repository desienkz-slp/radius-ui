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

# Patch pppd RADIUS auth for L2TP (mirrors installer). Idempotent: only adds what is missing.
PPP_OPTS="/etc/ppp/options.xl2tpd"
RC_DIR="/etc/radiusclient"
if [ -f "$PPP_OPTS" ] && ! grep -q '^[[:space:]]*plugin[[:space:]]\+radius.so' "$PPP_OPTS"; then
    echo "[System] Patching $PPP_OPTS with pppd RADIUS plugin..."
    cp "$PPP_OPTS" "$PPP_OPTS.bak.$(date +%Y%m%d%H%M%S)"
    printf '\nplugin radius.so\nplugin radattr.so\nradius-config-file %s/radiusclient.conf\n' "$RC_DIR" >> "$PPP_OPTS"
    mkdir -p "$RC_DIR"
    if [ ! -f "$RC_DIR/radiusclient.conf" ]; then
        cat > "$RC_DIR/radiusclient.conf" <<'EOF'
auth_order      radius
login_tries     4
login_timeout   60
nologin /etc/nologin
issue   /etc/radiusclient/issue
authserver      localhost:1812
acctserver      localhost:1813
servers         /etc/radiusclient/servers
dictionary      /etc/freeradius/3.0/dictionary
default_realm
radius_timeout  10
radius_retries  3
bindaddr *
EOF
    fi
    [ -f "$RC_DIR/servers" ] || { echo "localhost testing123" > "$RC_DIR/servers"; chmod 600 "$RC_DIR/servers"; }
    systemctl restart xl2tpd || echo "[System] xl2tpd restart failed, restart manually."
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
