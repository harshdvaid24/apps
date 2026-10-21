# Harsh's Apps

A tiny personal app store: **https://harshdvaid24.github.io/apps/**

Open it on an Android phone, tap **Install**, open the download. Watch faces install from the paired phone. Web apps open in the browser.

## How it works

- `index.html` — one static page (no build step). Reads `apps.json`, renders sections (Android · Wear OS · TV · Web), a featured card, category filters and a detail sheet. Deep links: `#solarlens`.
- `apps.json` — the manifest: one entry per app (name, package, version, size, min Android, icon, screenshots, APK URL) and per website.
- APKs are **GitHub Release assets** on this repo, one release per app (tag = slug), only the newest APK kept: `releases/download/<slug>/<slug>-<version>.apk`. Nothing heavy in git.
- `scripts/publish-to-store.sh <apk>` reads the APK's real package/version/size/minSdk with `aapt2`, uploads it, extracts the launcher icon if the store has none, updates `apps.json`, commits and pushes. GitHub Pages redeploys in about a minute.

```bash
scripts/publish-to-store.sh path/to/app-release.apk            # one app (slug from its label)
scripts/publish-to-store.sh path/to/app.apk --slug my-app --category wear --desc "…"
scripts/publish-to-store.sh --all                              # everything in sources.local.json
```

A Claude Code hook (`~/.claude/hooks/store-publish-on-build.sh`, PostToolUse on Bash) runs the script automatically after any successful `./gradlew assembleRelease` / `bundleRelease` in a project, so every build lands here.

## Adding an app

Build a release APK, then run the script (or let the hook do it). Edit the new entry's `tagline`, `description`, `tags`, `screenshots` in `apps.json` and drop images under `assets/`.

## Notes

- Apps are personal builds; each app keeps the same signing key across releases so updates install over the old version.
- The page needs no server features: works on GitHub Pages, any static host, or `python3 -m http.server`.
