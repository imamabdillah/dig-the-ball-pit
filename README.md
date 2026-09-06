# Dig The Ball Pit — prototipe minggu 1

Loop inti server-authoritative. Gali, buang, upgrade, longsor. Kotak abu-abu,
tanpa aset, tanpa DataStore — sesuai lingkup minggu 1 di dokumen konsep.

## Isi

```
default.project.json          konfigurasi Rojo
src/shared/Config.luau        SELURUH angka balance ada di sini
src/shared/Remotes.luau       tiga RemoteEvent, dibuat server, ditunggu client
src/server/PitService.luau    keadaan kolam sebagai satu angka + bangun dunia
src/server/PlayerData.luau    profil pemain di memori + sinkronisasi atribut
src/server/Main.server.luau   seluruh aturan dan SELURUH validasi
src/client/Main.client.luau   input dan HUD
```

## Menjalankan

Butuh Rojo 7.7 dan plugin Studio-nya. Sekali pasang:

```bash
rojo plugin install
```

### Harian: sinkron hidup

```bash
rojo serve
```

Di Studio, buka panel **Rojo** dari tab Plugins, tekan **Connect**. Simpan file
di editor, perubahannya langsung masuk ke Studio. Tidak ada build ulang, tidak
ada buka-tutup place.

Arahnya satu arah: `src/` sumber kebenaran. Mengedit skrip di dalam Studio
tidak kembali ke `src/`, dan akan tertimpa pada sinkron berikutnya.

### Sesekali: rakit satu file place

```bash
rojo build default.project.json -o place.rbxlx
```

Untuk membuka tanpa plugin, atau mengunggah ke Roblox. `place.rbxlx` adalah
hasil rakitan, bukan sumber — sudah masuk `.gitignore`.

### Struktur yang dihasilkan

| Instance                                         | Jenis        |
| ------------------------------------------------ | ------------ |
| `ReplicatedStorage/Shared/Config`                | ModuleScript |
| `ReplicatedStorage/Shared/Remotes`               | ModuleScript |
| `ServerScriptService/Server/PitService`          | ModuleScript |
| `ServerScriptService/Server/PlayerData`          | ModuleScript |
| `ServerScriptService/Server/Main`                | Script       |
| `StarterPlayer/StarterPlayerScripts/Client/Main` | LocalScript  |

Nama folder `Shared` dan `Server` harus persis — modul saling mencari lewat
nama itu. Sufiks `.server` dan `.client` pada nama file yang menentukan
Script versus LocalScript; `Main.client.luau` di `src/client/` menjadi
LocalScript bernama `Main` di dalam folder `Client`.

Baseplate, spawn, kolam, dan kolom penjualan dibangun otomatis saat runtime.
Tidak ada yang perlu disusun tangan di Workspace.

## Cara main

- **Tahan klik kiri** (atau tahan sentuh) di permukaan kolam untuk menggali
- Kantong penuh, jalan ke **kolom hijau** — penjualan otomatis saat masuk radius
- Tiga tombol di bawah layar untuk upgrade

## Yang dijaga server

Client hanya boleh mengusulkan dua hal: satu `Vector3` titik galian, dan satu
nama jalur upgrade. Semua sisanya dihitung server.

Empat pemeriksaan sebelum sebutir bola berpindah, di `Main.server.luau`:

1. Jarak antar galian minimal `Interval × 0.85` — 15% kelonggaran untuk jitter
2. Rate limit jendela bergulir, maksimal 12 permintaan per 3 detik
3. Jarak pemain ke titik galian di bawah 12 stud
4. Titik galian memang di permukaan kolam, bukan di dalam badannya

Pemeriksaan 1 dan 2 gagal dalam permainan normal, jadi ditolak diam-diam.
Pemeriksaan 3 dan 4 hanya bisa gagal kalau client berbohong, jadi dilaporkan.

Cash tidak pernah dihitung di client, bahkan untuk tampilan. HUD membaca
atribut yang ditulis server.

## Menyetel angka

Semua di `src/shared/Config.luau`. Yang paling sering perlu digeser:

| Knob                     | Sekarang | Pengaruh                             |
| ------------------------ | -------- | ------------------------------------ |
| `Sell.CashPerBall`       | 2        | kecepatan seluruh ekonomi            |
| `Upgrades.tool` cost     | 150      | waktu ke pembelian pertama           |
| `Settle.BaseRate`        | 0.30     | seberapa menyakitkan longsor         |
| `Pit.TotalBalls`         | 5000     | panjang satu putaran kolam           |

Harga di sini lebih murah dari tabel dokumen konsep. Dengan harga dokumen
(Ember 250), pembelian pertama butuh ~3 menit; itu terlalu lama untuk
pembelian pertama. Target 60–90 detik.

Perkiraan kasar dengan angka sekarang: kolam pertama tuntas dalam 11–12 menit,
sesuai target 8–12 menit di dokumen.

## Gerbang minggu 1

Mainkan sendiri 10 menit tanpa menyentuh apa pun yang lain. Kalau bosan di
menit ketiga, angkanya yang salah — jangan tambah grafis untuk menutupinya.

## Diketahui kasar, sengaja dibiarkan

- **Progres hilang saat keluar.** Tanpa DataStore, sesuai lingkup. ProfileStore
  dan session locking masuk minggu 2.
- **Karakter tersentak saat kolam menyusut.** Part yang diubah ukurannya di
  bawah pemain yang berdiri. Hilang di minggu 4 saat kolam jadi mesh.
- **Longsor tanpa efek visual.** Angkanya bekerja, animasinya minggu 3.
- **Satu kolam saja.** Kolam 2–5 dan rebirth masuk minggu 2.
