# OKN Animation Static Page

- Added `okn-animation/` as a standalone static OKN stimulus page for normal-subject testing workflows.
- The page renders moving black/white stripe animation on canvas and supports speed, stripe width, contrast, duration, direction, pause/reset, and fullscreen controls.
- The stimulus frame intentionally contains no timer, direction label, or center mark, so fullscreen playback stays visually pure.
- Public deployment target is a separate GitHub Pages repository: `PinkR1ver/okn-animation`.
- Published URL: `https://pinkr1ver.github.io/okn-animation/`.
- Keep the local folder deployable as static files without a build step.
- GitHub Pages was switched from legacy branch builds to workflow deployment because the legacy Pages build stayed stuck on the first commit and kept serving stale HTML.
