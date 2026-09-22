# Showcase media and signal sources

Accessed and prepared on 2026-08-29. Version 4 pairs every displayed measurement
with the exact adopted source video. It does not present inferred 2D values as
metric depth, gaze angle, or a clinical result.

## Clinical full-body walking

- Title: VisionMD-Gait demo video
- Creator: MEA Lab / VisionMD-Gait authors
- Canonical repository: https://github.com/mea-lab/GaitValidation/blob/main/DEMO/demo.mp4
- Related paper: https://doi.org/10.1038/s41598-025-34912-5
- Original filename: `DEMO/demo.mp4`
- Local source: `source-media/candidates/visionmd-gait-demo.mp4`
- Showcase derivatives: `source-media/processed/body-walk-overlay-v4.mp4`,
  `body-walk-overlay-v4-film.mp4`, and `body-walk-overlay-v4-slide.mp4`
- Changes: YOLO11n Pose was run on every output frame; 17 keypoints and the standard
  skeleton edges were burned into the walking footage. Blurred side fill preserves
  the full vertical frame without cropping the feet.

The source shows a complete walking sequence in a clinical lab. The repository does
not expose a clear media license at its root, so redistribution/commercial use needs
separate license confirmation or replacement media.

## Direct nystagmus close-up

- Title: “Nystagmus eye movement.gif”
- Creator: Mr.Polaz
- Canonical record: https://commons.wikimedia.org/wiki/File:Nystagmus_eye_movement.gif
- License: Creative Commons Attribution-ShareAlike 4.0 International
- Local source: `source-media/candidates/nystagmus-eye-movement.gif`
- Showcase derivative: `source-media/processed/nystagmus-demo-v3.mp4`
- Changes: looped the 1.79-second original to 10 seconds, resized/padded to 1280×720,
  converted to silent H.264 at 30 fps.

This is a direct eye close-up, not a recording of a diagnostic monitor. Share-alike
and attribution obligations apply to redistribution of the derivative.

## Reproducible signal extraction

- Script: `scripts/extract_demo_signals.py`
- Body method: YOLO11n Pose weighted inference at 10 Hz on the exact v4 walking video.
- Eye method: iris-circle center tracking followed by the reference VertiWisdom chain:
  fifth-order 0.1 Hz high-pass, fifth-order 6 Hz low-pass, 600 Hz resampling, turning
  point detection, adjacent-slope fast/slow classification, and a same-direction
  continuity gate of at least three patterns.
- Reference: `/Volumes/macOSexternal/Documents/proj/SwinUNet-VOG/vertiwisdom.py`
- Shared output: `source-media/processed/demo-signals-v4.js`
- Runtime copies: `video/assets/demo-signals-v4.js` and
  `slides/composition/assets/demo-signals-v4.js`
- YOLO weights: `source-media/models/yolo11n-pose.pt`

Verified summary from the generated data:

- Body: minimum 14/17 valid keypoints, mean confidence 0.7778, normalized walking
  vertical excursion 0.0235, ankle-separation range 0.01401–0.10979, and shoulder
  sway 0.08256 of frame width.
- Eye: 33 turning points and 12 fast/slow phase candidates. The sample does not pass
  the strict requirement for at least three consecutive same-direction patterns, so
  the showcase correctly reports no positive nystagmus classification.

The eye trace is normalized image-plane displacement in percent of frame width. It is
not degrees or clinical SPV and is not a substitute for calibrated VNG analysis.

## Single-pass film cut (v5)

- The film body source is `video/assets/body-walk-once-hold-v5.mp4`: one 4.53-second
  walk followed only by a 0.47-second last-frame hold.
- The film eye source is `video/assets/gaze-once-hold-v5.mp4`: one 1.8-second eye
  movement cycle followed only by a 2.2-second last-frame hold.
- Neither source repeats. The v5 signal file was regenerated from the single-pass eye
  clip and reports 7 turning points and 3 fast/slow phase candidates.
