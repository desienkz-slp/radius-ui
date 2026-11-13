#!/bin/bash
# fix-mariadb-timezone.sh — SAMAKAN ZONA WAKTU MariaDB DENGAN OS (WIB/Asia-Jakarta)
# Aman untuk semua kondisi server:
#   1. Pasang default-time-zone = '+07:00' (skip jika sudah).
#   2. HANYA jika NOW() DB ternyata BERBEDA dari jam OS (berarti record lama
#      ditulis di zona berbeda): geser timestamp historis +offset yang terukur,
#      sekali saja (flag _netora_tz_migrated). Jika NOW() DB == jam OS, tidak
#      ada yang digeser — hanya flag yang dipasang.

TZ_TARGET='+07:00'
HOUR_TARGET=7

echo "[TZ] Memeriksa zona waktu MariaDB..."

# ---- Kredensial DB dari .env radius-ui ----
ENV_FILE=""
for f in /var/www/radius-ui/server/.env /var/www/radius-ui/.env; do
    [ -f "$f" ] && ENV_FILE="$f" && break
done
DB_USER=$(grep '^DB_USER=' "$ENV_FILE" 2>/dev/null | cut -d= -f2); DB_USER="${DB_USER:-root}"
DB_PASS=$(grep '^DB_PASSWORD=' "$ENV_FILE" 2>/dev/null | cut -d= -f2)
DB_NAME=$(grep '^DB_NAME=' "$ENV_FILE" 2>/dev/null | cut -d= -f2); DB_NAME="${DB_NAME:-radius}"
MYSQL="mysql -u $DB_USER ${DB_PASS:+-p$DB_PASS} $DB_NAME -N -e"

# ---- Flag: sudah pernah diproses? ----
FLAG=$($MYSQL "SELECT 1 FROM information_schema.tables WHERE table_schema='$DB_NAME' AND table_name='_netora_tz_migrated'" 2>/dev/null | tail -1)
if [ "$FLAG" = "1" ]; then
    echo "[TZ] Sudah pernah diproses (flag ada) — tidak ada yang diubah. SELESAI."
    exit 0
fi

# ---- 1. Ukur selisih DB vs OS SEBELUM mengubah apa pun ----
DB_NOW=$($MYSQL "SELECT NOW()" 2>/dev/null | tail -1)
OS_NOW=$(date '+%Y-%m-%d %H:%M:%S')
DIFF_SEC=$($MYSQL "SELECT ABS(TIMESTAMPDIFF(SECOND, '$DB_NOW', '$OS_NOW'))" 2>/dev/null | tail -1)
DIFF_SEC=${DIFF_SEC:-0}
echo "[TZ] NOW() DB: $DB_NOW | OS: $OS_NOW | selisih: ${DIFF_SEC}s"

# ---- 2. Pasang default-time-zone jika belum ----
CURRENT_TZ=$($MYSQL "SELECT @@global.time_zone" 2>/dev/null | tail -1)
if [ "$CURRENT_TZ" != "$TZ_TARGET" ]; then
    echo "[TZ] Zona DB '$CURRENT_TZ' != '$TZ_TARGET' — memasang..."
    systemctl is-active --quiet mariadb 2>/dev/null && SVC=mariadb || SVC=mysql
    CNF=""
    for f in /etc/mysql/mariadb.conf.d/50-server.cnf /etc/mysql/my.cnf /etc/my.cnf; do
        [ -f "$f" ] && CNF="$f" && break
    done
    if [ -n "$CNF" ]; then
        cp -n "$CNF" "$CNF.bak.$(date +%Y%m%d%H%M%S)"
        grep -q 'default-time-zone' "$CNF" || printf "\n# NETORA: zona waktu eksplisit WIB agar NOW() = jam OS\ndefault-time-zone = '+07:00'\n" >> "$CNF"
        systemctl restart "$SVC"
        sleep 3
        echo "[TZ] MariaDB direstart dengan $TZ_TARGET."
    else
        echo "[TZ] Konfigurasi MySQL tidak ditemukan — hanya set runtime."
        $MYSQL "SET GLOBAL time_zone = '$TZ_TARGET';" 2>/dev/null
    fi
fi

# ---- 3. Keputusan migrasi berbasis selisih terukur ----
# Selisih kecil (< 300s) = DB sudah sinkron dengan OS → record historis aman, JANGAN geser.
if [ "$DIFF_SEC" -lt 300 ]; then
    echo "[TZ] DB sudah sinkron dengan OS (selisih ${DIFF_SEC}s < 300s) — tidak ada data yang perlu digeser."
    $MYSQL "CREATE TABLE IF NOT EXISTS _netora_tz_migrated (done_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP, ts VARCHAR(64));
             INSERT INTO _netora_tz_migrated (ts) VALUES ('no-shift-needed diff=${DIFF_SEC}s');" 2>/dev/null
    echo "[TZ] SELESAI. OS = DB = WIB, data historis aman."
    exit 0
fi

# ---- 4. Migrasi historis (hanya jika terbukti DB berbeda dari OS) ----
# Timestamp batas: record pra-switch ditulis dengan jam DB lama (NOW() lama = $DB_NOW).
# Geser sebesar selisih terukur (dibulatkan ke jam penuh, umumnya 25200s = 7h).
SHIFT_SEC=$(( (DIFF_SEC / 3600) * 3600 ))
if [ "$SHIFT_SEC" -lt 3600 ]; then SHIFT_SEC=$((HOUR_TARGET * 3600)); fi
SHIFT_H=$((SHIFT_SEC / 3600))
echo "[TZ] Record historis ditulis dengan zona berbeda — geser +${SHIFT_H} jam."

BACKUP="/root/backup_tz_migrate_$(date +%Y%m%d_%H%M%S).sql"
if mysqldump -u "$DB_USER" ${DB_PASS:+-p$DB_PASS} "$DB_NAME" radacct radpostauth > "$BACKUP" 2>/dev/null && [ -s "$BACKUP" ]; then
    echo "[TZ] Backup tersimpan: $BACKUP"
else
    echo "[TZ] GAGAL backup — BATAL migrasi demi keamanan data."
    exit 1
fi

$MYSQL "
START TRANSACTION;
UPDATE radacct SET
  acctstarttime  = DATE_ADD(acctstarttime, INTERVAL $SHIFT_SEC SECOND),
  acctstoptime   = IFNULL(DATE_ADD(acctstoptime, INTERVAL $SHIFT_SEC SECOND), NULL),
  acctupdatetime = DATE_ADD(acctupdatetime, INTERVAL $SHIFT_SEC SECOND)
WHERE acctupdatetime < '$DB_NOW';
SELECT ROW_COUNT() AS radacct_shifted;
UPDATE radpostauth SET
  authdate = DATE_ADD(authdate, INTERVAL $SHIFT_SEC SECOND)
WHERE authdate < '$DB_NOW';
SELECT ROW_COUNT() AS radpostauth_shifted;
CREATE TABLE IF NOT EXISTS _netora_tz_migrated (done_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP, ts VARCHAR(64));
INSERT INTO _netora_tz_migrated (ts) VALUES ('shift=${SHIFT_H}h cutoff=$DB_NOW');
COMMIT;
" 2>/dev/null

echo "[TZ] Migrasi selesai. NOW() DB: $($MYSQL 'SELECT NOW()' 2>/dev/null | tail -1) | OS: $(date '+%Y-%m-%d %H:%M:%S %Z')"
echo "[TZ] SELESAI. OS = DB = WIB, data historis sudah digeser ${SHIFT_H} jam."
