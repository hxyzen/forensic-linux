#=============================================================================
#  OTOMATIK BUILD SCRIPTI - Forensic Linux ISO
#  Bu script senin yerine herşeyi yapar:
#  1. GitHub'da repo açar
#  2. Kodları push eder
#  3. GitHub Actions ile ISO build alır
#  4. ISO'yu indirip masaustune koyar
#  
#  Senin yapman gereken tek sey:
#  1. GitHub'a kaydolmak (ilk seferde)
#  2. Bir "token" alip buraya yapistirmak
#=============================================================================

$ErrorActionPreference = "Stop"
$ProjectDir = Split-Path -Parent $MyInvocation.MyCommand.Path

function Write-Step {
    param([string]$Text, [string]$Color = "Cyan")
    Write-Host ""
    Write-Host "========================================" -ForegroundColor $Color
    Write-Host "  $Text" -ForegroundColor $Color
    Write-Host "========================================" -ForegroundColor $Color
}

function Write-Info {
    param([string]$Text)
    Write-Host "  [*] $Text" -ForegroundColor Gray
}

function Write-Success {
    param([string]$Text)
    Write-Host "  [✔] $Text" -ForegroundColor Green
}

function Write-Warning {
    param([string]$Text)
    Write-Host "  [!] $Text" -ForegroundColor Yellow
}

Clear-Host
Write-Host ""
Write-Host "╔══════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║        FORENSIC LINUX - OTOMATIK BUILD          ║" -ForegroundColor Cyan
Write-Host "║     Bu script herseyi senin yerine yapar        ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# Check portable git
$GitExe = Resolve-Path "$env:TEMP\git-portable\bin\git.exe" -ErrorAction SilentlyContinue
if (-not $GitExe) {
    Write-Warning "Git bulunamadi, indiriliyor..."
    $url = "https://github.com/git-for-windows/git/releases/download/v2.47.1.windows.2/PortableGit-2.47.1.2-64-bit.7z.exe"
    $out = "$env:TEMP\git-portable.exe"
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $url -OutFile $out -UseBasicParsing
    mkdir "$env:TEMP\git-portable" -Force | Out-Null
    & $out -o"$env:TEMP\git-portable" -y
    $GitExe = "$env:TEMP\git-portable\bin\git.exe"
}
Write-Success "Git: $(& $GitExe version)"

# Check portable gh
$GhExe = Resolve-Path "$env:TEMP\gh-portable\bin\gh.exe" -ErrorAction SilentlyContinue
if (-not $GhExe) {
    Write-Warning "GitHub CLI bulunamadi, indiriliyor..."
    $url = "https://github.com/cli/cli/releases/download/v2.63.2/gh_2.63.2_windows_amd64.zip"
    $out = "$env:TEMP\gh.zip"
    Invoke-WebRequest -Uri $url -OutFile $out -UseBasicParsing
    Expand-Archive -Path $out -DestinationPath "$env:TEMP\gh-portable" -Force
    $GhExe = "$env:TEMP\gh-portable\bin\gh.exe"
}
Write-Success "GitHub CLI: $(& $GhExe version 2>&1 | Select-Object -First 1)"

#=============================================================================
# STEP 1: GitHub Token
#=============================================================================
Write-Step "ADIM 1: GitHub Hesabi ve Token" -Color "Yellow"

$env:GIT_TERMINAL_PROMPT=0

Write-Info "GitHub hesabin varsa token al, yoksa once kaydol:"
Write-Info ""
Write-Info "  ► Kaydol: https://github.com/signup"
Write-Info "  ► Token al: https://github.com/settings/tokens/new"
Write-Info ""
Write-Info "Token olustururken:"
Write-Info "  - 'repo' (tumunu isaretle)"
Write-Info "  - 'workflow' isaretle"
Write-Info "  - 'Generate token' de"
Write-Info "  - Cikan kodu kopyala (------buna benzer)"
Write-Info ""

start "https://github.com/signup"

$token = ""
while ([string]::IsNullOrEmpty($token)) {
    $token = Read-Host "Token'i buraya yapistir (veya bos birakip cikis yap)"
    if ([string]::IsNullOrEmpty($token)) {
        Write-Warning "Cikis yapiliyor..."
        exit
    }
    # Test token
    try {
        $test = Invoke-RestMethod -Uri "https://api.github.com/user" -Headers @{Authorization = "token $token"} -ErrorAction Stop
        Write-Success "Giris basarili: $($test.login)"
        Write-Success "Email: $($test.email)"
    } catch {
        Write-Warning "Token gecersiz! Tekrar dene."
        $token = ""
    }
}

