# Home Nystagmus Monitor - AGENTS

## Project Intent
- Build an Android app for home monitoring of possible nystagmus.
- App collects session records and uploads them to a remote server.
- Detection algorithm is intentionally deferred for later phases.
- Current phase goal: framework, navigation, UI flow, data model, and upload pipeline placeholders.

## Current Phase Scope (Init)
- Android app project bootstrapping
- Basic app architecture and package structure
- UI screens runnable end-to-end
- In-memory record storage and fake upload
- Clean TODO boundaries for future detection algorithm integration

## Rules (Vibe Coding)
- Keep each step small, runnable, and verifiable.
- Prefer simple architecture over premature abstractions.
- Do not implement real detection logic before explicit request.
- Keep algorithm entry points stable so later replacement is cheap.
- Use clear state-driven UI and avoid hidden side effects.
- Use English identifiers in code; product copy can be Chinese.
- Every non-trivial module should include one clear TODO for next phase.

## Memory
- Platform: Android (Kotlin + Jetpack Compose)
- Environment: Android Studio + OpenJDK available
- Algorithm: postponed, to be specified by user later
- Primary objective now: "UI and framework logic runs through"

## Milestones
1. Init project and run first screen
2. Add session lifecycle UI and local record list
3. Add remote upload placeholder path
4. Integrate real detection algorithm module
5. Add persistence, permissions, and production hardening

## Next When User Asks
- Replace fake detection with real algorithm module and camera pipeline
- Add Room/DataStore persistence
- Add auth + signed upload + retry policy
- Add patient workflow and clinical export format
