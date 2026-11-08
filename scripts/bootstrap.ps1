[CmdletBinding()]
param(
    [string]$ProjectPath = (Get-Location).Path,
    [string]$Organization
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$FlutterVersion = '3.47.9'
$Repository = 'ParkersYourDad/auralis'
$ExpectedRemote = 'https://github.com/ParkersYourDad/auralis.git'

function Invoke-Native {
    param(
        [Parameter(Mandatory)][string]$Command,
        [Parameter(Mandatory)][string[]]$Arguments
    )
    & $Command @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Command failed ($LASTEXITCODE): $Command $($Arguments -join ' ')"
    }
}

$Root = (Resolve-Path -LiteralPath $ProjectPath).Path
Set-Location -LiteralPath $Root

if (-not (Test-Path -LiteralPath (Join-Path $Root 'README.md'))) {
    throw 'README.md was not found. Run this script from the Auralis repository root.'
}

$Remote = (& git remote get-url origin).Trim()
if ($LASTEXITCODE -ne 0 -or $Remote -notin @($ExpectedRemote, 'git@github.com:ParkersYourDad/auralis.git')) {
    throw "The origin remote is not $Repository. Found: $Remote"
}

$Branch = (& git branch --show-current).Trim()
if ($LASTEXITCODE -ne 0 -or $Branch -ne 'main') {
    throw "Expected branch 'main'; found '$Branch'."
}

$DirtyState = @(& git status --porcelain)
if ($LASTEXITCODE -ne 0) { throw 'Could not inspect Git working-tree state.' }
if ($DirtyState.Count -gt 0) {
    throw 'Working tree is not clean. Commit or stash existing changes before running this bootstrap.'
}

$ExistingProjectFiles = @(
    'pubspec.yaml', '.fvmrc', 'android', 'ios', 'lib', 'test'
) | Where-Object { Test-Path -LiteralPath (Join-Path $Root $_) }
if ($ExistingProjectFiles.Count -gt 0) {
    throw "Refusing to overwrite existing Flutter project content: $($ExistingProjectFiles -join ', ')"
}

if (-not (Get-Command fvm -ErrorAction SilentlyContinue)) {
    throw 'FVM was not found in PATH. Install FVM first, open a new PowerShell window, then rerun this script.'
}

if ([string]::IsNullOrWhiteSpace($Organization)) {
    $Organization = Read-Host 'Enter your reverse-domain application ID (example: com.yourcompany)'
}
if ($Organization -notmatch '^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z][A-Za-z0-9_]*)+$' -or $Organization -match '(^|\.)example(\.|$)') {
    throw 'A real reverse-domain identifier is required; example.com is not accepted.'
}

Write-Host '[1/7] Installing and pinning Flutter 3.47.9 through FVM...'
Invoke-Native 'fvm' @('install', $FlutterVersion)
Invoke-Native 'fvm' @('use', $FlutterVersion)

Write-Host '[2/7] Creating the Android/iOS Flutter application scaffold...'
Invoke-Native 'fvm' @(
    'flutter', 'create',
    '--empty',
    '--platforms=android,ios',
    "--org=$Organization",
    '--project-name=auralis',
    '--description=A reusable Flutter foundation for Android and iOS.',
    '.'
)

$RequiredGeneratedFiles = @(
    'pubspec.yaml',
    'analysis_options.yaml',
    '.metadata',
    'android/app',
    'ios/Runner',
    'lib/main.dart'
)
foreach ($RelativePath in $RequiredGeneratedFiles) {
    if (-not (Test-Path -LiteralPath (Join-Path $Root $RelativePath))) {
        throw "Flutter scaffold is incomplete; missing: $RelativePath"
    }
}

Write-Host '[3/7] Applying Auralis bootstrap and platform minimums...'

$MainDart = @'
import 'package:auralis/app/auralis_app.dart';
import 'package:flutter/widgets.dart';

void main() {
  runApp(const AuralisApp());
}
'@

$AppDart = @'
import 'package:flutter/widgets.dart';

class AuralisApp extends StatelessWidget {
  const AuralisApp({super.key});

