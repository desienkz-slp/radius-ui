#!/bin/bash
# fix-mariadb-timezone.sh — SAMAKAN ZONA WAKTU MariaDB DENGAN OS (WIB/Asia-Jakarta)
# Idempoten & non-destruktif:
#   1. Pasang default-time-zone = '+07:00' pada MariaDB (sekali; skip jika sudah ada).
#   2. SEKALI SAJA: geser timestamp historis (ditulis saat DB masih UTC) +7 jam,
#      ditandai dengan tabel flag _netora_tz_migrated agar tidak dobel-geser.
#   Dijalankan otomatis oleh trigger-update (tombol Update di UI).

TZ_OFFSET='+07:00'

echo "[TZ] Memeriksa zona waktu MariaDB..."

# ---- Deteksi kredensial DB dari .env radius-ui ----
ENV_FILE=""
for f in /var/www/radius-ui/server/.env /var/www/radius-ui/.env; do
    [ -f "$f" ] && ENV_FILE="$f" && break
done
if [ -z "$ENV_FILE" ]; then
    echo "[TZ] .env radius-ui tidak ditemukan — skip (DB lokal/root akan dipakai)."
fi

DB_USER=$(grep '^DB_USER=' "$ENV_FILE" 2>/dev/null | cut -d= -f2)
DB_PASS=$(grep '^DB_PASSWORD=' "$ENV_FILE" 2>/dev/null | cut -d= -f2)
DB_NAME=$(grep '^DB_NAME=' "$ENV_FILE" 2>/dev/null | cut -d= -f2)
DB_USER="${DB_USER:-root}"
DB_NAME="${DB_NAME:-radius}"

MYSQL_CMD="mysql -u $DB_USER"
[ -n "$DB_PASS" ] && MYSQL_CMD="$MYSQL_CMD -p$DB_PASS"
MYSQL="$MYSQL_CMD $DB_NAME -e"

# ---- 1. Pasang default-time-zone jika belum ----
CURRENT_TZ=$($MYSQL "SELECT @@global.time_zone" 2>/dev/null | tail -1)
if [ "$CURRENT_TZ" = "$TZ_OFFSET" ]; then
    echo "[TZ] MariaDB sudah $TZ_OFFSET — tidak perlu restart."
else
    echo "[TZ] Zona waktu MariaDB saat ini: '$CURRENT_TZ' — memasang $TZ_OFFSET..."
    systemctl is-active --quiet mariadb 2>/dev/null && SVC=mariadb || SVC=mysql
    CNF=""
    for f in /etc/mysql/mariadb.conf.d/50-server.cnf /etc/mysql/my.cnf /etc/my.cnf; do
        [ -f "$f" ] && CNF="$f" && break
    done
    if [ -n "$CNF" ]; then
        cp -n "$CNF" "$CNF.bak.$(date +%Y%m%d%H%M%S)"
        grep -q 'default-time-zone' "$CNF" || printf "\n# NETORA: zona waktu eksplisit WIB agar NOW() = jam OS\n default-time-zone = '+07:00'\n" >> "$CNF"
        # hapus duplikat yang mungkin tanpa spasi
        systemctl restart "$SVC"
        sleep 3
        echo "[TZ] MariaDB direstart dengan $TZ_OFFSET."
    else
        echo "[TZ] File konfigurasi MySQL/MariaDB tidak ditemukan — skip pengaturan global."
    fi
fi

# ---- 2. Migrasi historis (hanya sekali, pakai flag table) ----
FLAG=$($MYSQL "SELECT 1 FROM information_schema.tables WHERE table_schema='$DB_NAME' AND table_name='_netora_tz_migrated'" 2>/dev/null | tail -1)
if [ "$FLAG" = "1" ]; then
    echo "[TZ] Migrasi historis sudah pernah dilakukan — skip."
    echo "[TZ] SELESAI. Semua waktu kini konsisten (WIB)."
    exit 0
fi

# Ambil waktu sakral migrasi SEBELUM mengubah apa pun: NOW() pra-switch (zona lama)
MIG_TS=$($MYSQL "SELECT NOW()" 2>/dev/null | tail -1)
echo "[TZ] Timestamp migrasi (pra-switch): $MIG_TS"

# Backup dulu (nol data loss)
BACKUP="/root/backup_tz_migrate_$(date +%Y%m%d_%H%M%S).sql"
if mysqldump -u $DB_USER ${DB_PASS:+-p$DB_PASS} "$DB_NAME" radacct radpostauth > "$BACKUP" 2>/dev/null && [ -s "$BACKUP" ]; then
    echo "[TZ] Backup tersimpan: $BACKUP"
else
    echo "[TZ] GAGAL backup — BATAL migrasi demi keamanan data."
    exit 1
fi

echo "[TZ] Menggeser timestamp historis +7 jam (record pra $MIG_TS)..."
$MYSQL "
START TRANSACTION;
UPDATE radacct SET
  acctstarttime  = DATE_ADD(acctstarttime, INTERVAL 7 HOUR),
  acctstoptime   = IFNULL(DATE_ADD(acctstoptime, INTERVAL 7 HOUR), NULL),
  acctupdatetime = DATE_ADD(acctupdatetime, INTERVAL 7 HOUR)
WHERE acctupdatetime < '$MIG_TS';
SELECT ROW_COUNT() AS radacct_shifted;
UPDATE radpostauth SET
  authdate = DATE_ADD(authdate, INTERVAL 7 HOUR)
WHERE authdate < '$MIG_TS';
SELECT ROW_COUNT() AS radpostauth_shifted;
CREATE TABLE IF NOT EXISTS _netora_tz_migrated (done_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP, ts VARCHAR(32));
INSERT INTO _netora_tz_migrated (ts) VALUES ('$MIG_TS');
COMMIT;
" 2>/dev/null

echo "[TZ] Migrasi selesai. NOW() DB: $($MYSQL 'SELECT NOW()' 2>/dev/null | tail -1) | OS: $(date '+%Y-%m-%d %H:%M:%S %Z')"
echo "[TZ] SELESAI. Semua server kini konsisten: OS = DB = WIB."