# Save token for later use
$global:GitHubToken = $token
$global:GitHubUser = $test.login

#=============================================================================
# STEP 2: Create GitHub Repo
#=============================================================================
Write-Step "ADIM 2: GitHub Reposu Olusturuluyor" -Color "Yellow"

$repoName = "forensic-linux-$((Get-Random -Maximum 9999).ToString('0000'))"

Write-Info "Repo adi: $repoName"
Write-Info "Repo olusturuluyor..."

$body = @{
    name = $repoName
    description = "Forensic Linux Distribution - Custom build from scratch"
    private = $false
    auto_init = $false
} | ConvertTo-Json

try {
    $repo = Invoke-RestMethod -Uri "https://api.github.com/user/repos" -Method Post -Body $body -ContentType "application/json" -Headers @{Authorization = "token $token"} -ErrorAction Stop
    Write-Success "Repo olusturuldu: $($repo.html_url)"
    $repoUrl = $repo.clone_url
} catch {
    Write-Error "Repo olusturulamadi: $_"
    Read-Host "Enter'a basarak cik"
    exit 1
}

#=============================================================================
# STEP 3: Push Code to GitHub
#=============================================================================
Write-Step "ADIM 3: Kodlar GitHub'a Yukleniyor" -Color "Yellow"

try {
    # Setup git remote with token auth
    $remoteUrl = "https://$($test.login):$token@github.com/$($test.login)/$repoName.git"
    
    Set-Location -LiteralPath $ProjectDir
    & $GitExe remote add origin $remoteUrl 2>&1 | Out-Null
    & $GitExe remote set-url origin $remoteUrl 2>&1 | Out-Null
    & $GitExe branch -M main 2>&1 | Out-Null
    
    Write-Info "Push yapiliyor..."
    & $GitExe push -u origin main 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Push failed" }
    Write-Success "Kodlar GitHub'a yuklendi"
} catch {
    Write-Error "Push hatasi: $_"
    Read-Host "Enter'a basarak cik"
    exit 1
}

# Remove token from URL (security)
& $GitExe remote set-url origin "https://github.com/$($test.login)/$repoName.git" 2>&1 | Out-Null

#=============================================================================
# STEP 4: Trigger GitHub Actions
#=============================================================================
Write-Step "ADIM 4: GitHub Actions Build Baslatiliyor" -Color "Yellow"

Write-Info "Build tetikleniyor (bu ~30-60 dk surebilir)..."
Write-Info ""

# Trigger workflow via API
$workflowBody = @{
    ref = "main"
} | ConvertTo-Json

try {
    $workflowDispatch = Invoke-RestMethod -Uri "https://api.github.com/repos/$($test.login)/$repoName/actions/workflows/build.yml/dispatches" -Method Post -Body $workflowBody -ContentType "application/json" -Headers @{Authorization = "token $token"} -ErrorAction Stop
    Write-Success "Build baslatildi!"
} catch {
    Write-Warning "Workflow tetiklenemedi, push ile otomatik baslamali: $_"
}

Write-Info "Build URL: https://github.com/$($test.login)/$repoName/actions"

#=============================================================================
# STEP 5: Wait and Download ISO
#=============================================================================
Write-Step "ADIM 5: Build Bekleniyor ve ISO Indiriliyor" -Color "Yellow"

Write-Info "Build'in bitmesi bekleniyor..."
Write-Info "Bu kisim 30-60 dakika surebilir. Bekle..."
Write-Info ""
Write-Info "Build'i canli izlemek icin: https://github.com/$($test.login)/$repoName/actions"
Write-Info ""

$maxWaitSeconds = 7200  # 2 saat max bekle
$checkInterval = 30      # 30 saniyede bir kontrol et
$elapsed = 0
$downloaded = $false

