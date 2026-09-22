# Rehab Motion demo: stereo body + head + gaze

## Delivered state

- Target: `rehab-demo/RehabDemo.xcodeproj`
- Minimum iOS: 18.0
- The Apple body-pose request was removed from this target.
- Model: Ultralytics `YOLO11n-pose`, source revision `ef78744`
- Hugging Face source weight SHA-256:
  `869e83fcdffdc7371fa4e34cd8e51c838cc729571d1635e5141e3075e9319dc0`
- Bundled artifact: `RehabDemo/Resources/YOLO11nPose.mlpackage`
- License: AGPL-3.0 according to the source model repository. Confirm obligations or
  obtain a commercial license before proprietary distribution.

## Capture architecture

- The original front+rear interpretation was corrected on 2026-07-29. The required dual camera is now the calibrated back `builtInDualWideCamera` (physical wide + ultrawide), not front + rear.
- On the connected iPhone 16 Pro, runtime verification reported `stereo=true`, 1920×1080 video, and synchronized 320×180 depth.
- `AVCaptureDataOutputSynchronizer` pairs video and depth. YOLO joints are sampled against converted Float32 depth and projected with `AVCameraCalibrationData.intrinsicMatrix` into camera-space X/Y/Z.
- Independent FCQ MobileNetV3 Core ML weights provide head yaw/pitch/roll; the existing 29 MB `swinunet_web.onnx` provides gaze through ONNX Runtime 1.24.2.
- Scheduling caps are body 10 fps, head 10 fps, gaze 20 fps, depth preview 6 fps; frames are dropped rather than queued. Eye ROI has a raw-pixel quality gate.
- Start/stop assessment records a time series to `Documents/RehabSessions/rehab-*.json`, including head/gaze, depth coverage, and per-joint 2D plus camera-space X/Y/Z.
- Devices without Dual Wide streaming depth transparently rebuild as rear-camera-only.
- The UI always displays whether the current source is dual-camera or compatibility mode.

## Verification

- Debug simulator SDK build: passed
- Release simulator SDK build: passed
- Debug iPhoneOS SDK build: passed
- Xcode static analysis: passed
- `swift-format lint`: passed
- Core ML smoke inference on the Ultralytics bus test image:
  - person confidence: `0.90087890625`
  - visible keypoints at threshold 0.2: `17/17`
- Deterministic warm-inference reference benchmark on the current Apple Silicon Mac:
  - YOLO11n Pose: median 4.5 ms, P95 4.6 ms
  - FCQ Head Pose: median 0.6 ms, P95 0.7 ms
  - SwinUNet Gaze with ONNX Runtime CPU: median 5.4 ms, P95 5.7 ms
- The gaze vector conversion must follow MPIIGaze coordinates:
  `pitch = asin(-y)` and `yaw = atan2(-x, -z)`. This is shared with the
  existing iPhone analysis pipeline.
- Physical-device install and launch: passed on the connected iPhone 16 Pro.
- Physical-device capture runtime: `stereo=true`, 1920×1080 reference video,
  synchronized 320×180 depth.
- Device screenshot visually confirmed the rebuilt capture UI and false-color depth
  picture-in-picture.

## Local signing note

- A signed build is installed on the iPhone. Subsequent non-interactive signing can fail
  with `errSecInternalComponent` when the macOS login keychain is locked; unlock the login
  keychain in Xcode/Keychain Access before installing a newer binary.

## Demo showcase assets

- HyperFrames source projects live under `rehab-demo/showcase/video/` and
  `rehab-demo/showcase/slides/`.
- Final video:
  `rehab-demo/showcase/video/renders/rehab-stereo-model-demo.mp4`
  (H.264, 1920×1080, 30 fps, 34 seconds).
- The video uses a consistent split-screen instrument layout: source footage on the left,
  derived body/head/gaze/depth/quality signals on the right, followed by a three-signal
  fusion summary.
- On 2026-08-28, both placeholder-like clips were replaced with licensed online sources:
  a Mixkit wide-shot squat/overhead-reach clip with the full body visible, and a Figshare
  CC BY 4.0 VNG clip showing real horizontal positional nystagmus. Source, license, crop,
  retiming, and retrieval details are recorded in `rehab-demo/showcase/SOURCES.md`.
