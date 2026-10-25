<#
    build_release.ps1 - Repeatable ClassTrack release build for Google Play.

    Why this exists:
      ClassTrack reads its RevenueCat PUBLIC key at build time via
      --dart-define (see lib/features/subscription/domain/pro_constants.dart).
      If you forget to pass it, ProConstants.enabled is false and the app ships
      with NO paywall (everything free forever). This script makes the correct
      build the only build you run.

    The RevenueCat PUBLIC SDK key (goog_... / appl_...) is NOT a secret. It is
    safe to ship inside the client binary. It is different from the RevenueCat
    SECRET API key and from the webhook auth secret; never put those here.

    USAGE (PowerShell, from the project root):

      # Recommended: keep the key in an env var so it is not in your history.
      $env:REVENUECAT_ANDROID_KEY = "goog_xxxxxxxxxxxxxxxxxxxx"
      ./tool/build_release.ps1

      # Or pass it explicitly:
      ./tool/build_release.ps1 -AndroidKey "goog_xxxxxxxxxxxxxxxxxxxx"

      # Build an APK instead of an AAB (for sideloading during testing):
      ./tool/build_release.ps1 -Apk

    OUTPUT:
      AAB (upload to Play):  build/app/outputs/bundle/release/app-release.aab
      APK (-Apk):            build/app/outputs/flutter-apk/app-release.apk
#>

[CmdletBinding()]
param(
    [string]$AndroidKey = $env:REVENUECAT_ANDROID_KEY,
    [string]$IosKey = $env:REVENUECAT_IOS_KEY,
    [switch]$Apk,
    [switch]$Ios
)

$ErrorActionPreference = "Stop"

# Always run from the project root (the folder that contains pubspec.yaml).
$projectRoot = Split-Path -Parent $PSScriptRoot
Set-Location $projectRoot

function Fail($msg) {
    Write-Host "ERROR: $msg" -ForegroundColor Red
    exit 1
}

# --- Validate the RevenueCat key ------------------------------------------
$key = if ($Ios) { $IosKey } else { $AndroidKey }
$expectedPrefix = if ($Ios) { "appl_" } else { "goog_" }
$envVarName = if ($Ios) { "REVENUECAT_IOS_KEY" } else { "REVENUECAT_ANDROID_KEY" }
$paramName = if ($Ios) { "-IosKey" } else { "-AndroidKey" }

if ([string]::IsNullOrWhiteSpace($key)) {
    Fail "No RevenueCat key provided. Set env var $envVarName or pass $paramName. Building without it would ship the app with NO paywall."
}

if ($key.StartsWith("test_")) {
    Fail "That looks like a RevenueCat TEST key (test_...). A test key makes the SDK show a Wrong API Key dialog and force-close a real build. Use the platform PUBLIC key ($expectedPrefix...)."
}

if (-not $key.StartsWith($expectedPrefix)) {
    Write-Host "WARNING: key does not start with $expectedPrefix -- double-check you are using the correct platform PUBLIC key." -ForegroundColor Yellow
}

# --- Build ----------------------------------------------------------------
$sw = [Diagnostics.Stopwatch]::StartNew()

# Builds crawl when Windows runs out of RAM and starts paging (a 16 GB PC with
# Chrome, `flutter run` and an emulator open took 35-45 min instead of ~10).
try {
    $freeGb = [math]::Round((Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory / 1MB, 1)
    if ($freeGb -lt 4) {
        Write-Host "WARNING: only $freeGb GB RAM free. Close Chrome tabs, 'flutter run' sessions and emulators for a much faster build." -ForegroundColor Yellow
    }
} catch {}

Write-Host "==> flutter pub get" -ForegroundColor Cyan
flutter pub get
if ($LASTEXITCODE -ne 0) { Fail "flutter pub get failed." }

$defines = @("--dart-define=REVENUECAT_ANDROID_KEY=$AndroidKey")
if (-not [string]::IsNullOrWhiteSpace($IosKey)) {
    $defines += "--dart-define=REVENUECAT_IOS_KEY=$IosKey"
}

# Dart-level obfuscation + debug-info stripping. Renames Dart symbols inside
# libapp.so (improves Play Console's "Obfuscation" score for Flutter apps) and
# writes the symbol map to build/debug-info so crash traces can be de-obfuscated
# later (keep this folder for each release you ship). Native R8/shrink/optimize
# is already enabled in android/app/build.gradle.kts.
$obfuscate = @(
    "--obfuscate",
    "--split-debug-info=build/debug-info"
)

if ($Ios) {
    Write-Host "==> flutter build ipa (release, obfuscated)" -ForegroundColor Cyan
    flutter build ipa --release @defines @obfuscate
}
elseif ($Apk) {
    Write-Host "==> flutter build apk (release, obfuscated)" -ForegroundColor Cyan
    flutter build apk --release @defines @obfuscate
}
else {
    Write-Host "==> flutter build appbundle (release, obfuscated)" -ForegroundColor Cyan
    flutter build appbundle --release @defines @obfuscate
}
if ($LASTEXITCODE -ne 0) { Fail "flutter build failed." }
Write-Host ("Built in {0:mm\:ss} (min:sec)." -f $sw.Elapsed) -ForegroundColor Green

# --- Upload Dart symbols to Crashlytics ------------------------------------
# The build is obfuscated, so without these symbols every Dart crash in
# Firebase Crashlytics shows unreadable frames. The Gradle plugin uploads the
# Android (R8) mapping by itself, but NOT the Dart symbols. Needs the Firebase
# CLI (npm i -g firebase-tools) and `firebase login`. A failure here does not
# fail the build: re-run the printed command later (keep build/debug-info!).
$crashlyticsAppId = if ($Ios) { $env:FIREBASE_IOS_APP_ID } else { "1:401205940629:android:caaf9d27160a016651a69c" }
if (-not [string]::IsNullOrWhiteSpace($crashlyticsAppId)) {
    # The symbol tool needs `java`. Use Android Studio's bundled one when Java
    # isn't installed separately.
    if (-not (Get-Command java -ErrorAction SilentlyContinue)) {
        $jbr = @("C:\Program Files\Android\Android Studio\jbr", "$env:LOCALAPPDATA\Programs\Android Studio\jbr") |
            Where-Object { Test-Path "$_\bin\java.exe" } | Select-Object -First 1
        if ($jbr) { $env:JAVA_HOME = $jbr; $env:Path = "$jbr\bin;$env:Path" }
    }
    $uploadCmd = "firebase crashlytics:symbols:upload --app=$crashlyticsAppId build/debug-info"
    Write-Host "==> $uploadCmd" -ForegroundColor Cyan
    try {
        firebase crashlytics:symbols:upload --app=$crashlyticsAppId build/debug-info
        if ($LASTEXITCODE -ne 0) { throw "exit $LASTEXITCODE" }
    } catch {
        Write-Host "WARNING: symbol upload failed ($_). Run later: $uploadCmd" -ForegroundColor Yellow
    }
} else {
    Write-Host "WARNING: set FIREBASE_IOS_APP_ID to upload iOS Dart symbols to Crashlytics." -ForegroundColor Yellow
}

# --- Report artifact path -------------------------------------------------
$artifact = if ($Ios) {
    "build/ios/ipa/*.ipa"
}
elseif ($Apk) {
    "build/app/outputs/flutter-apk/app-release.apk"
}
else {
    "build/app/outputs/bundle/release/app-release.aab"
}

Write-Host ""
Write-Host "Build complete." -ForegroundColor Green
Write-Host "Artifact: $artifact"
Write-Host "Upload the .aab to Play Console -> Test and release -> your track."
