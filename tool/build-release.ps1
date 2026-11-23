# Builds the release APK and stages it as release\HYETI.apk, but only if it is signed with the key
# that signed the earlier releases, so it installs over the app already on phones.
# Run from anywhere:  powershell -ExecutionPolicy Bypass -File tool\build-release.ps1
$ErrorActionPreference = 'Stop'
# The key that signed v1.1.1 onwards (made 2026-11-15 as this PC's debug key, kept since as android\hyeti-release.jks).
# v1.1.0 used 87:7B:AB:...:2D:2A.
$expected = 'CB:A9:CC:FE:AA:E9:28:CC:52:8B:70:B2:DB:A7:D4:54:06:94:5F:2C:2B:CE:51:3A:A6:19:C0:A2:C3:93:C3:0E'
$root = Split-Path $PSScriptRoot -Parent
Set-Location $root

if (-not (Test-Path (Join-Path $root 'android\key.properties'))) {
    Write-Host 'android\key.properties is missing: copy it and android\hyeti-release.jks from your backup first.' -ForegroundColor Red
    exit 1
}

flutter analyze; if ($LASTEXITCODE) { exit 1 }
# The screenshot test draws the real clock, so its pictures only match in the minute they were made; leave it out.
$tests = Get-ChildItem test -Filter '*_test.dart' | Where-Object Name -ne 'render_preview_test.dart' | ForEach-Object { "test/$($_.Name)" }
flutter test @tests; if ($LASTEXITCODE) { exit 1 }
flutter build apk --release --target-platform android-arm64; if ($LASTEXITCODE) { exit 1 }

$apk = Join-Path $root 'build\app\outputs\flutter-apk\app-release.apk'
$sdk = (Get-Content android\local.properties | Select-String '^sdk.dir=') -replace '^sdk.dir=', '' -replace '\\\\', '\'
$apksigner = Get-ChildItem (Join-Path $sdk 'build-tools') -Recurse -Filter apksigner.bat | Select-Object -Last 1
$certs = & $apksigner.FullName verify --print-certs $apk 2>$null | Select-String 'SHA-256 digest'
$apkDigest = ($certs -replace '.*digest:\s*', '').Trim().ToUpper()
if ($apkDigest -ne ($expected -replace ':', '')) {
    Write-Host "The built APK has a different signature ($apkDigest). Not staged." -ForegroundColor Red
    exit 1
}

New-Item -ItemType Directory -Force (Join-Path $root 'release') | Out-Null
Copy-Item $apk (Join-Path $root 'release\HYETI.apk') -Force
$version = (Get-Content pubspec.yaml | Select-String '^version:') -replace '^version:\s*', '' -replace '\+.*', ''
Write-Host "release\HYETI.apk is ready. Publish it as a GitHub release tagged v$version." -ForegroundColor Green
