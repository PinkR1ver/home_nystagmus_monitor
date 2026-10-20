# Android APK distribution

- Date: 2026-10-20
- Status: Completed; public page and APK verified
- User requested GitHub Pages distribution of the current Android app.
- Existing Pages source remains main:/docs. Download landing page: docs/android/index.html; existing homepage Android button links there. APK is a GitHub Release asset rather than a large Git blob.
- Release tag android-v1.2.0, prerelease, version 1.2.0 (12), Android 9+ ARM64. Explicitly labeled debug-signed preview; existing signing identity retained.
- SHA256SUMS.txt and docs/android/release.json record artifact hash, size and provenance. Android source is in the separate Motion Lab checkout at 3500ef9; the distribution tag does not imply this source exists in the root main branch.
- Future versions: upload a new release, update page and metadata together, verify public download digest. Signing keystores and credentials must never be committed.

## Published verification

- Page: https://pinkr1ver.github.io/home_nystagmus_monitor/android/ (HTTP 200 and browser rendered).
- Release: https://github.com/PinkR1ver/home_nystagmus_monitor/releases/tag/android-v1.2.0 (public prerelease).
- APK public range request returned HTTP 206; GitHub asset digest matches local SHA-256 7450b1ced2741426b86e71a1be59efd9da527a7163b4e4d9915e5834960c34a5.
- PR #2 merged as 34c8d4b; GitGuardian passed, Pages build succeeded. Desktop and 390px mobile layout inspected.
- Upload over default HTTP/2 was slow; GODEBUG=http2client=0 completed. Temporary probe/incomplete assets removed; only APK and checksum remain.
