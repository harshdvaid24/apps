#!/usr/bin/env bash
# Publish an APK to the app store (GitHub Pages site + GitHub Releases).
#   publish-to-store.sh <apk> [--slug s] [--name "N"] [--category android|wear|tv] [--desc "..."] [--repo url]
#   publish-to-store.sh --all            # republish every APK listed in sources.local.json
# One release per app (tag = slug); the newest APK is the only asset kept. apps.json is updated and pushed,
# so GitHub Pages redeploys the store within a minute. Prints one summary line at the end.
set -euo pipefail

STORE_DIR="${STORE_DIR:-$HOME/Projects/apps}"
STORE_REPO="${STORE_REPO:-harshdvaid24/apps}"
AAPT2="$(ls -d "$HOME/Library/Android/sdk/build-tools"/*/aapt2 2>/dev/null | sort -V | tail -1)"
[ -x "$AAPT2" ] || { echo "aapt2 not found under Android build-tools" >&2; exit 1; }

usage() { sed -n '2,6p' "$0" >&2; exit 2; }

if [ "${1:-}" = "--all" ]; then
  python3 -c 'import json;d=json.load(open("'"$STORE_DIR"'/sources.local.json"));[print(k,v) for k,v in d.items() if not k.startswith("_")]' |
  while read -r slug apk; do "$0" "$apk" --slug "$slug" || echo "FAILED $slug" >&2; done
  exit 0
fi

APK="${1:-}"; [ -f "$APK" ] || usage; shift
SLUG="" NAME="" CATEGORY="" DESC="" REPO=""
while [ $# -gt 0 ]; do case "$1" in
  --slug) SLUG="$2"; shift 2;; --name) NAME="$2"; shift 2;; --category) CATEGORY="$2"; shift 2;;
  --desc) DESC="$2"; shift 2;; --repo) REPO="$2"; shift 2;; *) usage;; esac; done

# --- read what is actually inside the APK ---------------------------------------------------
BADGE="$("$AAPT2" dump badging "$APK")"
PKG="$(sed -nE "s/^package: name='([^']+)'.*/\1/p" <<<"$BADGE")"
VCODE="$(sed -nE "s/^package:.*versionCode='([^']+)'.*/\1/p" <<<"$BADGE")"
VNAME="$(sed -nE "s/^package:.*versionName='([^']*)'.*/\1/p" <<<"$BADGE")"
LABEL="$(sed -nE "s/^application-label:'([^']+)'.*/\1/p" <<<"$BADGE" | head -1)"
MINSDK="$(sed -nE "s/^(minSdkVersion|sdkVersion):'([^']+)'.*/\2/p" <<<"$BADGE" | head -1)"
SIZE="$(stat -f%z "$APK")"
[ -n "$VNAME" ] || VNAME="0.$VCODE"
[ -n "$SLUG" ] || SLUG="$(tr '[:upper:]' '[:lower:]' <<<"${LABEL:-${PKG##*.}}" | sed -E 's/[^a-z0-9]+/-/g; s/^-|-$//g')"
[ -n "$NAME" ] || NAME="${LABEL:-$SLUG}"
if [ -z "$CATEGORY" ]; then
  if grep -q "android.hardware.type.watch" <<<"$BADGE"; then CATEGORY=wear
  elif grep -q "android.software.leanback" <<<"$BADGE"; then CATEGORY=tv
  else CATEGORY=android; fi
fi
ASSET="$SLUG-$VNAME.apk"
URL="https://github.com/$STORE_REPO/releases/download/$SLUG/$ASSET"
TODAY="$(date +%F)"

# --- release: create once per app, keep only the newest APK ---------------------------------
if ! gh release view "$SLUG" -R "$STORE_REPO" >/dev/null 2>&1; then
  gh release create "$SLUG" -R "$STORE_REPO" --title "$NAME" --notes "Latest APK of $NAME ($PKG). Updated automatically by publish-to-store.sh." >/dev/null
fi
# The download URL uses the asset's file name (a "#label" only changes the display label), so upload a copy with the final name.
TMPD="$(mktemp -d)"; cp "$APK" "$TMPD/$ASSET"
gh release upload "$SLUG" "$TMPD/$ASSET" -R "$STORE_REPO" --clobber >/dev/null
rm -rf "$TMPD"
for old in $(gh release view "$SLUG" -R "$STORE_REPO" --json assets -q '.assets[].name'); do
  [ "$old" = "$ASSET" ] || gh release delete-asset "$SLUG" "$old" -R "$STORE_REPO" -y >/dev/null 2>&1 || true
done

# --- icon: pull the launcher PNG out of the APK when the store has none yet ------------------
cd "$STORE_DIR"
if [ ! -f "assets/icons/$SLUG.png" ]; then
  ICON_PATH="$(sed -nE "s/^application-icon-[0-9]+:'([^']+\.png)'.*/\1/p" <<<"$BADGE" | tail -1)"
  if [ -n "$ICON_PATH" ]; then
    unzip -p "$APK" "$ICON_PATH" > "/tmp/_icon_$SLUG.png" 2>/dev/null && sips -Z 256 "/tmp/_icon_$SLUG.png" --out "assets/icons/$SLUG.png" >/dev/null 2>&1 || true
  fi
fi

# --- apps.json: update the entry (or add one) --------------------------------------------------
python3 - "$SLUG" "$NAME" "$CATEGORY" "$PKG" "$VNAME" "$VCODE" "$MINSDK" "$SIZE" "$TODAY" "$URL" "$DESC" "$REPO" <<'EOF'
import json, sys
slug, name, cat, pkg, vname, vcode, minsdk, size, today, url, desc, repo = sys.argv[1:]
d = json.load(open("apps.json"))
apps = d["apps"]
e = next((a for a in apps if a["slug"] == slug), None)
fields = dict(package=pkg, version=vname, versionCode=int(vcode or 0), minSdk=int(minsdk) if minsdk else None,
              sizeBytes=int(size), updated=today, apk=url)
if e is None:
    e = dict(slug=slug, name=name, category=cat, tagline="", description=desc or "", icon=f"assets/icons/{slug}.png",
             screenshots=[], tags=[], **fields)
    if repo: e["repo"] = repo
    apps.append(e)
else:
    e.update(fields)
    if desc: e["description"] = desc
    if repo: e["repo"] = repo
d["store"]["updated"] = today
json.dump(d, open("apps.json", "w"), indent=2, ensure_ascii=False); open("apps.json", "a").write("\n")
EOF

# --- push: GitHub Pages redeploys ----------------------------------------------------------------
git add apps.json assets/icons >/dev/null
if ! git diff --cached --quiet; then
  git commit -q -m "store: $NAME $VNAME ($VCODE)" && git push -q
fi
echo "PUBLISHED $NAME $VNAME ($VCODE) → $URL · store: https://harshdvaid24.github.io/apps/"
