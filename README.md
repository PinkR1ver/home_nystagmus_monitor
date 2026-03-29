# Home Nystagmus Monitor (Init)

Android app scaffold for home nystagmus monitoring.

## What is done in this init
- Compose-based 3-tab UI (采集 / 记录 / 设置)
- Session lifecycle placeholder (start/stop)
- In-memory mock record generation
- Pending-record upload placeholder
- `AGENTS.md` for vibe coding rules and project memory

## Project structure
- `AGENTS.md`: rules + memory + milestones
- `app/src/main/java/com/kk/homenystagmusmonitor/data`: model + repository
- `app/src/main/java/com/kk/homenystagmusmonitor/ui`: view model + screens

## Run in Android Studio
1. Open this folder as project root.
2. Let Android Studio sync Gradle settings.
3. Run app module on emulator/device.

## Next phase
- Integrate real eye-motion detection pipeline
- Replace fake upload with real API client
- Add local persistence (Room/DataStore)
