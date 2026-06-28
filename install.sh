#!/bin/bash
# ==========================================================
# RADIUS-UI SECURE INSTALLER SCRIPT
# Run this on a fresh Ubuntu 22.04 / 20.04 server as root
# ==========================================================

INSTALL_DIR=$(pwd)
set -e

echo "=========================================================="
echo "ðŸš€ RADIUS-UI SECURE AUTOMATED INSTALLER"
echo "=========================================================="

echo "[1/8] Updating system and installing basic dependencies..."
apt-get update && apt-get upgrade -y
apt-get install -y curl wget git build-essential unzip

echo "[2/8] Installing MariaDB and configuring database..."
apt-get install -y mariadb-server
systemctl start mariadb
systemctl enable mariadb

mysql -e "CREATE DATABASE IF NOT EXISTS radius_db;"
mysql -e "CREATE USER IF NOT EXISTS 'radius_user'@'localhost' IDENTIFIED BY 'radius_password_123';"
mysql -e "GRANT ALL PRIVILEGES ON radius_db.* TO 'radius_user'@'localhost';"
mysql -e "FLUSH PRIVILEGES;"

mysql radius_db -e "CREATE TABLE IF NOT EXISTS app_fup_policies (
    id INT AUTO_INCREMENT PRIMARY KEY,
    groupname VARCHAR(64) NOT NULL,
    quota_bytes BIGINT NOT NULL,
    address_list_name VARCHAR(100) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);"

echo "[3/8] Installing Node.js 20 LTS and PM2..."
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt-get install -y nodejs
npm install -g pm2

echo "[4/8] Installing Nginx, FreeRADIUS, and network components..."
apt-get install -y nginx freeradius freeradius-mysql freeradius-utils wireguard iptables strongswan xl2tpd ppp

echo "[*] Setting up WireGuard wg0 interface..."
umask 077
wg genkey | tee /etc/wireguard/privatekey | wg pubkey > /etc/wireguard/publickey
cat << 'EOF' > /etc/wireguard/wg0.conf
[Interface]
Address = 10.8.0.1/24
ListenPort = 51820
SaveConfig = true
EOF
echo "PrivateKey = $(cat /etc/wireguard/privatekey)" >> /etc/wireguard/wg0.conf
sed -i 's/#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/' /etc/sysctl.conf
sysctl -p
systemctl enable wg-quick@wg0
systemctl start wg-quick@wg0

echo "[*] Setting up L2TP/IPsec (xl2tpd & strongswan)..."
cat << 'EOF' > /etc/ipsec.conf
config setup
    charondebug="ike 1, knl 1, cfg 0"
    uniqueids=no

conn L2TP-PSK-NAT
    rightsubnet=vhost:%priv
    also=L2TP-PSK-noNAT

conn L2TP-PSK-noNAT
    authby=secret
    pfs=no
    auto=add
    keyingtries=3
    rekey=no
    ikelifetime=8h
    keylife=1h
    type=transport
    left=%any
    leftprotoport=17/1701
    right=%any
    rightprotoport=17/%any
EOF

cat << 'EOF' > /etc/ipsec.secrets
%any %any : PSK "rahasia"
EOF

cat << 'EOF' > /etc/xl2tpd/xl2tpd.conf
[global]
ipsec saref = yes
port = 1701

[lns default]
ip range = 10.9.0.2-10.9.0.254
local ip = 10.9.0.1
require chap = yes
refuse pap = yes
require authentication = yes
name = LinuxVPNserver
ppp debug = yes
pppoptfile = /etc/ppp/options.xl2tpd
length bit = yes
EOF

cat << 'EOF' > /etc/ppp/options.xl2tpd
ipcp-accept-local
ipcp-accept-remote
ms-dns 8.8.8.8
ms-dns 8.8.4.4
noccp
auth
mtu 1280
mru 1280
nodefaultroute
debug
proxyarp
connect-delay 5000
EOF

systemctl enable strongswan-starter
systemctl restart strongswan-starter
systemctl enable xl2tpd
systemctl restart xl2tpd

umask 022

