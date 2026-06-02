#=============================================================================
#  Windows Build Helper for Forensic Linux Distribution
#  Sets up WSL Ubuntu and runs the build inside it
#=============================================================================

$ProjectDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$DistroName = Split-Path -Leaf $ProjectDir
$WslDistro = "ForensicLinux"

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  Forensic Linux Distribution Build" -ForegroundColor Cyan
Write-Host "  Windows Build Helper v1.0" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

# Check admin rights
$IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $IsAdmin) {
    Write-Host "WARNING: This script needs Administrator privileges for WSL." -ForegroundColor Yellow
    Write-Host "Right-click PowerShell and select 'Run as Administrator'." -ForegroundColor Yellow
    Write-Host ""
}

# Check WSL
$wsl = Get-Command wsl.exe -ErrorAction SilentlyContinue
if (-not $wsl) {
    Write-Host "ERROR: WSL not found. Install WSL first:" -ForegroundColor Red
    Write-Host "  wsl --install -d Ubuntu" -ForegroundColor Yellow
    Write-Host "  Then restart and run this script again." -ForegroundColor Yellow
    exit 1
}

# Menu
Write-Host "Select build option:" -ForegroundColor Green
Write-Host "  1. Install WSL Ubuntu (if not installed)" -ForegroundColor White
Write-Host "  2. Build ISO (full build in WSL)" -ForegroundColor White
Write-Host "  3. Build ISO with custom name" -ForegroundColor White
Write-Host "  4. Enter WSL shell (manual build)" -ForegroundColor White
Write-Host "  5. Copy ISO to Windows" -ForegroundColor White
Write-Host ""

$choice = Read-Host "Choice (1-5)"
Write-Host ""

switch ($choice) {
    "1" {
        Write-Host "Installing WSL Ubuntu..." -ForegroundColor Yellow
        wsl --install -d Ubuntu
        Write-Host "DONE" -ForegroundColor Green
        Write-Host "Restart your terminal, then run option 2." -ForegroundColor Yellow
    }
    "2" {
        Write-Host "Copying project to WSL and building..." -ForegroundColor Yellow
        wsl -d Ubuntu -- bash -c "
            sudo apt-get update -qq && sudo apt-get install -y -qq debootstrap wget xorriso mtools grub-pc-bin squashfs-tools build-essential libncurses-dev bc bison flex libssl-dev && \
            cd ~ && rm -rf linux-distro && mkdir -p linux-distro && \
            exit
        "
        # Copy project files
        Copy-Item -Path "$ProjectDir\*" -Destination "\$env:USERPROFILE\AppData\Local\Packages\*\LocalState\rootfs\home\$env:USERNAME\linux-distro" -Recurse -Force -ErrorAction SilentlyContinue
        
        # Alternative: copy via WSL filesystem
        wsl -d Ubuntu -- mkdir -p ~/linux-distro 2>$null
        
        # Build
        wsl -d Ubuntu -- bash -c "
            cd ~/linux-distro && \
            echo 'Starting build...' && \
            sudo ./build.sh 2>&1 | tee build.log
        "
        Write-Host "Build complete!" -ForegroundColor Green
    }
    "3" {
        $name = Read-Host "Enter distribution name"
        if (-not $name) { $name = "ForensicOS" }
        Write-Host "Building '$name'..." -ForegroundColor Yellow
        
        wsl -d Ubuntu -- bash -c "
            sudo apt-get update -qq && sudo apt-get install -y -qq debootstrap wget xorriso mtools grub-pc-bin squashfs-tools build-essential bc bison flex libssl-dev 2>&1 | tail -1
        "
        # Rename project directory in WSL
        wsl -d Ubuntu -- bash -c "
            rm -rf ~/$name ~/linux-distro && \
            sudo mkdir -p ~/$name && \
            sudo chown \$(whoami):\$(whoami) ~/$name
        "
        # Copy files via tar
        wsl -d Ubuntu -- bash -c "
            cd ~/$name && \
            # Create build.sh
            cat > build.sh << 'SCRIPT'
#!/bin/bash
$(Get-Content "$ProjectDir\build.sh" -Raw)
SCRIPT
            chmod +x build.sh
            mkdir -p configs scripts
        "
        
        Write-Host "Manual setup needed for full automation." -ForegroundColor Yellow
        Write-Host "Opening WSL shell..." -ForegroundColor Green
        wsl -d Ubuntu
    }
    "4" {
        Write-Host "Opening WSL shell..." -ForegroundColor Green
        wsl -d Ubuntu
    }
    "5" {
        Write-Host "Copying ISO from WSL to Windows..." -ForegroundColor Yellow
        wsl -d Ubuntu -- bash -c "
            cp ~/linux-distro/*.iso /mnt/c/Users/$(whoami)/Desktop/ 2>/dev/null || \
            cp ~/*.iso /mnt/c/Users/$(whoami)/Desktop/ 2>/dev/null || \
            echo 'No ISO found.'
        "
        Get-ChildItem "$env:USERPROFILE\Desktop\*.iso" | ForEach-Object {
            Write-Host "  Found: $($_.Name) ($([math]::Round($_.Length/1MB)) MB)" -ForegroundColor Green
        }
    }
    default {
        Write-Host "Invalid choice." -ForegroundColor Red
    }
}
