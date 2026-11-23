<#
.SYNOPSIS
Iltarusko_2000 - installer / packaging script.

.DESCRIPTION
Asks where the ORIGINAL 1991 Twilight: 2000 DOS game is installed, extracts the
assets with tools/extract_original.py, and builds a CLEAN, distributable game
folder next to this one (..\Iltarusko_2000_game).

The distributable contains only what the game needs:

    Iltarusko_2000_game\
        Kaynnista.bat
        README.md
        godot\
            project.godot
            data\        scenes\        scripts\        original\

Everything else (.git, .godot, .github, docs, tools, tests, .uid files,
ZIP packages and executables) is left out.

USAGE
    powershell -ExecutionPolicy Bypass -File .\install.ps1
    powershell -ExecutionPolicy Bypass -File .\install.ps1 -GamePath "C:\pelit\T2000"
#>
param([string]$GamePath)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$gameDir = Join-Path $root 'godot'
$publish = Join-Path (Split-Path $root -Parent) 'Iltarusko_2000_game'

function Write-Step($msg) { Write-Host "`n==> $msg" -ForegroundColor Cyan }

# ---------------------------------------------------------------- ask for data
Write-Step 'Alkuperäisen pelin sijainti'
if ([string]::IsNullOrWhiteSpace($GamePath)) {
    Write-Host 'Anna kansion polku, jossa on alkuperäisen Twilight: 2000 (DOS) -pelin'
    Write-Host 'GAMEDATA-alakansio (esim. C:\Twilight-2000_DOS_EN\gamedata\C\T2000):'
    $GamePath = Read-Host 'Polku'
}
$GamePath = $GamePath.Trim().Trim('"')
if (-not (Test-Path (Join-Path $GamePath 'GAMEDATA\ANIMS.LB'))) {
    throw "Alkuperäistä peliä ei löytynyt polusta '$GamePath' (GAMEDATA\ANIMS.LB puuttuu)."
}
Write-Host "Käytetään: $GamePath" -ForegroundColor Green

# ---------------------------------------------------------------- tools
$python = (Get-Command python -ErrorAction SilentlyContinue).Source
if (-not $python) { $python = (Get-Command py -ErrorAction SilentlyContinue).Source }
if (-not $python) { throw 'Pythonia ei löytynyt PATHista. Asenna Python 3.9+ ja yritä uudelleen.' }
$extractor = Join-Path $root 'tools\extract_original.py'
if (-not (Test-Path $extractor)) { throw "Purkutyökalu puuttuu: $extractor" }

Write-Step 'Puretaan assetit alkuperäisestä pelistä'
$reference = Join-Path (Split-Path $root -Parent) 'remake\godot\original'
if (-not (Test-Path $reference)) { $reference = $env:T2K_REFERENCE_DIR }
$refArgs = @()
if ($reference -and (Test-Path $reference)) {
    Write-Host "Käytetään valmiita sprite-PNG:tä: $reference" -ForegroundColor Green
    $refArgs = @('--reference-dir', $reference)
}
& $python $extractor --game $GamePath --out (Join-Path $gameDir 'original') @refArgs
if ($LASTEXITCODE -ne 0) { throw 'Assetien purku epäonnistui.' }
if ($reference -and (Test-Path $reference)) {
    Copy-Item (Join-Path $reference '*') (Join-Path $gameDir 'original') -Recurse -Force
} else {
    # Self-contained fallback: a locally bundled dictionary of decoded sprites.
    $dict = Join-Path $root 'asset_library\twilight2000_assets.zip'
    if (-not (Test-Path $dict)) { $dict = $env:T2K_ASSET_DICT }
    if ($dict -and (Test-Path $dict)) {
        Write-Host "Käytetään paikallista asset-kirjastoa: $dict" -ForegroundColor Green
        Expand-Archive -Path $dict -DestinationPath (Join-Path $gameDir 'original') -Force
    } else {
        Write-Host 'VAROITUS: ei referenssikansiota eikä asset-kirjastoa - sprite-jäsenet jäävät raakoiksi .bin-tiedostoiksi.' -ForegroundColor Yellow
    }
}

$sprites = @(Get-ChildItem (Join-Path $gameDir 'original\graphics\ANIMS') -Filter '*.png' -ErrorAction SilentlyContinue).Count
if ($sprites -lt 10) {
    Write-Host "`nVAROITUS: alkuperäisen pelin .LB-spritejen token-pakkausta ei osata vielä" -ForegroundColor Yellow
    Write-Host 'purkaa PNG:ksi. Peli käynnistyy, mutta hahmot ja rakennukset näkyvät' -ForegroundColor Yellow
    Write-Host 'tyhjinä, kunnes puuttuva dekooderi saadaan toteutettua.' -ForegroundColor Yellow
}

# ---------------------------------------------------------------- publish
Write-Step "Rakennetaan puhdas julkaisukansio: $publish"
if (Test-Path $publish) { Remove-Item -Recurse -Force $publish }
New-Item -ItemType Directory -Path $publish | Out-Null
New-Item -ItemType Directory -Path (Join-Path $publish 'godot') | Out-Null

Copy-Item (Join-Path $gameDir 'project.godot') (Join-Path $publish 'godot\project.godot')
foreach ($dir in @('data', 'scenes', 'scripts', 'original')) {
    $src = Join-Path $gameDir $dir
    if (Test-Path $src) { Copy-Item $src (Join-Path $publish "godot\$dir") -Recurse }
}
if (Test-Path (Join-Path $root 'README.md')) { Copy-Item (Join-Path $root 'README.md') (Join-Path $publish 'README.md') }

# Godot-generated UID files and raw extractor leftovers are not needed at runtime.
Get-ChildItem $publish -Recurse -File -Filter '*.uid' -ErrorAction SilentlyContinue | Remove-Item -Force
Get-ChildItem (Join-Path $publish 'godot\original') -Recurse -File -Filter '*.bin' -ErrorAction SilentlyContinue | Remove-Item -Force
$manifest = Join-Path $publish 'godot\original\manifest.json'
if (Test-Path $manifest) { Remove-Item $manifest -Force }

@"
@echo off
echo ============================================
echo  Iltarusko_2000 - Twilight: 2000 Remake
echo ============================================
echo.
where godot >nul 2>nul
if errorlevel 1 (
  echo Godotia ei loytynyt PATHista.
  echo Asenna Godot 4.7.2+ osoitteesta https://godotengine.org/download
  echo ja lisaa godot.exe PATHiin, tai korvaa tama rivi polulla godot.exe:n.
  pause
  exit /b 1
)
godot --path "%~dp0godot" %*
"@ | Set-Content -Encoding ASCII (Join-Path $publish 'Kaynnista.bat')

# ---------------------------------------------------------------- summary
$files = @(Get-ChildItem $publish -Recurse -File).Count
$size = [math]::Round((Get-ChildItem $publish -Recurse -File | Measure-Object Length -Sum).Sum / 1MB, 1)
Write-Step 'Valmis'
Write-Host "Julkaisukansio : $publish"
Write-Host "Tiedostoja     : $files"
Write-Host "Kokoono        : $size MB"
Write-Host "Jätettiin pois : .git, .godot, .github, docs, tools, tests, *.uid, *.zip, *.exe"
Write-Host "`nKäynnistä peli: $publish\Kaynnista.bat" -ForegroundColor Green
