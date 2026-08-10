# NETORA-Radius

Sistem Manajemen Jaringan berbasis Web UI untuk otentikasi (FreeRADIUS) dan VPN (WireGuard & L2TP).

## Cara Instalasi

1. Download atau *clone* seluruh isi repositori ini ke server Linux Ubuntu 22.04 / 20.04 yang masih bersih (Fresh Install).
2. Masuk ke direktori repositori ini (`cd radius-ui` atau sesuai nama foldernya).
3. Jalankan perintah instalasi otomatis sebagai `root`:
   ```bash
   chmod +x install.sh
   ./install.sh
   ```
4. Tunggu hingga proses selesai. Semua *service* (Nginx, MariaDB, Node.js, FreeRADIUS, WireGuard, L2TP) akan dipasang otomatis.

## Login Default

Setelah instalasi selesai, buka IP Address server Anda di browser (misal: `http://192.168.1.10` atau domain).

- **Username Default**: `superadmin`
- **Password Default**: `admin123`

âš ï¸ **Sangat disarankan** untuk segera mengganti password `superadmin` setelah berhasil login pertama kali demi keamanan server Anda.

## Cara Update (Pembaruan)

Jika ada pembaruan kode terbaru di GitHub dan Anda ingin memperbarui aplikasi di server Anda yang sudah berjalan, ikuti langkah ini:

1. Masuk ke folder *clone* repositori Anda (bukan folder instalasi Nginx), misalnya:
   ```bash
   cd ~/radius-ui
   ```
2. Tarik pembaruan terbaru dari GitHub:
   ```bash
   git pull origin main
   ```
   *(Jika Anda mendapati error "unrelated histories" karena riwayat GitHub telah di-reset oleh developer, gunakan perintah ini sebagai gantinya: `git fetch origin && git reset --hard origin/main`)*
3. Salin/Timpa file terbaru ke direktori aktif (Nginx):
   ```bash
   cp -r ~/radius-ui/client-dist/* /var/www/radius-ui/client-dist/
   cp -r ~/radius-ui/server/* /var/www/radius-ui/server/
   ```
4. Restart *backend API* agar memuat kode *server* terbaru:
   ```bash
   pm2 restart radius-api
   ```
5. Lakukan **Hard Refresh (Ctrl + F5)** pada browser Anda untuk melihat perubahan tampilan.