  @override
  Widget build(BuildContext context) {
    return WidgetsApp(
      color: const Color(0xFF000000),
      home: const AuralisRoot(),
    );
  }
}

class AuralisRoot extends StatelessWidget {
  const AuralisRoot({super.key});

  @override
  Widget build(BuildContext context) {
    return const SizedBox.expand();
  }
}
'@

$TestDart = @'
import 'package:auralis/app/auralis_app.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('boots the Auralis widget application', (tester) async {
    await tester.pumpWidget(const AuralisApp());

    expect(find.byType(AuralisRoot), findsOneWidget);
  });
}
'@

New-Item -ItemType Directory -Force -Path (Join-Path $Root 'lib/app') | Out-Null
[System.IO.File]::WriteAllText((Join-Path $Root 'lib/main.dart'), $MainDart, [System.Text.UTF8Encoding]::new($false))
[System.IO.File]::WriteAllText((Join-Path $Root 'lib/app/auralis_app.dart'), $AppDart, [System.Text.UTF8Encoding]::new($false))
[System.IO.File]::WriteAllText((Join-Path $Root 'test/widget_test.dart'), $TestDart, [System.Text.UTF8Encoding]::new($false))

$AndroidGradle = Join-Path $Root 'android/app/build.gradle.kts'
if (-not (Test-Path -LiteralPath $AndroidGradle)) {
    $AndroidGradle = Join-Path $Root 'android/app/build.gradle'
}
if (-not (Test-Path -LiteralPath $AndroidGradle)) {
    throw 'Could not locate the generated Android app Gradle file.'
}
$AndroidContent = [System.IO.File]::ReadAllText($AndroidGradle)
$AndroidPattern = 'minSdk\s*=\s*flutter\.minSdkVersion|minSdkVersion\s+flutter\.minSdkVersion'
if ($AndroidContent -notmatch $AndroidPattern) {
    throw 'The generated Android minSdk declaration did not match the expected Flutter template.'
}
$AndroidContent = [regex]::Replace(
    $AndroidContent,
    $AndroidPattern,
    { param($Match) if ($Match.Value -match '^minSdk') { 'minSdk = 24' } else { 'minSdkVersion 24' } }
)
[System.IO.File]::WriteAllText($AndroidGradle, $AndroidContent, [System.Text.UTF8Encoding]::new($false))

$IosProject = Join-Path $Root 'ios/Runner.xcodeproj/project.pbxproj'
if (-not (Test-Path -LiteralPath $IosProject)) {
    throw 'Generated iOS Xcode project file was not found.'
}
$IosContent = [System.IO.File]::ReadAllText($IosProject)
$IosMatches = [regex]::Matches($IosContent, 'IPHONEOS_DEPLOYMENT_TARGET = [0-9.]+;')
if ($IosMatches.Count -eq 0) {
    throw 'Could not find the iOS deployment target in the generated Xcode project.'
}
$IosContent = [regex]::Replace($IosContent, 'IPHONEOS_DEPLOYMENT_TARGET = [0-9.]+;', 'IPHONEOS_DEPLOYMENT_TARGET = 15.0;')
[System.IO.File]::WriteAllText($IosProject, $IosContent, [System.Text.UTF8Encoding]::new($false))

$GitIgnore = @'
# Dart / Flutter
.dart_tool/
.packages
.pub/
.pub-cache/
build/
.flutter-plugins
.flutter-plugins-dependencies

# FVM SDK symlink (keep .fvmrc tracked)
.fvm/flutter_sdk

# Android / iOS local state
android/local.properties
ios/Flutter/Generated.xcconfig
ios/Flutter/flutter_export_environment.sh

# IDEs
.idea/
.vscode/
*.iml

# OS
.DS_Store
Thumbs.db

# Local environment and secrets
.env
.env.*
!.env.example
'@
[System.IO.File]::WriteAllText((Join-Path $Root '.gitignore'), $GitIgnore, [System.Text.UTF8Encoding]::new($false))

$Readme = @'
# Auralis

