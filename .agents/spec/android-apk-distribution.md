# Android APK distribution

- Date: 2026-10-20
- Status: Implemented; publishing verification pending
- User requested GitHub Pages distribution of the current Android app.
- Existing Pages source remains main:/docs. Download landing page: docs/android/index.html; existing homepage Android button links there. APK is a GitHub Release asset rather than a large Git blob.
- Release tag android-v1.2.0, prerelease, version 1.2.0 (12), Android 9+ ARM64. Explicitly labeled debug-signed preview; existing signing identity retained.
- SHA256SUMS.txt and docs/android/release.json record artifact hash, size and provenance. Android source is in the separate Motion Lab checkout at 3500ef9; the distribution tag does not imply this source exists in the root main branch.
- Future versions: upload a new release, update page and metadata together, verify public download digest. Signing keystores and credentials must never be committed.
