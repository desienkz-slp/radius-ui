#!/bin/bash
# Plugin installer untuk WireGuard

set -e

PLUGIN_NAME="wireguard"
PLUGIN_DIR="/app/plugins/$PLUGIN_NAME"
PLUGIN_DATA_DIR="/app/plugin-data/$PLUGIN_NAME"

echo "📦 Installing WireGuard Plugin..."

# Create plugin directories
mkdir -p "$PLUGIN_DIR" "$PLUGIN_DATA_DIR"

# Install WireGuard package
echo "📥 Installing WireGuard packages..."
apt-get update
apt-get install -y wireguard wireguard-tools

# Create basic configuration
echo "⚙️ Configuring WireGuard..."

# Generate keys
wg genkey | tee "$PLUGIN_DATA_DIR/server_private.key" | wg pubkey > "$PLUGIN_DATA_DIR/server_public.key"

# Create basic interface configuration
cat > "$PLUGIN_DATA_DIR/wg0.conf" << EOF
[Interface]
PrivateKey = $(cat $PLUGIN_DATA_DIR/server_private.key)
Address = 10.0.0.1/24
ListenPort = 51820
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -A FORWARD -o wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -D FORWARD -o wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE

# Peers will be added dynamically via API
EOF

echo "✅ WireGuard installation complete!"
echo "📍 Configuration stored at: $PLUGIN_DATA_DIR"
echo ""
echo "Server Public Key: $(cat $PLUGIN_DATA_DIR/server_public.key)"
echo ""
echo "To bring up WireGuard interface:"
echo "  sudo ip link add dev wg0 type wireguard"
echo "  sudo ip address add 10.0.0.1/24 dev wg0"
echo "  sudo wg set wg0 private-key <(cat $PLUGIN_DATA_DIR/server_private.key)"
echo "  sudo ip link set wg0 up"
