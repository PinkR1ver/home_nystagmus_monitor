# Showcase media and signal sources

See `../SOURCES.md` for the authoritative v4 media, model, processing, provenance,
license, and clinical-boundary notes. The packaged deck contains the following exact
runtime derivatives:

- `composition/assets/body-walk-overlay-v4.mp4` — full-body lab walking with
  frame-by-frame YOLO11n Pose keypoints and skeleton burned into the source.
- `composition/assets/gaze-demo-v3.mp4` — direct eye close-up synchronized to the
  derived image-plane trace.
- `composition/assets/demo-signals-v4.js` — body samples plus the 0.1/6 Hz filter,
  600 Hz resampling, turning points, and fast/slow phase candidates.

The eye sample yields 33 turning points and 12 phase candidates but does not pass the
strict three-consecutive-same-direction gate. Units are percent of frame width, not
degrees or clinical SPV.

<!-- Historical v3 source detail retained below for provenance. -->

## Front-view full-body movement

- Title: “Front Squat Full Body 2”
- Creator: Schulich School of Medicine and Dentistry, Western University
- Canonical record: https://rsc.lib.uwo.ca/s/healthedu/item/2174
- Legacy record: https://ir.lib.uwo.ca/healthed_anatomy/50/
- License: Creative Commons Attribution-NonCommercial 4.0 International
- Original filename: `Anatomy_Squat_FullBody2.mp4`
- Local source: `source-media/candidates/front-squat.mp4`
- Showcase derivative: `source-media/processed/body-pose-demo-v3.mp4`
- Changes: selected the first 12 seconds, resized/padded to 1280×720, converted to
  silent H.264 at 30 fps.

The subject is directly front-facing against a plain white background, with the full
body and feet visible throughout the squat sequence. Because this source is CC BY-NC,
confirm that the intended distribution is non-commercial or replace it before a
commercial release.

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
- Body method: YOLO11n Pose weighted inference at 10 Hz on the exact v3 body video.
- Eye method: iris-circle center tracking at 10 Hz plus a 3-frame median filter on the
  exact v3 eye video.
- Shared output: `source-media/processed/demo-signals-v3.js`
- Runtime copies: `video/assets/demo-signals.js` and
  `slides/composition/assets/demo-signals.js`
- YOLO weights: `source-media/models/yolo11n-pose.pt`

Verified summary from the generated data:

- Body: 120 samples, minimum 17/17 valid keypoints, mean confidence 0.9702,
  normalized hip-center vertical range 0.44713–0.58627.
- Eye: 100 samples, horizontal peak-to-peak displacement 0.11344 of frame width.

The eye trace is a normalized pixel displacement used to prove source/video timing.
It is not labeled as degrees and is not a substitute for the app's SwinUNet gaze model
or clinical VNG analysis.
