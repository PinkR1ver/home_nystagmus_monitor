# GitHub Pages Landing Page

This folder contains a standalone static landing page for `Home Nystagmus Monitor`.

## Deploy with GitHub Pages

1. Push the repository to GitHub.
2. Open repository `Settings` -> `Pages`.
3. Set the source to `Deploy from a branch`.
4. Choose your branch and the `/docs` folder.
5. Save, then wait for GitHub Pages to publish.

## Before publishing

- APK is currently distributed from `docs/downloads/home-nystagmus-monitor-debug.apk`.
- The landing page button in `index.html` already points to that local file.
- Add contact info, privacy notice, and version number if this will be shared with patients.
- If you want to host the APK on GitHub, pair this page with a GitHub Release download link.

## Server Guide Section

`index.html` includes a "服务端部署说明（README 风格）" section with:

- Repository clone + `server/` quick-start commands
- Model path requirements
- Uvicorn start command
- Android server URL setup (emulator + device)
