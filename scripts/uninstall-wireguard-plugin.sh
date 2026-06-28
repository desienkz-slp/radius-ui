#!/bin/bash
# Plugin uninstaller untuk WireGuard

set -e

PLUGIN_NAME="wireguard"
PLUGIN_DATA_DIR="/app/plugin-data/$PLUGIN_NAME"

echo "🗑️ Uninstalling WireGuard Plugin..."

# Bring down interface
echo "Bringing down WireGuard interface..."
sudo ip link delete wg0 || true

# Uninstall package
echo "Removing WireGuard packages..."
apt-get remove -y wireguard wireguard-tools || true

# Clean up
echo "Cleaning up configuration..."
rm -rf "$PLUGIN_DATA_DIR"

echo "✅ WireGuard uninstalled!"
