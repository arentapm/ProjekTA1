# 📡 Aplikasi Prediksi Kualitas Jaringan (QoS) pada Layer 7
### Hybrid MSSA-LSTM | Flutter + FastAPI

Aplikasi monitoring dan prediksi kualitas layanan (QoS) jaringan WiFi berbasis traffic **Layer 7 (Application Layer)**, menggunakan model *hybrid* **MSSA (Multivariate Singular Spectrum Analysis) + LSTM**. Terdiri dari dua bagian utama:

- **Backend** — REST API (FastAPI) yang menjalankan model prediksi (TensorFlow/Keras)
- **Mobile App** — Aplikasi Android (Flutter) untuk monitoring real-time dan menampilkan hasil prediksi

---

## 📁 Struktur Proyek

**backend/**
- main.py — Entry point FastAPI
- models/
  - model_qos_dengan_MSSA.keras
  - scaler_feat.pkl
  - config.json
- requirements.txt

**mobile_app/**
- lib/
- pubspec.yaml
- android/

---

## ⚙️ Persyaratan Sistem

| Komponen | Versi Minimal |
|---|---|
| Python | 3.10+ (disarankan 3.13 sesuai penelitian) |
| Flutter SDK | 3.x |
| Android SDK | API 34 (Android 14) |
| RAM | minimal 8 GB |

---

## 🚀 1. Menjalankan Backend (Server Prediksi)

### 1.1 Clone & masuk ke folder backend
````bash
git clone <https://github.com/arentapm/backendML1.git>   
cd backend
````

### 1.2 Buat virtual environment

````bash
python -m venv venv

# Aktifkan venv
# Windows:
venv\Scripts\activate
# Linux/Mac:
source venv/bin/activate
````

### 1.3 Install dependency

````bash
pip install -r requirements.txt
````

Isi minimal `requirements.txt`:

````
fastapi
uvicorn
tensorflow
numpy
pandas
scikit-learn
joblib
python-multipart
````

### 1.4 Pastikan file model tersedia

Folder `backend/models/` harus berisi 3 file hasil training:

````
model_qos_dengan_MSSA.keras
scaler_feat.pkl
config.json
````

### 1.5 Jalankan server

````bash
uvicorn main:app --host 0.0.0.0 --port 8000 --reload
````

Server akan berjalan di:

````
http://127.0.0.1:8000
````

Dokumentasi API otomatis (Swagger) bisa diakses di:

````
http://127.0.0.1:8000/docs
````

### 1.6 Endpoint yang tersedia

| Method | Endpoint          | Deskripsi                                             |
| ------ | ----------------- | ------------------------------------------------------ |
| GET    | `/`                | Root / cek server aktif                                |
| GET    | `/status`          | Cek kesiapan server & model                             |
| POST   | `/predict`         | Prediksi 1 langkah ke depan (butuh 110 baris data QoS)  |
| POST   | `/predict_future`  | Prediksi multi-step (5 menit / 2 jam) — async job       |

---

## 📱 2. Menjalankan Aplikasi Mobile (Flutter)

### 2.1 Masuk ke folder aplikasi

````bash
cd mobile_app
````

### 2.2 Install dependency Flutter

````bash
flutter pub get
````

### 2.3 Atur URL backend

Buka file konfigurasi API (misal `lib/config/api_config.dart`) dan sesuaikan alamat backend:

````dart
// sesuaikan dengan IP backend Anda
const String baseUrl = "http://192.168.x.x:8000";
````

> ⚠️ Karena backend dan HP Android harus dalam satu jaringan WiFi yang sama saat testing lokal, gunakan **IP lokal komputer** (bukan `localhost`/`127.0.0.1`). Cek IP dengan `ipconfig` (Windows) atau `ifconfig` (Linux/Mac).

### 2.4 Jalankan aplikasi

Pastikan perangkat Android (fisik atau emulator, min. API 34) sudah terhubung:

````bash
flutter devices     
flutter run
````

### 2.5 Build APK (untuk instalasi manual)

````bash
flutter build apk --release
````

APK hasil build akan tersedia di:

````
build/app/outputs/flutter-apk/app-release.apk
````

---

## 🧭 3. Panduan Penggunaan Aplikasi

1. **Buka aplikasi** → akan tampil menu **Dashboard** dalam kondisi *Tidak Aktif*.
2. Tekan **"Aktifkan Monitoring"** → aplikasi mulai mengambil data Throughput, Delay, Jitter, dan SINR setiap 1 detik, dan menyimpannya ke SQLite lokal.
3. Buka menu **Monitoring** untuk melihat grafik real-time dan detail tiap parameter (tekan card parameter untuk melihat riwayat & standar TIPHON/ITU-T).
4. Buka menu **Prediksi**:

   * Tunggu hingga data mencapai **110 sampel** (progress bar penuh & status "Dataset siap diproses").
   * Tekan **"Jalankan Prediksi"**, lalu pilih interval:

     * **5 menit ke depan** → 300 titik prediksi (demo cepat)
     * **Setiap 30 menit (2 jam)** → 4 titik prediksi (jangka panjang)
   * Hasil prediksi (QoS Index 0–100) akan tampil beserta grafik dan level peringatan (Kritis/Waspada/Normal/Prima).
5. Buka menu **Status** untuk mengecek koneksi ke backend, info model yang digunakan, dan mengekspor data hasil monitoring ke **Excel**.

---

## 🔧 Troubleshooting

| Masalah | Solusi |
|---|---|
| App tidak bisa konek ke backend | Pastikan HP & PC satu jaringan WiFi, cek `baseUrl`, dan izinkan port 8000 di firewall |
| Model gagal dimuat (`/status` error) | Pastikan 3 file di `models/` lengkap dan path-nya benar |
| Prediksi selalu "Data belum cukup" | Tunggu monitoring berjalan hingga 110 sampel (± 2 menit dengan interval 1 detik) |
| `ModuleNotFoundError: tensorflow` | Jalankan ulang `pip install -r requirements.txt` di venv yang aktif |

---

## 👩‍💻 Kontributor

**Arenta Putri Maharani** — NPM 233307034
Program Studi D-III Teknologi Informasi, Politeknik Negeri Madiun

Pembimbing:

* Gus Nanang Syaifuddin, S.Kom., M.Kom.
* Muhammad Syaeful Fajar, S.Pd., Gr., M.Kom.

---

## 📄 Lisensi

Proyek ini dibuat untuk keperluan Tugas Akhir (Akademik). 
````
