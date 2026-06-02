# Forensic Linux - Adli Bilişim Linux Dağıtımı

Kendin yapabileceğin forensics (adli bilişim) Linux ISO'su.

## ⚠️ BU BİLGİSAYARDA BUILD OLMAZ

Bu proje Linux üzerinde build edilmek üzere tasarlandı. 
Senin bilgisayarında WSL kurulamadığı için (admin yetkisi yok) 
**GitHub Actions** ile ücretsiz cloud'da build alacağız.

---

## 📦 NASIL BUILD ALIRSIN (10 DAKİKA)

### 1. GitHub'a ücretsiz kaydol
- Git: https://github.com/signup
- Mail adresinle kaydol, hesabı onayla

### 2. Yeni repo oluştur
- Sağ üstte `+` işareti → "New repository"
- Repository name: `forensic-linux`
- "Public" seç
- "Create repository" de

### 3. Dosyaları yükle
- Açılan sayfada "uploading an existing file" linkine tıkla
- `linux-distro.zip` dosyasını çıkart (klasörün içindeki tüm dosyaları)
- Tüm dosyaları sürükle-bırak yap
- "Commit changes" de

### 4. Build'i başlat
- GitHub'da repo'nun içinde `Actions` sekmesine tıkla
- "Build Forensic Linux ISO" yazan workflow'u bul
- Sağdaki "Run workflow" dropdown'ına tıkla → "Run workflow" de
- Yeşil check işareti gelene kadar bekle (~30-60 dk)

### 5. ISO'yu indir
- Build bitince `Forensic-Linux-ISO` artifact'ine tıkla
- `.iso` dosyasını indir
- USB'ye yaz: `Rufus` programıyla "DD Image" modunda yaz

---

## 🛠 İÇİNDEKİ ARAÇLAR

**Disk Forensics:**
- Sleuth Kit (autopsy, fls, icat, mmls, etc.)
- TestDisk / PhotoRec
- Foremost
- Guymager
- dc3dd / ddrescue
- AFFLIB / EWF tools

**Memory Forensics:**
- Volatility 3
- Bulc Extractor
- YARA

**File Analysis:**
- Binwalk
- Strings / Hexdump / xxd
- ExifTool / Identify

**Network:**
- Wireshark / TShark
- Nmap / Netcat

**Python Kütüphaneleri:**
- dfVFS, dfImageTools
- Plaso (log2timeline)
- pytsk3, libvshadow, libvhdi, libvmdk
- capstone, pefile
- python-registry

**Özel Scriptler:**
- `disk-acquire.sh` - Adli disk imajı alma (dd + SHA256)
- `file-analyze.sh` - Dosya analizi (hash, string, exif)
- `mem-analyze.sh` - Hafıza dökümü analizi (Volatility3)
- `wipe-disk.sh` - Güvenli silme (zero/DOD/Gutmann)

---

## 💻 MANUAL BUILD (Linux'ta)

Linux makinen varsa direkt build alabilirsin:

```bash
sudo apt update
sudo apt install -y debootstrap wget xorriso mtools grub-pc-bin squashfs-tools build-essential bc bison flex libssl-dev libncurses-dev cpio python3-pip curl git
cd forensic-linux
sudo bash build.sh iso
```

ISO `ForensicOS-1.0-amd64.iso` olarak çıkacak.

---

## 🔧 ÖZELLİKLER

- **Özel Linux 6.12 kernel** - forensics için optimize edilmiş
- **Custom initramfs** - squashfs + overlayfs live boot
- **Debian bookworm** tabanlı rootfs
- **Squashfs** sıkıştırılmış dosya sistemi
- **GRUB** bootloader (normal, safe-mode, memtest, info)
- **forensics** kullanıcısı hazır (şifre: forensics)
- Çalışma alanı: ~/images, ~/cases, ~/tools, ~/reports
