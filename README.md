# PaceUp 🏃

**Level up every run.**

[![Android APK](https://github.com/rois-etalas/paceup/actions/workflows/android.yml/badge.svg)](https://github.com/rois-etalas/paceup/actions/workflows/android.yml)
[![Web](https://github.com/rois-etalas/paceup/actions/workflows/web.yml/badge.svg)](https://github.com/rois-etalas/paceup/actions/workflows/web.yml)

Aplikasi pelacak lari & aktivitas outdoor bergaya Strava, dibangun dengan **Flutter** + **PostgreSQL/Supabase**.

Rekam lari, hitung jarak, pace, split, elevasi, dan kalori secara real time — lalu bagikan ke feed sosial, kumpulkan kudos, dan bersaing di leaderboard.

---

## Mengapa "PaceUp"?

Nama dipilih karena bisa **dimiliki** dan langsung **menjual manfaat**:

| Kriteria | PaceUp | Alternatif populer |
|---|---|---|
| Arti langsung terbaca pelari | ✅ "pace" = istilah inti lari | Stride/Tempo sudah jadi merek besar |
| Bisa dimenangi di SEO/app store | ✅ tidak ada benturan | "Stride", "Tempo", "Pacer" sudah dikuasai perusahaan lain |
| Pendek & mudah diucapkan | ✅ 2 suku kata | "Cadence" sulit diingat orang awam |
| Janji peningkatan diri | ✅ "up" = naik level | — |

Tagline: **"Level up every run."** — menjual progres, bukan sekadar pencatatan.

---

## Fitur

### Perekaman aktivitas (inti)
- **Deteksi GPS** dengan penyaringan sinyal berlapis:
  - membuang titik berakurasi buruk (> 35 m),
  - menolak "teleport" / lompatan sinyal,
  - mengabaikan drift saat pengguna diam,
  - penghalusan kecepatan (EMA + moving window).
- **Deteksi jenis aktivitas otomatis** dari kecepatan (lari, trail, jalan, sepeda) — tetap bisa diubah manual.
- **Jarak** akurat dengan rumus Haversine.
- **Pace** saat ini, pace rata-rata, dan **kecepatan maksimal**.
- **Split per kilometer** (titik potong diinterpolasi agar pace tiap km tepat).
- **Elevasi** naik/turun dengan ambang noise 2 m.
- **Kadens** (langkah per menit) dan **detak jantung** (bila sensor tersedia).
- **Kalori** berbasis MET (memperhitungkan berat badan & pace).
- **Estimasi VO₂max** (formula Uth–Sørensen).
- **Auto-pause** saat berhenti, **elapsed vs moving time**.
- **Rekaman latar belakang** (foreground service di Android, background modes di iOS).

### Sosial
- Feed aktivitas orang yang diikuti + diri sendiri.
- **Kudos** (optimistic update, terasa instan).
- **Komentar**.
- **Follow / unfollow**.
- Profil atlet lain, saran atlet, pengikut & mengikuti.

### Statistik
- **Leaderboard** per periode (minggu/bulan/tahun/sepanjang waktu) × metrik (jarak/elevasi/pace).
- **Dasbor mingguan** dengan grafik volume harian.
- **Rekor pribadi (PR)**: 1K/5K/10K/Half tercepat, jarak terjauh, pace terbaik, elevasi terbanyak.
- Grafik volume 30 hari.

### Teknis
- **Peta rute** tanpa API key (CustomPaint), tetap tampil di feed.
- **Mode offline**: aktivitas yang gagal diunggah masuk antrean lalu dikirim ulang.
- **Dua backend dalam satu basis kode**: lokal (demo) & Supabase — UI tidak berubah.
- **RLS ketat** di Postgres: privasi per-aktivitas dihormati di level database.

---

## Coba tanpa memasang apa pun

### Di browser ponsel
Buka **https://rois-etalas.github.io/paceup/** lalu login dengan `demo@paceup.app` / `paceup123`.

GPS di browser bekerja lewat HTTPS (Pages sudah HTTPS) dan izin lokasi diminta saat menekan MULAI LARI.

### Pasang APK Android
APK dibangun otomatis di GitHub Actions, jadi tidak perlu memasang Android SDK di komputer:

1. Buka tab **Actions** → workflow **Android APK** → run terbaru.
2. Unduh artifact **`paceup-apk`** (berisi satu berkas `.apk`).
3. Kirim APK ke ponsel (kabel, Google Drive, atau `adb install`).
4. Di ponsel, aktifkan **"Install dari sumber tidak dikenal"** untuk aplikasi pengirim berkas, lalu buka APK-nya.

Atau lewat terminal:

```bash
# Unduh lewat GitHub CLI
gh run download -R rois-etalas/paceup -n paceup-apk

# Pasang langsung ke ponsel yang tersambung USB
adb install paceup-*.apk
```

> APK ini ditandatangani dengan **debug key**, cocok untuk pengujian pribadi — bukan untuk Play Store. Untuk rilis nyata, tambahkan keystore lewat GitHub Secrets.

## Menjalankan

### 1. Prasyarat
- Flutter **3.24+** (diuji pada 3.47)
- Untuk Android: Android SDK + JDK 17
- Untuk iOS: Xcode + CocoaPods

```bash
flutter --version
flutter doctor
```

### 2. Jalankan langsung (mode demo)

Tanpa konfigurasi apa pun, aplikasi berjalan penuh secara lokal:

```bash
cd paceup
flutter pub get
flutter run
```

Isi halaman login dengan akun contoh:
```
demo@paceup.app / paceup123
```

Mode demo menyemai otomatis: 4 pelari, 14 aktivitas dengan rute & elevasi, kudos, komentar, dan follow. Data disimpan di perangkat (`SharedPreferences`).

### 3. Jalankan dengan Supabase

```bash
flutter run \
  --dart-define=SUPABASE_URL=https://xxxx.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=eyJhbGciOi...
```

Wire-up-nya otomatis: kunci ada → pakai Supabase; kosong → mode demo.

Untuk CI, simpan kredensial sebagai repository secrets (**Settings → Secrets and variables → Actions**):

| Secret | Isi |
|---|---|
| `SUPABASE_URL` | URL proyek Supabase |
| `SUPABASE_ANON_KEY` | Anon/publishable key |

Bila kedua secret kosong, APK & web yang dibangun otomatis memakai mode demo.

---

## Menyiapkan Database

Urutan eksekusi (Supabase Dashboard → SQL Editor, atau `psql`):

| # | Berkas | Isi |
|---|---|---|
| 1 | `sql/schema.sql` | Tabel, enum, index, trigger, view, fungsi izin |
| 2 | `sql/rls.sql` | Row Level Security + policy |
| 3 | `sql/functions.sql` | RPC: `personal_records`, `best_effort`, `weekly_summary`, `nearby_activities`, `search_athletes` |
| 4 | `sql/seed.sql` | Data contoh (opsional) |

```bash
psql "$DATABASE_URL" -f sql/schema.sql
psql "$DATABASE_URL" -f sql/rls.sql
psql "$DATABASE_URL" -f sql/functions.sql

# Data contoh untuk akun tertentu (daftarkan dulu lewat aplikasi):
psql "$DATABASE_URL" -v email='kamu@contoh.com' -f sql/seed.sql
```

Di Supabase SQL Editor, jalankan isi berkasnya langsung, lalu:
```sql
select set_config('paceup.seed_email', 'kamu@contoh.com', false);
-- lanjutkan dengan isi seed.sql
```

### Struktur tabel

| Tabel | Isi |
|---|---|
| `profiles` | Profil + cache statistik (jumlah aktivitas, total jarak/elevasi, follower) |
| `activities` | Ringkasan aktivitas: jarak, durasi, pace, elevasi, kalori, bounding box rute |
| `activity_points` | Titik GPS mentah (dengan `seq` untuk urutan yang pasti) |
| `kudos` | Kudos (PK gabungan `activity_id` + `user_id`) |
| `comments` | Komentar |
| `follows` | Relasi pengikut |

**View:** `activity_details`, `leaderboard_weekly`, `leaderboard_monthly`, `leaderboard_yearly`, `leaderboard_all_time`.

Semua statistik agregat di-*cache* lewat trigger, jadi feed & leaderboard tidak perlu menjumlahkan seluruh tabel setiap kali dibuka.

### Privasi (RLS)

Aturan yang **diuji dengan data nyata**, bukan sekadar ditulis:

| Skenario | Hasil |
|---|---|
| Non-pengikut membuka aktivitas `followers` | ❌ ditolak |
| Non-pengikut membuka aktivitas profil privat | ❌ ditolak |
| Pengikut membuka aktivitas `followers` | ✅ diizinkan |
| Pemilik membuka aktivitas `only_me` | ✅ diizinkan |
| Titik GPS aktivitas yang tidak boleh dilihat | ❌ kosong |
| Memberi kudos/komentar ke aktivitas terlarang | ❌ ditolak |
| Memalsukan `user_id` saat insert | ❌ ditolak |
| Mengubah/menghapus aktivitas orang lain | ❌ 0 baris terpengaruh |
| Leaderboard | hanya menghitung aktivitas yang boleh dilihat |

Detail penting:
- `activity_details` memakai `security_invoker = true`. Tanpa ini, view berjalan sebagai owner dan **membocorkan** aktivitas `only_me`.
- View leaderboard berjalan sebagai owner (butuh agregat lintas pengguna) tetapi hanya menghitung aktivitas yang lolos `can_view_activity()`. Tanpa filter ini, anggota non-pengikut akan melihat total jarak dari aktivitas `followers` yang seharusnya tersembunyi.

---

## Arsitektur

```
lib/
├── main.dart                  # Titik masuk: pilih backend → jalankan app
├── router.dart                # go_router + bottom nav + redirect saat belum login
├── providers.dart             # Riverpod: repository, auth, feed, leaderboard
├── core/
│   ├── env.dart               # Konfigurasi --dart-define
│   ├── geo.dart               # Haversine, bearing + GpsFilter (inti deteksi lari)
│   ├── metrics.dart           # Mesin metrik + split (fungsi murni, teruji)
│   ├── date_format.dart       # Format tanggal aman (fallback locale)
│   └── theme.dart             # Tema & palet
├── data/
│   ├── models/models.dart     # Profile, Activity, RunPoint, polyline codec
│   ├── local/local_store.dart # SharedPreferences (mode offline)
│   └── repositories/          # Kontrak + 2 implementasi
├── services/
│   ├── location_service.dart      # Izin + stream GPS
│   ├── recording_controller.dart  # State machine perekaman
│   └── sync_service.dart          # Antrean unggah offline
├── features/                  # Layar per domain
│   ├── auth/  home/  record/  activity/  leaderboard/  profile/
└── widgets/                   # RouteMap, MetricTile, MiniBarChart, dll.
```

### Keputusan desain penting

**1. Satu kontrak, dua backend.** `PaceUpRepository` diimplementasikan oleh `LocalRepository` dan `SupabaseRepository`. UI hanya bergantung pada antarmuka, sehingga mode demo dan produksi memakai kode halaman yang identik.

**2. Logika inti murni & teruji.** `GpsFilter` dan `MetricsEngine` tidak menyentuh jaringan, UI, maupun penyimpanan. Semua perhitungan jarak/pace/split/elevasi bisa diuji tanpa emulator.

**3. Statistik dihitung di server.** Agregat (leaderboard, PR, ringkasan mingguan) dilakukan Postgres agar data tidak perlu ditarik semua ke perangkat.

**4. Peta tanpa API key.** Rute digambar dengan `CustomPaint` dari encoded polyline — aplikasi langsung jalan, tanpa biaya tile. Ingin peta ber-tile? Tambahkan `flutter_map` dan ganti `RouteMap`.

---

## Pengujian

```bash
flutter analyze     # No issues found!
flutter test        # 34 test, semua lulus
```

| Berkas | Cakupan |
|---|---|
| `test/metrics_test.dart` | Haversine, bearing, penyaringan GPS, split, elevasi, kalori, VO₂max, polyline, serialisasi |
| `test/app_flow_test.dart` | Login, routing, render feed, navigasi tab, kudos/komentar, leaderboard, PR, signup |

Skema database diuji dengan **Postgres 16 asli** (stub `auth.users` + `auth.uid()`), termasuk pengujian penetrasi RLS antar pengguna.

---

## Kalibrasi GPS

Ambang penyaringan ada di `GpsFilterConfig` (`lib/core/geo.dart`):

```dart
GpsFilterConfig(
  maxAccuracyMeters: 35,   // buang fix dengan akurasi lebih buruk
  minDistanceMeters: 3,    // abaikan drift saat diam
  maxSpeedMps: 12.5,       // ~45 km/jam: di atas ini bukan lari
  maxJumpMeters: 150,      // lompatan koordinat tak wajar
  smoothingWindow: 5,      // jendela penghalusan kecepatan
)
```

Untuk aktivitas non-lari, longgarkan `maxSpeedMps`. Ambang auto-pause ada di `RecordingController` (`autoPauseSpeedThreshold`).

---

## Batasan yang diketahui

- **`activity_points` tumbuh cepat** (~900 baris per 10 km pada 4 detik/titik). Untuk pengguna besar, arsipkan titik lama atau kurangi frekuensi sampling.
- **Estimasi kadens** dihitung dari kecepatan, bukan pedometer — nilainya perkiraan yang wajar, bukan pengukuran sensor.
- **Peta tanpa tile** menampilkan bentuk rute tanpa konteks jalan. Tambahkan `flutter_map` untuk peta sebenarnya.
- **Detak jantung** perlu perangkat wearable; saat ini kolomnya sudah disediakan dan akan terisi bila tersedia.
- **Uji di perangkat asli** masih perlu dilakukan untuk memvalidasi akurasi GPS, konsumsi baterai, dan perilaku rekaman latar belakang di iOS/Android.

---

## Lisensi

MIT.
