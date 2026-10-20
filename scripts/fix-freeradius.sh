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
RC_CONF="$RC_DIR/radiusclient.conf"
RC_DICT="$RC_DIR/dictionary"
FR_CLIENTS="/etc/freeradius/3.0/clients.conf"
PPP_CHANGED=0

if [ -f "$PPP_OPTS" ] && ! grep -q '^[[:space:]]*plugin[[:space:]]\+radius.so' "$PPP_OPTS"; then
    echo "[System] Patching $PPP_OPTS with pppd RADIUS plugin..."
    cp "$PPP_OPTS" "$PPP_OPTS.bak.$(date +%Y%m%d%H%M%S)"
    printf '\nplugin radius.so\nplugin radattr.so\nradius-config-file %s/radiusclient.conf\n' "$RC_DIR" >> "$PPP_OPTS"
    PPP_CHANGED=1
fi

if [ -f "$PPP_OPTS" ] && grep -q '^[[:space:]]*plugin[[:space:]]\+radius.so' "$PPP_OPTS"; then
    mkdir -p "$RC_DIR"
    # radius.so needs seqfile/mapfile/login_radius, and a dictionary its own parser can read
    # (FreeRADIUS 3 dictionaries make every attribute "unknown" -> CHAP auth fails).
    if [ ! -f "$RC_CONF" ] || ! grep -q '^seqfile' "$RC_CONF" || ! grep -q "^dictionary[[:space:]]\+$RC_DICT" "$RC_CONF"; then
        echo "[System] Writing $RC_CONF and $RC_DICT..."
        [ -f "$RC_CONF" ] && cp "$RC_CONF" "$RC_CONF.bak.$(date +%Y%m%d%H%M%S)"
        cat > "$RC_CONF" <<EOF
auth_order      radius
login_tries     4
login_timeout   60
nologin         /etc/nologin
issue           $RC_DIR/issue
authserver      localhost:1812
acctserver      localhost:1813
servers         $RC_DIR/servers
dictionary      $RC_DICT
login_radius    /usr/sbin/login.radius
seqfile         /var/run/radius.seq
mapfile         $RC_DIR/port-id-map
default_realm
radius_timeout  10
radius_retries  3
login_local     /bin/login
bindaddr        *
EOF
        cat > "$RC_DICT" <<'EOF'
ATTRIBUTE User-Name 1 string
ATTRIBUTE User-Password 2 string
ATTRIBUTE CHAP-Password 3 string
ATTRIBUTE NAS-IP-Address 4 ipaddr
ATTRIBUTE NAS-Port 5 integer
ATTRIBUTE Service-Type 6 integer
ATTRIBUTE Framed-Protocol 7 integer
ATTRIBUTE Framed-IP-Address 8 ipaddr
ATTRIBUTE Framed-IP-Netmask 9 ipaddr
ATTRIBUTE Filter-Id 11 string
ATTRIBUTE Framed-MTU 12 integer
ATTRIBUTE Reply-Message 18 string
ATTRIBUTE Class 25 string
ATTRIBUTE Session-Timeout 27 integer
ATTRIBUTE Idle-Timeout 28 integer
ATTRIBUTE Called-Station-Id 30 string
ATTRIBUTE Calling-Station-Id 31 string
ATTRIBUTE NAS-Identifier 32 string
ATTRIBUTE Acct-Status-Type 40 integer
ATTRIBUTE Acct-Delay-Time 41 integer
ATTRIBUTE Acct-Input-Octets 42 integer
ATTRIBUTE Acct-Output-Octets 43 integer
ATTRIBUTE Acct-Session-Id 44 string
ATTRIBUTE Acct-Authentic 45 integer
ATTRIBUTE Acct-Session-Time 46 integer
ATTRIBUTE Acct-Input-Packets 47 integer
ATTRIBUTE Acct-Output-Packets 48 integer
ATTRIBUTE Acct-Terminate-Cause 49 integer
ATTRIBUTE Acct-Input-Gigawords 52 integer
ATTRIBUTE Acct-Output-Gigawords 53 integer
ATTRIBUTE CHAP-Challenge 60 string
ATTRIBUTE NAS-Port-Type 61 integer
VALUE Service-Type Framed-User 2
VALUE Framed-Protocol PPP 1
VALUE Acct-Status-Type Start 1
VALUE Acct-Status-Type Stop 2
VALUE Acct-Status-Type Interim-Update 3
VALUE Acct-Authentic RADIUS 1
VALUE Acct-Authentic Local 2
VALUE NAS-Port-Type Async 0
VALUE NAS-Port-Type Virtual 5
EOF
        touch "$RC_DIR/issue" "$RC_DIR/port-id-map"
        PPP_CHANGED=1
    fi
    [ -f "$RC_DIR/servers" ] || { echo "localhost testing123" > "$RC_DIR/servers"; chmod 600 "$RC_DIR/servers"; }
    [ "$PPP_CHANGED" = 1 ] && { systemctl restart xl2tpd || echo "[System] xl2tpd restart failed, restart manually."; }
fi

# FreeRADIUS 3.0.26 (BlastRADIUS) drops requests lacking Message-Authenticator; radius.so does not send it.
# Opt out for the loopback client only (127.0.0.1, not reachable from the network).
if [ -f "$FR_CLIENTS" ] && ! awk '/^client localhost \{/,/^\}/' "$FR_CLIENTS" | grep -q '^[[:space:]]*require_message_authenticator'; then
    echo "[System] Relaxing Message-Authenticator for loopback client (pppd radius.so)..."
    cp "$FR_CLIENTS" "$FR_CLIENTS.bak.$(date +%Y%m%d%H%M%S)"
    awk '
    /^client localhost \{/ {inb=1}
    inb && /^[[:space:]]*secret[[:space:]]*=/ && !done {print; print "\trequire_message_authenticator = no"; print "\tlimit_proxy_state = no"; done=1; next}
    /^\}/ {inb=0}
    {print}' "$FR_CLIENTS" > "$FR_CLIENTS.new" && mv "$FR_CLIENTS.new" "$FR_CLIENTS"
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
