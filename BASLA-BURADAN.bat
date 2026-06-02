@echo off
title Forensic Linux Build
color 0A
echo ============================================
echo     FORENSIC LINUX - BUILD BASLAT
echo ============================================
echo.
echo Bu script GitHub'da build alman icin yardimci.
echo.
echo ============================================
echo ADIM 1: GitHub'a kaydol
echo ============================================
echo 1. https://github.com/signup adresine git
echo 2. Ucretsiz hesap ac, mailini onayla
echo.
start https://github.com/signup
pause
echo.
echo ============================================
echo ADIM 2: Yeni repo olustur
echo ============================================
echo 1. Sag ustteki (+) isareti -^> New repository
echo 2. Repo adi: forensic-linux
echo 3. "Public" sec
echo 4. "Create repository" de
echo.
start https://github.com/new
pause
echo.
echo ============================================
echo ADIM 3: Dosyalari yukle
echo ============================================
echo 1. Acilan sayfada "uploading an existing file" linkine tikla
echo 2. linux-distro klasorunun ICINDEKI tum dosyalari surukle
echo 3. Asagida "Commit changes" de
echo.
echo IPUCU: Klasoru acmak icin:
start C:\Users\LAB5\Desktop\linux-distro
pause
echo.
echo ============================================
echo ADIM 4: Build'i baslat
echo ============================================
echo 1. GitHub'da repo'nun Actions sekmesine tikla
echo 2. "Build Forensic Linux ISO" yazisini bul
echo 3. Sagdaki "Run workflow" -^> "Run workflow" de
echo 4. YESIL tik gelene kadar bekle (~30-60 dk)
echo.
echo ============================================
echo ADIM 5: ISO'yu indir
echo ============================================
echo 1. Build bitince "Forensic-Linux-ISO" artifact'ine tikla
echo 2. .iso dosyasini indir
echo 3. Rufus ile USB'ye yaz (DD Image modu)
echo.
echo ============================================
echo HAZIR!
echo Herhangi bir tusa basarak kapat.
echo ============================================
pause >nul
