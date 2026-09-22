# Apple Motion Lab

- Created / updated: 2026-09-22
- Status: In progress — full Android functionality port explicitly requested on 2026-09-22
- Branch: `codex/apple-motion-lab`, based on `c19cabd`
- User request: a separate Apple branch that follows the Android design completely. This explicitly resumes Apple work; Android remains the priority.
- Visual reference: separate Motion Lab Android checkout, v0.5.0 / commit `ee5243d`, `ui/AppUi.kt`.

## Delivered design

White backgrounds, #FF2442 accent, #F7F7F7 cards, #222329 text, #777B85 secondary text; 24pt margins; rounded cards/capsule actions. Home modes, eye entry, local history, profile, cloud and IMU entry, video/report detail. Fixed 首页 / 记录 / 我的 navigation. Content width capped at 640pt for iPad.

## Working functionality and limits

- Existing fixed-lens camera recorder, Photos video import for body tasks, Files import for eye videos.
- Video copied into Documents/MotionLab before analysis. Atomic JSON index, persistent Codable reports, share original file, persistent profile parameters.
- Eye analysis explicitly triggered after saving, using existing bundled ONNX and automatic ROI; 3–120 second input validation. Horizontal/vertical charts use actual results, no demo measurements.
- Manual fixed single-eye ROI is implemented with first-frame preview, bounds-limited controls, explicit confirmation and persisted normalized top-left coordinates. Full-video 30 Hz sampling replaces the old 420-frame cap; charts retain actual degrees and 600 Hz processed timestamps. Pixel-coordinate/JSON tests pass; runtime inference parity remains to validate.
- IMU now uses real Core Motion 100 Hz requested acceleration/gyro streams, SI units (g × 9.80665; rad/s), serial CSV writes, marker CSV, per-second metadata checkpoints, gap/invalid counters, foreground stop and persistent history/export. Writer smoke passes; real sensor validation pending.
- MediaPipeTasksVision 0.10.35 installed via CocoaPods; use the xcworkspace, not xcodeproj. Exact Android Heavy model and segment/STS configs bundled. CPU video detector uses 20 Hz unmirrored images, two-person detection and world/image landmarks. BodySegmentModel, BodyStsAnalyzer, BodyMotionMetrics and BodyGaitMetrics are ported; video record analysis/report UI is connected. Same Android t03 and synthetic standing/gait fixture tests passed.
- Apple authenticated HTTPS sync now implemented: Keychain credentials; `/v1/me` verification; endpoint+account-scoped snapshots, queues and cursors; immutable content-derived record versions; hash-checked artifact upload/download; retries/cancellation; incremental history/tombstones; local record merge preserves paths. Synthetic iOS simulator-to-production tests passed (details below). Further cross-account/partial-upload/merge acceptance remains pending.
- Existing DashboardView/CaptureStartView retained as legacy components, no longer the app entry.

## Verification

Simulator Debug build passed. iPhone 17 and iPad mini (A17 Pro), iOS 26.2, installed and launched. Home, eye entry, empty history, profile and cloud screenshots reviewed; no observed clipping in inspected pages (profile scrolls). Report serialization smoke passed including inconclusive outcome and stable sample/evidence UUIDs. Camera/ONNX execution on an Apple device has not been revalidated in this design task. Use external Xcode via DEVELOPER_DIR. Default simulator directory has external-volume permission failures; isolated device set at `~/Library/Developer/MotionLabSimulators` works without changing existing devices.

## Full-port requirements (2026-09-22)

User explicitly requires all missing features: same MediaPipe Heavy body model and movement calculations, real IMU acquisition, authenticated cloud synchronization including retries/account isolation, and confirmed manual fixed single-eye ROI. Completion requires runtime validation, not only UI/build evidence. Current work fixes fixed ROI and the legacy 14-second truncation/time-axis bug first.

## Current verification / next steps

- New workspace simulator build passed and app launched after MediaPipe linking.
- Pure Swift tests: EyeRegionSmoke and IMUWriterSmoke passed. Original ReportPersistenceSmoke remains applicable.
- Google API reference: https://developers.google.com/edge/mediapipe/solutions/vision/pose_landmarker/ios
- CocoaPods command: `~/.gem/ruby/3.4.0/bin/pod install --project-directory=iphone-app` (gem user installation). Pods ignored; Podfile.lock tracked.
- Next: live capture body overlay and capture guidance; eye quality/preprocessing/full-video runtime parity; ZIP/CSV report export; cloud cross-account/partial-upload/local merge edge tests and Android-origin report rendering; physical IMU/camera validation. Do not mark goal complete until these requirements are audited.
- `devicectl list devices` on 2026-09-22 reported paired iPhone 16 Pro available, iPad unavailable. Revalidate before device tests.

## 2026-09-22 body + cloud integration progress

- `BodyAnalysisSmoke.swift`: Android t03 five-rise boundaries within one frame, rise-duration CV 10.3540574, four seated intervals; SG quadratic/gap checks; body translation/mass normalization; multi-person exclusion.
- `MotionMetricsSmoke.swift`: corresponding Android standing-sine RMSD/ellipse, bilateral foot angle symmetry, stationary feet do not invent steps, alternating gait ~100 steps/min plus toe-off candidates, short/constant nonlinear gates, gap-respecting derivatives, t03 per-event/waveform statistics. Both pass.
- Actual 6-second `mixkit-squats-752.mp4` through iOS simulator MediaPipe: 120 frames, 0.9666667 valid coverage, one STS candidate; no assertion that this is a clinical chair test. Full-metrics rerun passed: 305 metrics and 120 frames; persisted evidence in iphone-app/tests/evidence/body-runtime-20260922.json.
- CloudRuntimeSmoke (DEBUG only, opt-in `MOTION_SMOKE_CLOUD=1`, credential injected outside source): Keychain restoration, synthetic IMU upload and pull, duplicate request, invalid-token 401, authenticated download SHA256, archive tombstone, queue/cursor restart all passed. Test removes its injected secret and disconnects; archives only its synthetic record. No source video uploaded.
- Cloud runtime requires simulator ad-hoc signing (`CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=-`); unsigned simulator build caused Keychain -34018. Workspace signed simulator build passes.
- Report merge sorts server revisions before updating, retains local source files, hides archived cloud-only rows and keeps local captures. Generic server report is authoritative; native report decode used when compatible. Android cloud payload adaptation still needs full UI parity.
- IMU finishing gate prevents a second session from replacing the writer before the previous flush callback completes.
