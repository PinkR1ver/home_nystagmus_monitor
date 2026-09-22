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
- Remaining validation: physical iPhone camera/IMU acceptance requires a signed Developer build. The implementation itself includes live body overlay/capture guidance, Android-aligned eye quality/preprocessing/full-video runtime, ZIP/CSV export, cloud upload/download/retry/merge. Physical signing is an environment prerequisite, not a missing code path.
- `devicectl list devices` on 2026-09-22 reported paired iPhone 16 Pro available, iPad unavailable. Revalidate before device tests.

## 2026-09-22 body + cloud integration progress

- `BodyAnalysisSmoke.swift`: Android t03 five-rise boundaries within one frame, rise-duration CV 10.3540574, four seated intervals; SG quadratic/gap checks; body translation/mass normalization; multi-person exclusion.
- `MotionMetricsSmoke.swift`: corresponding Android standing-sine RMSD/ellipse, bilateral foot angle symmetry, stationary feet do not invent steps, alternating gait ~100 steps/min plus toe-off candidates, short/constant nonlinear gates, gap-respecting derivatives, t03 per-event/waveform statistics. Both pass.
- Actual 6-second `mixkit-squats-752.mp4` through iOS simulator MediaPipe: 120 frames, 0.9666667 valid coverage, one STS candidate; no assertion that this is a clinical chair test. Full-metrics rerun passed: 305 metrics and 120 frames; persisted evidence in iphone-app/tests/evidence/body-runtime-20260922.json.
- CloudRuntimeSmoke (DEBUG only, opt-in `MOTION_SMOKE_CLOUD=1`, credential injected outside source): Keychain restoration, synthetic IMU upload and pull, duplicate request, invalid-token 401, authenticated download SHA256, archive tombstone, queue/cursor restart all passed. Test removes its injected secret and disconnects; archives only its synthetic record. No source video uploaded.
- Cloud runtime requires simulator ad-hoc signing (`CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=-`); unsigned simulator build caused Keychain -34018. Workspace signed simulator build passes.
- Report merge sorts server revisions before updating, retains local source files, hides archived cloud-only rows and keeps local captures. Generic server report is authoritative; native report decode is used when compatible. Cloud-only records can download the original artifact after merge.
- IMU finishing gate prevents a second session from replacing the writer before the previous flush callback completes.

- Eye runtime smoke passed on 3-second `rapid-horizontal-nystagmus-v4.mp4` with fixed ROI: persisted result `No clear nystagmus signal`, quality 1.0, after full ONNX/quality/report path. This is an algorithm runtime check, not a clinical validation.
- Live body camera preview now drops late frames, draws 33-point skeleton/one-person status/complete head-and-feet framing guidance, shows latency, and automatically stops at 115 seconds. The same recorder uses the body guide for STS/standing/gait and the eye guide for fixed ROI capture.
- Report ZIP writer passed external Python ZIP CRC and payload verification; export includes context, report, metrics/signals CSV, landmarks, eye signals, IMU CSV/markers, and cloud record when present.
- Complete pure Swift suite passed: report/ROI/IMU/eye-quality/archive/body-model/STS/motion-metric checks.
