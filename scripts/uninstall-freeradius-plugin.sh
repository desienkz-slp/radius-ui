#!/bin/bash
# Plugin uninstaller untuk FreeRADIUS

set -e

PLUGIN_NAME="freeradius"
PLUGIN_DATA_DIR="/app/plugin-data/$PLUGIN_NAME"

echo "🗑️ Uninstalling FreeRADIUS Plugin..."

# Stop service
echo "Stopping FreeRADIUS service..."
sudo systemctl stop freeradius || true

# Uninstall package
echo "Removing FreeRADIUS packages..."
apt-get remove -y freeradius freeradius-mysql freeradius-utils || true

# Clean up
echo "Cleaning up configuration..."
rm -rf "$PLUGIN_DATA_DIR"

echo "✅ FreeRADIUS uninstalled!"