A mobile-first Flutter foundation for building Android and iOS applications, with an original design system owned by this project.

## Baseline

- Flutter: 3.47.9 stable, pinned per project with FVM.
- Dart: the version bundled with the pinned Flutter SDK.
- Platforms: Android and iOS only.
- Minimum Android API: 24.
- Minimum iOS version: 15.0.
- UI foundation: Flutter SDK widgets and primitives; no external UI kit.
- Dependencies: Flutter SDK only at this stage.

## Requirements

- Git
- FVM
- Android development tools for Android builds
- macOS with Xcode for iOS builds

## Getting started

    fvm flutter pub get
    fvm flutter analyze
    fvm flutter test
    fvm flutter run

Use the project-pinned SDK through fvm flutter and fvm dart, not a machine-global Flutter version.

## Engineering direction

- Build Auralis-owned design tokens and components on Flutter SDK primitives.
- Keep application-specific decisions out of reusable foundation code.
- Add dependencies only when a concrete requirement justifies them.
- Treat accessibility, localization, RTL, and reduced motion as requirements.
- Keep architecture pragmatic; do not create speculative layers or placeholder features.

## Continuous integration

GitHub Actions runs formatting checks, static analysis, widget tests, and an Android debug build on pushes and pull requests targeting main.

## Current scope

This repository contains the minimal mobile platform scaffold and application bootstrap. The design system and reusable component APIs will be introduced in subsequent implementation stages.
'@
[System.IO.File]::WriteAllText((Join-Path $Root 'README.md'), $Readme, [System.Text.UTF8Encoding]::new($false))

$WorkflowDirectory = Join-Path $Root '.github/workflows'
New-Item -ItemType Directory -Force -Path $WorkflowDirectory | Out-Null
$Workflow = @'
name: Flutter CI

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

permissions:
  contents: read

jobs:
  verify:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: subosito/flutter-action@v2
        with:
          channel: stable
          flutter-version: 3.47.9
          cache: true

      - name: Install dependencies
        run: flutter pub get

      - name: Check formatting
        run: dart format --output=none --set-exit-if-changed lib test

      - name: Analyze
        run: flutter analyze --fatal-infos

      - name: Test
        run: flutter test

      - name: Build Android debug APK
        run: flutter build apk --debug
'@
[System.IO.File]::WriteAllText((Join-Path $WorkflowDirectory 'ci.yml'), $Workflow, [System.Text.UTF8Encoding]::new($false))

Write-Host '[4/7] Resolving Flutter dependencies...'
Invoke-Native 'fvm' @('flutter', 'pub', 'get')

Write-Host '[5/7] Formatting, analyzing, and testing...'
Invoke-Native 'fvm' @('dart', 'format', 'lib', 'test')
Invoke-Native 'fvm' @('dart', 'format', '--output=none', '--set-exit-if-changed', 'lib', 'test')
Invoke-Native 'fvm' @('flutter', 'analyze', '--fatal-infos')
Invoke-Native 'fvm' @('flutter', 'test')

Write-Host '[6/7] Building Android debug APK...'
Invoke-Native 'fvm' @('flutter', 'build', 'apk', '--debug')

$PinnedConfig = Join-Path $Root '.fvmrc'
if (-not (Test-Path -LiteralPath $PinnedConfig) -or (Get-Content -Raw $PinnedConfig) -notmatch [regex]::Escape($FlutterVersion)) {
    throw "FVM project pin was not written as expected: $FlutterVersion"
}

Write-Host '[7/7] Committing and pushing the verified foundation...'
Invoke-Native 'git' @('add', '-A')
Invoke-Native 'git' @('commit', '-m', 'Build initial Flutter mobile foundation')
Invoke-Native 'git' @('push', 'origin', 'main')

Write-Host 'Auralis foundation bootstrap completed.'
Write-Host "Flutter: $FlutterVersion (stable)"
Write-Host 'Android minimum API: 24'
Write-Host 'iOS minimum: 15.0'
Write-Host 'Local checks: format, analyze, widget test, Android debug build'
Write-Host "Repository: https://github.com/$Repository"
