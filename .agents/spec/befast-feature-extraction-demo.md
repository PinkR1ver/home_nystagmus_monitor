# BEFAST Literature Feature Extraction Demo

- Created: 2026-09-05
- Last updated: 2026-09-05
- Status: Completed
- Branch: `feature/befast-feature-extraction-demo`

## Goal

Turn the supplied BEFAST computer-vision literature review into a small, evidence-first demo that explains how the cited methods extract Face, Eye, Arm, Balance, and Speech features.

## Delivered

- `befast-feature-demo/`: nine-slide HTML presentation and HyperFrames composition.
- Reproduced aEYE recursive frame filtering on a licensed example eye video.
- Loaded Pavlikov et al.'s open upper-limb repetition data and thresholds.
- Ran the public wav2vec2-base model on a synthetic, non-patient speech sample and stored derived layer features.
- Added method-only Face and Balance visualizations where original weights/data were not public.
- Restructured all five feature modules as definition → visual evidence → extraction method.
- Added licensed paper figures for Face, aEYE, and EyePhone, plus the open-data elbow-threshold figure for Arm; retained actual local video/signal outputs where they explain the feature more directly.
- Documented paper, model, dataset, and license boundaries in `SOURCES.md`.
- Added `TALKING_GUIDE.md`, a concise 3–5 minute Chinese explanation script for the deck.

## Verification

- `npm run check`: 0 lint/runtime/layout/motion errors; 105/105 text checks pass WCAG AA.
- Captured and visually reviewed all nine slide snapshots.
- Standalone deck scales the full 1920×1080 stage to the browser viewport; verified at 1366×768, 1024×768, and 390×844 without clipping.
- Rechecked the six definition/extraction pages in the live browser: no card overflow and no broken images.
- This is a research/demo artifact, not a diagnostic system or clinical validation.
