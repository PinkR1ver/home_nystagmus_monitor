# GitHub Pages Landing Page

This folder contains a standalone static landing page for `Home Nystagmus Monitor`.

## Deploy with GitHub Pages

1. Push the repository to GitHub.
2. Open repository `Settings` -> `Pages`.
3. Set the source to `Deploy from a branch`.
4. Choose your branch and the `/docs` folder.
5. Save, then wait for GitHub Pages to publish.

## Before publishing

- Current Motion Lab Android APK is distributed through GitHub Releases; the download page is `docs/android/index.html`. The old downloads APK is historical and is not linked as the current build.
- The landing page button in `index.html` already points to that local file.
- Add contact info, privacy notice, and version number if this will be shared with patients.
- If you want to host the APK on GitHub, pair this page with a GitHub Release download link.

## Server Guide Section

`index.html` now links to a dedicated server setup page (`server.html`) so the landing stays lightweight.

`server.html` includes the full "Server Quick Start" with:

- Repository clone + `server/` quick-start commands
- Model path requirements
- Uvicorn start command
- Android server URL setup (emulator + device)

## Android distribution

- Public page: https://pinkr1ver.github.io/home_nystagmus_monitor/android/
- Release: `android-v1.2.0`; asset `motion-lab-1.2.0-android-arm64.apk`, plus `SHA256SUMS.txt`.
- Current artifact: 1.2.0 (12), Android 9+, ARM64, debug-signed preview. Source is the separate Motion Lab Android checkout, commit 3500ef9; this release tag tracks distribution metadata, not that Android source tree.
- Future updates: verify APK manifest and signature, upload a new versioned release and checksums, then update `android/release.json` and `android/index.html` together. Preserve signing identity for updates. Never upload keystores, account tokens or recordings.
