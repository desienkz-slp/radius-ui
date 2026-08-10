#!/bin/bash
# setup-autoupdate.sh

# Pastikan script dijalankan sebagai root
if [ "$EUID" -ne 0 ]; then
  echo "Harap jalankan script ini menggunakan sudo atau sebagai root."
  exit 1
fi

APP_DIR=$(pwd)
CRON_SCRIPT="/usr/local/bin/radius-auto-update.sh"
LOG_FILE="/var/log/radius-autoupdate.log"

echo "Mempersiapkan fitur Auto-Update untuk direktori: $APP_DIR"

# Buat script pengecekan update
cat <<EOF > $CRON_SCRIPT
#!/bin/bash
cd $APP_DIR || exit 1

# Fetch data terbaru dari github (remote origin) secara diam-diam
git remote update > /dev/null 2>&1

# Ambil hash commit lokal vs remote
LOCAL=\$(git rev-parse @ 2>/dev/null)
REMOTE=\$(git rev-parse @{u} 2>/dev/null)

# Jika gagal membaca branch (mungkin bukan repo git), hentikan
if [ -z "\$LOCAL" ] || [ -z "\$REMOTE" ]; then
    exit 0
fi

# Bandingkan, jika tidak sama, berarti ada update
if [ "\$LOCAL" != "\$REMOTE" ]; then
    echo "======================================" >> $LOG_FILE
    echo "\$(date): Pembaruan sistem terdeteksi!" >> $LOG_FILE
    
    # Jalankan git pull
    git pull >> $LOG_FILE 2>&1
    
    # Restart Node.js (Backend) menggunakan pm2 jika terinstal
    if command -v pm2 &> /dev/null; then
        echo "\$(date): Me-restart proses backend (pm2)..." >> $LOG_FILE
        # Coba restart process 'radius-api', jika gagal restart semua
        pm2 restart radius-api >> $LOG_FILE 2>&1 || pm2 restart all >> $LOG_FILE 2>&1
    else
        echo "\$(date): PERINGATAN - PM2 tidak terdeteksi di path, gagal restart backend." >> $LOG_FILE
    fi
    
    echo "\$(date): Update selesai." >> $LOG_FILE
fi
EOF

# Beri hak eksekusi
chmod +x $CRON_SCRIPT

# Tambahkan ke cron root (/etc/crontab) agar berjalan tiap 1 menit
if ! grep -q "$CRON_SCRIPT" /etc/crontab; then
    # Tambahkan baris cron
    echo "* * * * * root $CRON_SCRIPT" >> /etc/crontab
    echo "Cron job berhasil ditambahkan."
else
    echo "Cron job sudah terpasang."
fi

echo "======================================================"
echo "Sistem Auto-Update / CI/CD (Cron Polling) SUDAH AKTIF!"
echo "Server akan mengecek GitHub tiap menit."
echo "Log proses update otomatis ada di: $LOG_FILE"
echo "======================================================"