if [ -f /etc/freeradius/3.0/mods-config/sql/main/mysql/schema.sql ]; then
    mysql radius_db < /etc/freeradius/3.0/mods-config/sql/main/mysql/schema.sql
    mysql radius_db < /etc/freeradius/3.0/mods-config/sql/main/mysql/setup.sql || true
fi

cd /etc/freeradius/3.0/mods-enabled/
ln -sf ../mods-available/sql sql
sed -i 's/^.*driver = "rlm_sql_null".*/\tdriver = "rlm_sql_mysql"/' /etc/freeradius/3.0/mods-available/sql
sed -i 's/^.*dialect = "sqlite".*/\tdialect = "mysql"/' /etc/freeradius/3.0/mods-available/sql
sed -i 's/^.*server = "localhost".*/\tserver = "localhost"/' /etc/freeradius/3.0/mods-available/sql
sed -i 's/^.*port = 3306.*/\tport = 3306/' /etc/freeradius/3.0/mods-available/sql
sed -i 's/^.*password = "radpass".*/\tpassword = "radius_password_123"/' /etc/freeradius/3.0/mods-available/sql
sed -i 's/^.*login = "radius".*/\tlogin = "radius_user"/' /etc/freeradius/3.0/mods-available/sql
sed -i 's/^.*radius_db = "radius".*/\tradius_db = "radius_db"/' /etc/freeradius/3.0/mods-available/sql

sed -i '/^.*tls {/,/^.*}/ s/^/#/' /etc/freeradius/3.0/mods-available/sql
sed -i 's/^#\s*read_clients = yes/read_clients = yes/' /etc/freeradius/3.0/mods-available/sql

sed -i 's/-sql/sql/g' /etc/freeradius/3.0/sites-available/default
sed -i 's/-sql/sql/g' /etc/freeradius/3.0/sites-available/inner-tunnel
chown -R freerad:freerad /etc/freeradius/3.0/

systemctl enable nginx
systemctl enable freeradius
systemctl restart freeradius

echo "[5/8] Moving Radius-UI files to /var/www/radius-ui..."
APP_DIR="/var/www/radius-ui"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR"
cp -r "$INSTALL_DIR/"* "$APP_DIR/"

echo "[6/8] Setting up Node.js Backend..."
cd "$APP_DIR/server"
npm install --omit=dev

cat << 'EOF' > .env
PORT=3000
DB_HOST=localhost
DB_USER=radius_user
DB_PASSWORD=radius_password_123
DB_NAME=radius_db
API_TOKEN=rahasia_bebas_123
SERVER_IDENTITY=Radius-Core
SERVER_DESCRIPTION=Main Radius Server
EOF

pm2 start index.js --name radius-api
pm2 save
env PATH=$PATH:/usr/bin /usr/lib/node_modules/pm2/bin/pm2 startup systemd -u root --hp /root || true

echo "[7/8] Skipping React compilation (already bundled)..."

echo "[8/8] Setting up Nginx Web Server..."
cat << 'EOF' > /etc/nginx/sites-available/radius-ui
server {
    listen 80;
    server_name _;

    root /var/www/radius-ui/client-dist;
    index index.html;

    location / {
        try_files $uri $uri/ /index.html;
    }

    location /api/ {
        proxy_pass http://127.0.0.1:3000/api/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
EOF

ln -sf /etc/nginx/sites-available/radius-ui /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default
systemctl restart nginx

echo "[9/9] Configuring UFW Firewall..."
apt-get install -y ufw
ufw default deny incoming
ufw default allow outgoing

ufw allow 22/tcp      # SSH
ufw allow 80/tcp      # HTTP Web UI
ufw allow 443/tcp     # HTTPS
ufw allow 1812/udp    # FreeRADIUS Auth
ufw allow 1813/udp    # FreeRADIUS Acct
ufw allow 3799/udp    # FreeRADIUS CoA
ufw allow 51820/udp   # WireGuard

ufw --force enable

echo "=========================================================="
echo "âœ… SECURE INSTALLATION COMPLETE!"
echo "You can now access Radius-UI at: http://$(hostname -I | awk '{print $1}')"
echo "Default Username: superadmin"
echo "Default Password: admin123"
echo "=========================================================="