- The 8-slide Chinese deck uses `rehab-demo/showcase/slides/index.html` as its direct-open
  wrapper and `rehab-demo/showcase/slides/composition/index.html` as the HyperFrames
  composition. Run `npm run dev` from the slides directory for presenter mode.
- The deck was verified by keyboard-driving all eight slides in a real browser. The
  video passed full decode plus visual frame checks at 1, 8, 18, 24, and 32 seconds.
- All synthetic output values and development-machine timing measurements are explicitly
  labeled as demo/reference data. The deck and video also state the non-diagnostic boundary
  and model-license caveats.

## Showcase v3: source-synchronized evidence

- On 2026-08-28 the showcase was revised again after review found that the v2 media was
  not sufficiently direct and its charts were decorative rather than source-derived.
- The body source is now Western University's “Front Squat Full Body 2”: a plain-background,
  front-facing, fully visible squat sequence. It is CC BY-NC 4.0, so commercial reuse needs
  replacement or separate permission.
- The eye source is now Wikimedia Commons “Nystagmus eye movement.gif”: a direct eye
  close-up rather than a recording of a VNG monitor. It is CC BY-SA 4.0.
- `showcase/scripts/extract_demo_signals.py` runs YOLO11n Pose at 10 Hz on the exact body
  derivative and iris-circle tracking plus a 3-frame median filter on the exact eye
  derivative. It generates the shared `rehab.demo.signals.v1` JavaScript data contract.
- Verified signal summary: 120 body samples, 17/17 minimum valid keypoints, 0.9702 mean
  confidence, 0.13914 normalized hip-center vertical amplitude; 100 eye samples and
  0.11344 normalized horizontal peak-to-peak displacement.
- The video skeleton, body readouts, eye trace, eye playhead, and slides evidence pages now
  consume these real arrays. Fake depth in meters, fake head angles, synthetic sine curves,
  and hard-coded SVG waveforms were removed from the evidence scenes.
- Final v3 film: `showcase/video/renders/rehab-stereo-model-demo-v3.mp4` (34 seconds,
  1920×1080, H.264, 30 fps).
- Final v3 deck: `showcase/slides/rehab-stereo-slides-v3.zip`; the package includes its
  versioned media, shared signals, attribution/license notes, and direct-open wrapper.
- HyperFrames checks passed with zero runtime/layout errors for both projects. The film was
  visually checked across body standing/squat/rise and three eye-signal frames; the deck's
  body and eye evidence slides were re-snapshotted after forcing versioned media names to
  avoid stale frame-cache reuse.

## Showcase v4: walking skeleton + nystagmus phase processing

- On 2026-08-29 the body evidence was replaced by a full-body clinical-lab walking demo
  from VisionMD-Gait. YOLO11n Pose keypoints and skeleton edges are burned into every
  output frame, and the film/slides consume synchronized v4 pose arrays.
- `showcase/scripts/extract_demo_signals.py` now mirrors the relevant VertiWisdom signal
  chain: fifth-order 0.1 Hz high-pass, fifth-order 6 Hz low-pass, 600 Hz resampling,
  turning points, adjacent slope classification, fast/slow phase segments, and the
  same-direction continuity gate.
- The adopted eye sample produces 33 turning points and 12 candidate fast/slow patterns,
  but does not pass the strict `>=3` same-direction continuity gate. The UI therefore
  shows the candidates while explicitly withholding a positive classification.
- Eye displacement remains image-plane `% frame width`; it is not calibrated degrees or
  clinical SPV.
- Final v4 film: `showcase/video/renders/rehab-stereo-model-demo-v4.mp4` (34 seconds,
  1920x1080, H.264, 30 fps). Final deck: `showcase/slides/rehab-stereo-slides-v4.zip`.
- HyperFrames 0.8.17 checks passed with zero runtime/layout errors. The final film and the
  body/eye evidence slides were visually inspected after rendering.

## Showcase v5: single-pass evidence playback

- Reviewer feedback required eliminating repeated playback. The film now uses one full
  4.53-second walking pass and one 1.8-second direct-eye pass; each ends on a still frame
  while the readout remains visible, with no source loop.
- Single-pass eye processing yields 7 turning points and 3 candidate fast/slow patterns.
- The film timeline is reduced from 34 seconds to 19 seconds; slides remain on v4.
