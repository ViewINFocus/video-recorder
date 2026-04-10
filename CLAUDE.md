# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

`@capacitor-community/video-recorder` — A Capacitor 7 plugin for native video recording on iOS and Android. Web implementation is a preview-only mock (no actual recording). Published to npm as a community Capacitor plugin.

## Build & Development Commands

```bash
npm install                  # Install dependencies (also: brew install swiftlint on macOS)
npm run build                # Full build: docgen → tsc → rollup (outputs to dist/)
npm run watch                # TypeScript watch mode

npm run verify               # Build + validate all platforms (iOS, Android, web)
npm run verify:ios           # xcodebuild scheme CapacitorCommunityVideoRecorder
npm run verify:android       # cd android && ./gradlew clean build test

npm run lint                 # ESLint + Prettier (check) + SwiftLint (lint)
npm run fmt                  # ESLint fix + Prettier write + SwiftLint fix

npm run docgen               # Regenerate API docs in README.md from JSDoc in definitions.ts
```

### Example App (Ionic Angular)

```bash
cd example && npm install
npm run start                # ng serve (web dev)
npm run start:android        # ionic cap run android -l --external
npm run start:ios            # ionic cap run ios -l --external
```

## Architecture

### Plugin Bridge Pattern

Standard Capacitor plugin using the native bridge — NOT Flutter method channels. JS calls are auto-routed to native methods annotated with:
- **iOS**: `@objc func methodName(_ call: CAPPluginCall)`
- **Android**: `@PluginMethod() public void methodName(PluginCall call)`

Events flow back via `notifyListeners()` on both platforms (`onVolumeInput`, `audioStatusChanged`).

### Source Layout

| Path | Language | Purpose |
|------|----------|---------|
| `src/definitions.ts` | TypeScript | Plugin API contract (interfaces, enums) |
| `src/index.ts` | TypeScript | Plugin registration via `registerPlugin()` |
| `src/web.ts` | TypeScript | Web mock (preview only, no recording) |
| `ios/Sources/VideoRecorder/Plugin.swift` | Swift | Full iOS implementation (~840 lines, AVFoundation) |
| `android/src/main/java/com/capacitorcommunity/videorecorder/VideoRecorderPlugin.java` | Java | Full Android implementation (~648 lines, FancyCamera) |

### Camera Preview Architecture

The camera preview is a native view inserted behind (or in front of) the WebView. The WebView and all DOM layers must be transparent for `stackPosition: 'back'` to work:
- **iOS**: Sets `webView.isOpaque = false`, `backgroundColor = .clear`
- **Android**: Sets `backgroundColor = Color.argb(0,0,0,0)` on WebView
- **Consumer requirement**: `capacitor.config.ts` needs `backgroundColor: '#ff000000'` and CSS `--background: transparent`

### Platform-Specific Gotchas

- **Camera position enum mismatch**: iOS uses 0=front, Android FancyCamera uses 0=back. The Android code swaps values at initialization to keep the JS API consistent (FRONT=0, BACK=1).
- **Android camera position tracking**: Plugin maintains its own `currentCameraPositionInt` because FancyCamera's `getCameraPosition()` is unreliable.
- **Front camera mirroring**: iOS uses `connection.isVideoMirrored`, Android uses `setScaleX(-1f)`. Recorded video is never mirrored on either platform.
- **Phone call handling (iOS)**: Uses `CXCallObserver` to detect active calls. When a call is active, audio recording is skipped and `audioStatusChanged` event is emitted. `disableAudio` option lets callers explicitly skip audio.
- **Android flash**: Only works during active recording (FancyCamera limitation).
- **Android permissions**: Plugin does not request permissions itself — delegates to FancyCamera.

### Dependencies

- **Android**: `com.github.triniwiz:fancycamera:1.2.4` (from JitPack — consumers must add JitPack to their `build.gradle` repositories)
- **iOS**: AVFoundation (system framework), CallKit `CXCallObserver` for phone call detection
- **Both**: Capacitor Core >=7.0.0

## Versioning

- Current: v7.5.0 (Capacitor 7)
- Major version tracks Capacitor version (v5 → Cap 5, v6 → Cap 6, v7 → Cap 7)
- Branches: `main`, `capacitor/v5`, `capacitor/v6`
- `dist/` is gitignored; `prepublishOnly` runs build before npm publish
