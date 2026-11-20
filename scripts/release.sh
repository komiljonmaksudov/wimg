#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
YML="$ROOT/wimg-ios/project.yml"
CHANGELOG="$ROOT/CHANGELOG.md"

# ── helpers ──────────────────────────────────────────────────────────────────

die() { echo "error: $1" >&2; exit 1; }

usage() {
  echo "Usage: $0 <patch|minor|major|X.Y.Z> [--push]"
  echo ""
  echo "Examples:"
  echo "  $0 patch         # 0.4.2 → 0.4.3"
  echo "  $0 minor --push  # 0.4.2 → 0.5.0, push immediately"
  echo "  $0 major         # 0.4.2 → 1.0.0"
  echo "  $0 1.0.0         # explicit version"
  exit 1
}

current_version() {
  # The Android versionName is the source of truth (bumped together with iOS).
  grep 'versionName = "' "$ROOT/wimg-android/app/build.gradle.kts" | head -1 | sed 's/.*"\([0-9]*\.[0-9]*\.[0-9]*\)".*/\1/'
}

bump_version() {
  local cur="$1" type="$2"
  local major minor patch
  IFS='.' read -r major minor patch <<< "$cur"

  case "$type" in
    major) echo "$((major + 1)).0.0" ;;
    minor) echo "${major}.$((minor + 1)).0" ;;
    patch) echo "${major}.${minor}.$((patch + 1))" ;;
    *)     die "unknown bump type: $type" ;;
  esac
}

# ── args ─────────────────────────────────────────────────────────────────────

[[ $# -ge 1 ]] || usage

PUSH=false
BUMP_ARG=""

for arg in "$@"; do
  case "$arg" in
    --push) PUSH=true ;;
    *) BUMP_ARG="$arg" ;;
  esac
done

[[ -n "$BUMP_ARG" ]] || usage

OLD=$(current_version)
[[ -n "$OLD" ]] || die "could not read versionName from wimg-android/app/build.gradle.kts"

case "$BUMP_ARG" in
  patch|minor|major) NEW=$(bump_version "$OLD" "$BUMP_ARG") ;;
  [0-9]*.[0-9]*.[0-9]*) NEW="$BUMP_ARG" ;;
  *) usage ;;
esac

[[ "$OLD" != "$NEW" ]] || die "new version ($NEW) is same as current ($OLD)"

echo "Bumping $OLD → $NEW"

# Play takes the release notes from docs/play-whats-new/*.txt and uploads a draft
# (no tester gets it) when their first line isn't "# <version>". Say so now.
for notes in "$ROOT"/docs/play-whats-new/*.txt; do
  if [[ "$(head -1 "$notes")" != "# $NEW" ]]; then
    echo "  ! $(basename "$notes") starts with \"$(head -1 "$notes")\", not \"# $NEW\": Play will upload a draft."
    STALE_NOTES=true
  fi
done
if [[ "${STALE_NOTES:-}" == true ]]; then
  read -r -p "  Release anyway? [y/N] " answer
  [[ "$answer" == [yY]* ]] || die "update docs/play-whats-new first"
fi

# ── update package.json ──────────────────────────────────────────────────────


# ── update project.yml ───────────────────────────────────────────────────────

sed -i '' "s/MARKETING_VERSION: \"$OLD\"/MARKETING_VERSION: \"$NEW\"/" "$YML"
# Reset iOS build number to 1 on each new version
sed -i '' 's/CURRENT_PROJECT_VERSION: [0-9]*/CURRENT_PROJECT_VERSION: 1/' "$YML"
echo "  updated $YML (version + reset build number)"

# ── update Android build.gradle.kts ──────────────────────────────────────────

GRADLE="$ROOT/wimg-android/app/build.gradle.kts"
sed -i '' "s/versionName = \"$OLD\"/versionName = \"$NEW\"/" "$GRADLE"
grep -q "versionName = \"$NEW\"" "$GRADLE" || die "versionName in $GRADLE is not $OLD — fix it by hand"
echo "  updated $GRADLE"

# ── generate changelog entry ─────────────────────────────────────────────────

PREV_TAG=$(git tag -l --sort=-v:refname | head -1 2>/dev/null || true)
DATE=$(date +%Y-%m-%d)

if [[ -n "$PREV_TAG" ]]; then
  COMMITS=$(git log --pretty=format:"- %s" --no-merges "$PREV_TAG"..HEAD \
    | grep -vE '^- (release|chore|ci|build): ' || true)
else
  COMMITS=$(git log --pretty=format:"- %s" --no-merges \
    | grep -vE '^- (release|chore|ci|build): ' || true)
fi

if [[ -z "$COMMITS" ]]; then
  COMMITS="- Version bump"
fi

ENTRY="## v${NEW} (${DATE})

${COMMITS}"

if [[ -f "$CHANGELOG" ]]; then
  # insert new entry after the first line (# Changelog)
  TMPFILE=$(mktemp)
  head -1 "$CHANGELOG" > "$TMPFILE"
  echo "" >> "$TMPFILE"
  echo "$ENTRY" >> "$TMPFILE"
  tail -n +2 "$CHANGELOG" >> "$TMPFILE"
  mv "$TMPFILE" "$CHANGELOG"
else
  cat > "$CHANGELOG" <<EOF
# Changelog

$ENTRY
EOF
fi

echo "  updated $CHANGELOG"

# ── commit + tag ─────────────────────────────────────────────────────────────

git add "$YML" "$GRADLE" "$CHANGELOG"
git commit -m "release: v${NEW}"
git tag "v${NEW}"

echo ""
echo "Done! Created commit and tag v${NEW}."

# ── push ─────────────────────────────────────────────────────────────────────

if [[ "$PUSH" == true ]]; then
  echo ""
  echo "Pushing..."
  # Separate lines: in `a && b`, set -e ignores a failing `a`, and the script
  # printed "Pushed!" after a push GitHub had refused (HTTP 400, 16 Nov 2026).
  git push
  git push origin "v${NEW}"
  echo "Pushed! CI will build the release."
else
  echo ""
  echo "To publish:"
  echo "  git push && git push origin v${NEW}"
  echo ""
  echo "Or next time, use --push:"
  echo "  $0 $BUMP_ARG --push"
fi
