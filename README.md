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

Jika ada pembaruan kode terbaru di GitHub dan Anda ingin memperbarui aplikasi di server Anda yang sudah berjalan, Anda dapat menggunakan script pembaruan otomatis yang telah disediakan.

1. Masuk ke folder *clone* repositori Anda (bukan folder instalasi Nginx), misalnya:
   ```bash
   cd /var/www/radius-ui
   ```
2. Jalankan script update:
   ```bash
   bash update.sh
   ```

*(Jika Anda mendapati error "fatal: not a git repository" saat update, itu berarti server Anda belum terhubung dengan Git. Jalankan perintah ini: `git init && git remote add origin https://github.com/desienkz-slp/radius-ui.git && git fetch && git reset --hard origin/main`)*
