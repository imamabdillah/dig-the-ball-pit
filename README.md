# Dig The Ball Pit — prototipe minggu 1

Loop inti server-authoritative. Gali, buang, upgrade, longsor. Kotak abu-abu,
tanpa aset, tanpa DataStore — sesuai lingkup minggu 1 di dokumen konsep.

## Isi

```
default.project.json               konfigurasi Rojo
src/shared/Config.luau             SELURUH angka balance ada di sini
src/shared/Remotes.luau            empat RemoteEvent, dibuat server, ditunggu client
src/server/PitService.luau         satu kolam per pemain, satu angka masing-masing
src/server/PlayerData.luau         profil, session locking, sinkronisasi atribut
src/server/Main.server.luau        seluruh aturan dan SELURUH validasi
src/server/vendor/ProfileStore.luau  dependensi pihak ketiga, jangan diedit
src/client/Main.client.luau        input dan HUD
```

`vendor/ProfileStore.luau` disalin apa adanya dari
[MadStudioRoblox/ProfileStore](https://github.com/MadStudioRoblox/ProfileStore)
(MIT), commit `9580f7c`. Perbarui dengan mengunduh ulang, jangan menambal
tangan — tambalan lokal akan hilang pada pembaruan berikutnya.

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
- Kolam kosong → tombol **REBIRTH** muncul. Rebirth menghapus seluruh belanjaan
  dan cash, menyimpan gems, menambah pengali cash permanen, dan pada ambang
  tertentu membuka kolam yang lebih besar

## Satu kolam per pemain

Tiap pemain mendapat petaknya sendiri, berjarak 140 stud. Rebirth membuka kolam
yang lebih besar per pemain, jadi satu kolam bersama tidak bisa mewakili dua
pemain di tier berbeda.

Jarak petak itu juga yang mengamankan galian: `Dig.MaxDistance` hanya 12 stud,
jadi tidak ada posisi berdiri yang bisa menjangkau dua kolam sekaligus.

## Yang dijaga server

Client hanya boleh mengusulkan tiga hal: satu `Vector3` titik galian, satu nama
jalur upgrade, dan permintaan rebirth tanpa argumen. Semua sisanya dihitung
server.

Enam pemeriksaan sebelum sebutir bola berpindah, di `Main.server.luau`:

1. Rate limit jendela bergulir, maksimal 12 permintaan per 3 detik — menghitung
   **setiap** permintaan masuk, bukan hanya yang berhasil
2. Jarak sejak galian terakhir yang berhasil, minimal `Interval × 0.85`
3. Jarak pemain ke titik galian di bawah 12 stud
4. Titik galian di permukaan kolam **milik pemain itu**
5. Pemain tidak berdiri di zona mati sekitar corong
6. Kantong masih ada ruang

Pemeriksaan 1 dan 2 gagal dalam permainan normal, jadi ditolak diam-diam.
Sisanya dilaporkan ke pemain.

Cash tidak pernah dihitung di client, bahkan untuk tampilan. HUD membaca
atribut yang ditulis server.

Kantong sengaja tidak ikut disimpan. Bola dalam kantong sudah keluar dari kolam
tapi belum jadi cash; kalau keadaan itu ikut tersimpan, pemain bisa keluar
dengan kantong penuh dan menjualnya lagi di server lain.

## Menyetel angka

Semua di `src/shared/Config.luau`. Yang paling sering perlu digeser:

| Knob                       | Sekarang | Pengaruh                           |
| -------------------------- | -------- | ---------------------------------- |
| `Sell.CashPerBall`         | 2        | kecepatan seluruh ekonomi          |
| `Upgrades.tool` cost       | 150      | waktu ke pembelian pertama         |
| `Settle.BaseRate`          | 0.30     | seberapa menyakitkan longsor       |
| `Sell.NoDigRadius`         | 16       | biaya lari, dan nilai jalur kantong |
| `Pit.Tiers[n].TotalBalls`  | 5000+    | panjang satu putaran kolam         |
| `Rebirth.UnlocksPitAt`     | 1,3,6,10 | seberapa jauh kolam berikutnya     |

Harga di sini lebih murah dari tabel dokumen konsep. Dengan harga dokumen
(Ember 250), pembelian pertama butuh ~3 menit; itu terlalu lama untuk
pembelian pertama. Target 60–90 detik.

Perkiraan kasar dengan angka sekarang: kolam pertama tuntas dalam 11–12 menit,
sesuai target 8–12 menit di dokumen.

## Gerbang minggu 1

Mainkan sendiri 10 menit tanpa menyentuh apa pun yang lain. Kalau bosan di
menit ketiga, angkanya yang salah — jangan tambah grafis untuk menutupinya.

## Menyimpan progres

Memakai ProfileStore, bukan DataStore mentah. Yang dibeli dari situ adalah
**session locking**: satu profil hanya aktif di satu server pada satu waktu.
Tanpa itu, pemain masuk ke dua server sekaligus, belanja di keduanya, dan yang
menyimpan terakhir menang — cara paling umum mata uang digandakan di genre ini.

Bawaan saat ini `Config.Save.UseMockInStudio = true`, jadi di Studio semuanya
memakai penyimpanan tiruan di memori. Itu membuat loop bisa diuji tanpa
persiapan apa pun, **tapi tidak menguji session locking** — mock hidup di satu
server dan tidak ada server kedua yang bisa melihatnya.

Untuk menguji penyimpanan sungguhan:

1. Studio → **Game Settings → Security → Enable Studio Access to API Services**
2. Publikasikan place ke Roblox. DataStore tidak berfungsi di place lokal
3. Setel `Config.Save.UseMockInStudio = false`
4. Uji sungguhannya: masuk ke dua server sekaligus dan pastikan yang kedua
   menendang yang pertama, dan gems tidak bisa digandakan

Kalau bentuk data berubah tidak kompatibel, **naikkan** `Config.Save.StoreName`.
Menulis bentuk baru ke nama lama merusak profil yang sudah ada, dan itu tidak
bisa dibatalkan.

## Diketahui kasar, sengaja dibiarkan

- **Karakter tersentak saat kolam menyusut.** Part yang diubah ukurannya di
  bawah pemain yang berdiri. Hilang di minggu 4 saat kolam jadi mesh.
- **Longsor tanpa efek visual.** Angkanya bekerja lewat baris HUD, animasinya
  minggu 3.
- **Gems belum ada gunanya.** Wadahnya sudah ada; barang hilang dan buku
  koleksi yang memakainya masuk minggu 3.
