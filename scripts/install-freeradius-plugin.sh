#!/bin/bash
# Plugin installer untuk FreeRADIUS

set -e

PLUGIN_NAME="freeradius"
PLUGIN_DIR="/app/plugins/$PLUGIN_NAME"
PLUGIN_DATA_DIR="/app/plugin-data/$PLUGIN_NAME"

echo "📦 Installing FreeRADIUS Plugin..."

# Create plugin directories
mkdir -p "$PLUGIN_DIR" "$PLUGIN_DATA_DIR"

# Install FreeRADIUS package
echo "📥 Installing FreeRADIUS packages..."
apt-get update
apt-get install -y freeradius freeradius-mysql freeradius-utils

# Create basic configuration
echo "⚙️ Configuring FreeRADIUS..."
cat > "$PLUGIN_DATA_DIR/clients.conf" << 'EOF'
# FreeRADIUS clients configuration
client 127.0.0.1 {
    ipaddr = 127.0.0.1
    netmask = 32
    secret = testing123
    require_message_authenticator = no
}

client localhost {
    ipaddr = localhost
    netmask = 32
    secret = testing123
    require_message_authenticator = no
}
EOF

# Copy configuration to FreeRADIUS directory
sudo cp "$PLUGIN_DATA_DIR/clients.conf" /etc/freeradius/3.0/clients.conf

echo "✅ FreeRADIUS installation complete!"
echo "📍 Configuration stored at: $PLUGIN_DATA_DIR"
echo ""
echo "To start FreeRADIUS:"
echo "  sudo systemctl start freeradius"
echo ""
echo "To check status:"
echo "  sudo systemctl status freeradius"
