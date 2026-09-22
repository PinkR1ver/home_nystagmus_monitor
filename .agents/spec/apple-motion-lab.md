# Apple Motion Lab

- Created / updated: 2026-09-22
- Status: Completed — first Apple design version; functional parity remains a separate follow-up
- Branch: `codex/apple-motion-lab`, based on `c19cabd`
- User request: a separate Apple branch that follows the Android design completely. This explicitly resumes Apple work; Android remains the priority.
- Visual reference: separate Motion Lab Android checkout, v0.5.0 / commit `ee5243d`, `ui/AppUi.kt`.

## Delivered design

White backgrounds, #FF2442 accent, #F7F7F7 cards, #222329 text, #777B85 secondary text; 24pt margins; rounded cards/capsule actions. Home modes, eye entry, local history, profile, cloud and IMU entry, video/report detail. Fixed 首页 / 记录 / 我的 navigation. Content width capped at 640pt for iPad.

## Working functionality and limits

- Existing fixed-lens camera recorder, Photos video import for body tasks, Files import for eye videos.
- Video copied into Documents/MotionLab before analysis. Atomic JSON index, persistent Codable reports, share original file, persistent profile parameters.
- Eye analysis explicitly triggered after saving, using existing bundled ONNX and automatic ROI; 3–120 second input validation. Horizontal/vertical charts use actual results, no demo measurements.
- Android's manual single-eye ROI is not yet ported. The Apple automatic ROI behavior is explained in its preparation copy.
- Body model, IMU capture and authenticated cloud upload are NOT ported by this design task. Their routes explain availability; no fabricated metrics/connection states or embedded credentials.
- Existing DashboardView/CaptureStartView retained as legacy components, no longer the app entry.

## Verification

Simulator Debug build passed. iPhone 17 and iPad mini (A17 Pro), iOS 26.2, installed and launched. Home, eye entry, empty history, profile and cloud screenshots reviewed; no observed clipping in inspected pages (profile scrolls). Report serialization smoke passed including inconclusive outcome and stable sample/evidence UUIDs. Camera/ONNX execution on an Apple device has not been revalidated in this design task. Use external Xcode via DEVELOPER_DIR. Default simulator directory has external-volume permission failures; isolated device set at `~/Library/Developer/MotionLabSimulators` works without changing existing devices.
