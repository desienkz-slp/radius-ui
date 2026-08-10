#!/bin/bash
echo "=========================================================="
echo "ðŸš€ RADIUS-UI SECURE AUTOMATED UPDATER"
echo "=========================================================="

echo "[1/4] Menarik pembaruan terbaru dari GitHub..."
git fetch origin
git reset --hard origin/main

echo "[2/4] Menyalin file terbaru ke direktori web server (Nginx)..."
cp -r client-dist/* /var/www/radius-ui/client-dist/
cp -r server/* /var/www/radius-ui/server/

echo "[3/4] Mengatur ulang hak akses..."
chown -R www-data:www-data /var/www/radius-ui

echo "[4/4] Me-restart backend API (PM2)..."
pm2 restart radius-api

echo "=========================================================="
echo "âœ… UPDATE BERHASIL!"
echo "Lakukan Hard Refresh (Ctrl + F5) pada browser Anda untuk melihat perubahan."
echo "=========================================================="