while ($elapsed -lt $maxWaitSeconds) {
    Start-Sleep -Seconds $checkInterval
    $elapsed += $checkInterval
    
    try {
        $runs = Invoke-RestMethod -Uri "https://api.github.com/repos/$($test.login)/$repoName/actions/runs" -Headers @{Authorization = "token $token"}
        $latestRun = $runs.workflow_runs | Sort-Object created_at -Descending | Select-Object -First 1
        
        if ($latestRun) {
            Write-Info "Durum: $($latestRun.status) - $($latestRun.conclusion) ($elapsed saniye gecti)"
            
            if ($latestRun.status -eq "completed") {
                if ($latestRun.conclusion -eq "success") {
                    Write-Success "Build BASARILI!"
                    
                    # Get artifacts
                    $artifacts = Invoke-RestMethod -Uri "https://api.github.com/repos/$($test.login)/$repoName/actions/artifacts" -Headers @{Authorization = "token $token"}
                    $isoArtifact = $artifacts.artifacts | Where-Object { $_.name -eq "Forensic-Linux-ISO" } | Select-Object -First 1
                    
                    if ($isoArtifact) {
                        Write-Info "ISO artifact'i bulundu, indiriliyor: $($isoArtifact.name)"
                        
                        # Download artifact
                        $downloadUrl = $isoArtifact.archive_download_url
                        $isoZipPath = "$env:USERPROFILE\Desktop\forensic-linux-iso.zip"
                        
                        Invoke-WebRequest -Uri $downloadUrl -OutFile $isoZipPath -Headers @{Authorization = "token $token"} -UseBasicParsing
                        
                        # Extract ISO
                        Expand-Archive -Path $isoZipPath -DestinationPath "$env:USERPROFILE\Desktop" -Force
                        
                        # Find ISO
                        $isoFile = Get-ChildItem -Path "$env:USERPROFILE\Desktop" -Filter "*.iso" | Select-Object -First 1
                        
                        if ($isoFile) {
                            Write-Success "ISO INDIRILDI: $($isoFile.FullName)"
                            Write-Info "Boyut: $([math]::Round($isoFile.Length/1MB, 1)) MB"
                            $downloaded = $true
                        } else {
                            Write-Warning "ISO zip icinde bulunamadi, manuel kontrol et: $isoZipPath"
                        }
                    } else {
                        Write-Warning "ISO artifact'i henuz yayinlanmadi"
                        continue
                    }
                } else {
                    Write-Error "Build basarisiz oldu: $($latestRun.conclusion)"
                    Write-Info "Loglari burada gorebilirsin: https://github.com/$($test.login)/$repoName/actions"
                }
                break
            }
        } else {
            Write-Info "Henuz run baslamadi, bekleniyor... ($elapsed saniye)"
        }
    } catch {
        Write-Info "API hatasi, tekrar denenecek... ($elapsed saniye)"
    }
}

#=============================================================================
# FINISH
#=============================================================================
Write-Step "SONUC" -Color "Green"

if ($downloaded) {
    Write-Host ""
    Write-Host "  ╔════════════════════════════════════════╗" -ForegroundColor Green
    Write-Host "  ║         ISO HAZIR!                     ║" -ForegroundColor Green
    Write-Host "  ║  Masaustune indirildi!                 ║" -ForegroundColor Green
    Write-Host "  ║                                       ║" -ForegroundColor Green
    Write-Host "  ║  USB'ye yazmak icin Rufus kullan:     ║" -ForegroundColor Green
    Write-Host "  ║  - Device: USB bellegin                ║" -ForegroundColor Green
    Write-Host "  ║  - Boot selection: ISO dosyasi         ║" -ForegroundColor Green
    Write-Host "  ║  - Image option: DD Image              ║" -ForegroundColor Green
    Write-Host "  ║  - Start                             ║" -ForegroundColor Green
    Write-Host "  ║                                       ║" -ForegroundColor Green
    Write-Host "  ║  BIOS'tan USB'den boot et ve kullan!  ║" -ForegroundColor Green
    Write-Host "  ╚════════════════════════════════════════╝" -ForegroundColor Green
    Write-Host ""
    start "https://rufus.ie"
} else {
    Write-Warning "ISO otomatik indirilemedi."
    Write-Info ""
    Write-Info "Manuel olarak suradan indirebilirsin:"
    Write-Info "  https://github.com/$($test.login)/$repoName/actions"
    Write-Info "  1. En son workflow'a tikla"
    Write-Info "  2. 'Forensic-Linux-ISO' artifact'ine tikla"
    Write-Info "  3. .iso dosyasini indir"
    Write-Info "  4. Rufus ile USB'ye yaz"
}

Write-Host ""
Write-Info "Repo URL: https://github.com/$($test.login)/$repoName"
Write-Info "Build'ler: https://github.com/$($test.login)/$repoName/actions"
Write-Info ""

Read-Host "Islem tamam. Enter'a basarak kapat"
