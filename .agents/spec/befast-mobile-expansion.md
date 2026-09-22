# BEFAST mobile expansion

- Created / updated: 2026-09-23
- Status: Research complete; implementation proposed, not delivered
- Branch: `codex/befast-model-research`, from merged main `5a157cd`
- User request: after Git commit/PR/merge, read supplied BEFAST.html and look online for models to cover the app's BEFAST modules.

## Findings and next work

Authoritative plan: [BEFAST_MODEL_PLAN.md](../../docs/research/BEFAST_MODEL_PLAN.md); download evidence: [manifest](../../docs/research/BEFAST_MODEL_MANIFEST.json).

Android remains priority. B/E have existing pipelines, A can reuse Heavy but needs its own task; F needs Face Landmarker and normalized symmetry features; S needs visible audio capture/VAD/DSP/ASR. T in the supplied deck means Thunder; proposed product retains standard Time and adds patient-reported headache/NRS separately. No validated all-in-one stroke score was obtained. Do not infer NRS from behavior or treat ASR errors as dysarthria diagnoses.

Face task and Silero VAD were downloaded to the external model cache, hashed, and not bundled. Face archive CRC passed. Phone inference and F/A/S UI are not implemented in this research milestone. SenseVoice has a custom model license; openSMILE commercial use requires a separate license. Weight/source/version and clinical validation must remain distinct.

Deck's hospital-only / feature-only / 24-hour passive claims differ from current external ingestion server and visible short recording tasks. No server/app behavior changed. Proposed sequence: Android session + F/A/T, then speech, B/E protocol standardization, backend feature schema/doctor review, hardware and clinical validation, Apple parity.

## Prior Git milestone

PR #1 merged to main (5a157cdb58cc9b8064cba423a557f6fa9f0b99c2), GitGuardian passed. Original Apple branch preserved; unpublished 166 MB demo video migrated to LFS in isolated release history. Avoid merging the original pre-LFS history back into main; base new work on merged main.
